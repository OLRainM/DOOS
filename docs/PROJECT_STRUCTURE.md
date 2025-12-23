# DOOS 项目结构说明

## 目录树

```
doos/
├── cmd/                           # 服务入口目录
│   ├── order-service/             # 订单服务
│   │   └── main.go
│   ├── inventory-service/         # 库存服务
│   │   └── main.go
│   ├── message-relay/             # 消息中继服务
│   │   └── main.go
│   └── cdc-consumer/              # CDC 消费者服务
│       └── main.go
│
├── pkg/                           # 公共包目录
│   ├── idgen/                     # ID 生成器
│   │   ├── snowflake.go           # Snowflake 算法实现
│   │   └── snowflake_test.go      # 单元测试
│   └── sharding/                  # 分库中间件
│       ├── manager.go             # 分库管理器
│       └── manager_test.go        # 单元测试
│
├── config/                        # 配置文件目录
│   ├── dev.yaml                   # 开发环境配置
│   └── prod.yaml                  # 生产环境配置
│
├── scripts/                       # 脚本目录
│   ├── sql/                       # SQL 脚本
│   │   ├── t_order.sql            # 订单表
│   │   ├── t_order_item.sql       # 订单明细表
│   │   ├── t_local_message.sql    # 本地消息表
│   │   ├── t_inventory.sql        # 库存表
│   │   └── t_message_consume_log.sql  # 消息消费日志表
│   ├── init_db.sh                 # 数据库初始化脚本 (Linux/Mac)
│   ├── init_db.bat                # 数据库初始化脚本 (Windows)
│   ├── start.sh                   # 项目启动脚本 (Linux/Mac)
│   └── start.bat                  # 项目启动脚本 (Windows)
│
├── deployments/                   # 部署文件目录
│   ├── docker-compose.yml         # Docker Compose 配置
│   └── prometheus.yml             # Prometheus 配置
│
├── .gitignore                     # Git 忽略文件
├── go.mod                         # Go 模块定义
├── go.sum                         # Go 依赖校验
├── Makefile                       # Make 命令集合
├── README.md                      # 项目说明文档
├── QUICKSTART.md                  # 快速开始指南
├── DOOS_Requirements.md           # 原始需求文档
├── DOOS_Detailed_Requirements.md  # 详细需求文档
├── WEEK1_SUMMARY.md               # Week 1 完成总结
└── PROJECT_STRUCTURE.md           # 本文档
```

## 目录说明

### `/cmd` - 服务入口

存放各个微服务的 main 函数入口。每个服务一个子目录。

**设计原则**:
- 每个服务独立编译
- main.go 只负责启动，业务逻辑在 internal 中
- 便于独立部署和扩展

**当前服务**:
- `order-service`: 订单服务（端口 50051/8081）
- `inventory-service`: 库存服务（端口 50052/8082）
- `message-relay`: 消息中继服务（后台任务）
- `cdc-consumer`: CDC 消费者服务（后台任务）

### `/pkg` - 公共包

存放可以被外部项目引用的公共代码。

**设计原则**:
- 高内聚、低耦合
- 完善的单元测试
- 清晰的接口定义
- 详细的文档注释

**当前包**:
- `idgen`: Snowflake ID 生成器
  - 全局唯一 ID 生成
  - 并发安全
  - 高性能（单机 400w+/s）
  
- `sharding`: 分库中间件
  - 基于 user_id 的 Hash 分库
  - 连接池管理
  - 健康检查

**未来扩展**:
- `cache`: Redis 封装
- `mq`: Kafka 封装
- `errors`: 错误码定义
- `logger`: 日志封装
- `metrics`: 监控指标

### `/internal` - 内部业务逻辑

存放项目内部的业务逻辑代码（Week 2+ 创建）。

**规划结构**:
```
internal/
├── order/              # 订单模块
│   ├── handler/        # gRPC Handler
│   ├── service/        # 业务逻辑层
│   ├── repository/     # 数据访问层
│   └── model/          # 数据模型
├── inventory/          # 库存模块
├── message/            # 消息处理
└── cdc/                # CDC 处理
```

### `/api` - API 定义

存放 API 接口定义（Week 2+ 创建）。

