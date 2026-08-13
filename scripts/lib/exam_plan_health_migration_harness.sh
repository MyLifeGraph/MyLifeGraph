#!/usr/bin/env bash

# Full-chain verification for the additive Exam Plan Health snapshot RPC.
# The normal local database is inspected only for an exact history checksum;
# every migration and assertion runs in an ownership-labelled RAM-only
# Postgres container with no host volume.

exam_plan_health_harness_sanitize_output() {
  sed -E \
    -e 's#postgres(ql)?://[^[:space:]]+#postgresql://<redacted>#g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

run_exam_plan_health_migration_harness() (
  set -euo pipefail

  local root_dir="$1"
  local database_name='mylifegraph_exam_health_migration_test'
  local bootstrap_file="$root_dir/supabase/migration_tests/goal_removal/bootstrap.sql"
  local assertions_file="$root_dir/supabase/tests/exam_plan_health_v1_test.sql"
  local migration_file="$root_dir/supabase/migrations/20260813040200_exam_plan_health_v1.sql"
  local harness_root
  local database_container
  local test_url
  local normal_history_before
  local normal_history_after
  local normal_history_guarded=false

  assert_exam_health_normal_history_unchanged() {
    local stage="$1"
    normal_history_after="$(
      docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
        -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
        -c "select coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations"
    )"
    if [[ "$normal_history_after" != "$normal_history_before" ]]; then
      printf 'Exam-health harness detected normal migration-history drift after %s.\n' \
        "$stage" >&2
      return 1
    fi
  }

  if ! declare -F isolated_postgres_start >/dev/null 2>&1 ||
    ! declare -F isolated_postgres_stop >/dev/null 2>&1; then
    printf '%s\n' \
      'Exam-health harness requires local_supabase_database_safety.sh.' >&2
    return 2
  fi
  if [[ "$database_name" != 'mylifegraph_exam_health_migration_test' ]]; then
    printf '%s\n' 'Exam-health harness refused an unexpected database name.' >&2
    return 2
  fi
  for required_file in "$bootstrap_file" "$assertions_file" "$migration_file"; do
    if [[ ! -f "$required_file" ]]; then
      printf 'Exam-health harness file is missing: %s\n' "$required_file" >&2
      return 2
    fi
  done

  local_supabase_assert_exact_database_target "$root_dir" || return $?
  normal_history_before="$(
    docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
      -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
      -c "select coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations"
  )"

  harness_root="$(mktemp -d /tmp/mylifegraph-exam-health-harness.XXXXXX)"
  cleanup_exam_plan_health_harness() {
    local cleanup_status=$?
    if [[ "$normal_history_guarded" == true ]]; then
      assert_exam_health_normal_history_unchanged 'harness exit' || \
        cleanup_status=1
    fi
    isolated_postgres_stop || true
    rm -rf "$harness_root"
    return "$cleanup_status"
  }
  trap cleanup_exam_plan_health_harness EXIT
  normal_history_guarded=true

  isolated_postgres_start \
    "$root_dir" \
    'exam-health-migration-test' \
    "$database_name"
  database_container="$ISOLATED_POSTGRES_CONTAINER"
  test_url="$ISOLATED_POSTGRES_URL"

  printf '%s\n' \
    "Exam-health full-chain target is isolated in ${database_container}."
  if ! docker exec -i "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$bootstrap_file" >"$harness_root/bootstrap.log" 2>&1; then
    exam_plan_health_harness_sanitize_output \
      <"$harness_root/bootstrap.log" >&2
    return 1
  fi

  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$root_dir" \
    >"$harness_root/migrations.log" 2>&1; then
    exam_plan_health_harness_sanitize_output \
      <"$harness_root/migrations.log" >&2
    return 1
  fi
  assert_exam_health_normal_history_unchanged 'full-chain migration'

  if [[ "$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select count(*) from supabase_migrations.schema_migrations where version = '20260813040200'")" \
      != '1' ]]; then
    printf '%s\n' \
      'Exam-health harness did not apply the Exam Plan Health migration.' >&2
    return 1
  fi

  printf '%s\n' 'Running isolated Exam Plan Health pgTAP assertions.'
  if ! supabase_cli test db \
    --db-url "$test_url" \
    --workdir "$root_dir" \
    "$assertions_file" \
    >"$harness_root/assertions.log" 2>&1; then
    exam_plan_health_harness_sanitize_output \
      <"$harness_root/assertions.log" >&2
    return 1
  fi
  exam_plan_health_harness_sanitize_output <"$harness_root/assertions.log"
  assert_exam_health_normal_history_unchanged 'pgTAP assertions'
  printf '%s\n' 'Physically isolated Exam Plan Health full-chain harness passed.'
)
