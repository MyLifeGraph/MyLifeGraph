# Verification And Agent Automation

This document is the shared runbook for automated checks. It describes what can
be verified by agents without manual app exploration, what requires local
tooling, and what remains future work.

## Verification Levels

Use the lowest level that covers the change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Standard | `FLUTTER_BIN=/path/to/flutter scripts/verify.sh` | Non-destructive repo checks. | No |
| Local Supabase preflight | `FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Starts local Supabase, requires matching migration history, and runs tests with Supabase config. | No |
| Local Supabase migration apply | `APPLY_MIGRATIONS=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Explicitly applies reviewed pending SQL, verifies history, then runs tests. | May change or delete local rows |
| Local Supabase reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Recreates local DB, applies migrations, then runs tests. | Yes, local DB only |
| Browser E2E | `FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Requires matching local migration history, starts Flutter Web, drives Playwright, and checks uniquely named DB writes. | No reset; writes test rows |
| Browser E2E with reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Recreates local DB, then runs browser E2E. | Yes, local DB only |
| Demo seed | `npm run seed:demo` | Starts local Supabase and seeds repeatable demo users/data for manual exploration. | No |

Do not run destructive Supabase commands against a remote database. These
scripts are for the local Supabase stack from `supabase/config.toml`.

## Demo Seed

Manual product exploration can use local seeded accounts instead of hardcoded
mock data:

```bash
npm run seed:demo
```

This runs `scripts/seed_demo_data.sh`, which starts local Supabase, reads the
local service-role key from `supabase status -o env`, and invokes
`scripts/seed_demo_data.mjs`. The Node script rejects any API URL outside
`http://127.0.0.1:54321` and `http://localhost:54321`.

The seed is idempotent for the demo accounts. It keeps the local Auth users,
updates their password and metadata, clears their app rows, and recreates the
scenario data. Each Intake row is a valid applied revision with a stable request
id and intentionally empty optional Setup-owned collections. Separately seeded
goals, habits, and schedule rows retain `demo_seed` ownership and are not
presented as Setup materialization. The default local-only password is
`DemoPass123!` for:

- `student@example.test`
- `worker@example.test`
- `recovery@example.test`

Override it with `DEMO_PASSWORD` when needed. Do not use this workflow for a
remote Supabase project.

## Standard Verification

From the repository root:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

The script runs:

- `bash -n scripts/start_frontend.sh`
- syntax checks for the shared migration helper, local-stack supervisor, and
  their hermetic harnesses
- `bash scripts/test_local_supabase_migrations.sh`
- `bash scripts/test_start_local_stack.sh`
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `python3 -m compileall services/ai_service/app`
- `git diff --check`

FastAPI unit tests are run separately:

```bash
cd services/ai_service
./.venv/bin/python -m pytest
```

Use `python -m pytest` from an environment with `services/ai_service`
requirements installed if the local `.venv` does not exist.

Phase 10 follows that locked separation: every normal FastAPI, Flutter,
Supabase, and browser check uses an injected deterministic fake Coach provider.
Standard verification must never depend on a Codex installation, ChatGPT
subscription, OAuth login, live model, or external network call. The
development-only `local_codex_oauth` adapter is covered with fake process
runners. See `docs/phase-10-controlled-coach-plan.md`.

FastAPI tests cover authenticated Setup/Intake, deterministic recommendations,
and the snapshot aggregator endpoint. Setup coverage includes principal-derived
identity for both `GET /v1/intake/setup` and `POST /v1/intake/complete`, strict
structured item/cadence validation, zero materialized optional rows for blank
answers, idempotent request replay, stale base-revision conflicts, recovery from
partial repository failure, stable identities across edit, intentional removal,
preservation of non-Setup rows, stale-worker checks, and monotonic profile
projection through `profiles.setup_revision`. Atomic-apply coverage verifies one
service-role RPC for the complete projection, same-request worker convergence,
per-user serialization against a later revision, full rollback on ownership
collision, idempotent profile repair, and the exact-only legacy
`Math`/`Room 204`/Monday `08:15`-`09:45` cleanup. Snapshot tests verify
principal-derived `user_id`, request `user_id` rejection, scoped Supabase reads,
refreshing an existing `user_state_snapshots` row for the same period, and the
Phase 1 capture-date boundary. The snapshot repository reads `metadata` from
`daily_logs` and `behavioral_events`, widens the UTC event query safely, prefers
the explicit event `metadata.entry_date` for local-day filtering, excludes the
following local day, and retains a UTC fallback for legacy events without that
metadata. Phase 2 tests cover every capture taxonomy code; strict V2 identity,
enum, numeric, timestamp, and projection validation; unknown future metadata;
legacy-only fallback; separate seven-day state versus requested statistics
windows; Evening target/previous-day and Morning target-day freshness;
`missing`, `partial`, `current`, and `stale` quality; all four modes and
recovery-first conflict precedence; exact field-level evidence; deterministic
provenance; capture free-text exclusion; and stable daily/weekly same-period
recomputation. Recommendation tests prove that adding a Phase 2 daily snapshot
does not change deterministic candidate ranking. Aggregator assertions also
keep `summary.risk_flags` as the current Daily State alias, preserve older
window flags under `summary.window_risk_flags`, and derive
`recommended_next_focus` recovery-first from mode.

