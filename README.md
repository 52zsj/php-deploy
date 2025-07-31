# Gitee代码同步工具

这是一个自动从Gitee拉取代码并同步到多个服务器的工具。它使用rsync进行高效传输，支持文件去重和忽略特定文件。

## 特性

- 从Gitee仓库拉取指定分支的代码
- 支持同步到多个服务器
- 支持服务器分组（如测试环境、生产环境）
- 支持每个服务器独立配置分支
- 使用rsync高效传输，自动去重和压缩
- 支持文件和目录忽略
- 支持多个项目配置文件（YAML格式）
- 支持SSH密钥认证和密码认证
- 每个配置文件使用独立的凭据存储
- **支持多层级同步后命令执行（权限设置等）**
- **支持变量替换和自定义命令**
- **智能输出模式：精简模式和详细模式**
- **动态进度提示：实时显示操作进度，避免卡顿感**
- **安全设计：防止命令注入和密码泄露**
- 彩色输出，便于查看执行状态

## 依赖

- Git - 用于拉取代码
- rsync - 用于同步文件
- YAML解析工具（以下二选一）：
  - yq（推荐）- 用于解析YAML配置文件
  - Python3 + PyYAML - 作为yq的替代方案
- sshpass（可选）- 用于密码认证方式的SSH连接

## 安装指南

### 在 macOS 上安装

1. 安装 Homebrew（如果尚未安装）:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. 安装依赖:

```bash
# 安装Git (macOS通常已预装)
brew install git

# 安装rsync (macOS通常已预装，但可能需要更新)
brew install rsync

# 安装yq (推荐) - YAML解析工具
brew install yq

# 或者使用Python3 + PyYAML (替代方案)
# brew install python3
# pip3 install pyyaml

# 安装sshpass (可选，用于密码认证)
brew install hudochenkov/sshpass/sshpass
```

3. 设置可执行权限:

```bash
chmod +x sync.sh
```

### 在 Windows 上安装

