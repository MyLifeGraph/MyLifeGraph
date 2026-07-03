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
to Dashboard, Insights, central quick-action, Notifications, and More/Coach.

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

Several features use the same repository pattern:

1. Read app config and auth session from Riverpod providers.
2. Use mock data when `USE_MOCK_DATA=true`, when the session is guest, or when
   Supabase is not configured.
3. Use Supabase data sources only when a real Supabase client and authenticated
   user are available.

This pattern is visible in Dashboard, Insights, and Notifications.

Some write actions, such as daily check-ins and quick mood check-ins, directly
require Supabase. Without Supabase configuration they show an in-app message
instead of writing remote data.

## Authentication

The current auth modes are:

- Local guest session through `shared_preferences`.
- Supabase email/password auth.
- Supabase Google OAuth.

Guest sessions can complete onboarding locally. If a user later authenticates
with Supabase, parts of the guest onboarding/check-in data are migrated into
Supabase by the auth repository.

## Supabase

Supabase owns the planned production auth, PostgreSQL persistence, and RLS
surface. The canonical application schema is now snake_case and centered on:

- `profiles` for public user profile, role, provider, timezone, and onboarding
  state.
- `daily_logs` for one daily summary row per user/date.
- `behavioral_events` for granular AI signal history.
- `tasks`, `schedule_items`, `notifications`, and `coach_messages` for the
  current product workflows.
- `memory_entries`, `ai_insights`, `recommendations`, and
  `skillset_profiles` for AI-generated context and output.
- `goals`, `habits`, `habit_logs`, and `focus_sessions` for near-term coaching
  expansion.
- `intake_responses` and `user_state_snapshots` for structured first-run
  answers and compact backend-owned user state.

Legacy CamelCase tables such as `"User"`, `"DailyLog"`, and `"Task"` may still
exist in older remote projects. The canonical migration copies data from those
tables when present, but new Flutter code should target the snake_case tables.

See `docs/supabase-current-state.md` for the exact current schema caveat.

## FastAPI AI Service

The AI service lives in `services/ai_service`.

Current responsibilities:

- Serve `/v1/health`.
- Serve authenticated Intake V1 at `/v1/intake/complete`.
- Serve authenticated recommendation contract endpoints at
  `/v1/recommendations` and `/v1/recommendations/generate`.
- Serve authenticated deterministic snapshot refresh at
  `/v1/snapshots/generate`.
- Keep recommendation generation behind a service boundary.
- Verify bearer tokens through an isolated auth verifier when Supabase backend
  settings are configured.
- Store structured intake responses, update onboarding state, create initial
  goals, habits, schedule items, notification preferences, durable memories,
  and an onboarding `user_state_snapshots` row without LLM calls.
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

Flutter reads persisted recommendations through `GET /v1/recommendations` when
`USE_MOCK_DATA=false`, Supabase is configured, and a real Supabase session
access token is available. The app attaches that token as a bearer token for the
FastAPI request. Guest mode, mock mode, missing Supabase configuration, missing
sessions, and network failures continue to use the local mock recommendation
fallback. Flutter does not automatically call
`POST /v1/recommendations/generate`.
Authenticated Intake V1 completion calls the same backend generation path after
the onboarding snapshot is written; normal dashboard reads still never generate
recommendations.

Snapshot refresh is a deliberate authenticated backend action through
`POST /v1/snapshots/generate`. The request can select `daily` or `weekly`
scope and an optional target date, but the backend always derives `user_id` from
the verified bearer token. If a snapshot already exists for the same
`user_id`, `scope`, and `period_key`, the backend updates it instead of
inserting another row.

Flutter triggers the `daily` snapshot refresh best-effort after successful
Supabase-backed Daily Check-In, Quick Mood Check-In, dashboard task status, and
Quick Action habit completion writes. The trigger is guarded by runtime config,
Supabase configuration, and a real access token. Guest mode, mock mode, missing
tokens, and AI-service failures do not block the original user write path.

Flutter onboarding sends the structured Intake V1 payload to
`POST /v1/intake/complete` only in real backend mode with a Supabase access
token. Guest and mock paths keep local onboarding state and do not require the
AI service. If the AI service is unavailable during authenticated local
onboarding, the app falls back to the previous direct profile/timetable write so
the user can still enter the app; that fallback does not create
`intake_responses` or `user_state_snapshots`.

Current limitation: JWT verification is isolated behind the FastAPI auth
dependency and currently calls Supabase Auth's user endpoint with the configured
backend Supabase credentials. The repository still does not contain production
credentials, and the live remote database must be inspected directly before
making claims about deployed data.

## Security Posture

- Supabase RLS is enabled and forced where migrations touch tables.
- User-owned tables scope access by `auth.uid()` or admin role helpers.
- Supabase service-role secrets are not used by the mobile app.
- Mobile config uses Dart defines so credentials are not hard-coded in source.
- Production AI endpoints validate Supabase bearer tokens before reading user
  data or invoking privileged backend workflows when backend Supabase settings
  are configured.

## Known Gaps

- The remote Production project may still contain legacy CamelCase tables until
  the canonical schema migration has been applied and verified.
- The repository does not contain real Supabase credentials.
- The FastAPI service is connected to Supabase-backed deterministic
  recommendations, but no LLM/model provider is connected.
- Daily and weekly snapshot aggregation now exists behind an authenticated
  backend endpoint, and daily check-in, dashboard task status, and habit
  completion flows trigger daily refresh best-effort. There is not yet a
  background scheduler.
- Mock mode is the reliable path for local product exploration today.
