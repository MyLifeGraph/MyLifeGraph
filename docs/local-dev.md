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
- Optional Phase 10 real-model local path only: a real Codex CLI installed in
  the same Linux/WSL user account that runs FastAPI. Standard development and
  tests use the fake provider and do not require Codex or a ChatGPT login.

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

## Complete Local Stack

For the real-data WSL workflow, one supervisor starts or reuses local Supabase,
verifies that its migration history matches the repository, starts FastAPI,
runs the protected daily preparation loop, and starts Flutter Web:

```bash
FLUTTER_BIN=/path/to/flutter scripts/start_local_stack.sh
```

The default is migration inspection-only. If repository files and local
database history differ, the supervisor exits before reading keys or starting
app processes. Review the pending SQL and local data first, then opt in only
when those changes are intended:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/start_local_stack.sh
```

Pending migrations may change or delete local rows even though they do not
reset the whole database.

The safe default leaves the Coach provider disabled. Standard deterministic
development may use the fake provider:

```bash
LOCAL_STACK_COACH_PROVIDER=fake \
FLUTTER_BIN=/path/to/flutter scripts/start_local_stack.sh
```

The explicitly opt-in real local Coach uses only the current Linux user's
existing Codex login:

```bash
LOCAL_STACK_COACH_PROVIDER=local_codex_oauth \
FLUTTER_BIN=/path/to/flutter scripts/start_local_stack.sh
```

The supervisor binds only to loopback, keeps the service-role key and scheduler
token out of Flutter and command arguments, writes private logs under
`.tools/local-stack/`, and leaves Supabase running after Ctrl+C. It never runs a
database reset. It refuses occupied app ports instead of attaching to unknown
processes. Run `bash scripts/test_start_local_stack.sh` for the hermetic
credential-separation and cleanup check.

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
Calibration, Dashboard, Recommendations, Insights, and the Inbox stay
local; synced task, habit, and focus commands are unavailable; and snapshot
refresh is skipped. Set it to `false` to exercise real authenticated
Supabase/FastAPI sources.
In mock/demo mode, auth boot also skips remote profile reads/creation and guest
capture migration, then restores the locally applied Setup name and completion
state across reloads.

For web auth, allow both local origins in Supabase Auth redirect URLs. An
installed Android build additionally requires the exact callback
`com.mylifegraph.app://login-callback/` in the Supabase redirect allowlist;
signup confirmation, password recovery, and Google OAuth all use that callback
on Android. The manifest already declares the matching VIEW/BROWSABLE intent
filter. This repository has no iOS runner and therefore does not claim native
iOS callback handling.

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

`COACH_SURFACE_ENABLED` is ignored in every release build and whenever
`APP_ENV=production`; those modes always hide the Coach route. In a
non-production debug/profile build, exact `true` enables and exact `false`
disables the surface, with development defaulting to enabled. Exposing the
Flutter route does not make a provider ready; FastAPI capability remains the
independent send gate.

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

Phase 6 feedback is authenticated, tied to an exact action in an owned briefing,
and retry-safe through `request_id`:

```bash
curl -X POST http://localhost:8000/v1/feedback \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"11111111-1111-4111-8111-111111111111","briefing_id":"22222222-2222-4222-8222-222222222222","action_id":"open_task:33333333-3333-4333-8333-333333333333","feedback_type":"too_much"}'
```

`GET /v1/feedback` lists the recent 28-day history and
`DELETE /v1/feedback/{feedback_id}` corrects an entry. Feedback never executes
the action. A deliberate later briefing generation applies only bounded,
decayed context matches and reports the result under `feedback-ranking-v1`.

Phase 8 weekly review reads the latest completed profile-local ISO week without
generation:

```bash
curl http://localhost:8000/v1/weekly-reviews/latest \
  -H 'Authorization: Bearer <supabase_access_token>'
```

An explicit period read is also side-effect free:

