#!/usr/bin/env python3
"""Render and attest restore-only replay of the encrypted deletion journal."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID


EXPORT_VERSION = "mylifegraph-deletion-journal-export-v1"
JOURNAL_VERSION = "account-deletion-journal-v2"
REPORT_VERSION = "mylifegraph-deletion-replay-report-v1"
WATERMARK_VERSION = "mylifegraph-deletion-replay-watermark-v1"
BACKUP_VERSION = "mylifegraph-supabase-backup-v2"
TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
SHA256 = re.compile(r"[0-9a-f]{64}")
MAX_ENTRIES = 100_000
MAX_ENTRY_BYTES = 4096
MAX_EXPORT_BYTES = MAX_ENTRIES * MAX_ENTRY_BYTES


class DeletionReplayError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class JournalEntry:
    accepted_at: datetime
    accepted_at_text: str
    deletion_id: str
    user_id: str
    payload_sha256: str
    object_key: str


@dataclass(frozen=True, slots=True)
class ReplayInputs:
    backup_manifest: dict[str, Any]
    backup_manifest_sha256: str
    export_manifest: dict[str, Any]
    export_manifest_sha256: str
    entries_sha256: str
    entries: tuple[JournalEntry, ...]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise DeletionReplayError("deletion replay JSON is invalid") from exc
    if not isinstance(value, dict):
        raise DeletionReplayError("deletion replay JSON must be an object")
    return value


def _parse_time(value: Any, *, name: str) -> datetime:
    if not isinstance(value, str) or TIMESTAMP.fullmatch(value) is None:
        raise DeletionReplayError(f"{name} must be an exact UTC-second timestamp")
    parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)
    if parsed.year < 2025:
        raise DeletionReplayError(f"{name} is outside the supported range")
    return parsed


def _require_private(path: Path, *, directory: bool) -> None:
    info = path.lstat()
    expected_type = stat.S_ISDIR if directory else stat.S_ISREG
    if path.is_symlink() or not expected_type(info.st_mode):
        raise DeletionReplayError("deletion journal input type is invalid")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise DeletionReplayError("deletion journal input must be owner-only")


def _canonical_uuid(value: Any, *, name: str) -> str:
    if not isinstance(value, str):
        raise DeletionReplayError(f"{name} is invalid")
    try:
        parsed = UUID(value)
    except ValueError as exc:
        raise DeletionReplayError(f"{name} is invalid") from exc
    if str(parsed) != value or parsed.version != 4:
        raise DeletionReplayError(f"{name} must be a canonical UUIDv4")
    return value


def _load_inputs(
    payload: Path,
    journal_export: Path,
    required_through_utc: str,
) -> ReplayInputs:
    _require_private(journal_export, directory=True)
    children = {path.name for path in journal_export.iterdir()}
    if children != {"journal-export.json", "entries.jsonl"}:
        raise DeletionReplayError("deletion journal export has unexpected files")
    export_path = journal_export / "journal-export.json"
    entries_path = journal_export / "entries.jsonl"
    _require_private(export_path, directory=False)
    _require_private(entries_path, directory=False)
    if entries_path.stat().st_size > MAX_EXPORT_BYTES:
        raise DeletionReplayError("deletion journal export is too large")

    backup_path = payload / "backup-manifest.json"
    backup = _load_json(backup_path)
    export = _load_json(export_path)
    expected_export_keys = {
        "schema_version",
        "contract_version",
        "captured_from_utc",
        "captured_through_utc",
        "entry_count",
        "entries_file",
        "entries_sha256",
        "list_pass_count",
        "source_bucket_url",
        "source_inventory_sha256",
        "source_kms_key_arn",
        "source_object_count",
        "source_objects_through_cutoff",
    }
    if (
        backup.get("schema_version") != BACKUP_VERSION
        or not isinstance(backup.get("migration_head"), str)
        or re.fullmatch(
            r"[0-9]{14}_[a-z0-9_]+\.sql",
            backup["migration_head"],
        )
        is None
        or set(export) != expected_export_keys
        or export.get("schema_version") != EXPORT_VERSION
        or export.get("contract_version") != JOURNAL_VERSION
        or export.get("entries_file") != "entries.jsonl"
        or not isinstance(export.get("entry_count"), int)
        or not 0 <= export["entry_count"] <= MAX_ENTRIES
        or not isinstance(export.get("entries_sha256"), str)
        or SHA256.fullmatch(export["entries_sha256"]) is None
        or export.get("list_pass_count") != 2
        or not isinstance(export.get("source_bucket_url"), str)
        or re.fullmatch(
            r"https://[a-z0-9][a-z0-9.-]+\.s3\.[a-z0-9-]+\.amazonaws\.com",
            export["source_bucket_url"],
        )
        is None
        or not isinstance(export.get("source_inventory_sha256"), str)
        or SHA256.fullmatch(export["source_inventory_sha256"]) is None
        or not isinstance(export.get("source_object_count"), int)
        or not isinstance(export.get("source_kms_key_arn"), str)
        or re.fullmatch(
            r"arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}",
            export["source_kms_key_arn"],
        )
        is None
        or not 0 <= export["source_object_count"] <= MAX_ENTRIES
        or export.get("source_objects_through_cutoff") != export["entry_count"]
    ):
        raise DeletionReplayError("deletion journal export contract is invalid")
    entries_sha256 = _sha256(entries_path)
    if entries_sha256 != export["entries_sha256"]:
        raise DeletionReplayError("deletion journal entry checksum differs")

    backup_started = _parse_time(
        backup.get("started_at_utc"),
        name="backup started_at_utc",
    )
    backup_completed = _parse_time(
        backup.get("completed_at_utc"),
        name="backup completed_at_utc",
    )
    captured_from = _parse_time(
        export["captured_from_utc"],
        name="journal captured_from_utc",
    )
    captured_through = _parse_time(
        export["captured_through_utc"],
        name="journal captured_through_utc",
    )
    required_through = _parse_time(
        required_through_utc,
        name="required recovery cutoff",
    )
    if (
        backup_completed < backup_started
        or captured_through < captured_from
        or captured_from > backup_started
        or captured_through < backup_completed
        or captured_through != required_through
        or captured_through > datetime.now(UTC) + timedelta(minutes=5)
    ):
        raise DeletionReplayError("deletion journal export does not cover the backup")

    entries: list[JournalEntry] = []
    seen_users: set[str] = set()
    seen_deletions: set[str] = set()
    previous_identity: tuple[datetime, str] | None = None
    with entries_path.open("rb") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            if len(raw_line) > MAX_ENTRY_BYTES or not raw_line.endswith(b"\n"):
                raise DeletionReplayError("deletion journal line framing is invalid")
            try:
                line = raw_line[:-1].decode("ascii")
                value = json.loads(line)
            except (UnicodeError, json.JSONDecodeError) as exc:
                raise DeletionReplayError("deletion journal entry is invalid") from exc
            if not isinstance(value, dict) or set(value) != {
                "accepted_at",
                "contract_version",
                "deletion_id",
                "user_id",
            }:
                raise DeletionReplayError("deletion journal entry shape is invalid")
            canonical = json.dumps(
                value,
                ensure_ascii=True,
                separators=(",", ":"),
                sort_keys=True,
            )
            if line != canonical or value["contract_version"] != JOURNAL_VERSION:
                raise DeletionReplayError("deletion journal entry is not canonical")
            accepted_at = _parse_time(
                value["accepted_at"],
                name=f"entry {line_number} accepted_at",
            )
            deletion_id = _canonical_uuid(
                value["deletion_id"],
                name=f"entry {line_number} deletion_id",
            )
            user_id = _canonical_uuid(
                value["user_id"],
                name=f"entry {line_number} user_id",
            )
            if accepted_at > captured_through:
                raise DeletionReplayError("deletion journal entry is after its capture")
            identity = (accepted_at, deletion_id)
            if previous_identity is not None and identity <= previous_identity:
                raise DeletionReplayError("deletion journal entries are not strictly sorted")
            if user_id in seen_users or deletion_id in seen_deletions:
                raise DeletionReplayError("deletion journal contains duplicate identities")
            previous_identity = identity
            seen_users.add(user_id)
            seen_deletions.add(deletion_id)
            payload_sha256 = hashlib.sha256(raw_line[:-1]).hexdigest()
            entries.append(
                JournalEntry(
                    accepted_at=accepted_at,
                    accepted_at_text=value["accepted_at"],
                    deletion_id=deletion_id,
                    user_id=user_id,
                    payload_sha256=payload_sha256,
                    object_key=(
                        f"deletions/v2/{accepted_at:%Y/%m}/{deletion_id}/"
                        f"{payload_sha256}.json"
                    ),
                )
            )
    if len(entries) != export["entry_count"]:
        raise DeletionReplayError("deletion journal entry count differs")
    return ReplayInputs(
        backup_manifest=backup,
        backup_manifest_sha256=_sha256(backup_path),
        export_manifest=export,
        export_manifest_sha256=_sha256(export_path),
        entries_sha256=entries_sha256,
        entries=tuple(entries),
    )


def _sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def render_sql(inputs: ReplayInputs) -> str:
    replay_calls = "\n".join(
        "  perform public.replay_account_deletion_v2("
        f"{_sql_literal(entry.user_id)}::uuid,"
        f"{_sql_literal(entry.deletion_id)}::uuid,"
        f"{_sql_literal(entry.accepted_at_text)}::timestamptz,"
        f"{_sql_literal(entry.object_key)}::text,"
        f"{_sql_literal(entry.payload_sha256)}::text,"
        f"{_sql_literal(inputs.export_manifest['captured_through_utc'])}::timestamptz"
        ");"
        for entry in inputs.entries
    )
    expected_rows = ",\n".join(
        "  ("
        f"{_sql_literal(entry.user_id)}::uuid,"
        f"{_sql_literal(entry.deletion_id)}::uuid,"
        f"{_sql_literal(entry.accepted_at_text)}::timestamptz,"
        f"{_sql_literal(entry.object_key)}::text,"
        f"{_sql_literal(entry.payload_sha256)}::text"
        ")"
        for entry in inputs.entries
    )
    expected_insert = (
        "insert into mylifegraph_expected_deletions values\n" + expected_rows + ";"
        if expected_rows
        else ""
    )
    return f"""\\set ON_ERROR_STOP on