Account-control tests additionally cover strict bearer-derived timezone updates,
IANA validation, cross-owner export rejection, pagination and size bounds,
sanitized/omitted ledgers, exact download headers, exact delete confirmation,
session-bound and refresh-resistant 15-minute `amr` freshness rejection before
service calls, service-role-only RPC grants, both Phase 3 restrict links,
focus-first deletion, and the profile-cascade postcondition. Flutter tests cover the exact export
envelope/count parser, platform save/share cancellation truth, dedicated mobile
temporary-source cleanup, password recovery state and password validation,
rejected versus outcome-unknown timezone updates, device-persisted theme,
Settings capability gates, typed recent-auth and ambiguous-deletion notices,
and local session cleanup after a completed account deletion.
The export path also proves receive-time cancellation above 8 MiB, invalid
UTF-8 rejection, defensive raw-byte ownership, and byte-for-byte preservation
of large integers and precise decimals through the platform saver boundary.
The export checks pin 1,000-row server pages and the Flutter-only two-minute
receive timeout so the documented 50,000-row edge is not forced through the
ordinary 20-second JSON request path.
Migration-source tests inventory every repo-created canonical product/ledger
table and pin the application privilege guard's current-role, legacy-table,
projection, default-privilege, Auth-trigger-function, Notification-index, and
six `NOT VALID` timestamp-check statements. Those static tests do not prove a
particular local or remote database grant catalog; the local migration/reset
workflow and direct database inspection establish applied state separately.
Phase 3 backend tests validate strict `executable-action-v1` parsing and reject
unknown/coerced top-level and metadata fields, null/non-object metadata,
explicit-null metadata fields, invalid calendar dates,
kind/command/target/linkage mismatch, focus duration bounds, unsupported routes,
and command-specific metadata leakage in parity with Flutter. Snapshot tests
cover explicit completed/skipped habit outcomes plus focus
status/planned/actual-minute summaries, input counts, and evidence; focus local
`metadata.entry_date` wins over `started_at` after a broadened UTC read, with
deterministic UTC legacy fallback. Repository tests load more than 1,000 rows
from both action tables and assert stable offsets through the final page. They
also assert byte-for-byte-equivalent Phase 2 Daily State semantics for the same
capture inputs. Recommendation tests exclude terminal
done/cancelled/archived tasks from overdue, workload, and focus-pressure
candidates.
Phase 4 briefing tests prove that normal GET is read-only; authenticated routes
derive identity only from the bearer principal; local profile timezone selects
the briefing date; current generation is idempotent; changed snapshots mark a
briefing stale; recovery/missing-data rules precede overdue pressure; completed
or unscheduled habits are excluded; and every returned action passes the strict
`executable-action-v1` model with at most two support actions and no LLM use.
Phase 5 Flutter tests prove strict response/nested-action parsing, unknown-field
and freshness-shape rejection, bearer GET versus deliberate force POST,
guest/mock locality, current/missing/stale/error rendering, stale execution
disabling, and primary action dispatch. Dashboard tests keep direct source
metrics and recommendation failure truth intact below the new decision surface.
Phase 6 tests cover strict feedback parsing, exact owned-action validation,
idempotent request replay/conflict, authenticated GET/POST/DELETE, local-demo
isolation, 28-day context matching, decay/caps, unchanged original reasons, and
explicit feedback-ranking provenance. Insights tests prove insufficient versus
emerging/stronger observation labels, visible evidence windows, optional
bounded experiments, and non-causal copy. They also cover nullable persisted
confidence without a fabricated fallback, visible 7/14/30/90-day windows,
stable pagination across all five Supabase fact sources, the explicit 10,000-row
per-source client ceiling, missing/error retry truth, and readable Light/Dark
panel colors.
Phase 7 scheduled-preparation tests cover the backend-only token guard and
strict bounded request, including the maximum-20 `profile_ids` operational
filter and explicit `target_date` backfill override. Repository tests prove
that the filter still intersects onboarded
non-guest profiles; one captured timezone-aware UTC run instant resolves exact
profile-local dates; missing snapshots, missing briefings, stale snapshot
provenance, current pairs, and invalid timezones remain distinct; and a current
pair is selected only when an explicit recommendation pass still needs retry.
Service tests prove pinned local dates across different timezones, write-free
current briefing preparation, generated/reused snapshot and
generated/refreshed/unchanged briefing results, sanitized snapshot/briefing/
recommendation/profile-date failure stages, continuation after one user's
failure, and optional deterministic recommendation refresh with LLM wording
disabled. The default scheduled path does not generate recommendations or call
an LLM.
Phase 8 tests cover strict `weekly-review-v1` request/response parsing,
principal-derived ownership, profile-local completed ISO weeks across year/DST
boundaries, read-only latest/period GET, idempotent same-row generation, and
canonical source-fingerprint staleness. Fact tests keep completed/carried tasks,
stable versus changed habit definitions, completed/skipped/missed/recovery-open/
unknown opportunities, focus, recovery days, and feedback distinct. Repository
tests require stable full pagination and exact user/date scoping. Proposal tests
cap deterministic output at two, require matching `too_much` evidence before
the initial weekly-target shrink rule, preserve Setup ownership, and never apply
a user-owned mutation during generation.
Phase 9 tests cover strict `calendar-import-v1` and
`calendar-import-consent-v1` parsing, bearer-derived ownership, connection
without import, create/import request replay and conflict, bounded `.ics`
parsing, profile-local windows, stable event and recurrence identities,
identical versus conflicting duplicates, exclusive all-day dates, aware timed
intervals, explicit unsupported recurrence, cancellation tombstones, and
atomic replacement only after a complete valid parse. Repository/API tests also
cover stable event pagination and concurrent stale-projection detection,
read-only GET, exact body-free delete, disconnect retention, local imported-data
deletion, schedule preservation, global cross-owner/operation request identity,
reliable `PT409` conflicts, forced-RLS owner reads, and rejection of
authenticated direct or cross-owner writes.
Deadline Planner V1 focused coverage must keep `deadline-plan-v1` strict across
Pydantic and Flutter, require the user's explicit estimate/prior credit, and
prove deterministic timezone-aware blocks, honest unscheduled minutes, staged-
versus-active revisions, the 366-day horizon, separate latest/current revision
semantics, task-free draft cancellation, and exact retry/conflict behavior,
including replay returning a newer current detail projection without repeating
the original mutation. `preparation-workload-v1` coverage must require exactly
seven consecutive profile-local dates, strict arithmetic and provenance, active
confirmed-reservation totals, distinct active-plan counts, merged recurring
Setup commitments, and honest no-budget/over-budget/error states without
implying imported calendar or AI coverage.
`preparation-workload-detail-v1` coverage must independently require a date in
that current seven-day profile-local window; exact owner/date active-block
filters; at most 50 unique plan/title/minute/block contributions whose sum
equals the total; strict budget arithmetic and response keys; an empty
cross-owner projection; honest loading, retry, and changed-summary states; and
320 px/200-percent text plus browser navigation into review/replanning without
an automatic proposal or mutation. The original seven-day response shape must
remain unchanged.
Service and
migration tests must cover first-confirm managed-task creation, stable task
identity, generic task mutation/editor rejection and redirect, allowed open-task
focus, exact later-confirm fields, atomic matching terminal projection, linked
completed-focus progress without implicit completion, optional calendar busy-
time use, stale selected-event fingerprints, forced RLS, global
request identity, conflict instead of empty availability for disconnected/
deleted/missing-current imports, account cascade, export inclusion, and omitted
ledger policy. They must also cover nullable account-budget bounds and five-
minute increments, exact save/removal and response-loss reconciliation, owner-
derived persistence, authenticated direct-write denial, the shared owner lock,
other-plan deduction including earlier same-day confirmed blocks, and
confirmation conflict when capacity changed after preview.
Normal GET, import, Dashboard, scheduler, and focus-completion paths must remain
free of hidden proposal writes.
Phase 10 focused backend source coverage is split across strict model/API,
service, migration, and local-provider tests. It covers exact request/error
shapes and bearer-derived ownership; completed replay without context/provider;
public in-progress/conflict codes; missing-state uncertainty; deterministic
urgent safety bypass; unexpected provider failure terminalization; ambiguous
atomic completion; retained request-count budgets; message-free request claims;
exact completed message pairs; service-only memory selection; history
tombstones with retained usage; and authenticated mutation denial. The local
provider tests use fake runners to assert fixed argv, stdin-only prompt data,
allowlisted child environment, temporary-directory cleanup, explicit model
truth with no fallback, and rejection of tool/command/file events. This source
coverage is distinct from the opt-in live-Codex pass recorded below.
The follow-up migration contract test also checks that public
claim/complete/fail wrappers acquire the owner advisory lock before calling
their ungranted inner bodies, matching history-delete lock order. Additional
migration tests require exact provider-call safety provenance, backend-owned
profile identity fields, canonical-only role authority, rejected authenticated
profile deletion, and backend-owned onboarding eligibility. Real local
PostgreSQL parallel claim/completion/deletion smokes completed on 2026-07-13
without deadlock or timeout and converged on the expected message, usage, and
deletion outcomes.

