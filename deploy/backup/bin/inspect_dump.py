#!/usr/bin/env python3
"""Inspect aggregate Auth/Storage COPY counts without retaining row values."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


COPY_PATTERN = re.compile(
    r'^COPY (?:(?:"(?P<qschema>[^"]+)"\."(?P<qtable>[^"]+)")|'
    r"(?P<schema>[a-z_][a-z0-9_]*)\.(?P<table>[a-z_][a-z0-9_]*)) "
)
GATE_COPY_PATTERN = re.compile(
    r'^COPY (?:(?:"private"\."pilot_participation_gate_v1")|'
    r"(?:private\.pilot_participation_gate_v1)) \((?P<columns>[^)]+)\) FROM stdin;$"
)
REQUIRED = {
    ("auth", "users"),
    ("auth", "identities"),
    ("storage", "buckets"),
    ("storage", "objects"),
}
EXCLUDED_STORAGE_RELATIONS = (
    "storage.buckets_vectors",
    "storage.vector_indexes",
)


POSTGRES_VERSION = re.compile(
    r"^-- Dumped from database version (?P<version>[0-9]+(?:\.[0-9]+){1,2}(?:[-+][A-Za-z0-9._-]+)?)$"
)
EXTENSION_PATTERN = re.compile(
    r'^CREATE EXTENSION IF NOT EXISTS (?:(?:"(?P<quoted>[a-z0-9_]+)")|'
    r"(?P<plain>[a-z0-9_]+))(?: WITH SCHEMA [^;]+)?;$"
)


def inspect(path: Path) -> dict[str, object]:
    counts: dict[str, int] = {}
    seen: set[tuple[str, str]] = set()
    active: tuple[str, str] | None = None
    active_columns: list[str] = []
    gate_rows: list[dict[str, str | None]] = []
    try:
        with path.open("r", encoding="utf-8", errors="strict") as handle:
            for line in handle:
                if active is None:
                    match = COPY_PATTERN.match(line)
                    if match is None:
                        continue
                    candidate = (
                        match.group("qschema") or match.group("schema"),
                        match.group("qtable") or match.group("table"),
                    )
                    key = f"{candidate[0]}.{candidate[1]}"
                    if key in counts:
                        raise ValueError("data dump contains a duplicate COPY section")
                    if len(counts) >= 4096:
                        raise ValueError("data dump table inventory is too large")
                    counts[key] = 0
                    active = candidate
                    gate_match = GATE_COPY_PATTERN.fullmatch(line.rstrip("\n"))
                    active_columns = (
                        [
                            column.strip().strip('"')
                            for column in gate_match.group("columns").split(",")
                        ]
                        if gate_match is not None
                        else []
                    )
                    if candidate in REQUIRED:
                        seen.add(candidate)
                elif line == "\\.\n" or line == "\\.":
                    active = None
                else:
                    key = f"{active[0]}.{active[1]}"
                    counts[key] += 1
                    if active == ("private", "pilot_participation_gate_v1"):
                        values = line.rstrip("\n").split("\t")
                        if len(values) != len(active_columns):
                            raise ValueError("participation gate row is malformed")
                        gate_rows.append(
                            {
                                column: None if value == r"\N" else value
                                for column, value in zip(
                                    active_columns,
                                    values,
                                    strict=True,
                                )
                            }
                        )
    except (OSError, UnicodeError) as exc:
        raise ValueError("data dump is unreadable") from exc
    missing = REQUIRED - seen
    if missing:
        raise ValueError("data dump lacks required Auth or Storage COPY sections")
    if "private.pilot_participation_gate_v1" in counts:
        if len(gate_rows) != 1:
            raise ValueError("participation gate must contain one singleton row")
        gate = gate_rows[0]
        required = gate.get("participation_required")
        project_ref = gate.get("project_ref")
        notice_version = gate.get("notice_version")
        if (
            gate.get("singleton") != "t"
            or required not in {"t", "f"}
            or (
                required == "t"
                and (
                    not isinstance(project_ref, str)
                    or re.fullmatch(r"[a-z]{20}", project_ref) is None
                    or notice_version != "pilot-participation-notice-v1"
                )
            )
            or (
                required == "f"
                and (project_ref is not None or notice_version is not None)
            )
        ):
            raise ValueError("participation gate singleton shape is invalid")
        participation_gate: dict[str, object] = {
            "present": True,
            "project_ref": project_ref,
            "participation_required": required == "t",
            "notice_version": notice_version,
        }
    else:
        participation_gate = {"present": False}
    return {
        "table_row_counts": dict(sorted(counts.items())),
        "data_schemas": sorted({key.split(".", 1)[0] for key in counts}),
        "table_count": len(counts),
        "total_row_count": sum(counts.values()),
        "pilot_participation_gate": participation_gate,
    }


def postgres_version(path: Path) -> str:
    matches: list[str] = []
    try:
        with path.open("r", encoding="utf-8", errors="strict") as handle:
            for line in handle:
                match = POSTGRES_VERSION.fullmatch(line.rstrip("\n"))
                if match is not None:
                    matches.append(match.group("version"))
    except (OSError, UnicodeError) as exc:
        raise ValueError("schema dump is unreadable") from exc
    if len(matches) != 1:
        raise ValueError("schema dump lacks one exact PostgreSQL server version")
    return matches[0]


def extensions(path: Path) -> list[str]:
    values: list[str] = []
    try:
        with path.open("r", encoding="utf-8", errors="strict") as handle:
            for line in handle:
                match = EXTENSION_PATTERN.fullmatch(line.rstrip("\n"))
                if match is not None:
                    values.append(match.group("quoted") or match.group("plain"))
    except (OSError, UnicodeError) as exc:
        raise ValueError("schema dump is unreadable") from exc
    if len(values) != len(set(values)):
        raise ValueError("schema dump extensions are duplicate")
    return sorted(values)


def excluded_storage_counts(path: Path) -> dict[str, dict[str, object]]:
    rows: dict[str, dict[str, object]] = {}
    try:
        lines = path.read_text(encoding="ascii", errors="strict").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ValueError("excluded Storage inventory is unreadable") from exc
    for line in lines:
        parts = line.split("|")
        if len(parts) != 3:
            raise ValueError("excluded Storage inventory row is malformed")
        relation, present_text, count_text = parts
        if (
            relation not in EXCLUDED_STORAGE_RELATIONS
            or relation in rows
            or present_text not in {"t", "f"}
            or re.fullmatch(r"0|[1-9][0-9]*", count_text) is None
        ):
            raise ValueError("excluded Storage inventory row is invalid")
        count = int(count_text)
        present = present_text == "t"
        if not present and count != 0:
            raise ValueError("absent excluded Storage relation has rows")
        rows[relation] = {"present": present, "row_count": count}
    if set(rows) != set(EXCLUDED_STORAGE_RELATIONS):
        raise ValueError("excluded Storage inventory is incomplete")
    return dict(sorted(rows.items()))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("data_dump")
    parser.add_argument("--schema-dump", required=True)
    parser.add_argument("--excluded-storage-counts", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        inspected = inspect(Path(args.data_dump))
        counts = inspected["table_row_counts"]
        assert isinstance(counts, dict)
        schema_dump = Path(args.schema_dump)
        excluded_counts = excluded_storage_counts(
            Path(args.excluded_storage_counts),
        )
        output = {
            "schema_version": "mylifegraph-backup-inventory-v1",
            "postgres_server_version": postgres_version(schema_dump),
            "extensions": extensions(schema_dump),
            "auth_user_count": counts["auth.users"],
            "auth_identity_count": counts["auth.identities"],
            "storage_bucket_count": counts["storage.buckets"],
            "storage_object_count": counts["storage.objects"],
            "excluded_storage_relation_counts": excluded_counts,
            "data_schemas": inspected["data_schemas"],
            "table_count": inspected["table_count"],
            "total_row_count": inspected["total_row_count"],
            "table_row_counts": counts,
            "pilot_participation_gate": inspected["pilot_participation_gate"],
        }
        Path(args.output).write_text(
            json.dumps(output, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if (
            output["storage_bucket_count"]
            or output["storage_object_count"]
            or any(
                descriptor["row_count"]
                for descriptor in excluded_counts.values()
            )
        ):
            print(
                "backup inventory error: non-empty Storage requires object-byte backup",
                file=sys.stderr,
            )
            return 2
    except ValueError as exc:
        print(f"backup inventory error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
