#!/usr/bin/env bash

# Physically isolated transition verification for the two-step Goal retirement
# migration. The caller provides `supabase_cli`, sources
# local_supabase_database_safety.sh, and starts the normal local stack first.
# The normal Postgres container is read only for an exact history checksum; all
# fixtures, locks, migration writes, and pgTAP assertions run in a separate
# labelled RAM-only container with no host volume.

goal_removal_harness_sanitize_output() {
  sed -E \
    -e 's#postgres(ql)?://[^[:space:]]+#postgresql://<redacted>#g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

run_goal_removal_migration_harness() (
  set -euo pipefail

  local root_dir="$1"
  local database_name='mylifegraph_goal_removal_migration_test'
  local pre_goal_version='20260804102409'
  local original_version='20260804150153'
  local followup_version='20260804192406'
  local original_file
  local followup_file
  local fixture_file
  local between_fixture_file
  local assertions_file
  local bootstrap_file
  local database_container
  local test_url
  local normal_history_before
  local normal_history_after
  local harness_root
  local stage_root
  local migration_file
  local migration_name
  local blocker_pid=

  if ! declare -F isolated_postgres_start >/dev/null 2>&1 ||
    ! declare -F isolated_postgres_stop >/dev/null 2>&1; then
    printf '%s\n' \
      'Goal-removal harness requires local_supabase_database_safety.sh.' >&2
    return 2
  fi
  if [[ "$database_name" != 'mylifegraph_goal_removal_migration_test' ]]; then
    printf '%s\n' 'Goal-removal harness refused an unexpected database name.' >&2
    return 2
  fi

  original_file="$root_dir/supabase/migrations/${original_version}_remove_goals_and_make_weekly_review_observational.sql"
  followup_file="$root_dir/supabase/migrations/${followup_version}_harden_goal_removal_dependencies.sql"
  fixture_file="$root_dir/supabase/migration_tests/goal_removal/before_fixture.sql"
  between_fixture_file="$root_dir/supabase/migration_tests/goal_removal/between_fixture.sql"
  assertions_file="$root_dir/supabase/migration_tests/goal_removal/assertions.sql"
  bootstrap_file="$root_dir/supabase/migration_tests/goal_removal/bootstrap.sql"
  for required_file in \
    "$original_file" \
    "$followup_file" \
    "$fixture_file" \
    "$between_fixture_file" \
    "$assertions_file" \
    "$bootstrap_file"; do
    if [[ ! -f "$required_file" ]]; then
      printf 'Goal-removal harness file is missing: %s\n' "$required_file" >&2
      return 2
    fi
  done

  local_supabase_assert_exact_database_target "$root_dir" || return $?
  normal_history_before="$(
    docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
      -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
      -c "select coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations"
  )"

  harness_root="$(mktemp -d /tmp/mylifegraph-goal-removal-harness.XXXXXX)"
  stage_root="$harness_root/stage"
  mkdir -p "$stage_root/supabase/migrations"
  cp "$root_dir/supabase/config.toml" "$stage_root/supabase/config.toml"

  cleanup_goal_removal_harness() {
    local cleanup_status=$?
    if [[ -n "$blocker_pid" ]]; then
      kill "$blocker_pid" 2>/dev/null || true
      wait "$blocker_pid" 2>/dev/null || true
    fi
    isolated_postgres_stop || true
    rm -rf "$harness_root"
    return "$cleanup_status"
  }
  trap cleanup_goal_removal_harness EXIT

  isolated_postgres_start \
    "$root_dir" \
    'goal-removal-migration-test' \
    "$database_name"
  database_container="$ISOLATED_POSTGRES_CONTAINER"
  test_url="$ISOLATED_POSTGRES_URL"

  printf '%s\n' \
    "Goal-removal transition target is physically isolated in ${database_container}."
  if ! docker exec -i "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$bootstrap_file" >"$harness_root/bootstrap.log" 2>&1; then
    goal_removal_harness_sanitize_output <"$harness_root/bootstrap.log" >&2
    return 1
  fi

  assert_normal_history_unchanged() {
    local stage="$1"
    normal_history_after="$(
      docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
        -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
        -c "select coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations"
    )"
    if [[ "$normal_history_after" != "$normal_history_before" ]]; then
      printf 'Goal-removal harness detected normal migration-history drift after %s.\n' \
        "$stage" >&2
      return 1
    fi
  }

  for migration_file in "$root_dir"/supabase/migrations/*.sql; do
    migration_name="$(basename "$migration_file")"
    if [[ "$migration_name" < "${original_version}_" ]]; then
      cp "$migration_file" "$stage_root/supabase/migrations/$migration_name"
    fi
  done

  printf '%s\n' \
    "Initializing isolated ${database_name} through migration ${pre_goal_version}."
  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/pre-goal.log" 2>&1; then
    goal_removal_harness_sanitize_output <"$harness_root/pre-goal.log" >&2
    return 1
  fi
  assert_normal_history_unchanged 'pre-Goal bootstrap'
  if [[ "$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c 'select max(version) from supabase_migrations.schema_migrations')" \
      != "$pre_goal_version" ]]; then
    printf '%s\n' \
      'Goal-removal harness did not reach the requested isolated version.' >&2
    return 1
  fi

  if ! docker exec -i "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$fixture_file" >"$harness_root/before-fixture.log" 2>&1; then
    goal_removal_harness_sanitize_output \
      <"$harness_root/before-fixture.log" >&2
    return 1
  fi

  cp "$original_file" \
    "$stage_root/supabase/migrations/$(basename "$original_file")"
  printf '%s\n' "Applying original Goal migration ${original_version} in isolation."
  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/original.log" 2>&1; then
    goal_removal_harness_sanitize_output <"$harness_root/original.log" >&2
    return 1
  fi
  assert_normal_history_unchanged 'the original Goal migration'

  if ! docker exec -i "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$between_fixture_file" >"$harness_root/between-fixture.log" 2>&1; then
    goal_removal_harness_sanitize_output \
      <"$harness_root/between-fixture.log" >&2
    return 1
  fi
  cp "$followup_file" \
    "$stage_root/supabase/migrations/$(basename "$followup_file")"

  # Hold a genuine writer lock in a second session. The first follow-up attempt
  # must hit its five-second lock_timeout and leave fixtures/history unchanged.
  docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    -c "begin; update public.tasks set metadata = metadata where id = 'e2000000-0000-4000-8000-000000000201'; select pg_sleep(8); rollback" \
    >"$harness_root/blocker.log" 2>&1 &
  blocker_pid=$!

  local lock_ready=false
  local attempt
  for attempt in $(seq 1 50); do
    if [[ "$(docker exec "$database_container" psql \
      -U postgres -d "$database_name" -X -At \
      -c "select count(*) from pg_locks where relation = 'public.tasks'::regclass and mode = 'RowExclusiveLock' and granted")" -ge 1 ]]; then
      lock_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$lock_ready" != 'true' ]]; then
    printf '%s\n' 'Goal-removal harness did not observe the writer lock.' >&2
    return 1
  fi

  set +e
  supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/locked-migration.log" 2>&1
  local locked_status=$?
  set -e
  if [[ "$locked_status" -eq 0 ]]; then
    printf '%s\n' 'Goal-removal migration unexpectedly passed under a writer lock.' >&2
    return 1
  fi
  if ! grep -Eqi 'lock timeout|canceling statement due to lock timeout' \
    "$harness_root/locked-migration.log"; then
    goal_removal_harness_sanitize_output \
      <"$harness_root/locked-migration.log" >&2
    printf '%s\n' 'Goal-removal migration failed for an unexpected reason.' >&2
    return 1
  fi

  local rollback_state
  rollback_state="$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select concat_ws('|', (select count(*) from supabase_migrations.schema_migrations where version = '${followup_version}'), (select count(*) from public.tasks where id = 'e2000000-0000-4000-8000-000000000201' and metadata #>> '{legacy_ref,field}' = 'metadata.goal_id'), (select count(*) from pg_proc where pronamespace = 'private'::regnamespace and proname in ('goal_path_references_feature_v2','is_goal_reference_object_v2','references_goal_feature_v2','sanitize_goal_feature_v2','references_doomed_goal_record_v2','remove_goal_derived_history_v2')))"
  )"
  if [[ "$rollback_state" != '0|1|0' ]]; then
    printf 'Goal-removal lock rollback assertion failed: %s\n' \
      "$rollback_state" >&2
    return 1
  fi
  assert_normal_history_unchanged 'the expected lock timeout'

  wait "$blocker_pid"
  blocker_pid=

  printf '%s\n' \
    "Re-applying follow-up Goal migration ${followup_version} after lock release."
  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/followup.log" 2>&1; then
    goal_removal_harness_sanitize_output <"$harness_root/followup.log" >&2
    return 1
  fi
  assert_normal_history_unchanged 'the follow-up Goal migration'

  printf '%s\n' 'Running isolated Goal-removal pgTAP assertions.'
  if ! supabase_cli test db \
    --db-url "$test_url" \
    --workdir "$root_dir" \
    "$assertions_file" \
    >"$harness_root/assertions.log" 2>&1; then
    goal_removal_harness_sanitize_output <"$harness_root/assertions.log" >&2
    return 1
  fi
  goal_removal_harness_sanitize_output <"$harness_root/assertions.log"
  assert_normal_history_unchanged 'isolated pgTAP'
  printf '%s\n' 'Physically isolated Goal-removal migration harness passed.'
)
