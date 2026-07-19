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
16. `docs/ui-language-and-copy-contract.md` before changing student-facing
    names, capability claims, retry copy, localization, or large-text behavior
17. `docs/product-review-handoff.md` when starting a fresh whole-product review
    of Deadline Planner and the current usability-polish slice

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
- `intake_responses`, `user_state_snapshots`
- `daily_briefings`, `decision_feedback`, `weekly_reviews`
- `calendar_connections`, `calendar_imports`, `calendar_events`
- `calendar_request_identities`
- `coach_requests`, `coach_usage_events`, `coach_memory_selections`
- `deadline_plans`, `deadline_plan_revisions`, `deadline_plan_blocks`
- `deadline_plan_request_identities`

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
restores the one missing backend `SELECT` grant required by the existing
31-table Account Export V1 contract. It grants only `service_role` read access
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
`supabase/migrations/20260719120000_account_preparation_budget_v1.sql` adds the
nullable `25..480` five-minute account-wide preparation rule, revokes direct
application-role writes to that profile column, and exposes only an owner-
locked service-role setter. Deadline-plan confirmation rechecks aggregate active
minutes on the candidate revision's local dates at the database boundary.

## Important Docs

- `docs/architecture.md` - system shape and current backend/frontend boundary.
- `docs/backend-roadmap.md` - target backend flow, product agents, data model
  direction, LLM cost controls, and the next implementation sequence.
- `docs/daily-briefing-implementation-plan.md` - current product direction for
  the daily decision loop, lightweight capture cadence, stress taxonomy, Daily
  Mode, briefing service, and next implementation phases.
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
Phase 5 now consumes that contract in a decision-first Today Dashboard: normal
load is GET-only, missing/stale/error truth stays visible, stale actions are
disabled until deliberate adjustment, and validated primary/support targets
dispatch through the existing Phase 3 handlers. Guest/mock remains local and
never fabricates a personalized briefing.
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
confirmed. Setup-owned goals, active habits, and fixed commitments have durable
review/edit/archive, pause, and removal paths without touching manual rows.
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
Evening energy. Supabase writes rebuild a dynamic set of at most four
deterministically identified current-state events; guest storage uses V2 daily
JSON while continuing to read and migrate V1 guest check-ins. Real capture
writes refresh the explicit local `target_date` snapshot best-effort, while the
backend prefers event `metadata.entry_date` over UTC timestamps when filtering
the broadened read window. Dashboard reads remain direct and nullable, expose
only persisted capture context, and never synthesize a mode or score. Phase 1
does not add Daily Mode, briefing ranking or persistence, recommendation
generation on save, an LLM, calendar import, or autonomous workers. The Phase
0C Setup service-role RPC and its retry/revision contract are unchanged.

Phase 2, Explainable Daily State, is implemented. Daily and weekly snapshots
add `summary.daily_state` under the `explainable-daily-state-v1` contract. A
strict parser trusts Phase 1 V2 capture metadata only when its identity, enum,
numeric, timestamp, and numeric-projection invariants hold; legacy numeric
fallback is allowed only when no V2 marker exists. Daily State uses a fixed
seven-day state lookback independent of the requested statistics window.
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
action-fact pages, and `explainable-daily-state-v1` remains unchanged.
Guest/mock sessions expose none of these remote commands.

Phase 5, Decision-First Today Dashboard, is implemented. It consumes the
persisted Phase 4 briefing without generation on normal load, puts mode,
capacity, freshness, and one strict primary action above secondary metrics,
dispatches validated actions through Phase 3, and preserves
missing/stale/error/demo truth.

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
32 KiB of owner-scoped `coach-context-v1` data from current state, briefing,
active facts, a current weekly review, explicitly selected eligible memory, and
up to six completed turns. Imported calendar content, hidden capture/intake
free text, credentials, and cross-user rows are excluded. Capability, history,
and memory reads never call a model; every response is a deliberate, budgeted
send. Urgent safety may bypass the provider, and no suggestion can execute or
mutate product state.

