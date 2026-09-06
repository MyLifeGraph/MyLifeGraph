# MyLifeGraph VPS pilot operations

This directory is the versioned, secret-free deployment contract for the
single-host pilot. It does not prove that a VPS, DNS record, certificate,
Supabase project, Codex login, or public deployment currently exists.

For initial Gregor/Matthias/automation accounts before a domain or app
installation, use [Project access bootstrap](ACCESS.md). It preserves existing
host `ops` and `agent` accounts. Linux identities are now `mylifegraph-deploy`
and `mylifegraph-coach`; the `mylifegraph-coach-executor.service`/`.socket` names
and `coach-executor-v1` protocol remain unchanged. Old host identities require a
separately reviewed migration, not automatic reuse.

After account acceptance, prepare the [runtime foundation](RUNTIME.md) locally.
Its separately approved installer adds missing rootless prerequisites, a pinned
Caddy binary and held service definitions while preserving the existing system
Docker. Only the Coach's user Docker starts; no application release or sudo
grant is installed by that stage. The root-owned user-manager cgroup owns the
aggregate resource limit, including sibling container scopes.

## Fixed runtime boundary

- `ops` prepares and seals each release directory as
  `root:mylifegraph-release` with no write bits. The release parent and atomic
  `current`/`previous` symlinks are root-owned. `mylifegraph-deploy` can invoke only the
  root-owned promotion helper; it cannot create releases, repoint links, or
  restart units directly.
- `mylifegraph-build` is a locked, no-home, no-supplementary-group account used
  only while preparing a candidate. Candidate Python, dependency tooling, and
  import smoke tests never execute as root.
- `mylifegraph-api` runs one Uvicorn worker and can read only `api.env`, the
  selected release, and its own bounded state.
- `mylifegraph-coach` runs the subscription-backed provider, owns its isolated
  Codex home and rootless Docker daemon, and can read only `executor.env` plus
  the selected release.
- `caddy` is the only public application process. FastAPI listens on
  `127.0.0.1:8000`; the executor listens on a Unix socket.
- The API and executor have distinct UIDs. The executor validates the API peer
  UID with `SO_PEERCRED`, in addition to filesystem permissions.
- The executor hides `/home` and `/root`; `/run/user` remains visible read-only
  solely so its own rootless-Docker Unix socket can be reached.
- API and executor each receive a private `/tmp`; executor turn files instead
  use its mode-0700 state directory so the rootless daemon can mount them by an
  exact host path.
- Scheduled Daily Preparation is deliberately not operated for the first
  pilot. Enabling it is a separate product/operations change.

The expected layout is:

```text
/srv/mylifegraph/
  current -> releases/v0.1.0-pilot.1-rc.1
  previous -> releases/<last-known-good-tag>
  incoming/  # root:root 0700, transport inputs only
  releases/<immutable-tag>/
/srv/mylifegraph-build/  # root:mylifegraph-build 0710, transient jobs only
/etc/mylifegraph/
  api.env
  executor.env
  caddy.env
/var/lib/mylifegraph-api/
/var/lib/mylifegraph-coach/
  codex-home/
  tmp/
/run/mylifegraph-coach/executor.sock
/opt/mylifegraph/codex/
  current -> 0.148.0
  0.148.0/bin/codex
```

## Fast path before the domain exists

The domain is not needed for repository verification, release-candidate
creation, Android signing preparation, the VPS user/filesystem bootstrap, or a
held offline candidate. It becomes mandatory for the stable app/API origins,
public TLS, CORS, Supabase Auth callbacks, the SMTP sender, CAPTCHA, and final
phone/browser acceptance.

Complete these domain-independent gates first:

1. Start from a clean commit that is intended for protected `main`, capture it
   as the task base, run the focused VPS/backup/Android/Vercel gates, and then
   run `npm run verify:affected -- --base-ref <captured-task-base>`. Do not tag
   or describe the result as deployed merely because local checks pass.
2. Keep `OPERATOR_CODEX_PILOT_ENABLED=false` in both host environment files.
   BYOK OpenAI/Gemini remains independently available; the shared provider is
   not a fallback for an invalid or absent user key.
3. Prepare a secret-free inventory naming the intended VPS, the distinct
   staging and pilot Supabase project refs, release owner, backup owner, Codex
   account/quota owner, Android signing certificate fingerprint, and the
   planned `app`, `api`, and sender hostnames. Store actual keys only in their
   protected target environments.
