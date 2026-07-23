# MyLifeGraph

Mobile-first foundation for an AI-powered personal coach and life graph product.

The repository currently contains a Flutter web/mobile client, a small FastAPI
AI-service boundary, and Supabase migrations/configuration. The most reliable
way to explore the product today is the Flutter app in mock-data guest mode.

## Current Status

- The Flutter app is the primary user experience.
- Mock/guest mode is the default local path and does not require Supabase keys.
- Supabase Auth and persistence are wired in the app. The canonical snake_case
  migrations create the current app tables, including Intake V1 tables, for
  local Supabase-backed testing.
- The FastAPI service exposes authenticated typed Setup read/completion/edit,
  deterministic recommendation and briefing endpoints, and deterministic
  snapshot refresh.
  Applying Intake V1 triggers a controlled recommendation refresh from the
  constant onboarding snapshot. Daily and weekly user-state snapshots can be
  refreshed without an LLM provider and now include an explainable
  deterministic Daily State with freshness, quality, risks, reasons, and a
  recovery-first Daily Mode. Snapshots also include additive explicit habit
  outcomes and focus-session counts/minutes without changing the Phase 2
  classifier. The dashboard includes a deliberate deterministic recommendation
  refresh action. A protected backend-only scheduler captures one UTC run
  instant, resolves each onboarded non-guest profile's local date, and prepares
  missing daily snapshots plus missing or snapshot-stale persisted briefings
  without an LLM.
- Insights includes deterministic correlation exploration for available sleep,
  planned minutes, stress, energy, mood, screen time, activity, steps, habits,
  and completed focus minutes. Missing metrics are hidden, focus comes from real
  sessions, and the primary observation requires 14 shared days. It computes
  bounded 7/14/30/90-day relationships in Flutter from paginated Supabase rows
  or local mock time series, without LLM usage. Real accounts do not show the
  unproduced Skillset surface; local demo mode labels its Skill profile as
  example data only and never presents it as learned user evidence.
- Real authenticated accounts now have durable timezone editing, a strict
  bounded `account-export-v1` JSON portability export, password reset/confirmation-email
  recovery, and confirmed permanent account deletion. The deletion is one
  service-role-only database transaction and requires session-bound Supabase
  sign-in evidence no more than 15 minutes old; guest/mock exposes none of
  these as synced operations. Theme choice is persisted on the current device.
- A global offline banner distinguishes local guest/demo persistence from
  unavailable synced writes. It reports network transport only; it is not a
  Supabase/FastAPI health check and the app does not claim an offline sync queue.
