#!/usr/bin/python3 -I
"""Administrator preview/apply for runtime foundation; application remains held."""

from __future__ import annotations

import argparse
import fcntl
import grp
import hashlib
import io
import json
import os
import platform
import pwd
import re
import socket
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

SCHEMA = "mylifegraph-runtime-bootstrap-v1"
BUNDLE = Path("/root/mylifegraph-runtime")
RECEIPT = Path("/etc/mylifegraph/runtime-bootstrap.json")
COACH = "mylifegraph-coach"
COACH_HOME = Path("/var/lib/mylifegraph-coach")
ENV = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LANG": "C", "LC_ALL": "C"}
PACKAGES = (
    "python3.12-venv",
    "dbus-user-session",
    "uidmap",
    "rootlesskit",
    "slirp4netns",
    "fuse-overlayfs",
)
ALLOWED_ADDITIONS = set(PACKAGES) | {"libslirp0", "libsubid4"}
HELPERS = (
    "prepare_release.sh",
    "promote_release.sh",
    "rollback_release.sh",
    "health_check.py",
    "analysis_image_revision.py",
    "release_manifest.py",
    "release_tree.py",
    "validate_public_origin.py",
    "install_codex_cli.py",
    "verify_permissions.sh",
    "preflight_host.sh",
)
UNITS = (
    "mylifegraph-api.service",
    "mylifegraph-coach-executor.service",
    "mylifegraph-coach-executor.socket",
    "mylifegraph-disk-monitor.service",
    "mylifegraph-disk-monitor.timer",
    "caddy.service",
)
SOURCE_MAP = {
    **{name: "bin/" + name for name in HELPERS},
    **{name: "systemd/" + name for name in UNITS},
    "bootstrap_runtime.py": "bin/bootstrap_runtime.py",
    "docker-rootless.service": "systemd/docker-rootless.service",
    "disk_monitor.sh": "bin/disk_monitor.sh",
    "Caddyfile": "caddy/Caddyfile",
    "executor.env.example": "env/executor.env.example",
    "api.env.example": "env/api.env.example",
    "caddy.env.example": "env/caddy.env.example",
    "codex-cli.json": "manifests/codex-cli.json",
    "runtime-sources.json": "manifests/runtime-sources.json",
    "tmpfiles.conf": "tmpfiles.d/mylifegraph.conf",
    "RUNTIME.md": "RUNTIME.md",
}


class RuntimeError_(RuntimeError):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def run(*args, env=None):
    result = subprocess.run(
        args, env=env or ENV, capture_output=True, text=True, check=False
    )
    if result.returncode:
        raise RuntimeError_(
            f"{Path(args[0]).name} failed (exit {result.returncode}); inspect locally as ops."
        )
    return result.stdout


def protect(path, directory=False):
    for item in (path, *path.parents):
        info = item.lstat()
        want_dir = directory or item != path
        valid = stat.S_ISDIR(info.st_mode) if want_dir else stat.S_ISREG(info.st_mode)
        if not valid or info.st_uid != 0 or info.st_mode & 0o022:
            raise RuntimeError_(f"Untrusted protected path: {item}")
        if not want_dir and info.st_nlink != 1:
            raise RuntimeError_(f"Hard-linked input: {item}")


def load_bundle():
    protect(BUNDLE, directory=True)
    protect(BUNDLE / "manifest.json")
    manifest = json.loads((BUNDLE / "manifest.json").read_bytes())
    expected = set(SOURCE_MAP) | {"caddy.tar.gz", "dockerd-rootless.sh"}
    if (
        set(manifest) != {"schema_version", "files"}
        or manifest["schema_version"] != SCHEMA
        or set(manifest["files"]) != expected
    ):
        raise RuntimeError_("Unexpected runtime manifest shape or input inventory.")
    files = {}
    for name in sorted(expected):
        protect(BUNDLE / name)
        files[name] = (BUNDLE / name).read_bytes()
        if sha(files[name]) != manifest["files"][name]:
            raise RuntimeError_(f"Runtime input checksum mismatch: {name}")
    sources = json.loads(files["runtime-sources.json"])
    if (
        sha(files["caddy.tar.gz"]) != sources["caddy_sha256"]
        or sha(files["dockerd-rootless.sh"]) != sources["rootless_sha256"]
    ):
        raise RuntimeError_("External artifact hash does not match pinned sources.")
    return manifest, files, sources


