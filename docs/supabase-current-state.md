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
| Google OAuth | Yes | Uses Supabase OAuth; web returns to the current origin and installed Android returns through `com.mylifegraph.app://login-callback/`. |

Supabase local auth config allows:

- `http://127.0.0.1:7357`
- `http://localhost:7357`
- `com.mylifegraph.app://login-callback/`

The Android callback is also used for signup confirmation and password
recovery. A remote Supabase project must allowlist it explicitly before an
installed Android build can complete those flows. There is no iOS runner in
this repository, so native iOS callbacks are outside the current boundary.

## Canonical Tables Referenced By The Flutter App

The app table constants live in
`apps/mobile/lib/core/supabase/supabase_tables.dart`.

| Table | Current app use |
| --- | --- |
| `profiles` | Canonical auth profile projection. Identity/authority (`role`, `auth_provider`) and onboarding eligibility are backend-owned; authenticated edits are limited to explicitly granted non-authority fields, `setup_revision` remains a monotonic backend projection guard, and the nullable account-wide preparation budget is read-only to application roles. |
| `daily_logs` | One canonical daily row whose V2 metadata owns separate Evening/Morning captures plus direct nullable numeric Dashboard projections; the Dashboard does not synthesize proxy scores. |
| `behavioral_events` | Granular AI signal stream; canonical capture writes a dynamic deterministic maximum of four current events linked to its `daily_logs` row. |
| `tasks` | Owner-scoped executable tasks with create/edit/complete/postpone/cancel/restore/undo, optional 5-480 minute estimates, and explicit completion/cancellation timestamps. |
| `notifications` | Authenticated read-only Inbox projection with backend-owned read/unread/dismiss lifecycle plus optional deterministic generation key/category/local-date/provenance and foreground receipt time. A stored row alone does not prove delivery. |
| `notification_action_requests` | Service-role-only exact retry/result ledger for `notification-lifecycle-v1`; it contains identities and lifecycle projections, not notification copy. |
| `schedule_items` | Setup-owned confirmed fixed commitments plus preserved manual/other-source dashboard schedule rows. Setup-owned metadata may add inclusive optional `valid_from`/`valid_until` semester dates; older/undated rows remain unbounded. |
| `ai_insights` | Insights list. |
| `coach_messages` | Bounded validated Phase 10 user/assistant history linked to a retry-safe backend request. Authenticated owners can read; only FastAPI can insert/delete V1 turns. Legacy rows remain distinguishable by null request/contract fields. |
| `memory_entries` | Durable Setup/manual memory content. Authenticated owners can read, but Phase 10 selection is a separate projection and does not transfer Setup ownership or promote check-in/conversation text automatically. Preference rows remain ineligible until a later sensitivity contract can distinguish hidden context safely. |
| `focus_sessions` | Real one-active-session Deep Work lifecycle with bounded planned/measured duration, fully immutable terminal history, persisted local start date, and at most one owned task or active-habit target whose deletion is restricted. |
| `goals` | User goals, including deterministically identified Setup-owned rows with archive lifecycle. |
| `habits` | Habit V1 daily, selected-ISO-weekday, or weekly-target cadence plus active/paused/archived manual lifecycle; Setup owns definition/lifecycle for its rows while active rows share execution. |
| `habit_logs` | One explicit `completed` or `skipped` outcome per habit/local date, with checked 1/0 compatibility value; open and missed opportunities are derived and progress/streaks are cadence-aware. |
| `skillset_profiles` | Generated coaching/skill profile snapshots. |
| `recommendations` | Generated recommendations and user statuses; FastAPI can create first deterministic rows after authenticated Intake V1. |
| `notification_preferences` | Reminder/category/quiet-hour configuration plus separate fail-closed in-app delivery consent/version/timestamps and a bounded daily cap. Reminder fields alone grant no delivery. |
| `intake_responses` | Typed Setup history with request identity, optimistic revision, pending/applied state, and structured lifecycle items. |
| `user_state_snapshots` | Compact backend-owned onboarding/daily/weekly state; daily and weekly summaries add Phase 2 Daily State plus Phase 3 explicit habit-outcome/focus facts while remaining deterministic recommendation context. |
| `daily_briefings` | One backend-owned deterministic `daily-briefing-v1` decision per user/profile-local date with strict executable actions, source-snapshot provenance, bounded evidence, and stale detection. |
| `decision_feedback` | Retry-safe append-only feedback for an exact owned briefing action; authenticated owners can read/delete history and FastAPI owns validated writes. |
| `weekly_reviews` | One backend-owned bounded `weekly-review-v1` output per user/completed ISO week with source fingerprint, at most two proposals, owner/admin reads, and service-role writes. |
| `calendar_connections` | One optional consented `ical_file` source per owner with stable connect/disconnect/delete identity and no provider credential. |
| `calendar_imports` | Immutable retry-safe `.ics` import identity, bounded window/counts, and canonical input/request fingerprints. |
| `calendar_events` | Current whitelisted imported event copy with stable single/recurrence identity and explicit imported/read-only provenance. |
| `calendar_request_identities` | Minimal global UUID/owner/connection/operation registry enforcing stable identity across calendar lifecycle mutations; forced RLS and service-role insert/select only, with no content fingerprint. |
| `deadline_plans` | Owner-scoped exam/assignment lifecycle with immutable original estimate/prior credit, one stable managed-task identity after first confirmation, and active/pending revision projections. |
| `deadline_plan_revisions` | Immutable proposed, active, or superseded preparation inputs/results, including proposal-time focus credit, exact remaining/planned/unscheduled totals, source provenance, and lifecycle timestamps. |
| `deadline_plan_blocks` | Bounded immutable dated app-owned preparation reservations for one revision; they remain separate from `schedule_items` and imported calendar events. |
| `deadline_plan_request_identities` | Backend-only global request UUID/owner/plan/operation/payload identity for exact replay and conflict detection; never exposed through Account Export. |
| `coach_requests` | Backend-only retry/lease/terminal ledger. Pending rows store only a SHA-256 message fingerprint; completed rows store the strict response/manifest; deleted rows are content-free tombstones. |
| `coach_usage_events` | Backend-only append-only one-row-per-request outcome/counter ledger retained across conversation deletion and used with request rows for the profile-local daily attempt budget. |
| `coach_memory_selections` | Explicit owner-scoped selection of at most eight eligible `memory_entries` for Coach context, stored separately from memory ownership/content. |