- Phase 0A through Phase 10 are implemented at the repository boundary. Evening and Morning merge without
  erasing each other and feed a strict backend-only state parser; Setup remains
  progressive, revision-safe, reviewable, and atomically materialized. Phase 3
  adds durable task commands, cadence-aware Habit V1 outcomes, linked focus
  sessions, and parser-equivalent strict Flutter/FastAPI
  `executable-action-v1` models. Ambiguous committed task/focus transitions are
  reconciled by exact persisted state rather than repeated blindly. These remote
  actions remain unavailable to guest/demo sessions. Phase 4 adds persisted,
  deterministic `daily-briefing-v1` output behind read-only
  `GET /v1/briefings/today` and deliberate `POST /v1/briefings/generate`.
  Read-only `GET /v1/today/overview` remains available, while the app consumes
  additive `GET /v1/today/overview-v2`. Today now leads
  with a strict both-capture streak, transparent dynamic `x/y` progress, a
  vertical agenda that also includes Planner Task/Habit/commitment blocks,
  selected tasks, and selected habits. Multiple blocks never duplicate a
  target in progress. Counted-source failures make progress explicitly unavailable while
  independent sections remain usable; guest/demo computes only local facts and
  makes no authenticated call. Existing execution commands remain authoritative,
  while workload, Weekly review, saved
  signals, recommendations, feedback history, and the full week load lazily
  under `More`. Phase 6 adds retry-safe owner-scoped feedback, bounded 28-day
  context-matched ranking effects with explicit provenance, deletable history,
  and one cautious default Insight before advanced correlation exploration.
  Phase 7 adds bounded scheduled daily preparation: missing prerequisites are
  generated, stale briefings are refreshed against their exact source snapshot,
  and current snapshot/briefing pairs remain write-free. Each user failure is
  isolated and reports its stage. Phase 8 adds one backend-owned
  `weekly-review-v1` identity per completed profile-local ISO week. Read paths
  remain side-effect free, deliberate generation persists only derived facts
  and at most two proposals, and exact source fingerprints expose staleness.
  Confirmed manual Habit V1 shrink/pause/archive changes reuse Phase 3; Setup
  changes deep-link to Setup, while replacement and goal/task/schedule changes
  remain staged. Phase 9 adds one optional authenticated `ical_file` connection
  with explicit read/store consent, deliberate bounded `.ics` import, stable
  connection/import/event identities, and visibly read-only imported events.
  Connect never imports; repeated files reconcile instead of duplicating rows;
  disconnect retains the local copy, while a separate confirmed delete removes
  only imported local data. No provider credential, URL fetch, provider write,
  background sync, LLM processing, or `schedule_items` mutation is introduced.
  Deadline Planner V1 adds a separate explicit planning loop for exams and
  assignments: the user supplies total active preparation time and prior
  credit, reviews deterministic dated blocks, and confirms one immutable
  revision before it becomes active. First confirmation creates one stable
  managed task; completed post-activation focus linked to that task contributes
  measured progress without completing the task or plan. A manual deadline or
  one deliberately selected imported event may be used, and imported busy time
  is an optional per-plan input only from a connected, non-deleted current
  import. Planning is bounded to 366 days. There is no title inference,
  calendar write, notification, LLM call, background sync, or hidden proposal.
  The managed task accepts focus while open, but all edit/lifecycle authority
  remains in the preparation plan instead of generic Task controls. Settings
  may add an explicit account-wide daily preparation budget; new proposals
  deduct confirmed blocks from other plans, and confirmation rechecks the rule
  under the owner lock. Today and Preparation plans show a strict seven-day
  view of confirmed preparation plus separately labelled weekly Setup
  commitments. This remains a transparent deterministic rule, not an AI effort
  estimate or a complete calendar/free-time model. Replanning an active plan
  without a pending preview now starts with a compact saved-value review and one
  deliberate staged-preview action; changing values still uses the full editor,
  and current reservations remain active until confirmation.
  Planner V1 is the central authenticated planning surface for Task/Habit
  creation and timing, Deadline Planner entry, and one-off or weekly fixed
  commitments. Its shared deterministic availability engine stages five-minute
  Task blocks or stable Habit slots and reserves them only after explicit
  confirmation. Setup is the primary availability source: recurring classes,
  work, and other weekly blocks can have optional inclusive semester dates and
  can be duplicated across weekdays. Planner warns before automatic planning
  when no current availability source is visible, while still allowing an
  explicit continue. Calendar import is not part of onboarding; one optional
  explicit read-only busy-time preference is shared with Deadline Planner.
  Current conflicts create attention facts, never hidden or background
  replanning. Inbox moved from the app shell to Settings without changing
  notification persistence or delivery.
  The repository does not configure a deployed cron. Notification Delivery V1
  can create bounded local deterministic Inbox rows only after separate in-app
  consent; it still adds no provider/system delivery channel.
  Phase 10 adds a strict authenticated, deliberate-send Coach boundary with a
  32 KiB owner-scoped context cap, visible source/freshness/uncertainty
  provenance, explicit selection of up to eight eligible memories, bounded
  validated history, retained usage accounting, and at most one review-only
  suggestion. Capability/history/memory reads never call a model; guest/mock is
  zero-call; Coach cannot mutate tasks, habits, goals, schedules, briefings,
  reviews, memory content, or calendar data. Standard tests use the deterministic
  fake provider. The Coach UI is hard-hidden in release builds and whenever
  `APP_ENV=production`; a Flutter define cannot override that boundary. The
  real-model adapter is intentionally local-development-only:
  FastAPI invokes an explicitly enabled Codex CLI already authenticated by the
  current Linux/WSL user, so local subscription testing needs no application API
  key and shares no OAuth files. It prefers the explicitly configured `gpt-5.5`
  setting, reports unavailable login/model/tool-free capability honestly, and
  never silently falls back. Production deployment requires a separate
  provider/security contract. An opt-in synthetic-context smoke completed on
  2026-07-13 with the explicitly requested `gpt-5.5` model (`1 passed`), no
  fallback, and no answer/prompt/raw event stream logged. That result is
  machine- and account-specific. A separate authenticated Flutter -> FastAPI ->
  `local_codex_oauth` -> same-user Codex CLI live turn also passed and persisted
  a validated response on this machine with explicit `gpt-5.5`; no prompt or
  answer content was logged. The current checkout's focused Phase 10 rerun and
  subsequent full non-destructive local browser-E2E journey also passed with
  the deterministic fake provider. None of these results establishes a remote/
  production provider or another developer's account; the separate other-Linux-
  user acceptance remains open.
  Notification Lifecycle V1 adds strict stored-Inbox read/unread/dismiss
  tombstones for real authenticated accounts through FastAPI and one
  service-role-only retry ledger. Guest/demo stays local and zero-call, and
  direct authenticated Notification DML remains forbidden. Notification
  Delivery V1 keeps that lifecycle separate while adding fail-closed in-app
  consent, deterministic/no-LLM generation, timezone/quiet/category/cap/dedupe
  guards, the local runner, and an acknowledged foreground Flutter banner. It
  enables no push, browser, email, Android, background-mobile, or deployed
  scheduling channel; existing reminder settings remain configuration rather
  than delivery consent.
  See
  `docs/phase-3-executable-actions-contract.md` and
  `docs/phase-8-weekly-review-contract.md`, and
  `docs/phase-9-calendar-import-contract.md`. Deadline planning is specified in
  `docs/deadline-planner-v1-contract.md`; the controlled Coach boundary lives
  in `docs/phase-10-controlled-coach-plan.md`.
