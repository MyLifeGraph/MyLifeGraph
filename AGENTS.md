# Agent Instructions

These instructions are for coding agents working in this repository. They are
repo-local and must not depend on any user-private Codex skill or machine-local
profile configuration.

This file is the required starting point for agents. Read it before making code
or schema changes, then consult the linked docs for more detail.

## Start Here

Read these files before making changes:

1. `README.md`
2. `docs/local-dev.md`
3. `docs/architecture.md`
4. `docs/backend-roadmap.md` before planning backend, AI, onboarding, or agent
   workflows
5. `docs/daily-briefing-implementation-plan.md` before planning the next
   product slice, daily check-in changes, recommendation ranking, or dashboard
   decision-loop work
6. `docs/verification.md` before running or changing test automation
7. `docs/supabase-current-state.md` when touching Supabase, auth, data sources,
   or migrations
8. `docs/phase-3-executable-actions-contract.md` before changing executable
   actions or consuming them in a briefing
9. `docs/phase-8-weekly-review-contract.md` before changing weekly review
   facts, freshness, proposals, or confirmed habit adaptation
10. `docs/phase-9-calendar-import-contract.md` before changing calendar
    consent, `.ics` parsing, imported-event identity, disconnect, or deletion
11. `docs/phase-10-controlled-coach-plan.md` before changing Coach routing,
    model providers, LLM context, memory selection, chat persistence, usage
    budgets, or local Codex subprocess behavior
12. `docs/notification-lifecycle-v1-contract.md` before changing Inbox reads,
    notification lifecycle commands, retry identity, read/dismiss state, or
    notification mutation authority
13. `docs/v1-account-controls-contract.md` before changing password recovery,
    profile timezone, account export, or permanent account deletion
14. `docs/notification-delivery-v1-contract.md` before changing notification
    consent, deterministic generation, quiet hours, category/cap enforcement,
    local scheduling, foreground delivery, or delivery provenance
15. `docs/deadline-planner-v1-contract.md` before changing exam/assignment
    preparation estimates, plan revisions, dated blocks, managed plan tasks,
    calendar-derived availability, or tracked-focus progress
16. `docs/exam-week-outlook-v1-contract.md` before changing Daily Capture V4
    sleep planning, sleep-duration projection, exam-window activation,
    sleep-protected capacity, or the Planner outlook card
17. `docs/setup-personalization-retirement-contract.md` before changing Setup
    inputs, Goal compatibility, friction handling, Daily State capture
    compatibility, Coach context, or Reminder ownership
18. `docs/ui-language-and-copy-contract.md` before changing student-facing
    names, capability claims, retry copy, localization, or large-text behavior
19. `docs/today-overview-v1-contract.md` before changing the Today streak,
    progress arithmetic, timeline sources, task/habit selection, or supporting
    section boundary
20. `docs/planner-v1-contract.md` before changing Planner navigation,
    availability, Action Plans, fixed commitments, calendar busy-time consent,
    or Today Overview V2
21. `docs/study-setup-v1-contract.md` before changing optional Study Setup,
    focus rhythm, preparation checklist, recovery reservations, semester
    planning, or course-selection attention
22. `docs/product-review-handoff.md` when starting a fresh whole-product review
    of Deadline Planner and the current usability-polish slice
23. `docs/personal-learning-v1-contract.md` before changing Focus reflections,
    learning preferences, personal patterns, shared sleep parsing, learned
    Planner timing, or the recommendation-cleanup follow-up
24. `docs/frontend-visual-system-v2.md` before changing Flutter themes,
    typography, icons, surfaces, motion, brand assets, or presentation styling

## Current State

MyLifeGraph is a Flutter web/mobile app with Supabase for auth and persistence
and a FastAPI service for authenticated deterministic recommendation workflows
and future AI integrations.

The app now targets a canonical snake_case Supabase schema. Older remote
databases may still contain legacy CamelCase tables such as `"User"`,
`"DailyLog"`, and `"Task"`, but new app code should use:

- `profiles`
- `daily_logs`
- `behavioral_events`
- `tasks`
- `schedule_items`
- `notifications`
- `notification_action_requests`
- `coach_messages`
- `memory_entries`
- `ai_insights`
- `recommendations`
- `skillset_profiles`
- `notification_preferences`
- `goals`, `habits`, `habit_logs`, `focus_sessions`
- `focus_session_reflections`, `learning_preferences`
- `learning_request_identities`
- `intake_responses`, `user_state_snapshots`
- `daily_briefings`, `decision_feedback`, `weekly_reviews`
- `calendar_connections`, `calendar_imports`, `calendar_events`
- `calendar_request_identities`
- `coach_requests`, `coach_usage_events`, `coach_memory_selections`
- `deadline_plans`, `deadline_plan_revisions`, `deadline_plan_blocks`
- `deadline_plan_request_identities`
- `planner_preferences`, `planner_action_plans`
- `planner_action_plan_revisions`, `planner_task_blocks`
- `planner_habit_slots`, `planner_commitments`, `planner_request_identities`
- `study_setup_profiles`