```bash
curl http://localhost:8000/v1/weekly-reviews/2026-W28 \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Replace `2026-W28` with the `period_key` returned by `latest`; V1 accepts only
the latest completed profile-local ISO week.

Deliberately generate or refresh that completed week with:

```bash
curl -X POST http://localhost:8000/v1/weekly-reviews/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"period_key":"2026-W28","force":false}'
```

The generate request uses that same latest completed `period_key`.

The response preserves `not_ready`, missing, current, or stale truth. Generation
persists one backend-owned derived review and never applies its proposals. In
Flutter, only an eligible manual Habit V1 shrink/pause/archive proposal can be
confirmed through the existing exact timestamp/readback command. Setup-owned
changes return to Setup; replace/defer and goal/task/schedule proposals remain
staged. Guest/mock does not call this API or fabricate a local review.

Phase 9 calendar import is also authenticated and optional. Read the current
connection state without importing:

```bash
curl http://localhost:8000/v1/calendar-integrations \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Create consent separately from import:

```bash
curl -X POST http://localhost:8000/v1/calendar-integrations/connections \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"11111111-1111-4111-8111-111111111111","source_kind":"ical_file","source_label":"Work calendar","consent":{"consent_version":"calendar-import-consent-v1","read_calendar_events":true,"store_event_basics":true,"provider_writes":false,"llm_processing":false}}'
```

Connection alone reads no file and creates no event. Deliberate import sends a
new stable request id plus bounded UTF-8 iCalendar text to
`POST /v1/calendar-integrations/connections/{connection_id}/imports`. Keep the
same request id and exact bytes for an ambiguous retry. Prefer the Flutter file
picker for manual testing instead of putting a large `.ics` body on a command
line.

`GET /v1/calendar-integrations/connections/{connection_id}/events` is paginated
and side-effect free.
Disconnect and imported-data deletion require separate confirmations:

```text
POST   /v1/calendar-integrations/connections/{connection_id}/disconnect
DELETE /v1/calendar-integrations/connections/{connection_id}/imported-data?request_id=<uuid>
```

Disconnect retains the local read-only event copy and rejects future imports.
Delete is permitted only after disconnect and removes integration event/import
rows without touching `schedule_items` or any source calendar. Setup's calendar
interest answer never creates consent. The slice has no OAuth token, provider
URL, provider write, background sync, LLM processing, or automatic
snapshot/briefing input. See `docs/phase-9-calendar-import-contract.md`.

Deadline Planner V1 is a separate authenticated, explicit workflow. Read the
collection without generation:

```bash
curl http://localhost:8000/v1/deadline-plans \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Create a manual staged proposal with one stable client plan id and request id:

```bash
curl -X POST http://localhost:8000/v1/deadline-plans/proposals \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"11111111-1111-4111-8111-111111111111","plan_id":"22222222-2222-4222-8222-222222222222","base_revision":0,"kind":"exam","title":"Statistics exam","deadline_at":"2026-08-20T09:00:00+02:00","estimated_total_minutes":480,"credited_prior_minutes":60,"preferred_session_minutes":50,"max_daily_minutes":100,"planning_start_on":"2026-07-20","buffer_days":2,"source_kind":"manual","use_calendar_availability":false}'
```

The proposal persists immutable staged blocks and leaves the active revision
unchanged. Inspect it with
`GET /v1/deadline-plans/{plan_id}`. Confirm only after review:

```bash
curl -X POST \
  http://localhost:8000/v1/deadline-plans/22222222-2222-4222-8222-222222222222/confirm \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"33333333-3333-4333-8333-333333333333","expected_revision":1}'
