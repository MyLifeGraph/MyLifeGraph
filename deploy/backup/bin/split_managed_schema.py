#!/usr/bin/env python3
"""Split managed-schema SQL before app-dependent triggers/policies/grants."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ENTRY = re.compile(
    r"^-- Name: (?P<name>.+); Type: (?P<type>[A-Z ]+); "
    r"Schema: (?P<schema>[^;]+); Owner: .+$"
)
CONFLICT = re.compile(
    r"^(?P<table>[a-z_][a-z0-9_]*) "
    r"(?P<object>[a-z_][a-z0-9_]*|.+);$"
)
IDENTIFIER = re.compile(r"[a-z_][a-z0-9_]*")
POST_DATA_TYPES = {
    "ACL",
    "DEFAULT ACL",
    "POLICY",
    "PUBLICATION TABLE",
    "ROW SECURITY",
    "TRIGGER",
}


class ManagedSchemaError(ValueError):
    pass


def _write_private(path: Path, value: str) -> None:
    path.write_text(value, encoding="utf-8")
    path.chmod(0o600)


def split(source: Path) -> tuple[str, str, str]:
    try:
        lines = source.read_text(encoding="utf-8", errors="strict").splitlines(
            keepends=True
        )
    except (OSError, UnicodeError) as exc:
        raise ManagedSchemaError("managed schema dump is unreadable") from exc
    if not lines or source.is_symlink() or not source.is_file():
        raise ManagedSchemaError("managed schema dump type is invalid")
    entries: list[tuple[int, re.Match[str]]] = []
    for index, line in enumerate(lines):
        match = ENTRY.fullmatch(line.rstrip("\n"))
        if match is not None:
            entries.append((index, match))
    schema_entries = {
        match.group("name")
        for _, match in entries
        if match.group("type") == "SCHEMA"
    }
    if not {"auth", "storage"}.issubset(schema_entries):
        raise ManagedSchemaError("managed schema dump lacks Auth or Storage")
    post_entries = [
        (index, match)
        for index, match in entries
        if match.group("type") in POST_DATA_TYPES
    ]
    if not entries or not post_entries:
        raise ManagedSchemaError("managed schema dump lacks a post-data boundary")
    first_entry_index = entries[0][0]
    post_index = post_entries[0][0]
    if post_index <= first_entry_index:
        raise ManagedSchemaError("managed schema dump ordering is invalid")

    postgres_user_grants = [
        line
        for line in lines[post_index:]
        if line.startswith('GRANT ')
        and ' ON TABLE "auth"."users" TO "postgres"' in line
    ]
    grants_text = "".join(postgres_user_grants)
    if "REFERENCES" not in grants_text or "TRIGGER" not in grants_text:
        raise ManagedSchemaError(
            "managed schema dump lacks postgres Auth-user prerequisites"
        )

    cleanup: list[str] = ["\\set ON_ERROR_STOP on\n"]
    for _, match in post_entries:
        object_type = match.group("type")
        if object_type not in {"POLICY", "TRIGGER"}:
            continue
        schema = match.group("schema")
        identity = CONFLICT.fullmatch(match.group("name") + ";")
        if (
            identity is None
            or IDENTIFIER.fullmatch(schema) is None
            or IDENTIFIER.fullmatch(identity.group("table")) is None
            or IDENTIFIER.fullmatch(identity.group("object")) is None
        ):
            raise ManagedSchemaError(
                "managed schema conflict identity is unsupported"
            )
        keyword = "trigger" if object_type == "TRIGGER" else "policy"
        cleanup.append(
            f'drop {keyword} if exists "{identity.group("object")}" '
            f'on "{schema}"."{identity.group("table")}";\n'
        )

    prefix = lines[:first_entry_index]
    pre_data = (
        "".join(lines[:post_index])
        + "\n-- Migration prerequisites copied from the source Auth ACL.\n"
        + grants_text
    )
    post_data = "".join(prefix + lines[post_index:])
    return pre_data, post_data, "".join(cleanup)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("--pre-output", required=True)
    parser.add_argument("--post-output", required=True)
    parser.add_argument("--conflict-cleanup-output", required=True)
    args = parser.parse_args()
    try:
        pre_data, post_data, cleanup = split(Path(args.source))
        _write_private(Path(args.pre_output), pre_data)
        _write_private(Path(args.post_output), post_data)
        _write_private(Path(args.conflict_cleanup_output), cleanup)
    except (ManagedSchemaError, OSError, UnicodeError) as exc:
        print(f"managed schema split error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
