# 交互式命令测试指南

## 快速测试

### 1. 本地测试（推荐）

直接运行测试脚本，查看各种输出效果：

```bash
./test_interactive.sh
```

这个脚本会模拟：
- ✅ 快速命令
- ✅ 长时间运行的编译过程
- ✅ 依赖更新（类似 composer/npm）
- ✅ 交互式输入（需要用户输入）
- ✅ 数据库迁移
- ✅ 错误输出
- ✅ 大量文件处理

### 2. 添加到配置文件测试

在你的 `.yml` 配置文件中添加测试命令：

```yaml
server_groups:
  - name: 测试环境
    servers:
      - name: 测试服务器
        host: root@your-server
        # ... 其他配置 ...
        post_sync_commands:
          # 非交互式命令
          - ls -la {target_dir}
          - pwd
          
          # 长时间运行的命令（测试滚动显示）
          - for i in {1..50}; do echo "Processing $i"; sleep 0.1; done
          
          # 交互式命令（脚本会提示是否需要交互）
          - read -p "Enter your name: " name && echo "Hello $name"
          
          # 实际的部署命令
          - composer -d {target_dir} update
          - php {target_dir}/artisan migrate --force
          - chown -R www-data:www-data {target_dir}
```

## 日志系统说明

### 新的日志格式

日志现在按日期划分，每天一个文件，多次同步会追加到同一个文件：

```
logs/
  ├── demo/
  │   └── sync_2025-12-22.log
  └── demo2/
      └── sync_2025-12-22.log
```

### 日志内容示例

```
═══════════════════════════════════════════════════════════════
              [2025-12-22 15:37:09] 启动同步
═══════════════════════════════════════════════════════════════
配置文件: demo

配置详情:
  仓库URL: https://gitee.com/...
  本地目录: /tmp/demo
  认证类型: ssh

... (同步详细日志) ...

───────────────────────────────────────────────────────────────
              [2025-12-22 15:42:15] 同步完成
───────────────────────────────────────────────────────────────


═══════════════════════════════════════════════════════════════
              [2025-12-22 16:20:33] 启动同步
═══════════════════════════════════════════════════════════════
配置文件: demo

... (第二次同步的日志) ...
```

## 命令类型说明

### 非交互式命令（自动使用滚动显示）

这些命令会在灰色滚动窗口中显示输出，完成后自动清除：

```bash
- ls -la {target_dir}
- composer update
- npm install
- php artisan migrate
- chown -R www-data:www-data {target_dir}
- systemctl restart nginx
```

### 交互式命令（需要确认）

这些命令会被自动检测，并提示是否需要交互：

```bash
- mysql -u root -p                    # 需要密码
- vim /etc/nginx/nginx.conf          # 编辑器
- apt-get install package             # 可能需要确认
- read -p "Input: " var              # 读取输入
- sudo -i                            # 切换用户
```

**脚本会显示：**
```
[→] 执行 [1]: mysql -u root -p
  ⚠ 检测到可能的交互式命令
  是否需要交互? (y/n, 默认n):
```

- 选择 `y`: 直接显示命令输出，支持用户交互
- 选择 `n`: 使用滚动显示模式（非交互）

## 实际使用建议

### 1. 常规部署命令

对于这些命令，无需交互，让它们在后台运行：

```yaml
post_sync_commands:
  - composer -d {target_dir} install --no-dev --optimize-autoloader
  - php {target_dir}/artisan config:cache
  - php {target_dir}/artisan route:cache
  - php {target_dir}/artisan view:cache
  - chown -R www-data:www-data {target_dir}
  - chmod -R 755 {target_dir}/storage
  - systemctl restart php8.1-fpm
```

### 2. 需要确认的命令

如果命令可能需要用户确认，添加 `--yes` 或 `-y` 参数：

```yaml
post_sync_commands:
  - php {target_dir}/artisan migrate --force   # Laravel 强制迁移
  - npm install --yes                          # npm 自动确认
  - apt-get install -y package                 # apt 自动确认
```

### 3. 长时间运行的命令

这些命令会显示滚动进度：

```yaml
post_sync_commands:
  - composer -d {target_dir} update -vvv       # 详细输出
  - npm run build                              # 构建前端
  - php {target_dir}/artisan queue:work --stop-when-empty
```

## 测试效果预览

### 非交互式命令效果：
```
[→] 执行 [1]: composer update
  │ Loading composer repositories...
  │ Updating dependencies
  │ Lock file operations: 5 installs
  │ Writing lock file
  │ Installing dependencies...
  │ Package operations: 5 installs
  │ Downloading packages...
  │ Generating autoload files
  │ Done!
  (灰色滚动显示，完成后消失)
  [✓] 命令 [1] 完成
```

### 交互式命令效果：
```
[→] 执行 [2]: read -p "Name: " name
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Name: John
  Hello John!
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [✓] 命令 [2] 完成
```

## 故障排除

### 问题1：命令卡住不动

**原因**：命令可能需要交互，但被识别为非交互式  
**解决**：重新运行脚本，当提示时选择 `y` 进行交互

### 问题2：输出显示不完整

**原因**：滚动窗口只显示最后10行  
**解决**：查看日志文件获取完整输出，或使用 `-v` 参数运行脚本

### 问题3：交互式命令无法输入

**原因**：SSH 连接未分配 TTY  
**解决**：脚本会自动使用 `-t` 参数，如果仍有问题，请检查 SSH 配置

## 高级用法

### 查看今天的所有同步日志

```bash
cat logs/demo/sync_$(date +%Y-%m-%d).log
```

### 实时监控同步过程

```bash
tail -f logs/demo/sync_$(date +%Y-%m-%d).log
```

### 统计今天的同步次数

```bash
grep -c "启动同步" logs/demo/sync_$(date +%Y-%m-%d).log
```