```

First confirmation creates the stable managed task; later confirmed revisions
retain it and may change only its title/deadline/update projection while open.
Generic Task edit/lifecycle/editor paths must reject that managed source and
redirect to `/preparation-plans`; focus may still target the open task. Complete
or cancel a plan through the corresponding
`/{plan_id}/complete|cancel` POST with a new request id. Completion requires an
active plan and its expected `current_revision`. Cancellation accepts either an
active plan's `current_revision` or a still-draft plan's `latest_revision`; a
draft discard creates or changes no managed task. Replanning instead sends the
returned `latest_revision` as `base_revision`. Keep the exact body for an
ambiguous retry. The same id with another operation, revision, or payload is a
conflict. Active-plan complete/cancel and the matching task
`done`/`cancelled` timestamp projection commit atomically. The local deadline
day may be no more than 366 days after `planning_start_on`.

An event-derived proposal uses `source_kind=calendar_event` and must include the
explicitly selected current `source_calendar_event_id` and lowercase source
fingerprint. `use_calendar_availability` independently controls whether current
imported busy intervals constrain that proposal. Enabling it requires a
connected source, no imported-data deletion, and a non-null current import;
otherwise the proposal conflicts instead of assuming an empty calendar.
Neither choice writes to the source calendar. Flutter exposes this at
`/preparation-plans`; guest/mock is zero-call. See
`docs/deadline-planner-v1-contract.md`.

For the daily briefing endpoint, `force=false` returns an already-current
persisted briefing unchanged. Missing
or stale output refreshes the daily snapshot and upserts the same
`(user_id, briefing_date)` identity. `force=true` deliberately recomputes it.

In authenticated real mode, Dashboard consumes this contract above metrics.
Normal page load calls GET only. Missing state offers explicit generation;
`Adjust today` sends `{"force":true}`; stale actions remain visible but disabled
until that succeeds. Guest/mock shows an explicit local-demo boundary and never
calls either privileged briefing endpoint or fabricates a personalized plan.

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
for local scheduler invocations and tests.

The scheduler-triggered daily preparation endpoint is intentionally not a
Flutter client endpoint:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <local scheduler token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":7,"limit":100,"include_recommendations":false}'
```

The backend captures one UTC `run_at`, resolves one local `briefing_date` from
each eligible profile's IANA timezone, and prepares the exact-date daily snapshot
and persisted briefing. Missing snapshots are generated; existing snapshots are
reused when only the briefing is missing; stale briefings are refreshed against
the matching snapshot; and current snapshot/briefing pairs are skipped without
changing ids or timestamps. `target_date` is optional and should be used only as
an explicit backfill override; it cannot be combined with
`include_notifications=true`.

For a bounded operational retry, a token holder can restrict the request to at
most 20 UUIDs:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <local scheduler token>' \
  -H 'Content-Type: application/json' \
  -d '{"profile_ids":["11111111-1111-4111-8111-111111111111"],"window_days":7,"limit":1,"include_recommendations":false}'
