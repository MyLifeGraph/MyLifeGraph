#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
RESET_DB="${RESET_DB:-false}"
SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME"

if command -v supabase >/dev/null 2>&1; then
  SUPABASE_BIN="$(command -v supabase)"
else
  echo "Supabase CLI is not available." >&2
  echo "Install the Supabase CLI in Ubuntu and make 'supabase --version' work." >&2
  exit 127
fi

supabase_cli() {
  HOME="$SUPABASE_HOME" SUPABASE_TELEMETRY_DISABLED=1 "$SUPABASE_BIN" "$@"
}

sanitize_supabase_output() {
  sed -E \
    -e 's/(Publishable[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Access Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

supabase_cli --version
supabase_cli --help >/dev/null
start_output="$(supabase_cli start 2>&1)"
printf '%s\n' "$start_output" | sanitize_supabase_output

if [[ "$RESET_DB" == "true" ]]; then
  supabase_cli db reset
else
  echo "Skipping destructive local reset. Re-run with RESET_DB=true to execute supabase db reset."
fi

status_output="$(supabase_cli status -o env)"
api_url="$(printf '%s\n' "$status_output" | awk -F= '$1 == "API_URL" {gsub(/"/, "", $2); print $2; exit}')"
local_anon_key="$(printf '%s\n' "$status_output" | awk -F= '$1 == "ANON_KEY" {gsub(/"/, "", $2); print $2; exit}')"

if [[ -z "$local_anon_key" && -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Could not read the local anon key from 'supabase status'." >&2
  echo "Export SUPABASE_ANON_KEY manually and re-run this script." >&2
  exit 2
fi

echo "Supabase local API: ${api_url:-http://127.0.0.1:54321}"
echo "Local anon key: available"

cd "$ROOT_DIR/apps/mobile"

USE_MOCK_DATA=false \
SUPABASE_URL="${SUPABASE_URL:-${api_url:-http://127.0.0.1:54321}}" \
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$local_anon_key}" \
"$FLUTTER_BIN" test
