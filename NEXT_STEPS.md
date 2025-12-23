# 下一步操作指南

## 🎉 恭喜！Week 1 已完成

你已经成功完成了 DOOS 项目的基础设施搭建。现在需要完成以下步骤。

---

## 📋 立即需要做的事情

### 1. 配置 SSH 密钥并推送到 GitHub ⚠️

**当前状态**: 代码已提交到本地，但还未推送到 GitHub

**操作步骤**:

#### 方式 A: 使用 SSH (推荐)

1. **生成 SSH 密钥**
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```

2. **复制公钥**
   ```bash
   # Linux/Mac
   cat ~/.ssh/id_ed25519.pub
   
   # Windows PowerShell
   Get-Content ~/.ssh/id_ed25519.pub
   ```

3. **添加到 GitHub**
   - 访问 https://github.com/settings/keys
   - 点击 "New SSH key"
   - 粘贴公钥并保存

4. **测试连接**
   ```bash
   ssh -T git@github.com
   ```

5. **推送代码**
   ```bash
   git push -u origin main
   git push origin --tags
   ```

#### 方式 B: 使用 HTTPS (临时方案)

```bash
# 修改远程地址
git remote set-url origin https://github.com/OLRainM/DOOS.git

# 推送代码
git push -u origin main
git push origin --tags
```

**详细步骤**: 查看 [docs/GIT_SETUP.md](docs/GIT_SETUP.md)

---

### 2. 验证 Docker 环境 ✅

**操作步骤**:

```bash
# 启动 Docker 环境
cd deployments
docker-compose up -d

# 等待服务启动
sleep 30

# 检查服务状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

**预期结果**: 所有 10 个服务都显示 "Up" 状态

---

### 3. 初始化数据库 ✅

**操作步骤**:

```bash
cd scripts

# Linux/Mac
chmod +x init_db.sh
./init_db.sh

# Windows
init_db.bat
```

**验证**:
```bash
# 连接数据库
mysql -h localhost -P 3306 -uroot -proot123 -e "SHOW DATABASES;"
mysql -h localhost -P 3307 -uroot -proot123 -e "SHOW DATABASES;"
mysql -h localhost -P 3308 -uroot -proot123 -e "SHOW DATABASES;"

# 查看表结构
mysql -h localhost -P 3306 -uroot -proot123 doos_order_0 -e "SHOW TABLES;"
```

---

### 4. 运行测试 ✅

**操作步骤**:

```bash
# 运行所有测试
go test ./...

# 查看覆盖率
go test -cover ./pkg/...

# 生成覆盖率报告
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

**预期结果**: 所有测试通过

---

## 📚 推荐阅读

在开始 Week 2 之前，建议阅读以下文档：

1. ✅ [PROJECT_STATUS.md](PROJECT_STATUS.md) - 项目当前状态
2. ✅ [docs/DOOS_Detailed_Requirements.md](docs/DOOS_Detailed_Requirements.md) - 详细需求
3. ✅ [docs/CHECKLIST.md](docs/CHECKLIST.md) - 完成检查清单

---

## 🚀 Week 2 准备工作

### 需要安装的工具

1. **Protobuf 编译器**
   ```bash
   # Mac
   brew install protobuf
   
   # Linux
   sudo apt-get install protobuf-compiler
   
   # Windows
   # 下载: https://github.com/protocolbuffers/protobuf/releases
   ```

2. **Go Protobuf 插件**
   ```bash
   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
   ```

3. **其他依赖**
   ```bash
   # gRPC
   go get google.golang.org/grpc
   
   # Redis
   go get github.com/redis/go-redis/v9
   
   # Kafka
   go get github.com/IBM/sarama
   
   # Etcd
   go get go.etcd.io/etcd/client/v3
   ```

### 创建目录结构

```bash
# 创建 API 目录
mkdir -p api/proto/v1

# 创建 internal 目录
mkdir -p internal/order/{handler,service,repository,model}
mkdir -p internal/inventory/{handler,service,repository,model}
mkdir -p internal/message
mkdir -p internal/cdc

# 创建其他 pkg 目录
mkdir -p pkg/{cache,mq,errors,logger,metrics}
```

---

## 📝 Week 2 任务清单

### Phase 1: API 定义 (Day 1-2)

- [ ] 定义 `api/proto/v1/common.proto`
- [ ] 定义 `api/proto/v1/order.proto`
- [ ] 定义 `api/proto/v1/inventory.proto`
- [ ] 生成 Go 代码
- [ ] 编写 API 文档

### Phase 2: Order Service (Day 3-5)

- [ ] 实现 Order Handler
- [ ] 实现 Order Service
- [ ] 实现 Order Repository
- [ ] 实现本地消息表逻辑
- [ ] 编写单元测试

### Phase 3: Inventory Service (Day 6-8)

- [ ] 实现 Inventory Handler
- [ ] 实现 Inventory Service
- [ ] 实现 Inventory Repository
- [ ] 实现幂等性逻辑
- [ ] 编写单元测试

### Phase 4: Message Relay (Day 9-10)

- [ ] 实现消息扫描逻辑
- [ ] 实现 Kafka 发送
- [ ] 实现重试机制
- [ ] 编写单元测试

### Phase 5: 集成测试 (Day 11-14)

- [ ] 端到端测试
- [ ] 分布式事务测试
- [ ] 性能测试
- [ ] 文档更新

---

## 🎯 成功标准

Week 2 完成时，应该达到以下标准：

### 功能完整性
- ✅ 可以创建订单
- ✅ 可以查询订单
- ✅ 可以取消订单
- ✅ 库存可以正确扣减
- ✅ 消息可以正确投递

### 代码质量
- ✅ 测试覆盖率 > 80%
- ✅ 所有测试通过
- ✅ 代码符合规范
- ✅ 文档完整

### 性能指标
- ✅ 订单创建 QPS > 1,000
- ✅ 响应时间 P99 < 200ms
- ✅ 无内存泄漏

---

## 🔍 常见问题

### Q1: Docker 容器启动失败？

**检查**:
```bash
# 查看日志
docker logs doos-mysql-shard-0
docker logs doos-kafka

# 检查端口占用
netstat -ano | findstr "3306"  # Windows
lsof -i :3306                   # Linux/Mac
```

### Q2: 数据库连接失败？

**检查**:
- 容器是否启动成功
- 端口是否正确
- 密码是否正确 (root123)
- 等待时间是否足够 (建议 30 秒)

### Q3: Go 依赖下载失败？

**解决**:
```bash
# 设置代理
go env -w GOPROXY=https://goproxy.cn,direct

# 重新下载
go mod download
```

---

## 📞 获取帮助

如果遇到问题：

1. 查看 [docs/CHECKLIST.md](docs/CHECKLIST.md)
2. 查看 [QUICKSTART.md](QUICKSTART.md) 故障排除
3. 查看 Docker 日志
4. 提交 Issue: https://github.com/OLRainM/DOOS/issues

---

## 🎊 总结

你已经完成了：
- ✅ 项目初始化
- ✅ 核心基础组件
- ✅ Docker 环境配置
- ✅ 数据库设计
- ✅ 完整文档

现在需要：
1. ⚠️ 推送代码到 GitHub
2. ✅ 验证 Docker 环境
3. ✅ 初始化数据库
4. ✅ 运行测试
5. 🚀 准备 Week 2

**加油！你做得很棒！** 🎉

---

**创建日期**: 2025-12-24  
**状态**: Week 1 完成，准备 Week 2  
**下一里程碑**: 2025-01-07