```

`profile_ids` narrows selection only; it does not bypass the onboarded non-guest
eligibility checks. The response carries the batch `run_at` plus per-user local
date, selection reason, snapshot and briefing ids/statuses, and a sanitized
failure stage. Snapshot, briefing, timezone, or optional recommendation failure
for one profile does not stop other selected profiles.

Recommendation refresh is off by default. Explicit
`include_recommendations=true` runs only the deterministic recommendation path
and keeps LLM wording disabled. The supported local stack runner sends
`include_notifications=true` every 15 minutes. Only separately consented real
accounts can receive fixed current-day deterministic rows; the database
revalidates timezone, quiet hours, category flags, daily cap, and dedupe. An
open Flutter app acknowledges a row before showing a foreground banner.
Missing/stale Phase 7 preparation remains independent of consent, while a fully
current profile is selected for a notification-only runner pass only with active
in-app consent so consent-off current rows do not exhaust the bounded batch.
Dashboard loads remain GET-only, and this repository still contains no deployed
cron, push, browser, Android, email, or background-mobile delivery wiring.

Manage the separate foreground permission at Settings -> In-app reminders.
The old Setup reminder preference is not permission. A manual local one-shot
uses the same safe runner payload:

```bash
cd services/ai_service
python -m app.ops.local_daily_refresh --once
```

## Phase 10 Controlled Coach

The exact implemented boundary is
`docs/phase-10-controlled-coach-plan.md`. Coach is disabled by default. Standard
tests use the deterministic fake provider; the real local adapter uses the
developer's existing Codex CLI OAuth login rather than an OpenAI API key. No
Hermes process is involved. Each developer or project partner performs these
steps inside the Linux/WSL account that will run FastAPI:

```bash
codex --version
codex login
codex login status
```

Do not copy `~/.codex`, `auth.json`, browser tokens, or another developer's
`.env`. A Pro user and a Plus user use separate local login state; the repo
cannot guarantee that both accounts expose the same model. FastAPI does
surface `unavailable_model` honestly when an explicitly requested model is not
available. The preferred Phase 10 Coach model is `gpt-5.5`: the workflow needs
general conversational reasoning and structured output rather than a coding-
focused Spark model. A partner may explicitly choose another model their own
account exposes, but the provider must never change it silently.

The active backend-only settings are:

```env
APP_ENV=development
USE_MOCK_DATA=false
COACH_PROVIDER=local_codex_oauth
LOCAL_CODEX_ENABLED=true
LOCAL_CODEX_BIN=codex
LOCAL_CODEX_MODEL=gpt-5.5
LOCAL_CODEX_TIMEOUT_SECONDS=45
LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20
LOCAL_CODEX_GLOBAL_CONCURRENCY=2
```

Safe defaults remain `COACH_PROVIDER=disabled` and
`LOCAL_CODEX_ENABLED=false`. These values are FastAPI settings, not Flutter Dart
defines. `LOCAL_CODEX_MODEL=gpt-5.5` is recommended for the Coach. If that exact
model is unavailable, select another exposed model deliberately or leave the
provider unavailable; do not fall back automatically. Empty means CLI default,
and the app must not invent the exact model name.

For deterministic local automation instead, configure FastAPI with:

```env
COACH_PROVIDER=fake
COACH_FAKE_PROVIDER_ENABLED=true
```

Never enable the fake provider in production or present its fixed response as a
real model answer.

The adapter runs FastAPI as the logged-in Linux user, invokes Codex
with a fixed non-shell argv, passes context through stdin, ignores user config,
uses an ephemeral read-only empty workspace, explicitly disables every available
model-controlled shell/tool feature, and passes an allowlisted environment that
excludes every Supabase key and application secret. If the installed CLI cannot
prove a tool-free invocation, the provider remains unavailable. It must never
inspect the OAuth file. Standard pytest/Flutter/browser verification uses a
fake provider. The committed live smoke is skipped by default, uses only
synthetic context, and is per-machine:

```bash
cd services/ai_service
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

Run it only after the local provider settings above are enabled and
`codex login status` succeeds for the same Linux user. It must print no prompt,
token, OAuth state, answer, or raw CLI event stream. On 2026-07-13 this
synthetic-context smoke completed with the explicitly requested `gpt-5.5`
model (`1 passed`) and no fallback. That result applies only to the tested
machine, CLI, login, and account; it does not prove another developer's model
access or a deployable provider. The focused Phase 10 and subsequent full
non-destructive local fake-provider browser journeys also passed in the current
checkout; they do not establish remote state or production readiness.

A separate full-product live acceptance also passed on this machine on
2026-07-13: an existing onboarded local user authenticated through Flutter Web,
FastAPI used `local_codex_oauth` with exact `gpt-5.5`, and the same Linux user's
Codex login returned one validated, UI-rendered, persisted response. The harness
logged no question, assembled prompt, answer, raw event stream, stderr, account
identity, path, token, `.env` value, or Supabase key. This verifies the first
local live-account product path only; another Linux user must still clone, log
in with their own eligible account, and repeat the documented setup without
copied credentials.

This local adapter is suitable for developer testing on the machine that owns
the login. It is not a production deployment mechanism, does not make a mobile
app independently capable of contacting Codex, and must not be enabled by
`APP_ENV=production`.

All Coach endpoints require the normal Supabase bearer token. Read capability,
history, and eligible memory without generating:

```bash
curl http://localhost:8000/v1/coach/capabilities \
  -H 'Authorization: Bearer <supabase_access_token>'
curl http://localhost:8000/v1/coach/history \
  -H 'Authorization: Bearer <supabase_access_token>'
curl http://localhost:8000/v1/coach/memories \
  -H 'Authorization: Bearer <supabase_access_token>'
```

One deliberate send accepts only the strict `today` scope and a stable UUID:

```bash
curl -X POST http://localhost:8000/v1/coach/respond \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"contract_version":"coach-request-v1","request_id":"11111111-1111-4111-8111-111111111111","message":"What should I protect today?","context_scope":"today"}'
```

