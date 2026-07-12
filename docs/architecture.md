# Architecture

This document describes the current repository shape. It intentionally
distinguishes implemented behavior from planned backend integration. For the
target backend flow, product agents, LLM cost controls, and next implementation
sequence, see `docs/backend-roadmap.md`.

## High-Level Shape

```text
Flutter app <-> Supabase Auth/Postgres
Flutter app <-> FastAPI AI service
Flutter app <-> local mock data and guest storage
```

The Flutter app is the main product surface. Supabase is the intended auth and
persistence backend. The FastAPI service is an independent AI boundary that
currently serves authenticated Intake V1 and deterministic recommendation
workflows when backend Supabase settings are configured. It also owns
deterministic user-state snapshot aggregation for backend-generated `daily` and
`weekly` summaries.

## Mobile App

The Flutter app uses feature-first clean architecture:

- `core` contains config, bootstrap, routing, network clients, Supabase access,
  theme, and reusable widgets.
- `features/*/domain` contains entities and repository contracts.
- `features/*/data` contains mock data sources, Supabase data sources, and
  repository implementations.
- `features/*/application` contains orchestration that should not live in
  widgets.
- `features/*/presentation` contains pages, widgets, and Riverpod providers.

State management is Riverpod. Navigation is GoRouter. The shell navigation maps
to Dashboard, Insights, central quick-action, Notifications, and Settings.
Guest/demo sessions receive one persistent `Local demo` banner. The canned
Coach preview remains outside productive routing and redirects to Dashboard.
`/deep-work` now serves the real linked focus lifecycle only when synced
execution is available; guest/demo sessions redirect to Quick Action.

## Runtime Configuration

The mobile app reads Dart defines through `AppConfig.fromEnvironment()`:

- `APP_ENV`
- `USE_MOCK_DATA`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `AI_SERVICE_BASE_URL`

Supabase is initialized only when both Supabase values are non-empty. Without
them, the app can still run through local guest mode and mock data.

## Data Source Selection

Source selection is explicit rather than a recovery fallback:

1. Read app config, authenticated session, and Supabase availability from
   Riverpod providers.
2. Use local/mock data only when `USE_MOCK_DATA=true` or the current session is
   explicitly guest/demo.
3. Use Supabase/FastAPI sources for authenticated real accounts.
4. Treat missing real configuration, missing auth, invalid responses, and
   network failures as recoverable errors. Do not substitute personalized-looking
   mock content. A successful empty response remains a separate valid state.

Dashboard, Recommendations, Insights, and Notifications follow this source
boundary. `AppSurfaceCapabilities` also uses it to hide Supabase-only task,
habit, and focus commands from local guests and to validate route capabilities.

`USE_MOCK_DATA=true` wins over the presence of a Supabase client, access token,
or authenticated profile. Setup, canonical check-in, Dashboard,
Recommendations, Insights, and Notifications stay on their local/demo sources,
and synced execution plus snapshot actions remain unavailable. This prevents a
partly real, partly demo session during local exploration. Auth boot also skips
remote profile reads/creation and guest check-in migration in this mode, then
overlays the locally applied Setup name and completion state so reload remains
local and consistent.

Canonical daily capture selects its store from the authenticated session.
Guest/demo sessions merge one typed local daily entry through
`shared_preferences`; real sessions merge the same Evening or Morning capture
into Supabase. Other remote-only writes still show an in-app message when
Supabase is not configured.

## Canonical Daily Capture

`/quick-mood-check-in` is the Evening Shutdown implementation, and the legacy
`/daily-check-in` route redirects to it. `/morning-calibration` is a separate,
short Morning Calibration instead of another full daily form.

The current capture contract is:

- Typed `EveningShutdownDraft` and `MorningCalibrationDraft` values have stable
  capture ids through retry. `DailyCaptureEntry` is the one same-day aggregate.
- Evening requires mood, energy, stress intensity, the fixed stress source and
  controllability taxonomies, focus band, main friction, and tomorrow priority.
  Reflection, a specific blocker, and gentle-tomorrow intent are optional and
  omitted from metadata when blank or false.
