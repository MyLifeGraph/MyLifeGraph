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

## Tables Referenced By The Flutter App

The app table constants live in
`apps/mobile/lib/core/supabase/supabase_tables.dart`.

| Table | Current app use |
| --- | --- |
| `profiles` | Present in constants and initial migration. |
| `"User"` | Auth profile rows, roles, onboarding state. |
| `"DailyLog"` | Dashboard metrics, daily check-in, quick mood check-in. |
| `"SleepLog"` | Daily check-in and quick mood check-in detail writes. |
| `"MoodLog"` | Daily check-in and quick mood check-in detail writes. |
| `"ActivityLog"` | Daily check-in detail writes. |
| `"Task"` | Dashboard plan items and task completion updates. |
| `"Notification"` | Notifications list and read updates. |
| `"ScheduleItem"` | Onboarding timetable and dashboard schedule. |
| `"AIInsight"` | Insights list. |
| `"CoachMessage"` | More/coach message history and writes. |
| `"FocusSession"` | RLS-hardened if present, not central in current UI flow. |
| `"MemoryEntry"` | Quick mood check-in memory writes. |
| `behavioral_events` | Optimization event data source boundary. |
| `lifestyle_entries` | Newer life-graph schema. |
| `skillset_profiles` | Newer life-graph schema. |
| `recommendations` | Newer life-graph schema. |
| `notification_preferences` | Newer life-graph schema. |

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

## Important Caveat

A clean local Supabase database created only from these migrations may not
contain every CamelCase table the Flutter app expects. The later migrations use
`if to_regclass(...) is not null` checks for many app-facing tables, which means
they harden existing tables but do not create missing ones.

Before relying on `USE_MOCK_DATA=false`, confirm that the target Supabase
project has the expected app-facing tables and policies.

## What Agents Can Safely Infer

Agents can inspect and modify:

- Flutter Supabase client code.
- Supabase migrations in this repo.
- Environment examples.
- Local development docs.

Agents cannot infer the live remote database state from the repo alone.
Do not claim that remote tables exist unless you have inspected the Supabase
project with credentials.

## Recommended Next Schema Decision

Before expanding real Supabase mode, decide whether the product should standardize on:

1. The existing app-facing CamelCase tables such as `"DailyLog"` and `"Task"`.
2. The newer snake_case life-graph tables such as `lifestyle_entries`.
3. A deliberate migration path from one schema family to the other.

Until that decision is made, keep mock/guest mode as the default local path and
document Supabase behavior carefully.