Retry an ambiguous result with the exact message and request id. Editing the
message requires a new id. Completed replay returns the persisted response
without another provider call; failed and deleted ids remain terminal. Select a
memory with `POST /v1/coach/memories/{memory_id}/selection` and exact body
`{"selected":true}`; deselect with a body-free DELETE. `DELETE
/v1/coach/history` is also body-free. It deletes conversation content but
retains usage events and request tombstones, so it does not restore the daily
request budget.

## Stored Inbox Lifecycle

A real authenticated account reads its visible Inbox rows directly through
Supabase and sends lifecycle mutations through FastAPI:

```bash
curl -X POST \
  http://localhost:8000/v1/notifications/<notification_id>/actions \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"contract_version":"notification-lifecycle-v1","request_id":"11111111-1111-4111-8111-111111111111","command":"mark_read","expected_updated_at":"2026-07-14T08:30:00Z"}'
```

Use exactly `mark_read`, `mark_unread`, or `dismiss`. Retry an ambiguous result
with the unchanged request id, command, and expected timestamp. A definite
`409` requires reloading the Inbox state. Dismiss keeps a tombstone and hides it
from normal reads. This endpoint does not generate, schedule, or deliver a
notification; existing reminder settings are not delivery consent. See
`docs/notification-lifecycle-v1-contract.md`.

## V1 Account Controls

With FastAPI and the matching Supabase project configured, a real account can
update its IANA timezone, export bounded JSON, and permanently delete itself:

