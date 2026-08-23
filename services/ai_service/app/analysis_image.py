"""Stable source identity for the isolated Coach analysis image."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


ANALYSIS_IMAGE_REVISION_VERSION = b"mylifegraph-coach-analysis-revision-v1\0"
ANALYSIS_IMAGE_SOURCE_FILES = (
    "Dockerfile",
    "requirements.txt",
    "runner.py",
)


def analysis_image_revision(context: Path) -> str:
    root = context.resolve(strict=True)
    digest = hashlib.sha256(ANALYSIS_IMAGE_REVISION_VERSION)
    for name in ANALYSIS_IMAGE_SOURCE_FILES:
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Analysis image input is invalid: {name}")
        value = path.read_bytes()
        encoded_name = name.encode("ascii")
        digest.update(len(encoded_name).to_bytes(2, "big"))
        digest.update(encoded_name)
        digest.update(len(value).to_bytes(8, "big"))
        digest.update(value)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: analysis_image.py <context-directory>", file=sys.stderr)
        return 64
    try:
        print(analysis_image_revision(Path(sys.argv[1])))
    except (OSError, ValueError) as exc:
        print(f"analysis image fingerprint error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
