# Verification And Agent Automation

Coach V4 changes require mocked provider contract tests (including
`store:false`, tool replay, invalid credentials/output, rate limits, timeout,
no fallback, parallel key isolation, pre-stream admission, durable global
budget races, and strict executor framing), Flutter credential lifecycle tests,
the local Supabase migration/pgTAP gate, and the normal affected selector. A
provider live turn, remote migration, target-host permissions, OAuth dashboard
change, hosted staging smoke, and installed-device smoke are separate evidence
and must not be inferred from repository tests.
The checked current prompt is `free-coach-agent-prompt-v5`.

This is the current runbook for choosing and running repository verification,
recording checkout evidence, understanding CI, and tracking present automation
gaps. Dated superseded results are preserved in
[Verification History](verification-history.md) with explicit historical
status; they never prove a later checkout.

Before running or claiming a gate, inspect the affected boundary and its owning
contract. Test source or a historical pass is not current evidence.

The future hosted acceptance sequence is centralized in
[VPS Pilot Release Plan](vps-pilot-release-plan.md). Its repository,
infrastructure, Supabase/Auth, provider, Vercel, Android, capacity, rollback,
and professor-handoff gates are requirements, not current pass evidence. That
future gate also requires distinct staging/pilot project identities,
publishable/secret-key compatibility, pilot-target denial in synthetic seed
tooling, and versioned 18-or-older acceptance. The local configuration and
hosted-build guards now cover the first two: pilot current-key enforcement,
exact URL/ref binding, and staging crossover denial have focused tests. Remote
key state, a confirmed remote scenario run, VPS deployment, and the hosted
shared Codex provider remain open. Repository source now contains the
default-off operator provider/executor, tagged deployment/rollback package,
signed-APK workflow, and encrypted-backup runner; none is live evidence. The
`staging-scenarios-v1` generator has
source/unit/preview coverage only. `pilot-participation-v1` /
`pilot-participation-notice-v1` adult acceptance and persistent staging
identity now exist in the working tree with focused unit/widget/source tests;
their normal-database and complete captured-base gates now pass as well. The hosted
participation browser flow and remote gates are not current baseline evidence.
The additive `pilot-participation-gate-v1` restrictive-RLS contract and its
operator check/enable tool pass source plus isolated/current local database
tests; exact enablement and attestation against the hosted project remain open.
The `hosted-database-contract-v1` source gate binds hosted readiness and VPS
promotion to the release's ordered migration-prefix head/count/digest and
derives the prepared-deletion guard from installed function definitions. Its
local unit/pgTAP evidence is not a claim about a hosted database.

## Current Verified Baseline

### Matthias project-maintainer installed (2026-09-07)

Gregor ran the reviewed administrator package with SHA256
`f022cf1d1be36bb9d29a43bfaf8860af1a4d9c2d19ea6402ec90db8fcd0b025c`.
The installer returned `state=prepared`, `rootless_docker=true`,
`project_commands=true`, `general_sudo=false` and
`application_state_unchanged=true`. In this output, prepared means the maintainer
role and development environment are installed; it does not mean the application
has been activated. The supplied output explicitly showed a fresh clone into
`/home/mylifegraph-matthias/MyLifeGraph` from the reviewed source bundle at
`9c7b399daee9bdebae647fe61ff9f46e4c3f351c`. The installer checked
Matthias's native rootless Docker socket/security options and allowed sudo status
command before reporting success. No credentials were copied.

A subsequent independent project SSH connection confirmed both installed project
entrypoints as root-owned mode 0555, `user@1003.service` active, and effective
slice limits of 4,294,967,296 bytes, `CPUQuotaPerSecUSec=2s` and 2,048 tasks.
API, executor service/socket and Caddy remained inactive. The new Docker daemon's
native check was performed by the administrator installer; this independent
unprivileged connection does not read Matthias's private home/socket.

Matthias still needs to reconnect for the new SSH forwarding policy, source his
development environment, and verify Docker/project commands from his own login.
Domain/key entry, application activation, Vercel build/connection and browser
acceptance remain his next steps. The packaged checkout and this repository's
maintainer changes have not been pushed to GitHub by this agent; installing a
Git bundle does not publish its branch or update main.

### Matthias project-maintainer preparation (2026-09-07)

Task base: `8489a0554bfe0cb62eecd5344248613d4dd3666d`. Gregor explicitly authorized
Matthias to maintain the complete project on the VPS with his agents, including
editing/testing the server checkout and project deployment/configuration. General
host administration remains excluded. Gregor confirmed that GitHub, Supabase and
Vercel access already exists and reported a successful Matthias SSH login; the
two devices have not been individually attested.

The new role prepares a private working checkout, separate rootless development
Docker, a root-controlled user-slice limit and loopback local SSH forwarding.
It delegates one fixed command dispatcher plus exact-path sudoedit for the three
project environment files. This is deliberately elevated project authority,
including runtime data/secret access through deployed code, not general sudo or
independent server-side proof that uploaded artifacts came from reviewed main.
The initial RC4 archive and application source remain unchanged. Runtime code,
rootful Docker, Coach's separate daemon, database and provider credentials are
not modified by preparation.

Read-only VPS checks found existing Git, Node/npm, Python, Docker, rootlesskit,
slirp4netns and newuidmap; Matthias already has a dedicated subordinate-ID range.
The host has 8 GiB nominal RAM and about 27 GiB free disk. Flutter/Android/browser/
Supabase SDK installation remains a user-space development task; no missing host
package or alternate infrastructure is silently installed.

Focused tests cover invalid commands/tags, exact upload checksums/limits/replay,
clean root environments, interactive setup dispatch, exact sudoedit paths,
loopback/public release checks, and atomic SSH/sudoers publication failures.
The isolated Ubuntu rehearsal uses real sudo, SSH and Git; systemd actions are
substituted and no live rootless Docker or application activation is claimed.
All seven focused tests pass. The real Ubuntu sudo/SSH/Git rehearsal passed
fixed-command authorization and denials, an editor running as Matthias, immutable
uploads, local-tunnel success, remote-tunnel denial, and checkout creation/replay
without overwriting work. The installed VPS Docker binary accepted the proposed
loopback binding flags in validation-only mode; a local Supabase gateway inspect
showed no explicit host IP, allowing that daemon default to apply. No new VPS
Docker daemon was started during these checks.

The captured-base full affected workflow passed source, Flutter analysis/tests,
1,722 backend tests with two explicit opt-in skips, isolated/current local database
checks, web build and all eight browser journeys with cleanup. Root-policy
publication failures were tested both before and after publication; API checks
cover exact release/migration identity on loopback and public HTTPS. Final docs
checks and whitespace checks pass. No application-code changes were required.

At the end of preparation, target-host installation, the actual development
daemon/resource limits and the new sudo role were still unverified. The later
administrator installation and independent readback are recorded above.

### Matthias SSH enrollment installed (2026-09-07)

The administrator supplied successful v2 preview/apply output for the prepared
two-device bundle, bound to confirmation
`5ff8b86b481640cc95d75474ed35d03801a86873a4618d4654ba4ab721e0e443`.
It adds SSH access only for `mylifegraph-matthias`, retains the automation key,
and creates no accounts or sudo grants. A subsequent independent connection
using the existing automation key confirmed Matthias's UID 1003, `/bin/bash`,
primary group plus `mylifegraph-work`, root-owned mode-0644 managed keys, and the
root-owned mode-2770 shared workspace.

Both installed public-key fingerprints match the supplied devices:

- Laptop: `SHA256:yE6ilp3Q5UxMcyRZKtb01XNDJO08D5aBhWwv2/UkHSw`
- VM: `SHA256:KTB0BfjSBl9Fx7s9o8EpJOen1LqIbgDZ2auyMmm8pT8`

The same trusted connection read the server's Ed25519 host fingerprint:
`SHA256:T3cGRrXwo6ao6ECqPGoPlvSTwyDUBtaP/IoaHoLbV+0`.
No user private key was requested, read or used. Actual login and permission
acceptance from Matthias's laptop and VM remain outstanding. No application
activation or deployment authority was added by this operation.

### Multiple-device SSH enrollment preparation (2026-09-07)

Task base: `6df56f25ab87e26ac5682021b978a4eef47c0967`. The access installer now
prepares v2 per-login key lists and reads the existing v1 manifest/receipt form.
It permits additions only, rejects duplicates across devices/accounts, binds
added device fingerprints into confirmation, and preserves existing keys and
shells on enrollment errors. Key/receipt publication is atomic; rollback attempts
all restorations and explicitly reports incomplete cleanup. Runtime identity,
sudo denial, managed SSH restrictions and the separate administrator preview/apply
boundary are unchanged. Machine-specific public keys remain outside Git.

All 14 targeted tests pass, including a pre-publication write failure,
post-publication receipt failure with exact restoration, and an injected first
rollback failure proving later restoration attempts. The isolated real Ubuntu
SSH rehearsal passes v1 receipt upgrade, both Matthias device logins, preservation
of existing logins, a later third-device addition, no-op replay, removal denial,
managed-key enforcement and sudo/account-drift denial. No user private keys or
VPS access are used by that rehearsal. Independent review of source, bundle and
administrator preview command found no remaining material finding.

The prepared files were uploaded through the existing project SSH connection to
`/srv/mylifegraph-work/matthias-access-staging/` and readback hashes matched:

- `bootstrap_access.py`:
  `2994633eac0646c51c9b4c8d7bcbb27f180d27fb470bb8671ffc98a6458f5314`
- `access.json`:
  `6c9e8aa9d042576245f88c5af564ae8930b9d5be20b7b077148ea7fd1d56f4b4`

The manifest contains the two user-supplied Matthias public keys and preserves
the existing automation key; it contains no private keys. At the end of preparation, no administrator
preview/apply had run on the VPS. That SSH read still found Matthias's
nologin shell and empty managed key file. The reviewed operator command preserves
the previous root-owned installer bundle before sealing the v2 installer and
running preview only. The captured-base full affected workflow passed source,
Flutter analysis/tests, 1,722 backend tests with two explicit opt-in skips, local
database/isolated compatibility checks, web build and all eight browser journeys
with process/user cleanup. No reset or migration apply was authorized or used against the normal local
database; compatibility checks apply schemas only in disposable isolated targets. Preparation did not claim live SSH acceptance: the
project connection then observed Matthias's nologin account and empty managed
key file; the existing automation public-key fingerprint matched prior acceptance.
The SSH configuration is not readable by that project account and was not
inspected through elevated authority. Administrative preview still checks it.

### RC4 administrator handoff (2026-09-07)

The independently reviewed RC4 completion package targets application commit
`7228d0e18d371ee6c9a0a3a25553c673df67e017` and release
`v0.1.0-pilot.1-rc.4`. The annotated tag was created locally; no remote tag
publication is claimed. The source was already on remote main before this
separate documentation handoff. The artifact remains bound to that application
revision even when later documentation commits are pulled.

Project SSH upload and readback verified
`/srv/mylifegraph-work/rc4-staging/setup.tar` with SHA256
`4dbb604dc2798ec545bc083517ce713304f464af46f79225e899415a6b8336ce`.
The archive contains eight flat regular files, sealed with an internal checksum
list plus installed helper/unit/Caddy-file expectations. The initial handoff
copy is alongside it as `README-MATTHIAS.md`; the maintained continuation guide
is now [VPS handoff](vps-matthias-handoff.md).

Real isolated Ubuntu preparation installed the locked dependencies and checked
API UID 995, Coach UID 994, immutable release ownership/tree, repeat preparation,
and preservation of the pre-existing private journal directory. The 43 existing
VPS tests and documentation gate passed. Six activation scenarios exercised real
temporary-file writes/permissions, success, rollback after promotion/Coach/partial
enable failures, and preservation of an independently replaced executor file.
A real subprocess timeout killed a TERM-ignoring descendant whose leader exited
and whose pipes were closed. Systemd, DNS, credential entry and root ownership
were simulated in the activation harness; that is not live-host activation proof.