```bash
curl -X PATCH http://localhost:8000/v1/account/profile \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"timezone":"Europe/Berlin"}'

curl http://localhost:8000/v1/account/export \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Permanent deletion additionally requires
`20260713233000_v1_account_delete.sql` and exact `DELETE` confirmation. Exercise
it only with an intentionally disposable local account. The verified bearer
session must contain a recognized, non-refresh Supabase `amr` authentication
timestamp no more than 15 minutes old; otherwise FastAPI returns `403` before
the RPC. A successful call deletes the Auth user and every canonical owned
product row and cannot be undone. See `docs/v1-account-controls-contract.md`.
Do not run a live deletion merely to verify a non-destructive checkout.

Export first validates the complete bounded envelope. Web uses a browser
download, desktop opens a cancellable save-location dialog, and Android uses
the platform share sheet so the user chooses the destination. The app deletes
its dedicated Android source file best-effort after handoff and before the next
export, but the share plugin or operating system may retain a protected cache
copy until its own cleanup. The source contains an iOS share branch, but there
is no iOS runner or installed-iOS acceptance claim. An export is not a
transaction-wide point-in-time database snapshot or a restore format.

## Android Builds

Debug builds use the normal Android debug signing path. Distributable release
builds deliberately fail unless ignored `apps/mobile/android/key.properties`
contains all four values below and `storeFile` resolves to a private keystore:

```properties
storePassword=<secret>
keyPassword=<secret>
keyAlias=<alias>
storeFile=<path-to-keystore>
```

Neither file belongs in Git. The repository never falls back to the debug key
for a release. Installing a release also requires the remote Supabase redirect
allowlist entry described above.

## Supabase

Supabase is optional for mock mode. To work on local Supabase you need the real
Supabase CLI and Docker available in the Ubuntu shell.

Start or reuse the local stack, then inspect repository files against the local
database history:

```bash
supabase start
HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 \
supabase migration list --local
```

Repository scripts stop when either side differs and do not apply pending SQL
by default. After reviewing the migration and affected local rows, apply it and
verify the resulting history with:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

This explicit opt-in may change or delete local rows. It must not be described
as non-destructive merely because it avoids `db reset`.

Read `docs/supabase-current-state.md` first. The Phase 3 runtime requires the
local schema to include:

```text
20260711120000_phase_3_executable_action_schema.sql
```

Weekly Review additionally requires:

```text
20260712210000_phase_8_weekly_reviews.sql
20260712211500_phase_8_weekly_review_provenance_guard.sql
```

These migrations create forced-RLS backend-owned `weekly_reviews` persistence
and require its deterministic provenance keys to match the source fingerprint.
Authenticated users can read only their own review rows; only service role can
write them.

Calendar import additionally requires the Phase 9 migration listed in
`docs/supabase-current-state.md`. It creates dedicated backend-owned
`calendar_connections`, `calendar_imports`, and `calendar_events` plus four
service-role-only atomic lifecycle operations. Its follow-up guard adds the
minimal fingerprint-free `calendar_request_identities` registry and reliable
HTTP 409 conflict semantics. Apply both only after reviewing the SQL and local
rows, using the explicit `APPLY_MIGRATIONS=true` workflow above. Do not reset
the local database merely to install them.

Deadline Planner additionally requires the migration listed in
`docs/supabase-current-state.md`. It creates forced-RLS backend-owned plan,
revision, block, and request-identity tables plus service-role-only atomic
mutation RPCs. Review and apply it through the same explicit migration workflow;
do not encode dated blocks as recurring `schedule_items`.

Controlled Coach additionally requires:

```text
20260713200000_phase_10_controlled_coach.sql
20260713213000_phase_10_coach_lock_order_guard.sql
20260713220000_phase_10_coach_safety_provenance_guard.sql
20260713223000_phase_10_profile_privilege_guard.sql
20260713224500_phase_10_role_authority_guard.sql
20260713230000_phase_10_onboarding_eligibility_guard.sql
```

It creates backend-owned Coach request, usage, and memory-selection state;
hardens message/memory RLS and grants; and installs the service-role-only atomic
claim, complete, fail, select/deselect, and history-delete RPCs. Apply it with
the same reviewed, explicit `APPLY_MIGRATIONS=true` workflow. Migrations may
change or delete local rows. History deletion intentionally retains request
tombstones and usage rows.
The follow-up guard keeps the public RPC signatures but makes
claim/complete/fail acquire the same owner advisory lock before their existing
inner bodies, matching history deletion and avoiding inverse lock order.
The remaining guards persist exact provider-call truth for safety redirects;
block application-role profile insertion, role/provider changes, deletion, and
onboarding projection changes; and remove legacy `"User"` fallback from role
authority. Authenticated profile edits are limited to non-authority fields;
service role and the atomic Intake apply RPC retain the required backend
projection authority. A fresh migration-chain verification should end at
`20260714110000_account_export_lifestyle_entries_grant.sql`. The small final
grant gives only `service_role` the `lifestyle_entries` read authority required
by the existing Account Export V1 table set. The account-delete
migration installs the service-role-only full-account delete transaction; it
removes restrict-linked focus history before the Auth/profile/product cascade
without changing normal task or habit deletion. The later Notification
migration adds the service-role-only lifecycle RPC and retry ledger without
delivery behavior.
The final privilege guard covers every repo-owned product and ledger table:
`anon` receives no table authority, authenticated users lose `TRUNCATE`,
`REFERENCES`, and `TRIGGER` while intended table-specific DML remains, and the
four backend projections stay read-only. Optional legacy tables are frozen,
future public tables created by `postgres` inherit fail-closed application-role
defaults, and the installed Auth triggers continue firing even though their
security-definer functions are no longer reusable by application or service
roles. The migration also adds the Notification-ledger child index and six
`NOT VALID` timestamp-order checks; those checks protect new or updated rows
without claiming that pre-existing remote rows have been validated.
On 2026-07-13 real local PostgreSQL parallel claim/completion/deletion smokes
completed without deadlock or timeout and converged on the expected message,
usage, and deletion state. This is local concurrency evidence, not remote
project verification.

The earlier Phase 3 migration adds bounded task fields, explicit habit outcomes, and the real
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
2. Confirm that `migration list --local` matches. If it does not, review the
   SQL and local data before using `APPLY_MIGRATIONS=true`, or use the
   `RESET_DB=true` verification flow only when a fresh local database is
   deliberately intended.
3. Run `supabase status` and copy the local anon key into `.env`.
4. Set `USE_MOCK_DATA=false`, `SUPABASE_URL=http://127.0.0.1:54321`, and
   `SUPABASE_ANON_KEY=<local anon key>`.
