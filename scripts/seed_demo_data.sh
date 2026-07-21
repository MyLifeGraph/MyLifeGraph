#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${NODE_BIN:-node}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/services/ai_service/.venv/bin/python}"
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

if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
  echo "Node.js is not available as '$NODE_BIN'." >&2
  echo "Install Node.js in Ubuntu and make 'node --version' work." >&2
  exit 127
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "The FastAPI virtual environment is not available at '$PYTHON_BIN'." >&2
  echo "Create services/ai_service/.venv and install its requirements, or set PYTHON_BIN." >&2
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
if ! start_output="$(supabase_cli start 2>&1)"; then
  printf '%s\n' "$start_output" | sanitize_supabase_output >&2
  exit 1
fi
printf '%s\n' "$start_output" | sanitize_supabase_output

status_output="$(supabase_cli status -o env)"
api_url="$(printf '%s\n' "$status_output" | awk -F= '$1 == "API_URL" {gsub(/"/, "", $2); print $2; exit}')"
local_service_role_key="$(printf '%s\n' "$status_output" | awk -F= '$1 == "SERVICE_ROLE_KEY" {gsub(/"/, "", $2); print $2; exit}')"

if [[ -z "$api_url" || -z "$local_service_role_key" ]]; then
  echo "Could not read local Supabase API URL or service role key from 'supabase status -o env'." >&2
  exit 2
fi

echo "Supabase local API: $api_url"
echo "Local service role key: available for demo seeding"

SUPABASE_URL="$api_url" \
SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
"$NODE_BIN" scripts/seed_demo_data.mjs

SUPABASE_URL="$api_url" \
SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
PYTHONPATH="$ROOT_DIR/services/ai_service" \
"$PYTHON_BIN" scripts/seed_student_feature_data.py
