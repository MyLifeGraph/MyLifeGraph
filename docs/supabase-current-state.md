# Supabase Current State

This document captures the repository state, not the live remote Supabase
project state. The repo does not contain credentials, so a live remote database
must be inspected through the Supabase dashboard or CLI by someone with access.

This file is the sole current owner of the latest repository migration filename
and reset boundary. Machine-checked cross-document contract versions, canonical
code sources, and documentation owners are declared in
`docs/current-contracts.json`.

The current Setup/Goal/friction cleanup and compatibility boundary is recorded
in `docs/setup-personalization-retirement-contract.md` and migration
`20260725120000_retire_setup_goals_and_friction.sql`.
The later deterministic learning boundary is recorded in
`docs/personal-learning-v1-contract.md` and migrations
`20260726120000_personal_learning_v1.sql`,
`20260726150000_learned_focus_planning_v1.sql`,
`20260726170000_recommendation_refresh_v2.sql`,
`20260726180000_learned_focus_planning_rpc_guard.sql`,
`20260726190000_planning_confirmation_timestamp_guard.sql`, and
`20260726200000_learned_timing_setup_fallback_provenance.sql`.
The later bounded Coach context-ledger extension is migration
`20260728120000_coach_longitudinal_context_v1.sql`. The current free read-only
Coach agent persistence is the additive migration
`20260728160000_free_read_only_coach_agent_v1.sql`.
The current repository boundary then adds write stabilization and
observation-ordered persistence through
`20260729130000_observed_projection_persistence.sql`, followed by rolling-safe
English-only Coach prompt provenance in
`20260729160000_coach_english_prompt_v2.sql`, and immutable scheduled-Focus
provenance plus V2 lifecycle RPCs in
`20260802083219_focus_schedule_sources_v2.sql`. The current boundary is the
contract-neutral privileged-function cleanup in
`20260802111518_privileged_function_lint_cleanup.sql`.

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
| `profiles` | Canonical auth profile projection. Identity/authority (`role`, `auth_provider`) and onboarding eligibility are backend-owned; `setup_revision`, `timezone_revision`, and `preparation_budget_revision` are monotonic backend guards, and timezone/preparation-budget writes require revisioned service-role RPCs. |
| `daily_logs` | One canonical daily row whose V4 metadata owns separate Evening/Morning captures plus direct nullable numeric Dashboard projections; authenticated callers have owner reads but no direct DML. |
| `behavioral_events` | Granular AI signal stream; the Capture RPC transactionally replaces only the dynamic deterministic maximum of four `quick_check_in` events linked to its `daily_logs` row. Other sources are preserved and application roles have no direct DML. |
| `daily_capture_request_identities` | Service-role-only exact payload/result anti-replay ledger for branch-local `daily-capture-write-v1`; omitted from Account Export. |
| `account_setting_request_identities` | Service-role-only operation/payload/result anti-replay ledger for revisioned timezone and preparation-budget writes; omitted from Account Export. |
| `tasks` | Owner-scoped executable tasks with create/edit/complete/postpone/cancel/restore/undo, optional 5-480 minute estimates, and explicit completion/cancellation timestamps. |
| `notifications` | Authenticated read-only Inbox projection with backend-owned read/unread/dismiss lifecycle plus optional deterministic generation key/category/local-date/provenance and foreground receipt time. A stored row alone does not prove delivery. |
| `notification_action_requests` | Service-role-only exact retry/result ledger for `notification-lifecycle-v1`; it contains identities and lifecycle projections, not notification copy. |
| `schedule_items` | Setup-owned confirmed fixed commitments plus preserved manual/other-source dashboard schedule rows. Setup-owned metadata may add inclusive optional `valid_from`/`valid_until` semester dates; older/undated rows remain unbounded. |
| `ai_insights` | Insights list. |
| `coach_messages` | Bounded validated user/assistant history linked to a retry-safe backend request. Authenticated owners can read; only FastAPI inserts/deletes turns. V3 answers use `coach-response-v2`; legacy and fixed-mode V1/V2 rows remain readable. |
| `memory_entries` | Durable Setup/manual memory content. Authenticated owners can read it. Current free-question Coach snapshots may include sanitized owner memory detail as untrusted data; the old explicit selection projection remains only for V1/V2 compatibility and never changes content ownership. |
| `focus_sessions` | Real one-active-session Deep Work lifecycle with bounded planned/measured duration, fully immutable terminal history, persisted local start date, and at most one owned task or active-habit target whose deletion is restricted. |
| `focus_session_schedule_sources` | Immutable optional origin for a scheduled Focus session: one owned Deadline or Planner Task block plus its original Focus interval and recovery snapshot. Forced owner-read RLS; direct application DML is forbidden and source deletion is restricted until Focus/account deletion removes the provenance. |
| `focus_session_reflections` | At most one editable `focus-reflection-v1` rating per owned terminal Focus session, with two bounded scores and up to two controlled obstacles. Forced owner RLS; account deletion cascades it. |
| `learning_preferences` | One revisioned `learning-preferences-v1` projection per owner for prompt, analysis, and separately gated learned-Planning choices. Learned planning cannot remain enabled while analysis is disabled. |
| `learning_request_identities` | Backend-only global retry/result ledger for exact preference updates and confirmed reflection-history clearing; omitted from Account Export. |
| `goals` | Retained compatibility and Account Export storage. Setup-owned rows are archived; manual/foreign-managed rows are preserved, and no active product service evaluates them. |
| `habits` | Habit V1 daily, selected-ISO-weekday, or weekly-target cadence plus active/paused/archived manual lifecycle; Setup owns definition/lifecycle for its rows while active rows share execution. |
| `habit_logs` | One explicit `completed` or `skipped` outcome per habit/local date, with checked 1/0 compatibility value; open and missed opportunities are derived and progress/streaks are cadence-aware. |
| `skillset_profiles` | Generated coaching/skill profile snapshots. |
| `recommendations` | Generated recommendations and user statuses from explicit/scheduled runtime refresh; Intake V1 completion does not generate them. A deliberate refresh atomically retires the prior current `new` set while preserving historical rows. |
| `notification_preferences` | Reminder/category/quiet-hour configuration plus separate fail-closed in-app delivery consent/version/timestamps and a bounded daily cap. Reminder fields alone grant no delivery. |
| `intake_responses` | Typed Setup history with request identity, optimistic revision, pending/applied state, and structured routine/commitment/Study lifecycle items. Retired personalization keys are stripped. |
| `study_setup_profiles` | Optional `study-setup-v1` projection from the current applied Intake revision: focus/recovery rhythm, ordered preparation-item definitions, current/next semester, and Setup revision. Forced owner-read RLS; only the backend writes. |
| `user_state_snapshots` | Compact backend-owned onboarding/daily/weekly state with `source_observed_at`; a V2 persistence RPC lets only a later-observed run replace the period projection. |
| `daily_briefings` | One backend-owned deterministic `daily-briefing-v1` decision per user/profile-local date with strict executable actions, source-snapshot provenance, bounded evidence, and stale detection. |
| `decision_feedback` | Retry-safe append-only feedback for an exact owned briefing action; authenticated owners can read/delete history and FastAPI owns validated writes. |
| `weekly_reviews` | One backend-owned bounded `weekly-review-v1` output per user/completed ISO week with source fingerprint, `source_observed_at`, at most two proposals, owner/admin reads, and owner-locked V2 persistence. |
| `calendar_connections` | One optional consented `ical_file` source per owner with stable connect/disconnect/delete identity and no provider credential. |
| `calendar_imports` | Immutable retry-safe `.ics` import identity, bounded window/counts, profile timezone revision, and `not_imported|current|profile_timezone_changed|disconnected|deleted` planning status. |
| `calendar_events` | Current whitelisted imported event copy with stable single/recurrence identity and explicit imported/read-only provenance. |
| `calendar_request_identities` | Minimal global UUID/owner/connection/operation registry enforcing stable identity across calendar lifecycle mutations; forced RLS and service-role insert/select only, with no content fingerprint. |
| `deadline_plans` | Owner-scoped exam/assignment lifecycle with immutable original estimate/prior credit, one stable managed-task identity after first confirmation, and active/pending revision projections. |
| `deadline_plan_revisions` | Immutable proposed, active, or superseded preparation inputs/results, including proposal-time focus credit, exact remaining/planned/unscheduled totals, source provenance, optional Study Setup revision/recovery truth, additive learned/setup timing evidence, and lifecycle timestamps. |
| `deadline_plan_blocks` | Bounded immutable dated app-owned preparation reservations for one revision, with focus end and full recovery-reserved end kept separate; they remain separate from `schedule_items` and imported calendar events. |
| `deadline_plan_request_identities` | Backend-only global request UUID/owner/plan/operation/payload identity for exact replay and conflict detection; never exposed through Account Export. |
| `planner_preferences` | Owner choice for using the current imported-calendar busy projection in deterministic Planner and Preparation availability. |
| `planner_action_plans` | Owner-scoped staged/active Task or Habit plan identity and lifecycle. |
| `planner_action_plan_revisions` | Immutable Planner proposal/activation history, including optional Task Study Setup revision/recovery truth and additive learned/setup timing evidence. |
| `planner_task_blocks` | Dated Planner Task focus reservations with a separate full recovery-reserved end. |
| `planner_habit_slots` | Stable recurring wall-clock slots for planned Habit occurrences; Study rhythm does not apply. |
| `planner_commitments` | Authoritative owner-created one-off or weekly fixed commitments. |
| `planner_request_identities` | Backend-only global retry ledger for Planner preferences, plans, and commitments; omitted from Account Export. |
| `coach_requests` | Backend-only retry/lease/terminal ledger. V1 remains `today` with `{}` and V2 stores fixed scope parameters; V3 replay binds only owner/request/message and persists exact backend-derived evidence, bounded agent trace/tool count, and service-tier truth on completion. Deleted rows are content-free tombstones and clear V3 detail without clearing usage. |
| `coach_usage_events` | Backend-only append-only one-row-per-request outcome/counter ledger retained across conversation deletion and used with request rows for the profile-local daily attempt budget. |
| `coach_memory_selections` | Legacy explicit selection of at most eight eligible memories for fixed-context V1/V2 Coach. It remains readable for compatibility but current V3 Flutter does not call or depend on it. |

