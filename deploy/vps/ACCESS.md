# Project access before application installation

This is the first, account-only stage of [VPS operations](README.md). Local
bundle preparation never contacts a server. Administrator preview and apply on
the VPS require separate authorization. A bundle is not a release or deployment.

## Accounts and authority

| Account | Purpose | First-stage access |
| --- | --- | --- |
| `mylifegraph-gregor` | Gregor's project login | Own home and shared workspace; own public key |
| `mylifegraph-matthias` | Matthias' project login | Own home and shared workspace; own public key |
| `mylifegraph-agent` | Project automation | Own home and shared workspace; separate automation key |
| `mylifegraph-deploy` | Activate prepared releases later | No SSH login or sudo grant in this stage |
| `mylifegraph-api` | FastAPI runtime | No SSH login; private state |
| `mylifegraph-coach` | Coach executor/rootless Docker | No SSH login; private state |
| `mylifegraph-build` | Secret-free release preparation | No login, home, or supplementary groups |

Existing `ops`, `agent`, Hermes, and unrelated accounts/services are not adopted
or modified. Personal/automation accounts belong to their own primary group and
`mylifegraph-work`; deploy/API/Coach additionally join `mylifegraph-release`.
None joins `sudo`, `adm`, `systemd-journal`, or the host `docker` group.

`/srv/mylifegraph-work` is writable by the three project logins. It is not an
authoritative release directory and must contain no application credentials.
Anyone able to deploy arbitrary backend code can indirectly access its secrets;
code review and administrator-sealed releases remain necessary.

