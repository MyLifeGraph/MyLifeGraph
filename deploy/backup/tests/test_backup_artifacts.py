from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path


BACKUP_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKUP_ROOT.parents[1]
BIN_ROOT = BACKUP_ROOT / "bin"


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def _realtime_fixture() -> dict[str, object]:
    return {
        "private_only": False,
        "connection_pool": 15,
        "max_concurrent_users": 200,
        "max_events_per_second": 100,
        "max_bytes_per_second": 100000,
        "max_channels_per_client": 100,
        "max_joins_per_second": 100,
        "max_presence_events_per_second": 100,
        "max_payload_size_in_kb": 256,
        "suspend": False,
        "presence_enabled": True,
    }


def _auth_capture(config: dict[str, object]) -> str:
    config.update(
        {
            "mailer_subjects_confirmation": "Confirm your account",
            "mailer_templates_confirmation_content": "<p>Confirm</p>",
            "mailer_subjects_recovery": "Reset your password",
            "mailer_templates_recovery_content": "<p>Reset</p>",
            "rate_limit_email_sent": 4,
            "rate_limit_token_refresh": 150,
            "rate_limit_verify": 30,
        }
    )
    return json.dumps({"auth": config, "realtime": _realtime_fixture()})


class BackupArtifactTests(unittest.TestCase):
    def test_protected_environment_has_no_mandatory_reviewer_dependency(
        self,
    ) -> None:
        readme = (BACKUP_ROOT / "README.md").read_text()

        self.assertIn("No second reviewer account is mandatory", readme)
        self.assertNotIn("independent required reviewer", readme)

    def test_sources_parse_and_backup_script_never_uses_dry_run(self) -> None:
        for path in sorted(BIN_ROOT.glob("*.sh")):
            result = _run("bash", "-n", str(path))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("--dry-run", path.read_text())
            self.assertNotIn("--password", path.read_text())
        for path in sorted(BIN_ROOT.glob("*.py")):
            result = _run(sys.executable, "-m", "py_compile", str(path))
            self.assertEqual(result.returncode, 0, result.stderr)
        runner = (BIN_ROOT / "run_backup.sh").read_text()
        self.assertIn("approved off-host backend", runner)
        self.assertIn('! -L "$protected_file"', runner)
        self.assertIn("accessible outside its owner", runner)
        self.assertIn(
            '--file "$payload/schema.sql" --keep-comments',
            runner,
        )
        self.assertIn('"$SCRIPT_DIR/inventory_excluded_storage.sql"', runner)
        self.assertIn("--excluded-storage-counts", runner)
        excluded_inventory_sql = (
            BIN_ROOT / "inventory_excluded_storage.sql"
        ).read_text()
        self.assertIn("storage.buckets_vectors", excluded_inventory_sql)
        self.assertIn("storage.vector_indexes", excluded_inventory_sql)

    def test_dump_inventory_counts_auth_and_requires_empty_storage(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-backup-test.") as raw:
            root = Path(raw)
            dump = root / "data.sql"
            schema = root / "schema.sql"
            excluded_storage = root / "excluded-storage-counts.tsv"
            schema.write_text("-- Dumped from database version 15.8.1\n")
            excluded_storage.write_text(
                "storage.buckets_vectors|t|0\n"
                "storage.vector_indexes|t|0\n",
                encoding="ascii",
            )
            dump.write_text(
                "\n".join(
                    [
                        'COPY "auth"."users" ("id") FROM stdin;',
                        "one",
                        "two",
                        "\\.",
                        'COPY "auth"."identities" ("id") FROM stdin;',
                        "identity",
                        "\\.",
                        'COPY "storage"."buckets" ("id") FROM stdin;',
                        "\\.",
                        'COPY "storage"."objects" ("id") FROM stdin;',
                        "\\.",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            output = root / "inventory.json"
            result = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_dump.py"),
                str(dump),
                "--schema-dump",
                str(schema),
                "--excluded-storage-counts",
                str(excluded_storage),
                "--output",
                str(output),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(output.read_text())
            self.assertEqual(inventory["auth_user_count"], 2)
            self.assertEqual(inventory["auth_identity_count"], 1)
            self.assertEqual(inventory["storage_object_count"], 0)
            self.assertEqual(
                inventory["excluded_storage_relation_counts"],
                {
                    "storage.buckets_vectors": {
                        "present": True,
                        "row_count": 0,
                    },
                    "storage.vector_indexes": {
                        "present": True,
                        "row_count": 0,
                    },
                },
            )
            self.assertEqual(inventory["postgres_server_version"], "15.8.1")
            self.assertEqual(inventory["total_row_count"], 3)
            self.assertEqual(inventory["data_schemas"], ["auth", "storage"])
            self.assertEqual(
                inventory["pilot_participation_gate"],
                {"present": False},
            )

            dump.write_text(
                dump.read_text().replace(
                    'COPY "storage"."objects" ("id") FROM stdin;\n\\.',
                    'COPY "storage"."objects" ("id") FROM stdin;\nobject\n\\.',
                )
            )
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_dump.py"),
                str(dump),
                "--schema-dump",
                str(schema),
                "--excluded-storage-counts",
                str(excluded_storage),
                "--output",
                str(output),
            )
            self.assertEqual(rejected.returncode, 2)
            self.assertNotIn("object\n", rejected.stderr)

            dump.write_text(
                dump.read_text().replace(
                    'COPY "storage"."objects" ("id") FROM stdin;\nobject\n\\.',
                    'COPY "storage"."objects" ("id") FROM stdin;\n\\.',
                )
            )
            excluded_storage.write_text(
                "storage.buckets_vectors|t|1\n"
                "storage.vector_indexes|t|0\n",
                encoding="ascii",
            )
            vector_rejected = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_dump.py"),
                str(dump),
                "--schema-dump",
                str(schema),
                "--excluded-storage-counts",
                str(excluded_storage),
                "--output",
                str(output),
            )
            self.assertEqual(vector_rejected.returncode, 2)

    def test_manifest_round_trip_detects_restored_part_tampering(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-backup-test.") as raw:
            payload = Path(raw) / "payload"
            payload.mkdir()
            for name in [
                "roles.sql",
                "managed_schema.sql",
                "schema.sql",
                "data.sql",
                "history_schema.sql",
                "history_data.sql",
                "auth_storage_diff.sql",
            ]:
                (payload / name).write_text(f"-- {name}\n")
            (payload / "inventory.json").write_text(
                json.dumps(
                    {
                        "schema_version": "mylifegraph-backup-inventory-v1",
                        "postgres_server_version": "15.8.1",
                        "extensions": [],
                        "auth_user_count": 2,
                        "auth_identity_count": 2,
                        "storage_bucket_count": 0,
                        "storage_object_count": 0,
                        "excluded_storage_relation_counts": {
                            "storage.buckets_vectors": {
                                "present": True,
                                "row_count": 0,
                            },
                            "storage.vector_indexes": {
                                "present": True,
                                "row_count": 0,
                            },
                        },
                        "data_schemas": ["auth", "public", "storage"],
                        "table_count": 4,
                        "total_row_count": 4,
                        "table_row_counts": {
                            "auth.identities": 2,
                            "auth.users": 2,
                            "storage.buckets": 0,
                            "storage.objects": 0,
                        },
                        "pilot_participation_gate": {"present": False},
                    }
                )
            )
            (payload / "migration-inventory.json").write_text(
                json.dumps(
                    {
                        "schema_version": "mylifegraph-migration-inventory-v1",
                        "status": "exact_expected_boundary",
                        "expected_count": 1,
                        "actual_count": 1,
                        "expected_head": "20260819203000_coach_operator_pilot_v1.sql",
                        "actual_head": "20260819203000_coach_operator_pilot_v1.sql",
                        "repository_target_count": 1,
                        "repository_target_head": "20260819203000_coach_operator_pilot_v1.sql",
                        "applied_identity_sha256": "a" * 64,
                        "migrations": [],
                    }
                )
            )
            (payload / "auth-config-inventory.json").write_text(
                json.dumps(
                    {
                        "schema_version": "mylifegraph-auth-config-inventory-v1",
                        "project_ref": "abcdefghijklmnopqrst",
                        "policy_status": "compliant",
                    }
                )
            )
            (payload / "auth-config-recovery.json").write_text(
                json.dumps(
                    {
                        "schema_version": "mylifegraph-auth-config-recovery-v1",
                        "project_ref": "abcdefghijklmnopqrst",
                        "capture_status": "captured",
                    }
                )
            )
            create = _run(
                sys.executable,
                str(BIN_ROOT / "backup_manifest.py"),
                "create",
                "--payload",
                str(payload),
                "--project-ref",
                "abcdefghijklmnopqrst",
                "--started-at",
                "2026-08-19T00:00:00Z",
                "--completed-at",
                "2026-08-19T00:01:00Z",
                "--migration-head",
                "20260819203000_coach_operator_pilot_v1.sql",
                "--retention-class",
                "routine",
                "--supabase-version",
                "2.107.0",
                "--restic-version",
                "0.19.1",
            )
            self.assertEqual(create.returncode, 0, create.stderr)
            verified = _run(
                sys.executable,
                str(BIN_ROOT / "backup_manifest.py"),
                "verify-tree",
                "--root",
                raw,
            )
            self.assertEqual(verified.returncode, 0, verified.stderr)
            (payload / "data.sql").write_text("tampered")
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "backup_manifest.py"),
                "verify-tree",
                "--root",
                raw,
            )
            self.assertNotEqual(rejected.returncode, 0)

    def test_missing_empty_schema_diff_becomes_a_safe_sql_part(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-backup-test.") as raw:
            root = Path(raw)
            sql_part = root / "auth_storage_diff.sql"
            command = (
                sys.executable,
                str(BIN_ROOT / "backup_manifest.py"),
                "ensure-sql-part",
                "--path",
                str(sql_part),
            )

            created = _run(*command)
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertEqual(
                sql_part.read_text(),
                "-- No custom auth/storage schema changes were detected.\n",
            )
            self.assertEqual(sql_part.stat().st_mode & 0o777, 0o600)

            sql_part.write_text("select 1;\n")
            preserved = _run(*command)
            self.assertEqual(preserved.returncode, 0, preserved.stderr)
            self.assertEqual(sql_part.read_text(), "select 1;\n")

            sql_part.unlink()
            sql_part.symlink_to(root / "missing-target")
            rejected = _run(*command)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertFalse((root / "missing-target").exists())

            runner = (BIN_ROOT / "run_backup.sh").read_text()
            self.assertLess(
                runner.index("db diff --db-url"),
                runner.index("ensure-sql-part"),
            )
            self.assertLess(
                runner.index("ensure-sql-part"),
                runner.index("inspect_dump.py"),
            )
            self.assertLess(
                runner.index("inventory_excluded_storage.sql"),
                runner.index("inspect_dump.py"),
            )

    def test_migration_inventory_requires_exact_database_history(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-backup-test.") as raw:
            root = Path(raw)
            migrations = root / "migrations"
            migrations.mkdir()
            (migrations / "20260101000000_first.sql").write_text("select 1;\n")
            (migrations / "20260102000000_second.sql").write_text("select 2;\n")
            history = root / "history.sql"
            history.write_text(
                "\n".join(
                    [
                        "COPY supabase_migrations.schema_migrations (version, name) FROM stdin;",
                        "20260101000000\tfirst",
                        "20260102000000\tsecond",
                        r"\.",
                        "",
                    ]
                )
            )
            output = root / "migration-inventory.json"
            exact = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_migration_history.py"),
                str(history),
                "--migrations-root",
                str(migrations),
                "--expected-head",
                "20260102000000_second.sql",
                "--output",
                str(output),
            )
            self.assertEqual(exact.returncode, 0, exact.stderr)
            inventory = json.loads(output.read_text())
            self.assertEqual(inventory["status"], "exact_expected_boundary")
            self.assertEqual(inventory["actual_head"], "20260102000000_second.sql")

            history.write_text(
                "\n".join(
                    [
                        "COPY supabase_migrations.schema_migrations (version, name) FROM stdin;",
                        "20260102000000\tsecond",
                        "20260101000000\tfirst",
                        r"\.",
                        "",
                    ]
                )
            )
            unordered = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_migration_history.py"),
                str(history),
                "--migrations-root",
                str(migrations),
                "--expected-head",
                "20260102000000_second.sql",
                "--output",
                str(output),
            )
            self.assertEqual(unordered.returncode, 0, unordered.stderr)
            unordered_inventory = json.loads(output.read_text())
            self.assertEqual(
                [
                    row["version"]
                    for row in unordered_inventory["migrations"]
                ],
                ["20260101000000", "20260102000000"],
            )

            history.write_text(
                "\n".join(
                    [
                        "COPY supabase_migrations.schema_migrations (version, name) FROM stdin;",
                        "20260101000000\tfirst",
                        "20260101000000\tfirst",
                        r"\.",
                        "",
                    ]
                )
            )
            duplicate = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_migration_history.py"),
                str(history),
                "--migrations-root",
                str(migrations),
                "--expected-head",
                "20260102000000_second.sql",
                "--output",
                str(output),
            )
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn("duplicate identity", duplicate.stderr)

            history.write_text(
                "\n".join(
                    [
                        "COPY supabase_migrations.schema_migrations (version, name) FROM stdin;",
                        "20260101000000\tfirst",
                        r"\.",
                        "",
                    ]
                )
            )
            lagging = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_migration_history.py"),
                str(history),
                "--migrations-root",
                str(migrations),
                "--expected-head",
                "20260102000000_second.sql",
                "--output",
                str(output),
            )
            self.assertNotEqual(lagging.returncode, 0)
            self.assertIn("differs from repository", lagging.stderr)

            pre_migration = _run(
                sys.executable,
                str(BIN_ROOT / "inspect_migration_history.py"),
                str(history),
                "--migrations-root",
                str(migrations),
                "--expected-head",
                "20260101000000_first.sql",
                "--output",
                str(output),
            )
            self.assertEqual(pre_migration.returncode, 0, pre_migration.stderr)
            pre_inventory = json.loads(output.read_text())
            self.assertEqual(pre_inventory["actual_count"], 1)
            self.assertEqual(
                pre_inventory["repository_target_head"],
                "20260102000000_second.sql",
            )

    def test_auth_config_inventory_is_secret_free_and_captcha_required(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-backup-test.") as raw:
            root = Path(raw)
            source = root / "auth.json"
            output = root / "auth-inventory.json"
            recovery_output = root / "auth-recovery.json"
            config = {
                "site_url": "https://app.example.test",
                "uri_allow_list": (
                    "https://app.example.test/,"
                    "com.mylifegraph.app://login-callback/"
                ),
                "external_email_enabled": True,
                "disable_signup": False,
                "mailer_autoconfirm": False,
                "external_google_enabled": True,
                "external_google_client_id": "client-id.apps.example.test",
                "external_google_secret": "must-not-survive",
                "security_captcha_enabled": True,
                "security_captcha_provider": "turnstile",
                "security_captcha_secret": "must-not-survive-either",
                "smtp_host": "smtp.example.test",
                "smtp_port": 587,
                "smtp_sender_name": "MyLifeGraph",
                "smtp_admin_email": "ops@example.test",
                "smtp_user": "secret-user",
                "smtp_pass": "secret-password",
            }
            source.write_text(_auth_capture(config))
            accepted = _run(
                sys.executable,
                str(BIN_ROOT / "fetch_auth_config_inventory.py"),
                "--project-ref",
                "abcdefghijklmnopqrst",
                "--expected-app-origin",
                "https://app.example.test",
                "--expected-turnstile-site-key",
                "1x00000000000000000000AA",
                "--input",
                str(source),
                "--output",
                str(output),
                "--recovery-output",
                str(recovery_output),
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            serialized = output.read_text()
            self.assertNotIn("must-not-survive", serialized)
            self.assertNotIn("secret-user", serialized)
            self.assertNotIn("secret-password", serialized)
            inventory = json.loads(serialized)
            recovery = json.loads(recovery_output.read_text())
            self.assertEqual(inventory["captcha"]["provider"], "turnstile")
            self.assertEqual(
                inventory["captcha"]["site_key_sha256"],
                hashlib.sha256(b"1x00000000000000000000AA").hexdigest(),
            )
            self.assertEqual(inventory["google_oauth"]["client_id_count"], 1)
            self.assertNotIn("client-id.apps.example.test", serialized)
            self.assertNotIn("ops@example.test", serialized)
            self.assertNotIn("<p>Confirm</p>", serialized)
            self.assertEqual(
                recovery["google_oauth"]["client_ids"],
                ["client-id.apps.example.test"],
            )
            self.assertEqual(recovery["smtp"]["host"], "smtp.example.test")
            self.assertEqual(
                recovery["email_templates"]["confirmation"]["content"],
                "<p>Confirm</p>",
            )
            recovery_serialized = recovery_output.read_text()
            self.assertNotIn("must-not-survive", recovery_serialized)
            self.assertNotIn("secret-user", recovery_serialized)
            self.assertNotIn("secret-password", recovery_serialized)
            self.assertEqual(inventory["policy_status"], "compliant")
            self.assertIn(
                "com.mylifegraph.app://login-callback/",
                inventory["redirect_allowlist"],
            )

            config["security_captcha_enabled"] = False
            source.write_text(_auth_capture(config))
            drifted = _run(
                sys.executable,
                str(BIN_ROOT / "fetch_auth_config_inventory.py"),
                "--project-ref",
                "abcdefghijklmnopqrst",
                "--expected-app-origin",
                "https://app.example.test",
                "--expected-turnstile-site-key",
                "1x00000000000000000000AA",
                "--input",
                str(source),
                "--output",
                str(output),
                "--recovery-output",
                str(recovery_output),
            )
            self.assertEqual(drifted.returncode, 0, drifted.stderr)
            drift_inventory = json.loads(output.read_text())
            self.assertEqual(drift_inventory["policy_status"], "noncompliant")
            self.assertIn(
                "captcha_disabled", drift_inventory["policy_violations"]
            )

            config["security_captcha_enabled"] = True
            config["security_captcha_provider"] = "hcaptcha"
            source.write_text(_auth_capture(config))
            wrong_provider = _run(
                sys.executable,
                str(BIN_ROOT / "fetch_auth_config_inventory.py"),
                "--project-ref",
                "abcdefghijklmnopqrst",
                "--expected-app-origin",
                "https://app.example.test",
                "--expected-turnstile-site-key",
                "1x00000000000000000000AA",
                "--input",
                str(source),
                "--output",
                str(output),
                "--recovery-output",
                str(recovery_output),
            )
            self.assertEqual(wrong_provider.returncode, 0, wrong_provider.stderr)
            wrong_inventory = json.loads(output.read_text())
            self.assertEqual(wrong_inventory["policy_status"], "noncompliant")
            self.assertIn(
                "captcha_provider_mismatch",
                wrong_inventory["policy_violations"],
            )

            config["security_captcha_provider"] = "turnstile"
            config["uri_allow_list"] += ",custom.attacker://callback/"
            source.write_text(_auth_capture(config))
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "fetch_auth_config_inventory.py"),
                "--project-ref",
                "abcdefghijklmnopqrst",
                "--expected-app-origin",
                "https://app.example.test",
                "--expected-turnstile-site-key",
                "1x00000000000000000000AA",
                "--input",
                str(source),
                "--output",
                str(output),
                "--recovery-output",
                str(recovery_output),
            )
            self.assertNotEqual(rejected.returncode, 0)

    def test_auth_config_policy_flags_origin_redirect_and_smtp_drift(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-backup-test.") as raw:
            root = Path(raw)
            source = root / "auth.json"
            output = root / "auth-inventory.json"
            recovery_output = root / "auth-recovery.json"
            base = {
                "site_url": "https://wrong.example.test",
                "uri_allow_list": "https://app.example.test/",
                "external_email_enabled": True,
                "disable_signup": False,
                "mailer_autoconfirm": False,
                "external_google_enabled": False,
                "external_google_client_id": "",
                "security_captcha_enabled": True,
                "security_captcha_provider": "turnstile",
                "smtp_host": "",
                "smtp_port": None,
                "smtp_sender_name": "",
                "smtp_admin_email": "",
            }
            source.write_text(_auth_capture(base))
            result = _run(
                sys.executable,
                str(BIN_ROOT / "fetch_auth_config_inventory.py"),
                "--project-ref",
                "abcdefghijklmnopqrst",
                "--expected-app-origin",
                "https://app.example.test",
                "--expected-turnstile-site-key",
                "1x00000000000000000000AA",
                "--input",
                str(source),
                "--output",
                str(output),
                "--recovery-output",
                str(recovery_output),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(output.read_text())
            self.assertEqual(inventory["policy_status"], "noncompliant")
            self.assertEqual(
                set(inventory["policy_violations"]),
                {
                    "site_url_mismatch",
                    "native_redirect_missing",
                    "custom_smtp_host_missing",
                    "custom_smtp_port_missing",
                    "custom_smtp_sender_name_missing",
                    "custom_smtp_admin_email_missing",
                },
            )
            self.assertFalse(inventory["smtp"]["custom_configured"])

    def test_workflow_is_default_off_and_never_uploads_plaintext(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/pilot-backup.yml").read_text()
        self.assertIn("if: vars.PILOT_BACKUP_ENABLED == 'true'", workflow)
        self.assertIn(
            "supabase/setup-cli@3c2f5e2ae34c34e428e8e206e2c4d21fa2d20fbf # v2",
            workflow,
        )
        self.assertIn("version: 2.107.0", workflow)
        self.assertIn("SUPABASE_BIN: supabase", workflow)
        self.assertNotIn("SUPABASE_BIN: /usr/local/bin/supabase", workflow)
        self.assertNotIn("actions/upload-artifact", workflow)
        self.assertNotIn("--dry-run", workflow)
        self.assertIn("RUN_DATABASE_RESTORE_REHEARSAL", workflow)
        self.assertIn("17 3 1 * *", workflow)
        identity_index = workflow.index(
            "Verify protected main identity before secrets"
        )
        secret_index = workflow.index("Prepare protected backup credentials")
        self.assertLess(identity_index, secret_index)
        for required in (
            '[[ "$GITHUB_REPOSITORY" == "MyLifeGraph/MyLifeGraph" ]]',
            '[[ "$GITHUB_REF" == "refs/heads/main" ]]',
            '[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]',
            '[[ "$(git rev-parse refs/remotes/origin/main)" == "$GITHUB_SHA" ]]',
            '[[ -z "$(git status --porcelain=v1)" ]]',
        ):
            self.assertIn(required, workflow)
        restore_runner = (BIN_ROOT / "run_restore_rehearsal.sh").read_text()
        self.assertIn(
            'RECOVERY_MIGRATION_HEAD="20260820200000_account_deletion_replayer_role_guard_v2.sql"',
            restore_runner,
        )
        self.assertLess(
            restore_runner.index('"$SUPABASE_BIN" migration up'),
            restore_runner.index('"$SCRIPT_DIR/replay_deletion_journal.py" render-sql'),
        )
        self.assertIn(
            '--recovery-migration-head "$RECOVERY_MIGRATION_HEAD"',
            restore_runner,
        )
        action_refs = re.findall(r"^\s*(?:-\s*)?uses:\s*([^\s#]+)", workflow, re.M)
        self.assertTrue(action_refs)
        self.assertTrue(
            all(re.search(r"@[0-9a-f]{40}$", ref) for ref in action_refs),
            action_refs,
        )

    def test_restore_targets_pin_hosted_postgres_major(self) -> None:
        for relative in (
            "restore-target/supabase/config.toml",
            "reference-target/supabase/config.toml",
        ):
            config = (BACKUP_ROOT / relative).read_text()
            self.assertIn("major_version = 17", config)
            self.assertNotIn("major_version = 15", config)

        normalizer = (
            BACKUP_ROOT / "reference-target/normalize_optional_legacy.sql"
        ).read_text()
        for table in (
            "FocusSession",
            "CoachMessage",
            "AIInsight",
            "ActivityLog",
            "DailyLog",
            "MemoryEntry",
            "MoodLog",
            "Notification",
            "ScheduleItem",
            "SleepLog",
            "Task",
            "Habit",
            "Goal",
            "User",
        ):
            self.assertIn(f'drop table if exists public."{table}"', normalizer)

        public_defaults = (
            BACKUP_ROOT / "restore-target/neutralize_public_defaults.sql"
        ).read_text()
        creator_defaults = (
            BACKUP_ROOT
            / "restore-target/neutralize_restore_creator_defaults.sql"
        ).read_text()
        for object_kind in ("tables", "sequences", "functions"):
            self.assertIn(
                f"revoke all on {object_kind} from public, postgres, anon, "
                "authenticated, service_role",
                public_defaults,
            )
            self.assertIn(
                f"revoke all on {object_kind} from public, postgres, anon, "
                "authenticated, service_role",
                creator_defaults,
            )
        self.assertIn("for role postgres in schema public", public_defaults)
        self.assertIn(
            "for role supabase_admin in schema public", creator_defaults
        )
        restore_runner = (BIN_ROOT / "run_restore_rehearsal.sh").read_text()
        self.assertLess(
            restore_runner.index("neutralize-public-defaults.sql"),
            restore_runner.index("--file /tmp/mylifegraph-restore/schema.sql"),
        )
        self.assertGreaterEqual(
            restore_runner.count("neutralize-restore-creator-defaults.sql"),
            2,
        )

    def test_managed_schema_split_keeps_dependencies_and_conflicts_separate(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-managed-split.") as raw:
            root = Path(raw)
            source = root / "managed.sql"
            pre = root / "pre.sql"
            post = root / "post.sql"
            cleanup = root / "cleanup.sql"
            source.write_text(
                "-- PostgreSQL database dump\n"
                "-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres\n"
                "create schema auth;\n"
                "-- Name: storage; Type: SCHEMA; Schema: -; Owner: postgres\n"
                "create schema storage;\n"
                "-- Name: users; Type: TABLE; Schema: auth; Owner: postgres\n"
                "create table auth.users (id uuid primary key);\n"
                "-- Name: users users_id_check; Type: CONSTRAINT; Schema: auth; Owner: postgres\n"
                "alter table auth.users add constraint users_id_check "
                "check (id is not null);\n"
                "-- Name: users app_trigger; Type: TRIGGER; Schema: auth; Owner: postgres\n"
                "create trigger app_trigger after insert on auth.users "
                "execute function public.handle_user();\n"
                "-- Name: objects owner_policy; Type: POLICY; Schema: storage; Owner: postgres\n"
                "create policy owner_policy on storage.objects using (true);\n"
                "-- Name: TABLE users; Type: ACL; Schema: auth; Owner: postgres\n"
                'GRANT REFERENCES,TRIGGER ON TABLE "auth"."users" TO "postgres";\n'
            )
            result = _run(
                sys.executable,
                str(BIN_ROOT / "split_managed_schema.py"),
                str(source),
                "--pre-output",
                str(pre),
                "--post-output",
                str(post),
                "--conflict-cleanup-output",
                str(cleanup),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("create table auth.users", pre.read_text())
            self.assertIn("users_id_check", pre.read_text())
            self.assertIn("REFERENCES,TRIGGER", pre.read_text())
            self.assertNotIn("create trigger app_trigger", pre.read_text())
            self.assertIn("create trigger app_trigger", post.read_text())
            self.assertIn("create policy owner_policy", post.read_text())
            self.assertIn(
                'drop trigger if exists "app_trigger" on "auth"."users";',
                cleanup.read_text(),
            )
            self.assertIn(
                'drop policy if exists "owner_policy" on "storage"."objects";',
                cleanup.read_text(),
            )
            for output in (pre, post, cleanup):
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_schema_comparison_separates_acl_authority_and_boolean_format(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-schema-compare.") as raw:
            root = Path(raw)
            restored = root / "restored.sql"
            reference = root / "reference.sql"
            output = root / "comparison.json"
            restored.write_text(
                "create table public.profiles (\n"
                "  daily_preparation_budget_minutes integer,\n"
                "  CONSTRAINT profiles_daily_preparation_budget_minutes_check "
                "CHECK (((daily_preparation_budget_minutes IS NULL) OR "
                "((daily_preparation_budget_minutes >= 25) AND "
                "(daily_preparation_budget_minutes <= 480) AND "
                "((daily_preparation_budget_minutes % 5) = 0))))\n"
                ");\n"
            )
            reference.write_text(
                "create table public.profiles (\n"
                "  daily_preparation_budget_minutes integer,\n"
                "  CONSTRAINT profiles_daily_preparation_budget_minutes_check "
                "CHECK (((daily_preparation_budget_minutes IS NULL) OR "
                "(((daily_preparation_budget_minutes >= 25) AND "
                "(daily_preparation_budget_minutes <= 480)) AND "
                "((daily_preparation_budget_minutes % 5) = 0))))\n"
                ");\n"
            )
            accepted = _run(
                sys.executable,
                str(BIN_ROOT / "compare_schema_dumps.py"),
                "--restored",
                str(restored),
                "--reference",
                str(reference),
                "--output",
                str(output),
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            comparison = json.loads(output.read_text())
            self.assertEqual(
                comparison["schema_version"],
                "mylifegraph-schema-comparison-v2",
            )
            self.assertEqual(
                comparison["normalization"]["acl_authority"],
                "strict-schema-digest",
            )

            restored.write_text(
                restored.read_text()
                + "GRANT ALL ON TABLE public.profiles TO service_role;\n"
            )
            acl_rejected = _run(
                sys.executable,
                str(BIN_ROOT / "compare_schema_dumps.py"),
                "--restored",
                str(restored),
                "--reference",
                str(reference),
                "--output",
                str(output),
            )
            self.assertNotEqual(acl_rejected.returncode, 0)
            self.assertFalse(json.loads(output.read_text())["match"])
            restored.write_text(
                restored.read_text().replace(
                    "GRANT ALL ON TABLE public.profiles TO service_role;\n",
                    "",
                )
            )

            reference.write_text(
                reference.read_text().replace("<= 480", "<= 481")
            )
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "compare_schema_dumps.py"),
                "--restored",
                str(restored),
                "--reference",
                str(reference),
                "--output",
                str(output),
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertFalse(json.loads(output.read_text())["match"])

    def test_restore_reference_can_advance_an_exact_backup_prefix(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-reference-test.") as raw:
            root = Path(raw)
            payload = root / "payload"
            migrations = root / "migrations"
            output = root / "output"
            payload.mkdir()
            migrations.mkdir()
            files = [
                "20260101000000_first.sql",
                "20260102000000_second.sql",
                "20260103000000_recovery.sql",
            ]
            for index, name in enumerate(files, start=1):
                (migrations / name).write_text(f"select {index};\n")
            first = migrations / files[0]
            (payload / "migration-inventory.json").write_text(
                json.dumps(
                    {
                        "schema_version": "mylifegraph-migration-inventory-v1",
                        "migrations": [
                            {
                                "version": "20260101000000",
                                "name": "first",
                                "file": files[0],
                                "sha256": hashlib.sha256(
                                    first.read_bytes()
                                ).hexdigest(),
                            }
                        ],
                    }
                )
            )

            result = _run(
                sys.executable,
                str(BIN_ROOT / "prepare_restore_reference.py"),
                "--payload",
                str(payload),
                "--migrations-root",
                str(migrations),
                "--target-head",
                files[-1],
                "--output",
                str(output),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                sorted(path.name for path in output.iterdir()),
                files,
            )
            self.assertTrue(
                all(path.stat().st_mode & 0o777 == 0o400 for path in output.iterdir())
            )

    def test_restore_report_requires_exact_counts_history_and_security(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-restore-test.") as raw:
            payload = Path(raw) / "payload"
            payload.mkdir()
            inventory = {
                "schema_version": "mylifegraph-backup-inventory-v1",
                "postgres_server_version": "15.8.1",
                "extensions": [],
                "auth_user_count": 1,
                "auth_identity_count": 1,
                "storage_bucket_count": 0,
                "storage_object_count": 0,
                "excluded_storage_relation_counts": {
                    "storage.buckets_vectors": {
                        "present": True,
                        "row_count": 0,
                    },
                    "storage.vector_indexes": {
                        "present": True,
                        "row_count": 0,
                    },
                },
                "data_schemas": ["auth", "public", "storage"],
                "table_count": 4,
                "total_row_count": 3,
                "table_row_counts": {
                    "auth.identities": 1,
                    "auth.users": 1,
                    "public.profiles": 1,
                    "storage.objects": 0,
                },
                "pilot_participation_gate": {
                    "present": True,
                    "project_ref": "abcdefghijklmnopqrst",
                    "participation_required": True,
                    "notice_version": "pilot-participation-notice-v1",
                },
            }
            migrations = {
                "schema_version": "mylifegraph-migration-inventory-v1",
                "migrations": [
                    {
                        "version": "20260820150000",
                        "name": "pilot_participation_rls_gate_v1",
                        "file": (
                            "20260820150000_pilot_participation_rls_gate_v1.sql"
                        ),
                        "sha256": "a" * 64,
                    }
                ],
            }
            manifest = {
                "schema_version": "mylifegraph-supabase-backup-v2",
                "project_ref": "abcdefghijklmnopqrst",
                "migration_head": (
                    "20260820150000_pilot_participation_rls_gate_v1.sql"
                ),
                "inventory": inventory,
            }
            (payload / "inventory.json").write_text(json.dumps(inventory))
            (payload / "migration-inventory.json").write_text(
                json.dumps(migrations)
            )
            (payload / "backup-manifest.json").write_text(json.dumps(manifest))
            sql = Path(raw) / "verify.sql"
            rendered = _run(
                sys.executable,
                str(BIN_ROOT / "verify_restored_database.py"),
                "render-sql",
                "--payload",
                str(payload),
                "--output",
                str(sql),
            )
            self.assertEqual(rendered.returncode, 0, rendered.stderr)
            self.assertIn('from "auth"."users"', sql.read_text())
            self.assertIn(
                'from "storage"."buckets_vectors"',
                sql.read_text(),
            )
            restore_verifier_source = (
                BIN_ROOT / "verify_restored_database.py"
            ).read_text()
            self.assertIn("role.rolcanlogin", restore_verifier_source)
            self.assertIn("pg_catalog.pg_auth_members", restore_verifier_source)
            self.assertIn("server_version_num", restore_verifier_source)
            self.assertIn(
                "membership.member = current_user::regrole",
                restore_verifier_source,
            )
            self.assertIn("membership.grantor = 10", restore_verifier_source)
            self.assertIn("'inherit_option'", restore_verifier_source)
            self.assertIn("'set_option'", restore_verifier_source)
            self.assertIn("session_replication_role", (
                BIN_ROOT / "run_restore_rehearsal.sh"
            ).read_text())
            self.assertIn(
                "public.claim_coach_request_v7(uuid,uuid,text,date,text,text,"
                "text,text,timestamp with time zone,timestamp with time zone,"
                "integer)",
                restore_verifier_source,
            )
            self.assertNotIn(
                "public.claim_coach_request_v7(uuid,text,uuid,text,date",
                restore_verifier_source,
            )

            report = {
                "schema_version": "mylifegraph-restore-report-v1",
                "postgres_server_version": "15.8.1.060",
                "table_row_counts": inventory["table_row_counts"],
                "excluded_storage_relation_counts": inventory[
                    "excluded_storage_relation_counts"
                ],
                "migration_identities": [
                    ["20260820150000", "pilot_participation_rls_gate_v1"]
                ],
                "profiles_without_auth": 0,
                "auth_without_profiles": 0,
                "public_rls_unforced": 0,
                "application_executable_security_definers": 0,
                "anon_table_privilege_drift": 0,
                "authenticated_dangerous_privilege_drift": 0,
                "anon_table_default_privilege_drift": 0,
                "authenticated_dangerous_table_default_privilege_drift": 0,
                "generated_projection_grant_drift": 0,
                "critical_service_rpc_missing": 0,
                "legacy_delete_privilege_drift": 0,
                "deletion_replay_authority_drift": 0,
                "critical_owner_policy_missing": 0,
                "auth_profile_trigger_missing": 0,
                "participation_policy_missing": 0,
                "participation_gate_present": True,
                "participation_gate": {
                    "project_ref": "abcdefghijklmnopqrst",
                    "participation_required": True,
                    "notice_version": "pilot-participation-notice-v1",
                },
            }
            report_path = Path(raw) / "report.json"
            schema_comparison = Path(raw) / "schema-comparison.json"
            restored_schema = Path(raw) / "restored-schema.sql"
            reference_schema = Path(raw) / "reference-schema.sql"
            output = Path(raw) / "attestation.json"
            report_path.write_text(json.dumps(report))
            restored_schema.write_text("create schema public;\n")
            reference_schema.write_text("create schema public;\n")
            compared = _run(
                sys.executable,
                str(BIN_ROOT / "compare_schema_dumps.py"),
                "--restored",
                str(restored_schema),
                "--reference",
                str(reference_schema),
                "--output",
                str(schema_comparison),
            )
            self.assertEqual(compared.returncode, 0, compared.stderr)
            accepted = _run(
                sys.executable,
                str(BIN_ROOT / "verify_restored_database.py"),
                "validate",
                "--payload",
                str(payload),
                "--report",
                str(report_path),
                "--schema-comparison",
                str(schema_comparison),
                "--output",
                str(output),
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertEqual(
                json.loads(output.read_text())["postconditions"],
                "passed",
            )

            restore_attestation = json.loads(output.read_text())
            restore_attestation["deletion_replay_required"] = True
            restore_attestation["recovery_migration_head"] = (
                "20260820200000_account_deletion_replayer_role_guard_v2.sql"
            )
            restore_attestation["deletion_replay"] = {
                "schema_version": "mylifegraph-deletion-replay-watermark-v1",
                "project_ref": "abcdefghijklmnopqrst",
                "backup_manifest_sha256": "a" * 64,
                "backup_cutoff_utc": "2026-08-19T00:00:00Z",
                "journal_capture_through_utc": "2026-08-19T01:00:00Z",
                "journal_export_manifest_sha256": "b" * 64,
                "journal_source_inventory_sha256": "c" * 64,
                "replay_set_sha256": "d" * 64,
                "replayed_entry_count": 2,
                "last_replayed_accepted_at": "2026-08-19T00:30:00Z",
                "owner_relation_count": 50,
                "postconditions": "passed",
            }
            output.write_text(json.dumps(restore_attestation))
            summarized = _run(
                sys.executable,
                str(BIN_ROOT / "summarize_restore_attestation.py"),
                str(output),
            )
            self.assertEqual(summarized.returncode, 0, summarized.stderr)
            restore_evidence = json.loads(summarized.stdout)
            self.assertEqual(
                restore_evidence["deletion_replay"]["replay_set_sha256"],
                "d" * 64,
            )
            self.assertEqual(
                restore_evidence["deletion_replay"]["replayed_entry_count"],
                2,
            )
            self.assertNotIn("project_ref", restore_evidence)
            self.assertNotIn("user_id", summarized.stdout)
            self.assertNotIn("deletion_id", summarized.stdout)

            report["auth_without_profiles"] = 1
            report_path.write_text(json.dumps(report))
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "verify_restored_database.py"),
                "validate",
                "--payload",
                str(payload),
                "--report",
                str(report_path),
                "--schema-comparison",
                str(schema_comparison),
                "--output",
                str(output),
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("auth_without_profiles", rejected.stderr)

    def test_deletion_journal_replay_is_strict_and_writes_secret_free_watermark(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-replay-test.") as raw:
            root = Path(raw)
            payload = root / "payload"
            journal = root / "journal"
            payload.mkdir(mode=0o700)
            journal.mkdir(mode=0o700)
            now = datetime.now(UTC).replace(microsecond=0)

            def timestamp(value: datetime) -> str:
                return value.isoformat().replace("+00:00", "Z")

            backup_manifest = {
                "schema_version": "mylifegraph-supabase-backup-v2",
                "project_ref": "abcdefghijklmnopqrst",
                "started_at_utc": timestamp(now - timedelta(hours=3)),
                "completed_at_utc": timestamp(now - timedelta(hours=2)),
                "migration_head": (
                    "20260820150000_pilot_participation_rls_gate_v1.sql"
                ),
            }
            (payload / "backup-manifest.json").write_text(
                json.dumps(backup_manifest)
            )
            entry = {
                "accepted_at": timestamp(now - timedelta(hours=1)),
                "contract_version": "account-deletion-journal-v2",
                "deletion_id": "ef100000-0000-4000-8000-000000000001",
                "user_id": "ef000000-0000-4000-8000-000000000001",
            }
            canonical = json.dumps(
                entry,
                ensure_ascii=True,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("ascii") + b"\n"
            entries = journal / "entries.jsonl"
            entries.write_bytes(canonical)
            export_manifest = {
                "schema_version": "mylifegraph-deletion-journal-export-v1",
                "contract_version": "account-deletion-journal-v2",
                "captured_from_utc": timestamp(now - timedelta(hours=4)),
                "captured_through_utc": timestamp(now),
                "entry_count": 1,
                "entries_file": "entries.jsonl",
                "entries_sha256": hashlib.sha256(canonical).hexdigest(),
                "list_pass_count": 2,
                "source_bucket_url": (
                    "https://journal-bucket.s3.eu-central-1.amazonaws.com"
                ),
                "source_inventory_sha256": "c" * 64,
                "source_kms_key_arn": (
                    "arn:aws:kms:eu-central-1:123456789012:key/"
                    "12345678-1234-1234-1234-123456789abc"
                ),
                "source_object_count": 1,
                "source_objects_through_cutoff": 1,
            }
            export_path = journal / "journal-export.json"
            export_path.write_text(json.dumps(export_manifest))
            os.chmod(entries, 0o600)
            os.chmod(export_path, 0o600)

            sql = root / "replay.sql"
            rendered = _run(
                sys.executable,
                str(BIN_ROOT / "replay_deletion_journal.py"),
                "render-sql",
                "--payload",
                str(payload),
                "--journal-export",
                str(journal),
                "--required-through-utc",
                timestamp(now),
                "--output",
                str(sql),
            )
            self.assertEqual(rendered.returncode, 0, rendered.stderr)
            source = sql.read_text()
            self.assertIn("set local role mylifegraph_deletion_replayer", source)
            self.assertIn("replay_account_deletion_v2", source)
            self.assertIn("pg_catalog.pg_attribute", source)
            self.assertEqual(sql.stat().st_mode & 0o777, 0o600)

            report = root / "report.json"
            report.write_text(
                json.dumps(
                    {
                        "schema_version": (
                            "mylifegraph-deletion-replay-report-v1"
                        ),
                        "requested_count": 1,
                        "completed_receipt_count": 1,
                        "receipt_mismatch_count": 0,
                        "auth_user_remaining": 0,
                        "auth_identity_remaining": 0,
                        "profile_remaining": 0,
                        "owner_relation_count": 50,
                        "owner_rows_remaining": 0,
                        "storage_objects_remaining": 0,
                    }
                )
            )
            watermark = root / "watermark.json"
            accepted = _run(
                sys.executable,
                str(BIN_ROOT / "replay_deletion_journal.py"),
                "validate",
                "--payload",
                str(payload),
                "--journal-export",
                str(journal),
                "--required-through-utc",
                timestamp(now),
                "--report",
                str(report),
                "--output",
                str(watermark),
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            serialized = watermark.read_text()
            self.assertNotIn(entry["user_id"], serialized)
            self.assertNotIn(entry["deletion_id"], serialized)
            value = json.loads(serialized)
            self.assertEqual(value["postconditions"], "passed")
            self.assertEqual(value["replayed_entry_count"], 1)

            report_value = json.loads(report.read_text())
            report_value["auth_user_remaining"] = 1
            report.write_text(json.dumps(report_value))
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "replay_deletion_journal.py"),
                "validate",
                "--payload",
                str(payload),
                "--journal-export",
                str(journal),
                "--required-through-utc",
                timestamp(now),
                "--report",
                str(report),
                "--output",
                str(watermark),
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("auth_user_remaining", rejected.stderr)

            os.chmod(entries, 0o644)
            exposed = _run(
                sys.executable,
                str(BIN_ROOT / "replay_deletion_journal.py"),
                "render-sql",
                "--payload",
                str(payload),
                "--journal-export",
                str(journal),
                "--required-through-utc",
                timestamp(now),
                "--output",
                str(sql),
            )
            self.assertNotEqual(exposed.returncode, 0)
            self.assertIn("owner-only", exposed.stderr)

    def test_deletion_journal_export_requires_two_stable_complete_listings(
        self,
    ) -> None:
        module_path = BIN_ROOT / "export_deletion_journal.py"
        spec = importlib.util.spec_from_file_location(
            "mylifegraph_export_deletion_journal",
            module_path,
        )
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader if spec else None)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)

        now = datetime.now(UTC).replace(microsecond=0)
        # The intent predates the backup, but its durable object/delete happens
        # afterwards. Selection is therefore based on S3 LastModified, not the
        # earlier prepare timestamp.
        accepted = now - timedelta(hours=4)
        entry = {
            "accepted_at": accepted.isoformat().replace("+00:00", "Z"),
            "contract_version": "account-deletion-journal-v2",
            "deletion_id": "ef100000-0000-4000-8000-000000000001",
            "user_id": "ef000000-0000-4000-8000-000000000001",
        }
        body = json.dumps(
            entry,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("ascii")
        digest = hashlib.sha256(body).hexdigest()
        key = (
            f"deletions/v2/{accepted:%Y/%m}/{entry['deletion_id']}/"
            f"{digest}.json"
        )
        old_accepted = now - timedelta(hours=5)
        old_entry = {
            "accepted_at": old_accepted.isoformat().replace("+00:00", "Z"),
            "contract_version": "account-deletion-journal-v2",
            "deletion_id": "ef000000-0000-4000-8000-000000000001",
            "user_id": "ef900000-0000-4000-8000-000000000001",
        }
        old_body = json.dumps(
            old_entry,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("ascii")
        old_digest = hashlib.sha256(old_body).hexdigest()
        old_key = (
            f"deletions/v2/{old_accepted:%Y/%m}/{old_entry['deletion_id']}/"
            f"{old_digest}.json"
        )
        listing = (
            {
                "key": old_key,
                "etag": '"old-etag"',
                "version_id": "old-object-version",
                "size": len(old_body),
                "last_modified": (now - timedelta(hours=4))
                .isoformat()
                .replace("+00:00", "Z"),
            },
            {
                "key": key,
                "etag": '"opaque-etag"',
                "version_id": "object-version-1",
                "size": len(body),
                "last_modified": (now - timedelta(hours=1))
                .isoformat()
                .replace("+00:00", "Z"),
            },
        )

        class Reader:
            bucket_url = (
                "https://journal-bucket.s3.eu-central-1.amazonaws.com"
            )
            kms_key_arn = (
                "arn:aws:kms:eu-central-1:123456789012:key/"
                "12345678-1234-1234-1234-123456789abc"
            )

            def __init__(self, *, unstable: bool = False) -> None:
                self.calls = 0
                self.unstable = unstable
                self.fetched: list[str] = []

            def list_objects(self):
                self.calls += 1
                if self.unstable and self.calls == 2:
                    return ()
                return listing

            def get_object(self, object_key, version_id, *, recovery_cutoff):
                self.fetched.append(object_key)
                self.assert_key = object_key
                self.assert_version = version_id
                return {old_key: old_body, key: body}[object_key]

        with tempfile.TemporaryDirectory(
            prefix="mylifegraph-journal-export-test."
        ) as raw:
            snapshot_dump = Path(raw) / "data.sql"
            snapshot_dump.write_text(
                "COPY public.account_deletion_intents (deletion_id, state) FROM stdin;\n"
                f"{old_entry['deletion_id']}\tappending\n"
                "\\.\n"
            )
            self.assertEqual(
                module._snapshot_pending_deletions(snapshot_dump),
                {old_entry["deletion_id"]: "appending"},
            )
            output = Path(raw) / "export"
            reader = Reader()
            module.export_journal(
                reader,
                required_from=now - timedelta(hours=3),
                recovery_cutoff=now,
                snapshot_pending={},
                output=output,
            )
            manifest = json.loads((output / "journal-export.json").read_text())
            self.assertEqual(manifest["list_pass_count"], 2)
            self.assertEqual(manifest["source_object_count"], 2)
            self.assertEqual(manifest["source_objects_through_cutoff"], 1)
            self.assertEqual(manifest["entry_count"], 1)
            self.assertEqual(reader.assert_key, key)
            self.assertEqual(reader.assert_version, "object-version-1")
            self.assertEqual(reader.fetched, [key])
            self.assertEqual(output.stat().st_mode & 0o777, 0o700)
            self.assertEqual(
                (output / "entries.jsonl").stat().st_mode & 0o777,
                0o600,
            )

            pending_output = Path(raw) / "pending-export"
            pending_reader = Reader()
            module.export_journal(
                pending_reader,
                required_from=now - timedelta(hours=3),
                recovery_cutoff=now,
                snapshot_pending={old_entry["deletion_id"]: "appending"},
                output=pending_output,
            )
            pending_manifest = json.loads(
                (pending_output / "journal-export.json").read_text()
            )
            self.assertEqual(pending_manifest["entry_count"], 2)
            self.assertEqual(pending_reader.fetched, [old_key, key])

            with self.assertRaisesRegex(
                module.JournalExportError,
                "accepted deletion lacks",
            ):
                module.export_journal(
                    Reader(),
                    required_from=now - timedelta(hours=3),
                    recovery_cutoff=now,
                    snapshot_pending={
                        "ef200000-0000-4000-8000-000000000001": "accepted"
                    },
                    output=Path(raw) / "missing-accepted",
                )

            with self.assertRaisesRegex(
                module.JournalExportError,
                "changed during complete listing",
            ):
                module.export_journal(
                    Reader(unstable=True),
                    required_from=now - timedelta(hours=3),
                    recovery_cutoff=now,
                    snapshot_pending={},
                    output=Path(raw) / "unstable",
                )

        class Response:
            def __init__(self, request, body, headers=None):
                self.status = 200
                self._url = request.full_url
                self._body = body
                self.headers = headers or {}

            def geturl(self):
                return self._url

            def read(self, _limit):
                return self._body

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

        class Opener:
            def __init__(self, body, headers=None):
                self.body = body
                self.headers = headers

            def open(self, request, timeout):
                self.timeout = timeout
                return Response(request, self.body, self.headers)

        delete_marker_xml = b'''<?xml version="1.0" encoding="UTF-8"?>
<ListVersionsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <IsTruncated>false</IsTruncated>
  <DeleteMarker><Key>deletions/v2/2026/08/x</Key></DeleteMarker>
</ListVersionsResult>'''
        reader = module.S3JournalReader(
            bucket_url="https://journal-bucket.s3.eu-central-1.amazonaws.com",
            region="eu-central-1",
            access_key_id="ABCDEFGHIJKLMNOP",
            secret_access_key="s" * 40,
            kms_key_arn=(
                "arn:aws:kms:eu-central-1:123456789012:key/"
                "12345678-1234-1234-1234-123456789abc"
            ),
            opener=Opener(delete_marker_xml),
            now=lambda: now,
        )
        with self.assertRaisesRegex(
            module.JournalExportError,
            "delete marker",
        ):
            reader.list_objects()

        reader = module.S3JournalReader(
            bucket_url="https://journal-bucket.s3.eu-central-1.amazonaws.com",
            region="eu-central-1",
            access_key_id="ABCDEFGHIJKLMNOP",
            secret_access_key="s" * 40,
            kms_key_arn=(
                "arn:aws:kms:eu-central-1:123456789012:key/"
                "12345678-1234-1234-1234-123456789abc"
            ),
            opener=Opener(body, {"x-amz-version-id": "wrong-version"}),
            now=lambda: now,
        )
        with self.assertRaisesRegex(
            module.JournalExportError,
            "retention attestation",
        ):
            reader.get_object(
                key,
                "object-version-1",
                recovery_cutoff=now,
            )


if __name__ == "__main__":
    unittest.main()