def parse_apt_simulation(text):
    additions = {}
    for line in text.splitlines():
        if line.startswith("Remv "):
            raise RuntimeError_("Package removal is outside this bootstrap.")
        if not line.startswith("Inst "):
            continue
        match = re.fullmatch(r"Inst ([a-z0-9+.-]+) \(([^ ]+) .+\)", line)
        if not match or match[1] not in ALLOWED_ADDITIONS:
            raise RuntimeError_(
                "Package upgrade or unexpected dependency; review separately."
            )
        additions[match[1]] = match[2]
    return additions


def subordinate_range(text, username=COACH):
    end = 100000
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split(":")
        if (
            len(parts) != 3
            or not parts[1].isdigit()
            or not parts[2].isdigit()
            or int(parts[2]) <= 0
        ):
            raise RuntimeError_("Malformed subordinate-ID map.")
        if parts[0] == username:
            raise RuntimeError_(
                "Coach subordinate IDs already exist; refusing to replace them."
            )
        end = max(end, int(parts[1]) + int(parts[2]))
    if end + 65535 >= 2**32 - 1:
        raise RuntimeError_("No supported subordinate-ID range remains.")
    return [end, end + 65535]


def coach_run(*args):
    uid = pwd.getpwnam(COACH).pw_uid
    # All values are fixed or derived from the verified passwd identity.
    return run(
        "/usr/sbin/runuser",
        "-u",
        COACH,
        "--",
        "/usr/bin/env",
        "-i",
        f"HOME={COACH_HOME}",
        f"USER={COACH}",
        f"LOGNAME={COACH}",
        f"XDG_RUNTIME_DIR=/run/user/{uid}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus",
        "PATH=/usr/local/libexec/mylifegraph:/usr/sbin:/usr/bin:/sbin:/bin",
        "LANG=C.UTF-8",
        *args,
    )