5. Start the frontend with `scripts/start_frontend.sh`.
6. Smoke test registration or sign-in, required-only Setup, Setup re-entry/edit/
   review, required-only Evening Shutdown, Morning Calibration on the same local
   date, Evening re-entry/edit without losing Morning state, task
   create/edit/postpone/undo/complete/restore/cancel/restore, manual and
   Setup-owned habit complete/skip/undo, focus start/finish/abandon with an owned
   target, the decision-first Today briefing with deliberate adjustment,
   bounded Weekly Review with one cancelled and one confirmed manual Habit V1
   proposal, Inbox (`/alerts`), real Deep Work, and Controlled Coach capability,
   memory selection, deliberate response, history, and confirmed history
   deletion with a fake provider.

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
- deletes and recreates only the three confirmed local demo Auth users through
  the full-account cascade, so a rerun also resets immutable local retry and
  usage ledgers (and signs out an open demo session);
- writes one typed applied Setup revision per user with a stable request UUID
  and intentionally empty optional Setup-owned collections, while leaving
  separately seeded `demo_seed` objects non-Setup-owned;
- replaces their base demo app rows, then enriches `student@example.test`
  through the real FastAPI service classes with current snapshots/briefings,
  feedback, Weekly Review, Calendar Import, Preparation Plans, foreground
  notification consent/generation, and fake-provider Coach persistence;
- verifies the student coverage before reporting success. This enrichment
  requires `services/ai_service/.venv`, or an equivalent `PYTHON_BIN`.

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
Dashboard, Inbox, Insights, and Habits across scenarios. The student account is
the broad manual product fixture: Today, all three Habit cadences, resumable
Deep Work, Weekly Review proposals, Calendar Import, active and staged
Preparation Plans, capacity, notification consent, and Coach history are
pre-populated. Mutate these freely and rerun the seed to restore them. Coach
sending remains disabled unless FastAPI is deliberately started with a ready
provider; the stored demo turns use the deterministic fake provider and imply
no live model connection.
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

The command starts or reuses the repository's local Supabase stack, verifies
that repository and database migration history match, reads the local anon key
without printing it, and does not reset or apply migrations. A mismatch fails
with instructions before Flutter tests run.

After reviewing pending SQL and local data, the explicit application path is:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

That operation may change or delete local rows.

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

This is the normal non-reset path. It requires repository and local database
migration history to match and never applies pending SQL automatically. It
writes only its uniquely named test data to the local stack and skips
`supabase db reset` unless `RESET_DB=true` is explicitly supplied. After
reviewing pending SQL and local rows, `APPLY_MIGRATIONS=true` is the separate
opt-in; it may change or delete those rows.

For a narrow Phase 10 diagnosis against an already-created, onboarded E2E
principal, reuse that principal's exact run id:

```bash
E2E_PHASE10_ONLY=true \
E2E_RUN_ID=<existing-e2e-run-id> \
FLUTTER_BIN=/path/to/flutter \
bash scripts/e2e_web.sh
```

This mode signs in as the existing `e2e-<run-id>@example.test` account, clears
only its Coach E2E state, and reruns the bounded Coach browser/RLS assertions.
It does not create the prerequisite user or exercise Setup, capture, action,
briefing, review, and calendar journeys, so it is a diagnostic/repetition aid,
never a substitute for the full command above.

On 2026-07-13 the focused non-reset run with `E2E_RUN_ID=1783945829` passed,
then the full non-destructive current-checkout command passed against local
Supabase with the deterministic fake Coach provider and reported
`E2E browser smoke passed for e2e-1783947134@example.test`.

Browser E2E with a fresh local database:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

The E2E script starts local Supabase, starts the FastAPI AI service with the
local Supabase backend settings and deterministic fake Coach provider, starts Flutter Web on `http://127.0.0.1:7357`,
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
execution, deliberate dashboard recommendation refresh, Inbox (`/alerts`), and
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