Ten database-preflight cases passed using native Settings, the native REST
client, contract validators and real temporary journal permissions with synthetic
HTTP responses. Coverage includes invalid credentials, incompatible schema/gate,
pending deletion and unsafe journal permissions. UID and release metadata were
simulated; no real credentials or network were used in that harness. A discovered
integer-Literal parsing issue was resolved in the packaged configuration by
omitting four redundant fixed quota overrides and asserting the native defaults
of 5 per-user requests/day, 15 global requests/day, one concurrent request and a
15-second retry interval. No application-code or policy change was made.

The final independent source/archive/handoff review found no remaining material
finding. After upload, project SSH rechecked that API, executor service/socket
and Caddy remained inactive; before upload they were also disabled. The existing
Matthias account still had a nologin shell. RC3 remains the held installed release;
RC4 is staged, not installed or promoted. Domain, protected backend-key entry,
public HTTPS/readiness, boot enablement, Vercel build repair/connection and browser
acceptance remain outstanding. Installer service/configuration rollback cannot
undo database reconciliation or requests already handled by a started API.
No backup automation, model request, hosted database mutation or VPS activation
was performed during this handoff preparation.

### Optional pilot confirmation (2026-09-07)

The user authorized optional confirmation for the current small pilot. The
new `PILOT_PARTICIPATION_REQUIRED` setting defaults to true in backend/Dart
configuration; the VPS template explicitly selects false, and hosted Flutter
builds default to false for pilot and true for staging. Exact overrides pass
through Vercel's public allowlist and both Android build workflows. Read-only
participation checks and hosted API readiness require the database gate to
match the configured mode, including exact false/null/null in optional mode.

Optional confirmation removes the signup/product-access prerequisite without
recording acceptance automatically. Hosted users can explicitly confirm later
through Settings and leave the existing confirmation page without submitting.
Authentication, owner isolation, CAPTCHA, hosted guest denial, contact/HTTPS/
release validation, and account-deletion locks remain independent. Readiness
still verifies deletion recovery and the release's migration identity. No SQL,
RLS, migration or public wire-version change was needed; the remote gate was
already disabled and no remote state was changed.

Focused backend auth/readiness/configuration tests pass all 52 cases. The
complete backend suite passes 1,722 tests with two intentional provider/image
opt-in skips. Flutter's focused suite and analysis pass; the added failure
regression passes in the five-test confirmation-page suite and verifies that a
failed optional save preserves authentication and permits Back to the dashboard.
Build/configuration and documentation checks pass. Independent review found no
remaining findings after clarifying voluntary-save wording and adding that
failure regression. The captured-base full affected workflow passed source,
Flutter, backend, local database/isolated compatibility and web-build checks,
plus all eight browser journeys with fixture and process cleanup. Final
source/test/docs review has no remaining findings.

These are local implementation checks. The installed VPS remains held RC3;
optional API/client configuration is for the next release and is not yet a
claim about a running hosted app. Previously recorded acceptances are retained.

### Direct MCP database attestation after reauthentication (2026-09-07)

After native MCP OAuth reauthentication with supported scopes and a client
restart, the direct `supabase` MCP successfully queried the intended pilot
`oscrunlndfrecjilojja`. The installed hosted-database-contract RPC returned the
exact RC3 prefix and current identity: 69 migrations ending at
`20260820200000_account_deletion_replayer_role_guard_v2.sql`, SHA256
`e1c5fe56d8a359f4aa08248e5363a2cdbafd518c09e4046d48ccf1ae7f4f8ff9`,
and `prepared_deletion_pending_guard=true`. Deletion recovery reported zero
pending intents and revoked direct legacy deletion.

The participation gate is still disabled, with null project/notice bindings.
A separate aggregate read found one profile and zero current-notice acceptances.
Those reads changed nothing; no acceptance was recorded for a user and no gate
was enabled. The result accepts SQL access and the queried database contracts,
not complete API readiness. Native Vercel project/domain reads also confirmed
`my-life-graph-mu.vercel.app` as the verified domain assigned to the existing
project; no Vercel setting or deployment was changed.

### Held RC3 and VPS journal installed (2026-09-07)

PR #10's six selected required CI jobs passed; the separate migration job was
path-skipped. The user explicitly confirmed the protected fast-forward from
`18e681d2e584ea3913a79b7d87b207de883c1808` to
`bd8aac2dff01f1abcf4858c3b0db7a32e8dcc6a8`; local and remote main matched,
and GitHub marked the PR merged. The separate Vercel preview remained failed
and was outside the required status contexts. The normal source-bundle helper
created local annotated `v0.1.0-pilot.1-rc.3` from that exact main commit;
no remote tag publication is claimed.

The RC3 source archive SHA256 is
`bc827b1a47d7a51606f0f5c619dc54ddf016d80eda10aa9312d7ddaf3a3c0290`,
and its source-manifest SHA256 is
`68c3e405692104bb277cdf76d78cd1a53b79dfa227cde10a29f669ca4e2462ff`.
The independently reviewed eight-file administrator archive has SHA256
`47d158ab09da301476e43effcf80b32ffcf8599a9cf5c0a1079b3dd8613ee4f7`.
Before handoff, the final bounded Ubuntu rehearsal passed real dependency
installation, target-UID imports, release sealing, helper updates, filesystem
journal checks and initial-only replay refusal. Only systemd state reads were
substituted. Review changed directory creation to atomic mkdir plus descriptor-
based ownership/mode updates, so an intervening directory cannot be adopted,
and named the same-process retry result `fresh_writer_retry_verified`.

The administrator subsequently executed that hash-verified archive on the VPS.
The supplied output confirms held RC3 installation, runtime and fixed tool
policy under API UID 995 and Coach UID 994, and a successful `vps_file` probe.
The real API identity wrote synthetic data in a temporary child of the newly
provisioned private journal, reopened it through a fresh writer, rejected a
conflicting retry, and removed all synthetic files. No database request or
model turn was sent. The wrapper also checks project-role traversal denial,
the final release seal, absent current link and stopped application units.

Independent follow-up project-SSH reads confirmed the installed host-check
hashes match the reviewed new sources, all four application units are inactive
and disabled, Docker/Hermes/Coach user manager remain active, and the build/API
UIDs have no running processes. The project SSH identity cannot inspect the
protected release or journal directly; their acceptance above is based on the
administrator output. This accepts held installation and the tested filesystem
journal behavior, not an API HTTP start, real account deletion, restored data,
public deployment, or a new RC3 model turn. API configuration remains open;
the subsequently restored direct-MCP SQL attestation is recorded above.

### Explicit VPS file deletion journal (2026-09-07)

The user authorized the small `vps_file` pilot and accepted loss of the journal
with the VPS, while deferring AWS and backup automation. The implementation
retains the existing deletion intent/receipt/completion and reconciliation flow,
canonical V2 envelope, logical receipt key and public contracts. No migration,
new service identity, daemon or dependency is introduced. The hosted default
remains S3; the VPS template explicitly selects the private file backend.

The file writer requires a provisioned API-owned mode-0700 directory and never
creates or repairs missing storage. It writes private canonical receipts with
atomic no-overwrite publication, synchronizes the file, journal directory and
its existing parent before acknowledgement, and verifies exact retry content.
The tests cover concurrent retries, process exit before and after publication,
thread-waiter cancellation, corrupt/non-regular/symlink entries, restrictive
umask and failures at each synchronization stage. Account-service integration
proves write failures remain pending without journal acceptance or completion,
and a later retry can complete. Host preflight tests exercise both profiles and
reject missing/unsafe file storage. The recovery-page message now confirms a
durable request without claiming off-site storage; its existing widget test
covers durable pending without premature completion or sign-out.

The final backend gate passes 1,713 tests with two intentional live-provider/
real-image opt-in skips. The VPS gate passes 43 tests and the focused account
controls widget gate passes all 10 tests. The captured-base affected selector
selected the full local verification workflow, which passed source/Flutter/
backend checks, local database verification and isolated compatibility checks,
the web build, and all eight browser journeys with fixture/process cleanup.
After the review corrections, the complete backend, focused widget checks and
web build were repeated successfully. Independent review found no remaining material
issue after the neutral UI wording and additional crash/cancellation evidence.
The final documentation and whitespace checks pass.

The file profile has no WORM/off-host guarantee, automatic pruning, or supported
database restore/reopening procedure, including Supabase Auth/Data API. Existing
S3 recovery tooling remains S3-only. This section records local implementation
checks; the subsequent main update and held RC3 installation are accepted above.
No remote migration, API activation or new model turn is claimed.

### API configuration preflight, not started (2026-09-07)

Direct Supabase MCP project-URL reads verified the intended pilot target as
`oscrunlndfrecjilojja`; the connector named `supabase_pilot` instead points to
staging `kvdunemnuqcvbhrlfnsh`. Connector names are not environment authority.
The pilot's migration-list call returned 69 entries ending at
`20260820200000_account_deletion_replayer_role_guard_v2.sql`, the same count and
last identity as the RC2 source. SQL-based checks failed with `Insufficient
scope`, so current participation-gate, deletion-recovery and installed runtime
contract attestation remain unverified. A matching migration-list head/count
is not a substitute for those checks or the ordered-identity digest.

Source inspection of RC2 confirms hosted API composition constructs the S3/KMS
journal writer during startup, and its lifespan reconciles Coach and deletion
state. Starting it against the real database is therefore not a read-only
connection probe. A secret-free configuration draft has the verified project
refs; credentials, journal destination and real origin are unresolved. No API
start, database change, AWS provisioning or backup configuration occurred.

### Single model turn through the RC2 service accepted (2026-09-07)

After the internal control-path acceptance, the user authorized one synthetic
model turn through that service. The new administrator handoff archive has
SHA256 `cd00a222bcb7ab41db8a942cb7dfcfd2ae615d617afa96f4dcbeda28ce8a9e34`.
It reuses the held RC2 service override and the prior direct-test fixture,
executes the actual socket client as API UID 995, and permits one execute frame
without retry. It checks the returned model identity when present, reply,
three completed data tools, snapshot integrity and cleanup. The pinned model
configuration does not independently identify a model when `model_reported`
is null.

The new client passed real local Unix-transport rehearsals against a fake
provider for success, provider failure, invalid trace and cancellation, with
exactly one execute and empty client/executor temporary directories each time.
Wrapper success and injected start/API/stop failures passed with substituted
systemd/host reads. Real dummy process groups exercised both graceful and
forced termination after a client timeout. No real model was called during
these local checks. The target's normal 180-second model limit remains;
the temporary service lifetime is 240 seconds and its API probe has a
210-second process-group watchdog plus a 10-second kill grace period.

Cleanup checks stopped services, removed runtime configuration, unchanged
persisted configuration and release link, absent analysis containers and restored
application temporary-directory entry sets. This does not claim removal of
native CLI cache or OAuth helper state.

The administrator subsequently ran the hash-verified archive on the VPS.
The supplied output reports `passed` for exactly one execute request through
the real service, with all three tools (`inspect_data`, `query_data`,
`run_python`) completed, three trace rows and a 994-character reply. The fixture
was synthetic, its snapshot was unchanged, and API temporary-file removal
passed. Configured model was `gpt-5.5`; `model_reported` was null, so the result
does not independently confirm model identity or delivered service tier.
Cleanup reported no failed checks: analysis containers and application temporary
files were cleared, the runtime override removed, services stopped and persisted
provider enablement left false.

Independent follow-up project-SSH reads confirmed API, executor, socket and
Caddy inactive and disabled with empty `DropInPaths`, the runtime override
absent, Docker/Hermes/Coach user manager active, no API-UID processes and only
the pre-existing user-manager/rootless-Docker processes under Coach UID 994.
This accepts one synthetic live turn through the installed systemd executor,
its native Codex/MCP path and isolated analysis tools on this machine/account.
It does not accept API HTTP/persistence, durable quotas, public TLS/browser
operation or general response quality. No extra model turn was sent during
follow-up checks; backups and domain setup remain deferred.

