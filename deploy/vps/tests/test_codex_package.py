from __future__ import annotations

import importlib.util
import io
import json
import os
import stat
import tarfile
import tempfile
import unittest
from pathlib import Path


VPS = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "codex_package_installer", VPS / "bin/install_codex_cli.py"
)
assert SPEC and SPEC.loader
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)
MANIFEST = json.loads((VPS / "manifests/codex-cli.json").read_text())
METADATA = {
    "layoutVersion": 1,
    "version": "0.148.0",
    "target": "x86_64-unknown-linux-musl",
    "variant": "codex",
    "entrypoint": "bin/codex",
    "resourcesDir": "codex-resources",
    "pathDir": "codex-path",
}
FILES = {
    "bin/codex": b"main binary",
    "bin/codex-code-mode-host": b"code mode helper",
    "codex-package.json": json.dumps(METADATA).encode(),
    "codex-path/rg": b"search helper",
    "codex-resources/bwrap": b"sandbox helper",
    "codex-resources/zsh/bin/zsh": b"shell helper",
}
DIRS = ["bin", "codex-path", "codex-resources", "codex-resources/zsh",
        "codex-resources/zsh/bin"]


def package(*, files=None, extra=None, special=None):
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode="w:gz") as archive:
        for name in DIRS:
            entry = tarfile.TarInfo(name)
            entry.type = tarfile.DIRTYPE
            archive.addfile(entry)
        for name, content in (FILES if files is None else files).items():
            entry = tarfile.TarInfo(name)
            entry.size = len(content)
            archive.addfile(entry, io.BytesIO(content))
        if extra:
            entry = tarfile.TarInfo(extra)
            entry.size = 1
            archive.addfile(entry, io.BytesIO(b"x"))
        if special:
            archive.addfile(special)
    result.seek(0)
    return result


class CodexPackageTests(unittest.TestCase):
    def test_complete_package_and_modes_survive_restrictive_umask(self):
        with tempfile.TemporaryDirectory() as raw:
            target = Path(raw) / "package"
            previous = os.umask(0o077)
            try:
                INSTALLER._extract_package(package(), MANIFEST, target)
            finally:
                os.umask(previous)
            for name, content in FILES.items():
                self.assertEqual((target / name).read_bytes(), content)
                expected = 0o444 if name == "codex-package.json" else 0o555
                self.assertEqual(stat.S_IMODE((target / name).stat().st_mode), expected)
            for name in ["", *DIRS]:
                self.assertEqual(stat.S_IMODE((target / name).stat().st_mode), 0o555)
            original = INSTALLER._package_digests(target)
            helper = target / "bin/codex-code-mode-host"
            helper.chmod(0o755)
            helper.write_bytes(b"tampered sidecar")
            changed = INSTALLER._package_digests(target)
            self.assertEqual(original["bin/codex"], changed["bin/codex"])
            self.assertNotEqual(original, changed)

    def test_rejects_missing_extra_duplicate_and_unsafe_members(self):
        missing = dict(FILES)
        del missing["codex-path/rg"]
        cases = [package(files=missing)]
        for name in ["extra", "bin/codex", "../escape", "/absolute"]:
            cases.append(package(extra=name))
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE]:
            files = dict(FILES)
            del files["bin/codex"]
            entry = tarfile.TarInfo("bin/codex")
            entry.type = kind
            entry.linkname = "/etc/passwd"
            cases.append(package(files=files, special=entry))
        for archive in cases:
            with self.subTest(archive=archive), tempfile.TemporaryDirectory() as raw:
                with self.assertRaises(INSTALLER.CodexInstallError):
                    INSTALLER._extract_package(archive, MANIFEST, Path(raw) / "package")
                self.assertFalse((Path(raw) / "package").exists())

    def test_rejects_wrong_or_ambiguous_package_metadata(self):
        invalid = [
            {**METADATA, "version": "0.149.0"},
            {**METADATA, "target": "aarch64-unknown-linux-musl"},
            {**METADATA, "layoutVersion": True},
            {**METADATA, "entrypoint": "../codex"},
            {**METADATA, "extra": "unsupported"},
            [],
        ]
        payloads = [json.dumps(value).encode() for value in invalid]
        payloads.append(json.dumps(METADATA).replace('"layoutVersion": 1',
                        '"layoutVersion": 1, "layoutVersion": 1').encode())
        for payload in payloads:
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as raw:
                files = {**FILES, "codex-package.json": payload}
                with self.assertRaises(INSTALLER.CodexInstallError):
                    INSTALLER._extract_package(package(files=files), MANIFEST,
                                               Path(raw) / "package")

    def test_rejects_oversized_package_before_extracting(self):
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as raw:
            with patch.object(INSTALLER, "MAX_BINARY_BYTES", 10):
                with self.assertRaises(INSTALLER.CodexInstallError):
                    INSTALLER._extract_package(package(), MANIFEST, Path(raw) / "package")
            self.assertFalse((Path(raw) / "package").exists())


if __name__ == "__main__":
    unittest.main()
