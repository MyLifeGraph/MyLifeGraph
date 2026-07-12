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
| `daily_logs` | One canonical daily row whose V2 metadata owns separate Evening/Morning captures plus direct nullable numeric Dashboard projections; the Dashboard does not synthesize proxy scores. |
| `behavioral_events` | Granular AI signal stream; canonical capture writes a dynamic deterministic maximum of four current events linked to its `daily_logs` row. |
| `tasks` | Owner-scoped executable tasks with create/edit/complete/postpone/cancel/restore/undo, optional 5-480 minute estimates, and explicit completion/cancellation timestamps. |
| `notifications` | Read-only Notifications inbox; original type, priority, read state, and allowlisted internal `action_url` targets. |
| `schedule_items` | Setup-owned confirmed fixed commitments plus preserved manual/other-source dashboard schedule rows. |
| `ai_insights` | Insights list. |
| `coach_messages` | Reserved persisted history; the canned Coach preview is gated from production navigation. |
| `memory_entries` | Durable onboarding and future reviewed coach memory. Check-in notes are not promoted automatically. |
| `focus_sessions` | Real one-active-session Deep Work lifecycle with bounded planned/measured duration, fully immutable terminal history, persisted local start date, and at most one owned task or active-habit target whose deletion is restricted. |
| `goals` | User goals, including deterministically identified Setup-owned rows with archive lifecycle. |
| `habits` | Habit V1 daily, selected-ISO-weekday, or weekly-target cadence plus active/paused/archived manual lifecycle; Setup owns definition/lifecycle for its rows while active rows share execution. |
| `habit_logs` | One explicit `completed` or `skipped` outcome per habit/local date, with checked 1/0 compatibility value; open and missed opportunities are derived and progress/streaks are cadence-aware. |
| `skillset_profiles` | Generated coaching/skill profile snapshots. |
| `recommendations` | Generated recommendations and user statuses; FastAPI can create first deterministic rows after authenticated Intake V1. |
| `notification_preferences` | User alert preferences. |
| `intake_responses` | Typed Setup history with request identity, optimistic revision, pending/applied state, and structured lifecycle items. |
| `user_state_snapshots` | Compact backend-owned onboarding/daily/weekly state; daily and weekly summaries add Phase 2 Daily State plus Phase 3 explicit habit-outcome/focus facts while remaining deterministic recommendation context. |
| `daily_briefings` | One backend-owned deterministic `daily-briefing-v1` decision per user/profile-local date with strict executable actions, source-snapshot provenance, bounded evidence, and stale detection. |
| `decision_feedback` | Retry-safe append-only feedback for an exact owned briefing action; authenticated owners can read/delete history and FastAPI owns validated writes. |

Phase 1 canonical capture upserts one `daily_logs` row per user/date with source
`quick_check_in`. `metadata.capture_version=daily-capture-v2` contains separate
owned `captures.evening` and `captures.morning` objects. Saving one kind replaces
only that object, preserving the other capture and unrelated metadata. Numeric
projection keeps existing consumers compatible: Morning energy takes
precedence, Evening owns mood and stress, and Morning owns sleep. Rough focus is
kept as a structured band and does not fabricate `focus_minutes`.

After each write Flutter removes the existing `quick_check_in` events linked to
that `daily_log_id` and upserts the explicit current signals with deterministic
ids derived from the daily row and event kind. The resulting set is dynamic and
contains at most mood, energy, stress, and sleep; an Evening-only or
Morning-only day therefore does not create unanswered events. Event metadata
mirrors the relevant capture kind, id, local entry date, capture time, and
bounded context. Repeated same-day saves converge without append-only signal
history. Existing columns, grants, and RLS policies are sufficient, so Phase 1
adds no schema migration.

Guest capture stores the same ownership model as V2 JSON in
`shared_preferences`, still reads V1 guest JSON, and keeps the existing
best-effort check-in migration into a real non-demo account. Guest Setup remains
separate and is still not migrated automatically. Real capture saves request a
best-effort daily snapshot for their explicit local `target_date`. FastAPI loads
daily/event metadata, widens the UTC event query by one calendar day on both
sides, prefers `metadata.entry_date` when filtering, and falls back to
`occurred_at` for legacy events.

Dashboard reads keep direct nullable numeric values and persisted capture
presence/context only. Phase 1 does not add Daily Mode, briefing ranking,
recommendation generation on save, or LLM usage. It also does not change the
Phase 0C revision tables, profile guard, or atomic Setup RPC.

