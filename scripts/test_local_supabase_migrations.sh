#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"
source "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh"

TEST_ROOT="$(mktemp -d /tmp/mylifegraph-migration-safety-test.XXXXXX)"
STATE_FILE="$TEST_ROOT/state"
EVENTS_FILE="$TEST_ROOT/events"

cleanup_test() {
  rm -rf "$TEST_ROOT"
}
trap cleanup_test EXIT

write_current_list() {
  cat <<'LIST'
  Local          | Remote         | Time (UTC)
 ----------------|----------------|---------------------
  20260714100000 | 20260714100000 | 2026-07-14 10:00:00
  20260714103000 | 20260714103000 | 2026-07-14 10:30:00
LIST
}

write_pending_list() {
  cat <<'LIST'
  Local          | Remote         | Time (UTC)
 ----------------|----------------|---------------------
  20260714100000 | 20260714100000 | 2026-07-14 10:00:00
  20260714103000 |                | 2026-07-14 10:30:00
LIST
}

write_divergent_list() {
  cat <<'LIST'
  Local          | Remote         | Time (UTC)
 ----------------|----------------|---------------------
                 | 20260714094500 | 2026-07-14 09:45:00
  20260714100000 | 20260714100000 | 2026-07-14 10:00:00
  20260714103000 |                | 2026-07-14 10:30:00
LIST
}

supabase_cli() {
  printf '%s\n' "$*" >>"$EVENTS_FILE"
  case "$*" in
    'migration list --local')
      case "$(cat "$STATE_FILE")" in
        current) write_current_list ;;
        pending) write_pending_list ;;
        divergent) write_divergent_list ;;
        malformed) printf 'unexpected output\n' ;;
        failure) return 91 ;;
        *) return 92 ;;
      esac
      ;;
    'migration up --local')
      printf 'current\n' >"$STATE_FILE"
      ;;
    'db reset --local')
      printf 'current\n' >"$STATE_FILE"
      ;;
    *) return 93 ;;
  esac
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected %q in %s\n' "$expected" "$file" >&2
    sed -n '1,240p' "$file" >&2 || true
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    printf 'Did not expect %q in %s\n' "$unexpected" "$file" >&2
    sed -n '1,240p' "$file" >&2 || true
    exit 1
  fi
}

reset_scenario() {
  local state="$1"
  : >"$EVENTS_FILE"
  printf '%s\n' "$state" >"$STATE_FILE"
}

reset_scenario current
local_supabase_prepare_migration_state false false true \
  >"$TEST_ROOT/current.log" 2>&1
assert_contains "$EVENTS_FILE" 'migration list --local'
assert_not_contains "$EVENTS_FILE" 'migration up --local'
assert_not_contains "$EVENTS_FILE" 'db reset'
assert_contains "$TEST_ROOT/current.log" 'migration history matches the repository'

reset_scenario pending
set +e
local_supabase_prepare_migration_state false false true \
  >"$TEST_ROOT/pending.log" 2>&1
pending_status=$?
set -e
[[ "$pending_status" -eq 1 ]]
assert_contains "$EVENTS_FILE" 'migration list --local'
assert_not_contains "$EVENTS_FILE" 'migration up --local'
assert_not_contains "$EVENTS_FILE" 'db reset'
assert_contains "$TEST_ROOT/pending.log" 'No migration was applied automatically.'
assert_contains "$TEST_ROOT/pending.log" 'APPLY_MIGRATIONS=true'

reset_scenario pending
local_supabase_prepare_migration_state false true true \
  >"$TEST_ROOT/apply.log" 2>&1
assert_contains "$EVENTS_FILE" 'migration up --local'
assert_contains "$EVENTS_FILE" 'migration list --local'
assert_contains "$TEST_ROOT/apply.log" 'may change or delete local rows'
assert_contains "$TEST_ROOT/apply.log" 'migration history matches the repository'

reset_scenario current
set +e
local_supabase_prepare_migration_state true true true \
  >"$TEST_ROOT/conflict.log" 2>&1
