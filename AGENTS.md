# Agent Instructions

These instructions are for coding agents working in this repository. They are
repo-local and must not depend on any user-private Codex skill or machine-local
profile configuration.

This file is the required starting point for agents. Read it before making code
or schema changes, then consult the linked docs for more detail.

## Start Here

Read these files before making changes:

1. `README.md`
2. `docs/local-dev.md`
3. `docs/architecture.md`
4. `docs/backend-roadmap.md` before planning backend, AI, onboarding, or agent
   workflows
5. `docs/daily-briefing-implementation-plan.md` before planning the next
   product slice, daily check-in changes, recommendation ranking, or dashboard
   decision-loop work
6. `docs/verification.md` before running or changing test automation
7. `docs/supabase-current-state.md` when touching Supabase, auth, data sources,
   or migrations
8. `docs/phase-3-executable-actions-contract.md` before changing executable
   actions or consuming them in a briefing

## Current State

MyLifeGraph is a Flutter web/mobile app with Supabase for auth and persistence
and a FastAPI service for authenticated deterministic recommendation workflows
and future AI integrations.

The app now targets a canonical snake_case Supabase schema. Older remote
databases may still contain legacy CamelCase tables such as `"User"`,
`"DailyLog"`, and `"Task"`, but new app code should use:

- `profiles`
- `daily_logs`
- `behavioral_events`
- `tasks`
- `schedule_items`
- `notifications`
- `coach_messages`
- `memory_entries`
- `ai_insights`
- `recommendations`
- `skillset_profiles`
- `notification_preferences`
- `goals`, `habits`, `habit_logs`, `focus_sessions`
- `intake_responses`, `user_state_snapshots`
- `daily_briefings`

The migration
`supabase/migrations/20260618170000_create_canonical_app_schema.sql` creates the
canonical schema, applies RLS policies, and copies data from legacy CamelCase
tables when they exist. It intentionally does not drop legacy tables. The
migration
`supabase/migrations/20260702092807_intake_v1_backend_foundation.sql` adds the
Intake V1 backend tables and RLS policies. The migration
`supabase/migrations/20260702195915_unique_user_state_snapshot_period.sql`
deduplicates `user_state_snapshots` by user/scope/period and adds the unique
index required for atomic backend upserts. The migration
`supabase/migrations/20260710120000_phase_0c_intake_request_revisions.sql`
adds the request identity, base/revision, pending/applied state, and uniqueness
constraints used by retry-safe Setup completion and editing. The migration
`supabase/migrations/20260710153000_profile_setup_revision_guard.sql` adds and
backfills `profiles.setup_revision`; FastAPI advances that projection only to a
newer applied Setup revision so a stale worker cannot overwrite a newer profile
projection. The migration
`supabase/migrations/20260710180000_atomic_intake_v1_setup_apply.sql` adds the
service-role-only `apply_intake_v1_setup_revision` RPC. It serializes Setup apply
per user with a transaction-scoped advisory lock and atomically reconciles
preferences, Setup-owned records, the canonical onboarding snapshot, the intake
state, and the profile projection.
The migration
`supabase/migrations/20260711120000_phase_3_executable_action_schema.sql` adds
task estimates and terminal timestamps, explicit habit outcomes, and the linked
focus-session lifecycle. It preserves existing table RLS/grants while adding
exact task/focus lifecycle and duration checks, locked active/cadence-aware
habit-outcome validation, locked focus-target validation, restricted target
deletion, full terminal-history immutability, deterministic UTC-date backfill
for legacy focus rows, and the one-active-focus-session invariant.
The migration
`supabase/migrations/20260712064836_phase_4_daily_briefings.sql` adds the
owner-scoped persisted daily briefing identity, bounded JSON checks, explicit
Data API grants, and forced RLS policies used by the backend-only generator.

## Important Docs

- `docs/architecture.md` - system shape and current backend/frontend boundary.
- `docs/backend-roadmap.md` - target backend flow, product agents, data model
  direction, LLM cost controls, and the next implementation sequence.
- `docs/daily-briefing-implementation-plan.md` - current product direction for
  the daily decision loop, lightweight capture cadence, stress taxonomy, Daily
  Mode, briefing service, and next implementation phases.
- `docs/supabase-current-state.md` - canonical schema, legacy table mapping, and
  migration notes.
- `docs/local-dev.md` - local runbook for Flutter, Supabase, and FastAPI.
- `docs/verification.md` - automated checks, local Supabase verification, and
  current E2E gaps.
- `docs/phase-3-executable-actions-contract.md` - implemented task, habit,
  focus, and ranking-independent action-target contract.
