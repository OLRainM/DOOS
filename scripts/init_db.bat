@echo off
REM Windows 数据库初始化脚本

setlocal

set MYSQL_USER=root
set MYSQL_PASSWORD=root123
set SHARD_0_HOST=localhost
set SHARD_0_PORT=3306
set SHARD_1_HOST=localhost
set SHARD_1_PORT=3307
set INVENTORY_HOST=localhost
set INVENTORY_PORT=3308

set SCRIPT_DIR=%~dp0
set SQL_DIR=%SCRIPT_DIR%sql

echo =========================================
echo DOOS 数据库初始化脚本
echo =========================================

echo.
echo 初始化订单分库 0 (%SHARD_0_HOST%:%SHARD_0_PORT%)...
mysql -h %SHARD_0_HOST% -P %SHARD_0_PORT% -u%MYSQL_USER% -p%MYSQL_PASSWORD% -e "CREATE DATABASE IF NOT EXISTS doos_order_0 DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci; USE doos_order_0; SOURCE %SQL_DIR%/t_order.sql; SOURCE %SQL_DIR%/t_order_item.sql; SOURCE %SQL_DIR%/t_local_message.sql;"
if %errorlevel% neq 0 (
    echo 错误: 订单分库 0 初始化失败
    exit /b 1
)
echo √ 订单分库 0 初始化完成

echo.
echo 初始化订单分库 1 (%SHARD_1_HOST%:%SHARD_1_PORT%)...
mysql -h %SHARD_1_HOST% -P %SHARD_1_PORT% -u%MYSQL_USER% -p%MYSQL_PASSWORD% -e "CREATE DATABASE IF NOT EXISTS doos_order_1 DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci; USE doos_order_1; SOURCE %SQL_DIR%/t_order.sql; SOURCE %SQL_DIR%/t_order_item.sql; SOURCE %SQL_DIR%/t_local_message.sql;"
if %errorlevel% neq 0 (
    echo 错误: 订单分库 1 初始化失败
    exit /b 1
)
echo √ 订单分库 1 初始化完成

echo.
echo 初始化库存库 (%INVENTORY_HOST%:%INVENTORY_PORT%)...
mysql -h %INVENTORY_HOST% -P %INVENTORY_PORT% -u%MYSQL_USER% -p%MYSQL_PASSWORD% -e "CREATE DATABASE IF NOT EXISTS doos_inventory DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci; USE doos_inventory; SOURCE %SQL_DIR%/t_inventory.sql; SOURCE %SQL_DIR%/t_message_consume_log.sql;"
if %errorlevel% neq 0 (
    echo 错误: 库存库初始化失败
    exit /b 1
)
echo √ 库存库初始化完成

echo.
echo =========================================
echo 数据库初始化完成！
echo =========================================

endlocal
