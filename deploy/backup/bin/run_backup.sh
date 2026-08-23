#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-/usr/local/bin/supabase}"
RESTIC_BIN="${RESTIC_BIN:-/opt/mylifegraph/restic/current/restic}"
PSQL_BIN="${PSQL_BIN:-/usr/bin/psql}"
SUPABASE_EXPECTED_VERSION="${SUPABASE_EXPECTED_VERSION:-2.107.0}"
RESTIC_EXPECTED_VERSION="${RESTIC_EXPECTED_VERSION:-0.19.1}"
RUN_DATABASE_RESTORE_REHEARSAL="${RUN_DATABASE_RESTORE_REHEARSAL:-false}"
BACKUP_RETENTION_CLASS="${BACKUP_RETENTION_CLASS:-routine}"
CLEAN_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

fail() {
  printf 'Supabase backup error: %s\n' "$1" >&2
  exit 1
}

[[ "$(id -u)" -ne 0 ]] || fail "backup runner must not run as root"
for name in PILOT_SUPABASE_PROJECT_REF PILOT_PUBLIC_APP_ORIGIN PILOT_EXPECTED_MIGRATION_HEAD TURNSTILE_SITE_KEY SUPABASE_ACCESS_TOKEN SUPABASE_DB_URL SUPABASE_DB_PASSWORD RESTIC_REPOSITORY RESTIC_PASSWORD_FILE BACKUP_HEARTBEAT_CURL_CONFIG; do
  [[ -n "${!name:-}" ]] || fail "required protected setting is missing: $name"
done
[[ "$PILOT_SUPABASE_PROJECT_REF" =~ ^[a-z]{20}$ ]] || fail "pilot project ref is invalid"
[[ "$RUN_DATABASE_RESTORE_REHEARSAL" == true || "$RUN_DATABASE_RESTORE_REHEARSAL" == false ]] ||
  fail "RUN_DATABASE_RESTORE_REHEARSAL must be exact true or false"
[[ "$BACKUP_RETENTION_CLASS" =~ ^(routine|pre_migration|release_candidate)$ ]] ||
  fail "BACKUP_RETENTION_CLASS is invalid"

# Copy the protected runner input into non-exported shell variables, then
# remove every broad workflow variable before invoking any child process.
pilot_project_ref="$PILOT_SUPABASE_PROJECT_REF"
pilot_public_origin="$PILOT_PUBLIC_APP_ORIGIN"
pilot_expected_migration_head="$PILOT_EXPECTED_MIGRATION_HEAD"
turnstile_site_key="$TURNSTILE_SITE_KEY"
supabase_access_token="$SUPABASE_ACCESS_TOKEN"
supabase_db_url="$SUPABASE_DB_URL"
supabase_db_password="$SUPABASE_DB_PASSWORD"
restic_repository="$RESTIC_REPOSITORY"
restic_password_file="$RESTIC_PASSWORD_FILE"
heartbeat_config="$BACKUP_HEARTBEAT_CURL_CONFIG"
restore_rehearsal="$RUN_DATABASE_RESTORE_REHEARSAL"
retention_class="$BACKUP_RETENTION_CLASS"
deletion_journal_bucket_url="${ACCOUNT_DELETION_JOURNAL_S3_URL:-}"
deletion_journal_region="${ACCOUNT_DELETION_JOURNAL_S3_REGION:-}"
deletion_journal_kms_key_arn="${ACCOUNT_DELETION_JOURNAL_S3_KMS_KEY_ARN:-}"
deletion_journal_read_access_key_id="${DELETION_JOURNAL_READ_ACCESS_KEY_ID:-}"
deletion_journal_read_secret_access_key="${DELETION_JOURNAL_READ_SECRET_ACCESS_KEY:-}"
deletion_journal_read_session_token="${DELETION_JOURNAL_READ_SESSION_TOKEN:-}"
backup_aws_access_key_id="${AWS_ACCESS_KEY_ID:-}"
backup_aws_secret_access_key="${AWS_SECRET_ACCESS_KEY:-}"
backup_aws_session_token="${AWS_SESSION_TOKEN:-}"
backup_aws_region="${AWS_DEFAULT_REGION:-${AWS_REGION:-}}"
unset PILOT_SUPABASE_PROJECT_REF PILOT_PUBLIC_APP_ORIGIN
unset PILOT_EXPECTED_MIGRATION_HEAD SUPABASE_ACCESS_TOKEN
unset TURNSTILE_SITE_KEY
unset SUPABASE_DB_URL SUPABASE_DB_PASSWORD RESTIC_REPOSITORY
unset RESTIC_PASSWORD_FILE BACKUP_HEARTBEAT_CURL_CONFIG
unset RUN_DATABASE_RESTORE_REHEARSAL BACKUP_RETENTION_CLASS
unset ACCOUNT_DELETION_JOURNAL_S3_URL ACCOUNT_DELETION_JOURNAL_S3_REGION
unset ACCOUNT_DELETION_JOURNAL_S3_KMS_KEY_ARN
unset DELETION_JOURNAL_READ_ACCESS_KEY_ID
unset DELETION_JOURNAL_READ_SECRET_ACCESS_KEY
unset DELETION_JOURNAL_READ_SESSION_TOKEN
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset AWS_DEFAULT_REGION AWS_REGION PGPASSWORD