- `README.md` - high-level project overview.

## Next Implementation Direction

The **Intake V1 without LLM** foundation, controlled deterministic
recommendation refresh after authenticated intake, and the authenticated
deterministic snapshot aggregator endpoint now exist. A deliberate dashboard
refresh action calls the deterministic recommendation generate endpoint without
LLM wording. Phase 3 executable tasks, cadence-aware habits, linked focus
sessions, and the strict `executable-action-v1` envelope are implemented for
authenticated real accounts. Snapshots now include additive habit-outcome and
focus-session summaries while preserving Phase 2 Daily State unchanged. A
backend-only scheduled endpoint refreshes onboarded non-guest profiles for
cron-style runs. Phase 4 now persists one strict deterministic briefing per
profile-local date behind read-only GET and deliberate idempotent POST routes.
Phase 5 now consumes that contract in a decision-first Today Dashboard: normal
load is GET-only, missing/stale/error truth stays visible, stale actions are
disabled until deliberate adjustment, and validated primary/support targets
dispatch through the existing Phase 3 handlers. Guest/mock remains local and
never fabricates a personalized briefing.
Read `docs/backend-roadmap.md`,
`docs/daily-briefing-implementation-plan.md`, and the Phase 3 contract before
planning the next backend, briefing, dashboard, or agent workflow.

Do not jump straight to broad LLM integration, calendar import, weekly planning,
vector search, or autonomous background agents. The next product slice is Phase
6's bounded decision-feedback history and useful default Insight; it must learn
deterministically without erasing original briefing evidence. Phase 0A, Honest Capture, is
implemented: `/daily-check-in` redirects to the canonical lightweight flow;
measurements require explicit selection; a typed draft drives guest and Supabase
persistence; same-day guest rows and linked behavioral events are deduplicated;
failed writes retain the draft; guest saves are readable on return; and
value-level widget/data-source/browser assertions cover distinctive values.

Phase 0B, Source And Surface Truth, is implemented. Explicit guest/demo mode is
labeled and stays local; authenticated dashboard, notification, and
recommendation failures no longer become mock content; recommendation feeds
preserve empty/stale/fresh/error semantics; the dashboard shows direct nullable
check-in values instead of proxy scores; notification actions use a strict
internal allowlist; Coach and the former Deep Work preview were gated; Settings
contains only durable behavior; and guest users no longer see Supabase-only
habit actions. Phase 3 later replaced the Deep Work preview with a real synced
focus flow. `USE_MOCK_DATA=true` deliberately makes product data surfaces local/
demo even if a Supabase auth session exists; real authenticated sources are used
only with `USE_MOCK_DATA=false`. Mock/demo auth boot does not read or create a
remote profile, and it restores locally applied Setup across reloads.

Phase 0C, First-Run And Setup Integrity, is implemented. Setup now uses explicit
required selections and progressive optional detail; blank optional answers
create no owned records. Guest and authenticated re-entry load a typed saved
setup with loading, error, and retry states. Authenticated saves use
`request_id` plus `base_revision`, converge safely across retries and edits,
and never fall back to direct partial profile/timetable completion. Named
routines remain candidates in the intake response until cadence is explicitly
confirmed. Setup-owned goals, active habits, and fixed commitments have durable
review/edit/archive, pause, and removal paths without touching manual rows.
Setup apply is one database transaction behind a service-role-only RPC. Client
validation and HTTP 4xx failures leave the draft editable, a 409 suggests
reloading server state, and an ambiguous network/5xx/invalid-response result
locks the exact submitted draft for unchanged retry or reload. Setup-owned
habits are edited only through Settings Setup, but active ones remain available
for daily completion in Habit Completion.

Phase 1, Lightweight Evening And Morning Capture, is implemented. Evening
Shutdown and Morning Calibration are separate typed flows over one
`DailyCaptureEntry`. Their same-day merge replaces only the submitted capture
kind under `daily_logs.metadata.captures`, preserves the other kind, and
projects compatible numeric columns with Morning energy taking precedence over
Evening energy. Supabase writes rebuild a dynamic set of at most four
deterministically identified current-state events; guest storage uses V2 daily
JSON while continuing to read and migrate V1 guest check-ins. Real capture
writes refresh the explicit local `target_date` snapshot best-effort, while the
backend prefers event `metadata.entry_date` over UTC timestamps when filtering
the broadened read window. Dashboard reads remain direct and nullable, expose
only persisted capture context, and never synthesize a mode or score. Phase 1
does not add Daily Mode, briefing ranking or persistence, recommendation
generation on save, an LLM, calendar import, or autonomous workers. The Phase
0C Setup service-role RPC and its retry/revision contract are unchanged.

