from __future__ import annotations

import base64
import importlib.util
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


BIN = Path(__file__).resolve().parents[1] / "bin"
spec = importlib.util.spec_from_file_location(
    "access_bootstrap", BIN / "bootstrap_access.py"
)
access = importlib.util.module_from_spec(spec)
spec.loader.exec_module(access)


def key(byte: int = 1) -> str:
    blob = (
        struct.pack(">I", 11)
        + b"ssh-ed25519"
        + struct.pack(">I", 32)
        + bytes([byte]) * 32
    )
    return "ssh-ed25519 " + base64.b64encode(blob).decode()


def manifest(keys=None):
    return {"schema_version": access.SCHEMA, "keys": keys or {}}


class AccessBootstrapTests(unittest.TestCase):
    def test_keys_are_plain_distinct_public_keys_for_named_logins(self):
        value = manifest({"mylifegraph-gregor": key() + " gregor@laptop"})
        self.assertEqual(
            access.load_manifest(json.dumps(value).encode()),
            manifest({"mylifegraph-gregor": key()}),
        )
        invalid = [
            manifest({"ops": key()}),
            manifest({"mylifegraph-api": key()}),
            manifest({"mylifegraph-gregor": key(), "mylifegraph-agent": key()}),
            manifest({"mylifegraph-agent": "-----BEGIN OPENSSH PRIVATE KEY-----"}),
            manifest({"mylifegraph-agent": 'command="bash" ' + key()}),
            manifest({"mylifegraph-agent": key() + "\n" + key(2)}),
            manifest({"mylifegraph-agent": "ssh-ed25519 AAAA"}),
            manifest({"mylifegraph-agent": 1}),
            {**manifest(), "sudo": True},
        ]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(access.AccessError):
                access.load_manifest(json.dumps(value).encode())
        with self.assertRaises(access.AccessError):
            access.load_manifest(
                b'{"schema_version":"mylifegraph-access-bootstrap-v1","keys":{},"keys":{}}'
            )

    def test_keyless_accounts_and_services_cannot_get_interactive_shells(self):
        for user in access.USERS:
            self.assertEqual(
                access.account_spec(user, {})["shell"], "/usr/sbin/nologin"
            )
        for user in access.PEOPLE:
            self.assertEqual(
                access.account_spec(user, {user: key()})["shell"], "/bin/bash"
            )
            self.assertEqual(
                access.account_spec(user, {})["groups"], ["mylifegraph-work"]
            )
        self.assertEqual(
            access.account_spec("mylifegraph-build", {})["home"], "/nonexistent"
        )
        self.assertEqual(access.account_spec("mylifegraph-build", {})["groups"], [])

    def test_confirmation_binds_host_keys_installer_and_current_state(self):
        args = dict(
            manifest=manifest(),
            state={"users": {}, "groups": {}},
            previous_keys={},
            host="test-host",
            machine="test-machine",
            installer_digest="a" * 64,
            ssh_digest="b" * 64,
        )
        original = access.digest(access.canonical(access.make_plan(**args)))
        changes = {
            "manifest": manifest({"mylifegraph-agent": key()}),
            "host": "another-host",
            "machine": "another-machine",
            "installer_digest": "c" * 64,
            "ssh_digest": "d" * 64,
            "state": {"users": {"unexpected": {}}, "groups": {}},
        }
        for field, value in changes.items():
            with self.subTest(field=field):
                changed = access.digest(
                    access.canonical(access.make_plan(**{**args, field: value}))
                )
                self.assertNotEqual(original, changed)

    def test_existing_accounts_are_not_silently_adopted(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                patch.object(access, "RECEIPT", Path(directory) / "missing.json"),
                patch.object(
                    access,
                    "identity_snapshot",
                    return_value={"users": {"mylifegraph-agent": {}}, "groups": {}},
                ),
            ):
                with self.assertRaisesRegex(access.AccessError, "refusing adoption"):
                    access.inspect_state(manifest())

    def test_symlink_input_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "target").write_text("test")
            (root / "link").symlink_to(root / "target")
            with self.assertRaises(access.AccessError):
                access.protected(root / "link")

    def test_builder_only_reads_pub_files_and_never_reuses_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            public = root / "agent.pub"
            public.write_text(key())
            output = root / "bundle"
            command = [
                sys.executable,
                str(BIN / "prepare_access_bundle.py"),
                "--output",
                str(output),
                "--key",
                f"mylifegraph-agent={public}",
            ]
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                set(p.name for p in output.iterdir()),
                {"bootstrap_access.py", "access.json", "SHA256SUMS", "ACCESS.md"},
            )
            self.assertEqual(
                json.loads((output / "access.json").read_text()),
                manifest({"mylifegraph-agent": key()}),
            )
            self.assertNotEqual(
                subprocess.run(command, capture_output=True).returncode, 0
            )
            private = root / "id_ed25519"
            private.write_text("PRIVATE CONTENT MUST NOT BE READ OR ECHOED")
            command[-1] = f"mylifegraph-agent={private}"
            command[3] = str(root / "other-bundle")
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PRIVATE CONTENT", result.stdout + result.stderr)
            self.assertFalse((root / "other-bundle").exists())

    def test_non_root_cli_never_mutates_the_host(self):
        with (
            patch.object(access.os, "geteuid", return_value=1000),
            patch.object(
                access.sys, "argv", ["bootstrap_access.py", "--apply", "--confirm", "x"]
            ),
            patch.object(access, "apply") as apply,
        ):
            with self.assertRaisesRegex(access.AccessError, "system|sudo"):
                access.main()
            apply.assert_not_called()

    def test_failed_ssh_validation_removes_own_config_and_never_enables_logins(self):
        commands = []

        def run(*args):
            commands.append(args)
            if args == ("/usr/sbin/sshd", "-t"):
                raise access.AccessError("Invalid SSH configuration")
            return ""

        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "new.conf"
            config.write_text("created by this bootstrap")
            with (
                patch.object(access, "SSH_CONFIG", config),
                patch.object(access, "run", side_effect=run),
                patch.object(access, "effective_ssh", return_value="existing"),
                patch.object(access, "mkdir"),
                patch.object(access, "write"),
                patch.object(Path, "chmod"),
            ):
                with self.assertRaises(access.AccessError):
                    access.apply(
                        manifest({"mylifegraph-agent": key()}), {"users": {}}, {}
                    )
            self.assertFalse(config.exists())
        self.assertFalse(
            any(
                command[0] in ("/usr/bin/systemctl", "/usr/sbin/usermod")
                for command in commands
            )
        )
        self.assertTrue(
            all(
                "--shell" not in command
                or command[command.index("--shell") + 1] == "/usr/sbin/nologin"
                for command in commands
            )
        )

    def test_names_are_aligned_without_changing_protocol_or_service_names(self):
        root = BIN.parent
        self.assertIn(
            "mylifegraph-deploy ALL=",
            (root / "sudoers.d/mylifegraph-deploy").read_text(),
        )
        self.assertIn(
            "User=mylifegraph-coach\n",
            (root / "systemd/mylifegraph-coach-executor.service").read_text(),
        )
        self.assertIn(
            'EXECUTOR_USER = "mylifegraph-coach"',
            (BIN / "install_codex_cli.py").read_text(),
        )
        self.assertIn("mylifegraph-coach", (BIN / "verify_permissions.sh").read_text())
        self.assertNotIn("mylifegraph-mylifegraph", (root / "README.md").read_text())


if __name__ == "__main__":
    unittest.main()
