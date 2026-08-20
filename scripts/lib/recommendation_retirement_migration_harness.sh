#!/usr/bin/env bash

# Physically isolated transition proof for Recommendation and Decision Feedback
# retirement. The normal local Postgres is read only for its migration-history
# SHA-256 over complete ordered version/name/statements facts; fixtures, lock
# contention, migration writes, and pgTAP run in a labelled RAM-only container
# with no host database volume.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/coach_operator_concurrency_harness.sh"

recommendation_retirement_harness_sanitize_output() {
  sed -E \
    -e 's#postgres(ql)?://[^[:space:]]+#postgresql://<redacted>#g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

run_recommendation_retirement_migration_harness() (
  set -euo pipefail

  local root_dir="$1"
  local postgres_image="${2:-}"
  local pg15_image='public.ecr.aws/supabase/postgres:15.8.1.085'
  local pg17_image='public.ecr.aws/supabase/postgres:17.6.1.113'
  local bootstrap_user='postgres'
  local purpose='recommendation-retirement-test'
  local harness_variant='default'
  local database_name='mylifegraph_recommendation_retirement_test'
  local target_version='20260813200057'
  local pre_target_version='20260813081814'
  local deletion_recovery_boundary='20260820170000_account_deletion_recovery_v2.sql'
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
  local replayer_boundary
  local expected_replayer_boundary
  local server_version_number
  local container_ip
  local pg17_dump
  local pg17_source_facts
  local pg17_restore_facts
  local blocker_pid=

  if [[ -n "$postgres_image" ]]; then
    case "$postgres_image" in
      "$pg15_image")
        purpose='recommendation-retirement-pg15'
        harness_variant='pg15'
        ;;
      "$pg17_image")
        bootstrap_user='mylifegraph_pg17_bootstrap'
        purpose='recommendation-retirement-pg17'
        harness_variant='pg17'
        ;;
      *)
        printf 'Recommendation-retirement harness refused image %q.\n' \
          "$postgres_image" >&2
        return 2
        ;;
    esac
  fi

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
    "$purpose" \
    "$database_name" \
    "$postgres_image" \
    "$bootstrap_user"
  database_container="$ISOLATED_POSTGRES_CONTAINER"
  test_url="$ISOLATED_POSTGRES_URL"
  printf '%s\n' \
    "Recommendation-retirement target is isolated in ${database_container}."

  if ! docker exec -i "$database_container" psql \
    -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$bootstrap_file" >"$harness_root/bootstrap.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/bootstrap.log" >&2
    return 1
  fi
  server_version_number="$(docker exec "$database_container" psql \
    -U "$bootstrap_user" -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select current_setting('server_version_num')")"
  if [[ ! "$server_version_number" =~ ^[0-9]+$ ]]; then
    printf '%s\n' \
      'Recommendation-retirement harness could not determine PostgreSQL version.' >&2
    return 1
  fi
  if [[ "$server_version_number" -ge 160000 ]]; then
    # Mirror hosted Supabase: the bootstrap superuser remains OID 10 while the
    # migration identity is a separate non-superuser CREATEROLE principal.
    docker exec "$database_container" psql \
      -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 \
      -c "create extension if not exists dblink with schema extensions; create role postgres login nosuperuser nocreatedb createrole inherit noreplication bypassrls connection limit -1; alter database ${database_name} owner to postgres; alter schema auth owner to postgres; alter table auth.users owner to postgres; alter function auth.uid() owner to postgres; alter function auth.role() owner to postgres; grant usage on schema extensions to postgres; grant anon, authenticated, service_role to postgres with admin option;" \
      >"$harness_root/pg17-migration-role.log" 2>&1
    container_ip="$(docker inspect \
      --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
      "$database_container")"
    if ! awk -F. '
      NF != 4 { exit 1 }
      {
        for (octet = 1; octet <= 4; octet++) {
          if ($octet !~ /^[0-9]+$/ || $octet < 0 || $octet > 255) {
            exit 1
          }
        }
      }
    ' <<<"$container_ip"; then
      printf 'Recommendation-retirement harness rejected container IP %q.\n' \
        "$container_ip" >&2
      return 1
    fi
    docker exec \
      --env "MYLIFEGRAPH_CONTAINER_SELF_IP=${container_ip}" \
      "$database_container" bash -ceu \
      'printf "host all all %s/32 scram-sha-256\n" "${MYLIFEGRAPH_CONTAINER_SELF_IP}" >>/var/lib/postgresql/data/pg_hba.conf'
    docker exec "$database_container" psql \
      -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 \
      -c 'select pg_reload_conf()' \
      >"$harness_root/pg17-hba-reload.log" 2>&1
    test_url="postgresql://postgres@127.0.0.1:${ISOLATED_POSTGRES_PORT}/${database_name}?sslmode=disable"
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

  # Reproduce the hostile upgrade shape immediately before any repository
  # migration can create the reserved restore role. Supabase's ordinary
  # migration identity is intentionally not a true superuser, so Deletion V2
  # must refuse this role before its first replay EXECUTE grant rather than
  # pretending it can normalize privileged attributes.
  docker exec -i "$database_container" psql \
    -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