Phase 2 also requires no migration. FastAPI extends existing daily and weekly
snapshot JSON additively under `summary.daily_state` and
`signals.daily_state`, with contract version `explainable-daily-state-v1`.
`summary.daily_state` contains target date, `push|steady|recover|plan` mode,
`missing|partial|current|stale` quality, per-kind freshness, bounded structured
context, current risk/reason codes, readable explanations, load guidance, and
deterministic provenance. `signals.daily_state` contains generated time,
provenance rows, field-level risk/reason evidence, and bounded quality-issue
codes. Capture free text is excluded.

Daily State always uses a fixed seven-day lookback even when the caller requests
a different statistics window. Evening is current from the target date or
previous date; Morning is current only from the target date. Strict V2 parsing
does not fall back to projected columns after a malformed or unsupported V2
marker. Legacy numeric rows are accepted conservatively only when no V2 marker
exists. Missing, partial, or stale evidence cannot produce `push`, and recovery
rules precede planning/productivity rules.

The persisted source marker remains `snapshot-aggregator-v1`. Metadata adds
`daily_state_contract_version` and `state_lookback_days`; existing
`window_days` remains the statistics window. Top-level `summary.risk_flags`
aliases the current Daily State risk codes. The previous window-aggregate flags
remain additive under `summary.window_risk_flags`, and
`recommended_next_focus` is derived recovery-first from Daily Mode. The unique
`(user_id, scope, period_key)` index continues to make recomputation an atomic
same-row replacement rather than append-only history.

Phase 3 adds executable storage contracts through
`20260711120000_phase_3_executable_action_schema.sql`. Tasks gain an optional
bounded estimate plus `completed_at` and `cancelled_at`; a lifecycle check ties
each terminal status to exactly its owned timestamp. `habit_logs.status` is
authoritative (`completed|skipped`), while a check keeps the legacy `value`
projection at 1 or 0. A `FOR NO KEY UPDATE` trigger locks the same-user habit and
requires current active lifecycle, executable Setup state, and (for weekday
cadence) a scheduled ISO weekday on `entry_date`. Open means no row exists for
that local date; missed is derived from an elapsed scheduled opportunity.

Focus sessions gain `active|completed|abandoned` status, optional `task_id` or
`habit_id`, and `updated_at`. Planned duration is constrained to 5–240 minutes;
terminal rows carry an end timestamp and exact whole elapsed minutes.
Constraints, a same-user/available-target trigger that locks the selected
target row, an all-update terminal immutability trigger, and a partial unique
index enforce at most one active session per user and at most one owned target.
Every update to a terminal row is rejected, including `updated_at`. The
task/habit FKs use `ON DELETE RESTRICT`, preserving historical attribution.
Historical duplicate open sessions are reconciled deterministically during
migration. Missing legacy `metadata.entry_date` values are backfilled from the
UTC calendar date of `started_at`. Existing RLS and table grants remain
unchanged.

The Flutter Habit V1 reader paginates 500 habit rows and 1,000 log rows per
request for outcomes beginning 370 calendar days before today. New manual habits
persist local `metadata.started_on`; date-component iteration and UTC-normalized
calendar-day differences avoid 23/25-hour DST shifts. Every task update,
including undo, and each manual habit definition/lifecycle update reconciles an
ambiguous committed response only by exact owner-scoped
timestamp/requested-field readback. Habit outcome/undo captures one target date
before awaiting persistence, proves the exact row or absence, and refreshes
that same date. Focus finish/abandon uses exact terminal readback.

The snapshot aggregator now reads explicit `habit_logs` and `focus_sessions`
and adds bounded action summaries, counts, minutes, and evidence. These facts do
not change `summary.daily_state`, `signals.daily_state`, the
`explainable-daily-state-v1` classifier, or `snapshot-aggregator-v1`. Successful
real task, habit, and focus writes request snapshot refresh best-effort; they do
not generate recommendations or call an LLM. Focus start persists
`metadata.entry_date`; all focus transitions refresh the persisted start day.
Backend filtering prefers that local date over the deterministic UTC
`started_at` fallback shared with Flutter after a widened read. Habit-log and
focus-session inputs paginate in stable 1,000-row pages through the complete
requested window. See
`docs/phase-3-executable-actions-contract.md` for command, validation, and
failure semantics.

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

`20260711120000_phase_3_executable_action_schema.sql` adds task estimates and
terminal timestamps; explicit habit-log outcomes and update timestamps; and
focus status, targets, and update timestamps. It backfills documented legacy
task terminals, positive habit completions, and focus lifecycle fields,
including missing focus entry dates from the UTC date of `started_at`. It
reconciles duplicate legacy active focus rows deterministically, then enforces
task estimate/lifecycle bounds, habit status/value consistency plus active-owner
and selected-weekday locking, focus duration/lifecycle shape, one target, one
active session, locked target ownership/availability, rejection of every
terminal-row update, and restricted target deletion. Hardened private
security-definer helpers have fixed search paths and no callable grant for app
roles. Existing table RLS and grants remain unchanged.