- Morning requires sleep hours, current energy, and `normal`, `constrained`, or
  `flexible` day shape. It does not repeat Evening questions and explicitly
  states that it does not generate recommendations or create or change a plan.
- Same-day merge replaces only the submitted `metadata.captures.evening` or
  `.morning` object, preserving the other capture and unrelated metadata.
  Numeric compatibility projects mood and stress from Evening, sleep from
  Morning, and energy from Morning when present or Evening otherwise.
- Guest saves use a versioned V2 daily JSON object and remain readable on
  return. Legacy V1 guest JSON remains readable and is preserved during the
  existing best-effort guest-to-real-account check-in migration.
- Supabase saves upsert the `(user_id, entry_date)` `daily_logs` row and rebuild
  a dynamic set of at most four current `behavioral_events`. Mood, energy,
  stress, and sleep receive deterministic ids derived from the daily row and
  event kind, are linked through `daily_log_id`, and mirror relevant structured
  capture metadata.
- The upsert clears legacy placeholder-only steps, activity, screen-time, focus,
  nutrition, and day-focus values because the canonical form does not collect
  them. Rough focus stays a structured band and is not converted into invented
  `focus_minutes`.
- Optional notes remain check-in context. They are not promoted to durable
  `memory_entries`, tasks, recommendations, schedule rows, or notification copy.
- A failed write keeps the draft and exposes retry; an in-flight save ignores a
  second submit. Successful real-account writes refresh the daily snapshot for
  the capture's explicit local `target_date` best-effort; guest/mock writes do
  not call Supabase or FastAPI.

## Dashboard Source Contract

`DashboardSnapshot` carries an explicit `localDemo` or `account` origin, load
time, nullable latest check-in, true check-in streak, task rows, and schedule
entries. The Supabase mapper preserves stored mood, energy, sleep, stress,
focus, steps, activity, and screen-time values exactly and reads only persisted
Evening/Morning flags, focus band, stress context, and day shape from metadata.
The guest mapper uses the same merged daily object. The UI shows only fields
that exist and labels the latest row by its real date; missing values do not
become zero, a mode, or a derived readiness score.

The former wellness/optimization/recovery score, fake steps, derived sleep,
invented screen time, hydration estimate, and schedule activity bars are
removed. Tasks retain their own description, deadline, priority, status, and
optional estimate; recommendation reasons are no longer copied into unrelated
task descriptions. Authenticated users can execute typed task commands from the
existing task section, while a small unranked `Today execution` section links to
today's habits and focus. This is not the later decision-first Today redesign.
A local guest dashboard reads the locally saved canonical check-in and otherwise
shows a real empty state instead of a static fake plan.

Insights also uses this boundary for deterministic correlation analysis. In
mock or guest mode it renders local time series. In real Supabase mode it reads
recent `daily_logs`, `tasks`, `schedule_items`, `habits`, and `habit_logs`,
derives daily metric values, and computes 7/14/30-day correlations in Flutter.
This path does not call FastAPI or an LLM.

## Phase 3 Executable Actions

Phase 3 keeps simple user-owned mutations in typed Flutter/Supabase boundaries:

- `TaskSupabaseDataSource` resolves the authenticated user, scopes every read and
  update by both user and object id, and supports idempotent UUID-keyed create,
  edit, complete, postpone, cancel, restore, and immediate undo. Failed creates
  retain their draft/request id for retry. Every update, including edit,
  lifecycle transitions, restore, and undo, chooses a mutation timestamp and
  reconciles a lost committed response only when an exact owner-scoped
  timestamp/requested-field readback matches; concurrent divergence remains an
  error. Terminal actions are confirmed or expose undo.
- Habit V1 stores `daily`, selected ISO weekdays, or `weekly_target` cadence in
  bounded `habits.metadata` while retaining compatible `frequency`/`target`
  columns. Manual habits have active/paused/archived lifecycle. Today Habits
  persists exactly one explicit `completed` or `skipped` row per local date and
  deletes it for undo; open and missed opportunities remain derived. Setup-owned
  definitions/lifecycle stay in Settings Setup, but active rows share the daily
  outcome path. Manual edit/pause/archive/restore uses exact mutation readback
  after response loss. Outcome/undo captures its local target date before the
  write, proves the exact row or absence after response loss, and refreshes the
  same date. Paginated reads load all habits plus outcomes beginning 370
  calendar days before today. Manual creation persists local `started_on`, and
  date-component arithmetic keeps scheduled opportunities stable across DST
  boundaries.
