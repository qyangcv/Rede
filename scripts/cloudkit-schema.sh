#!/bin/bash
# CloudKit schema gate.
#
# Usage:
#   bash scripts/cloudkit-schema.sh generate # create the Development schema from the models in code
#   bash scripts/cloudkit-schema.sh record   # generate, then export Development to cloudkit/schema.ckdb
#   bash scripts/cloudkit-schema.sh release  # record, commit schema.ckdb if changed, then wait until Production contains it
#
# cktool can only write the Development schema; Production is deployed from the
# CloudKit Console (iCloud.dev.qyang.Rede → Development → Deploy Schema Changes…).

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID=BTW6LD2Q74
CONTAINER_ID=iCloud.dev.qyang.Rede
SCHEMA=cloudkit/schema.ckdb
DERIVED_DATA=build/schema
APP=$DERIVED_DATA/Build/Products/Debug/Rede.app
CONSOLE_URL=https://icloud.developer.apple.com/dashboard/database

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

usage() {
  sed -n '2,9p' "$0"
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

# Debug macOS build calls initializeCloudKitSchema for every model in LibrarySchema
generate() {
  gum spin --title "Building schema generator…" --show-error -- \
    xcodebuild build -quiet -allowProvisioningUpdates \
      -scheme Rede -configuration Debug \
      -destination "platform=macOS,arch=$(uname -m)" \
      -derivedDataPath "$DERIVED_DATA"
  gum spin --title "Generating Development schema from models…" --show-error -- \
    "$APP/Contents/MacOS/Rede" --initialize-cloudkit-schema
}

record() {
  generate
  mkdir -p "$(dirname "$SCHEMA")"
  export_env development "$TMP/development.ckdb"
  if cmp -s "$TMP/development.ckdb" "$SCHEMA"; then
    echo "$SCHEMA unchanged"
  else
    mv "$TMP/development.ckdb" "$SCHEMA"
    echo "Updated $SCHEMA"
  fi
}

# Loop until Production contains every line of $1 (normalized); guides the Console deploy when interactive
await_production() {
  local missing opened=false
  while :; do
    export_env production "$TMP/production.ckdb"
    normalize "$TMP/production.ckdb" > "$TMP/production"
    missing=$(comm -23 "$1" "$TMP/production")
    [[ -n "$missing" ]] || break

    echo "Pending for Production:" >&2
    printf '%s\n' "$missing" >&2
    [[ -t 0 ]] || fail "Deploy at $CONSOLE_URL ($CONTAINER_ID → Development → Deploy Schema Changes…)"
    if ! $opened; then
      open "$CONSOLE_URL"
      opened=true
    fi
    gum confirm "Deploy in the Console: $CONTAINER_ID → Development → Deploy Schema Changes…" \
      --affirmative "Re-check" --negative "Abort" || exit 1
  done
  echo "Production schema is up to date"
}

release() {
  record
  if [[ -n $(git status --porcelain -- "$SCHEMA") ]]; then
    git add "$SCHEMA"
    git commit --quiet -m "chore: 更新 CloudKit schema" -- "$SCHEMA"
    echo "Committed $SCHEMA"
  fi

  normalize "$SCHEMA" > "$TMP/wanted"
  await_production "$TMP/wanted"
}

case "${1:-}" in
  generate) generate ;;
  record)   record ;;
  release)  release ;;
  *)        usage; exit 64 ;;
esac
