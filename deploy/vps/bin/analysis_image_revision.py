#!/usr/bin/python3
"""Derive the Coach analysis-image revision without executing release code."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path


REVISION_VERSION = b"mylifegraph-coach-analysis-revision-v1\0"
SOURCE_FILES = ("Dockerfile", "requirements.txt", "runner.py")


def revision(context: Path) -> str:
    root = context.resolve(strict=True)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("analysis context is not a real directory")
    digest = hashlib.sha256(REVISION_VERSION)
    for name in SOURCE_FILES:
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"analysis image input is invalid: {name}")
        encoded_name = name.encode("ascii")
        value = path.read_bytes()
        digest.update(len(encoded_name).to_bytes(2, "big"))
        digest.update(encoded_name)
        digest.update(len(value).to_bytes(8, "big"))
        digest.update(value)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("context")
    args = parser.parse_args()
    try:
        print(revision(Path(args.context)))
    except (OSError, ValueError) as exc:
        print(f"analysis image fingerprint error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