- `/deep-work` is a real focus-session screen for authenticated real accounts.
  It starts at most one active session, optionally links one owned open task or
  active habit, measures whole elapsed minutes at finish/abandon, and never
  completes the linked object automatically. Finish/abandon use exact terminal
  readback after a committed response loss. Target validation locks the chosen
  task/habit row. Terminal rows reject every update, including `updated_at`, and
  `ON DELETE RESTRICT` target FKs preserve their historical linkage.

Flutter and FastAPI share a strict, ranking-independent
`executable-action-v1` envelope for `open_task`, `complete_task`, `log_habit`,
`start_focus`, `review_plan`, and `open_capture`. Kind/command/target and bounded
scalar metadata are validated; unknown combinations are rejected. Flutter's
`ExecutableActionDispatcher` exhaustively maps validated commands onto injected,
command-specific handlers and returns an explicit unavailable result before any
unsupported or unsynced execution. Flutter and FastAPI deliberately reject the
same unknown top-level/metadata fields, null or non-object metadata, explicit
null metadata fields, coercible numbers, invalid calendar dates, identifier
normalization, duration/linkage bounds, and command-specific metadata leakage.
`review_plan` is intentionally unavailable until a bounded planning surface
exists. Phase 3 defines executable targets but does not select a primary action,
persist a briefing, redesign Dashboard as Today, generate recommendations during
normal writes, or call an LLM. The full contract is in
`docs/phase-3-executable-actions-contract.md`.

## Authentication

The current auth modes are:

- Local guest session through `shared_preferences`.
- Supabase email/password auth.
- Supabase Google OAuth.

Guest sessions can complete onboarding locally. If a user later authenticates
with a real, non-demo Supabase account while `USE_MOCK_DATA=false`, canonical
guest check-ins are migrated best-effort into Supabase by the auth repository.
Guest Setup is intentionally not migrated: it remains local, while the real
account loads or creates its own authenticated backend Setup. Mock mode and
authenticated demo identities instead retain the local Setup across reload and
perform no remote profile/data bootstrap.

## First-Run And Setup Contract

Setup is one typed contract across first completion, re-entry, and review:

- Required focus, weekday shape, energy window, coaching style, and reminder
  choices are explicit. Goals, routines, context, calendar intent, and fixed
  commitments are progressive optional detail; blank values materialize no
  owned records.
- Guest/demo sessions read and write the typed setup locally. Authenticated
  real-mode sessions read `GET /v1/intake/setup` and save through
  `POST /v1/intake/complete`; there is no direct Supabase fallback that can mark
  an incomplete backend intake as finished.
- The Setup read returns the newest `intake-v1` row. A newest `pending` row is
  exposed with its request id so the client can freeze edits and retry that exact
  operation; otherwise the read returns the latest applied revision.
- A stable `request_id` makes a retry the same operation. `base_revision`
  provides optimistic edit concurrency, while persisted intake revisions move
  from `pending` to `applied`.
- `profiles.setup_revision` is a monotonic projection guard. Profile completion
  and optional display-name projection update only for a newer applied revision,
  so stale workers cannot overwrite a newer Setup projection.
- After the pending revision is claimed, FastAPI calls one service-role-only
  database RPC. A transaction-scoped per-user advisory lock serializes workers;
  preferences, Setup-owned goal/habit/schedule/memory reconciliation, the
  canonical onboarding snapshot, applied intake state, and profile projection
  either commit together or roll back together.
- Goals, activated habits, schedule items, and durable memories receive
  deterministic UUIDv5 record ids plus server-authored setup ownership metadata.
  Reconciliation converges to the submitted applied revision and never archives
  or removes manual/other-source rows. The only legacy exception deletes the
  exact unmarked onboarding placeholder `Math`, `Room 204`, Monday
  `08:15`-`09:45`; other manual and unmarked onboarding rows remain preserved.