Phase 1 canonical capture upserts one `daily_logs` row per user/date with source
`quick_check_in`. `metadata.capture_version=daily-capture-v2` contains separate
owned `captures.evening` and `captures.morning` objects. Saving one kind replaces
only that object, preserving the other capture and unrelated metadata. Numeric
projection keeps existing consumers compatible: Morning energy takes
precedence, Evening owns mood and stress, and Morning owns sleep. Evening stores
one required primary friction (including `no_major_friction`) plus at most two
unique optional `additional_frictions`; only the primary drives Daily Mode.
Morning stores an independent whole-number `1..10` `sleep_quality` estimate in
its JSON object. Older V2 Morning objects without it remain readable; new
Morning saves require it. No direct compatibility column is added.
New writes omit the retired `gentle_tomorrow` field, while legacy capture
objects containing it remain readable. Rough focus is kept as a structured band
and does not fabricate `focus_minutes`.

After each write Flutter removes the existing `quick_check_in` events linked to
that `daily_log_id` and upserts the explicit current signals with deterministic
ids derived from the daily row and event kind. The resulting set is dynamic and
contains at most mood, energy, stress, and sleep; an Evening-only or
Morning-only day therefore does not create unanswered events. Event metadata
mirrors the relevant capture kind, id, local entry date, capture time, and
bounded context. Sleep quality is mirrored on the existing Morning-origin
energy and sleep events instead of creating a fifth event. Repeated same-day
saves converge without append-only signal
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
rules precede planning/productivity rules. Very low current sleep quality may
select `recover` even with sufficient duration; moderately low quality prevents
`push`.

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
Dashboard/Inbox/Recommendation sources as empty or error according to
their contracts and never substitutes mock rows. Notification routing reads the
existing `action_url`, but only implemented internal paths are enabled; no
notification mutation is inferred from that link allowlist. Notification
Lifecycle V1 later added the separate durable backend-owned
read/unread/dismiss command without broadening direct authenticated table DML.

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

## Phase 7 Scheduled Daily Preparation

Phase 7 adds no migration and no table. The protected FastAPI scheduler reuses:

- `profiles.timezone`, `onboarding_completed_at`, and `role` to select only
  onboarded non-guest profiles and resolve one exact local date from the batch's
  captured timezone-aware UTC run instant;
- the unique `(user_id, scope, period_key)` snapshot identity to create a
  missing daily snapshot without duplicating an existing period; and
- the unique `(user_id, briefing_date)` briefing identity plus persisted source
  snapshot id/time provenance to distinguish missing, stale, and current output.

Normal runs omit `target_date` and use each profile's local date. An explicit
`target_date` is a privileged backfill override for the still-eligible selected
profiles; it does not change ownership or expose the scheduler to Flutter.

Missing prerequisites are created, a briefing whose snapshot provenance changed
is upserted on the same daily identity, and a current snapshot/briefing pair is
left write-free. Invalid profile timezones and snapshot, briefing, or optional
recommendation failures remain isolated per profile with sanitized stage
results. Recommendation generation is disabled by default and, when explicitly
requested, remains deterministic with LLM wording disabled.

The optional `profile_ids` request filter is bounded to 20 UUIDs and remains an
intersection with the same onboarded non-guest query; it does not grant access
to an otherwise ineligible profile. It supports targeted operational retry and
isolated local E2E without introducing a client-visible user selector. The
scheduler token and service-role key remain backend-only and are never Flutter
configuration.