SUPABASE_BIN="$(command -v -- "$SUPABASE_BIN" 2>/dev/null || true)"
RESTIC_BIN="$(command -v -- "$RESTIC_BIN" 2>/dev/null || true)"
PSQL_BIN="$(command -v -- "$PSQL_BIN" 2>/dev/null || true)"
CURL_BIN="$(command -v -- curl 2>/dev/null || true)"
[[ -n "$SUPABASE_BIN" && -x "$SUPABASE_BIN" && -n "$RESTIC_BIN" && -x "$RESTIC_BIN" ]] ||
  fail "pinned backup tools are unavailable"
[[ -n "$PSQL_BIN" && -x "$PSQL_BIN" ]] || fail "psql is unavailable"
[[ -n "$CURL_BIN" && -x "$CURL_BIN" ]] || fail "curl is unavailable"
[[ "$restic_repository" =~ ^(s3|sftp|rest|azure|gs|b2|rclone):[^[:space:]]+$ ]] ||
  fail "Restic repository must use an approved off-host backend"
for protected_file in "$restic_password_file" "$heartbeat_config"; do
  [[ -f "$protected_file" && ! -L "$protected_file" && -r "$protected_file" ]] ||
    fail "protected backup file is not a readable regular file"
  protected_mode="$(stat -c '%a' "$protected_file")"
  [[ "$protected_mode" =~ ^[0-7]{3,4}$ ]] ||
    fail "protected backup file mode is invalid"
  if (( (8#$protected_mode & 077) != 0 )); then
    fail "protected backup file is accessible outside its owner"
  fi
done

workdir="$(mktemp -d /tmp/mylifegraph-supabase-backup.XXXXXX)"
chmod 0700 "$workdir"
cleanup() {
  case "$workdir" in
    /tmp/mylifegraph-supabase-backup.*) rm -rf -- "$workdir" ;;
    *) printf 'Refusing unsafe backup cleanup path.\n' >&2 ;;
  esac
}
trap cleanup EXIT
payload="$workdir/payload"
verify_root="$workdir/verified-restore"
mkdir -m 0700 "$payload" "$verify_root" "$workdir/supabase-home"

clean_env=(/usr/bin/env -i PATH="$CLEAN_PATH" HOME="$workdir/supabase-home" LANG=C.UTF-8 LC_ALL=C.UTF-8)
supabase_db_env=("${clean_env[@]}" PGPASSWORD="$supabase_db_password" SUPABASE_TELEMETRY_DISABLED=1)
restic_env=("${clean_env[@]}" RESTIC_REPOSITORY="$restic_repository" RESTIC_PASSWORD_FILE="$restic_password_file")
for credential_name in backup_aws_access_key_id backup_aws_secret_access_key backup_aws_session_token backup_aws_region; do
  credential_value="${!credential_name}"
  [[ -n "$credential_value" ]] || continue
  case "$credential_name" in
    backup_aws_access_key_id) restic_env+=(AWS_ACCESS_KEY_ID="$credential_value") ;;
    backup_aws_secret_access_key) restic_env+=(AWS_SECRET_ACCESS_KEY="$credential_value") ;;
    backup_aws_session_token) restic_env+=(AWS_SESSION_TOKEN="$credential_value") ;;
    backup_aws_region) restic_env+=(AWS_DEFAULT_REGION="$credential_value") ;;
  esac
