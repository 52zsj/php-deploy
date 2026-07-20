#!/usr/bin/env bash
# 根目录快捷打包入口 → script/pack.sh
# 用法:
#   ./pack.sh              # 默认打 macOS + Windows（便于本机测试）
#   ./pack.sh macos
#   ./pack.sh windows
#   ./pack.sh macos windows
#   ./pack.sh all          # linux + macos + windows + docker
#   ./pack.sh bin          # 仅单文件二进制
#   ./pack.sh -h

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ ! -x "$ROOT/script/pack.sh" ]; then
  chmod +x "$ROOT/script/pack.sh" 2>/dev/null || true
fi

if [ "$#" -eq 0 ]; then
  set -- macos windows
fi

exec "$ROOT/script/pack.sh" "$@"
