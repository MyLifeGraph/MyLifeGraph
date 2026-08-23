#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is not available." >&2
  exit 127
fi

supabase_cli() {
  HOME="$SUPABASE_HOME" SUPABASE_TELEMETRY_DISABLED=1 supabase "$@"
}

supabase_cli start >/dev/null
status_output="$(supabase_cli status -o env)"
api_url="$(printf '%s\n' "$status_output" | awk -F= '$1 == "API_URL" {gsub(/"/, "", $2); print $2; exit}')"
service_role_key="$(printf '%s\n' "$status_output" | awk -F= '$1 == "SERVICE_ROLE_KEY" {gsub(/"/, "", $2); print $2; exit}')"

if [[ -z "$api_url" || -z "$service_role_key" ]]; then
  echo "Could not read the local Supabase URL and service-role key." >&2
  exit 2
fi

SUPABASE_URL="$api_url" \
SUPABASE_SERVICE_ROLE_KEY="$service_role_key" \
node scripts/cleanup_local_e2e_users.mjs "$@"