Canonical authenticated Capture uses `apply_daily_capture_branch_v1` to merge
one `daily_logs` row per user/date with source `quick_check_in`.
`metadata.capture_version=daily-capture-v4` contains separate owned
`captures.evening` and `captures.morning` objects. Saving one kind compares and
replaces only that object, preserving the other capture and unrelated metadata.
Numeric
projection keeps existing consumers compatible: Morning energy takes
precedence, Evening owns mood and stress, and Morning owns sleep. Evening stores
no primary/additional friction fields. It requires one planned local sleep
clock and one bounded target. Morning stores aware estimated start/wake
instants, their exact derived minutes/compatible hours, the target used,
optional source Evening id, and an independent whole-number `1..10`
`sleep_quality` estimate. V2/V3 objects remain readable and may remain explicit
compatibility branches until edited. No direct compatibility or sleep-profile
column is added.
New writes omit the retired `gentle_tomorrow` field, while legacy capture
objects containing it remain readable. Capture does not ask for a focus band
and does not fabricate `focus_minutes`.

After each write Flutter removes the existing `quick_check_in` events linked to
that `daily_log_id` and upserts the explicit current signals with deterministic
ids derived from the daily row and event kind. The resulting set is dynamic and
contains at most mood, energy, stress, and sleep; an Evening-only or
Morning-only day therefore does not create unanswered events. Event metadata
mirrors the relevant capture kind, id, local entry date, capture time, and
bounded context. Sleep quality is mirrored on the existing Morning-origin
energy and sleep events instead of creating a fifth event. Raw planned/
estimated clocks, target, and source Evening id are not mirrored; only the
derived Sleep value leaves Daily Log metadata. Repeated same-day
saves converge without append-only signal
history. Existing columns, grants, and RLS policies are sufficient, so Capture
V4 and the derived read-only Exam-Week Outlook add no schema migration.

