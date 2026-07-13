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
    check-ins, behavioral events, tasks, goals, habits, explicit habit outcomes,
    focus sessions, schedule items, and memory entries.
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
  - Additive action summaries count explicit completed/skipped habit logs and
    active/completed/abandoned focus sessions with minutes and evidence. They do
    not change `explainable-daily-state-v1` mode, quality, risks, or reasons.
    Backend reads paginate complete action-fact windows in stably ordered
    1,000-row pages rather than accepting a PostgREST-capped first page as the
    full count.
  - Best-effort Flutter daily snapshot refresh after canonical capture and every
    durable task, habit, or focus write.
- Phase 3 executable actions:
  - Dashboard tasks support create/edit/complete/postpone/cancel/restore/undo,
    validated estimates, stable create ids, user scoping, recoverable drafts,
    exact committed-response-loss reconciliation for every update including
    undo, and best-effort snapshot refresh.
  - Habit V1 supports daily, selected ISO weekdays, and weekly targets; manual
    active/paused/archived lifecycle; explicit completed/skipped outcomes;
    cadence-aware progress/streaks; and same-day undo. Setup remains owner of its
    habit definitions/lifecycle while active rows share execution. Outcome
    writes lock and revalidate current lifecycle/cadence; paginated reads,
    `started_on`, and date-component math preserve large-account and DST truth.
    Definition/lifecycle changes reconcile exact owner-scoped mutations after
    response loss. Outcome/undo fixes its target date before the write,
    reconciles the exact row or absence, and refreshes that same date.
  - `/deep-work` provides a real one-active-session focus lifecycle with optional
    owned task/habit linkage, measured finish/abandon duration, and no implicit
    target completion. Target validation locks the chosen task/habit row;
    terminal writes reconcile exact persisted results after response loss;
    every update to terminal history is rejected; and target deletion is
    restricted. New rows persist a local start date, with deterministic UTC
    legacy backfill and shared Flutter/FastAPI fallback.
  - Flutter and FastAPI enforce parser parity for unknown, explicit-null,
    coerced, or mismatched `executable-action-v1` envelopes. Flutter dispatches
    every supported command through a typed injected handler. Phase 8 gives
    `review_plan` a real synced weekly-review navigation handler without making
    dispatch itself mutate or generate.
  - Migration `20260711120000_phase_3_executable_action_schema.sql` adds the
    necessary task, habit-log, and focus columns/checks/triggers while preserving
    existing RLS and table grants.
- Phase 7 scheduled daily preparation backend:
  - `POST /v1/scheduled/daily-refresh`.
  - Protected by backend-only `X-Scheduled-Refresh-Token`.
  - Pins one timezone-aware `run_at`, resolves each onboarded non-guest
    profile's IANA timezone to its local briefing date, and keeps an explicit
    `target_date` as a deterministic operator override.
  - Selects only missing snapshots, missing briefings, or briefings stale
    against snapshot id/time provenance. Current snapshot/briefing pairs are
    write-free; when optional recommendation retry is requested, the current
    briefing is still reused unchanged.
  - Creates a missing daily snapshot exactly once, reuses an existing snapshot,
    and generates or refreshes the same `(user_id, briefing_date)` briefing.
    One bounded post-write check repairs a concurrent snapshot change or
    reports a briefing-stage failure.
  - Supports a bounded `profile_ids` UUID filter that still intersects
    onboarded non-guest eligibility, bounded batch size and concurrency, and
    per-user `profile_date|snapshot|briefing|recommendations` failure results.
  - Optional recommendation refresh remains deterministic with LLM wording
    disabled. Normal Dashboard GET, capture, task, habit, and focus paths do not
    invoke scheduled preparation or gain hidden generation.
  - No notification is sent, no production worker is added, and repository
    implementation does not claim that a deployed cron/job invokes the endpoint.
- Phase 4 deterministic briefing service:
  - Persists one `daily_briefings` row per user and profile-local date under the
    strict `daily-briefing-v1` contract.
  - `GET /v1/briefings/today` remains read-only and distinguishes missing,
    current, and stale output by comparing source snapshot identity and time.
  - Deliberate `POST /v1/briefings/generate` derives the user from the bearer
    principal, refreshes Daily State when needed, and is idempotent unless
    `force=true` is requested.
  - Recovery-first deterministic ranking chooses one executable primary action
    and at most two support actions from open tasks, due habits, and conservative
    capture fallback. Every target passes `executable-action-v1`; no LLM is used.