- A named routine stays only in the intake response as a candidate. It becomes
  an active `habits` row only after explicit daily/weekly cadence confirmation.
- Settings links to the real Setup surface. Re-entry is prefilled and exposes
  loading, retryable error, edit, goal archive, habit pause/archive, and fixed
  commitment removal behavior.
- Setup-owned habits are edited, paused, or archived only through this Settings
  Setup surface. Active Setup habits remain visible for completion, intentional
  skip, and undo in Today Habits; generic Habit Management lists only
  non-Setup-managed habits.
- Client-side and HTTP 4xx rejection keeps the draft editable; 409 additionally
  recommends reloading server state. A timeout, 5xx, transport failure, or
  invalid success envelope leaves persistence uncertain, so the submitted draft
  is locked for exact unchanged retry or explicit reload.

## Supabase

Supabase owns the planned production auth, PostgreSQL persistence, and RLS
surface. The canonical application schema is now snake_case and centered on:

- `profiles` for public user profile, role, provider, timezone, onboarding
  state, and the monotonic Setup projection revision.
- `daily_logs` for one daily summary row per user/date.
- `behavioral_events` for granular AI signal history.
- `tasks`, `schedule_items`, `notifications`, and `coach_messages` for the
  current product workflows.
- `memory_entries`, `ai_insights`, `recommendations`, and
  `skillset_profiles` for AI-generated context and output.
- `goals`, `habits`, `habit_logs`, and `focus_sessions` for executable goal,
  habit-outcome, and focus workflows.
- `intake_responses` and `user_state_snapshots` for revisioned typed Setup
  history and compact backend-owned user state.

Legacy CamelCase tables such as `"User"`, `"DailyLog"`, and `"Task"` may still
exist in older remote projects. The canonical migration copies data from those
tables when present, but new Flutter code should target the snake_case tables.

See `docs/supabase-current-state.md` for the exact current schema caveat.

## FastAPI AI Service

The AI service lives in `services/ai_service`.

Current responsibilities:

- Serve `/v1/health`.
- Serve authenticated Setup read at `GET /v1/intake/setup` and Intake V1
  completion/edit at `POST /v1/intake/complete`.
- Serve authenticated recommendation contract endpoints at
  `/v1/recommendations` and `/v1/recommendations/generate`.
- Serve authenticated deterministic snapshot refresh at
  `/v1/snapshots/generate`.
- Serve scheduler-triggered deterministic daily refresh at
  `/v1/scheduled/daily-refresh` with a backend-only scheduled refresh token.
- Keep recommendation generation behind a service boundary.
- Verify bearer tokens through an isolated auth verifier when Supabase backend
  settings are configured.
- Claim revisioned structured intake responses, then call the service-role-only
  `apply_intake_v1_setup_revision` RPC. Its per-user advisory transaction lock
  atomically writes preferences, reconciles explicit Setup-owned goals,
  cadence-confirmed habits, schedule items and durable memories, upserts the
  constant `setup:intake-v1` onboarding snapshot, marks the intake applied, and
  advances the profile projection only from its canonical stored response.
- Load recent user-scoped data from `daily_logs`, `behavioral_events`, and
  `tasks` plus latest `user_state_snapshots`, run the deterministic v1
  recommendation engine, and persist verified recommendations to
  `recommendations`.
- Create or refresh compact `daily` and `weekly` `user_state_snapshots` from
  recent `daily_logs`, `behavioral_events`, `tasks`, `goals`, `habits`, explicit
  `habit_logs`, `focus_sessions`, `schedule_items`, and `memory_entries` without
  reading full history.
- Parse the same strict `executable-action-v1` envelope as Flutter so a later
  briefing cannot return unknown commands, mismatched target kinds, nested
  metadata, or unsafe routes. No endpoint ranks or returns a briefing yet.
- Add `summary.daily_state` and `signals.daily_state` under the
  `explainable-daily-state-v1` contract. The parser trusts V2 capture metadata
  only after strict identity, type, enum, numeric, timestamp, and projection
  checks. Legacy numeric fallback applies only when no V2 marker exists.
