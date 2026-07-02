# Supabase Current State

This document captures the repository state, not the live remote Supabase
project state. The repo does not contain credentials, so a live remote database
must be inspected through the Supabase dashboard or CLI by someone with access.

## Runtime Activation

The Flutter app initializes Supabase only when both values are non-empty:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Without those values, `supabaseClientProvider` returns `null`. The app still
runs through guest mode and mock data.

## Auth Modes

| Mode | Requires Supabase | Current behavior |
| --- | --- | --- |
| Guest | No | Stores session and onboarding state locally with `shared_preferences`. |
| Email/password | Yes | Uses Supabase Auth `signInWithPassword` and `signUp`. |
| Google OAuth | Yes | Uses Supabase OAuth and redirects to the current web origin. |

Supabase local auth config allows:

- `http://127.0.0.1:7357`
- `http://localhost:7357`

## Canonical Tables Referenced By The Flutter App

The app table constants live in
`apps/mobile/lib/core/supabase/supabase_tables.dart`.

| Table | Current app use |
| --- | --- |
| `profiles` | Auth profile rows, roles, provider, timezone, onboarding state. |
| `daily_logs` | Dashboard metrics, daily check-in, quick mood check-in. |
| `behavioral_events` | Granular AI signal stream from check-ins and optimization events. |
| `tasks` | Dashboard plan items and task completion updates. |
| `notifications` | Notifications list and read updates. |
| `schedule_items` | Onboarding timetable and dashboard schedule. |
| `ai_insights` | Insights list. |
| `coach_messages` | More/coach message history and writes. |
| `memory_entries` | Quick mood check-in memory writes. |
| `focus_sessions` | Focus-session history for future coaching flows. |
| `goals` | User goals for future coaching flows. |
| `habits` | User habits for future coaching flows. |
| `habit_logs` | Habit completions for future coaching flows. |
| `skillset_profiles` | Generated coaching/skill profile snapshots. |
| `recommendations` | Generated recommendations and user statuses; FastAPI can create first deterministic rows after authenticated Intake V1. |
| `notification_preferences` | User alert preferences. |
| `intake_responses` | Raw structured first-run Intake V1 answers. |
| `user_state_snapshots` | Compact backend-owned user state snapshots and deterministic recommendation input. |

## Legacy Tables

Older remote databases may contain CamelCase app tables:

| Legacy table | Canonical replacement |
| --- | --- |
| `"User"` | `profiles` |
| `"DailyLog"` | `daily_logs` |
| `"SleepLog"` | `behavioral_events` |
| `"MoodLog"` | `daily_logs` and `behavioral_events` |
| `"ActivityLog"` | `daily_logs` and `behavioral_events` |
| `"Task"` | `tasks` |
| `"Notification"` | `notifications` |
| `"ScheduleItem"` | `schedule_items` |
| `"AIInsight"` | `ai_insights` |
| `"CoachMessage"` | `coach_messages` |
| `"FocusSession"` | `focus_sessions` |
| `"MemoryEntry"` | `memory_entries` |

## Migration State

`20260514183000_initial_schema.sql` creates:

- `profiles`
- `behavioral_events`
- `lifestyle_entries`
- `skillset_profiles`
- `recommendations`
- `notification_preferences`

It also creates a `handle_new_user()` trigger for `profiles` and notification
preferences.

`20260602162000_auth_roles_rls.sql` adds role support and RLS for app-facing
CamelCase tables only when those tables already exist. It also creates
`handle_new_auth_user()` for `"User"`.

`20260613183000_harden_public_rls.sql` forces RLS and adds own-or-admin policies
for both schema families where tables exist.

`20260613190000_restrict_security_definer_functions.sql` moves role lookup into
the `private` schema and revokes public execution for security-definer helpers.

`20260618170000_create_canonical_app_schema.sql` creates the canonical
snake_case app schema, updates auth/profile helper functions, grants the
`authenticated` role app-table CRUD privileges for the Flutter client, grants
matching app-table privileges to `service_role` for local admin/E2E assertions,
adds RLS policies, and copies data from legacy CamelCase tables when they exist.

`20260702092807_intake_v1_backend_foundation.sql` adds
`intake_responses` and `user_state_snapshots`, indexes them by user/time access
patterns, grants read access to `authenticated`, grants full access to
`service_role`, enables and forces RLS, and applies own-or-admin read policies
plus service-role write policies. The FastAPI recommendation context loader now
reads latest `user_state_snapshots` through the backend service-role client with
explicit `user_id` filters. The FastAPI snapshot aggregator also reuses
`user_state_snapshots` for deterministic `daily` and `weekly` summaries.

`20260702195915_unique_user_state_snapshot_period.sql` deduplicates existing
`user_state_snapshots` rows by `(user_id, scope, period_key)`, keeping the most
recent `generated_at` row, then adds a unique index on those columns. The
FastAPI snapshot repository relies on that index for atomic upserts.

## Local Verification Workflow

For local Supabase-backed testing, the reset should complete through:

```text
20260702195915_unique_user_state_snapshot_period.sql
```

Then configure `.env` with:

```env
USE_MOCK_DATA=false
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<local anon key from supabase status>
```

Run the standard local checks first:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

This includes Flutter analysis, widget tests, Python compile checks, whitespace
checks, and the automated guest onboarding/quick-check-in smoke tests.

For local Supabase preflight without resetting the database:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

For local Supabase reset and migration verification:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The reset form should apply all migrations through
`20260702195915_unique_user_state_snapshot_period.sql`; expected legacy-table skip
notices may be emitted for missing CamelCase tables.

Then either run the browser E2E smoke in `scripts/e2e_web.sh` or start the
frontend with `scripts/start_frontend.sh` and manually verify the
Supabase-backed path:

- Register or sign in.
- Complete onboarding.
- Save a daily check-in.
- Save a quick mood check-in.
- Open dashboard.
- Open notifications.
- Send a coach message.

This checks that Auth, RLS, grants, and the app's snake_case table mappings work
together. The repository provides `scripts/e2e_web.sh` for browser automation of
this Supabase-backed flow. The browser smoke still focuses on direct app writes;
FastAPI Intake V1 and its post-intake deterministic recommendation refresh have
unit coverage and can be manually checked by running the AI service with backend
Supabase settings before completing onboarding. Do not run destructive reset
commands against a remote database.

See `docs/verification.md` for the current automation boundary.

## Important Caveat

The canonical Flutter code now targets snake_case tables. Legacy CamelCase
tables may still exist in the remote Production project, but new product code
should not add dependencies on them.

Before relying on `USE_MOCK_DATA=false`, confirm that the target Supabase
project has applied the canonical schema migration and has the expected RLS
policies.

## What Agents Can Safely Infer

Agents can inspect and modify:

- Flutter Supabase client code.
- Supabase migrations in this repo.
- Environment examples.
- Local development docs.

Agents cannot infer the live remote database state from the repo alone.
Do not claim that remote tables exist unless you have inspected the Supabase
project with credentials.

## Schema Direction

The product should standardize on the snake_case schema. CamelCase tables are
legacy compatibility only and should be dropped in a later dedicated migration
after data migration and app verification are complete.

The latest schema additions are `intake_responses` and
`user_state_snapshots` for the "Intake V1 without LLM" slice. The backend now
reuses those tables for authenticated daily and weekly snapshot aggregation
without adding broad LLM, calendar, or worker infrastructure.