Phase 2, Explainable Daily State, is implemented. Daily and weekly snapshots
add `summary.daily_state` under the `explainable-daily-state-v1` contract. A
strict parser trusts Phase 1 V2 capture metadata only when its identity, enum,
numeric, timestamp, and numeric-projection invariants hold; legacy numeric
fallback is allowed only when no V2 marker exists. Daily State uses a fixed
seven-day state lookback independent of the requested statistics window.
Evening is current on the target date or previous date, Morning only on the
target date. The result exposes `missing`, `partial`, `current`, or `stale`
quality; recovery-first `push`, `steady`, `recover`, or `plan` classification;
bounded risks and reasons with field-level evidence; and deterministic
provenance without persisting capture free text. The existing
`snapshot-aggregator-v1` source marker remains stable, while snapshot metadata
records the Daily State contract version and lookback. Top-level
`summary.risk_flags` aliases the current Daily State codes, older
statistics-window flags live under `summary.window_risk_flags`, and
`recommended_next_focus` is derived recovery-first from the mode. Phase 2 adds
no schema, Today UI, recommendation ranking, briefing persistence, or LLM
usage.

Phase 3, Executable Action And Habit Contracts, is implemented. Authenticated
real accounts can create/edit/complete/postpone/cancel/restore tasks with
estimates and recoverable UI; manage daily, selected-weekday, and weekly-target
habits with explicit completed/skipped outcomes and undo; and start, finish, or
abandon at most one active focus session linked to an owned task or habit.
Setup-owned habit definitions remain owned by Settings Setup while their active
rows remain executable. Habit reads paginate history starting 370 calendar days
before today, and local `started_on` plus calendar-date arithmetic keep progress
stable across DST changes. Every task update, including undo, and every manual
habit definition/lifecycle update reconciles an ambiguous committed response
only by exact owner-scoped timestamp/requested-field readback. Habit outcome
and undo capture one target date before awaiting the write, reconcile the exact
row or its absence, and refresh that same date. Focus finish/abandon uses exact
terminal readback. Terminal focus history rejects every update and linked
targets cannot be deleted out from under it. The strict Flutter/FastAPI
`executable-action-v1` parsers reject the same unknown, explicit-null, coerced,
and mismatched shapes; unsupported commands remain explicit, and `review_plan`
stays unavailable. New focus rows persist the local start `entry_date`; the
migration backfills missing legacy values from the UTC date of `started_at`,
which is also the shared Flutter/FastAPI fallback. Snapshots add bounded
habit/focus counts and evidence from fully paginated, stably ordered 1,000-row
action-fact pages, and `explainable-daily-state-v1` remains unchanged.
Guest/mock sessions expose none of these remote commands.

Phase 5, Decision-First Today Dashboard, is implemented. It consumes the
persisted Phase 4 briefing without generation on normal load, puts mode,
capacity, freshness, and one strict primary action above secondary metrics,
dispatches validated actions through Phase 3, and preserves
missing/stale/error/demo truth. The immediate next slice is Phase 6 feedback and
useful Insights; do not fold Coach, calendar import, broad automation, or LLM
work into it.

FastAPI-backed browser E2E coverage for revisioned Setup ownership/retry/edit,
concurrent same-request convergence, post-intake recommendations, exact Phase 2
Daily State recomputation, daily snapshot refresh, deliberate dashboard
recommendation refresh, and Supabase-backed habit management now exists.
Phase 3 adds focused Flutter/FastAPI tests, but its task/habit/focus database
journeys are also encoded as exact Playwright/database assertions, including
committed-response-loss reconciliation for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish. Negative writes
cover lifecycle/range/cadence constraints and every terminal focus update,
including `updated_at`. Phase 4 adds exact read-only/generate, persisted action,
and idempotent daily-identity assertions. Phase 5 adds GET-only Dashboard load,
honest briefing state, deliberate `force=true` adjustment, and real primary
action dispatch assertions. The combined browser journey passed
non-destructively in the 2026-07-12 implementation checkout; later changes must
still establish their own current-checkout pass before claiming E2E.

The implemented post-intake refresh is backend-only and best-effort:

- `GET /v1/intake/setup` derives `user_id` from the verified Supabase bearer
  token and returns the newest `intake-v1` Setup row: the latest pending row for
  an exact retry/resume, otherwise the latest applied revision.
- `POST /v1/intake/complete` derives `user_id` from the verified bearer token
  and acts as both initial completion and revision-checked edit.