The migration
`supabase/migrations/20260618170000_create_canonical_app_schema.sql` creates the
canonical schema, applies RLS policies, and copies data from legacy CamelCase
tables when they exist. It intentionally does not drop legacy tables. The
migration
`supabase/migrations/20260702092807_intake_v1_backend_foundation.sql` adds the
Intake V1 backend tables and RLS policies. The migration
`supabase/migrations/20260702195915_unique_user_state_snapshot_period.sql`
deduplicates `user_state_snapshots` by user/scope/period and adds the unique
index required for atomic backend upserts. The migration
`supabase/migrations/20260710120000_phase_0c_intake_request_revisions.sql`
adds the request identity, base/revision, pending/applied state, and uniqueness
constraints used by retry-safe Setup completion and editing. The migration
`supabase/migrations/20260710153000_profile_setup_revision_guard.sql` adds and
backfills `profiles.setup_revision`; FastAPI advances that projection only to a
newer applied Setup revision so a stale worker cannot overwrite a newer profile
projection. The migration
`supabase/migrations/20260710180000_atomic_intake_v1_setup_apply.sql` adds the
service-role-only `apply_intake_v1_setup_revision` RPC. It serializes Setup apply
per user with a transaction-scoped advisory lock and atomically reconciles
preferences, Setup-owned records, the canonical onboarding snapshot, the intake
state, and the profile projection.
The migration
`supabase/migrations/20260711120000_phase_3_executable_action_schema.sql` adds
task estimates and terminal timestamps, explicit habit outcomes, and the linked
focus-session lifecycle. It preserves existing table RLS/grants while adding
exact task/focus lifecycle and duration checks, locked active/cadence-aware
habit-outcome validation, locked focus-target validation, restricted target
deletion, full terminal-history immutability, deterministic UTC-date backfill
for legacy focus rows, and the one-active-focus-session invariant.
The migration
`supabase/migrations/20260712064836_phase_4_daily_briefings.sql` adds the
owner-scoped persisted daily briefing identity, bounded JSON checks, explicit
Data API grants, and forced RLS policies used by the backend-only generator.
The migration
`supabase/migrations/20260712190000_phase_6_decision_feedback.sql` adds bounded
append-only decision feedback with retry-safe request identity, owner-scoped
read/delete RLS, backend-owned writes, and context indexes for its 28-day
deterministic ranking window.
The migration
`supabase/migrations/20260712210000_phase_8_weekly_reviews.sql` adds one bounded
backend-owned deterministic review per profile/ISO-week identity, exact
Monday-to-Sunday and source-fingerprint checks, authenticated owner/admin reads,
service-role writes, and forced RLS.
The migration
`supabase/migrations/20260712211500_phase_8_weekly_review_provenance_guard.sql`
non-destructively completes the weekly-review provenance check by requiring the
strict deterministic contract keys and matching source fingerprint.
The migration
`supabase/migrations/20260713120000_phase_9_calendar_import.sql` adds dedicated
consented calendar connection, immutable import, and current imported-event
tables with forced RLS and service-role-only atomic connection, import,
disconnect, and local-delete RPCs. It stores no provider credential and never
copies imported events into `schedule_items`.
The migration
`supabase/migrations/20260713143000_phase_9_calendar_request_identity_guard.sql`
non-destructively adds one minimal global request-identity registry across
calendar create/import/disconnect/delete, changes application conflicts to
PostgREST `PT409`, and permits import replay only while that import is still the
connected source's current projection. The registry stores no file or content
fingerprint and is service-role insert/select only with forced RLS.
The migration
`supabase/migrations/20260713200000_phase_10_controlled_coach.sql` adds the
retry-safe Coach request ledger, append-only usage ledger, explicit memory
selection projection, and bounded request-linked message pairs. It hardens
`coach_messages` and `memory_entries` to authenticated owner reads with
backend-owned mutations, forces RLS on the Coach tables, and exposes only
service-role claim/complete/fail/selection/history-delete RPCs. Conversation
deletion removes message content and tombstones request content while retaining
usage rows and request identities, so deletion cannot reset the daily budget or
reinterpret an old request id.
The follow-up migration
`supabase/migrations/20260713213000_phase_10_coach_lock_order_guard.sql`
wraps Coach claim, complete, and fail with the same owner advisory lock that
history deletion takes first. The renamed inner RPC bodies are uncallable by
application roles, including `service_role`; only the public wrappers remain
service-role executable. The consistent owner-before-request/row lock order
removes the inverse ordering between concurrent claim/completion/deletion paths.
The migration
`supabase/migrations/20260713220000_phase_10_coach_safety_provenance_guard.sql`
extends the strict persisted response contract with backend-owned
`provider_called` truth so a deterministic safety redirect records whether it
bypassed the provider or replaced a provider result. The migrations
`supabase/migrations/20260713223000_phase_10_profile_privilege_guard.sql` and
`supabase/migrations/20260713224500_phase_10_role_authority_guard.sql` make
canonical profile identity and authorization backend-owned: application roles
cannot insert a profile, change `role`/`auth_provider`, delete the canonical
profile, or gain authority from a legacy `"User"` fallback. The migration
`supabase/migrations/20260713230000_phase_10_onboarding_eligibility_guard.sql`
also removes authenticated write authority over
`profiles.onboarding_completed_at`; only the backend-owned Intake apply path
may advance that eligibility projection.
The migration
`supabase/migrations/20260713233000_v1_account_delete.sql` adds the
service-role-only transactional V1 account-deletion RPC. It locks existing
owner workflows, removes restrict-linked focus history, deletes the Supabase
Auth user, and verifies the canonical profile/product cascade without changing
normal task or habit deletion semantics. It also makes new profile defaults
explicitly UTC, removes direct authenticated timezone mutation, freezes all
known CamelCase legacy tables against application-role repopulation, and limits
notifications, AI insights, recommendations, and Skillset projections to
authenticated reads with service-role writes.
The migration
`supabase/migrations/20260714100000_notification_lifecycle_v1.sql` adds exact
read/dismiss timestamps and the global service-role-only Notification action
request ledger. Its owner-locked RPC provides retry-safe mark-read, mark-unread,
and dismiss tombstones while direct application-role Notification DML remains
forbidden.
The migration
`supabase/migrations/20260714103000_application_table_privilege_guard.sql`
closes unintended application-role privileges across every repo-owned product
and ledger table. It makes `anon` fail closed, removes authenticated
`TRUNCATE`, `REFERENCES`, and `TRIGGER` authority while preserving intended
per-table DML, keeps backend projections read-only, freezes any retained legacy
tables, and hardens future `postgres`-created public-table defaults. Existing
Auth triggers remain installed, but their security-definer functions cannot be
reused by application or service roles. It also adds the Notification-ledger
child lookup index and non-validating timestamp-order checks that protect new
or updated rows without assuming old remote rows are already clean.
The migration
`supabase/migrations/20260714110000_account_export_lifestyle_entries_grant.sql`
restores the one missing backend `SELECT` grant required by the then-31-table
Account Export V1 contract. It grants only `service_role` read access
to `lifestyle_entries`; it adds no guest or authenticated-user authority.
The migration
`supabase/migrations/20260714130000_notification_delivery_v1.sql` adds
fail-closed explicit in-app consent, settings request identity, bounded
deterministic generation provenance/dedupe fields, and an at-most-once
foreground receipt. Its settings, generation, and delivery RPCs take the owner
lock, are service-role-only, and revalidate timezone/local date, quiet hours,
category flags, daily cap, and current consent. It adds no push/system or
deployed delivery channel.
The follow-up migration
`supabase/migrations/20260714143000_notification_delivery_settings_guard.sql`
binds Settings replay to the complete request payload and expected revision,
invalidates that identity when Setup changes the shared preference projection,
and keeps `updated_at` monotone and no earlier than retained consent timestamps.
The migration
`supabase/migrations/20260718120000_deadline_planner_v1.sql` adds the forced-RLS
Deadline Planner plan, immutable revision, dated block, and global request-
identity tables plus service-role-only owner-locked proposal, confirmation, and
lifecycle RPCs. Authenticated clients retain only the intended owner read
projection.
The migration
`supabase/migrations/20260719120000_account_preparation_budget_v1.sql` adds the
nullable `25..480` five-minute account-wide preparation rule, revokes direct
application-role writes to that profile column, and exposes only an owner-
locked service-role setter. Deadline-plan confirmation rechecks aggregate active
minutes on the candidate revision's local dates at the database boundary.
The migration
`supabase/migrations/20260722120000_planner_v1.sql` adds the forced-RLS Planner
preference, Action Plan/revision, dated Task block, recurring Habit slot,
manual commitment, and backend-only retry-ledger tables. Service-role-only
owner-locked RPCs stage and atomically confirm or cancel plans, create/update/
archive authoritative commitments, recheck target/calendar/reservation state,
and release future reservations when a Task or Habit becomes terminal.
The follow-up migration
`supabase/migrations/20260722234000_setup_commitment_validity_guards.sql`
keeps Planner and Deadline Planner confirmation aligned with the optional
inclusive Setup semester bounds. It adds no table or column and fails closed if
either protected RPC definition has drifted.
The migration
`supabase/migrations/20260723120000_study_setup_v1.sql` adds the forced-RLS
Study Setup projection, atomically projects optional focus rhythm and semester
planning from the canonical applied Intake revision, and extends Planner and
Deadline revisions/blocks with Study revision and recovery-reservation truth.
It preserves old Intake rows and old zero-recovery blocks, makes Study-bound
previews stale after a rhythm edit, and prevents confirmation against changed
settings or overlapping recovery time.
The migration
`supabase/migrations/20260723200707_optimize_canonical_rls_policies.sql` removes
six superseded initial policies and makes the eleven unchanged canonical owner/
admin predicates initialization-plan safe. It changes no table privilege, RLS
mode, owner/admin rule, or service-role boundary.
The migration
`supabase/migrations/20260725120000_retire_setup_goals_and_friction.sql`
idempotently strips retired Setup/friction JSON, archives only Setup-owned
Goals, deletes only retired Setup-derived memories, and invalidates reproducible
derived output that referenced those fields without regenerating it. Its
compatibility wrappers keep the Setup Apply signature stable while ignoring
Goal/Reminder inputs, and admit paired Coach prompt/context V2 provenance while
preserving readable V1 history.
The migration
`supabase/migrations/20260726120000_personal_learning_v1.sql` adds the forced-
RLS Focus reflection and learning-preference projections plus a backend-only
retry ledger. It enforces terminal-session ownership, controlled ratings and
obstacles, the analysis/Planner preference dependency, retry-safe preference
updates, and confirmed reflection-history clearing.
The migration
`supabase/migrations/20260726150000_learned_focus_planning_v1.sql` adds immutable
learned-timing provenance to Planner and Deadline revisions and makes
confirmation fail closed if a learned preview is no longer permitted. It
changes no active block and adds no automatic replanning.
The migration
`supabase/migrations/20260726170000_recommendation_refresh_v2.sql` makes a
deliberate Recommendation refresh replace the prior current `new` set
atomically while retaining dismissed history and accepted decisions.
The follow-up migration
`supabase/migrations/20260726180000_learned_focus_planning_rpc_guard.sql`
keeps additive timing provenance outside the strict established Planner and
Deadline proposal payloads, then binds it in the same transaction with exact
replay checks.
The migration
`supabase/migrations/20260726190000_planning_confirmation_timestamp_guard.sql`
normalizes confirmation instants against persisted plan, revision, target, and
block timestamps under the existing owner lock so clock skew cannot move audit
timestamps backwards.
The migration
`supabase/migrations/20260726200000_learned_timing_setup_fallback_provenance.sql`
preserves the learned evidence source while permitting immutable provenance to
record that actual block allocation used the ordinary Setup fallback sequence.

