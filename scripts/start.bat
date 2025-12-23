@echo off
REM DOOS 项目启动脚本

setlocal

echo =========================================
echo DOOS 项目启动脚本
echo =========================================

REM 检查 Docker 是否运行
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo 错误: Docker 未运行，请先启动 Docker
    exit /b 1
)

REM 启动 Docker 环境
echo.
echo 步骤 1: 启动 Docker 环境...
cd ..\deployments
docker-compose up -d

REM 等待服务启动
echo.
echo 步骤 2: 等待服务启动（约 30 秒）...
timeout /t 30 /nobreak >nul

REM 检查服务状态
echo.
echo 步骤 3: 检查服务状态...
docker-compose ps

REM 初始化数据库
echo.
echo 步骤 4: 初始化数据库...
cd ..\scripts
call init_db.bat

echo.
echo =========================================
echo 环境启动完成！
echo =========================================
echo.
echo 服务访问地址:
echo   - MySQL Shard 0:    localhost:3306
echo   - MySQL Shard 1:    localhost:3307
echo   - MySQL Inventory:  localhost:3308
echo   - Redis:            localhost:6379
echo   - Kafka:            localhost:9092
echo   - Etcd:             localhost:2379
echo   - Elasticsearch:    http://localhost:9200
echo   - Kibana:           http://localhost:5601
echo   - Prometheus:       http://localhost:9090
echo   - Grafana:          http://localhost:3000 (admin/admin)
echo.
echo 下一步:
echo   1. 运行订单服务:   go run cmd/order-service/main.go
echo   2. 运行库存服务:   go run cmd/inventory-service/main.go
echo   3. 运行测试:       go test ./...
echo.

endlocal
