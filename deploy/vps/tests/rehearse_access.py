"""Run only inside the disposable Ubuntu image described in ACCESS.md.

Uses actual accounts, permissions, sudo policy and SSH authentication. The only
substitute is systemctl reload: this non-systemd container sends sshd SIGHUP.
"""

import json
import os
import shutil
import socket
import subprocess
import time
from pathlib import Path


def run(*args, ok=True):
    result = subprocess.run(args, text=True, capture_output=True)
    if ok and result.returncode:
        raise AssertionError(f"{args[0]} failed: {result.stderr}\n{result.stdout}")
    return result


def main():
    if (
        not Path("/.dockerenv").is_file()
        or os.geteuid() != 0
        or not Path("/input/bin/bootstrap_access.py").is_file()
    ):
        raise SystemExit("This rehearsal requires the documented disposable container.")
    with Path("/etc/hosts").open("a") as output:
        output.write(f"\n127.0.0.1 {socket.gethostname()}\n")
    Path("/etc/machine-id").write_text("a" * 32 + "\n")
    Path("/run/sshd").mkdir(exist_ok=True)
    root = Path("/root/mylifegraph-access")
    root.mkdir(mode=0o700)
    shutil.copyfile("/input/bin/bootstrap_access.py", root / "bootstrap_access.py")
    for user in ("ops", "agent"):
        run("useradd", "-m", user)
        Path(f"/home/{user}").chmod(0o700)
    for name in ("gregor", "matthias", "agent"):
        run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", f"/tmp/{name}")
    manifest = {
        "schema_version": "mylifegraph-access-bootstrap-v1",
        "keys": {
            "mylifegraph-gregor": Path("/tmp/gregor.pub").read_text(),
            "mylifegraph-agent": Path("/tmp/agent.pub").read_text(),
        },
    }
    (root / "access.json").write_text(json.dumps(manifest))
    # A narrow substitute for systemd in this test container only.
    Path("/usr/bin/systemctl").write_text(
        '#!/bin/sh\nset -eu\n[ "$#" = 2 ] && [ "$1" = reload ] && [ "$2" = ssh ]\n'
        'echo reload >> /tmp/reloads\nkill -HUP "$(cat /run/sshd.pid)"\n'
    )
    Path("/usr/bin/systemctl").chmod(0o755)
    daemon = subprocess.Popen(
        ["/usr/sbin/sshd", "-D", "-e"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        for _ in range(50):
            try:
                with socket.create_connection(("127.0.0.1", 22), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        known = run("ssh-keyscan", "-t", "ed25519", "127.0.0.1").stdout
        Path("/tmp/known_hosts").write_text(known)
        command = ["/usr/bin/python3", "-I", str(root / "bootstrap_access.py")]

        def preview():
            result = run(*command)
            return result.stdout.split("Confirmation SHA256: ")[1].splitlines()[0]

        def ssh(name, command, ok=True):
            return run(
                "ssh",
                "-i",
                f"/tmp/{name}",
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                "UserKnownHostsFile=/tmp/known_hosts",
                "-o",
                "ConnectTimeout=3",
                f"mylifegraph-{name}@127.0.0.1",
                command,
                ok=ok,
            )

        token = preview()
        assert run("getent", "passwd", "mylifegraph-agent", ok=False).returncode != 0
        assert run(*command, "--apply", "--confirm", "wrong", ok=False).returncode != 0
        assert run("getent", "passwd", "mylifegraph-agent", ok=False).returncode != 0
        run(*command, "--apply", "--confirm", token)
        for name in ("gregor", "agent"):
            assert ssh(name, "id -un").stdout.strip() == f"mylifegraph-{name}"
            ssh(name, "touch /srv/mylifegraph-work/" + name)
            ssh(
                name,
                "test ! -x /home/ops && test ! -x /home/agent && test ! -x /var/lib/mylifegraph-coach",
            )
            ssh(name, "test ! -w /etc/mylifegraph/authorized_keys/mylifegraph-agent")
            assert ssh(name, "sudo -n true", ok=False).returncode != 0
        assert ssh("matthias", "id -un", ok=False).returncode != 0
        before = Path("/tmp/reloads").read_text()
        run(*command, "--apply", "--confirm", preview())
        assert Path("/tmp/reloads").read_text() == before
        stale = preview()
        manifest["keys"]["mylifegraph-matthias"] = Path("/tmp/matthias.pub").read_text()
        (root / "access.json").write_text(json.dumps(manifest))
        assert run(*command, "--apply", "--confirm", stale, ok=False).returncode != 0
        run(*command, "--apply", "--confirm", preview())
        assert ssh("matthias", "id -un").stdout.strip() == "mylifegraph-matthias"
        # A user's own ~/.ssh/authorized_keys must not grant access to another key.
        agent_public = Path("/tmp/agent.pub").read_text().strip()
        ssh(
            "gregor",
            'mkdir -m 700 ~/.ssh; printf "%s\\n" '
            + repr(agent_public)
            + " > ~/.ssh/authorized_keys",
        )
        result = run(
            "ssh",
            "-i",
            "/tmp/agent",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "BatchMode=yes",
            "-o",
            "UserKnownHostsFile=/tmp/known_hosts",
            "mylifegraph-gregor@127.0.0.1",
            "true",
            ok=False,
        )
        assert result.returncode != 0
        run("usermod", "-aG", "sudo", "mylifegraph-agent")
        assert run(*command, ok=False).returncode != 0
        print(
            "Ubuntu access rehearsal passed: preview, stale confirmation, SSH identities, permissions, "
            "sudo denial, idempotence, later Matthias enrollment, managed keys, and account drift."
        )
    finally:
        daemon.terminate()
        daemon.wait(timeout=5)


if __name__ == "__main__":
    main()
