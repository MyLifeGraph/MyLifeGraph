# Architecture

This document describes the current repository shape. It intentionally
distinguishes implemented behavior from planned backend integration.

## High-Level Shape

```text
Flutter app <-> Supabase Auth/Postgres
Flutter app <-> FastAPI AI service
Flutter app <-> local mock data and guest storage
```

The Flutter app is the main product surface. Supabase is the intended auth and
persistence backend. The FastAPI service is an independent AI boundary that
currently returns placeholder recommendations.

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

Legacy CamelCase tables such as `"User"`, `"DailyLog"`, and `"Task"` may still
exist in older remote projects. The canonical migration copies data from those
tables when present, but new Flutter code should target the snake_case tables.

See `docs/supabase-current-state.md` for the exact current schema caveat.

## FastAPI AI Service

The AI service lives in `services/ai_service`.

Current responsibilities:

- Serve `/v1/health`.
- Serve authenticated recommendation contract endpoints at
  `/v1/recommendations` and `/v1/recommendations/generate`.
- Keep recommendation generation behind a service boundary.
- Verify bearer tokens through an isolated auth verifier when Supabase backend
  settings are configured.
- Load recent user-scoped data from `daily_logs`, `behavioral_events`, and
  `tasks`, run the deterministic v1 recommendation engine, and persist verified
  recommendations to `recommendations`.

Flutter reads persisted recommendations through `GET /v1/recommendations` when
`USE_MOCK_DATA=false`, Supabase is configured, and a real Supabase session
access token is available. The app attaches that token as a bearer token for the
FastAPI request. Guest mode, mock mode, missing Supabase configuration, missing
sessions, and network failures continue to use the local mock recommendation
fallback. Flutter does not automatically call
`POST /v1/recommendations/generate`.

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
- Mock mode is the reliable path for local product exploration today.