def fresh_plan(manifest, sources):
    os_release = Path("/etc/os-release").read_text()
    if (
        "ID=ubuntu\n" not in os_release
        or 'VERSION_ID="24.04"' not in os_release
        or platform.machine() != "x86_64"
    ):
        raise RuntimeError_("Runtime bundle requires Ubuntu 24.04 x86_64.")
    if not run("/usr/bin/dockerd", "--version").startswith(
        "Docker version " + sources["docker_version"] + ","
    ):
        raise RuntimeError_(
            "Installed Docker differs from the pinned rootless wrapper version."
        )
    run("/usr/bin/python3.12", "--version")
    run("/usr/sbin/sysctl", "--version")
    run("/usr/bin/systemd-tmpfiles", "--version")
    identities = {}
    for name in (
        "mylifegraph-agent",
        "mylifegraph-deploy",
        "mylifegraph-api",
        COACH,
        "mylifegraph-build",
    ):
        entry = pwd.getpwnam(name)
        if entry.pw_uid == 0:
            raise RuntimeError_("Project runtime UID must be non-root.")
        identities[name] = [entry.pw_uid, entry.pw_gid, entry.pw_dir, entry.pw_shell]
    if len({v[0] for v in identities.values()}) != len(identities):
        raise RuntimeError_("Project identities must have distinct UIDs.")
    if identities[COACH][2] != str(COACH_HOME) or identities["mylifegraph-build"][
        2:
    ] != ["/nonexistent", "/usr/sbin/nologin"]:
        raise RuntimeError_("Unexpected runtime homes or build shell.")
    protect(Path("/etc/mylifegraph"), directory=True)
    protect(Path("/etc/mylifegraph/access-bootstrap.json"))
    access = json.loads(Path("/etc/mylifegraph/access-bootstrap.json").read_bytes())
    for name, expected in access["identities"]["users"].items():
        entry = pwd.getpwnam(name)
        groups = sorted(g.gr_name for g in grp.getgrall() if name in g.gr_mem)
        if [entry.pw_uid, entry.pw_gid, entry.pw_dir, entry.pw_shell, groups] != [
            expected["uid"],
            expected["gid"],
            expected["home"],
            expected["shell"],
            expected["groups"],
        ]:
            raise RuntimeError_(
                "Access-bootstrap identity drift; review before runtime installation."
            )
    uid = identities[COACH][0]
    destinations = [
        Path("/usr/local/libexec/mylifegraph"),
        Path("/usr/local/libexec/mylifegraph-disk-monitor"),
        Path("/usr/local/bin/caddy"),
        Path("/usr/bin/caddy"),
        Path("/etc/caddy"),
        Path("/var/lib/caddy"),
        Path("/var/log/caddy"),
        Path("/srv/mylifegraph"),
        Path("/srv/mylifegraph-build"),
        RECEIPT,
        Path("/etc/mylifegraph/executor.env"),
        Path("/etc/tmpfiles.d/mylifegraph.conf"),
        Path(f"/etc/systemd/system/user@{uid}.service.d"),
        *(Path("/etc/systemd/system") / unit for unit in UNITS),
    ]
    for path in destinations:
        if path.exists() or path.is_symlink():
            raise RuntimeError_(
                f"Runtime target already exists: {path}; no automatic overwrite."
            )
    try:
        pwd.getpwnam("caddy")
    except KeyError:
        pass
    else:
        raise RuntimeError_("An existing caddy account must be reviewed separately.")
    try:
        grp.getgrnam("caddy")
    except KeyError:
        pass
    else:
        raise RuntimeError_("An existing caddy group must be reviewed separately.")
    for relative in (".config", ".local", "codex-home", "tmp"):
        if (COACH_HOME / relative).exists() or (COACH_HOME / relative).is_symlink():
            raise RuntimeError_(
                "Coach runtime state already exists; no automatic adoption."
            )
    if (
        Path(f"/var/lib/systemd/linger/{COACH}").exists()
        or Path(f"/run/user/{uid}").exists()
    ):
        raise RuntimeError_(
            "Coach user manager already exists; review before changing it."
        )
    if (
        Path("/proc/sys/kernel/apparmor_restrict_unprivileged_userns")
        .read_text()
        .strip()
        != "1"
    ):
        raise RuntimeError_(
            "Expected Ubuntu user-namespace restriction is not enabled."
        )
    profile = Path("/etc/apparmor.d/rootlesskit").read_text()
    if "/usr/bin/rootlesskit" not in profile or "userns," not in profile:
        raise RuntimeError_("Ubuntu rootlesskit AppArmor profile is missing.")
    if run("/usr/bin/stat", "-fc", "%T", "/sys/fs/cgroup").strip() != "cgroup2fs":
        raise RuntimeError_("cgroup v2 is required for enforced sandbox limits.")
    maps = {name: Path("/etc/" + name).read_text() for name in ("subuid", "subgid")}
    additions = parse_apt_simulation(
        run(
            "/usr/bin/apt-get",
            "--simulate",
            "--no-install-recommends",
            "--no-upgrade",
            "install",
            *PACKAGES,
        )
    )
    return {
        "schema_version": SCHEMA,
        "hostname": socket.gethostname(),
        "machine_sha256": sha(Path("/etc/machine-id").read_bytes()),
        "manifest_sha256": sha(canonical(manifest)),
        "identities": identities,
        "package_additions": additions,
        "package_database_sha256": sha(Path("/var/lib/dpkg/status").read_bytes()),
        "subordinate_map_hashes": {
            name: sha(value.encode()) for name, value in maps.items()
        },
        "rootlesskit_profile_sha256": sha(profile.encode()),
        "subordinate_ranges": {
            name: subordinate_range(value) for name, value in maps.items()
        },
        "rootful_docker_state": run(
            "/usr/bin/systemctl",
            "show",
            "docker.service",
            "-p",
            "MainPID",
            "-p",
            "ActiveState",
        ),
        "caddy_version": sources["caddy_version"],
        "docker_version": sources["docker_version"],
        "write_targets": [str(p) for p in destinations if p != Path("/usr/bin/caddy")],
        "starts": [
            "mylifegraph-coach user manager",
            "only its rootless docker.service",
        ],
        "held": [
            "Caddy/public ports",
            "API",
            "Coach executor",
            "disk timer",
            "sudo grants",
            "provider login",
            "release deployment",
        ],
    }


def install(path, data, mode=0o644, group="root"):
    protect(path.parent, directory=True)
    with os.fdopen(
        os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode), "wb"
    ) as output:
        output.write(data)
        os.fchown(output.fileno(), 0, grp.getgrnam(group).gr_gid)
        os.fchmod(output.fileno(), mode)


