# GitShip

从 Git 仓库拉取代码，或上传本地构建产物，再 rsync 同步到多台服务器。支持 Gitee / GitHub / GitLab 等任意 Git 远端。

**两种配置类型：**

| 类型 | 流水线 |
|------|--------|
| `type: git`（默认） | 选配置 → Git 拉取 → Replace → rsync → 同步后命令 |
| `type: dir` | 选配置 → 上传到临时工作区 → rsync 覆盖 → 同步后命令 |

---

## 特性

- **以 Git 为真相源** — 只操作 Git 跟踪的文件；Git 删除的会同步删除；未入库文件（如插件生成物）不受影响
- **目录同步** — 本地 HTML/打包产物上传到容器临时目录后直接推送，无需在服务器构建；不删除远端多余文件
- **智能比对** — `rsync --checksum`，仅上传内容有变的文件
- **Replace 优先** — `replace/<项目>/<env>/` 覆盖本地检出，优先级高于 Git（仅 Git 模式）
- **多机多组** — 服务器组、按机分支、SSH 密钥或密码认证
- **同步后命令** — 全局 / 组 / 单机三级 `post_sync`，支持 `chown`、重启服务等
- **Web 配置界面** — 表单编辑 YAML、上传 Replace / 目录产物、流式执行日志
- **Docker 友好** — 镜像只含框架，`data/` 外挂配置与密钥；目录同步通过 UI 上传进容器，无需额外挂载源目录

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

**拉不到 `debian:bookworm-slim`（Docker Hub 超时 / `auth.docker.io` i/o timeout）时：**

```bash
# 1）本机已有旧镜像时，用它当基础镜像，不再访问 Hub
docker images | head   # 看是否有 gitship:local / php-deploy:local / debian
GITSHIP_BASE_IMAGE=gitship:local docker compose build
# 或：GITSHIP_BASE_IMAGE=php-deploy:local docker compose build

# 2）没有本地基础镜像：换网络 / VPN，或配置国内镜像加速后再 build
# 3）怀疑 IPv6 超时：Docker Desktop → Settings → Docker Engine 加 "ipv6": false 后 Apply & Restart，再重试
```

宿主机目录与容器映射：

| 宿主机 | 说明 |
|--------|------|
| `data/configs/*.yml` | 项目配置（容器内 `/data/configs`，重建不丢） |
| `data/secrets/<名>.env` | 密码等密钥 |
| `data/ssh/` | SSH 私钥（只读挂载） |
| `data/replace/` | 环境替换文件 |
| `data/logs/` | 同步日志 |

Web UI 保存的配置会直接写到宿主机 `data/configs/`，重建容器不会丢。无配置时自动从镜像种子 `demo.yml` / `demo-dir.yml`。

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

配置统一放在 **`data/configs/`**（本地 CLI / Web UI / Docker 共用）：

```bash
cp data/configs/demo.yml data/configs/myproject.yml
# 或目录同步：
cp data/configs/demo-dir.yml data/configs/mysite.yml
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

### 3. 目录同步（静态站 / 本地打包产物）

适用于已在本地打包好的 HTML、前端 dist 等，**不需要在服务器上构建**。

```bash
cp data/configs/demo-dir.yml data/configs/mysite.yml
```

Web UI：

1. 同步类型选 **目录同步**
2. 「上传文件夹」或「上传压缩包」→ 写入容器内 `./.uploads/<配置名>/`（临时工作区，类似 Git 检出目录）
3. 配置好服务器组后执行同步 → rsync **覆盖上传**，远端多出的文件**不会删除**

Docker 下无需把宿主机源目录挂进容器；通过 UI 上传即可。重建容器后工作区可能清空，需重新上传。

CLI（本机已有目录时）：

```yaml
type: dir
dir:
  source_dir: "/绝对路径/或/./.uploads/mysite"
```

```bash
./sync.sh -y --config=mysite.yml --group=1
```

### 4. 命令行同步（Git）

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
data/configs/demo.yml       # Git 配置模板
data/configs/demo-dir.yml   # 目录同步模板
data/configs/*.yml          # 运行时配置（CLI / UI / Docker 共用）
replace/<项目>/<env>/       # 环境替换文件
.secrets/<配置名>.env       # 密钥（gitignore）
.credentials/               # Git 凭据缓存（gitignore）
logs/<配置名>/              # 同步日志
script/
  start-ui.sh               # 启动 Web UI
  sync-ui/                  # Web 界面
  pack.sh                   # 多平台打包
  docker-entrypoint.sh
data/                       # Docker 外挂数据卷（见上表）
```

---

## 配置说明

最小示例见 `data/configs/demo.yml`。关键字段：

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
| `GITSHIP_BASE_IMAGE` | 构建用的基础镜像，默认 `debian:bookworm-slim`；Hub 不通时可设为已有本地镜像（如 `gitship:local`） |
| `GITSHIP_IMAGE` | compose 使用的镜像名 |
| `DIST` | 输出目录，默认 `dist/` |

---

## 安全提示

- 勿将 `.secrets/`、`.credentials/`、真实生产配置提交到 Git
- 仓库仅跟踪 `data/configs/demo.yml`、`demo-dir.yml`；其余配置勿提交真实密钥
- Replace 目录中的生产密钥勿入库
- Docker 生产环境建议 `data/ssh` 只读挂载私钥

---

## 许可证

MIT — 详见 [LICENSE](LICENSE)
