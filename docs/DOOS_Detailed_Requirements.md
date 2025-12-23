# 分布式高并发订单管理系统 (DOOS) - 详细需求文档

| 项目名称 | Distributed Omni-Order System (DOOS) |
| :--- | :--- |
| **版本** | V1.0.0 - 详细需求 |
| **状态** | 详细设计中 |
| **文档类型** | 详细需求规格说明书 (Detailed Requirements Specification) |
| **最后更新** | 2025-12-23 |

---

## 目录
1. [系统架构详细设计](#1-系统架构详细设计)
2. [数据库详细设计](#2-数据库详细设计)
3. [后端服务详细设计](#3-后端服务详细设计)
4. [前端详细设计](#4-前端详细设计)
5. [非功能性需求](#5-非功能性需求)
6. [部署与运维](#6-部署与运维)
7. [测试策略](#7-测试策略)
8. [风险与应对](#8-风险与应对)

---

## 1. 系统架构详细设计

### 1.1 整体架构图

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ↓
┌─────────────────────────────────────────┐
│         Nginx / API Gateway             │
│  (负载均衡 + TLS终止 + 限流)              │
└──────┬──────────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────────┐
│         gRPC Services Layer              │
│  ┌──────────┐  ┌──────────┐              │
│  │  Order   │  │Inventory │              │
│  │ Service  │  │ Service  │              │
│  └────┬─────┘  └────┬─────┘              │
└───────┼─────────────┼────────────────────┘
        │             │
        ↓             ↓
┌───────────────┐  ┌──────────┐
│  MySQL Shard  │  │  Redis   │
│  ┌─────┬─────┐│  │ (Cache)  │
│  │DB_0 │DB_1 ││  └──────────┘
│  └─────┴─────┘│
└───────┬───────┘
        │ Binlog
        ↓
┌──────────────┐     ┌──────────────┐
│    Canal     │────→│ Elasticsearch│
│   (CDC)      │     │   (CQRS)     │
└──────────────┘     └──────────────┘
```

### 1.2 服务拆分与职责

#### 1.2.1 Order Service (订单服务)
**端口**: 50051 (gRPC), 8081 (HTTP Gateway)

**核心职责**:
- 订单创建、查询、更新、取消
- 分库路由逻辑封装
- 本地消息表管理
- 订单状态机流转

**依赖服务**:
- MySQL Sharding (doos_order_0, doos_order_1)
- Redis (订单缓存、分布式锁)
- Kafka/RabbitMQ (发布库存扣减消息)
- Etcd (服务注册与配置)

**关键指标**:
- QPS: 10,000+ (创建订单)
- 响应时间: P99 < 200ms
- 可用性: 99.9%

#### 1.2.2 Inventory Service (库存服务)
**端口**: 50052 (gRPC), 8082 (HTTP Gateway)

**核心职责**:
- 库存查询、扣减、回滚
- 消费 MQ 消息进行异步库存扣减
- 幂等性保证 (基于消息ID去重)
- 库存预警与补货通知

**依赖服务**:
- MySQL (单库，库存表)
- Redis (库存缓存、热点商品预扣减)
- Kafka/RabbitMQ (消费订单消息)

**关键指标**:
- 消息消费延迟: < 100ms
- 库存扣减成功率: > 99.5%
- 超卖率: 0%

#### 1.2.3 Message Relay Service (消息中继服务)
**端口**: 无对外端口 (后台任务)

**核心职责**:
- 定时扫描所有分库的 `t_local_message` 表
- 将状态为 `Ready` 的消息发送到 MQ
- 失败重试机制 (指数退避)
- 消息状态更新

**扫描策略**:
- 每 5 秒扫描一次
- 每次最多处理 100 条消息
- 失败消息最多重试 5 次
- 重试间隔: 1s, 2s, 4s, 8s, 16s

#### 1.2.4 CDC Consumer Service (数据同步服务)
**端口**: 无对外端口 (后台任务)

**核心职责**:
- 连接 Canal Server 获取 Binlog 事件
- 解析订单表的 INSERT/UPDATE 事件
- 数据清洗与转换
- 写入 Elasticsearch 或 OLAP 数据库

**同步策略**:
- 实时同步 (延迟 < 3s)
- 批量写入 ES (每 100 条或 1 秒)
- 失败重试与死信队列

---

## 2. 数据库详细设计

### 2.1 分库分表策略详解

#### 2.1.1 分库规则
**Sharding Key**: `user_id`
**算法**: `shard_index = user_id % 2`
**优势**:
- 同一用户的订单在同一库，查询效率高
- 避免跨库 JOIN
- 扩容时可采用一致性哈希或翻倍扩容

**劣势与应对**:
- 无法按 `order_id` 直接查询 → 需要通过 ES 或全库扫描
- 数据倾斜风险 → 监控各分库数据量，必要时调整算法

#### 2.1.2 全局唯一 ID 生成
**方案**: Snowflake 算法
**结构** (64 bit):
```
| 1 bit (符号) | 41 bit (时间戳) | 10 bit (机器ID) | 12 bit (序列号) |
```
**实现**:
- 使用 `github.com/bwmarrin/snowflake` 库
- 机器 ID 从 Etcd 获取 (避免冲突)
- 每毫秒可生成 4096 个 ID

### 2.2 核心表结构详细设计

#### 2.2.1 订单主表 (`t_order`)
```sql
CREATE TABLE `t_order` (
  `id` BIGINT UNSIGNED NOT NULL COMMENT '全局唯一订单ID (Snowflake)',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户ID (分库键)',
  `order_no` VARCHAR(32) NOT NULL COMMENT '订单号 (业务层生成，便于展示)',
  `total_amount` DECIMAL(10, 2) NOT NULL COMMENT '订单总金额',
  `discount_amount` DECIMAL(10, 2) DEFAULT 0.00 COMMENT '优惠金额',
  `actual_amount` DECIMAL(10, 2) NOT NULL COMMENT '实付金额',
  `status` TINYINT NOT NULL DEFAULT 0 COMMENT '订单状态: 0-待支付, 1-已支付, 2-已发货, 3-已完成, 4-已取消',
  `payment_method` VARCHAR(20) COMMENT '支付方式: alipay, wechat, credit_card',
  `shipping_address` VARCHAR(500) COMMENT '收货地址 (JSON格式)',
  `remark` VARCHAR(200) COMMENT '订单备注',
  `paid_at` TIMESTAMP NULL COMMENT '支付时间',
  `shipped_at` TIMESTAMP NULL COMMENT '发货时间',
  `completed_at` TIMESTAMP NULL COMMENT '完成时间',
  `cancelled_at` TIMESTAMP NULL COMMENT '取消时间',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_no` (`order_no`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_status_created` (`status`, `created_at`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单主表';
```

**索引说明**:
- `uk_order_no`: 保证订单号唯一性，支持按订单号查询
- `idx_user_id`: 分库键索引，必须
- `idx_status_created`: 支持"查询某状态下的订单列表"
- `idx_created_at`: 支持按时间范围查询

#### 2.2.2 订单明细表 (`t_order_item`)
```sql
CREATE TABLE `t_order_item` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` BIGINT UNSIGNED NOT NULL COMMENT '订单ID',
  `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
  `product_name` VARCHAR(200) NOT NULL COMMENT '商品名称 (冗余)',
  `product_image` VARCHAR(500) COMMENT '商品图片URL',
  `sku_id` BIGINT UNSIGNED COMMENT 'SKU ID',
  `price` DECIMAL(10, 2) NOT NULL COMMENT '商品单价',
  `quantity` INT NOT NULL COMMENT '购买数量',
  `subtotal` DECIMAL(10, 2) NOT NULL COMMENT '小计金额',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_order_id` (`order_id`),
  KEY `idx_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细表';
```

**设计说明**:
- 与 `t_order` 在同一分库
- 冗余商品名称和图片，避免查询商品服务
- `subtotal` 字段便于对账

#### 2.2.3 本地消息表 (`t_local_message`)
```sql
CREATE TABLE `t_local_message` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` VARCHAR(64) NOT NULL COMMENT '消息唯一ID (UUID)',
  `tx_id` VARCHAR(64) NOT NULL COMMENT '业务事务ID (如 order_id)',
  `topic` VARCHAR(50) NOT NULL COMMENT 'MQ Topic',
  `event_type` VARCHAR(50) NOT NULL COMMENT '事件类型: order.created, stock.deduct',
  `payload` JSON NOT NULL COMMENT '消息体',
  `status` TINYINT NOT NULL DEFAULT 0 COMMENT '0-待发送, 1-已发送, 2-已确认, 3-失败',
  `retry_count` INT DEFAULT 0 COMMENT '重试次数',
  `max_retry` INT DEFAULT 5 COMMENT '最大重试次数',
  `next_retry_at` TIMESTAMP NULL COMMENT '下次重试时间',
  `error_msg` VARCHAR(500) COMMENT '失败原因',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_message_id` (`message_id`),
  KEY `idx_status_next_retry` (`status`, `next_retry_at`),
  KEY `idx_tx_id` (`tx_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='本地消息表';
```

**关键字段说明**:
- `message_id`: 全局唯一，用于幂等性校验
- `next_retry_at`: 支持延迟重试
- `error_msg`: 记录失败原因，便于排查

#### 2.2.4 库存表 (`t_inventory`)
```sql
CREATE TABLE `t_inventory` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `product_id` BIGINT UNSIGNED NOT NULL COMMENT '商品ID',
  `sku_id` BIGINT UNSIGNED COMMENT 'SKU ID',
  `available_stock` INT NOT NULL DEFAULT 0 COMMENT '可用库存',
  `locked_stock` INT NOT NULL DEFAULT 0 COMMENT '锁定库存',
  `total_stock` INT NOT NULL DEFAULT 0 COMMENT '总库存',
  `version` INT NOT NULL DEFAULT 0 COMMENT '乐观锁版本号',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_product_sku` (`product_id`, `sku_id`),
  KEY `idx_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存表';
```

**库存扣减策略**:
1. **预扣减** (下单时):
   ```sql
   UPDATE t_inventory 
   SET locked_stock = locked_stock + ?, 
       available_stock = available_stock - ?,
       version = version + 1
   WHERE product_id = ? AND available_stock >= ? AND version = ?;
   ```
2. **确认扣减** (支付成功):
   ```sql
   UPDATE t_inventory 
   SET locked_stock = locked_stock - ?,
       total_stock = total_stock - ?
   WHERE product_id = ?;
   ```
3. **回滚** (订单取消):
   ```sql
   UPDATE t_inventory 
   SET locked_stock = locked_stock - ?,
       available_stock = available_stock + ?
   WHERE product_id = ?;
   ```

#### 2.2.5 消息消费记录表 (`t_message_consume_log`)
```sql
CREATE TABLE `t_message_consume_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` VARCHAR(64) NOT NULL COMMENT '消息ID',
  `consumer_group` VARCHAR(50) NOT NULL COMMENT '消费者组',
  `status` TINYINT NOT NULL COMMENT '0-处理中, 1-成功, 2-失败',
  `retry_count` INT DEFAULT 0,
  `error_msg` VARCHAR(500),
  `consumed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_message_consumer` (`message_id`, `consumer_group`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='消息消费日志';
```

**用途**: 实现消息消费的幂等性

### 2.3 数据库连接池配置

**推荐配置** (基于 `database/sql`):
```go
db.SetMaxOpenConns(100)      // 最大连接数
db.SetMaxIdleConns(20)       // 最大空闲连接
db.SetConnMaxLifetime(1 * time.Hour)  // 连接最大生命周期
db.SetConnMaxIdleTime(10 * time.Minute) // 空闲连接超时
```

**监控指标**:
- 连接池使用率
- 慢查询日志 (> 100ms)
- 死锁检测

---

## 3. 后端服务详细设计

### 3.1 项目目录结构 (Go)

```
doos/
├── cmd/
│   ├── order-service/        # 订单服务入口
│   ├── inventory-service/    # 库存服务入口
│   ├── message-relay/        # 消息中继服务
│   └── cdc-consumer/         # CDC 消费者
├── api/
│   └── proto/v1/             # Protobuf 定义
│       ├── order.proto
│       ├── inventory.proto
│       └── common.proto
├── internal/
│   ├── order/                # 订单服务业务逻辑
│   │   ├── handler/          # gRPC Handler
│   │   ├── service/          # 业务逻辑层
│   │   ├── repository/       # 数据访问层
│   │   └── model/            # 数据模型
│   ├── inventory/            # 库存服务
│   ├── message/              # 消息处理
│   └── cdc/                  # CDC 处理
├── pkg/
│   ├── sharding/             # 分库中间件
│   ├── idgen/                # ID 生成器
│   ├── cache/                # Redis 封装
│   ├── mq/                   # MQ 封装
│   └── errors/               # 错误码定义
├── config/
│   ├── dev.yaml              # 开发环境配置
│   └── prod.yaml             # 生产环境配置
├── deployments/
│   ├── docker-compose.yml    # 本地开发环境
│   └── k8s/                  # Kubernetes 部署文件
├── scripts/
│   ├── init_db.sh            # 数据库初始化脚本
│   └── migrate.sh            # 数据库迁移脚本
├── go.mod
└── go.sum
```

### 3.2 核心接口详细定义

#### 3.2.1 订单服务 Proto 完整定义

```protobuf
syntax = "proto3";

package order.v1;

option go_package = "api/proto/v1;orderv1";

import "google/protobuf/timestamp.proto";

service OrderService {
    // 创建订单
    rpc CreateOrder (CreateOrderRequest) returns (CreateOrderResponse);
    
    // 获取订单详情
    rpc GetOrderDetail (GetOrderDetailRequest) returns (GetOrderDetailResponse);
    
    // 获取用户订单列表
    rpc ListOrders (ListOrdersRequest) returns (ListOrdersResponse);
    
    // 取消订单
    rpc CancelOrder (CancelOrderRequest) returns (CancelOrderResponse);
    
    // 更新订单状态 (内部接口，供库存服务调用)
    rpc UpdateOrderStatus (UpdateOrderStatusRequest) returns (UpdateOrderStatusResponse);
}

message CreateOrderRequest {
    int64 user_id = 1;
    repeated OrderItem items = 2;
    string shipping_address = 3;  // JSON 格式
    string remark = 4;
    string payment_method = 5;
}

message OrderItem {
    int64 product_id = 1;
    int64 sku_id = 2;
    string product_name = 3;
    string product_image = 4;
    double price = 5;
    int32 quantity = 6;
}

message CreateOrderResponse {
    int64 order_id = 1;
    string order_no = 2;
    double actual_amount = 3;
    string status = 4;
    google.protobuf.Timestamp created_at = 5;
}

message GetOrderDetailRequest {
    int64 user_id = 1;  // 用于分库路由
    int64 order_id = 2;
}

message GetOrderDetailResponse {
    Order order = 1;
}

message Order {
    int64 id = 1;
    string order_no = 2;
    int64 user_id = 3;
    double total_amount = 4;
    double actual_amount = 5;
    string status = 6;
    string payment_method = 7;
    string shipping_address = 8;
    repeated OrderItem items = 9;
    google.protobuf.Timestamp created_at = 10;
    google.protobuf.Timestamp paid_at = 11;
}

message ListOrdersRequest {
    int64 user_id = 1;
    string status = 2;  // 可选过滤条件
    int32 page = 3;
    int32 page_size = 4;
}

message ListOrdersResponse {
    repeated Order orders = 1;
    int32 total = 2;
}

message CancelOrderRequest {
    int64 user_id = 1;
    int64 order_id = 2;
    string reason = 3;
}

message CancelOrderResponse {
    bool success = 1;
    string message = 2;
}

message UpdateOrderStatusRequest {
    int64 order_id = 1;
    int64 user_id = 2;
    string status = 3;
}

message UpdateOrderStatusResponse {
    bool success = 1;
}
```

#### 3.2.2 库存服务 Proto 定义

```protobuf
syntax = "proto3";

package inventory.v1;

option go_package = "api/proto/v1;inventoryv1";

service InventoryService {
    // 查询库存
    rpc GetStock (GetStockRequest) returns (GetStockResponse);
    
    // 预扣减库存 (下单时调用)
    rpc PreDeductStock (PreDeductStockRequest) returns (PreDeductStockResponse);
    
    // 确认扣减库存 (支付成功后，由 MQ 消费触发)
    rpc ConfirmDeductStock (ConfirmDeductStockRequest) returns (ConfirmDeductStockResponse);
    
    // 回滚库存 (订单取消)
    rpc RollbackStock (RollbackStockRequest) returns (RollbackStockResponse);
}

message GetStockRequest {
    int64 product_id = 1;
    int64 sku_id = 2;
}

message GetStockResponse {
    int32 available_stock = 1;
    int32 locked_stock = 2;
}

message PreDeductStockRequest {
    int64 product_id = 1;
    int64 sku_id = 2;
    int32 quantity = 3;
}

message PreDeductStockResponse {
    bool success = 1;
    string message = 2;
}

message ConfirmDeductStockRequest {
    string message_id = 1;  // 用于幂等性
    int64 order_id = 2;
    int64 product_id = 3;
    int64 sku_id = 4;
    int32 quantity = 5;
}

message ConfirmDeductStockResponse {
    bool success = 1;
}

message RollbackStockRequest {
    int64 order_id = 1;
    int64 product_id = 2;
    int64 sku_id = 3;
    int32 quantity = 4;
}

message RollbackStockResponse {
    bool success = 1;
}
```

### 3.3 核心业务流程详细设计

#### 3.3.1 创建订单流程 (时序图)

```
用户 -> Order Service: CreateOrder(user_id, items)
Order Service -> Redis: 检查用户是否重复提交 (防重令牌)
Redis -> Order Service: OK
Order Service -> Inventory Service: PreDeductStock(items)
Inventory Service -> Redis: 检查库存缓存
Redis -> Inventory Service: 库存充足
Inventory Service -> MySQL: UPDATE t_inventory (乐观锁)
MySQL -> Inventory Service: 扣减成功
Inventory Service -> Order Service: 预扣减成功
Order Service -> MySQL Shard: BEGIN TRANSACTION
Order Service -> MySQL Shard: INSERT INTO t_order
Order Service -> MySQL Shard: INSERT INTO t_order_item
Order Service -> MySQL Shard: INSERT INTO t_local_message (event: stock.confirm)
Order Service -> MySQL Shard: COMMIT
MySQL Shard -> Order Service: 事务提交成功
Order Service -> 用户: 返回订单ID
```

**关键点**:
1. **防重提交**: 使用 Redis SET NX 实现，key 为 `order:submit:{user_id}:{token}`，过期时间 10 秒
2. **预扣减**: 先扣减库存，失败则直接返回"库存不足"
3. **本地事务**: 订单创建和消息插入在同一事务中
4. **异步确认**: 消息中继服务会将消息发送到 MQ，库存服务消费后确认扣减

#### 3.3.2 消息中继服务处理流程

```go
// 伪代码
func MessageRelayWorker() {
    ticker := time.NewTicker(5 * time.Second)
    for range ticker.C {
        // 遍历所有分库
        for _, shard := range shards {
            messages := shard.Query(`
                SELECT * FROM t_local_message 
                WHERE status = 0 
                AND (next_retry_at IS NULL OR next_retry_at <= NOW())
                LIMIT 100
            `)
            
            for _, msg := range messages {
                err := mqProducer.Send(msg.Topic, msg.Payload)
                if err != nil {
                    // 更新失败状态
                    shard.Exec(`
                        UPDATE t_local_message 
                        SET retry_count = retry_count + 1,
                            next_retry_at = DATE_ADD(NOW(), INTERVAL POW(2, retry_count) SECOND),
                            error_msg = ?,
                            status = CASE WHEN retry_count >= max_retry THEN 3 ELSE 0 END
                        WHERE id = ?
                    `, err.Error(), msg.ID)
                } else {
                    // 更新为已发送
                    shard.Exec(`
                        UPDATE t_local_message 
                        SET status = 1, updated_at = NOW()
                        WHERE id = ?
                    `, msg.ID)
                }
            }
        }
    }
}
```

**关键设计**:
- 指数退避重试 (2^n 秒)
- 失败超过 5 次标记为失败状态
- 支持手动重试 (运维工具)

#### 3.3.3 库存服务消费 MQ 消息流程

```go
func ConsumeStockMessage(msg *kafka.Message) error {
    // 1. 幂等性检查
    exists := db.QueryRow(`
        SELECT 1 FROM t_message_consume_log 
        WHERE message_id = ? AND consumer_group = 'inventory-service'
    `, msg.MessageID).Scan()
    
    if exists {
        log.Info("消息已处理，跳过")
        return nil
    }
    
    // 2. 解析消息
    var payload StockDeductPayload
    json.Unmarshal(msg.Value, &payload)
    
    // 3. 确认扣减库存
    tx, _ := db.Begin()
    result := tx.Exec(`
        UPDATE t_inventory 
        SET locked_stock = locked_stock - ?,
            total_stock = total_stock - ?
        WHERE product_id = ? AND locked_stock >= ?
    `, payload.Quantity, payload.Quantity, payload.ProductID, payload.Quantity)
    
    if result.RowsAffected == 0 {
        tx.Rollback()
        return errors.New("库存不足或已扣减")
    }
    
    // 4. 记录消费日志
    tx.Exec(`
        INSERT INTO t_message_consume_log (message_id, consumer_group, status)
        VALUES (?, 'inventory-service', 1)
    `, msg.MessageID)
    
    tx.Commit()
    
    // 5. 回调订单服务更新状态
    orderClient.UpdateOrderStatus(ctx, &UpdateOrderStatusRequest{
        OrderID: payload.OrderID,
        UserID:  payload.UserID,
        Status:  "paid",
    })
    
    return nil
}
```

**异常处理**:
- 消费失败自动重试 (Kafka 自动重试机制)
- 超过重试次数进入死信队列
- 告警通知运维人员

### 3.4 分库中间件实现

```go
// pkg/sharding/manager.go
package sharding

import (
    "github.com/gocraft/dbr/v2"
)

type ShardingManager struct {
    nodes map[int]*dbr.Connection
}

func NewShardingManager(configs []DBConfig) *ShardingManager {
    nodes := make(map[int]*dbr.Connection)
    for i, cfg := range configs {
        conn, _ := dbr.Open("mysql", cfg.DSN, nil)
        nodes[i] = conn
    }
    return &ShardingManager{nodes: nodes}
}

// 根据 user_id 获取对应的数据库连接
func (m *ShardingManager) GetSession(userID int64) *dbr.Session {
    shardIndex := int(userID % int64(len(m.nodes)))
    return m.nodes[shardIndex].NewSession(nil)
}

// 全库扫描 (用于后台任务)
func (m *ShardingManager) GetAllSessions() []*dbr.Session {
    sessions := make([]*dbr.Session, 0, len(m.nodes))
    for _, conn := range m.nodes {
        sessions = append(sessions, conn.NewSession(nil))
    }
    return sessions
}
```

**使用示例**:
```go
// internal/order/repository/order_repo.go
func (r *OrderRepository) CreateOrder(ctx context.Context, order *model.Order) error {
    sess := r.shardingMgr.GetSession(order.UserID)
    tx, _ := sess.Begin()
    defer tx.RollbackUnlessCommitted()
    
    // 插入订单
    _, err := tx.InsertInto("t_order").
        Columns("id", "user_id", "total_amount", "status").
        Record(order).
        Exec()
    if err != nil {
        return err
    }
    
    // 插入订单明细
    for _, item := range order.Items {
        tx.InsertInto("t_order_item").Record(item).Exec()
    }
    
    // 插入本地消息
    msg := &model.LocalMessage{
        MessageID: uuid.New().String(),
        TxID:      fmt.Sprintf("%d", order.ID),
        Topic:     "stock.deduct",
        Payload:   buildPayload(order),
    }
    tx.InsertInto("t_local_message").Record(msg).Exec()
    
    return tx.Commit()
}
```

### 3.5 错误码设计

```go
// pkg/errors/codes.go
package errors

const (
    // 通用错误 (1xxxx)
    ErrCodeSuccess         = 10000
    ErrCodeInvalidParam    = 10001
    ErrCodeUnauthorized    = 10002
    ErrCodeInternalError   = 10003
    
    // 订单错误 (2xxxx)
    ErrCodeOrderNotFound   = 20001
    ErrCodeOrderCancelled  = 20002
    ErrCodeOrderPaid       = 20003
    ErrCodeDuplicateSubmit = 20004
    
    // 库存错误 (3xxxx)
    ErrCodeStockInsufficient = 30001
    ErrCodeStockLocked       = 30002
)

type BizError struct {
    Code    int
    Message string
}

func (e *BizError) Error() string {
    return fmt.Sprintf("[%d] %s", e.Code, e.Message)
}
```

### 3.6 配置文件示例

```yaml
# config/dev.yaml
server:
  grpc_port: 50051
  http_port: 8081

database:
  shards:
    - dsn: "root:password@tcp(localhost:3306)/doos_order_0?parseTime=true"
      max_open_conns: 100
      max_idle_conns: 20
    - dsn: "root:password@tcp(localhost:3307)/doos_order_1?parseTime=true"
      max_open_conns: 100
      max_idle_conns: 20

redis:
  addr: "localhost:6379"
  password: ""
  db: 0
  pool_size: 100

kafka:
  brokers:
    - "localhost:9092"
  topics:
    stock_deduct: "doos.stock.deduct"

etcd:
  endpoints:
    - "localhost:2379"
  timeout: 5s

snowflake:
  machine_id: 1  # 从 Etcd 获取
```

---

## 4. 前端详细设计

### 4.1 技术栈与工具链

**核心依赖**:
```json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "typescript": "^5.0.0",
    "antd": "^5.0.0",
    "zustand": "^4.0.0",
    "axios": "^1.0.0",
    "react-router-dom": "^6.0.0",
    "@tanstack/react-query": "^5.0.0"
  },
  "devDependencies": {
    "vite": "^5.0.0",
    "@vitejs/plugin-react": "^4.0.0",
    "tailwindcss": "^3.0.0"
  }
}
```

### 4.2 页面结构与路由

```typescript
// src/router/index.tsx
import { createBrowserRouter } from 'react-router-dom';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      { path: '/', element: <HomePage /> },
      { path: '/products', element: <ProductListPage /> },
      { path: '/products/:id', element: <ProductDetailPage /> },
      { path: '/cart', element: <CartPage /> },
      { path: '/orders', element: <OrderListPage /> },
      { path: '/orders/:id', element: <OrderDetailPage /> },
      { path: '/dashboard', element: <DashboardPage /> },
    ],
  },
]);
```

### 4.3 核心页面设计

#### 4.3.1 商品列表页 (`/products`)

**功能需求**:
- 展示商品列表 (分页)
- 支持搜索和筛选
- 显示库存状态
- 加入购物车 / 立即购买

**关键组件**:
```typescript
// src/pages/ProductList/index.tsx
import { useQuery } from '@tanstack/react-query';
import { Card, Button, message } from 'antd';
import { productApi } from '@/api/product';
import { useCartStore } from '@/store/cart';

export const ProductListPage = () => {
  const { data: products, isLoading } = useQuery({
    queryKey: ['products'],
    queryFn: productApi.getList,
  });
  
  const addToCart = useCartStore(state => state.addItem);
  
  const handleAddCart = (product: Product) => {
    addToCart(product);
    message.success('已加入购物车');
  };
  
  const handleBuyNow = async (product: Product) => {
    try {
      const orderId = await orderApi.create({
        user_id: getCurrentUserId(),
        items: [{ product_id: product.id, quantity: 1 }],
      });
      message.success('下单成功');
      navigate(`/orders/${orderId}`);
    } catch (error) {
      message.error(error.message);
    }
  };
  
  return (
    <div className="product-list">
      {products?.map(product => (
        <Card key={product.id}>
          <img src={product.image} />
          <h3>{product.name}</h3>
          <p>¥{product.price}</p>
          <p>库存: {product.stock}</p>
          <Button onClick={() => handleAddCart(product)}>加入购物车</Button>
          <Button type="primary" onClick={() => handleBuyNow(product)}>
            立即购买
          </Button>
        </Card>
      ))}
    </div>
  );
};
```

#### 4.3.2 订单列表页 (`/orders`)

**功能需求**:
- 展示用户订单列表
- 按状态筛选 (全部/待支付/已支付/已发货/已完成)
- 订单状态实时更新 (轮询或 WebSocket)
- 取消订单功能

**状态轮询实现**:
```typescript
// src/pages/OrderList/index.tsx
import { useQuery } from '@tanstack/react-query';
import { orderApi } from '@/api/order';

export const OrderListPage = () => {
  const [statusFilter, setStatusFilter] = useState('all');
  
  // 每 5 秒轮询一次
  const { data: orders } = useQuery({
    queryKey: ['orders', statusFilter],
    queryFn: () => orderApi.getList({ status: statusFilter }),
    refetchInterval: 5000,  // 轮询间隔
  });
  
  const handleCancel = async (orderId: number) => {
    await orderApi.cancel(orderId);
    message.success('订单已取消');
  };
  
  return (
    <div>
      <Tabs onChange={setStatusFilter}>
        <TabPane tab="全部" key="all" />
        <TabPane tab="待支付" key="pending" />
        <TabPane tab="已支付" key="paid" />
      </Tabs>
      
      {orders?.map(order => (
        <OrderCard 
          key={order.id} 
          order={order}
          onCancel={handleCancel}
        />
      ))}
    </div>
  );
};
```

#### 4.3.3 数据大屏 (`/dashboard`)

**功能需求**:
- 实时订单流 (最近 100 条)
- 今日销售额统计
- 热销商品 Top 10
- 订单状态分布饼图

**数据来源**: Elasticsearch (通过 HTTP API)

```typescript
// src/pages/Dashboard/index.tsx
import { useQuery } from '@tanstack/react-query';
import { Line, Pie } from '@ant-design/charts';
import { dashboardApi } from '@/api/dashboard';

export const DashboardPage = () => {
  const { data: stats } = useQuery({
    queryKey: ['dashboard-stats'],
    queryFn: dashboardApi.getStats,
    refetchInterval: 10000,  // 10 秒刷新
  });
  
  return (
    <div className="dashboard">
      <Card title="今日销售额">
        <Statistic value={stats?.todaySales} prefix="¥" />
      </Card>
      
      <Card title="实时订单流">
        <Timeline>
          {stats?.recentOrders.map(order => (
            <Timeline.Item key={order.id}>
              订单 {order.order_no} - ¥{order.amount}
            </Timeline.Item>
          ))}
        </Timeline>
      </Card>
      
      <Card title="订单状态分布">
        <Pie data={stats?.statusDistribution} angleField="value" colorField="status" />
      </Card>
    </div>
  );
};
```

### 4.4 API 客户端封装

```typescript
// src/api/order.ts
import axios from 'axios';

const client = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
  timeout: 10000,
});

// 请求拦截器 (添加 Token)
client.interceptors.request.use(config => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// 响应拦截器 (统一错误处理)
client.interceptors.response.use(
  response => response.data,
  error => {
    const { code, message } = error.response?.data || {};
    if (code === 10002) {
      // 未授权，跳转登录
      window.location.href = '/login';
    }
    return Promise.reject(new Error(message || '请求失败'));
  }
);

export const orderApi = {
  create: (data: CreateOrderRequest) => 
    client.post('/v1/order/create', data),
  
  getDetail: (orderId: number, userId: number) => 
    client.get(`/v1/order/${orderId}`, { params: { user_id: userId } }),
  
  getList: (params: { status?: string; page?: number }) => 
    client.get('/v1/order/list', { params }),
  
  cancel: (orderId: number) => 
    client.post(`/v1/order/${orderId}/cancel`),
};
```

### 4.5 状态管理 (Zustand)

```typescript
// src/store/cart.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface CartItem {
  product_id: number;
  product_name: string;
  price: number;
  quantity: number;
}

interface CartStore {
  items: CartItem[];
  addItem: (product: Product) => void;
  removeItem: (productId: number) => void;
  updateQuantity: (productId: number, quantity: number) => void;
  clear: () => void;
  getTotalAmount: () => number;
}

export const useCartStore = create<CartStore>()(
  persist(
    (set, get) => ({
      items: [],
      
      addItem: (product) => set(state => {
        const existing = state.items.find(i => i.product_id === product.id);
        if (existing) {
          return {
            items: state.items.map(i => 
              i.product_id === product.id 
                ? { ...i, quantity: i.quantity + 1 }
                : i
            ),
          };
        }
        return {
          items: [...state.items, {
            product_id: product.id,
            product_name: product.name,
            price: product.price,
            quantity: 1,
          }],
        };
      }),
      
      removeItem: (productId) => set(state => ({
        items: state.items.filter(i => i.product_id !== productId),
      })),
      
      updateQuantity: (productId, quantity) => set(state => ({
        items: state.items.map(i => 
          i.product_id === productId ? { ...i, quantity } : i
        ),
      })),
      
      clear: () => set({ items: [] }),
      
      getTotalAmount: () => {
        const { items } = get();
        return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
      },
    }),
    { name: 'cart-storage' }
  )
);
```

---

## 5. 非功能性需求

### 5.1 性能指标

| 指标 | 目标值 | 测量方法 |
|------|--------|----------|
| 订单创建 QPS | 10,000+ | JMeter 压测 |
| 订单查询 QPS | 50,000+ | 缓存命中率 > 80% |
| API 响应时间 (P99) | < 200ms | Prometheus + Grafana |
| 数据库连接池使用率 | < 80% | 监控告警 |
| MQ 消息消费延迟 | < 100ms | Kafka Lag 监控 |
| Binlog 同步延迟 | < 3s | Canal 监控 |

### 5.2 可用性与容错

**目标**: 99.9% 可用性 (每月停机时间 < 43 分钟)

**容错措施**:
1. **服务多实例部署**: 每个服务至少 3 个实例
2. **数据库主从复制**: 主库故障自动切换到从库
3. **消息队列集群**: Kafka 3 节点集群
4. **熔断降级**: 使用 Hystrix 或 Sentinel
5. **限流**: 基于 Token Bucket 算法

**熔断策略示例**:
```go
// 使用 go-hystrix
hystrix.ConfigureCommand("create_order", hystrix.CommandConfig{
    Timeout:                1000,  // 超时时间 1s
    MaxConcurrentRequests:  100,   // 最大并发
    ErrorPercentThreshold:  50,    // 错误率阈值
    RequestVolumeThreshold: 20,    // 最小请求数
    SleepWindow:            5000,  // 熔断恢复时间
})

err := hystrix.Do("create_order", func() error {
    return orderService.CreateOrder(ctx, req)
}, func(err error) error {
    // 降级逻辑：返回缓存数据或友好提示
    return errors.New("系统繁忙，请稍后重试")
})
```

### 5.3 安全性需求

#### 5.3.1 认证与授权
- **JWT Token**: 有效期 2 小时，Refresh Token 7 天
- **RBAC**: 用户、管理员、运维三种角色
- **API 签名**: 关键接口需要签名验证

#### 5.3.2 数据安全
- **敏感数据加密**: 用户地址、手机号使用 AES-256 加密
- **SQL 注入防护**: 使用参数化查询
- **XSS 防护**: 前端输入过滤和转义
- **HTTPS**: 生产环境强制 HTTPS

#### 5.3.3 防刷与限流
```go
// 基于 Redis 的限流器
func RateLimiter(userID int64, limit int, window time.Duration) bool {
    key := fmt.Sprintf("rate_limit:%d", userID)
    count, _ := redis.Incr(key)
    if count == 1 {
        redis.Expire(key, window)
    }
    return count <= limit
}

// 使用示例：每分钟最多 10 次请求
if !RateLimiter(userID, 10, time.Minute) {
    return errors.New("请求过于频繁")
}
```

### 5.4 可观测性

#### 5.4.1 日志规范
**日志级别**: DEBUG, INFO, WARN, ERROR, FATAL
**日志格式** (JSON):
```json
{
  "timestamp": "2025-12-23T10:30:00Z",
  "level": "INFO",
  "service": "order-service",
  "trace_id": "abc123",
  "user_id": 10001,
  "message": "订单创建成功",
  "order_id": 123456789,
  "duration_ms": 45
}
```

**日志收集**: Filebeat -> Elasticsearch -> Kibana

#### 5.4.2 监控指标
**使用 Prometheus + Grafana**

**关键指标**:
```go
// 自定义指标
var (
    orderCreatedCounter = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "order_created_total",
            Help: "订单创建总数",
        },
        []string{"status"},
    )
    
    orderCreateDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "order_create_duration_seconds",
            Help:    "订单创建耗时",
            Buckets: []float64{0.01, 0.05, 0.1, 0.5, 1, 2},
        },
        []string{"status"},
    )
)

// 使用示例
func CreateOrder(ctx context.Context, req *CreateOrderRequest) error {
    start := time.Now()
    defer func() {
        duration := time.Since(start).Seconds()
        orderCreateDuration.WithLabelValues("success").Observe(duration)
        orderCreatedCounter.WithLabelValues("success").Inc()
    }()
    
    // 业务逻辑
    return nil
}
```

#### 5.4.3 链路追踪
**使用 OpenTelemetry + Jaeger**

```go
import "go.opentelemetry.io/otel"

func CreateOrder(ctx context.Context, req *CreateOrderRequest) error {
    tracer := otel.Tracer("order-service")
    ctx, span := tracer.Start(ctx, "CreateOrder")
    defer span.End()
    
    // 添加属性
    span.SetAttributes(
        attribute.Int64("user_id", req.UserID),
        attribute.Float64("amount", req.TotalAmount),
    )
    
    // 调用下游服务时传递 context
    err := inventoryService.PreDeductStock(ctx, req.Items)
    if err != nil {
        span.RecordError(err)
        return err
    }
    
    return nil
}
```

### 5.5 数据一致性保证

#### 5.5.1 分布式事务方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| 2PC (两阶段提交) | 强一致性 | 性能差、阻塞 | 金融核心系统 |
| TCC (Try-Confirm-Cancel) | 性能好 | 实现复杂 | 高并发场景 |
| 本地消息表 | 实现简单、可靠 | 最终一致性 | 本项目采用 |
| Saga | 灵活 | 补偿逻辑复杂 | 长事务 |

**本项目选择**: 本地消息表 + MQ

#### 5.5.2 幂等性设计

**场景 1: API 幂等性**
```go
// 使用防重令牌
func CreateOrder(ctx context.Context, req *CreateOrderRequest) error {
    // 检查令牌
    key := fmt.Sprintf("order:token:%s", req.IdempotencyToken)
    exists := redis.SetNX(key, 1, 10*time.Second)
    if !exists {
        return errors.New("重复提交")
    }
    
    // 业务逻辑
    return nil
}
```

**场景 2: MQ 消费幂等性**
```go
// 使用消息 ID 去重
func ConsumeMessage(msg *Message) error {
    // 检查是否已处理
    exists := db.QueryRow(`
        SELECT 1 FROM t_message_consume_log 
        WHERE message_id = ?
    `, msg.ID).Scan()
    
    if exists {
        return nil  // 已处理，直接返回
    }
    
    // 处理业务 + 记录日志在同一事务中
    tx.Begin()
    // ... 业务逻辑
    tx.Exec(`INSERT INTO t_message_consume_log ...`)
    tx.Commit()
    
    return nil
}
```

---

## 6. 部署与运维

### 6.1 Docker Compose 本地开发环境

```yaml
# deployments/docker-compose.yml
version: '3.8'

services:
  # MySQL 分库 0
  mysql-shard-0:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: doos_order_0
    ports:
      - "3306:3306"
    volumes:
      - ./scripts/init_db.sql:/docker-entrypoint-initdb.d/init.sql
      - mysql-shard-0-data:/var/lib/mysql
    command: --default-authentication-plugin=mysql_native_password

  # MySQL 分库 1
  mysql-shard-1:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: doos_order_1
    ports:
      - "3307:3306"
    volumes:
      - ./scripts/init_db.sql:/docker-entrypoint-initdb.d/init.sql
      - mysql-shard-1-data:/var/lib/mysql

  # MySQL 库存库
  mysql-inventory:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: doos_inventory
    ports:
      - "3308:3306"
    volumes:
      - mysql-inventory-data:/var/lib/mysql

  # Redis
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes

  # Kafka
  kafka:
    image: bitnami/kafka:latest
    ports:
      - "9092:9092"
    environment:
      KAFKA_CFG_NODE_ID: 0
      KAFKA_CFG_PROCESS_ROLES: controller,broker
      KAFKA_CFG_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_CFG_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: 0@kafka:9093
      KAFKA_CFG_CONTROLLER_LISTENER_NAMES: CONTROLLER

  # Etcd
  etcd:
    image: bitnami/etcd:latest
    ports:
      - "2379:2379"
    environment:
      ALLOW_NONE_AUTHENTICATION: yes

  # Elasticsearch
  elasticsearch:
    image: elasticsearch:8.11.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
    ports:
      - "9200:9200"
    volumes:
      - es-data:/usr/share/elasticsearch/data

  # Kibana
  kibana:
    image: kibana:8.11.0
    ports:
      - "5601:5601"
    environment:
      ELASTICSEARCH_HOSTS: http://elasticsearch:9200

  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml

  # Grafana
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin

volumes:
  mysql-shard-0-data:
  mysql-shard-1-data:
  mysql-inventory-data:
  es-data:
```

### 6.2 Kubernetes 生产部署

#### 6.2.1 Order Service Deployment
```yaml
# deployments/k8s/order-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: doos
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
      - name: order-service
        image: doos/order-service:v1.0.0
        ports:
        - containerPort: 50051
          name: grpc
        - containerPort: 8081
          name: http
        env:
        - name: CONFIG_PATH
          value: /etc/config/prod.yaml
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8081
          initialDelaySeconds: 10
          periodSeconds: 5
        volumeMounts:
        - name: config
          mountPath: /etc/config
      volumes:
      - name: config
        configMap:
          name: order-service-config
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: doos
spec:
  selector:
    app: order-service
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
  - name: http
    port: 8081
    targetPort: 8081
  type: ClusterIP
```

#### 6.2.2 HPA (水平自动扩缩容)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-service-hpa
  namespace: doos
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 6.3 数据库迁移脚本

```bash
#!/bin/bash
# scripts/init_db.sh

SHARDS=("localhost:3306" "localhost:3307")
INVENTORY_HOST="localhost:3308"
PASSWORD="root123"

echo "初始化订单分库..."
for shard in "${SHARDS[@]}"; do
    echo "处理分库: $shard"
    mysql -h ${shard%:*} -P ${shard#*:} -uroot -p$PASSWORD <<EOF
CREATE DATABASE IF NOT EXISTS doos_order_${shard#*:} DEFAULT CHARSET utf8mb4;
USE doos_order_${shard#*:};

-- 创建订单表
$(cat sql/t_order.sql)

-- 创建订单明细表
$(cat sql/t_order_item.sql)

-- 创建本地消息表
$(cat sql/t_local_message.sql)
EOF
done

echo "初始化库存库..."
mysql -h ${INVENTORY_HOST%:*} -P ${INVENTORY_HOST#*:} -uroot -p$PASSWORD <<EOF
CREATE DATABASE IF NOT EXISTS doos_inventory DEFAULT CHARSET utf8mb4;
USE doos_inventory;

$(cat sql/t_inventory.sql)
$(cat sql/t_message_consume_log.sql)
EOF

echo "数据库初始化完成！"
```

### 6.4 监控告警规则

```yaml
# config/prometheus-rules.yml
groups:
- name: doos_alerts
  interval: 30s
  rules:
  # API 错误率告警
  - alert: HighErrorRate
    expr: |
      rate(http_requests_total{status=~"5.."}[5m]) 
      / rate(http_requests_total[5m]) > 0.05
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "服务 {{ $labels.service }} 错误率过高"
      description: "错误率: {{ $value | humanizePercentage }}"

  # 响应时间告警
  - alert: HighLatency
    expr: |
      histogram_quantile(0.99, 
        rate(http_request_duration_seconds_bucket[5m])
      ) > 0.2
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "服务 {{ $labels.service }} 响应时间过长"
      description: "P99 延迟: {{ $value }}s"

  # 数据库连接池告警
  - alert: DBPoolExhausted
    expr: |
      db_connections_in_use / db_connections_max > 0.8
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "数据库连接池使用率过高"

  # MQ 消费延迟告警
  - alert: KafkaConsumerLag
    expr: kafka_consumer_lag > 1000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Kafka 消费延迟过高"
      description: "Topic: {{ $labels.topic }}, Lag: {{ $value }}"
```

### 6.5 备份与恢复策略

**数据库备份**:
- **全量备份**: 每天凌晨 2 点执行
- **增量备份**: 每小时执行一次 Binlog 备份
- **保留策略**: 全量备份保留 30 天，增量备份保留 7 天

```bash
#!/bin/bash
# scripts/backup_db.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/data/backup/mysql"

# 备份订单分库
for port in 3306 3307; do
    mysqldump -h localhost -P $port -uroot -proot123 \
        --single-transaction \
        --master-data=2 \
        --databases doos_order_$port \
        | gzip > $BACKUP_DIR/order_${port}_${DATE}.sql.gz
done

# 上传到 S3 (可选)
aws s3 cp $BACKUP_DIR/ s3://doos-backup/mysql/ --recursive

echo "备份完成: $DATE"
```

---

## 7. 测试策略

### 7.1 单元测试

**覆盖率要求**: > 80%

**示例**:
```go
// internal/order/service/order_service_test.go
package service

import (
    "testing"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

type MockOrderRepo struct {
    mock.Mock
}

func (m *MockOrderRepo) Create(order *model.Order) error {
    args := m.Called(order)
    return args.Error(0)
}

func TestCreateOrder_Success(t *testing.T) {
    // Arrange
    mockRepo := new(MockOrderRepo)
    mockRepo.On("Create", mock.Anything).Return(nil)
    
    service := NewOrderService(mockRepo)
    
    // Act
    err := service.CreateOrder(ctx, &CreateOrderRequest{
        UserID: 123,
        Items:  []OrderItem{{ProductID: 1, Quantity: 1}},
    })
    
    // Assert
    assert.NoError(t, err)
    mockRepo.AssertExpectations(t)
}

func TestCreateOrder_InsufficientStock(t *testing.T) {
    // 测试库存不足场景
    // ...
}
```

### 7.2 集成测试

**测试环境**: Docker Compose 启动完整环境

```go
// test/integration/order_test.go
func TestCreateOrderE2E(t *testing.T) {
    // 1. 准备测试数据
    db.Exec("INSERT INTO t_inventory (product_id, available_stock) VALUES (1, 100)")
    
    // 2. 调用 gRPC 接口
    client := orderv1.NewOrderServiceClient(conn)
    resp, err := client.CreateOrder(ctx, &orderv1.CreateOrderRequest{
        UserID: 123,
        Items: []*orderv1.OrderItem{
            {ProductID: 1, Quantity: 1},
        },
    })
    
    // 3. 验证结果
    assert.NoError(t, err)
    assert.NotZero(t, resp.OrderId)
    
    // 4. 验证数据库
    var order model.Order
    db.QueryRow("SELECT * FROM t_order WHERE id = ?", resp.OrderId).Scan(&order)
    assert.Equal(t, "pending", order.Status)
    
    // 5. 验证消息表
    var msgCount int
    db.QueryRow("SELECT COUNT(*) FROM t_local_message WHERE tx_id = ?", resp.OrderId).Scan(&msgCount)
    assert.Equal(t, 1, msgCount)
}
```

### 7.3 性能测试

**工具**: JMeter / Gatling

**测试场景**:
1. **创建订单**: 10,000 QPS, 持续 10 分钟
2. **查询订单**: 50,000 QPS, 持续 10 分钟
3. **混合场景**: 读写比 8:2

**JMeter 脚本示例**:
```xml
<ThreadGroup>
  <stringProp name="ThreadGroup.num_threads">1000</stringProp>
  <stringProp name="ThreadGroup.ramp_time">60</stringProp>
  <stringProp name="ThreadGroup.duration">600</stringProp>
  
  <HTTPSamplerProxy>
    <stringProp name="HTTPSampler.domain">localhost</stringProp>
    <stringProp name="HTTPSampler.port">8081</stringProp>
    <stringProp name="HTTPSampler.path">/v1/order/create</stringProp>
    <stringProp name="HTTPSampler.method">POST</stringProp>
    <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
  </HTTPSamplerProxy>
</ThreadGroup>
```

**性能基准**:
- TPS: > 10,000
- 平均响应时间: < 50ms
- P99 响应时间: < 200ms
- 错误率: < 0.1%

### 7.4 混沌工程测试

**使用 Chaos Mesh 进行故障注入**:

```yaml
# test/chaos/network-delay.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay
  namespace: doos
spec:
  action: delay
  mode: one
  selector:
    namespaces:
      - doos
    labelSelectors:
      app: order-service
  delay:
    latency: "100ms"
    correlation: "100"
  duration: "5m"
```

**测试场景**:
- 网络延迟 (100ms, 500ms, 1s)
- 数据库故障 (主库宕机)
- MQ 故障 (Kafka 节点宕机)
- 服务 OOM (内存限制)

---

## 8. 风险与应对

### 8.1 技术风险

| 风险 | 影响 | 概率 | 应对措施 |
|------|------|------|----------|
| 数据库分库扩容困难 | 高 | 中 | 预留扩容方案 (一致性哈希)，监控数据增长 |
| 消息丢失导致数据不一致 | 高 | 低 | 本地消息表 + 重试机制 + 死信队列 |
| 热点数据导致分库倾斜 | 中 | 中 | 监控各分库数据量，必要时调整分库算法 |
| Binlog 同步延迟过高 | 中 | 低 | 优化 Canal 配置，增加消费者实例 |
| 缓存雪崩 | 高 | 低 | 缓存预热 + 随机过期时间 + 熔断降级 |

### 8.2 业务风险

| 风险 | 影响 | 概率 | 应对措施 |
|------|------|------|----------|
| 超卖问题 | 高 | 中 | 乐观锁 + Redis 预扣减 + 库存对账 |
| 恶意刷单 | 中 | 高 | 限流 + 风控规则 + 验证码 |
| 订单状态不一致 | 中 | 低 | 定时对账任务 + 人工介入 |
| 支付回调丢失 | 高 | 低 | 主动查询支付状态 + 补偿机制 |

### 8.3 运维风险

| 风险 | 影响 | 概率 | 应对措施 |
|------|------|------|----------|
| 数据库主库宕机 | 高 | 低 | 主从切换 + 定期演练 |
| 磁盘空间不足 | 高 | 中 | 监控告警 + 自动清理日志 |
| 配置错误导致服务不可用 | 高 | 中 | 配置版本管理 + 灰度发布 |
| 依赖服务故障 | 中 | 中 | 熔断降级 + 多活部署 |

### 8.4 应急预案

#### 8.4.1 数据库故障
**现象**: 订单创建失败，错误日志显示数据库连接超时

**处理步骤**:
1. 检查数据库状态: `SHOW PROCESSLIST;`
2. 如果主库宕机，切换到从库
3. 如果是慢查询导致，Kill 慢查询进程
4. 通知 DBA 介入

#### 8.4.2 MQ 消息堆积
**现象**: Kafka Lag 持续增长，库存扣减延迟

**处理步骤**:
1. 检查消费者状态和日志
2. 增加消费者实例数量
3. 如果是消费逻辑问题，紧急修复并重新部署
4. 必要时暂停生产者，优先消费积压消息

#### 8.4.3 缓存穿透
**现象**: Redis 命中率骤降，数据库负载飙升

**处理步骤**:
1. 启用布隆过滤器拦截无效请求
2. 对空值进行短时间缓存
3. 限流保护数据库
4. 排查攻击来源并封禁 IP

---

## 9. 开发排期与里程碑

### 9.1 Phase 1: 基础设施搭建 (Week 1)

**目标**: 完成开发环境搭建和基础框架

**任务清单**:
- [ ] 初始化 Go 项目结构
- [ ] 编写 Docker Compose 配置
- [ ] 搭建 MySQL 分库 (2 节点)
- [ ] 搭建 Redis, Kafka, Etcd
- [ ] 实现分库中间件 (基于 dbr)
- [ ] 实现 Snowflake ID 生成器
- [ ] 编写数据库初始化脚本

**交付物**:
- 可运行的本地开发环境
- 分库中间件代码
- 数据库表结构 SQL

### 9.2 Phase 2: 核心业务开发 (Week 2-3)

**目标**: 完成订单和库存服务核心功能

**任务清单**:
- [ ] 定义 Protobuf 接口
- [ ] 实现 Order Service CRUD
- [ ] 实现本地消息表逻辑
- [ ] 实现 Message Relay Service
- [ ] 实现 Inventory Service
- [ ] 实现 MQ 消费逻辑
- [ ] 实现幂等性保证
- [ ] 编写单元测试 (覆盖率 > 80%)

**交付物**:
- 可运行的订单创建流程
- 可运行的库存扣减流程
- 单元测试报告

### 9.3 Phase 3: 数据同步与查询 (Week 4)

**目标**: 实现 CDC 数据同步和 CQRS 查询

**任务清单**:
- [ ] 部署 Canal Server
- [ ] 实现 Binlog Consumer
- [ ] 数据写入 Elasticsearch
- [ ] 实现跨库查询接口
- [ ] 实现数据大屏 API

**交付物**:
- 实时数据同步功能
- Elasticsearch 查询接口

### 9.4 Phase 4: 前端开发 (Week 5)

**目标**: 完成前端页面和联调

**任务清单**:
- [ ] 初始化 React 项目
- [ ] 实现商品列表页
- [ ] 实现购物车功能
- [ ] 实现订单列表页
- [ ] 实现订单详情页
- [ ] 实现数据大屏
- [ ] 前后端联调

**交付物**:
- 可用的前端应用
- 前后端联调通过

### 9.5 Phase 5: 测试与优化 (Week 6)

**目标**: 完成性能测试和优化

**任务清单**:
- [ ] 编写集成测试
- [ ] 执行性能测试 (JMeter)
- [ ] 性能优化 (缓存、索引)
- [ ] 压测报告
- [ ] 混沌工程测试
- [ ] 文档完善

**交付物**:
- 性能测试报告
- 优化方案文档
- 完整的技术文档

### 9.6 Phase 6: 上线准备 (Week 7)

**目标**: 完成生产环境部署

**任务清单**:
- [ ] 编写 Kubernetes 部署文件
- [ ] 配置监控告警
- [ ] 配置日志收集
- [ ] 配置链路追踪
- [ ] 编写运维手册
- [ ] 灰度发布
- [ ] 生产环境验证

**交付物**:
- 生产环境部署成功
- 监控大盘
- 运维手册

---

## 10. 附录

### 10.1 术语表

| 术语 | 全称 | 说明 |
|------|------|------|
| DOOS | Distributed Omni-Order System | 分布式全渠道订单系统 |
| CDC | Change Data Capture | 变更数据捕获 |
| CQRS | Command Query Responsibility Segregation | 命令查询职责分离 |
| TCC | Try-Confirm-Cancel | 补偿型分布式事务 |
| QPS | Queries Per Second | 每秒查询数 |
| TPS | Transactions Per Second | 每秒事务数 |
| P99 | 99th Percentile | 99 分位数 |
| HPA | Horizontal Pod Autoscaler | 水平自动扩缩容 |

### 10.2 参考资料

1. **分布式事务**:
   - [Saga 模式详解](https://microservices.io/patterns/data/saga.html)
   - [本地消息表实践](https://www.infoq.cn/article/solution-of-distributed-system-transaction-consistency)

2. **数据库分库分表**:
   - [MySQL 分库分表最佳实践](https://dev.mysql.com/doc/refman/8.0/en/partitioning.html)
   - [Snowflake ID 生成算法](https://github.com/bwmarrin/snowflake)

3. **Go 微服务**:
   - [gRPC Go 官方文档](https://grpc.io/docs/languages/go/)
   - [Go 项目布局标准](https://github.com/golang-standards/project-layout)

4. **监控与可观测性**:
   - [Prometheus 最佳实践](https://prometheus.io/docs/practices/)
   - [OpenTelemetry 入门](https://opentelemetry.io/docs/)

### 10.3 联系方式

**项目负责人**: [姓名]
**技术负责人**: [姓名]
**产品负责人**: [姓名]

---

**文档结束**

*本文档为 DOOS 项目的详细需求规格说明书，涵盖了系统架构、数据库设计、接口定义、部署运维等各个方面。如有疑问或需要补充，请联系项目组。*