Current Flutter widget tests include:

- Auth gate renders.
- Guest can complete required-only progressive Setup, persist exact empty
  optionals, and reach the dashboard without an invented goal, friction,
  routine, note, or commitment.
- Typed Setup model/data-source tests cover stable item keys, candidate versus
  confirmed cadence, `request_id`/`base_revision` request JSON, authenticated
  setup reads, and invalid response/error propagation.
- Setup widget/repository coverage exercises guest and authenticated prefill,
  loading/error/retry, retained drafts and request ids, edit without duplicate
  records, ambiguous-failure retry locking, review lifecycle actions, and the
  real Settings Setup entry.
- Auth repository tests prove mock/demo authenticated boot skips remote profile
  access and guest migration, restores local Setup name/completion across reload,
  and never leaks a remote onboarding marker into local-demo state.
- Setup save-state tests keep validation and HTTP 4xx failures editable, make
  409 suggest reload, and lock timeout/5xx/malformed results to exact retry or
  explicit reload.
- Capture-domain tests cover every bounded stress source, controllability,
  focus-band, friction, and day-shape value; rating, half-hour sleep, date, and
  text boundaries; omission of blank Evening optionals; and explicit inclusion
  of supplied reflection, blocker, and gentle-tomorrow values.
- Same-day merge tests cover Evening-then-Morning and Morning-then-Evening,
  replacing one branch without erasing the other, Morning-over-Evening energy
  precedence, removal of deliberately cleared optionals, preservation of
  foreign top-level metadata, and legacy V1 calendar-date compatibility.
- Capture payload tests assert one merged `daily_logs` row with
  `capture_version=daily-capture-v2`, nested `captures.evening|morning`, direct
  nullable compatibility values, and only explicitly available current
  `behavioral_events`. Event identities remain stable across exact retry and
  event metadata mirrors capture kind/date plus the relevant stress, friction,
  focus, priority, and day-shape context.
- Guest-store tests cover typed Evening/Morning JSON, both-order same-day merge,
  exact retry deduplication, V1 guest rows with an explicit local date, and
  recovery from corrupted local JSON.
- Evening widget tests cover required explicit selections, exact typed draft
  retention after failure, stable retry identity, prefilled re-entry with blank
  optionals still blank, and suppression of a duplicate in-flight write.
- The guest app smoke completes distinctive required-only Evening Shutdown and
  Morning Calibration, persists one local merged day, reads Morning energy over
  Evening energy, and shows the exact saved summary on return.
- Guest sees only locally functional Quick Actions; Supabase-only Habit
  Completion and Habit Management are hidden and their direct routes redirect.
- The Intake API data source gets `GET /v1/intake/setup` and posts
  `POST /v1/intake/complete` with bearer auth and the structured revisioned
  payload; authenticated failure does not invoke the old direct-write fallback.
- The optimization repository keeps normal recommendation reads as `GET` only,
  and the deliberate refresh path posts `POST /v1/recommendations/generate`
  with bearer auth, `force=false`, and `allow_llm_wording=false`.
- Recommendation repository/provider tests prove that only explicit guest/demo
  sessions receive demo feeds, even with a leftover token. Real missing-config,
  missing-token, network, and malformed-response paths throw and never consult
  mock data; current/missing/stale feed metadata is preserved.
- Dashboard mapper/widget tests assert exact raw values, Phase 1 capture
  provenance and structured context, Morning energy precedence, honest
  empty/error states, local source labels, and the absence of former proxy
  metrics.
- Capability, Settings, and notification tests cover the real-account Coach
  route plus guest/mock zero-call boundary, real synced Deep Work versus
  guest/mock redirect, unavailable guest/mock execution,
  persistent local-demo label, the strict `action_url` allowlist, original
  notification fields/read state, separate real empty/error states, strict
  due/dismiss visibility, lifecycle parser parity, confirmed read/unread/
  dismiss state, exact ambiguous retry, retained refresh data, accessibility,
  and 320 px/2x-text layout.
- Notification Delivery V1 model/repository/controller/widget tests keep saved
  reminder flags separate from explicit consent, validate generated provenance,
  stop consent-off before a pending-row query, filter disabled categories before
  the bounded query, retain an exact ambiguous settings retry, keep a definitive
  conflict locked through failed reloads, acknowledge before presentation,
  suppress receipt replays,
  render the explicit consent dialog/settings, and show one deterministic/no-
  LLM foreground banner. Weekly Review widget tests visibly distinguish direct
  manual actions from Setup guidance and non-executable staged suggestions.
- The Snapshot refresh service posts `POST /v1/snapshots/generate` with bearer
  auth in real backend mode, includes an explicit capture `target_date`, skips
  guest/mock/missing-token paths, and treats network failures as best-effort.
- Task, habit, and focus snapshot-refresh entrypoints route through the same
  authenticated daily behavior and preserve an explicit `target_date`. The
  focus page is implemented to pass its persisted start `entry_date` or legacy
  `started_at` date after start/finish/abandon.
- Guest can inspect the deterministic Insights correlation surface without
  requiring Supabase.
- The correlation analyzer covers positive, negative, missing, low-variation,
  and weak-relationship ranking behavior.
- The Insights repository keeps mock correlation data scoped to mock/guest mode
  and does not substitute demo correlations for empty or failing real Supabase
  reads.
- Source-boundary provider tests keep Setup, Evening/Morning capture, Dashboard,
  and Insights on local/demo sources when `USE_MOCK_DATA=true`, even if an
  authenticated Supabase session exists.
- Habit visibility tests exclude every Setup-managed habit from generic Habit
  Management while keeping active Setup habits in Habit Completion and hiding
  candidate/archived states.
