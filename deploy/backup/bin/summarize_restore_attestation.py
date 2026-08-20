#!/usr/bin/python3
"""Emit a strict identifier-free restore/replay evidence summary."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


DIGEST = re.compile(r"^[0-9a-f]{64}$")
HEAD = re.compile(r"^[0-9]{14}_[a-z0-9_]+\.sql$")


class EvidenceError(ValueError):
    pass


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise EvidenceError("restore attestation contains a duplicate key")
        value[key] = item
    return value


def summarize(path: Path) -> dict[str, object]:
    raw = path.read_bytes()
    if not raw or len(raw) > 65_536:
        raise EvidenceError("restore attestation size is invalid")
    try:
        value = json.loads(raw, object_pairs_hook=_unique_object)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError("restore attestation is invalid JSON") from exc
    expected = {
        "schema_version",
        "project_ref",
        "migration_head",
        "recovery_migration_head",
        "postgres_source_version",
        "postgres_restore_version",
        "table_count",
        "total_row_count",
        "postconditions",
        "deletion_replay_required",
        "participation_gate",
        "schema_reference_sha256",
        "deletion_replay",
    }
    if (
        not isinstance(value, dict)
        or set(value) != expected
        or value.get("schema_version") != "mylifegraph-restore-attestation-v1"
        or value.get("postconditions") != "passed"
        or HEAD.fullmatch(str(value.get("migration_head"))) is None
        or HEAD.fullmatch(str(value.get("recovery_migration_head"))) is None
        or DIGEST.fullmatch(str(value.get("schema_reference_sha256"))) is None
        or type(value.get("deletion_replay_required")) is not bool
    ):
        raise EvidenceError("restore attestation shape is invalid")
    replay = value["deletion_replay"]
    if value["deletion_replay_required"]:
        replay_keys = {
            "schema_version",
            "project_ref",
            "backup_manifest_sha256",
            "backup_cutoff_utc",
            "journal_capture_through_utc",
            "journal_export_manifest_sha256",
            "journal_source_inventory_sha256",
            "replay_set_sha256",
            "replayed_entry_count",
            "last_replayed_accepted_at",
            "owner_relation_count",
            "postconditions",
        }
        if (
            not isinstance(replay, dict)
            or set(replay) != replay_keys
            or replay.get("schema_version")
            != "mylifegraph-deletion-replay-watermark-v1"
            or replay.get("postconditions") != "passed"
            or type(replay.get("replayed_entry_count")) is not int
            or replay["replayed_entry_count"] < 0
            or any(
                DIGEST.fullmatch(str(replay.get(name))) is None
                for name in (
                    "journal_export_manifest_sha256",
                    "journal_source_inventory_sha256",
                    "replay_set_sha256",
                )
            )
        ):
            raise EvidenceError("deletion replay watermark shape is invalid")
        replay_summary: dict[str, object] = {
            "status": "passed",
            "journal_export_manifest_sha256": replay[
                "journal_export_manifest_sha256"
            ],
            "journal_source_inventory_sha256": replay[
                "journal_source_inventory_sha256"
            ],
            "replay_set_sha256": replay["replay_set_sha256"],
            "replayed_entry_count": replay["replayed_entry_count"],
        }
    else:
        if replay != {"status": "not_applicable_contract_absent"}:
            raise EvidenceError("pre-contract replay status is invalid")
        replay_summary = {"status": "not_applicable_contract_absent"}
    return {
        "schema_version": "mylifegraph-restore-evidence-v1",
        "restore_attestation_sha256": hashlib.sha256(raw).hexdigest(),
        "schema_reference_sha256": value["schema_reference_sha256"],
        "migration_head": value["migration_head"],
        "recovery_migration_head": value["recovery_migration_head"],
        "postconditions": "passed",
        "deletion_replay": replay_summary,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: summarize_restore_attestation.py <attestation>", file=sys.stderr)
        return 64
    try:
        print(json.dumps(summarize(Path(sys.argv[1])), separators=(",", ":")))
    except (EvidenceError, OSError, TypeError, ValueError) as exc:
        print(f"restore evidence error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
