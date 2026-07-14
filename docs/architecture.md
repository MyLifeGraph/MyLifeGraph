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
FastAPI -> local Codex CLI/OAuth (explicit Phase 10 development adapter only)
```

The Flutter app is the main product surface. Supabase is the intended auth and
persistence backend. The FastAPI service is an independent AI boundary that
currently serves authenticated Intake V1 and deterministic recommendation
and daily-briefing workflows when backend Supabase settings are configured. It
also owns deterministic user-state snapshot aggregation plus the protected
scheduled preparation boundary for backend-generated daily state and briefings,
the bounded deterministic weekly-review boundary, and the optional bounded
read-only `.ics` import boundary.
It also owns the bounded authenticated Coach boundary. Only a deliberate
`POST /v1/coach/respond` may invoke a configured provider; capability, history,
memory, Dashboard, capture, action, scheduler, recommendation, and weekly-review
paths remain generation-free. The first real provider is explicitly enabled and
development-only; the CLI/OAuth process is not a new Flutter or Supabase
connection.

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
to Dashboard, Insights, central quick-action, the stored Inbox, and Settings.
Guest/demo sessions receive one persistent `Local demo` banner. The canned
Coach preview and direct Supabase message writer have been replaced by a typed
FastAPI Coach surface at `/coach`; `/more` aliases that route. Guest/mock renders
honest local unavailability and makes no Coach HTTP call.
`/deep-work` now serves the real linked focus lifecycle only when synced
execution is available; guest/demo sessions redirect to Quick Action.

## Runtime Configuration

The mobile app reads Dart defines through `AppConfig.fromEnvironment()`:

- `APP_ENV`
- `USE_MOCK_DATA`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `AI_SERVICE_BASE_URL`
- `COACH_SURFACE_ENABLED`

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

Dashboard, Recommendations, Insights, and the Inbox follow this source
boundary. `AppSurfaceCapabilities` also uses it to hide Supabase-only task,
habit, and focus commands from local guests and to validate route capabilities.
Calendar import follows the same rule: a real authenticated account uses the
FastAPI-backed integration source, while guest/mock renders an honest local
state and makes no calendar API call.
Coach follows it too: `COACH_SURFACE_ENABLED` controls whether navigation is
shown and whether `/coach` remains accessible. It is fail-closed in every
release build and for `APP_ENV=production` unless the exact value `true` is
supplied. When the surface is enabled, a static real-account capability permits
backend access while the authenticated backend capability independently reports
`disabled|unavailable|ready` and controls sending. Provider outage does not hide
persisted history or memory controls.

The global offline banner observes network transport only. It does not claim
that Supabase or FastAPI is reachable, and synced writes are not queued for
later delivery. Guest/demo persistence can continue locally on the current
device; failed synced forms retain their own draft/retry behavior.

`USE_MOCK_DATA=true` wins over the presence of a Supabase client, access token,
or authenticated profile. Setup, canonical check-in, Dashboard,
Recommendations, Insights, and the Inbox stay on their local/demo sources,
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
existing task section. The decision-first Today area now reads the persisted
`daily-briefing-v1` contract through FastAPI, shows mode, data quality,
freshness, capacity note, one primary action, and at most two support actions
above source metrics, then dispatches current targets through the exhaustive
Phase 3 action dispatcher. Normal load is GET-only; generation is explicit.
A local guest dashboard reads the locally saved canonical check-in and otherwise
shows a real empty state instead of a static fake plan. It labels briefing
generation unavailable instead of inventing a personalized local decision.

Authenticated real accounts can open `/weekly-review` from Dashboard or a
strict `review_plan` action. Flutter reads the latest completed profile-local
ISO week without generation, preserves `not_ready`, missing, current, stale,
and error truth, and generates or refreshes only after an explicit control.
Only a manual Habit V1 shrink/pause/archive proposal can call an existing typed
Habit V1 command after exact before/after confirmation. Setup-owned changes
return to Settings Setup; staged replacement, goal, task, or schedule proposals
do not mutate a record. Guest/mock sessions never call the weekly-review API.

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
Phase 8 gives `review_plan` a real authenticated `/weekly-review` navigation
handler; guest/mock and unsupported sessions stay unavailable, and dispatch
never generates or mutates. Phase 3 defines executable targets but does not select a primary action,
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
- `daily_briefings` for one persisted deterministic decision per user/local
  date; authenticated users may read their row, while FastAPI owns writes.
- `decision_feedback` for retry-safe owner-scoped outcome/preference events;
  users may read/delete history while FastAPI validates and inserts it.
- `weekly_reviews` for one backend-owned deterministic completed-ISO-week
  review per user/period; authenticated owners may read but only FastAPI writes.
- `calendar_connections`, `calendar_imports`, and `calendar_events` for one
  explicitly consented `.ics` source, immutable retry identities, and the
  current whitelisted read-only local event copy. A backend-only
  `calendar_request_identities` registry prevents request reinterpretation
  across owners and operations without retaining content fingerprints. These
  tables remain separate from app-authored `schedule_items`.
- `coach_requests` for message-free pending claims, retry/lease state, bounded
  validated response/provenance, and deletion tombstones;
  `coach_usage_events` for retained append-only per-request outcomes/counters;
  and `coach_memory_selections` for explicit owner-scoped Coach use without
  rewriting `memory_entries`. Completed turns use exactly one bounded user and
  assistant `coach_messages` pair linked to the request.

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
- Serve scheduler-triggered deterministic daily preparation at
  `/v1/scheduled/daily-refresh` with a backend-only scheduled refresh token.
- Serve authenticated retry-safe stored-Inbox lifecycle at
  `POST /v1/notifications/{notification_id}/actions`; owner-scoped
  read/unread/dismiss mutations use one service-role-only RPC and never imply
  notification generation or delivery.
- Serve bearer-derived notification settings and foreground acknowledgement.
  The protected daily refresh may request deterministic generation; its
  database boundary revalidates explicit consent, timezone/local date, quiet
  hours, category, daily cap, and dedupe under the owner lock.
- Serve read-only latest/explicit weekly-review GETs plus deliberate
  `POST /v1/weekly-reviews/generate` under `weekly-review-v1`.
- Serve authenticated calendar connection/read endpoints plus deliberate file
  import, disconnect, and imported-data deletion under `calendar-import-v1`.
  The service parses bounded caller-selected UTF-8 `.ics` text; it does not
  fetch arbitrary URLs, hold provider credentials, or write to a calendar.
- Serve authenticated `coach-capabilities-v1`, `coach-request-v1`,
  `coach-response-v1`, `coach-history-v1`, and
  `coach-memory-selection-v1` endpoints. Only `POST /v1/coach/respond` can call
  a provider; exact completed replay returns the persisted result without
  another call.
- Claim a request without storing its message, build at most 32 KiB of bounded
  owner-scoped `coach-context-v1`, run deterministic safety boundaries, and
  atomically persist a successful user/assistant pair, response manifest, and
  retained usage event. Failed claims remain terminal; history deletion removes
  content and tombstones requests without deleting usage or freeing budget.
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
- Parse the same strict `executable-action-v1` envelope as Flutter so persisted
  briefings cannot return unknown commands, mismatched target kinds, nested
  metadata, or unsafe routes. `GET /v1/briefings/today` reads that decision and
  deliberate `POST /v1/briefings/generate` ranks or refreshes it.
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
- Support a bounded scheduler-triggered preparation pass that finds onboarded
  non-guest profiles, pins one local date per profile from one UTC run instant,
  and prepares deterministic daily snapshots plus persisted briefings. Current
  pairs are write-free; missing prerequisites and stale briefings converge on
  their existing daily identities. Recommendations remain disabled by default,
  and explicit opt-in still forces LLM wording off.

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
Persisted recommendation `action_label` values are rendered as informational
"Suggested next step" text, not as controls. Executable Today actions come only
from a validated current `daily-briefing-v1` target and its Phase 3 dispatcher.

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
evidence references. These action facts are additive inputs for briefing
selection. The repository paginates habit-log and focus-session windows in stable
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

Scheduled preparation is backend-only. `POST /v1/scheduled/daily-refresh`
requires `X-Scheduled-Refresh-Token` and captures one aware UTC instant for the
run. The service-role repository lists only onboarded non-guest profiles and
derives each profile's `briefing_date` with its IANA timezone. A request may
optionally supply `target_date` as an explicit backfill override.

Selection compares the exact local-date snapshot with the briefing's source
snapshot id and generation time. A missing snapshot is generated once; an
existing snapshot is reused when only its briefing is missing; a stale briefing
is updated against the exact snapshot; and an already-current pair performs no
write. Unique `(user_id, scope, period_key)` and `(user_id, briefing_date)`
identities make retries converge. A token holder may narrow an operational retry
with at most 20 `profile_ids`; those ids are still intersected with eligible
profiles and never bypass onboarding or guest exclusion. Per-user results expose
the local date, selection reason, snapshot/briefing ids and statuses, and a
sanitized failing stage (`profile_date`, `snapshot`, `briefing`, or
`recommendations`). One user's failure does not stop the rest of the bounded
batch.

Recommendation generation is disabled by default. Explicit
`include_recommendations=true` remains deterministic and forces LLM wording off;
snapshot and briefing preparation never call an LLM. This endpoint is not a
Flutter or browser runtime endpoint, and normal Dashboard load remains GET-only.
The repository contains no deployed cron manifest or production worker. The
local stack runner requests current-day deterministic notification generation
every 15 minutes, and Flutter can acknowledge/show a foreground banner after
separate consent. That local path must not be described as deployed scheduling,
push, browser, Android, or background-mobile delivery.
The target selector still prepares missing/stale Phase 7 state for eligible
profiles, but includes a fully current profile in a notification-only batch only
when the dedicated consent row is active.

Weekly review is authenticated but not scheduled. FastAPI resolves one
completed ISO week from the profile timezone, loads exact durable facts with
stable pagination, computes a canonical SHA-256 source fingerprint, and
persists one `(user_id, period_key)` review only on deliberate generation.
Read-only GET recomputes freshness without changing the row. The existing
generic weekly snapshot is supporting evidence, not a historical ledger:
task undo/restore and habit definition revisions cannot be reconstructed, so
those limitations stay explicit and affected habit opportunities become
unknown. Generation never applies a proposal or mutates a user-owned object.

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

### Implemented Phase 10 Controlled Coach Boundary

The exact Phase 10 contract is
`docs/phase-10-controlled-coach-plan.md`. Its first real provider is intentionally a
local test adapter, not a deployed service:

```text
authenticated Flutter request
  -> FastAPI owner-scoped bounded context
  -> fixed, hardened local `codex exec` subprocess
  -> current Linux user's existing Codex OAuth login
  -> schema validation and backend-owned provenance
