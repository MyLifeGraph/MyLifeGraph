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

`USE_MOCK_DATA=true` is also an explicit source override: product surfaces stay
local/demo even when Supabase is configured and an authenticated session exists.
Auth boot skips remote profile reads/creation and guest-data migration in this
mode, then restores locally applied Setup state across reloads. Use
`USE_MOCK_DATA=false` to exercise the real Supabase/FastAPI paths.

## Auth Modes

| Mode | Requires Supabase | Current behavior |
| --- | --- | --- |
| Guest | No | Stores session and typed revisioned Setup state locally with `shared_preferences`; Setup is not copied into a later account automatically. |
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
| `profiles` | Auth profile rows, roles, provider, timezone, onboarding state, and monotonic `setup_revision` projection guard. |
| `daily_logs` | Canonical daily check-in and direct nullable Dashboard signals; the Dashboard does not synthesize proxy scores. |
| `behavioral_events` | Granular AI signal stream; the canonical check-in writes four events linked to its `daily_logs` row. |
| `tasks` | Dashboard plan items and task completion updates. |
| `notifications` | Read-only Notifications inbox; original type, priority, read state, and allowlisted internal `action_url` targets. |
| `schedule_items` | Setup-owned confirmed fixed commitments plus preserved manual/other-source dashboard schedule rows. |
| `ai_insights` | Insights list. |
| `coach_messages` | Reserved persisted history; the canned Coach preview is gated from production navigation. |
| `memory_entries` | Durable onboarding and future reviewed coach memory. Check-in notes are not promoted automatically. |
| `focus_sessions` | Focus-session history for future coaching flows. |
| `goals` | User goals, including deterministically identified Setup-owned rows with archive lifecycle. |
| `habits` | Cadence-confirmed Setup routines and manually managed habits; Setup owns edits/lifecycle for its rows, while Habit Completion can log active rows and unconfirmed candidates remain only in `intake_responses`. |
| `habit_logs` | Daily habit completion writes and 7-day completion progress for Quick Action habit flows. |
| `skillset_profiles` | Generated coaching/skill profile snapshots. |
| `recommendations` | Generated recommendations and user statuses; FastAPI can create first deterministic rows after authenticated Intake V1. |
| `notification_preferences` | User alert preferences. |
| `intake_responses` | Typed Setup history with request identity, optimistic revision, pending/applied state, and structured lifecycle items. |
| `user_state_snapshots` | Compact backend-owned user state snapshots and deterministic recommendation input. |

The canonical check-in upserts one `daily_logs` row per user/date with source
`quick_check_in`. It then replaces exactly four same-source events for that
`daily_log_id`: mood, energy, stress, and sleep. Repeated same-day saves therefore
represent the current daily state without append-only event duplication. This
uses existing columns and policies; no schema migration was required. The same
upsert nulls the legacy fixed steps, activity, screen-time, focus, nutrition, and
day-focus values that the canonical form does not collect.

Phase 0B did not require a migration. Flutter now treats missing or failing real
Dashboard/Notifications/Recommendation sources as empty or error according to
their contracts and never substitutes mock rows. Notification routing reads the
existing `action_url`, but only implemented internal paths are enabled; no
notification read-state write is claimed until a durable repository command is
added.

Phase 0C adds the revision history contract to `intake_responses` and the
monotonic projection revision to `profiles`. Setup-created goals, habits,
schedule items, and memories reuse their existing primary keys and metadata:
FastAPI derives deterministic UUIDv5 ids and writes `managed_by`,
`setup_item_id`, revision, lifecycle, and `source=intake-v1` metadata. This
makes ownership queryable without claiming manual or `demo_seed` rows. Candidate
routines do not create a `habits` row until cadence is confirmed. The apply RPC
preserves unmarked onboarding schedule rows except for the exact historical
placeholder `Math`, `Room 204`, Monday `08:15`-`09:45` with empty metadata,
which is removed when omitted.

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

`20260710120000_phase_0c_intake_request_revisions.sql` adds `request_id`,
`base_revision`, `revision`, `state`, and `updated_at` to `intake_responses`.
Legacy rows are deterministically ranked per user/version and marked applied.
Checks enforce a positive next revision, nonnegative base revision, consecutive
base/revision pairs, and `pending|applied` state. Unique indexes on
`(user_id, version, request_id)` and `(user_id, version, revision)` support
idempotent replay and optimistic edits. Existing authenticated-own-read and
service-role-write policies continue to apply.

`20260710153000_profile_setup_revision_guard.sql` adds nonnegative
`profiles.setup_revision` with a default of zero, backfills it to each user's
highest applied `intake-v1` revision, and adds its check constraint. FastAPI
conditionally advances this value with the profile projection so a stale worker
cannot overwrite fields from a newer applied Setup revision. This migration does
not change RLS policies or grants.

`20260710180000_atomic_intake_v1_setup_apply.sql` creates the security-definer
`apply_intake_v1_setup_revision` RPC with its final 13-parameter signature. It
revokes execute from `public`, `anon`, and `authenticated`, granting it only to
`service_role`. The function obtains a transaction-scoped advisory lock derived
from `user_id`, locks and validates the claimed canonical `intake-v1` row, then
atomically upserts notification preferences; reconciles Setup-owned goals,
habits, schedule items, and memories; upserts the canonical
`(user, onboarding, setup:intake-v1)` snapshot; marks the intake applied; and
projects profile completion, explicit display name, and `setup_revision`.
Ownership collisions or any failed assertion roll back the whole apply. An
applied replay is idempotent apart from a guarded repair of the newest profile
projection.

## Local Verification Workflow

For local Supabase-backed testing, the reset should complete through:

```text
20260710180000_atomic_intake_v1_setup_apply.sql
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
`20260710180000_atomic_intake_v1_setup_apply.sql`; expected legacy-table
skip notices may be emitted for missing CamelCase tables.

Then either run the browser E2E smoke in `scripts/e2e_web.sh` or start the
frontend with `scripts/start_frontend.sh` and manually verify the
Supabase-backed path:

- Register or sign in.
- Complete required-only Setup, re-enter it, and save an edit.
- Review/archive or remove one Setup-owned item and preserve a manual row.
- Save the canonical daily check-in through either current route.
- Open dashboard.
- Open notifications.

This checks that Auth, RLS, grants, FastAPI backend workflows, and the app's
snake_case table mappings work together. The repository provides
`scripts/e2e_web.sh` for browser automation of this Supabase-backed flow. The
browser smoke starts the AI service with backend local Supabase settings and
asserts revisioned Intake V1 rows, ownership-scoped Setup reconciliation,
onboarding and daily `user_state_snapshots`, post-intake deterministic
`recommendations`, and direct app writes. Do not run destructive reset commands
against a remote database.

For manual local product exploration, `npm run seed:demo` creates repeatable
local-only Auth users and app rows for student, worker, and recovery scenarios.
The seed script uses the local Supabase service-role key from
`supabase status -o env`, refuses non-local API URLs, and writes typed applied
Setup revisions with stable request ids and empty optional Setup-owned
collections. It does not change the schema or relabel the separately seeded
`demo_seed` objects as Setup-owned.

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

The latest schema addition is the Phase 0C service-role-only atomic Setup apply
RPC layered on the revision contract and monotonic profile guard. The backend
reuses `intake_responses` and `user_state_snapshots` for authenticated Setup and
deterministic daily/weekly aggregation without adding broad LLM, calendar, or
worker infrastructure.