## Important Docs

- `docs/architecture.md` - system shape and current backend/frontend boundary.
- `docs/backend-roadmap.md` - target backend flow, product agents, data model
  direction, LLM cost controls, and the next implementation sequence.
- `docs/daily-briefing-implementation-plan.md` - current product direction for
  the daily decision loop, lightweight capture cadence, stress taxonomy, Daily
  Mode, briefing service, and next implementation phases.
- `docs/today-overview-v1-contract.md` - current read-only Today projection,
  streak/progress arithmetic, timeline sources, selection rules, and UI order.
- `docs/planner-v1-contract.md` - central Planner navigation, shared
  availability, staged Task/Habit reservations, commitments, and Today V2.
- `docs/study-setup-v1-contract.md` - optional focus rhythm, transient start
  ritual, recovery reservations, semester planning, course-selection attention,
  and the exact Intake/projection authority boundary.
- `docs/supabase-current-state.md` - canonical schema, legacy table mapping, and
  migration notes.
- `docs/local-dev.md` - local runbook for Flutter, Supabase, and FastAPI.
- `docs/verification.md` - automated checks, local Supabase verification, and
  current E2E gaps.
- `docs/phase-3-executable-actions-contract.md` - implemented task, habit,
  focus, and ranking-independent action-target contract.
- `docs/phase-8-weekly-review-contract.md` - implemented bounded ISO-week fact,
  proposal, freshness, ownership, and confirmed Habit V1 adaptation contract.
- `docs/phase-9-calendar-import-contract.md` - implemented explicit consent,
  bounded `.ics` reconciliation, imported/read-only provenance, and separate
  disconnect/local-delete contract.
- `docs/phase-10-controlled-coach-plan.md` - implemented first bounded Coach
  contract and the development-only subscription-backed local Codex OAuth
  adapter, including its separate live-verification boundary.
- `docs/notification-lifecycle-v1-contract.md` - authenticated stored-Inbox
  visibility, strict lifecycle commands, replay/conflict behavior, owner/RLS
  boundary, and explicit delivery non-claims.
- `docs/notification-delivery-v1-contract.md` - explicit in-app consent,
  deterministic bounded generation, timezone/quiet/category/cap/dedupe guards,
  local runner behavior, and foreground at-most-once delivery.
- `docs/v1-account-controls-contract.md` - authenticated timezone, bounded JSON
  export, password recovery, and permanent account deletion boundary.
- `docs/deadline-planner-v1-contract.md` - explicit user-estimated exam/
  assignment preparation, staged dated blocks, confirmation, progress, calendar
  isolation, retry identity, and non-automation boundary.
- `docs/exam-week-outlook-v1-contract.md` - Daily Capture V4 sleep estimates,
  automatic exam-window modes, read-only dual capacity simulation, risk
  warnings, and the Planner-only presentation boundary.
- `docs/setup-personalization-retirement-contract.md` - retired Setup Goals and
  personalization inputs, friction-free Capture compatibility, Daily State V2,
  Coach V2, Reminder ownership, and stored-data cleanup.
- `docs/personal-learning-v1-contract.md` - Focus reflection collection,
  revisioned learning preferences, deterministic 90-day personal patterns,
  optional learned Planner timing, and recommendation cleanup boundaries.
- `docs/frontend-visual-system-v2.md` - Flutter palette, local typography,
  brand, icon, surface, motion, accessibility, and visual source-guard
  contract.
- `README.md` - high-level project overview.

## Next Implementation Direction