### Internal RC2 executor service accepted (2026-09-07)

The user authorized an internal systemd/socket test while deferring backups
and domain setup. Fresh project-SSH inspection found the API, Coach executor,
executor socket and Caddy inactive and disabled, with the installed executor
unit/socket matching the repository definitions. No service was started by
that inspection.

The administrator handoff temporarily selects the sealed RC2 release through
an override below `/run/systemd/system`, preserving the installed service
sandbox. It enables the executor only through a temporary environment file,
uses the actual API adapter as UID 995 to trigger socket activation and check
readiness, reserve/busy/release and malformed-request rejection, and checks
API denial of the analysis socket plus automation/filesystem and Coach/peer-UID
denial of the executor socket. No execute frame or model turn is sent. Cleanup
attempts both stops, override removal, unit reload and unchanged-state checks
even after a probe or cleanup-step failure. The persisted environment and
public release link are not changed; this is not an API or public deployment.

All 11 existing executor tests passed with local Unix-socket I/O enabled. The
new API probe also passed against the real local protocol server with a fake
provider; target UIDs and Docker-socket denial were simulated in that rehearsal.
Success, start failure, API failure, peer-probe failure and socket-stop failure
were exercised with real temporary override files and substituted manager/host
reads. Cleanup continued after the injected stop failure and reported failure
rather than claiming successful restoration. Those local rehearsals alone do
not prove the target host's systemd execution.

The administrator subsequently executed the independently reviewed handoff
archive with verified SHA256
`4cc2638b3441d1c3d18e755059a9ca9f9a1c3746a0b258291f66b7d3799f9868`.
The supplied output reports successful socket activation of the actual service
under Coach UID 994 and `ready` through the API adapter. Busy rejection,
reservation release, malformed-request rejection, API denial of the rootless
Docker socket, wrong-peer-UID rejection and automation socket denial all passed.
Cleanup reported no failed checks, removed the runtime override, stopped the
services and verified persisted provider enablement remained false. No model
request was sent.

Independent follow-up project-SSH reads confirmed all four application units
inactive and disabled with empty `DropInPaths`, the temporary override directory
absent, and system Docker, Hermes and the Coach user manager active. Only the
existing user-manager/rootless-Docker processes remained under Coach UID 994.
This accepts the installed systemd activation, control protocol, native readiness
and tested access boundaries. The subsequent synthetic model turn through
systemd is accepted above. API persistence and quotas, browser/TLS and public
deployment remain separate acceptance steps. Backups and domain setup are
still deferred by the user.

### Authenticated RC2 Coach smoke on the VPS (2026-09-07)

The administrator ran the independently reviewed readiness probe as Coach UID
994 against the installed RC2 runtime and protected executor configuration.
It reported `ready`, CLI `0.153.4`, configured model `gpt-5.5`, and persisted
provider enablement `false`, without sending a model request. Only native CLI
status was inspected; no raw OAuth state was exposed or copied by the diagnostics.

The administrator then ran the root-sealed live probe with SHA256
`f97a9f692268f6f892da346138ea73da72e2f760f08cd69a29dc6907116de754`.
Its supplied output reports `passed` for one direct Coach turn using only
synthetic data, bounded to 180 seconds. All three tools (`inspect_data`,
`query_data`, `run_python`) completed, producing three trace rows and a
1,149-character reply. Snapshot integrity, analysis-container cleanup and
temporary-file removal passed. GPT-5.5 and Fast were explicitly configured;
`model_reported` was null, so there is no independently reported model identity
or service-tier confirmation. The probe enabled dispatch only in memory;
persisted provider enablement remained false.

Subsequent independent project-SSH reads confirm API, executor, executor socket
and Caddy inactive, system Docker and Hermes active, and no remaining Codex
process under the Coach UID. This accepts the direct authenticated provider/MCP
path for this machine/account and fixture. It does not accept the systemd
executor/socket path, API persistence or quotas, public TLS/browser flow,
general response quality, or shared-account policy. Those release gates remain
separate; no second live turn was sent during the follow-up verification.

### Held RC2 installed with tool policy (2026-09-07)

PR #9's required CI completed with five successful jobs and two path-selected
skips; the user confirmed the exact protected fast-forward to
`18e681d2e584ea3913a79b7d87b207de883c1808`. Local annotated tag
`v0.1.0-pilot.1-rc.2` identifies that source. Its archive SHA256 is
`3719cbe717c0d3a6561fd052875d865f4e40d8524765c28b4f19162ba949f0c4`;
the source manifest SHA256 is
`526f0d63cc2ede53cbadbcf274c6f5954d3b1012a3e044b17110a49f61d13e5e`.
No remote tag publication is claimed.

The administrator ran the independently reviewed, root-sealed RC2 package on
the VPS after verifying its outer SHA256
`47559444e94e106f6c684768149f3b4df42edf08fe5f4aaf899c3601531daa16`.
Its output confirms source/helper hashes, real locked dependency installation,
the held release at `/srv/mylifegraph/releases/v0.1.0-pilot.1-rc.2`, and runtime
imports plus the fixed tool-policy hash under both API UID 995 and Coach UID
994. The root script's final seal and stopped-service checks passed; it did not
switch `current` or modify RC1. These privileged results come from the supplied
administrator output; the project SSH identity cannot traverse the release tree.

Subsequent independent project-SSH reads confirm API, executor, executor socket
and Caddy inactive, system Docker and Hermes active, Codex `current` at 0.153.4,
and no remaining build-UID process. This accepts the installed held candidate
and policy readability, not an authenticated provider turn or public release.
Login and direct live model/tool/event acceptance were subsequently exercised
in the scoped smoke above. Account/terms and privacy decisions, domain/TLS and
other public-release gates remain separate.

### Codex Coach tool authority (2026-09-06)

Task base is `fbdf39500bd55ba9c4f8cc002bdf583e6c0cd6f2`. The VPS has the
installed CLI 0.153.4 but its application/provider remain held. An actual CLI
run against a simulated loopback Responses endpoint inside a networkless
container exposed the old configuration's built-in apply-patch, search,
request-input and resource tools; the three data tools were deferred behind
tool search. No account, real model request or personal data was involved.
Exact-source review rejected PreToolUse hooks as a hard boundary because
failure cases can continue execution and CLI JSONL omits hook lifecycle events.

The implemented adapter uses the complete selected upstream GPT-5.5 metadata
with only its apply-patch/shell/tool-search fields changed and its empty
experimental-tool list retained. Its fixed hash is verified before readiness
and every dispatch. Actual data-agent wire capture from the implemented adapter contains
exactly the three data tools plus three resource helpers, with file editing,
web search, planning and user-input tools absent. The metadata's static model
manager prevents remote refresh from restoring those fields. The three resource
helpers remain visible, but the sole Coach server rejects all resource methods;
the event allowlist has not been expanded.
A separate actual wire capture for the implemented legacy response path
contained no model tools, preserving its no-MCP behavior.

Focused provider/MCP verification passed 100 tests with one intentional
real-image opt-in skip. New checks cover upstream metadata preservation,
missing/tampered/symlink/oversized/FIFO profiles, cached-readiness invalidation,
and hostile resource methods including a host-file URI with no file, snapshot,
trace or data-tool effects. The captured-base selector chose Source and Backend;
both passed, including 39 VPS tests, 16 backup tests and 1,691 backend tests with
two intentional skips. It did not select Flutter, Database or Browser for this
backend-only change. Documentation/diff checks also passed. This
implementation is local; it has not changed the immutable installed RC, started
the provider or authenticated Codex. Live response/event acceptance remains open.

### Requested Codex CLI 0.153.4 upgrade (2026-09-06)

Upgrade base is `15b6b6c66ca44d3a1b655edee36b84c7d79d6f46`, the local
package-installer fix; protected `main` and the installed held RC still identify
`73206e7aeb96fef018e86f54be5522a209fb7339`. The user requested the newest stable
CLI before installing 0.148.0. Official release metadata identifies 0.153.4,
published on 2026-09-04; its asset digest, official checksum-list entry and
downloaded x86_64 musl archive match
`a822187e1a2420c61c5926721bfbd878701ed95547c9bb0d4de4498a16ba1821`.
The complete layoutVersion1 package shape is unchanged. Manifest, executor
version pin, current examples and pin-specific tests now agree on 0.153.4;
generic version-validation fixtures and prior evidence retain their original
versions. The explicit Coach model remains `gpt-5.5` with Fast mode.

All 39 VPS tests and Ruff pass. A networkless Ubuntu check installed the actual
package twice under the isolated Coach UID for its version probe. Actual global
help, exec help and feature output pass the existing provider compatibility
parsers; its generated exec argv parses and its MCP configuration is accepted.
Inspection subcommands omit the exec-only `--strict-config` flag. The effective
feature view retains `unified_exec=true`, while `shell_tool=false` prevents
shell/unified-exec registration in the exact-tag source. Other non-removed
features are disabled except Fast. This is not proof of an exclusive three-tool
model surface: model-driven ApplyPatch and MCP-resource handlers are also
registered, as they were in 0.148.0. Do not enable the provider until that
existing integration gap has a proven control and live acceptance; event
rejection is unchanged. Full verification against the upgrade base passed:
39 VPS and 16 backup tests, 1,057 Flutter tests, 1,683 backend tests with two
intentional skips, Web, 24-file/486-assertion final-state pgTAP on isolated
PG15/PG17 and the normal local database, and all eight browser journeys without
retries. Documentation/diff checks pass as well.

The concrete root-sealed handoff was rehearsed with the actual package in a
networkless Ubuntu container: unexpected executor configuration drift was
refused before replacement, old files were backed up, and only the expected
CLI version changed in the preserved executor configuration. That wrapper's
systemd state reads were substituted in the container; real VPS state remains
separate evidence. Independent source/handoff review passed. The six-file
flat bundle is staged on the VPS and its outer transport hash matches
`77516d216ceeb783424749a65493fdd8570e55e6006ee4bfb3dbdf8d94dca55b`.
The administrator subsequently ran that exact package successfully: archive,
payload and prior-state hashes passed, Codex 0.153.4 installed, and the executor
version pin updated. Independent project-SSH reads confirm `current` points to
`/opt/mylifegraph/codex/0.153.4`, the version directory/main binary/code-mode
host are root-owned mode `0555`, and package metadata is root-owned `0444`.
Installed helper and manifest hashes match the reviewed inputs. API, executor,
executor socket and Caddy remain inactive; system Docker and Hermes remain
active, with about 27 GiB disk space free. The privileged installer output is
the evidence for its version probe/configuration update; the project SSH user
cannot independently read the protected executor environment. No OAuth login,
provider call or application activation is claimed. The tool-surface acceptance
gap above still blocks provider enablement.

### Codex package installer correction and VPS analysis acceptance (2026-09-06)

Task base is `73206e7aeb96fef018e86f54be5522a209fb7339`, the clean protected
`main` result of PR #8. Its complete manual CI passed all seven jobs; regular
PR CI passed its five selected jobs and legitimately skipped Web/Database.
The exact fast-forward succeeded after PR checks appeared in GitHub's rollup.
The manual run alone had been rejected by branch protection despite passing;
the manual-CI promotion instructions below are not proof of GitHub acceptance.

The user installed the local annotated RC `v0.1.0-pilot.1-rc.1` from that SHA
on the VPS through independently checked root-private source inputs. The
administrator-run analysis acceptance then passed final-path API/Coach imports
(UIDs 995/994), the release-bound rootless image build and synthetic MCP checks.
The image revision is
`4d47a6a1688e4706587f85027a6ebc35a98041e4a15b9b92aa7401e11c067ca9`;
its host-local image ID is
`sha256:6179930c000bc64ff45f131713fb768af13e1b34173b9152e5204200161bd245`.
Observed limits were 512 MiB memory, no swap, one CPU and 64 PIDs, UID 65532,
no capabilities, no-new-privileges, loopback-only networking and a read-only
root/snapshot. Host-file/environment access and a network connection were
denied; the snapshot stayed unchanged. Synthetic error and actual 30.3-second
timeout cleanup left no analysis containers. Final release-seal verification
passed; API, Coach executor and Caddy stayed stopped. These are scoped host
acceptance results, not memory/PID exhaustion, reboot, provider or public tests.

