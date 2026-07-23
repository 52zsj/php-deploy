#!/bin/bash
# 将 data/configs/*.yml（兼容旧 yml/）中的明文密码迁移到 .secrets/<配置名>.env
# 兼容 macOS bash 3.2（不用关联数组）

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
if [ -n "${DATA_CONFIGS:-}" ]; then
  CONFIG_DIR="$DATA_CONFIGS"
else
  CONFIG_DIR="$ROOT/data/configs"
fi
SECRETS_DIR="$ROOT/.secrets"
mkdir -p "$SECRETS_DIR" "$CONFIG_DIR"

# 旧 yml/ 迁移
if [ -d "$ROOT/yml" ]; then
  for f in "$ROOT/yml"/*.yml; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue
    base=$(basename "$f")
    [ -f "$CONFIG_DIR/$base" ] || cp "$f" "$CONFIG_DIR/$base"
  done
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "需要 yq: brew install yq"
  exit 1
fi

sanitize_key() {
  echo "$1" | sed 's/[^A-Za-z0-9_]/_/g' | sed 's/^_//;s/_$//'
}

is_ref() {
  case "$1" in
    secret:*|env:*) return 0 ;;
    *) return 1 ;;
  esac
}

# 向 env 文件写入/更新 KEY=VALUE
upsert_secret() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp=$(mktemp)
  if [ -f "$file" ]; then
    grep -v "^${key}=" "$file" > "$tmp" || true
  else
    : > "$tmp"
  fi
  echo "${key}=${value}" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

migrate_one() {
  local yml="$1"
  local stem
  stem=$(basename "$yml" .yml)
  local env_file="$SECRETS_DIR/${stem}.env"
  local changed=0

  local auth_type
  auth_type=$(yq e '.gitee.auth_type // ""' "$yml")
  if [ "$auth_type" = "password" ]; then
    local pw
    pw=$(yq e '.gitee.password // ""' "$yml")
    if [ -n "$pw" ] && [ "$pw" != "null" ] && ! is_ref "$pw"; then
      upsert_secret "$env_file" "GITEE_PASSWORD" "$pw"
      yq e -i '.gitee.password = "secret:GITEE_PASSWORD"' "$yml"
      changed=1
      echo "  [gitee.password] -> secret:GITEE_PASSWORD"
    fi
  fi

  local gcount
  gcount=$(yq e '.server_groups | length' "$yml")
  [ "$gcount" = "null" ] && gcount=0
  local gi si
  for ((gi=0; gi<gcount; gi++)); do
    local scount
    scount=$(yq e ".server_groups[$gi].servers | length" "$yml")
    [ "$scount" = "null" ] && scount=0
    for ((si=0; si<scount; si++)); do
      local stype sname ainfo key
      stype=$(yq e ".server_groups[$gi].servers[$si].auth_type // \"\"" "$yml")
      [ "$stype" != "password" ] && continue
      sname=$(yq e ".server_groups[$gi].servers[$si].name // \"server_${gi}_${si}\"" "$yml")
      ainfo=$(yq e ".server_groups[$gi].servers[$si].auth_info // \"\"" "$yml")
      if [ -n "$ainfo" ] && [ "$ainfo" != "null" ] && ! is_ref "$ainfo"; then
        key="SERVER_$(sanitize_key "$sname")"
        if [ -z "$key" ] || [ "$key" = "SERVER_" ]; then
          key="SERVER_${gi}_${si}"
        fi
        upsert_secret "$env_file" "$key" "$ainfo"
        yq e -i ".server_groups[$gi].servers[$si].auth_info = \"secret:$key\"" "$yml"
        changed=1
        echo "  [servers.$sname.auth_info] -> secret:$key"
      fi
    done
  done

  if [ $changed -eq 1 ]; then
    echo "✓ 已迁移: $yml  ->  $env_file"
  else
    echo "- 无需迁移: $yml"
  fi
}

echo "迁移明文密码到 .secrets/ ..."
for f in "$CONFIG_DIR"/*.yml; do
  [ -f "$f" ] || continue
  echo ""
  echo "== $(basename "$f") =="
  migrate_one "$f"
done
echo ""
echo "完成。请确认 .secrets/ 已在 .gitignore 中，且不要提交密钥文件。"