- The intake service writes pending/applied `intake_responses` revisions,
  then calls the service-role-only atomic Setup apply RPC. The RPC takes a
  per-user transaction advisory lock; reconciles notification preferences and
  Setup-owned goals, habits, schedule items, and memories; upserts the canonical
  `setup:intake-v1` onboarding snapshot; marks the intake applied; and projects
  `profiles.setup_revision`, completion time, and explicit display name in the
  same transaction.
- Applied Setup advances `profiles.setup_revision` monotonically; an older
  worker or replay cannot project stale profile fields over a newer revision.
- Retries reuse `request_id`; edits send `base_revision`. Blank optional values
  materialize nothing, and reconciliation archives/removes only setup-owned
  records while preserving rows from manual or other sources.
- One exact legacy placeholder is removed during reconciliation when omitted:
  unmarked onboarding `Math`, `Room 204`, Monday `08:15`-`09:45`. Other manual
  or unmarked onboarding rows remain preserved.
- It then calls the deterministic recommendation engine with no LLM usage.
- The recommendation engine reads recent `daily_logs`, `behavioral_events`,
  `tasks`, and latest `user_state_snapshots`, verifies candidates, dedupes by
  fingerprint, and persists accepted rows to `recommendations`.
- Normal dashboard reads through `GET /v1/recommendations` must still not
  generate recommendations.
- The dashboard refresh action is deliberate and calls
  `POST /v1/recommendations/generate` with LLM wording disabled after a
  best-effort daily snapshot refresh. Guest/mock paths must remain local.
- `POST /v1/snapshots/generate` derives `user_id` from the verified Supabase
  bearer token and creates or refreshes deterministic `daily` and `weekly`
  `user_state_snapshots`.
- `POST /v1/scheduled/daily-refresh` is backend-only, uses
  `X-Scheduled-Refresh-Token`, lists onboarded non-guest profiles, and refreshes
  deterministic daily snapshots without LLM usage. If recommendation refresh is
  explicitly included, LLM wording remains disabled.
- The canonical Supabase-backed Evening Shutdown and Morning Calibration plus
  authenticated task, habit, and focus writes call daily snapshot refresh
  best-effort after the durable write. Capture refreshes include their explicit
  local `target_date`. Refresh failure never rolls back the original action;
  guest/mock paths remain local and must not call the AI service.

## Local Supabase Workflow

Supabase CLI and Docker are required for local database testing. Use real Ubuntu
tool installations; `supabase --version` and `docker --version` must work in the
Ubuntu shell. The preferred
agent-safe command is:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify_supabase_local.sh
```

This starts the local Supabase stack, redacts CLI key output, reads the local
anon key from `supabase status -o env`, and runs Flutter tests with
`USE_MOCK_DATA=false`.

If Node.js, npm, or Supabase CLI are installed through `nvm`, a non-interactive
agent shell may not inherit that `PATH` even though the commands work in the
user's interactive Ubuntu shell. In that case, source the real nvm environment
or pass a narrow `PATH`/`NODE_BIN` override. Do not install replacement Node or
Supabase binaries into `.tools/`.

For manual local Supabase inspection from the repo root:

```bash
supabase start
supabase status
```

Use the scripted `RESET_DB=true ... scripts/verify_supabase_local.sh` form when
you actually intend to run `supabase db reset`.

`supabase db reset` must complete through:

```text
20260712064836_phase_4_daily_briefings.sql
```

Expected local reset notices include skipped legacy CamelCase tables and
already-existing canonical tables. Those notices are normal. Errors are not.
The Phase 3 migration normalizes every positive legacy value to completion and
intentionally errors when a legacy `habit_logs` row has no status and
`value <= 0`; inspect and resolve that row's real meaning rather than
fabricating an intentional skip. Use
`HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local`
for a non-destructive pending local migration, and the scripted
`RESET_DB=true` flow only when proving the full chain on a fresh local database.

Do not assume the live remote database state from migrations alone. Inspect it
through the Supabase dashboard, CLI, or connector before making claims about the
remote project.

Do not run destructive Supabase commands such as `supabase db reset` unless the
user explicitly asks for that operation or is actively working with you on local
database reset/debugging. Use the scripted form when a local reset is intended:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

Never paste or commit Supabase keys. For the Flutter app, only the local anon key
belongs in `.env`. Never use the service role key in the client.

## Local App Workflow

Create a local `.env` from `.env.example`:

```bash
cp .env.example .env
```

For local Supabase-backed testing:

```env
APP_ENV=development
USE_MOCK_DATA=false
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<local anon key from supabase status>
AI_SERVICE_BASE_URL=http://localhost:8000
```

Start Flutter:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/start_frontend.sh
```

