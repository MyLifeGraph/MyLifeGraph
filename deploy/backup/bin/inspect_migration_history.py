#!/usr/bin/env python3
"""Compare the dumped Supabase migration history with the repository exactly."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


MIGRATION_FILE = re.compile(r"(?P<version>[0-9]{14})_(?P<name>[a-z0-9_]+)\.sql")
COPY_HEADER = re.compile(
    r'^COPY (?:(?:"supabase_migrations"\."schema_migrations")|'
    r"(?:supabase_migrations\.schema_migrations)) \((?P<columns>[^)]+)\) "
    r"FROM stdin;$"
)


class MigrationHistoryError(ValueError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _repository_migrations(root: Path) -> list[dict[str, str]]:
    migrations: list[dict[str, str]] = []
    for path in sorted(root.glob("*.sql")):
        match = MIGRATION_FILE.fullmatch(path.name)
        if match is None or path.is_symlink() or not path.is_file():
            raise MigrationHistoryError(f"invalid repository migration: {path.name}")
        migrations.append(
            {
                "version": match.group("version"),
                "name": match.group("name"),
                "file": path.name,
                "sha256": _sha256(path),
            }
        )
    versions = [item["version"] for item in migrations]
    if not migrations or versions != sorted(set(versions)):
        raise MigrationHistoryError("repository migration versions are missing or duplicate")
    return migrations


def _copy_value(value: str) -> str | None:
    if value == r"\N":
        return None
    return (
        value.replace(r"\t", "\t")
        .replace(r"\n", "\n")
        .replace(r"\r", "\r")
        .replace(r"\\", "\\")
    )


def _dumped_migrations(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    active = False
    columns: list[str] = []
    copy_sections = 0
    try:
        with path.open("r", encoding="utf-8", errors="strict") as handle:
            for raw_line in handle:
                line = raw_line.rstrip("\n")
                if not active:
                    match = COPY_HEADER.fullmatch(line)
                    if match is None:
                        continue
                    copy_sections += 1
                    columns = [
                        value.strip().strip('"')
                        for value in match.group("columns").split(",")
                    ]
                    if "version" not in columns or "name" not in columns:
                        raise MigrationHistoryError(
                            "migration history COPY lacks version or name"
                        )
                    active = True
                    continue
                if line == r"\.":
                    active = False
                    continue
                values = line.split("\t")
                if len(values) != len(columns):
                    raise MigrationHistoryError("migration history row is malformed")
                record = dict(zip(columns, map(_copy_value, values), strict=True))
                version = record["version"]
                name = record["name"]
                if (
                    not isinstance(version, str)
                    or re.fullmatch(r"[0-9]{14}", version) is None
                    or not isinstance(name, str)
                    or re.fullmatch(r"[a-z0-9_]+", name) is None
                ):
                    raise MigrationHistoryError("migration history identity is invalid")
                rows.append({"version": version, "name": name})
    except (OSError, UnicodeError) as exc:
        raise MigrationHistoryError("migration history dump is unreadable") from exc
    if active or copy_sections != 1 or not rows:
        raise MigrationHistoryError(
            "migration history must contain one complete non-empty COPY section"
        )
    identities = [(row["version"], row["name"]) for row in rows]
    if len(identities) != len(set(identities)):
        raise MigrationHistoryError("migration history contains a duplicate identity")
    return sorted(rows, key=lambda row: (row["version"], row["name"]))


def inspect(
    history_dump: Path, migrations_root: Path, expected_head: str
) -> dict[str, object]:
    repository = _repository_migrations(migrations_root)
    expected_indexes = [
        index for index, item in enumerate(repository) if item["file"] == expected_head
    ]
    if len(expected_indexes) != 1:
        raise MigrationHistoryError("expected migration head is not in the repository")
    expected = repository[: expected_indexes[0] + 1]
    actual = _dumped_migrations(history_dump)
    expected_identities = [
        (item["version"], item["name"]) for item in expected
    ]
    actual_identities = [(item["version"], item["name"]) for item in actual]
    if actual_identities != expected_identities:
        first_difference = next(
            (
                index
                for index, pair in enumerate(
                    zip(expected_identities, actual_identities, strict=False)
                )
                if pair[0] != pair[1]
            ),
            min(len(expected_identities), len(actual_identities)),
        )
        expected_value = (
            expected_identities[first_difference][0]
            if first_difference < len(expected_identities)
            else "end"
        )
        actual_value = (
            actual_identities[first_difference][0]
            if first_difference < len(actual_identities)
            else "end"
        )
        raise MigrationHistoryError(
            "database migration history differs from repository at "
            f"position {first_difference}: expected {expected_value}, got {actual_value}"
        )
    canonical_versions = json.dumps(
        actual_identities, separators=(",", ":"), ensure_ascii=True
    ).encode("ascii")
    return {
        "schema_version": "mylifegraph-migration-inventory-v1",
        "status": "exact_expected_boundary",
        "expected_count": len(expected),
        "actual_count": len(actual),
        "expected_head": expected[-1]["file"],
        "actual_head": expected[-1]["file"],
        "repository_target_count": len(repository),
        "repository_target_head": repository[-1]["file"],
        "applied_identity_sha256": hashlib.sha256(canonical_versions).hexdigest(),
        "migrations": expected,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("history_dump")
    parser.add_argument("--migrations-root", required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        result = inspect(
            Path(args.history_dump), Path(args.migrations_root), args.expected_head
        )
        Path(args.output).write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(result["actual_head"])
    except MigrationHistoryError as exc:
        print(f"migration inventory error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