- Repository docs and scripts should be treated as the shared team source of
  truth. Do not depend on user-local Codex skills or machine-specific paths.

## Repository Structure

- `apps/mobile` - Flutter app with Riverpod state, GoRouter navigation,
  Supabase boundaries, mock data sources, and FastAPI client boundaries.
- `services/ai_service` - Python FastAPI service for recommendation and future
  ML workflows.
- `supabase` - Supabase config, PostgreSQL migrations, and RLS policies.
- `docs` - Architecture, local development, and Supabase status notes.
- `scripts` - Team-friendly helper scripts for local development.
- `AGENTS.md` - Repo-local instructions for coding agents.

## Quick Start

Prerequisites:

- Flutter SDK available on `PATH`, or set `FLUTTER_BIN=/path/to/flutter`.
- Python 3.11+ if you want to run the AI service or static web fallback.
- Node.js 20+ and npm for browser E2E.
- Supabase CLI and Docker for local Supabase-backed tests and browser E2E.
- Codex CLI plus a per-user `codex login` only for the opt-in Phase 10
  real-model local path; it is not needed for standard tests.

From a fresh clone:

```bash
cp .env.example .env
scripts/start_frontend.sh
```

Open:

```text
http://127.0.0.1:7357
```

Use **Continue as guest** in the app. This is the intended local path when no
Supabase credentials are configured.

For the complete local real-data stack (Supabase, FastAPI, daily preparation
runner, and Flutter Web), run:

```bash
FLUTTER_BIN=/path/to/flutter scripts/start_local_stack.sh
```

The default command verifies that local database migration history exactly
matches the repository and exits without applying SQL when it differs. After
reviewing pending SQL and local rows, opt in explicitly with
`APPLY_MIGRATIONS=true`; a migration may change or delete local rows. The Coach
is safely disabled by default. Use
`LOCAL_STACK_COACH_PROVIDER=fake` for deterministic development or explicitly
use `LOCAL_STACK_COACH_PROVIDER=local_codex_oauth` with the current WSL user's
existing `codex login`. The supervisor is loopback-only, never resets the
database, does not expose backend keys to Flutter, and stores private logs under
`.tools/local-stack/`. See `docs/local-dev.md` for the exact boundary.

If Flutter is not on `PATH`:

```bash
FLUTTER_BIN=/path/to/flutter scripts/start_frontend.sh
```

Static build fallback:

```bash
MODE=static scripts/start_frontend.sh
```

Windows PowerShell users can also run:

```powershell
apps\mobile\start_server_7357.ps1
```

## Runtime Configuration

The Flutter app reads runtime values from Dart defines. The repo script maps
matching environment variables into Dart defines:

```env
APP_ENV=development
USE_MOCK_DATA=true
SUPABASE_URL=
SUPABASE_ANON_KEY=
AI_SERVICE_BASE_URL=http://localhost:8000
```

Useful examples:

```bash
USE_MOCK_DATA=true scripts/start_frontend.sh
```

`USE_MOCK_DATA=true` is an explicit local-demo boundary for product data
surfaces, including when a Supabase authentication session happens to exist.
Mock/demo auth boot avoids remote profile/data reads and restores the locally
applied Setup across reloads. Use `USE_MOCK_DATA=false` for authenticated
Supabase/FastAPI data.

```bash
USE_MOCK_DATA=false \
SUPABASE_URL=https://your-project.supabase.co \
SUPABASE_ANON_KEY=your-anon-key \
scripts/start_frontend.sh
```

Never commit real Supabase keys.

## AI Service

The AI service is optional for the default mock-data app preview.

