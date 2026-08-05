#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"
source "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh"

RESET_DB="${RESET_DB-false}"
RESET_DB_CONFIRMATION="${RESET_DB_CONFIRMATION-}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS-false}"
SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME"

local_supabase_validate_boolean RESET_DB "$RESET_DB" || exit $?
local_supabase_validate_boolean APPLY_MIGRATIONS "$APPLY_MIGRATIONS" || exit $?
if [[ "$APPLY_MIGRATIONS" != 'false' ]]; then
  printf '%s\n' \
    'Local database reset error: APPLY_MIGRATIONS is not accepted by the reset workflow.' >&2
  exit 2
fi
for command_name in supabase docker sha256sum rg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Local database reset error: required command %s is unavailable.\n' \
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
supabase_cli db reset --help >/dev/null
if ! start_output="$(supabase_cli start 2>&1)"; then
  printf '%s\n' "$start_output" | sanitize_supabase_output >&2
  exit 1
fi
printf '%s\n' "$start_output" | sanitize_supabase_output

local_supabase_capture_reset_facts "$ROOT_DIR"
if [[ "$RESET_DB" != 'true' ]]; then
  if [[ -n "$RESET_DB_CONFIRMATION" ]]; then
    printf '%s\n' \
      'Local database reset error: RESET_DB_CONFIRMATION is accepted only together with RESET_DB=true.' >&2
    exit 2
  fi
  local_supabase_print_reset_preview
  printf '%s\n' \
    'No data changed. To execute, review the target above and rerun:' \
    "RESET_DB=true RESET_DB_CONFIRMATION='${LOCAL_SUPABASE_RESET_TOKEN}' npm run db:reset:local" \
    'The executing run first creates and restore-verifies a full local backup.'
  exit 0
fi

local_supabase_execute_guarded_reset \
  "$ROOT_DIR" \
  "$RESET_DB_CONFIRMATION"
