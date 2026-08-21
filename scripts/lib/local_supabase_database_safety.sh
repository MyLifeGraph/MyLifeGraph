#!/usr/bin/env bash

# Safety primitives for the repository's local Supabase Postgres only.
#
# This file owns the only supported `supabase db reset` invocation. Normal
# verification and application startup never source reset authority from user
# input. A reset must be target-bound, preceded by a full verified backup, and
# invoked through scripts/reset_local_supabase.sh.

local_supabase_is_recognized_postgres_image() {
  local image="$1"

  [[ "$image" =~ ^(public\.ecr\.aws|ghcr\.io)/supabase/postgres:[A-Za-z0-9._-]+$ ]]
}

local_supabase_safety_project_id() {
  local root_dir="$1"
  local project_id

  project_id="$(
    awk -F '=' '
      /^project_id[[:space:]]*=/ {
        value = $2
        gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", value)
        print value
        exit
      }
    ' "$root_dir/supabase/config.toml"
  )"
  if [[ -z "$project_id" || ! "$project_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf '%s\n' \
      'Local database safety error: supabase/config.toml has no safe project_id.' >&2
    return 2
  fi
  printf '%s\n' "$project_id"
}

local_supabase_assert_exact_database_target() {
  local root_dir="$1"
  local project_id database_container project_label running image identity

  project_id="$(local_supabase_safety_project_id "$root_dir")" || return $?
  database_container="supabase_db_${project_id}"

  if ! project_label="$(
    docker inspect \
      --format '{{ index .Config.Labels "com.supabase.cli.project" }}' \
      "$database_container" 2>/dev/null
  )"; then
    printf 'Local database safety error: expected container %s is absent.\n' \
      "$database_container" >&2
    return 1
  fi
  if [[ "$project_label" != "$project_id" ]]; then
    printf '%s\n' \
      'Local database safety error: the Postgres container project label does not match supabase/config.toml.' >&2
    return 1
  fi

  running="$(docker inspect --format '{{.State.Running}}' "$database_container")"
  if [[ "$running" != 'true' ]]; then
    printf 'Local database safety error: container %s is not running.\n' \
      "$database_container" >&2
    return 1
  fi

  image="$(docker inspect --format '{{.Config.Image}}' "$database_container")"
  if ! local_supabase_is_recognized_postgres_image "$image"; then
    printf '%s\n' \
      'Local database safety error: the running database does not use a recognized Supabase Postgres image.' >&2
    return 1
  fi

  identity="$(
    docker exec "$database_container" psql \
      -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
      -c "select current_database() || '|' || current_user"
  )" || return $?
  if [[ "$identity" != 'postgres|postgres' ]]; then
    printf 'Local database safety error: unexpected database identity %q.\n' \
      "$identity" >&2
    return 1
  fi

  LOCAL_SUPABASE_SAFETY_PROJECT_ID="$project_id"
  LOCAL_SUPABASE_SAFETY_CONTAINER="$database_container"
  LOCAL_SUPABASE_SAFETY_IMAGE="$image"
}