- Executable task tests cover title/description/estimate validation, typed
  persistence mapping, owner-scoped create/edit/complete/postpone/cancel/
  restore transitions, stable create identity, undo data, retained failures,
  exact lifecycle shapes, and snapshot refresh boundaries.
- Habit V1 tests cover daily, selected ISO weekday, and weekly-target cadence;
  compatibility projections; completed/skipped/open/missed opportunity math;
  current ISO-week progress; completion streaks; same-day upsert/undo; manual
  lifecycle; Setup-owned execution authority; local `started_on`; and
  Europe/Berlin spring/fall DST calendar arithmetic.
- Focus tests cover planned-duration bounds, one optional owned target, active
  session parsing, measured whole-minute finish/abandon, terminal transitions,
  no implicit target completion, recent history, and snapshot refresh.
- Executable action-target tests cover every supported kind/command matrix,
  strict top-level/metadata shapes and scalar types, exact ids/dates/durations,
  task/habit/focus/capture routing, the real synced `review_plan` handler, and
  unsupported-command behavior. Dispatcher tests prove one typed handler per
  command, unavailable-before-handler behavior, and failure propagation.
- Weekly Review tests cover strict nested parsing, `not_ready`/missing/current/
  stale/error/local-demo states, latest GET versus deliberate generate/refresh,
  separate weekly facts, the two-proposal cap, stale disabled controls, exact
  before/after confirmation, cancel with zero writes, Setup deep-link without a
  generic write, manual Habit V1 expected-timestamp application, and guest/mock
  API isolation.
- Calendar import tests cover strict nested consent/connection/import/event
  parsing, authenticated bearer requests, local-demo zero-call selection,
  unchecked consent, connection-without-import, retained exact retry identity,
  imported/read-only source labels, stable pagination, event-local timezone and
  all-day rendering, no event mutation controls, and the distinct disconnect,
  retained-data, delete, empty, and error states.
- Controlled Coach tests cover strict capability/request/response/history/
  memory parsing; exact bearer-authenticated GET/POST/DELETE calls; guest/mock
  zero HTTP; timeout-aware exact retry identity and preserved drafts; duplicate
  submit prevention; distinct unavailable/rate-limit/error states; visible
  uncertainty, safety, provider/model/prompt/context provenance and `Data used`
  counts; review-only suggestions; memory selection/Setup routing; and confirmed
  conversation deletion without a direct Supabase Coach write.

These tests cover the default mock/guest product path. They do not prove real
Supabase registration, RLS, or browser behavior.

## Local Supabase Verification

From the repository root:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Runs Supabase with `HOME=.tools/supabase-home` and
   `SUPABASE_TELEMETRY_DISABLED=1` so the CLI does not need to write to the
   user's real home directory.
3. Starts the local Supabase stack.
4. Redacts Supabase keys from CLI output.
5. Reads `API_URL` and `ANON_KEY` from `supabase status -o env` without printing
   the key.
6. Runs Flutter tests from `apps/mobile` with:

```env
USE_MOCK_DATA=false
SUPABASE_URL=<local API URL>
SUPABASE_ANON_KEY=<local anon key>
```

With the default `RESET_DB=false` and `APPLY_MIGRATIONS=false`, the script runs
`supabase migration list --local` and requires every repository/DB history row
to match. It never applies pending SQL automatically. A mismatch fails before
reading client configuration or running Flutter tests and explains the two
explicit choices.

After reviewing the pending SQL and affected local rows, apply intentionally:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

The script warns that this may change or delete local rows, runs
`migration up --local`, and verifies history again before continuing. An empty,
unknown, or non-boolean flag value is rejected. `APPLY_MIGRATIONS=true` and
`RESET_DB=true` are mutually exclusive.

## Local Supabase Reset

Run this only when a local database reset is intended:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

This executes:

```bash
supabase db reset
```

Expected successful reset output applies migrations through:

```text
20260714143000_notification_delivery_settings_guard.sql
```

Expected notices include skipped legacy CamelCase tables and already-existing
canonical objects. Those notices are normal. Errors are not normal.

The final privilege-guard migration must leave `anon` with no repo-owned
product/ledger table privileges and remove authenticated `TRUNCATE`,
`REFERENCES`, and `TRIGGER` without erasing intended table-specific DML.
Backend projections stay authenticated read-only, optional legacy tables stay
mutation-frozen, and future public tables created by `postgres` inherit the
fail-closed defaults. Existing Auth triggers must still fire even though their
security-definer functions are no longer reusable by application or service
roles. Its Notification-ledger index and six `NOT VALID` timestamp-order checks
must exist; `NOT VALID` intentionally means old rows were not scanned, while
new and updated rows are constrained.

The Phase 3 migration backfills and constrains task, habit-log, and focus rows,
including missing focus `metadata.entry_date` from the UTC date of `started_at`.
It normalizes positive legacy habit values to completion and deliberately fails
if a legacy habit log has no status and `value <= 0`, because that row cannot be
interpreted honestly as completion or intentional skip. Inspect and resolve
such local data before retrying. The reset also installs exact task lifecycle,
locked active/weekday habit eligibility, bounded focus lifecycle, locked target
validation, one-active, all-update terminal immutability, and restrict-delete
target constraints/triggers. Existing local stacks may apply reviewed pending
migrations explicitly with:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

This is not a non-destructive claim: migration SQL may change or delete local
rows even when it does not reset the entire database.

Use the reset form to prove the complete migration chain from an empty local
database; do not use it merely because a reviewed migration is pending.

The reset destroys and recreates the local Supabase database. It must not be
used for a remote project.

## Browser E2E

Browser E2E is implemented with Playwright:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

This is the normal non-reset database path: the script starts or reuses the
repository's local Supabase stack, skips `supabase db reset`, inspects
`supabase migration list --local`, and fails when repository and database
history differ. It never applies pending SQL automatically. The smoke still
writes a uniquely named local Auth user and its test rows. Do not set
`RESET_DB=true` unless recreating the local database is explicitly intended.

After a full or partially completed run has already created and onboarded its
E2E principal, Phase 10 can be repeated narrowly for diagnosis:

```bash
E2E_PHASE10_ONLY=true \
E2E_RUN_ID=<existing-e2e-run-id> \
FLUTTER_BIN=/path/to/flutter \
bash scripts/e2e_web.sh
```

This mode signs in to the existing `e2e-<run-id>@example.test` principal,
resets only its Coach E2E state, and repeats the fake-provider Coach UI/API/RLS
assertions. It does not create the prerequisite principal or exercise Setup,
capture, executable actions, briefing, feedback, weekly review, or calendar
import. Treat it as a focused diagnosis/repetition path, never as a substitute
for the full command.

For a fresh local database before the browser run:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