Guest capture stores the same ownership model as V4 JSON in
`shared_preferences`, still reads and sanitizes V1/V2/V3 guest JSON, and keeps the
existing best-effort check-in migration into a real non-demo account. Guest Setup remains
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
`signals.daily_state`, with contract version `explainable-daily-state-v2`.
`summary.daily_state` contains target date, `push|steady|recover|plan` mode,
`missing|partial|current|stale` quality, per-kind freshness, bounded structured
context, current risk/reason codes, readable explanations, load guidance, and
deterministic provenance. `signals.daily_state` contains generated time,
provenance rows, field-level risk/reason evidence, and bounded quality-issue
codes. Capture free text is excluded.

Daily State always uses a fixed seven-day lookback even when the caller requests
a different statistics window. Evening is current from the target date or
previous date; Morning is current only from the target date. Strict V2/V3/V4
capture parsing validates V4 branch compatibility and sleep intervals, ignores
friction, and does not fall back to projected columns after a malformed
structured marker. Legacy numeric rows are accepted conservatively only when no
structured capture marker exists. Missing, partial, or stale evidence cannot
produce `push`; current `push` also requires an active Task, and recovery rules
precede planning/productivity rules. Very low current sleep quality may select
`recover` even with sufficient duration; moderately low quality prevents
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
`explainable-daily-state-v2` classifier, or `snapshot-aggregator-v1`. Successful
real task, habit, and focus writes request snapshot refresh best-effort; they do
not generate recommendations or call an LLM. Focus start persists
`metadata.entry_date`; all focus transitions refresh the persisted start day.
Backend filtering prefers that local date over the deterministic UTC
`started_at` fallback shared with Flutter after a widened read. Habit-log and
focus-session inputs paginate in stable 1,000-row pages through the complete
requested window. See
`docs/phase-3-executable-actions-contract.md` for command, validation, and
failure semantics.

## Personal Learning V1