```bash
cd services/ai_service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Then check:

```bash
curl http://localhost:8000/v1/health
```

The service remains deterministic except for an explicit authenticated Coach
send. Coach is disabled by default; automated tests use an explicitly enabled
fake provider, while the development-only `local_codex_oauth` adapter never
uses `OPENAI_API_KEY`. Each Linux/WSL developer authenticates their own Codex
CLI manually, and FastAPI uses it only behind explicit local flags. Do not copy
another developer's Codex OAuth state into the repo or `.env`. See
`docs/phase-10-controlled-coach-plan.md` for the exact boundary and
`docs/local-dev.md` for the active settings and routes.

See `services/ai_service/README.md` for details.

## Supabase

Supabase is the intended auth and persistence backend. The current app supports:

- Guest mode without Supabase.
- Email/password auth through Supabase Auth.
- Google OAuth through Supabase Auth when OAuth is configured.
- Supabase-backed reads/writes for selected feature data when credentials and
  expected tables exist.
- In real mode, structured Setup reads authenticated state through
  `GET /v1/intake/setup` and saves initial completion or edits through
  `POST /v1/intake/complete` using a stable request id and optimistic base
  revision. Guest or mock Setup follows the same typed semantics locally and
  never calls Supabase or FastAPI.
- Guest Setup is intentionally not copied into an account automatically. A
  newly authenticated account loads its own backend Setup; canonical guest
  check-ins are the only guest product data migrated best-effort today, and only
  for a real non-demo account with `USE_MOCK_DATA=false`.
- Blank optional Setup answers create no goals, habits, schedule items, or
  memories. Named routines remain candidates until cadence is confirmed;
  setup-owned records use deterministic identities and can be reviewed, edited,
  archived, paused, or removed without reconciling manual rows.
- Setup-owned habits are edited, paused, or archived through Settings Setup;
  active Setup habits still appear in Today Habits for completion, intentional
  skip, and undo. Generic Habit Management edits only manually managed habits.
- A rejected 4xx Setup save keeps the draft editable; 409 also prompts a server
  reload. Timeouts, 5xx failures, and invalid success envelopes have an unknown
  durable result, so the exact submitted draft is locked for unchanged retry or
  explicit reload.
- Evening check-in is a two-page flow for mood, energy, stress, and friction.
  Stress source/influence is requested only from medium stress upward;
  the required primary-friction question includes `No major friction`, and up
  to two different `Also present` frictions are optional. Only the primary
  friction shapes Daily Mode. Tomorrow priority, reflection, and blocker are
  optional; the former gentle-tomorrow switch is no longer written. It no
  longer asks users to estimate focus that completed Focus sessions can
  measure. Morning check-in remains a separate short flow for sleep hours,
  an independent required 1–10 estimate of sleep quality, current energy, and
  day shape.
- Both captures merge under `daily_logs.metadata.captures` for the same user and
  date. Morning energy owns the compatible `energy_level` projection when
  present; Evening owns mood and stress, and Morning owns sleep. Linked
  `behavioral_events` are a dynamic, deterministically identified set of at
  most mood, energy, stress, and sleep events. Guest storage uses the same V2
  daily model while retaining V1 read/migration compatibility. Sleep quality
  stays in the Morning capture metadata and is mirrored onto its existing
  Morning-origin events, so it does not create an invented fifth event.
- The dashboard refresh action first refreshes the daily snapshot best-effort,
  then calls the deterministic recommendation generator with LLM wording
  disabled. Normal dashboard reads still do not generate recommendations.
- Supabase-backed Evening and Morning saves refresh the backend daily
  `user_state_snapshots` row best-effort for their explicit local
  `target_date`. Durable task, habit, and focus writes use the same refresh path
  after successful Supabase updates; refresh failure cannot roll back the
  original write, and guest/mock paths stay local.
- Dashboard tasks support create/edit, validated `5..480` minute estimates,
  complete, postpone, cancel, restore, and direct undo. Habit V1 supports daily,
  selected-ISO-weekday, and `1..7`-times-per-week cadence, active/paused/archived
  lifecycle for manual habits, explicit `completed|skipped` daily outcomes, and
  cadence-aware progress/streaks. `/deep-work` is now a real authenticated focus
  flow with one active session per user, optional owned task/habit linkage, and
  finish/abandon transitions that never complete the target implicitly.
  The Focus surface reconstructs a live countdown after reload, accepts custom
  duration, reuses the latest planned duration, and may suggest a median only
  after five completed sessions without changing it automatically. Dashboard
  keeps briefing, next block, capture status, Focus/Habits, and tasks prominent;
  signal detail, secondary suggestions, and the full week are collapsed.
- Every task update, including direct undo, and every manual habit
  edit/lifecycle update accepts a committed response loss only when an
  owner-scoped readback matches the exact mutation timestamp and requested
  fields. Habit outcome/undo fixes its target date before awaiting the write,
  reconciles the exact row or its absence, and refreshes that same date. Focus
  finish/abandon uses exact terminal readback. Every update to a terminal focus
  row is rejected; linked task/habit deletion is restricted; and snapshot
  refresh remains attributed to the persisted local focus start `entry_date`,
  even when the session ends later. The migration backfills missing legacy
  dates from `started_at` in UTC, which is also the Flutter/FastAPI fallback.
- Habit outcomes are revalidated under a database lock against the current
  active lifecycle and selected-weekday cadence. Paginated habit/outcome reads,
  local `started_on`, and calendar-date arithmetic avoid silent truncation and
  DST-dependent progress shifts. FastAPI also paginates complete habit-log and
  focus-session snapshot windows instead of treating server-capped pages as
  complete counts, using stable 1,000-row pages. Focus target validation locks
  the selected task or habit row before the session write.
- The strict `executable-action-v1` envelope is implemented in Flutter and
  FastAPI and is consumed by persisted briefings. Both parsers reject the same
  unknown fields, explicit-null metadata fields, coercions, invalid dates,
  duration bounds, metadata leakage, and command/kind/target mismatches.
  `review_plan` opens the real authenticated `/weekly-review` surface and never
  generates or applies a proposal by itself. Guest/mock sessions remain
  unavailable.
- The additive `summary.daily_state` contract is
  `explainable-daily-state-v1`. It uses strict V2 parsing, a fixed seven-day
  state lookback separate from the requested statistics window, explicit
  `missing`/`partial`/`current`/`stale` quality, and recovery-first
  `push`/`steady`/`recover`/`plan` classification. It carries bounded evidence
  and provenance but excludes tomorrow-priority, reflection, and blocker text.
  A very low current sleep-quality estimate can select recovery even after a
  long night; a moderately low estimate prevents `push` without treating sleep
  duration and quality as interchangeable.
- Phase 1 does not assign Daily Mode, rank briefing actions, generate
  recommendations on capture save, or call an LLM. Phase 2 assigns Daily Mode
  only inside persisted backend snapshots. Phase 3 exposes unranked execution
  controls but still does not rank actions, persist a briefing, mutate a plan,
  or call an LLM. Dashboard capture cards continue to show direct nullable
  source values and persisted structured context. Phase 4 owns deterministic
  briefing selection; Phase 5 reads or deliberately refreshes that persisted
  decision, and Phase 6 adds bounded recent feedback without changing the
  source evidence or Daily State classifier.
- `POST /v1/scheduled/daily-refresh` is a backend-only scheduler endpoint
  protected by `X-Scheduled-Refresh-Token`; it must not be called from Flutter.
  One UTC run instant determines each profile-local `briefing_date`. Missing
  snapshots or briefings are created, stale briefings are refreshed, and current
  pairs are skipped without changing their identities or timestamps. A bounded
  `profile_ids` list can target at most 20 eligible profiles for an operational
  retry without broadening access to guests or incomplete profiles. Results
  expose per-user snapshot, briefing, and failure-stage status. Recommendation
  refresh is off by default, and every scheduler path remains no-LLM. Normal
  Dashboard loads continue to read briefings with GET only.
- `GET /v1/weekly-reviews/latest` and the explicit-period GET are read-only.
  `POST /v1/weekly-reviews/generate` deliberately persists one deterministic
  completed-ISO-week review. Stale proposal controls stay disabled until a
  deliberate refresh. Direct application is limited to confirmed manual Habit
  V1 shrink/pause/archive commands with an exact target timestamp; other
  proposal kinds remain staged or return to Settings Setup.
- `/v1/calendar-integrations` exposes the optional `calendar-import-v1`
  boundary. Connection requires explicit `calendar-import-consent-v1`, file
  import is a deliberate retry-safe POST, event pages are read-only, and
  disconnect/delete have separate local semantics. Imported events never become
  app-authored commitments or provider writes.
- `/v1/deadline-plans` exposes the authenticated `deadline-plan-v1` boundary.
  GET is read-only; deliberate proposal/confirm/complete/cancel commands use
  stable request identities and separate latest/current optimistic revisions.
  The user's explicit estimate owns the budget, staged blocks do not replace an
  active revision, and first confirmation creates the stable managed task.
  Generic task mutations are rejected; plan completion/cancellation atomically
  projects matching task terminal state. Both require an active revision.
  Calendar-event selection and current-import availability use are explicit and
  never write back. `GET /v1/deadline-plans/workload` returns the strict side-
  effect-free seven-day reservation/Setup-commitment projection. Expanding one
  of those dates calls the separate compatible
  `GET /v1/deadline-plans/workload/{local_date}`
  `preparation-workload-detail-v1` read, which explains the owner-scoped plan
  minute/block contributions without choosing or changing a plan. The optional
  account rule is set through `PATCH /v1/account/preparation-budget`; `null`
  retains per-plan-only capacity, while `25..480` five-minute values cap total
  confirmed preparation per local date for new confirmations.
- `/v1/coach/capabilities`, `/v1/coach/history`, and `/v1/coach/memories` are
  authenticated read/control boundaries that do not generate a reply.
  `POST /v1/coach/respond` is the only deliberate model-call path. Completed
  request replay is provider-free; one request id cannot be reinterpreted, one
  owner has at most one in-flight request, and the default daily limit is 20
  retained attempts in the profile-local day. History deletion removes message
  content, tombstones requests, and keeps usage rows plus request identities.
  Memory selection is a separate owner-scoped projection and never edits the
  underlying Setup/manual memory.
- `POST /v1/notifications/{notification_id}/actions` is the authenticated
  `notification-lifecycle-v1` path for retry-safe read/unread/dismiss
  tombstones. Direct authenticated Notification DML remains forbidden, and the
  endpoint does not itself create or deliver notifications. Settings use
  `GET/PATCH /v1/notifications/settings`; foreground presentation uses
  `POST /v1/notifications/{notification_id}/delivery` only after explicit
  consent and deterministic generation through the protected local scheduler.

Important current caveat: the Flutter app targets the canonical snake_case
schema. The migration chain currently ends at
`20260722234000_setup_commitment_validity_guards.sql`. It adds no table or
column; it keeps Planner and Deadline Planner confirmation aligned with the
optional inclusive Setup semester bounds and fails closed on protected-function
drift. The preceding Planner migration adds its seven forced-RLS tables. The
earlier account preparation migration adds the nullable bounded profile rule,
service-role-only owner-locked setter, and database-boundary confirmation
recheck without rewriting existing plans. The earlier
`20260714143000_notification_delivery_settings_guard.sql` follow-up makes
Notification Settings replays request-exact across the shared Setup writer and
keeps the preference revision monotone. The preceding Notification Delivery
migration adds explicit consent, deterministic generation, and foreground
receipts. The earlier Account Export
grant restores only FastAPI's service-role read access to `lifestyle_entries`,
which was required by the then-31-table Account Export V1 contract. Planner V1
later extends the current export to 37 owner-content tables. Phase 3 adds task
estimates/terminal times, locked cadence-aware habit outcomes, immutable linked
focus history, and restricted target deletion without replacing existing RLS
or table grants.
Phase 4 adds the persisted owner-scoped daily briefing identity and policies.
Phase 8 adds the backend-owned owner-readable weekly review identity, forced
RLS, and a strict deterministic-provenance guard; it does not grant
authenticated review writes.
Phase 10 adds `coach_requests`, `coach_usage_events`, and
`coach_memory_selections`, hardens Coach/message-memory grants and forced RLS,
and installs service-role-only atomic request, turn, selection, and deletion
RPCs. Its follow-up guard aligns claim/complete/fail with history deletion on an
owner-first advisory-lock order. The later Phase 10 guards preserve whether a
safety redirect called the provider, make profile identity/role authority
canonical and backend-owned, remove legacy-role fallback and authenticated
profile deletion, and reserve onboarding eligibility projection for the atomic
backend Intake path. Real local PostgreSQL parallel claim/completion/deletion
smokes completed without deadlock or timeout and converged on the expected
message/usage/tombstone outcomes.
The V1 account migration adds a service-role-only full-account deletion RPC;
it removes restrict-linked focus history before the Auth/profile/product
cascade and does not weaken normal task or habit deletion.
The Notification lifecycle migration adds its owner-locked read/unread/dismiss
RPC and retry ledger. The subsequent application-table privilege guard makes
`anon` fail closed across every repo-owned product/ledger table, removes
authenticated `TRUNCATE`, `REFERENCES`, and `TRIGGER` authority while preserving
the intended per-table DML, and retains backend projections as read-only. It
also freezes optional legacy tables, hardens future `postgres` public-table
defaults, prevents reuse of the installed Auth trigger functions without
removing their triggers, and adds the Notification-ledger lookup index plus
non-validating timestamp-order checks for new or updated rows.
Remote projects still need to be inspected directly before relying on
`USE_MOCK_DATA=false`.

See `docs/supabase-current-state.md` before changing Supabase schema or relying
on real remote data.

For local product exploration with real Supabase-backed dashboards, seed three
local demo accounts:

```bash
npm run seed:demo
```

The script starts local Supabase if needed, refuses non-local Supabase URLs, and
replaces only the three local demo accounts with repeatable student, worker,
and recovery scenarios. Its typed Setup rows include valid applied revisions
with intentionally empty Setup-owned optional collections; separately seeded
scenario goals, habits, and commitments remain `demo_seed` data. The student
scenario is additionally enriched through the real backend services with
current Today/Weekly Review output, all three Habit cadences, Focus history,
Calendar Import, Preparation Plans, notification consent, and validated Coach
history. All demo accounts use the local-only password `DemoPass123!`.

## Verification

Standard non-destructive checks:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

This runs Flutter dependency resolution, analysis, widget tests, Python compile
checks, shell syntax checks, and whitespace checks.

Flutter app, if running commands manually:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter build web --debug --no-wasm-dry-run
```

