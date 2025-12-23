# DOOS 快速开始指南

本指南将帮助你在 5 分钟内启动 DOOS 项目。

## 前置要求

确保你的系统已安装：

- ✅ Go 1.25+ ([下载](https://golang.org/dl/))
- ✅ Docker Desktop ([下载](https://www.docker.com/products/docker-desktop))
- ✅ Git

## 快速启动（3 步）

### 步骤 1: 克隆项目

```bash
git clone <repository-url>
cd doos
```

### 步骤 2: 启动环境

**方式 A: 使用启动脚本（推荐）**

Linux/Mac:
```bash
cd scripts
chmod +x start.sh
./start.sh
```

Windows:
```cmd
cd scripts
start.bat
```

**方式 B: 使用 Makefile**

```bash
make init
```

这将自动完成：
- 下载 Go 依赖
- 启动 Docker 容器（MySQL, Redis, Kafka, Etcd, ES 等）
- 初始化数据库表结构

### 步骤 3: 运行服务

打开新的终端窗口，运行订单服务：

```bash
go run cmd/order-service/main.go
```

看到以下输出表示成功：
```
Order Service Starting...
Order Service is ready
```

## 验证安装

### 1. 检查 Docker 容器状态

```bash
cd deployments
docker-compose ps
```

所有服务应该显示 `Up` 状态。

### 2. 检查数据库连接

```bash
# 连接到订单分库 0
mysql -h localhost -P 3306 -uroot -proot123 -e "SHOW DATABASES;"

# 连接到订单分库 1
mysql -h localhost -P 3307 -uroot -proot123 -e "SHOW DATABASES;"

# 连接到库存库
mysql -h localhost -P 3308 -uroot -proot123 -e "SHOW DATABASES;"
```

### 3. 运行测试

```bash
go test ./...
```

应该看到所有测试通过：
```
ok      github.com/doos/order-system/pkg/idgen      0.123s
ok      github.com/doos/order-system/pkg/sharding   0.045s
```

## 服务访问地址

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

# 查看 Docker 日志
make logs

# 格式化代码
make fmt

# 清理编译产物
make clean
```

## 下一步

现在你已经成功启动了 DOOS 项目！接下来可以：

1. 📖 阅读 [详细需求文档](docs/DOOS_Detailed_Requirements.md)
2. 🔧 开始 Week 2 的开发工作（实现核心业务逻辑）
3. 🧪 编写更多测试用例
4. 📊 配置 Grafana 监控面板

## 故障排除

### 问题 1: Docker 容器启动失败

**原因**: 端口被占用

**解决方案**:
```bash
# 检查端口占用
netstat -ano | findstr "3306"  # Windows
lsof -i :3306                   # Linux/Mac

# 停止占用端口的进程或修改 docker-compose.yml 中的端口映射
```

### 问题 2: 数据库连接失败

**原因**: 容器还未完全启动

**解决方案**:
```bash
# 等待 30 秒后重试
# 或查看容器日志
docker logs doos-mysql-shard-0
```

### 问题 3: Go 依赖下载失败

**原因**: 网络问题

**解决方案**:
```bash
# 设置 Go 代理
go env -w GOPROXY=https://goproxy.cn,direct

# 重新下载依赖
go mod download
```

### 问题 4: Kafka 连接失败

**原因**: Kafka 启动较慢

**解决方案**:
```bash
# 等待 Kafka 完全启动（约 1 分钟）
docker logs doos-kafka

# 检查 Kafka 健康状态
docker exec doos-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## 获取帮助

如果遇到问题：

1. 查看 [README.md](README.md) 中的常见问题
2. 查看 Docker 容器日志: `docker logs <container-name>`
3. 提交 Issue

## Week 1 完成清单

- [x] 初始化 Go 项目结构
- [x] 编写 Docker Compose 配置
- [x] 搭建 MySQL 分库（2 节点）
- [x] 搭建 Redis, Kafka, Etcd
- [x] 实现分库中间件（基于 dbr）
- [x] 实现 Snowflake ID 生成器
- [x] 编写数据库初始化脚本
- [x] 编写项目文档

恭喜！你已经完成了 Week 1 的所有任务！🎉