1. 安装 Git for Windows:
   - 下载并安装 [Git for Windows](https://gitforwindows.org/)
   - 安装时选择"Git Bash"，它提供了类Unix的命令行环境

2. 安装 rsync:
   - 方法1: 通过 [Cygwin](https://www.cygwin.com/) 安装 rsync
   - 方法2: 在Git Bash中使用 [Chocolatey](https://chocolatey.org/) 安装

```bash
# 安装Chocolatey (以管理员身份运行PowerShell)
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 使用Chocolatey安装rsync
choco install rsync
```

3. 安装 YAML 解析工具:
   - 方法1: 在[此处](https://github.com/mikefarah/yq/releases)下载yq并添加到PATH
   - 方法2: 安装Python3和PyYAML
   ```bash
   choco install python3
   pip3 install pyyaml
   ```

4. 安装 sshpass (可选，用于密码认证):
   - Windows下可以通过Cygwin安装，或使用WSL(Windows Subsystem for Linux)

5. 运行脚本:
   - 在Git Bash中运行脚本

```bash
chmod +x sync.sh
./sync.sh
```

## 配置

创建YAML配置文件（例如 `项目名称.yml`）:

```yaml
# Gitee仓库配置
gitee:
  repo_url: "git@gitee.com:username/repo.git"  # Gitee仓库SSH URL
  default_branch: "master"                     # 默认分支
  local_dir: "./repo_local"                    # 本地存储仓库的目录
  auth_type: "ssh"                             # 认证类型: ssh 或 password
  ssh_key: "~/.ssh/id_rsa"                     # 如果使用SSH认证
  # 如果使用密码认证，则设置以下字段
  # username: "your_username"
  # password: "your_password"

# 同步配置
sync:
  # 忽略的文件和目录，使用rsync格式
  exclude:
    - ".git/"
    - ".gitignore"
    - "*.log"
    - "node_modules/"
    - "vendor/"  # PHP Composer依赖

    # 🔒 保护运行时目录和文件（重要！）
    - "runtime/"
    - "logs/"
    - "log/"
    - "uploads/"
    - "upload/"
    - "storage/"
    - "cache/"
    - "temp/"
    - "tmp/"
    - "data/"
    - "backup/"
    - "backups/"

    # 🔒 保护进程和锁文件
    - "*.pid"
    - "*.lock"
    - "*.tmp"

    # 🔒 保护配置文件（根据需要调整）
    - ".env"
    - ".env.local"
    - "config/database.php"
    - "config/app.php"

    # 🔒 保护SSL证书
    - "*.key"
    - "*.crt"
    - "*.pem"

    # 框架特定排除规则
    # Laravel
    - "storage/app/"
    - "storage/logs/"
    - "bootstrap/cache/"

    # ThinkPHP
    - "runtime/"
    - "public/uploads/"

    # WordPress
    - "wp-content/uploads/"
    - "wp-config.php"

  # rsync选项
  rsync_options: "-az --delete --info=progress2"  # 可根据需要调整

  # 配置替换目录
  replace_dir: "~/replace/demo"   # 基础替换目录

# 全局默认的同步后执行命令（优先级最低）
default_post_sync_commands:
  - "chown -R www-data:www-data {target_dir}"
  - "find {target_dir} -type d -exec chmod 755 {} \\;"
  - "find {target_dir} -type f -exec chmod 644 {} \\;"

# 服务器配置组
server_groups:
  - name: "测试环境"                           # 服务器组名称
    env: "develop"                             # 环境标识，用于选择配置替换目录
    # 服务器组级别的同步后执行命令（覆盖全局默认，优先级中等）
    post_sync_commands:
      - "chown -R nginx:nginx {target_dir}"
      - "find {target_dir} -type d -exec chmod 755 {} \\;"
      - "find {target_dir} -type f -exec chmod 644 {} \\;"
      - "systemctl reload nginx"
    servers:
      - name: "测试服务器"                     # 服务器名称
        host: "user@test-server.com"           # 服务器地址
        target_dir: "/path/to/target/"         # 目标目录
        branch: "develop"                      # 使用的分支
        auth_type: "password"                  # 认证类型: password 或 ssh
        auth_info: "your_password"             # 密码或SSH密钥路径
        # 服务器级别的同步后执行命令（优先级最高，覆盖服务器组和全局设置）
        post_sync_commands:
          - "chown -R apache:apache {target_dir}"
          - "chmod -R 755 {target_dir}"
          - "systemctl restart httpd"

  - name: "生产环境"                           # 另一个服务器组
    env: "product"                             # 环境标识，用于选择配置替换目录
    # 生产环境使用全局默认权限设置
    servers:
      - name: "生产服务器1"                    # 服务器名称
        host: "user@prod-server1.com"          # 服务器地址
        target_dir: "/path/to/target/"         # 目标目录
        branch: "master"                       # 使用的分支
        auth_type: "ssh"                       # 认证类型
        auth_info: "~/.ssh/prod_key"           # SSH密钥路径
        # 使用全局默认权限设置

      - name: "生产服务器2"                    # 另一台服务器
        host: "user@prod-server2.com"          # 服务器地址
        target_dir: "/path/to/target/"         # 目标目录
        branch: "master"                       # 使用的分支
        auth_type: "ssh"                       # 认证类型
        auth_info: "~/.ssh/prod_key"           # SSH密钥路径
        # 服务器级别自定义权限
        post_sync_commands:
          - "chown -R www:www {target_dir}"
          - "find {target_dir} -name '*.php' -exec chmod 644 {} \\;"

## 多项目和服务器分组支持

你可以为每个项目创建单独的YAML配置文件，并在每个配置文件中定义服务器分组：

1. 为每个项目创建一个配置文件，例如：
   - `项目A.yml`
   - `项目B.yml`

2. 在每个配置文件中，定义服务器分组，例如：
   - 测试环境（使用develop分支）
   - 预发布环境（使用staging分支）
   - 生产环境（使用master分支）

3. 运行脚本时，会自动检测所有`.yml`文件，并让你选择：
   - 先选择要使用的配置文件
   - 然后选择要部署的服务器组

4. 每个配置文件会使用独立的Git凭据存储：
   - 凭据文件存储在`.credentials`目录下
   - 文件名格式为`配置文件名.git-credentials`
   - 这确保了不同项目之间的凭据不会相互覆盖

## 使用方法

### 基本用法

```bash
# 默认精简输出（推荐）
./sync.sh

# 详细输出模式（显示所有Git和rsync详细信息）
./sync.sh --verbose
./sync.sh -v

# 查看帮助信息
./sync.sh --help
./sync.sh -h
```

### 输出模式说明

**精简输出模式（默认）：**
- Git操作：显示动态进度提示（如"正在拉取分支 develop 的最新代码..."）
- 配置替换：显示动态进度和替换文件总数
- rsync同步：显示动态进度和传输统计信息
- 动态点点点效果：让用户知道程序正在工作，没有卡住
- 适合日常使用，输出简洁清晰，减少99%的输出内容

**详细输出模式（--verbose）：**
- Git操作：显示完整的pull输出和所有文件变更
- 配置替换：显示每个被替换的文件路径
- rsync同步：显示所有被处理的文件列表
- 适合调试和详细了解同步过程

**动态进度提示特性：**
- 实时显示当前操作：`正在克隆代码...` → `正在克隆代码完成`
- 动态点点点效果：每0.5秒循环显示 `   ` → `.  ` → `.. ` → `...`
- 避免长时间无反馈导致的"卡住"感觉
- 每个操作完成后都有明确的完成提示

脚本将：
1. 检查所需依赖
2. 显示可用的配置文件列表，让你选择一个配置文件
3. 解析所选配置文件
4. 显示可用的服务器组列表，让你选择一个服务器组
5. 从Gitee拉取所需的所有分支
6. 对选定服务器组中的每个服务器，使用其配置的分支进行同步

## 🔒 安全注意事项

### 重要安全警告

⚠️ **在生产环境使用前，请务必阅读以下安全注意事项**

### 配置文件安全

1. **文件权限设置**：
   ```bash
   # 设置配置文件权限，防止其他用户读取
   chmod 600 *.yml

   # 设置脚本权限
   chmod 700 sync.sh
   ```

2. **敏感信息保护**：
   - 配置文件包含服务器密码和SSH密钥路径
   - 不要将配置文件提交到版本控制系统
   - 建议使用SSH密钥认证替代密码认证

3. **路径验证**：
   - 脚本会自动验证目标路径，防止操作系统关键目录
   - 不允许使用相对路径（如 `../`）
   - 禁止操作 `/bin`, `/sbin`, `/usr`, `/etc` 等系统目录

### 密码安全

1. **密码处理**：
   - 脚本使用临时文件存储密码，避免在进程列表中暴露
   - 临时文件设置为600权限，只有当前用户可读
   - 执行完成后自动清理所有临时文件

2. **SSH密钥安全**：
   - 推荐使用SSH密钥认证替代密码
   - SSH私钥文件应设置为600权限
   - 定期轮换SSH密钥

### 命令执行安全

1. **命令验证**：
   - 同步后命令会在执行前显示给用户确认
   - 支持逐个确认执行，避免批量执行危险命令
   - 禁止执行包含特殊字符的命令

2. **权限控制**：
   - 确保SSH用户只有必要的权限
   - 避免使用root用户进行同步
   - 建议为同步操作创建专用用户

### 生产环境部署建议

1. **部署前检查清单**：
   ```bash
   # 1. 检查配置文件权限
   ls -la *.yml

   # 2. 验证排除规则
   ./sync.sh --verbose  # 先用详细模式检查

   # 3. 测试环境验证
   # 先在测试环境完整测试一遍

   # 4. 备份重要数据
   # 备份目标服务器的重要文件
   ```

2. **分阶段部署**：
   - **第一阶段**：只同步代码，不执行同步后命令
   - **第二阶段**：验证文件同步正确后，再执行权限设置命令
   - **第三阶段**：重启服务和清理缓存

3. **监控和回滚**：
   - 部署后立即检查网站/应用是否正常
   - 准备快速回滚方案
   - 监控错误日志和性能指标

4. **团队协作**：
   - 建立部署权限管理制度
   - 记录每次部署的变更内容
   - 建立部署失败的应急响应流程

## 分支管理

每个服务器可以配置使用不同的分支：

1. 在配置文件中设置`default_branch`作为默认分支
2. 在每个服务器配置中可以通过`branch`字段指定使用的分支
3. 如果服务器没有指定分支，则使用默认分支
4. 脚本会自动拉取所需的所有分支

这样可以实现：
- 测试服务器使用develop分支
- 预发布服务器使用staging分支
- 生产服务器使用master分支

## 认证方式说明

### Gitee仓库认证

1. **SSH密钥认证** (推荐):
   - 设置 `auth_type: "ssh"`
   - 设置 `ssh_key` 为你的SSH私钥路径
   - 确保已将公钥添加到Gitee账户

2. **密码认证**:
   - 设置 `auth_type: "password"`
   - 设置 `username` 和 `password`
   - 适用于HTTPS仓库URL

### 服务器认证

1. **密码认证** (默认):
   - 配置: `auth_type: "password"` 和 `auth_info: "your_password"`
   - 需要安装sshpass工具

2. **SSH密钥认证**:
   - 配置: `auth_type: "ssh"` 和 `auth_info: "~/.ssh/id_rsa"`
   - 确保已将公钥添加到目标服务器的authorized_keys

## 定时运行

### 在 macOS/Linux 上设置定时任务

```bash
# 编辑crontab
crontab -e

# 添加如下内容，每天凌晨2点同步
0 2 * * * /path/to/sync.sh
```

### 在 Windows 上设置计划任务

1. 打开"任务计划程序"
2. 创建基本任务
3. 设置触发器（如每天特定时间）
4. 设置操作：启动程序
   - 程序: C:\Program Files\Git\bin\bash.exe
   - 参数: -c "/path/to/sync.sh"

## 故障排除

1. 如果遇到SSH连接问题，请确保：
   - SSH密钥已添加到目标服务器的`authorized_keys`文件中
   - SSH密钥路径在配置文件中正确设置
   - 目标服务器可以通过网络访问

2. 如果遇到权限问题，请确保：
   - 目标目录的写入权限正确
   - SSH用户有足够的权限

3. 如果使用密码认证遇到问题：
   - 确保已安装sshpass
   - 密码中不含有特殊字符；如有特殊字符，需要适当转义
   
4. 如果脚本无法解析配置文件：
   - 确保已安装yq或Python3+PyYAML
   - 检查配置文件的YAML格式是否正确

5. 如果遇到Git凭据问题：
   - 检查`.credentials`目录下是否存在对应配置文件的凭据文件
   - 确保凭据文件中的用户名和密码正确
   - 如需重置凭据，可以删除对应的凭据文件 

## 环境配置替换

该工具支持根据不同环境自动替换配置文件：

1. 在配置文件中设置基础替换目录：
   ```yaml
   sync:
     replace_dir: "~/replace/demo"  # 基础替换目录
   ```

2. 为每个服务器组设置环境标识：
   ```yaml
   server_groups:
     - name: "测试环境"
       env: "develop"  # 环境标识
       # ...
     
     - name: "生产环境"
       env: "product"  # 环境标识
       # ...
   ```

3. 创建对应的环境配置目录结构：
   ```
   ~/replace/demo/
   ├── develop/        # 测试环境配置
   │   ├── config/
   │   │   └── app.php
   │   └── .env
   │
   └── product/        # 生产环境配置
       ├── config/
       │   └── app.php
       └── .env
   ```

4. 工作原理：
   - 脚本会根据选择的服务器组确定环境标识（如 `develop` 或 `product`）
   - 然后查找对应环境目录下的所有文件（如 `~/replace/demo/develop/` 或 `~/replace/demo/product/`）
   - 将这些文件复制到对应的Git仓库目录中，保持相同的目录结构
   - 例如，`~/replace/demo/develop/config/app.php` 会替换 `本地仓库目录/config/app.php`

5. 注意事项：
   - 替换目录中的文件结构应与Git仓库中的结构保持一致
   - 只有替换目录中存在的文件会被替换，其他文件保持不变
   - 如果替换目录不存在或环境标识未设置，则跳过替换步骤

这种方式允许您为不同环境（如测试环境、预发布环境、生产环境）维护不同的配置文件，而无需将这些配置文件提交到Git仓库中。

## 同步后命令执行（权限设置等）

该工具支持在文件同步完成后自动执行命令，常用于设置文件权限、重启服务等操作。

### 多层级优先级配置

支持三个层级的命令配置，优先级从高到低：

1. **服务器级别** - 在具体服务器配置中的 `post_sync_commands`
2. **服务器组级别** - 在服务器组配置中的 `post_sync_commands`
3. **全局默认级别** - 在根配置中的 `default_post_sync_commands`

### 配置示例

```yaml
# 全局默认的同步后执行命令（优先级最低）
default_post_sync_commands:
  - "chown -R www-data:www-data {target_dir}"
  - "find {target_dir} -type d -exec chmod 755 {} \\;"
  - "find {target_dir} -type f -exec chmod 644 {} \\;"

server_groups:
  - name: "测试环境"
    # 服务器组级别的同步后执行命令（覆盖全局默认，优先级中等）
    post_sync_commands:
      - "chown -R nginx:nginx {target_dir}"
      - "find {target_dir} -type d -exec chmod 755 {} \\;"
      - "find {target_dir} -type f -exec chmod 644 {} \\;"
      - "systemctl reload nginx"
    servers:
      - name: "测试服务器1"
        host: "root@test-server.com"
        target_dir: "/www/myapp"
        # 服务器级别的同步后执行命令（优先级最高）
        post_sync_commands:
          - "chown -R apache:apache {target_dir}"
          - "chmod -R 755 {target_dir}"
          - "systemctl restart httpd"

      - name: "测试服务器2"
        host: "root@test-server2.com"
        target_dir: "/www/myapp"
        # 不配置，使用服务器组的命令
```

### 支持的变量

在命令中可以使用以下变量，脚本会自动替换：

- `{target_dir}` - 目标目录路径（如 `/www/myapp`）
- `{server_name}` - 服务器名称（如 `测试服务器1`）
- `{branch}` - 使用的分支名称（如 `develop`）

### 常用命令示例

#### 权限设置命令
```yaml
post_sync_commands:
  # 设置文件所有者
  - "chown -R nginx:nginx {target_dir}"
  - "chown -R www-data:www-data {target_dir}"
  - "chown -R apache:apache {target_dir}"

  # 设置目录权限
  - "find {target_dir} -type d -exec chmod 755 {} \\;"
  - "find {target_dir} -type d -exec chmod 750 {} \\;"

  # 设置文件权限
  - "find {target_dir} -type f -exec chmod 644 {} \\;"
  - "find {target_dir} -name '*.php' -exec chmod 644 {} \\;"
  - "find {target_dir} -name '*.sh' -exec chmod 755 {} \\;"

  # 设置特定目录权限
  - "chmod -R 777 {target_dir}/storage"
  - "chmod -R 755 {target_dir}/public"
```

#### 服务重启命令
```yaml
post_sync_commands:
  # Web服务器
  - "systemctl reload nginx"
  - "systemctl restart nginx"
  - "systemctl restart apache2"
  - "systemctl restart httpd"

  # PHP服务
  - "systemctl restart php-fpm"
  - "systemctl restart php7.4-fpm"

  # 应用服务
  - "supervisorctl restart myapp"
  - "pm2 restart myapp"
```

#### 缓存清理命令
```yaml
post_sync_commands:
  # Laravel框架
  - "cd {target_dir} && php artisan cache:clear"
  - "cd {target_dir} && php artisan config:clear"
  - "cd {target_dir} && php artisan view:clear"

  # 清理临时文件
  - "rm -rf {target_dir}/temp/*"
  - "rm -rf {target_dir}/cache/*"
```

#### 复合操作示例
```yaml
post_sync_commands:
  # 1. 设置基本权限
  - "chown -R nginx:nginx {target_dir}"
  - "find {target_dir} -type d -exec chmod 755 {} \\;"
  - "find {target_dir} -type f -exec chmod 644 {} \\;"

  # 2. 设置特殊目录权限
  - "chmod -R 777 {target_dir}/storage"
  - "chmod -R 777 {target_dir}/bootstrap/cache"

  # 3. 清理缓存
  - "cd {target_dir} && php artisan cache:clear"

  # 4. 重启服务
  - "systemctl reload nginx"
  - "systemctl restart php-fpm"
```

### 安全注意事项

1. **命令验证**: 脚本会在执行前显示要执行的命令，并要求用户确认
2. **错误处理**: 如果某个命令执行失败，会询问是否继续执行后续命令
3. **权限要求**: 确保SSH用户有足够的权限执行这些命令
4. **命令安全**: 避免使用危险命令，建议只使用文件权限、服务管理等安全操作

### 执行流程

1. 文件同步完成后，脚本会检查是否配置了同步后命令
2. 按优先级选择要执行的命令列表（服务器级别 > 服务器组级别 > 全局默认）
3. **显示所有待执行命令**：清晰列出每个命令，让用户了解将要执行的操作
4. **选择执行方式**：
   - `[1] 执行所有命令`：批量执行所有命令
   - `[2] 逐个确认执行`：对每个命令单独确认，可以跳过或退出
   - `[3] 跳过所有命令`：不执行任何命令
5. **逐个执行命令**：替换其中的变量（如 `{target_dir}`, `{server_name}`）
6. **记录执行结果**：显示每个命令的执行状态
7. **错误处理**：如果某个命令失败，询问是否继续执行后续命令

### 交互示例

```
========== 待执行的同步后命令 ==========
[1] chown -R nginx:nginx /www/myproject
[2] find /www/myproject -type d -exec chmod 755 {} \;
[3] systemctl reload nginx
=========================================

请选择执行方式：
  [1] 执行所有命令
  [2] 逐个确认执行
  [3] 跳过所有命令
请输入选择 (1/2/3): 2

准备执行命令 [1]: chown -R nginx:nginx /www/myproject
是否执行此命令? (y/n/q): y
执行命令 [1]: chown -R nginx:nginx /www/myproject
命令 [1] 执行成功

准备执行命令 [2]: find /www/myproject -type d -exec chmod 755 {} \;
是否执行此命令? (y/n/q): n
跳过此命令
```

## rsync 选项说明

该工具使用rsync进行高效的文件同步，支持增量传输和文件去重。

### 推荐的rsync选项

```yaml
sync:
  rsync_options: "-az --delete --progress"
```

### 选项详解

- **`-a` (archive)**: 归档模式，等同于 `-rlptgoD`
  - `-r`: 递归处理目录
  - `-l`: 保持符号链接
  - `-p`: 保持文件权限
  - `-t`: 保持文件时间戳
  - `-g`: 保持文件组
  - `-o`: 保持文件所有者
  - `-D`: 保持设备文件和特殊文件

- **`-z`**: 压缩传输数据，减少网络带宽使用

- **`--delete`**: 删除目标目录中源目录没有的文件，保持目录同步
  - ⚠️ **重要**：会删除目标服务器上源目录没有的文件
  - 必须配置 `exclude` 排除运行时目录，避免误删重要数据

- **`--progress`**: 显示传输进度信息

### 其他常用选项

```yaml
# 详细输出（显示所有文件）
rsync_options: "-azv --delete"

# 显示进度信息（推荐）
rsync_options: "-az --delete --progress"

# 新版本rsync的进度显示（需要rsync 3.1.0+）
rsync_options: "-az --delete --info=progress2"

# 只显示统计信息
rsync_options: "-az --delete --stats"

# 模拟运行（不实际传输）
rsync_options: "-azv --delete --dry-run"

# 限制带宽（KB/s）
rsync_options: "-az --delete --bwlimit=1000"

# 保持部分传输的文件
rsync_options: "-az --delete --partial"
```

### 性能优化

- **增量传输**: rsync只传输文件的变化部分，大大减少传输时间
- **压缩传输**: `-z` 选项在网络传输时压缩数据
- **时间戳检查**: 通过比较文件大小和修改时间快速识别变化
- **校验和验证**: 确保传输的文件完整性

### 注意事项

1. **首次同步**: 第一次同步会传输所有文件
2. **时间戳**: 如果本地文件时间戳发生变化，rsync会重新传输
3. **权限**: 确保目标服务器有足够的权限创建和修改文件
4. **网络**: 在网络不稳定的环境下，建议添加 `--partial` 选项
5. **版本兼容性**:
   - macOS自带的rsync版本较老，不支持 `--info=progress2`，建议使用 `--progress`
   - 如需使用新特性，可通过 `brew install rsync` 安装新版本

### 🚨 重要安全提醒

**关于 `--delete` 选项的风险：**

⚠️ **`--delete` 选项会永久删除目标服务器上源目录中不存在的文件和目录！**

**高风险目录（必须排除）：**

- **运行时目录**：`runtime/`, `logs/`, `cache/`, `temp/` 等
- **上传目录**：`uploads/`, `storage/` 等用户上传的文件
- **数据目录**：`data/`, `backup/` 等重要数据
- **进程文件**：`*.pid`, `*.lock` 等运行时文件
- **配置文件**：数据库配置、环境变量文件等
- **SSL证书**：`*.crt`, `*.key`, `*.pem` 等证书文件

**真实案例风险：**
- 误删用户上传的图片、文档等重要文件
- 清空数据库备份目录
- 删除SSL证书导致网站无法访问
- 清除日志文件影响问题排查

**必须配置排除规则：**

```yaml
sync:
  exclude:
    # 保护运行时目录（必须配置！）
    - "runtime/"
    - "logs/"
    - "uploads/"
    - "storage/"
    - "cache/"
    - "temp/"
    - "data/"
    - "*.pid"
    - "*.lock"
```

**建议的安全做法：**

1. **首次部署前**：仔细检查 `exclude` 配置
2. **测试环境验证**：先在测试环境验证排除规则
3. **备份重要数据**：定期备份目标服务器的重要数据
4. **监控同步结果**：检查同步日志，确认没有误删文件

## 📄 许可证

本项目使用 [MIT License](LICENSE) 许可证。

### ✅ 你可以做什么

- **商业使用**: 在商业项目中使用、销售此软件
- **修改**: 修改源代码以满足你的需求
- **分发**: 分发原始版本或修改版本
- **私有使用**: 在私有项目中使用
- **子许可**: 在你的项目中重新许可

### 📋 你需要做什么

- **保留版权声明**: 在所有副本中包含原始的版权声明
- **保留许可证**: 在所有副本中包含MIT许可证文本

### 🛡️ 作者的权益保护

- **版权归属**: 原始代码的版权始终属于作者
- **免责声明**: 作者不承担软件使用产生的任何责任
- **署名要求**: 使用者必须保留作者的版权声明

### 💡 为什么选择MIT License

- **简单明了**: 最简洁易懂的开源许可证
- **广泛接受**: 被jQuery、Rails、Node.js等知名项目使用
- **商业友好**: 企业和个人都可以放心使用
- **最小限制**: 只需要保留版权声明即可

## 👨‍💻 作者

**zsj-950127**
- 项目创建者和主要维护者
- Copyright © 2025 zsj-950127

## 🤝 贡献

欢迎贡献代码！请阅读 [贡献指南](CONTRIBUTING.md) 了解如何参与项目开发。

所有贡献者的代码将在MIT License下发布。

## 🌟 致谢

感谢以下开源项目：
- [yq](https://github.com/mikefarah/yq) - YAML处理工具
- [rsync](https://rsync.samba.org/) - 文件同步工具
- [sshpass](https://sourceforge.net/projects/sshpass/) - SSH密码认证工具

## 📞 支持

如果你在使用过程中遇到问题：

1. 查看 [故障排除](#故障排除) 章节
2. 检查 [安全注意事项](#-安全注意事项)
3. 提交 [Issue](https://gitee.com/json_decode/php-deploy/issues)

---