If an existing local database differs from repository migrations, review the
pending SQL and affected local rows before opting into application:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
bash scripts/e2e_web.sh
```

This may change or delete local rows. The script verifies history again before
starting FastAPI, Flutter, or Playwright.

Use real Ubuntu-installed Node.js, npm, Supabase CLI, and Docker. If these tools
are installed through nvm, non-interactive agent shells may need an explicit
`PATH` or `NODE_BIN` override even when `node --version` works in the user's
interactive shell. Do not install replacement tool binaries into `.tools/`.

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Starts the local Supabase stack and optionally runs `supabase db reset`.
3. Reads `API_URL`, `ANON_KEY`, and `SERVICE_ROLE_KEY` from
   `supabase status -o env` without printing key values.
4. Starts the FastAPI AI service on `127.0.0.1:8000` by default with backend
   local Supabase settings, a run-scoped scheduled-refresh token, and
   `COACH_PROVIDER=fake` plus `COACH_FAKE_PROVIDER_ENABLED=true`. Standard E2E
   never contacts a live Codex account.
5. Starts Flutter Web on `127.0.0.1:7357` with `USE_MOCK_DATA=false` and
   `AI_SERVICE_BASE_URL` pointing at the local FastAPI service.
6. Passes the same token only to the Node assertion process and runs
   `e2e/web/smoke.mjs` with Playwright. The token is never passed to Flutter.

The script waits for the Flutter log line containing `is being served at` before
starting Playwright. A plain `curl` response from `/` is not enough, because
`flutter run -d web-server` can answer before the debug web bundle is ready; if
Playwright opens the page during that window, screenshots are often blank white.

The E2E Flutter process also passes `--dart-define=E2E_ENABLE_SEMANTICS=true`.
`apps/mobile/lib/main.dart` uses that test-only flag to keep Flutter Semantics
enabled, which gives Playwright stable text fields, buttons, and labels instead
of relying on canvas pixels.

The browser smoke creates a confirmed local Supabase Auth user through the local
admin API and walks the Phase 0C Setup journeys before continuing through the
existing product smoke. It covers required-only completion with zero optional
owned records; one explicit goal, routine candidate, and fixed commitment;
retry after a response is lost; prefilled edit with stable identity; cadence
confirmation; and review actions that archive/pause/remove Setup-owned rows.
Node-side fixtures include manual rows, and database assertions require those
rows to survive reconciliation unchanged.

After the Phase 3 action journeys, the smoke also exercises Phase 4 directly
through authenticated FastAPI calls. It proves that the first briefing GET is
read-only and missing, deliberate POST persists exactly one owner/local-date
row, response and JSONB action payloads match, every returned target is an
implemented strict command, and a repeated `force=false` request preserves the
same id and timestamps.
It then opens Dashboard and proves Phase 5 normal load issues no briefing POST,
renders the exact persisted primary title, dispatches the returned real command,
and sends exactly `{"force":true}` only after `Adjust today`, preserving the
same daily briefing identity.
Phase 6 then records `too_much` through Today, asserts the exact owner-scoped
database row and ranking provenance after adjustment, opens history, deletes the
entry, and proves a subsequent generation returns to zero feedback influence.
It also proves Insights begins with one cautious observation and keeps the
correlation controls inside explicit advanced exploration.

The Phase 7 portion calls the protected scheduler only with the uniquely named
E2E profile through the bounded `profile_ids` filter; it does not run an
unscoped batch against unrelated local accounts. It compares the scheduler's
captured UTC `run_at` with the profile timezone, requires the exact local
briefing date, and accepts only a missing snapshot or missing briefing as the
first preparation reason. Database assertions prove one exact daily snapshot
and one exact briefing identity, deterministic/no-LLM provenance, and exact
source-snapshot id and timestamp linkage. A repeated scheduled request must
process zero users and leave both rows and timestamps unchanged. The subsequent
Dashboard path remains GET-only; the E2E scheduler token stays outside Flutter.

The Phase 8 portion seeds one completed profile-local ISO week with exact task,
manual and Setup-owned habit, habit-outcome, focus, daily-state, and
decision-feedback rows. Latest GET must report missing without a write;
deliberate generation must persist exactly one owner/period review whose facts,
fingerprint, no-LLM provenance, and at-most-two proposals match the response.
A repeated read remains write-free. Cancelling the before/after dialog changes
nothing; confirming the eligible manual weekly-target shrink must preserve the
habit identity/ownership/logs, use its exact expected timestamp, and make the
old review stale. Setup-owned review navigation must not write a habit or goal.
Deliberate refresh reuses the same weekly review identity. Authenticated REST
assertions use a second principal to prove owner-only SELECT and rejection of
direct review-table writes/cross-owner habit changes.

The Phase 9 source portion starts from an exact empty read, confirms explicit
read/store consent, and proves that connection alone creates no import/event.
It imports bounded `.ics` fixtures with duplicate, all-day, timezone-aware,
materialized recurrence, unsupported recurrence, and cancellation cases;
asserts stable retry/event identities plus paginated read-only provenance; and
keeps `schedule_items` byte-for-byte unchanged. Separate confirmations prove
disconnect retains the stale local copy while delete removes only integration
events/history. The opaque fingerprint-free request ledger rejects reuse across
operations and owners, a disconnected or superseded import cannot replay, and
DELETE rejects a body. A second principal checks owner-only visibility and
rejected direct/cross-owner writes. Guest/mock coverage remains zero-call.
The complete combined browser command passed these assertions non-destructively
in the 2026-07-13 Phase 9 implementation checkout.

Deadline Planner interaction coverage is currently split honestly across two
layers. Flutter widget tests drive the calendar prefill and three-step wizard,
require explicit exam/assignment and distinctive total/prior inputs, inspect the
staged preview, confirm explicitly, retain and rebase a draft after `409`, and
exercise the narrow/large-text layout. They additionally cover Settings budget
save/removal, the 320-pixel/200-percent dialog and seven-day card, account-cap
deduction, and truthful loading/error/overage states. The browser/database
journey creates and
activates the lifecycle through the authenticated API, then verifies the real
Flutter active-plan surface, managed-task/focus behavior, no `schedule_items` or
imported-event mutation, owner/cross-owner authority, Account Export inclusion/
cascade, and guest zero-call. It also sets and reads the budget through the
authenticated product boundary, rejects direct profile mutation and request-
provided identity, validates the strict seven-day workload, proves a stale
preview cannot confirm after the budget is lowered, restores the setting, and
checks Today/Preparation plans without broadening calendar claims. It does not
currently claim that Playwright drives
the wizard itself; a single end-to-end browser wizard journey remains additional
coverage rather than evidence already supplied by the API-seeded journey.

The Phase 10 source portion uses only the deterministic fake provider. It is
designed to assert read-only capability/history/memory calls, explicit memory
selection, one deliberate bounded response, exact persisted message/request/
usage identity, same-id replay without another durable turn, conflicting-id
rejection, deterministic safety bypass, visible UI provenance and review-only
suggestion, conversation deletion with retained tombstones/usage, owner-only
reads and rejected authenticated mutations, plus guest/mock zero Coach calls.
On 2026-07-13 a focused non-reset run with `E2E_RUN_ID=1783945829` passed. The
subsequent full current-checkout command also passed non-destructively against
local Supabase with the deterministic fake provider and reported
`E2E browser smoke passed for e2e-1783947134@example.test`.

The Setup assertions inspect exact `request_id`, base/revision, applied state,
stable materialized ids, server ownership metadata, record counts, and the
constant onboarding snapshot identity. A named unconfirmed routine must remain
only in `intake_responses`; it must not appear as an active daily habit. Replaying
one request must return the same result without another revision or owned row,
while a real edit advances the revision and preserves stable record ids. After
the UI journeys, two simultaneous authenticated POSTs with the same new request
id must both return the same applied revision, produce exactly one
`intake_responses` row, and advance `profiles.setup_revision` only once. This
exercises the migrated advisory-lock RPC against real local PostgreSQL rather
than only the in-memory concurrency tests.

The smoke then creates a habit through Habit Management and follows
`/daily-check-in` into the canonical Evening Shutdown at
`/quick-mood-check-in`. It records distinctive mood `2`, Evening energy `9`,
stress `8`, private/emotional hardly-controllable stress, a focus band,
friction, and tomorrow priority while leaving reflection, specific blocker, and
gentle-tomorrow blank. Playwright lets the first `daily_logs` upsert commit but
drops its browser response, verifies that the exact draft remains available,
then retries without creating another daily row or event set.

The same browser user then completes `/morning-calibration` with sleep `5.5`,
Morning energy `4`, and constrained day shape. Database assertions require
exactly one `(user_id, entry_date)` row with
`metadata.capture_version=daily-capture-v2`, both nested capture branches,
absent blank optional keys, mood/stress from Evening, sleep from Morning, and
Morning energy taking precedence in `energy_level`. The smoke reopens Evening,
checks its saved state, edits stress to workload/mostly-controllable and the
priority, and requires the exact Morning capture identity and values to remain.

Linked current-event assertions require three explicit events after
Evening-only and exactly four after Morning merge and Evening edit. All final
events share the daily-log id, have unique deterministic ids, carry the correct
numeric value/unit, and mirror their relevant `capture_kind`, `entry_date`,
capture id/time, stress taxonomy, focus/friction/priority, or day-shape
metadata. Capture success sends `POST /v1/snapshots/generate` with the explicit
local `target_date`; the committed-response failure does not. Normal capture is
also observed to make no browser request to
`POST /v1/recommendations/generate` and to leave Setup revisions/profile
projection plus unrelated task, goal, habit, schedule, memory, notification,
and recommendation identities unchanged.

The browser also inspects each Phase 2 snapshot response. Evening-only
private/emotional, hardly-controllable stress must produce partial `recover`
state with exact source risks. Adding target-day Morning sleep `5.5`, energy
`4`, and constrained day shape must produce current `recover` state. Editing
Evening to workload/mostly-controllable must keep the same snapshot id, add
workload risks, remove stale private/low-control risks, retain recovery because
of current compound signals, and persist exactly one target-period row. The
assertions require `explainable-daily-state-v1`, deterministic/no-baseline
provenance, field-level evidence for the daily log, and absence of both original
and edited priority text from summary and signals.

After the Phase 1/2 assertions, the Phase 3 browser journey completes, undoes,
skips, and undoes a manual habit; completes and undoes an active Setup-owned
habit without mutating its definition; and asserts one explicit outcome row at
most per habit/local date. It creates and edits one typed task without changing
identity, postpones and undoes the deadline, completes/restores, and
cancels/restores while checking exact status, estimate, and terminal timestamp
rows. Habit and task creates deliberately lose one committed HTTP response, then
prove that retained drafts and stable request ids converge on one row. Habit
outcome and undo each lose a committed response; reconciliation must prove the
exact row or its absence for the target date captured before the write, and
refresh that same date.

The journey then starts and finishes a task-linked focus session, proves that
the task was not completed implicitly, and starts/abandons an independent
session. Database assertions cover one active session at a time, terminal
timestamps, measured whole elapsed minutes, target linkage, and no remaining
active row. Focus start also loses one committed response and must reconcile the
same active session before refreshing its persisted start date. Task completion,
task undo, and focus finish each lose a committed transition response and must
accept the exact stored result without a second transition. Negative database
checks reject a task terminal without its timestamp, a second active focus
session, terminal-focus lifecycle, `entry_date`, and `updated_at` rewrites, an
out-of-range focus duration, and outcomes for an inactive or unscheduled
selected-weekday habit. A refreshed daily snapshot must contain the explicit
habit/focus input counts and neutral summaries while preserving the Phase 2
Daily State, and observed task/habit/focus writes must make no
recommendation-generate request.
The smoke then uses deliberate recommendation refresh and exercises Inbox
(`/alerts`) through one real unread/read/unread/dismiss lifecycle. It checks
the exact FastAPI payload/result, persisted tombstone and three-row retry
ledger, exact replay, request-id reinterpretation conflict, foreign-owner 404,
owner/cross-owner SELECT, direct authenticated DML rejection, ledger
invisibility, due filtering, and dismissal after reload. It then exercises the
Controlled Coach journey against the deterministic fake provider, verifies real
Deep Work, and checks the explicit payloads of manual snapshot/recommendation
requests. Source coverage is not a current-checkout pass.

These assertions are present in `e2e/web/smoke.mjs`; run one of the commands in
this section to establish pass/fail for the current checkout. Documentation of
the path is not evidence that a current full browser run passed.

`e2e/web/smoke.mjs` navigates Flutter routes through root hash URLs such as
`/#/auth`, `/#/daily-check-in`, and `/#/morning-calibration`. This avoids direct
deep-link requests against the `flutter run -d web-server` development server,
which does not provide a production-style rewrite layer for every app path.

