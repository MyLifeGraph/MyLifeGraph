#!/usr/bin/env bash

# Physically isolated transition proof for Recommendation and Decision Feedback
# retirement. The normal local Postgres is read only for its migration-history
# SHA-256 over complete ordered version/name/statements facts; fixtures, lock
# contention, migration writes, and pgTAP run in a labelled RAM-only container
# with no host database volume.

recommendation_retirement_harness_sanitize_output() {
  sed -E \
    -e 's#postgres(ql)?://[^[:space:]]+#postgresql://<redacted>#g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

run_recommendation_retirement_migration_harness() (
  set -euo pipefail

  local root_dir="$1"
  local database_name='mylifegraph_recommendation_retirement_test'
  local target_version='20260813200057'
  local pre_target_version='20260813081814'
  local target_file
  local fixture_file
  local assertions_file
  local bootstrap_file
  local database_container
  local test_url
  local normal_history_hash_before
  local normal_history_hash_after
  local normal_history_hash_query
  local retained_notification_hash_before
  local retained_notification_hash_after
  local harness_root
  local stage_root
  local migration_file
  local migration_name
  local blocker_pid=

  if ! declare -F isolated_postgres_start >/dev/null 2>&1 ||
    ! declare -F isolated_postgres_stop >/dev/null 2>&1; then
    printf '%s\n' \
      'Recommendation-retirement harness requires database safety helpers.' >&2
    return 2
  fi
  if [[ "$database_name" != 'mylifegraph_recommendation_retirement_test' ]]; then
    printf '%s\n' \
      'Recommendation-retirement harness refused an unexpected database name.' >&2
    return 2
  fi

  target_file="$root_dir/supabase/migrations/${target_version}_retire_recommendations_and_decision_feedback.sql"
  fixture_file="$root_dir/supabase/migration_tests/recommendation_retirement/before_fixture.sql"
  assertions_file="$root_dir/supabase/migration_tests/recommendation_retirement/assertions.sql"
  bootstrap_file="$root_dir/supabase/migration_tests/goal_removal/bootstrap.sql"
  for required_file in \
    "$target_file" "$fixture_file" "$assertions_file" "$bootstrap_file"; do
    if [[ ! -f "$required_file" ]]; then
      printf 'Recommendation-retirement harness file is missing: %s\n' \
        "$required_file" >&2
      return 2
    fi
  done

  local_supabase_assert_exact_database_target "$root_dir" || return $?
  normal_history_hash_query="
    select encode(
      extensions.digest(
        convert_to(
          coalesce(
            jsonb_agg(
              jsonb_build_object(
                'version', version,
                'name', name,
                'statements', statements
              ) order by version, name, statements
            ),
            '[]'::jsonb
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
    from supabase_migrations.schema_migrations
  "
  recommendation_normal_history_hash() {
    docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
      -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
      -c "$normal_history_hash_query"
  }
  normal_history_hash_before="$(recommendation_normal_history_hash)"
  if [[ ! "$normal_history_hash_before" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s\n' \
      'Recommendation-retirement harness could not hash normal history.' >&2
    return 2
  fi

  assert_recommendation_normal_history_unchanged() {
    local stage="$1"
    normal_history_hash_after="$(recommendation_normal_history_hash)"
    if [[ "$normal_history_hash_after" != "$normal_history_hash_before" ]]; then
      printf 'Recommendation-retirement harness detected complete normal history drift after %s.\n' \
        "$stage" >&2
      return 1
    fi
  }

  harness_root="$(mktemp -d /tmp/mylifegraph-recommendation-retirement.XXXXXX)"
  stage_root="$harness_root/stage"
  mkdir -p "$stage_root/supabase/migrations"
  cp "$root_dir/supabase/config.toml" "$stage_root/supabase/config.toml"

  cleanup_recommendation_retirement_harness() {
    local cleanup_status=$?
    if [[ -n "$blocker_pid" ]]; then
      kill "$blocker_pid" 2>/dev/null || true
      wait "$blocker_pid" 2>/dev/null || true
    fi
    isolated_postgres_stop || true
    rm -rf "$harness_root"
    return "$cleanup_status"
  }
  trap cleanup_recommendation_retirement_harness EXIT

  isolated_postgres_start \
    "$root_dir" \
    'recommendation-retirement-test' \
    "$database_name"
  database_container="$ISOLATED_POSTGRES_CONTAINER"
  test_url="$ISOLATED_POSTGRES_URL"
  printf '%s\n' \
    "Recommendation-retirement target is isolated in ${database_container}."

  if ! docker exec -i "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$bootstrap_file" >"$harness_root/bootstrap.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/bootstrap.log" >&2
    return 1
  fi
  for migration_file in "$root_dir"/supabase/migrations/*.sql; do
    migration_name="$(basename "$migration_file")"
    if [[ "$migration_name" < "${target_version}_" ]]; then
      cp "$migration_file" "$stage_root/supabase/migrations/$migration_name"
    fi
  done

  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/pre-target.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/pre-target.log" >&2
    return 1
  fi
  assert_recommendation_normal_history_unchanged 'pre-target bootstrap'
  if [[ "$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c 'select max(version) from supabase_migrations.schema_migrations')" \
      != "$pre_target_version" ]]; then
    printf '%s\n' \
      'Recommendation-retirement harness reached an unexpected pre-target version.' >&2
    return 1
  fi

  if ! docker exec -i "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$fixture_file" >"$harness_root/fixture.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/fixture.log" >&2
    return 1
  fi
  retained_notification_hash_before="$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select encode(extensions.digest(convert_to(to_jsonb(notification)::text, 'UTF8'), 'sha256'), 'hex') from public.notifications as notification where id = 'f7000000-0000-4000-8000-000000000603'")"
  if [[ ! "$retained_notification_hash_before" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s\n' \
      'Recommendation-retirement retained-notification fixture is missing.' >&2
    return 1
  fi

  cp "$target_file" "$stage_root/supabase/migrations/$(basename "$target_file")"

  docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    -c "begin; update public.tasks set metadata = metadata where id = 'f7000000-0000-4000-8000-000000000201'; select pg_sleep(8); rollback" \
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
    printf '%s\n' \
      'Recommendation-retirement harness did not observe the writer lock.' >&2
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
    printf '%s\n' \
      'Recommendation-retirement migration passed under a writer lock.' >&2
    return 1
  fi
  if ! rg -qi 'SQLSTATE[[:space:]]+55P03' \
    "$harness_root/locked-migration.log"; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/locked-migration.log" >&2
    printf '%s\n' \
      'Recommendation-retirement lock attempt failed unexpectedly.' >&2
    return 1
  fi

  local rollback_state
  rollback_state="$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select concat_ws('|', (select count(*) from supabase_migrations.schema_migrations where version = '${target_version}'), to_regclass('public.recommendations') is not null, (select count(*) from public.daily_briefings where id = 'f7000000-0000-4000-8000-000000000411'), (select count(*) from public.weekly_reviews where id = 'f7000000-0000-4000-8000-000000000501'), (select count(*) from public.coach_usage_events where request_id = 'f7000000-0000-4000-8000-000000000801'), (select metadata ? 'recommendation_id' from public.tasks where id = 'f7000000-0000-4000-8000-000000000201'), to_regprocedure('private.references_retired_recommendation_v1(jsonb)') is null, to_regprocedure('private.sanitize_retired_recommendation_v1(jsonb)') is null, to_regprocedure('public.claim_coach_request_v6(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)') is null, to_regprocedure('public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)') is null, (select count(*) from pg_constraint where conname in ('daily_briefings_v2_sources', 'weekly_reviews_retired_sources')))"
  )"
  if [[ "$rollback_state" != '0|t|1|1|1|t|t|t|t|t|0' ]]; then
    printf 'Recommendation-retirement rollback assertion failed: %s\n' \
      "$rollback_state" >&2
    return 1
  fi
  assert_recommendation_normal_history_unchanged 'expected lock timeout'

  wait "$blocker_pid"
  blocker_pid=

  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/target.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/target.log" >&2
    return 1
  fi
  assert_recommendation_normal_history_unchanged 'successful target migration'

  if [[ "$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select count(*) from supabase_migrations.schema_migrations where version = '${target_version}'")" \
      != '1' ]]; then
    printf '%s\n' \
      'Recommendation-retirement migration was not recorded once.' >&2
    return 1
  fi

  retained_notification_hash_after="$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select encode(extensions.digest(convert_to(to_jsonb(notification)::text, 'UTF8'), 'sha256'), 'hex') from public.notifications as notification where id = 'f7000000-0000-4000-8000-000000000603'")"
  if [[ "$retained_notification_hash_after" != \
    "$retained_notification_hash_before" ]]; then
    printf '%s\n' \
      'Recommendation-retirement changed a retained generated notification.' >&2
    return 1
  fi

  printf '%s\n' 'Running isolated Recommendation-retirement pgTAP assertions.'
  if ! supabase_cli test db \
    --db-url "$test_url" \
    --workdir "$root_dir" \
    "$assertions_file" \
    >"$harness_root/assertions.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/assertions.log" >&2
    return 1
  fi
  recommendation_retirement_harness_sanitize_output \
    <"$harness_root/assertions.log"
  assert_recommendation_normal_history_unchanged 'transition assertions'

  # The transition proof stops at its historical target. Add every later
  # immutable migration before the shared final-state pgTAP corpus so new
  # contracts are tested without weakening the transition fixture.
  for migration_file in "$root_dir"/supabase/migrations/*.sql; do
    migration_name="$(basename "$migration_file")"
    if [[ "$migration_name" > "${target_version}_" ]]; then
      cp "$migration_file" "$stage_root/supabase/migrations/$migration_name"
    fi
  done
  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/post-target.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/post-target.log" >&2
    return 1
  fi
  assert_recommendation_normal_history_unchanged 'post-target migrations'

  # The normal Supabase Postgres session exposes extensions after public
  # (`show search_path` => "$user", public, extensions). Mirror that database
  # default only inside this disposable container before running the shared
  # pgTAP corpus, whose historical fixtures intentionally call crypt/gen_salt
  # without schema qualification.
  docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    -c 'alter database mylifegraph_recommendation_retirement_test set search_path = "$user", public, extensions' \
    >"$harness_root/search-path.log" 2>&1
  printf '%s\n' \
    'Running the complete pgTAP suite against the isolated final state.'
  if ! supabase_cli test db \
    --db-url "$test_url" \
    --workdir "$root_dir" \
    >"$harness_root/full-pgtap.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/full-pgtap.log" >&2
    return 1
  fi
  recommendation_retirement_harness_sanitize_output \
    <"$harness_root/full-pgtap.log"
  assert_recommendation_normal_history_unchanged 'complete pgTAP suite'
  printf '%s\n' \
    'Physically isolated Recommendation-retirement harness passed.'
)
