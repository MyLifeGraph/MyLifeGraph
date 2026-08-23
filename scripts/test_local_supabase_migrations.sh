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

for recognized_image in \
  'public.ecr.aws/supabase/postgres:17.6.1.113' \
  'ghcr.io/supabase/postgres:17.6.1.113'; do
  if ! local_supabase_is_recognized_postgres_image "$recognized_image"; then
    printf 'Expected recognized Supabase Postgres image: %s\n' \
      "$recognized_image" >&2
    exit 1
  fi
done

for rejected_image in \
  'docker.io/supabase/postgres:17.6.1.113' \
  'ghcr.io/other/postgres:17.6.1.113' \
  'ghcr.io/supabase/postgres' \
  'ghcr.io/supabase/postgres:17.6.1.113@sha256:unsafe'; do
  if local_supabase_is_recognized_postgres_image "$rejected_image"; then
    printf 'Unexpectedly recognized Supabase Postgres image: %s\n' \
      "$rejected_image" >&2
    exit 1
  fi
done

assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'if ! local_supabase_is_recognized_postgres_image "$requested_image"; then'
assert_not_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'if [[ ! "$requested_image" =~ ^public\.ecr\.aws/supabase/postgres:'

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
marker_free_dump=$'COPY public.profiles (id) FROM stdin;\n00000000-0000-0000-0000-000000000001\n\\.'
normalized_marker_free_dump="$(
  printf '%s' "$marker_free_dump" |
    local_supabase_normalize_protected_data_dump
)"
[[ "$normalized_marker_free_dump" == "$marker_free_dump" ]]

normalized_dump_a="$(
  printf '%s\n' \
    '\restrict Alpha123' \
    'COPY public.profiles (id) FROM stdin;' \
    '00000000-0000-0000-0000-000000000001' \
    '\.' \
    '\unrestrict Alpha123' |
    local_supabase_normalize_protected_data_dump
)"
normalized_dump_b="$(
  printf '%s\n' \
    '\restrict Beta456' \
    'COPY public.profiles (id) FROM stdin;' \
    '00000000-0000-0000-0000-000000000001' \
    '\.' \
    '\unrestrict Beta456' |
    local_supabase_normalize_protected_data_dump
)"
[[ "$normalized_dump_a" == "$normalized_dump_b" ]]
assert_not_contains <(printf '%s\n' "$normalized_dump_a") '\restrict'
assert_not_contains <(printf '%s\n' "$normalized_dump_a") '\unrestrict'

declare -a malformed_restrict_cases=(
  'missing-close'
  'mismatched-nonce'
  'reversed-pair'
  'duplicate-pair'
  'invalid-nonce'
  'noncanonical-spacing'
)
for malformed_restrict_case in "${malformed_restrict_cases[@]}"; do
  case "$malformed_restrict_case" in
    missing-close)
      malformed_restrict_input=$'\\restrict Alpha123\nSELECT 1;'
      ;;
    mismatched-nonce)
      malformed_restrict_input=$'\\restrict Alpha123\nSELECT 1;\n\\unrestrict Beta456'
      ;;
    reversed-pair)
      malformed_restrict_input=$'\\unrestrict Alpha123\nSELECT 1;\n\\restrict Alpha123'
      ;;
    duplicate-pair)
      malformed_restrict_input=$'\\restrict Alpha123\n\\unrestrict Alpha123\n\\restrict Beta456\n\\unrestrict Beta456'
      ;;
    invalid-nonce)
      malformed_restrict_input=$'\\restrict invalid-token\n\\unrestrict invalid-token'
      ;;
    noncanonical-spacing)
      malformed_restrict_input=$' \\restrict Alpha123\n\\unrestrict Alpha123 '
      ;;
  esac
  set +e
  printf '%s\n' "$malformed_restrict_input" |
    local_supabase_normalize_protected_data_dump \
      >"$TEST_ROOT/malformed-restrict-$malformed_restrict_case.log" 2>&1
  malformed_restrict_status=$?
  set -e
  [[ "$malformed_restrict_status" -eq 65 ]]
  assert_contains \
    "$TEST_ROOT/malformed-restrict-$malformed_restrict_case.log" \
    'malformed pg_dump restrict marker pair'
done

MOCK_RESET_TOKEN='reset-local-mylifegraph-0123456789abcdef'
MOCK_RESET_TOKEN_AFTER_BACKUP="$MOCK_RESET_TOKEN"

