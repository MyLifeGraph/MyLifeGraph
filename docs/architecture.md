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
Coach and no-op Deep Work previews are not built by production routes;
compatibility links redirect to Dashboard and Notifications respectively.

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
boundary. `AppSurfaceCapabilities` also uses it to hide Supabase-only habit
actions from local guests and to validate route capabilities.

`USE_MOCK_DATA=true` wins over the presence of a Supabase client, access token,
or authenticated profile. Setup, canonical check-in, Dashboard,
Recommendations, Insights, and Notifications stay on their local/demo sources,
and synced-habit plus snapshot actions remain unavailable. This prevents a
partly real, partly demo session during local exploration. Auth boot also skips
remote profile reads/creation and guest check-in migration in this mode, then
overlays the locally applied Setup name and completion state so reload remains
local and consistent.

The canonical daily check-in selects its store from the authenticated session.
Guest/demo sessions write one typed local entry per day through
`shared_preferences`; real sessions upsert the same selected values to Supabase.
Other remote-only writes still show an in-app message when Supabase is not
configured.

## Canonical Daily Capture

`/quick-mood-check-in` is the single implementation for current daily capture;
the legacy `/daily-check-in` route redirects to it. The removed legacy page and
data source previously displayed and persisted fixed example values.

The current capture contract is:

- Mood, energy, sleep hours, and stress have no measured default. The user must
  select each value before continuing; the context note is optional.
- One typed `QuickCheckInDraft` carries the selected values and a stable capture
  id through retry.
- Guest saves replace the same local calendar day's entry and can be read back
  in Quick Action and when reopening the flow.
- Supabase saves upsert the `(user_id, entry_date)` `daily_logs` row and replace
  exactly four `behavioral_events` linked through `daily_log_id`. This prevents
  repeated same-day saves from appending duplicate current-state signals.
- The upsert clears legacy placeholder-only steps, activity, screen-time, focus,
  nutrition, and day-focus values because the canonical form does not collect
  them. A future real source for those signals needs an explicit merge contract.
- The optional context note remains check-in context. It is no longer promoted
  automatically to a durable `memory_entries` pattern.
- A failed write keeps the draft and exposes retry; an in-flight save ignores a
  second submit. Successful real-account writes still refresh the daily snapshot
  best-effort.

## Dashboard Source Contract

`DashboardSnapshot` carries an explicit `localDemo` or `account` origin, load
time, nullable latest check-in, true check-in streak, task rows, and schedule
entries. The Supabase mapper preserves stored mood, energy, sleep, stress,
focus, steps, activity, and screen-time values exactly. The UI shows only fields
that exist and labels the latest row by its real date; missing values do not
become zero.

The former wellness/optimization/recovery score, fake steps, derived sleep,
invented screen time, hydration estimate, and schedule activity bars are
removed. Tasks retain their own deadline, priority, and status; recommendation
reasons are no longer copied into unrelated task descriptions. A local guest
dashboard reads the locally saved canonical check-in and otherwise shows a real
empty state instead of a static fake plan.

Insights also uses this boundary for deterministic correlation analysis. In
mock or guest mode it renders local time series. In real Supabase mode it reads
recent `daily_logs`, `tasks`, `schedule_items`, `habits`, and `habit_logs`,
derives daily metric values, and computes 7/14/30-day correlations in Flutter.
This path does not call FastAPI or an LLM.

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
  Setup surface. Active Setup habits remain visible and completable in Habit
  Completion; generic Habit Management lists only non-Setup-managed habits.
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
- `goals`, `habits`, `habit_logs`, and `focus_sessions` for near-term coaching
  expansion.
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
  recent `daily_logs`, `behavioral_events`, `tasks`, `goals`, `habits`,
  `schedule_items`, and `memory_entries` without reading full history.
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
inserting another row.

Flutter triggers the `daily` snapshot refresh best-effort after successful
Supabase-backed canonical daily check-in, dashboard task status, and
Quick Action habit writes. The habit flow now includes creating habits, editing
their frequency and target, pausing or restoring them, viewing 7-day completion
progress, and logging daily completions. Generic management excludes
Setup-owned habits, whose definition/lifecycle remains owned by Settings Setup;
Habit Completion includes their active rows. The trigger is guarded by runtime
config, Supabase configuration, and a real access token. Guest mode, mock mode,
missing tokens, and AI-service failures do not block the original user write
path.

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
- Mobile config uses Dart defines so credentials are not hard-coded in source.
- Production AI endpoints validate Supabase bearer tokens before reading user
  data or invoking privileged backend workflows when backend Supabase settings
  are configured.

## Known Gaps

- Coach and Deep Work remain unimplemented preview files, but production
  navigation and deep links gate them. Settings exposes read-only account data,
  session-only theme, the durable Setup entry, and sign-out.
- Notifications are currently a read-only inbox. Original `type`, `priority`,
  read state, and supported `action_url` are shown; there is no mark-read command
  until the repository has a durable write contract.
- Evening capture still lacks stress source, controllability, friction, and
  gentle-tomorrow intent, and there is no short returning-morning calibration.
  Those are the Phase 1 capture targets before Daily Mode work.
- The remote Production project may still contain legacy CamelCase tables until
  the canonical schema migration has been applied and verified.
- The repository does not contain real Supabase credentials.
- The FastAPI service is connected to Supabase-backed deterministic
  recommendations, but no LLM/model provider is connected.
- Daily and weekly snapshot aggregation now exists behind an authenticated
  backend endpoint, and daily check-in, dashboard task status, and habit
  management/completion flows trigger daily refresh best-effort. There is not
  yet a production background worker, but a scheduler-triggered daily refresh
  endpoint exists for cron-style invocation.
- Explicit local demo mode remains the no-credentials exploration path and is
  labeled throughout the shell.
