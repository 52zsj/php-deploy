#!/bin/bash
# 启动配置界面（桌面窗口优先，否则浏览器）

cd "$(dirname "$0")/.." || exit 1

if ! command -v yq >/dev/null 2>&1 && ! python3 -c "import yaml" 2>/dev/null; then
  echo "需要 yq 或 PyYAML: brew install yq  或  pip3 install pyyaml"
  exit 1
fi

# SYNC_UI_CLASSIC=1 则只用浏览器标签页（原 app.py）
if [ "${SYNC_UI_CLASSIC:-}" = "1" ]; then
  exec python3 script/sync-ui/app.py
fi

exec python3 script/sync-ui/desktop.py