local_supabase_capture_reset_facts() {
  local root_dir="$1"
  local facts database_name database_user auth_users profiles database_bytes
  local latest_migration protected_data_digest digest_output token_input token_hash

  local_supabase_assert_exact_database_target "$root_dir" || return $?
  facts="$(
    docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" psql \
      -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 \
      -c "select concat_ws('|', current_database(), current_user, (select count(*) from auth.users), (select count(*) from public.profiles), pg_database_size(current_database()), coalesce((select max(version) from supabase_migrations.schema_migrations), ''))"
  )" || return $?

  IFS='|' read -r \
    database_name \
    database_user \
    auth_users \
    profiles \
    database_bytes \
    latest_migration <<<"$facts"

  if [[ "$database_name" != 'postgres' || "$database_user" != 'postgres' ||
    ! "$auth_users" =~ ^[0-9]+$ || ! "$profiles" =~ ^[0-9]+$ ||
    ! "$database_bytes" =~ ^[0-9]+$ ||
    ! "$latest_migration" =~ ^[0-9]{14}$ ]]; then
    printf 'Local database safety error: reset facts could not be validated (%q).\n' \
      "$facts" >&2
    return 1
  fi

  if ! digest_output="$(
    docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" \
      pg_dump -U postgres -d postgres --data-only --no-owner \
      --no-privileges --no-comments --strict-names \
      --schema=auth --schema=private --schema=public --schema=storage \
      --schema=supabase_migrations 2>/dev/null |
      local_supabase_normalize_protected_data_dump |
      sha256sum
  )"; then
    printf '%s\n' \
      'Local database safety error: protected logical data could not be fingerprinted.' >&2
    return 1
  fi
  protected_data_digest="${digest_output%% *}"
  if [[ ! "$protected_data_digest" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'Local database safety error: protected data digest is malformed (%q).\n' \
      "$digest_output" >&2
    return 1
  fi

  token_input="project=${LOCAL_SUPABASE_SAFETY_PROJECT_ID}|container=${LOCAL_SUPABASE_SAFETY_CONTAINER}|database=${database_name}|auth_users=${auth_users}|profiles=${profiles}|database_bytes=${database_bytes}|latest_migration=${latest_migration}|protected_data_sha256=${protected_data_digest}"
  token_hash="$(printf '%s' "$token_input" | sha256sum | awk '{print $1}')"

  LOCAL_SUPABASE_RESET_DATABASE="$database_name"
  LOCAL_SUPABASE_RESET_AUTH_USERS="$auth_users"
  LOCAL_SUPABASE_RESET_PROFILES="$profiles"
  LOCAL_SUPABASE_RESET_DATABASE_BYTES="$database_bytes"
  LOCAL_SUPABASE_RESET_LATEST_MIGRATION="$latest_migration"
  LOCAL_SUPABASE_RESET_PROTECTED_DATA_SHA256="$protected_data_digest"
  LOCAL_SUPABASE_RESET_TOKEN="reset-local-${LOCAL_SUPABASE_SAFETY_PROJECT_ID}-${token_hash:0:16}"
}

local_supabase_normalize_protected_data_dump() {
  # PostgreSQL 17 emits a fresh psql \restrict nonce in every plain dump. It is
  # transport metadata, not database content. Remove only the exact paired
  # meta-command shape so identical logical data produces an identical reset
  # token; reject a future or malformed marker shape instead of weakening the
  # content binding silently.
  awk '
    function fail_marker() {
      print "Local database safety error: malformed pg_dump restrict marker pair." > "/dev/stderr"
      invalid = 1
      exit 65
    }
    $0 ~ /^\\restrict [A-Za-z0-9]+$/ {
      if (marker_state != 0) {
        fail_marker()
      }
      marker_nonce = $0
      sub(/^\\restrict /, "", marker_nonce)
      marker_state = 1
      next
    }
    $0 ~ /^\\unrestrict [A-Za-z0-9]+$/ {
      if (marker_state != 1) {
        fail_marker()
      }
      closing_nonce = $0
      sub(/^\\unrestrict /, "", closing_nonce)
      if (closing_nonce != marker_nonce) {
        fail_marker()
      }
      marker_state = 2
      next
    }
    $0 ~ /^[[:space:]]*\\(un)?restrict([[:space:]]|$)/ {
      fail_marker()
    }
    { print }
    END {
      if (!invalid && marker_state == 1) {
        fail_marker()
      }
    }
  '
}

local_supabase_print_reset_preview() {
  printf '%s\n' \
    'Local database reset preview (no data changed):' \
    "  project: ${LOCAL_SUPABASE_SAFETY_PROJECT_ID}" \
    "  container: ${LOCAL_SUPABASE_SAFETY_CONTAINER}" \
    "  database: ${LOCAL_SUPABASE_RESET_DATABASE}" \
    "  auth users: ${LOCAL_SUPABASE_RESET_AUTH_USERS}" \
    "  profiles: ${LOCAL_SUPABASE_RESET_PROFILES}" \
    "  database bytes: ${LOCAL_SUPABASE_RESET_DATABASE_BYTES}" \
    "  latest migration: ${LOCAL_SUPABASE_RESET_LATEST_MIGRATION}" \
    "  protected data digest: ${LOCAL_SUPABASE_RESET_PROTECTED_DATA_SHA256:0:16}" \
    "  required confirmation: ${LOCAL_SUPABASE_RESET_TOKEN}"
}

isolated_postgres_start() {
  local root_dir="$1"
  local purpose="$2"
  local database_name="$3"
  local requested_image="${4:-}"
  local bootstrap_user="${5:-postgres}"
  local preload_libraries='pg_net'
  local enable_ssl='true'
  local image_user identity uid gid container_name container_id label port_line
  local postgres_image
  local docker_gateway
  local attempt

  if [[ ! "$purpose" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]; then
    printf 'Isolated Postgres error: unsafe purpose %q.\n' "$purpose" >&2
    return 2
  fi
  if [[ ! "$database_name" =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
    printf 'Isolated Postgres error: unsafe database name %q.\n' \
      "$database_name" >&2
    return 2
  fi
  if [[ ! "$bootstrap_user" =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
    printf 'Isolated Postgres error: unsafe bootstrap user %q.\n' \
      "$bootstrap_user" >&2
    return 2
  fi
  if [[ "$bootstrap_user" != 'postgres' ]]; then
    preload_libraries=''
  fi

  local_supabase_assert_exact_database_target "$root_dir" || return $?
  postgres_image="$LOCAL_SUPABASE_SAFETY_IMAGE"
  if [[ -n "$requested_image" ]]; then
    if ! local_supabase_is_recognized_postgres_image "$requested_image"; then
      printf 'Isolated Postgres error: unsafe image %q.\n' \
        "$requested_image" >&2
      return 2
    fi
    if ! docker image inspect "$requested_image" >/dev/null 2>&1; then
      printf 'Isolated Postgres error: required local image is absent: %s\n' \
        "$requested_image" >&2
      return 1
    fi
    postgres_image="$requested_image"
  fi
  identity="$(
    docker run --rm --entrypoint id "$postgres_image" postgres
  )" || return $?
  if [[ ! "$identity" =~ uid=([0-9]+)\(postgres\)[[:space:]]gid=([0-9]+)\(postgres\) ]]; then
    printf '%s\n' \
      'Isolated Postgres error: could not validate the image postgres uid/gid.' >&2
    return 1
  fi
  uid="${BASH_REMATCH[1]}"
  gid="${BASH_REMATCH[2]}"
  docker_gateway="$(
    docker network inspect bridge \
      --format '{{ (index .IPAM.Config 0).Gateway }}'
  )" || return $?
  if ! awk -F. '
    NF != 4 { exit 1 }
    {
      for (octet = 1; octet <= 4; octet++) {
        if ($octet !~ /^[0-9]+$/ || $octet < 0 || $octet > 255) {
          exit 1
        }
      }
    }
  ' <<<"$docker_gateway"; then
    printf 'Isolated Postgres error: unsafe Docker gateway %q.\n' \
      "$docker_gateway" >&2
    return 1
  fi

  container_name="mylifegraph-${purpose}-$$"
  label="mylifegraph-${purpose}"
  if docker inspect "$container_name" >/dev/null 2>&1; then
    printf 'Isolated Postgres error: container %s already exists.\n' \
      "$container_name" >&2
    return 1
  fi

  container_id="$(
    docker run --detach \
      --name "$container_name" \
      --label "com.mylifegraph.owned=${label}" \
      --label "com.mylifegraph.source-project=${LOCAL_SUPABASE_SAFETY_PROJECT_ID}" \
      --read-only \
      --tmpfs "/var/lib/postgresql/data:rw,nosuid,nodev,size=1024m,uid=${uid},gid=${gid}" \
      --tmpfs "/run/postgresql:rw,nosuid,nodev,size=16m,uid=${uid},gid=${gid}" \
      --tmpfs "/tmp:rw,nosuid,nodev,size=64m,uid=${uid},gid=${gid}" \
      --publish 127.0.0.1::5432 \
      --user "${uid}:${gid}" \
      --cap-drop ALL \
      --security-opt no-new-privileges=true \
      --memory 1g \
      --memory-swap 1g \
      --cpus 2 \
      --pids-limit 256 \
      --env "MYLIFEGRAPH_ISOLATED_DATABASE=${database_name}" \
      --env "MYLIFEGRAPH_DOCKER_GATEWAY=${docker_gateway}" \
      --env "MYLIFEGRAPH_ISOLATED_BOOTSTRAP_USER=${bootstrap_user}" \
      --env "MYLIFEGRAPH_ISOLATED_PRELOAD_LIBRARIES=${preload_libraries}" \
      --env "MYLIFEGRAPH_ISOLATED_ENABLE_SSL=${enable_ssl}" \
      --entrypoint bash \
      "$postgres_image" \
      -ceu 'initdb -D /var/lib/postgresql/data --username="${MYLIFEGRAPH_ISOLATED_BOOTSTRAP_USER}" --auth-local=trust --auth-host=trust; printf "host all all %s/32 trust\n" "${MYLIFEGRAPH_DOCKER_GATEWAY}" >>/var/lib/postgresql/data/pg_hba.conf; if [ "${MYLIFEGRAPH_ISOLATED_ENABLE_SSL}" = true ]; then openssl_bin="$(command -v openssl || find /nix/store -type f -path "*openssl-*-bin/bin/openssl" -print -quit 2>/dev/null)"; test -n "${openssl_bin}" && test -x "${openssl_bin}"; "${openssl_bin}" req -new -x509 -nodes -days 1 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -keyout /var/lib/postgresql/data/server.key -out /var/lib/postgresql/data/server.crt >/dev/null 2>&1; chmod 600 /var/lib/postgresql/data/server.key; exec postgres -D /var/lib/postgresql/data -c "listen_addresses=*" -c "ssl=on" -c "ssl_cert_file=/var/lib/postgresql/data/server.crt" -c "ssl_key_file=/var/lib/postgresql/data/server.key" -c "shared_preload_libraries=${MYLIFEGRAPH_ISOLATED_PRELOAD_LIBRARIES}" -c "pg_net.database_name=${MYLIFEGRAPH_ISOLATED_DATABASE}"; else exec postgres -D /var/lib/postgresql/data -c "listen_addresses=*" -c "ssl=off" -c "shared_preload_libraries=${MYLIFEGRAPH_ISOLATED_PRELOAD_LIBRARIES}" -c "pg_net.database_name=${MYLIFEGRAPH_ISOLATED_DATABASE}"; fi'
  )" || return $?

  ISOLATED_POSTGRES_CONTAINER="$container_name"
  ISOLATED_POSTGRES_DATABASE="$database_name"
  ISOLATED_POSTGRES_OWNERSHIP_LABEL="$label"
  ISOLATED_POSTGRES_IMAGE="$postgres_image"
  ISOLATED_POSTGRES_BOOTSTRAP_USER="$bootstrap_user"
  ISOLATED_POSTGRES_CREATED=true

  for attempt in $(seq 1 120); do
    if docker exec "$container_name" pg_isready \
      -U "$bootstrap_user" -d postgres >/dev/null 2>&1; then
      break
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != 'true' ]]; then
      printf 'Isolated Postgres error: container %s exited during startup.\n' \
        "$container_name" >&2
      docker logs "$container_name" >&2 || true
      return 1
    fi
    sleep 0.25
  done
  if ! docker exec "$container_name" pg_isready \
    -U "$bootstrap_user" -d postgres >/dev/null 2>&1; then
    printf 'Isolated Postgres error: container %s did not become ready.\n' \
      "$container_name" >&2
    return 1
  fi

  if [[ "$database_name" != 'postgres' ]]; then
    docker exec "$container_name" createdb \
      -U "$bootstrap_user" -T template0 "$database_name" || return $?
  fi
  image_user="$(
    docker inspect \
      --format '{{ index .Config.Labels "com.mylifegraph.owned" }}' \
      "$container_name"
  )"
  if [[ "$image_user" != "$label" ]]; then
    printf '%s\n' \
      'Isolated Postgres error: ownership label changed after startup.' >&2
    return 1
  fi

  port_line="$(docker port "$container_name" 5432/tcp)"
  if [[ ! "$port_line" =~ ^127\.0\.0\.1:([0-9]+)$ ]]; then
    printf 'Isolated Postgres error: unexpected loopback mapping %q.\n' \
      "$port_line" >&2
    return 1
  fi
  ISOLATED_POSTGRES_PORT="${BASH_REMATCH[1]}"
  ISOLATED_POSTGRES_URL="postgresql://${bootstrap_user}@127.0.0.1:${ISOLATED_POSTGRES_PORT}/${database_name}?sslmode=disable"

  if [[ -z "$container_id" ]]; then
    printf '%s\n' 'Isolated Postgres error: Docker returned no container id.' >&2
    return 1
  fi
}