The **Intake V1 without LLM** foundation, controlled deterministic
recommendation refresh after authenticated intake, and the authenticated
deterministic snapshot aggregator endpoint now exist. A deliberate dashboard
refresh action calls the deterministic recommendation generate endpoint without
LLM wording. Phase 3 executable tasks, cadence-aware habits, linked focus
sessions, and the strict `executable-action-v1` envelope are implemented for
authenticated real accounts. Snapshots now include additive habit-outcome and
focus-session summaries while preserving Phase 2 Daily State unchanged. Phase
7 extends the backend-only scheduled endpoint into idempotent daily preparation:
one captured UTC instant resolves each eligible profile's local date, missing
snapshots and briefings are created, snapshot-stale briefings are refreshed,
and current pairs are left untouched. Phase 4 persists one strict deterministic
briefing per profile-local date behind read-only GET and deliberate idempotent
POST routes.
The later `today-overview-v2` surface supersedes the briefing-first Today
presentation without removing the persisted briefing backend or the compatible
V1 read. Normal Today load is one read-only owner-scoped overview, with a strict
both-capture streak, transparent dynamic progress, Setup/Planner/Preparation/
Calendar/Focus agenda facts, selected Tasks and Habits without block-based
double counting, isolated partial failures, and lazy supporting detail.
Guest/mock stays local and never fabricates a personalized briefing or overview
fact.
Planner V1 is the central authenticated planning home. Task/Habit changes use
immutable deterministic previews and atomically create or update their target
only at explicit confirmation; Exam/Assignment creation delegates to Deadline
Planner. Manual one-off/weekly commitments are authoritative and conflicts only
create attention. Setup is the primary timetable: recurring commitments may
carry optional inclusive semester dates, onboarding does not ask for calendar
interest, and Planner warns before automatic planning when no current
availability source is visible. Shared Availability considers Setup/manual commitments,
confirmed Planner and Preparation reservations, and separately consented
current imported busy time. It never infers missing duration/deadline/cadence,
moves blocks automatically, writes a calendar, or serves guest/demo fake plans.
Daily Capture V4 adds a required intended sleep start and explicit duration
target to Evening plus aware estimated sleep start/wake instants to Morning.
Only the derived duration leaves `daily_logs.metadata`. The read-only
`exam-week-outlook-v1` Planner card activates from an active exam at 14 days or
less, counts competing assignments without letting them activate the mode, and
compares regular capacity with a hypothetical sleep-protected calculation. It
creates no preview, Notification, Today item, separate sleep profile, or
automatic plan change.
When its development-only surface gate is enabled, Coach replaces the redundant
Settings item as the fifth shell destination. Settings remains available from
the top-right Today control; a gated-off Coach is omitted rather than replaced
by Settings.
Study Setup V1 adds optional focus/recovery rhythm, a transient Focus-start
ritual, and exactly one current/next semester through that same revisioned
Setup. Deadline plans always use a configured rhythm; ordinary Planner Tasks
use it only after explicit opt-in and Habits never do. Recovery is reserved
busy time but not study time or preparation capacity. Rhythm edits invalidate
open previews and mark active Study-bound plans for review without moving them.
The next semester's profile-local course-selection window creates only Planner
attention linked to Settings; it creates no Task, Calendar row, Today item, or
Notification.
Personal Learning V1 adds one editable reflection per terminal Focus session,
revisioned Settings controls, and a read-only profile-timezone 90-day pattern
endpoint. Insights shows transparent sample, coverage, evidence, and
limitations without causal or medical claims. A mature learned daytime window
may softly order only newly requested Task, Exam, and Assignment previews when
both the user preference and the development pilot flag are enabled. Setup
timing and all existing availability rules remain fallbacks; confirmed plans,
sleep targets, capacity, Study rhythm, recovery, Habits, and Coach never change
automatically. Recommendation refresh now uses profile-local structured Focus,
sleep, and measured movement evidence and atomically retires obsolete current
cards while preserving history. Read
`docs/personal-learning-v1-contract.md` before extending this boundary.
Phase 6 adds exact owned-action feedback with idempotent requests, deletable
history, a decayed/capped context match under `feedback-ranking-v1`, and one
cautious default Insight before advanced correlation exploration.
Phase 7 adds bounded per-user failure stages, retry-safe daily identities, an
optional eligible-profile-filtered operational retry, and no hidden Dashboard
generation.
Phase 8 adds one strict `weekly-review-v1` review for an explicit completed
profile-local ISO week. Read paths are side-effect free; deliberate generation
persists only derived facts and at most two proposals. Only explicit
confirmation may reuse the existing exact manual Habit V1 shrink/pause/archive
commands. Setup-owned changes stay in Settings Setup, and replacement plus
goal/task/schedule proposals remain staged and non-mutating.
Phase 9 adds one optional explicitly consented `ical_file` connection and
bounded deliberate `.ics` import. Dedicated imported rows retain stable
read-only provenance; disconnect and local imported-data deletion remain
separate and never mutate `schedule_items` or a source calendar.
Deadline Planner V1 builds on, but does not weaken, those boundaries. A real
authenticated user explicitly enters an exam or assignment, their own total
active-preparation estimate, and prior credit. A deliberate proposal persists
one immutable staged revision with deterministic dated blocks; only explicit
confirmation activates it and creates the stable managed task. Completed
post-activation focus linked to that task contributes measured progress but
never completes the plan. Planning is bounded to 366 days. Calendar-event source
and current-import busy-time use are separate explicit choices; title inference,
provider writes, notifications, LLM use, background sync, and hidden generation
remain absent. Read
`docs/deadline-planner-v1-contract.md` before extending this slice.
The optional account-wide daily preparation budget is explicit user input, not
an AI estimate. When present, proposals deduct confirmed other-plan blocks on
each profile-local date and confirmation rechecks the current rule under the
shared owner lock. Earlier same-day reservations still consume that date's
capacity. Budget changes never rewrite active revisions; the seven-day Today/
Preparation plans projection reports confirmed reservations and separately
labelled weekly Setup commitments, not complete calendar availability.
Expanding a date uses the separate strict read-only
`preparation-workload-detail-v1` contract. It groups only that owner's active
plan reservations, states exact date overage, and may open existing review or
staged replanning UI without choosing a plan or mutating data.
For an active plan without a pending preview, replanning first shows a compact
saved-value review. Opening it performs no request; its explicit primary action
uses the existing proposal contract and remains staged, while `Change values`
opens the full editor. Pending previews and retained conflict drafts keep the
full-editor path, and current reservations remain active until confirmation.
The managed task remains planner-owned: generic Task mutations/editor paths are
forbidden, while starting focus on the open task remains allowed.
These phases do not claim deployed cron wiring. Notification Delivery V1 below
separately adds only consented local deterministic rows and foreground banners,
not push/system delivery.
Read `docs/backend-roadmap.md`,
`docs/daily-briefing-implementation-plan.md`, and the Phase 3 and Phase 8
contracts plus the Phase 9 calendar contract and Phase 10 Coach plan before
planning the next backend, briefing, dashboard, integration, or agent workflow.

