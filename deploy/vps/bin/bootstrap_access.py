#!/usr/bin/python3 -I
"""Preview/apply the first, account-only VPS bootstrap from a sealed bundle.

No package installation, application deployment, sudo grants, or network calls.
Run only with the system Python in isolated mode from /root/mylifegraph-access.
"""

from __future__ import annotations

import argparse
import base64
import fcntl
import grp
import hashlib
import json
import os
import pwd
import socket
import stat
import struct
import subprocess
import sys
from pathlib import Path


INSTALL_ROOT = Path("/root/mylifegraph-access")
RECEIPT = Path("/etc/mylifegraph/access-bootstrap.json")
SSH_CONFIG = Path("/etc/ssh/sshd_config.d/60-mylifegraph-access.conf")
KEY_ROOT = Path("/etc/mylifegraph/authorized_keys")
WORK_ROOT = Path("/srv/mylifegraph-work")
PEOPLE = ("mylifegraph-gregor", "mylifegraph-matthias", "mylifegraph-agent")
RUNTIME = (
    "mylifegraph-deploy",
    "mylifegraph-api",
    "mylifegraph-coach",
    "mylifegraph-build",
)
USERS = PEOPLE + RUNTIME
SCHEMA = "mylifegraph-access-bootstrap-v1"
ENV = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LANG": "C", "LC_ALL": "C"}


class AccessError(RuntimeError):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def public_key(value: str) -> str:
    """Accept only a single plain Ed25519 public key, without SSH options."""
    fields = value.strip().split()
    if "\n" in value.strip() or len(fields) < 2 or fields[0] != "ssh-ed25519":
        raise AccessError(
            "Expected one plain ssh-ed25519 public key, never a private key."
        )
    try:
        blob = base64.b64decode(fields[1], validate=True)
    except ValueError as exc:
        raise AccessError("Invalid public key encoding.") from exc
    prefix = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32)
    if len(blob) != len(prefix) + 32 or not blob.startswith(prefix):
        raise AccessError("Invalid Ed25519 public key structure.")
    return "ssh-ed25519 " + base64.b64encode(blob).decode()


def load_manifest(data: bytes) -> dict:
    def unique(pairs):
        result = {}
        for key, item in pairs:
            if key in result:
                raise AccessError("Duplicate access manifest field.")
            result[key] = item
        return result

    try:
        value = json.loads(data, object_pairs_hook=unique)
    except (ValueError, UnicodeError) as exc:
        raise AccessError("Invalid access manifest JSON.") from exc
    if not isinstance(value, dict) or set(value) != {"schema_version", "keys"}:
        raise AccessError("Unexpected access manifest fields.")
    if value["schema_version"] != SCHEMA or not isinstance(value["keys"], dict):
        raise AccessError("Unsupported access manifest.")
    keys = value["keys"]
    if set(keys) - set(PEOPLE) or any(
        not isinstance(key, str) for key in keys.values()
    ):
        raise AccessError(
            "Public keys may target only the three project login accounts."
        )
    keys = {user: public_key(key) for user, key in keys.items()}
    if len(set(keys.values())) != len(keys):
        raise AccessError("Each project login requires its own public key.")
    return {"schema_version": SCHEMA, "keys": keys}


def run(*args: str) -> str:
    result = subprocess.run(args, env=ENV, text=True, capture_output=True, check=False)
    if result.returncode:
        # Command output can include host configuration; never echo it blindly.
        raise AccessError(f"{Path(args[0]).name} failed (exit {result.returncode}).")
    return result.stdout


def protected(path: Path, *, directory: bool = False) -> None:
    """Reject symlinks and writable/non-root ancestors all the way to /."""
    for item in (path, *path.parents):
        info = item.lstat()
        is_dir = directory if item == path else True
        valid_type = (
            stat.S_ISDIR(info.st_mode) if is_dir else stat.S_ISREG(info.st_mode)
        )
        if not valid_type or info.st_uid != 0 or info.st_mode & 0o022:
            raise AccessError(f"Untrusted ownership, type, or permissions: {item}")
        if not is_dir and info.st_nlink != 1:
            raise AccessError(f"Hard-linked protected input: {item}")