4. Resolve the non-domain prerequisites: an Ubuntu 24.04 host meeting
   `bin/preflight_host.sh`, a distinct pilot Supabase project with current
   publishable/secret keys, the S3 Object-Lock/KMS deletion journal, encrypted
   off-host Restic storage plus heartbeat, the private Android keystore, and
   the public-registration privacy decision. SMTP, CAPTCHA, Google OAuth, and
   their final redirects can be selected now but require the real domain for
   acceptance.
5. Record the account/terms and privacy go/no-go for subscription-backed
   Project Coach. Repository packaging is deliberately default-off and is not
   evidence that the account permits a multi-user hosted service.

After the domain is registered, follow this shortest safe order: configure
recoverable DNS ownership and the three hostname roles; finish the separate
pilot Supabase/Auth/SMTP/CAPTCHA/OAuth configuration and restore proof;
bootstrap the VPS with the shared provider still off; install and preflight the
held immutable RC; prove DNS/TLS; pass the executor-only Codex login,
permission, image, and live multi-tool smoke; enable the shared provider using
the staged sequence below; then promote the exact Vercel, VPS, and Android
artifacts and run public/physical-device acceptance. The full evidence and
stop conditions remain authoritative in
`docs/vps-pilot-release-plan.md#ordered-execution-checklist`.

## Privileged bootstrap (`ops`)

Run these steps only from a second, proven SSH session. Replace every example
identifier before use; never paste a secret into shell history.

1. Record OS, CPU, RAM, swap, clock sync, free disk, existing listeners, IPv4,
   and IPv6. Apply the owned Ubuntu security-update/reboot policy.
2. Create group `mylifegraph-release` and the runtime users above. Also create
   `mylifegraph-build` as a locked system user with home `/nonexistent`, shell
   `/usr/sbin/nologin`, its own primary group, and no supplementary groups.
   `tmpfiles.d/mylifegraph.conf` creates its separate mode-0710 workspace; the
   account cannot traverse `/srv/mylifegraph/releases` or the private incoming
   directory.
   If the access bootstrap has completed, verify and reuse those identities
   instead of recreating them. Runtime accounts have nologin shells; an
   administrator starts an explicit shell as `mylifegraph-coach` for provider
   and rootless setup without enabling SSH login.
   Give mylifegraph-deploy, API, and executor read-only membership in
   `mylifegraph-release`; do not grant any of them general sudo. Only mylifegraph-deploy
   receives the single audited promotion command from `sudoers.d/`.
3. Install the reviewed files from `systemd/`, `tmpfiles.d/`, `caddy/`, and
   `sudoers.d/` into their matching system locations. Install
   `bin/disk_monitor.sh` root-owned mode `0755` as
   `/usr/local/libexec/mylifegraph-disk-monitor`. Install `prepare_release.sh`,
   `promote_release.sh`, `health_check.py`, `analysis_image_revision.py`,
   `release_manifest.py`, `release_tree.py`, and `validate_public_origin.py`
   root-owned mode `0755` below the root-owned
   `/usr/local/libexec/mylifegraph/` directory. These installed copies, not a
   repository worktree, are the privileged promotion boundary. Replace the numeric UID
   placeholders in `executor.env` with `id -u` output; run `systemd-analyze
   verify` and `visudo -cf` before enabling anything. Enable the disk-monitor
   timer only after its first manual invocation reports valid JSON.
   Install `install_codex_cli.py` separately as root-owned mode `0555` and
   `manifests/codex-cli.json` as root-owned mode `0444` at
   `/usr/local/libexec/mylifegraph/install_codex_cli.py` and
   `/usr/local/libexec/mylifegraph/manifests/codex-cli.json`. Obtain both
   bootstrap inputs through the same independent trusted hash channel as the
   release helper suite; never install either from a deploy-writable checkout.