AI service:

```bash
cd services/ai_service
uvicorn app.main:app --reload --port 8000
curl http://localhost:8000/v1/health
./.venv/bin/python -m pytest
```

Local Supabase verification:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

This default is inspection-only for migrations and fails if repository files
and local database history differ. After reviewing the pending SQL and local
data, use:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

That opt-in may change or delete local rows.

Local Supabase reset and migration verification:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

`RESET_DB=true` destroys and recreates the local Supabase database only. It must
not be used against a remote database.

Browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

The normal E2E command likewise requires current migration history and never
applies pending SQL automatically. Use `APPLY_MIGRATIONS=true` only after
reviewing and accepting the possible local-row changes.

For diagnosis only, `E2E_PHASE10_ONLY=true` plus the exact `E2E_RUN_ID` of an
existing eligible principal repeats the Coach portion against that E2E user.
It is not a substitute for the full command; see `docs/verification.md`.

The browser E2E script starts local Supabase, starts FastAPI with local backend
Supabase settings and the deterministic fake Coach provider, and runs Flutter
Web. It never contacts a live Codex account. Its smoke path includes authenticated
Setup ownership/revision assertions, Evening/Morning merge assertions,
deterministic linked-event checks, snapshot refresh, recommendations, core app
writes, and a token-protected Phase 7 preparation targeted only to its unique
test profile. The scheduler assertion verifies profile-local date, persisted
snapshot/briefing identities, no-LLM provenance, and a write-free retry; its
token is passed to FastAPI and the Node assertion process, never Flutter. Run
the command before claiming the current checkout passes that path.
The smoke now contains Phase 3 task transition/undo, habit skip/undo, focus,
committed-response-loss reconciliation for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish, plus negative
database assertions including terminal-focus `updated_at` mutation. Do not
describe them as passed in a later checkout until that checkout's command
succeeds.
The Phase 8 source path additionally covers missing/read-only review truth,
deliberate generation, exact persisted weekly facts/proposals, confirmed manual
habit adaptation, stale refresh, Setup non-mutation, and review-table RLS. Phase
9 adds explicit consent, bounded `.ics` reconciliation, paginated imported-only
events, disconnect/delete separation, schedule preservation, and integration
RLS. Phase 10 adds fake-provider Coach request/replay/safety/history/memory/RLS/
UI assertions. A focused Phase 10 rerun and the subsequent full combined journey
passed non-destructively against local Supabase in the 2026-07-13 current
checkout; the full run reported
`E2E browser smoke passed for e2e-1783947134@example.test`.

