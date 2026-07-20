#!/usr/bin/env bash
# GitShip 自解压启动壳（由 pack.sh 生成）
set -euo pipefail

VERSION="__VERSION__"
MARKER="__ARCHIVE_BELOW__"

resolve_home() {
  if [ -n "${GITSHIP_HOME:-${PHP_DEPLOY_HOME:-}}" ]; then
    echo "${GITSHIP_HOME:-$PHP_DEPLOY_HOME}"
    return
  fi
  if [ "${GITSHIP_PORTABLE:-${PHP_DEPLOY_PORTABLE:-}}" = "1" ]; then
    local self
    self="$(cd "$(dirname "$0")" && pwd)"
    echo "${self}/gitship-home"
    return
  fi
  # 默认安装目录（各平台用户配置目录）
  case "$(uname -s)" in
    Darwin)
      echo "${HOME}/Library/Application Support/gitship"
      ;;
    *)
      echo "${XDG_CONFIG_HOME:-$HOME/.config}/gitship"
      ;;
  esac
}

extract_if_needed() {
  local home="$1"
  local archive_line
  archive_line=$(awk "/^${MARKER}/ {print NR + 1; exit 0}" "$0")
  [ -n "$archive_line" ] || { echo "[gitship] corrupt sfx"; exit 1; }

  local need=1
  if [ -f "$home/VERSION" ] && [ "$(tr -d '[:space:]' < "$home/VERSION")" = "$VERSION" ]; then
    # 同版本时若无 .payload-id 变化则跳过；SFX 内 stamp 在归档里，简化：同版本仍跳过
    # （正式分发请升 VERSION；Go 启动器会比对 .payload-id）
    need=0
  fi
  if [ "$need" -eq 0 ]; then
    return 0
  fi
  mkdir -p "$home"
  echo "[gitship] 安装/更新 v${VERSION} → $home" >&2
  local tmp
  tmp=$(mktemp -d)
  tail -n +"$archive_line" "$0" | tar -xz -C "$tmp"
  local top
  top=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  if [ -n "$top" ]; then
    (cd "$top" && tar cf - .) | (cd "$home" && tar xf -)
  fi
  rm -rf "$tmp"
}

open_desktop() {
  export SYNC_UI_NO_BROWSER=1
  if [ -f script/sync-ui/desktop.py ]; then
    exec python3 script/sync-ui/desktop.py
  fi
  exec ./script/start-ui.sh
}

HOME_DIR="$(resolve_home)"
extract_if_needed "$HOME_DIR"
cd "$HOME_DIR"

mode="ui"
args=()
if [ "$#" -gt 0 ]; then
  case "$1" in
    ui|sync|help|-h|--help)
      mode="$1"
      shift
      ;;
    *)
      mode="sync"
      ;;
  esac
fi
args=("$@")

case "$mode" in
  help|-h|--help)
    cat <<EOF
gitship ${VERSION}

  $0              打开配置界面（独立窗口）
  $0 ui
  $0 sync [args]

默认安装目录: ${HOME_DIR}
便携模式: GITSHIP_PORTABLE=1
EOF
    exit 0
    ;;
  ui)
    open_desktop
    ;;
  sync)
    exec ./sync.sh "${args[@]}"
    ;;
  *)
    echo "unknown: $mode" >&2
    exit 1
    ;;
esac
exit 0
__ARCHIVE_BELOW__
