# VPS Pilot Release Plan

Status: planned, not implemented. This plan was consolidated on 2026-08-19.

This document is the delivery and release authority for turning the current
checkout into the first assessable, phone-usable MyLifeGraph pilot. It owns the
sequence from local implementation through a tagged release, VPS operation,
Vercel, hosted Supabase, signed Android delivery, verification, and handoff.
It does not replace the current product, wire-format, schema, or feature
contracts. Those documents remain authoritative for behavior that already
exists.

Nothing in this document is evidence that a VPS, DNS name, TLS certificate,
provider, Vercel deployment, Android package, remote Auth setting, or release
currently exists. A checkbox is evidence only when its named gate has been run
against the named release candidate and its result has been recorded.

## Outcome And Scope

The first pilot is complete when a person can receive the public web URL or
signed Android package, register their own account, finish Setup, use the
implemented Supabase-backed product, and deliberately use one of the available
Coach modes over HTTPS. The expected first audience is the two developers and
the professor, but that is a capacity assumption, not an account cap.

The pilot must support:

- public self-registration with email/password;
- optional Google OAuth after its hosted configuration is verified;
- no invitation, user allowlist, or hard-coded three-user limit;
- participation restricted to adults through a versioned 18-or-older
  self-attestation that stores no date of birth;
- ordinary use with the participant's own persisted Supabase data, not a
  synthetic-only evaluation mode;
- Vercel-hosted Flutter Web and a signed Android release package;
- one hosted Supabase pilot project for real participant data and a separately
  identified hosted staging project for synthetic fixtures;
- FastAPI and the controlled Coach runtime on the VPS;
- user-supplied OpenAI or Gemini keys through the existing BYOK boundary;
- a separately selected, operator-funded Codex subscription pilot mode after
  its account/terms and privacy gates pass;
- exact HTTPS, CORS, stream, quota, backup, rollback, and release gates; and
- a documented migration path from the VPS to Render or another stateless
  backend host.

This plan does not add a production SLA, promise unlimited free model use, or
claim readiness for thousands of simultaneous users. Public registration and
bounded provider capacity are separate concerns: anyone may create an account,
while an overloaded or exhausted shared Coach may honestly return busy or
unavailable.

### Release profiles

The target handoff is the **full evaluation pilot**. It includes working BYOK
configuration and a ready no-BYOK `operator_codex_pilot` choice, so the
professor can evaluate Coach without owning an API key. If the account/terms,
privacy, or provider smoke gate cannot be closed, this target is a no-go.

A **degraded BYOK-only pilot** may be released only after the two developers
and the academic scope owner explicitly accept the reduced outcome and the
handoff states that an evaluator needs their own provider key. It is not a
successful completion of the full evaluation-pilot objective and must not be
quietly substituted for it.

The developers have chosen the subscription-backed provider as the intended
technical no-BYOK path for the first small pilot. That decision authorizes the
local implementation and isolated VPS packaging work behind a default-off kill
switch; it does not itself prove that OpenAI permits a multi-user hosted use.
The external account/terms gate therefore remains unresolved until supported
written guidance or the final explicit go/no-go decision records the remaining
risk without describing the path as approved or generally production-ready.

## Decision Record

| Boundary | Pilot decision | Important consequence |
| --- | --- | --- |
| Web client | Flutter Web on Vercel; Hobby only if the current eligibility and limits fit | Vercel receives only public Flutter defines; it never receives Supabase service-role or Codex credentials. Non-commercial eligibility, repository ownership, usage, domain, and rollback limits are release gates. |
| Android client | Signed release APK for direct distribution | Release signing, the Supabase deep-link redirect, and a physical-device smoke are mandatory. |
| Identity and data | Existing inspected project remains staging; a distinct hosted project becomes the real-data pilot | No Postgres service is installed on the VPS. A project may remain on Free only while current limits and pause behavior fit; neither environment may be inferred from the other. |
| Test data | Versioned scenario fixtures only in staging | A fail-closed generator may create targeted synthetic users/data only after an exact staging-project preview and confirmation. It must reject the pilot project and never seed real participant accounts. |
| Participation | Adults only; normal personal use is allowed | Store a versioned 18-or-older acceptance and notice version/time, not a birth date. Real mood, sleep, stress, study, planning, and Coach data make privacy, deletion, backup, and processor disclosure release gates. |
| Public domain | Buy one independently controlled low-renewal-cost domain | Use `app.<domain>` for Vercel, `api.<domain>` for the VPS, and a dedicated sender subdomain such as `auth.<domain>`. Continue using the free project-ref `*.supabase.co` endpoints; do not buy the Supabase Custom Domain add-on for this pilot. |
| Operating budget | At most EUR 10/month in additional recurring services beyond the already held VPS and Codex subscription | Domain renewal, SMTP, CAPTCHA, monitoring, and encrypted off-host storage must fit this ceiling without automatic paid upgrades or uncapped overage. Target domain renewal is at most EUR 20/year. |
| Public Auth mail | Custom SMTP for arbitrary addresses | Supabase may remain on Free, but the SMTP/domain provider is a separate account, operational dependency, and possible cost that must be accepted before release. |
| Off-host recovery | Encrypted backup store plus append-only deletion journal | This is independent of the VPS and may require a small storage/monitoring account; its current price, retention, and object-lock support are release decisions. |
| Backend | One FastAPI instance plus one separately sandboxed Coach executor on the VPS | Port 8000 stays on loopback; only HTTPS through the reverse proxy is public. FastAPI owns Supabase access, while the executor alone owns Codex OAuth and the rootless container daemon. |
| App access | Public self-signup, email/password plus optional Google | There is no invite flow, account allowlist, or three-user hard cap. CAPTCHA and rate limits control abuse. |
| BYOK | OpenAI and Gemini keys supplied by the user | A key stays out of Postgres and server logs. An invalid BYOK turn fails as that provider and never changes provider automatically. |
| Supabase application credentials | Migrate hosted clients/backends to current publishable and secret keys in a focused compatibility change | Flutter receives only a publishable key. API and backup components receive distinct backend secret keys where supported. Database grants may still name PostgreSQL role `service_role`; legacy key names remain compatibility-only until every caller is verified and rotation is separately authorized. |
| Shared Coach | Explicit proposed provider `operator_codex_pilot` | It is a first-class user choice, not a fallback. It has independent gates, budgets, concurrency, disclosure, and a kill switch. |
| Initial process model | One Uvicorn worker, one narrow Unix-socket executor, and one admitted shared-provider turn | Admission is reserved before HTTP/SSE commitment. Capacity is raised only after measurement or a cross-process coordinator. |
| Source of releases | Protected `main` plus an annotated tag | The VPS never deploys a mutable development branch. |
| Future host move | Preserve a stable `api.<domain>` boundary | Render migration changes DNS and secrets/configuration rather than the app-facing API URL or database. |

The proposed provider and setting names in this plan are design placeholders.
They do not exist until the corresponding implementation changes, contracts,
tests, migration, and documentation are merged.

## Current Evidence And No-Go Findings

### Repository state

