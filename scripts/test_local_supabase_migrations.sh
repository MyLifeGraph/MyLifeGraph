#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"

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
    'db reset')
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

reset_scenario divergent
local_supabase_prepare_migration_state true false true \
  >"$TEST_ROOT/reset.log" 2>&1
assert_contains "$EVENTS_FILE" 'db reset'
assert_contains "$EVENTS_FILE" 'migration list --local'
assert_contains "$TEST_ROOT/reset.log" 'destroys and recreates the local Supabase database'

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
set -e
[[ "$conflict_status" -eq 2 ]]
[[ "$invalid_status" -eq 2 ]]
[[ "$reset_forbidden_status" -eq 2 ]]
[[ ! -s "$EVENTS_FILE" ]]
assert_contains "$TEST_ROOT/conflict.log" 'mutually exclusive'
assert_contains "$TEST_ROOT/invalid.log" 'must be exactly true or false'
assert_contains "$TEST_ROOT/reset-forbidden.log" 'this command never resets the database'

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

for integrated_script in \
  scripts/e2e_web.sh \
  scripts/verify_supabase_local.sh \
  scripts/start_local_stack.sh; do
  assert_contains "$ROOT_DIR/$integrated_script" \
    'source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"'
  assert_contains "$ROOT_DIR/$integrated_script" \
    'local_supabase_prepare_migration_state'
done

printf 'local Supabase migration safety tests passed\n'
