#!/bin/bash
# CloudKit schema gate.
#
# Usage:
#   bash scripts/cloudkit-schema.sh record   # export the Development schema to cloudkit/schema.ckdb
#   bash scripts/cloudkit-schema.sh check    # schema.ckdb matches Development and Production contains it
#   bash scripts/cloudkit-schema.sh deploy   # record, open the CloudKit Console to deploy, then check
#
# cktool can only write the Development schema; Production is deployed from the
# CloudKit Console (Schema → Deploy Schema Changes).

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID=BTW6LD2Q74
CONTAINER_ID=iCloud.dev.qyang.Rede
SCHEMA=cloudkit/schema.ckdb
CONSOLE_URL=https://icloud.developer.apple.com/

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

usage() {
  sed -n '2,10p' "$0"
}

fail() {
  echo "$1" >&2
  exit 1
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

# Flatten a schema file into "RECORD_TYPE field type index" lines, dropping system fields, GRANT and Users
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

# Lines of $1 (normalized) that Production lacks
missing_in_production() {
  export_env production "$TMP/production.ckdb"
  normalize "$TMP/production.ckdb" > "$TMP/production"
  comm -23 "$1" "$TMP/production"
}

record() {
  mkdir -p "$(dirname "$SCHEMA")"
  export_env development "$SCHEMA"
  echo "Wrote $SCHEMA"
  git diff --stat -- "$SCHEMA" || true
}

check() {
  [[ -f "$SCHEMA" ]] || fail "$SCHEMA not found; run: bash scripts/cloudkit-schema.sh record"

  export_env development "$TMP/development.ckdb"
  normalize "$SCHEMA" > "$TMP/committed"
  normalize "$TMP/development.ckdb" > "$TMP/development"

  if ! diff -u "$TMP/committed" "$TMP/development" > "$TMP/stale.diff"; then
    cat "$TMP/stale.diff" >&2
    fail "$SCHEMA is behind Development; run: bash scripts/cloudkit-schema.sh record"
  fi

  local missing
  missing=$(missing_in_production "$TMP/development")
  if [[ -n "$missing" ]]; then
    printf '%s\n' "$missing" >&2
    fail "Production is missing the structures above; deploy at $CONSOLE_URL ($CONTAINER_ID → Schema → Deploy Schema Changes)"
  fi

  echo "Production schema is up to date"
}

deploy() {
  record

  normalize "$SCHEMA" > "$TMP/wanted"
  local missing
  missing=$(missing_in_production "$TMP/wanted")
  if [[ -z "$missing" ]]; then
    echo "Production schema is up to date"
    return
  fi

  echo "Pending for Production:"
  printf '%s\n' "$missing"

  open "$CONSOLE_URL"
  echo "Opened CloudKit Console: $CONTAINER_ID → Schema → Deploy Schema Changes"
  if [[ -t 0 ]]; then
    read -r -p "Press Enter after deploying to verify" _
  fi

  check
}

case "${1:-}" in
  record) record ;;
  check)  check ;;
  deploy) deploy ;;
  *)      usage; exit 64 ;;
esac