done

[[ "$("${clean_env[@]}" SUPABASE_TELEMETRY_DISABLED=1 "$SUPABASE_BIN" --version)" == "$SUPABASE_EXPECTED_VERSION" ]] ||
  fail "Supabase CLI version differs from the approved pin"
restic_version="$("${clean_env[@]}" "$RESTIC_BIN" version | awk 'NR == 1 {print $2}')"
[[ "$restic_version" == "$RESTIC_EXPECTED_VERSION" ]] ||
  fail "Restic version differs from the approved pin"

"${clean_env[@]}" python3 - "$supabase_db_url" "$pilot_project_ref" <<'PY'
import re, sys
from urllib.parse import urlsplit
parsed = urlsplit(sys.argv[1])
project_ref = sys.argv[2]
if parsed.scheme not in {"postgres", "postgresql"}:
    raise SystemExit("database URL must use PostgreSQL")
if parsed.password is not None or not parsed.username or not parsed.hostname:
    raise SystemExit("database URL must have a user/host and no embedded password")
is_session_pooler = (
    parsed.username == f"postgres.{project_ref}"
    and parsed.hostname.endswith(".pooler.supabase.com")
)
is_direct = (
    parsed.username == "postgres"
    and parsed.hostname == f"db.{project_ref}.supabase.co"
)
if not (is_session_pooler or is_direct):
    raise SystemExit("database URL is not exactly bound to the pilot project ref")
if parsed.port != 5432 or parsed.path != "/postgres":
    raise SystemExit("database URL must use the reviewed session/direct port and database")
if parsed.query != "sslmode=require" or parsed.fragment:
    raise SystemExit("database URL must require TLS and contain no fragment")
PY

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ "$pilot_expected_migration_head" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]] ||
  fail "expected migration head is invalid"

"${supabase_db_env[@]}" "$SUPABASE_BIN" db dump --db-url "$supabase_db_url" --file "$payload/roles.sql" --role-only
"${supabase_db_env[@]}" "$SUPABASE_BIN" db dump --db-url "$supabase_db_url" \
  --file "$payload/managed_schema.sql" --schema auth,storage --keep-comments
"${supabase_db_env[@]}" "$SUPABASE_BIN" db dump --db-url "$supabase_db_url" --file "$payload/schema.sql" --keep-comments
"${supabase_db_env[@]}" "$SUPABASE_BIN" db dump --db-url "$supabase_db_url" --file "$payload/data.sql" \
  --use-copy --data-only \
  --exclude storage.buckets_vectors \
  --exclude storage.vector_indexes
"${supabase_db_env[@]}" "$SUPABASE_BIN" db dump --db-url "$supabase_db_url" \
  --file "$payload/history_schema.sql" --schema supabase_migrations
"${supabase_db_env[@]}" "$SUPABASE_BIN" db dump --db-url "$supabase_db_url" \
  --file "$payload/history_data.sql" --schema supabase_migrations \
  --use-copy --data-only
"${supabase_db_env[@]}" "$SUPABASE_BIN" db diff --db-url "$supabase_db_url" \
  --schema auth,storage --output "$payload/auth_storage_diff.sql"