This is Unix account isolation, not a VM/chroot: shell users can read public
host information, initiate network connections, and consume shared resources.
It assumes trusted collaborators. Disabling SSH forwarding does not prevent a
shell user from implementing a proxy. A private test tunnel can still use the
existing administrative account. See [OpenSSH](https://man.openbsd.org/sshd_config#Match)
and [Docker group authority](https://docs.docker.com/engine/install/linux-postinstall/).

## Local bundle

Use a new directory outside the repository:

```bash
python3 deploy/vps/bin/prepare_access_bundle.py \
  --output /tmp/mylifegraph-access-bundle
```

Without keys this produces a review bundle: all accounts would have `nologin`
shells. For the final bundle, add the optional public-key arguments:

```bash
python3 deploy/vps/bin/prepare_access_bundle.py \
  --output /tmp/mylifegraph-access-with-keys \
  --key mylifegraph-gregor=/path/to/gregor-project.pub \
  --key mylifegraph-agent=/path/to/automation-project.pub \
  --key mylifegraph-matthias=/path/to/matthias-project.pub
```

Only plain single Ed25519 `.pub` files are accepted. Private-key files, SSH
options, multiple/duplicate keys, and arbitrary account names are rejected;
comments are stripped. Each login needs its own key. The builder cannot detect
reuse outside the project: use dedicated keys, especially for automation, and
never assign the administrative key to automation. Private keys stay on their
originating machines. No private key or password is generated or read.

Retain the printed `SHA256SUMS` independently of uploaded files. Local bundle
creation does not authorize upload or host changes.

## Administrator step after approval

Prerequisites: Ubuntu 24.04, system Python 3, OpenSSH server, sudo and standard
account utilities. No domain, Docker setup, or application credentials needed.

1. Keep an `ops` SSH session open. Transfer the approved bundle to a private
   staging directory and retain expected hashes through the local review channel.
2. As `ops`, create `/root/mylifegraph-access` root-owned mode `0700`. Copy only
   `bootstrap_access.py` and `access.json` into it with
   `sudo install -o root -g root -m 0400`. Verify hashes **after copying** against
   the independent expected values. Never execute uploaded Python as root from
   the staging/work directory. Review any existing root bundle before replacing
   it; a matching uploaded checksum file alone is not independent approval.
3. Preview with the system Python in isolated mode:

   ```bash
   sudo /usr/bin/python3 -I /root/mylifegraph-access/bootstrap_access.py
   ```

4. Review account names, public-key fingerprints, scope, and confirmation hash.
   Apply only that exact reviewed state:

   ```bash
   sudo /usr/bin/python3 -I /root/mylifegraph-access/bootstrap_access.py \
     --apply --confirm <confirmation-sha256-from-preview>
   ```

The confirmation binds host/machine, installer, keys, current project identities,
and effective SSH configuration. Do not automatically extract and apply tokens
in the real workflow: preview/review are separate steps.

Apply creates accounts/groups/homes, the workspace, root-managed authorized keys,
the receipt and a project-only SSH drop-in. It validates configuration before
enabling logins, then reloads SSH without terminating existing sessions. Effective
`ops`, `agent`, and `root` settings are compared before/after for a loopback
connection. Address-dependent policies and actual remote login require additional
verification from the real client. Existing project sudo authority blocks login
enablement. No packages, sudo grants, API/Coach services, firewall changes,
reboots, provider login, secrets, or application deployment are included.

## Acceptance and later keys

Test each enrolled key from its own client using `BatchMode=yes` and strict host
verification. Confirm identity, workspace access, sudo denial and private-path
denial. Existing application directory permissions must be audited separately.
Project logins gain no automatic system-log or credential access.

Root owns `/etc/mylifegraph/authorized_keys`; user `~/.ssh/authorized_keys`,
certificate authorities and external key commands do not grant project access.
Passwords remain locked. Missing-key accounts and runtime accounts stay nologin.

An exact repeated apply is a no-op after inspection. A later manifest may add a
previously missing key, such as Matthias', while retaining existing assignments.
The administrator copies/verifies that manifest, previews its fingerprint, and
approves the addition. Replacing/revoking keys, deleting accounts, changing roles,
and migrating old usernames are separate operations; legacy `agent`, `deploy`,
or `coach-executor` accounts are never adopted.

Account/group/key/config drift stops the installer without automatic repair.
Failure can leave new accounts/directories: review them before continuing.
Ordinary enrollment errors revert newly enabled shells/keys; an interrupted or
killed installer still requires manual inspection before any retry.
A newly created drop-in is removed if SSH validation/reload fails. No rollback
deletes users, homes, unrelated files, or services.

Continue with [VPS operations](README.md) after acceptance, reusing the exact
created identities. Only `mylifegraph-deploy` later gets the root-owned promotion
helper; developers/automation do not inherit it. Additional delegation requires
separate review, never a blanket `sudo su`, `systemctl`, Docker, Python or shell
grant. Release preparation remains an `ops` task. The administrator launches an
explicit shell as the nologin Coach UID for provider/rootless-Docker setup; no
SSH key or another user's provider credential store is copied to that account.
After a later deployment-authorization step adds the deploy sudo grant, further access
changes require a separate administrator operation: this first-stage installer
deliberately stops on any existing sudo authority, including that later grant.

## Local verification

`npm run verify:vps` includes the unit tests. The disposable Ubuntu rehearsal uses
real users, permissions, sudo and SSH with synthetic keys. Only `systemctl reload
ssh` is substituted with SIGHUP because the container has no systemd. This is not
VPS, systemd, or live-provider evidence.

Build with the narrow test directory, never a repository/secret-containing build
context. Run without network, published ports, secrets, or Docker-socket mounts:

```bash
docker build -f deploy/vps/tests/access.Dockerfile \
  -t mylifegraph-access-rehearsal:local deploy/vps/tests
docker run --rm --network none --memory 512m --cpus 1 --pids-limit 128 \
  --mount "type=bind,source=$PWD/deploy/vps,target=/input,readonly" \
  mylifegraph-access-rehearsal:local \
  /usr/bin/python3 -I /input/tests/rehearse_access.py
```

The test image downloads Ubuntu packages but installs no host binaries. Run
affected verification with the captured task base as specified in
[verification](../../docs/verification.md).
