#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_TEMPLATE="$BACKUP_ROOT/restore-target/supabase/config.toml"
REFERENCE_TEMPLATE="$BACKUP_ROOT/reference-target/supabase/config.toml"
REFERENCE_NORMALIZER="$BACKUP_ROOT/reference-target/normalize_optional_legacy.sql"
APPLICATION_PROBE="$BACKUP_ROOT/restore-target/application_probe.sql"
PUBLIC_DEFAULT_NORMALIZER="$BACKUP_ROOT/restore-target/neutralize_public_defaults.sql"
RESTORE_CREATOR_NORMALIZER="$BACKUP_ROOT/restore-target/neutralize_restore_creator_defaults.sql"
REPO_ROOT="$(cd "$BACKUP_ROOT/../.." && pwd)"
RESTORE_PROJECT_ID="mylifegraph-restore-rehearsal"
REFERENCE_PROJECT_ID="mylifegraph-schema-reference"
active_project="$RESTORE_PROJECT_ID"
CONTAINER_NAME="supabase_db_${RESTORE_PROJECT_ID}"
SUPABASE_BIN="${SUPABASE_BIN:-/usr/local/bin/supabase}"
SUPABASE_EXPECTED_VERSION="${SUPABASE_EXPECTED_VERSION:-2.107.0}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
RECOVERY_MIGRATION_HEAD="20260820200000_account_deletion_replayer_role_guard_v2.sql"

fail() {
  printf 'Supabase restore rehearsal error: %s\n' "$1" >&2
  exit 1
}

[[ "$#" -eq 4 ]] ||
  fail "usage: run_restore_rehearsal.sh <payload> <attestation-output> <journal-export> <recovery-cutoff-utc>"
payload="$(realpath -e -- "$1")"
attestation_output="$2"
journal_export="$(realpath -e -- "$3")"
recovery_cutoff_utc="$4"
[[ -d "$payload" && ! -L "$payload" ]] || fail "payload must be a real directory"
[[ -f "$TARGET_TEMPLATE" && ! -L "$TARGET_TEMPLATE" ]] ||
  fail "restore target template is unavailable"
[[ -f "$REFERENCE_TEMPLATE" && ! -L "$REFERENCE_TEMPLATE" ]] ||
  fail "schema reference target template is unavailable"
[[ -f "$REFERENCE_NORMALIZER" && ! -L "$REFERENCE_NORMALIZER" ]] ||
  fail "schema reference normalizer is unavailable"
[[ -f "$APPLICATION_PROBE" && ! -L "$APPLICATION_PROBE" ]] ||
  fail "restore application probe is unavailable"
[[ -f "$PUBLIC_DEFAULT_NORMALIZER" && ! -L "$PUBLIC_DEFAULT_NORMALIZER" ]] ||
  fail "public default-privilege normalizer is unavailable"
[[ -f "$RESTORE_CREATOR_NORMALIZER" && ! -L "$RESTORE_CREATOR_NORMALIZER" ]] ||
  fail "restore-creator default-privilege normalizer is unavailable"
SUPABASE_BIN="$(command -v -- "$SUPABASE_BIN" 2>/dev/null || true)"
DOCKER_BIN="$(command -v -- "$DOCKER_BIN" 2>/dev/null || true)"
[[ -n "$SUPABASE_BIN" && -x "$SUPABASE_BIN" ]] || fail "Supabase CLI is unavailable"
[[ -n "$DOCKER_BIN" && -x "$DOCKER_BIN" ]] || fail "Docker CLI is unavailable"
[[ "$("$SUPABASE_BIN" --version)" == "$SUPABASE_EXPECTED_VERSION" ]] ||
  fail "Supabase CLI version differs from the backup pin"
if "$DOCKER_BIN" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  fail "the exact disposable restore target already exists"
fi

python3 "$SCRIPT_DIR/backup_manifest.py" verify-tree --root "$payload"

workdir="$(mktemp -d /tmp/mylifegraph-restore-rehearsal.XXXXXX)"
chmod 0700 "$workdir"
started=false
cleanup() {
  if [[ "$started" == true ]]; then
    HOME="$workdir/home" SUPABASE_TELEMETRY_DISABLED=1 \
      "$SUPABASE_BIN" stop --project-id "$active_project" --no-backup >/dev/null || true
  fi
  case "$workdir" in
    /tmp/mylifegraph-restore-rehearsal.*) rm -rf -- "$workdir" ;;
    *) printf 'Refusing unsafe restore cleanup path.\n' >&2 ;;
  esac
}
trap cleanup EXIT
mkdir -m 0700 "$workdir/home" "$workdir/project" "$workdir/project/supabase"
install -m 0600 "$TARGET_TEMPLATE" "$workdir/project/supabase/config.toml"
python3 "$SCRIPT_DIR/split_managed_schema.py" "$payload/managed_schema.sql" \
  --pre-output "$workdir/managed-pre.sql" \
  --post-output "$workdir/managed-post.sql" \
  --conflict-cleanup-output "$workdir/managed-conflict-cleanup.sql"

