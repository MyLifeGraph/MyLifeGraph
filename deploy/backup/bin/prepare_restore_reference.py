#!/usr/bin/env python3
"""Materialize the exact hashed repository migration prefix for rehearsal."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path


class ReferenceError(ValueError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True)
    parser.add_argument("--migrations-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--target-head")
    args = parser.parse_args()
    try:
        payload = Path(args.payload).resolve(strict=True)
        migrations_root = Path(args.migrations_root).resolve(strict=True)
        output = Path(args.output)
        if output.exists() and any(output.iterdir()):
            raise ReferenceError("reference migration output must be empty")
        output.mkdir(parents=True, exist_ok=True, mode=0o700)
        inventory = json.loads(
            (payload / "migration-inventory.json").read_text(encoding="utf-8")
        )
        rows = inventory.get("migrations") if isinstance(inventory, dict) else None
        if not isinstance(rows, list) or not rows:
            raise ReferenceError("migration inventory is empty or invalid")
        inventory_files: list[str] = []
        for row in rows:
            if (
                not isinstance(row, dict)
                or set(row) != {"version", "name", "file", "sha256"}
                or row.get("file")
                != f"{row.get('version')}_{row.get('name')}.sql"
                or re.fullmatch(r"[0-9a-f]{64}", str(row.get("sha256")))
                is None
            ):
                raise ReferenceError("migration inventory row is invalid")
            source = migrations_root / row["file"]
            if (
                not source.is_file()
                or source.is_symlink()
                or _sha256(source) != row["sha256"]
            ):
                raise ReferenceError(
                    "repository migration differs from the backed-up boundary"
                )
            inventory_files.append(row["file"])
        if inventory_files != sorted(inventory_files):
            raise ReferenceError("migration inventory is not ordered")
        repository_files = sorted(
            path.name
            for path in migrations_root.glob("*.sql")
            if path.is_file() and not path.is_symlink()
        )
        if repository_files[: len(inventory_files)] != inventory_files:
            raise ReferenceError(
                "backed-up migrations are not an exact repository prefix"
            )
        target_head = args.target_head or inventory_files[-1]
        if target_head not in repository_files:
            raise ReferenceError("target migration head is unavailable")
        target_index = repository_files.index(target_head)
        if target_index + 1 < len(inventory_files):
            raise ReferenceError("target migration head predates the backup")
        for name in repository_files[: target_index + 1]:
            source = migrations_root / name
            destination = output / name
            shutil.copyfile(source, destination)
            destination.chmod(0o400)
    except (OSError, UnicodeError, json.JSONDecodeError, ReferenceError) as exc:
        print(f"restore reference error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
