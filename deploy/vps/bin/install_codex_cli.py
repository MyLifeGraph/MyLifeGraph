#!/usr/bin/python3 -I
"""Install one verified Codex CLI archive through the root bootstrap boundary."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import BinaryIO, Iterator


INSTALLER_PATH = Path("/usr/local/libexec/mylifegraph/install_codex_cli.py")
MANIFEST_PATH = Path("/usr/local/libexec/mylifegraph/manifests/codex-cli.json")
INCOMING_ROOT = Path("/srv/mylifegraph/incoming")
INSTALL_ROOT = Path("/opt/mylifegraph/codex")
EXECUTOR_USER = "mylifegraph-coach"
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
MAX_BINARY_BYTES = 512 * 1024 * 1024
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
DIGEST = re.compile(r"[0-9a-f]{64}")
ASSET = re.compile(r"codex-package-[A-Za-z0-9_.-]+\.tar\.gz")


class CodexInstallError(RuntimeError):
    pass


def _fail(message: str) -> None:
    raise CodexInstallError(message)


def _sha256(handle: BinaryIO) -> str:
    handle.seek(0)
    digest = hashlib.sha256()
    while chunk := handle.read(1024 * 1024):
        digest.update(chunk)
    handle.seek(0)
    return digest.hexdigest()


def _safe_parent_chain(path: Path, stop: Path, *, expected_uid: int) -> None:
    current = path
    stop = stop.resolve(strict=True)
    while True:
        info = current.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != expected_uid:
            _fail("protected path parent ownership is invalid")
        if stat.S_IMODE(info.st_mode) & 0o022:
            _fail("protected path parent is group/world writable")
        if current == stop:
            return
        if stop not in current.parents:
            _fail("protected path leaves its approved parent chain")
        current = current.parent


@contextmanager
def _open_protected_file(
    path: Path,
    *,
    expected_parent: Path,
    chain_stop: Path,
    expected_uid: int,
    expected_mode: int,
    max_bytes: int,
) -> Iterator[BinaryIO]:
    if path.parent != expected_parent:
        _fail("protected input is outside its exact approved directory")
    _safe_parent_chain(path.parent, chain_stop, expected_uid=expected_uid)
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        info = os.fstat(descriptor)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != expected_uid
            or stat.S_IMODE(info.st_mode) != expected_mode
            or info.st_nlink != 1
            or info.st_size <= 0
            or info.st_size > max_bytes
        ):
            _fail("protected input metadata is invalid")
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            yield handle
    finally:
        os.close(descriptor)


def _load_manifest(handle: BinaryIO) -> dict[str, str]:
    try:
        raw = handle.read(MAX_ARCHIVE_BYTES + 1)
        handle.seek(0)
        value = json.loads(raw)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise CodexInstallError("Codex manifest is invalid JSON") from exc
    required = {
        "schema_version",
        "version",
        "platform",
        "asset_name",
        "asset_sha256",
        "source_url",
        "checksum_source_url",
        "expected_version_output",
        "install_root",
        "verified_utc_date",
    }
    if (
        not isinstance(value, dict)
        or set(value) != required
        or not all(isinstance(item, str) for item in value.values())
    ):
        _fail("Codex manifest shape is invalid")
    manifest: dict[str, str] = value
    if manifest["schema_version"] != "mylifegraph-codex-cli-v1":
        _fail("Codex manifest version is unsupported")
    if VERSION.fullmatch(manifest["version"]) is None:
        _fail("Codex version is invalid")
    if manifest["platform"] != "x86_64-unknown-linux-musl":
        _fail("Codex platform is not approved")
    if ASSET.fullmatch(manifest["asset_name"]) is None:
        _fail("Codex asset name is invalid")
    if DIGEST.fullmatch(manifest["asset_sha256"]) is None:
        _fail("Codex asset checksum is invalid")
    expected_release = f"rust-v{manifest['version']}"
    expected_source = (
        f"https://github.com/openai/codex/releases/download/{expected_release}/"
        f"{manifest['asset_name']}"
    )
    expected_checksums = (
        f"https://github.com/openai/codex/releases/download/{expected_release}/"
        "codex-package_SHA256SUMS"
    )
    if (
        manifest["source_url"] != expected_source
        or manifest["checksum_source_url"] != expected_checksums
        or manifest["expected_version_output"]
        != f"codex-cli {manifest['version']}"
        or manifest["install_root"] != str(INSTALL_ROOT)
        or re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", manifest["verified_utc_date"])
        is None
    ):
        _fail("Codex manifest authority fields are invalid")
    return manifest


def _extract_binary(
    archive_handle: BinaryIO, manifest: dict[str, str], destination: Path
) -> None:
    expected_member = f"codex-{manifest['platform']}"
    try:
        with tarfile.open(fileobj=archive_handle, mode="r:gz") as archive:
            members = archive.getmembers()
            if (
                len(members) != 1
                or not members[0].isreg()
                or members[0].name != expected_member
                or members[0].size <= 0
                or members[0].size > MAX_BINARY_BYTES
            ):
                _fail("Codex archive must contain exactly the bounded expected binary")
            source = archive.extractfile(members[0])
            if source is None:
                _fail("Codex archive binary is unreadable")
            with source, destination.open("xb") as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
    except tarfile.TarError as exc:
        raise CodexInstallError("Codex archive is invalid") from exc
    destination.chmod(0o555)


def _probe_as_executor(binary: Path, manifest: dict[str, str], root: Path) -> None:
    try:
        account = pwd.getpwnam(EXECUTOR_USER)
    except KeyError as exc:
        raise CodexInstallError("mylifegraph-coach account does not exist") from exc
    os.chown(root, 0, account.pw_gid)
    root.chmod(0o750)
    probe_root = root / "probe"
    codex_home = probe_root / ".codex"
    probe_root.mkdir(mode=0o750)
    codex_home.mkdir(mode=0o700)
    os.chown(probe_root, 0, account.pw_gid)
    os.chown(codex_home, account.pw_uid, account.pw_gid)

    def demote() -> None:
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
        os.umask(0o077)

    result = subprocess.run(
        [str(binary), "--version"],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
        cwd=probe_root,
        env={
            "HOME": str(probe_root),
            "CODEX_HOME": str(codex_home),
            "PATH": "/usr/bin:/bin",
            "LANG": "C.UTF-8",
        },
        preexec_fn=demote,
    )
    if (
        result.returncode != 0
        or result.stdout.strip() != manifest["expected_version_output"]
        or result.stderr.strip()
    ):
        _fail("Codex binary failed the unprivileged exact-version probe")


def _validate_installed_binary(binary: Path, expected_digest: str) -> None:
    for directory in [binary.parents[1], binary.parent]:
        info = directory.lstat()
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_uid != 0
            or stat.S_IMODE(info.st_mode) != 0o555
        ):
            _fail("existing Codex version directory is mutable or invalid")
    info = binary.lstat()
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != 0
        or stat.S_IMODE(info.st_mode) != 0o555
        or info.st_nlink != 1
    ):
        _fail("existing Codex binary metadata is invalid")
    with binary.open("rb") as handle:
        if _sha256(handle) != expected_digest:
            _fail("existing Codex binary differs from the verified archive")


def _install(extracted: Path, manifest: dict[str, str], digest: str) -> Path:
    INSTALL_ROOT.mkdir(parents=True, exist_ok=True, mode=0o755)
    _safe_parent_chain(INSTALL_ROOT.parent, Path("/opt"), expected_uid=0)
    install_info = INSTALL_ROOT.lstat()
    if (
        not stat.S_ISDIR(install_info.st_mode)
        or install_info.st_uid != 0
        or stat.S_IMODE(install_info.st_mode) != 0o755
    ):
        _fail("Codex install root metadata is invalid")
    version_root = INSTALL_ROOT / manifest["version"]
    binary = version_root / "bin/codex"
    if version_root.exists() or version_root.is_symlink():
        _validate_installed_binary(binary, digest)
    else:
        staging = Path(
            tempfile.mkdtemp(prefix=f".{manifest['version']}.", dir=INSTALL_ROOT)
        )
        try:
            os.chown(staging, 0, 0)
            bin_root = staging / "bin"
            bin_root.mkdir(mode=0o755)
            target = bin_root / "codex"
            with extracted.open("rb") as source, target.open("xb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
            os.chown(target, 0, 0)
            target.chmod(0o555)
            bin_root.chmod(0o555)
            staging.chmod(0o555)
            staging.replace(version_root)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
        _validate_installed_binary(binary, digest)
    current = INSTALL_ROOT / "current"
    if current.exists() and not current.is_symlink():
        _fail("Codex current path is not a symlink")
    if current.is_symlink():
        target = Path(os.readlink(current))
        if not target.is_absolute() or target.parent != INSTALL_ROOT:
            _fail("Codex current symlink target is invalid")
    current_tmp = INSTALL_ROOT / f".current.{os.getpid()}"
    if current_tmp.exists() or current_tmp.is_symlink():
        _fail("Codex temporary current link already exists")
    current_tmp.symlink_to(version_root)
    current_tmp.replace(current)
    return binary


def _validate_installer() -> None:
    invoked = Path(__file__).absolute()
    if invoked != INSTALLER_PATH or invoked.is_symlink():
        _fail("installer must run from its exact installed non-symlink path")
    with _open_protected_file(
        INSTALLER_PATH,
        expected_parent=INSTALLER_PATH.parent,
        chain_stop=Path("/usr/local"),
        expected_uid=0,
        expected_mode=0o555,
        max_bytes=1024 * 1024,
    ):
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("installation must run as root")
    try:
        if not sys.flags.isolated:
            _fail("installer must run through its isolated Python shebang")
        if platform.system() != "Linux" or platform.machine() not in {
            "x86_64",
            "AMD64",
        }:
            _fail("Codex manifest is approved only for x86_64 Linux")
        _validate_installer()
        archive_path = Path(args.archive).absolute()
        with _open_protected_file(
            MANIFEST_PATH,
            expected_parent=MANIFEST_PATH.parent,
            chain_stop=Path("/usr/local"),
            expected_uid=0,
            expected_mode=0o444,
            max_bytes=64 * 1024,
        ) as manifest_handle:
            manifest = _load_manifest(manifest_handle)
        if archive_path.name != manifest["asset_name"]:
            _fail("Codex archive filename does not match the manifest")
        with _open_protected_file(
            archive_path,
            expected_parent=INCOMING_ROOT,
            chain_stop=Path("/srv"),
            expected_uid=0,
            expected_mode=0o400,
            max_bytes=MAX_ARCHIVE_BYTES,
        ) as archive_handle:
            digest = _sha256(archive_handle)
            if digest != manifest["asset_sha256"]:
                _fail("Codex archive checksum does not match the manifest")
            with tempfile.TemporaryDirectory(
                prefix="mylifegraph-codex-install-", dir="/tmp"
            ) as raw_tmp:
                temp_root = Path(raw_tmp)
                extracted = temp_root / "codex"
                _extract_binary(archive_handle, manifest, extracted)
                _probe_as_executor(extracted, manifest, temp_root)
                with extracted.open("rb") as extracted_handle:
                    binary_digest = _sha256(extracted_handle)
                binary = _install(extracted, manifest, binary_digest)
        print(f"Installed verified Codex CLI {manifest['version']} at {binary}")
        return 0
    except (
        OSError,
        ValueError,
        KeyError,
        CodexInstallError,
        subprocess.SubprocessError,
    ) as exc:
        print(f"Codex installation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
