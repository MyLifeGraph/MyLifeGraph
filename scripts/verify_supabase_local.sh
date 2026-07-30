#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"

RESET_DB="${RESET_DB-false}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS-false}"
SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME"

local_supabase_validate_migration_flags \
  "$RESET_DB" "$APPLY_MIGRATIONS" true || exit $?

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

local_supabase_prepare_migration_state \
  "$RESET_DB" "$APPLY_MIGRATIONS" true

echo "Running the complete local pgTAP suite."
supabase_cli test db
