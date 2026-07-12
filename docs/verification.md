# Verification And Agent Automation

This document is the shared runbook for automated checks. It describes what can
be verified by agents without manual app exploration, what requires local
tooling, and what remains future work.

## Verification Levels

Use the lowest level that covers the change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Standard | `FLUTTER_BIN=/path/to/flutter scripts/verify.sh` | Non-destructive repo checks. | No |
| Local Supabase preflight | `FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Starts local Supabase and runs tests with Supabase config. | No |
| Local Supabase reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Recreates local DB, applies migrations, then runs tests. | Yes, local DB only |
| Browser E2E | `FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Starts local Supabase, starts Flutter Web, drives Playwright, and checks DB writes. | No |
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
bounded experiments, and non-causal copy.
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
- Capability, Settings, and notification tests cover gated Coach, real synced
  Deep Work versus guest/mock redirect, unavailable guest/mock execution,
  persistent local-demo label, the strict `action_url` allowlist, original
  notification fields/read state, and separate real empty/error states.
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
  task/habit/focus/capture routing, explicit `review_plan` unavailability, and
  unsupported-command behavior. Dispatcher tests prove one typed handler per
  command, unavailable-before-handler behavior, and failure propagation.

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

Without `RESET_DB=true`, the script does not reset the database. It is useful as
a Docker/Supabase/toolchain preflight plus app test run.

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
20260712190000_phase_6_decision_feedback.sql
```

Expected notices include skipped legacy CamelCase tables and already-existing
canonical objects. Those notices are normal. Errors are not normal.

The Phase 3 migration backfills and constrains task, habit-log, and focus rows,
including missing focus `metadata.entry_date` from the UTC date of `started_at`.
It normalizes positive legacy habit values to completion and deliberately fails
if a legacy habit log has no status and `value <= 0`, because that row cannot be
interpreted honestly as completion or intentional skip. Inspect and resolve
such local data before retrying. The reset also installs exact task lifecycle,
locked active/weekday habit eligibility, bounded focus lifecycle, locked target
validation, one-active, all-update terminal immutability, and restrict-delete
target constraints/triggers. Existing local stacks may apply pending migrations
non-destructively with:

```bash
HOME=.tools/supabase-home \
SUPABASE_TELEMETRY_DISABLED=1 \
supabase migration up --local
```

Use the reset form to prove the complete migration chain from an empty local
database; do not use it merely because a non-destructive migration is pending.

The reset destroys and recreates the local Supabase database. It must not be
used for a remote project.

## Browser E2E

Browser E2E is implemented with Playwright:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

This is the normal non-destructive database path: the script starts or reuses
the repository's local Supabase stack and skips `supabase db reset`. The smoke
still writes a uniquely named local Auth user and its test rows. Do not set
`RESET_DB=true` unless recreating the local database is explicitly intended.

For a fresh local database before the browser run:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

If an existing local database is behind the repository migrations, apply pending
local migrations before running the smoke:

```bash
HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local
```

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
   local Supabase settings plus a run-scoped scheduled-refresh token.
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
The smoke then uses deliberate recommendation refresh, opens
Notifications, verifies real Deep Work and the gated Coach route, and checks the
explicit payloads of manual snapshot/recommendation requests.

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

## Current Automation Gap

The repository now contains browser E2E automation, but it still depends on a
real Ubuntu Node.js 20+ installation, `npm`, Playwright browser installation,
Docker access, and a real Ubuntu `supabase` CLI on `PATH`.

The combined Phase 3/4/5/6/7 browser journey passed non-destructively in the
2026-07-12 Phase 7 implementation checkout. Future changes must establish their own
current-checkout result with the browser command above; use the `RESET_DB=true`
form when proving the full migration chain from a fresh database. The journey
includes committed-response-loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish, plus negative
lifecycle/range/active-target/weekday-cadence checks and terminal-focus
`updated_at` mutation. It does not yet construct a second authenticated
principal for an explicit cross-user target attempt or directly exercise
restrict-delete FKs. It also does not seed more than one habit/log page to prove
the browser pagination boundary or carry a focus session across local midnight
to assert the refresh date in-browser. Backend repository tests separately
cover more than 1,000 habit-log and focus-session rows. Do not infer the other
paths merely from the same-user UI journey.

Phase 7 targeted scheduled-preparation assertions passed as part of that
non-destructive 2026-07-12 browser run. They verify only the local test stack and
uniquely named E2E profile. They do not establish remote database state,
deployed cron execution, production token configuration, or notification
delivery.

Known harmless local E2E output includes Chromium WebGL performance warnings.
The FastAPI AI service must be healthy for the browser smoke to pass.

Still missing for broader product verification:

- CI wiring for the browser E2E command.
- Playwright trace artifact collection on failure.
- Deployed scheduler/cron wiring and monitoring; the repository verifies the
  protected preparation endpoint, not any production invocation platform.
- Dedicated database assertions for notifications, notification preferences,
  and non-Setup memory behavior beyond the current Setup ownership/snapshot
  checks.
- Coverage for Google OAuth, mobile layout, and best-effort authenticated guest
  check-in migration. Guest Setup intentionally has no automatic account
  migration.

When changing E2E flows, keep `e2e/web/smoke.mjs`, `scripts/e2e_web.sh`, and
this document in sync.