After Deadline Planner V1 was added, the full non-reset combined journey passed
again on 2026-07-18 after the product-polish slice. It reported
`E2E browser smoke passed for e2e-1784404040@example.test` and included the
two-page Evening flow, compact Dashboard expansions, the weekly-review entry,
planner lifecycle/projection, Calendar isolation, focus progress, RLS, Account
Export, account deletion, and guest zero-call checks.

The account-wide preparation-capacity follow-up then passed the full non-reset
combined journey locally on 2026-07-19:
`E2E browser smoke passed for e2e-1784448992@example.test`. It adds exact budget
save/direct-write denial, strict seven-day workload, cross-plan capacity,
changed-budget confirmation conflict, Today/Preparation-plans UI, cross-owner
isolation, export, and guest zero-call assertions. This is not evidence of a
remote migration, installed device, production provider, participant study, or
long-term outcome.

The subsequent actionable workload-day follow-up passed the standard gate and
non-reset Supabase verification with `608` Flutter tests, the complete FastAPI
suite with `766 passed, 1 skipped`, and the final full browser journey with
`E2E browser smoke passed for e2e-1784465767@example.test`. The browser pass
includes strict per-day plan contributions, cross-owner isolation, staged
replan navigation, and the root-modal fix that keeps `Cancel` on Preparation
plans. It remains local evidence and does not change the non-claims above.