create role mylifegraph_deletion_replayer
  login superuser inherit bypassrls connection limit -1;
grant service_role to mylifegraph_deletion_replayer;
grant mylifegraph_deletion_replayer to authenticated;
SQL

  # The transition proof stops at its historical target. First stop exactly at
  # Deletion V2 and require the hostile role to block the migration without
  # persisting either the migration record or the replay function/grant.
  for migration_file in "$root_dir"/supabase/migrations/*.sql; do
    migration_name="$(basename "$migration_file")"
    if [[ "$migration_name" > "${target_version}_" &&
      ( "$migration_name" < "$deletion_recovery_boundary" ||
        "$migration_name" == "$deletion_recovery_boundary" ) ]]; then
      cp "$migration_file" "$stage_root/supabase/migrations/$migration_name"
    fi
  done
  if supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/deletion-boundary.log" 2>&1; then
    printf '%s\n' \
      'Deletion V2 unexpectedly accepted a hostile pre-existing replay role.' >&2
    return 1
  fi
  if ! rg -q \
    'Account deletion replayer role has unsafe attributes' \
    "$harness_root/deletion-boundary.log"; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/deletion-boundary.log" >&2
    printf '%s\n' \
      'Deletion V2 did not fail through the expected role-attribute guard.' >&2
    return 1
  fi
  replayer_refusal="$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select concat_ws('|',(select count(*)=0 from supabase_migrations.schema_migrations where version='20260820170000'),to_regprocedure('public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)') is null,(select rolsuper from pg_roles where rolname='mylifegraph_deletion_replayer'),(select count(*) from pg_auth_members as membership join pg_roles as role on role.rolname='mylifegraph_deletion_replayer' where membership.roleid=role.oid or membership.member=role.oid))")"
  [[ "$replayer_refusal" == 't|t|t|2' ]] || {
    printf 'Deletion V2 hostile-role refusal failed: %s\n' \
      "$replayer_refusal" >&2
    return 1
  }
  assert_recommendation_normal_history_unchanged 'Deletion V2 role refusal'

  # The isolated target's actual superuser now performs the explicit trusted
  # cleanup that hosted operators would have to escalate rather than encoding
  # impossible superuser repair in an ordinary Supabase migration.
  docker exec -i "$database_container" psql \
    -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
revoke service_role from mylifegraph_deletion_replayer;
revoke mylifegraph_deletion_replayer from authenticated;
drop role mylifegraph_deletion_replayer;
SQL
  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$stage_root" \
    >"$harness_root/deletion-boundary-clean.log" 2>&1; then
    recommendation_retirement_harness_sanitize_output \
      <"$harness_root/deletion-boundary-clean.log" >&2
    return 1
  fi
  replayer_boundary="$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select concat_ws('|',(select not rolcanlogin and not rolsuper and not rolcreatedb and not rolcreaterole and not rolinherit and not rolreplication and not rolbypassrls and rolconnlimit=0 and rolconfig is null from pg_roles where rolname='mylifegraph_deletion_replayer'),(select count(*) from pg_auth_members as membership join pg_roles as role on role.rolname='mylifegraph_deletion_replayer' where membership.roleid=role.oid or membership.member=role.oid),(select count(*) from pg_auth_members as membership join pg_roles as role on role.rolname='mylifegraph_deletion_replayer' where membership.roleid=role.oid and membership.member=current_user::regrole and membership.grantor=10 and membership.admin_option and coalesce((to_jsonb(membership)->>'inherit_option')::boolean,false)=false and coalesce((to_jsonb(membership)->>'set_option')::boolean,false)=false),has_function_privilege('authenticated','public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)','EXECUTE'),has_function_privilege('service_role','public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)','EXECUTE'),has_function_privilege('mylifegraph_deletion_replayer','public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)','EXECUTE'))")"
  if [[ "$server_version_number" -ge 160000 ]]; then
    expected_replayer_boundary='t|1|1|f|f|t'
  else
    expected_replayer_boundary='t|0|0|f|f|t'
  fi
  [[ "$replayer_boundary" == "$expected_replayer_boundary" ]] || {
    printf 'Deletion V2 clean role boundary failed: %s\n' \
      "$replayer_boundary" >&2
    return 1
  }
  assert_recommendation_normal_history_unchanged 'Deletion V2 clean role boundary'

  # Add every remaining immutable migration before the shared final-state
  # pgTAP corpus so new contracts are tested without weakening the transition
  # fixture.
  for migration_file in "$root_dir"/supabase/migrations/*.sql; do
    migration_name="$(basename "$migration_file")"
    if [[ "$migration_name" > "$deletion_recovery_boundary" ]]; then
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

  run_coach_operator_concurrency_harness \
    "$database_container" \
    "$database_name" \
    "$harness_root/coach-operator-concurrency" \
    "$harness_variant"
  assert_recommendation_normal_history_unchanged 'Coach operator concurrency'

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

  if [[ "$server_version_number" -ge 160000 ]]; then
    # A fresh-migration proof is necessary but not sufficient for recovery.
    # Round-trip the complete final database into a second PG17 container,
    # preserve owners/ACLs and global role shape, then execute one deletion
    # replay through the restored NOLOGIN role.
    pg17_dump="$harness_root/pg17-final.dump"
    pg17_source_facts="$(docker exec "$database_container" psql \
      -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
      -c "select concat_ws('|',current_setting('server_version_num'),(select count(*) from supabase_migrations.schema_migrations),(select max(version) from supabase_migrations.schema_migrations),private.account_deletion_replayer_role_safe_v2(),(select count(*) from pg_auth_members as membership join pg_roles as role on role.rolname='mylifegraph_deletion_replayer' where membership.roleid=role.oid or membership.member=role.oid))")"
    [[ "$pg17_source_facts" == \
      '170006|69|20260820200000|t|1' ]] || {
      printf 'PG17 source restore facts are unexpected: %s\n' \
        "$pg17_source_facts" >&2
      return 1
    }
    docker exec "$database_container" pg_dump \
      -U postgres -d "$database_name" --format=custom >"$pg17_dump"
    [[ -s "$pg17_dump" ]] || {
      printf '%s\n' 'PG17 restore proof produced an empty archive.' >&2
      return 1
    }
    chmod 600 "$pg17_dump"
    isolated_postgres_stop

    isolated_postgres_start \
      "$root_dir" \
      'account-deletion-pg17-restore' \
      'mylifegraph_account_deletion_pg17_restore' \
      "$postgres_image" \
      "$bootstrap_user"
    database_container="$ISOLATED_POSTGRES_CONTAINER"
    docker exec "$database_container" psql \
      -U "$bootstrap_user" \
      -d 'mylifegraph_account_deletion_pg17_restore' \
      -X -v ON_ERROR_STOP=1 \
      -c "create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; create role postgres login nosuperuser nocreatedb createrole inherit noreplication bypassrls connection limit -1; alter database mylifegraph_account_deletion_pg17_restore owner to postgres; grant anon, authenticated, service_role to postgres with admin option;" \
      >"$harness_root/pg17-restore-roles.log" 2>&1
    docker exec "$database_container" psql \
      -U postgres \
      -d 'mylifegraph_account_deletion_pg17_restore' \
      -X -v ON_ERROR_STOP=1 \
      -c "select set_config('createrole_self_grant','',false); create role mylifegraph_deletion_replayer nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 0;" \
      >"$harness_root/pg17-restore-replayer-role.log" 2>&1
    if ! docker exec -i "$database_container" pg_restore \
      -U "$bootstrap_user" \
      -d 'mylifegraph_account_deletion_pg17_restore' \
      --exit-on-error \
      <"$pg17_dump" \
      >"$harness_root/pg17-restore.log" 2>&1; then
      recommendation_retirement_harness_sanitize_output \
        <"$harness_root/pg17-restore.log" >&2
      return 1
    fi
    pg17_restore_facts="$(docker exec "$database_container" psql \
      -U postgres \
      -d 'mylifegraph_account_deletion_pg17_restore' \
      -X -At -v ON_ERROR_STOP=1 \
      -c "select concat_ws('|',current_setting('server_version_num'),(select count(*) from supabase_migrations.schema_migrations),(select max(version) from supabase_migrations.schema_migrations),private.account_deletion_replayer_role_safe_v2(),(select count(*) from pg_auth_members as membership join pg_roles as role on role.rolname='mylifegraph_deletion_replayer' where membership.roleid=role.oid or membership.member=role.oid))")"
    [[ "$pg17_restore_facts" == "$pg17_source_facts" ]] || {
      printf 'PG17 restored facts differ: %s\n' "$pg17_restore_facts" >&2
      return 1
    }
    docker exec -i "$database_container" psql \
      -U "$bootstrap_user" \
      -d 'mylifegraph_account_deletion_pg17_restore' \
      -X -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ed170000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'pg17-restore-replay@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
begin;
set local role mylifegraph_deletion_replayer;
select public.replay_account_deletion_v2(
  'ed170000-0000-4000-8000-000000000001',
  'ed170100-0000-4000-8000-000000000001',
  timestamptz '2026-08-20 15:00:00+00',
  'deletions/v2/2026/08/ed170100-0000-4000-8000-000000000001/' ||
    repeat('d', 64) || '.json',
  repeat('d', 64),
  timestamptz '2026-08-20 15:00:01+00'
);
commit;
do $$
begin
  if exists (
    select 1 from auth.users
    where id = 'ed170000-0000-4000-8000-000000000001'
  ) or exists (
    select 1 from public.profiles
    where id = 'ed170000-0000-4000-8000-000000000001'
  ) or not exists (
    select 1
    from public.account_deletion_intents
    where deletion_id = 'ed170100-0000-4000-8000-000000000001'
      and state = 'completed'
  ) then
    raise exception 'PG17 restored deletion replay postconditions failed.';
  end if;
end;
$$;
SQL
    printf '%s\n' \
      'PG17 full-database restore and deletion replay proof passed.'
    assert_recommendation_normal_history_unchanged 'PG17 restore and replay'
  fi
  printf '%s\n' \
    'Physically isolated Recommendation-retirement harness passed.'
)
