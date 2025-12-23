# 项目需求文档：分布式高并发订单管理系统 (DOOS)

| 项目名称 | Distributed Omni-Order System (DOOS) |
| :--- | :--- |
| **版本** | V1.0.0 |
| **状态** | 拟定中 |
| **技术核心** | Go, gRPC, dbr, MySQL Sharding, Binlog CDC, React/TSX |

---

## 1. 项目概述

### 1.1 背景
本项目旨在构建一个模拟中大型电商平台核心交易链路的后端系统。系统需解决单一数据库在高并发写入下的性能瓶颈，并保证分布式环境下的数据最终一致性。

### 1.2 核心目标
1.  **高性能**：通过水平分库（Sharding）支撑海量订单数据的写入与查询。
2.  **一致性**：实现“下单”与“库存扣减”的分布式事务一致性（基于本地消息表方案）。
3.  **可观测性**：通过 Binlog 实时同步数据，实现异构数据的查询与统计。
4.  **工程化**：建立符合企业级标准的 Go 微服务工程规范。

---

## 2. 技术架构选型

### 2.1 后端技术栈
* **语言**：Go (Golang) 1.25
* **微服务框架**：gRPC + Protobuf (v3)
* **数据库访问 (ORM)**：`gocraft/dbr` (轻量级，便于手动控制分库逻辑)
* **数据库**：MySQL 8.0 (主库 + 分库实例)
* **消息队列**：Kafka 或 RabbitMQ (用于解耦库存与订单)
* **缓存**：Redis (用于库存预扣减、热点数据)
* **配置中心/注册中心**：Etcd 或 Consul
* **数据同步 (CDC)**：Canal (监听 Binlog) -> Go Consumer -> Elasticsearch/OLAP

### 2.2 前端技术栈
* **框架**：React 18
* **语言**：TypeScript (TSX)
* **UI 组件库**：Ant Design 或 Tailwind CSS
* **状态管理**：Zustand 或 Redux Toolkit
* **构建工具**：Vite

---

## 3. 数据库设计与分库策略

### 3.1 分库策略 (Sharding)
由于单表数据量过大，订单表需进行水平拆分。
* **Sharding Key**: `user_id` (确保同一个用户的订单在同一个库，方便用户查询)。
* **算法**: `Hash(user_id) % NodeCount`。
* **节点规划**: 
    * `doos_order_0`: 存储 `user_id` 偶数的数据。
    * `doos_order_1`: 存储 `user_id` 奇数的数据。

### 3.2 核心表结构 (SQL)

以下 DDL 需在每个分库实例中执行。

