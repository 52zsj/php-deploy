# 使用指南

## 快速开始

### 1. 配置文件

复制 `demo.yml` 创建你的配置：

```bash
cp demo.yml myproject.yml
```

修改关键配置：

```yaml
gitee:
  repo_url: "你的仓库地址"
  local_dir: "/tmp/myproject"
  auth_type: "ssh"
  ssh_key: "~/.ssh/id_rsa"

sync:
  rsync_options: "-az --progress"
  exclude:
    - "runtime/"
    - "uploads/"

server_groups:
  - name: "生产环境"
    servers:
      - name: "服务器1"
        host: "user@server.com"
        target_dir: "/var/www/myproject"
        branch: "master"
        auth_type: "ssh"
        auth_info: "~/.ssh/id_rsa"
```

### 2. 运行同步

```bash
./sync.sh
```

## 核心特性

### 🎯 以 Git 为准

- **Git 管理的文件** → 同步到服务器
- **Git 删除的文件** → 服务器也删除
- **不在 Git 中的文件** → 完全不受影响

**优势：插件生成的文件自动被保护！**

### 🚀 智能比对

使用 `rsync --checksum` 比对文件内容，只上传有变化的文件。

```
待检查: 100 个文件
实际上传: 15 个文件 (85个未变化，跳过)
```

### 📝 Replace 优先级最高

环境配置文件会覆盖 Git 变更：

```
1. Git Pull: config/database.php 被修改
2. Replace: 替换 config/database.php  
3. 结果: 使用 Replace 版本 ✓
```

## 工作流程

```
Git Pull → 检测变更 → Replace 替换 → 智能比对 → 上传/删除
```

### 示例

```bash
./sync.sh

[→] 拉取代码...
  [i] 分支 master 变更统计:
    新增: 2 个文件
    修改: 3 个文件
    删除: 1 个文件

[→] 替换环境配置...
  [✓] 已替换 2 个文件

[→] 智能比对 7 个文件...
  同步统计:
    Number of files: 5
    Total transferred: 8.5K

[→] 删除服务器上的文件...
  [✗] src/OldController.php

[✓] 同步完成！
```

## 配置说明

### 必需配置

```yaml
gitee:
  repo_url: "仓库地址"
  local_dir: "本地目录"
  auth_type: "ssh 或 password"

sync:
  rsync_options: "-az --progress"

server_groups:
  - servers:
      - host: "user@server"
        target_dir: "目标目录"
```

### 可选配置

```yaml
sync:
  # 排除目录（删除时跳过）
  exclude:
    - "runtime/"
    - "uploads/"
  
  # 配置替换
  replace_dir: "~/replace/myproject"

server_groups:
  - env: "production"  # 环境标识
    post_sync_commands:  # 同步后命令
      - "chown -R www-data:www-data {target_dir}"
```

## 常见问题

**Q: 插件生成的文件会被删除吗？**  
A: 不会！只要不在 Git 中，就不受影响。

**Q: 如何保护某些目录？**  
A: 添加到 `exclude` 列表。

**Q: Replace 会被 Git 覆盖吗？**  
A: 不会！Replace 优先级最高。

## 命令选项

```bash
./sync.sh                 # 正常模式
./sync.sh -v             # 详细输出
./sync.sh -q             # 精简模式
./sync.sh --log=/path    # 指定日志文件
```

## 更多信息

- 配置示例：`demo.yml`
- 测试指南：`TEST_GUIDE.md`
- 完整文档：`README.md`

