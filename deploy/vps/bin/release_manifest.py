#!/usr/bin/env python3
"""Create and validate the secret-free VPS source-release manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tarfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA_VERSION = "mylifegraph-source-release-v1"
TAG_PATTERN = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+-rc\.[0-9]+$")
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
TIME_PATTERN = re.compile(
    r"^[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])"
    r"T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"
)
MAX_ARCHIVE_MEMBERS = 50_000
MAX_UNPACKED_BYTES = 1_073_741_824
REQUIRED_ARCHIVE_PATHS = {
    "services/ai_service/app/analysis_image.py",
    "services/ai_service/app/main.py",
    "services/ai_service/coach_analysis/Dockerfile",
    "services/ai_service/coach_analysis/requirements.txt",
    "services/ai_service/coach_analysis/runner.py",
    "services/ai_service/requirements.txt",
    "docs/current-contracts.json",
}


class ManifestError(ValueError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ManifestError("Manifest JSON contains a duplicate key.")
        result[key] = value
    return result


def _read_manifest(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
        value = json.loads(raw, object_pairs_hook=_unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ManifestError("Source manifest is unreadable or invalid JSON.") from exc
    if not isinstance(value, dict):
        raise ManifestError("Source manifest must be a JSON object.")
    return value


def _exact_object(value: object, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ManifestError(f"{label} has an invalid shape.")
    return value


def _validate_manifest(value: dict[str, Any]) -> dict[str, Any]:
    manifest = _exact_object(
        value,
        {
            "schema_version",
            "release_tag",
            "release_sha",
            "created_at_utc",
            "source_archive",
            "requirements_sha256",
            "contracts_sha256",
            "migration_head",
            "migration_inventory",
        },
        "Source manifest",
    )
    if manifest["schema_version"] != SCHEMA_VERSION:
        raise ManifestError("Source manifest version is unsupported.")
    if (
        not isinstance(manifest["release_tag"], str)
        or TAG_PATTERN.fullmatch(manifest["release_tag"]) is None
    ):
        raise ManifestError("Release tag is not an exact pilot RC tag.")
    if (
        not isinstance(manifest["release_sha"], str)
        or SHA_PATTERN.fullmatch(manifest["release_sha"]) is None
    ):
        raise ManifestError("Release SHA is invalid.")
    if (
        not isinstance(manifest["created_at_utc"], str)
        or TIME_PATTERN.fullmatch(manifest["created_at_utc"]) is None
    ):
        raise ManifestError("Manifest timestamp is invalid.")
    archive = _exact_object(
        manifest["source_archive"], {"name", "sha256"}, "Source archive"
    )
    expected_name = f"mylifegraph-{manifest['release_tag']}.tar.gz"
    if archive["name"] != expected_name:
        raise ManifestError("Source archive name does not match the release tag.")
    for key in ["requirements_sha256", "contracts_sha256"]:
        if (
            not isinstance(manifest[key], str)
            or DIGEST_PATTERN.fullmatch(manifest[key]) is None
        ):
            raise ManifestError(f"{key} is invalid.")
    if (
        not isinstance(archive["sha256"], str)
        or DIGEST_PATTERN.fullmatch(archive["sha256"]) is None
    ):
        raise ManifestError("Source archive checksum is invalid.")
    migration_head = manifest["migration_head"]
    if (
        not isinstance(migration_head, str)
        or re.fullmatch(r"[0-9]{14}_[a-z0-9_]+\.sql", migration_head) is None
    ):
        raise ManifestError("Migration head is invalid.")
    migration_inventory = _exact_object(
        manifest["migration_inventory"],
        {"count", "sha256", "identity_sha256"},
        "Migration inventory",
    )
    if (
        not isinstance(migration_inventory["count"], int)
        or migration_inventory["count"] < 1
        or migration_inventory["count"] > MAX_ARCHIVE_MEMBERS
        or not isinstance(migration_inventory["sha256"], str)
        or DIGEST_PATTERN.fullmatch(migration_inventory["sha256"]) is None
        or not isinstance(migration_inventory["identity_sha256"], str)
        or DIGEST_PATTERN.fullmatch(migration_inventory["identity_sha256"]) is None
    ):
        raise ManifestError("Migration inventory is invalid.")
    return manifest


@dataclass(frozen=True, slots=True)
class ArchiveInspection:
    embedded_digests: dict[str, str]
    git_commit: str
    migrations: tuple[tuple[str, str], ...]


def _migration_inventory(
    migrations: tuple[tuple[str, str], ...],
) -> dict[str, object]:
    serialized = "".join(
        f"{digest}  {name}\n" for name, digest in migrations
    ).encode("ascii")
    return {
        "count": len(migrations),
        "sha256": hashlib.sha256(serialized).hexdigest(),
        "identity_sha256": hashlib.sha256(
            "".join(f"{name}\n" for name, _digest in migrations).encode("ascii")
        ).hexdigest(),
    }


def _inspect_archive(path: Path, release_tag: str) -> ArchiveInspection:
    expected_prefix = f"mylifegraph-{release_tag}"
    seen: set[str] = set()
    embedded_digests: dict[str, str] = {}
    migration_digests: dict[str, str] = {}
    total_size = 0
    try:
        with tarfile.open(path, mode="r:gz") as archive:
            git_commit = archive.pax_headers.get("comment", "")
            if SHA_PATTERN.fullmatch(git_commit) is None:
                raise ManifestError("Source archive lacks an exact Git commit identity.")
            members = archive.getmembers()
            if not members or len(members) > MAX_ARCHIVE_MEMBERS:
                raise ManifestError("Source archive member count is invalid.")
            for member in members:
                candidate = PurePosixPath(member.name)
                if candidate.is_absolute() or ".." in candidate.parts:
                    raise ManifestError("Source archive contains an unsafe path.")
                if not (member.isdir() or member.isreg()):
                    raise ManifestError("Source archive contains a non-file entry.")
                parts = candidate.parts
                if not parts or parts[0] != expected_prefix:
                    raise ManifestError("Source archive prefix is invalid.")
                relative = PurePosixPath(*parts[1:]).as_posix()
                if relative in seen:
                    raise ManifestError("Source archive contains a duplicate path.")
                comments = {
                    value
                    for key, value in member.pax_headers.items()
                    if key == "comment"
                }
                if comments and comments != {git_commit}:
                    raise ManifestError("Source archive Git identity is inconsistent.")
                relative_path = PurePosixPath(relative)
                if relative_path.name in {".env", "auth.json", "key.properties"}:
                    raise ManifestError("Source archive contains a credential file.")
                if relative_path.name.endswith((".jks", ".keystore")):
                    raise ManifestError("Source archive contains signing material.")
                if member.isreg():
                    total_size += member.size
                    if total_size > MAX_UNPACKED_BYTES:
                        raise ManifestError("Source archive is too large.")
                    seen.add(relative)
                    if relative in {
                        "services/ai_service/requirements.txt",
                        "docs/current-contracts.json",
                    }:
                        source = archive.extractfile(member)
                        if source is None:
                            raise ManifestError("Source archive entry is unreadable.")
                        digest = hashlib.sha256()
                        with source:
                            while chunk := source.read(1024 * 1024):
                                digest.update(chunk)
                        embedded_digests[relative] = digest.hexdigest()
                    if relative.startswith("supabase/migrations/"):
                        migration_name = relative.removeprefix(
                            "supabase/migrations/"
                        )
                        if (
                            "/" in migration_name
                            or re.fullmatch(
                                r"[0-9]{14}_[a-z0-9_]+\.sql",
                                migration_name,
                            )
                            is None
                        ):
                            raise ManifestError(
                                "Source archive migration identity is invalid."
                            )
                        source = archive.extractfile(member)
                        if source is None:
                            raise ManifestError(
                                "Source archive migration is unreadable."
                            )
                        digest = hashlib.sha256()
                        with source:
                            while chunk := source.read(1024 * 1024):
                                digest.update(chunk)
                        migration_digests[migration_name] = digest.hexdigest()
    except (OSError, tarfile.TarError) as exc:
        raise ManifestError("Source archive is unreadable.") from exc
    missing = REQUIRED_ARCHIVE_PATHS - seen
    if missing:
        raise ManifestError("Source archive is missing required release files.")
    migrations = tuple(sorted(migration_digests.items()))
    if not migrations:
        raise ManifestError("Source archive contains no Supabase migrations.")
    return ArchiveInspection(
        embedded_digests=embedded_digests,
        git_commit=git_commit,
        migrations=migrations,
    )


def _create(args: argparse.Namespace) -> None:
    root = Path(args.repo_root).resolve(strict=True)
    archive = Path(args.archive).resolve(strict=True)
    output = Path(args.output)
    tag = args.tag
    sha = args.sha
    if TAG_PATTERN.fullmatch(tag) is None or SHA_PATTERN.fullmatch(sha) is None:
        raise ManifestError("Source tag or SHA is invalid.")
    expected_name = f"mylifegraph-{tag}.tar.gz"
    if archive.name != expected_name:
        raise ManifestError("Source archive filename is invalid.")
    requirements = root / "services/ai_service/requirements.txt"
    contracts = root / "docs/current-contracts.json"
    migrations = sorted((root / "supabase/migrations").glob("*.sql"))
    if not requirements.is_file() or not contracts.is_file() or not migrations:
        raise ManifestError("Release source inputs are incomplete.")
    inspection = _inspect_archive(archive, tag)
    requirements_digest = _sha256(requirements)
    contracts_digest = _sha256(contracts)
    if inspection.git_commit != sha:
        raise ManifestError("Archive Git identity does not match the release SHA.")
    if inspection.embedded_digests != {
        "services/ai_service/requirements.txt": requirements_digest,
        "docs/current-contracts.json": contracts_digest,
    }:
        raise ManifestError("Archive content does not match the tagged checkout.")
    checkout_migrations = tuple((path.name, _sha256(path)) for path in migrations)
    if inspection.migrations != checkout_migrations:
        raise ManifestError("Archive migrations do not match the tagged checkout.")
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "release_tag": tag,
        "release_sha": sha,
        "created_at_utc": args.created_at,
        "source_archive": {"name": archive.name, "sha256": _sha256(archive)},
        "requirements_sha256": requirements_digest,
        "contracts_sha256": contracts_digest,
        "migration_head": inspection.migrations[-1][0],
        "migration_inventory": _migration_inventory(inspection.migrations),
    }
    _validate_manifest(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _verify(args: argparse.Namespace) -> None:
    manifest = _validate_manifest(_read_manifest(Path(args.manifest)))
    archive = Path(args.archive).resolve(strict=True)
    if archive.name != manifest["source_archive"]["name"]:
        raise ManifestError("Archive filename does not match its manifest.")
    if _sha256(archive) != manifest["source_archive"]["sha256"]:
        raise ManifestError("Archive checksum does not match its manifest.")
    if args.expected_tag and args.expected_tag != manifest["release_tag"]:
        raise ManifestError("Manifest release tag is not the expected tag.")
    inspection = _inspect_archive(archive, manifest["release_tag"])
    if inspection.git_commit != manifest["release_sha"]:
        raise ManifestError("Archive Git identity does not match the manifest.")
    if inspection.embedded_digests != {
        "services/ai_service/requirements.txt": manifest["requirements_sha256"],
        "docs/current-contracts.json": manifest["contracts_sha256"],
    }:
        raise ManifestError("Archive content hashes do not match the manifest.")
    if (
        inspection.migrations[-1][0] != manifest["migration_head"]
        or _migration_inventory(inspection.migrations)
        != manifest["migration_inventory"]
    ):
        raise ManifestError("Archive migrations do not match the manifest.")


def _field(args: argparse.Namespace) -> None:
    manifest = _validate_manifest(_read_manifest(Path(args.manifest)))
    if args.name == "migration_count":
        value = manifest["migration_inventory"]["count"]
    elif args.name == "migration_identity_sha256":
        value = manifest["migration_inventory"]["identity_sha256"]
    else:
        value = manifest[args.name]
    if not isinstance(value, (str, int)):
        raise ManifestError("Requested manifest field is not scalar text.")
    print(value)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="operation", required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--repo-root", required=True)
    create.add_argument("--archive", required=True)
    create.add_argument("--tag", required=True)
    create.add_argument("--sha", required=True)
    create.add_argument("--created-at", required=True)
    create.add_argument("--output", required=True)
    create.set_defaults(handler=_create)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--manifest", required=True)
    verify.add_argument("--archive", required=True)
    verify.add_argument("--expected-tag")
    verify.set_defaults(handler=_verify)
    field = subparsers.add_parser("field")
    field.add_argument("--manifest", required=True)
    field.add_argument(
        "--name",
        choices=[
            "release_tag",
            "release_sha",
            "migration_head",
            "migration_count",
            "migration_identity_sha256",
        ],
        required=True,
    )
    field.set_defaults(handler=_field)
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        args.handler(args)
    except ManifestError as exc:
        print(f"release manifest error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
