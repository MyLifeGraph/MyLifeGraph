# Backend Roadmap

This document is the source of truth for the intended backend flow and the next
implementation sequence. It describes the target product architecture, the
background service roles, the data model direction, and how to keep LLM usage
low enough for multiple users.

## Product Goal

MyLifeGraph should become a personal coaching app that can start with a small
guided intake, learn from daily use, and produce useful recommendations without
calling an LLM for every screen load.

The product should not compete as a complete task manager, habit tracker,
journal, wearable dashboard, and chat assistant at the same time. Its primary
job is to turn current capacity, goals, commitments, habits, and recent behavior
into one realistic next action, then learn from the outcome. The detailed user
operating loop, product object model, habit contract, and maturity gates live in
`docs/daily-briefing-implementation-plan.md`.

The backend direction is:

```text
Flutter app
  -> Supabase Auth
  -> Supabase Postgres for user-owned records
  -> FastAPI AI service for privileged and intelligence workflows
       -> deterministic services first
       -> optional job workers
       -> LLM provider only behind budgeted service boundaries
```

Flutter may write simple user-owned records directly through Supabase RLS:
profiles, check-ins, tasks, goals, habits, schedule items, notifications, and
coach messages. FastAPI owns workflows that need service-role access,
aggregation, generation, verification, cross-table reasoning, or any LLM call.

## Current Backend State

Already implemented:

- Supabase Auth and canonical snake_case app tables.
- Flutter mock and guest mode.
- Flutter Supabase-backed auth, onboarding, dashboard, notifications, and
  check-ins. The unimplemented Coach surface is gated from production routing.
- Honest Capture:
  - One canonical lightweight check-in implementation serves both current routes.
  - Mood, energy, sleep, and stress require explicit selection and flow through a
    typed draft to local guest or Supabase persistence.
  - Supabase writes link four current signals to the daily log and replace them
    on same-day save; guest storage also keeps one entry per calendar day.
  - Failed writes retain the draft, in-flight duplicate submits are ignored, and
    exact values are covered by mapper, widget, guest, and browser assertions.
- Lightweight Evening And Morning Capture:
  - `EveningShutdownDraft` and `MorningCalibrationDraft` merge into one typed
    `DailyCaptureEntry` per local date without one capture erasing the other.
  - Evening stores exact stress intensity/source/controllability, focus band,
    friction, tomorrow priority, and only explicitly supplied optional detail;
    Morning stores sleep hours, current energy, and day shape only.
  - `daily_logs.metadata.captures` owns the two structured states. Numeric
    projections retain existing consumers: Morning energy takes precedence,
    Evening owns mood/stress, and Morning owns sleep.
  - Supabase rebuilds a dynamic maximum of four deterministically identified
    current-state events linked to the daily row. Guest V2 storage keeps the
    same merge semantics and retains V1 read/auth-migration compatibility.
  - Successful real captures request the daily snapshot for their explicit
    local `target_date`; backend event filtering prefers metadata entry date in
    a broadened UTC read window. Guest/mock remains entirely local.
  - Dashboard capture state stays direct and nullable. Phase 1 adds no Daily
    Mode, action ranking, briefing persistence, recommendation generation on
    save, or LLM usage.
- FastAPI `/v1/health`.
- FastAPI authenticated recommendation endpoints:
  - `GET /v1/recommendations`
  - `POST /v1/recommendations/generate`
- Supabase bearer token verification in FastAPI when backend Supabase settings
  are configured.
- Deterministic recommendation generation from `daily_logs`,
  `behavioral_events`, `tasks`, and latest `user_state_snapshots`.
- Recommendation verification, dedupe fingerprints, freshness checks, and
  persistence to `recommendations`.
- Controlled post-intake recommendation refresh from the onboarding snapshot.
- Deliberate dashboard recommendation refresh/generate UX that calls the
  deterministic backend generate endpoint with LLM wording disabled.
- Flutter reads persisted recommendations through FastAPI in real backend mode.
  Only explicit guest/mock sessions receive labeled demo data; missing real
  session/config, network errors, and invalid responses remain errors.
