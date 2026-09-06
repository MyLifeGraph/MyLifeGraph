#!/usr/bin/env python3
"""Assemble a local runtime bundle from explicitly downloaded, pinned assets."""

import argparse
import hashlib
import json
import os
from pathlib import Path

from bootstrap_runtime import SOURCE_MAP, SCHEMA


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    vps = Path(__file__).resolve().parents[1]
    repo = vps.parents[1]
    output = args.output.absolute()
    if output.resolve() == repo or repo in output.resolve().parents:
        parser.error("Runtime bundles must remain outside the repository.")
    sources = json.loads((vps / "manifests/runtime-sources.json").read_text())
    files = {name: (vps / source).read_bytes() for name, source in SOURCE_MAP.items()}
    for name, field in [
        ("caddy.tar.gz", "caddy_sha256"),
        ("dockerd-rootless.sh", "rootless_sha256"),
    ]:
        path = args.assets / name
        if path.is_symlink() or not path.is_file():
            parser.error("Runtime artifacts must be regular files.")
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != sources[field]:
            parser.error(f"Pinned artifact checksum mismatch: {name}")
        files[name] = data
    os.umask(0o077)
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    for name, data in files.items():
        (output / name).write_bytes(data)
    manifest = {
        "schema_version": SCHEMA,
        "files": {
            name: hashlib.sha256(data).hexdigest()
            for name, data in sorted(files.items())
        },
    }
    raw = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    (output / "manifest.json").write_bytes(raw)
    print("Runtime bundle:", output)
    print("manifest.json SHA256:", hashlib.sha256(raw).hexdigest())
    print("bootstrap_runtime.py SHA256:", manifest["files"]["bootstrap_runtime.py"])
    print("No network request or host installation performed.")


if __name__ == "__main__":
    main()