`20260726120000_personal_learning_v1.sql` adds one reflection primary key per
Focus session and a composite `(focus_session_id, user_id)` foreign key back to
the terminal session owner. A locked trigger rejects active sessions and
cross-owner linkage without changing terminal Focus immutability. Rating,
contract-version, distinct-obstacle, obstacle-count, and timestamp checks are
enforced at the database boundary. Forced RLS grants authenticated owners only
their intended reflection CRUD; `anon` and cross-owner reads/writes fail
closed.

The same migration adds default-on reflection prompting and pattern analysis,
default-off learned Planner use, a monotone revision, and a check that Planner
use implies analysis. Service-role-only owner-locked RPCs bind request ids to
the full preference payload or confirmed `CLEAR` command and return exact
replays. `learning_request_identities` contains no ratings and remains hidden
from authenticated users and Account Export.

`20260726150000_learned_focus_planning_v1.sql` adds only immutable proposal
provenance columns: `setup|learned_personal_pattern`, the fixed local window,
evidence count/date interval/fingerprint, and Setup-fallback state. Planner and
Deadline confirmation still recheck every prior revision, availability,
budget, calendar, recovery, and Study rule. A preview that claims learned
timing also requires the current account permission; changed evidence alone
does not reinterpret it. Existing active revisions and blocks are backfilled as
Setup timing and never moved.

`20260726170000_recommendation_refresh_v2.sql` installs the service-role-only
atomic replacement RPC used by a deliberate deterministic refresh. It marks
the prior current `new` rows as dismissed history, inserts the verified new
set, and leaves accepted or already historical rows intact. Empty output
therefore truthfully clears the current feed without deleting history.

`20260726180000_learned_focus_planning_rpc_guard.sql` removes additive timing
from the strict established Planner/Deadline payload before delegating, then
binds exact provenance under the same owner transaction and admits only an
exact retry. `20260726190000_planning_confirmation_timestamp_guard.sql` keeps
the existing confirmation signatures while clamping their supplied instant to
the latest persisted plan/revision/target/block timestamp under the owner lock.
`20260726200000_learned_timing_setup_fallback_provenance.sql` relaxes only the
two provenance-shape checks so a learned source can truthfully retain its
evidence and mark `timing_fell_back_to_setup=true` after allocation uses an
ordinary Setup window. It changes no grant, active block, or confirmation
authority.

Account Export now contains exactly 41 owner-content tables, including
`learning_preferences`, `focus_session_reflections`, and
`focus_session_schedule_sources`, and names the learning retry ledger under its
omission policy. Canonical profile deletion cascades the product projections.
See `docs/personal-learning-v1-contract.md`.

Phase 0B did not require a migration. Flutter now treats missing or failing real
Dashboard/Inbox/Recommendation sources as empty or error according to
their contracts and never substitutes mock rows. Notification routing reads the
existing `action_url`, but only implemented internal paths are enabled; no
notification mutation is inferred from that link allowlist. Notification
Lifecycle V1 later added the separate durable backend-owned
read/unread/dismiss command without broadening direct authenticated table DML.

Phase 0C adds the revision history contract to `intake_responses` and the
monotonic projection revision to `profiles`. Current Setup-created habits,
schedule items, Study Setup, and the energy memory reuse existing primary keys
and metadata:
FastAPI derives deterministic UUIDv5 ids and writes `managed_by`,
`setup_item_id`, revision, lifecycle, and `source=intake-v1` metadata. This
makes ownership queryable without claiming manual or `demo_seed` rows. Candidate
routines do not create a `habits` row until cadence is confirmed. The apply RPC
preserves unmarked onboarding schedule rows except for the exact historical
placeholder `Math`, `Room 204`, Monday `08:15`-`09:45` with empty metadata,
which is removed when omitted.

The 2026-07-25 compatibility migration keeps the Setup Apply RPC signature but
ignores `p_notification_preferences` and `p_goals`. It leaves
`notification_preferences` byte-for-byte unchanged, archives Setup-owned Goals,
retains manual/foreign Goals, and reconciles only the active Setup projections.

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
Setup; replacement/task/schedule changes remain staged. Weekly Review does not
load Goals, and the retained V1 `goal_linked_completed` field is always zero.

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

`20260718120000_deadline_planner_v1.sql` creates the four forced-RLS Deadline
Planner tables, their ownership and bounded-value constraints, supporting
indexes, and the service-role-only proposal/confirmation/lifecycle RPCs. It
grants authenticated owners only the documented read projection and leaves the
global request-identity ledger backend-only.