The subsequent genuine Codex archive rehearsal exposed a pre-existing installer
defect: the pinned `0.148.0` archive contains a package, not a standalone binary.
The correction on `fix/vps-codex-package-installer` retains the exact version,
archive checksum and manifest authority, validates the full fixed package and
metadata, and verifies every installed file before accepting a repeated install.
Four focused package tests and Ruff pass. A networkless Ubuntu rehearsal with
the actual official archive passed installation, the unprivileged exact-version
probe, repeat integrity and restrictive `umask 077`. Sidecar-only tampering was
rejected with the main binary and `current` symlink inode unchanged. The empty
probe home uses a disposable root-created `/var/lib` tree to satisfy Codex's
PATH-helper rules without touching real OAuth state. Independent review passed
after that correction. The full affected gate against the task base passed:
39 VPS tests, 16 backup tests, Flutter's 1,057 tests, FastAPI's 1,683 tests
(two intentional skips), Web, the 24-file/486-assertion final-state pgTAP suite
on isolated PG15/PG17 and the normal local database, and all eight browser
journeys without retries. No reset or remote migration ran. The corrected
installer is staged but has not been installed on the VPS; no login has occurred.

### Release candidate and local analysis image (2026-09-06)

The reviewed access/runtime work is committed locally as
`70fddd6d24a8cd0a1692da127181df82a00766a0` on `setup/vps-project-access`, based on
`3693aeca71f78b9805c9fb953f0c58541d522981`. The independent candidate review found
no source blocker; two stale documentation statements were corrected before
commit. Runtime/application code is unchanged from the completed Full run
recorded below. This follow-up runs Docs/diff hygiene and explicit real-image
checks rather than repeating unchanged broad product suites.

The existing image preparation script built the source-bound local image with
revision `4d47a6a1688e4706587f85027a6ebc35a98041e4a15b9b92aa7401e11c067ca9`.
Its local Docker image ID is
`sha256:f58b777c46f7faedf2590a644106f4b5d1d8c1d8af80a40a2b1bedf8fc6aee3c`;
this is an image ID, not a published registry-manifest digest or RC artifact.
The existing opt-in real-image pytest passed (one test): synthetic snapshot
queries succeeded, snapshot/host-file writes or reads were denied as appropriate,
the host environment was absent, networking was inaccessible, and cleanup passed.

A supplemental real-container probe through the existing MCP executor observed
UID 65532, zero effective capabilities, `NoNewPrivs=1`, a read-only root mount,
only the loopback interface, `memory.max=536870912`, `memory.swap.max=0`,
`cpu.max=100000 100000`, and `pids.max=64`. Synthetic error cleanup passed; an
actual endless program hit the host's 30-second deadline in 30.21 seconds and
was removed. The snapshot remained unchanged and no analysis test container
remained. This is local Docker evidence, not VPS rootless-container, provider,
reboot or public-release acceptance; memory/PID exhaustion stress was not run.

Read-only GitHub inspection found `main` still at the base commit above, with
all seven required CI checks, strict status checks and administrator enforcement;
force pushes/deletion remain blocked and PRs are optional. No repository ruleset
was returned, and the required `pilot-release`/`pilot-backup` environments were
not present in the environment listing. Their release-authority configuration
must be completed separately before those protected release operations.
The working branch has not been pushed and no candidate CI run or RC tag/source
bundle is claimed. The official source-bundle helper still requires an annotated
tag on the exact clean commit contained in reviewed `origin/main`.

### Runtime foundation host acceptance (2026-09-06)

The user applied the independently reviewed, root-sealed runtime package on
`openclaw-01`. Installer SHA256 was
`5de96e256726ad56166ed8a7de83fc067e454f1f457d0df4e446af9fb1071bc7`;
the copied manifest SHA256 was
`27547dc00a2e98e31bec96629c9bfb58a66b59e0f50d08750c8b976766129cef`.
The installer reported successful completion after its rootless/cgroup capability,
socket ownership, API/deploy/automation socket-denial and existing-Docker checks.
Those installer checks are distinguished from the subsequent direct SSH evidence.

Read-only verification as `mylifegraph-agent` independently observed Caddy
2.11.4, the existing system Docker still active at PID 1200, and Hermes active.
The Coach user manager was active with `MemoryMax=2147483648`,
`CPUQuotaPerSecUSec=2s`, and `TasksMax=512`. Its kernel cgroup files contained
`memory.max=2147483648`, `cpu.max=200000 100000`, and `pids.max=512`, with
`cpuset cpu io memory pids` available. The running rootless dockerd PID 451065
belonged to `/user.slice/user-994.slice/user@994.service/app.slice/docker.service`,
beneath that limited manager. Its user-namespace maps bound inner UID/GID zero
to host UID 994/GID 980, with the remaining 65,536 IDs starting at 427680.
The project automation socket connection raised the expected `PermissionError`.

Caddy, API, Coach executor/socket and disk-monitor timer were all inactive and
disabled. No HTTP/HTTPS or public Docker listener appeared; SSH and the existing
loopback listeners remained. About 6.6 GiB RAM was available. The independent
review accepted this scoped interpretation and requested the daemon cgroup
membership check, which then passed.

This accepts installed runtime foundations and configured aggregate kernel
limits, not a complete application release or stress proof. Real analysis-image
execution, per-container resource/network/filesystem isolation, cleanup,
daemon restart/reboot, provider login, deployment and TLS acceptance remain
open. This follow-up changes evidence documentation only; Docs and diff hygiene
cover it, while the prior Full run covers unchanged runtime/application code.

### Runtime foundation preparation (2026-09-06)

The runtime follow-up retains task base
`3693aeca71f78b9805c9fb953f0c58541d522981`. Read-only VPS inspection confirmed
the existing Ubuntu Docker engine and an APT simulation with six additions,
zero upgrades, and zero removals. No runtime package was applied during that
local preparation phase; the later host acceptance is recorded above.

An independent review/fix/retest loop corrected the rootless executable PATH,
aggregate limits on the root-owned user-manager cgroup, post-APT venv probing,
explicit permission-denial detection, startup cleanup coverage, child daemon
notification and user D-Bus dependencies. The final independent source review
reported no remaining material finding. Local Ruff, 35 VPS tests and the
Ubuntu installation rehearsal passed. The rehearsal verifies actual account/
file permissions, pinned Caddy parsing, preview/stale-confirmation behavior,
held application files, socket denial and exact no-op replay. Its kernel,
AppArmor, service-manager and Docker-capability substitutes do not prove live
rootless startup or cgroup enforcement; those remain target-host acceptance.

`RESET_DB=false APPLY_MIGRATIONS=false npm run verify:affected -- --base-ref
3693aeca71f78b9805c9fb953f0c58541d522981` selected Full and passed on the corrected
source: Source/Docs/Visual, 35 VPS tests, 16 backup tests, Flutter analysis and
1,057 Flutter tests, FastAPI Ruff and 1,683 tests with two intentional skips,
the Web build, isolated migration/restore/replay checks, and all eight browser
journeys without retries. The 24-file/486-assertion pgTAP corpus passed on both
pinned majors and the normal local database. Normal migration history matched;
no reset or normal-database migration was performed. Browser test-user/process
cleanup completed. The final evidence-only documentation update is checked with
Docs and diff hygiene separately. This is runtime preparation evidence only;
public services, provider login, release installation and remote resource
enforcement are not claimed.

### Project VPS access acceptance (2026-09-06)

After local preparation below, the user separately approved the package upload
and ran the root-sealed preview/apply on `openclaw-01`. The applied installer
SHA256 was `ea549cba80e2997ca1a884ccda8642a6e0a0ba373652b22a096d5d2b4282c0c0`.
This supersedes the preparation-only host status for the access stage, not the
application release gates.

A subsequent real SSH connection authenticated as `mylifegraph-agent` using
its dedicated key with `IdentityAgent=none`, `IdentitiesOnly=yes`,
`BatchMode=yes`, and strict known-host verification. The observed UID was 1004,
with only its primary group and `mylifegraph-work` supplementary membership.
Create/read/delete of an exact temporary workspace file passed and left no file.
Noninteractive `sudo true` was denied. Directory traversal was denied for
`/root`, the existing `ops`/`agent` homes, both personal project homes, and the
API/Coach/deploy private state directories. Writes to the root-managed agent
authorized-key file, project SSH configuration, and host Docker socket were
denied. An SSH attempt to `ops` using only the project key was denied.

All seven project accounts were visible through NSS. Gregor, Matthias, deploy,
API, Coach, and build retained `nologin`; only project automation had a Bash
shell. Both `hermes-gateway.service` and `ssh.service` reported active. These
are scoped access checks, not a complete audit of other applications or proof
of VM-like isolation. No package installation, application service, domain/TLS,
provider login, rootless Docker setup, or deployment permission is claimed.
Only the documentation evidence changes in this follow-up require Docs and
diff hygiene; the previously completed Full run still covers unchanged code.

### Project VPS access preparation (2026-09-06)

This task captured clean base `3693aeca71f78b9805c9fb953f0c58541d522981`.
The initial project-account bootstrap work was local preparation only. Its separate disposable
Ubuntu 24.04/OpenSSH rehearsal passed preview non-mutation, stale-confirmation
denial, real per-user SSH login, private-path/managed-key boundaries, sudo
denial, no-op replay, later Matthias key enrollment and account-drift refusal.
The rehearsal substitutes only SSH service reload with SIGHUP; it does not prove
VPS/systemd installation, provider access or public deployment. The actual VPS
was not changed during that preparation phase; subsequent access acceptance is
recorded above.

`RESET_DB=false APPLY_MIGRATIONS=false npm run verify:affected -- --base-ref
3693aeca71f78b9805c9fb953f0c58541d522981` selected Full and passed: source and
documentation/visual gates, 25 VPS tests, 16 backup tests, Flutter analysis and
1,057 Flutter tests, FastAPI Ruff and 1,683 tests with two intentional skips,
the debug Web build, and all eight browser journeys without retries. Normal
local migration history matched; no reset or normal-database migration was
performed. Isolated migration/restore/replay gates and the 24-file/486-assertion
pgTAP suite on both pinned majors and the normal local database passed. Browser
test-user and process cleanup completed. The final evidence-only edit to this
document is checked separately with Docs and diff hygiene.

### Scoped simplification (2026-09-05)

This task captured clean base `6384f8a7372364bd86de2b1e3bd774aa17dee13f`
and prepared its code candidate at
`e75125dc81f708c3725636d5afff12e16151d328` on
`simplify/maintenance-and-verification`. The seven bounded fixes and subsequent
Settings-copy correction each completed independent read-only review; review
findings were corrected and reviewed again before their local commits.

`RESET_DB=false APPLY_MIGRATIONS=false npm run verify:affected -- --base-ref
6384f8a7372364bd86de2b1e3bd774aa17dee13f` selected Full and passed:
Flutter analysis and all 1,057 Flutter tests; FastAPI Ruff and 1,683 tests with
two intentional skips; the shared source/documentation/visual gate; and the
debug Web build. The first Full attempt found one Account Controls assertion
affected by unnecessarily reworded budget help. The correction preserved the
original truthful wording, removed only the obsolete marker promise, and added
focused assertions before the successful complete rerun.

Normal local history matched all 69 repository migrations. No migration was
applied to, and no reset performed on, the normal local database. The separate
Goal, Exam Health, Multi-Exam, and pinned PG15/PG17 transition checks passed.
The complete pgTAP suite passed 486 assertions in 24 files on each pinned major
and the normal local database; the PG17 owner/ACL restore and deletion replay
also passed. Browser run `20260905T070556Z-1355173` passed all eight journeys
without retry and completed run-owned Auth and process cleanup.