def mkdir(path, mode=0o755, owner="root", group="root"):
    protect(path.parent, directory=True)
    path.mkdir(mode=mode)
    os.chown(path, pwd.getpwnam(owner).pw_uid, grp.getgrnam(group).gr_gid)
    path.chmod(mode)


def caddy_binary(archive):
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as source:
        matches = [member for member in source.getmembers() if member.name == "caddy"]
        if (
            len(matches) != 1
            or not matches[0].isfile()
            or not 0 < matches[0].size < 128 * 1024 * 1024
        ):
            raise RuntimeError_("Unexpected Caddy archive member.")
        return source.extractfile(matches[0]).read()


def apply(plan, files, sources):
    additions = plan["package_additions"]
    if additions:
        pinned = tuple(
            name + "=" + version for name, version in sorted(additions.items())
        )
        simulation = parse_apt_simulation(
            run(
                "/usr/bin/apt-get",
                "--simulate",
                "--no-install-recommends",
                "--no-upgrade",
                "install",
                *pinned,
            )
        )
        if simulation != additions:
            raise RuntimeError_(
                "Pinned package transaction changed before installation."
            )
        run(
            "/usr/bin/apt-get",
            "--yes",
            "--no-remove",
            "--no-upgrade",
            "--no-install-recommends",
            "install",
            *pinned,
            env={**ENV, "DEBIAN_FRONTEND": "noninteractive", "NEEDRESTART_MODE": "l"},
        )
    run("/usr/bin/python3.12", "-c", "import venv, ensurepip")
    base = Path("/usr/local/libexec")
    if not base.exists():
        mkdir(base)
    helper = base / "mylifegraph"
    mkdir(helper)
    for name in HELPERS:
        install(helper / name, files[name], 0o555)
    install(helper / "dockerd-rootless.sh", files["dockerd-rootless.sh"], 0o555)
    install(helper / "docker-rootless.service", files["docker-rootless.service"])
    mkdir(helper / "manifests")
    install(helper / "manifests/codex-cli.json", files["codex-cli.json"], 0o444)
    install(base / "mylifegraph-disk-monitor", files["disk_monitor.sh"], 0o555)
    run("/usr/sbin/groupadd", "--system", "caddy")
    run(
        "/usr/sbin/useradd",
        "--system",
        "--no-create-home",
        "--gid",
        "caddy",
        "--home-dir",
        "/var/lib/caddy",
        "--shell",
        "/usr/sbin/nologin",
        "caddy",
    )
    mkdir(Path("/var/lib/caddy"), 0o750, "caddy", "caddy")
    mkdir(Path("/var/log/caddy"), 0o750, "caddy", "adm")
    mkdir(Path("/etc/caddy"))
    install(Path("/usr/local/bin/caddy"), caddy_binary(files["caddy.tar.gz"]), 0o555)
    install(Path("/etc/caddy/Caddyfile"), files["Caddyfile"])
    version = run(
        "/usr/sbin/runuser",
        "-u",
        "mylifegraph-build",
        "--",
        "/usr/local/bin/caddy",
        "version",
    )
    if not version.startswith("v" + sources["caddy_version"] + " "):
        raise RuntimeError_("Installed Caddy version differs from the verified bundle.")
    run(
        "/usr/sbin/runuser",
        "-u",
        "caddy",
        "--",
        "/usr/bin/env",
        "-i",
        "PATH=/usr/bin:/bin",
        "MYLIFEGRAPH_API_HOST=api.example.test",
        "/usr/local/bin/caddy",
        "adapt",
        "--config",
        "/etc/caddy/Caddyfile",
    )
    mkdir(Path("/srv/mylifegraph"), 0o750, group="mylifegraph-release")
    mkdir(Path("/srv/mylifegraph/releases"), 0o750, group="mylifegraph-release")
    mkdir(Path("/srv/mylifegraph/incoming"), 0o700)
    mkdir(Path("/srv/mylifegraph-build"), 0o710, group="mylifegraph-build")
    uid = plan["identities"][COACH][0]
    # Private state is created under the target UID, never by root following user paths.
    coach_run(
        "/usr/bin/mkdir",
        "-m",
        "0700",
        "-p",
        str(COACH_HOME / ".config/systemd/user"),
        str(COACH_HOME / "codex-home"),
        str(COACH_HOME / "tmp"),
    )
    coach_run(
        "/usr/bin/install",
        "-m",
        "0644",
        str(helper / "docker-rootless.service"),
        str(COACH_HOME / ".config/systemd/user/docker.service"),
    )
    env = (
        files["executor.env.example"]
        .decode()
        .replace("<mylifegraph-api-uid>", str(plan["identities"]["mylifegraph-api"][0]))
        .replace("<mylifegraph-coach-uid>", str(uid))
    )
    install(Path("/etc/mylifegraph/executor.env"), env.encode(), 0o640, COACH)
    for unit in UNITS:
        install(Path("/etc/systemd/system") / unit, files[unit])
    if not Path("/etc/tmpfiles.d").exists():
        mkdir(Path("/etc/tmpfiles.d"))
    install(Path("/etc/tmpfiles.d/mylifegraph.conf"), files["tmpfiles.conf"])
    run("/usr/bin/systemd-tmpfiles", "--create", "/etc/tmpfiles.d/mylifegraph.conf")
    delegation = Path(f"/etc/systemd/system/user@{uid}.service.d")
    mkdir(delegation)
    install(
        delegation / "mylifegraph.conf",
        b"[Service]\nDelegate=cpu cpuset io memory pids\nMemoryMax=2G\nCPUQuota=200%\nTasksMax=512\n",
    )
    for name in ("subuid", "subgid"):
        if (
            sha(Path("/etc/" + name).read_bytes())
            != plan["subordinate_map_hashes"][name]
        ):
            raise RuntimeError_("Subordinate-ID map changed during preparation.")
    first, last = plan["subordinate_ranges"]["subuid"]
    gfirst, glast = plan["subordinate_ranges"]["subgid"]
    run(
        "/usr/sbin/usermod",
        "--add-subuids",
        f"{first}-{last}",
        "--add-subgids",
        f"{gfirst}-{glast}",
        COACH,
    )
    profile_path = Path("/etc/apparmor.d/rootlesskit")
    protect(profile_path)
    if sha(profile_path.read_bytes()) != plan["rootlesskit_profile_sha256"]:
        raise RuntimeError_("RootlessKit AppArmor profile changed during preparation.")
    run("/usr/sbin/apparmor_parser", "-r", str(profile_path))
    run("/usr/bin/systemctl", "daemon-reload")
    try:
        run("/usr/bin/loginctl", "enable-linger", COACH)
        run("/usr/bin/systemctl", "start", f"user@{uid}.service")
        verify_rootless(plan)
    except (RuntimeError_, OSError, ValueError):
        # The preflight required this user's daemon/manager to be absent.
        # Stop only the newly provisioned Coach runtime, never host Docker.
        for action in (
            lambda: coach_run(
                "/usr/bin/systemctl", "--user", "disable", "--now", "docker.service"
            ),
            lambda: run("/usr/bin/systemctl", "stop", f"user@{uid}.service"),
            lambda: run("/usr/bin/loginctl", "disable-linger", COACH),
        ):
            try:
                action()
            except (RuntimeError_, OSError):
                print(
                    "Coach runtime cleanup needs administrator inspection.",
                    file=sys.stderr,
                )
        raise
    recorded = [
        helper / name
        for name in (*HELPERS, "dockerd-rootless.sh", "docker-rootless.service")
    ]
    recorded += [
        helper / "manifests/codex-cli.json",
        base / "mylifegraph-disk-monitor",
        Path("/usr/local/bin/caddy"),
        Path("/etc/caddy/Caddyfile"),
        Path("/etc/mylifegraph/executor.env"),
        Path("/etc/tmpfiles.d/mylifegraph.conf"),
        delegation / "mylifegraph.conf",
    ]
    recorded += [Path("/etc/systemd/system") / unit for unit in UNITS]
    install(
        RECEIPT,
        canonical(
            {
                "plan": plan,
                "rootless_verified": True,
                "application_started": False,
                "installed_files": {
                    str(path): sha(path.read_bytes()) for path in recorded
                },
            }
        )
        + b"\n",
        0o600,
    )