The service-role key is used only in the Node-side E2E process for local setup
and assertions and in the FastAPI process for backend persistence. It must never
be passed into Flutter or browser runtime configuration.

The E2E script generates a local scheduled-refresh token unless an override is
provided. It passes that token only to FastAPI and the Node assertion process,
does not print it, and never exposes it through Flutter configuration.

The canonical schema grants app-table privileges to `service_role` so these
local REST assertions can query rows after RLS-protected browser writes.

Useful overrides:

```bash
NODE_BIN=/path/to/node
CHROME_BIN=/path/to/chrome
HEADED=true
HOST=127.0.0.1
PORT=7357
APP_URL=http://127.0.0.1:7357
AI_SERVICE_HOST=127.0.0.1
AI_SERVICE_PORT=8001
AI_SERVICE_BASE_URL=http://127.0.0.1:8001
AI_SERVICE_PYTHON=/path/to/python
AI_SERVICE_START=false
SCHEDULED_REFRESH_TOKEN=local-e2e-override
E2E_RUN_ID=manual-001
```

By default, `scripts/e2e_web.sh` starts FastAPI from the current checkout and
does not reuse an arbitrary service that is already listening on the same port.
If the port is occupied, stop that service or set `AI_SERVICE_PORT` to a free
port. Use `AI_SERVICE_START=false` only when you intentionally want to reuse a
compatible FastAPI process that is already running with the same local Supabase
project settings and scheduled-refresh token.