`20260719120000_account_preparation_budget_v1.sql` adds nullable
`profiles.daily_preparation_budget_minutes`, constrained to `25..480` in
five-minute increments. Existing null rows retain the per-plan-only behavior.
Application roles may read the owner profile through existing RLS but cannot
write this column. The service-role-only
`set_daily_preparation_budget_v1(uuid,int)` RPC originally took the same owner
advisory lock as planner mutations. The stabilization migration revokes its
execute authority and replaces it with the revision-checked, fingerprinted
`apply_account_preparation_budget_v2` path.

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

## Study Setup V1

`20260723120000_study_setup_v1.sql` adds
`study_setup_profiles` as the optional current projection of
`responses.study_setup` from the applied revisioned Intake flow. The row stores
the exact focus/recovery rhythm, ordered preparation-item definitions, current
and next semester JSON, source Setup revision, and timestamps. When a newer
confirmed Setup omits Study Setup, the atomic Intake RPC removes the projection;
no default row is fabricated.

The table uses forced RLS. Authenticated owners/admins have SELECT only,
`anon` has no authority, and backend-owned writes remain limited to
`service_role`. The profile foreign key cascades on deletion. Account Export
includes the bounded owner row.

The migration preserves the public signatures of the established Intake,
Deadline Planner, and Planner RPCs by moving their reviewed bodies behind
ungranted inner functions and installing service-role-only wrappers. The Intake
wrapper validates and projects the canonical applied response in the same
transaction. The planning wrappers validate current Study revision, exact
focus-sized blocks, recovery duration, full `reserved_ends_at`, and all
competing reservations before persistence or activation.

`deadline_plan_revisions` and `planner_action_plan_revisions` gain nullable
`study_setup_revision` plus zero-or-configured `recovery_minutes`.
`deadline_plan_blocks` and `planner_task_blocks` gain
`recovery_minutes` and non-null `reserved_ends_at`. Existing revisions remain
null/zero; existing blocks are backfilled with zero recovery and their prior
end. Active indexes and confirmation conflict checks use the full reserved end,
while daily preparation arithmetic continues to sum only focus minutes.

The full Intake, Focus, planning, semester-attention, export, and non-claim
boundary is in `docs/study-setup-v1-contract.md`.

## Phase 10 Coach Persistence

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
`type='preference'` or `type='goal'` memory. Retired Intake context/style/Goal
memories are removed by the cleanup migration. Selection never changes the
underlying memory row or its Setup metadata.

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
The Flutter Auth repository therefore requires the trigger-created profile
after one owner-scoped read. A missing row is an invariant failure and never
causes an authenticated insert/upsert or a fabricated local profile.
`20260713230000_phase_10_onboarding_eligibility_guard.sql` additionally revokes
authenticated updates to `onboarding_completed_at` and blocks application-role
identity/eligibility mutation in the profile trigger. Service role and the
service-role-only atomic Intake apply RPC retain backend projection authority.

`20260728120000_coach_longitudinal_context_v1.sql` additively adds non-null
`coach_requests.context_parameters` with an exact empty-object default.
Existing `coach-request-v1` rows and `claim_coach_request_v1` remain unchanged:
their scope is `today`, their parameters are `{}`, and their prompt/context
pair is V1 or V2. `coach-request-v2` permits only these exact combinations:
`today` or `review` with `{}`; `patterns` with only `horizon` set to
`90_days`, `1_year`, or `all_available`; and `focus` with only a canonical
`focus_session_id` UUID string. V2 requires
`controlled-coach-prompt-v3`/`coach-context-v3`.

The new service-role-only `claim_coach_request_v2` keeps the established
owner-before-request advisory-lock order and the same daily-limit, lease,
one-pending-request, terminal, and deletion behavior. Its retry identity binds
the message fingerprint, context scope, and exact parameters while preserving
the originally claimed local date, provider/model, and version provenance. The
response validator accepts paired V3 provenance by normalizing it through the
existing strict V1-only envelope validator, while paired V1 and V2 history
remain valid. The used-context manifest stays bounded to ten entries and adds
the per-source names `daily_capture`, `focus_reflections`, `habit_outcomes`,
`decision_feedback`, `weekly_reviews`, and `task_lifecycle`. Existing
completion, failure, and deletion RPCs continue to handle both request
versions. Partial `(user_id, completed_at, id)` and
`(user_id, cancelled_at, id)` Task indexes accelerate owner-scoped terminal
history without changing Task lifecycle authority.

`20260728160000_free_read_only_coach_agent_v1.sql` additively implements the
current free-question persistence contract without rewriting old rows. It adds
nullable `evidence`, `agent_trace`, `tool_call_count`, and `service_tier`
columns to `coach_requests`; V1/V2 rows keep those fields null.