isolated_postgres_stop() {
  local container_name="${ISOLATED_POSTGRES_CONTAINER:-}"
  local expected_label="${ISOLATED_POSTGRES_OWNERSHIP_LABEL:-}"
  local actual_label

  if [[ "${ISOLATED_POSTGRES_CREATED:-false}" != 'true' ||
    -z "$container_name" || -z "$expected_label" ]]; then
    return 0
  fi
  if ! actual_label="$(
    docker inspect \
      --format '{{ index .Config.Labels "com.mylifegraph.owned" }}' \
      "$container_name" 2>/dev/null
  )"; then
    ISOLATED_POSTGRES_CREATED=false
    return 0
  fi
  if [[ "$actual_label" != "$expected_label" ]]; then
    printf 'Isolated Postgres cleanup refused container %s with label %q.\n' \
      "$container_name" "$actual_label" >&2
    return 1
  fi
  docker rm --force "$container_name" >/dev/null
  ISOLATED_POSTGRES_CREATED=false
}

local_supabase_create_verified_backup() (
  set -euo pipefail

  local root_dir="$1"
  local reason="${2:-manual}"
  local backup_id backup_dir partial_dump final_dump archive_list metadata_file
  local checksum_file restore_log restore_roles source_auth source_profiles
  local source_migration restored_facts restored_auth restored_profiles
  local restored_migration checksum

  if [[ ! "$reason" =~ ^[a-z0-9][a-z0-9_-]{0,39}$ ]]; then
    printf 'Local backup error: unsafe reason %q.\n' "$reason" >&2
    return 2
  fi

  local_supabase_capture_reset_facts "$root_dir"
  source_auth="$LOCAL_SUPABASE_RESET_AUTH_USERS"
  source_profiles="$LOCAL_SUPABASE_RESET_PROFILES"
  source_migration="$LOCAL_SUPABASE_RESET_LATEST_MIGRATION"
  backup_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  backup_dir="$root_dir/.tools/supabase-backups"
  partial_dump="$backup_dir/.mylifegraph-local-${backup_id}.dump.partial"
  final_dump="$backup_dir/mylifegraph-local-${backup_id}.dump"
  archive_list="$backup_dir/.mylifegraph-local-${backup_id}.list.partial"
  metadata_file="${final_dump}.metadata"
  checksum_file="${final_dump}.sha256"
  restore_log="$backup_dir/.mylifegraph-local-${backup_id}.restore.log"
  restore_roles="$root_dir/supabase/migration_tests/local_database_safety/restore_roles.sql"

  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"
  umask 077
  if [[ -e "$partial_dump" || -e "$final_dump" ||
    -e "$metadata_file" || -e "$checksum_file" ]]; then
    printf 'Local backup error: backup id collision at %s.\n' "$final_dump" >&2
    return 1
  fi
  if [[ ! -f "$restore_roles" ]]; then
    printf 'Local backup error: restore-role bootstrap is missing: %s\n' \
      "$restore_roles" >&2
    return 2
  fi

  cleanup_local_backup() {
    local cleanup_status=$?
    isolated_postgres_stop || true
    rm -f "$partial_dump" "$archive_list" "$restore_log"
    return "$cleanup_status"
  }
  trap cleanup_local_backup EXIT

  printf '%s\n' \
    'Creating a full custom-format dump of the exact local Supabase postgres database.' >&2
  docker exec "$LOCAL_SUPABASE_SAFETY_CONTAINER" pg_dump \
    -U postgres -d postgres --format=custom >"$partial_dump"
  if [[ ! -s "$partial_dump" ]]; then
    printf '%s\n' 'Local backup error: pg_dump produced an empty archive.' >&2
    return 1
  fi

  docker exec -i "$LOCAL_SUPABASE_SAFETY_CONTAINER" pg_restore --list \
    <"$partial_dump" >"$archive_list"
  for required_entry in \
    'TABLE DATA auth users' \
    'TABLE DATA public profiles' \
    'TABLE DATA supabase_migrations schema_migrations'; do
    if ! grep -Eq "[[:space:]]${required_entry}[[:space:]]" "$archive_list"; then
      printf 'Local backup error: archive is missing %s.\n' \
        "$required_entry" >&2
      return 1
    fi
  done

  printf '%s\n' \
    'Restoring the archive into a separate RAM-only Postgres container for verification.' >&2
  isolated_postgres_start \
    "$root_dir" \
    'local-backup-restore-test' \
    'mylifegraph_local_backup_restore_test'
  docker exec -i "$ISOLATED_POSTGRES_CONTAINER" psql \
    -U postgres -d "$ISOLATED_POSTGRES_DATABASE" \
    -X -v ON_ERROR_STOP=1 <"$restore_roles" >/dev/null
  if ! docker exec -i "$ISOLATED_POSTGRES_CONTAINER" pg_restore \
    -U postgres \
    -d "$ISOLATED_POSTGRES_DATABASE" \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    >"$restore_log" 2>&1 <"$partial_dump"; then
    sed -E \
      -e 's#postgres(ql)?://[^[:space:]]+#postgresql://<redacted>#g' \
      -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g' \
      "$restore_log" >&2
    printf '%s\n' 'Local backup error: isolated restore verification failed.' >&2
    return 1
  fi

  restored_facts="$(
    docker exec "$ISOLATED_POSTGRES_CONTAINER" psql \
      -U postgres -d "$ISOLATED_POSTGRES_DATABASE" \
      -X -At -v ON_ERROR_STOP=1 \
      -c "select concat_ws('|', (select count(*) from auth.users), (select count(*) from public.profiles), coalesce((select max(version) from supabase_migrations.schema_migrations), ''))"
  )"
  IFS='|' read -r restored_auth restored_profiles restored_migration \
    <<<"$restored_facts"
  if [[ "$restored_auth" != "$source_auth" ||
    "$restored_profiles" != "$source_profiles" ||
    "$restored_migration" != "$source_migration" ]]; then
    printf 'Local backup error: isolated restore facts differ (%q).\n' \
      "$restored_facts" >&2
    return 1
  fi
  isolated_postgres_stop

  mv "$partial_dump" "$final_dump"
  checksum="$(sha256sum "$final_dump" | awk '{print $1}')"
  printf '%s  %s\n' "$checksum" "$(basename "$final_dump")" \
    >"$checksum_file"
  printf '%s\n' \
    "format=pg_dump_custom" \
    "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "reason=${reason}" \
    "project_id=${LOCAL_SUPABASE_SAFETY_PROJECT_ID}" \
    "database=postgres" \
    "auth_users=${source_auth}" \
    "profiles=${source_profiles}" \
    "latest_migration=${source_migration}" \
    "sha256=${checksum}" \
    "archive_list_verified=true" \
    "isolated_restore_verified=true" \
    >"$metadata_file"
  chmod 600 "$final_dump" "$checksum_file" "$metadata_file"
  printf '%s\n' "$final_dump"
)