Flutter Web logs for the E2E run are written to:

```text
.tools/e2e/flutter-web.log
```

FastAPI logs for the E2E run are written to:

```text
.tools/e2e/ai-service.log
```

On browser failure, Playwright saves a screenshot named:

```text
.tools/e2e/failure-<run-id>.png
```

`.tools/` is ignored by git.

## Phase 10 Provider Verification

Phase 10 keeps two strictly separate paths:

1. The default deterministic path uses a fake provider/process runner in
   pytest, Flutter tests, and the configured browser environment. It asserts
   strict HTTP/models, request replay, safety, memory/history behavior, fixed
   argv, stdin-only prompt transport, temporary-directory cleanup, an
   allowlisted environment, explicit model truth, and unsafe tool-event
   rejection. Before a full boundary claim, the combined suites must also prove
   no application secret reaches the child, mandatory feature disabling and
   unavailable tool-free state, strict output/timeout/process termination,
   sanitized errors, owner scoping, context caps/exclusions, retry/budget,
   memory/RLS, Flutter states, and zero hidden calls.
2. `services/ai_service/tests/test_local_codex_smoke.py` is the deliberately
   separate per-machine real-model smoke. It is skipped unless
   `RUN_LOCAL_CODEX_SMOKE=true`, uses only synthetic context, and must print no
   prompts, OAuth/account data, paths, raw JSON events, stderr, or tokens. Run
   it only with the explicit local provider settings and an existing login:

```bash
cd services/ai_service
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

The opt-in smoke proves only the exact machine, CLI version, account, and model
tested at that time. It does not prove availability for another developer's
Plus/Pro account and is not evidence of production readiness. A missing login,
unavailable model, rate/account limit, invalid output, or timeout is an honest
smoke failure, never a reason to add an API-key or model fallback silently.

Recorded local result on 2026-07-13: the synthetic-context smoke completed
against the explicitly requested `gpt-5.5` model (`1 passed`), with no fallback
and no answer, prompt, OAuth/account data, or raw event stream logged.
This does not replace the fake-provider browser journey or satisfy the separate
another-developer/login acceptance check.

Recorded full-product local result on 2026-07-13 in the working tree based on
`b8c7935`: an existing onboarded local E2E principal authenticated through
Flutter Web, loaded a ready `local_codex_oauth` capability from FastAPI, and
deliberately received one validated and persisted `coach-response-v1` through
the same Linux user's logged-in Codex CLI. The configured request was exactly
`gpt-5.5`, no fake provider or fallback was enabled, and persisted provenance
reported `source=model`, `provider_called=true`,
`controlled-coach-prompt-v1`, and `coach-context-v1`. The CLI did not provide a
reliable selected-model event, so `model_reported` truthfully remained `null`.
Flutter rendered the response, expanded `Data used`, and expanded provider/model
truth; authenticated history returned the exact turn. The harness logged only
sanitized contract/provenance/count results, never the question, assembled
prompt, answer, raw event stream, stderr, account identity, path, token, `.env`
value, or Supabase key.

That live manifest included current profile and daily snapshot; a stale daily
briefing; current goals, tasks, habits, and focus sessions; and explicitly
omitted the stale weekly review. No memory was selected and no previous
completed turn entered context. This proves the first local live-account
product-path criterion on this machine only. The separate clone/setup/login
acceptance with another Linux user and their own eligible account remains open.

Keep the smoke out of the standard verification-level table and CI. It is an
explicit account/network action, not a prerequisite for deterministic checks.

## Local Tool State

The scripts use a local CLI home at:

```text
.tools/supabase-home
```

This directory is ignored through `.tools/`. It may contain CLI state and must
not be committed. Do not install tool binaries into `.tools/`; install real
Ubuntu tools so commands such as `supabase --version`, `node --version`,
`npm --version`, and `npx --version` work in the Ubuntu shell.

## Secrets And Logs

Do not paste, print, or commit Supabase keys. Local anon keys may be used by the
Flutter client for local development, but they should still be treated as
credentials in chat and logs.

`scripts/verify_supabase_local.sh` and `scripts/e2e_web.sh` intentionally print
availability messages instead of key values:

```text
Local anon key: available
Local service role key: available for backend and Node-side assertions
```

If command output includes a key unexpectedly, redact it before sharing logs.

Codex OAuth state is also secret. Verification may run sanitized commands such
as `codex login status`, but must never read, print, copy, snapshot, or attach
`~/.codex/auth.json` or equivalent CLI state. The Phase 10 child process must
receive an allowlisted environment rather than inheriting FastAPI's Supabase
service-role key or other backend secrets.

## Current Automation Gap

The repository now contains browser E2E automation, but it still depends on a
real Ubuntu Node.js 20+ installation, `npm`, Playwright browser installation,
Docker access, and a real Ubuntu `supabase` CLI on `PATH`.

The combined Phase 3/4/5/6/7/8/9 browser journey first passed in the Phase 9
implementation checkout. A focused Phase 10 run and the subsequent full
Phase 3-through-10 journey passed without a database reset against local Supabase in
the 2026-07-13 current checkout. Later changes must establish their own full
result with the browser command above; the focused mode is diagnostic only, and
the `RESET_DB=true` form is reserved for proving the migration chain from a
fresh database. The full journey
includes committed-response-loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish, plus negative
lifecycle/range/active-target/weekday-cadence checks and terminal-focus
`updated_at` mutation. Phase 8 adds a second principal for weekly-review RLS and
one cross-owner habit attempt; it still does not directly exercise restrict-
delete FKs. It also does not seed more than one habit/log page to prove
the browser pagination boundary or carry a focus session across local midnight
to assert the refresh date in-browser. Backend repository tests separately
cover more than 1,000 habit-log and focus-session rows. Do not infer the other
paths merely from the same-user UI journey.

Phase 7 targeted scheduled-preparation, Phase 8 bounded weekly-review, and Phase
9 bounded calendar-import assertions passed as part of that non-destructive
2026-07-13 browser run. They verify only the local test stack and uniquely named
E2E profile. They do not establish remote database state, deployed cron
execution, production token configuration, weekly scheduling, notification
delivery, or autonomous planning.

Notification Delivery V1 currently has focused backend contract/repository/
service/API/scheduler/migration tests and Flutter parser/controller/settings/
Inbox/banner tests. The browser source now also encodes explicit UI consent,
settings replay/conflict, scheduler generation, privacy-safe provenance,
dedupe, category/quiet/cap rejection, foreground receipt, Inbox truth, and
receipt replay suppression. After explicit authorization,
`20260714130000_notification_delivery_v1.sql` was applied to the local stack and
the reviewed `20260714143000_notification_delivery_settings_guard.sql` follow-up
was subsequently applied without a reset. Local history matches the repository.
A rollback-only database smoke verified exact replay, expected-revision
conflict, Setup-style monotone timestamps, consent ordering, and identity
invalidation. The full non-reset current-checkout browser journey passed on
2026-07-14 with
`E2E browser smoke passed for e2e-1784046486@example.test`. That run exercised
the real local Flutter -> FastAPI -> Supabase consent, deterministic generation,
policy rejection, foreground receipt, banner, Inbox refresh/provenance, dedupe,
and replay boundaries. It exposed and fixed a stale Inbox provider after a
foreground receipt before the recorded passing rerun.
Focused source tests also cover recovery opt-out suppression, Phase 8
fingerprint freshness,
request-exact Settings replay, monotone cross-writer revisions, category
starvation, and the reload-required Flutter state.

The Phase 8 pass also does not establish complete task-transition history,
historical habit-definition revisions, or remote RLS state.

Phase 9 source coverage is not a real Google/Microsoft/Apple Calendar test. It
uses selected local `.ics` bytes and does not establish provider OAuth, token
refresh/revocation, arbitrary URL fetch, incremental/background sync, provider
writes, mobile-native file-picker behavior, or remote RLS state.

Deadline Planner source coverage likewise does not establish long-term study
outcomes, a live provider calendar, notifications, background replanning,
remote migration/RLS state, or an installed-device pass. No passing browser or
local migration result should be recorded until the full current-checkout
commands complete after the new migration is applied.

Those local commands completed on 2026-07-18. A rollback-only database smoke
verified manual and current-calendar proposal/confirmation, active-Focus and
stale-Focus guards, exact collection/detail projection, and a 1,202-block
projection without PostgREST truncation. The complete AI-service suite reported
`745 passed, 1 skipped`; the final standard source gate reported a clean Flutter
analysis and `579` passing Flutter tests. The final post-polish non-reset
combined browser run reported
`E2E browser smoke passed for e2e-1784404040@example.test`. That is evidence for
this local current checkout only and does not expand any of the non-claims
above. The manual five-student usability study remains not run.

The subsequent five-agent compressed persona walkthrough on 2026-07-18 is
documented in
`docs/synthetic-student-persona-simulation-2026-07-18.md`. It produced code-
backed findings, not participant or two-month evidence. After its fixes, the
changed-area suites reported `63` Flutter tests and `14` focused Deadline
Planner backend tests; the complete FastAPI suite reported
`748 passed, 1 skipped`. The standard gate and non-reset local Supabase check
each passed all `591` Flutter tests with clean analysis and matching local
migration history. The full non-reset browser journey reported
`E2E browser smoke passed for e2e-1784413991@example.test`. These results apply
only to this local checkout and do not change the manual/external gaps below.

The optional account-wide preparation-capacity follow-up completed on
2026-07-19. The complete FastAPI suite reported `763 passed, 1 skipped`; the
standard gate and subsequent non-reset local Supabase preflight each passed all
`601` Flutter tests with clean analysis and matching migration history through
`20260719120000_account_preparation_budget_v1.sql`. The full non-reset browser
journey reported
`E2E browser smoke passed for e2e-1784448992@example.test`. It covered the exact
budget Settings request, authenticated direct-write rejection, strict seven-day
workload, cross-plan deduction, a budget change between preview and confirm,
retained staged state after exact `409`, Today/Preparation-plans rendering,
cross-owner isolation, export, and guest zero-call. This remains local evidence;
the five-student study is still unrun and no remote, installed-device,
background-delivery, production-provider, localization, or longitudinal claim
is added.

The compatible actionable workload-day follow-up also completed locally on
2026-07-19. Its focused backend suite reported `27 passed`; the complete FastAPI
suite reported `766 passed, 1 skipped`. After a browser-discovered nested-modal
navigation defect was fixed, the standard gate and non-reset local Supabase
verification each passed all `608` Flutter tests with clean analysis and
matching migration history. The final full non-reset browser journey reported
`E2E browser smoke passed for e2e-1784465767@example.test`. It covered strict
owner/date detail arithmetic, cross-owner emptiness, on-demand Flutter detail,
exact overage copy, staged replan entry, and a root modal barrier that prevents
Shell navigation from stealing `Cancel`. This is local evidence only; the
five-student study and all remote, installed-device, background-delivery,
production-provider, localization, and longitudinal checks remain unrun.

Phase 10 has focused fake-provider/process-runner, strict contract, service,
migration, repository, controller, and widget tests in the checkout. Its
focused browser path and the subsequent full fake-provider browser journey
passed locally in this checkout. The development-only local Codex OAuth
adapter's opt-in synthetic-context smoke and the separate authenticated
Flutter-to-live-Codex product path also passed on this machine with explicit
`gpt-5.5`; these results establish neither remote state, another account's
availability, nor production readiness. Multi-developer acceptance still needs
one different Linux user to clone, authenticate their own eligible account, and
complete the documented path without copied credentials.

Known harmless local E2E output includes Chromium WebGL performance warnings.
The FastAPI AI service must be healthy for the browser smoke to pass.

Still missing for broader product verification:

- CI wiring for the browser E2E command.
- Playwright trace artifact collection on failure.
- Deployed scheduler/cron wiring and monitoring; the repository verifies the
  protected preparation endpoint, not any production invocation platform.
- Android/system notification delivery is not part of Notification Delivery V1
  and remains absent; physical-device foreground acceptance is still useful.
- Installed-device Google OAuth/recovery acceptance, a complete physical-device
  layout/accessibility pass, and best-effort authenticated guest check-in
  migration. Widget tests cover the critical 320 px/text-scale surfaces, but
  do not replace device acceptance. Guest Setup intentionally has no automatic
  account migration.

When changing E2E flows, keep `e2e/web/smoke.mjs`, `scripts/e2e_web.sh`, and
this document in sync.