4. Create `/etc/mylifegraph` as root-owned mode `0751`. Install `api.env` as
   `root:mylifegraph-api` mode `0640`, `executor.env` as
   `root:mylifegraph-coach` mode `0640`, and `caddy.env` as `root:caddy` mode
   `0640`. Templates contain names and examples only.
   Before the API can start in `pilot`, create a dedicated AWS S3 bucket with
   versioning and Object Lock enabled and a dedicated KMS key. Give the API
   credential only `PutObject` access to `deletions/v2/*`, require SSE-KMS,
   COMPLIANCE retention, `If-None-Match: *`, and the expected bucket owner.
   Put the five `ACCOUNT_DELETION_JOURNAL_S3_*` values only in `api.env`; they
   must never appear in `executor.env`. Read/replay authority belongs to the
   separate restore operator and is not granted to the API process.
5. Install Caddy 2.10 or newer from its supported distribution. This minimum
   is required for the configured request-body limit. Validate with `caddy
   adapt --config /etc/caddy/Caddyfile --validate` before reload.
6. Install rootless Docker only for `mylifegraph-coach`, enable its user service
   and linger, and verify its socket is exactly
   `/run/user/<executor-uid>/docker.sock`. Do not expose a TCP Docker API and do
   not add the API user to any Docker group.
7. Download the exact Codex archive and checksum list named in the installed
   Codex manifest through a trusted `ops` session. Independently compare the
   checksum-list entry with the installed manifest, then copy the archive with
   `install -o root -g root -m 0400` into the already root-owned mode-0700
   `/srv/mylifegraph/incoming` directory. Invoke only the absolute installed
   `/usr/local/libexec/mylifegraph/install_codex_cli.py` path and pass that
   root-private archive path; there is no manifest override. The isolated
   installer pins the already-open input inode, verifies digest/archive shape,
   probes `--version` after dropping to `mylifegraph-coach`, rejects symlink or
   mutable pre-existing installs, seals the binary/version tree root-owned
   mode `0555`, and atomically updates `current`. The preceding version is
   retained for rollback.
8. As `mylifegraph-coach`, set `CODEX_HOME` to the isolated directory and perform
   the supported interactive ChatGPT login. Never copy another user's OAuth
   files. Run only the sanitized `codex login status` acceptance check.
9. Configure UFW (or the provider firewall) for SSH and TCP 80/443 only. Prove
   second-session key access before disabling password/root SSH. Port 8000
   must remain loopback-only.
10. Run `bin/verify_permissions.sh` as root. Any failed negative-access check
    is a release blocker. It resolves the actual API/executor UIDs, checks the
    configured peer and rootless-socket identities, rejects a mutable image
    override, validates the generated revision tag, and proves both runtime
    users cannot modify a release.

## DNS and HTTPS

Use `app.<domain>` for the manually promoted Vercel client and `api.<domain>`
for this service. Keep the normal project-ref Supabase URL. Point only an A
record at first; add AAAA only after IPv6 and its firewall path pass end to end.
Set `MYLIFEGRAPH_API_HOST=api.<domain>` in `caddy.env`, start Caddy, and prove:

- HTTP redirects to HTTPS;
- the certificate chain and hostname are valid;
- renewal storage is healthy;
- `/v1/health` and `/v1/ready` remain distinct; and
- browser CORS preflight and Coach SSE work through the public hostname.

The Caddy template relies on Caddy's native immediate SSE flushing and does not
enable response buffering or low-latency mode that would suppress upstream
cancellation. HSTS is intentionally absent until HTTPS and rollback have been
observed successfully; adding it is a separate irreversible-cache decision.

## Build and release flow

Only an annotated RC tag on protected `main` is a source authority. GitHub must
additionally protect the pilot RC/final tag patterns from arbitrary creation,
update, and deletion and restrict the `pilot-release` environment to those
protected tags. No second reviewer account is mandatory; creation is limited
to named release owners and the workflow's source-identity guards remain
fail-closed. These are external settings gates; the repository's tag-to-main
checks are defense in depth, not proof that signing secrets cannot reach
modified workflow code.

1. From the clean tagged checkout, run
   `bin/build_source_bundle.sh <rc-tag> <output-directory>`. It rejects a
   lightweight tag, a dirty checkout, a tag not contained in the reviewed
   `refs/remotes/origin/main`, and an output inside the repository. It never
   treats mutable local `main` as remote/protection evidence. It creates a
   deterministic Git archive and a source manifest with exact checksums.
2. Transfer both files to a private deploy staging directory. From an
   independent trusted channel, give `ops` the expected hashes. `ops` copies
   each artifact with `install -o root -g root -m 0400` into the root-owned
   mode-0700 `/srv/mylifegraph/incoming/` directory and compares the hashes
   there. Never prepare directly from a deploy-writable directory; replacing
   both archive and manifest together would otherwise bypass transport
   authority.