local_supabase_execute_guarded_reset() {
  local root_dir="$1"
  local supplied_confirmation="$2"
  local expected_confirmation backup_path post_backup_confirmation

  local_supabase_capture_reset_facts "$root_dir" || return $?
  expected_confirmation="$LOCAL_SUPABASE_RESET_TOKEN"
  if [[ "$supplied_confirmation" != "$expected_confirmation" ]]; then
    local_supabase_print_reset_preview >&2
    printf '%s\n' \
      'Local database reset refused: RESET_DB_CONFIRMATION does not match the current target and contents.' \
      'Run npm run db:reset:local for a fresh preview. No backup or reset was performed.' >&2
    return 2
  fi

  backup_path="$(
    local_supabase_create_verified_backup "$root_dir" 'pre_reset'
  )" || return $?

  local_supabase_capture_reset_facts "$root_dir" || return $?
  post_backup_confirmation="$LOCAL_SUPABASE_RESET_TOKEN"
  if [[ "$post_backup_confirmation" != "$expected_confirmation" ]]; then
    printf '%s\n' \
      "Local database reset refused: the database changed while the verified backup was created." \
      "Verified backup retained at: ${backup_path}" \
      'Run npm run db:reset:local again to review the new target fingerprint.' >&2
    return 1
  fi

  printf '%s\n' \
    "Verified pre-reset backup: ${backup_path}" \
    'Executing the one supported destructive command against --local.' >&2
  supabase_cli db reset --local || return $?
  local_supabase_assert_migration_history_current false || return $?
  printf '%s\n' \
    'Guarded local Supabase reset completed.' \
    "Recovery archive: ${backup_path}"
}
