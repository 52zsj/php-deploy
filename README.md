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

# 服务器配置组
server_groups:
  - name: "测试环境"                           # 服务器组名称
    servers:
      - name: "测试服务器"                     # 服务器名称
        host: "user@test-server.com"           # 服务器地址
        target_dir: "/path/to/target/"         # 目标目录
        branch: "develop"                      # 使用的分支
        auth_type: "password"                  # 认证类型: password 或 ssh
        auth_info: "your_password"             # 密码或SSH密钥路径
  
  - name: "生产环境"                           # 另一个服务器组
    servers:
      - name: "生产服务器1"                    # 服务器名称
        host: "user@prod-server1.com"          # 服务器地址
        target_dir: "/path/to/target/"         # 目标目录
        branch: "master"                       # 使用的分支
        auth_type: "ssh"                       # 认证类型
        auth_info: "~/.ssh/prod_key"           # SSH密钥路径
      
      - name: "生产服务器2"                    # 另一台服务器
        host: "user@prod-server2.com"          # 服务器地址
        target_dir: "/path/to/target/"         # 目标目录
        branch: "master"                       # 使用的分支
        auth_type: "ssh"                       # 认证类型
        auth_info: "~/.ssh/prod_key"           # SSH密钥路径

# 同步配置
sync:
  # 忽略的文件和目录，使用rsync格式
  exclude:
    - ".git/"
    - ".gitignore"
    - "*.log"
    - "node_modules/"
    # 添加更多需要忽略的文件或目录...
  
  # rsync选项
  rsync_options: "-avz --delete"  # 可根据需要调整
```

## 多项目和服务器分组支持

你可以为每个项目创建单独的YAML配置文件，并在每个配置文件中定义服务器分组：

1. 为每个项目创建一个配置文件，例如：
   - `项目A.yml`
   - `项目B.yml`
   - `精简范.yml`

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

直接运行脚本：

```bash
./sync.sh
```

脚本将：
1. 检查所需依赖
2. 显示可用的配置文件列表，让你选择一个配置文件
3. 解析所选配置文件
4. 显示可用的服务器组列表，让你选择一个服务器组
5. 从Gitee拉取所需的所有分支
6. 对选定服务器组中的每个服务器，使用其配置的分支进行同步

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