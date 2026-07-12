# Local Development

This guide is written for a fresh clone. It avoids machine-specific paths and
does not assume any user-local Codex skills.

## Prerequisites

- Flutter SDK. Confirm with `flutter --version`.
- Python 3.11+ for the AI service and static web fallback.
- Node.js 20+ and npm for browser E2E. Confirm with `node --version` and
  `npm --version` in the Ubuntu shell.
- Optional: Supabase CLI and Docker for local Supabase work. Install the real
  Supabase CLI so `supabase --version` works in the Ubuntu shell; do not rely on
  a repo-local binary. Confirm Docker with `docker --version`.

If Node.js, npm, or Supabase CLI are installed through `nvm`, remember that
non-interactive agent shells may not source nvm automatically. In that case,
source nvm before running commands or pass a narrow override such as:

```bash
PATH=/path/to/nvm/versions/node/vXX/bin:$PATH \
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

Do not install tool binaries into `.tools/`; `.tools/` is only for ignored local
runtime state and artifacts.

If Flutter is not on `PATH`, set `FLUTTER_BIN` when running scripts:

```bash
FLUTTER_BIN=/path/to/flutter scripts/start_frontend.sh
```

## First Run

From the repository root:

```bash
cp .env.example .env
scripts/start_frontend.sh
```

Open:

```text
http://127.0.0.1:7357
```

Choose **Continue as guest**. The default local workflow uses mock data and does
not need Supabase.

## Environment

The root `.env.example` documents the shared local values:

```env
APP_ENV=development
USE_MOCK_DATA=true
SUPABASE_URL=
SUPABASE_ANON_KEY=
AI_SERVICE_BASE_URL=http://localhost:8000
```

The Bash and PowerShell start scripts pass these values into Flutter as Dart
defines.

`USE_MOCK_DATA=true` is a deliberate whole-product local/demo boundary even if
the browser still has a Supabase auth session. Setup, Evening Shutdown, Morning
Calibration, Dashboard, Recommendations, Insights, and Notifications stay
local; synced task, habit, and focus commands are unavailable; and snapshot
refresh is skipped. Set it to `false` to exercise real authenticated
Supabase/FastAPI sources.
In mock/demo mode, auth boot also skips remote profile reads/creation and guest
capture migration, then restores the locally applied Setup name and completion
state across reloads.

## Frontend Script

Default Flutter web-server mode:

```bash
scripts/start_frontend.sh
```

Static build mode:

```bash
MODE=static scripts/start_frontend.sh
```

Useful overrides:

```bash
HOST=0.0.0.0 PORT=8080 scripts/start_frontend.sh
```

```bash
USE_MOCK_DATA=false \
SUPABASE_URL=https://your-project.supabase.co \
SUPABASE_ANON_KEY=your-anon-key \
scripts/start_frontend.sh
```

Windows PowerShell:

```powershell
apps\mobile\start_server_7357.ps1
```

The PowerShell script reads `.env`, builds Flutter Web, and serves `build\web`
on `127.0.0.1:7357`.

## AI Service

The AI service is optional for the default mock frontend.

```bash
cd services/ai_service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Health check:

```bash
curl http://localhost:8000/v1/health
```

Recommendation contract endpoints require an authenticated bearer token. PR1
defined the contract; backend Supabase settings are now required for real
token verification and recommendation persistence. In real backend mode,
successful Intake V1 completion or edit also triggers a best-effort deterministic
recommendation refresh from the constant onboarding snapshot. Read the newest
Setup row with:

```bash
curl http://localhost:8000/v1/intake/setup \
  -H 'Authorization: Bearer <supabase_access_token>'
```

The normal result is the latest applied revision. If the newest row is pending,
the response includes that exact payload and request id so the client can retry
the same save; it must not be edited into a different request.

For a first save, use `base_revision=0` and keep the same `request_id` when
retrying after a timeout:

```bash
curl -X POST http://localhost:8000/v1/intake/complete \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"version":"intake-v1","request_id":"11111111-1111-4111-8111-111111111111","base_revision":0,"responses":{"primary_focus_areas":["focus"],"goals":[{"key":"22222222-2222-4222-8222-222222222222","title":"Protect focus time","status":"active"}],"friction_points":[],"weekday_shape":"school_or_work","best_energy_window":"morning","coaching_style":"direct","reminder_preference":{"enabled":true,"quiet_hours":{"starts_at":"21:00","ends_at":"07:00"}},"routines":[{"key":"33333333-3333-4333-8333-333333333333","title":"Walk after lunch","status":"candidate","cadence_confirmed":false,"frequency":null,"target":null}],"fixed_commitments":[],"calendar_connection_intent":"not_now"},"metadata":{"client":"curl"}}'
```