started=true
HOME="$workdir/home" SUPABASE_TELEMETRY_DISABLED=1 \
  "$SUPABASE_BIN" db start --workdir "$workdir/project"
"$DOCKER_BIN" container inspect "$CONTAINER_NAME" >/dev/null 2>&1 ||
  fail "Supabase CLI did not create the exact isolated database container"

"$DOCKER_BIN" exec "$CONTAINER_NAME" mkdir -m 0700 /tmp/mylifegraph-restore
for name in roles.sql schema.sql data.sql history_schema.sql history_data.sql auth_storage_diff.sql; do
  [[ -f "$payload/$name" && ! -L "$payload/$name" ]] ||
    fail "restore part is unavailable: $name"
  "$DOCKER_BIN" cp "$payload/$name" "$CONTAINER_NAME:/tmp/mylifegraph-restore/$name"
done
"$DOCKER_BIN" cp "$workdir/managed-pre.sql" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/managed-pre.sql"
"$DOCKER_BIN" cp "$workdir/managed-post.sql" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/managed-post.sql"
"$DOCKER_BIN" cp "$PUBLIC_DEFAULT_NORMALIZER" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/neutralize-public-defaults.sql"
"$DOCKER_BIN" cp "$RESTORE_CREATOR_NORMALIZER" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/neutralize-restore-creator-defaults.sql"

# This is the documented Supabase logical-restore order. The target is a fresh
# base Supabase Postgres instance, and all application triggers are disabled
# only for the COPY phase inside this transaction.
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file /tmp/mylifegraph-restore/roles.sql
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --variable ON_ERROR_STOP=1 \
  --command 'drop schema auth cascade' \
  --command 'drop schema storage cascade' \
  --file /tmp/mylifegraph-restore/neutralize-restore-creator-defaults.sql \
  --file /tmp/mylifegraph-restore/neutralize-public-defaults.sql
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file /tmp/mylifegraph-restore/managed-pre.sql \
  --file /tmp/mylifegraph-restore/schema.sql \
  --file /tmp/mylifegraph-restore/managed-post.sql \
  --command 'SET session_replication_role = replica' \
  --file /tmp/mylifegraph-restore/data.sql
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username postgres \
  --dbname postgres \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file /tmp/mylifegraph-restore/history_schema.sql \
  --file /tmp/mylifegraph-restore/history_data.sql

# Prove the logical restore at its exact historical boundary before applying
# any recovery migration or deletion receipt.
python3 "$SCRIPT_DIR/verify_restored_database.py" render-sql \
  --payload "$payload" \
  --output "$workdir/verify.sql"
"$DOCKER_BIN" cp "$workdir/verify.sql" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/verify.sql"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username postgres \
  --dbname postgres \
  --no-psqlrc \
  --quiet \
  --file /tmp/mylifegraph-restore/verify.sql > "$workdir/report.json"

mkdir -m 0700 "$workdir/recovery" "$workdir/recovery/supabase"
install -m 0600 "$REFERENCE_TEMPLATE" \
  "$workdir/recovery/supabase/config.toml"
python3 "$SCRIPT_DIR/prepare_restore_reference.py" \
  --payload "$payload" \
  --migrations-root "$REPO_ROOT/supabase/migrations" \
  --target-head "$RECOVERY_MIGRATION_HEAD" \
  --output "$workdir/recovery/supabase/migrations"
HOME="$workdir/home" SUPABASE_TELEMETRY_DISABLED=1 \
  "$SUPABASE_BIN" migration up --include-all --yes \
    --db-url postgresql://postgres:postgres@127.0.0.1:56322/postgres \
    --workdir "$workdir/recovery"

"$DOCKER_BIN" cp "$APPLICATION_PROBE" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/application_probe.sql"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username postgres \
  --dbname postgres \
  --no-psqlrc \
  --quiet \
  --file /tmp/mylifegraph-restore/application_probe.sql

python3 "$SCRIPT_DIR/replay_deletion_journal.py" render-sql \
  --payload "$payload" \
  --journal-export "$journal_export" \
  --required-through-utc "$recovery_cutoff_utc" \
  --output "$workdir/deletion-replay.sql"
"$DOCKER_BIN" cp "$workdir/deletion-replay.sql" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/deletion-replay.sql"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username postgres \
  --dbname postgres \
  --no-psqlrc \
  --quiet \
  --tuples-only \
  --no-align \
  --file /tmp/mylifegraph-restore/deletion-replay.sql \
    > "$workdir/deletion-replay-report.json"
python3 "$SCRIPT_DIR/replay_deletion_journal.py" validate \
  --payload "$payload" \
  --journal-export "$journal_export" \
  --required-through-utc "$recovery_cutoff_utc" \
  --report "$workdir/deletion-replay-report.json" \
  --output "$workdir/deletion-replay-watermark.json"

