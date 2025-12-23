# DOOS - Distributed Omni-Order System

分布式高并发订单管理系统

[![Version](https://img.shields.io/badge/version-v0.1.0-blue.svg)](https://github.com/OLRainM/DOOS/releases)
[![Go Version](https://img.shields.io/badge/go-1.25+-00ADD8.svg)](https://golang.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-Week%201%20Complete-success.svg)](PROJECT_STATUS.md)

## 项目简介

DOOS 是一个模拟中大型电商平台核心交易链路的后端系统，采用 Go 语言开发，实现了：

- 🚀 **高性能**: 通过水平分库支撑海量订单数据
- 🔄 **分布式事务**: 基于本地消息表的最终一致性方案
- 📊 **数据同步**: 通过 Binlog CDC 实现异构数据查询
- 🛠️ **工程化**: 企业级 Go 微服务工程规范

## 技术栈

### 后端
- **语言**: Go 1.25+
- **框架**: gRPC + Protobuf
- **ORM**: gocraft/dbr
- **数据库**: MySQL 8.0 (分库)
- **缓存**: Redis 7
- **消息队列**: Kafka
- **服务发现**: Etcd
- **数据同步**: Canal (Binlog CDC)
- **搜索引擎**: Elasticsearch

### 前端
- **框架**: React 18
- **语言**: TypeScript
- **UI**: Ant Design
- **状态管理**: Zustand
- **构建工具**: Vite

## 快速开始

### 前置要求

- Go 1.25+
- Docker & Docker Compose
- MySQL Client (可选，用于手动初始化)

### 1. 克隆项目

```bash
git clone git@github.com:OLRainM/DOOS.git
cd DOOS
```

### 2. 启动基础设施

使用 Docker Compose 启动所有依赖服务：

```bash
cd deployments
docker-compose up -d
```

等待所有服务启动完成（约 1-2 分钟）：

```bash
docker-compose ps
```

### 3. 初始化数据库

**Linux/Mac:**
```bash
cd scripts
chmod +x init_db.sh
./init_db.sh
```

**Windows:**
```cmd
cd scripts
init_db.bat
```

### 4. 安装 Go 依赖

```bash
go mod download
```

### 5. 运行服务

```bash
# 运行订单服务
go run cmd/order-service/main.go

# 运行库存服务
go run cmd/inventory-service/main.go
```

### 6. 运行测试

```bash
# 运行所有测试
go test ./...

# 运行测试并显示覆盖率
go test -cover ./...
```

### 服务访问地址

启动成功后，可以访问以下服务：

| 服务 | 地址 | 说明 |
|------|------|------|
| MySQL Shard 0 | localhost:3306 | 订单分库 0 |
| MySQL Shard 1 | localhost:3307 | 订单分库 1 |
| MySQL Inventory | localhost:3308 | 库存库 |
| Redis | localhost:6379 | 缓存 |
| Kafka | localhost:9092 | 消息队列 |
| Etcd | localhost:2379 | 服务发现 |
| Elasticsearch | http://localhost:9200 | 搜索引擎 |
| Kibana | http://localhost:5601 | ES 可视化 |
| Prometheus | http://localhost:9090 | 监控 |
| Grafana | http://localhost:3000 | 监控可视化 (admin/admin) |

## 项目结构

```
doos/
├── cmd/                    # 服务入口
│   ├── order-service/      # 订单服务
│   ├── inventory-service/  # 库存服务
│   ├── message-relay/      # 消息中继服务
│   └── cdc-consumer/       # CDC 消费者
├── internal/               # 内部业务逻辑 (Week 2+)
│   ├── order/              # 订单模块
│   ├── inventory/          # 库存模块
│   ├── message/            # 消息处理
│   └── cdc/                # CDC 处理
├── pkg/                    # 公共包
│   ├── sharding/           # 分库中间件 ✅
│   ├── idgen/              # ID 生成器 ✅
│   ├── cache/              # Redis 封装 (Week 2+)
│   ├── mq/                 # MQ 封装 (Week 2+)
│   └── errors/             # 错误码定义 (Week 2+)
├── api/                    # API 定义 (Week 2+)
│   └── proto/v1/           # Protobuf 文件
├── config/                 # 配置文件 ✅
├── scripts/                # 脚本 ✅
│   └── sql/                # SQL 脚本 ✅
├── deployments/            # 部署文件 ✅
│   ├── docker-compose.yml  # Docker Compose ✅
│   └── k8s/                # Kubernetes (Week 6+)
└── docs/                   # 文档 ✅
    ├── DOOS_Requirements.md
    ├── DOOS_Detailed_Requirements.md
    └── ...
```

## 核心功能

### 1. 分库分表

- 基于 `user_id` 的 Hash 分库策略
- 支持 2 个分库节点（可扩展）
- 自动路由到对应分库

### 2. 分布式事务

- 本地消息表 + MQ 实现最终一致性
- 消息重试机制（指数退避）
- 幂等性保证

### 3. 数据同步

- Canal 监听 MySQL Binlog
- 实时同步到 Elasticsearch
- 支持跨库查询和统计

### 4. ID 生成

- Snowflake 算法
- 全局唯一、递增
- 高性能（单机 400w+/s）

## 配置说明

配置文件位于 `config/` 目录：

- `dev.yaml`: 开发环境配置
- `prod.yaml`: 生产环境配置

主要配置项：

```yaml
server:
  grpc_port: 50051
  http_port: 8081

database:
  shards:
    - dsn: "root:root123@tcp(localhost:3306)/doos_order_0"
    - dsn: "root:root123@tcp(localhost:3307)/doos_order_1"

redis:
  addr: "localhost:6379"

kafka:
  brokers:
    - "localhost:9092"
```

## 常用命令

```bash
# 编译所有服务
make build

# 运行测试
make test

# 查看测试覆盖率
make test-cover

# 启动 Docker 环境
make docker-up

# 停止 Docker 环境
make docker-down

# 初始化数据库
make init-db

# 格式化代码
make fmt

# 清理编译产物
make clean

# 查看所有命令
make help
```

## 监控与可观测性

### Prometheus

访问 http://localhost:9090 查看 Prometheus

### Grafana

访问 http://localhost:3000 查看 Grafana
- 用户名: admin
- 密码: admin

### Kibana

访问 http://localhost:5601 查看 Kibana

## 常见问题

### Q: Docker 容器启动失败？

A: 检查端口是否被占用，确保 3306, 3307, 3308, 6379, 9092 等端口可用。

### Q: 数据库连接失败？

A: 确保 Docker 容器已启动，检查配置文件中的 DSN 是否正确。

### Q: Kafka 消息发送失败？

A: 等待 Kafka 完全启动（约 30 秒），检查 Kafka 健康状态。

## 文档

详细的技术文档和需求说明请查看：

- [详细需求文档](docs/DOOS_Detailed_Requirements.md) - 完整的系统设计和技术规格

## 开发路线图

- [x] **Week 1**: 基础设施搭建 ✅
- [ ] **Week 2**: 核心业务开发
- [ ] **Week 3**: 数据同步与 CDC
- [ ] **Week 4**: 前端开发
- [ ] **Week 5**: 测试与优化
- [ ] **Week 6**: 上线准备

## 贡献指南

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 联系方式

- GitHub: [@OLRainM](https://github.com/OLRainM)
- 项目地址: https://github.com/OLRainM/DOOS
