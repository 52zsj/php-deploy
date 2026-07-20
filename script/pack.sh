#!/usr/bin/env bash
# 打包发行物：
#   linux/macos  → tar.gz + 自解压 .sh/.command 壳 + Go 单文件
#   windows      → zip + gitship.exe
#   docker       → 离线镜像包
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "0.0.0")"
DIST="${DIST:-$ROOT/dist}"
NAME="gitship"
IMAGE="${PACK_IMAGE:-gitship:${VERSION}}"
LAUNCHER_DIR="$ROOT/script/pack/launcher"
PAYLOAD="$LAUNCHER_DIR/payload.tar.gz"

TARGETS=("$@")
if [ "${#TARGETS[@]}" -eq 0 ] || [ "${1:-}" = "all" ]; then
  TARGETS=(linux macos windows docker)
fi

mkdir -p "$DIST"

log() { printf '[pack] %s\n' "$*"; }
die() { printf '[pack] ERROR: %s\n' "$*" >&2; exit 1; }

stage_framework() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest/script" "$dest/replace" "$dest/logs" "$dest/data/configs" \
    "$dest/data/secrets" "$dest/data/credentials" "$dest/data/replace" \
    "$dest/data/logs" "$dest/data/ssh"

  cp -R sync.sh test_interactive.sh LICENSE NOTICE VERSION "$dest/"
  # 每次打包写入唯一 stamp，同版本号重打包也会触发安装目录覆盖
  date +%Y%m%d%H%M%S > "$dest/.payload-id"
  mkdir -p "$dest/yml"
  cp -R yml/demo.yml "$dest/yml/"
  cp -R script/start-ui.sh script/migrate-secrets.sh script/docker-entrypoint.sh "$dest/script/"
  cp -R script/sync-ui "$dest/script/"
  find "$dest/script/sync-ui" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
  find "$dest/script/sync-ui" -name '*.pyc' -delete 2>/dev/null || true

  mkdir -p "$dest/script/pack"
  # 不把 launcher 源码/payload 打进发行包，避免循环膨胀
  cp script/pack/start-ui.bat script/pack/start-ui.ps1 script/pack/start-sync.bat \
    script/pack/sfx-header.sh "$dest/script/pack/" 2>/dev/null || true

  if [ -f replace/.gitignore ]; then cp replace/.gitignore "$dest/replace/"; fi
  if [ -f logs/.gitignore ]; then cp logs/.gitignore "$dest/logs/"; fi
  touch "$dest/data/configs/.gitkeep" "$dest/data/secrets/.gitkeep" \
    "$dest/data/credentials/.gitkeep" "$dest/data/replace/.gitkeep" \
    "$dest/data/logs/.gitkeep" "$dest/data/ssh/.gitkeep"

  chmod +x "$dest/sync.sh" "$dest/test_interactive.sh" \
    "$dest/script/start-ui.sh" "$dest/script/migrate-secrets.sh" \
    "$dest/script/docker-entrypoint.sh" 2>/dev/null || true
}

# 供 Go embed / SFX 共用的框架 tarball
build_payload() {
  local stage="$DIST/.payload-stage"
  local out_base="${NAME}-${VERSION}-payload"
  rm -rf "$stage"
  stage_framework "$stage/${out_base}"
  mkdir -p "$LAUNCHER_DIR"
  tar -czf "$PAYLOAD" -C "$stage" "$out_base"
  rm -rf "$stage"
  log "payload → $PAYLOAD ($(du -h "$PAYLOAD" | awk '{print $1}'))"
}

write_unix_readme() {
  local dest="$1"
  local os_label="$2"
  cat > "$dest/PACK.txt" <<EOF
gitship ${VERSION} (${os_label})
==============================

推荐：使用单文件启动器（同目录下的 gitship / gitship.sh）
  ./gitship           # 启动 UI（首次自动解压到系统配置目录或 ./gitship-home）
  ./gitship sync -y --config=demo.yml --group=1

或解压本目录后:
  ./script/start-ui.sh
  ./sync.sh

依赖: bash, git, rsync, openssh, python3（可选 yq / sshpass）
密码写入 gitship 数据目录 .secrets/，勿提交。
EOF
}

write_windows_readme() {
  local dest="$1"
  cat > "$dest/PACK.txt" <<EOF
gitship ${VERSION} (Windows)
==============================

推荐: 双击 gitship.exe（首次解压到系统 AppData\\gitship 或同目录 gitship-home\\）
  gitship.exe
  gitship.exe sync -y --config=demo.yml --group=1

依赖:
  - Python 3（UI）
  - 同步需 Git Bash 或 WSL

也可使用 start-ui.bat / start-sync.bat
EOF
}