This repository state proves the local persistence contract only. It does not
claim that a remote project has the migrations, profile timezones, token, or
deployed cron wiring configured. Notification Delivery V1 adds only the local
runner and foreground Flutter path; it adds no push/system, background-mobile,
email, browser, Android, snooze, or production scheduling claim.

## Phase 8 Bounded Weekly Review

Phase 8 adds `weekly_reviews` rather than overloading generic weekly snapshots,
recommendations, or daily briefings. Each row owns one `(user_id, period_key)`
identity with exact profile-local Monday/Sunday dates, timezone, bounded
narrative and JSON facts/proposals/evidence/provenance, and the canonical
lowercase SHA-256 source fingerprint used for stale detection.

Authenticated users may select only their own rows; authenticated insert,
update, and delete are not granted. FastAPI uses service-role writes after
bearer-token verification and explicit owner-scoped source queries. RLS is
enabled and forced. Deliberate generation persists derived review output only;
proposal confirmation continues through existing authenticated Habit V1
commands and never grants the client review-table writes.

The existing weekly snapshot is supporting evidence, not a complete historical
ledger. Current task rows cannot recreate undone transitions, and current habit
rows cannot recreate prior cadence/lifecycle definitions. Phase 8 keeps those
limitations explicit, marks affected opportunity math unknown, and does not
infer an adaptation from misses alone. Direct application remains limited to
confirmed manual Habit V1 shrink/pause/archive. Setup-owned changes stay in
Setup; replacement and goal/task/schedule changes remain staged.

## Phase 9 Bounded Calendar File Import

Phase 9 adds dedicated integration tables instead of copying external events
into `schedule_items`. One real authenticated owner may create one consented
`ical_file` connection. Connection alone stores consent and source identity; it
does not parse a file or create an event.

A deliberate backend import stores one immutable `(user_id, request_id)` row
and atomically reconciles the connection's current event copy. Event identity is
derived from connection, exact iCalendar `UID`, and either `single` or the
normalized `RECURRENCE-ID`, so retry, edit, moved occurrence, duplicate, and
cancellation behavior does not create parallel rows. Timed instants and
event-local projections stay separate from exclusive all-day dates. Raw files,
descriptions, attendees, organizer addresses, conferencing data, alarms, and
unknown provider payload are not persisted.

RLS is enabled and forced. Authenticated owners/admins may read the public
connection/event projection; authenticated direct writes are not granted.
FastAPI owns create/import/disconnect/delete after bearer verification, and the
atomic import operation is service-role-only. Composite ownership checks keep
connection/import/event users consistent even under privileged writes.

Disconnect retains the visibly read-only local event copy and rejects another
import. A separate confirmed delete hard-deletes imported events/history while
preserving the minimal connection tombstone and every manual or Setup-owned
schedule row. The schema stores no OAuth/refresh token or provider cursor and
supports no provider write, URL fetch, background sync, or automatic
snapshot/briefing consumption.

`20260713120000_phase_9_calendar_import.sql` creates these three tables and the
service-role-only atomic RPCs `create_calendar_connection_v1`,
`apply_calendar_import_v1`, `disconnect_calendar_connection_v1`, and
`delete_calendar_imported_data_v1`. Authenticated clients receive only the
bounded public connection/event projection and no internal request identities
or source keys.

`20260713143000_phase_9_calendar_request_identity_guard.sql` adds a minimal
global `(request_id, user_id, connection_id, operation)` registry across all
four lifecycle operations. Its backfill aborts instead of reinterpreting an
existing cross-scope collision. The table uses forced RLS, grants service role
only immutable select/insert access, and stores no imported content or content/
source fingerprint. The migration also replaces application-conflict SQLSTATEs
with PostgREST `PT409` and restricts import replay to an exact-input import that
is still connected and current.

## Deadline Planner V1

Deadline Planner V1 persists explicit preparation work separately from imported
calendar rows and ordinary schedule items. The user supplies the exam or
assignment type, deadline, total active-preparation estimate, prior credit, and
session constraints within a 366-day horizon. A deliberate proposal stores one immutable revision and
its deterministic blocks; it does not replace an active revision until an exact
confirm command succeeds.

`deadline_plans` owns the plan lifecycle and immutable original estimate/prior
credit plus separate current/latest revision counters. `deadline_plan_revisions` freezes every proposal's inputs, source and
planning fingerprints, proposal-time completed-focus total, exact remaining,
planned and unscheduled minutes, and activation/supersession provenance.
`deadline_plan_blocks` owns at most 120 bounded dated blocks per revision.
`deadline_plan_request_identities` is the minimal global anti-replay ledger for
proposal, confirm, complete, and cancel operations.

All four tables use forced RLS. Authenticated owners receive only the intended
plan/revision/block read projection and no direct mutation authority. The
request ledger is service-role-only. Backend mutations derive the owner from a
verified bearer, take the shared owner advisory lock, and atomically reconcile
request identity, revisions/blocks, plan projections, and first-confirm task
creation. Composite ownership references prevent cross-owner plan, task,
calendar-event, revision, and block linkage.