The migration safely normalizes positive legacy habit values to completion. It
intentionally stops with a check violation if a legacy habit log has
`status is null` and `value <= 0`, because such a row does not prove an
intentional skip. Inspect and resolve its meaning before applying the migration;
do not coerce it into `skipped` merely to make migration pass.

## Local Verification Workflow

For local Supabase-backed testing, the reset should complete through:

```text
20260712190000_phase_6_decision_feedback.sql
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

If the existing local database is behind, apply pending migrations without
destroying its data:

```bash
HOME=.tools/supabase-home \
SUPABASE_TELEMETRY_DISABLED=1 \
supabase migration up --local
```

For local Supabase reset and migration verification:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The reset form should apply all migrations through
`20260712190000_phase_6_decision_feedback.sql`; expected legacy-table
skip notices may be emitted for missing CamelCase tables. Use reset when proving
the full migration/backfill/constraint chain from a fresh local database, not
merely because one non-destructive migration is pending.

Then either run the browser E2E smoke in `scripts/e2e_web.sh` or start the
frontend with `scripts/start_frontend.sh` and manually verify the
Supabase-backed path:

- Register or sign in.
- Complete required-only Setup, re-enter it, and save an edit.
- Review/archive or remove one Setup-owned item and preserve a manual row.
- Save Evening Shutdown through either current route, then save Morning
  Calibration and confirm that the same daily row retains both captures.
- From Dashboard, create/edit/postpone/undo/complete/restore/cancel/restore a
  task and confirm estimates and terminal timestamps remain coherent.
- Complete, skip, and undo one manual habit and one active Setup-owned habit;
  confirm there is at most one outcome row per habit/local date.
- Start, finish, and abandon Deep Work with an owned task or active-habit link;
  confirm the target itself is not completed implicitly.
- Open Dashboard and confirm its execution links remain unranked. Call the
  read-only briefing GET, deliberately generate once, and confirm exactly one
  `daily_briefings` row whose actions point to current executable targets.
- Record briefing feedback, confirm its exact `decision_feedback` context,
  deliberately adjust Today, then delete the history row and confirm the next
  adjustment reports zero feedback influence.
- Open notifications.

This checks that Auth, RLS, grants, FastAPI backend workflows, and the app's
snake_case table mappings work together. The repository provides
`scripts/e2e_web.sh` for browser automation of this Supabase-backed flow. The
browser smoke starts the AI service with backend local Supabase settings and
asserts revisioned Intake V1 rows, ownership-scoped Setup reconciliation,
onboarding and daily `user_state_snapshots`, post-intake deterministic
`recommendations`, exact Phase 2 recomputation, and direct app writes. Phase 3
browser completion additionally requires exact task transition/undo rows,
manual and Setup habit completion/skip/undo without duplicates, and focus
start/finish/abandon with owned linkage and no implicit target mutation. The
source injects committed response loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish. Negative
task/focus/habit lifecycle, duration, active-target, and weekday-cadence writes
include terminal-focus `updated_at` mutation. Run the smoke successfully before
claiming coverage passed; this document does not claim such a run. Do not run
destructive reset commands against a remote database.

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

The latest schema addition is
`20260712190000_phase_6_decision_feedback.sql`. It creates owner-scoped
`decision_feedback` history with a unique `(user_id, request_id)`, exact bounded
feedback/context fields, read/delete RLS for authenticated owners, service-role
writes, and indexes for the 28-day ranking window. The preceding Phase 4
migration creates one owner-scoped `daily_briefings` row per user/local date with bounded action/evidence JSON,
explicit authenticated read and service-role write grants, forced RLS, and
owner/admin select plus service-role policies. The preceding Phase 3
executable-action migration over the existing task, habit-log, and focus-session
tables preserves table RLS and
grants while adding explicit fields, checks, ownership/transition triggers, and
the one-active-focus index required by the runtime contract. Locked habit
eligibility, immutable focus history, and restricted target FKs protect the
contract against stale/concurrent client state. The earlier Phase
0C service-role-only atomic Setup RPC, revision contract, and monotonic profile
guard remain unchanged. Phase 1 changes only typed capture metadata and
client/backend mapping; Phase 2 consumes that data inside existing snapshot
JSON; Phase 3 adds action facts without changing Phase 2 classification; and
Phase 4 persists deterministic briefing decisions without changing either
contract; Phase 6 adds feedback as separate evidence and never rewrites those
persisted reasons.