**规划结构**:
```
api/
└── proto/v1/           # Protobuf 定义
    ├── order.proto     # 订单服务接口
    ├── inventory.proto # 库存服务接口
    └── common.proto    # 公共定义
```

### `/config` - 配置文件

存放不同环境的配置文件。

**配置项**:
- 服务端口配置
- 数据库连接配置
- Redis 配置
- Kafka 配置
- Etcd 配置
- 日志配置

**使用方式**:
```bash
# 开发环境
go run cmd/order-service/main.go -config config/dev.yaml

# 生产环境
go run cmd/order-service/main.go -config config/prod.yaml
```

### `/scripts` - 脚本工具

存放各种脚本工具。

**SQL 脚本** (`/scripts/sql`):
- 数据库表结构定义
- 初始化数据
- 迁移脚本

**Shell 脚本**:
- `init_db.sh/bat`: 初始化数据库
- `start.sh/bat`: 启动项目
- 未来可添加：备份、迁移、部署等脚本

### `/deployments` - 部署配置

存放部署相关的配置文件。

**当前文件**:
- `docker-compose.yml`: 本地开发环境
- `prometheus.yml`: Prometheus 监控配置

**未来扩展**:
```
deployments/
├── docker-compose.yml
├── prometheus.yml
└── k8s/                # Kubernetes 部署
    ├── order-service.yaml
    ├── inventory-service.yaml
    └── ingress.yaml
```

### `/docs` - 文档

存放项目文档（未来创建）。

**规划内容**:
- API 文档
- 架构设计文档
- 开发规范
- 运维手册
- 故障排查手册

## 文件说明

### 核心文件

| 文件 | 说明 |
|------|------|
| `go.mod` | Go 模块定义，管理依赖 |
| `go.sum` | 依赖校验文件 |
| `Makefile` | 常用命令集合 |
| `.gitignore` | Git 忽略规则 |

### 文档文件

| 文件 | 说明 |
|------|------|
| `README.md` | 项目说明，快速了解项目 |
| `QUICKSTART.md` | 快速开始指南，5 分钟上手 |
| `DOOS_Requirements.md` | 原始 PRD 文档 |
| `DOOS_Detailed_Requirements.md` | 详细需求文档 |
| `WEEK1_SUMMARY.md` | Week 1 完成总结 |
| `PROJECT_STRUCTURE.md` | 本文档，项目结构说明 |

## 代码组织原则

### 1. 标准项目布局

遵循 Go 社区的标准项目布局：
- https://github.com/golang-standards/project-layout

### 2. 分层架构

```
Handler (API 层)
    ↓
Service (业务逻辑层)
    ↓
Repository (数据访问层)
    ↓
Database (数据库)
```

### 3. 依赖方向

- `cmd` 依赖 `internal` 和 `pkg`
- `internal` 依赖 `pkg`
- `pkg` 不依赖任何内部包（可独立使用）

### 4. 命名规范

- 包名：小写，单数形式（如 `order` 而非 `orders`）
- 文件名：小写，下划线分隔（如 `order_service.go`）
- 接口名：名词或形容词（如 `OrderService`, `Readable`）
- 测试文件：`_test.go` 后缀

## 扩展计划

### Week 2 新增

```
internal/
├── order/
│   ├── handler/
│   │   └── order_handler.go
│   ├── service/
│   │   └── order_service.go
│   ├── repository/
│   │   └── order_repository.go
│   └── model/
│       └── order.go
└── inventory/
    └── ...

api/
└── proto/v1/
    ├── order.proto
    └── inventory.proto

pkg/
├── cache/
│   └── redis.go
└── mq/
    └── kafka.go
```

### Week 3 新增

```
internal/
├── message/
│   └── relay.go
└── cdc/
    └── consumer.go

pkg/
└── canal/
    └── client.go
```

### Week 4 新增

```
web/                    # 前端项目
├── src/
│   ├── pages/
│   ├── components/
│   └── api/
└── package.json
```

## 总结

当前项目结构清晰、模块化，遵循 Go 社区最佳实践。随着项目发展，会逐步添加新的模块和功能，但核心结构保持稳定。

**核心优势**:
- ✅ 清晰的目录结构
- ✅ 良好的代码组织
- ✅ 便于团队协作
- ✅ 易于扩展维护

---

**最后更新**: Week 1 完成
**下次更新**: Week 2 开始时