`20260719120000_account_preparation_budget_v1.sql` adds nullable
`profiles.daily_preparation_budget_minutes`, constrained to `25..480` in
five-minute increments. Existing null rows retain the per-plan-only behavior.
Application roles may read the owner profile through existing RLS but cannot
write this column. The service-role-only
`set_daily_preparation_budget_v1(uuid,int)` RPC takes the same owner advisory
lock as planner mutations and returns only the exact nullable value.

Proposal calculation subtracts confirmed blocks from other plans on each
profile-local planning date, including earlier reservations on the current
date. The `deadline_plan_blocks_enforce_account_budget` trigger independently
checks the candidate revision plus active other-plan blocks on only that
candidate revision's dates during proposed-to-active transition. It raises a
PostgREST `PT409` conflict without changing the active revision when aggregate
minutes exceed the current profile budget. Lowering a budget never rewrites
existing active rows; the read-only seven-day workload projection reports any
resulting overage for explicit replanning.

The separate `preparation-workload-detail-v1` FastAPI read adds no schema or
grant. It derives the principal from the bearer and explicitly filters
`profiles`, active `deadline_plan_blocks`, and `deadline_plans` by that owner
plus one current-seven-day local date. Authenticated Data API access continues
to use the existing forced owner RLS, while the backend's service-role reads do
not treat that bypass as ownership authority.

The first confirmation creates exactly one planner-managed task with
`task.id = deadline_plan.id`; subsequent revisions keep that identity and may
change only title/deadline/update time while it remains open. Generic Task
mutations/editor paths reject the managed source; focus may target the open task,
and only plan complete/cancel owns its atomic matching terminal projection. A
completed linked focus session after activation contributes only derived
progress and never completes a task or plan. Imported events remain read-only:
one explicitly selected current event may be pinned as proposal provenance,
and optional busy-time use may read owner-scoped busy rows only from a
connected, non-deleted source's non-null current import,
but no planner operation changes an import, `schedule_items`, or a source
calendar.

Account Export V1 includes bounded owner rows from `deadline_plans`,
`deadline_plan_revisions`, and `deadline_plan_blocks`; it names
`deadline_plan_request_identities` as an omitted backend anti-replay ledger.
Full-account deletion cascades all four tables. See
`docs/deadline-planner-v1-contract.md` for the exact HTTP, revision, progress,
source, and non-claim boundary.

## Planner V1

`20260722120000_planner_v1.sql` adds the central planning persistence without
migrating or silently scheduling existing Tasks, Habits, or Deadline Plans.
`planner_preferences` stores only the explicit owner choice to use current
imported-calendar busy time. `planner_action_plans` and immutable
`planner_action_plan_revisions` own staged and active Task/Habit plans;
`planner_task_blocks` stores dated reservations and `planner_habit_slots`
stores stable weekly slots. `planner_commitments` owns manually entered
one-off or weekly authoritative busy time. `planner_request_identities` is the
backend-only global retry ledger.

No additional timetable table is required for bounded Setup commitments. Their
optional inclusive semester dates are part of Setup-owned `schedule_items`
metadata and are reconciled atomically with the rest of the Setup projection.
Planner, Deadline Planner, Today, and snapshots use the same date-applicability
rule. Calendar import remains separate and optional.

All seven tables use forced RLS. Authenticated owners receive read-only access
to preferences, plans, revisions, blocks, slots, and commitments; they receive
no direct mutation access and no ledger access. Service-role-only,
owner-locked RPCs update preferences, stage immutable proposals, atomically
confirm or cancel a revision, and create/update/archive commitments. Confirm
rechecks the target version, current calendar-import identity, planning
fingerprint, and competing Planner/Preparation/Setup/calendar reservations.
A stale preview raises `PT409` and leaves the active revision unchanged.

Task completion/cancellation and Habit pause/archive release future Planner
reservations through guarded lifecycle triggers. Restore/undo does not revive
released slots. The Deadline Planner activation trigger also treats confirmed
Planner reservations and manual commitments as busy time. Account Export
includes the six owner-content tables and explicitly omits the retry ledger.
See `docs/planner-v1-contract.md` for the full HTTP, availability, Today V2,
and non-automation boundary.

## Phase 10 Controlled Coach

`20260713200000_phase_10_controlled_coach.sql` adds
`coach_requests`, `coach_usage_events`, and `coach_memory_selections`, then
extends `coach_messages` with nullable `request_id` and `contract_version` so
legacy rows remain valid while new `coach-message-v1` rows form exactly one
bounded user/assistant pair per completed request. The request table owns global
retry identity, one pending request per owner, a bounded lease, configured
provider/model/prompt/context truth, strict response/manifest/error JSON, and
content-free deletion tombstones. A pending request stores the message
fingerprint only; the full message is written only as part of atomic successful
completion.