FastAPI-backed browser E2E coverage for revisioned Setup ownership/retry/edit,
concurrent same-request convergence, post-intake recommendations, exact Phase 2
Daily State recomputation, daily snapshot refresh, deliberate dashboard
recommendation refresh, and Supabase-backed habit management now exists.
Phase 3 adds focused Flutter/FastAPI tests, but its task/habit/focus database
journeys are also encoded as exact Playwright/database assertions, including
committed-response-loss reconciliation for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish. Negative writes
cover lifecycle/range/cadence constraints and every terminal focus update,
including `updated_at`. Phase 4 adds exact read-only/generate, persisted action,
and idempotent daily-identity assertions. Phase 5 adds GET-only Dashboard load,
honest briefing state, deliberate `force=true` adjustment, and real primary
action dispatch. Phase 6 adds exact feedback create/history/delete, bounded
ranking provenance, correction back to zero influence, and the cautious default
Insight before advanced correlations. Phase 7 replaces the first manual briefing
generation in that journey with a token-protected, single-profile scheduled
preparation and verifies local-date, snapshot/briefing identity, no-LLM
provenance, and a write-free retry.
Phase 8 extends that source journey with read-only missing truth, deliberate
weekly generation, exact persisted facts/proposals, confirmed manual Habit V1
adaptation, Setup ownership, stale/refresh behavior, and review-table RLS.
Phase 9 source assertions extend the journey with consent, connect-without-
import, retry-safe `.ics` reconciliation, paginated read-only events,
disconnect-retains, local delete, schedule preservation, and integration-table
RLS. The combined Phase 3/4/5/6/7/8/9 browser journey passed non-destructively
in the 2026-07-13 Phase 9 implementation checkout. Later changes must still
establish their own current-checkout pass before claiming E2E.
Phase 10 source uses only the deterministic fake provider for deliberate send,
replay/conflict, safety bypass, exact persistence, memory selection, history
delete/tombstones, ownership/RLS, UI provenance, and guest zero-call assertions.
The opt-in synthetic `local_codex_oauth` smoke completed on 2026-07-13 against
the explicitly requested `gpt-5.5` model (`1 passed`), with no fallback and no
answer, prompt, or raw event stream logged. Real local PostgreSQL parallel lock
smokes also completed without deadlock or timeout and converged the
claim/completion/deletion outcomes. A focused fake-provider Phase 10 browser
rerun and the subsequent full non-destructive browser journey both passed on
the current checkout against local Supabase; the full run reported
`E2E browser smoke passed for e2e-1783947134@example.test`. These checks
establish only this machine's local/provider boundaries, not remote Supabase,
production readiness, or a second developer's account. A separate authenticated
Flutter -> FastAPI -> `local_codex_oauth` -> same-user Codex CLI live turn also
passed non-destructively on 2026-07-13 with explicit `gpt-5.5`, strict validated
and persisted response provenance, visible UI data-use/provider truth, and no
question/prompt/answer/raw-event logging. The different-Linux-user clone/login
acceptance remains open.

After explicit local migration authorization, Notification Delivery V1's base
`20260714130000_notification_delivery_v1.sql` and the reviewed follow-up
`20260714143000_notification_delivery_settings_guard.sql` were applied to the
local stack on 2026-07-14; local history matches the repository. A rollback-only
database smoke verified exact replay, expected-revision conflict, Setup-style
monotone timestamps, consent ordering, and request-identity invalidation. The
full non-reset current-checkout browser journey then passed with
`E2E browser smoke passed for e2e-1784046486@example.test`. It exercised exact
foreground consent, settings replay/conflict, deterministic scheduler
generation, category/quiet/cap rejection, UUIDv5 dedupe, receipt replay,
privacy-safe provenance, acknowledged banner display, and fresh Inbox display.
That run proves only this local fake-provider stack; it adds no push/system,
background-mobile, deployed scheduler, remote Supabase, or live-provider claim.