- Intake V1 and First-Run/Setup integrity without LLM:
  - Authenticated `GET /v1/intake/setup` plus completion/edit through
    `POST /v1/intake/complete`, both derived from the verified bearer token.
  - Progressive explicit Flutter Setup with typed guest and authenticated
    prefill, loading, error, retry, and review states.
  - Request-id replay, optimistic base revisions, pending/applied intake rows,
    deterministic UUIDv5 materialized record ids, and convergent reconciliation.
  - A backfilled monotonic `profiles.setup_revision` guard prevents an older
    worker from projecting stale profile fields over a newer applied revision.
  - A service-role-only PostgreSQL RPC uses a per-user transaction advisory lock
    and atomically applies preferences, owned records, onboarding snapshot,
    intake state, and profile projection.
  - Optional blanks create no owned row. Named routines remain response-only
    candidates until cadence confirmation; manual/other-source rows are never
    archived or removed by Setup, apart from one exact known legacy
    `Math`/`Room 204`/Monday `08:15`-`09:45` placeholder.
  - Durable goal archive, habit pause/archive, fixed-commitment removal, one
    constant-period onboarding snapshot upsert, and first deterministic
    recommendations from explicit structured answers.
  - Setup-owned habits are managed through Settings Setup but remain available
    in Habit Completion when active; generic Habit Management excludes them.
- Snapshot Aggregator foundation:
  - `POST /v1/snapshots/generate`.
  - Authenticated backend snapshot refresh derived from the verified bearer
    token.
  - Deterministic `daily` and `weekly` `user_state_snapshots` from recent
    check-ins, behavioral events, tasks, goals, habits, schedule items, and
    memory entries.
  - Compact summaries with risk flags, next-focus hints, input counts, and
    evidence references.
  - Additive `summary.daily_state` and `signals.daily_state` under
    `explainable-daily-state-v1`, with a strict V2-only parser, legacy fallback
    only when no V2 marker exists, and a fixed seven-day state lookback separate
    from the statistics window.
  - Explicit Evening/Morning freshness plus `missing`, `partial`, `current`, and
    `stale` quality. Evening may be current from the target date or previous
    date; Morning is current only from the target date.
  - Recovery-first `push`, `steady`, `recover`, and `plan` classification with
    bounded risks, reasons, field-level evidence, deterministic provenance, no
    learned-baseline claim, and no persisted capture free text.
  - Best-effort Flutter daily snapshot refresh after the canonical
    Supabase-backed daily check-in, dashboard task status writes, and Quick
    Action habit management/completion writes.
  - Snapshot refresh service entrypoints for task and habit changes are wired to
    the active dashboard task and Quick Action habit paths.
- Quick Action habit management:
  - Authenticated Supabase users can create, edit, pause, restore, and inspect
    7-day progress for habits.
  - The flow uses the existing `habits` and `habit_logs` tables and does not
    add schema, workers, or LLM usage.
  - Successful habit writes trigger the same best-effort daily snapshot refresh
    as habit completions.
- Scheduled refresh foundation:
  - `POST /v1/scheduled/daily-refresh`.
  - Protected by backend-only `X-Scheduled-Refresh-Token`.
  - Lists onboarded non-guest profiles, prioritizes users missing the target
    date's daily snapshot, then fills the batch with the oldest existing daily
    snapshots.
  - Refreshes deterministic daily snapshots with the existing idempotent
    snapshot upsert.
  - Can optionally run deterministic recommendation generation with LLM wording
    disabled.
- Browser E2E starts FastAPI with local Supabase backend settings and verifies
  authenticated required-only Setup, retry/edit/review identity and ownership,
  deterministic post-intake recommendations, backend daily snapshot refresh
  after check-ins, exact Phase 2 state recomputation, and core Supabase-backed
  app writes.

Not yet implemented:

- A coherent Today action surface connecting tasks, habits, focus sessions,
  recommendations, and feedback.
- Cadence-aware Habit V1 semantics. Current completion progress is a seven-day
  completion count; it does not yet model scheduled opportunities, intentional
  skip, weekly-target streaks, or undo.
- Coherent executable task, habit, focus-session, and bounded planning command
  contracts that a future briefing can safely target.
- A production background job queue or worker.
- Deployed cron wiring for the scheduler-triggered refresh endpoint.
- Real coach-response backend.
- LLM provider integration.
- Memory extraction beyond current direct writes.
- Weekly planning and weekly review.
- Calendar import.

## Architectural Principles