begin;
set local role mylifegraph_deletion_replayer;
do $mylifegraph_replay$
begin
{replay_calls}
end
$mylifegraph_replay$;
commit;

begin;
create temporary table mylifegraph_expected_deletions (
  user_id uuid primary key,
  deletion_id uuid not null unique,
  accepted_at timestamptz not null,
  object_key text not null,
  payload_sha256 text not null
) on commit drop;
{expected_insert}

create temporary table mylifegraph_owner_checks (
  relation_name text primary key,
  violations bigint not null
) on commit drop;

do $mylifegraph_owner_checks$
declare
  relation record;
  replay_user_ids text[];
  remaining bigint;
begin
  select coalesce(array_agg(user_id::text), array[]::text[])
  into replay_user_ids
  from mylifegraph_expected_deletions;
  for relation in
    select namespace.nspname as schema_name, class.relname as table_name
    from pg_catalog.pg_class as class
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = class.relnamespace
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = class.oid
     and attribute.attname = 'user_id'
     and attribute.attnum > 0
     and not attribute.attisdropped
    where namespace.nspname = 'public'
      and class.relkind in ('r', 'p')
      and class.relname <> 'account_deletion_intents'
  loop
    execute format(
      'select count(*) from %I.%I where user_id::text = any ($1)',
      relation.schema_name,
      relation.table_name
    ) into remaining using replay_user_ids;
    insert into mylifegraph_owner_checks values (
      relation.schema_name || '.' || relation.table_name,
      remaining
    );
  end loop;