"$DOCKER_BIN" cp "$REFERENCE_NORMALIZER" \
  "$CONTAINER_NAME:/tmp/mylifegraph-restore/normalize-optional-legacy.sql"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --no-psqlrc \
  --quiet \
  --file /tmp/mylifegraph-restore/normalize-optional-legacy.sql
"$DOCKER_BIN" exec "$CONTAINER_NAME" pg_dump \
  --username postgres \
  --dbname postgres \
  --schema-only \
  --no-owner \
  --schema auth \
  --schema private \
  --schema public \
  --schema storage > "$workdir/restored-schema.sql"

HOME="$workdir/home" SUPABASE_TELEMETRY_DISABLED=1 \
  "$SUPABASE_BIN" stop --project-id "$RESTORE_PROJECT_ID" --no-backup >/dev/null
started=false
if "$DOCKER_BIN" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  fail "restored database container survived its exact stop boundary"
fi

mkdir -m 0700 "$workdir/reference" "$workdir/reference/supabase"
install -m 0600 "$REFERENCE_TEMPLATE" \
  "$workdir/reference/supabase/config.toml"
python3 "$SCRIPT_DIR/prepare_restore_reference.py" \
  --payload "$payload" \
  --migrations-root "$REPO_ROOT/supabase/migrations" \
  --target-head "$RECOVERY_MIGRATION_HEAD" \
  --output "$workdir/reference/supabase/migrations"
active_project="$REFERENCE_PROJECT_ID"
CONTAINER_NAME="supabase_db_${REFERENCE_PROJECT_ID}"
if "$DOCKER_BIN" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  fail "the exact disposable schema-reference target already exists"
fi
started=true
HOME="$workdir/home" SUPABASE_TELEMETRY_DISABLED=1 \
  "$SUPABASE_BIN" db start --workdir "$workdir/reference"
"$DOCKER_BIN" container inspect "$CONTAINER_NAME" >/dev/null 2>&1 ||
  fail "Supabase CLI did not create the schema-reference database"
"$DOCKER_BIN" cp "$workdir/managed-pre.sql" \
  "$CONTAINER_NAME:/tmp/managed-pre.sql"
"$DOCKER_BIN" cp "$workdir/managed-post.sql" \
  "$CONTAINER_NAME:/tmp/managed-post.sql"
"$DOCKER_BIN" cp "$workdir/managed-conflict-cleanup.sql" \
  "$CONTAINER_NAME:/tmp/managed-conflict-cleanup.sql"
"$DOCKER_BIN" cp "$RESTORE_CREATOR_NORMALIZER" \
  "$CONTAINER_NAME:/tmp/neutralize-restore-creator-defaults.sql"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --variable ON_ERROR_STOP=1 \
  --command 'drop schema auth cascade' \
  --command 'drop schema storage cascade' \
  --file /tmp/neutralize-restore-creator-defaults.sql \
  --file /tmp/managed-pre.sql
HOME="$workdir/home" SUPABASE_TELEMETRY_DISABLED=1 \
  "$SUPABASE_BIN" migration up --local --include-all --yes \
    --workdir "$workdir/reference"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file /tmp/managed-conflict-cleanup.sql \
  --file /tmp/managed-post.sql
"$DOCKER_BIN" cp "$REFERENCE_NORMALIZER" \
  "$CONTAINER_NAME:/tmp/normalize-optional-legacy.sql"
"$DOCKER_BIN" exec "$CONTAINER_NAME" psql \
  --username supabase_admin \
  --dbname postgres \
  --no-psqlrc \
  --quiet \
  --file /tmp/normalize-optional-legacy.sql
"$DOCKER_BIN" exec "$CONTAINER_NAME" pg_dump \
  --username postgres \
  --dbname postgres \
  --schema-only \
  --no-owner \
  --schema auth \
  --schema private \
  --schema public \
  --schema storage > "$workdir/reference-schema.sql"
python3 "$SCRIPT_DIR/compare_schema_dumps.py" \
  --restored "$workdir/restored-schema.sql" \
  --reference "$workdir/reference-schema.sql" \
  --output "$workdir/schema-comparison.json"
verification_args=(
  validate
  --payload "$payload"
  --report "$workdir/report.json"
  --schema-comparison "$workdir/schema-comparison.json"
  --recovery-migration-head "$RECOVERY_MIGRATION_HEAD"
  --output "$workdir/attestation.json"
)
verification_args+=(
  --deletion-replay-watermark "$workdir/deletion-replay-watermark.json"
)
python3 "$SCRIPT_DIR/verify_restored_database.py" "${verification_args[@]}"
[[ ! -L "$attestation_output" ]] || fail "attestation output cannot be a symlink"
install -m 0600 "$workdir/attestation.json" "$attestation_output"
printf 'Isolated Supabase database restore verified.\n'