Phase 10 Controlled Coach is implemented at the repository boundary. It adds a
bounded authenticated explanation/context/budget contract, explicit memory
selection, persisted validated history, retained usage accounting, and at most
one review-only staged suggestion. Its first real-model provider is deliberately
`local_codex_oauth`: FastAPI may invoke the current
Linux/WSL user's explicitly enabled, already authenticated Codex CLI without an
API key, while OAuth state stays outside Flutter, Supabase, Git, and application
logs. This adapter is local-development-only; another developer must run their
own `codex login`, and the repo must not promise that one model is available to
every Plus/Pro account. Prefer `gpt-5.5` for the normal Coach because this is a
general conversational reasoning/structured-output workflow, not a coding-agent
task. Do not silently fall back to a Codex/Spark model; an unavailable preferred
model is honest configuration, and another developer may explicitly select a
model their account exposes. Standard automation uses the deterministic fake
provider and never requires Codex, OAuth, or a network call. A real-model smoke
is explicitly opt-in and must not be claimed without a recorded current-machine
run.

Do not expand this boundary into broad LLM integration, vector search,
autonomous background agents, model-controlled tools, unreviewed provider
writes, or automatic memory extraction. Live calendar provider OAuth/sync/writes, a
deployable LLM provider, deployed scheduling, and push/background notification
delivery still require their own directly verified contracts.
Notification Lifecycle V1 is implemented at the repository boundary: real
authenticated accounts may mark stored Inbox rows read/unread or dismiss them
through one strict FastAPI/service-role RPC, while guest/mock remains zero-call
and direct authenticated DML remains forbidden. Dismissal is a retained
tombstone, not hard deletion. This does not generate, schedule, or deliver a
notification, and existing reminder preferences are not permission for a new
delivery channel.
Notification Delivery V1 separately adds explicit foreground consent,
deterministic fixed-copy generation from current briefing/recovery or the exact
completed week, the local 15-minute runner, and acknowledged at-most-once
Flutter banners. Guest/demo remains zero-call. It does not enable browser,
Android, push, email, background-mobile, or deployed scheduling.
The scheduler continues missing/stale Phase 7 preparation for eligible profiles,
but selects a fully current profile for a notification-only run only when its
separate in-app consent is active, preventing consent-off current profiles from
consuming the bounded runner batch.
Phase 0A, Honest Capture, is
implemented: `/daily-check-in` redirects to the canonical lightweight flow;
measurements require explicit selection; a typed draft drives guest and Supabase
persistence; same-day guest rows and linked behavioral events are deduplicated;
failed writes retain the draft; guest saves are readable on return; and
value-level widget/data-source/browser assertions cover distinctive values.

Phase 0B, Source And Surface Truth, is implemented. Explicit guest/demo mode is
labeled and stays local; authenticated dashboard, notification, and
recommendation failures no longer become mock content; recommendation feeds
preserve empty/stale/fresh/error semantics; the dashboard shows direct nullable
check-in values instead of proxy scores; notification links use a strict
internal allowlist and Notification Lifecycle V1 later added durable
read/unread/dismiss commands; Coach and the former Deep Work preview were
gated; Settings
contains only durable behavior; and guest users no longer see Supabase-only
habit actions. Phase 3 later replaced the Deep Work preview with a real synced
focus flow. `USE_MOCK_DATA=true` deliberately makes product data surfaces local/
demo even if a Supabase auth session exists; real authenticated sources are used
only with `USE_MOCK_DATA=false`. Mock/demo auth boot does not read or create a
remote profile, and it restores locally applied Setup across reloads.

Phase 0C, First-Run And Setup Integrity, is implemented. Setup now uses explicit
required selections and progressive optional detail; blank optional answers
create no owned records. Guest and authenticated re-entry load a typed saved
setup with loading, error, and retry states. Authenticated saves use
`request_id` plus `base_revision`, converge safely across retries and edits,
and never fall back to direct partial profile/timetable completion. Named
routines remain candidates in the intake response until cadence is explicitly
confirmed. Weekly fixed commitments support optional inclusive semester dates
and duplication across weekdays; calendar import stays outside onboarding.
Active Setup-owned habits and fixed commitments have durable review/edit/
archive, pause, and removal paths without touching manual rows. Goals and
retired personalization answers have no active Setup surface; legacy Setup-owned
Goals are archived while manual and foreign-managed Goals remain compatibility
data.
Setup apply is one database transaction behind a service-role-only RPC. Client
validation and HTTP 4xx failures leave the draft editable, a 409 suggests
reloading server state, and an ambiguous network/5xx/invalid-response result
locks the exact submitted draft for unchanged retry or reload. Setup-owned
habits are edited only through Settings Setup, but active ones remain available
for daily completion in Habit Completion.

Phase 1, Lightweight Evening And Morning Capture, is implemented. Evening
Shutdown and Morning Calibration are separate typed flows over one
`DailyCaptureEntry`. Their same-day merge replaces only the submitted capture
kind under `daily_logs.metadata.captures`, preserves the other kind, and
projects compatible numeric columns with Morning energy taking precedence over
Evening energy. Under `daily-capture-v4`, Evening requires mood, energy, stress,
one planned local sleep time, and a `300..720` minute target on a 15-minute grid;
stress source and controllability are required together at stress `5..10`.
Primary/additional friction and `gentle_tomorrow` are not written. Morning
requires aware estimated sleep-start/wake instants, their derived whole-minute
duration and compatible hours, the target used for that night, a `1..10`
estimated sleep-quality rating, current energy, and day shape. Raw sleep clocks,
target, and source Evening identity remain only in Daily Log metadata; other
consumers receive the derived duration. V2/V3 branches remain readable and may
survive as explicit compatibility branches until edited. Supabase writes
rebuild a dynamic set of at most four deterministically identified current-state
events; guest storage uses V4 daily JSON while continuing to read V1/V2/V3
entries. Real capture writes refresh the explicit local `target_date` snapshot
best-effort, while the backend prefers event `metadata.entry_date` over UTC
timestamps when filtering the broadened read window. Dashboard reads remain
direct and nullable, expose only persisted capture context, and never synthesize
a mode or score. Capture does not rank a briefing, generate a Recommendation,
call an LLM, change a plan, or create an autonomous workflow.

Phase 2, Explainable Daily State, is implemented. Daily and weekly snapshots
add `summary.daily_state` under the `explainable-daily-state-v2` contract. A
strict branch-compatible parser trusts V2/V3/V4 capture metadata only when its
identity, enum, numeric, timestamp, sleep-interval, and numeric-projection
invariants hold; legacy numeric fallback is allowed only when no structured
capture marker exists. Friction is ignored and V1 Daily State is sanitized only
for readable history. Daily State uses a fixed seven-day state lookback
independent of the requested statistics window.
Evening is current on the target date or previous date, Morning only on the
target date. The result exposes `missing`, `partial`, `current`, or `stale`
quality; recovery-first `push`, `steady`, `recover`, or `plan` classification;
bounded risks and reasons with field-level evidence; and deterministic
provenance without persisting capture free text. The existing
`snapshot-aggregator-v1` source marker remains stable, while snapshot metadata
records the Daily State contract version and lookback. Top-level
`summary.risk_flags` aliases the current Daily State codes, older
statistics-window flags live under `summary.window_risk_flags`, and
`recommended_next_focus` is derived recovery-first from the mode. Phase 2 adds
no schema, Today UI, recommendation ranking, briefing persistence, or LLM
usage.