The compact existing-plan replanning follow-up then passed the standard gate
with `610` Flutter tests and the final full non-reset browser journey with
`E2E browser smoke passed for e2e-1784475200@example.test`. The final run covers
the compact zero-request review, deliberate full-editor transition, cancellation,
existing planner/RLS lifecycle, and strengthened exact Flutter-Web input
checks. It remains local automated evidence and adds no participant, remote,
installed-device, background, provider, localization, or outcome claim.

With a fresh local database:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

Use real Ubuntu-installed `node`, `npm`, `supabase`, and Docker for E2E. If
those tools are installed through `nvm`, make sure the shell running the command
has the nvm bin directory on `PATH`.

## Documentation Map

- `docs/current-product-guide.md` - Concrete German map of the current product,
  navigation, features, data, learning behavior, dashboards, core concepts,
  Coach limits, and present information-architecture friction.
- `docs/local-dev.md` - Full local setup and troubleshooting.
- `docs/architecture.md` - Current architecture and data-flow overview.
- `docs/backend-roadmap.md` - Target backend flow, product agents, data model
  direction, LLM cost controls, and next implementation sequence.
- `docs/supabase-current-state.md` - Supabase auth, schema, RLS, and known gaps.
- `docs/verification.md` - Automated verification scripts and browser E2E.
- `docs/today-overview-v1-contract.md` - Read-only Today endpoint, exact
  streak/progress rules, agenda sources, Task/Habit selection, partial failures,
  guest boundary, and UI order.