For an edit, load Setup first, send its `revision` as the next request's
`base_revision`, and use a new request id. Candidate routines must not include
frequency/target values until cadence is explicitly confirmed.

The Flutter save state distinguishes known rejection from an unknown result.
Client validation and HTTP 4xx responses leave the draft editable; 409 also
offers `Reload saved setup`. A timeout, transport failure, 5xx, or invalid
success envelope locks the exact submitted draft and request id for unchanged
retry or explicit reload.

```bash
curl http://localhost:8000/v1/recommendations \
  -H 'Authorization: Bearer <supabase_access_token>'
```

```bash
curl -X POST http://localhost:8000/v1/recommendations/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":28,"force":false,"allow_llm_wording":false}'
```

```bash
curl -X POST http://localhost:8000/v1/snapshots/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"scope":"daily","window_days":7}'
```

The snapshot endpoint also accepts `"scope":"weekly"` and an optional
`"target_date":"YYYY-MM-DD"`. It derives the user from the bearer token and
uses the backend service-role key only inside FastAPI.

Daily and weekly responses add `summary.daily_state` and
`signals.daily_state` under `explainable-daily-state-v1`. `window_days` remains
the statistics window; the Daily State parser always loads a separate fixed
seven-day lookback. Evening is current on the target date or previous date,
while Morning is current only on the target date. The resulting quality is
`missing`, `partial`, `current`, or `stale`, and recovery safeguards precede
`plan`, `push`, and the conservative `steady` fallback.

V2 capture metadata is trusted only after strict identity, enum, numeric,
timestamp, and projection checks. A malformed V2 row never falls back to its
projected numeric columns. Numeric legacy fallback is available only when the
row has no V2 marker. The source remains `snapshot-aggregator-v1`; metadata
records `daily_state_contract_version=explainable-daily-state-v1` and
`state_lookback_days=7`. Top-level `summary.risk_flags` aliases the current
Daily State codes, while the older statistics-window flags remain separately in
`summary.window_risk_flags`. `recommended_next_focus` is derived recovery-first
from the mode.

Phase 3 adds neutral execution facts to snapshot responses. Explicit
completed/skipped habit outcomes appear under
`summary.habits.outcome_counts` and `signals.habit_outcome_counts`; focus status
counts and planned/actual minutes appear under `summary.focus_sessions`, with
signal status counts under `signals.focus_session_status_counts`. Input counts
and bounded evidence references include both tables. Those additions do not
alter `summary.daily_state` or `signals.daily_state`. FastAPI paginates both
action-fact tables in stably ordered 1,000-row pages until the window is
complete.
Every successful or exactly reconciled real task, habit, or focus write requests
a daily snapshot refresh best-effort. Habit outcome/undo captures one target
date before awaiting persistence, uses that date for exact reconciliation, and
refreshes the same date. New focus rows persist the local start
`metadata.entry_date`; legacy/invalid metadata uses the UTC calendar date of
persisted `started_at` in both Flutter and FastAPI. Finish/abandon does not
retarget a new session to its terminal day. Refresh failure does not roll back
the durable write, and ordinary action writes do not generate recommendations.

Authenticated real-data mode exposes owner-scoped task
create/edit/complete/postpone/cancel/restore/undo, Habit V1 daily execution at
`/habit-completion`, manual habit lifecycle at `/habits`, and the real
one-active-session focus flow at `/deep-work`. Focus may link one owned task or
active habit and never completes that target implicitly. Guest/mock users do
not receive these synced commands. Every task update including undo and every
manual habit definition/lifecycle update reconciles committed response loss
only by exact owner-scoped requested-field/timestamp readback. Habit
outcome/undo proves the exact row or its absence; focus finish/abandon proves
the exact terminal result. Habit reads paginate history beginning 370 calendar
days before today and use `started_on` with DST-safe calendar arithmetic. The
ranking-independent action envelope has strict Flutter/FastAPI parser parity,
including explicit-null metadata-field rejection, and is documented in
`docs/phase-3-executable-actions-contract.md`. Phase 4 wraps only these strict
targets in persisted deterministic briefings. Read without side effects using:

