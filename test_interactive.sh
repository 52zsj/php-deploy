#!/bin/bash

# 交互式命令测试脚本
# 用于测试 sync.sh 的交互式命令处理功能

echo "========================================="
echo "      交互式命令测试 Demo"
echo "========================================="
echo ""
echo "这个脚本模拟各种类型的命令，用于测试同步脚本的显示效果"
echo ""

# 1. 快速命令
echo "[测试1] 快速执行的命令（ls -la）..."
ls -la
echo ""
sleep 1

# 2. 模拟编译/安装过程（带进度输出）
echo "[测试2] 模拟长时间运行的命令（模拟编译）..."
for i in {1..30}; do
    echo "正在编译文件 $i/30: src/module_$i.c"
    sleep 0.2
done
echo "编译完成！"
echo ""
sleep 1

# 3. 模拟composer/npm更新（带详细输出）
echo "[测试3] 模拟依赖更新（类似 composer update）..."
echo "Loading composer repositories with package information"
sleep 0.5
echo "Updating dependencies"
sleep 0.5
echo "Lock file operations: 5 installs, 12 updates, 0 removals"
sleep 0.3
for pkg in "symfony/console" "guzzlehttp/guzzle" "monolog/monolog" "doctrine/orm" "phpunit/phpunit"; do
    echo "  - Installing $pkg (v3.2.1)"
    sleep 0.3
done
echo "Writing lock file"
sleep 0.3
echo "Installing dependencies from lock file"
sleep 0.3
echo "Package operations: 5 installs, 12 updates, 0 removals"
sleep 0.3
for i in {1..17}; do
    echo "  - Downloading package $i/17"
    sleep 0.15
done
echo "Generating optimized autoload files"
sleep 0.5
echo "Done!"
echo ""
sleep 1

# 4. 交互式命令测试（需要用户输入）
echo "[测试4] 交互式命令（需要用户输入）..."
read -p "请输入你的名字: " username
if [ -z "$username" ]; then
    username="匿名用户"
fi
echo "你好，$username！"
echo ""
sleep 1

read -p "是否继续下一步测试? (y/n): " continue_test
if [ "$continue_test" != "y" ] && [ "$continue_test" != "Y" ]; then
    echo "测试中止"
    exit 0
fi
echo ""

# 5. 模拟数据库操作
echo "[测试5] 模拟数据库操作..."
echo "Connecting to database..."
sleep 0.5
echo "Running migrations..."
for i in {1..8}; do
    echo "  Migrating: 2024_01_0${i}_create_table_$i"
    sleep 0.3
done
echo "Migration completed successfully!"
echo ""
sleep 1

# 6. 模拟错误输出
echo "[测试6] 模拟命令错误..."
echo "Starting process..."
sleep 0.5
echo "WARNING: Configuration file not found, using defaults" >&2
sleep 0.3
echo "Processing items..."
for i in {1..5}; do
    echo "  Processing item $i"
    sleep 0.2
done
echo "ERROR: Failed to connect to external service" >&2
sleep 0.3
echo "Retrying..."
sleep 0.5
echo "Connection established"
echo "Process completed with warnings"
echo ""

# 7. 模拟多行输出命令
echo "[测试7] 模拟大量输出..."
for i in {1..50}; do
    echo "处理文件: /path/to/very/long/directory/structure/file_${i}.txt"
    sleep 0.05
done
echo "批处理完成！"
echo ""

echo "========================================="
echo "所有测试完成！"
echo "========================================="
echo ""
echo "测试说明："
echo "- 测试1: 快速命令，应该瞬间完成"
echo "- 测试2-3: 长时间命令，应该看到滚动显示效果"
echo "- 测试4: 交互式命令，需要用户输入"
echo "- 测试5-6: 模拟实际部署场景"
echo "- 测试7: 大量输出，测试滚动显示"