end
$mylifegraph_owner_checks$;

select jsonb_build_object(
  'schema_version', '{REPORT_VERSION}',
  'requested_count', (select count(*) from mylifegraph_expected_deletions),
  'completed_receipt_count', (
    select count(*)
    from mylifegraph_expected_deletions as expected
    join public.account_deletion_intents as intent
      on intent.user_id = expected.user_id
     and intent.deletion_id = expected.deletion_id
     and intent.accepted_at = expected.accepted_at
     and intent.journal_object_key = expected.object_key
     and intent.journal_payload_sha256 = expected.payload_sha256
     and intent.state = 'completed'
  ),
  'receipt_mismatch_count', (
    select count(*)
    from mylifegraph_expected_deletions as expected
    left join public.account_deletion_intents as intent
      on intent.user_id = expected.user_id
    where intent.deletion_id is distinct from expected.deletion_id
       or intent.accepted_at is distinct from expected.accepted_at
       or intent.journal_object_key is distinct from expected.object_key
       or intent.journal_payload_sha256 is distinct from expected.payload_sha256
       or intent.state is distinct from 'completed'
  ),
  'auth_user_remaining', (
    select count(*) from auth.users
    where id in (select user_id from mylifegraph_expected_deletions)
  ),
  'auth_identity_remaining', (
    select count(*) from auth.identities
    where user_id in (select user_id from mylifegraph_expected_deletions)
  ),
  'profile_remaining', (
    select count(*) from public.profiles
    where id in (select user_id from mylifegraph_expected_deletions)
  ),
  'owner_relation_count', (select count(*) from mylifegraph_owner_checks),
  'owner_rows_remaining', (
    select coalesce(sum(violations), 0) from mylifegraph_owner_checks
  ),
  'storage_objects_remaining', (select count(*) from storage.objects)
)::text;
commit;
"""


def validate_report(inputs: ReplayInputs, report_path: Path) -> dict[str, Any]:
    report = _load_json(report_path)
    expected_keys = {
        "schema_version",
        "requested_count",
        "completed_receipt_count",
        "receipt_mismatch_count",
        "auth_user_remaining",
        "auth_identity_remaining",
        "profile_remaining",
        "owner_relation_count",
        "owner_rows_remaining",
        "storage_objects_remaining",
    }
    count = len(inputs.entries)
    if (
        set(report) != expected_keys
        or report.get("schema_version") != REPORT_VERSION
        or report.get("requested_count") != count
        or report.get("completed_receipt_count") != count
        or not isinstance(report.get("owner_relation_count"), int)
        or report["owner_relation_count"] < 1
    ):
        raise DeletionReplayError("deletion replay report shape is invalid")
    for name in (
        "receipt_mismatch_count",
        "auth_user_remaining",
        "auth_identity_remaining",
        "profile_remaining",
        "owner_rows_remaining",
        "storage_objects_remaining",
    ):
        if report.get(name) != 0:
            raise DeletionReplayError(f"deletion replay postcondition failed: {name}")
    last_accepted = (
        inputs.entries[-1].accepted_at_text if inputs.entries else None
    )
    return {
        "schema_version": WATERMARK_VERSION,
        "project_ref": inputs.backup_manifest["project_ref"],
        "backup_manifest_sha256": inputs.backup_manifest_sha256,
        "backup_cutoff_utc": inputs.backup_manifest["started_at_utc"],
        "journal_capture_through_utc": inputs.export_manifest[
            "captured_through_utc"
        ],
        "journal_export_manifest_sha256": inputs.export_manifest_sha256,
        "journal_source_inventory_sha256": inputs.export_manifest[
            "source_inventory_sha256"
        ],
        "replay_set_sha256": inputs.entries_sha256,
        "replayed_entry_count": count,
        "last_replayed_accepted_at": last_accepted,
        "owner_relation_count": report["owner_relation_count"],
        "postconditions": "passed",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="operation", required=True)
    render = subparsers.add_parser("render-sql")
    render.add_argument("--payload", required=True)
    render.add_argument("--journal-export", required=True)
    render.add_argument("--required-through-utc", required=True)
    render.add_argument("--output", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--payload", required=True)
    validate.add_argument("--journal-export", required=True)
    validate.add_argument("--required-through-utc", required=True)
    validate.add_argument("--report", required=True)
    validate.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        payload = Path(args.payload).resolve(strict=True)
        journal_export = Path(args.journal_export).resolve(strict=True)
        inputs = _load_inputs(
            payload,
            journal_export,
            args.required_through_utc,
        )
        output = Path(args.output)
        if output.exists() and output.is_symlink():
            raise DeletionReplayError("deletion replay output cannot be a symlink")
        if args.operation == "render-sql":
            output.write_text(render_sql(inputs), encoding="utf-8")
        else:
            watermark = validate_report(inputs, Path(args.report))
            output.write_text(
                json.dumps(watermark, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        output.chmod(0o600)
    except (
        DeletionReplayError,
        OSError,
        UnicodeError,
        KeyError,
        TypeError,
        ValueError,
    ) as exc:
        print(f"deletion replay error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