def read_protected(path: Path) -> bytes:
    protected(path)
    data = path.read_bytes()
    if len(data) > 256 * 1024:
        raise AccessError(f"Protected input too large: {path}")
    return data


def ssh_configuration() -> bytes:
    return (
        "# Project accounts only; existing ops/agent and other users are unaffected.\n"
        "Match User " + ",".join(USERS) + "\n"
        "    AuthorizedKeysFile /etc/mylifegraph/authorized_keys/%u\n"
        "    AuthorizedKeysCommand none\n"
        "    TrustedUserCAKeys none\n"
        "    AuthenticationMethods publickey\n"
        "    PubkeyAuthentication yes\n"
        "    PasswordAuthentication no\n"
        "    KbdInteractiveAuthentication no\n"
        "    DisableForwarding yes\n"
        "    PermitUserRC no\n"
        "Match all\n"
    ).encode()


def account_spec(user: str, keys: dict) -> dict:
    if user in PEOPLE:
        return {
            "home": f"/home/{user}",
            "shell": "/bin/bash" if user in keys else "/usr/sbin/nologin",
            "groups": ["mylifegraph-work"],
        }
    homes = {
        "mylifegraph-deploy": "/var/lib/mylifegraph-deploy",
        "mylifegraph-api": "/var/lib/mylifegraph-api",
        "mylifegraph-coach": "/var/lib/mylifegraph-coach",
        "mylifegraph-build": "/nonexistent",
    }
    return {
        "home": homes[user],
        "shell": "/usr/sbin/nologin",
        "groups": [] if user == "mylifegraph-build" else ["mylifegraph-release"],
    }


def identity_snapshot() -> dict:
    users = {}
    groups = {}
    for name in USERS:
        try:
            entry = pwd.getpwnam(name)
            users[name] = {
                "uid": entry.pw_uid,
                "gid": entry.pw_gid,
                "home": entry.pw_dir,
                "shell": entry.pw_shell,
                "groups": sorted(g.gr_name for g in grp.getgrall() if name in g.gr_mem),
            }
        except KeyError:
            pass
    for name in (*USERS, "mylifegraph-work", "mylifegraph-release"):
        try:
            entry = grp.getgrnam(name)
            groups[name] = {"gid": entry.gr_gid, "members": sorted(entry.gr_mem)}
        except KeyError:
            pass
    return {"users": users, "groups": groups}


def assert_no_sudo(user: str) -> None:
    result = subprocess.run(
        ["/usr/bin/sudo", "-l", "-U", user],
        env=ENV,
        text=True,
        capture_output=True,
        check=False,
    )
    expected = f"User {user} is not allowed to run sudo on {socket.gethostname()}."
    if result.returncode != 0 or result.stdout.strip() != expected:
        raise AccessError(
            "A project account has existing sudo authority; administrator review required."
        )


def inspect_state(manifest: dict) -> tuple[dict, dict]:
    state = identity_snapshot()
    if RECEIPT.exists() or RECEIPT.is_symlink():
        receipt = json.loads(read_protected(RECEIPT))
        if receipt.get("schema_version") != SCHEMA:
            raise AccessError("Unknown existing bootstrap receipt.")
        previous = load_manifest(canonical(receipt["manifest"]))
        if state != receipt["identities"]:
            raise AccessError(
                "Project account/group drift; administrator review required."
            )
        for user, key in previous["keys"].items():
            if manifest["keys"].get(user) != key:
                raise AccessError(
                    "Key removal/replacement requires a separate reviewed operation."
                )
        if read_protected(SSH_CONFIG) != ssh_configuration():
            raise AccessError("Project SSH configuration drift.")
        for user in USERS:
            assert_no_sudo(user)
            expected = (
                (previous["keys"][user] + "\n").encode()
                if user in previous["keys"]
                else b""
            )
            if read_protected(KEY_ROOT / user) != expected:
                raise AccessError("Project authorized-key drift.")
        for directory in (Path("/etc/mylifegraph"), KEY_ROOT):
            protected(directory, directory=True)
        return state, previous["keys"]
    if state["users"] or state["groups"]:
        raise AccessError(
            "Project account/group already exists without receipt; refusing adoption."
        )
    for path in (
        Path("/etc/mylifegraph"),
        SSH_CONFIG,
        WORK_ROOT,
        *(Path(account_spec(u, {})["home"]) for u in USERS if u != "mylifegraph-build"),
    ):
        if path.exists() or path.is_symlink():
            raise AccessError(
                f"Existing project path requires administrator review: {path}"
            )
    return state, {}