The briefing portion first proves that authenticated GET is read-only while the
daily briefing is missing. It then invokes the protected Phase 7 scheduler with
`profile_ids` restricted to the smoke's unique test user. Database and response
assertions require the profile-local date, exact source snapshot and briefing
ids, deterministic no-LLM provenance, and one persisted daily identity. An
immediate identical retry must select no current work and preserve both rows and
their timestamps. Dashboard subsequently reads that prepared briefing with GET
only; it still does not generate during normal load. The E2E script supplies a
local scheduler token to FastAPI and the Node assertion process only, never to
Flutter.

The Phase 0C portion remains part of the same smoke: it verifies revisioned
Setup ownership and retry/edit behavior, the service-role-only atomic apply RPC,
manual-row preservation, profile projection, and concurrent same-request
convergence before and after the capture journey. This describes the coverage
implemented by `e2e/web/smoke.mjs`. The Phase 8 path adds read-only missing
truth, deliberate generation, exact persisted weekly facts/proposals, confirmed
manual Habit V1 adaptation, stale/refresh behavior, Setup non-mutation, and
review-table RLS.

The Phase 9 source journey additionally covers explicit consent, connection
without import, retry-safe `.ics` reconciliation, stable paginated event reads,
read-only provenance, all-day/timezone/recurrence/cancellation boundaries,
disconnect-retains versus delete-local-only behavior, schedule preservation,
and owner/cross-owner RLS. Phase 10 adds the deterministic fake-provider Coach
journey. The focused Phase 10 rerun and subsequent full Phase 3-through-10 path
passed non-destructively in the 2026-07-13 current checkout. Use the complete
command above to establish a new result after later changes; the focused mode
or source coverage alone is not a full-checkout pass.

Deadline Planner source coverage must additionally prove explicit estimate and
prior-credit input, deterministic bounded block totals, staged-versus-active
revision truth, first-confirm task creation, linked-focus progress without
implicit completion, calendar isolation/optional busy time, exact retry and
cross-owner RLS, Account Export inclusion, and guest zero-call. This paragraph
does not claim those assertions or a current browser pass; run the full command
after the implementation and migration are present.

By default the script starts FastAPI on `http://127.0.0.1:8000`. Useful AI
service overrides:

```bash
AI_SERVICE_PORT=8001
AI_SERVICE_BASE_URL=http://127.0.0.1:8001
AI_SERVICE_PYTHON=/path/to/python
AI_SERVICE_START=false
SCHEDULED_REFRESH_TOKEN=<token configured in the reused FastAPI process>
```

By default the script always starts FastAPI from the current checkout. It does
not reuse an already-running service on the same port; stop that service or set
`AI_SERVICE_PORT` to a free port. Use `AI_SERVICE_START=false` only when you
intentionally want to reuse a compatible FastAPI process that is already running
with local `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` settings. Because the
smoke exercises Phase 7, a reused process must also use the same
`SCHEDULED_REFRESH_TOKEN` supplied to the script. If a reused process is meant
to exercise Coach, it must also use the fake-provider settings above; standard
E2E must not contact a live Codex account.

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
- If E2E preflight or database assertions say migration history or required
  fields differ, inspect `supabase migration list --local`, the pending SQL,
  and affected local rows. Re-run with `APPLY_MIGRATIONS=true` only when those
  changes are intended, or use the fresh local DB flow with `RESET_DB=true`
  only when destroying the local database is intended.
- If the Phase 3 migration refuses a legacy habit log with missing status and
  `value <= 0`, inspect that local row and decide its real outcome before
  retrying. The migration deliberately will not reinterpret it as a skip;
  positive legacy values are safely normalized to completion.
- If the AI service exits early during E2E, inspect
  `.tools/e2e/ai-service.log` and confirm `services/ai_service` dependencies are
  installed. If the log says the address is already in use, stop the stale
  service or set `AI_SERVICE_PORT` to a free port.
- If the local Coach reports that its provider is
  unavailable, run `codex --version` and `codex login status` as the same Linux
  user that runs FastAPI. Do not troubleshoot by opening or copying the Codex
  auth file. An unavailable explicitly configured model is not permission to
  fall back silently.
- If Flutter Web exits early during E2E, inspect `.tools/e2e/flutter-web.log`.
- Chromium WebGL performance warnings during E2E are expected in headless/local
  runs.