Phase 3, Executable Action And Habit Contracts, is implemented. Authenticated
real accounts can create/edit/complete/postpone/cancel/restore tasks with
estimates and recoverable UI; manage daily, selected-weekday, and weekly-target
habits with explicit completed/skipped outcomes and undo; and start, finish, or
abandon at most one active focus session linked to an owned task or habit.
Setup-owned habit definitions remain owned by Settings Setup while their active
rows remain executable. Habit reads paginate history starting 370 calendar days
before today, and local `started_on` plus calendar-date arithmetic keep progress
stable across DST changes. Every task update, including undo, and every manual
habit definition/lifecycle update reconciles an ambiguous committed response
only by exact owner-scoped timestamp/requested-field readback. Habit outcome
and undo capture one target date before awaiting the write, reconcile the exact
row or its absence, and refresh that same date. Focus finish/abandon uses exact
terminal readback. Terminal focus history rejects every update and linked
targets cannot be deleted out from under it. The strict Flutter/FastAPI
`executable-action-v1` parsers reject the same unknown, explicit-null, coerced,
and mismatched shapes; unsupported commands remain explicit. Phase 8 gives
`review_plan` one real synced navigation handler without making it a mutation.
New focus rows persist the local start `entry_date`; the
migration backfills missing legacy values from the UTC date of `started_at`,
which is also the shared Flutter/FastAPI fallback. Snapshots add bounded
habit/focus counts and evidence from fully paginated, stably ordered 1,000-row
action-fact pages, and `explainable-daily-state-v2` remains unchanged.
Guest/mock sessions expose none of these remote commands.

Today Overview V2 supersedes the visible Phase 5 briefing card while preserving
the V1 read for existing clients. The persisted Phase 4 briefing and Phase 6
feedback contracts remain backend/history inputs, but the app now reads
`GET /v1/today/overview-v2` and leads with the both-capture streak, honest `x/y`
progress, Setup/Planner/Preparation/Calendar/Focus timeline, Today Tasks, and
Today Habits. Existing Phase 3 commands remain the only execution mutations;
supporting workload, reviews, signals, recommendations, feedback history, and
the full week are lazy behind `More`.

Phase 6, Feedback And Useful Insights, is implemented. `done`, `later`,
`not_helpful`, `too_much`, and `does_not_fit` are additional historical evidence
and never execute or rewrite an action. Recent context-matched effects decay,
remain bounded behind recovery/urgency safeguards, and are exposed in briefing
provenance. Users can inspect and delete history. Insights starts with one
non-causal observation, evidence window, confidence/data-quality label, and an
optional bounded experiment.

Phase 7, Scheduled Daily Preparation, is implemented at the backend boundary.
The protected scheduler selects only onboarded non-guest profiles whose exact
profile-local date is missing a snapshot/briefing or has stale briefing
provenance. Preparation reuses current snapshots, creates only missing
prerequisites, converges briefing provenance after overlapping upserts, and
reports sanitized per-user stages without failing the whole batch. A bounded
`profile_ids` filter supports operational retry and isolated E2E. Normal
Dashboard GET remains read-only. The later Notification Delivery V1 local
runner reuses this endpoint with explicit current-day generation, but deployed
cron and every push/background channel remain unclaimed.

Phase 8, Bounded Weekly Review And Habit Adaptation, is implemented through a
strict authenticated FastAPI/Flutter boundary. The latest read resolves one
completed profile-local ISO week and never generates; an explicit POST persists
one `weekly_reviews` identity with exact bounded facts, a canonical source
fingerprint, deterministic/no-baseline/no-LLM provenance, and at most two
proposals. Completed, carried, skipped, missed, unknown, and recovery facts stay
distinct. Only manual Habit V1 shrink/pause/archive proposals are directly
applicable after a before/after confirmation and exact `updated_at` check.
Setup-owned proposals open Settings Setup without a generic write; replace,
defer, goal, task, and schedule proposals remain staged. `review_plan` opens the
real synced weekly-review surface but never generates or applies by itself.

Phase 9, Bounded Calendar File Import, is implemented through one optional
authenticated `ical_file` source. Exact `calendar-import-consent-v1` is required
before connection, and connection alone imports nothing. A deliberate bounded
UTF-8 `.ics` upload reconciles stable request/event/recurrence identities into
dedicated backend-owned rows with imported/read-only provenance. Disconnect
retains the stale local copy; a separate confirmed delete removes imported
local events/history while preserving every `schedule_items` row. Guest/mock is
zero-call. There is no provider OAuth/token, URL fetch, RRULE engine, provider
write, background sync, LLM processing, or automatic calendar-derived action.

Phase 10, Controlled Coach, is implemented through strict authenticated
`coach-request-v1`, `coach-response-v1`, `coach-capabilities-v1`,
`coach-history-v1`, and `coach-memory-selection-v1` boundaries. `/coach` uses
FastAPI only for a real authenticated account; `/more` is an alias. Guest/mock
is zero-call and shows honest local unavailability. FastAPI builds at most
32 KiB of owner-scoped `coach-context-v2` data from current state, briefing,
active facts, a current weekly review, explicitly selected eligible memory, and
up to six completed turns. Imported calendar content, hidden capture/intake
free text, retired Goals/onboarding preferences/coaching style/friction,
credentials, and cross-user rows are excluded. New requests use
`controlled-coach-prompt-v2`; persisted V1 history remains readable. Capability,
history, and memory reads never call a model; every response is a deliberate,
budgeted send. Urgent safety may bypass the provider, and no suggestion can
execute or mutate product state.

FastAPI, Flutter, migration, and browser coverage spans Setup ownership and
retry, Capture V4, Daily State V2, executable Tasks/Habits/Focus, Today,
briefings, feedback, Weekly Review, Calendar Import, Notification lifecycle and
delivery, Planner/Deadline Planner, Exam-Week Outlook, account controls, and the
fake-provider Coach boundary. The browser source includes exact persistence,
retry, cross-owner/RLS, read-only, and guest zero-call assertions. Test source
being present is not evidence that a later checkout passed it.