`coach-request-v3` has no user-selected scope or parameter object. Its
service-role-only `claim_coach_request_v3` reuses the established owner-before-
request locks, one-pending-owner rule, lease, terminal replay, and profile-local
daily budget. Replay binds derived owner, request UUID, and exact message
fingerprint only. A new claim stores
`free-coach-agent-prompt-v1`/`personal-snapshot-v1`; the later V4 claim wrapper
stores `free-coach-agent-prompt-v2` for a newly claimed request. The legacy physical scope
columns stay neutral `today`/`{}` for schema compatibility and are not a
current product mode.

The service-role-only `complete_coach_request_v2` requires one exact
`coach-response-v2` and validates:

- response request identity and bounded reply/uncertainty/safety;
- backend-derived evidence source/count/period rows;
- at most 12 contiguous `inspect_data|query_data|run_python` trace steps,
  completion/failure status, bounded summaries/counts/durations, and
  limitations;
- exact equality between response and separately supplied evidence/trace/tool
  count;
- paired `free-coach-agent-prompt-v1|v2` and `personal-snapshot-v1` provenance;
- snapshot rows no greater than 50,000 and bytes no greater than 8 MiB; and
- `local_codex_oauth` truth fixed to `gpt-5.5`, explicit Fast configured, and
  no non-Codex Fast claim.

The response validator continues to admit strict `coach-response-v1`; existing
completion/failure rows, usage events, and histories remain readable. The
history-delete wrapper calls the prior owner-locked transaction and then clears
V3 evidence, trace, tool count, and service tier from tombstones. It does not
delete usage/request identities and conflicts with an active turn.

All new validator and mutation functions are revoked from `public`, `anon`, and
`authenticated`. Only `service_role` may execute the V3 claim, V2 completion,
or history-delete RPC. No new application-role table write is introduced.

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
The scheduled-Focus provenance rows cascade from Focus before their restricted
Planner/Deadline block references are reached, so this ordering also preserves
the existing complete-account deletion path.
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
from `user_id` and locks and validates the claimed canonical `intake-v1` row.
Its original materialization included notification preferences and Setup Goals;
the 2026-07-25 compatibility wrapper now ignores both retained parameters,
archives Setup-owned Goals, and reconciles only Habits, schedule/Study rows, and
the energy memory. It then upserts the canonical
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

`20260723120000_study_setup_v1.sql` adds the forced-RLS Study Setup projection
and atomically composes it with the revisioned Intake apply. It extends
Planner/Deadline revisions and blocks with Study revision, recovery duration,
and full reserved-end truth; backfills existing blocks as zero recovery; and
wraps proposal/confirmation with exact current-setting and recovery-conflict
guards.

`20260723200707_optimize_canonical_rls_policies.sql` removes six superseded
initial-schema policies and rebuilds the eleven canonical owner/admin policies
with statement-cached identity and role helpers. It changes no table privilege,
RLS mode, owner/admin predicate, or service-role boundary.

`20260728120000_coach_longitudinal_context_v1.sql` preserves V1 Coach claims
while adding exact V2 context parameters/replay, paired V3 provenance
validation, and partial completed/cancelled Task history indexes.

`20260728160000_free_read_only_coach_agent_v1.sql` admits message-only
`coach-request-v3`, exact `coach-response-v2`, and backend-owned
evidence/agent-trace/tool-count/Fast-tier persistence. Its service-role-only
claim/completion wrappers retain the owner lock, daily budget, terminal replay,
legacy history, and deletion tombstones while adding no application write
authority.

`20260729120000_stabilization_write_authority.sql` adds branch-CAS Daily
Capture and revision-CAS account-setting ledgers/RPCs, removes direct Capture
DML and the old preparation setter's execute authority, binds Planner,
Deadline, and Calendar projections to timezone revision, adds Calendar
planning status, guards Setup-owned rows, and gives manual Task/Habit creation
immutable retry identity.

`20260729130000_observed_projection_persistence.sql` adds
`source_observed_at` to user-state Snapshots and Weekly Reviews plus the
service-role-only V2 persistence RPCs. A later-observed Snapshot wins; Weekly
Review persistence validates the current weekly Snapshot identity and
provenance under the owner/row lock.

`20260729160000_coach_english_prompt_v2.sql` admits the paired free-agent V1/V2
prompt provenance and adds service-role-only `claim_coach_request_v4`. It
upgrades only a newly claimed pending request to V2, so existing V1 requests
and exact replays retain their original provenance. Application roles receive
no new table or RPC write authority.

`20260802083219_focus_schedule_sources_v2.sql` adds immutable optional
planned-block provenance, owner-locked replay-safe Focus V2 lifecycle RPCs,
scheduled interval collision checks, and an internal source-aware Deadline
projection. It changes no historical Focus row and keeps V1 writes available
for older clients.