#### 3.2.1 订单主表 (`t_order`)
````sql
CREATE TABLE `t_order` (
  `id` BIGINT UNSIGNED NOT NULL COMMENT '分布式全局唯一ID (Snowflake)',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '分库键',
  `total_amount` DECIMAL(10, 2) NOT NULL,
  `status` TINYINT NOT NULL DEFAULT 0 COMMENT '0:Pending, 1:Paid, 2:Shipped, 3:Cancelled',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单分片表';
````

#### 3.2.2 本地消息表 (`t_local_message`)
**核心设计**：用于实现分布式事务的“可靠消息最终一致性”。该表必须与 `t_order` 在同一个物理库中，以保证本地事务。

````sql
CREATE TABLE `t_local_message` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `tx_id` VARCHAR(64) NOT NULL COMMENT '业务事务ID (如 order_id)',
  `topic` VARCHAR(50) NOT NULL COMMENT 'MQ Topic',
  `payload` JSON NOT NULL COMMENT '消息体 (包含 product_id, count)',
  `status` TINYINT NOT NULL DEFAULT 0 COMMENT '0:Ready, 1:Published, 2:Consumed, 3:Failed',
  `retry_count` INT DEFAULT 0,
  `next_retry` TIMESTAMP NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_status_next_retry` (`status`, `next_retry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='本地消息表';
````

---

## 4. 后端核心功能需求

### 4.1 数据库中间件封装 (`infra/persistence`)
**需求**：不使用现成的重量级中间件（如 MyCat），在代码层基于 `dbr` 封装分库逻辑。

**实现逻辑 (伪代码)**：
````go
type ShardingSession struct {
    nodes map[int]*dbr.Session // key: 0, 1
}

func (s *ShardingSession) GetSession(userID int64) *dbr.Session {
    shardIndex := userID % 2
    return s.nodes[shardIndex]
}

// 使用示例
func CreateOrder(ctx context.Context, order *model.Order) error {
    sess := shardingMgr.GetSession(order.UserID)
    tx, _ := sess.Begin()
    // ... 执行业务
}
````

### 4.2 下单核心流程 (分布式事务)
**场景**：用户下单 -> 创建订单 -> 扣减库存。
**方案**：本地消息表 + 异步 MQ。

**步骤详情**：
1.  **API 层**：接收 `CreateOrderRequest`。
2.  **Service 层 (事务开始 - Order DB)**：
    * 根据 `user_id` 路由到指定 DB。
    * 开启 `dbr` 事务。
    * `INSERT INTO t_order ...` (状态：Pending)。
    * `INSERT INTO t_local_message ...` (内容：`{"event":"DeductStock", "product_id":101, "qty":1}`, 状态：Ready)。
    * **提交事务** (Commit)。
3.  **消息投递服务 (独立协程/进程)**：
    * 轮询所有分库的 `t_local_message` (条件：`status=0`)。
    * 将消息推送到 Kafka/RabbitMQ。
    * 推送成功后，更新 `t_local_message` 状态为 `1 (Published)`。
4.  **库存服务 (Inventory Service)**：
    * 监听 MQ。
    * 执行库存扣减 `UPDATE stock SET count=count-? WHERE id=?`。
    * **幂等性处理**：检查该消息是否已处理过。
    * 处理成功后，调用 OrderService 的 gRPC 接口，将订单状态更为 `Paid` (或 `Confirmed`)。

### 4.3 数据同步与搜索 (CQRS)
**场景**：运营后台需要查询“昨日销量前十的商品”或“跨库搜索订单”。分库后 SQL 无法直接查询。
**方案**：CDC (Change Data Capture)。

**步骤详情**：
1.  **Canal 部署**：配置 Canal 伪装成 Slave 连接 MySQL 主库。
2.  **Binlog Consumer (Go)**：
    * 连接 Canal Server。
    * 解析 `RowChange` 事件。
    * 过滤 `t_order` 表的 `INSERT` 和 `UPDATE`。
3.  **异构存储**：
    * 将清洗后的数据写入 **Elasticsearch** (便于搜索) 或一张 **MySQL 宽表** (便于报表统计)。

---

## 5. API 接口定义 (Proto)

位于 `api/proto/v1/order.proto`。

````protobuf
syntax = "proto3";

package order.v1;

option go_package = "api/proto/v1;orderv1";

service OrderService {
    // 创建订单
    rpc CreateOrder (CreateOrderRequest) returns (CreateOrderResponse);
    // 获取订单详情 (需处理分库路由)
    rpc GetOrderDetail (GetOrderDetailRequest) returns (GetOrderDetailResponse);
}

message CreateOrderRequest {
    int64 user_id = 1;
    repeated OrderItem items = 2;
    string address = 3;
}

message OrderItem {
    int64 product_id = 1;
    int32 count = 2;
}

message CreateOrderResponse {
    int64 order_id = 1;
    string status = 2;
}
````

---

## 6. 前端开发需求 (TSX)

前端项目结构建议使用 Vite + React + TypeScript。

### 6.1 页面清单
1.  **商品列表页 (`/products`)**
    * 展示模拟商品。
    * 功能：加入购物车、立即购买 (触发 CreateOrder)。
2.  **我的订单页 (`/orders`)**
    * 调用后端 `GetOrders(user_id)`。
    * 展示订单状态（待支付/处理中/已完成）。
    * **难点**：前端需轮询或通过 WebSocket 接收订单状态变化的通知（因为库存扣减是异步的）。
3.  **数据大屏 (`/dashboard`)**
    * **只读**。数据来源于 Elasticsearch 或聚合库。
    * 展示：实时订单流、总销售额。

### 6.2 关键代码示例 (API Client)

````typescript
// src/api/order.ts
import { CreateOrderRequest, CreateOrderResponse } from './proto/order_pb';
import client from './grpc-client'; // 假设封装了 gRPC-Web 或 HTTP 转码

export const createOrder = async (userId: number, items: any[]): Promise<string> => {
    try {
        const req: CreateOrderRequest = { user_id: userId, items };
        const res = await client.post('/v1/order/create', req);
        return res.order_id;
    } catch (e) {
        console.error("Order failed", e);
        throw e;
    }
};
````

---

## 7. 开发路线图 (Roadmap)

1.  **Phase 1: 基础设施 (Week 1)**
    * 搭建 Go Project Layout。
    * Docker Compose 编排 MySQL (2节点), Redis, Etcd。
    * 封装 `dbr` 实现基础的分库路由。
2.  **Phase 2: 核心业务 (Week 2)**
    * 实现 Order Service 的 CRUD。
    * 实现 `Local Message` 表的插入与轮询 Worker。
    * 搭建 MQ，实现 Inventory Service 的消费逻辑。
3.  **Phase 3: 数据同步 (Week 3)**
    * 引入 Canal/Go-mysql。
    * 实现 Binlog 解析器，数据写入 ES。
4.  **Phase 4: 前端与联调 (Week 4)**
    * React 页面开发。
    * 全链路压测 (JMeter)，观察分库下的性能表现。