def make_plan(
    manifest: dict,
    state: dict,
    previous_keys: dict,
    *,
    host: str,
    machine: str,
    installer_digest: str,
    ssh_digest: str,
) -> dict:
    return {
        "schema_version": SCHEMA,
        "hostname": host,
        "machine_fingerprint": digest(machine.encode()),
        "installer_sha256": installer_digest,
        "manifest_sha256": digest(canonical(manifest)),
        "ssh_config_sha256": ssh_digest,
        "current_identities": state,
        "accounts": {user: account_spec(user, manifest["keys"]) for user in USERS},
        "new_ssh_access": [
            user
            for user in PEOPLE
            if user in manifest["keys"] and user not in previous_keys
        ],
        "key_fingerprints": {
            user: "SHA256:"
            + base64.b64encode(
                hashlib.sha256(base64.b64decode(key.split()[1])).digest()
            )
            .decode()
            .rstrip("=")
            for user, key in manifest["keys"].items()
        },
        "create_accounts": not bool(state["users"]),
        "scope": [
            "project accounts/groups/homes",
            str(WORK_ROOT),
            str(KEY_ROOT),
            str(SSH_CONFIG),
            "validate and reload SSH; no existing sessions terminated",
        ],
        "not_included": [
            "sudo grants",
            "packages",
            "application services",
            "firewall",
            "reboot",
            "provider login",
            "credentials",
            "deployment",
        ],
    }


def mkdir(path: Path, mode: int, user: str = "root", group: str = "root") -> None:
    protected(path.parent, directory=True)
    path.mkdir(mode=mode)
    os.chown(path, pwd.getpwnam(user).pw_uid, grp.getgrnam(group).gr_gid)
    path.chmod(mode)


