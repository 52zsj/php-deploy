# GitShip

从 Git 仓库拉取代码，按环境替换配置，再 rsync 同步到多台服务器。支持 Gitee / GitHub / GitLab 等任意 Git 远端。

**流水线：** 选配置 → Git 拉取 → Replace 覆盖 → 智能 rsync → 同步后命令

---

## 特性

- **以 Git 为真相源** — 只操作 Git 跟踪的文件；Git 删除的会同步删除；未入库文件（如插件生成物）不受影响
- **智能比对** — `rsync --checksum`，仅上传内容有变的文件
- **Replace 优先** — `replace/<项目>/<env>/` 覆盖本地检出，优先级高于 Git
- **多机多组** — 服务器组、按机分支、SSH 密钥或密码认证
- **同步后命令** — 全局 / 组 / 单机三级 `post_sync`，支持 `chown`、重启服务等
- **Web 配置界面** — 表单编辑 YAML、上传 Replace、流式执行日志
- **Docker 友好** — 镜像只含框架，`data/` 外挂配置与密钥

---

## 环境要求

| 依赖 | 用途 | 必需 |
|------|------|------|
| bash | 主脚本 | ✓ |
| git | 拉取代码 | ✓ |
| rsync | 同步文件 | ✓ |
| openssh | SSH 连接 | ✓ |
| yq **或** python3+PyYAML | 解析配置 | ✓ 二选一 |
| python3 | Web UI | UI 需要 |
| sshpass | 密码认证 SSH | 可选 |

**macOS 安装依赖：**

```bash
brew install git rsync yq
# 密码认证时：brew install hudochenkov/sshpass/sshpass
# UI 若无 yq：pip3 install pyyaml
```

---

## 安装与运行

### 方式一：源码 / 开发（推荐上手）

```bash
git clone <本仓库>
cd php-deploy
chmod +x sync.sh script/start-ui.sh

# Web 界面（http://127.0.0.1:8765）
./script/start-ui.sh

# 或命令行交互
./sync.sh
```

### 方式二：Docker（推荐部署）

```bash
mkdir -p data/{configs,secrets,credentials,replace,logs,ssh}
docker compose build
docker compose up -d
# 浏览器打开 http://127.0.0.1:8765
```

宿主机目录与容器映射：

| 宿主机 | 说明 |
|--------|------|
| `data/configs/*.yml` | 项目配置 |
| `data/secrets/<名>.env` | 密码等密钥 |
| `data/ssh/` | SSH 私钥（只读挂载） |
| `data/replace/` | 环境替换文件 |
| `data/logs/` | 同步日志 |

无配置文件时，容器会自动从 `demo.yml` 种子一份到 `data/configs/`。

**命令行同步（CI / 一次性）：**

```bash
docker compose run --rm sync sync -y --config=demo.yml --group=1 --post-sync=1
docker compose exec ui version
```

### 方式三：打包分发

```bash
./pack.sh              # 默认 macOS + Windows
./pack.sh all          # linux + macos + windows + docker 离线包
./pack.sh docker       # 仅 Docker 镜像 tar
./pack.sh -h           # 查看全部目标
```

产物在 `dist/`，推荐单文件启动器：

| 文件 | 平台 |
|------|------|
| `gitship-<ver>-macos-arm64` | Apple Silicon |
| `gitship-<ver>-linux-amd64` | Linux |
| `gitship.exe` | Windows |

首次运行自动解压到系统配置目录（macOS：`~/Library/Application Support/gitship`）；便携模式：同目录下 `gitship-home/`（`GITSHIP_PORTABLE=1`）。

---

## 快速使用

### 1. 创建配置

复制模板（路径二选一，取决于运行方式）：

```bash
# 源码 / CLI
cp yml/demo.yml yml/myproject.yml

# Docker
cp yml/demo.yml data/configs/myproject.yml
```

编辑仓库地址、本地检出目录、服务器与认证信息。密码不要写进 yml，使用：