`20260802111518_privileged_function_lint_cleanup.sql` replaces the retained
public legacy role helper with an application-inaccessible `SECURITY INVOKER`
wrapper over `private.current_app_role()`, removes only the shadowed Account
Delete loop-variable declaration, and uses `PERFORM` for the deliberately
discarded Coach V3 expiry-failure response. It restates the existing minimal
grants, hardens fixed search paths, and changes no Account or Coach result,
lock, replay, deletion, or application-authority contract.

## Local Verification Workflow

For local Supabase-backed testing, the reset should complete through:

```text
20260802111518_privileged_function_lint_cleanup.sql
```

Then configure `.env` with:

```env
USE_MOCK_DATA=false
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<local anon key from supabase status>
```

Run the standard local checks first:

```bash
FLUTTER_BIN=/path/to/flutter npm run verify:fast
```

This includes docs/visual/source checks, clean Flutter analysis and the
complete Flutter suite, the complete FastAPI pytest suite, compile checks, and
whitespace checks.

For local Supabase preflight without resetting the database:

```bash
npm run verify:db
```

This default starts/reuses the local stack, inspects
`supabase migration list --local`, and fails if repository files and database
history differ. It then runs the complete pgTAP suite and never runs Flutter
tests. It never applies SQL automatically. If the histories differ, review the
pending SQL and affected local rows before opting in:

```bash
APPLY_MIGRATIONS=true npm run verify:db
```

Pending migrations may change or delete local rows. Avoid describing this path
as non-destructive merely because it does not reset the full database. The
script verifies migration history again after the explicit application.

Python `test_*_migration.py` files are historical source guards for exact
rollout identity and share their loader/extractors in
`services/ai_service/tests/migration_source.py`. They are not the authority for
the current applied schema. Final RLS mode, policy/catalog presence, effective
role privileges, constraints, installed triggers, and database behavior belong
in `supabase/tests/*.sql`, which runs only after the complete local migration
history is confirmed.

For local Supabase reset and migration verification:

```bash
RESET_DB=true npm run verify:db
```

The reset form should apply all migrations through
`20260802111518_privileged_function_lint_cleanup.sql`; expected legacy-table
skip notices may be emitted for missing CamelCase tables. Use reset when proving
the full migration/backfill/constraint chain from a fresh local database, not
merely because a reviewed migration is pending.

Then either run the browser E2E smoke in `scripts/e2e_web.sh` or start the
frontend with `scripts/start_frontend.sh` and manually verify the
Supabase-backed path:

- Register or sign in.
- Complete Setup with only Typical weekday and Best energy, re-enter it, and
  save an edit. Confirm retired personalization controls/keys stay absent and a
  customized `notification_preferences` row remains exactly unchanged.
- Enable Focus setup and Semester planning, confirm the 45/10 defaults and
  projection, then verify that a later omitted section is removed only through
  the revisioned Setup save.
- Start Focus through a Study-aware block, exercise the transient checklist,
  complete it, and verify the local recovery countdown without a recovery row.
- Review/archive or remove one Setup-owned Habit/commitment, confirm a legacy
  Setup-owned Goal is archived, and preserve manual Goal/memory rows.
- Save Evening Shutdown through either current route, then save Morning
  Calibration and confirm that the same daily row retains both V3 captures
  without friction keys.
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
- Open Coach with the fake provider, confirm read-only capability/history,
  send a free V3 question, observe safe stream activity, inspect actual
  evidence/trace/provenance, replay its id with the exact message, and delete
  history. Confirm messages and V3 detail are gone while request tombstones and
  usage remain. Confirm there is no fixed mode/memory/suggestion UI and
  guest/mock makes no Coach request.
- Open Inbox (`/alerts`); mark one row read/unread, dismiss it, reload, and do
  not infer notification delivery from stored rows or preferences.