"${clean_env[@]}" python3 "$SCRIPT_DIR/backup_manifest.py" ensure-sql-part \
  --path "$payload/auth_storage_diff.sql"
"${supabase_db_env[@]}" "$PSQL_BIN" "$supabase_db_url" \
  --no-psqlrc --quiet --tuples-only --no-align --set ON_ERROR_STOP=1 \
  --file "$SCRIPT_DIR/inventory_excluded_storage.sql" \
  > "$workdir/excluded-storage-counts.tsv"

"${clean_env[@]}" python3 "$SCRIPT_DIR/inspect_dump.py" "$payload/data.sql" \
  --schema-dump "$payload/schema.sql" \
  --excluded-storage-counts "$workdir/excluded-storage-counts.tsv" \
  --output "$payload/inventory.json"
migration_head="$("${clean_env[@]}" python3 "$SCRIPT_DIR/inspect_migration_history.py" "$payload/history_data.sql" \
  --migrations-root "$REPO_ROOT/supabase/migrations" \
  --expected-head "$pilot_expected_migration_head" \
  --output "$payload/migration-inventory.json")"
[[ "$migration_head" == "$pilot_expected_migration_head" ]] ||
  fail "migration inventory returned an unexpected boundary"
"${clean_env[@]}" SUPABASE_ACCESS_TOKEN="$supabase_access_token" \
  python3 "$SCRIPT_DIR/fetch_auth_config_inventory.py" \
  --project-ref "$pilot_project_ref" \
  --expected-app-origin "$pilot_public_origin" \
  --expected-turnstile-site-key "$turnstile_site_key" \
  --output "$payload/auth-config-inventory.json" \
  --recovery-output "$payload/auth-config-recovery.json"
supabase_access_token=""
auth_config_policy_status="$("${clean_env[@]}" python3 - "$payload/auth-config-inventory.json" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
status = value.get("policy_status")
if status not in {"compliant", "noncompliant", "unavailable"}:
    raise SystemExit("invalid Auth config policy status")
print(status)
PY
)"
completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"${clean_env[@]}" python3 "$SCRIPT_DIR/backup_manifest.py" create \
  --payload "$payload" \
  --project-ref "$pilot_project_ref" \
  --started-at "$started_at" \
  --completed-at "$completed_at" \
  --migration-head "$migration_head" \
  --retention-class "$retention_class" \
  --supabase-version "$SUPABASE_EXPECTED_VERSION" \
  --restic-version "$RESTIC_EXPECTED_VERSION"

supabase_db_password=""
supabase_db_env=("${clean_env[@]}" SUPABASE_TELEMETRY_DISABLED=1)
retention_tag="mylifegraph-retention-${retention_class//_/-}"
(
  cd "$workdir"
  "${restic_env[@]}" "$RESTIC_BIN" backup --json \
    --host mylifegraph-pilot-backup \
    --tag mylifegraph-supabase-v1 \
    --tag "$retention_tag" payload > "$workdir/restic-result.jsonl"
)
snapshot_id="$(
  "${clean_env[@]}" python3 "$SCRIPT_DIR/backup_manifest.py" snapshot-id \
    --input "$workdir/restic-result.jsonl"
)"
"${restic_env[@]}" "$RESTIC_BIN" restore "$snapshot_id" --target "$verify_root"
"${clean_env[@]}" python3 "$SCRIPT_DIR/backup_manifest.py" verify-tree --root "$verify_root"
"${restic_env[@]}" "$RESTIC_BIN" check --read-data
"${restic_env[@]}" "$RESTIC_BIN" forget --host mylifegraph-pilot-backup \
  --tag mylifegraph-supabase-v1 --keep-within 7d --keep-weekly 4 \
  --keep-tag mylifegraph-retention-pre-migration \
  --keep-tag mylifegraph-retention-release-candidate
"${restic_env[@]}" "$RESTIC_BIN" forget --host mylifegraph-pilot-backup \
  --tag mylifegraph-retention-pre-migration --keep-within 35d
