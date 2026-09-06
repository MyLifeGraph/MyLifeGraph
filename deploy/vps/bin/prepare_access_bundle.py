#!/usr/bin/env python3
"""Build a local, public-key-only access bundle. Never contacts a server."""

import argparse
import hashlib
import json
import os
from pathlib import Path

from bootstrap_access import AccessError, PEOPLE, SCHEMA, load_manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New directory outside the repository",
    )
    parser.add_argument(
        "--key", action="append", default=[], metavar="ACCOUNT=PUBLIC_KEY.pub"
    )
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    output = args.output.absolute()
    if output.resolve() == repo or repo in output.resolve().parents:
        parser.error("Keep machine-specific access bundles outside the repository.")
    keys = {}
    for assignment in args.key:
        user, separator, filename = assignment.partition("=")
        if not separator or user not in PEOPLE or user in keys:
            parser.error("--key requires a distinct supported project login account.")
        path = Path(filename).expanduser()
        if path.suffix != ".pub" or path.is_symlink() or path.stat().st_size > 4096:
            parser.error(
                "Only small regular .pub files are accepted; never supply private keys."
            )
        keys[user] = path.read_text()
    manifest = load_manifest(
        json.dumps({"schema_version": SCHEMA, "keys": keys}).encode()
    )
    os.umask(0o077)
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    (output / "access.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    (output / "bootstrap_access.py").write_bytes(
        Path(__file__).with_name("bootstrap_access.py").read_bytes()
    )
    (output / "ACCESS.md").write_bytes(
        Path(__file__).resolve().parents[1].joinpath("ACCESS.md").read_bytes()
    )
    lines = []
    for name in ("bootstrap_access.py", "access.json", "ACCESS.md"):
        sha = hashlib.sha256((output / name).read_bytes()).hexdigest()
        lines.append(f"{sha}  {name}\n")
    (output / "SHA256SUMS").write_text("".join(lines))
    print(f"Local bundle: {output}")
    print("".join(lines), end="")
    print(
        "SSH-enabled accounts:", ", ".join(keys) or "none; all accounts remain nologin"
    )
    print(
        "No server contacted. Follow deploy/vps/ACCESS.md for review and administrator installation."
    )


if __name__ == "__main__":
    try:
        main()
    except (AccessError, OSError) as exc:
        raise SystemExit(f"Bundle preparation stopped: {exc}")