3. After `mylifegraph-deploy` has independently checked the transported artifacts, `ops`
   runs `/usr/local/libexec/mylifegraph/prepare_release.sh
   /srv/mylifegraph/incoming/<archive>
   /srv/mylifegraph/incoming/<manifest>`
   as root. Never run preparation from the uploaded archive or a deploy-owned
   checkout. The installed helper validates archive paths/types, extracts a new
   tag-named release, and derives the analysis-image revision with the separate
   root-owned helper. Before any candidate Python, dependency tooling, bytecode
   compilation, or app import runs, it drops to the secret-free
   `mylifegraph-build` UID with no capabilities or supplementary groups. It
   keeps archive-derived source, migrations, manifest, and generated release
   identity root-owned/read-only; only the pre-created virtualenv and detached
   bytecode cache are build-writable. Any leftover process under the dedicated
   build UID is killed and treated as a preparation failure.
   It installs the committed hashed Python runtime lock, compiles the backend,
   derives the immutable API
   SHA/tag environment from that manifest, seals a canonical full-tree digest,
   changes the tree to root-owned/read-only, and never binds the live port. The
   mutable `/etc/mylifegraph/api.env` cannot override that identity. An existing
   release is accepted only if its recorded source manifest and runtime
   identity are exact and its environment is complete.
   The systemd path is optional only so unit syntax can be verified before a
   first release exists; hosted FastAPI startup itself requires both values and
   fails closed when the generated file is absent.
   Before crossing either the Participation-RLS or Deletion-V2 migration
   boundary, prove that no older public web candidate is reachable and have
   `ops` stop the public API plus executor socket/service. An already installed
   older APK may remain on a device, so the API withdrawal and database guards
   are mandatory; Vercel withdrawal alone is not sufficient. The very first
   pilot install satisfies this only while no public client/API has ever been
   opened. Record the withdrawal before applying the migrations.

   After the additive database migrations are verified, use the tagged
   checkout's `npm run configure:pilot-participation -- --check` as a read-only
   attestation. A newly migrated database is deliberately disabled. Enable it
   exactly once with `--enable --confirm
   ENABLE:<exact-project-ref>:pilot-participation-gate-v1`, then repeat
   `--check`; the secret key stays in the protected environment. Hosted
   `/v1/ready` remains `503` until the exact project/notice contract is enabled.
   The separate break-glass rollback requires `--disable --confirm
   DISABLE:<exact-project-ref>:pilot-participation-gate-v1`; disabling the gate
   while a public client is reachable is forbidden. Keep the API withdrawn
   until the new candidate passes readiness; do not restart the old service
   after enabling the gate. If migration rollback is
   required, first withdraw every public client and API, then disable and
   attest before restoring the prior schema boundary.
4. As `mylifegraph-coach`, build the exact analysis image from that release using
   `scripts/prepare_coach_analysis_image.sh`, with the pinned rootless
   `DOCKER_HOST`. The Dockerfile uses an immutable base digest and a hash-locked
   binary-only Python dependency graph; the path-independent source revision
   must match executor capability. Release preparation writes
   `.mylifegraph-executor-release.env` with the deterministic
   `mylifegraph-coach-analysis:sha256-<revision>` tag; the helper rejects a
   conflicting override. Record the resulting image digest in the artifact
   manifest.
5. After every repository, signing, restore, provider, and permission gate has
   passed, run
   `sudo -n /usr/local/libexec/mylifegraph/promote_release.sh <rc-tag>` as
   `mylifegraph-deploy`. The helper derives the one public HTTPS origin from the root-owned
   `caddy.env`; callers cannot redirect its privileged health probe. It records
   and re-verifies the sealed candidate/prior trees immediately before it
   atomically switches `current`, restarts the narrow units,
   and checks loopback plus public release identity/readiness. On failure within
   the same irreversible database-compatibility boundary it restores the prior
   symlink, restarts, verifies rollback, and exits nonzero. If the candidate
   crosses the Participation-RLS or Deletion-V2 boundary, failure instead stops
   the units, removes the unsafe current link, and requires a reviewed
   fix-forward candidate; an older runtime is never restarted against the new
   database contract. Reopen Vercel/public distribution only after the new API,
   RLS gate, Auth, and exact release identity all pass.