The append-only usage table stores one completed, failed, or deterministic
safety-redirect outcome per request with bounded byte/code-point counters. The
request and usage rows remain after history deletion, so delete cannot restore
the profile-local daily request allowance or permit an old request id to be
reused with different content. History deletion removes all owner
`coach_messages`, clears stored response/context/error/fingerprint data, and
marks request rows deleted. It rejects a still-live request and first
terminalizes an expired lease.

Memory selection uses a composite `(memory_id, user_id)` ownership foreign key,
an owner-level advisory lock, and a maximum of eight rows. It excludes every
`type='preference'` memory because current Intake hidden context and coaching
style share that type without a stable sensitivity discriminator. Selection
never changes the underlying memory row or its Setup metadata.

RLS is forced on the new tables plus hardened `coach_messages` and
`memory_entries`. Authenticated users receive owner/admin SELECT only for
messages, memories, and selections; they receive no direct request, usage,
message, memory-selection, or memory-content mutation grant from this migration.
Service role owns the exact claim, atomic complete, fail, selection, and
history-delete RPCs. All RPC execute grants are revoked from `public`, `anon`,
and `authenticated`.

`20260713213000_phase_10_coach_lock_order_guard.sql` is a non-destructive
follow-up. It renames the tested claim/complete/fail bodies to uncallable inner
functions, then recreates the public service-role-only RPC signatures as
wrappers that acquire the owner advisory lock first. History deletion already
uses that owner-first order. The wrapper preserves the exact transaction
contracts while preventing a completion from holding a request row lock and
waiting on an owner lock held by a concurrent claim or deletion. Real local
PostgreSQL parallel claim/completion/deletion smokes completed on 2026-07-13
without deadlock or timeout and converged on the expected message, usage, and
deletion outcomes.

`20260713220000_phase_10_coach_safety_provenance_guard.sql` extends the exact
persisted response validator with `provenance.provider_called`. A model response
must record `true`; deterministic safety copy records whether it bypassed the
provider (`false`) or replaced provider output (`true`).

`20260713223000_phase_10_profile_privilege_guard.sql` makes profile identity
backend-owned. Application roles cannot insert a profile or change `role` or
`auth_provider`; authenticated updates are reduced to named non-identity
projection columns. `20260713224500_phase_10_role_authority_guard.sql` makes
`private.current_app_role()` read only canonical `profiles`, removes mutable
legacy `"User"` fallback authority, and revokes authenticated profile deletion.
`20260713230000_phase_10_onboarding_eligibility_guard.sql` additionally revokes
authenticated updates to `onboarding_completed_at` and blocks application-role
identity/eligibility mutation in the profile trigger. Service role and the
service-role-only atomic Intake apply RPC retain backend projection authority.

## V1 Account Deletion

`20260713233000_v1_account_delete.sql` adds one
`delete_account_v1(uuid, text)` function. Execute is revoked from `public`,
`anon`, and `authenticated` and granted only to `service_role`. The FastAPI
account route may call it only after deriving the owner from a verified bearer
principal and receiving exact `DELETE` confirmation.

The RPC takes the existing Intake, Calendar, and Coach owner advisory locks in
fixed order, pre-locks Calendar request identities before their connection rows,
and locks the matching `auth.users` row. Phase 3 intentionally uses
`ON DELETE RESTRICT` from focus history to task/habit targets, so the full-account
transaction deletes only that owner's `focus_sessions` first. Deleting the Auth
user then activates the canonical `auth.users -> profiles -> owned tables`
cascade. A missing Auth user and a completed deletion have distinct exact JSON
results; success additionally requires that the profile no longer exists.
Normal task/habit lifecycle and deletion constraints are unchanged.

The same migration gives new canonical and legacy Auth profile projections a
UTC default without rewriting existing users, removes authenticated direct
timezone updates, freezes all 14 known CamelCase tables against application-role
insert/update/delete/truncate, and makes `notifications`, `ai_insights`,
`recommendations`, and `skillset_profiles` authenticated-read/service-write
projections. These grants prevent an old JWT from repopulating legacy owner rows
after deletion and avoid exposing writes that the Flutter product does not own.

## Application Table Privilege Guard

`20260714103000_application_table_privilege_guard.sql` closes unintended
table-level authority across all 30 repo-owned canonical product and ledger
tables. `public` and `anon` lose every table privilege. `authenticated` loses
`TRUNCATE`, `REFERENCES`, and `TRIGGER`, which RLS does not safely substitute
for, while each table's intended `SELECT`/`INSERT`/`UPDATE`/`DELETE` grants stay
intact. The four backend-owned projections `notifications`, `ai_insights`,
`recommendations`, and `skillset_profiles` are reaffirmed as authenticated
read-only. Any retained subset of the 14 CamelCase legacy tables remains
application-role mutation-frozen.