"${restic_env[@]}" "$RESTIC_BIN" forget --host mylifegraph-pilot-backup \
  --tag mylifegraph-retention-release-candidate --keep-within 14d
"${restic_env[@]}" "$RESTIC_BIN" prune

database_restore_status="not_scheduled"
restore_evidence_json="null"
if [[ "$restore_rehearsal" == true ]]; then
  deletion_journal_recovery_cutoff="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  journal_export="$workdir/deletion-journal-export"
  if [[ -n "$deletion_journal_bucket_url" \
        && -n "$deletion_journal_region" \
        && -n "$deletion_journal_kms_key_arn" \
        && -n "$deletion_journal_read_access_key_id" \
        && -n "$deletion_journal_read_secret_access_key" ]] \
    && "${clean_env[@]}" \
      DELETION_JOURNAL_READ_ACCESS_KEY_ID="$deletion_journal_read_access_key_id" \
      DELETION_JOURNAL_READ_SECRET_ACCESS_KEY="$deletion_journal_read_secret_access_key" \
      DELETION_JOURNAL_READ_SESSION_TOKEN="$deletion_journal_read_session_token" \
      python3 "$SCRIPT_DIR/export_deletion_journal.py" \
        --bucket-url "$deletion_journal_bucket_url" \
        --region "$deletion_journal_region" \
        --kms-key-arn "$deletion_journal_kms_key_arn" \
        --required-from-utc "$started_at" \
        --recovery-cutoff-utc "$deletion_journal_recovery_cutoff" \
        --snapshot-data-sql "$verify_root/payload/data.sql" \
        --output "$journal_export" \
    && "${clean_env[@]}" SUPABASE_BIN="$SUPABASE_BIN" \
      SUPABASE_EXPECTED_VERSION="$SUPABASE_EXPECTED_VERSION" \
      "$SCRIPT_DIR/run_restore_rehearsal.sh" \
        "$verify_root/payload" "$workdir/restore-attestation.json" \
        "$journal_export" "$deletion_journal_recovery_cutoff"; then
    database_restore_status="passed"
    restore_evidence_json="$(
      "${clean_env[@]}" python3 \
        "$SCRIPT_DIR/summarize_restore_attestation.py" \
        "$workdir/restore-attestation.json"
    )"
  else
    database_restore_status="failed"
  fi
  deletion_journal_read_access_key_id=""
  deletion_journal_read_secret_access_key=""
  deletion_journal_read_session_token=""
fi

"${clean_env[@]}" python3 - "$snapshot_id" "$completed_at" \
  "$auth_config_policy_status" "$database_restore_status" \
  "$restore_evidence_json" > "$workdir/heartbeat.json" <<'PY'
import json
import sys

evidence = json.loads(sys.argv[5])
if evidence is not None and not isinstance(evidence, dict):
    raise SystemExit("restore evidence summary is invalid")
print(json.dumps({
    "status": "ok",
    "snapshot": sys.argv[1],
    "completed_at": sys.argv[2],
    "auth_config_policy_status": sys.argv[3],
    "database_restore_status": sys.argv[4],
    "restore_evidence": evidence,
}, separators=(",", ":")))
PY
"${clean_env[@]}" "$CURL_BIN" --disable --silent --show-error --fail \
  --config "$heartbeat_config" \
  --header 'Content-Type: application/json' \
  --data-binary "@$workdir/heartbeat.json" >/dev/null
printf 'Encrypted Supabase backup verified: %s %s\n' \
  "$completed_at" "${snapshot_id:0:12}"
if [[ "$auth_config_policy_status" != "compliant" ]]; then
  printf 'Supabase Auth configuration drift: %s (backup still completed).\n' \
    "$auth_config_policy_status" >&2
  exit 2
fi
if [[ "$database_restore_status" == "failed" ]]; then
  printf 'Isolated database restore rehearsal failed after backup completion.\n' >&2
  exit 3
fi