- Phase 6 feedback and useful Insights:
  - `GET|POST|DELETE /v1/feedback` derives the owner from the bearer token,
    validates an exact action inside an owned briefing, and makes create retries
    idempotent through `(user_id, request_id)`.
  - `decision_feedback` remains separate append-only evidence; users can delete
    a mistaken entry and original briefing/recommendation reasons never change.
  - `feedback-ranking-v1` applies only a 28-day mode/kind/rule match, decays by
    age, caps contribution, and keeps missing/stale capture plus urgent facts
    ahead of preference fit. Briefing provenance exposes every applied effect.
  - Insights defaults to one cautious observation with an evidence window,
    confidence/data quality, non-causal copy, and optional bounded experiment;
    the existing correlation tools remain available as advanced exploration.
- Phase 8 bounded weekly review and Habit V1 adaptation:
  - Read-only latest and explicit-period GETs resolve one completed
    profile-local ISO week; deliberate POST persists one stable
    `weekly-review-v1` identity with no LLM.
  - Canonical source fingerprints distinguish missing, current, and stale
    derived output while completed, carried, skipped, missed, unknown, recovery,
    focus, and feedback facts remain explicit.
  - At most two proposals are persisted. Only confirmed manual Habit V1
    shrink/pause/archive reuses an existing exact owner-scoped command.
    Setup-owned changes return to Setup; replacements and goal/task/schedule
    proposals remain staged.
- Phase 9 bounded calendar import:
  - One authenticated `ical_file` source requires exact explicit read/store
    consent. Creating the source does not import anything.
  - A deliberate bounded UTF-8 `.ics` upload reconciles stable connection,
    import, single-event, and recurrence-occurrence identities in dedicated
    tables with imported/read-only provenance.
  - Disconnect retains the imported local copy; a separate confirmed delete
    removes imported events/history only. Manual and Setup-owned
    `schedule_items` remain unchanged.
  - There is no provider OAuth/token, arbitrary URL fetch, calendar write,
    hidden sync, RRULE engine, LLM processing, or calendar-driven ranking.
- Browser E2E starts FastAPI with local Supabase backend settings and verifies
  authenticated required-only Setup, retry/edit/review identity and ownership,
  deterministic post-intake recommendations, backend daily snapshot refresh
  after check-ins, exact Phase 2 state recomputation, core Supabase-backed app
  writes, Phase 4 read-only/generate/idempotent briefing persistence, and Phase
  5 GET-only Today load, deliberate adjustment, primary action dispatch, and
  Phase 6 feedback persistence/ranking/deletion plus useful default Insights,
  and the Phase 8 weekly-review contract and confirmed Habit V1 boundary.

Not yet implemented:

- Broad weekly planning or compound goal/task/schedule/replacement execution;
  Phase 8 implements only bounded review navigation and confirmed manual Habit
  V1 shrink/pause/archive.
- A production background job queue or worker.
- Deployed cron wiring for the scheduler-triggered refresh endpoint.
- Real coach-response backend.
- LLM provider integration.
- Memory extraction beyond current direct writes.
- Autonomous weekly planning.
- Live calendar-provider OAuth, refresh tokens, URL subscriptions, background
  sync, and provider writes.

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
| Signal aggregator | Intake, daily check-in, task/habit/focus changes, scheduled jobs | `daily_logs`, `behavioral_events`, `tasks`, `goals`, `habits`, `habit_logs`, `focus_sessions`, `schedule_items`, `memory_entries` | `user_state_snapshots`, optional `ai_insights` | None by default |
| Recommendation service | Intake complete, explicit refresh, scheduled refresh | `user_state_snapshots`, `daily_logs`, `behavioral_events`, `tasks`, existing `recommendations` | `recommendations` | Optional wording only later |
| Recommendation verifier | Every generated recommendation | Candidate metadata, active recommendations | Accept/reject result | None |
| Daily briefing service | Explicit refresh today; protected scheduled daily preparation | `user_state_snapshots`, `recommendations`, goals, tasks, habits, habit outcomes, `decision_feedback` | `daily_briefings` | None for v1 |
| Weekly review service | Explicit completed-week review read/generation | Profile timezone, weekly snapshot, tasks, goals, habits/outcomes, focus, daily snapshots, `decision_feedback` | `weekly_reviews` derived output only | None for v1 |
| Calendar import service | Explicit consent and selected `.ics` upload | Bounded iCalendar text, profile timezone, owned connection | `calendar_connections`, `calendar_imports`, `calendar_events`, opaque `calendar_request_identities` | None |
| Coach service | Deliberate authenticated user send | Current snapshot/briefing, bounded active facts, selected memory, recent completed turns | Validated `coach_messages`, compact provenance/usage only | One configured provider call, budgeted |
| Memory selection service | Explicit user inspect/select/deselect/edit/delete | Owner-scoped `memory_entries` plus Setup ownership | Separate Coach selection projection; content only through its owning contract | None for Phase 10 v1 |
| Planning service | Weekly review, user request | Goals, tasks, habits, schedule, snapshots | `tasks`, `schedule_items`, `recommendations`, `coach_messages` | Optional for complex plans |
| Notification service | Schedule and event changes | Preferences, recommendations, deadlines | `notifications` | None |