```bash
curl http://localhost:8000/v1/briefings/today \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Deliberately generate or refresh today's profile-local briefing using:

```bash
curl -X POST http://localhost:8000/v1/briefings/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"force":false}'
```

`force=false` returns an already-current persisted briefing unchanged. Missing
or stale output refreshes the daily snapshot and upserts the same
`(user_id, briefing_date)` identity. `force=true` deliberately recomputes it.

When FastAPI is running and Flutter is in real backend mode, a successful daily
capture calls the daily snapshot endpoint best-effort with the capture's
explicit local `target_date`. `/daily-check-in` redirects to the canonical
Evening Shutdown at `/quick-mood-check-in`; the separate short
`/morning-calibration` route captures sleep, current energy, and day shape. If
FastAPI is down, the durable Supabase capture still succeeds and the snapshot
refresh is skipped by the client. Normal capture does not generate
recommendations or create or change a plan. Guest/mock capture remains local.

Evening and Morning writes merge into one `(user_id, entry_date)` `daily_logs`
row. Phase 1 stores its bounded structured state under
`metadata.capture_version=daily-capture-v2` and
`metadata.captures.evening|morning`. Direct numeric columns remain compatible:
Morning energy takes precedence when present, while mood and stress come from
Evening and sleep comes from Morning. The writer reconciles the linked current
mood, energy, stress, and sleep events without duplicates and mirrors relevant
capture metadata onto those events. Blank Evening reflection, blocker, and
gentle-tomorrow answers stay absent and do not create other product records.

Backend-only Supabase configuration for the AI service:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=<local service-role key from supabase status>
SUPABASE_TIMEOUT_SECONDS=10
SCHEDULED_REFRESH_TOKEN=<local scheduler token>
```

Keep `SUPABASE_SERVICE_ROLE_KEY` only in the FastAPI service environment. Do
not add it to Flutter `.env`, docs examples with real values, browser runtime
configuration, or committed files. Keep `SCHEDULED_REFRESH_TOKEN` backend-only
for local cron/scheduler tests.

The scheduler-triggered daily refresh endpoint is intentionally not a Flutter
client endpoint:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <local scheduler token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":7,"limit":100,"include_recommendations":false}'
```

It refreshes deterministic daily snapshots for onboarded non-guest profiles.
When `include_recommendations=true`, it also runs the deterministic
recommendation generator with LLM wording disabled.

## Supabase

Supabase is optional for mock mode. To work on local Supabase you need the real
Supabase CLI and Docker available in the Ubuntu shell.

Start or reuse the local stack, then apply pending migrations without deleting
local data:

```bash
supabase start
HOME=.tools/supabase-home \
SUPABASE_TELEMETRY_DISABLED=1 \
supabase migration up --local
```

Read `docs/supabase-current-state.md` first. The Phase 3 runtime requires the
local schema to include:

```text
20260711120000_phase_3_executable_action_schema.sql
```

That migration adds bounded task fields, explicit habit outcomes, and the real
focus lifecycle. Its checks/triggers enforce exact task/focus shapes, lock and
revalidate active selected-weekday habit eligibility and selected focus targets,
reject every update to a terminal focus row, restrict linked-target deletion,
and permit one active focus session. It backfills a missing legacy focus
`metadata.entry_date` from the UTC date of `started_at`, normalizes positive
legacy habit values to completion, and rejects ambiguous legacy rows with
missing status and `value <= 0`; inspect and resolve those rows rather than
fabricating an intentional skip. Existing table RLS/grants remain.

The earlier `20260710180000_atomic_intake_v1_setup_apply.sql` migration installs
the service-role-only
`apply_intake_v1_setup_revision` RPC. It serializes apply per user with a
transaction advisory lock and atomically commits preferences, Setup-owned
goals/habits/schedule/memory reconciliation, the canonical onboarding snapshot,
applied intake state, and profile projection. During schedule reconciliation it
removes only the exact unmarked legacy onboarding placeholder `Math`,
`Room 204`, Monday `08:15`-`09:45`; other manual or unmarked onboarding rows are
preserved.

The canonical app schema is snake_case. Legacy CamelCase tables are only used as
optional migration sources when they already exist. A fresh reset is required
when verifying the complete migration chain and its backfills/constraints from
an empty local database; use the guarded repository script:

```bash
RESET_DB=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

For local Supabase-backed app testing:

1. Run `supabase start`.
2. Apply pending migrations with the non-reset command above, or use the
   `RESET_DB=true` verification flow when a fresh local database is intended.
3. Run `supabase status` and copy the local anon key into `.env`.
4. Set `USE_MOCK_DATA=false`, `SUPABASE_URL=http://127.0.0.1:54321`, and
   `SUPABASE_ANON_KEY=<local anon key>`.