The migration also changes default privileges for future public tables created
by the repository migration role `postgres`: `public` and `anon` default to no
table authority, and authenticated future grants exclude `TRUNCATE`,
`REFERENCES`, and `TRIGGER`. Other creators' defaults and service-role defaults
are deliberately not rewritten. Execute on `handle_new_user()` and
`handle_new_auth_user()` is revoked from application roles and `service_role`,
preventing those security-definer functions from being attached to another
table. Their already-installed `auth.users` triggers are not removed and keep
their normal firing behavior.

A child-side `(notification_id, user_id)` index supports Notification-ledger
cascades. Six timestamp-order checks cover `notifications` and
`notification_action_requests` with `NOT VALID`: PostgreSQL enforces them for
new or updated rows, but the migration neither scans nor claims validation of
pre-existing remote rows. Legacy cleanup and later constraint validation remain
separate evidence-driven work.

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

`20260712064836_phase_4_daily_briefings.sql` creates one backend-owned
`daily_briefings` row per `(user_id, briefing_date)`, bounded JSON checks,
authenticated owner/admin reads, service-role writes, forced RLS, and the index
used for recent owner-scoped reads.

`20260712190000_phase_6_decision_feedback.sql` creates retry-safe
`decision_feedback` history with unique `(user_id, request_id)`, bounded exact
action/context fields, authenticated owner read/delete access, service-role
writes, forced RLS, and indexes for the deterministic 28-day ranking window.

Phase 7 adds no migration after Phase 6. Scheduled preparation relies on the
existing profile timezone and the Phase 2/4 unique snapshot and briefing
identities described above.

`20260712210000_phase_8_weekly_reviews.sql` creates one backend-owned
`weekly_reviews` row per `(user_id, period_key)`. Checks require the exact ISO
period derived from a Monday `week_start`, a Sunday `week_end`, bounded timezone
and narrative, `insufficient|partial|sufficient` quality, bounded JSON objects,
at most two proposals, at most 40 evidence references, and one lowercase
64-character hexadecimal source fingerprint. Authenticated owners/admins have
SELECT only; service role owns writes; RLS is enabled and forced.

`20260712211500_phase_8_weekly_review_provenance_guard.sql` replaces the initial
provenance check non-destructively. It requires the deterministic engine,
`weekly-review-v1`, `baseline=none`, `llm_used=false`, bounded evidence-window
and limitations containers, source snapshot fields, and the exact matching
source fingerprint.

`20260713120000_phase_9_calendar_import.sql` creates the bounded Phase 9
connection/import/event schema and its four service-role-only atomic RPCs.
Forced RLS, column-level grants, composite owner foreign keys, and terminal
request identities keep authenticated reads bounded and all mutations behind
FastAPI.

`20260713143000_phase_9_calendar_request_identity_guard.sql` non-destructively
backfills and enforces one global minimal calendar request identity, makes the
registry service-role insert/select only under forced RLS, returns reliable
`PT409` application conflicts, and prevents replay of a superseded,
disconnected, or deleted import.

`20260713200000_phase_10_controlled_coach.sql` creates the bounded Coach
request/usage/selection schema, adds the request-linked V1 message contract,
hardens memory/message grants and forced RLS, and installs service-role-only
`claim_coach_request_v1`, `complete_coach_request_v1`,
`fail_coach_request_v1`, `set_coach_memory_selection_v1`, and
`delete_coach_history_v1` RPCs. Claim and owner advisory locks enforce exact
replay, one active request, lease expiry, and the profile-local daily limit;
completion atomically writes the validated turn and usage event; delete retains
content-free request tombstones and usage rows.

`20260713213000_phase_10_coach_lock_order_guard.sql` keeps the public Coach RPC
signatures and service-role-only grants but places the owner advisory lock in
front of the existing claim/complete/fail bodies, aligning them with history
delete and removing inverse lock ordering.

`20260713220000_phase_10_coach_safety_provenance_guard.sql` makes
`provider_called` a required boolean in persisted `coach-response-v1`
provenance, preserving the distinction between pre-provider and post-provider
deterministic safety redirects.

`20260713223000_phase_10_profile_privilege_guard.sql` blocks application-role
profile insertion and identity-field mutation while narrowing authenticated
updates to explicit non-identity columns.

`20260713224500_phase_10_role_authority_guard.sql` removes the legacy `"User"`
authorization fallback and authenticated profile deletion.

`20260713230000_phase_10_onboarding_eligibility_guard.sql` makes
`profiles.onboarding_completed_at` backend-owned, preserving service-role and
atomic Intake RPC projection while rejecting application-role eligibility
changes.

`20260713233000_v1_account_delete.sql` adds the owner-locked permanent-account
RPC and freezes backend-owned projections and known legacy tables against
application-role mutation.

`20260714100000_notification_lifecycle_v1.sql` adds `read_at` and
`dismissed_at`, consistent lifecycle checks, the service-role-only global
`notification_action_requests` ledger, and the owner-locked
`apply_notification_action_v1` RPC. Authenticated users retain owner/admin
SELECT only; direct application-role Notification DML remains revoked.