- Keep Supabase as the source of truth for auth and user-owned data.
- Keep the Supabase service-role key only in backend environments.
- Derive `user_id` on the backend from a verified Supabase bearer token.
- Never trust request-provided `user_id`.
- Use RLS on every exposed Supabase table.
- Prefer deterministic rules, cached summaries, and explicit jobs over live LLM
  calls.
- Never call an LLM on dashboard load.
- Never send full user history to an LLM.
- Calendar import is optional. It improves coaching quality, but it must not be
  required to start using the product.
- New backend work should preserve mock and guest mode.
- Guest/demo, real-backend, derived, integrated, and model-generated data must
  have distinct provenance. Never silently replace failed real-user reads with
  personalized-looking demo data.
- Every personalized output should carry freshness, evidence or reason, and a
  data-quality state where history is required.
- Every production-visible primary action must execute a real command, persist
  correctly, and expose stale/error/rollback behavior.
- Recommendations may propose tasks, habits, focus sessions, or schedule changes,
  but must not create user-owned commitments without confirmation.

## Target Backend Services

These are "agents" in the product sense. Implement them as explicit services,
repositories, and jobs, not as unconstrained autonomous LLM loops.

| Service | Trigger | Reads | Writes | LLM use |
| --- | --- | --- | --- | --- |
| Intake service | First completed onboarding | Intake payload, profile | `intake_responses`, `profiles`, `goals`, `habits`, `schedule_items`, `notification_preferences`, `memory_entries`, `user_state_snapshots` | None for v1 |
| Signal aggregator | Intake, daily check-in, task/habit changes, scheduled jobs | `daily_logs`, `behavioral_events`, `tasks`, `goals`, `habits`, `schedule_items`, `memory_entries` | `user_state_snapshots`, optional `ai_insights` | None by default |
| Recommendation service | Intake complete, explicit refresh, scheduled refresh | `user_state_snapshots`, `daily_logs`, `behavioral_events`, `tasks`, existing `recommendations` | `recommendations` | Optional wording only later |
| Recommendation verifier | Every generated recommendation | Candidate metadata, active recommendations | Accept/reject result | None |
| Daily briefing service | Evening shutdown, morning calibration, explicit refresh, scheduled jobs | `user_state_snapshots`, `recommendations`, recent check-ins, goals, tasks, habits, feedback | `daily_briefings` or derived briefing payload, optional recommendation status updates | None for v1 |
| Coach service | User sends coach message | Recent messages, snapshots, selected memory | `coach_messages`, optional memory candidates | Yes, budgeted |
| Memory service | Check-ins, coach conversations, weekly review | Raw notes/messages, existing memory | `memory_entries` | Optional extraction only |
| Planning service | Weekly review, user request | Goals, tasks, habits, schedule, snapshots | `tasks`, `schedule_items`, `recommendations`, `coach_messages` | Optional for complex plans |
| Notification service | Schedule and event changes | Preferences, recommendations, deadlines | `notifications` | None |

The intake foundation, controlled post-intake recommendation refresh, first
authenticated snapshot aggregator endpoint, deliberate dashboard refresh UX,
first real habit management flow, scheduler-triggered daily refresh endpoint,
and deterministic Insights correlation exploration now exist. The next product
work should build the Daily Briefing / Daily Decision Loop foundation before
coach, memory extraction, weekly planning, calendar import, or LLM provider
work. Deployed cron/job execution remains useful, but it should precompute a
defined daily state or briefing contract rather than exist as infrastructure in
search of a product output. See `docs/daily-briefing-implementation-plan.md`
for the current product contract and phase sequence.

## User Start Flow

The user should not start with an empty dashboard and should not be forced to
connect a calendar. The required intake path should stay under three minutes;
detail can be added progressively. The intended first-run flow is:

1. Register, sign in, or continue as guest.
2. Complete a short guided intake using explicit answers only.
3. Pick current focus areas and describe the typical day.
4. Optionally add up to three named goals, routines, or fixed commitments.
5. Set basic reminder preferences.
6. Optionally connect a calendar later.
7. Land on an intake-based starting briefing or one missing calibration question.

The app must not create fallback goals, habits, or timetable blocks for blank
answers. Existing routines collected during intake should remain candidates
until the user confirms their cadence. First-day output must say that it is based
on intake/current calibration and must not imply a learned personal baseline.

## User Operating Loop

The complete acceptance path is defined in
`docs/daily-briefing-implementation-plan.md`. Backend and Flutter work should
support this sequence:

```text
first intake
  -> conservative starting briefing
  -> short morning calibration
  -> one executable primary action
  -> passive task/habit/focus feedback during the day
  -> evening shutdown and provisional tomorrow preview
  -> returning-morning correction
  -> weekly review only after enough real outcomes exist
```

Capability should mature with evidence:

- Start: use only explicit intake and current calibration.
- First week: use recency, action outcomes, and simple workload/recovery flags.
- Two-plus weeks: show only emerging patterns with sample size and confidence.
- One-plus month: introduce personal baselines, weekly adaptation, and stronger
  ranking.
- Later: integrations reduce capture effort; controlled Coach explains or stages
  changes after the deterministic loop is useful.

No stage may claim causation, diagnosis, or a stable learned baseline before the
required evidence exists.

### Intake Questions

Use structured answers rather than free text wherever possible.

Required fields:

- Primary focus areas: `focus`, `energy`, `sleep`, `stress`, `planning`,
  `movement`.
- Typical weekday shape.
- Best energy window.
- Desired coaching style: direct, gentle, analytical, accountability-focused.
- Reminder preference and quiet hours.

Optional fields:

- Top 1 to 3 goals.
- Current friction points.
- Existing named routines, initially as candidates.
- Known fixed commitments.
- Free-form context note.
- Calendar connection intent.

### Calendar Policy

Calendar import is a quality booster, not an onboarding gate.

Implement later as:

- Optional connection after the first useful dashboard.
- Read/import into canonical schedule/calendar tables.
- User-visible controls for disconnecting and deleting imported data.
- No LLM processing of calendar content by default.

If calendar support is added, prefer dedicated tables such as
`calendar_connections` and `calendar_events` instead of overloading
`schedule_items` with provider sync state. `schedule_items` can still represent
stable user routines and app-authored planned blocks.

## Data Model Direction

The current canonical schema already has useful tables:

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

`profiles.setup_revision` stores the latest Setup revision projected onto the
profile. It starts at zero, is backfilled from applied `intake-v1` history, and
may advance only monotonically.

Migration `20260710180000_atomic_intake_v1_setup_apply.sql` defines
`apply_intake_v1_setup_revision`. Execute is restricted to `service_role`. The
function locks by user with `pg_advisory_xact_lock`, validates the claimed
canonical intake row and ownership metadata, and applies every Setup projection
inside one transaction. Recommendation generation remains a separate
best-effort post-commit step.

The Intake V1 foundation and Phase 0C revision contract provide the Setup state:

### `intake_responses`

Purpose: preserve typed Setup revisions, make retries/edit concurrency explicit,
and support future schema versions without losing applied intake history.

Implemented columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references profiles(id) on delete cascade`
- `version text not null default 'intake-v1'`
- `request_id uuid not null`
- `base_revision int not null`
- `revision int not null`
- `state text not null check (state in ('pending', 'applied'))`
- `responses jsonb not null`
- `completed_at timestamptz not null default now()`
- `metadata jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Unique indexes:

- `(user_id, version, request_id)` for idempotent request replay.
- `(user_id, version, revision)` for one ordered revision per user/version.

Access:

- User can read own rows.
- User should not update old intake history directly.
- Backend service-role can insert and update after token verification.

### `user_state_snapshots`

Purpose: store compact user state that recommendation, coach, planning, and
memory flows can use without reading full history or building huge prompts.

