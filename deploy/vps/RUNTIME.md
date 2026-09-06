# Runtime foundation before a public release

This stage follows [project access acceptance](ACCESS.md). It prepares the host
runtime while Caddy, FastAPI and the Coach executor remain stopped. Local bundle
preparation and a successful test rehearsal do not authorize VPS installation.
The administrator separately reviews the target preview and applies its exact
confirmation. No domain or application credentials are needed yet.

## Concrete scope

- Keep the installed Ubuntu Docker engine and all existing system Docker
  workloads. The wrapper source is pinned to that engine version; a mismatch
  stops preview. This is not an upgrade to Docker CE or a replacement daemon.
- Install only missing rootless prerequisites through Ubuntu's signed package
  repositories. Preview lists exact additions/versions. Package upgrades,
  removals and dependencies outside the reviewed allowlist are refused. No
  `apt update`, full system upgrade, reboot, or firewall change is implicit.
- Install the checksum-pinned official Caddy binary independently under
  `/usr/local/bin/caddy`. Ubuntu's default Caddy is below the repository's
  required version. No external APT repository is added. Binary security updates
  require a separately reviewed source-pin/package update; Ubuntu unattended
  upgrades will not update this standalone Caddy binary.
- Reuse the accepted project accounts. Create only the separate `caddy` system
  account/group, release directories, helper files, tmpfiles rules and held
  service definitions. Existing paths/accounts are not overwritten or adopted.
- Give `mylifegraph-coach` non-overlapping subordinate UID/GID ranges and an
  explicitly scoped `user@<coach-uid>.service` cgroup delegation. Activate only
  Ubuntu's existing `/usr/bin/rootlesskit` AppArmor profile; keep the global
  unprivileged-user-namespace restriction enabled. Other user managers and
  AppArmor profiles are not reconfigured.
- Enable linger and the **user** `docker.service` for that UID. Its socket is
  `/run/user/<coach-uid>/docker.sock`; rootless data remains in that user's private
  state. The root-owned user-manager drop-in sets the 2 GiB/2-CPU/512-task
  aggregate ceiling across the daemon and sibling container scopes. It permits no host
  loopback access through RootlessKit and exposes no Docker TCP API. Individual
  analysis jobs retain the existing stricter network/filesystem/resource limits.
- Require Docker to report rootless mode, systemd/cgroup v2, and memory/CPU/PID
  limit support. Test that API, project automation and deploy UIDs cannot connect
  to its Unix socket. Require the existing system Docker PID/state to remain
  unchanged. Failure stops/disables only the newly created Coach daemon and its
  user manager where possible; manual inspection is required after any failure.

The bundle installs **no sudo grant**, shared-provider login, Codex binary,
application secrets, release checkout, analysis image, public DNS/TLS, or app
deployment. It does not change SSH access or enable the disk timer. The supplied
global journald policy is deliberately not installed on a shared host: changing
retention for unrelated services needs its own review. The default-off executor
configuration gets its real UIDs, but API and Caddy environment files remain
absent until their configuration stage. Caddy logs no process environment.

## Build the bundle locally

`manifests/runtime-sources.json` records official source URLs and exact hashes.
Download `caddy.tar.gz` and `dockerd-rootless.sh` into a private directory outside
the repository. Do not execute a downloaded installer or put replacement
runtime binaries into the repository. The builder verifies both pinned hashes:

```bash
python3 deploy/vps/bin/prepare_runtime_bundle.py \
  --assets /tmp/mylifegraph-runtime-assets \
  --output /tmp/mylifegraph-runtime-bundle
```

The output directory must be new and outside the checkout. The builder has no
network or server operations. Preserve its printed installer and manifest hashes
independently of transport; all package files are flat, with a fixed inventory.

## Administrator preview and apply

After explicit approval, upload the bundle through the project working area.
The administrator copies its files as data into `/root/mylifegraph-runtime`,
root-owned mode `0700`, with files root-owned mode `0400`. Verify the copied
installer and `manifest.json` against the independently retained hashes before
running any package code. Do not execute root Python from a project-writable
directory or unpack an unreviewed archive as root.

```bash
sudo /usr/bin/python3 -I /root/mylifegraph-runtime/bootstrap_runtime.py
```

Review the exact machine, current identities, package transaction, subordinate
ID ranges, file destinations and service-start scope. Only then run:

```bash
sudo /usr/bin/python3 -I /root/mylifegraph-runtime/bootstrap_runtime.py \
  --apply --confirm <sha256-from-the-reviewed-preview>
```

The confirmation binds package state, identities, source bundle and relevant
host configuration. A changing package transaction or subordinate map stops
execution. There is no automatic acceptance of a new preview. The installer
uses a minimal environment and never receives app/provider credentials.

A successful completion records a root-private receipt. Repeating the exact
bundle with unchanged recorded files makes no changes; this is not a new runtime
health attestation. Changed configuration, another bundle or an incomplete prior
installation requires administrator review. Package/account/directory creation
is not transactional: failures may leave prepared files or installed packages.
Nothing automatically deletes accounts, data, host Docker, or unrelated services.

## Acceptance and what follows

After approved installation, verify rootless socket access, systemd resource
delegation and daemon restart behavior on the actual VPS. The reported Docker
capabilities are necessary but not sufficient: before any real-data Coach use,
run the existing analysis image and prove memory/CPU/PID enforcement, no network,
read-only snapshot mounts and cancellation cleanup. Confirm that the old Hermes
and Docker workloads still run. Reboot acceptance is a separately approved step.

Then continue [VPS operations](README.md): install the pinned Codex archive
through its existing dedicated installer; authenticate as the isolated Coach
UID; prepare a verified tagged release and its hash-locked Python environment;
build its revision-bound analysis image; configure the hosted data/backup and
deletion-journal prerequisites; obtain the domain; validate Caddy/TLS/CORS; and
finally promote the exact release after all gates. Never start the local
development server publicly to bypass missing pilot configuration.

The unit tests run in `npm run verify:vps`. The local Ubuntu rehearsal uses real
package binaries/filesystem operations and Caddy parsing; its service-manager,
AppArmor and Docker-capability substitutes are not evidence of a real rootless
daemon, target kernel policy, cgroup enforcement or installed VPS state. Exact
test evidence belongs in `docs/verification.md`.

To repeat the local rehearsal, build only the narrow test context and mount the
prepared bundle/tests read-only. The container has no network or Docker socket:

```bash
docker build -f deploy/vps/tests/runtime.Dockerfile \
  -t mylifegraph-runtime-rehearsal:local deploy/vps/tests
docker run --rm --network none --memory 512m --cpus 1 --pids-limit 128 \
  --mount type=bind,source=/tmp/mylifegraph-runtime-bundle,target=/bundle,readonly \
  --mount "type=bind,source=$PWD/deploy/vps/tests,target=/tests,readonly" \
  mylifegraph-runtime-rehearsal:local \
  /usr/bin/python3 -I /tests/rehearse_runtime.py
```

References: [Docker rootless prerequisites](https://docs.docker.com/engine/security/rootless/),
[rootless systemd and resource limits](https://docs.docker.com/engine/security/rootless/tips/),
[Ubuntu AppArmor requirements](https://docs.docker.com/engine/security/rootless/troubleshoot/),
[Caddy running as a service](https://caddyserver.com/docs/running), and
[pinned Caddy release](https://github.com/caddyserver/caddy/releases/tag/v2.11.4).