These results supersede the earlier dated entries below for this code
candidate. They are local evidence, not hosted CI, remote migration, provider,
or deployment evidence. The final baseline-only documentation update is
verified separately with Docs and diff hygiene.

### Targeted maintenance (2026-09-04)

This task captured clean base `71164bb28b13bb5c361af3c466c6f76c00169203`.
Its working-tree changes share the local/CI source gate, correct Planner
timezone display/input/conflicts, retain visible Assignment Series exact
recovery, and translate Deadline-source Planner conflicts. Each code package
has passed a separate independent review and its focused diagnostics. On
2026-09-04, `npm run verify:affected -- --base-ref
71164bb28b13bb5c361af3c466c6f76c00169203` selected and passed the Full lane:
Flutter analysis and all 1,115 tests; FastAPI Ruff and 1,683 tests with two
intentional skips; the shared source/documentation/visual gates; and the debug
Web build. An initial Fast attempt found a banned phrase in an internal code
comment; its comment-only correction and the complete Full rerun passed.

The normal PostgreSQL 17 migration history matched all 69 repository versions;
no migration or reset was performed. Pinned isolated PostgreSQL 15 and 17
full-chain checks and the normal database each passed 486 pgTAP assertions in
24 files, including the new cap/replay fixture. The PG17 owner/ACL-preserving
restore and deletion replay also passed. Browser run
`20260904T213333Z-1058142` passed all eight journeys without retry and completed
all run-owned Auth and process cleanup. This is evidence over the local
uncommitted candidate, not a release or deployment. Earlier dated runs below
do not prove these changed files.