def verify_rootless(plan):
    uid = plan["identities"][COACH][0]
    limits = dict(
        line.split("=", 1)
        for line in run(
            "/usr/bin/systemctl",
            "show",
            f"user@{uid}.service",
            "-p",
            "MemoryMax",
            "-p",
            "CPUQuotaPerSecUSec",
            "-p",
            "TasksMax",
        ).splitlines()
    )
    if limits != {
        "MemoryMax": "2147483648",
        "CPUQuotaPerSecUSec": "2s",
        "TasksMax": "512",
    }:
        raise RuntimeError_("Coach user-manager aggregate limits are not active.")
    coach_run("/usr/bin/systemctl", "--user", "daemon-reload")
    coach_run("/usr/bin/systemctl", "--user", "enable", "--now", "docker.service")
    info = json.loads(
        coach_run(
            "/usr/bin/docker",
            "--host",
            f"unix:///run/user/{uid}/docker.sock",
            "info",
            "--format",
            "{{json .}}",
        )
    )
    if (
        info.get("CgroupDriver") != "systemd"
        or str(info.get("CgroupVersion")) != "2"
        or not any("rootless" in item for item in info.get("SecurityOptions", []))
    ):
        raise RuntimeError_(
            "Docker does not report rootless mode with systemd/cgroup v2."
        )
    if not all(
        info.get(flag) is True for flag in ("MemoryLimit", "CpuCfsQuota", "PidsLimit")
    ):
        raise RuntimeError_(
            "Rootless Docker does not report required resource limit support."
        )
    sock = Path(f"/run/user/{uid}/docker.sock")
    if sock.stat().st_uid != uid or not stat.S_ISSOCK(sock.stat().st_mode):
        raise RuntimeError_("Unexpected rootless Docker socket owner/type.")
    for name in ("mylifegraph-agent", "mylifegraph-api", "mylifegraph-deploy"):
        assert_socket_denied(name, sock)
    after = run(
        "/usr/bin/systemctl",
        "show",
        "docker.service",
        "-p",
        "MainPID",
        "-p",
        "ActiveState",
    )
    if after != plan["rootful_docker_state"]:
        raise RuntimeError_(
            "Existing system Docker state changed; inspect before continuing."
        )


