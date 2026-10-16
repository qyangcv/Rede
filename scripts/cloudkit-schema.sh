#!/bin/bash
# CloudKit schema gate.
#
# Usage:
#   bash scripts/cloudkit-schema.sh record   # Development 导出 schema → cloudkit/schema.ckdb
#   bash scripts/cloudkit-schema.sh check    # schema.ckdb 未过期，且 Production 已包含其结构
#   bash scripts/cloudkit-schema.sh deploy   # record + 打开 CloudKit Console 部署 + 校验
#
# cktool 的 schema 写入端点只对 development 环境开放，production 的部署只能在
# CloudKit Console 里执行 Deploy Schema Changes。

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID=BTW6LD2Q74
CONTAINER_ID=iCloud.dev.qyang.Rede
SCHEMA=cloudkit/schema.ckdb
CONSOLE_URL=https://icloud.developer.apple.com/

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

usage() {
  sed -n '2,11p' "$0"
}

run_cktool() {
  local output
  if ! output=$(xcrun cktool "$@" --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" 2>&1); then
    printf '%s\n' "$output" | grep -v -E 'DEBUG:|NetworkStorageDB|read-connection|writeDBwithCachedResponse' >&2 || true
    return 1
  fi
}

export_env() {
  run_cktool export-schema --environment "$1" --output-file "$2"
}

# 把 schema 文件压成 "RECORD TYPE 字段 类型 索引" 行，忽略系统字段、GRANT 与 Users
normalize() {
  awk '
    /^[[:space:]]*RECORD TYPE / { type = $3; next }
    type != "" && /^[[:space:]]*\);/ { type = ""; next }
    type != "" && $1 != "GRANT" && $1 !~ /^"/ && NF > 0 {
      line = $0
      sub(/,$/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      sub(/^ /, "", line)
      sub(/ $/, "", line)
      print type " " line
    }
  ' "$1" | grep -v '^Users ' | LC_ALL=C sort -u
}

record() {
  mkdir -p "$(dirname "$SCHEMA")"
  export_env development "$SCHEMA"
  echo "已写入 $SCHEMA"
  git diff --stat -- "$SCHEMA" || true
}

check() {
  [[ -f "$SCHEMA" ]] || { echo "缺少 $SCHEMA：先运行 bash scripts/cloudkit-schema.sh record"; exit 1; }

  export_env development "$TMP/development.ckdb"
  export_env production "$TMP/production.ckdb"

  normalize "$SCHEMA" > "$TMP/committed"
  normalize "$TMP/development.ckdb" > "$TMP/development"
  normalize "$TMP/production.ckdb" > "$TMP/production"

  if ! diff -u "$TMP/committed" "$TMP/development" > "$TMP/stale.diff"; then
    echo "❌ $SCHEMA 与 Development 不一致：模型改动没有同步到云端 schema 基线"
    cat "$TMP/stale.diff"
    echo "→ 运行 bash scripts/cloudkit-schema.sh record 并提交 $SCHEMA"
    exit 1
  fi

  local missing
  missing=$(comm -23 "$TMP/development" "$TMP/production")
  if [[ -n "$missing" ]]; then
    echo "❌ Production 缺少以下结构，新版本一旦写入就会同步失败："
    printf '%s\n' "$missing"
    echo "→ 部署：$CONSOLE_URL → $CONTAINER_ID → Schema → Deploy Schema Changes"
    exit 1
  fi

  echo "✅ Production schema 已包含 $SCHEMA 的全部结构"
}

deploy() {
  record

  export_env production "$TMP/production.ckdb"
  normalize "$SCHEMA" > "$TMP/wanted"
  normalize "$TMP/production.ckdb" > "$TMP/production"

  local missing
  missing=$(comm -23 "$TMP/wanted" "$TMP/production")
  if [[ -z "$missing" ]]; then
    echo "✅ Production 已是最新，无需部署"
    return
  fi

  echo "需要部署到 Production 的结构："
  printf '%s\n' "$missing"

  open "$CONSOLE_URL"
  echo "已在浏览器打开 CloudKit Console：$CONTAINER_ID → Schema → Deploy Schema Changes"
  if [[ -t 0 ]]; then
    read -r -p "部署完成后按回车校验…" _
  fi

  check
}

case "${1:-}" in
  record) record ;;
  check)  check ;;
  deploy) deploy ;;
  *)      usage; exit 64 ;;
esac