`20260714103000_application_table_privilege_guard.sql` removes unintended
application-role table authority across the complete repo-owned schema,
hardens optional legacy tables and future `postgres` public-table defaults,
prevents reuse of the installed Auth trigger functions, adds the
Notification-ledger child index, and enforces six new/updated-row timestamp
ordering checks without validating historical rows.

`20260714110000_account_export_lifestyle_entries_grant.sql` restores only the
service-role read grant required by the existing Account Export table set.

`20260714130000_notification_delivery_v1.sql` adds separate fail-closed in-app
consent, settings request identity, category/quiet/cap fields, deterministic
generation identity/provenance, an at-most-once foreground receipt, and three
owner-locked service-role-only RPCs. Authenticated users keep owner SELECT but
cannot mutate delivery settings or generated notifications directly.

`20260714143000_notification_delivery_settings_guard.sql` adds a SHA-256
fingerprint over the complete Settings request, including its expected
revision. A row trigger invalidates that replay identity when Intake Setup
changes the shared preference projection and prevents Setup's earlier captured
timestamp from regressing `updated_at` below either the prior revision or
retained consent timestamps.

`20260719120000_account_preparation_budget_v1.sql` adds the optional explicit
profile-local daily preparation capacity and its owner-locked setter.

`20260722120000_planner_v1.sql` adds the seven forced-RLS Planner tables,
service-role-only owner-locked preference/action-plan/commitment RPCs,
lifecycle release triggers, and the Deadline Planner reservation guard. It
does not migrate or schedule existing targets.

`20260722234000_setup_commitment_validity_guards.sql` keeps the existing Planner
and Deadline Planner confirmation RPCs aligned with inclusive optional Setup
semester bounds. It adds one private non-executable predicate and no table or
column; guarded replacement aborts if the installed RPC definitions drifted.

## Local Verification Workflow

For local Supabase-backed testing, the reset should complete through:

```text
20260722234000_setup_commitment_validity_guards.sql
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

This default starts/reuses the local stack, inspects
`supabase migration list --local`, and fails if repository files and database
history differ. It never applies SQL automatically. If the histories differ,
review the pending SQL and affected local rows before opting in:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

Pending migrations may change or delete local rows. Avoid describing this path
as non-destructive merely because it does not reset the full database. The
script verifies migration history again after the explicit application.

For local Supabase reset and migration verification:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The reset form should apply all migrations through
`20260719120000_account_preparation_budget_v1.sql`; expected legacy-table
skip notices may be emitted for missing CamelCase tables. Use reset when proving
the full migration/backfill/constraint chain from a fresh local database, not
merely because a reviewed migration is pending.

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
- Open Weekly Review, confirm latest GET is read-only, deliberately generate one
  completed ISO week, and inspect one exact `weekly_reviews` identity. Cancel a
  proposal without writes; confirm an eligible manual Habit V1 change; verify
  Setup ownership is untouched and the old review becomes stale until refresh.
- Open Calendar integration, create the consented file source, deliberately
  import a bounded `.ics` file, page through events, disconnect while retaining
  the visibly imported/read-only copy, then delete that local copy and confirm
  `schedule_items` is unchanged.
- Open Coach with the fake provider, confirm read-only capability/history/
  memory loading, explicitly select one eligible memory, send one bounded turn,
  replay its request id, delete the conversation, and confirm messages are gone
  while request tombstones and usage remain. Confirm guest/mock makes no Coach
  request.
- Open Inbox (`/alerts`); mark one row read/unread, dismiss it, reload, and do
  not infer notification delivery from stored rows or preferences.

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
include terminal-focus `updated_at` mutation. Phase 8/9 source adds weekly review
and calendar import. Phase 10 source starts FastAPI with the deterministic fake
provider and adds bounded Coach persistence, replay, safety, memory, history,
RLS, UI, and guest-zero-call assertions. The combined Phase 3 through Phase 9
smoke first passed in the Phase 9 implementation checkout. In the 2026-07-13
current checkout, a focused Phase 10 rerun and the subsequent full combined
journey passed non-destructively against local Supabase with the deterministic
fake provider. This establishes neither remote migration/RLS state nor
production readiness. On 2026-07-19 the reviewed account-wide preparation-
capacity migration was explicitly applied locally without a reset; history
matched through `20260719120000_account_preparation_budget_v1.sql`, the non-reset
preflight passed all `601` Flutter tests, and the full browser journey reported
`E2E browser smoke passed for e2e-1784448992@example.test`. That remains local
evidence and establishes no remote database state. Later changes must establish
a new full pass. Do not run
destructive reset commands against a remote database.

For manual local product exploration, `npm run seed:demo` creates repeatable
local-only Auth users and app rows for student, worker, and recovery scenarios.
It replaces only those three named demo accounts through the full-account
cascade, so immutable retry and usage rows are reset without weakening their
normal contracts. The seed script uses the local Supabase service-role key from
`supabase status -o env`, refuses non-local API URLs, and writes typed applied
Setup revisions with stable request ids and empty optional Setup-owned
collections. It then uses the existing backend services to enrich and verify
the student account across Today, Weekly Review, Calendar Import, Deadline
Planner, notification delivery, and Coach. It does not change the schema or
relabel the separately seeded `demo_seed` objects as Setup-owned.

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

The latest migration is
`20260722234000_setup_commitment_validity_guards.sql`. It adds no schema object
beyond one private helper and keeps Planner/Deadline confirmation aligned with
optional inclusive Setup semester bounds. The preceding
`20260722120000_planner_v1.sql` adds additive forced-RLS Planner preference,
immutable Action Plan revision, Task block, Habit slot, manual commitment, and
retry-ledger persistence plus service-only owner-locked mutations. Existing
targets remain unchanged. The earlier
`20260719120000_account_preparation_budget_v1.sql` adds the explicit optional
daily preparation-capacity rule. Earlier,
`20260714143000_notification_delivery_settings_guard.sql` made the
Notification Delivery Settings identity request-exact across the
shared Intake Setup writer and enforced monotone consent-safe revisions. The
preceding `20260714130000_notification_delivery_v1.sql` adds explicit foreground
consent and deterministic generated-notification/receipt fields without a new
table, so Account Export V1's table count is unchanged. Its settings,
generation, and delivery RPCs are service-role-only and revalidate current
owner state under the advisory lock. The preceding
`20260714110000_account_export_lifestyle_entries_grant.sql` grants only
`service_role` `SELECT` on the legacy-but-canonical `lifestyle_entries` table,
which Account Export V1 must read even when it has no rows. It does not change
anon or authenticated application authority. The preceding
`20260714103000_application_table_privilege_guard.sql` closes unintended
application-role table privileges across every repo-owned product and ledger
table, makes `anon` fail closed, preserves intended authenticated DML while
removing `TRUNCATE`/`REFERENCES`/`TRIGGER`, and keeps backend projections
read-only. It also freezes optional legacy tables, hardens future `postgres`
public-table defaults, prevents reuse of installed Auth trigger functions,
adds the Notification-ledger lookup index, and protects new/updated timestamp
ordering without claiming historical validation. The preceding
`20260714100000_notification_lifecycle_v1.sql` adds exact stored-Inbox
read/unread/dismiss tombstones and retry identity; its lifecycle remains
separate from the later generation/delivery path. The preceding
`20260713233000_v1_account_delete.sql` adds the
confirmed service-role-only transactional full-account cascade while
preserving ordinary Phase 3 target-history restrictions. The preceding
`20260713230000_phase_10_onboarding_eligibility_guard.sql`, together with the
profile privilege and canonical role-authority guards immediately before it,
makes profile identity, application role, and onboarding eligibility
backend-owned, removes legacy-role fallback, and preserves the atomic Intake
RPC as the onboarding projection path. The preceding safety-provenance guard
requires exact provider-call truth for persisted Coach safety redirects. The
earlier lock-order guard gives Coach claim/complete/fail/history-delete one
owner-first advisory lock order without changing their public signatures or
service-role-only boundary; the base Phase 10 migration adds retry-safe bounded
Coach request, usage, selection, message, deletion, grant, and forced-RLS
contracts.
The earlier
`20260713143000_phase_9_calendar_request_identity_guard.sql` adds the global
minimal calendar request registry, forced RLS with service-role insert/select
only, reliable `PT409` conflicts, and current-only import replay. The preceding
`20260713120000_phase_9_calendar_import.sql` creates the dedicated bounded
calendar connection/import/event schema, restricted authenticated reads,
service-role writes, and four atomic lifecycle RPCs. The earlier
`20260712211500_phase_8_weekly_review_provenance_guard.sql` completes the
bounded backend-owned weekly-review schema with strict deterministic-provenance
and matching-fingerprint checks. The Phase 8 table migration creates
one review per owner/ISO period with exact week checks, forced RLS,
authenticated owner/admin reads, and service-role writes.
The preceding Phase 6 migration creates owner-scoped `decision_feedback`
history with a unique `(user_id, request_id)`, exact bounded feedback/context
fields, read/delete RLS for authenticated owners, service-role writes, and
indexes for the 28-day ranking window. The preceding Phase 4
migration creates one owner-scoped `daily_briefings` row per user/local date
with bounded action/evidence JSON, explicit authenticated read and service-role
write grants, forced RLS, and owner/admin select plus service-role policies. The
preceding Phase 3
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
persisted reasons. Phase 7 adds no schema object; it prepares the existing
snapshot and briefing identities by profile-local date. Phase 8 persists only
derived weekly review output and reuses existing Habit V1 mutations after
explicit confirmation. Phase 10 adds conversational explanation without making
any Coach suggestion executable or changing the deterministic briefing loop.