5. Start the frontend with `scripts/start_frontend.sh`.
6. Smoke test registration or sign-in, required-only Setup, Setup re-entry/edit/
   review, required-only Evening Shutdown, Morning Calibration on the same local
   date, Evening re-entry/edit without losing Morning state, task
   create/edit/postpone/undo/complete/restore/cancel/restore, manual and
   Setup-owned habit complete/skip/undo, focus start/finish/abandon with an owned
   target, the source-aware Dashboard, Notifications, real Deep Work, and the
   gated Coach compatibility redirect.

Do not infer remote Supabase state from local migrations. Verify the remote
project through the Supabase dashboard, CLI, or connector before using it for
real data.

## Demo Data

For local Supabase-backed product exploration, seed repeatable demo accounts:

```bash
npm run seed:demo
```

Equivalent direct command:

```bash
bash scripts/seed_demo_data.sh
```

The script:

- starts the local Supabase stack if needed;
- reads the local service-role key from `supabase status -o env` without
  printing it;
- refuses to run unless the API URL is `http://127.0.0.1:54321` or
  `http://localhost:54321`;
- creates or updates three confirmed local Auth users;
- writes one typed applied Setup revision per user with a stable request UUID
  and intentionally empty optional Setup-owned collections, while leaving
  separately seeded `demo_seed` objects non-Setup-owned;
- replaces their demo app rows in `daily_logs`, `behavioral_events`, `tasks`,
  `schedule_items`, `habits`, `habit_logs`, `notifications`, `ai_insights`,
  `memory_entries`, `recommendations`, `coach_messages`,
  `intake_responses`, and `user_state_snapshots`.

Demo logins:

| Scenario | Email | Password |
| --- | --- | --- |
| Student focus | `student@example.test` | `DemoPass123!` |
| Busy worker | `worker@example.test` | `DemoPass123!` |
| Recovery builder | `recovery@example.test` | `DemoPass123!` |

Override the local demo password for a fresh seed run with:

```bash
DEMO_PASSWORD='AnotherLocalPassword123!' npm run seed:demo
```

After seeding, start Flutter in real local mode:

```bash
USE_MOCK_DATA=false \
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_ANON_KEY=<local anon key from supabase status> \
FLUTTER_BIN=/path/to/flutter \
scripts/start_frontend.sh
```

Open `http://127.0.0.1:7357`, sign in with one of the demo accounts, and compare
Dashboard, Notifications, Insights, and Habits across scenarios. Coach and Deep
Work no longer share the same status: Coach remains gated, while authenticated
real-data mode exposes the Phase 3 Deep Work lifecycle.
Seeded recommendations are visible through the FastAPI recommendation endpoint
when the AI service is running with the same local Supabase project settings;
without FastAPI, an authenticated account shows a recoverable recommendation
error and never substitutes local mock recommendations.

Automated local preflight without resetting the database:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

Automated local reset and test run:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The script runs Supabase with telemetry disabled, redacts keys from output,
reads the local anon key from `supabase status -o env`, and runs Flutter tests
with `USE_MOCK_DATA=false`.

## Verification

Flutter:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter build web --debug --no-wasm-dry-run
```

AI service:

```bash
cd services/ai_service
python -m compileall app
./.venv/bin/python -m pytest
```

All standard non-destructive checks from the repository root:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

Non-destructive local Supabase preflight:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The command starts or reuses the repository's local Supabase stack, reads the
local anon key without printing it, and does not reset the database.

Local Supabase reset workflow, only when a fresh local database is explicitly
intended:

```bash
RESET_DB=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

`RESET_DB=true` destroys and recreates the local database. The script requires
the Supabase CLI and Docker to be available to the same shell that runs it. It
reads the local anon key from `supabase status` without printing the key.

For details on what each script verifies and what is still not automated, read
`docs/verification.md`.

Browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

This is the normal non-reset path. It writes only its uniquely named test data
to the local stack and skips `supabase db reset` unless `RESET_DB=true` is
explicitly supplied.

Browser E2E with a fresh local database:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

The E2E script starts local Supabase, starts the FastAPI AI service with the
local Supabase backend settings, starts Flutter Web on `http://127.0.0.1:7357`,
creates a confirmed local test user through the local Supabase admin API, signs
in through the app, completes required-only Setup, exercises retry/edit/review
and ownership-safe reconciliation, then walks Phase 1 Evening Shutdown and
Morning Calibration. Its implemented assertions cover a committed
`daily_logs` response loss followed by exact retry, same-day Evening/Morning
merge, Evening re-entry/edit, one `daily_logs` row, nested
`daily-capture-v2` metadata, absent blank optionals, four deduplicated linked
current events, Morning-over-Evening numeric energy precedence, capture-scoped
snapshot refresh with `target_date`, and no recommendation-generate request
during normal capture. The same responses and persisted row are checked for
Phase 2 partial/current quality, recovery-first classification, exact stress/
sleep/energy/day-shape context, source-risk replacement after an Evening edit,
stable same-period snapshot identity, field-level evidence, deterministic
provenance, and capture free-text exclusion. It then continues through habit
execution, deliberate dashboard recommendation refresh, Notifications, and
implemented compatibility routes.

