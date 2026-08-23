#!/usr/bin/env python3
"""Seal and verify one immutable prepared VPS release tree."""

from __future__ import annotations

import argparse
import grp
import hashlib
import hmac
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


SEAL_NAME = ".mylifegraph-tree.sha256"
SEAL_VERSION = b"mylifegraph-release-tree-v1\0"
DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}\n$")
VENV_PREFIX = ("services", "ai_service", ".venv")


class ReleaseTreeError(ValueError):
    pass


def _field(digest: Any, value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _entries(root: Path) -> list[tuple[Path, Path]]:
    result: list[tuple[Path, Path]] = []

    def visit(directory: Path) -> None:
        try:
            with os.scandir(directory) as iterator:
                entries = sorted(iterator, key=lambda item: os.fsencode(item.name))
        except OSError as exc:
            raise ReleaseTreeError("Release tree cannot be enumerated.") from exc
        for entry in entries:
            path = Path(entry.path)
            relative = path.relative_to(root)
            if relative.as_posix() == SEAL_NAME:
                continue
            result.append((relative, path))
            if entry.is_dir(follow_symlinks=False):
                visit(path)

    visit(root)
    return result


def _digest_tree(root: Path) -> str:
    digest = hashlib.sha256(SEAL_VERSION)
    for relative, path in _entries(root):
        relative_bytes = os.fsencode(relative.as_posix())
        metadata = path.lstat()
        if stat.S_ISDIR(metadata.st_mode):
            digest.update(b"D")
            _field(digest, relative_bytes)
            continue
        if stat.S_ISLNK(metadata.st_mode):
            if relative.parts[: len(VENV_PREFIX)] != VENV_PREFIX:
                raise ReleaseTreeError("Release symlink exists outside the virtualenv.")
            digest.update(b"L")
            _field(digest, relative_bytes)
            _field(digest, os.fsencode(os.readlink(path)))
            continue
        if not stat.S_ISREG(metadata.st_mode):
            raise ReleaseTreeError("Release tree contains a special file.")
        digest.update(b"F")
        _field(digest, relative_bytes)
        digest.update(metadata.st_size.to_bytes(8, "big"))
        try:
            with path.open("rb") as handle:
                while chunk := handle.read(1024 * 1024):
                    digest.update(chunk)
        except OSError as exc:
            raise ReleaseTreeError("Release file cannot be read.") from exc
    return digest.hexdigest()


def _release_root(value: str) -> Path:
    raw = Path(value)
    if raw.is_symlink():
        raise ReleaseTreeError("Release root must not be a symlink.")
    try:
        root = raw.resolve(strict=True)
    except OSError as exc:
        raise ReleaseTreeError("Release root does not exist.") from exc
    if not root.is_dir():
        raise ReleaseTreeError("Release root is not a directory.")
    return root


def _verify_permissions(root: Path, *, expected_gid: int) -> None:
    for relative, path in [(Path("."), root), *_entries(root), (Path(SEAL_NAME), root / SEAL_NAME)]:
        metadata = path.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != expected_gid:
            raise ReleaseTreeError(f"Release ownership is invalid at {relative}.")
        if not stat.S_ISLNK(metadata.st_mode) and metadata.st_mode & 0o222:
            raise ReleaseTreeError(f"Release path remains writable at {relative}.")


def _seal(root: Path, *, test_mode: bool, group_name: str) -> None:
    seal = root / SEAL_NAME
    if seal.exists() or seal.is_symlink():
        raise ReleaseTreeError("Release tree is already sealed.")
    if not test_mode:
        if os.geteuid() != 0:
            raise ReleaseTreeError("Release sealing must run as root.")
        expected_gid = grp.getgrnam(group_name).gr_gid
        # All existing paths were made root-owned/read-only by the caller.
        for relative, path in [(Path("."), root), *_entries(root)]:
            metadata = path.lstat()
            if metadata.st_uid != 0 or metadata.st_gid != expected_gid:
                raise ReleaseTreeError(f"Release ownership is invalid at {relative}.")
            if not stat.S_ISLNK(metadata.st_mode) and metadata.st_mode & 0o222:
                raise ReleaseTreeError(f"Release path remains writable at {relative}.")
    digest = _digest_tree(root)
    temporary = root / f".{SEAL_NAME}.new.{os.getpid()}"
    try:
        with temporary.open("x", encoding="ascii") as handle:
            handle.write(f"{digest}\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(seal)
    except OSError as exc:
        raise ReleaseTreeError("Release seal could not be written.") from exc


def _verify(root: Path, *, test_mode: bool, group_name: str) -> None:
    seal = root / SEAL_NAME
    if seal.is_symlink() or not seal.is_file():
        raise ReleaseTreeError("Release tree seal is missing.")
    try:
        expected = seal.read_text(encoding="ascii")
    except (OSError, UnicodeError) as exc:
        raise ReleaseTreeError("Release tree seal is unreadable.") from exc
    if DIGEST_PATTERN.fullmatch(expected) is None:
        raise ReleaseTreeError("Release tree seal is invalid.")
    if not test_mode:
        _verify_permissions(root, expected_gid=grp.getgrnam(group_name).gr_gid)
    if not hmac.compare_digest(_digest_tree(root), expected.strip()):
        raise ReleaseTreeError("Release tree differs from its sealed digest.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["seal", "verify"])
    parser.add_argument("--release", required=True)
    parser.add_argument("--group", default="mylifegraph-release")
    parser.add_argument("--test-mode", action="store_true")
    args = parser.parse_args()
    try:
        root = _release_root(args.release)
        if args.operation == "seal":
            _seal(root, test_mode=args.test_mode, group_name=args.group)
        else:
            _verify(root, test_mode=args.test_mode, group_name=args.group)
    except (KeyError, OSError, ReleaseTreeError) as exc:
        print(f"release tree error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
