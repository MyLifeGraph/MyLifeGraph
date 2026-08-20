#!/usr/bin/env bash

# Full-chain proof for Multi Exam Plan V1. Product migrations and pgTAP run
# only in a labelled, RAM-only Postgres container. The normal local database
# is read solely to compare its migration-history checksum before and after.

multi_exam_plan_harness_sanitize_output() {
  sed -E \
    -e 's#postgres(ql)?://[^[:space:]]+#postgresql://<redacted>#g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

run_multi_exam_plan_migration_harness() (
  set -euo pipefail

  local root_dir="$1"
  local database_name='mylifegraph_multi_exam_plan_migration_test'
  local bootstrap_user='postgres'
  local bootstrap_file="$root_dir/supabase/migration_tests/goal_removal/bootstrap.sql"
  local assertions_file="$root_dir/supabase/tests/multi_exam_plan_v1_test.sql"
  local migration_file="$root_dir/supabase/migrations/20260813081814_multi_exam_plan_v1.sql"
  local harness_root database_container test_url
  local postgres_image postgres_image_tag postgres_major
  local server_version_number container_ip
  local normal_history_before normal_history_after
  local normal_history_guarded=false

  assert_multi_exam_normal_history_unchanged() {
    local stage="$1"
    normal_history_after="$(
      docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
        -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
        -c "select coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations"
    )"
    if [[ "$normal_history_after" != "$normal_history_before" ]]; then
      printf 'Multi-Exam harness detected normal migration-history drift after %s.\n' \
        "$stage" >&2
      return 1
    fi
  }

  if ! declare -F isolated_postgres_start >/dev/null 2>&1 ||
    ! declare -F isolated_postgres_stop >/dev/null 2>&1; then
    printf '%s\n' 'Multi-Exam harness requires database safety helpers.' >&2
    return 2
  fi
  if [[ "$database_name" != 'mylifegraph_multi_exam_plan_migration_test' ]]; then
    printf '%s\n' 'Multi-Exam harness refused an unexpected database name.' >&2
    return 2
  fi
  for required_file in "$bootstrap_file" "$assertions_file" "$migration_file"; do
    if [[ ! -f "$required_file" ]]; then
      printf 'Multi-Exam harness file is missing: %s\n' "$required_file" >&2
      return 2
    fi
  done

  local_supabase_assert_exact_database_target "$root_dir" || return $?
  postgres_image="$LOCAL_SUPABASE_SAFETY_IMAGE"
  postgres_image_tag="${postgres_image##*:}"
  postgres_major="${postgres_image_tag%%.*}"
  if [[ ! "$postgres_major" =~ ^[0-9]+$ ]]; then
    printf 'Multi-Exam harness rejected image version %q.\n' \
      "$postgres_image_tag" >&2
    return 2
  fi
  if [[ "$postgres_major" -ge 16 ]]; then
    bootstrap_user='mylifegraph_multi_exam_bootstrap'
  fi
  normal_history_before="$(
    docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
      -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
      -c "select coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations"
  )"

  harness_root="$(mktemp -d /tmp/mylifegraph-multi-exam-harness.XXXXXX)"
  cleanup_multi_exam_plan_harness() {
    local cleanup_status=$?
    if [[ "$normal_history_guarded" == true ]]; then
      assert_multi_exam_normal_history_unchanged 'harness exit' || cleanup_status=1
    fi
    isolated_postgres_stop || true
    rm -rf "$harness_root"
    return "$cleanup_status"
  }
  trap cleanup_multi_exam_plan_harness EXIT
  normal_history_guarded=true

  isolated_postgres_start \
    "$root_dir" \
    'multi-exam-migration-test' \
    "$database_name" \
    "$postgres_image" \
    "$bootstrap_user"
  database_container="$ISOLATED_POSTGRES_CONTAINER"
  test_url="$ISOLATED_POSTGRES_URL"
  printf '%s\n' "Multi-Exam full-chain target is isolated in ${database_container}."

  if ! docker exec -i "$database_container" psql \
    -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 \
    <"$bootstrap_file" >"$harness_root/bootstrap.log" 2>&1; then
    multi_exam_plan_harness_sanitize_output <"$harness_root/bootstrap.log" >&2
    return 1
  fi
  server_version_number="$(docker exec "$database_container" psql \
    -U "$bootstrap_user" -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select current_setting('server_version_num')")"
  if [[ ! "$server_version_number" =~ ^[0-9]+$ ]]; then
    printf '%s\n' \
      'Multi-Exam harness could not determine PostgreSQL version.' >&2
    return 1
  fi
  if [[ "$server_version_number" -ge 160000 ]]; then
    # Match hosted Supabase's PG16+ role boundary: OID 10 remains a bootstrap
    # superuser while migrations run as a separate non-superuser CREATEROLE
    # principal named postgres.
    docker exec "$database_container" psql \
      -U "$bootstrap_user" -d "$database_name" -X -v ON_ERROR_STOP=1 \
      -c "create extension if not exists dblink with schema extensions; create role postgres login nosuperuser nocreatedb createrole inherit noreplication bypassrls connection limit -1; alter database ${database_name} owner to postgres; alter schema auth owner to postgres; alter table auth.users owner to postgres; alter function auth.uid() owner to postgres; alter function auth.role() owner to postgres; grant usage on schema extensions to postgres; grant anon, authenticated, service_role to postgres with admin option;" \
      >"$harness_root/pg16-plus-migration-role.log" 2>&1
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
      printf 'Multi-Exam harness rejected container IP %q.\n' \
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
      >"$harness_root/pg16-plus-hba-reload.log" 2>&1
    test_url="postgresql://postgres@127.0.0.1:${ISOLATED_POSTGRES_PORT}/${database_name}?sslmode=disable"
  fi
  if ! supabase_cli migration up \
    --db-url "$test_url" \
    --workdir "$root_dir" \
    >"$harness_root/migrations.log" 2>&1; then
    multi_exam_plan_harness_sanitize_output <"$harness_root/migrations.log" >&2
    return 1
  fi
  assert_multi_exam_normal_history_unchanged 'full-chain migration'
  if [[ "$(docker exec "$database_container" psql \
    -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 \
    -c "select count(*) from supabase_migrations.schema_migrations where version = '20260813081814'")" \
      != '1' ]]; then
    printf '%s\n' 'Multi-Exam harness did not apply its migration.' >&2
    return 1
  fi

  local assertion_pass
  for assertion_pass in 1 2; do
    printf 'Running isolated Multi Exam Plan pgTAP assertions (pass %s/2).\n' \
      "$assertion_pass"
    if ! supabase_cli test db \
      --db-url "$test_url" \
      --workdir "$root_dir" \
      "$assertions_file" \
      >"$harness_root/assertions-${assertion_pass}.log" 2>&1; then
      multi_exam_plan_harness_sanitize_output \
        <"$harness_root/assertions-${assertion_pass}.log" >&2
      return 1
    fi
    multi_exam_plan_harness_sanitize_output \
      <"$harness_root/assertions-${assertion_pass}.log"
  done
  assert_multi_exam_normal_history_unchanged 'pgTAP assertions'
  printf '%s\n' 'Physically isolated Multi Exam Plan full-chain harness passed.'
)
