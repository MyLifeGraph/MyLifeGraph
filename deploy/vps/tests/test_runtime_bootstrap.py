import importlib.util
import io
import json
import subprocess
import tarfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "runtime_bootstrap", ROOT / "bin/bootstrap_runtime.py"
)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeBootstrapTests(unittest.TestCase):
    def test_socket_probe_only_accepts_permission_error(self):
        for status in (0, 1, 127, 77):
            with (
                self.subTest(status=status),
                patch.object(
                    runtime.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], status),
                ),
            ):
                if status == 77:
                    runtime.assert_socket_denied(
                        "mylifegraph-agent", Path("/run/test.sock")
                    )
                else:
                    with self.assertRaises(runtime.RuntimeError_):
                        runtime.assert_socket_denied(
                            "mylifegraph-agent", Path("/run/test.sock")
                        )

    def test_wrong_aggregate_limits_fail_before_daemon_start(self):
        with (
            patch.object(
                runtime,
                "run",
                return_value="MemoryMax=infinity\nCPUQuotaPerSecUSec=infinity\nTasksMax=512\n",
            ),
            patch.object(runtime, "coach_run") as coach,
        ):
            with self.assertRaises(runtime.RuntimeError_):
                runtime.verify_rootless({"identities": {runtime.COACH: [994]}})
            coach.assert_not_called()

    def test_apt_only_accepts_new_allowlisted_packages(self):
        text = "0 upgraded, 2 newly installed\nInst uidmap (1:4.13-1 Ubuntu [amd64])\nInst libsubid4 (1:4.13-1 Ubuntu [amd64])\nConf uidmap (1:4.13-1 Ubuntu [amd64])"
        self.assertEqual(
            runtime.parse_apt_simulation(text),
            {"uidmap": "1:4.13-1", "libsubid4": "1:4.13-1"},
        )
        for bad in (
            "Remv docker.io [29.1.3]",
            "Inst docker.io (30.0 Ubuntu [amd64])",
            "Inst uidmap [1:4.12] (1:4.13 Ubuntu [amd64])",
            "Inst unexpected (1 Ubuntu [amd64])",
        ):
            with self.subTest(bad=bad), self.assertRaises(runtime.RuntimeError_):
                runtime.parse_apt_simulation(bad)

    def test_subordinate_ranges_never_overlap_existing_assignments(self):
        first, last = runtime.subordinate_range(
            "ops:100000:65536\nagent:165536:65536\n"
        )
        self.assertEqual((first, last), (231072, 296607))
        self.assertEqual(runtime.subordinate_range(""), [100000, 165535])
        for bad in (
            "mylifegraph-coach:100000:65536",
            "broken",
            "ops:1:0",
            "ops:4294967294:10",
        ):
            with self.subTest(bad=bad), self.assertRaises(runtime.RuntimeError_):
                runtime.subordinate_range(bad)

    def test_caddy_archive_does_not_extract_paths_or_accept_linked_binary(self):
        def archive(kind, duplicate=False):
            data = io.BytesIO()
            with tarfile.open(fileobj=data, mode="w:gz") as output:
                entry = tarfile.TarInfo("caddy")
                entry.type = kind
                entry.size = 3 if kind == tarfile.REGTYPE else 0
                entry.linkname = "/etc/shadow" if kind == tarfile.SYMTYPE else ""
                output.addfile(entry, io.BytesIO(b"bin") if entry.size else None)
                if duplicate:
                    output.addfile(entry, io.BytesIO(b"bin"))
                ignored = tarfile.TarInfo("../../must-not-extract")
                ignored.size = 0
                output.addfile(ignored, io.BytesIO())
            return data.getvalue()

        self.assertEqual(runtime.caddy_binary(archive(tarfile.REGTYPE)), b"bin")
        for data in (archive(tarfile.SYMTYPE), archive(tarfile.REGTYPE, True)):
            with self.assertRaises(runtime.RuntimeError_):
                runtime.caddy_binary(data)

    def test_failed_package_replan_prevents_all_installation(self):
        with (
            patch.object(
                runtime, "run", return_value="Inst unexpected (1 Ubuntu [amd64])"
            ) as run,
            patch.object(runtime, "mkdir") as mkdir,
        ):
            with self.assertRaises(runtime.RuntimeError_):
                runtime.apply({"package_additions": {"uidmap": "1"}}, {}, {})
            self.assertEqual(run.call_count, 1)
            mkdir.assert_not_called()

    def test_docker_without_enforced_limits_is_rejected(self):
        base = {
            "CgroupDriver": "systemd",
            "CgroupVersion": "2",
            "SecurityOptions": ["name=rootless"],
            "MemoryLimit": True,
            "CpuCfsQuota": True,
            "PidsLimit": True,
        }
        plan = {"identities": {runtime.COACH: [994]}}
        for changes in (
            {"CgroupDriver": "none"},
            {"CgroupVersion": "1"},
            {"SecurityOptions": []},
            {"MemoryLimit": False},
            {"CpuCfsQuota": False},
            {"PidsLimit": False},
        ):
            with (
                self.subTest(changes=changes),
                patch.object(
                    runtime,
                    "run",
                    return_value="MemoryMax=2147483648\nCPUQuotaPerSecUSec=2s\nTasksMax=512\n",
                ),
                patch.object(
                    runtime,
                    "coach_run",
                    side_effect=["", "", json.dumps({**base, **changes})],
                ),
                self.assertRaises(runtime.RuntimeError_),
            ):
                runtime.verify_rootless(plan)

    def test_command_errors_do_not_echo_sensitive_output(self):
        result = subprocess.CompletedProcess(
            ["tool"], 1, "secret stdout", "secret stderr"
        )
        with patch.object(runtime.subprocess, "run", return_value=result):
            with self.assertRaises(runtime.RuntimeError_) as caught:
                runtime.run("/usr/bin/tool")
            self.assertNotIn("secret", str(caught.exception))

    def test_services_preserve_required_boundaries(self):
        docker = (ROOT / "systemd/docker-rootless.service").read_text()
        caddy = (ROOT / "systemd/caddy.service").read_text()
        for marker in (
            "Delegate=yes",
            "--host=unix://%t/docker.sock",
            "DISABLE_HOST_LOOPBACK=true",
        ):
            self.assertIn(marker, docker)
        self.assertNotIn("tcp://", docker)
        self.assertIn("NotifyAccess=all", docker)
        self.assertIn("Requires=dbus.socket", docker)
        self.assertIn("/usr/sbin:/usr/bin:/sbin:/bin", docker)
        self.assertNotIn("MemoryMax=", docker)
        self.assertNotIn("--environ", caddy)
        self.assertIn("User=caddy", caddy)
        self.assertIn("ConditionPathExists=/etc/mylifegraph/caddy.env", caddy)
        self.assertNotIn("sudoers", runtime.SOURCE_MAP)

    def test_local_source_pins_match_artifact_names(self):
        sources = json.loads((ROOT / "manifests/runtime-sources.json").read_text())
        self.assertIn("/v" + sources["caddy_version"] + "/", sources["caddy_url"])
        self.assertRegex(
            sources["rootless_url"],
            r"/moby/moby/[a-f0-9]{40}/contrib/dockerd-rootless.sh$",
        )
        for field in ("caddy_sha256", "rootless_sha256"):
            self.assertRegex(sources[field], r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main()