The intake foundation, controlled post-intake recommendation refresh, first
authenticated snapshot aggregator endpoint, deliberate dashboard refresh UX,
the Phase 3 task/habit/focus execution contracts, scheduler-triggered daily
refresh endpoint, and deterministic Insights correlation exploration now
exist. Phase 4's deterministic Daily Briefing service supplies the backend
decision contract, Phase 5 consumes it in the decision-first Today surface,
Phase 6 closes the bounded feedback/Insight loop, and the minimal Phase 7
backend prepares timezone-pinned daily snapshots and briefings through the
existing protected endpoint. Phase 8 adds bounded weekly review and
user-confirmed manual Habit V1 adaptation. Phase 9 adds the first optional
consented integration boundary as a user-selected `.ics` import with no
provider access or writes. The next product work is Phase 10's controlled Coach
boundary. Deployed cron/job wiring, notification delivery, real calendar
provider integration, and LLM provider work remain
unimplemented and must not be inferred from the callable endpoint. See
`docs/daily-briefing-implementation-plan.md` for the current product contract
and phase sequence, and
`docs/phase-3-executable-actions-contract.md` for the completed action contract.

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

The first bounded implementation is:

- Optional explicit `ical_file` consent after the first useful dashboard.
- Deliberate bounded file import into dedicated connection/import/event tables.
- User-visible, separate disconnect and imported-data deletion controls.
- Imported/read-only provenance and no LLM processing of calendar content.
- No provider OAuth, URL fetch, provider write, hidden sync, or automatic
  schedule/briefing mutation.

`schedule_items` continues to represent stable user routines and app-authored
planned blocks. A live-provider follow-up must keep credentials, cursors, and
webhooks backend-only and preserve the same explicit provenance/control rules.

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

Migration `20260711120000_phase_3_executable_action_schema.sql` completes the
Phase 3 storage contract. It adds bounded task estimates and terminal
timestamps; makes `habit_logs.status` (`completed` or `skipped`) authoritative
and consistent with `value`; and adds focus status, optional task/habit linkage,
measured terminal duration, and update timestamps. Database constraints,
ownership triggers, a partial unique index, restricted FKs, and an all-update
terminal-history guard enforce exact task/focus shapes, available same-user
targets, and at most one active focus session. Focus target validation locks the
selected task/habit row. Missing legacy focus `metadata.entry_date` values are
backfilled deterministically from the UTC date of `started_at`. Habit outcomes
lock their owned habit and validate active lifecycle plus selected ISO weekday
at write time.
Existing RLS policies and table grants remain in force. Positive legacy values
normalize to completion. The migration deliberately refuses ambiguous legacy
habit logs whose missing status is paired with `value <= 0`; inspect and resolve
those rows rather than inventing an intentional skip.

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

### `weekly_reviews`

Purpose: persist one bounded deterministic review for a completed
profile-local ISO week without mixing derived output into generic snapshots or
mutating user-owned records during generation.

Implemented identity and bounds:

- unique `(user_id, period_key)`;
- exact Monday `week_start` and Sunday `week_end` consistent with `IYYY-Www`;
- bounded timezone, narrative, facts, no more than two proposals, no more than
  40 evidence references, provenance, and SHA-256 source fingerprint;