Deadline Planner V1's final local migration/rollback smoke and the full
non-reset combined current-checkout browser journey passed on 2026-07-18. The
browser run reported
`E2E browser smoke passed for e2e-1784390610@example.test` and exercised manual
and selected-calendar proposals, draft discard, confirmation/replanning,
managed-task focus progress, bounded Dashboard reads, Calendar non-mutation,
RLS/ledger isolation, Account Export/deletion, and guest zero-call. This remains
a local fake-provider claim, not a remote migration, installed-device,
long-term-outcome, provider-calendar, push, or background-replanning claim.

After explicit local authorization, the account-wide preparation-capacity
migration was applied without a reset on 2026-07-19. The final local history
matched the repository; the complete FastAPI suite reported
`763 passed, 1 skipped`, the standard gate and non-reset Supabase preflight each
passed all `601` Flutter tests with clean analysis, and the full browser journey
reported `E2E browser smoke passed for e2e-1784448992@example.test`. It exercised
the exact Settings save, direct-write denial, seven-day projection, changed-
budget confirmation conflict, cross-owner isolation, and guest zero-call. This
is local evidence only and makes no remote migration, installed-device,
participant-study, long-term-outcome, provider-calendar, push/background, or
production-Coach claim.

The compatible actionable workload-day follow-up then completed locally on
2026-07-19 without another migration. The complete FastAPI suite reported
`766 passed, 1 skipped`; the standard gate and non-reset Supabase verification
each passed all `608` Flutter tests with clean analysis and matching history.
The final full browser journey reported
`E2E browser smoke passed for e2e-1784465767@example.test` after exposing and
fixing a nested Bottom Sheet whose barrier did not cover Shell navigation. The
passing run covers strict owner/date detail, cross-owner emptiness, deliberate
review/replan navigation, and modal cancellation without mutation. It adds no
remote, installed-device, participant, background, provider, localization, or
longitudinal claim.

The implemented post-intake refresh is backend-only and best-effort:

- `GET /v1/intake/setup` derives `user_id` from the verified Supabase bearer
  token and returns the newest `intake-v1` Setup row: the latest pending row for
  an exact retry/resume, otherwise the latest applied revision.
- `POST /v1/intake/complete` derives `user_id` from the verified bearer token
  and acts as both initial completion and revision-checked edit.
- The intake service writes pending/applied `intake_responses` revisions,
  then calls the service-role-only atomic Setup apply RPC. The RPC takes a
  per-user transaction advisory lock; reconciles notification preferences and
  Setup-owned goals, habits, schedule items, and memories; upserts the canonical
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
- It then calls the deterministic recommendation engine with no LLM usage.
- The recommendation engine reads recent `daily_logs`, `behavioral_events`,
  `tasks`, and latest `user_state_snapshots`, verifies candidates, dedupes by
  fingerprint, and persists accepted rows to `recommendations`.
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
20260714103000_application_table_privilege_guard.sql
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
credential/cleanup harness, Flutter dependency resolution, Flutter analysis,
Flutter widget tests, Python compile checks, and `git diff --check`.

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

Documentation must stay current. After any significant change to schema,
startup flow, configuration, architecture, environment variables, deployment, or
agent workflow, update the relevant docs in the same change.

At minimum:

- Schema or RLS changes: update `docs/supabase-current-state.md`.
- Backend/frontend boundary changes: update `docs/architecture.md`.
- Local setup or command changes: update `docs/local-dev.md`.
- Agent workflow or safety changes: update this `AGENTS.md`.
- Verification workflow changes: update `docs/verification.md` and link any
  changed commands from `docs/local-dev.md`.

Do not leave future agents to rediscover changed setup steps from terminal
history.

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