The current repository already contains the Flutter client, authenticated
FastAPI routes, hosted Supabase configuration boundaries, Vercel build support,
a Render blueprint, BYOK OpenAI/Gemini adapters, the development-only Codex
adapter, deterministic fake-provider tests, and extensive local verification.
The current product truth is documented in
[Current Product Guide](current-product-guide.md), and exact dated test evidence
lives only in [Current Verified Baseline](verification.md#current-verified-baseline).

The following gaps make the current checkout a no-go for the target topology:

1. Hosted Flutter rejects a Coach turn without user BYOK credentials before it
   reaches FastAPI.
2. `local_codex_oauth` reports unavailable outside exactly
   `APP_ENV=development`; running an Internet-facing VPS as development would
   be a false and unsafe workaround.
3. FastAPI CORS does not currently allow both Coach BYOK request headers, so a
   real browser preflight can reject otherwise valid BYOK requests.
4. The Codex provider requires the analysis image and Docker for the mandatory
   Python tool. The described VPS login currently has no usable Docker socket.
5. The repository has no VPS reverse-proxy, service-manager, install, update,
   rollback, log-retention, or backup/rebuild artifacts.
6. DNS, firewall, service accounts, `/etc`, Caddy, and `systemd` require an
   administrator; the described `agent` account has no `sudo` authority.
7. Public signup has not yet been protected with a verified hosted CAPTCHA and
   release-day Auth configuration.
8. The shared subscription provider lacks a persisted global budget, an honest
   busy response, public-pilot disclosure, and a hosted contract.
9. Current CI is not yet a complete tag-to-VPS/signed-APK release process, and
   the existing Android workflow creates a debug artifact rather than the
   final signed package.
10. Running FastAPI, Codex OAuth, and rootless Docker under one UID would let a
    compromised Internet-facing API process reach both the OAuth store and the
    container daemon while it also holds the Supabase service-role key. Mode
    `0700` and a child-process environment allowlist do not isolate one process
    from another process with the same UID.
11. No independently controlled public domain has been selected, so stable API
    HTTPS, branded Vercel routing, and authenticated SMTP sender records cannot
    yet pass their release gates.
12. The inspected Supabase target is staging. A distinct real-data pilot
    project, its current keys, Auth configuration, limits, and redirects have
    not been created, assigned, or inspected.
13. Current repository configuration still names legacy Supabase anon and
    service-role credentials. The hosted publishable/secret-key compatibility
    change and rotation evidence do not exist yet.
14. There is no staging-only scenario generator with an exact project-ref
    guard, and no versioned 18-or-older participation acceptance exists.

These are implementation tasks, not suggestions to weaken the current
development-only guards.

### Dated remote Supabase evidence

The authorized staging audit and later read-only planning recheck recorded in
[Supabase Current State](supabase-current-state.md)
own the exact dated migration, RLS, Auth-user, and Google-identity evidence. A
historical Google identity shows only that Google authentication succeeded at
least once; it does not prove the current provider toggle, Google credentials,
public-signup setting, Site URL, redirect allowlist, CAPTCHA, or present
end-to-end behavior. All of those are release-day checks.

That inspected project remains the staging candidate. It is not promoted in
place to the real-data pilot merely to avoid creating a second environment.
The pilot project does not exist as repository evidence until an authorized
Supabase MCP/dashboard inventory names it and its separate configuration has
been verified. Repository source and staging rows never prove pilot state.

### VPS inventory and capacity evidence

The VPS inventory is user-supplied and must be rechecked on the host before
installation:

- Ubuntu 24.04.4 LTS;
- 4 CPU cores and 7.6 GiB RAM;
- 75 GiB disk with about 29 GiB free;
- Node.js 24, npm 12, Python 3.12 plus a user-managed Python 3.11;
- Docker 29.1.3 and Compose v2 installed, but not usable by the described
  unprivileged session;
- Codex installed under the existing user account; and
- `agent` without `sudo`, while an `ops` account owns administrative access.

The tracked repository payload is small compared with the local checkout. The
large local footprint is dominated by ignored Flutter/Android build tools and
artifacts, which must not be copied to the VPS. A source checkout, Python
environment, a few versioned releases, Codex, the analysis image, and bounded
logs should fit in the reported 29 GiB. Four cores and 7.6 GiB RAM are a
reasonable starting point for the expected first users and one shared-provider
turn, but only target-host measurements can close that gate.

There is no account hard cap. Runtime admission control protects finite model
and machine capacity independently of how many people have registered.

## Target Topology

```text
Browser at https://app.<domain> --------+
                                         \
Signed Android APK -----------------------> Supabase Auth
                  |                       /  + hosted Postgres/RLS
                  | bearer token         /
                  v                      /
             https://api.<domain> ------+
                  |
             Caddy on VPS :443
                  |
             FastAPI 127.0.0.1:8000
                  |             |
                  |             +--> hosted Supabase service-role operations
                  |
                  +--> explicit BYOK OpenAI/Gemini request
                  |
                  +--> authenticated bounded Unix socket
                         |
                  coach-executor (separate UID, no Supabase/app secrets)
                         +--> Codex login state
                         +--> read-only personal snapshot MCP
                         +--> rootless analysis container, no network
```

The VPS is not a database authority. It can be rebuilt from a tagged release,
reviewed configuration, and fresh authentication. User product data remains in
Supabase. Flutter knows the stable API origin and Supabase publishable values;
all service-role, scheduler, operator-provider, and infrastructure secrets stay
server-side.

FastAPI and the executor share no home directory, environment file, container
socket, or writable release path. FastAPI may submit only a validated turn over
the bounded Unix protocol and pass the already owner-scoped snapshot as a file
descriptor or equivalent non-arbitrary handoff. It cannot submit shell
arguments, host paths, environment variables, or container commands. The
executor authenticates the peer UID, owns global operator-provider admission,
returns a bounded result/trace, and receives no bearer token, Supabase URL, or
service-role value.

Flutter uses the pilot project's default project-ref Supabase URL and current
publishable key. Paying Supabase for a custom domain would not host Flutter,
the VPS API, or SMTP, and is outside the pilot budget. Keeping application and
API hostnames on the independently owned root domain preserves later Vercel,
VPS, Render, SMTP, and provider changes without coupling them to a Supabase
add-on.

## Public Authentication And Abuse Boundary

Public availability means that possession of the URL or APK is sufficient to
reach registration. It does not mean unmetered provider use.

### Required account behavior

- Keep email/password signup visible and working.
- Offer Google OAuth when the hosted provider is verified; email/password
  remains the account-path fallback if Google itself is unavailable.
- Do not add invitation codes, a UUID allowlist, a three-user branch, or hidden
  registration UI.
- Preserve Supabase as session issuer. FastAPI derives the owner only from the
  verified bearer token.
- Preserve RLS and service-role-only mutation boundaries.
- Keep account export and confirmed deletion accessible and honest.
- Require one deliberate 18-or-older acceptance before account creation. Store
  the pending choice only in the current client flow; after Supabase has issued
  the account and before Setup or any product read/write, commit the accepted
  notice version and UTC time through a bearer-derived FastAPI command into a
  backend-owned record. Do not use editable Auth `user_metadata` as eligibility
  authority and do not collect a date of birth merely for this pilot.
- Treat a synced account as ordinary real use: empty reads stay empty and no
  targeted synthetic persona is silently inserted into a participant account.

### Privacy and participation gate

Public registration requires a general privacy boundary even when Coach is
disabled. Before exposing the account form, publish and review:

- the responsible controller/project contact and incident contact;
- the prototype/evaluation purpose and whether participation is restricted by
  age, university, course, or jurisdiction;
- the data categories stored in Supabase and processed by Vercel, the VPS,
  Google OAuth, user-selected BYOK providers, and the operator provider;
- which paths are necessary for the app and which require a separate deliberate
  Coach or Calendar action;
- retention, export, deletion, backup-retention, and support procedures;
- applicable processors/subprocessors, regions, contractual basis, and
  international-transfer implications;
- consent or other legal basis and the approved student-facing notice; and
- a method to withdraw from the evaluation without losing access to mandatory
  account export/deletion information.

The notice must explicitly cover that participants may enter real mood, sleep,
stress, study, calendar, planning, reflection, and Coach content. It must be
available before the age acceptance and account creation. The controller and
incident contact may be one of the developers or an institution, but the named
choice is an external release decision and cannot be inferred from Git.

This is a project/institutional decision, not a claim that the repository alone
provides legal compliance.

### Hosted Auth configuration gate

Before release, an authorized project administrator must verify and record:

- the exact pilot and staging Supabase project references and proof that the
  public build uses only the pilot values;
- the current Supabase plan, database/storage/egress/Auth-user limits,
  inactivity/pausing behavior, backup/restore features, and a response plan for
  approaching a free-tier limit;
- email signup and the intended email-confirmation policy;
- the Google provider toggle, Google client id/secret, and consent-screen
  configuration;
- the exact Vercel production Site URL;
- exact Vercel production redirect URLs;
- `com.mylifegraph.app://login-callback/` for signup confirmation, recovery,
  and Google OAuth on installed Android;
- any preview URLs, which must not get unintended production-data authority;
- the configured CAPTCHA provider and keys;
- Auth rate limits appropriate for the pilot;
- the email sender, templates, link behavior, delivery limits, and a real
  confirmation/recovery delivery test; and
- leaked-password and other available security controls, recording any
  plan-level feature that cannot be enabled.

The hosted key migration is a separate compatibility step. First verify by
Supabase MCP/dashboard that both projects expose current publishable and secret
keys. Add code/config support without logging either value; migrate Flutter,
FastAPI, backup, CI, and remote harness callers one component at a time; prove
Auth, Data API, Storage, Realtime if used, and service-role RPC behavior; then
rotate/remove legacy hosted keys only through a separately authorized remote
operation. Local Supabase tooling may retain its generated legacy key names
until that tooling supports the same path.

Supabase redirect URLs must be allowlisted. Exact production redirects are
preferred; broad wildcard redirects belong only to deliberately isolated
preview environments.

As of 2026-08-19, Supabase documents that its built-in email provider sends only
to pre-authorized project-team addresses and allows two email-sending Auth
requests per hour project-wide. The release owner must recheck both rules.
Because this plan requires arbitrary public email registration, the full pilot
requires custom SMTP with a verified sender/domain, SPF, DKIM, DMARC, reviewed
link behavior, delivery/bounce handling, and real inbox tests. Disabling email
confirmation or relying on the built-in sender does not close public signup and
recovery.

When Supabase CAPTCHA is enabled, Flutter must obtain a fresh supported token
for every protected email sign-in, sign-up, password-reset, and applicable
confirmation-resend call on web and Android, pass it through the SDK operation,
then reset the challenge after the attempt. The implementation must define
token expiry, retry, accessibility, a challenge that cannot load, and a
deterministic local/test fake. Google OAuth remains governed by its own provider
flow; do not invent a CAPTCHA claim for an operation Supabase does not protect.

### Pilot, staging, and synthetic-fixture isolation

The existing inspected Supabase project remains staging and contains no
release authority over the future pilot project. The initial environment model
is:

- **staging** — synthetic accounts, deterministic fixtures, remote isolation
  tests, held preview clients, and no participant data;
- **pilot** — public signup, real participant data, release migrations, custom
  SMTP, exact production redirects, and no seed command; and
- **local** — disposable local/demo identities owned by the existing local
  safety workflows, never evidence about either hosted project.

Add a versioned scenario generator with named, reviewable cases such as fresh
account, exam week, overdue tasks, sleep deficit/high stress, existing Coach
history, and deadline conflicts. It must print a non-secret preview containing
the target project ref, scenario ids, and exact identities; require a fresh
content-bound confirmation; compare the target against an immutable
staging-only allowlist; and abort if it matches the pilot ref or cannot prove
the environment. It creates only uniquely named synthetic Auth identities,
records their exact UUIDs for bounded cleanup, is idempotent by run/scenario
identity, and verifies cleanup. Secrets/passwords stay in the caller
environment and never enter scenario files, logs, chat, or Git.

Staging and pilot builds must carry distinct non-secret environment/project
identities and a visible staging label. Preview deployments and staging APKs
must not receive pilot keys or URLs. A production/pilot build fails closed if
given the staging project ref, and the seed tool fails closed if given the
pilot project ref.

### Abuse and capacity controls

Implement controls by request and provider, not by blocking registration:

- per-account Coach-turn limit per profile-local day;
- persistent global shared-provider turn or token budget per UTC day;
- one initial global shared-provider execution at a time;
- an initial one-second maximum admission decision followed by an explicit busy response and
  `Retry-After`, rather than holding every request for 180 seconds;
- bounded request size, snapshot size, tools, SQL, Python, response, and total
  turn time;
- Supabase CAPTCHA and Supabase Auth rate limits for direct Flutter-to-Supabase
  authentication requests, without pretending Caddy or FastAPI sees them;
- route-class connection, request-size, and rate limits on the public VPS for
  expensive authenticated Coach and non-Coach FastAPI operations;
- a global shared-provider kill switch;
- separate BYOK and shared-provider availability in capabilities; and
- alerts for repeated authentication, quota, provider, and 5xx failures.

Limits are configuration with reviewed defaults. They may be adjusted from
measured use without changing who may register.

## Coach Provider Policy

### Explicit provider selection

The hosted Coach needs three honest choices:

1. `openai_user_key` — the user deliberately supplies an OpenAI key.
2. `gemini_user_key` — the user deliberately supplies a Gemini key.
3. `operator_codex_pilot` — the user deliberately selects the shared pilot
   provider and sees its disclosure and capacity limits.

There is no provider fallback. In particular:

- an invalid, exhausted, or rejected BYOK key returns that provider's sanitized
  error and never consumes the operator subscription;
- an unavailable or busy operator provider never switches to a user key;
- replay retains the originally claimed provider and never dispatches twice;
- changing provider requires a new request id and an explicit user action; and
- capabilities may advertise unavailable modes without pretending they work.

### Shared operator subscription boundary

The current personal Codex OAuth adapter is proven only as a development
adapter on one machine/account/date. Hosting it for turns submitted by other
registered people is a materially different use. Before enabling the proposed
shared mode, the release owner must confirm that the current OpenAI account and
service terms permit the intended pilot use and that the university/privacy
owner accepts the data-processing path. Official Codex authentication guidance
distinguishes ChatGPT subscription login from API-key authentication for
programmatic workflows; this plan therefore treats subscription-backed shared
service as a revocable pilot exception, never the scalable production default.

If that gate is not closed, the full evaluation pilot is a no-go. Public
accounts and BYOK may ship only as the separately approved degraded BYOK-only
profile, with `operator_codex_pilot` off and honestly shown as unavailable. Do
not bypass the gate with `APP_ENV=development`, token copying, an undocumented
account, or silent API-key creation.

When enabled:

- the provider runs only in an explicit staging/pilot environment with a
  separate fail-closed pilot flag;
- the Codex login belongs only to the dedicated `coach-executor` user;
- login uses the supported headless/device flow where needed;
- local OAuth state is treated like a password, stored mode 0700, never read by
  the FastAPI UID, copied into the repository, printed, or put in ordinary
  backups;
- the executor process and Codex child receive an allowlisted environment that
  contains no Supabase, scheduler, BYOK, or other application secret;
- FastAPI cannot traverse the executor home or connect to its rootless Docker
  socket, and the executor cannot read the FastAPI environment file;
- prompts, answers, personal rows, access tokens, API keys, and raw Codex output
  never enter proxy/application logs;
- a provider call is counted before dispatch and remains counted after client
  disconnect or ambiguous failure according to the established usage contract;
  and
- disabling the provider is one configuration change plus a service restart,
  without disabling the rest of the app.

An eventual operator API key belongs in the VPS/Render secret store, not in a
Supabase application table. BYOK credentials continue to be request-scoped and
must not become an operator secret.

## Work To Complete In The Local Repository

The following work is done and reviewed on developer machines before any VPS
configuration becomes the primary debugging environment.

### 0. Establish environment, key, participation, and fixture foundations

- Add distinct `local`, `staging`, and `pilot` configuration identities and
  fail-closed project-ref guards to the hosted define helper, FastAPI startup,
  remote harness, and future seed tooling.
- Implement the current Supabase publishable/secret-key compatibility path as
  a focused change. Keep legacy hosted variables only as an explicitly tested
  transition; do not rotate or remove a remote key during repository work.
- Define a versioned 18-or-older acceptance and privacy-notice version/time
  record without collecting date of birth. The UI presents it before signup;
  a bearer-derived backend command commits it after authentication and blocks
  Setup/product access until it succeeds. Keep editable Auth user metadata out
  of the eligibility decision and keep the notice reachable after login.
- Add the deterministic staging-only scenario manifest/generator, exact preview
  and confirmation, pilot-project denial, bounded cleanup, and tests.
- Add distinct visible staging identity and negative tests proving no pilot
  build receives staging values and no staging tool accepts pilot values.

Exit criterion: local tests prove environment/key separation, adult acceptance,
and staging-only fixture authority without a remote mutation or secret in Git.

### 1. Establish the hosted Coach contract

- Time-box one compatibility spike to at most four developer hours before
  extending the hand-written CLI event adapter. Test only the stable published
  Python Codex SDK and its pinned runtime against the exact required model/Fast
  configuration, custom MCP-only tool allowlist, read-only sandbox, ignored
  user apps/plugins/rules, strict output schema, cancellation, timeout, and
  child-environment isolation. Keep the current pinned `codex exec` adapter if
  any required control is absent or experimental; do not make the spike a
  release dependency or use an experimental network listener.
- Define the next capabilities/request/response/history semantics for explicit
  provider selection and shared-provider availability.
- Choose and register named cross-runtime versions if the wire format changes.
- Add persisted provenance and a migration if the existing provider/status
  constraints cannot represent the shared mode honestly.
- Define exact replay behavior across provider changes, quota exhaustion,
  disconnect, timeout, cancellation, busy, and provider kill switch.
- Keep response evidence, trace, snapshot, usage, deletion, and RLS guarantees.
- Update the Coach owner, architecture, service/client documentation, contract
  registry, and migration owner in the same implementation change.

Exit criterion: Flutter, FastAPI, Postgres, and docs describe one provider
decision with no ambiguous fallback.

### 2. Implement the Flutter hosted surface

- Remove the unconditional hosted no-key rejection only for the new explicit
  shared mode.
- Present `Project Coach` and `Use my API key` as deliberate choices with
  concise privacy/cost/availability copy.
- Keep OpenAI and Gemini credentials isolated from one another and clearable.
  Preserve the current web tab-memory-only boundary and encrypted Android
  device storage; never sync a BYOK key through Supabase or retain it after the
  documented logout/profile/delete lifecycle.
- Never place a key in URL, analytics, crash text, persisted Coach history, or
  backend logs.
- Add unavailable, busy, quota, invalid-key, timeout, cancellation, and retry
  states.
- Preserve no-fallback behavior when a BYOK request fails.
- Make the Coach surface available in the signed pilot build through an honest
  pilot build gate; do not disguise the build as development.
- Add CAPTCHA token acquisition/reset/error behavior to every Supabase-protected
  email sign-in, sign-up, reset, and applicable resend operation on web and
  Android; preserve Google callback behavior separately.
- Add non-secret `APP_BUILD_SHA` and release-tag defines through the hosted
  define helper and expose them in a secondary About/diagnostic surface so the
  Vercel build and APK can be matched to the manifest.

Exit criterion: browser and Flutter tests prove every provider/auth state and a
release-mode build exposes only the intended pilot behavior.

### 3. Implement the FastAPI hosted provider boundary

- Add a staging/pilot-only provider gate independent of
  `APP_ENV=development`.
- Keep production fail-closed until a later production provider is designed.
- Allow the exact BYOK headers in CORS for the exact production Vercel origin;
  do not combine credentialed requests with a wildcard origin.
- Expose the bounded `Retry-After` response header through CORS and add real
  preflight plus browser-origin 429/header integration coverage.
- Disable or protect interactive API documentation outside development.
- Add explicit provider admission before a request claim, usage accounting,
  snapshot creation, `StreamingResponse`, or the first SSE event. A rejected
  provider-bound turn returns HTTP `429`, one stable sanitized problem code,
  and a bounded `Retry-After`; it neither terminalizes the request id nor
  consumes user/global budget, so the same id/message can be retried.
- Use proposed problem code `provider_busy` and an integer-seconds
  `Retry-After` clamped to 5–30 seconds (15 seconds initially). Flutter shows a
  countdown/manual retry and never starts an unbounded automatic retry loop.
- Run the pure message-only pre-provider safety classifier before provider
  admission. A deterministic safety bypass uses the ordinary owner-locked
  request claim/completion and per-user question accounting but no provider
  reservation or global provider budget. A non-safety turn first acquires its
  provider/resource-class reservation and only then claims the request; replay
  or claim failure releases the unused reservation without dispatch. Test that
  exact safety, busy, first-claim, simultaneous-retry, and terminal-replay order.
- Persist a global shared-provider budget or otherwise prove that restart and
  concurrency cannot bypass it.
- After admission and request claim but before the socket dispatch, persist one
  append-only global dispatch/reservation identity and consume its budget
  conservatively. Executor tokens are one-use; startup reconciles an expired
  claimed dispatch to an interrupted terminal request, so the same request id
  cannot cause a second provider call after an ambiguous crash.
- Start with one Uvicorn worker. The separate executor or another durable
  cross-process authority owns shared-provider reservations; an opaque
  short-lived reservation is consumed once by execution and released on every
  replay, validation, disconnect, timeout, and failure path.
- Bind each reservation to one executor process/cgroup and a 240-second
  fail-safe lease around the 180-second turn limit. API/executor crash, socket
  loss, or reboot must kill/reap the child and make the slot reusable without
  minting a second provider dispatch for the claimed request.
- Preserve bearer-derived ownership, service-role isolation, SSE cancellation,
  and secret-redacted error translation.
- Keep `/v1/health` a cheap liveness/release-identity route and add a separate
  sanitized core-readiness probe that validates required FastAPI/Supabase
  configuration without invoking a Coach provider. Provider readiness remains
  only in authenticated Coach capabilities.
- Add bounded route-class admission for expensive authenticated endpoints; it
  is separate from direct Supabase Auth protection.

Exit criterion: deterministic tests prove provider selection, pre-stream 429
admission, quota, concurrency, CORS, replay, cancellation, kill switch, and
zero secret leakage or busy-budget consumption.

### 4. Package the analysis sandbox safely

- Retain a pinned, versioned analysis image and validate its revision at
  executor capability startup, not core FastAPI liveness.
- Run containers rootless only under the dedicated `coach-executor` user.
- Never expose or mount the rootless daemon socket to FastAPI or an
  Internet-facing container.
- Implement a separately hardened `coach-executor` `systemd` unit and bounded
  Unix-socket protocol. Authenticate the FastAPI peer UID; accept no arbitrary
  command, path, environment, mount, image, or model field; bound framing,
  snapshot descriptor, output, trace, deadline, and reservation identity.
- Keep sandbox networking disabled, filesystem read-only, CPU/memory/time
  bounded, and only the per-turn snapshot mounted.
- Prove cleanup after success, failure, cancellation, service restart, and host
  reboot.
- Add negative permissions tests proving the FastAPI UID cannot read the Codex
  home or use the Docker socket, the executor cannot read application secrets,
  and an unauthorized peer or malformed/oversized protocol request is rejected.
- Add a compromise/kill-switch test: stopping or disabling the executor makes
  only the shared-provider capability unavailable while core FastAPI remains
  healthy.

Exit criterion: the exact executor user can run the committed provider smoke;
the API/executor permission matrix and protocol tests pass; and no application
secret is visible in the executor, sandbox, or Codex process.

### 5. Add versioned VPS deployment artifacts

Create reviewed repository artifacts, expected under a dedicated `deploy/vps/`
boundary, for:

- an environment-file template containing names but no values;
- a Caddy site template for the stable API host and SSE behavior;
- separate FastAPI and `coach-executor` `systemd` service/socket configuration
  with an explicit filesystem/UID permission matrix;
- a versioned executor protocol schema and hermetic negative-permission tests;
- an optional protected scheduler `systemd` service/timer;
- install/preflight, deploy, health-check, rollback, and rebuild runbooks or
  scripts;
- a Codex-CLI installation manifest with approved package/source, exact version,
  expected checksum/signature evidence, root-owned immutable path, and binary
  rollback procedure;
- release-directory and atomic `current`-symlink layout;
- log retention and disk-monitoring configuration;
- a secret-redaction checklist; and
- a release-manifest template.

The initial deploy path uses one offline-preflight strategy, not implicit
blue/green. It must install the hashed Python runtime dependencies for an exact
tag, validate configuration shape and image/runtime preflight without binding
the live port, retain the previous working release, switch the `current`
symlink atomically, restart, and poll readiness. If readiness fails, it switches
the symlink back and restarts the previous release, then verifies that rollback
before reporting failure. It must never reset or roll back Supabase migrations.

Exit criterion: the artifacts pass static/shell tests and a disposable or
local-host deployment rehearsal before an administrator uses them on the VPS.

### 6. Complete local product and release verification

At minimum, the implementation change must run the task-base affected selector.
Because it will cross Flutter, FastAPI, Auth/configuration, Coach, and likely
schema boundaries, expect the Full lane rather than a docs-only lane. Required
focused coverage includes:

- OpenAI BYOK success and every sanitized error path through deterministic
  mocks;
- Gemini BYOK success and every sanitized error path;
- invalid BYOK with proof of zero shared-provider dispatch;
- explicit shared-provider success through the deterministic fake seam;
- per-user and global budget races;
- simultaneous admission, busy, disconnect, cancellation, exact replay, and
  cleanup;
- browser CORS preflight from the exact Vercel origin;
- public email signup, Google routing, CAPTCHA token handling, confirmation,
  recovery, logout, and session restoration;
- foreign-owner read/write rejection;
- release-mode Flutter Web and signed-build configuration; and
- secret scans and log assertions.

No live provider call belongs in standard CI. The real Codex smoke remains a
separate, explicit, account- and machine-bound acceptance gate.

## Git, `main`, And Release Policy

### Transition from the current branch

At plan creation the active integration branch is `new_backend_gh`, while
`main` is substantially behind it and the accumulated promotion pull request is
already large. For this pilot, retain `new_backend_gh` as the temporary local
integration authority through implementation rather than creating a second
partially integrated branch stack:

1. Keep the verified documentation baseline and every local VPS-pilot
   implementation slice on `new_backend_gh`. Use focused, independently
   testable commits even though they will later appear in one accumulated pull
   request.
2. Do not deploy, tag, or configure Vercel production from
   `new_backend_gh`. It remains an implementation branch, not a release
   authority.
3. If `main` changes before promotion, incorporate and review that drift
   explicitly without force-pushing, rewriting history, or silently dropping
   either side.
4. After the complete local pilot implementation passes its captured-base
   affected gate, externally verify `main` branch protection and prove that a
   merge cannot automatically assign the Vercel production domain. If either
   condition cannot be proven, stop before the remote merge.
5. Open or update one deliberate final promotion pull request from
   `new_backend_gh` into `main`. Review the entire accumulated diff, its
   focused commit sequence, release documentation, and green merge-candidate
   gates; do not force-push or rewrite either branch.
6. Once that pull request is merged, make protected `main` the sole release
   authority. Create RC/final tags only from the verified `main` SHA and keep
   Vercel/VPS promotion held until the immutable release-candidate gates.
7. Retire or archive `new_backend_gh` only after the merge and source identity
   are verified. Deleting it or changing remote protection is a separate
   authorized action. Any later fix starts from protected `main` on a focused
   branch.

### Branch protection

Configure `main` so that:

- direct pushes, force pushes, and deletion are blocked;
- pull requests and one approval from the second developer are required;
- required current CI checks must pass against the merge candidate;
- stale approvals are dismissed after relevant changes;
- unresolved conversations block merge; and
- administrators do not routinely bypass the rules.

Repository source can describe this policy but cannot prove remote GitHub
settings. Record a release-day screenshot or settings export as external
evidence.

### Release identity

Release identity is deliberately two-stage so tags do not depend on artifacts
that do not yet exist:

1. After the complete pilot branch is promoted into `main` through the final
   reviewed pull request and the source/CI gates pass, create one immutable
   annotated RC tag such as
   `v0.1.0-pilot.1-rc.1` on the exact `main` SHA. Never move or reuse it.
2. Publish a source manifest for that RC: Git SHA/tag, current contract and
   migration references, intended toolchain/lock identities, target project/API
   identifiers, and the source-gate results. It does not claim artifact hashes
   or deployment ids yet.
3. Build the VPS release, Vercel candidate deployment, signed APK, SBOM, and
   analysis image exactly once from that RC. Record their immutable hashes,
   image digest, APK version/checksum, Vercel candidate id, and actual Codex/
   Python/Docker versions in an artifact-manifest draft.
4. Run every pre-promotion repository, isolated-database, signing, restore,
   permission, direct-executor/provider, and offline candidate-host gate against
   those exact artifacts. Do not switch the public VPS symlink or Vercel domain
   in order to manufacture pre-promotion evidence.
5. If they pass, create the immutable final annotated tag
   `v0.1.0-pilot.1` on the same SHA. The tag names the accepted artifact set; it
   is not rebuilt from a later commit.
6. Deploy/promote those exact artifacts to the VPS, Vercel production domain,
   and Android handoff, then run the post-promotion public/TLS/Auth/SSE/device/
   rollback smokes.
7. Sign the final attestation manifest containing production deployment ids,
   all artifact hashes, release/toolchain identities, completed gate evidence,
   known limitations, and rollback owner, and attach it to the final release.
8. If post-promotion fails, roll back, mark that release attempt failed, and
   create a new RC tag after the fix. Never repair evidence by moving a tag or
   replacing an artifact under the same identity.

The immutable clients display the RC artifact tag and Git SHA they were built
from. They are not rebuilt merely to replace that label with the later final
tag. The signed final attestation maps the final tag on the same SHA to those
exact RC-labelled artifacts and checksums.

The VPS is not automatically deployed from a mutable branch. Before the final
accumulated promotion into `main`, externally verify that Vercel cannot
automatically assign the production domain to the merge. Build the RC candidate
first and promote it only at step 6 above. A merge to `main` must not silently
become public before the tag decision. A small two-person team benefits more
from an observable manual promotion than from an unreviewed push-to-production
hook.

## VPS Preparation And Privileged Bootstrap

The work is split by authority. Codex or a developer can prepare exact,
idempotent artifacts and validate user-owned paths. An `ops`/provider
administrator must perform privileged host changes.

### Administrator tasks

- Reconfirm OS, CPU, RAM, free disk, swap, time synchronization, IPv4/IPv6,
  open ports, and existing services.
- Create three separate tightly scoped identities: a `deploy` owner for
  immutable release directories/symlink promotion, a `mylifegraph-api` user for
  FastAPI with read-only release access and the backend environment, and a
  `coach-executor` user for Codex OAuth/rootless containers. Do not run FastAPI
  as `root`, `ops`, the deployment owner, executor, or a general interactive
  developer. Combining API and executor identity is not an acceptable pilot
  exception.
- Create and permission release, configuration, runtime state, temporary, and
  log directories. The API user may write only bounded API temp/runtime state;
  the executor may write only its Codex home, rootless container state, and
  bounded per-turn temp. Neither may modify a release.
- Provide rootless Docker only for `coach-executor`. A host-root daemon or an
  API-readable daemon socket leaves the full evaluation profile No-Go.
- Ensure the executor's rootless daemon and required user-session/linger boundary
  start after reboot without an interactive developer login.
- Install and enable Caddy from a supported source.
- Install the release-approved Codex CLI version from its trusted distribution
  source into a root-owned versioned path executable but not writable by
  `coach-executor`. Verify its expected checksum/signature evidence, disable
  unattended self-update, and configure the executor unit with that absolute
  `LOCAL_CODEX_BIN`; do not reuse a user-global binary from `agent`.
- Configure the firewall to expose only SSH plus TCP 80/443. Bind FastAPI only
  to `127.0.0.1`; never open 8000 publicly.
- Harden SSH to keys and disable root/password login only after a second
  administrative session has proved access, avoiding lockout.
- Install the reviewed `systemd` units and limited administrative permissions
  needed for deploy/restart, without granting general sudo.
- Install/rotate a FastAPI environment file readable only by root and
  `mylifegraph-api`. The executor unit receives a separate non-secret/allowlisted
  environment and no Supabase, scheduler, BYOK, or application credentials.
- If backups run on the VPS, create a separate non-interactive backup identity
  and timer whose database/Storage credential file is unreadable by all three
  release/API/executor identities.
- Configure bounded journald/log retention and disk alerts.
- Apply current Ubuntu security updates, configure an owned update/reboot
  policy, and record the initial package/reboot state.
- Configure a small swap file if measurement shows none and the administrator
  accepts it; swap is an OOM safety margin, not capacity.

### Deployment and runtime-user tasks

- The deployment owner obtains the exact tagged source without ignored local
  build directories, verifies the tag/manifest, creates the release-local
  Python 3.12 environment, and installs the committed hashed runtime lock.
- The executor user builds or loads the pinned rootless analysis image through
  the reviewed helper and runs its preflight.
- The executor user proves the configured absolute Codex binary path, exact
  version, executable permissions, sanitized help/feature capability, and the
  tested fallback to the previously retained CLI version without gaining write
  access to either binary.
- An authorized operator configures an isolated Codex home for the executor user
  and completes supported device authentication interactively without exposing
  tokens.
- Deployment preflight verifies only that the API unit can read a correctly
  permissioned environment file and that the executor cannot; it neither reads
  nor installs secret values.
- The deployment owner runs offline release preflight, atomically switches the
  `current` symlink, restarts through the narrow allowed unit, polls loopback
  and public HTTPS readiness, and performs the defined switch-back plus second
  restart if readiness fails.
- Retain the previous release until the observation window closes.

Codex installed under a different account is not sufficient evidence. The
exact executor user must pass sanitized `codex login status`, Docker/image
preflight, and the committed live provider smoke. The API user must fail
Codex-home and container-socket access tests.

## DNS, HTTPS, Reverse Proxy, And Network

Use a dedicated stable hostname such as `api.<domain>`. The app and Android
build use that hostname, not a raw VPS IP or provider-specific host.

No root domain is currently owned for this pilot. Before remote Auth or VPS
cutover, buy one domain whose normal renewal price is at most EUR 20/year and
whose DNS/account recovery can be held by the named owner. Use
`app.<domain>` for the manually promoted Vercel client, `api.<domain>` for
Caddy/FastAPI, and a separate sender subdomain such as `auth.<domain>` for
transactional mail. The default project-ref `*.supabase.co` address remains the
Supabase client/Auth endpoint. Do not enable the paid Supabase Custom Domain or
experimental vanity-subdomain path for this budgeted pilot.

### DNS and certificate sequence

1. Register the root domain, verify account recovery, and create the app/API/
   sender DNS zones without pointing an unverified service at participants.
2. Reserve the API hostname and lower its DNS TTL at least one old-TTL period
   before the first cutover.
3. Add an A record to the VPS IPv4 address.
4. Add AAAA only if inbound IPv6, firewalling, and Caddy have been tested end to
   end; a broken AAAA record can make a healthy IPv4 service appear offline.
5. Start Caddy on ports 80/443 and allow ACME certificate issuance.
6. Verify certificate chain, hostname, renewal storage, and renewal dry-run or
   staging behavior.
7. Verify HTTP redirects to HTTPS and add HSTS only after the stable HTTPS path
   is proven and rollback implications are understood.

### Reverse-proxy contract

The versioned Caddy configuration must:

- proxy only to `127.0.0.1:8000`;
- forward the intended client/proto/host metadata through a reviewed trusted
  proxy boundary;
- preserve streaming responses without response buffering;
- flush the SSE `started` event promptly;
- allow a complete 180-second Coach turn with a proxy timeout margin of at
  least 60 seconds;
- preserve `Cache-Control: no-cache, no-store` and stream cancellation;
- set safe request/body/header limits without truncating supported calls;
- omit authorization, BYOK, cookie, query-secret, prompt, and response data
  from access logs; and
- expose no directory, internal service, Docker API, development documentation,
  or admin endpoint.

Acceptance requires a public health request, a real browser preflight, an SSE
timing check, cancellation, and a full-duration synthetic provider turn through
the public hostname.

## Runtime, Secrets, Logging, And Operations

### Runtime process

- Use one Uvicorn worker initially because the existing global concurrency
  semaphore is process-local; the new executor reservation is still the
  authoritative shared-provider slot.
- Use separate hardened API and executor `systemd` units with
  restart-on-failure, startup/stop timeouts, restricted users, fixed working
  directories, and conservative filesystem/process hardening.
- Do not use `--reload`, `tmux`, `screen`, a developer shell, or an interactive
  Codex session as the production supervisor.
- Keep `/v1/health` as process liveness/release identity; it invokes no model,
  Docker, Codex, or Supabase workflow. Use a distinct sanitized core-readiness
  probe for required settings and bounded Supabase reachability. Neither probe
  depends on the Coach executor or analysis image.
- Keep shared-provider readiness in authenticated Coach capabilities and the
  executor reservation/capability probe. Missing login/image/executor makes
  only that provider unavailable; it does not make core API liveness fail.
- Emit the non-secret release SHA so the running version is inspectable.
- If the protected Daily Preparation loop is required for the demonstration,
  invoke it with a dedicated `systemd` timer and backend-only token. Otherwise
  list scheduled preparation as deliberately not operated. Enabling it also
  requires the Daily Briefing and Notification Delivery owners and their
  verification gates to be updated in the implementation change.

### Secrets

Keep the following only in a root/service-readable VPS environment file or
dedicated secret store:

- current Supabase backend secret key for the pilot API;
- scheduled-refresh token;
- explicit pilot/provider gates;
- narrowly scoped deletion-journal append credential;
- any future operator API key; and
- other backend-only runtime credentials.

The Vercel and Android builds receive only the current Supabase publishable
value, public pilot-project URL, public HTTPS API URL, and non-secret
feature/build flags. A legacy anon value may exist only during the focused
compatibility window and must never be confused with a backend secret.
No secret is placed in GitHub logs, Vercel client output, Flutter assets,
systemd command arguments, Caddy logs, release manifests, screenshots, or
documentation.

Codex OAuth state is not an application environment value. Keep it in the
executor user's private Codex home and renew it through login rather than
copying another user's auth files.

The secret inventory must name an owner, creation date, rotation/revocation
procedure, and dependent restart for each credential. Rehearse revoking the
shared provider and scheduler token without rebuilding either client.

### Observability and retention

Record only sanitized operational facts:

- request/correlation id;
- release SHA;
- route class, status, and duration;
- provider class, not key or account token;
- quota decision, queue/busy decision, tool counts, and sanitized error code;
- process restart/OOM state; and
- CPU, memory, disk, image, release, and journal usage.

Alert or visibly report at 70%, 80%, and 90% disk use. Bound journal retention,
retain only two or three known-good releases, and inspect image/layer growth.
Do not run blind automatic Docker prune because it can remove the only prepared
analysis image or rollback dependency.

The operator runbook must contain kill switches for the shared provider, all
Coach sending, scheduled preparation, and the full FastAPI service, plus the
expected user-visible result of each switch. Stopping the executor or disabling
the shared provider must preserve core API health and make capabilities report
only that provider as unavailable.

### Off-host monitoring contract

Choose and name an external monitor before release; a timer or journal on the
same VPS cannot report that the VPS or network is down. The initial contract is:

- request public HTTPS `/v1/health` and the sanitized core-readiness probe from
  outside the VPS every five minutes, tracking their failures separately;
- alert after three consecutive failures and record recovery;
- alert on TLS expiry at 21 and 7 days;
- send a daily backup-job heartbeat and alert when no successful, checksum-
  verified backup is recorded for 26 hours;
- aggregate sanitized API metrics and alert on at least three unexpected 5xx
  responses in ten minutes, three consecutive executor/provider failures, or
  disk thresholds of 70/80/90 percent; busy 429 is measured separately and is
  not relabelled as provider failure;
- deliver to a named primary and secondary off-host channel owned by the
  incident contact; and
- trigger, receive, acknowledge, and record one test alert before release and
  monthly during a longer evaluation window.

The monitor stores no bearer token, prompt, answer, user identifier, BYOK key,
or Supabase secret. Provider-capability monitoring uses a synthetic authorized
test identity only if privacy and cleanup are separately approved; otherwise a
local executor probe sends only an aggregate heartbeat.

### Maintenance ownership

- Review Ubuntu/Caddy/Docker security advisories and free disk weekly during
  the evaluation window; apply security updates in a scheduled window and
  prove service health after any required reboot.
- Update Codex CLI, Python locks, or the analysis image only through a separate
  compatibility/security pull request and repeat the live provider/sandbox
  gates. Never let a global auto-update silently change the evaluated runtime.
- Record Caddy, Docker, Codex source/version/checksum/path, Python, OS package
  baseline, and analysis-image digest in the release manifest/SBOM.
- Scan the runtime lock and analysis image before release and on a documented
  cadence; triage findings rather than claiming that a scanner proves safety.
- Freeze discretionary runtime changes at least 48 hours before the professor
  evaluation, while retaining authority for an urgent security shutdown.

## Backup, Restore, Rebuild, And Rollback

### Supabase

The versioned VPS/release runbook must define one executable remote-backup
contract. For the intended Supabase Free pilot, whose current official guidance
recommends regular off-site logical exports rather than relying on paid daily
backups, the initial contract is:

- create one logical export every 24 hours and immediately before every
  authorized migration or release-data change;
- target RPO 24 hours and target RTO 4 hours for the evaluation window;
- use the installed Supabase CLI only after inspecting its current `db dump`
  help and the official restore procedure, producing the supported roles,
  schema, and `--use-copy --data-only` parts from the exact project connection
  without placing its password in arguments or logs;
- export `supabase_migrations` schema/data as separately identified parts and
  fail the job unless the data export contains the required Auth users/
  identities. Preserve reviewed custom `auth`/`storage` schema changes through
  the currently supported separate diff/export path rather than assuming the
  normal schema dump owns Supabase-managed definitions;
- inventory Storage buckets/objects. If none exist, record the verified empty
  inventory. If any exist, back up object bytes through the supported Storage/
  S3 download path with per-object inventory and checksums; a database dump
  contains Storage metadata but cannot restore deleted object bytes;
- inventory non-database hosted configuration needed to rebuild Auth and the
  project, including Site URL, redirects, email policy/templates, Google,
  CAPTCHA, SMTP, Realtime/extensions, and sender/domain settings. Preserve a
  reviewed non-secret shape and a separate credential rotation/re-entry
  procedure; do not pretend a SQL dump contains API keys or provider secrets;
- record project ref, UTC start/end, migration boundary, CLI/Postgres versions,
  included/excluded schemas, row/size summaries, and a SHA-256 for every part;
- encrypt before off-host transfer with a key not stored on the VPS, restrict
  access to the named backup owner, and verify the encrypted-object checksum at
  the off-site destination;
- create any plaintext parts only in a backup-owned mode-0700 bounded temporary
  directory, exclude them from logs and general host backups, and remove them
  after the encrypted off-site object is verified;
- retain seven daily and four weekly sets; retain a pre-migration set through
  the rollback window. Document that deleted user data may remain inside an
  inaccessible backup until this bounded expiry; any restore follows the
  deletion-recovery contract below before reopening access;
- restore the complete set into a physically separate disposable Supabase/
  Postgres target before the first release, after any backup-format/tool change,
  and at least monthly if the pilot runs longer; verify Auth/profile ownership,
  migration history, RLS/grants, canonical row counts, and application reads;
  then destroy that disposable target through a separate authorized cleanup;
  and
- emit only the success/failure timestamp and checksum identity to the off-host
  monitor. A file that was created but not checksum-verified and restore-proven
  is not a successful backup.

Run the scheduled export as a separate non-interactive backup identity or an
off-host job. Its database/Storage credentials are unreadable by `deploy`,
`mylifegraph-api`, and `coach-executor`; it cannot alter releases, Codex state,
or application configuration. A root-owned wrapper may install or rotate that
secret but the application process never receives it.

Choose the backup execution host in the runbook before release. The preferred
shape is a named off-host runner with the current Supabase CLI and its own
isolated container runtime. A VPS-local alternative uses only a matching,
version-pinned native Postgres client or a separate backup-owned rootless
runtime. It must never connect to the `coach-executor` Docker socket merely to
make `supabase db dump` work. Record and test the exact choice against the
official CLI restore procedure.

### Restore-safe account deletion

The current account deletion transaction removes `auth.users` and owner data
without creating a backup-independent receipt. Before the public pilot, add a
versioned deletion-recovery contract owned jointly by Account Controls,
Supabase, Backup, and Privacy:

- assign one idempotent deletion id after recent-auth and exact `DELETE`
  confirmation, then durably append an envelope-encrypted off-host intent
  containing only that id, the Auth user UUID, and UTC acceptance time. The
  decryption key is not on the VPS and neither email nor product content is in
  the journal;
- use a named append-only/object-locked destination separate from restorable
  database parts. FastAPI receives at most a write-only append credential; it
  cannot list, read, rewrite, or delete receipts. Recovery read/decrypt/delete
  authority belongs only to the Backup and Privacy owners and is tested
  negatively from the API/executor identities;
- make journal acceptance the explicit irreversible point in the UI/API. Only
  after its durable receipt may the backend invoke the owner-locked database
  deletion. A failed or ambiguous database step becomes `deletion_pending`,
  blocks further product use through a service-role-only pending-intent
  boundary, and is retried/reconciled instead of silently cancelling the
  accepted deletion;
- finalize the journal entry after database deletion, while treating pending
  entries as work that must converge. Both journal append and deletion are
  idempotent by deletion id; no request may create two intents;
- retain each encrypted entry for at least the longest backup retention plus
  seven days (35 days for the initial 7-daily/4-weekly policy). Remove it only
  after every backup that could contain the account has verifiably expired;
- provide a versioned restore tool that, while the restored target is isolated,
  decrypts all journal entries newer than the backup cutoff, invokes the exact
  owner-locked deletion idempotently, and verifies absence from `auth.users`,
  `profiles`, every owner-data source, and Storage inventory before recording a
  replay watermark; and
- prohibit opening a restored target to users until the replay watermark and
  deletion postconditions pass. If this ledger/tool is not implemented, no
  backup predating a user deletion may be restored and the full public pilot is
  No-Go.

The implementation may require an additive service-role-only intent/receipt
table and a new Account deletion wire version. It must preserve forced RLS,
deny `anon`/`authenticated` access, stay outside Account Export and Coach
snapshots, and update every schema/account/verification owner in the same
change. The journal is recovery metadata, not a product analytics or audit
feed.

Do not use the normal local database or remote project as the restore target.
Do not run `db reset`, linked reset, destructive repair, or a live migration
merely as a verification shortcut.

### VPS

Treat the VPS as rebuildable. Preserve:

- versioned deployment artifacts and release manifests in Git/release storage;
- an encrypted off-host copy of reviewed non-secret configuration shape and a
  separate secret inventory/recovery procedure;
- Caddy and `systemd` configuration in reproducible templates; and
- the prior tagged release and Python environment during the observation
  window.

Do not put Codex OAuth state into a general VPS backup. Reauthenticate the
`coach-executor` user during a rebuild. Caddy certificates can normally be
reissued;
the DNS and ACME recovery procedure still belongs in the runbook.

Application rollback switches the release symlink to the last known-good code
and restarts both FastAPI and the executor against that release. It never
reverses applied Supabase migrations. Therefore
every migration in the pilot sequence must be forward-compatible with the
previous application until the rollback window closes.

## Vercel Release

- Verify the current Vercel plan before relying on it. Hobby is acceptable only
  if this academic pilot qualifies under the current personal/non-commercial
  terms, the repository can be connected under its ownership rules, and its
  build, transfer, domain, collaboration, retention, and usage limits fit. As
  of 2026-08-19, exceeding included Hobby usage can pause the project and Hobby
  rollback is limited to the previous production deployment; recheck both on
  release day.
- Connect builds to protected `main`, not the temporary integration branch,
  but hold automatic production-domain assignment until manual promotion of
  the tagged and manifested commit.
- Build from the exact release commit with the hosted Flutter define helper.
- Embed the non-secret build SHA/tag and verify it in the deployed secondary
  About/diagnostic surface.
- Use the stable HTTPS API hostname.
- Keep only the pilot Supabase publishable key client-side and every backend
  secret or provider credential out of Vercel. A preview/staging build receives
  the staging project values and a visible staging label instead.
- Set exact production CORS origin on FastAPI.
- Treat preview deployments as separate environments. They must not silently
  receive production secrets or mutate pilot data.
- Configure and test static-site security headers appropriate to the Flutter
  bundle, including a reviewed Content Security Policy/connect allowlist,
  frame-ancestor protection, referrer policy, content-type protection, and
  permissions policy, without breaking Supabase Auth, CAPTCHA, or the API.
- Verify the deployed build identity, sign-up, email confirmation/recovery,
  Google OAuth, refresh/reload session, complete product smoke, every Coach
  choice, logout, and account deletion/export boundary.
- Rehearse the supported rollback to the immediately preceding production
  deployment and record how production-domain assignment is restored after a
  rollback.

The hosting platform may call the deployment "Production" while the
application environment remains an explicitly named pilot/staging tier. The
UI and documentation must not label that shared subscription provider as a
general production service.

## Android Release

- Create a private release keystore and ignored `key.properties`; never use the
  debug key for the handoff artifact.
- Decide and record application id, version name, and monotonically increasing
  version code before signing.
- Build from the same tagged commit and public hosted defines as Vercel.
- Verify every release Supabase/API origin resolves to HTTPS and that the merged
  Android release manifest/network-security policy does not permit cleartext
  traffic to a fallback host.
- Generate and publish SHA-256 beside the APK.
- Install the APK on at least one physical Android device from a clean state.
- Verify email signup/confirmation, password recovery, Google OAuth redirect,
  session restoration, deep links, complete Setup, core product use, BYOK,
  shared-provider selection, stream/cancel/retry, export/share, deletion guard,
  and any claimed Focus Protection behavior.
- Test update installation from the preceding signed pilot build when one
  exists; the keystore must remain stable for updates.
- Treat a bad installed APK as a forward-fix: stop distributing the affected
  file, publish a newly signed package with a higher version code, and notify
  testers. Do not promise remote recall or a downgrade over a higher installed
  version code.
- Record Android version, device model, app version, release SHA, time, and
  result without recording personal data.

Direct APK distribution is sufficient for the professor pilot. Store review is
a separate future release track and is not silently folded into this plan.

## Capacity Plan

The starting configuration is deliberately conservative:

| Resource/control | Initial value | Promotion condition |
| --- | --- | --- |
| Uvicorn workers | 1 | Add only after global budgets/concurrency are cross-process and load-tested. |
| Shared-provider concurrency | 1 executor-owned reservation | Raise to 2 only after target-host CPU/RAM, cancellation, race/replay behavior, and three-client tests remain stable. |
| Per-user shared turns | 5 per profile-local day initially | Tune from measured duration and fair-use needs; it is a provider-use limit, not a registration cap. |
| Global shared-provider budget | 15 newly dispatched turns per UTC day initially | Raise only with account/terms approval and usage evidence; retries/replays must not mint budget. |
| Retained releases | 2 or 3 | Increase only while disk thresholds remain healthy. |
| FastAPI bind | Loopback only | Never promoted to a public raw port. |

Before release, measure idle, one-turn, busy-rejection, three-client, restart,
and cancellation behavior on the VPS. A correct test may admit one shared turn
and return immediate busy responses to the other clients; it must not exhaust
memory, deadlock, leak containers, or time all clients out. BYOK turns need
their own concurrency accounting because they still consume snapshot and tool
resources even though the user pays the model provider.

Record sanitized command output and timestamps for these initial acceptance
thresholds after the analysis image is already present:

- public busy/load-shed response begins within 2 seconds as HTTP `429`, before
  `StreamingResponse` or any `started` event, and includes a bounded
  `Retry-After` without claiming the request or consuming budget;
- an admitted public SSE request emits `started` within 5 seconds under normal
  pilot load and reaches a terminal event within the existing 180-second
  application limit;
- the three-client scenario produces no OOM kill, unexpected service restart,
  deadlock, or unbounded queue;
- total host memory remains below 80% at the observed peak and returns to a
  stable post-turn baseline; sustained swap growth is a failure, not capacity;
- every success, failure, and cancellation leaves no per-turn running container
  and no stale snapshot/temp file; after ten mixed turns, residual disk growth
  outside bounded logs remains below 100 MiB from the prepared baseline;
- loopback health returns within 30 seconds after a normal service restart and
  within 90 seconds after a host reboot; and
- disk remains below the 70% warning threshold at release.

Capture `systemd` unit state, process/cgroup memory, load, `df`, rootless
container state, response timings, and bounded journal summaries. Redact user
content and credentials. If real provider latency makes the SSE timing
unreachable, revise the threshold only through a recorded release decision and
an honest client timeout change, not by omitting the measurement.

The reported machine should be sufficient for the initial expected use if the
service stays single-worker, concurrency is bounded, ignored local SDK/build
directories are excluded, images/logs/releases are controlled, and no other
large VPS workload competes for memory or disk. This is a capacity hypothesis
until target-host measurements pass.

## Verification And Go/No-Go Gates

### Repository gate

- All feature contracts and `docs/current-contracts.json` are synchronized.
- `npm run verify:docs` passes.
- The captured-base affected selector chooses and passes every required lane.
- Full Flutter/FastAPI tests, web build, local database/pgTAP, and all browser
  journeys pass when selected.
- Provider-specific deterministic, pre-stream admission, concurrency, replay,
  disconnect, CORS, Auth/CAPTCHA, executor-protocol, negative-permission, and
  secret-leakage tests pass.
- `git diff --check` passes and staged, unstaged, and untracked files are
  reviewed.
- The single accumulated promotion pull request preserves the focused local
  commit sequence, is approved and green against protected `main`, and does
  not silently promote Vercel production.
- Environment guards reject staging/pilot project-ref crossover, the synthetic
  scenario generator rejects the pilot target, and the hosted publishable/
  secret-key compatibility tests pass without exposing a credential.

### Infrastructure gate

- Exact DNS records, valid TLS, renewal, redirect, firewall, and loopback bind
  are verified.
- The `deploy`, `mylifegraph-api`, and `coach-executor` identities and their
  filesystem/socket permission matrix pass without an API/executor same-UID
  exception. Any VPS-local backup identity/credential is isolated from all
  three. Rootless sandbox, Caddy, `systemd`, retention, off-host alerts,
  maintenance, and kill switches pass.
- Reboot returns the correct tagged release to health without an interactive
  shell.
- Public liveness and core readiness independently report the release; stopping
  the executor changes only authenticated Coach capability, not either core
  probe.
- Public SSE starts promptly, runs to completion, cancels, and cleans up.
- Release SHA from public health matches the manifest.

### Provider gate

- BYOK OpenAI and Gemini each complete one separately authorized live test, or
  the unavailable live mode is documented without weakening deterministic
  coverage.
- Invalid BYOK proves zero operator-provider dispatch.
- The exact `coach-executor` user passes Codex login status, analysis-image
  preflight, and the sanitized committed multi-tool live smoke. The
  `mylifegraph-api` user cannot traverse the Codex home or use the container
  socket, the executor cannot read the API environment, and unauthorized socket
  peers or malformed requests are rejected.
- Shared-provider per-user/global limits, pre-SSE busy behavior, replay,
  cancellation, reservation cleanup, executor kill switch, and restart behavior
  pass while core API health remains available.
- Terms/account and university/privacy approval for the shared subscription
  path are recorded. Otherwise the full evaluation profile is a no-go and only
  an explicitly accepted degraded BYOK-only profile may ship.

### Supabase and Auth gate

- An authorized release-day read-only audit proves both exact project refs,
  that staging remains synthetic-only, that public clients use only the pilot,
  and the pilot's
  migration, RLS, grants, policies, RPCs, and absence of orphaned identities.
- Current publishable/secret keys are proven per component; any legacy hosted
  key is either removed through separately authorized rotation or explicitly
  retained with a dated migration owner and no client/backend confusion.
- Backup and separate restore rehearsal pass before any release migration.
- The isolated restore replays the encrypted deletion journal through its
  cutoff, proves all deletion postconditions, and records the replay watermark
  before any user access.
- Public email sign-in/signup, confirmation/resend, recovery, fresh CAPTCHA
  token/reset/error handling, logout, and session refresh work on web and
  Android.
- Custom SMTP sender/domain authentication, templates, delivery/bounce behavior,
  and inbox tests pass for arbitrary non-team addresses.
- Google provider settings and both exact web/Android redirects work.
- At least two independently created users prove owner isolation through the
  remote harness and exact cleanup of its temporary identities.
- The versioned 18-or-older acceptance and notice version/time persist without
  a date of birth, editable Auth user metadata grants no eligibility, and the
  privacy notice is accessible before signup and after authentication.
- Public registration remains open without an invitation/allowlist branch.

### Client and product gate

- Vercel production and the signed APK identify the same source release.
- Vercel plan eligibility/limits, manual production promotion, security
  headers, and previous-deployment rollback are verified.
- A newly self-registered account can finish Setup and use the complete claimed
  Supabase/FastAPI slice.
- A real participant account starts empty and persists only that participant's
  deliberate data; no staging fixture or synthetic persona appears in pilot.
- Web and Android each prove explicit BYOK and shared-provider UI states.
- The three expected pilot participants can use the target concurrently with
  correct admission behavior, without any user-count special case.
- Export, deletion, privacy disclosure, support contact, known limitations,
  and recovery instructions are present.
- The public-account privacy/participation gate is approved independently of
  the shared Coach decision.

### Release decision

Any failed security, ownership, secret, TLS, backup/restore, Auth callback,
provider-fallback, or rollback gate is a no-go. Capacity failure may be closed
by lowering provider concurrency or budget if the resulting busy behavior is
honest and tested; it may not be hidden with unbounded queues or user account
blocking.

## Professor Handoff

Deliver one coherent package:

- stable Vercel URL;
- signed APK and SHA-256;
- final release tag, Git SHA, signed attestation manifest, artifact checksums,
  and build date;
- short installation and self-registration instructions;
- note that email/password always exists and Google is optional;
- state that the pilot is for adults, accepts ordinary personal use, and does
  not require a date of birth;
- privacy disclosure for Supabase, BYOK providers, and the shared operator
  provider;
- a five-to-ten-minute demonstration path using a freshly created account;
- known limitations, quotas, and what a busy/unavailable Coach means;
- exact supported Android/browser versions tested;
- support and incident contact for the evaluation window; and
- rollback and outage message plan.

Run a same-day preflight before the evaluation: Vercel quota/health, Supabase
Auth email and Google, public TLS/API health, one fresh registration, one
no-BYOK Coach turn, one signed-device launch, and current disk/provider budget.
Keep a clearly labelled local fake/demo fallback and optional redacted screen
recording for explaining an external outage; neither may be presented as proof
that the hosted pilot passed.

Do not hand over a developer `.env`, Supabase service-role value, Google secret,
keystore, scheduler token, Codex login state, or operator credential. The
professor should be able to register normally rather than receive an
administrator-created invitation.

## Migration To Render

The stable API hostname makes a later move intentionally small at the network
boundary:

1. Keep FastAPI stateless with all user data and durable request/usage state in
   Supabase.
2. Keep environment-specific secrets out of images and the repository.
3. Produce a Render-compatible release from protected `main` and the same
   runtime lock.
4. Deploy it on a temporary Render hostname with the shared subscription
   provider disabled.
5. Verify health, CORS, Auth, remote isolation, BYOK, SSE, cancellation, and
   the complete hosted smoke.
6. At least one full old-TTL interval before cutover, lower the API record TTL;
   do not lower it in the same step as the address change.
7. After acceptance and the TTL wait, change `api.<domain>` to Render.
8. Repeat public web and Android smoke without rebuilding clients if the stable
   API name did not change.
9. Observe, retain VPS rollback, then decommission the VPS service through a
   separate authorized operation.

The personal Codex OAuth plus local Docker sandbox is not assumed portable to
Render. A scaled shared-provider offering requires a supported server-side API
credential/provider, explicit cost controls, and a new production contract.
BYOK remains portable because the FastAPI request boundary already owns it.

## Ordered Execution Checklist

### Phase 0 — documentation baseline and integration-branch setup

- [ ] Synchronize and verify this decision baseline without remote mutation.
- [ ] Retain `new_backend_gh` as the temporary implementation authority and
      keep each local slice in a focused, independently verified commit.
- [ ] Keep tags, Vercel production, and VPS deployment disabled for this
      mutable integration branch.

### Phase A — local design and implementation

- [ ] Implement local/staging/pilot identities, current Supabase publishable/
      secret-key compatibility, crossover denial, and distinct staging UI.
- [ ] Implement versioned 18-or-older acceptance without date-of-birth storage.
- [ ] Implement the previewed, confirmed, staging-only synthetic scenario
      generator and pilot-target denial.
- [ ] Run the time-boxed stable Codex Python SDK compatibility spike; retain the
      pinned CLI adapter unless every required control passes.
- [ ] Approve the explicit provider contract and disclosure.
- [ ] Approve the general public-registration privacy/participation boundary.
- [ ] Implement every protected Auth/CAPTCHA operation, challenge lifecycle,
      SMTP-dependent UX, and exact redirect in code/tests.
- [ ] Implement hosted Flutter provider selection and states.
- [ ] Implement FastAPI pilot gate, CORS, global budget, busy response, and
      release identity.
- [ ] Add the Flutter build SHA/tag to hosted defines and About/diagnostics.
- [ ] Add any additive Supabase migration and synchronize every owner.
- [ ] Implement the restore-safe deletion intent/journal/replay contract and its
      pending/irreversible UI state.
- [ ] Implement the bounded executor protocol, separate API/executor identities,
      rootless sandbox safeguards, and negative-permission tests.
- [ ] Add versioned VPS deployment artifacts.
- [ ] Add signed Android release automation without storing signing secrets.

### Phase B — local verification and release-candidate creation

- [ ] Run focused tests and the captured-base affected selector.
- [ ] Run local full/browser/database gates selected by the change.
- [ ] Rehearse install/update/rollback with the deployment artifacts.
- [ ] Review secret handling and complete diff.
- [ ] Finish and review the focused commit sequence on `new_backend_gh`, then
      run the complete captured-base affected gate over the accumulated task.
- [ ] Prove remote `main` protection and that the merge cannot auto-assign the
      Vercel production domain.
- [ ] Promote the complete verified branch into protected `main` through one
      reviewed, fully green pull request; do not deploy from the merge alone.
- [ ] Confirm Vercel cannot assign the production domain automatically; verify
      Hobby eligibility/limits and keep the candidate deployment held.
- [ ] Create one immutable annotated RC tag from the exact `main` SHA and publish
      its source-only manifest.
- [ ] Build the VPS release, held Vercel candidate, signed APK, analysis image,
      SBOM, and artifact-manifest draft exactly once from that RC.

### Phase C — authorized Supabase and account setup

- [ ] Buy the independently controlled low-renewal-cost root domain, configure
      recoverable DNS ownership, and keep the paid Supabase Custom Domain off.
- [ ] Use an authorized Supabase MCP/dashboard inventory to retain the existing
      target as staging and create/assign a separate real-data pilot project;
      record both exact refs without copying credentials into evidence.
- [ ] Back up and separately restore-verify before remote migration.
- [ ] Audit/apply the exact reviewed migrations with explicit authorization.
- [ ] Migrate each hosted component to current publishable/secret keys and
      rotate legacy keys only after the separately authorized compatibility
      evidence passes.
- [ ] Configure public email signup/sign-in, confirmation/resend/recovery,
      CAPTCHA, Auth limits, and custom SMTP for arbitrary non-team addresses.
- [ ] Configure and verify Google OAuth and exact redirects.
- [ ] Run the remote owner-isolation harness and cleanup.

### Phase D — VPS bootstrap and held offline candidate

- [ ] Administrator creates and verifies the separate `deploy`,
      `mylifegraph-api`, and `coach-executor` identities, rootless executor-only
      Docker, firewall, Caddy, directories, secrets, `systemd`, retention,
      updates, and alerts. API/executor same-UID operation is not an exception.
- [ ] Shared-provider account/terms and privacy approvals are recorded before
      login or live server-mode testing; otherwise stop the full evaluation
      profile or obtain explicit degraded-profile acceptance.
- [ ] Ops installs the manifest-pinned Codex CLI at the root-owned absolute
      executor path and proves checksum/integrity, exact version, no auto-update,
      and binary rollback.
- [ ] DNS and TLS pass before clients point at the service.
- [ ] Deployment owner installs the exact RC artifact and hashed runtime
      dependencies in a release directory without switching the public
      `current` symlink.
- [ ] `coach-executor` authenticates Codex through the supported flow; API and
      executor negative-permission checks pass.
- [ ] Analysis image, executor protocol, direct executor live smoke, permission
      matrix, offline API configuration preflight, daemon-after-reboot behavior,
      and disposable deployment/rollback rehearsal pass without public traffic.

### Phase E — artifact acceptance, final identity, and promotion

- [ ] Complete every pre-promotion repository, restore, permission, offline
      candidate-host, direct-provider, signing, and held-client gate against the
      exact RC artifact set.
- [ ] Create the immutable final annotated tag on the same SHA; do not rebuild
      or replace any accepted artifact.
- [ ] Promote the exact held Vercel candidate and VPS artifacts, distribute the
      already signed/checksummed APK, and verify security headers and rollback.
- [ ] Complete post-promotion core health/capability, pre-SSE busy response,
      public HTTPS/Auth/SSE/cancel/restart/rollback, three-client capacity, and
      physical-device product/Coach smokes.
- [ ] Complete and retain the measurable three-client capacity/admission and
      owner-isolation evidence.
- [ ] Sign and attach the final attestation manifest with production ids,
      artifact hashes, toolchain identities, gate evidence, and limitations.
- [ ] Finalize professor handoff, off-host monitoring, known limitations, and
      support.
- [ ] Make and record the final go/no-go decision.

## Responsibility Matrix

Assign a named person to every role before remote work. One person may hold
several roles in a two-developer team, but each hat retains its own checklist
and no one self-approves a change for which the plan requires the second
developer's review.

| Accountable role | Required ownership and evidence |
| --- | --- |
| Release and go/no-go owner | Coordinates gates, enforces the additional EUR 10/month ceiling, freezes the candidate, signs the manifest, chooses full versus explicitly approved degraded profile, and records the final decision. |
| Independent code/release reviewer | Reviews PRs, full promotion diff, secret boundaries, manifest, and rollback evidence without being the change author for the approval in question. |
| Supabase/Auth/SMTP owner | Owns distinct staging/pilot refs, publishable/secret-key migration, staging-only fixtures, backup/restore, migrations, RLS/grants, Auth/CAPTCHA, Google, redirects, SMTP/domain delivery, rate limits, and release-day read-only evidence. |
| VPS/DNS/Caddy owner | Holds privileged `ops` authority and owns host patching, the three service identities, filesystem/Unix-socket permissions, executor-only rootless Docker, firewall, DNS/TLS, Caddy, `systemd`, logs, reboot, and rebuild. |
| Codex account/quota owner | Confirms terms/account permission, performs only the `coach-executor` login, owns global/per-user budget and provider kill switch, monitors allowance, and can revoke the provider. |
| Privacy and academic-scope owner | Approves public participation boundary, processor/provider disclosures, retention/deletion, age/scope, consent/legal basis, and any BYOK-only scope reduction. |
| Android keystore custodian | Creates and secures the keystore, maintains encrypted recovery and access separation, signs/version-codes releases, publishes checksum, and owns forward-fix procedure. |
| Vercel owner | Confirms plan eligibility/limits, project/repository ownership, environment values, manual promotion, custom domain, headers, usage monitoring, and rollback. |
| Backup and recovery owner | Owns the 24-hour export job, encryption/off-site retention, manifests/checksums, deletion replay record, separate restore rehearsal, RPO/RTO evidence, and recovery authorization. |
| Monitoring and incident owner | Owns the external monitor, primary/secondary delivery channels, monthly test alert, backup heartbeat, user-visible outage/busy communication, same-day preflight, and rollback/provider-shutdown coordination. |

Keystore recovery, secret escrow, DNS/provider account recovery, and absence
coverage must exist outside the repository without copying secrets into the
release manifest.

## Ownership And References

- Current user-facing behavior: [Current Product Guide](current-product-guide.md)
- Flutter navigation, Auth, BYOK storage, and build surface:
  [Mobile App](../apps/mobile/README.md)
- Public FastAPI routes/runtime configuration:
  [AI Service](../services/ai_service/README.md)
- Cross-system authority: [Architecture](architecture.md)
- Product/backend evolution: [Backend Roadmap](backend-roadmap.md)
- Coach contract: [Phase 10 Free Read-Only Coach](phase-10-controlled-coach-plan.md)
- Hosted student-facing disclosure/capability language:
  [UI Language And Copy](ui-language-and-copy-contract.md)
- Hosted provider/Auth/About presentation and responsive/accessibility review:
  [Frontend Visual System V2](frontend-visual-system-v2.md)
- Export, recovery, deletion, and credential cleanup:
  [Account Controls](v1-account-controls-contract.md)
- Any claimed installed-device Focus behavior:
  [Android Focus Protection](android-focus-protection-v1-contract.md)
- Schema/Auth/RLS/live-audit boundary: [Supabase Current State](supabase-current-state.md)
- Supported workstation commands: [Local Development](local-dev.md)
- Gate selection and evidence: [Verification](verification.md)
- If scheduled Daily Preparation is enabled:
  [Daily Briefing](daily-briefing-implementation-plan.md) and
  [Notification Delivery](notification-delivery-v1-contract.md)
- Whole-product review: [Product Review Handoff](product-review-handoff.md)
- Machine-checked versions: [Current Contracts](current-contracts.json)
- Official Supabase redirect guidance: <https://supabase.com/docs/guides/auth/redirect-urls>
- Official Supabase CAPTCHA guidance: <https://supabase.com/docs/guides/auth/auth-captcha>
- Official Supabase Auth rate limits: <https://supabase.com/docs/guides/auth/rate-limits>
- Official Supabase custom SMTP guidance: <https://supabase.com/docs/guides/auth/auth-smtp>
- Official Supabase Google Auth guidance: <https://supabase.com/docs/guides/auth/social-login/auth-google>
- Official Supabase publishable/secret-key migration:
  <https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys>
- Official Supabase Custom Domain boundary:
  <https://supabase.com/docs/guides/platform/custom-domains>
- Official Supabase pricing: <https://supabase.com/pricing>
- Official Supabase backup guidance: <https://supabase.com/docs/guides/platform/backups>
- Official Supabase CLI backup/restore guidance:
  <https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore>
- Official Vercel Hobby plan: <https://vercel.com/docs/plans/hobby>
- Official Vercel rollback guidance: <https://vercel.com/docs/cli/rollback>
- Official Codex authentication guidance: <https://learn.chatgpt.com/docs/auth>
- Official Codex SDK guidance: <https://learn.chatgpt.com/docs/codex-sdk>