This checks that Auth, RLS, grants, FastAPI backend workflows, and the app's
snake_case table mappings work together. The repository provides
`scripts/e2e_web.sh` for browser automation of this Supabase-backed flow. The
browser smoke starts the AI service with backend local Supabase settings and
asserts revisioned Intake V1 rows, ownership-scoped Setup reconciliation,
onboarding and daily `user_state_snapshots`, absence of post-intake
Recommendations, explicit runtime Recommendation refresh, exact Daily State V2
recomputation, and direct app writes. Phase 3
browser completion additionally requires exact task transition/undo rows,
manual and Setup habit completion/skip/undo without duplicates, and focus
start/finish/abandon with owned linkage and no implicit target mutation. The
source injects committed response loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish. Negative
task/focus/habit lifecycle, duration, active-target, and weekday-cadence writes
include terminal-focus `updated_at` mutation. Phase 8/9 source adds weekly review
and calendar import. Phase 10 source starts FastAPI with the deterministic fake
provider and adds free-question streaming, snapshot/trace/evidence persistence,
replay, cancellation, safety, limits, history deletion, RLS, no-fixed-mode UI,
and guest-zero-call assertions. Exact current results and dated run
history live in
[Current Verified Baseline](verification.md#current-verified-baseline) and the
historical sections of `docs/verification.md`. They establish neither remote
migration/RLS state nor production readiness. Later changes must establish a
new full pass. Do not run destructive reset commands against a remote database.

For manual local product exploration, `npm run seed:demo` creates four
repeatable local-only Auth users. `onboarding@example.test` is recreated with an
incomplete `Europe/Berlin` profile, the Auth-created default notification
and Personal Learning preferences, and no activity, Setup, planning, Coach, or
retry-ledger rows. Student, worker, and recovery remain the three populated
scenarios. The command replaces only
those four named accounts through the full-account cascade, so immutable retry
and usage rows are reset without weakening their normal contracts. The seed
script uses the local Supabase service-role key from
`supabase status -o env`, refuses non-local API URLs, and writes typed applied
Setup revisions with stable request ids and empty optional Setup-owned
collections only for the populated accounts. It then uses the existing backend
services to enrich and verify the student account across Today, Weekly Review,
Calendar Import, Deadline Planner, notification delivery, and Coach. It does
not change the schema or relabel the separately seeded `demo_seed` objects as
Setup-owned.

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
`20260802111518_privileged_function_lint_cleanup.sql`. It removes the final
privileged-function schema-lint diagnostics without changing Account Delete,
Coach replay, role authority, or application grants. The preceding Focus
migration adds scheduled-Focus provenance and service-role-only V2 lifecycle/
projection RPCs without changing legacy client write authority. The earlier
Coach migration adds rolling-safe
English-only prompt provenance and a service-role-only V4 claim wrapper. The
preceding stabilization migrations
establish retry-safe write authority and observation-order persistence. The
earlier `20260728160000_free_read_only_coach_agent_v1.sql` preserves fixed-mode
V1/V2 rows while adding message-only V3 claim, exact V2 response, backend-owned
evidence/trace/tool/tier persistence, and compatible history deletion. The
preceding `20260728120000_coach_longitudinal_context_v1.sql` adds exact V2
scope/parameter replay, paired V3 prompt/context provenance, and partial
terminal Task history indexes. The preceding
`20260726200000_learned_timing_setup_fallback_provenance.sql` preserves learned
evidence while recording actual Setup allocation fallback. The earlier
confirmation-time and proposal-RPC guards keep timestamps monotone, strict V1
delegation payloads unchanged, and retries exact. The preceding
Recommendation migration installs atomic current-feed replacement for
deliberate deterministic refresh while preserving historical decisions. The
earlier
`20260726150000_learned_focus_planning_v1.sql` adds immutable learned/setup
timing provenance and confirmation permission guards without moving active
plans. The preceding `20260726120000_personal_learning_v1.sql` adds forced-RLS
Focus reflections, revisioned learning preferences, and their service-only
retry ledger/RPCs. The earlier
`20260725120000_retire_setup_goals_and_friction.sql` performs idempotent cleanup:
it strips retired Setup/friction JSON, archives only Setup-owned Goals, deletes
only retired Setup-derived memories, invalidates reproducible derived output
that references those fields, and performs no regeneration. Its compatibility
wrappers leave the Setup Apply signature intact while ignoring Goal/Reminder
arguments and admit paired Coach prompt/context V2 provenance while preserving
V1 history. The preceding
`20260723200707_optimize_canonical_rls_policies.sql` removes redundant initial
policies and makes the unchanged canonical owner/admin predicates
initialization-plan safe without changing grants or RLS authority. The
preceding `20260723120000_study_setup_v1.sql` adds the forced-RLS
Study Setup projection, composes it atomically with applied Intake, and adds
recovery-aware revision/block truth and confirmation guards to Planner and
Deadline Planner. The preceding
`20260722234000_setup_commitment_validity_guards.sql` adds no schema object
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
0C service-role-only atomic Setup RPC signature, revision contract, and
monotonic profile guard remain compatible. Current Capture V4 changes only
typed metadata and client/backend mapping; Daily State V2 consumes sanitized
data inside existing snapshot JSON; Phase 3 adds action facts without changing
Daily State classification; and
Phase 4 persists deterministic briefing decisions without changing either
contract; Phase 6 adds feedback as separate evidence and never rewrites those
persisted reasons. Phase 7 adds no schema object; it prepares the existing
snapshot and briefing identities by profile-local date. Phase 8 persists only
derived weekly review output and reuses existing Habit V1 mutations after
explicit confirmation. Phase 10 adds conversational explanation without making
any Coach suggestion executable or changing the deterministic briefing loop.
