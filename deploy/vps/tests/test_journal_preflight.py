"""Run the actual protected-env preflight with simulated target ownership."""

import contextlib
from pathlib import Path
import pwd
import stat
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/preflight_host.sh"
SOURCE = (
    SCRIPT.read_text()
    .split("python3 - /etc/mylifegraph/api.env <<'PY'\n", 1)[1]
    .split("\nPY\n", 1)[0]
)
DIRECTORY = Path("/var/lib/mylifegraph-api/deletion-journal")


class JournalPreflightTests(unittest.TestCase):
    def check_config(self, values, *, mode=0o700, uid=995, present=True, symlink=False):
        real_resolve, real_stat = Path.resolve, Path.lstat

        def resolve(path, *args, **kwargs):
            if path == DIRECTORY:
                if not present:
                    raise FileNotFoundError
                return Path("/other") if symlink else DIRECTORY
            return real_resolve(path, *args, **kwargs)

        def lstat(path, *args, **kwargs):
            if path == DIRECTORY:
                return SimpleNamespace(
                    st_mode=stat.S_IFDIR | mode, st_uid=uid, st_gid=981
                )
            return real_stat(path, *args, **kwargs)

        with tempfile.TemporaryDirectory() as raw:
            config = Path(raw) / "api.env"
            config.write_text(
                "".join(f"{key}={value}\n" for key, value in values.items())
            )
            with contextlib.ExitStack() as stack:
                stack.enter_context(
                    patch.object(sys, "argv", ["preflight", str(config)])
                )
                stack.enter_context(patch.object(Path, "resolve", resolve))
                stack.enter_context(patch.object(Path, "lstat", lstat))
                stack.enter_context(
                    patch.object(
                        pwd,
                        "getpwnam",
                        return_value=SimpleNamespace(pw_uid=995, pw_gid=981),
                    )
                )
                try:
                    exec(compile(SOURCE, str(SCRIPT), "exec"), {})
                except SystemExit as result:
                    if result.code != 0:
                        raise

    def test_file_profile_needs_no_s3_credentials(self):
        self.check_config(
            {
                "ACCOUNT_DELETION_JOURNAL_BACKEND": "vps_file",
                "ACCOUNT_DELETION_JOURNAL_DIRECTORY": str(DIRECTORY),
            }
        )

    def test_file_profile_rejects_unprovisioned_or_unsafe_storage(self):
        values = {
            "ACCOUNT_DELETION_JOURNAL_BACKEND": "vps_file",
            "ACCOUNT_DELETION_JOURNAL_DIRECTORY": str(DIRECTORY),
        }
        for options in [
            {"mode": 0o750},
            {"uid": 0},
            {"symlink": True},
            {"present": False},
        ]:
            with (
                self.subTest(options=options),
                self.assertRaises((SystemExit, OSError)),
            ):
                self.check_config(values, **options)
        for path in ["", "/tmp/journal", str(DIRECTORY) + "/child"]:
            with self.subTest(path=path), self.assertRaises(SystemExit):
                self.check_config(
                    {**values, "ACCOUNT_DELETION_JOURNAL_DIRECTORY": path}
                )

    def test_unknown_or_missing_s3_configuration_cannot_fall_back(self):
        for values in [
            {},
            {"ACCOUNT_DELETION_JOURNAL_BACKEND": "vps"},
            {"ACCOUNT_DELETION_JOURNAL_BACKEND": "s3"},
        ]:
            with self.subTest(values=values), self.assertRaises(SystemExit):
                self.check_config(values)

    def test_existing_explicit_and_implicit_s3_profile_still_validate(self):
        values = {
            "ACCOUNT_DELETION_JOURNAL_S3_URL": "https://journal-example.s3.eu-central-1.amazonaws.com",
            "ACCOUNT_DELETION_JOURNAL_S3_REGION": "eu-central-1",
            "ACCOUNT_DELETION_JOURNAL_S3_ACCESS_KEY_ID": "A" * 20,
            "ACCOUNT_DELETION_JOURNAL_S3_SECRET_ACCESS_KEY": "s" * 40,
            "ACCOUNT_DELETION_JOURNAL_S3_KMS_KEY_ARN": "arn:aws:kms:eu-central-1:123456789012:key/11111111-2222-4333-8444-555555555555",
        }
        self.check_config(values)
        self.check_config({**values, "ACCOUNT_DELETION_JOURNAL_BACKEND": "s3"})


if __name__ == "__main__":
    unittest.main()