The sole current exact commit, command counts, E2E identity, and evidence limits
live in
[Current Verified Baseline](docs/verification.md#current-verified-baseline).
Historical results remain in `docs/verification.md` and explicitly historical
reports; do not copy them into current contracts or runbooks. The opt-in
`local_codex_oauth` checks remain machine/account-specific and separate from
standard deterministic verification.

The implemented Intake apply and separate refresh boundaries are backend-owned:

- `GET /v1/intake/setup` derives `user_id` from the verified Supabase bearer
  token and returns the newest `intake-v1` Setup row: the latest pending row for
  an exact retry/resume, otherwise the latest applied revision.
- `POST /v1/intake/complete` derives `user_id` from the verified bearer token
  and acts as both initial completion and revision-checked edit.
- The intake service writes pending/applied `intake_responses` revisions,
  then calls the service-role-only atomic Setup apply RPC. The RPC takes a
  per-user transaction advisory lock; reconciles Habits, schedule/Study rows,
  and the best-energy memory; archives legacy Setup-owned Goals; leaves
  `notification_preferences` byte-for-byte unchanged; upserts the canonical
  `setup:intake-v1` onboarding snapshot; marks the intake applied; and projects
  `profiles.setup_revision`, completion time, and explicit display name in the
  same transaction.
- Applied Setup advances `profiles.setup_revision` monotonically; an older
  worker or replay cannot project stale profile fields over a newer revision.
- Retries reuse `request_id`; edits send `base_revision`. Blank optional values
  materialize nothing, and reconciliation archives/removes only setup-owned
  records while preserving rows from manual or other sources.
- One exact legacy placeholder is removed during reconciliation when omitted:
  unmarked onboarding `Math`, `Room 204`, Monday `08:15`-`09:45`. Other manual
  or unmarked onboarding rows remain preserved.
- Setup completion generates no Recommendation. The separate deterministic
  recommendation engine reads recent `daily_logs`, `behavioral_events`, `tasks`,
  and latest `user_state_snapshots`, verifies candidates, dedupes by fingerprint,
  and persists accepted rows only when its explicit or scheduled boundary is
  invoked.
- Normal dashboard reads through `GET /v1/recommendations` must still not
  generate recommendations.
- The dashboard refresh action is deliberate and calls
  `POST /v1/recommendations/generate` with LLM wording disabled after a
  best-effort daily snapshot refresh. Guest/mock paths must remain local.
- `POST /v1/snapshots/generate` derives `user_id` from the verified Supabase
  bearer token and creates or refreshes deterministic `daily` and `weekly`
  `user_state_snapshots`.
- `POST /v1/scheduled/daily-refresh` is backend-only, uses
  `X-Scheduled-Refresh-Token`, lists onboarded non-guest profiles, resolves one
  local briefing date per profile from one UTC run instant, and prepares missing
  daily snapshots plus missing or snapshot-stale persisted briefings. Current
  pairs remain write-free on retry. An optional bounded `profile_ids` filter is
  backend-only; if recommendation refresh is explicitly included, LLM wording
  remains disabled.
- The canonical Supabase-backed Evening Shutdown and Morning Calibration plus
  authenticated task, habit, and focus writes call daily snapshot refresh
  best-effort after the durable write. Capture refreshes include their explicit
  local `target_date`. Refresh failure never rolls back the original action;
  guest/mock paths remain local and must not call the AI service.

## Local Supabase Workflow

Supabase CLI and Docker are required for local database testing. Use real Ubuntu
tool installations; `supabase --version` and `docker --version` must work in the
Ubuntu shell. The preferred
agent-safe command is:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify_supabase_local.sh
```

This starts the local Supabase stack, redacts CLI key output, reads the local
anon key from `supabase status -o env`, and runs Flutter tests with
`USE_MOCK_DATA=false`.

If Node.js, npm, or Supabase CLI are installed through `nvm`, a non-interactive
agent shell may not inherit that `PATH` even though the commands work in the
user's interactive Ubuntu shell. In that case, source the real nvm environment
or pass a narrow `PATH`/`NODE_BIN` override. Do not install replacement Node or
Supabase binaries into `.tools/`.

For manual local Supabase inspection from the repo root:

```bash
supabase start
supabase status
```

Use the scripted `RESET_DB=true ... scripts/verify_supabase_local.sh` form when
you actually intend to run `supabase db reset`.

`supabase db reset` must complete through:

```text
20260726200000_learned_timing_setup_fallback_provenance.sql
```

Expected local reset notices include skipped legacy CamelCase tables and
already-existing canonical tables. Those notices are normal. Errors are not.
The Phase 3 migration normalizes every positive legacy value to completion and
intentionally errors when a legacy `habit_logs` row has no status and
`value <= 0`; inspect and resolve that row's real meaning rather than
fabricating an intentional skip. All repository scripts inspect
`supabase migration list --local` and fail without applying SQL when repository
files and local database history differ. After reviewing the pending SQL and
local data, use the scripted `APPLY_MIGRATIONS=true` opt-in when the migration
is intended. A pending migration may change or delete local rows; never call it
non-destructive merely because it avoids a reset. Use `RESET_DB=true` only when
proving the full chain on a deliberately fresh local database.

Do not assume the live remote database state from migrations alone. Inspect it
through the Supabase dashboard, CLI, or connector before making claims about the
remote project.

Do not run destructive Supabase commands such as `supabase db reset` unless the
user explicitly asks for that operation or is actively working with you on local
database reset/debugging. Use the scripted form when a local reset is intended:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

Never paste or commit Supabase keys. For the Flutter app, only the local anon key
belongs in `.env`. Never use the service role key in the client.

## Local App Workflow

Create a local `.env` from `.env.example`:

```bash
cp .env.example .env
```

For local Supabase-backed testing:

```env
APP_ENV=development
USE_MOCK_DATA=false
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<local anon key from supabase status>
AI_SERVICE_BASE_URL=http://localhost:8000
```

Start Flutter:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/start_frontend.sh
```

For the complete loopback-only real-data stack, prefer:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/start_local_stack.sh
```

It starts or reuses local Supabase, verifies that its migration history exactly
matches the repository, then starts FastAPI, the sanitized daily-refresh loop,
and Flutter. A mismatch fails closed. After reviewing the pending SQL and local
data, explicitly set `APPLY_MIGRATIONS=true` to apply it; that operation may
change or delete local rows. The default Coach provider is disabled; opt into
`fake` or `local_codex_oauth` with `LOCAL_STACK_COACH_PROVIDER`. The supervisor
must never expose the service-role key or scheduler token to Flutter, logs,
status files, or command arguments, and must never reset or stop Supabase.

Prefer the repo script over ad hoc Flutter commands. If Flutter is not on
`PATH`, ask for or infer a `FLUTTER_BIN` override instead of hard-coding a
machine-specific path in source files.

Open:

```text
http://127.0.0.1:7357
```

Manual smoke test after schema or Supabase-client changes:

- Register or sign in.
- Complete required-only setup, then re-enter it from Settings.
- Add, edit, and review one setup-owned commitment without changing a manual row.
- Save Evening Shutdown through either current route, then save Morning
  Calibration and confirm that both states remain present.
- Create/edit/postpone/complete/undo/cancel/restore one task.
- Create daily, weekday, and weekly-target habits; complete, skip, and undo an
  outcome while preserving Setup ownership.
- Start and finish or abandon a linked focus session without completing its
  target automatically.
- Create a manual exam/assignment preparation proposal with an explicit total
  estimate and prior credit, review its staged blocks, confirm it, and verify
  linked completed focus changes progress without completing the plan.
- If Calendar Import is connected, select one event deliberately and verify
  that optional busy-time use neither infers a deadline nor writes to the
  source calendar.
- Open dashboard.
- Open Inbox (`/alerts`); exercise read/unread/dismiss lifecycle and keep
  generation/delivery explicitly unclaimed.
- Open Coach with a real local account and confirm capability, history, and
  memory reads do not generate. Use the fake provider for ordinary automated
  smoke; enable `local_codex_oauth` only for a deliberate per-machine check.

The browser smoke path is automated through Playwright in `scripts/e2e_web.sh`.
The widget tests still cover the faster guest auth, guest onboarding, and guest
canonical check-in path. See `docs/verification.md` before changing or
claiming E2E coverage.

## Verification Commands

Run these after relevant changes:

```bash
cd apps/mobile
flutter analyze
flutter test
```

If Flutter is not on `PATH`, use:

```bash
cd apps/mobile
/home/gregor/tools/flutter/bin/flutter analyze
/home/gregor/tools/flutter/bin/flutter test
```

From the repo root:

```bash
python3 -m compileall services/ai_service/app
git diff --check
```

Or run the standard non-destructive verification bundle:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh
```

`scripts/verify.sh` runs shell syntax checks, the hermetic local-stack
credential/cleanup harness, the documentation consistency tests/gate, Flutter
dependency resolution, Flutter analysis, Flutter widget tests, Python compile
checks, and `git diff --check`.

For docs and shell scripts:

```bash
bash -n scripts/start_frontend.sh
bash -n scripts/start_local_stack.sh
bash scripts/test_local_supabase_migrations.sh
bash scripts/test_start_local_stack.sh
```

If Supabase migrations changed and a local reset is intended, use the scripted
reset form:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

Do not run a raw `supabase db reset` unless the user explicitly asks for that
operation or you are already debugging the local reset workflow with them.

For the local Supabase-backed preflight workflow:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

This default path only inspects migration history and fails if it differs. To
apply reviewed pending SQL intentionally, set `APPLY_MIGRATIONS=true`; pending
migrations may change or delete local rows.

For the local Supabase reset workflow:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

For browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter bash scripts/e2e_web.sh
```

For a focused Phase 10 diagnosis only, reuse an existing eligible E2E principal:

```bash
E2E_PHASE10_ONLY=true \
E2E_RUN_ID=<existing-e2e-run-id> \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
bash scripts/e2e_web.sh
```

That mode resets and repeats only the existing user's Coach assertions. It
requires the prior E2E user and never substitutes for a full browser run.

Browser E2E also requires real Ubuntu Node.js 20+ and npm. Windows `npm`/`npx`
shims are not sufficient inside this WSL project.
If the interactive Ubuntu shell has Node/Supabase through nvm but the agent
shell cannot find them, run with the real nvm bin directory on `PATH` or set
`NODE_BIN`; keep using the actual installed tools.

For browser E2E with a fresh local database:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
bash scripts/e2e_web.sh
```

If browser E2E reports that local database history differs from repository
migrations, review the pending SQL and local rows first. Re-run the same command
with `APPLY_MIGRATIONS=true` only when those data changes are intended. Use
`RESET_DB=true` only when a fresh local database is deliberately intended.

The E2E script may read the local service-role key from `supabase status -o env`
for FastAPI backend settings plus Node-side local test user creation and
database assertions. Never pass the service-role key into Flutter, browser code,
docs examples, or chat output.

## Documentation Requirement

Documentation is part of the Definition of Done, not a later cleanup task.
Before changing behavior, identify the owning contract or runbook from
`Start Here`; update it in the same change as the implementation. A task is not
complete while current docs describe an older route, contract version,
migration boundary, source of truth, UI behavior, command, or verification
state.

At minimum, keep these owners aligned:

- Schema, RLS, grants, RPCs, or migrations: `docs/supabase-current-state.md`
  and the migration inventory in this file.
- FastAPI/Flutter data flow or authority boundary: `docs/architecture.md` plus
  the owning feature contract.
- Public FastAPI route or payload contract: `services/ai_service/README.md`
  plus the owning feature contract and affected client docs.
- Flutter surface, navigation, persistence, or copy: `apps/mobile/README.md`
  plus the owning feature and copy contracts.
- Local setup, environment, or command: `docs/local-dev.md`.
- Agent workflow or safety: this `AGENTS.md`.
- Verification automation or evidence: `docs/verification.md`; link commands
  from `docs/local-dev.md` and never treat test-source presence as a pass.

`docs/verification.md#current-verified-baseline` is the sole current source for
exact verification counts, commit ids, and E2E identities. Other current docs
must link to it rather than copy those values. A dated report may retain its
checkout-local evidence only when its opening metadata explicitly contains
`Status: historical`; such evidence never proves the current checkout.

Before handing off any repository change:

1. Review changed code, schema, scripts, tests, and docs together for
   documentation impact.
2. Update status dates, compatibility language, examples, and non-claims where
   behavior changed.
3. Run `npm run verify:docs`. The check validates links, canonical contract
   versions, current migration references, documented FastAPI routes,
   duplicated verification evidence, known stale claims, and changed-file
   documentation ownership.
4. Run the relevant product checks and `git diff --check`.

The docs-impact check compares the working tree with `HEAD` by default. The
GitHub workflow supplies the push or pull-request base through `DOCS_BASE_REF`;
a manual feature-branch audit should do the same so committed branch changes are
checked too. Do not leave future agents to reconstruct changed behavior from
terminal history.

## Environment And Secrets

`.env` is intentionally ignored by git. Agents may technically read it in the
local workspace if needed to run the project, but must treat it as secret
material:

- Do not print `.env` contents in chat or logs.
- Do not commit `.env`.
- Do not copy keys into docs.
- Prefer asking the user to paste redacted command output.
- If a value is needed for a command, pass it through the existing scripts or
  environment, not through committed files.

Local Supabase anon keys are acceptable in `.env` for local development only.
Production service-role keys must never be used in the Flutter app.

Local Codex OAuth state is user-private secret material too. Agents must never
read, print, copy, parse, commit, or move `~/.codex/auth.json` or equivalent
files. Phase 10 may check sanitized CLI capability through commands such as
`codex login status`; authentication itself remains a manual per-Linux-user
step. A Codex subprocess must receive an allowlisted environment that excludes
Supabase keys and application secrets.

## Working Tree Safety

This repo may contain user changes. Do not revert unrelated files. In
particular, dependency lockfiles may change after running package managers; call
that out clearly instead of silently discarding it.

Before broad edits, inspect `git status --short`. If a file already has changes,
read it carefully and work with those changes instead of overwriting them.