- `insufficient|partial|sufficient` data quality separate from freshness;
- authenticated owner/admin SELECT only, service-role writes, forced RLS.

The review GET computes missing/current/stale truth without writing. Deliberate
generation upserts the derived row. Proposal application is not a table write:
confirmed eligible manual Habit V1 changes reuse Phase 3 owner-scoped commands.

### Later Tables

`daily_briefings`, `decision_feedback`, `weekly_reviews`, and the bounded Phase
9 calendar import tables are implemented
after their owning contracts proved the persistence boundary. Do not add these remaining tables
until their owning phase needs them:
- `backend_jobs` for durable idempotent jobs and retries.
- `llm_usage_events` for per-user budget tracking.
- provider-account, credential, cursor, or webhook tables for live calendar
  sync.
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

1. Derive the owner from the verified Supabase bearer token and claim a
   retry-safe bounded request identity.
2. Build `coach-context-v1` from the current snapshot/Daily State, current
   persisted briefing, bounded active goals/actions/focus facts, an explicitly
   fresh weekly review when useful, explicitly selected memory, and a small
   completed-turn window.
3. Attach stable caps/order and a user-visible source/count/freshness manifest.
   Never give a model database credentials, arbitrary SQL, full history,
   imported calendar content, hidden free text, or cross-user rows.
4. Call one explicitly configured provider only after a deliberate Coach send.
5. Validate strict model output, then attach backend-owned request, provider,
   model, prompt, context, time, safety, and uncertainty provenance.
6. Persist only the bounded validated turn and compact manifest under a defined
   retention/delete contract. Do not store the assembled prompt or raw provider
   event stream.
7. Return at most one review-only staged suggestion with no mutation command.

This should come after the snapshot aggregator, because the coach needs
structured daily/weekly context to be useful and affordable.

The first test provider is deliberately `local_codex_oauth`. When explicitly
enabled in development, FastAPI invokes the current Linux/WSL user's already
authenticated Codex CLI without an application API key. Each developer runs
their own `codex login`; OAuth files never enter Flutter, Supabase, Git, `.env`,
or application logs. This same-user agentic subprocess is a local testing
adapter, not a production isolation/deployment design. The complete locked
boundary is `docs/phase-10-controlled-coach-plan.md`.
The preferred normal Coach model is `gpt-5.5`: this workflow values general
conversation, synthesis, cautious planning, and strict structured output over
coding-agent speed. Do not default to Spark merely because Codex CLI supplies
the local OAuth bridge, and do not silently replace an unavailable configured
model.

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
- Keep per-user, concurrency, timeout, input, context, and output caps even when
  local subscription access rather than an API bill supplies the model.
- Prefer small/cheap models for wording and extraction.
- Use larger models only for complex coach or weekly planning tasks.
- Cache or persist generated outputs.
- Add feature flags for every LLM-backed path.

## Immediate Implementation Plan

The next implementation should build on completed Phase 0 product integrity,
Phase 1 capture, Phase 2 explainable state, Phase 3 executable action targets,
Phase 4's persisted deterministic briefing contract, Phase 5's decision-first
Today consumer, Phase 6's bounded feedback/Insight loop, the minimal Phase 7
scheduled preparation backend, and Phase 8's bounded weekly review plus
confirmed manual Habit V1 adaptation, and Phase 9's bounded `.ics` import. The
immediate next slice is **Phase 10: Controlled Coach**: begin with a bounded
authenticated context, budget, safety, provenance, and staged-suggestion
contract. The deterministic standalone loop must remain the source of truth.
Implement it against the development-only local Codex OAuth adapter and fake-
provider test seam fixed in `docs/phase-10-controlled-coach-plan.md`; do not
generalize this into a production or autonomous agent platform.

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
- Implemented: Coach and the former placeholder Deep Work preview were removed
  from productive routes, Settings was reduced to durable behavior, and
  compatibility links redirected to working surfaces. Phase 3 later replaced
  the Deep Work placeholder with a real authenticated focus-session flow.
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

### Completed Slice 3: Executable Action And Habit Contracts

- Implemented reliable `executable-action-v1` targets for task, habit, focus,
  and capture commands. Flutter and FastAPI reject unknown fields, invalid
  kind/command/target combinations, and unsupported routes. Planning's
  `review_plan` was explicitly unavailable in Phase 3 until Phase 8 supplied
  its real navigation surface; the reserved `recovery` kind has no executable
  command yet.