def write(path: Path, data: bytes, *, replace: bool = False) -> None:
    protected(path.parent, directory=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW
    flags |= os.O_TRUNC if replace else os.O_EXCL
    with os.fdopen(os.open(path, flags, 0o600), "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def effective_ssh(user: str) -> str:
    return run(
        "/usr/sbin/sshd", "-T", "-C", f"user={user},host=localhost,addr=127.0.0.1"
    )


def apply(manifest: dict, state: dict, previous_keys: dict) -> None:
    # Never invoke this until every preview/precondition and the confirmation pass.
    before = {user: effective_ssh(user) for user in ("ops", "agent", "root")}
    if not state["users"]:
        for group in ("mylifegraph-work", "mylifegraph-release", *USERS):
            run("/usr/sbin/groupadd", "--system", group)
        for user in USERS:
            spec = account_spec(
                user, {}
            )  # Remain nologin until SSH validation succeeds.
            args = [
                "/usr/sbin/useradd",
                "--no-create-home",
                "--no-log-init",
                "--gid",
                user,
                "--home-dir",
                spec["home"],
                "--shell",
                "/usr/sbin/nologin",
            ]
            if user in RUNTIME:
                args.append("--system")
            if spec["groups"]:
                args += ["--groups", ",".join(spec["groups"])]
            run(*args, user)
            if user != "mylifegraph-build":
                mkdir(
                    Path(spec["home"]),
                    0o750 if user == "mylifegraph-api" else 0o700,
                    user,
                    user,
                )
        mkdir(WORK_ROOT, 0o2770, group="mylifegraph-work")
        mkdir(Path("/etc/mylifegraph"), 0o751)
        mkdir(KEY_ROOT, 0o755)
        for user in USERS:
            # Files are public keys, readable by sshd's unprivileged key check.
            write(KEY_ROOT / user, b"")
            (KEY_ROOT / user).chmod(0o644)
        write(SSH_CONFIG, ssh_configuration())
    try:
        run("/usr/sbin/sshd", "-t")
        for user, value in before.items():
            if effective_ssh(user) != value:
                raise AccessError(
                    "Existing administrative SSH behavior changed; refusing reload."
                )
        expected = {
            "authorizedkeysfile": str(KEY_ROOT / "%u"),
            "authorizedkeyscommand": "none",
            "trustedusercakeys": "none",
            "authenticationmethods": "publickey",
            "pubkeyauthentication": "yes",
            "passwordauthentication": "no",
            "kbdinteractiveauthentication": "no",
            "disableforwarding": "yes",
            "permituserrc": "no",
        }
        for user in USERS:
            settings = dict(
                line.split(" ", 1) for line in effective_ssh(user).splitlines()
            )
            if any(settings.get(key) != value for key, value in expected.items()):
                raise AccessError(
                    "Project SSH rules are ineffective; refusing to enable logins."
                )
            assert_no_sudo(user)
        run("/usr/bin/systemctl", "reload", "ssh")
    except (AccessError, OSError):
        if not state["users"]:
            # This file was created with O_EXCL by this attempt. Accounts are
            # still nologin and have no keys; preserve them for operator review.
            SSH_CONFIG.unlink()
        raise
    additions = [
        user
        for user in PEOPLE
        if user in manifest["keys"] and user not in previous_keys
    ]
    try:
        for user in additions:
            write(
                KEY_ROOT / user, (manifest["keys"][user] + "\n").encode(), replace=True
            )
            run("/usr/sbin/usermod", "--shell", "/bin/bash", user)
        receipt = {
            "schema_version": SCHEMA,
            "manifest": manifest,
            "identities": identity_snapshot(),
        }
        write(RECEIPT, canonical(receipt) + b"\n", replace=bool(state["users"]))
    except (AccessError, OSError):
        for user in additions:
            run("/usr/sbin/usermod", "--shell", "/usr/sbin/nologin", user)
            write(KEY_ROOT / user, b"", replace=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument(
        "--confirm", help="SHA256 shown by the immediately preceding host preview"
    )
    args = parser.parse_args()
    if os.geteuid() != 0 or not sys.flags.isolated:
        raise AccessError(
            "Use sudo /usr/bin/python3 -I; preview also needs administrative inspection."
        )
    if Path(__file__).absolute() != INSTALL_ROOT / "bootstrap_access.py":
        raise AccessError(f"Use the administrator-sealed installer in {INSTALL_ROOT}.")
    script = read_protected(Path(__file__))
    manifest = load_manifest(read_protected(INSTALL_ROOT / "access.json"))
    os_release = Path("/etc/os-release").read_text()
    if "ID=ubuntu\n" not in os_release or 'VERSION_ID="24.04"' not in os_release:
        raise AccessError("This bootstrap targets Ubuntu 24.04 only.")
    for parent in ("/home", "/var/lib", "/srv", "/etc/ssh/sshd_config.d"):
        protected(Path(parent), directory=True)
    run("/usr/sbin/sshd", "-t")
    # Lock the immutable root-owned bundle, not any user-controlled /tmp file.
    with (INSTALL_ROOT / "bootstrap_access.py").open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state, previous = inspect_state(manifest)
        ssh_state = {
            user: effective_ssh(user) for user in (*USERS, "ops", "agent", "root")
        }
        plan = make_plan(
            manifest,
            state,
            previous,
            host=socket.gethostname(),
            machine=Path("/etc/machine-id").read_text(),
            installer_digest=digest(script),
            ssh_digest=digest(canonical(ssh_state)),
        )
        token = digest(canonical(plan))
        print(json.dumps(plan, indent=2, sort_keys=True))
        print(f"Confirmation SHA256: {token}", flush=True)
        if not args.apply:
            if args.confirm:
                raise AccessError("--confirm is only valid with --apply.")
            return 0
        if args.confirm != token:
            raise AccessError(
                "Missing/stale confirmation; preview this exact host and bundle again."
            )
        if state["users"] and manifest["keys"] == previous:
            print("Already configured; no changes made.")
            return 0
        apply(manifest, state, previous)
    print(
        "Project access prepared. Application and deployment privileges remain unconfigured."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AccessError, OSError, ValueError, KeyError) as exc:
        print(f"Access bootstrap stopped: {exc}", file=sys.stderr)
        raise SystemExit(1)