write_docker_readme() {
  local dest="$1"
  local tarname="$2"
  cat > "$dest/PACK.txt" <<EOF
gitship ${VERSION} (Docker)
==============================

  docker load -i ${tarname}
  mkdir -p data/{configs,secrets,credentials,replace,logs,ssh}
  docker compose up -d

UI: http://127.0.0.1:8765
配置: data/configs/*.yml
密钥: data/secrets/<配置名>.env
SSH:  data/ssh/
Replace: data/replace/

同步示例:
  docker compose run --rm sync sync -y --config=demo.yml --group=1 --post-sync=1

检查:
  docker compose exec ui version
EOF
}

# 自解压壳：header + payload.tar.gz
pack_sfx() {
  local os="$1"
  local ext="sh"
  [ "$os" = "macos" ] && ext="command"
  local out="$DIST/${NAME}-${VERSION}-${os}.${ext}"
  local header="$DIST/.sfx-header-$os.sh"

  [ -f "$PAYLOAD" ] || build_payload

  sed "s/__VERSION__/${VERSION}/g" "$ROOT/script/pack/sfx-header.sh" > "$header"
  # 确保 marker 行后直接接二进制
  cat "$header" "$PAYLOAD" > "$out"
  chmod +x "$out"
  rm -f "$header"
  log "ok sfx ${out}"
}

# Go 单文件（windows=exe，linux/macos=无后缀二进制）
pack_bin() {
  local goos="$1"
  local goarch="${2:-amd64}"
  local label="$3"
  local out

  command -v go >/dev/null 2>&1 || die "需要 Go 才能打单文件二进制（brew install go）"
  [ -f "$PAYLOAD" ] || build_payload

  case "$goos" in
    windows) out="$DIST/${NAME}-${VERSION}-windows-${goarch}.exe" ;;
    darwin) out="$DIST/${NAME}-${VERSION}-macos-${goarch}" ;;
    linux) out="$DIST/${NAME}-${VERSION}-linux-${goarch}" ;;
    *) die "unknown goos $goos" ;;
  esac

  log "go build ${label} → $(basename "$out")"
  (
    cd "$LAUNCHER_DIR"
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
      go build -trimpath \
      -ldflags "-s -w -X main.Version=${VERSION}" \
      -o "$out" .
  )
  chmod +x "$out" 2>/dev/null || true
  log "ok bin ${out}"
}

pack_unix() {
  local os="$1"
  local stage="$DIST/.stage-${os}"
  local out_base="${NAME}-${VERSION}-${os}"
  local archive="$DIST/${out_base}.tar.gz"

  log "staging ${os}..."
  stage_framework "$stage/${out_base}"
  write_unix_readme "$stage/${out_base}" "$os"
  cat > "$stage/${out_base}/start-ui" <<'EOF'
#!/usr/bin/env bash
cd "$(dirname "$0")"
exec ./script/start-ui.sh "$@"
EOF
  chmod +x "$stage/${out_base}/start-ui"

  tar -czf "$archive" -C "$stage" "$out_base"
  rm -rf "$stage"
  log "ok ${archive}"

  # 壳：自解压 sh/command + Go 二进制
  pack_sfx "$os"
  if [ "$os" = "linux" ]; then
    pack_bin linux amd64 "linux/amd64"
    pack_bin linux arm64 "linux/arm64" || true
  else
    pack_bin darwin arm64 "macos/arm64"
    pack_bin darwin amd64 "macos/amd64" || true
  fi
}

pack_windows() {
  local stage="$DIST/.stage-windows"
  local out_base="${NAME}-${VERSION}-windows"
  local archive="$DIST/${out_base}.zip"

  log "staging windows..."
  stage_framework "$stage/${out_base}"
  write_windows_readme "$stage/${out_base}"
  cp script/pack/start-ui.bat "$stage/${out_base}/"
  cp script/pack/start-ui.ps1 "$stage/${out_base}/"
  cp script/pack/start-sync.bat "$stage/${out_base}/"

  if command -v zip >/dev/null 2>&1; then
    (cd "$stage" && zip -qr "$archive" "$out_base")
  else
    python3 - <<PY
import shutil
shutil.make_archive("${archive%.zip}", "zip", "$stage", "$out_base")
PY
  fi
  rm -rf "$stage"
  log "ok ${archive}"

  pack_bin windows amd64 "windows/amd64"
  # 友好短名
  cp -f "$DIST/${NAME}-${VERSION}-windows-amd64.exe" "$DIST/${NAME}.exe"
  log "ok $DIST/${NAME}.exe (copy)"
}

pack_docker() {
  local stage="$DIST/.stage-docker"
  local out_base="${NAME}-${VERSION}-docker"
  local img_tar="${NAME}-${VERSION}-image.tar"
  local archive="$DIST/${out_base}.tar.gz"

  command -v docker >/dev/null 2>&1 || die "需要 docker 才能打包 docker 目标"

  log "docker build ${IMAGE} (VERSION=${VERSION})..."
  docker build \
    --build-arg "VERSION=${VERSION}" \
    --build-arg "BASE_IMAGE=${GITSHIP_BASE_IMAGE:-debian:bookworm-slim}" \
    -t "$IMAGE" \
    -t "gitship:latest" \
    -t "gitship:${VERSION}" \
    "$ROOT"

  mkdir -p "$stage/${out_base}"
  docker save -o "$stage/${out_base}/${img_tar}" "$IMAGE"

  cat > "$stage/${out_base}/docker-compose.yml" <<EOF
name: gitship
services:
  ui:
    image: ${IMAGE}
    container_name: gitship-ui
    ports:
      - "\${SYNC_UI_PORT:-8765}:8765"
    environment:
      SYNC_UI_HOST: "0.0.0.0"
      SYNC_UI_PORT: "8765"
      SYNC_UI_NO_BROWSER: "1"
    volumes:
      - ./data/configs:/data/configs
      - ./data/secrets:/data/secrets
      - ./data/credentials:/data/credentials
      - ./data/replace:/data/replace
      - ./data/logs:/data/logs
      - ./data/ssh:/data/ssh:ro
    restart: unless-stopped
  sync:
    image: ${IMAGE}
    profiles: ["cli"]
    environment:
      SYNC_UI_NO_BROWSER: "1"
    volumes:
      - ./data/configs:/data/configs
      - ./data/secrets:/data/secrets
      - ./data/credentials:/data/credentials
      - ./data/replace:/data/replace
      - ./data/logs:/data/logs
      - ./data/ssh:/data/ssh:ro
    entrypoint: ["/app/script/docker-entrypoint.sh"]
    command: ["sync"]
EOF

  cp LICENSE NOTICE VERSION "$stage/${out_base}/"
  mkdir -p "$stage/${out_base}/yml"
  [ -f yml/demo.yml ] && cp yml/demo.yml "$stage/${out_base}/yml/"
  for d in configs secrets credentials replace logs ssh; do
    mkdir -p "$stage/${out_base}/data/$d"
    touch "$stage/${out_base}/data/$d/.gitkeep"
  done
  write_docker_readme "$stage/${out_base}" "$img_tar"
  cat > "$stage/${out_base}/load-and-up.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\$0")"
docker load -i ${img_tar}
mkdir -p data/{configs,secrets,credentials,replace,logs,ssh}
docker compose up -d
echo "UI: http://127.0.0.1:8765"
echo "配置: ./data/configs/  密钥: ./data/secrets/  SSH: ./data/ssh/"
EOF
  chmod +x "$stage/${out_base}/load-and-up.sh"
  tar -czf "$archive" -C "$stage" "$out_base"
  rm -rf "$stage"
  log "ok ${archive}"
}

# 确保 launcher 有可 embed 的占位
if [ ! -f "$PAYLOAD" ]; then
  mkdir -p "$LAUNCHER_DIR"
  echo "$VERSION" > "$DIST/.ph-version"
  tar -czf "$PAYLOAD" -C "$DIST" .ph-version
  rm -f "$DIST/.ph-version"
fi

build_payload

for t in "${TARGETS[@]}"; do
  case "$t" in
    linux|macos) pack_unix "$t" ;;
    windows) pack_windows ;;
    docker) pack_docker ;;
    sfx)
      pack_sfx linux
      pack_sfx macos
      ;;
    bin)
      pack_bin linux amd64 linux/amd64
      pack_bin linux arm64 linux/arm64 || true
      pack_bin darwin arm64 macos/arm64
      pack_bin darwin amd64 macos/amd64 || true
      pack_bin windows amd64 windows/amd64
      cp -f "$DIST/${NAME}-${VERSION}-windows-amd64.exe" "$DIST/${NAME}.exe"
      ;;
    all) ;;
    -h|--help|help)
      cat <<EOF
用法: ./script/pack.sh [linux|macos|windows|docker|sfx|bin|all]

单文件壳（推荐分发）:
  dist/${NAME}-${VERSION}-linux-amd64          # Linux 可执行文件
  dist/${NAME}-${VERSION}-macos-arm64          # Apple Silicon
  dist/${NAME}-${VERSION}-windows-amd64.exe    # Windows
  dist/${NAME}.exe                             # Windows 短名
  dist/${NAME}-${VERSION}-linux.sh             # 纯 bash 自解压壳
  dist/${NAME}-${VERSION}-macos.command        # macOS 双击（Terminal）

仍附带传统压缩包 .tar.gz / .zip。默认数据目录为系统配置下的 gitship/（便携模式为可执行文件旁 gitship-home/）。
EOF
      exit 0
      ;;
    *) die "未知目标: $t" ;;
  esac
done

log "done → ${DIST}/"
ls -lh "$DIST" | sed -n '1,40p'
