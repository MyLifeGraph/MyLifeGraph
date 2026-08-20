#!/usr/bin/env python3
"""Create and verify a bounded Supabase logical-backup manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


PART_NAMES = (
    "roles.sql",
    "managed_schema.sql",
    "schema.sql",
    "data.sql",
    "history_schema.sql",
    "history_data.sql",
    "auth_storage_diff.sql",
    "inventory.json",
    "migration-inventory.json",
    "auth-config-inventory.json",
    "auth-config-recovery.json",
)


class BackupManifestError(ValueError):
    pass


EMPTY_SCHEMA_DIFF = "-- No custom auth/storage schema changes were detected.\n"


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise BackupManifestError("backup manifest is invalid") from exc
    if not isinstance(value, dict):
        raise BackupManifestError("backup manifest is not an object")
    return value


def _create(args: argparse.Namespace) -> None:
    payload = Path(args.payload).resolve(strict=True)
    if re.fullmatch(r"[a-z]{20}", args.project_ref) is None:
        raise BackupManifestError("project ref is invalid")
    if args.retention_class not in {
        "routine",
        "pre_migration",
        "release_candidate",
    }:
        raise BackupManifestError("backup retention class is invalid")
    parts: dict[str, dict[str, object]] = {}
    for name in PART_NAMES:
        path = payload / name
        if not path.is_file() or path.is_symlink():
            raise BackupManifestError(f"backup part is missing: {name}")
        parts[name] = {"sha256": _digest(path), "bytes": path.stat().st_size}
    inventory = _load(payload / "inventory.json")
    expected_inventory_keys = {
        "schema_version",
        "postgres_server_version",
        "extensions",
        "auth_user_count",
        "auth_identity_count",
        "storage_bucket_count",
        "storage_object_count",
        "excluded_storage_relation_counts",
        "data_schemas",
        "table_count",
        "total_row_count",
        "table_row_counts",
        "pilot_participation_gate",
    }
    if set(inventory) != expected_inventory_keys:
        raise BackupManifestError("backup inventory shape is invalid")
    excluded_storage = inventory["excluded_storage_relation_counts"]
    if (
        not isinstance(excluded_storage, dict)
        or set(excluded_storage)
        != {"storage.buckets_vectors", "storage.vector_indexes"}
        or any(
            not isinstance(descriptor, dict)
            or set(descriptor) != {"present", "row_count"}
            or not isinstance(descriptor["present"], bool)
            or not isinstance(descriptor["row_count"], int)
            or isinstance(descriptor["row_count"], bool)
            or descriptor["row_count"] < 0
            or (not descriptor["present"] and descriptor["row_count"] != 0)
            for descriptor in excluded_storage.values()
        )
    ):
        raise BackupManifestError("excluded Storage inventory is invalid")
    if (
        inventory["storage_bucket_count"] != 0
        or inventory["storage_object_count"] != 0
        or any(
            descriptor["row_count"] for descriptor in excluded_storage.values()
        )
    ):
        raise BackupManifestError("non-empty Storage is unsupported")
    migration_inventory = _load(payload / "migration-inventory.json")
    if (
        migration_inventory.get("schema_version")
        != "mylifegraph-migration-inventory-v1"
        or migration_inventory.get("status") != "exact_expected_boundary"
        or migration_inventory.get("expected_head") != args.migration_head
        or migration_inventory.get("actual_head") != args.migration_head
    ):
        raise BackupManifestError("migration inventory is not an exact match")
    auth_inventory = _load(payload / "auth-config-inventory.json")
    if (
        auth_inventory.get("schema_version")
        != "mylifegraph-auth-config-inventory-v1"
        or auth_inventory.get("project_ref") != args.project_ref
        or auth_inventory.get("policy_status")
        not in {"compliant", "noncompliant", "unavailable"}
    ):
        raise BackupManifestError("Auth config inventory is invalid")
    auth_recovery = _load(payload / "auth-config-recovery.json")
    if (
        auth_recovery.get("schema_version")
        != "mylifegraph-auth-config-recovery-v1"
        or auth_recovery.get("project_ref") != args.project_ref
        or auth_recovery.get("capture_status") not in {"captured", "unavailable"}
    ):
        raise BackupManifestError("Auth recovery configuration is invalid")
    manifest = {
        "schema_version": "mylifegraph-supabase-backup-v2",
        "project_ref": args.project_ref,
        "started_at_utc": args.started_at,
        "completed_at_utc": args.completed_at,
        "migration_head": args.migration_head,
        "retention_class": args.retention_class,
        "migration_boundary": {
            "expected_head": migration_inventory["expected_head"],
            "actual_head": migration_inventory["actual_head"],
            "expected_count": migration_inventory["expected_count"],
            "actual_count": migration_inventory["actual_count"],
            "applied_identity_sha256": migration_inventory[
                "applied_identity_sha256"
            ],
            "repository_target_head": migration_inventory[
                "repository_target_head"
            ],
            "repository_target_count": migration_inventory[
                "repository_target_count"
            ],
        },
        "postgres_server_version": inventory["postgres_server_version"],
        "logical_scope": {
            "included_parts": [
                "roles",
                "schema",
                "managed_auth_storage_schema",
                "data",
                "supabase_migrations",
                "auth_storage_diff",
                "auth_config_inventory",
                "auth_config_recovery",
            ],
            "data_schemas_observed": inventory["data_schemas"],
            "extensions_observed": inventory["extensions"],
            "data_excluded_relations": [
                "storage.buckets_vectors",
                "storage.vector_indexes",
            ],
        },
        "supabase_cli_version": args.supabase_version,
        "restic_version": args.restic_version,
        "rpo_hours": 24,
        "target_rto_hours": 4,
        "deletion_replay_required": True,
        "auth_config_policy_status": auth_inventory["policy_status"],
        "inventory": inventory,
        "parts": parts,
    }
    (payload / "backup-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _verify_tree(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve(strict=True)
    manifests = list(root.rglob("backup-manifest.json"))
    if len(manifests) != 1:
        raise BackupManifestError("restored tree must contain exactly one manifest")
    manifest_path = manifests[0]
    manifest = _load(manifest_path)
    if manifest.get("schema_version") != "mylifegraph-supabase-backup-v2":
        raise BackupManifestError("restored manifest version is unsupported")
    if manifest.get("deletion_replay_required") is not True:
        raise BackupManifestError("restored backup does not require deletion replay")
    parts = manifest.get("parts")
    if not isinstance(parts, dict) or set(parts) != set(PART_NAMES):
        raise BackupManifestError("restored backup part inventory is invalid")
    for name in PART_NAMES:
        descriptor = parts[name]
        path = manifest_path.parent / name
        if (
            not isinstance(descriptor, dict)
            or set(descriptor) != {"sha256", "bytes"}
            or not path.is_file()
            or path.is_symlink()
            or path.stat().st_size != descriptor["bytes"]
            or _digest(path) != descriptor["sha256"]
        ):
            raise BackupManifestError(f"restored backup part failed checksum: {name}")


def _snapshot_id(args: argparse.Namespace) -> None:
    try:
        values = [
            json.loads(line) for line in Path(args.input).read_text().splitlines()
        ]
    except (OSError, json.JSONDecodeError) as exc:
        raise BackupManifestError("Restic JSON output is invalid") from exc
    snapshot_ids = [
        value.get("snapshot_id")
        for value in values
        if isinstance(value, dict) and value.get("message_type") == "summary"
    ]
    if (
        len(snapshot_ids) != 1
        or not isinstance(snapshot_ids[0], str)
        or re.fullmatch(r"[0-9a-f]{64}", snapshot_ids[0]) is None
    ):
        raise BackupManifestError("Restic did not return one exact snapshot id")
    print(snapshot_ids[0])


def _ensure_sql_part(args: argparse.Namespace) -> None:
    path = Path(args.path)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags, 0o600)
    except FileExistsError:
        try:
            descriptor = os.open(
                path,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
            )
        except OSError as exc:
            raise BackupManifestError("SQL backup part is not a regular file") from exc
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise BackupManifestError("SQL backup part is not a regular file")
            os.fchmod(descriptor, 0o600)
        finally:
            os.close(descriptor)
        return
    except OSError as exc:
        raise BackupManifestError("SQL backup part cannot be created") from exc
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(EMPTY_SCHEMA_DIFF)
    except OSError as exc:
        raise BackupManifestError("SQL backup part cannot be written") from exc


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="operation", required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--payload", required=True)
    create.add_argument("--project-ref", required=True)
    create.add_argument("--started-at", required=True)
    create.add_argument("--completed-at", required=True)
    create.add_argument("--migration-head", required=True)
    create.add_argument("--retention-class", required=True)
    create.add_argument("--supabase-version", required=True)
    create.add_argument("--restic-version", required=True)
    create.set_defaults(handler=_create)
    verify = subparsers.add_parser("verify-tree")
    verify.add_argument("--root", required=True)
    verify.set_defaults(handler=_verify_tree)
    snapshot = subparsers.add_parser("snapshot-id")
    snapshot.add_argument("--input", required=True)
    snapshot.set_defaults(handler=_snapshot_id)
    ensure_sql = subparsers.add_parser("ensure-sql-part")
    ensure_sql.add_argument("--path", required=True)
    ensure_sql.set_defaults(handler=_ensure_sql_part)
    args = parser.parse_args()
    try:
        args.handler(args)
    except BackupManifestError as exc:
        print(f"backup manifest error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
