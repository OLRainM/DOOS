.PHONY: help build test clean docker-up docker-down init-db proto

# 默认目标
help:
	@echo "DOOS - Distributed Omni-Order System"
	@echo ""
	@echo "可用命令:"
	@echo "  make build        - 编译所有服务"
	@echo "  make test         - 运行测试"
	@echo "  make test-cover   - 运行测试并生成覆盖率报告"
	@echo "  make clean        - 清理编译产物"
	@echo "  make docker-up    - 启动 Docker 环境"
	@echo "  make docker-down  - 停止 Docker 环境"
	@echo "  make init-db      - 初始化数据库"
	@echo "  make proto        - 生成 Protobuf 代码"
	@echo "  make run-order    - 运行订单服务"
	@echo "  make run-inventory - 运行库存服务"
	@echo "  make run-relay    - 运行消息中继服务"
	@echo "  make run-cdc      - 运行 CDC 消费者"
	@echo "  make lint         - 运行代码检查"
	@echo "  make fmt          - 格式化代码"

# 编译所有服务
build:
	@echo "编译订单服务..."
	@go build -o bin/order-service cmd/order-service/main.go
	@echo "编译库存服务..."
	@go build -o bin/inventory-service cmd/inventory-service/main.go
	@echo "编译消息中继服务..."
	@go build -o bin/message-relay cmd/message-relay/main.go
	@echo "编译 CDC 消费者..."
	@go build -o bin/cdc-consumer cmd/cdc-consumer/main.go
	@echo "编译完成！"

# 运行测试
test:
	@echo "运行测试..."
	@go test -v ./...

# 运行测试并生成覆盖率报告
test-cover:
	@echo "运行测试并生成覆盖率报告..."
	@go test -coverprofile=coverage.out ./...
	@go tool cover -html=coverage.out -o coverage.html
	@echo "覆盖率报告已生成: coverage.html"

# 清理编译产物
clean:
	@echo "清理编译产物..."
	@rm -rf bin/
	@rm -f coverage.out coverage.html
	@echo "清理完成！"

# 启动 Docker 环境
docker-up:
	@echo "启动 Docker 环境..."
	@cd deployments && docker-compose up -d
	@echo "等待服务启动..."
	@sleep 10
	@cd deployments && docker-compose ps
	@echo "Docker 环境已启动！"

# 停止 Docker 环境
docker-down:
	@echo "停止 Docker 环境..."
	@cd deployments && docker-compose down
	@echo "Docker 环境已停止！"

# 初始化数据库
init-db:
	@echo "初始化数据库..."
ifeq ($(OS),Windows_NT)
	@cd scripts && init_db.bat
else
	@cd scripts && chmod +x init_db.sh && ./init_db.sh
endif
	@echo "数据库初始化完成！"

# 生成 Protobuf 代码
proto:
	@echo "生成 Protobuf 代码..."
	@protoc --go_out=. --go_opt=paths=source_relative \
		--go-grpc_out=. --go-grpc_opt=paths=source_relative \
		api/proto/v1/*.proto
	@echo "Protobuf 代码生成完成！"

# 运行订单服务
run-order:
	@echo "运行订单服务..."
	@go run cmd/order-service/main.go

# 运行库存服务
run-inventory:
	@echo "运行库存服务..."
	@go run cmd/inventory-service/main.go

# 运行消息中继服务
run-relay:
	@echo "运行消息中继服务..."
	@go run cmd/message-relay/main.go

# 运行 CDC 消费者
run-cdc:
	@echo "运行 CDC 消费者..."
	@go run cmd/cdc-consumer/main.go

# 代码检查
lint:
	@echo "运行代码检查..."
	@golangci-lint run ./...

# 格式化代码
fmt:
	@echo "格式化代码..."
	@go fmt ./...
	@echo "代码格式化完成！"

# 安装依赖
deps:
	@echo "安装依赖..."
	@go mod download
	@go mod tidy
	@echo "依赖安装完成！"

# 查看 Docker 日志
logs:
	@cd deployments && docker-compose logs -f

# 重启 Docker 环境
restart: docker-down docker-up

# 完整初始化（首次运行）
init: deps docker-up
	@echo "等待数据库启动..."
	@sleep 30
	@$(MAKE) init-db
	@echo "初始化完成！可以运行 make run-order 启动服务"