conflict_status=$?
local_supabase_prepare_migration_state yes false true \
  >"$TEST_ROOT/invalid.log" 2>&1
invalid_status=$?
local_supabase_prepare_migration_state true false false \
  >"$TEST_ROOT/reset-forbidden.log" 2>&1
reset_forbidden_status=$?
local_supabase_prepare_migration_state true false true \
  >"$TEST_ROOT/reset-delegation-forbidden.log" 2>&1
reset_delegation_forbidden_status=$?
set -e
[[ "$conflict_status" -eq 2 ]]
[[ "$invalid_status" -eq 2 ]]
[[ "$reset_forbidden_status" -eq 2 ]]
[[ "$reset_delegation_forbidden_status" -eq 2 ]]
[[ ! -s "$EVENTS_FILE" ]]
assert_contains "$TEST_ROOT/conflict.log" 'mutually exclusive'
assert_contains "$TEST_ROOT/invalid.log" 'must be exactly true or false'
assert_contains "$TEST_ROOT/reset-forbidden.log" 'this command never resets the database'
assert_contains "$TEST_ROOT/reset-delegation-forbidden.log" \
  'generic migration preparation has no reset authority'

for unsafe_state in malformed failure; do
  reset_scenario "$unsafe_state"
  set +e
  local_supabase_prepare_migration_state false false true \
    >"$TEST_ROOT/$unsafe_state.log" 2>&1
  unsafe_status=$?
  set -e
  [[ "$unsafe_status" -eq 1 ]]
  assert_not_contains "$EVENTS_FILE" 'migration up --local'
  assert_not_contains "$EVENTS_FILE" 'db reset'
  assert_contains "$TEST_ROOT/$unsafe_state.log" 'No migration was applied automatically'
done

# The dedicated reset wrapper binds approval to the exact inspected target,
# creates a verified backup first, checks the fingerprint again, and invokes
# only the CLI's explicit local target. These are hermetic function tests: no
# Docker container or database is touched.
MOCK_RESET_TOKEN='reset-local-mylifegraph-0123456789abcdef'
MOCK_RESET_TOKEN_AFTER_BACKUP="$MOCK_RESET_TOKEN"

local_supabase_capture_reset_facts() {
  LOCAL_SUPABASE_SAFETY_PROJECT_ID='mylifegraph'
  LOCAL_SUPABASE_SAFETY_CONTAINER='supabase_db_mylifegraph'
  LOCAL_SUPABASE_RESET_DATABASE='postgres'
  LOCAL_SUPABASE_RESET_AUTH_USERS='4'
  LOCAL_SUPABASE_RESET_PROFILES='4'
  LOCAL_SUPABASE_RESET_DATABASE_BYTES='123456'
  LOCAL_SUPABASE_RESET_LATEST_MIGRATION='20260804102409'
  LOCAL_SUPABASE_RESET_WAL_LSN='0/ABCDEF'
  if [[ "$(wc -l <"$EVENTS_FILE")" -gt 0 ]] &&
    grep -Fq 'verified backup' "$EVENTS_FILE"; then
    LOCAL_SUPABASE_RESET_TOKEN="$MOCK_RESET_TOKEN_AFTER_BACKUP"
  else
    LOCAL_SUPABASE_RESET_TOKEN="$MOCK_RESET_TOKEN"
  fi
  printf '%s\n' 'capture target fingerprint' >>"$EVENTS_FILE"
}

local_supabase_create_verified_backup() {
  printf '%s\n' 'verified backup' >>"$EVENTS_FILE"
  printf '%s\n' "$TEST_ROOT/verified.dump"
}

local_supabase_assert_migration_history_current() {
  printf '%s\n' 'verify migration history' >>"$EVENTS_FILE"
}

supabase_cli() {
  printf '%s\n' "$*" >>"$EVENTS_FILE"
}

reset_scenario current
set +e
local_supabase_execute_guarded_reset "$ROOT_DIR" 'wrong-token' \
  >"$TEST_ROOT/wrong-token.log" 2>&1