```yaml
password: "secret:GITEE_PASSWORD"
```

对应密钥文件：`.secrets/myproject.env` 或 `data/secrets/myproject.env`：

```env
GITEE_PASSWORD=你的密码
```

### 2. Web 界面同步

1. `./script/start-ui.sh` 或 Docker `compose up`
2. 填写 / 加载配置，选择部署组
3. 点击「执行同步」，右侧查看实时日志

### 3. 命令行同步

```bash
# 交互选择配置与服务器组
./sync.sh

# 非交互（适合脚本 / CI）
./sync.sh -y --config=myproject.yml --group=1

# 常用参数
./sync.sh -v              # 详细输出
./sync.sh -f              # 强制全量同步 Git 文件
./sync.sh -q              # 安静模式（详情写日志）
./sync.sh --post-sync=3   # 跳过同步后命令
```

---

## 目录结构

```
sync.sh                 # 主入口（CLI）
pack.sh                 # 打包快捷入口 → script/pack.sh
docker-compose.yml
yml/demo.yml            # 配置模板（唯一入库的 yml）
replace/<项目>/<env>/   # 环境替换文件
.secrets/<配置名>.env   # 密钥（gitignore）
.credentials/           # Git 凭据缓存（gitignore）
logs/<配置名>/          # 同步日志
script/
  start-ui.sh           # 启动 Web UI
  sync-ui/              # Web 界面
  pack.sh               # 多平台打包
  docker-entrypoint.sh
data/                   # Docker 外挂数据卷（见上表）
```

---

## 配置说明

最小示例见 `yml/demo.yml`。关键字段：

```yaml
gitee:                          # 历史键名，兼容任意 Git 托管
  repo_url: "https://..."
  default_branch: "develop"
  local_dir: "/tmp/myproject"
  auth_type: "ssh"              # ssh | password
  ssh_key: "~/.ssh/id_rsa"

sync:
  rsync_options: "-az --progress"
  exclude: ["runtime/", "uploads/"]
  replace_dir: "./replace/myproject"

server_groups:
  - name: "生产"
    env: "production"           # 对应 replace/.../production/
    servers:
      - name: "web1"
        host: "user@1.2.3.4"
        target_dir: "/www/wwwroot/myproject"
        branch: "master"
        auth_type: "ssh"
        auth_info: "~/.ssh/id_rsa"
        post_sync_commands:
          - "chown -R www:www {target_dir}"
```

**Replace：** 将 `replace_dir/<env>/` 下文件按相对路径覆盖到本地检出后再同步，优先级最高。

**排除规则：** `sync.exclude` 中的路径不同步、不删除；以 `.` 开头的**目录**（`.git`、`.cursor` 等）内置过滤，以 `.` 开头的**文件**（如 `.env`）仍会同步。

---

## 打包详解

```bash
./pack.sh linux      # tar.gz + 自解压 .sh + Go 二进制
./pack.sh macos      # tar.gz + .command + Go 二进制
./pack.sh windows    # zip + gitship.exe
./pack.sh docker     # 镜像 tar + compose + load-and-up.sh
./pack.sh bin        # 仅 Go 单文件，不打压缩包
```

环境变量：

| 变量 | 说明 |
|------|------|
| `GITSHIP_BASE_IMAGE` | Docker 构建基础镜像（离线构建） |
| `GITSHIP_IMAGE` | compose 使用的镜像名 |
| `DIST` | 输出目录，默认 `dist/` |

---

## 安全提示

- 勿将 `.secrets/`、`.credentials/`、真实生产 `yml` 提交到 Git
- 仓库仅保留 `yml/demo.yml` 与 `data/configs/demo.yml` 模板
- Replace 目录中的生产密钥勿入库
- Docker 生产环境建议 `data/ssh` 只读挂载私钥

---

## 许可证

MIT — 详见 [LICENSE](LICENSE)