local_supabase_capture_reset_facts() {
  LOCAL_SUPABASE_SAFETY_PROJECT_ID='mylifegraph'
  LOCAL_SUPABASE_SAFETY_CONTAINER='supabase_db_mylifegraph'
  LOCAL_SUPABASE_RESET_DATABASE='postgres'
  LOCAL_SUPABASE_RESET_AUTH_USERS='4'
  LOCAL_SUPABASE_RESET_PROFILES='4'
  LOCAL_SUPABASE_RESET_DATABASE_BYTES='123456'
  LOCAL_SUPABASE_RESET_LATEST_MIGRATION='20260804192406'
  LOCAL_SUPABASE_RESET_PROTECTED_DATA_SHA256='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
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
  'source "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'run_goal_removal_migration_harness "$ROOT_DIR"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'source "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'run_exam_plan_health_migration_harness "$ROOT_DIR"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'source "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'public.ecr.aws/supabase/postgres:15.8.1.085'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'public.ecr.aws/supabase/postgres:17.6.1.113'
assert_contains "$ROOT_DIR/.github/workflows/ci.yml" \
  'docker pull public.ecr.aws/supabase/postgres:15.8.1.085'
assert_contains "$ROOT_DIR/.github/workflows/ci.yml" \
  'docker pull public.ecr.aws/supabase/postgres:17.6.1.113'
assert_contains "$ROOT_DIR/supabase/config.toml" \
  'major_version = 17'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'source "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh"'
assert_not_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'start_output='
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'mktemp "${TMPDIR:-/tmp}/mylifegraph-supabase-start.XXXXXX"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'chmod 600 "$start_log"'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'trap cleanup_start_log EXIT'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  'tail -n "$SUPABASE_START_FAILURE_TAIL_LINES" "$start_log" |'
assert_contains "$ROOT_DIR/scripts/verify_supabase_local.sh" \
  "Supabase local stack started."
assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  '(public\.ecr\.aws|ghcr\.io)/supabase/postgres:'
assert_contains "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh" \
  'isolated_postgres_start'
assert_contains "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh" \
  "grep -Eqi 'lock timeout|canceling statement due to lock timeout'"
assert_not_contains "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh" \
  "rg -qi 'lock timeout|canceling statement due to lock timeout'"
assert_not_contains "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh" \
  'db reset --db-url'
assert_not_contains "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh" \
  'create database'
assert_not_contains "$ROOT_DIR/scripts/lib/goal_removal_migration_harness.sh" \
  'drop database'
assert_contains "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  'isolated_postgres_start'
assert_contains "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  'supabase_cli migration up'
assert_not_contains "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  'db reset'
assert_not_contains "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  'create database'
assert_not_contains "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  'drop database'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'isolated_postgres_start'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'supabase_cli migration up'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  "bootstrap_user='mylifegraph_pg17_bootstrap'"
assert_contains \
  "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  "bootstrap_user='mylifegraph_exam_health_bootstrap'"
assert_contains \
  "$ROOT_DIR/scripts/lib/exam_plan_health_migration_harness.sh" \
  'create role postgres login nosuperuser nocreatedb createrole'
assert_contains \
  "$ROOT_DIR/scripts/lib/multi_exam_plan_migration_harness.sh" \
  "bootstrap_user='mylifegraph_multi_exam_bootstrap'"
assert_contains \
  "$ROOT_DIR/scripts/lib/multi_exam_plan_migration_harness.sh" \
  'create role postgres login nosuperuser nocreatedb createrole'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'membership.grantor=10'
assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'required local image is absent'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  "grep -Eqi 'SQLSTATE[[:space:]]+55P03'"
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'grep -Fq'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'Account deletion replayer role has unsafe attributes'
assert_not_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'rg -q'
assert_not_contains \
  "$ROOT_DIR/scripts/lib/coach_operator_concurrency_harness.sh" \
  'rg -q'
assert_not_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'rg -q'
assert_not_contains "$ROOT_DIR/scripts/backup_local_supabase.sh" \
  'sha256sum rg'
assert_not_contains "$ROOT_DIR/scripts/reset_local_supabase.sh" \
  'sha256sum rg'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  "'version', version"
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  "'name', name"
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  "'statements', statements"
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  ') order by version, name, statements'
assert_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  "'sha256'"
assert_not_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'string_agg(version'
assert_not_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'db reset'
assert_not_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'create database'
assert_not_contains \
  "$ROOT_DIR/scripts/lib/recommendation_retirement_migration_harness.sh" \
  'drop database'
assert_contains "$ROOT_DIR/supabase/migration_tests/goal_removal/bootstrap.sql" \
  'alter role service_role bypassrls;'
assert_contains "$ROOT_DIR/supabase/migration_tests/goal_removal/bootstrap.sql" \
  'grant usage on schema extensions to anon, authenticated, service_role;'
assert_contains "$ROOT_DIR/scripts/reset_local_supabase.sh" \
  'local_supabase_execute_guarded_reset'
assert_contains "$ROOT_DIR/scripts/backup_local_supabase.sh" \
  'local_supabase_create_verified_backup'
assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  '--schema=auth --schema=private --schema=public --schema=storage'
assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  '--schema=supabase_migrations'
assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'local_supabase_normalize_protected_data_dump'
assert_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'protected_data_sha256='
assert_not_contains "$ROOT_DIR/scripts/lib/local_supabase_database_safety.sh" \
  'pg_current_wal_lsn'
assert_contains "$ROOT_DIR/package.json" \
  '"db:backup:local": "bash scripts/backup_local_supabase.sh"'
assert_contains "$ROOT_DIR/package.json" \
  '"db:reset:local": "bash scripts/reset_local_supabase.sh"'

direct_reset_calls="$TEST_ROOT/direct-reset-calls"
grep -RInE --exclude='test_local_supabase_migrations.sh' \
  '^[[:space:]]*supabase_cli db reset --local([[:space:]]|$)' \
  "$ROOT_DIR/scripts" >"$direct_reset_calls"
[[ "$(wc -l <"$direct_reset_calls")" -eq 1 ]]
assert_contains "$direct_reset_calls" \
  'scripts/lib/local_supabase_database_safety.sh:'
assert_contains "$direct_reset_calls" 'supabase_cli db reset --local'
if grep -RInE --exclude='test_local_supabase_migrations.sh' \
  'db reset --(db-url|linked)' \
  "$ROOT_DIR/scripts" "$ROOT_DIR/.github" >"$TEST_ROOT/unsafe-reset-targets"; then
  printf '%s\n' 'Unsafe Supabase reset target found:' >&2
  sed -n '1,120p' "$TEST_ROOT/unsafe-reset-targets" >&2
  exit 1
fi

printf 'local Supabase migration safety tests passed\n'
