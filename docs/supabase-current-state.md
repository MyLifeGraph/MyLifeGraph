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
| `recommendations` | Generated recommendations and user statuses. |
| `notification_preferences` | User alert preferences. |

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
`authenticated` role app-table CRUD privileges, adds RLS policies, and copies
data from legacy CamelCase tables when they exist.

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