The Phase 3 portion contains exact assertions for a typed task's create/edit,
postpone/undo, complete/restore, cancel/restore, stable identity, terminal
timestamps, and estimate; manual and Setup-owned habit completion/skip/undo
without duplicate outcomes or definition mutation; and linked plus independent
focus start/finish/abandon with no implicit task completion. Committed responses
are deliberately lost for task/habit create, habit outcome/undo, task
completion/undo, and focus start/finish. Negative writes check task lifecycle,
duplicate active focus, terminal focus immutability including `updated_at` and
snapshot-date metadata, focus duration, inactive habit, and unscheduled weekday
rejection. It also checks that the refreshed snapshot contains neutral action
facts and that ordinary action writes did not call recommendation generation.

The Phase 0C portion remains part of the same smoke: it verifies revisioned
Setup ownership and retry/edit behavior, the service-role-only atomic apply RPC,
manual-row preservation, profile projection, and concurrent same-request
convergence before and after the capture journey. This describes the coverage
implemented by `e2e/web/smoke.mjs`; use the command above to establish the
result for the current checkout and local environment. Its presence is not a
claim that the current checkout has completed a full Phase 3 E2E run.

By default the script starts FastAPI on `http://127.0.0.1:8000`. Useful AI
service overrides:

```bash
AI_SERVICE_PORT=8001
AI_SERVICE_BASE_URL=http://127.0.0.1:8001
AI_SERVICE_PYTHON=/path/to/python
AI_SERVICE_START=false
```

By default the script always starts FastAPI from the current checkout. It does
not reuse an already-running service on the same port; stop that service or set
`AI_SERVICE_PORT` to a free port. Use `AI_SERVICE_START=false` only when you
intentionally want to reuse a compatible FastAPI process that is already running
with local `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` settings.

The local service-role key is used only inside FastAPI and the Node E2E process
for local test setup and assertions. It is not passed to Flutter.
This automated browser smoke covers the manual Supabase-backed smoke path for
the listed screens. Keep manual testing for flows not listed in
`docs/verification.md`.

## Troubleshooting

- If `flutter` is not found, install Flutter or set `FLUTTER_BIN`.
- If port `7357` is already in use, open `http://127.0.0.1:7357` first to see
  whether the app is already running.
- A `HEAD /` request may not prove the Flutter web-server is broken. Test with
  a normal browser request or `curl http://127.0.0.1:7357/`.
- If Supabase auth buttons fail, confirm `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  and provider redirect URLs.
- If real Supabase reads return empty data, confirm the authenticated user and
  expected tables exist.
- If `scripts/verify_supabase_local.sh` cannot connect to Docker, rerun it in an
  environment with Docker socket access.
- If `scripts/verify_supabase_local.sh` says Supabase CLI is missing, install
  the real Supabase CLI in Ubuntu so `supabase --version` works.
- If `scripts/e2e_web.sh` says Node.js is missing, install real Node.js in
  Ubuntu so `node --version` works.
- If `scripts/e2e_web.sh` says Playwright is missing, run `npm install`.
- If Playwright cannot find a browser, run `npx playwright install chromium` or
  set `CHROME_BIN=/path/to/chrome`.
- If E2E database assertions say `intake_responses`, `user_state_snapshots`,
  `habit_logs.status`, `focus_sessions.status`, or the Phase 3 task fields are
  missing, apply pending local migrations with
  `HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local`
  or run the fresh local DB flow with `RESET_DB=true`.
- If the Phase 3 migration refuses a legacy habit log with missing status and
  `value <= 0`, inspect that local row and decide its real outcome before
  retrying. The migration deliberately will not reinterpret it as a skip;
  positive legacy values are safely normalized to completion.
- If the AI service exits early during E2E, inspect
  `.tools/e2e/ai-service.log` and confirm `services/ai_service` dependencies are
  installed. If the log says the address is already in use, stop the stale
  service or set `AI_SERVICE_PORT` to a free port.
- If Flutter Web exits early during E2E, inspect `.tools/e2e/flutter-web.log`.
- Chromium WebGL performance warnings during E2E are expected in headless/local
  runs.