```

OAuth state stays inside the local Codex installation. Flutter sends only its
normal Supabase bearer token to FastAPI; it never sees a Codex token, model
credential, or `CODEX_HOME`. FastAPI must not inspect OAuth files. Each Linux/
WSL developer logs in independently with `codex login`, and account/model
eligibility is an external capability that the app reports honestly.
`gpt-5.5` is the preferred normal Coach model because the boundary needs
general conversational reasoning and strict structured output, not coding-agent
specialization. The CLI is transport/authentication only. An account that does
not expose the configured model receives an honest unavailable state; there is
no automatic Spark/model fallback.

The provider is gated by development environment plus explicit Coach/local-
Codex flags. It receives stdin prompt data in an isolated empty directory with
ignored user configuration, ephemeral execution, read-only sandboxing, strict
output schema, explicit disabling of every available model-controlled tool,
bounded environment/output/time/concurrency, and no inherited Supabase or
application secrets. A CLI that cannot establish tool-free execution is
unavailable before context is sent. Because a same-user agentic CLI is not a
production-grade isolation boundary, this adapter must never be enabled in
production or presented as the deployed LLM architecture.

The context boundary follows "full reach, minimal disclosure": FastAPI may read
relevant canonical rows for the bearer-derived owner, but sends only a compact
32 KiB `coach-context-v1` package for the current request. The first package is
limited to current snapshot/Daily State, current briefing, bounded active
actions/goals/focus facts, an explicitly fresh weekly review when useful,
selected reviewable memory, and a small completed-turn window. The model gets
no database credential, SQL/tool access, cross-user data, imported calendar
content, or hidden free text. FastAPI attaches the exact used-data manifest;
the model cannot invent provenance.

Authenticated HTTP separates read/control paths from generation:
`GET /v1/coach/capabilities`, `GET|DELETE /v1/coach/history`, and
`GET /v1/coach/memories` plus explicit selection/deselection never call a model.
`POST /v1/coach/respond` accepts one strict 2,000-code-point message with a
retry-safe request id and `today` scope. One owner may have one live claim and,
by default, 20 retained attempts per profile-local day. Successful completion
atomically writes exactly one bounded user/assistant message pair and an
append-only usage event. History deletion removes those messages and clears
message fingerprints, responses, used-context manifests, and errors into
tombstones. Bounded provider/model/prompt/context accounting metadata, usage
events, and request identities remain, so deletion cannot reset budget or
permit request-id reinterpretation.
Memory selection is a separate projection capped at eight and does not rewrite
Setup-owned or manual memory content.

All standard tests use an injected fake provider. A live subscription smoke is
explicitly opt-in and never part of CI, normal verification, or a claim about a
different developer's account. The synthetic-context smoke completed on
2026-07-13 with the explicitly requested `gpt-5.5` model (`1 passed`), without
fallback and without logging the answer, prompt, or raw event stream. Real
local PostgreSQL parallel lock smokes also completed without deadlock or
timeout. Those results establish only this machine's provider path and local
database concurrency contract. A focused Phase 10 fake-provider browser rerun
and the subsequent full non-destructive local-Supabase journey also passed in
the current checkout. A separate authenticated Flutter -> FastAPI ->
`local_codex_oauth` -> same-user Codex CLI product-path turn also passed with
explicit `gpt-5.5`, strict persisted provenance, and visible UI data-use truth.
None of these checks establishes remote state, production readiness, or another
developer's account.

### V1 Account Controls

The exact boundary is `docs/v1-account-controls-contract.md`. Real authenticated
accounts use bearer-derived FastAPI routes for durable IANA timezone changes, a
strict bounded `account-export-v1` JSON portability export, and permanent
deletion.
Password reset and confirmation resend remain Supabase Auth operations with a
dedicated recovery-event route in Flutter. Guest/mock sessions make no account
API calls.

Export reads only owner-filtered canonical product tables, applies field
allowlists to backend-owned Calendar/Coach ledgers, names the anti-replay ledger
it omits, and fails rather than truncating at a V1 bound. Flutter validates the
entire envelope and counts before saving. Full deletion requires exact typed
confirmation and one service-role-only database RPC. The RPC locks the existing
owner workflows, removes restrict-linked focus history, deletes the Auth user,
and verifies the profile/product cascade in one transaction. The client then
clears its local session even if the deleted remote session can no longer be
signed out normally.

Insights correlation exploration is bounded to visible 7/14/30/90-day windows.
Its five Supabase fact sources use stable pagination and fail explicitly at the
client row ceiling instead of presenting a silently truncated or unbounded
all-time result.

## Security Posture

- Supabase RLS is enabled and forced where migrations touch tables.
- User-owned tables scope access by `auth.uid()` or admin role helpers.
- Supabase service-role secrets are not used by the mobile app.
- The atomic Setup apply RPC revokes execute from `public`, `anon`, and
  `authenticated`; only the FastAPI service-role client can invoke it.
- Canonical profile identity and eligibility are backend-owned. Application
  roles cannot insert/delete profiles, change `role` or `auth_provider`, or
  write `onboarding_completed_at`; authorization reads only `profiles` and
  never falls back to a mutable legacy `"User"` row. The service-role Intake
  apply path retains the authority needed to project onboarding state.
- Phase 3 preserves existing table RLS/grants. A locked habit trigger rejects
  cross-user, inactive, paused/archived/candidate, and unscheduled selected-
  weekday outcomes. Focus triggers reject invalid links and every update to a
  terminal row; direct helper execution is revoked from app roles. Restricted
  target FKs preserve history, and a partial unique index permits at most one
  active focus session per user.
- `weekly_reviews` uses forced RLS, authenticated owner/admin SELECT only, and
  service-role writes. FastAPI scopes every privileged source query by the
  bearer-derived owner. Confirmed manual habit changes reuse authenticated
  Habit V1 ownership and optimistic timestamp checks.
- Calendar integration tables use forced RLS and backend-owned writes.
  FastAPI derives the owner before connect/import/disconnect/delete, and the
  schema prevents privileged cross-owner child rows.
- `notifications` remains authenticated read-only through the Data API.
  Lifecycle DML is available only through bearer-derived FastAPI and the
  owner-locked service-role `apply_notification_action_v1` RPC; its retry
  ledger is forced-RLS and unavailable to application roles.
- `notification_preferences` delivery fields are authenticated read-only and
  default fail-closed. Settings, deterministic generated-row creation, and
  foreground receipts use three owner-locked service-role-only RPCs. Flutter
  presents a banner only after the receipt RPC revalidates current consent,
  category, due time, timezone, and quiet hours. Settings replay fingerprints
  the expected revision and complete payload; the shared Setup writer
  invalidates that identity and cannot regress the preference revision.
- `20260714103000_application_table_privilege_guard.sql` closes table-level
  authority that RLS does not cover across every repo-owned product and ledger
  table. `anon` is fail-closed; authenticated `TRUNCATE`, `REFERENCES`, and
  `TRIGGER` are removed while intended table-specific DML is preserved; and
  backend projections remain authenticated read-only. Optional legacy tables
  are frozen and future `postgres`-created public tables inherit the same safe
  defaults. The installed Auth triggers remain active, but application and
  service roles cannot reuse their security-definer functions on another
  table. Notification child lookup and non-validating timestamp-order checks
  complete the guard without treating unverified legacy rows as clean.
- `20260714110000_account_export_lifestyle_entries_grant.sql` adds the missing
  `service_role`-only `SELECT` grant for the legacy-but-canonical
  `lifestyle_entries` table. Account Export V1 reads it even when it is empty;
  authenticated and anonymous application permissions remain unchanged.
- Mobile config uses Dart defines so credentials are not hard-coded in source.
- Production AI endpoints validate Supabase bearer tokens before reading user
  data or invoking privileged backend workflows when backend Supabase settings
  are configured.
- Phase 10 local Codex auth remains per-Linux-user CLI state. It must
  never be copied into Flutter, Supabase, `.env`, Git, logs, fixtures, or a
  subprocess environment alongside backend service credentials.
- Phase 10 Coach tables use forced RLS. Authenticated users may read only their
  own validated message, memory, and selection projections; request, usage,
  response, selection, and deletion mutations are service-role-only RPC work.
  Pending claims contain only a message fingerprint, not the message itself.
- V1 account profile/export/delete routes derive identity only from the verified
  bearer principal. The full-delete RPC is executable only by `service_role`,
  requires exact confirmation, and verifies the profile cascade before success.

## Known Gaps

- Coach is now a typed FastAPI surface for authenticated real accounts, with
  `/more` as a compatibility alias. Its backend capability may still report
  disabled or unavailable; production hides the surface unless explicitly
  enabled, and guest/mock makes zero Coach HTTP calls. Deep
  Work is available only to authenticated real accounts with synced execution
  capability. Settings exposes durable timezone, export and confirmed deletion
  for synced accounts, device-persisted theme, the durable Setup entry, optional
  Calendar Import and gated Coach entries, and sign-out.
- Inbox is a strict stored-item view. Original `type`, `priority`, read state,
  and supported `action_url` are shown; authenticated real accounts use the
  FastAPI `notification-lifecycle-v1` boundary to mark rows read/unread or keep
  a dismiss tombstone. Guest/mock stays local and zero-call. Explicit in-app
  consent now permits only fixed deterministic current briefing/recovery and
  exact completed-week items. The local runner creates bounded stored rows and
  an open authenticated Flutter app may acknowledge/show one at-most-once
  foreground banner. Recovery mode suppresses focus even when the recovery
  category is off, and weekly copy reuses the full Phase 8 source-fingerprint
  freshness check. Pending polling filters currently disabled categories before
  its bounded query. Existing reminder preferences alone grant no delivery;
  push/system delivery and deployed scheduling remain absent.
- Phase 4 persists one deterministic daily briefing per user/local date and
  ranks only strict Phase 3 targets. `GET /v1/briefings/today` is read-only and
  reports missing/current/stale state; deliberate
  `POST /v1/briefings/generate` refreshes the daily snapshot when generation is
  needed and upserts the same daily identity. Phase 5 consumes this strict
  contract in Flutter: a normal
  Dashboard read never posts, stale actions are disabled until deliberate
  `force=true` adjustment, and current primary/support actions reuse Phase 3
  handlers. Phase 6 adds `/v1/feedback` GET/POST/DELETE, exact owned-action
  validation, and a deterministic 28-day `feedback-ranking-v1` contribution.
  Original action reasons remain immutable; bounded contribution and reason
  codes are additive briefing provenance. Insights starts with one cautious
  observation and keeps full correlation analytics as advanced exploration.
- Phase 8 persists a deterministic weekly review only after explicit
  generation. `review_plan` is a real synced navigation handler, not an enabled
  no-op. Direct apply remains limited to manual Habit V1 shrink/pause/archive.
  Setup ownership stays in Setup, while replacement and goal/task/schedule
  changes remain staged. There is no task-transition or habit-definition
  history claim.
- Phase 9 accepts one explicitly consented, user-selected `.ics` source for a
  real account. Connection alone imports nothing; a bounded deliberate import
  reconciles stable event identities and exposes imported/read-only provenance.
  Disconnect retains the local copy, and confirmed deletion removes only local
  imported data. There is no provider OAuth, URL fetch, recurrence engine,
  provider write, background sync, or calendar-driven ranking change.
- The remote Production project may still contain legacy CamelCase tables until
  the canonical schema migration has been applied and verified.
- The repository does not contain real Supabase credentials.
- The only real-model adapter is `local_codex_oauth`, and it is disabled by
  default, development-only, same-Linux-user, and deliberately tool-free. It is
  not evidence of a production provider, subscription entitlement, universal
  model availability, or server deployment. No API-key fallback or provider
  failover exists.
- Daily and weekly snapshot aggregation exists behind an authenticated backend
  endpoint, and daily capture plus task/habit/focus writes trigger daily refresh
  best-effort. The protected scheduled endpoint can prepare profile-local daily
  snapshots and briefings, but there is no deployed cron configuration or
  production background worker in this repository.
- Focused Flutter/FastAPI tests cover Phase 3 contracts, parser parity, DST-safe
  calendar math, and focus local-day filtering. The browser smoke contains exact
  task/habit/focus rows; response-loss paths for habit/task create, habit
  outcome/undo, task completion/undo, and focus start/finish; and negative
  database lifecycle/range/cadence assertions including terminal-focus
  `updated_at`. The journey also covers Phase 8 weekly-review and Phase 9
  bounded calendar-import ownership and recovery boundaries. The combined Phase
  3 through Phase 9 journey passed non-destructively in the 2026-07-13 Phase 9
  implementation checkout. Later changes must establish their own
  current-checkout pass before claiming E2E.
- Explicit local demo mode remains the no-credentials exploration path and is
  labeled throughout the shell.
- The repository records one successful opt-in synthetic local Codex smoke for
  this machine and `gpt-5.5`, one successful authenticated Flutter-to-live-
  Codex product turn, plus focused and full current-checkout local browser
  passes with the deterministic fake provider. Standard automation remains
  fake-provider-only, and these checks do not establish remote state, another
  developer's account, or production readiness.
