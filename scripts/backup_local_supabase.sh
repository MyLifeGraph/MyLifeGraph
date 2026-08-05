#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh"

SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME"

for command_name in supabase docker sha256sum rg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Local backup error: required command %s is unavailable.\n' \
      "$command_name" >&2
    exit 127
  fi
done
SUPABASE_BIN="$(command -v supabase)"

supabase_cli() {
  HOME="$SUPABASE_HOME" SUPABASE_TELEMETRY_DISABLED=1 \
    "$SUPABASE_BIN" "$@"
}

sanitize_supabase_output() {
  sed -E \
    -e 's#postgres(ql)?://[^[:space:]│]+#postgresql://<redacted>#g' \
    -e 's/(Publishable[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Access Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

supabase_cli --version
supabase_cli db dump --help >/dev/null
if ! start_output="$(supabase_cli start 2>&1)"; then
  printf '%s\n' "$start_output" | sanitize_supabase_output >&2
  exit 1
fi
printf '%s\n' "$start_output" | sanitize_supabase_output

backup_path="$(
  local_supabase_create_verified_backup "$ROOT_DIR" 'manual'
)"
printf '%s\n' \
  "Verified local Supabase backup created: ${backup_path}" \
  "Checksum: ${backup_path}.sha256" \
  "Metadata: ${backup_path}.metadata"