- Implemented owner-scoped task create/edit/complete/postpone/cancel/restore and
  direct undo with validation, stable create ids, retained drafts, confirmation
  for terminal actions, exact requested-field/timestamp reconciliation after an
  ambiguous response from every update including undo, and snapshot refresh
  after durable writes.
- Implemented Habit V1 daily, selected-weekday, and weekly-target cadence;
  explicit completed/skipped/open/missed outcomes; cadence-aware progress and
  streaks; same-day undo; and separate manual versus Setup-owned lifecycle
  authority. Database locking closes pause/archive/cadence races; paginated
  outcome reads beginning 370 calendar days before today and local `started_on`
  keep calendar math DST-safe. Manual definition/lifecycle updates use exact
  response-loss readback; outcome/undo captures one target date and proves the
  exact row or absence before refreshing that same day.
- Implemented a real one-active-session focus lifecycle with optional owned
  task or active-habit linkage, bounded planned duration, measured finish or
  abandon duration, locked target validation, exact terminal response-loss
  reconciliation, all-update terminal-history rejection, restricted target
  deletion, deterministic local/legacy start-day snapshot attribution, and no
  implicit target completion.
- Added deterministic habit-outcome and focus-session snapshot summaries while
  preserving the exact Phase 2 Daily State result and normal recommendation
  read/generate boundaries. See
  `docs/phase-3-executable-actions-contract.md` for the complete matrix.

### Completed Slice 4: Deterministic Briefing Service

- Implemented a FastAPI-owned deterministic service that ranks one executable primary
  action plus at most two support actions from Phase 2 state, Phase 3 action
  contracts, existing recommendations, and current owned records.
- `GET /v1/briefings/today` reads only and distinguishes current, stale,
  missing, and error states. Normal Dashboard load must not generate a briefing.
- `POST /v1/briefings/generate` is deliberate, authenticated, idempotent for
  its user/local date, and use no LLM.
- Includes mode, bounded reason, time/capacity note, provenance, freshness,
  evidence references, and strictly validated `executable-action-v1` targets.
- Added `daily_briefings` persistence for stable local-date identity, stale
  detection, morning availability, and exact database assertions.
- Kept the decision-first Today/Dashboard redesign and feedback controls in
  Phase 5; Phase 4 proves the backend briefing contract first.

### Completed Slice 5: Decision-First Today Dashboard

- Added strict Flutter `daily-briefing-v1` parsing, authenticated repository and
  provider boundaries, with no privileged API calls in guest/mock mode.
- Normal Dashboard load calls read-only GET only and preserves loading,
  missing, current, stale, error, and local-demo truth.
- Places Daily Mode, data quality, capacity note, reason, primary action, and at
  most two support actions above direct nullable check-in metrics.
- Disables stale actions until deliberate `Adjust today`, whose POST sends only
  `force=true`; missing state offers deliberate first generation.
- Dispatches current targets through the existing exhaustive Phase 3 handler
  boundary; Phase 8 later adds the real synced `review_plan` navigation handler.
- Adds model/repository/widget tests and browser assertions for read-only load,
  persisted identity, deliberate adjustment, and real action dispatch.

### Completed Slice 7: Scheduled Daily Preparation Backend

- Extended `POST /v1/scheduled/daily-refresh` rather than adding a worker or a
  second privileged boundary. The endpoint remains protected by the backend-only
  scheduled refresh token.
- Captures one aware run instant and resolves each eligible profile's local date
  from its stored IANA timezone. Invalid timezones fail only that profile; an
  explicit target date remains a deterministic operator/test override.
- Selects missing daily snapshots, missing briefings, and snapshot-provenance-
  stale briefings. Current pairs are normally skipped; optional deterministic
  recommendation retry can select them while leaving the briefing unchanged.
- Reuses existing snapshots, generates a missing snapshot once, upserts one
  stable daily briefing identity, and performs one bounded convergence retry if
  the source snapshot changes during persistence.
- Supports bounded UUID `profile_ids` targeting without bypassing onboarded
  non-guest eligibility. Per-user result envelopes expose selection reason,
  local date, snapshot/briefing status and ids, and a bounded failure stage while
  allowing the rest of the batch to continue.