The direct project-scoped Supabase MCP was used for read-only checks on
`oscrunlndfrecjilojja`: its 69 listed migration versions exactly match the
repository through `20260820200000`. The Security Advisor reports one warning
for [disabled leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
The Performance Advisor reports 16 legacy CamelCase RLS-initplan warnings,
29 unindexed-foreign-key notices, and 70 unused-index notices. These notices
are not a measured query-performance regression or permission to change indexes.
The MCP table summary reports RLS enabled for all 66 listed public tables;
that flag alone does not prove row isolation or least-privilege grants.
The MCP refused the aggregate SQL inspection with `Insufficient scope`, so
matching migration identities do not attest live function bodies or grants.
The separate staging target was not inspected through this project-bound MCP;
no Vercel MCP was available to inspect current deployments. No remote mutation,
deployment, provider call, or credential retrieval was performed by this task.

### Earlier recorded evidence

The preceding Vercel-build-fix candidate's task base was
`3def90d2ed84b0c22c2541329077c8a012c3c3dc`, the protected-`main` result after
PR #3 removed the standing external-account approval requirement while
retaining the technical branch protections. That base contains the reviewed
promotion merge `f9198ce2a9560916e8d3c440ea31a6097a651fef` plus the bounded
Supabase-runner diagnostics, image-identity fixes, and checkout-complete CI
toolchains, including the shared exact ECR/GHCR allowlist for validated running
and explicitly requested isolated Postgres images, and pins every Android CI,
staging, and release workflow to guarded Java 21. It also removes the optional
`rg` runtime dependency from database harness error, role, archive, and source
classification in favor of baseline `grep`. The post-base correction makes
fresh database CI fetch both pinned PG15/PG17 compatibility images before the
gate instead of relying on the normal stack's different PG17 image. The
promotion merge integrates
GitHub `main` commit `87277e704f318bc569d12c88d665759a22eda2f1`
without rewriting either history. Its captured-base selector chooses the Full
lane. The complete captured-base Full selector passed on 2026-08-21: Flutter analysis passed with
1,100 tests, FastAPI Ruff passed with 1,681 tests and 2 intentional skips, and
the debug web bundle built successfully. The source group in the same Fast run
passed the documentation, visual, E2E-split, VPS, backup, Vercel, Android,
Turnstile, staging, participation-operator, and local-safety gates. The normal
PostgreSQL 17 migration history already matched all 69 repository migrations;
the run neither reset the database nor applied SQL. The Database gate passed
against that normal PG17 state and the pinned isolated PG15/PG17 full chains,
including the PG17 owner/ACL restore and deletion replay. Full selector browser
run `20260821T150712Z-550816` passed all eight independent UI journeys without
retry and with exact run-owned Auth cleanup. This is a pass over the local
merge candidate selected from the captured base, not a tagged or deployed
release identity.
The Vercel fix's captured-base selector again chose the Full lane and passed on
2026-08-23. Flutter analysis and all 1,100 tests passed; FastAPI Ruff and all
1,681 tests with 2 intentional skips passed; documentation/source guards, the
debug Web build, the normal PostgreSQL 17 history, pinned isolated PG15/PG17
chains, restore/deletion replay, and all database assertions passed. Browser
run `20260823T164225Z-1487184` passed all eight independent journeys without
retry and removed every run-owned Auth identity. This local evidence includes
the SHA-bound hosted identity change and the Vercel build-user tool-trust fix;
it is not by itself a successful provider deployment claim.
GitHub PR #2 then ran all seven protected required checks against source head
`76fa77097dfae53b7d571523b262a8c96acc7ead` in Actions run `32496871368`:
classification, documentation/visual contracts, Flutter/Android, complete
FastAPI, debug web, fresh migrations/pgTAP, and full browser E2E all passed.
The PR merged normally without an administrator bypass on 2026-08-23, producing
protected `main` commit `f1556bc7a4aac8d0d00228428e9f05e668fb0671`.
PR #3 then produced protected `main`
`3def90d2ed84b0c22c2541329077c8a012c3c3dc`. The linked MyLifeGraph Vercel
project's Production deployment `dpl_9KsQf5crXUpQuF18TEAEXvqrjWoy` failed
before Flutter with the filtered provider error
`system tool ownership is invalid: node`. The repository check had incorrectly
required root ownership even though Vercel's version-managed Node binary is
provider-owned rather than root-owned. The current fix keeps Git, curl,
sha256sum, and tar root-only and gives only the exact resolved
`/node24/bin/node` path plus its two consistently owned provider parents an
exception.
It additionally requires Node major 24, regular/executable tools, refusal of
checkout/temp/home paths, no group/world-writable tool or parent, and the clean
public child-environment allowlist. It also derives the Web build SHA and `main-<SHA>`
or `preview-<SHA>` identity from Vercel's exact provider context instead of a
mutable project value or an annotated tag. PR #4 Preview deployment
`my-life-graph-qxrknizc4-my-life-graph-s-projects.vercel.app` from source
`1010607` reproduced the same ownership error and proved that Vercel's Node
owner is also distinct from the build shell EUID. The follow-up therefore
keys its exception only to the exact resolved provider path, consistent
non-root parent ownership, safe modes, and Node 24; executable negative tests
deny non-root Git/download/checksum/archive tools, wrong Node paths or parents,
foreign owners, and writable modes. Preview deployment
`dpl_4MJ7MY6pjBgptLGznyGWHetoFaXf` from the resulting source `e3737c0` then
passed Node trust, checkout identity, and the pinned Flutter archive checksum.
It exposed the next provider mismatch: root-run tar retained the archive's
numeric Flutter owner, so Git refused the extracted temporary SDK as dubious
ownership. The current follow-up extracts the checksum-verified SDK with
`--no-same-owner`; it does not broaden Git `safe.directory`. A new successful Production build
is not claimed until the protected PR merge and live provider verification.
No successful tagged artifact or VPS/Android deployment is claimed.
The pre-domain VPS-handoff task captured base
`bd963d97b6173c096a1ff1bd7bca058aaf6b75f6`; its working-tree selector chose
the Full lane and passed on 2026-08-26. Flutter analysis and all 1,100 tests
passed; FastAPI Ruff and 1,681 tests with 2 intentional skips passed; the debug
Web build, normal PostgreSQL 17 state, pinned isolated PG15/PG17 full chains,
restore/deletion replay, and all database assertions passed. Browser run
`20260826T081628Z-98397` passed all eight independent journeys without retry
and removed every run-owned Auth identity. The same task's focused source gates
passed 16 VPS tests, 16 backup tests, the Vercel and Android release guards, and
documentation consistency. This is local default-off deployment/readiness
evidence only; it does not prove a domain, remote pilot project, target VPS,
Codex account permission/login, live provider, signed APK, or deployment.
The former
2026-08-19 counts belong to the pre-Coach-V4/pre-hosting predecessor and are
retained only in
[Verification History](verification-history.md); they do not prove this tree.

Current 2026-08-26 repository evidence includes 16 VPS tests, 16 backup tests,
3 Vercel-release tests, 5 Android-release tests plus the static Android guard,
documentation consistency across 96 Markdown files and 82 FastAPI routes, the
complete Fast suites above, and the debug web build containing the Turnstile
assets. The tracked, checksum-verified Gradle 8.14 wrapper also completed the
Android `testDebugUnitTest` and `lintDebug` gate successfully on Java 21. The
Android source guard requires that same exact Java version in CI, staging, and
release workflows so Android 36/Robolectric tests cannot regress to the
unsupported Java 17 runner. The normal local
PostgreSQL 17 database and pinned, physically separate
RAM-only PostgreSQL 15 and 17 runs apply the complete 69-file repository chain.
The Recommendation transition suite passed 53 assertions on both pinned
majors, the real multi-session Coach harness passed global 15-of-16 dispatch
admission, 5-of-6 per-owner UTC admission, exact replay, and reconcile/delete
interleavings, and an intentionally compromised pre-existing
deletion-replayer role was refused before its first grant. After trusted
isolated cleanup, PG15 created the exact role without membership while PG17
created only its bootstrap-granted, ADMIN-only creator edge with `SET` and
`INHERIT` disabled. The complete final-state pgTAP corpus passed 475 assertions
in 23 files on pinned PG15, pinned PG17, and the normal PG17 database. The PG17
lane additionally passed a full owner/ACL-preserving dump/restore into a second
RAM-only target and a restored deletion replay. This is local
migration/concurrency/recovery evidence, not remote migration state.

A separate pre-migration rehearsal used the confirmed Staging PostgreSQL 17.6
source at its 59-migration
`20260815082606_coach_byok_completion_dispatch_v1.sql` boundary. It restored the
captured application plus managed Auth/Storage schema into a disposable PG17.6
target, applied the ten recovery migrations to the 69-file head, and matched
raw DDL plus ACLs against an independently migration-built PG17 reference. The
role guard and required deletion-replay transition also passed. This local,
ignored plaintext rehearsal set is pre-migration safety evidence only: it is
not an encrypted off-host Restic snapshot, contains no Management-API Auth
configuration inventory, and did not exercise an off-host deletion journal.

After that rehearsal, independent review, and the full local gate, the user
authorized the exact ten-migration Staging apply from migration-source commit
`2723ab641518e4cd4e68f2f0a45e055926f55f4b`. Supabase CLI 2.107.0 first
reconfirmed project ref `oscrunlndfrecjilojja`, the 59-migration remote
boundary, and an exact ten-file dry-run. The push completed through
`20260820200000_account_deletion_replayer_role_guard_v2.sql`; the post-push
linked listing matched all 69 repository versions and a new dry-run reported
the remote database up to date. A newly authenticated direct Supabase-MCP audit
then passed the PG17.6 Hosted Database Contract, prepared-deletion guard,
version-aware deletion-role attributes/membership, postgres global/public
default-ACL boundary, six-table explicit-grant set, and zero-row classic/vector
Storage inventory. It also confirmed that the participation gate remains off.
The aggregate MCP result is `post_migration_pass=true` and
`overall_pass=false` solely because the Advisor clear-flags are false. Provider
findings remain: leaked-password protection is disabled; 16
RLS-initplan performance warnings belong to retained legacy CamelCase policies;
and 29 unindexed-FK plus 70 unused-index notices are informational. This is
Staging database evidence only; no application, Auth-setting/provider, VPS,
Vercel, or public-pilot deployment is claimed.

On 2026-08-26 the user explicitly reassigned that inspected project
`oscrunlndfrecjilojja` as the real-data pilot candidate and the separately
created pristine project `kvdunemnuqcvbhrlfnsh` as staging. Fresh direct MCP
aggregate checks found the pilot candidate still on PostgreSQL 17.6 with the
exact 69-migration head, one non-scenario Google identity, one profile, two
Daily Logs, three Schedule Items, zero Scenario users, and no accepted pilot
participation. Its Security Advisor still has the single leaked-password
warning. The new staging target has PostgreSQL 17.6, zero users, identities,
public tables, application migrations, or Storage rows, and zero Advisor
findings. These were read-only checks; they do not prove identity ownership,
staging bootstrap, hosted keys/Auth settings, backup/restore, two-user
isolation, Vercel, VPS, or public release.

The hosted-role source task captured base
`fcbf76e4201909783c682e0fef7109ff00d4da1b`; its affected selector chose the
Full lane and passed on 2026-08-26. Flutter analysis and all 1,100 tests passed;
FastAPI Ruff and 1,681 tests with 2 intentional skips passed; documentation,
source, debug Web, normal PostgreSQL 17 history, pinned isolated PG15/PG17
chains, 23-file/475-assertion pgTAP, owner/ACL restore, and deletion replay all
passed. Browser run `20260826T161609Z-816225` passed all eight independent
journeys without retry and removed every run-owned Auth identity. This proves
the local ref-guard/documentation change from the captured base, not the
pending remote staging bootstrap or any deployment.

| Lane | Latest recorded evidence | Scope limit |
| --- | --- | --- |
| Current VPS/backup/Vercel/Android source gates | The captured-base rerun passed on 2026-08-26, including the default-off shared-provider templates and Vercel identity/environment/secret-isolation guards; Docs passed across 96 Markdown files and 82 FastAPI routes. Current evidence includes VPS 16, backup 16, Android 5 plus its static guard, and the earlier checksum-verified Gradle 8.14 `testDebugUnitTest`/`lintDebug` pass. | Templates/unit and local JVM/lint checks only; the observed Vercel failure is provider evidence, but no successful new deployment, VPS, signing-key, APK-device, or physical Focus Protection execution is claimed. |
| Current Flutter/FastAPI/Web | The 2026-08-26 captured-base Full pass includes Flutter analysis and 1,100 tests, FastAPI Ruff and 1,681 tests/2 skips, and the debug web build. Browser run `20260826T081628Z-98397` passed 8/8 journeys without retry and with exact cleanup. | Local browser/fake-provider evidence only; no successful hosted public-origin or real-provider claim. |
| Current database | Normal PG17 plus pinned RAM-only PG15/PG17 69-migration runs again passed on 2026-08-26, including both 53-assertion transition proofs, hostile pre-role refusal/safe clean retry, real multi-session Coach races, 23-file/475-assertion final-state pgTAP, and PG17 owner/ACL restore plus deletion replay. The pilot candidate has the matching 69-migration head; the assigned staging target is pristine at zero migrations. | Hosted evidence is read-only role-assignment/inventory evidence only; staging bootstrap, encrypted off-host restore/replay, Auth configuration, and real public operation remain unproved. |
| Historical pre-migration restore | Confirmed PG17.6/59-migration dump from the then-Staging project restored to disposable PG17.6, advanced to 69, matched strict DDL/ACL reference, and passed role/deletion-recovery postconditions. | Local ignored plaintext rehearsal only; no off-host Restic, Management-API Auth-config inventory, or deletion-journal replay claim. |
| Historical browser/Android/local-provider/staging | See Verification History and the dated remote staging section below. | Historical evidence only; never a claim about this checkout. |

Product lanes above remain lane-specific evidence; they are not permission to
claim remote migration state, deployment, installed-device behavior,
push/background delivery, model availability for another account, participant
results, or longitudinal outcomes.

This section is the sole current source for exact test counts, commit ids, E2E
identities, and checkout evidence. Other current documents link here instead of
copying those values.

## Task Base And Affected Selection

Capture the task base before the first change:

```bash
git rev-parse HEAD
```

Run affected selection only with that captured commit:

```bash
npm run verify:affected -- --base-ref <task-base-ref>
```

The wrapper fails closed when `--base-ref` is absent or invalid. It combines
the committed diff from `<task-base-ref>` through current `HEAD` with staged,
unstaged, and untracked paths, classifies them, prints the selected gates, and
runs those gates. Passing `HEAD` covers only current working-tree changes; once
the task creates commits, it omits the earlier committed portion of the task.
Always retain the commit captured before work began.

Expected path selection is conservative:

- documentation-only paths select Docs and Visual;
- ordinary backend paths select Source and Backend;
- ordinary Flutter paths select Source, Flutter, and Web;
- the exact `app_spacing.dart` and `app_radii.dart` files below
  `apps/mobile/lib/core/constants/` also select Source, Flutter, and Web locally;
- Auth, routing, core, configuration, schema, mixed-stack, or unknown paths
  otherwise retain Full. Adding such a path to a presentation-only change
  broadens the selection to Full.

These narrower commands apply locally. Path categories and all CI selection
outputs remain unchanged, including Full E2E for the two core constants.

## Verification Levels

Project account/bootstrap unit tests run in `npm run verify:vps` and the Source
gate. The optional real Ubuntu SSH rehearsal and its exact isolated Docker
commands are documented in [Project access bootstrap](../deploy/vps/ACCESS.md).
Neither path uses a VPS, real SSH credentials, database, or provider account.

Use the lowest level that covers the complete change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Docs | `npm run verify:docs` | Documentation tests, links, routes, current versions, owner coverage, current claims, and docs-impact rules. | No |
| Visual | `npm run verify:visual` | Frontend visual-system tests and source contract. | No |
| Source | `npm run verify:source` | Shared documentation, visual, shell, deployment, and source contract checks used locally and by CI. | No |
| Affected | `npm run verify:affected -- --base-ref <task-base-ref>` | Classifies every task path and runs the required gates. | Depends on selected gates; never grants reset authority. |
| Fast | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:fast` | Docs/visual/source checks, complete Flutter analysis/tests, complete FastAPI checks, and diff hygiene. | No |
| Flutter | `npm run verify:flutter` | Flutter dependency resolution, analysis, and the complete Flutter suite. | No |
| Backend | `npm run verify:backend` | Python compilation, Ruff, and the complete FastAPI suite. | No |
| Web | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:web` | Builds the Flutter debug web bundle. | No |
| Database | `npm run verify:db` | Requires matching local migration history, runs the isolated transition harnesses including the pinned PG17 migration/restore/replay lane, then the complete normal-local pgTAP suite. | No |
| Reviewed migration apply | `APPLY_MIGRATIONS=true npm run verify:db` | Applies reviewed pending local SQL, rechecks history, then runs database verification. | May change or delete local rows. |
| Full | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:full` | Runs Fast, Database, Web, and all browser journeys. | No reset; browser tests create and remove exact local users. |
| Browser smoke | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:smoke` | Runs four representative independent UI journeys. | No reset; removes exact test users. |
| Browser full | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:full` | Runs all eight independent UI journeys. | No reset; removes exact test users. |
| Demo seed | `npm run seed:demo` | Recreates only the four named local demo accounts. | Destructive only to those local demo identities. |

`FLUTTER_BIN` falls back to `flutter` and may be set to another executable by
the caller. Do not document or commit a workstation-specific SDK path.

## Documentation And Visual Gates

Run the documentation gate for every repository documentation change:

```bash
npm run verify:docs
```

It runs the documentation regression tests and the live consistency checker.
The checker validates:

- Markdown links and anchors;
- the strict sorted `docs/current-contracts.json` schema;
- every registered code selector and owner version;
- exhaustive named Flutter/FastAPI version-pair coverage within the registry's
  scope;
- the latest migration owner;
- documented FastAPI routes and methods;
- centralization of current checkout evidence;
- known superseded current-state claims.

Changed-code documentation ownership is reported separately as non-blocking
review hints when an owning document is absent from the diff. Review whether
behavior, contracts, commands, or guarantees actually changed; update affected
documentation or briefly explain why it is still accurate in the fix report.
A hint is not a consistency error and does not require a cosmetic document edit.
Missing registered owners, code/owner version mismatches, broken links, route
contradictions, and the migration inventory still fail the gate.

The docs-impact checker compares uncommitted local changes with `HEAD` by
default. CI supplies `DOCS_BASE_REF` so committed pull-request changes are also
included. For whole-task product-gate selection, use the captured task base with
the affected command above; these are related but distinct comparisons.

Run the visual contract separately when selected:

```bash
npm run verify:visual
```

It pins the local font/icon/brand foundation and rejects uncontrolled Material
icons, gradients, colors, radii, fonts, and route-local text styles. It does not
replace viewport screenshots, accessibility checks, or human visual review.
The hosted equivalent is the `docs-visual` job in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## Current Version Coverage

Exam Plan Health is tracked as shared named `exam-plan-health-v1`. Focused
verification covers strict FastAPI/Dart envelopes, exact threshold boundaries,
shared Exam priority and consumers, Focus/reservation arithmetic,
Calendar-window and DST Unknown behavior, owner-derived GET/preview routing,
untruncated one-RPC parsing, Flutter Guest/Mock zero-call guards, editor preview
generation races, Preparation values, Planner combined-empty semantics, Today
non-green filtering, transport-vs-Unknown copy, and 320 px/200% layout.
The focused boundary also covers block-linked versus proposal-time Focus
credit, retained 120-block exhaustion, previous-day overnight and DST anchors,
new/existing preview identity and base revision, Health independence from an
overfull legacy feed, Assignment Series exact-retry invalidation, and previous-
value Async loading/error states.

Multi-Exam balancing is tracked as shared named `multi-exam-plan-v1`.
Focused verification covers strict union/key/revision/change-axis parsing,
explicit target/revision binding, retain-and-supplement and target-only stages,
exact cardinality/tie ordering and search-limit failure, unchanged-plan
canonicalization, single-plan one-time adoption, batch list/detail/confirm/
cancel routing, immutable exact retry across same-principal refresh and
transient Auth error recovery, terminal
proposal replay conflict, stale/saved-refresh confirmation authority, all
competing batch-child mutation guards, shared mutation gating, deep-link/detail
recovery under failed/limited or late bounded feeds, selected-detail versus
list-detail success/error race ordering with source-bound retry authority,
fail-closed DST conversion, valid current-profile IANA confirmation authority,
Guest/Mock zero calls, and populated
narrow/large-text presentation. Backend API/service/repository tests cover
owner-derived identity, one-snapshot authority, total planner-evaluation bounds,
stable `55P03`/`40P01` conflict mapping, learned-timing permission/provenance
CAS, all-or-none result handling, and request replay.

Today Full week is tracked as shared named `today-week-agenda-v1`. Focused
backend coverage proves bearer-derived ownership, exact profile-local
Monday-through-Sunday bounds, one call per source seam, dedicated bounded
owner/range queries and fixed non-rowwise relation reads, canonical
current-revision Preparation credit/lifecycle, current Calendar-import
authority, disconnected-empty and stale-unavailable behavior, all seven
categories/actions, independent partial failure, route-wide profile/timezone
`503`, and DST fold/gap behavior. Focused Flutter coverage proves the strict
temporal envelope including overflow-component rejection and valid fractional
offset timestamps, the identity/action/status union, no device-local time
conversion, guest zero calls, lazy open/retry, midnight-safe Habit navigation,
source-partial rendering, current action mapping, whole-row actionable
semantics and two-pixel schedule-row/accordion keyboard focus rings,
two/two-and-a-half-card mobile widths,
weekend clamp, day snap and week bounds, the 208-pixel seven-column threshold,
dense 320 px/200-percent layout, refresh mapping, and independent 44/24-pixel
information/accordion controls. The old two-source rating/`fullyRated` week
projection is not compatibility behavior; Today at a glance remains unchanged.

The generic Today Recommendation and Decision Feedback retirement is verified
across FastAPI route composition, strict scheduler input, Briefing V2, Weekly
Review V3, Account Export V6, Personal Snapshot V3, Coach prompt V4/context V3,
Flutter provider/surface absence, notification source parsing, and preserved
Sleep Recommendation/Skillset/Insight/Memory/controlled-Coach concepts. The
isolated migration proof uses two owners, a real concurrent lock timeout with
SQLSTATE `55P03`, rollback residue checks, exact structured sanitization,
content-free Coach tombstones with usage retention, current writer/grant/RLS
checks, and the complete final-state pgTAP suite. Historical immutable
Recommendation transition tests remain source evidence but are not current
product-surface evidence.

The [contract registry](current-contracts.json) is the source for exact current
versions, code selectors, and their contract, persistence, or operational owners.
This runbook describes verification coverage rather than maintaining a second
version table. General READMEs, architecture/product overviews, development and
verification runbooks, and copy/visual guides are not mandatory locations for
repeating version identifiers. Their behavioral documentation still needs to
stay accurate when the behavior it describes changes.
Operational READMEs that define a compatibility boundary, such as the backup
journal contract, remain registered owners.

Feature contracts remain the complete wire-format and compatibility authority.

## Fast Verification

Run the standard non-destructive source gate from the repository root:

```bash
FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:fast
```

`npm run verify` and `scripts/verify.sh` are compatible aliases. Fast runs the
documentation and visual gates, shell/source contract tests, Flutter dependency
resolution, clean Flutter analysis and the complete Flutter suite, Python
compilation, non-mutating Ruff, the complete FastAPI pytest suite, and
`git diff --check`. Its independent source, Flutter, and backend groups may run
concurrently.

`npm run verify:flutter` and `npm run verify:backend` select just their existing
group through `scripts/verify_fast.sh --group flutter|backend`. The runner also
accepts `--group source`; unknown or incomplete arguments fail before any tool
runs. With no arguments it still runs all three groups. Each selected group
propagates failure. Runner regression tests use isolated substitute programs
to prove group selection and failure handling without starting product stacks.

The source group delegates to `scripts/verify_source.sh`, also exposed as
`npm run verify:source`. The existing CI `docs-visual` job runs this same entry
point, including the Vercel/CSP, Turnstile, affected-selection, VPS/backup, and
local shell-safety tests. This group needs Node.js and Python, but no Flutter
SDK, live database, provider account, or deployment credentials. Any failed
check fails the shared entry point and its caller.

For a focused Deadline allocation diagnostic before the selected gate, run:

```bash
cd services/ai_service
./.venv/bin/python -m pytest -q \
  tests/test_planning_availability.py \
  tests/test_deadline_plan_service.py \
  tests/test_assignment_series_service.py
cd ../../apps/mobile
"${FLUTTER_BIN:-flutter}" test test/deadline_plans_page_test.dart
```

These files cover kind-specific placement, budget/busy/recovery/remainder/DST
constraints, series windows, internal fingerprinting, and Flutter default/value
retention. A focused pass is diagnostic and does not replace Fast, Web, or the
task-base affected gate.

For a focused Planner Overview V2 diagnostic, run:

```bash
cd services/ai_service
./.venv/bin/python -m pytest -q \
  tests/test_planner_service.py \
  tests/test_planner_api.py \
  tests/test_planner_repository.py \
  tests/test_today_overview_service.py
cd ../../apps/mobile
"${FLUTTER_BIN:-flutter}" analyze
"${FLUTTER_BIN:-flutter}" test \
  test/planner_contract_test.dart \
  test/planner_page_test.dart
```

`test/planner_timezone_test.dart` additionally checks profile-local agenda and
stored-preview clocks, retained and edited timestamps, and gap/fold rejection
through the real Task and fixed-commitment dialogs. The Planner page suite
covers profile-local weekly conflict previews including recovery and midnight.
Backend Planner API regressions exercise the real service and route with both
direct and shared-context Deadline conflicts, preserving the existing `409`
status/detail instead of an unhandled `500`.

This pair covers the strict V2 projection and cross-runtime parser, the
unchanged V1 mutation seam, Planner/Today integration, guest call suppression,
bidirectional Task lifecycle/reason relations, current-fact pending staleness,
target-/preview-bound draft cleanup, post-mutation projection locks, and narrow
large-text presentation. Changes limited to those application and
documentation boundaries do not select the database lane because Overview V2
adds no schema, migration, RLS, grant, or RPC; the captured task-base affected
gate remains authoritative if another changed path broadens that scope.

For a focused Today Week Agenda diagnostic, run:

```bash
cd services/ai_service
./.venv/bin/python -m pytest -q \
  tests/test_today_week_agenda_repository.py \
  tests/test_today_week_agenda_service.py \
  tests/test_today_week_agenda_api.py \
  tests/test_today_overview_service.py \
  tests/test_today_overview_api.py
cd ../../apps/mobile
"${FLUTTER_BIN:-flutter}" test \
  test/dashboard_full_week_api_test.dart \
  test/app_schedule_day_card_test.dart \
  test/dashboard_sections_test.dart \
  test/dashboard_page_test.dart \
  test/projection_refresh_coordinator_test.dart
```

The focused run verifies contract/projection/query/action/layout boundaries but
does not replace full Flutter analysis/tests, FastAPI Ruff/compilation/tests,
Docs, Visual, Web, or the task-base affected selector.

Database integration is deliberately separate. A deterministic fake Coach
provider/process seam is mandatory for standard verification; Fast must not
depend on Codex installation, OAuth, model access, subscription status, or an
external network call.

## Local Supabase Verification

`supabase/tests/deadline_plan_limit_test.sql` adds rollback-only execution
coverage for the existing 50-open-plan cap: Series rejection leaves no partial
occurrences or retry ledgers, and an exact successful request remains replayable
at the limit. Flutter Series regressions cover visible errors before a saved
card exists, retained values, exact retry, and reload/competing-action locks.

The pending Exam Plan Health migration has an additional dedicated
`scripts/lib/exam_plan_health_migration_harness.sh` path. The harness proves
that its target is the physically isolated RAM-only container, applies the full
migration chain there, runs `supabase/tests/exam_plan_health_v1_test.sql`, and
compares the normal local migration history before and after. It never applies
the pending migration to the normal local database. The pgTAP contract checks
service-role-only execution, the inclusive 366-day Exam horizon, exact Focus
credit, confirmed consumer inclusion, and authenticated denial. This isolated
gate is wired into the migration-aware fast/local verification scripts; a
normal local apply still requires the repository's separate explicit opt-in.

The Multi-Exam migration has its own
`scripts/lib/multi_exam_plan_migration_harness.sh` full-chain proof. It uses the
same labeled RAM-only isolation and history-before/after checks, then runs
`supabase/tests/multi_exam_plan_v1_test.sql`. Each of its 104-assertion passes
is run twice against the same isolated database to prove fixture cleanup and
repeatability. The assertions cover the five
private tables, forced RLS and least privilege, composite ownership and bounds,
referencing indexes, service-role-only public RPCs, ungranted inner helpers,
canonical context and learned-timing marker sources, the shared owner-lock
triggers on legacy direct-write authorities, real concurrent Proposal/Task and
Confirm/Habit owner-lock exclusion, explicit committed-fixture/helper cleanup,
owner/request/row-lock order, and failure-reentrant cleanup of its fixed test
owner, helpers, and login. Its second sessions use an expiring test login with
a random SCRAM secret held only in `pg_temp`: normal non-superuser verification
connects through the server interface where password authentication is
required, while the physically isolated superuser target uses its allowed
loopback path. The login receives only exact execution of the Proposal and
Confirm RPCs plus its private fixture/helpers; it never receives
`service_role`. No credential is hard-coded, printed, or retained. If the test
must install `dblink`, the same transaction persists a marker bound to the
extension OID, owner, schema, and version. Cleanup drops an extension without
`CASCADE` only when that exact marker validates; a markerless pre-existing
extension is preserved, and a later run repairs an interrupted marker-owned
installation. Coverage also includes
append-only identity, all single-plan proposal/replan/confirm/complete/cancel
batch-child guards, exact batch replay, cancel cleanup, preference/pilot stale
confirmation, cancel-only-staged semantics, the disjoint
retained/shifted/removed/added review math, and a transactional two-Exam
proposal/stale-confirm/cancel/re-proposal/atomic-confirm lifecycle. The harness
never applies the migration to the normal local database and does not claim
remote state.

The Recommendation/Decision Feedback erase migration has the dedicated
`scripts/lib/recommendation_retirement_migration_harness.sh` full-chain proof.
It uses the same labeled RAM-only isolation and compares a deterministic
SHA-256 over every ordered normal-history `version`, `name`, and `statements`
fact after each stage, applies filled two-owner fixtures, forces a
concurrent-writer `55P03` timeout and verifies full rollback/no helper residue,
then succeeds and runs 53
transition assertions plus the complete final-state pgTAP suite. Its disposable
bootstrap mirrors normal Supabase `service_role BYPASSRLS` and
`"$user", public, extensions` session semantics. The gate runs the complete
chain on pinned `public.ecr.aws/supabase/postgres:15.8.1.085` and
`public.ecr.aws/supabase/postgres:17.6.1.113`, independent of the normal local
major. PG16+ full-chain harnesses keep bootstrap superuser OID 10 separate from
a non-superuser `postgres` migration identity with `CREATEROLE`. The PG17 lane
verifies the automatic ADMIN-only creator edge, runs the complete 23-file pgTAP
corpus, then full-dumps the final database, restores it with owners/ACLs into a
second RAM-only PG17 target, and executes one restored deletion replay before
cleanup. The proof never applies the erase migration to the normal local
database and grants no remote authority.

The local harness refuses to download either compatibility image implicitly.
Fresh database CI explicitly pulls both pinned compatibility tags before
invoking the same gate; the configured normal Supabase start's separate PG17
image is not accepted as an implicit substitute.

Read `docs/supabase-current-state.md` and
`docs/local-database-safety.md` before database work. Inspect installed CLI
flags with `--help` instead of guessing them.

The normal gate is:

```bash
npm run verify:db
```

It uses the real Supabase CLI and Docker, starts or reuses the local stack,
redacts keys and database credentials, requires repository and local migration
history to match, runs the physically isolated Goal-removal transition harness,
and runs the complete final-state pgTAP suite. It never resets the normal local
database or applies pending SQL automatically.

During database verification and browser E2E, `supabase start` writes its raw
progress to a mode-`0600` temporary log. A successful start emits one stable
marker; a failed start emits only the final 200 sanitized lines and preserves
the CLI failure. The raw log is trap-cleaned. This keeps GitHub Actions log
backpressure from turning a successful multi-image pull into a false failure
while retaining bounded diagnostics. Running-target validation and explicit
isolated-image requests share one allowlist for only the official ECR and GHCR
Supabase Postgres namespaces. Expected lock-timeout/role-guard and Coach-limit
classification plus backup archive and safety source scans use baseline runner
text tools and have no optional `rg` dependency.

Migration verification has separate complementary layers:

- Python source guards preserve rollout-sensitive historical migration text.
- The isolated transition harness proves the bounded multi-migration and lock
  behavior in a separate Postgres process with no normal Supabase volume.
- `supabase/tests/*.sql` proves the final applied schema, RLS, grants, triggers,
  constraints, and database behavior.

The Deadline Plan kind-authority coverage pairs a source guard for wrapper
signature, lock/replay ordering, inner/base-function authority, and Assignment
Series delegation with final-state pgTAP for denied direct service-role base
execution, draft and active mismatches, unchanged roots/request ledgers, valid
same-kind writes, and exact replay. The
scheduled-Focus pgTAP also starts and finishes both missed and upcoming
Deadline blocks at supplied server time while proving immutable planned origin,
terminal replay, and exactly-once remaining-minute credit.

A history mismatch fails before pgTAP. After reviewing the pending SQL and
affected local rows, apply it intentionally only with:

```bash
APPLY_MIGRATIONS=true npm run verify:db
```

That operation may change or delete local rows. It is not a reset and must not
be described as non-destructive.

### Backup And Reset Boundary

Normal verification, local-stack, and E2E commands reject `RESET_DB=true` and
have no reset branch. Create a full restore-verified archive with:

```bash
npm run db:backup:local
```

If the user explicitly intends to destroy the exact normal local database,
start with the non-destructive preview:

```bash
npm run db:reset:local
```

Only the content-bound command printed by that fresh preview may execute. The
wrapper creates and restore-verifies another complete backup, rejects target
drift, and invokes only `supabase db reset --local`. Raw reset, `--db-url`
reset, `--linked` reset, a temporary database inside the normal cluster, and
remote reset are forbidden. Follow `docs/local-database-safety.md` for recovery
and approval hygiene.

## Browser E2E

Install the committed Node dependencies and Playwright browser when needed:

```bash
npm install
npx playwright install chromium
```

Run either the representative or complete suite:

```bash
FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:smoke
FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:full
```

The smoke runs Setup, Auth/Capture/Today, Planner confirmation, and fake Coach.
The full suite adds Exam-Week Outlook, Notification Lifecycle, Account Controls,
and Personal Learning. `e2e/web/journey-manifest.mjs` is the canonical journey
registry. Every spec owns a fresh account and exact cleanup; cleanup failure
fails an otherwise passing run. Old E2E identities are outside normal cleanup
and use the separate fingerprint-confirmed `npm run e2e:cleanup:local` flow.

The runner requires matching migration history and never applies SQL or resets
automatically. It starts checkout-owned loopback FastAPI and Flutter processes,
uses the deterministic fake Coach provider, keeps service-role and scheduler
credentials out of Flutter, and writes run-specific logs/screenshots/traces
under `.tools/e2e/runs/<run-id>/`.

A single manifest journey may be selected through the focused command described
by `docs/local-dev.md`. Focused execution is diagnostic and never substitutes
for the selected smoke or full gate. If a fresh normal database is genuinely
required, finish the separate guarded reset workflow first and then run the
ordinary E2E command without reset authority.

## Android Verification

For Android Focus Protection or Android platform changes, use the SDK setup and
physical matrix in `docs/android-focus-protection-v1-contract.md`. The local
source/build commands use a caller-provided Flutter executable with fallback.
The Gradle 8.14 launcher scripts and wrapper JAR are tracked, so a fresh CI
checkout can run the JVM/lint gate. `verify:android-release` rejects an ignored
or missing wrapper, a wrapper JAR that differs from Gradle's published SHA-256,
or wrapper properties with missing, commented, duplicate, unexpected, or
mismatched active values. It also requires exactly one active Java 21 pin in
each Android CI, staging, and release workflow. Git pins the Unix launcher to
LF, the Windows launcher to CRLF, and the wrapper JAR to binary treatment:

```bash
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
cd apps/mobile
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test
cd android
ANDROID_HOME="$PWD/../../../.tools/android-sdk" \
ANDROID_SDK_ROOT="$PWD/../../../.tools/android-sdk" \
./gradlew testDebugUnitTest lintDebug
cd ..
"$FLUTTER_BIN" build apk --debug
```

JVM, lint, and APK success does not prove Accessibility blocking, DND/OEM
behavior, calls/alarms, process death, boot, or an installed-device layout.

## Phase 10 Provider Verification

### Analysis image verification without a model

The existing opt-in Docker test uses synthetic SQLite data and no provider
credentials. It verifies the real image through the MCP executor, including
read-only snapshot/host isolation, absent host environment and no network.
From the repository root, with local Docker and the backend test environment:

```bash
cd services/ai_service
analysis_revision="$(python3 app/analysis_image.py coach_analysis)"
COACH_ANALYSIS_IMAGE="mylifegraph-coach-analysis:sha256-$analysis_revision" \
  bash ../../scripts/prepare_coach_analysis_image.sh
COACH_REAL_ANALYSIS_IMAGE_TEST=1 \
  COACH_ANALYSIS_IMAGE="mylifegraph-coach-analysis:sha256-$analysis_revision" \
  .venv/bin/python -m pytest -q \
  tests/test_coach_data_mcp.py::test_real_analysis_image_enforces_isolation_and_conservative_scope
```

This test is intentionally separate from the default fake-only test suite. It
does not authenticate Codex, create a release tag or attest another Docker host.

### Optional live provider verification

Standard FastAPI, Flutter, database, and browser checks use fakes. The separate
real-model smoke is optional, explicit, network/account dependent, and skipped
by default:

```bash
npm run prepare:coach-analysis
cd services/ai_service
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

A valid result must prove the contract's exact model and Fast configuration,
required MCP startup, multi-tool synthetic-data execution, and matching
backend-derived trace/source scope. It must not print the prompt, answer, OAuth
state, account data, raw event stream, stderr, paths, or tokens. It proves only
the exact machine, CLI, image, login, account, and date. It does not prove
FastAPI persistence, Flutter presentation, production readiness, or another
developer's availability. Missing capability is an honest failure, never a
reason to add a key, model fallback, or standard-tier downgrade.

## Demo Seed

For repeatable local real-data exploration:

```bash
npm run seed:demo
```

The seed refuses non-loopback Supabase URLs and recreates only the four named
local demo accounts. It verifies the incomplete Setup account and the populated
Student, Worker, and Recovery scenarios. Rerunning invalidates their existing
sessions. The command is not authorized for a remote project and does not
replace browser or product verification.

## Secrets And Logs

- Never paste, print, or commit Supabase keys, database passwords, scheduler
  tokens, bearer tokens, `.env` contents, or Codex OAuth state.
- Current publishable and legacy anon keys are valid client configuration but
  still credentials in chat and logs. Current backend secret keys and legacy
  service-role JWTs remain FastAPI/Node-only and are stripped from Flutter
  build/start child environments.
- Sanitized `codex login status` is the maximum routine OAuth inspection. Never
  read or copy `~/.codex/auth.json`.
- Use run-specific ignored artifacts under `.tools/`; do not install replacement
  tool binaries there.
- Redact any unexpected credential output before sharing logs.

## Continuous Integration Gates

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) defines the current
hosted workflow:

- `docs-visual` always runs the shared source gate, including documentation,
  visual, shell-safety, deployment, and source contract tests;
- Flutter/Android and complete FastAPI suites run on pull requests;
- path classification adds a web build for Flutter changes;
- schema/database paths add a fresh local migration chain and pgTAP;
- Auth, routing, schema, core/configuration, unknown, or cross-stack changes add
  full browser E2E; and
- scheduled workflow runs execute full browser E2E;
- manual workflow runs execute every required check, including Web and Database,
  so a candidate can be verified without a pull request.

For a user-requested promotion without a PR, push the candidate to its working
branch and run `gh workflow run ci.yml --ref <candidate-branch>`. Inspect the
completed run and the required checks on the exact candidate SHA. Successful
manual jobs provide test evidence, but do not alone establish that GitHub will
accept the protected update: confirm that all required contexts also appear
and satisfy protection in the candidate's status-check rollup. The 2026-09-06
candidate's manual jobs were omitted from that rollup and its direct push was
rejected. A separately user-authorized PR supplied eligible PR checks for the
same candidate; the protected fast-forward then succeeded. If manual checks
are omitted, obtain PR authorization and run normal PR CI; do not synthesize
statuses or weaken protection. Manual and
scheduled documentation checks compare against `origin/main`; PR runs retain
their exact PR base SHA. Required checks and administrator enforcement stay
enabled when the PR requirement is removed. Once verification is complete,
ask the user to confirm the current/proposed `main` commits and intended
fast-forward or merge, following `AGENTS.md`. Do not update `main` before that
confirmation, and ask again if the candidate or target changes.

Fresh hosted runners obtain an empty local stack through normal startup. CI does
not set `RESET_DB=true` and cannot call the guarded reset execution path. A local
run is evidence only for the local checkout; do not report a hosted pull-request
gate until that hosted job succeeds.

The staging-APK, signed-pilot-APK, and pilot-backup workflows pin every
third-party Action to an immutable full commit SHA while retaining the reviewed
major version as an inline comment. Updating one of those SHAs is a separate
supply-chain review; a moving major tag is not accepted in these
credential-bearing workflows.

## Current Automation Gaps

- Hosted CI evidence must come from GitHub; repository source or a local run
  proves only that the workflow is defined.
- Project access and runtime foundations have the scoped host acceptance
  recorded above. Application release, HTTPS, rollback, complete runtime
  permissions, monitoring, and signed-Android gates remain open. Their
  certificate, signed-secret, physical-device, and promotion gates have no
  current deployment evidence. Static rehearsal binds each release to a
  deterministic analysis-image tag, seals the complete prepared tree, rejects
  post-seal mutation before promotion, and restores the prior tag on symlink
  rollback; actual root ownership and retained-image availability still require
  VPS evidence.
- There is no deployed scheduler/cron or production background worker.
- Notification Delivery has no Android/system, push, browser, email, or
  background-mobile channel; physical foreground acceptance remains useful.
- Installed-device Google OAuth/recovery, device-specific layout/accessibility,
  and best-effort authenticated guest-capture migration still need manual
  acceptance.
- Calendar coverage uses selected local `.ics` bytes, not provider OAuth,
  refresh/revocation, URL fetch, live sync, provider writes, or native picker
  behavior.
- OpenAI/Gemini BYOK adapters are covered by deterministic HTTP mocks but have
  no live-key turn. The local Codex provider remains development-only. The
  separate `mylifegraph-coach` protocol, admission, permission templates, and
  deterministic failure paths are implemented. Target-host identities, rootless
  startup and aggregate cgroup configuration have foundation acceptance, while
  real analysis-container, provider, restart/reboot and answer-quality acceptance
  remain open.
- Hosted Turnstile acquisition/reset/cancel/error source now covers each
  protected email Auth operation on web and Android, but the real widget,
  domain, Supabase provider/secret, browser, accessibility, and physical-device
  acceptance remain unverified. Release-day Google OAuth/redirect settings are
  also external gates. Shared-provider global admission/budget and invalid-BYOK
  no-fallback have deterministic repository coverage but remain unverified
  through public origins.
- No separate real-data pilot Supabase project or remote current-key rotation is
  repository-proven. Local code now supports publishable/secret keys and exact
  staging/pilot crossover guards plus source-level visible staging identity,
  versioned 18-or-older acceptance, and a hard-allowlisted staging scenario
  generator. Normal local migration evidence, confirmed remote fixture
  creation/cleanup, remote migration, and public-origin acceptance remain
  absent.
- Pre-stream HTTP 429 admission, same-id retry without claim/budget, executor
  reservation cleanup, and race/disconnect behavior are implemented and
  deterministically tested. The global UTC-day aggregate is tested to survive
  owner/account deletion while personal dispatch linkage cascades; public/VPS
  acceptance remains open.
- An inert protected GitHub workflow can create encrypted checksum-verified
  Restic snapshots, enforce empty Storage, retain 7 daily/4 weekly, and call an
  off-host heartbeat. No storage account/credentials, real backup snapshot,
  isolated database restore, deletion replay, API/TLS monitor, or tested alert
  exists yet.
- `account-deletion-v2`, `account-deletion-status-v2`, the
  `account-deletion-journal-v2` writer/exporter, dedicated-role replay, and
  watermark checks exist in source. No real object-locked journal, encrypted
  snapshot, isolated database restore/replay, or recovery cutoff has passed;
  an older backup must not be opened as if post-backup deletions were already
  preserved.
- The manual student usability study and longitudinal product-outcome evidence
  remain unrun.

When changing browser flows, keep the journey manifest, Playwright config,
fixtures/specs, split-contract guard, runner, local-development guide, and this
runbook aligned.