wrong_token_status=$?
set -e
[[ "$wrong_token_status" -eq 2 ]]
assert_contains "$EVENTS_FILE" 'capture target fingerprint'
assert_not_contains "$EVENTS_FILE" 'verified backup'
assert_not_contains "$EVENTS_FILE" 'db reset'
assert_contains "$TEST_ROOT/wrong-token.log" \
  'does not match the current target and contents'

reset_scenario current
local_supabase_execute_guarded_reset "$ROOT_DIR" "$MOCK_RESET_TOKEN" \
  >"$TEST_ROOT/guarded-reset.log" 2>&1
assert_contains "$EVENTS_FILE" 'verified backup'
assert_contains "$EVENTS_FILE" 'db reset --local'
assert_contains "$EVENTS_FILE" 'verify migration history'
backup_line="$(grep -Fn 'verified backup' "$EVENTS_FILE" | cut -d: -f1)"
reset_line="$(grep -Fn 'db reset --local' "$EVENTS_FILE" | cut -d: -f1)"
[[ "$backup_line" -lt "$reset_line" ]]
assert_not_contains "$EVENTS_FILE" 'db reset --db-url'
assert_not_contains "$EVENTS_FILE" 'db reset --linked'

reset_scenario current
MOCK_RESET_TOKEN_AFTER_BACKUP='reset-local-mylifegraph-changed0000000'
set +e
local_supabase_execute_guarded_reset "$ROOT_DIR" "$MOCK_RESET_TOKEN" \
  >"$TEST_ROOT/changed-during-backup.log" 2>&1
changed_during_backup_status=$?
set -e
[[ "$changed_during_backup_status" -eq 1 ]]
assert_contains "$EVENTS_FILE" 'verified backup'
assert_not_contains "$EVENTS_FILE" 'db reset'
assert_contains "$TEST_ROOT/changed-during-backup.log" \
  'database changed while the verified backup was created'

for integrated_script in \
  scripts/e2e_web.sh \
  scripts/verify_supabase_local.sh \
  scripts/start_local_stack.sh; do
  assert_contains "$ROOT_DIR/$integrated_script" \
    'source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"'
  assert_contains "$ROOT_DIR/$integrated_script" \
    'local_supabase_prepare_migration_state'
done

assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'source "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh"'
assert_contains "$ROOT_DIR/scripts/reset_local_supabase.sh" \
  'local_supabase_execute_guarded_reset'
assert_contains "$ROOT_DIR/scripts/backup_local_supabase.sh" \
  'local_supabase_create_verified_backup'
assert_contains "$ROOT_DIR/package.json" \
  '"db:backup:local": "bash scripts/backup_local_supabase.sh"'
assert_contains "$ROOT_DIR/package.json" \
  '"db:reset:local": "bash scripts/reset_local_supabase.sh"'

direct_reset_calls="$TEST_ROOT/direct-reset-calls"
rg -n --glob '!test_local_supabase_migrations.sh' \
  '^[[:space:]]*supabase_cli db reset --local([[:space:]]|$)' \
  "$ROOT_DIR/scripts" >"$direct_reset_calls"
[[ "$(wc -l <"$direct_reset_calls")" -eq 1 ]]
assert_contains "$direct_reset_calls" \
  'scripts/lib/local_supabase_database_safety.sh:'
assert_contains "$direct_reset_calls" 'supabase_cli db reset --local'
if rg -n --glob '!test_local_supabase_migrations.sh' \
  'db reset --(db-url|linked)' \
  "$ROOT_DIR/scripts" "$ROOT_DIR/.github" >"$TEST_ROOT/unsafe-reset-targets"; then
  printf '%s\n' 'Unsafe Supabase reset target found:' >&2
  sed -n '1,120p' "$TEST_ROOT/unsafe-reset-targets" >&2
  exit 1
fi

printf 'local Supabase migration safety tests passed\n'