- Compute Daily State from a fixed seven-day lookback independent of the
  requested statistics window. Evening on the target date or previous date is
  current; Morning is current only on the target date. Quality is explicit as
  `missing`, `partial`, `current`, or `stale`.
- Classify `push`, `steady`, `recover`, or `plan` with recovery safeguards before
  planning or push rules. Persist machine-stable risks/reasons, field-level
  evidence, deterministic provenance, and no learned-baseline claim. Capture
  free text is excluded from summary, signals, and snapshot metadata.
- Load capture metadata with daily rows and events. Event queries use a broadened
  UTC read window, then prefer the explicit local `metadata.entry_date` during
  in-memory filtering and fall back to `occurred_at` for legacy events.
- Trigger a best-effort deterministic recommendation refresh after authenticated
  Intake V1 completion so the first real dashboard can read persisted
  onboarding-derived recommendations.
- Support a deliberate dashboard recommendation refresh action that first
  refreshes the daily snapshot best-effort, then calls the deterministic
  recommendation generate endpoint with LLM wording disabled.
- Support a bounded scheduler-triggered refresh pass that finds onboarded
  non-guest profiles, refreshes their deterministic daily snapshots, and can
  optionally run deterministic recommendation generation with LLM wording
  disabled.

Flutter reads persisted recommendations through `GET /v1/recommendations` when
`USE_MOCK_DATA=false`, Supabase is configured, and a real Supabase session
access token is available. The app attaches that token as a bearer token for the
FastAPI request. The typed response preserves provenance, `needs_generation`,
generation time, period key, and current/missing/older/period-mismatch freshness.
Guest/mock sessions receive a visibly labeled local demo feed. Missing real
configuration or auth, network failures, and invalid envelopes propagate as
errors and never read mock recommendations. Flutter does not automatically call
`POST /v1/recommendations/generate` during a normal read.
Authenticated Intake V1 completion calls the same backend generation path after
the onboarding snapshot is written; normal dashboard reads still never generate
recommendations. The dashboard refresh command is the explicit user-visible path:
it calls `POST /v1/recommendations/generate` with `allow_llm_wording=false`
after a best-effort daily snapshot refresh, then reloads persisted
recommendations. A failed refresh retains the previously displayed feed and
shows a recoverable failure; local demo sessions do not call the backend.

Snapshot refresh is a deliberate authenticated backend action through
`POST /v1/snapshots/generate`. The request can select `daily` or `weekly`
scope and an optional target date, but the backend always derives `user_id` from
the verified bearer token. If a snapshot already exists for the same
`user_id`, `scope`, and `period_key`, the backend updates it instead of
inserting another row. The existing `snapshot-aggregator-v1` source marker stays
stable; metadata records `daily_state_contract_version` and the fixed state
lookback separately from `window_days`. Top-level `summary.risk_flags` aliases
the current Daily State codes; the older statistics-window flags remain under
`summary.window_risk_flags`. `recommended_next_focus` is derived recovery-first
from Daily Mode rather than letting overdue work override recovery.
Phase 3 adds `summary.habits.outcome_counts`,
`summary.focus_sessions`, matching signal counts/status counts, and bounded
evidence references. These action facts are additive inputs for future briefing
work. The repository paginates habit-log and focus-session windows in stable
1,000-row pages, so server response caps cannot silently truncate counts or
minutes. Tests require `summary.daily_state` and `signals.daily_state` to remain
byte-for-byte equivalent when action rows are added or removed.

Flutter triggers the `daily` snapshot refresh best-effort after successful or
exactly reconciled Supabase-backed Evening/Morning, task, habit, and focus
writes. Capture calls send their explicit local entry date. Habit outcome/undo
captures and refreshes one stable target date. New focus rows persist their
local start `metadata.entry_date`; start/finish/abandon refresh that date. The
migration backfills missing legacy dates from the UTC calendar date of
`started_at`, which Flutter and FastAPI also use for invalid/missing metadata.
FastAPI applies the same rule after widening its focus UTC read window, so a new
session ending after midnight remains on its explicit local start day. The
trigger is guarded by runtime config, Supabase configuration, a real session,
and an access token. Guest/mock/missing-token paths and AI-service failures do
not block or roll back the original write.