- Preserves deterministic no-LLM output, GET-only Dashboard load, deliberate
  user adjustment, and ordinary-write boundaries. It sends no notifications,
  installs no production worker, and does not establish deployed cron wiring.

### Completed Slice 8: Bounded Weekly Review And Habit Adaptation

- Added one strict `weekly-review-v1` contract over an explicit completed
  profile-local ISO week. Latest/period GET is read-only; deliberate generation
  upserts one stable `(user_id, period_key)` derived review.
- Added exact bounded task, habit, focus, recovery-day, and feedback facts with
  explicit unknown/limitation states. A canonical SHA-256 source fingerprint
  makes changed evidence or targets stale without a hidden write.
- Added at most two deterministic evidence-backed proposals. Misses alone never
  authorize an adaptation, recovery overlap remains separate, and no learned
  baseline or LLM is claimed.
- Added the real synced `/weekly-review` surface and `review_plan` navigation.
  Only an explicitly confirmed manual Habit V1 shrink/pause/archive reuses the
  existing Phase 3 exact timestamp/readback commands. Setup remains owner of its
  definitions; replacement and goal/task/schedule proposals remain staged.
- Added backend-owned `weekly_reviews` persistence with bounded JSON, exact ISO
  period checks, forced RLS, authenticated owner/admin reads, and service-role
  writes.

The complete limitation, proposal, freshness, and verification contract lives
in `docs/phase-8-weekly-review-contract.md`.

### Completed Slice 9: Bounded Calendar File Import

- Added the strict `calendar-import-v1` boundary for one optional authenticated
  `ical_file` source. `calendar-import-consent-v1` is explicit and independent
  of Setup's calendar-interest answer.
- Added retry-safe connection and import identities plus deterministic event
  reconciliation over a bounded profile-local window. Persisted fields are
  whitelisted; event reads are paginated, stable, and side-effect free.
- Timed, all-day, explicitly materialized recurrence occurrences, duplicate
  identity, cancellation, invalid component, and unsupported recurrence states
  remain explicit. Phase 9 does not invent a recurrence expansion engine.
- Added separate confirmed disconnect and imported-data deletion semantics.
  Disconnect retains a visibly stale/read-only local copy; delete removes only
  integration rows and preserves every manual or Setup-owned schedule row.
- Added no provider OAuth, credentials, URL fetch, provider mutation,
  background sync, snapshot/briefing input, LLM processing, or staged-block
  application.

The exact consent, import, identity, parser, privacy, and verification boundary
lives in `docs/phase-9-calendar-import-contract.md`.

### Planned Slice 10: Controlled Coach

- Add one strict authenticated `coach-request-v1` / `coach-response-v1`
  boundary and a side-effect-free provider capability read.
- Add an injectable provider abstraction. Standard tests use a fake; one
  explicit local-development adapter invokes the same Linux user's Codex CLI
  and existing OAuth login without `OPENAI_API_KEY` or Hermes.
- Prefer `gpt-5.5` for normal Coach turns. Treat its absence as honest
  configuration and allow an explicit per-developer override; do not silently
  choose a coding-focused Codex/Spark variant.
- Use full owner-scoped backend reach with minimal model disclosure: current
  compact state, briefing, bounded active life-graph facts, selected memory, and
  a small message window only. Imported calendar content remains excluded.
- Surface exact data-use, freshness, uncertainty, provider/model, prompt, and
  context provenance. Keep all suggestions review-only and non-mutating.
- Replace the gated canned Coach and direct Flutter message insert path; keep
  guest/mock at zero backend/model calls.
- Bound usage, concurrency, process environment, output, timeout, retention,
  memory selection, safety, and retry identity before calling a real model.

The detailed implementation order and acceptance criteria live in
`docs/phase-10-controlled-coach-plan.md`.

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
  behavioral events, tasks, goals, habits, explicit habit outcomes, focus
  sessions, schedule items, and memory entries.
- Implemented: snapshots stay compact and avoid reading full user history.
- Implemented: backend tests cover the strict capture parser, every taxonomy
  code, malformed/future metadata, current/stale/local-day boundaries, all four
  modes and precedence conflicts, sensitive-text exclusion, exact evidence,
  fixed state lookback, idempotent daily/weekly refresh, request `user_id`
  rejection, and user scoping.
