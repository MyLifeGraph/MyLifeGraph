from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


VPS_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = VPS_ROOT.parents[1]
BIN_ROOT = VPS_ROOT / "bin"


def _run(
    *args: str, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _seal_test_release(path: Path) -> None:
    result = _run(
        sys.executable,
        str(BIN_ROOT / "release_tree.py"),
        "seal",
        "--release",
        str(path),
        "--test-mode",
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr)


def _manifest(tag: str, sha: str) -> dict[str, object]:
    return {
        "schema_version": "mylifegraph-source-release-v1",
        "release_tag": tag,
        "release_sha": sha,
        "created_at_utc": "2026-08-19T00:00:00Z",
        "source_archive": {
            "name": f"mylifegraph-{tag}.tar.gz",
            "sha256": "0" * 64,
        },
        "requirements_sha256": "0" * 64,
        "contracts_sha256": "0" * 64,
        "migration_head": "20260820170000_account_deletion_recovery_v2.sql",
        "migration_inventory": {
            "count": 1,
            "identity_sha256": "0" * 64,
            "sha256": "0" * 64,
        },
    }


def _write_analysis_fixture(root: Path, revision: str = "c" * 64) -> None:
    app = root / "services/ai_service/app"
    context = root / "services/ai_service/coach_analysis"
    app.mkdir(parents=True, exist_ok=True)
    context.mkdir(parents=True, exist_ok=True)
    (app / "analysis_image.py").write_text(f"print({revision!r})\n")
    for name in ["Dockerfile", "requirements.txt", "runner.py"]:
        (context / name).write_text(f"# {name}\n")


class VpsArtifactTests(unittest.TestCase):
    def test_shell_and_python_sources_parse(self) -> None:
        for path in sorted(BIN_ROOT.glob("*.sh")):
            result = _run("bash", "-n", str(path))
            self.assertEqual(result.returncode, 0, f"{path}: {result.stderr}")

    def test_health_check_binds_readiness_to_the_manifest_migration_head(
        self,
    ) -> None:
        health_path = BIN_ROOT / "health_check.py"
        spec = importlib.util.spec_from_file_location(
            "mylifegraph_health_check",
            health_path,
        )
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        expected_sha = "a" * 40
        expected_tag = "v0.1.0-pilot.1-rc.1"
        expected_head = "20260820190000_hosted_database_contract_v1.sql"
        expected_count = 68
        expected_identity = "5" * 64
        original_argv = sys.argv
        original_get_json = module._get_json
        try:
            sys.argv = [
                str(health_path),
                "--base-url",
                "https://coach.example.test",
                "--expected-sha",
                expected_sha,
                "--expected-tag",
                expected_tag,
                "--expected-migration-head",
                expected_head,
                "--expected-migration-count",
                str(expected_count),
                "--expected-migration-identity-sha256",
                expected_identity,
            ]

            def exact_response(url: str, _timeout: float) -> dict[str, object]:
                if url.endswith("/v1/health"):
                    return {
                        "status": "ok",
                        "release_sha": expected_sha,
                        "release_tag": expected_tag,
                    }
                if "/v1/internal/database-contract?" in url:
                    return {
                        "contract_version": "hosted-database-contract-v1",
                        "migration_head": expected_head,
                        "migration_count": expected_count,
                        "migration_identity_sha256": expected_identity,
                        "prefix_head": expected_head,
                        "prefix_count": expected_count,
                        "prefix_identity_sha256": expected_identity,
                        "prepared_deletion_pending_guard": True,
                    }
                return {
                    "status": "ready",
                    "migration_head": expected_head,
                    "migration_count": expected_count,
                    "migration_identity_sha256": expected_identity,
                }

            module._get_json = exact_response
            self.assertEqual(module.main(), 0)

            sys.argv = [
                str(health_path),
                "--base-url",
                "https://coach.example.test",
                "--database-contract-only",
                "--expected-migration-head",
                expected_head,
                "--expected-migration-count",
                str(expected_count),
                "--expected-migration-identity-sha256",
                expected_identity,
            ]
            with io.StringIO() as standard_output:
                original_stdout = sys.stdout
                try:
                    sys.stdout = standard_output
                    self.assertEqual(module.main(), 0)
                finally:
                    sys.stdout = original_stdout
                self.assertEqual(
                    standard_output.getvalue().strip(),
                    f"{expected_head}\t{expected_count}\t{expected_identity}",
                )

            sys.argv = [
                str(health_path),
                "--base-url",
                "https://coach.example.test",
                "--expected-sha",
                expected_sha,
                "--expected-tag",
                expected_tag,
                "--expected-migration-head",
                expected_head,
                "--expected-migration-count",
                str(expected_count),
                "--expected-migration-identity-sha256",
                expected_identity,
            ]
            module._get_json = lambda url, timeout: (
                exact_response(url, timeout)
                if url.endswith("/v1/health")
                else {
                    "status": "ready",
                    "migration_head": expected_head,
                    "migration_count": expected_count - 1,
                    "migration_identity_sha256": "4" * 64,
                }
            )
            with io.StringIO() as error_output:
                original_stderr = sys.stderr
                try:
                    sys.stderr = error_output
                    self.assertEqual(module.main(), 1)
                finally:
                    sys.stderr = original_stderr
                self.assertIn(
                    "readiness response does not match",
                    error_output.getvalue(),
                )
        finally:
            sys.argv = original_argv
            module._get_json = original_get_json
        for path in sorted(BIN_ROOT.glob("*.py")):
            result = _run(sys.executable, "-m", "py_compile", str(path))
            self.assertEqual(result.returncode, 0, f"{path}: {result.stderr}")

    def test_executor_environment_is_secret_free_and_uid_bound(self) -> None:
        executor = (VPS_ROOT / "env/executor.env.example").read_text()
        for forbidden in [
            "SUPABASE_URL",
            "SUPABASE_SECRET_KEY",
            "SUPABASE_SERVICE_ROLE_KEY",
            "SCHEDULED_REFRESH_TOKEN",
            "OPENAI_API_KEY",
            "GEMINI_API_KEY",
        ]:
            self.assertNotIn(forbidden, executor)
        self.assertIn("LOCAL_CODEX_EXPECTED_VERSION=0.148.0", executor)
        self.assertIn("unix:///run/user/<coach-executor-uid>/docker.sock", executor)
        self.assertNotIn("\nCOACH_ANALYSIS_IMAGE=", executor)

    def test_systemd_and_caddy_preserve_security_boundaries(self) -> None:
        api = (VPS_ROOT / "systemd/mylifegraph-api.service").read_text()
        executor = (VPS_ROOT / "systemd/mylifegraph-coach-executor.service").read_text()
        socket = (VPS_ROOT / "systemd/mylifegraph-coach-executor.socket").read_text()
        caddy = (VPS_ROOT / "caddy/Caddyfile").read_text()
        self.assertIn("User=mylifegraph-api", api)
        self.assertIn("EnvironmentFile=/etc/mylifegraph/api.env", api)
        self.assertIn(
            "EnvironmentFile=-/srv/mylifegraph/current/.mylifegraph-release.env",
            api,
        )
        self.assertLess(
            api.index("EnvironmentFile=/etc/mylifegraph/api.env"),
            api.index(
                "EnvironmentFile=-/srv/mylifegraph/current/.mylifegraph-release.env"
            ),
        )
        self.assertIn("--host 127.0.0.1 --port 8000 --workers 1", api)
        self.assertIn("--no-access-log", api)
        self.assertIn("User=coach-executor", executor)
        self.assertIn("/v1/internal/*", caddy)
        self.assertIn(
            "EnvironmentFile=-/srv/mylifegraph/current/"
            ".mylifegraph-executor-release.env",
            executor,
        )
        self.assertLess(
            executor.index("EnvironmentFile=/etc/mylifegraph/executor.env"),
            executor.index(".mylifegraph-executor-release.env"),
        )
        self.assertIn("ProtectHome=read-only", executor)
        self.assertIn("InaccessiblePaths=/home /root", executor)
        self.assertNotIn("ProtectHome=true", executor)
        self.assertIn("PrivateTmp=true", executor)
        self.assertIn("RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6", executor)
        preflight = (BIN_ROOT / "preflight_host.sh").read_text()
        permissions = (BIN_ROOT / "verify_permissions.sh").read_text()
        tmpfiles = (VPS_ROOT / "tmpfiles.d/mylifegraph.conf").read_text()
        sudoers = (VPS_ROOT / "sudoers.d/mylifegraph-deploy").read_text()
        self.assertIn("/usr/local/libexec/mylifegraph-disk-monitor", preflight)
        self.assertIn("/usr/local/libexec/mylifegraph", preflight)
        self.assertIn("exact APP_ENV=pilot", preflight)
        self.assertIn("mylifegraph-disk-monitor.timer", preflight)
        self.assertIn("COACH_EXECUTOR_ALLOWED_API_UID", permissions)
        self.assertIn(
            "700:coach-executor:coach-executor",
            permissions,
        )
        self.assertIn(
            "750:mylifegraph-api:mylifegraph-api",
            permissions,
        )
        self.assertIn(
            "test ! -x /var/lib/mylifegraph-coach/codex-home",
            permissions,
        )
        self.assertIn(
            "test ! -x /var/lib/mylifegraph-api",
            permissions,
        )
        self.assertNotIn(
            "test ! -r /var/lib/mylifegraph-coach/codex-home",
            permissions,
        )
        self.assertIn(
            "mutable executor.env must not select an analysis image",
            permissions,
        )
        self.assertIn("release-owned executor image identity is invalid", permissions)
        self.assertIn(
            "d /srv/mylifegraph 0750 root mylifegraph-release -", tmpfiles
        )
        self.assertIn(
            "d /srv/mylifegraph/releases 0750 root mylifegraph-release -",
            tmpfiles,
        )
        self.assertIn(
            "d /srv/mylifegraph/incoming 0700 root root -",
            tmpfiles,
        )
        self.assertIn(
            "/usr/local/libexec/mylifegraph/promote_release.sh *", sudoers
        )
        self.assertIn("NOPASSWD:NOSETENV", sudoers)
        self.assertNotIn("/usr/bin/systemctl", sudoers)
        self.assertNotEqual(
            api.split("User=", 1)[1].splitlines()[0],
            executor.split("User=", 1)[1].splitlines()[0],
        )
        self.assertIn("SocketMode=0660", socket)
        self.assertIn("SocketGroup=mylifegraph-api", socket)
        self.assertIn("reverse_proxy 127.0.0.1:8000", caddy)
        self.assertIn("max_size 1MB", caddy)
        self.assertNotIn("max_size 12MB", caddy)
        self.assertIn("response_header_timeout 250s", caddy)
        self.assertNotIn("flush_interval -1", caddy)
        self.assertNotIn("response_buffers", caddy)
        self.assertNotIn("Strict-Transport-Security", caddy)
        for header in [
            "Authorization",
            "Cookie",
            "X-Scheduled-Refresh-Token",
            "X-MyLifeGraph-Coach-Api-Key",
        ]:
            self.assertIn(f"request>headers>{header} delete", caddy)

    def test_public_promotion_origin_is_one_canonical_https_hostname(self) -> None:
        validator = BIN_ROOT / "validate_public_origin.py"
        accepted = _run(
            sys.executable,
            str(validator),
            "--origin",
            "https://api.example.invalid",
        )
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertEqual(accepted.stdout, "https://api.example.invalid\n")
        for rejected_origin in [
            "http://api.example.invalid",
            "https://API.example.invalid",
            "https://api.example.invalid:443",
            "https://api.example.invalid/path",
            "https://user@api.example.invalid",
            "https://127.0.0.1",
            "https://localhost",
            "https://api_example.invalid",
            " https://api.example.invalid",
        ]:
            with self.subTest(origin=rejected_origin):
                rejected = _run(
                    sys.executable,
                    str(validator),
                    "--origin",
                    rejected_origin,
                )
                self.assertNotEqual(rejected.returncode, 0)

    def test_codex_manifest_pins_the_reviewed_official_archive(self) -> None:
        manifest = json.loads((VPS_ROOT / "manifests/codex-cli.json").read_text())
        self.assertEqual(manifest["version"], "0.148.0")
        self.assertEqual(
            manifest["asset_sha256"],
            "8c790500af2ba6e74ce4948fe26c651ac1f77f6dbb005b47c8d26ff711146262",
        )
        self.assertTrue(
            manifest["source_url"].startswith(
                "https://github.com/openai/codex/releases/download/rust-v0.148.0/"
            )
        )

    def test_codex_installer_has_a_root_private_non_overridable_boundary(self) -> None:
        installer_path = BIN_ROOT / "install_codex_cli.py"
        source = installer_path.read_text()
        self.assertTrue(source.startswith("#!/usr/bin/python3 -I\n"))
        self.assertIn("sys.flags.isolated", source)
        self.assertIn("/usr/local/libexec/mylifegraph/install_codex_cli.py", source)
        self.assertIn("/srv/mylifegraph/incoming", source)
        self.assertNotIn('add_argument("--manifest"', source)
        self.assertIn("os.O_NOFOLLOW", source)
        self.assertIn("info.st_nlink != 1", source)
        self.assertIn("os.setgroups([])", source)
        self.assertIn("os.setuid(account.pw_uid)", source)
        self.assertIn("stat.S_IMODE(info.st_mode) != 0o555", source)

        spec = importlib.util.spec_from_file_location(
            "mylifegraph_install_codex_cli", installer_path
        )
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix="mylifegraph-codex-test.") as raw:
            parent = Path(raw) / "incoming"
            parent.mkdir(mode=0o700)
            protected = parent / "archive.tar.gz"
            protected.write_bytes(b"archive")
            protected.chmod(0o400)
            with module._open_protected_file(
                protected,
                expected_parent=parent,
                chain_stop=parent,
                expected_uid=os.getuid(),
                expected_mode=0o400,
                max_bytes=1024,
            ) as handle:
                self.assertEqual(handle.read(), b"archive")

            symlink = parent / "symlink.tar.gz"
            symlink.symlink_to(protected)
            with self.assertRaises((OSError, module.CodexInstallError)):
                with module._open_protected_file(
                    symlink,
                    expected_parent=parent,
                    chain_stop=parent,
                    expected_uid=os.getuid(),
                    expected_mode=0o400,
                    max_bytes=1024,
                ):
                    pass

            hardlink = parent / "hardlink.tar.gz"
            os.link(protected, hardlink)
            with self.assertRaises(module.CodexInstallError):
                with module._open_protected_file(
                    protected,
                    expected_parent=parent,
                    chain_stop=parent,
                    expected_uid=os.getuid(),
                    expected_mode=0o400,
                    max_bytes=1024,
                ):
                    pass

    def test_analysis_image_inputs_are_immutable_and_hash_locked(self) -> None:
        context = REPO_ROOT / "services/ai_service/coach_analysis"
        dockerfile = (context / "Dockerfile").read_text()
        requirements = (context / "requirements.txt").read_text()
        prepare = (REPO_ROOT / "scripts/prepare_coach_analysis_image.sh").read_text()
        attestation = json.loads(
            (VPS_ROOT / "manifests/artifact-attestation.example.json").read_text()
        )
        self.assertIn(
            "python:3.12.10-slim-bookworm@sha256:"
            "fd95fa221297a88e1cf49c55ec1828edd7c5a428187e67b5d1805692d11588db",
            dockerfile,
        )
        self.assertIn("--only-binary=:all: --require-hashes", dockerfile)
        self.assertIn("--hash=sha256:", requirements)
        self.assertIn("app/analysis_image.py", prepare)
        self.assertIn("mylifegraph-coach-analysis:sha256-$expected_revision", prepare)
        self.assertIn("analysis_image_name", attestation["vps"])
        self.assertIn("analysis_image_revision", attestation["vps"])

    def test_manifest_verification_rejects_archive_tampering_and_links(self) -> None:
        bundle = (BIN_ROOT / "build_source_bundle.sh").read_text()
        self.assertIn("refs/remotes/origin/main", bundle)
        self.assertNotIn('"$release_sha" main', bundle)
        tag = "v0.1.0-pilot.1-rc.1"
        with tempfile.TemporaryDirectory(prefix="mylifegraph-vps-test.") as raw:
            root = Path(raw)
            repo = root / "repo"
            (repo / "services/ai_service/app").mkdir(parents=True)
            (repo / "docs").mkdir()
            (repo / "supabase/migrations").mkdir(parents=True)
            (repo / "services/ai_service/app/main.py").write_text("app = None\n")
            (repo / "services/ai_service/requirements.txt").write_text("")
            (repo / "docs/current-contracts.json").write_text("{}\n")
            _write_analysis_fixture(repo)
            (
                repo / "supabase/migrations/20260819203000_coach_operator_pilot_v1.sql"
            ).write_text("select 1;\n")
            archive = root / f"mylifegraph-{tag}.tar.gz"
            with tarfile.open(
                archive,
                "w:gz",
                format=tarfile.PAX_FORMAT,
                pax_headers={"comment": "a" * 40},
            ) as output:
                for relative in [
                    "services/ai_service/app/analysis_image.py",
                    "services/ai_service/app/main.py",
                    "services/ai_service/coach_analysis/Dockerfile",
                    "services/ai_service/coach_analysis/requirements.txt",
                    "services/ai_service/coach_analysis/runner.py",
                    "services/ai_service/requirements.txt",
                    "docs/current-contracts.json",
                    "supabase/migrations/20260819203000_coach_operator_pilot_v1.sql",
                ]:
                    output.add(repo / relative, arcname=f"mylifegraph-{tag}/{relative}")
            manifest = root / "source.json"
            create = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "create",
                "--repo-root",
                str(repo),
                "--archive",
                str(archive),
                "--tag",
                tag,
                "--sha",
                "a" * 40,
                "--created-at",
                "2026-08-19T00:00:00Z",
                "--output",
                str(manifest),
            )
            self.assertEqual(create.returncode, 0, create.stderr)
            verify = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "verify",
                "--manifest",
                str(manifest),
                "--archive",
                str(archive),
            )
            self.assertEqual(verify.returncode, 0, verify.stderr)
            original_manifest = json.loads(manifest.read_text())
            relabeled = dict(original_manifest)
            relabeled["release_sha"] = "b" * 40
            manifest.write_text(json.dumps(relabeled))
            rejected_identity = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "verify",
                "--manifest",
                str(manifest),
                "--archive",
                str(archive),
            )
            self.assertNotEqual(rejected_identity.returncode, 0)
            self.assertIn("Git identity", rejected_identity.stderr)

            wrong_migration = dict(original_manifest)
            wrong_migration["migration_head"] = (
                "20260820170000_account_deletion_recovery_v2.sql"
            )
            manifest.write_text(json.dumps(wrong_migration))
            rejected_migration = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "verify",
                "--manifest",
                str(manifest),
                "--archive",
                str(archive),
            )
            self.assertNotEqual(rejected_migration.returncode, 0)
            self.assertIn("migrations", rejected_migration.stderr)
            manifest.write_text(json.dumps(original_manifest))
            archive.write_bytes(archive.read_bytes() + b"tampered")
            rejected = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "verify",
                "--manifest",
                str(manifest),
                "--archive",
                str(archive),
            )
            self.assertNotEqual(rejected.returncode, 0)

            linked = root / f"mylifegraph-{tag}.tar.gz"
            with tarfile.open(
                linked,
                "w:gz",
                format=tarfile.PAX_FORMAT,
                pax_headers={"comment": "a" * 40},
            ) as output:
                info = tarfile.TarInfo(
                    f"mylifegraph-{tag}/services/ai_service/app/main.py"
                )
                info.type = tarfile.SYMTYPE
                info.linkname = "/etc/passwd"
                output.addfile(info)
            bad = _manifest(tag, "a" * 40)
            bad["source_archive"]["sha256"] = _digest(linked)  # type: ignore[index]
            bad_path = root / "bad.json"
            bad_path.write_text(json.dumps(bad))
            rejected_link = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "verify",
                "--manifest",
                str(bad_path),
                "--archive",
                str(linked),
            )
            self.assertNotEqual(rejected_link.returncode, 0)

            credential = root / f"mylifegraph-{tag}.tar.gz"
            with tarfile.open(
                credential,
                "w:gz",
                format=tarfile.PAX_FORMAT,
                pax_headers={"comment": "a" * 40},
            ) as output:
                info = tarfile.TarInfo(
                    f"mylifegraph-{tag}/services/ai_service/.env"
                )
                info.size = len(b"SECRET=value\n")
                output.addfile(info, io.BytesIO(b"SECRET=value\n"))
            bad["source_archive"]["sha256"] = _digest(credential)  # type: ignore[index]
            bad_path.write_text(json.dumps(bad))
            rejected_credential = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "verify",
                "--manifest",
                str(bad_path),
                "--archive",
                str(credential),
            )
            self.assertNotEqual(rejected_credential.returncode, 0)
            self.assertIn("credential file", rejected_credential.stderr)

    def test_prepare_release_rehearsal_is_idempotent(self) -> None:
        prepare_source = (BIN_ROOT / "prepare_release.sh").read_text()
        self.assertTrue(prepare_source.startswith("#!/bin/bash\n"))
        self.assertIn("flock -n 9", prepare_source)
        self.assertIn('! -L "$target"', prepare_source)
        self.assertIn("single-link root-owned mode 0400", prepare_source)
        self.assertIn("root-private incoming directory", prepare_source)
        self.assertIn("400:root:root:1", prepare_source)
        self.assertIn("privileged preparation must use the installed helper suite", prepare_source)
        self.assertIn('BUILD_USER=mylifegraph-build', prepare_source)
        self.assertIn('"$SETPRIV_BIN" --no-new-privs --bounding-set=-all', prepare_source)
        self.assertIn('"$SCRIPT_DIR/analysis_image_revision.py"', prepare_source)
        self.assertNotIn(
            '"$source_root/services/ai_service/app/analysis_image.py"',
            prepare_source,
        )
        self.assertIn("release_tree.py", prepare_source)
        tag = "v0.1.0-pilot.1-rc.2"
        with tempfile.TemporaryDirectory(prefix="mylifegraph-vps-test.") as raw:
            root = Path(raw)
            source = root / "source"
            app = source / "services/ai_service/app"
            app.mkdir(parents=True)
            (app / "__init__.py").write_text("")
            root_only_sentinel = root / "root-only" / "candidate-ran"
            root_only_sentinel.parent.mkdir(mode=0o500)
            (app / "main.py").write_text(
                "from pathlib import Path\n"
                "for candidate in (\n"
                f"    Path({str(root_only_sentinel)!r}),\n"
                "    Path(__file__),\n"
                "    Path(__file__).parents[3] / '.mylifegraph-release.env',\n"
                "):\n"
                "    try:\n"
                "        candidate.write_text('forged')\n"
                "    except PermissionError:\n"
                "        pass\n"
                "class A:\n    docs_url = '/docs'\n"
                "def create_app():\n    return A()\n"
            )
            original_main = (app / "main.py").read_bytes()
            _write_analysis_fixture(source)
            (source / "services/ai_service/requirements.txt").write_text("")
            (source / "docs").mkdir()
            (source / "docs/current-contracts.json").write_text("{}\n")
            (source / "supabase/migrations").mkdir(parents=True)
            (
                source
                / "supabase/migrations/20260820170000_account_deletion_recovery_v2.sql"
            ).write_text("select 1;\n")
            archive = root / f"mylifegraph-{tag}.tar.gz"
            with tarfile.open(
                archive,
                "w:gz",
                format=tarfile.PAX_FORMAT,
                pax_headers={"comment": "b" * 40},
            ) as output:
                output.add(source, arcname=f"mylifegraph-{tag}")
            manifest_path = root / "source.json"
            created = _run(
                sys.executable,
                str(BIN_ROOT / "release_manifest.py"),
                "create",
                "--repo-root",
                str(source),
                "--archive",
                str(archive),
                "--tag",
                tag,
                "--sha",
                "b" * 40,
                "--created-at",
                "2026-08-19T00:00:00Z",
                "--output",
                str(manifest_path),
            )
            self.assertEqual(created.returncode, 0, created.stderr)
            env = {
                **os.environ,
                "MYLIFEGRAPH_ROOT": str(root),
                "MYLIFEGRAPH_VPS_TEST_MODE": "1",
                "MYLIFEGRAPH_PYTHON_BIN": sys.executable,
            }
            first = _run(
                "bash",
                str(BIN_ROOT / "prepare_release.sh"),
                str(archive),
                str(manifest_path),
                env=env,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            second = _run(
                "bash",
                str(BIN_ROOT / "prepare_release.sh"),
                str(archive),
                str(manifest_path),
                env=env,
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("already prepared", second.stdout)
            self.assertFalse(
                root_only_sentinel.exists(),
                "candidate import unexpectedly had root write authority",
            )
            self.assertEqual(
                (root / "releases" / tag / "services/ai_service/app/main.py").read_bytes(),
                original_main,
                "candidate import modified its archive-derived source",
            )
            self.assertEqual(
                (root / "releases" / tag / ".mylifegraph-release.env").read_text(),
                f"APP_BUILD_SHA={'b' * 40}\n"
                f"APP_RELEASE_TAG={tag}\n"
                "APP_MIGRATION_HEAD="
                "20260820170000_account_deletion_recovery_v2.sql\n"
                "APP_MIGRATION_COUNT=1\n"
                "APP_MIGRATION_IDENTITY_SHA256="
                f"{json.loads(manifest_path.read_text())['migration_inventory']['identity_sha256']}\n",
            )
            trusted_revision = _run(
                sys.executable,
                str(BIN_ROOT / "analysis_image_revision.py"),
                str(source / "services/ai_service/coach_analysis"),
            )
            self.assertEqual(trusted_revision.returncode, 0, trusted_revision.stderr)
            self.assertEqual(
                (
                    root
                    / "releases"
                    / tag
                    / ".mylifegraph-executor-release.env"
                ).read_text(),
                "COACH_ANALYSIS_IMAGE=mylifegraph-coach-analysis:sha256-"
                f"{trusted_revision.stdout.strip()}\n",
            )

    def test_atomic_promotion_and_failed_candidate_rollback(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-vps-test.") as raw:
            root = Path(raw)
            releases = root / "releases"
            releases.mkdir()
            old_tag = "v0.1.0-pilot.1-rc.1"
            good_tag = "v0.1.0-pilot.1-rc.2"
            bad_tag = "v0.1.0-pilot.1-rc.3"
            for index, tag in enumerate([old_tag, good_tag, bad_tag], start=1):
                release = releases / tag
                release.mkdir()
                data = _manifest(tag, f"{index}" * 40)
                (release / ".mylifegraph-source-manifest.json").write_text(
                    json.dumps(data)
                )
                (release / "payload.txt").write_text(f"release {index}\n")
                _seal_test_release(release)
            (root / "current").symlink_to(releases / old_tag)
            systemctl = root / "systemctl"
            systemctl.write_text("#!/bin/sh\nexit 0\n")
            systemctl.chmod(0o755)
            health = root / "health.py"
            health.write_text(
                "import os,sys\n"
                "tag=sys.argv[sys.argv.index('--expected-tag')+1]\n"
                "current=os.path.basename(os.path.realpath(os.path.join(os.environ['MYLIFEGRAPH_ROOT'],'current')))\n"
                "raise SystemExit(0 if tag==current and not tag.endswith('rc.3') else 1)\n"
            )
            env = {
                **os.environ,
                "MYLIFEGRAPH_ROOT": str(root),
                "MYLIFEGRAPH_VPS_TEST_MODE": "1",
                "MYLIFEGRAPH_SYSTEMCTL_BIN": str(systemctl),
                "MYLIFEGRAPH_PYTHON_BIN": sys.executable,
                "MYLIFEGRAPH_HEALTH_CHECK_SCRIPT": str(health),
                "MYLIFEGRAPH_HEALTH_ATTEMPTS": "1",
                "MYLIFEGRAPH_HEALTH_DELAY_SECONDS": "0",
            }
            promoted = _run(
                "bash",
                str(BIN_ROOT / "promote_release.sh"),
                good_tag,
                "https://api.example.invalid",
                env=env,
            )
            self.assertEqual(promoted.returncode, 0, promoted.stderr)
            self.assertEqual(Path(os.path.realpath(root / "current")).name, good_tag)
            failed = _run(
                "bash",
                str(BIN_ROOT / "promote_release.sh"),
                bad_tag,
                "https://api.example.invalid",
                env=env,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(Path(os.path.realpath(root / "current")).name, good_tag)

            tampered_tag = "v0.1.0-pilot.1-rc.4"
            tampered = releases / tampered_tag
            tampered.mkdir()
            (tampered / ".mylifegraph-source-manifest.json").write_text(
                json.dumps(_manifest(tampered_tag, "4" * 40))
            )
            payload = tampered / "payload.txt"
            payload.write_text("sealed\n")
            _seal_test_release(tampered)
            payload.write_text("changed after verification\n")
            rejected = _run(
                "bash",
                str(BIN_ROOT / "promote_release.sh"),
                tampered_tag,
                "https://api.example.invalid",
                env=env,
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("sealed digest", rejected.stderr)
            self.assertEqual(Path(os.path.realpath(root / "current")).name, good_tag)

    def test_explicit_rollback_keeps_the_newer_attested_database_head(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-vps-test.") as raw:
            root = Path(raw)
            releases = root / "releases"
            releases.mkdir()
            old_tag = "v0.1.0-pilot.1-rc.1"
            current_tag = "v0.1.0-pilot.1-rc.2"
            old_head = "20260820190000_hosted_database_contract_v1.sql"
            actual_head = "20260820200000_forward_compatible_test.sql"
            for index, (tag, head) in enumerate(
                ((old_tag, old_head), (current_tag, actual_head)),
                start=1,
            ):
                release = releases / tag
                release.mkdir()
                manifest = _manifest(tag, f"{index}" * 40)
                manifest["migration_head"] = head
                (release / ".mylifegraph-source-manifest.json").write_text(
                    json.dumps(manifest)
                )
                (release / "payload.txt").write_text(f"release {index}\n")
                _seal_test_release(release)
            (root / "current").symlink_to(releases / current_tag)

            systemctl = root / "systemctl"
            systemctl.write_text("#!/bin/sh\nexit 0\n")
            systemctl.chmod(0o755)
            health = root / "health.py"
            health.write_text(
                "import os,sys\n"
                f"actual={actual_head!r}\n"
                "if '--database-contract-only' in sys.argv:\n"
                " print(actual+'\\t1\\t'+'0'*64)\n"
                " raise SystemExit(0)\n"
                "tag=sys.argv[sys.argv.index('--expected-tag')+1]\n"
                "head=sys.argv[sys.argv.index('--expected-migration-head')+1]\n"
                "count=sys.argv[sys.argv.index('--expected-migration-count')+1]\n"
                "digest=sys.argv[sys.argv.index('--expected-migration-identity-sha256')+1]\n"
                "current=os.path.basename(os.path.realpath(os.path.join(os.environ['MYLIFEGRAPH_ROOT'],'current')))\n"
                "failed=os.environ.get('MYLIFEGRAPH_TEST_FAIL_TAG')\n"
                "raise SystemExit(0 if tag==current and head==actual and count=='1' and digest=='0'*64 and tag!=failed else 1)\n"
            )
            env = {
                **os.environ,
                "MYLIFEGRAPH_ROOT": str(root),
                "MYLIFEGRAPH_VPS_TEST_MODE": "1",
                "MYLIFEGRAPH_SYSTEMCTL_BIN": str(systemctl),
                "MYLIFEGRAPH_PYTHON_BIN": sys.executable,
                "MYLIFEGRAPH_HEALTH_CHECK_SCRIPT": str(health),
                "MYLIFEGRAPH_HEALTH_ATTEMPTS": "1",
                "MYLIFEGRAPH_HEALTH_DELAY_SECONDS": "0",
            }
            rolled_back = _run(
                "bash",
                str(BIN_ROOT / "rollback_release.sh"),
                old_tag,
                "https://api.example.invalid",
                env=env,
            )
            self.assertEqual(rolled_back.returncode, 0, rolled_back.stderr)
            self.assertEqual(Path(os.path.realpath(root / "current")).name, old_tag)

            promoted = _run(
                "bash",
                str(BIN_ROOT / "promote_release.sh"),
                current_tag,
                "https://api.example.invalid",
                env=env,
            )
            self.assertEqual(promoted.returncode, 0, promoted.stderr)
            failed_rollback = _run(
                "bash",
                str(BIN_ROOT / "rollback_release.sh"),
                old_tag,
                "https://api.example.invalid",
                env={**env, "MYLIFEGRAPH_TEST_FAIL_TAG": old_tag},
            )
            self.assertNotEqual(failed_rollback.returncode, 0)
            self.assertEqual(
                Path(os.path.realpath(root / "current")).name,
                current_tag,
            )

    def test_post_switch_verifier_failure_restores_prior_release(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-vps-test.") as raw:
            root = Path(raw)
            releases = root / "releases"
            releases.mkdir()
            old_tag = "v0.1.0-pilot.1-rc.1"
            candidate_tag = "v0.1.0-pilot.1-rc.2"
            for index, tag in enumerate([old_tag, candidate_tag], start=1):
                release = releases / tag
                release.mkdir()
                (release / ".mylifegraph-source-manifest.json").write_text(
                    json.dumps(_manifest(tag, f"{index}" * 40))
                )
                (release / "payload.txt").write_text(f"release {index}\n")
                _seal_test_release(release)
            (root / "current").symlink_to(releases / old_tag)

            systemctl = root / "systemctl"
            systemctl.write_text("#!/bin/sh\nexit 0\n")
            systemctl.chmod(0o755)
            health = root / "health.py"
            health.write_text("raise SystemExit(0)\n")
            counter = root / "verify-count"
            verifier = root / "release_tree_wrapper.py"
            verifier.write_text(
                "import os,subprocess,sys\n"
                "path=os.environ['MYLIFEGRAPH_TEST_VERIFY_COUNT']\n"
                "try:\n count=int(open(path).read())\n"
                "except FileNotFoundError:\n count=0\n"
                "count += 1\n"
                "open(path,'w').write(str(count))\n"
                "if count == 4:\n raise SystemExit(1)\n"
                f"raise SystemExit(subprocess.run([{sys.executable!r}, "
                f"{str(BIN_ROOT / 'release_tree.py')!r}, *sys.argv[1:]]).returncode)\n"
            )
            result = _run(
                "bash",
                str(BIN_ROOT / "promote_release.sh"),
                candidate_tag,
                "https://api.example.invalid",
                env={
                    **os.environ,
                    "MYLIFEGRAPH_ROOT": str(root),
                    "MYLIFEGRAPH_VPS_TEST_MODE": "1",
                    "MYLIFEGRAPH_SYSTEMCTL_BIN": str(systemctl),
                    "MYLIFEGRAPH_PYTHON_BIN": sys.executable,
                    "MYLIFEGRAPH_HEALTH_CHECK_SCRIPT": str(health),
                    "MYLIFEGRAPH_RELEASE_TREE_SCRIPT": str(verifier),
                    "MYLIFEGRAPH_HEALTH_ATTEMPTS": "1",
                    "MYLIFEGRAPH_HEALTH_DELAY_SECONDS": "0",
                    "MYLIFEGRAPH_TEST_VERIFY_COUNT": str(counter),
                },
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(Path(os.path.realpath(root / "current")).name, old_tag)
            self.assertIn("Prior release was restored and verified", result.stderr)

    def test_irreversible_hosted_boundary_failure_stops_for_fix_forward(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-vps-test.") as raw:
            root = Path(raw)
            releases = root / "releases"
            releases.mkdir()
            old_tag = "v0.1.0-pilot.1-rc.1"
            candidate_tag = "v0.1.0-pilot.1-rc.2"
            old = releases / old_tag
            candidate = releases / candidate_tag
            for index, release in enumerate((old, candidate), start=1):
                release.mkdir()
                manifest = _manifest(release.name, f"{index}" * 40)
                if release == old:
                    manifest["migration_head"] = (
                        "20260820120000_coach_terminal_replay_probe_v1.sql"
                    )
                (release / ".mylifegraph-source-manifest.json").write_text(
                    json.dumps(manifest)
                )
                (release / "payload.txt").write_text(f"release {index}\n")
                _seal_test_release(release)
            (root / "current").symlink_to(old)
            systemctl = root / "systemctl"
            systemctl.write_text("#!/bin/sh\nexit 0\n")
            systemctl.chmod(0o755)
            health = root / "health.py"
            health.write_text("raise SystemExit(1)\n")
            result = _run(
                "bash",
                str(BIN_ROOT / "promote_release.sh"),
                candidate_tag,
                "https://api.example.invalid",
                env={
                    **os.environ,
                    "MYLIFEGRAPH_ROOT": str(root),
                    "MYLIFEGRAPH_VPS_TEST_MODE": "1",
                    "MYLIFEGRAPH_SYSTEMCTL_BIN": str(systemctl),
                    "MYLIFEGRAPH_PYTHON_BIN": sys.executable,
                    "MYLIFEGRAPH_HEALTH_CHECK_SCRIPT": str(health),
                    "MYLIFEGRAPH_HEALTH_ATTEMPTS": "1",
                    "MYLIFEGRAPH_HEALTH_DELAY_SECONDS": "0",
                },
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / "current").exists())
            self.assertFalse((root / "current").is_symlink())
            self.assertIn("fix-forward recovery", result.stderr)

    def test_promotion_fails_on_every_intermediate_systemd_error(self) -> None:
        tag = "v0.1.0-pilot.1-rc.9"
        for failed_call in range(1, 10):
            with self.subTest(failed_call=failed_call), tempfile.TemporaryDirectory(
                prefix="mylifegraph-vps-test."
            ) as raw:
                root = Path(raw)
                release = root / "releases" / tag
                release.mkdir(parents=True)
                (release / ".mylifegraph-source-manifest.json").write_text(
                    json.dumps(_manifest(tag, "9" * 40))
                )
                (release / "payload.txt").write_text("release\n")
                _seal_test_release(release)
                counter = root / "systemctl-count"
                systemctl = root / "systemctl"
                systemctl.write_text(
                    "#!/bin/sh\n"
                    'count="$(cat "$MYLIFEGRAPH_TEST_SYSTEMCTL_COUNT" 2>/dev/null || printf 0)"\n'
                    "count=$((count + 1))\n"
                    'printf "%s\\n" "$count" > "$MYLIFEGRAPH_TEST_SYSTEMCTL_COUNT"\n'
                    '[ "$count" -ne "$MYLIFEGRAPH_TEST_FAIL_CALL" ]\n'
                )
                systemctl.chmod(0o755)
                health = root / "health.py"
                health.write_text("raise SystemExit(0)\n")
                result = _run(
                    "bash",
                    str(BIN_ROOT / "promote_release.sh"),
                    tag,
                    "https://api.example.invalid",
                    env={
                        **os.environ,
                        "MYLIFEGRAPH_ROOT": str(root),
                        "MYLIFEGRAPH_VPS_TEST_MODE": "1",
                        "MYLIFEGRAPH_SYSTEMCTL_BIN": str(systemctl),
                        "MYLIFEGRAPH_PYTHON_BIN": sys.executable,
                        "MYLIFEGRAPH_HEALTH_CHECK_SCRIPT": str(health),
                        "MYLIFEGRAPH_HEALTH_ATTEMPTS": "1",
                        "MYLIFEGRAPH_HEALTH_DELAY_SECONDS": "0",
                        "MYLIFEGRAPH_TEST_SYSTEMCTL_COUNT": str(counter),
                        "MYLIFEGRAPH_TEST_FAIL_CALL": str(failed_call),
                    },
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / "current").exists())
                self.assertFalse((root / "current").is_symlink())


if __name__ == "__main__":
    unittest.main()