- `docs/planner-v1-contract.md` - Central Planner navigation, deterministic
  availability, staged Task/Habit reservations, commitments, and Today V2.
- `docs/phase-3-executable-actions-contract.md` - Implemented executable task,
  habit, focus, and action-target contract.
- `docs/phase-8-weekly-review-contract.md` - Bounded ISO-week facts,
  proposals, freshness, ownership, and confirmed habit adaptation.
- `docs/phase-9-calendar-import-contract.md` - Explicit `.ics` consent,
  bounded retry-safe import, read-only provenance, and disconnect/delete rules.
- `docs/deadline-planner-v1-contract.md` - Explicit exam/assignment estimates,
  staged deterministic blocks, revision confirmation, focus progress, calendar
  isolation, and retry-safe ownership.
- `docs/product-polish-follow-up.md` - Completion status for capability-truth
  and plain-language polish, with the manual student study still explicit.
- `docs/ui-language-and-copy-contract.md` - English V1 language decision,
  canonical surface names, capability wording, and accessibility copy gate.
- `docs/student-usability-test-script.md` - Ready-to-run five-student journey,
  evidence template, and honest not-yet-run status.
- `docs/student-usability-study/` - Recruitment copy, facilitator runbook,
  anonymized per-session note template, and synthesis template for the
  still-manual study.
- `docs/synthetic-student-persona-simulation-2026-07-18.md` - Five-agent
  compressed persona walkthrough, code-backed findings and fixes, and explicit
  limits; it is not a participant or longitudinal study.
- `docs/product-review-handoff.md` - Self-contained review scope, invariants,
  verification checklist, and prompt for a fresh review chat.
- `docs/phase-10-controlled-coach-plan.md` - Implemented bounded Coach contract,
  local subscription-backed Codex OAuth adapter, privacy limits, and separate
  live-verification criteria.
- `docs/notification-lifecycle-v1-contract.md` - Stored-Inbox visibility,
  read/unread/dismiss commands, exact retry/conflict behavior, and delivery
  non-claims.
- `docs/notification-delivery-v1-contract.md` - Explicit foreground consent,
  deterministic generation, timezone/quiet/category/cap/dedupe guards, local
  scheduling, and at-most-once in-app presentation.
- `docs/v1-account-controls-contract.md` - Authenticated timezone and daily
  preparation budget, strict data export, password recovery, and permanent
  account-deletion contract.
- `docs/local-product-completion-handoff.md` - Ordered local completion plan for
  the real Coach, notifications, scheduling, visible actions, full-stack startup,
  and release-candidate verification before Android production work.
- `docs/next-chat-prompt.md` - Ready-to-use prompt for the next critical review
  and test pass.
- `apps/mobile/README.md` - Flutter app commands and configuration.
- `services/ai_service/README.md` - FastAPI service setup and endpoints.
- `AGENTS.md` - Instructions for agents working in this repo.