- Implemented: the canonical Supabase-backed daily check-in triggers daily
  snapshot refresh best-effort after a successful write.
- Implemented: every successful or exactly reconciled real task, habit, or
  focus mutation triggers daily snapshot refresh best-effort without rolling
  back the durable write if refresh fails. Focus uses its persisted local start
  date rather than the terminal wall-clock date.
- Implemented: habit execution upserts an explicit completed or skipped
  `habit_logs` outcome and supports same-day undo.
- Implemented: Quick Action habit management can create, edit, pause, restore,
  archive, and inspect cadence-aware progress and streaks for manual habits;
  active Setup-owned habits remain executable without transferring definition
  ownership out of Settings Setup.
- Implemented: scheduler-triggered timezone-pinned daily snapshot and briefing
  preparation for onboarded non-guest profiles, with bounded targeting,
  idempotent current/missing/stale behavior, and per-user failure isolation.
- Still open: deployed cron/job wiring and all notification delivery. Their
  absence does not imply Dashboard-load generation or a hidden background
  process.

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
- Implemented: exact database assertions cover task
  create/edit/postpone/undo/complete/restore/cancel/restore; manual and Setup-owned
  habit complete/skip/undo without duplicate logs; and focus start/finish/abandon
  with owned linkage and no target mutation. Those assertions plus
  committed-response-loss for habit/task create, habit
  outcome/undo, task completion/undo, and focus start/finish are encoded in the
  smoke. Negative lifecycle/range/cadence writes include terminal-focus
  `updated_at`. The Phase 7 portion also proves targeted scheduled preparation
  and a write-free retry. Phase 8 adds bounded weekly review, and Phase 9 adds
  bounded calendar-import ownership, retry, pagination, and deletion boundaries.
  The combined Phase 3 through Phase 9 journey passed non-destructively in the
  2026-07-13 Phase 9 implementation checkout. Later changes must establish their
  own current-checkout pass before claiming E2E.

### Completed Slice: Controlled Snapshot Triggers

- Implemented: successful real task create/edit/status/deadline writes call the
  daily snapshot refresh best-effort.
- Implemented: habit definition/lifecycle and completed/skipped/undo writes call
  the same daily snapshot refresh best-effort. Outcome/undo captures its target
  date before awaiting persistence and refreshes that same date.
- Implemented: focus start/finish/abandon writes call the same daily snapshot
  refresh best-effort for persisted `metadata.entry_date`, with `started_at`
  UTC-date fallback for legacy/invalid rows.
- Implemented: `POST /v1/scheduled/daily-refresh` prepares deterministic daily
  snapshots and persisted briefings for each selected profile-local date and can
  optionally retry deterministic recommendations without LLM wording.
- Current snapshot/briefing pairs stay write-free unless optional recommendation
  retry explicitly selects them; missing/stale pairs converge on the existing
  daily identities with no Dashboard-load generation.
- Preserve guest/mock mode and keep failures best-effort for the user write.
- Do not introduce a production worker, LLM provider, or dashboard-load
  generation for this slice.

## Out Of Scope For The Next Slice

- Hidden or opaque feedback adaptation, mutation of original briefing reasons,
  or an unbounded personalization score.
- Changing the Phase 2 mode, freshness, evidence, or recovery-first rules as a
  side effect of briefing work.
- Changing Phase 3 task, habit, focus, action-target, or snapshot-refresh
  semantics as a side effect of ranking them.
- Generating a briefing or recommendations during normal Dashboard reads or
  ordinary task, habit, focus, or capture writes.
- Expanding `review_plan` beyond bounded review navigation into autonomous or
  compound plan mutation.
- Ungating the canned Coach or persisting its placeholder response.
- Any model integration other than the explicit development-only
  `local_codex_oauth` adapter behind the provider seam.
- A deployable OpenAI/OpenRouter/other API provider, API-key fallback, provider
  failover, or claims that a local subscription adapter is production-ready.
- Model-controlled tools, database access, unbounded history, automatic memory
  promotion, or executable Coach suggestions.
- Live calendar-provider OAuth, URL fetch, incremental/background sync,
  provider writes, and applying calendar-derived time blocks.
- Autonomous weekly plan rewrites or applying review proposals without explicit
  confirmation.
- Vector search.
- Background workers unless implementation cannot stay simple without them.
- Remote production database claims without direct inspection.