Prefer the repo script over ad hoc Flutter commands. If Flutter is not on
`PATH`, ask for or infer a `FLUTTER_BIN` override instead of hard-coding a
machine-specific path in source files.

Open:

```text
http://127.0.0.1:7357
```

Manual smoke test after schema or Supabase-client changes:

- Register or sign in.
- Complete required-only setup, then re-enter it from Settings.
- Add, edit, and review one setup-owned commitment without changing a manual row.
- Save Evening Shutdown through either current route, then save Morning
  Calibration and confirm that both states remain present.
- Create/edit/postpone/complete/undo/cancel/restore one task.
- Create daily, weekday, and weekly-target habits; complete, skip, and undo an
  outcome while preserving Setup ownership.
- Start and finish or abandon a linked focus session without completing its
  target automatically.
- Open dashboard.
- Open notifications.

The browser smoke path is automated through Playwright in `scripts/e2e_web.sh`.
The widget tests still cover the faster guest auth, guest onboarding, and guest
canonical check-in path. See `docs/verification.md` before changing or
claiming E2E coverage.

## Verification Commands

Run these after relevant changes:

```bash
cd apps/mobile
flutter analyze
flutter test
```

If Flutter is not on `PATH`, use:

```bash
cd apps/mobile
/home/gregor/tools/flutter/bin/flutter analyze
/home/gregor/tools/flutter/bin/flutter test
```

From the repo root:

```bash
python3 -m compileall services/ai_service/app
git diff --check
```

Or run the standard non-destructive verification bundle:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh
```

`scripts/verify.sh` runs shell syntax checks, Flutter dependency resolution,
Flutter analysis, Flutter widget tests, Python compile checks, and
`git diff --check`.

For docs and shell scripts:

```bash
bash -n scripts/start_frontend.sh
```

If Supabase migrations changed and a local reset is intended, use the scripted
reset form:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

Do not run a raw `supabase db reset` unless the user explicitly asks for that
operation or you are already debugging the local reset workflow with them.

For the local Supabase-backed preflight workflow:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

For the local Supabase reset workflow:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

For browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter bash scripts/e2e_web.sh
```

Browser E2E also requires real Ubuntu Node.js 20+ and npm. Windows `npm`/`npx`
shims are not sufficient inside this WSL project.
If the interactive Ubuntu shell has Node/Supabase through nvm but the agent
shell cannot find them, run with the real nvm bin directory on `PATH` or set
`NODE_BIN`; keep using the actual installed tools.

For browser E2E with a fresh local database:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
bash scripts/e2e_web.sh
```

If browser E2E fails because the local database is behind repository migrations,
prefer applying pending local migrations with
`HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local`
before using `RESET_DB=true`. Use reset only when a fresh local database is
intended.

The E2E script may read the local service-role key from `supabase status -o env`
for FastAPI backend settings plus Node-side local test user creation and
database assertions. Never pass the service-role key into Flutter, browser code,
docs examples, or chat output.

## Documentation Requirement

Documentation must stay current. After any significant change to schema,
startup flow, configuration, architecture, environment variables, deployment, or
agent workflow, update the relevant docs in the same change.

At minimum:

- Schema or RLS changes: update `docs/supabase-current-state.md`.
- Backend/frontend boundary changes: update `docs/architecture.md`.
- Local setup or command changes: update `docs/local-dev.md`.
- Agent workflow or safety changes: update this `AGENTS.md`.
- Verification workflow changes: update `docs/verification.md` and link any
  changed commands from `docs/local-dev.md`.

Do not leave future agents to rediscover changed setup steps from terminal
history.

## Environment And Secrets

`.env` is intentionally ignored by git. Agents may technically read it in the
local workspace if needed to run the project, but must treat it as secret
material:

- Do not print `.env` contents in chat or logs.
- Do not commit `.env`.
- Do not copy keys into docs.
- Prefer asking the user to paste redacted command output.
- If a value is needed for a command, pass it through the existing scripts or
  environment, not through committed files.

Local Supabase anon keys are acceptable in `.env` for local development only.
Production service-role keys must never be used in the Flutter app.

## Working Tree Safety

This repo may contain user changes. Do not revert unrelated files. In
particular, dependency lockfiles may change after running package managers; call
that out clearly instead of silently discarding it.

Before broad edits, inspect `git status --short`. If a file already has changes,
read it carefully and work with those changes instead of overwriting them.