Implemented columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references profiles(id) on delete cascade`
- `scope text not null check (scope in ('onboarding', 'daily', 'weekly'))`
- `period_key text not null`
- `summary jsonb not null`
- `signals jsonb not null default '{}'::jsonb`
- `source text not null default 'backend'`
- `generated_at timestamptz not null default now()`
- `metadata jsonb not null default '{}'::jsonb`

Indexes:

- `(user_id, scope, generated_at desc)`
- `(user_id, period_key)`
- Unique `(user_id, scope, period_key)` for atomic backend snapshot upserts.

Access:

- User can read own snapshots if the UI needs them.
- Writes should be backend-owned.

### Later Tables

Do not add these in the first slice unless the implementation genuinely needs
them:

- `daily_briefings` in Phase 4, after capture, Daily Mode, and executable action
  contracts are proven and persistence is needed for morning availability,
  stale detection, scheduling, or E2E assertions.
- `decision_feedback` in Phase 6, after the briefing action contract is stable
  and ranking needs append-only outcome history across recommendations and
  action types.
- `backend_jobs` for durable idempotent jobs and retries.
- `llm_usage_events` for per-user budget tracking.
- `calendar_connections` and `calendar_events` for provider sync.
- `memory_candidates` if memory extraction needs review before promotion to
  `memory_entries`.

## Setup Read And Completion Flow

Endpoints:

```text
GET /v1/intake/setup
POST /v1/intake/complete
Authorization: Bearer <supabase_access_token>
```

`GET` returns the newest `intake-v1` typed row and derives the user from the
bearer principal. Normally this is the latest applied revision, including stable
setup item keys and review lifecycle. If the newest revision is `pending`, the
endpoint exposes that exact payload and request id so the client can resume the
same operation rather than edit or create another revision.

`POST` handles both initial completion and later edits:

1. Verify the bearer token through the existing FastAPI auth dependency.
2. Derive `user_id` from the verified principal.
3. Validate `request_id`, `base_revision`, and the typed intake payload with
   strict Pydantic models.
4. Replay an already-applied matching request id, or reject a stale/conflicting
   base revision instead of appending another completion.
5. Persist the next revision as `pending` and derive stable UUIDv5 ids for every
   setup item from user, item kind, and stable item key.
6. Build materialization only from the claimed row's canonical stored responses:
   explicit active goals, cadence-confirmed active/paused habits, active fixed
   commitments, preferences, and bounded durable memories. Candidate routines
   remain only in `responses`.
7. Call the service-role-only atomic Setup RPC. Its transaction-scoped per-user
   advisory lock serializes competing workers. In that transaction it upserts
   preferences; reconciles only server-owned Setup goals, habits, schedule rows,
   and memories; upserts `(user, onboarding, setup:intake-v1)`; marks the intake
   applied; and advances the profile revision, completion time, and explicit
   display name.
8. Preserve all manual/other-source rows. The only narrow legacy cleanup is an
   omitted, unmarked onboarding row exactly matching `Math`, `Room 204`, Monday
   `08:15`-`09:45`; other unmarked onboarding rows are not claimed by Setup. An
   applied replay is side-effect free except that the newest applied revision
   may repair a missing profile projection.
9. Run the existing best-effort deterministic recommendation refresh and return
   the applied revision, snapshot summary, and accepted current recommendations.

Flutter keeps all 4xx failures editable; 409 additionally recommends reloading
the newest server state. Network/transport errors, 5xx responses, and invalid
success envelopes are ambiguous, so the exact submitted request is locked for
unchanged retry or explicit reload.

No LLM is required for v1 intake. If free text exists, store it as source
context and use deterministic categories first.

## Recommendation Flow

Current recommendation v1 exists and is triggered after authenticated Intake V1
completion:

1. User completes intake.
2. Backend creates a user state snapshot.
3. Recommendation service loads the snapshot plus recent user-owned rows.
4. Deterministic rules produce candidates.
5. Verifier rejects weak, duplicate, stale, invalid, or cross-user candidates.
6. Accepted recommendations are persisted.
7. Flutter reads them through `GET /v1/recommendations`.

The refresh is best-effort after intake completion: onboarding stays completed
if recommendation generation fails, and the dashboard can still read any
previously persisted active recommendations. The existing explicit generate UX
calls:

```text
POST /v1/recommendations/generate
```

Keep this as a deliberate action or controlled workflow. Do not call it on
every dashboard load.

## Coach Flow

Target endpoint, not implemented yet:

```text
POST /v1/coach/respond
Authorization: Bearer <supabase_access_token>
```

Target behavior:

1. Store the user message in `coach_messages`.
2. Build a compact context from:
   - recent `coach_messages`
   - latest `user_state_snapshots`
   - selected `memory_entries`
   - relevant active `recommendations`
3. Decide if a deterministic response is enough.
4. Call an LLM only when natural-language reasoning is needed.
5. Store the assistant response in `coach_messages`.
6. Optionally emit memory candidates, not direct high-confidence memory.

This should come after the snapshot aggregator, because the coach needs
structured daily/weekly context to be useful and affordable.

## LLM Cost Control

Use these rules before adding any model provider:

- No LLM calls on dashboard load.
- No LLM calls for simple CRUD, check-ins, or deterministic recommendations.
- No full-history prompts.
- Build and reuse `user_state_snapshots`.
- Limit coach context to the latest compact snapshot, selected memories, and a
  small message window.
- Use idempotency keys for jobs that could retry.
- Track LLM usage per user before enabling broad access.
- Prefer small/cheap models for wording and extraction.
- Use larger models only for complex coach or weekly planning tasks.
- Cache or persist generated outputs.
- Add feature flags for every LLM-backed path.

## Immediate Implementation Plan

The next implementation should build on completed Phase 0 product integrity,
Phase 1 capture, and Phase 2 explainable state, including retry-safe typed
Setup, controlled post-intake recommendation refresh, authenticated snapshot
aggregation, deliberate dashboard refresh, and the FastAPI-backed browser E2E
path. The immediate slice is **Phase 3: Executable Action And Habit
Contracts**: make task, habit, focus-session, and bounded planning targets real,
durable, and recoverable before a briefing ranks them. Phase 2 remains
state-only and contains no action ranking, briefing persistence, Today UI, or
LLM call.

### Completed Slice 0A: Honest Capture

- Implemented: `/daily-check-in` redirects to the canonical lightweight capture
  flow; the fixed page and `saveDefaultCheckIn()` data source are removed.
- Implemented: mood, energy, sleep, and stress begin unset and require explicit
  user selection. An optional context note remains attached to the check-in and
  is not silently promoted to durable memory.
- Implemented: uncollected legacy placeholder fields are cleared rather than
  surviving the canonical upsert as apparently measured data.
- Implemented: one typed draft drives guest and Supabase stores. Guest saves are
  readable on return and replace the same local day; later auth migration reuses
  the canonical Supabase writer.
- Implemented: Supabase upserts the daily log and replaces same-day
  current-state events linked through `daily_log_id`. The original complete V1
  form wrote four; Phase 1 generalizes this to a dynamic maximum of four.
- Implemented: failed writes preserve the draft, retry reuses the stable capture
  id, and in-flight duplicate submits are ignored.
- Implemented: non-functional Lifestyle Entry and Reflection Note tiles were
  removed from Quick Action.
- Implemented: mapper, guest-store, widget, and browser smoke assertions use
  distinctive values instead of checking row existence or defaults only.

### Completed Slice 0B: Source And Surface Truth

- Implemented: recommendation reads and refreshes use a typed feed with explicit
  demo/authenticated provenance, generation state, period, timestamp, and
  current/missing/stale semantics. Real configuration, auth, network, and format
  failures propagate and never consult mock recommendations.
- Implemented: refresh failure keeps the existing feed visible; successful
  deliberate refresh still uses deterministic generation with LLM wording off.
- Implemented: dashboard snapshots carry explicit origin and direct nullable
  stored values. Proxy wellness/recovery scores, fake steps/sleep/screen-time/
  hydration metrics, activity charts, and recommendation-derived task copy are
  removed.
- Implemented: dashboard tasks initialize from persisted status and roll back
  optimistic status changes when a write fails. Schedule UI renders only real
  commitments.
- Implemented: local guest sessions are persistently labeled `Local demo`, stay
  off snapshot/recommendation APIs, read their local canonical check-in, and do
  not expose Supabase-only Habit controls.
- Implemented: Coach and Deep Work previews are removed from productive routes,
  Settings is reduced to durable behavior, and compatibility links redirect to
  working surfaces.
- Implemented: Notifications preserve original fields and source read state,
  distinguish empty from error, and expose Open only for a strict allowlist of
  implemented internal `action_url` targets.
- Verified with mapper, repository, provider, widget, route-capability,
  notification-target, and browser smoke coverage.

### Completed Slice 0C: First-Run And Setup Integrity

- Implemented: explicit required selections stay short while goals, routines,
  context, calendar intent, and timetable detail are progressive and optional.
- Implemented: blank optional answers remain blank and create no fallback goal,
  habit, schedule item, friction, or memory row.
- Implemented: named routines are typed candidates in the intake response until
  cadence is explicitly confirmed; candidates do not become active daily habits.
- Implemented: guest and authenticated Setup re-entry use a typed prefilled read
  model with loading, error, retained draft, and retry states.
- Implemented: `request_id`, `base_revision`, pending/applied revisions,
  deterministic UUIDv5 ids, and ownership-scoped reconciliation make completion,
  replay, and edit converge without duplicates or changes to manual rows.
- Implemented: a per-user advisory-locked, service-role-only database RPC commits
  the full Setup projection atomically; an exact legacy placeholder cleanup does
  not broaden ownership of other unmarked onboarding rows.
- Implemented: Settings links to durable review/edit actions for Setup goals,
  activated habits, and fixed commitments, including archive, pause, restore,
  and removal behavior. Setup-owned habits remain completable through Habit
  Completion but are excluded from generic Habit Management edits.
- Implemented: mock/demo auth boot remains local across reload, while 4xx,
  conflict/reload, and ambiguous exact-retry states preserve honest save status.

### Completed Slice 1: Lightweight Daily Capture And Stress Taxonomy

- Implemented separate typed Evening Shutdown and Morning Calibration flows.
- Implemented one same-day ownership merge under
  `daily_logs.metadata.captures`: replacing Evening preserves Morning and vice
  versa, while unrelated metadata survives the mapper.
- Implemented exact numeric projection with Morning energy precedence, Evening
  mood/stress ownership, Morning sleep ownership, and no fabricated focus
  minutes or optional text.
- Implemented a dynamic maximum of four deterministic mood/energy/stress/sleep
  events with capture-kind metadata and linkage to the single daily row.
- Implemented guest V2 JSON with legacy V1 read and best-effort authenticated
  migration compatibility; guest/mock paths remain off Supabase and FastAPI.
- Implemented capture-date snapshot refresh plus backend metadata-date filtering
  over a timezone-tolerant UTC read window.
- Implemented direct nullable Dashboard mapping for capture presence, focus
  band, stress source/controllability, and day shape. It does not infer Daily
  Mode, ranking, causation, or a learned baseline.

### Completed Slice 2: Explainable Daily State

- Implemented `summary.daily_state` and `signals.daily_state` under
  `explainable-daily-state-v1` without schema changes.
- Implemented a strict V2 parser that validates capture identity, enums,
  numbers, timestamps, and numeric projections. Legacy numeric rows are read
  only when no V2 marker exists; malformed V2 never regains trust through
  projected columns.
- Implemented a fixed seven-day state lookback independent of the requested
  statistical window. Evening target-day or previous-day capture and Morning
  target-day capture form the current-state cadence.
- Implemented explicit `missing`, `partial`, `current`, and `stale` quality;
  bounded taxonomy, recovery, capacity, workload, and calibration risks;
  machine-stable reasons with field-level evidence; and deterministic
  provenance without capture free text or learned-baseline claims.
- Implemented recovery-first `push`, `steady`, `recover`, and `plan`
  classification. Missing, partial, and stale inputs remain conservative, and
  low-control/private-emotional/physical-recovery safeguards prevent push.
- Preserved `snapshot-aggregator-v1`, same-period atomic upsert, recommendation
  ranking, guest/mock locality, best-effort Flutter refresh, and the Phase 0C
  Setup contract. Metadata records the Daily State contract and lookback;
  top-level `summary.risk_flags` aliases current Daily State risks,
  `summary.window_risk_flags` retains window-aggregate flags, and
  `recommended_next_focus` is derived recovery-first from mode.

### Next Slice 3: Executable Action And Habit Contracts

- Add reliable action targets for task, habit, focus, and bounded planning
  commands before a briefing ranks them.
- Implement coherent task create/edit/outcome behavior where needed by Today.
- Correct Habit V1 cadence and progress semantics, add intentional skip and undo,
  and distinguish scheduled opportunities from misses.
- Add a structured habit-log outcome with migration/RLS/docs/E2E if metadata and
  the existing value field cannot represent the contract honestly.
- Implement a real linked focus-session lifecycle or keep the preview out of
  production navigation.

### Slice 4: Daily Briefing Service And Today Dashboard

- After capture, state, and executable targets are proven, add a FastAPI-owned
  briefing service that ranks one primary action plus at most two support actions.
- `GET /v1/briefings/today` reads only and reports stale/missing state.
- `POST /v1/briefings/generate` is deliberate and authenticated.
- Include mode, reason, time/capacity note, provenance, freshness, evidence refs,
  and executable action targets.
- Add `daily_briefings` persistence only when needed for morning availability,
  scheduling, stale detection, or E2E assertions.
- Reposition the dashboard to Daily Mode, primary action, reason, and capacity
  above secondary metrics, with start/done/later/replace/too-much feedback.

### Completed Slice: Controlled Recommendation Refresh

- Implemented: authenticated Intake V1 completion creates an onboarding
  snapshot, then triggers deterministic recommendation generation through the
  existing verifier, fingerprint, and persistence path.
- Implemented: the recommendation context loader reads latest
  `user_state_snapshots` with explicit `user_id` scoping.
- Implemented: normal dashboard reads still do not auto-generate
  recommendations.
- Implemented: the dashboard exposes a deliberate refresh action that refreshes
  the daily snapshot best-effort, then calls `POST /v1/recommendations/generate`
  with `allow_llm_wording=false`, and reloads persisted recommendations.

### Completed Slice: Snapshot Aggregator

- Implemented: authenticated `POST /v1/snapshots/generate` creates or refreshes
  `daily` and `weekly` `user_state_snapshots` from recent check-ins,
  behavioral events, tasks, goals, habits, schedule items, and memory entries.
- Implemented: snapshots stay compact and avoid reading full user history.
- Implemented: backend tests cover the strict capture parser, every taxonomy
  code, malformed/future metadata, current/stale/local-day boundaries, all four
  modes and precedence conflicts, sensitive-text exclusion, exact evidence,
  fixed state lookback, idempotent daily/weekly refresh, request `user_id`
  rejection, and user scoping.
- Implemented: the canonical Supabase-backed daily check-in triggers daily
  snapshot refresh best-effort after a successful write.
- Implemented: dashboard task status changes trigger daily snapshot refresh
  best-effort after successful Supabase writes.
- Implemented: Quick Action habit completion writes to `habit_logs`, updates the
  habit timestamp, and triggers daily snapshot refresh best-effort after a
  successful Supabase write.
- Implemented: Quick Action habit management can create, edit, pause, restore,
  and inspect 7-day progress for habits against the existing habit tables.
- Implemented: scheduler-triggered daily snapshot refresh endpoint for onboarded
  non-guest profiles.
- Still open: deployed cron/job wiring, but it should now be evaluated against
  the Daily Briefing cadence and not treated as the next product slice by
  itself.

### Completed Slice: E2E Expansion

- Implemented: browser E2E starts FastAPI with local Supabase backend settings.
- Implemented: the smoke covers revisioned Setup completion/replay/edit,
  concurrent same-request convergence, candidate cadence, exact ownership
  metadata and stable ids, preservation of manual rows, onboarding snapshots,
  deterministic post-intake recommendations, backend-refreshed daily snapshots
  after check-ins, exact Phase 2 partial/current/recovery state and stale-risk
  removal after edit, deliberate dashboard recommendation refresh, and core
  direct app writes.
- Implemented: the guest/mock widget smoke stays fast and separate.

### Completed Slice: Controlled Snapshot Triggers

- Implemented: dashboard task status changes call the daily snapshot refresh
  best-effort after a successful Supabase update.
- Implemented: Quick Action habit completions call the same daily snapshot
  refresh best-effort after a successful Supabase upsert.
- Implemented: Quick Action habit management calls the same daily snapshot
  refresh best-effort after successful create, edit, pause, or restore writes.
- Implemented: `POST /v1/scheduled/daily-refresh` refreshes deterministic daily
  snapshots for onboarded non-guest profiles and can optionally run
  deterministic recommendation generation without LLM wording.
- Next: use the Daily Briefing contract to decide whether scheduled refresh
  should generate only daily snapshots, recommendations, persisted briefings, or
  a combination.
- Preserve guest/mock mode and keep failures best-effort for the user write.
- Do not introduce a production worker, LLM provider, or dashboard-load
  generation for this slice.

## Out Of Scope For The Next Slice

- The full Daily Briefing service or `daily_briefings` migration.
- Briefing action ranking, recommendation-ranking redesign, or the
  decision-first Today dashboard. Phase 3 establishes executable targets; it
  does not choose or editorialize them.
- Briefing persistence before Phase 3 action contracts are proven.
- Changing the Phase 2 mode, freshness, evidence, or recommendation behavior as
  a side effect of action-contract work.
- Implementing the preview Coach or Deep Work UI merely to keep it visible.
- OpenAI/OpenRouter/local LLM integration.
- Real coach assistant replies.
- Calendar provider connection.
- Weekly planning or review.
- Vector search.
- Background workers unless implementation cannot stay simple without them.
- Remote production database claims without direct inspection.