def assert_socket_denied(name, sock):
    result = subprocess.run(
        [
            "/usr/sbin/runuser",
            "-u",
            name,
            "--",
            "/usr/bin/python3",
            "-I",
            "-c",
            "import socket,sys\ns=socket.socket(socket.AF_UNIX)\n"
            "try:\n s.connect(sys.argv[1])\n"
            "except PermissionError:\n sys.exit(77)\n",
            str(sock),
        ],
        env=ENV,
        capture_output=True,
    )
    if result.returncode != 77:
        raise RuntimeError_(
            "Could not prove permission denial for a non-Coach socket client."
        )


def already_prepared(manifest):
    if not RECEIPT.exists() and not RECEIPT.is_symlink():
        return False
    protect(RECEIPT)
    record = json.loads(RECEIPT.read_bytes())
    if record["plan"]["manifest_sha256"] != sha(canonical(manifest)):
        raise RuntimeError_(
            "A different runtime bundle was installed; upgrades require a separate review."
        )
    for name, expected in record["installed_files"].items():
        path = Path(name)
        protect(path)
        if sha(path.read_bytes()) != expected:
            raise RuntimeError_(
                "Installed runtime configuration changed; no automatic repair."
            )
    print(
        "This exact runtime foundation was already prepared; no changes made. Re-run target acceptance before release."
    )
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm")
    args = parser.parse_args()
    if (
        os.geteuid() != 0
        or not sys.flags.isolated
        or Path(__file__).absolute() != BUNDLE / "bootstrap_runtime.py"
    ):
        raise RuntimeError_(
            "Use sudo /usr/bin/python3 -I /root/mylifegraph-runtime/bootstrap_runtime.py."
        )
    os.umask(0o077)
    manifest, files, sources = load_bundle()
    with (BUNDLE / "bootstrap_runtime.py").open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if already_prepared(manifest):
            return
        plan = fresh_plan(manifest, sources)
        token = sha(canonical(plan))
        print(json.dumps(plan, indent=2, sort_keys=True))
        print("Confirmation SHA256:", token, flush=True)
        if not args.apply:
            if args.confirm:
                raise RuntimeError_("--confirm requires --apply.")
            return
        if args.confirm != token:
            raise RuntimeError_(
                "Missing/stale confirmation; preview the exact host and package state again."
            )
        apply(plan, files, sources)
        print(
            "Runtime foundation prepared. Caddy, API and Coach remain stopped and unconfigured for release."
        )


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError_, OSError, ValueError, KeyError) as exc:
        print("Runtime bootstrap stopped:", exc, file=sys.stderr)
        raise SystemExit(1)
