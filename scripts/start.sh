#!/bin/bash

# DOOS 项目启动脚本

set -e

echo "========================================="
echo "DOOS 项目启动脚本"
echo "========================================="

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo "错误: Docker 未运行，请先启动 Docker"
    exit 1
fi

# 检查 Docker Compose 是否安装
if ! command -v docker-compose &> /dev/null; then
    echo "错误: Docker Compose 未安装"
    exit 1
fi

# 启动 Docker 环境
echo ""
echo "步骤 1: 启动 Docker 环境..."
cd deployments
docker-compose up -d

# 等待服务启动
echo ""
echo "步骤 2: 等待服务启动（约 30 秒）..."
sleep 30

# 检查服务状态
echo ""
echo "步骤 3: 检查服务状态..."
docker-compose ps

# 初始化数据库
echo ""
echo "步骤 4: 初始化数据库..."
cd ../scripts
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    ./init_db.bat
else
    chmod +x init_db.sh
    ./init_db.sh
fi

echo ""
echo "========================================="
echo "环境启动完成！"
echo "========================================="
echo ""
echo "服务访问地址:"
echo "  - MySQL Shard 0:    localhost:3306"
echo "  - MySQL Shard 1:    localhost:3307"
echo "  - MySQL Inventory:  localhost:3308"
echo "  - Redis:            localhost:6379"
echo "  - Kafka:            localhost:9092"
echo "  - Etcd:             localhost:2379"
echo "  - Elasticsearch:    http://localhost:9200"
echo "  - Kibana:           http://localhost:5601"
echo "  - Prometheus:       http://localhost:9090"
echo "  - Grafana:          http://localhost:3000 (admin/admin)"
echo ""
echo "下一步:"
echo "  1. 运行订单服务:   go run cmd/order-service/main.go"
echo "  2. 运行库存服务:   go run cmd/inventory-service/main.go"
echo "  3. 运行测试:       go test ./..."
echo ""
