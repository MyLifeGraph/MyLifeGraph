"""Disposable-container filesystem/Caddy rehearsal, NOT real rootless acceptance."""

import contextlib
import importlib.util
import io
import json
import os
import pwd
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch


def main():
    if (
        not Path("/.dockerenv").exists()
        or os.geteuid() != 0
        or not Path("/bundle/manifest.json").is_file()
    ):
        raise SystemExit("Run only in the documented disposable runtime container.")
    Path("/root/mylifegraph-runtime").mkdir(mode=0o700)
    for source in Path("/bundle").iterdir():
        if source.is_file():
            shutil.copyfile(source, Path("/root/mylifegraph-runtime") / source.name)
    spec = importlib.util.spec_from_file_location(
        "runtime", "/root/mylifegraph-runtime/bootstrap_runtime.py"
    )
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    for name in ("mylifegraph-work", "mylifegraph-release"):
        subprocess.run(["groupadd", "--system", name], check=True)
    names = (
        "mylifegraph-gregor",
        "mylifegraph-matthias",
        "mylifegraph-agent",
        "mylifegraph-deploy",
        "mylifegraph-api",
        "mylifegraph-coach",
        "mylifegraph-build",
    )
    users = {}
    for name in names:
        home = "/home/" + name if name in names[:3] else "/var/lib/" + name
        if name == "mylifegraph-build":
            home = "/nonexistent"
        subprocess.run(
            [
                "useradd",
                "--system",
                "--user-group",
                "--no-create-home",
                "--home-dir",
                home,
                "--shell",
                "/usr/sbin/nologin",
                name,
            ],
            check=True,
        )
        entry = pwd.getpwnam(name)
        if home != "/nonexistent":
            Path(home).mkdir(mode=0o700)
            os.chown(home, entry.pw_uid, entry.pw_gid)
        users[name] = {
            "uid": entry.pw_uid,
            "gid": entry.pw_gid,
            "home": home,
            "shell": entry.pw_shell,
            "groups": [],
        }
    Path("/etc/mylifegraph").mkdir(mode=0o751)
    Path("/etc/mylifegraph/access-bootstrap.json").write_text(
        json.dumps({"identities": {"users": users}})
    )
    Path("/etc/machine-id").write_text("b" * 32 + "\n")
    real_run = runtime.run
    service_path = (
        Path("/root/mylifegraph-runtime/docker-rootless.service")
        .read_text()
        .split("Environment=PATH=", 1)[1]
        .splitlines()[0]
    )
    subprocess.run(
        [
            "/bin/sh",
            "-c",
            "command -v sysctl && command -v newuidmap && command -v rootlesskit",
        ],
        env={"PATH": service_path},
        check=True,
        stdout=subprocess.DEVNULL,
    )
    real_read = Path.read_text
    commands = []
    sockets = []
    uid = pwd.getpwnam(runtime.COACH).pw_uid

    def read(path, *args, **kwargs):
        if str(path) == "/proc/sys/kernel/apparmor_restrict_unprivileged_userns":
            return "1\n"
        return real_read(path, *args, **kwargs)

    def run(*args, env=None):
        commands.append(args)
        if args[0] == "/usr/bin/dockerd":
            return "Docker version 29.1.3, build rehearsal\n"
        if args[0] == "/usr/bin/apt-get":
            assert "--simulate" in args, "Rehearsal must not modify packages at runtime"
            return "0 upgraded, 0 newly installed, 0 to remove\n"
        if args[0] == "/usr/bin/systemctl":
            if args[1] == "show":
                if args[2] == f"user@{uid}.service":
                    return "MemoryMax=2147483648\nCPUQuotaPerSecUSec=2s\nTasksMax=512\n"
                return "MainPID=123\nActiveState=active\n"
            assert args[1:] in (("daemon-reload",), ("start", f"user@{uid}.service"))
            return ""
        if args[0] in ("/usr/bin/loginctl", "/usr/sbin/apparmor_parser"):
            return ""
        if args[0] == "/usr/sbin/runuser" and "/usr/bin/systemctl" in args:
            if "enable" in args:
                directory = Path(f"/run/user/{uid}")
                directory.mkdir(mode=0o700, parents=True)
                os.chown(directory, uid, pwd.getpwnam(runtime.COACH).pw_gid)
                sock = socket.socket(socket.AF_UNIX)
                sock.bind(str(directory / "docker.sock"))
                sock.listen()
                os.chown(
                    directory / "docker.sock", uid, pwd.getpwnam(runtime.COACH).pw_gid
                )
                sockets.append(sock)
            return ""
        if args[0] == "/usr/sbin/runuser" and "/usr/bin/docker" in args:
            return json.dumps(
                {
                    "CgroupDriver": "systemd",
                    "CgroupVersion": "2",
                    "SecurityOptions": ["name=rootless"],
                    "MemoryLimit": True,
                    "CpuCfsQuota": True,
                    "PidsLimit": True,
                }
            )
        return real_run(*args, env=env)

    try:
        with (
            patch.object(runtime, "run", side_effect=run),
            patch.object(Path, "read_text", read),
        ):
            with (
                patch.object(sys, "argv", ["bootstrap_runtime.py"]),
                contextlib.redirect_stdout(io.StringIO()) as capture,
            ):
                runtime.main()
            token = capture.getvalue().split("Confirmation SHA256: ")[1].splitlines()[0]
            assert not Path("/usr/local/bin/caddy").exists()
            with (
                patch.object(
                    sys,
                    "argv",
                    ["bootstrap_runtime.py", "--apply", "--confirm", "wrong"],
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                try:
                    runtime.main()
                except runtime.RuntimeError_:
                    pass
                else:
                    raise AssertionError("Stale confirmation accepted")
            assert not Path("/usr/local/bin/caddy").exists()
            with (
                patch.object(
                    sys, "argv", ["bootstrap_runtime.py", "--apply", "--confirm", token]
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                runtime.main()
            assert Path("/usr/local/bin/caddy").stat().st_mode & 0o777 == 0o555
            assert Path("/etc/mylifegraph/executor.env").stat().st_mode & 0o777 == 0o640
            assert (
                "OPERATOR_CODEX_PILOT_ENABLED=false"
                in Path("/etc/mylifegraph/executor.env").read_text()
            )
            assert not Path("/etc/mylifegraph/api.env").exists()
            assert not Path("/etc/mylifegraph/caddy.env").exists()
            assert not Path("/etc/sudoers.d/mylifegraph-deploy").exists()
            for name in ("mylifegraph-agent", "mylifegraph-api", "mylifegraph-deploy"):
                denied = subprocess.run(
                    [
                        "runuser",
                        "-u",
                        name,
                        "--",
                        "test",
                        "-r",
                        "/etc/mylifegraph/executor.env",
                    ]
                )
                assert denied.returncode != 0
            with (
                patch.object(sys, "argv", ["bootstrap_runtime.py"]),
                contextlib.redirect_stdout(io.StringIO()) as replay,
            ):
                runtime.main()
            assert "no changes made" in replay.getvalue()
            assert not any(
                call[:3]
                in (
                    ("/usr/bin/systemctl", "start", "caddy"),
                    ("/usr/bin/systemctl", "restart", "docker.service"),
                )
                for call in commands
            )
        subprocess.run(
            [
                "systemd-analyze",
                "verify",
                "/etc/systemd/system/caddy.service",
                "/usr/local/libexec/mylifegraph/docker-rootless.service",
            ],
            check=True,
        )
        print(
            "Runtime rehearsal passed: real file/account permissions, pinned Caddy parsing, "
            "preview/confirmation, held app services, private socket denial, exact no-op replay. "
            "Kernel/AppArmor/service manager/Docker capabilities were substituted, not live-verified."
        )
    finally:
        for sock in sockets:
            sock.close()


if __name__ == "__main__":
    main()
