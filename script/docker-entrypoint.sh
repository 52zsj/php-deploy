#!/bin/bash
# Docker 入口：挂载数据目录 → 启动 UI / 执行 sync
set -e
cd /app

DATA_CONFIGS="${DATA_CONFIGS:-/data/configs}"
DATA_SECRETS="${DATA_SECRETS:-/data/secrets}"
DATA_CREDENTIALS="${DATA_CREDENTIALS:-/data/credentials}"
DATA_REPLACE="${DATA_REPLACE:-/data/replace}"
DATA_LOGS="${DATA_LOGS:-/data/logs}"
DATA_SSH="${DATA_SSH:-/data/ssh}"

link_dir() {
  local src="$1"
  local dst="$2"
  mkdir -p "$src"
  if [ -d "$dst" ] && [ ! -L "$dst" ]; then
    rm -rf "$dst"
  fi
  ln -sfn "$src" "$dst"
}

# 宿主机 data/configs/*.yml → /app/yml/
sync_configs() {
  mkdir -p "$DATA_CONFIGS" /app/yml
  # 保留镜像内 demo.yml（非链接时）
  if [ -d "$DATA_CONFIGS" ]; then
    for f in "$DATA_CONFIGS"/*.yml "$DATA_CONFIGS"/*.yaml; do
      [ -e "$f" ] || continue
      ln -sfn "$f" "/app/yml/$(basename "$f")"
    done
  fi
  # 若用户未放任何配置，把 demo 拷一份到 data 方便改
  if ! ls "$DATA_CONFIGS"/*.yml "$DATA_CONFIGS"/*.yaml >/dev/null 2>&1; then
    if [ -f /app/yml/demo.yml ] && [ ! -L /app/yml/demo.yml ]; then
      cp -n /app/yml/demo.yml "$DATA_CONFIGS/demo.yml" 2>/dev/null || true
      ln -sfn "$DATA_CONFIGS/demo.yml" /app/yml/demo.yml
    fi
  fi
}

link_dir "$DATA_SECRETS" /app/.secrets
link_dir "$DATA_CREDENTIALS" /app/.credentials
link_dir "$DATA_REPLACE" /app/replace
link_dir "$DATA_LOGS" /app/logs
sync_configs

# SSH 密钥（只读挂载常见）
if [ -d "$DATA_SSH" ]; then
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  for f in "$DATA_SSH"/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    # 每次启动覆盖，保证宿主机更新能进容器
    cp -a "$f" "/root/.ssh/$name"
  done
  chmod 600 /root/.ssh/* 2>/dev/null || true
  chmod 644 /root/.ssh/*.pub 2>/dev/null || true
  chmod 644 /root/.ssh/known_hosts 2>/dev/null || true
  chmod 644 /root/.ssh/config 2>/dev/null || true
fi

cmd="${1:-ui}"
shift || true

case "$cmd" in
  ui)
    export SYNC_UI_HOST="${SYNC_UI_HOST:-0.0.0.0}"
    export SYNC_UI_PORT="${SYNC_UI_PORT:-8765}"
    export SYNC_UI_NO_BROWSER=1
    echo "[gitship] UI http://${SYNC_UI_HOST}:${SYNC_UI_PORT}  (data: configs→yml, secrets, replace, logs, ssh)"
    exec python3 /app/script/sync-ui/app.py
    ;;
  sync)
    exec /app/sync.sh "$@"
    ;;
  migrate-secrets)
    exec /app/script/migrate-secrets.sh "$@"
    ;;
  version)
    echo "GitShip $(tr -d '[:space:]' < /app/VERSION 2>/dev/null || echo unknown)"
    command -v yq >/dev/null && yq --version
    python3 --version
    git --version
    rsync --version | head -n1
    exit 0
    ;;
  bash|sh)
    exec /bin/bash "$@"
    ;;
  *)
    echo "用法: docker run ... gitship [ui|sync|migrate-secrets|version|bash] [args...]"
    echo "  ui               启动 Web 界面（默认）"
    echo "  sync [opts]      执行 ./sync.sh（建议 -y --config= --group=）"
    echo "  migrate-secrets  迁移明文密码到 .secrets"
    echo "  version          打印版本与依赖"
    echo "  bash             进入容器 shell"
    exit 1
    ;;
esac