Scheduled refresh is backend-only. `POST /v1/scheduled/daily-refresh` requires
`X-Scheduled-Refresh-Token`, lists onboarded non-guest profiles through the
backend Supabase service-role client, prioritizes profiles missing the target
date's daily snapshot, then fills the batch with the oldest existing daily
snapshots. It refreshes `user_state_snapshots` with an idempotent upsert and is
a scheduler/cron entrypoint, not a Flutter or browser runtime endpoint.

Flutter Setup sends the structured Intake V1 payload to
`POST /v1/intake/complete` only in real backend mode with a Supabase access
token and loads the newest Setup row through `GET /v1/intake/setup`. A pending
row resumes only with its original request id; otherwise the row is the latest
applied revision. Guest and mock paths keep the same typed setup locally and do
not require the AI service. Rejected 4xx saves remain editable, with reload
recommended for 409. An ambiguous timeout, 5xx, transport error, or invalid
response keeps the exact submitted draft and request id locked for unchanged
retry or explicit reload; no failure falls back to direct profile/timetable
writes or claims completion.

Current limitation: JWT verification is isolated behind the FastAPI auth
dependency and currently calls Supabase Auth's user endpoint with the configured
backend Supabase credentials. The repository still does not contain production
credentials, and the live remote database must be inspected directly before
making claims about deployed data.

## Security Posture

- Supabase RLS is enabled and forced where migrations touch tables.
- User-owned tables scope access by `auth.uid()` or admin role helpers.
- Supabase service-role secrets are not used by the mobile app.
- The atomic Setup apply RPC revokes execute from `public`, `anon`, and
  `authenticated`; only the FastAPI service-role client can invoke it.
- Phase 3 preserves existing table RLS/grants. A locked habit trigger rejects
  cross-user, inactive, paused/archived/candidate, and unscheduled selected-
  weekday outcomes. Focus triggers reject invalid links and every update to a
  terminal row; direct helper execution is revoked from app roles. Restricted
  target FKs preserve history, and a partial unique index permits at most one
  active focus session per user.
- Mobile config uses Dart defines so credentials are not hard-coded in source.
- Production AI endpoints validate Supabase bearer tokens before reading user
  data or invoking privileged backend workflows when backend Supabase settings
  are configured.

## Known Gaps

- Coach remains gated and redirects to Dashboard. Deep Work is no longer a
  preview: it is available only to authenticated real accounts with synced
  execution capability. Settings exposes read-only account data, session-only
  theme, the durable Setup entry, and sign-out.
- Notifications are currently a read-only inbox. Original `type`, `priority`,
  read state, and supported `action_url` are shown; there is no mark-read command
  until the repository has a durable write contract.
- Phase 3 executable targets are complete, but `review_plan` remains explicitly
  unavailable and there is no Phase 4 deterministic briefing service. Daily Mode
  remains backend snapshot state; the current Dashboard exposes only unranked
  execution links and does not choose a primary action, persist a briefing, or
  call an LLM.
- The remote Production project may still contain legacy CamelCase tables until
  the canonical schema migration has been applied and verified.
- The repository does not contain real Supabase credentials.
- The FastAPI service is connected to Supabase-backed deterministic
  recommendations, but no LLM/model provider is connected.
- Daily and weekly snapshot aggregation exists behind an authenticated backend
  endpoint, and daily capture plus task/habit/focus writes trigger daily refresh
  best-effort. There is not yet a production background worker, but a
  scheduler-triggered daily refresh endpoint exists for cron-style invocation.
- Focused Flutter/FastAPI tests cover Phase 3 contracts, parser parity, DST-safe
  calendar math, and focus local-day filtering. The browser smoke contains exact
  task/habit/focus rows; response-loss paths for habit/task create, habit
  outcome/undo, task completion/undo, and focus start/finish; and negative
  database lifecycle/range/cadence assertions including terminal-focus
  `updated_at`. A successful current-checkout browser run is still required
  before Phase 3 E2E may be claimed.
- Explicit local demo mode remains the no-credentials exploration path and is
  labeled throughout the shell.