6. Keep `previous` and at least one other known-good release through the
   observation window. Retain their revision-tagged rootless analysis images as
   well; switching `current` makes systemd reload that release's exact image
   identity. Never use application rollback to reverse a Supabase migration.

`bin/rollback_release.sh <tag>` is the explicit manual rollback path and has the
same health proof. It rejects a target below either irreversible hosted schema
boundary. Tags and artifacts are never moved or overwritten.

## Staged shared-provider enablement

The two committed host templates intentionally start with
`OPERATOR_CODEX_PILOT_ENABLED=false`. Enable Project Coach only after the
account/terms and privacy decisions are recorded and every preceding held-
candidate gate has passed:

1. Leave the API flag false. Install the manifest-pinned Codex CLI, authenticate
   only as `mylifegraph-coach`, build the release-bound analysis image, and pass
   `bin/verify_permissions.sh` plus the sanitized login/capability checks.
2. Set the flag to `true` only in `/etc/mylifegraph/executor.env`, restart the
   executor socket/service in a controlled maintenance window, and run the
   committed synthetic multi-tool live provider smoke as that exact user. A
   failed model, Fast, MCP, image, login, or tool-trace check returns the flag
   to false and stops this path.
3. After that direct provider evidence passes, set the flag to `true` in
   `/etc/mylifegraph/api.env`, restart the API, and verify that authenticated
   capabilities advertise `operator_codex_pilot` while core health/readiness
   remain independent.
4. Run the authenticated HTTPS/SSE acceptance turn, quota/busy/replay checks,
   and an invalid-BYOK check proving zero shared-provider dispatch before
   exposing the client artifact to participants.

Both flags must describe the same final enabled state. The API flag is the
immediate public kill switch; after setting it false and restarting the API,
stop the executor socket/service as defense in depth.

## Kill switches and expected behavior

- Shared provider: set `OPERATOR_CODEX_PILOT_ENABLED=false` in `api.env`, then
  restart the API. Core features remain healthy; Project Coach reports
  unavailable. Stop the executor socket/service as defense in depth.
- All Coach sending: set `COACH_SURFACE_ENABLED=false` in the hosted client and
  promote a new signed client artifact. Existing backend routes remain
  authenticated and fail closed by provider selection.
- Scheduled preparation: remains disabled because no scheduler unit is
  installed for this pilot.
- Full backend: stop `mylifegraph-api.service`; Caddy returns a clear upstream
  outage while Supabase-backed direct client features may continue.

Every configuration edit is followed by a controlled restart and health check.
Do not put prompts, responses, bearer tokens, BYOK headers, cookies, OAuth
state, or Supabase credentials in tickets, manifests, command arguments, or
logs.

## Operations and rebuild

- The disk timer records 70/80/90-percent thresholds. A separate off-host
  monitor must check public liveness/readiness every five minutes, TLS expiry,
  and the daily backup heartbeat; same-host monitoring is not outage evidence.
- Caddy access logs mask client addresses, strip URL queries, and remove all
  credential-bearing headers. Journald and Caddy retention are bounded by the
  supplied configuration. Never enable debug request/body logging.
- Caddy rejects bodies above 1 MiB. Hosted FastAPI then enforces separate
  readiness/read/mutation/Coach IP and verified-owner rates, concurrency slots,
  and the narrower 32-KiB Coach body cap in the single Uvicorn worker. These are
  traffic controls, not a registration limit.
- Review disk, rootless image/layer use, Ubuntu/Caddy/Docker advisories, and
  restart/OOM state weekly. Do not run blind Docker prune.
- Rebuild from the tagged source bundle, versioned host templates, independently
  retained secret inventory, and off-host Supabase backup. Reauthenticate the
  executor; never back up Codex OAuth state.
- Freeze discretionary runtime changes 48 hours before evaluation. Record the
  final SHA/tag, tool versions, image digest, APK checksum, TLS check, restore
  rehearsal, rollback owner, and known limitations in the attestation manifest.

Remote Supabase backup, deletion-journal replay, Android signing, and external
monitor setup have separate repository/runbook gates. Until those pass, these
VPS artifacts are implementation evidence, not a production-ready claim.
