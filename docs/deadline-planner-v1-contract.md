# Deadline Planner V1 Contract

Deadline Planner V1 turns one explicit exam or assignment deadline plus the
user's own preparation estimate into a reviewable set of dated focus blocks.
It is deterministic, authenticated, retry-safe, and no-LLM. It does not infer
that a calendar event is a deadline and never writes to a source calendar.

## Product Boundary

The user deliberately starts the flow from either:

- `Plan exam or assignment`, where they enter a manual title and deadline; or
- `Plan preparation` on one explicitly selected imported calendar event.

The flow always asks the user to choose `exam` or `assignment` and to enter:

- `estimated_total_minutes`, from 30 through 30,000; and
- `credited_prior_minutes`, from zero to strictly less than that estimate.

Active preparation means deliberate working or study time, not elapsed days,
classes, breaks, or calendar occupancy. The backend never invents either value
from the title, event duration, event type, another user's data, or an LLM.
Suggested duration chips are UI shortcuts only: no value is submitted until the
user explicitly selects or enters it. The UI states that it cannot estimate
effort for the user and offers topics multiplied by sessions per topic and
minutes per session only as a transparent estimation aid.

`credited_prior_minutes` is work the plan will not credit automatically. This
includes preparation completed before the plan's first activation and Focus
linked to another task. The user must not re-enter qualifying linked Focus that
the plan already shows, because that would double-count it.

Progress reports `accounted_minutes` as the estimate-bounded sum of prior
credit and qualifying completed focus time, plus exact `remaining_minutes` and
a non-mutating `completion_suggested` flag. The original estimate and original
prior credit remain durable even after a later explicit revision changes the
current estimate. Actual time may exceed either estimate; it is not clamped or
rewritten to make the estimate appear accurate.

## Proposal, Revision, And Confirmation

`deadline-plan-v1` uses immutable revisions:

1. A deliberate proposal request creates one `draft` plan when needed, one
   `proposed` revision, and its deterministic dated blocks.
2. A later proposal for the same plan creates another staged revision. It does
   not replace the currently `active` revision; only an older pending proposal
   becomes `superseded`.
3. Only explicit confirmation atomically activates the selected staged
   revision and its blocks and supersedes the previously active revision.
4. The previously active revision remains authoritative until that transaction
   commits. A failed, stale, or abandoned proposal therefore cannot silently
   change the user's plan.
5. The first successful confirmation also creates the plan's one managed
   `todo` task with `task.id = plan.id`, `estimated_minutes = null`, and
   `deadline-plan-v1` source metadata. Later confirmations retain that identity
   and, only while the task remains open, update exactly its title, deadline,
   and `updated_at` projection.

The managed task is a Phase 3-compatible focus target but remains planner-owned.
Generic task edit/complete/postpone/cancel/restore commands and the ordinary task
editor reject it and direct the user to `/preparation-plans`; starting focus on
the open task remains allowed. Explicit plan completion atomically projects the
task to `done` with its completion timestamp, and explicit plan cancellation
projects it to `cancelled` with its cancellation timestamp. Confirming a plan
does not start focus, complete work, or mutate an imported event. Cancelling or
completing an activated deadline plan requires its current active revision.
Cancellation also supports discarding a still-draft plan: it supersedes the
pending preview and its proposed blocks without creating or mutating a managed
task; the cancelled detail retains `current_revision = 0` and exposes no active
or pending revision. Plan status is exactly `draft`, `active`, `completed`, or
`cancelled`; neither terminal state is
inferred from time, deadline passage, task state, focus duration, or calendar
changes.

The plan identity distinguishes `current_revision` from `latest_revision`.
`current_revision` is zero before first activation and otherwise identifies the
currently confirmed revision. `latest_revision` identifies the newest persisted
sequence, including a pending or superseded proposal, and is at least one after
plan creation. Proposal `base_revision` must equal `latest_revision`; a new
proposal can never be based only on the older active projection.

Each block belongs to exactly one immutable revision and has one profile-local
date, aware start/end instants, and a `5..240` minute planned duration. One
revision contains at most 120 blocks. Persisted revision and block state is
exactly `proposed`, `active`, or `superseded`; public block progress is derived
as `proposed`, `upcoming`, `partial`, `completed`, or `missed`. Blocks are app-
owned reservations, not recurring `schedule_items` and not provider-calendar
events. An uncredited active block uses the half-open interval
`[starts_at, ends_at)` and is therefore `missed` at `now >= ends_at`, including
the exact end instant.

If all requested preparation time cannot fit before the deadline, the proposal
returns the exact unallocated minutes for explicit review. It never hides the
deficit, schedules work after the deadline, or fabricates available time.

When the owner has a current Study focus rhythm, Deadline Planner must use it.
Every normal block is exactly the saved focus duration and only the final
remaining block may be shorter. A smaller free gap is left unused and its
minutes remain visibly unscheduled. Each block reserves the full saved recovery
duration after focus. Preview and agenda projections expose both durations and
the complete `reserved_ends_at`.

Recovery is not active preparation: it is excluded from `planned_minutes`,
progress, the revision's per-plan daily cap, and the account-wide preparation
budget. Availability and database confirmation nevertheless treat
`[starts_at, reserved_ends_at)` as busy, so another reservation cannot occupy
the recovery period.

Every revision freezes the focus progress visible when it was proposed as
`tracked_focus_minutes_at_proposal`. Its proposal budget is exact:

```text
remaining_minutes_at_proposal = max(
  0,
  estimated_total_minutes - credited_prior_minutes
    - tracked_focus_minutes_at_proposal
)
planned_minutes + unscheduled_minutes = remaining_minutes_at_proposal
```

`planned_minutes` must also equal the sum of that revision's block durations.
A proposed revision has neither `activated_at` nor `superseded_at`; an active
revision has `activated_at` only. Superseding a formerly active revision keeps
its original `activated_at` and adds `superseded_at`, while a superseded pending
proposal has only `superseded_at`. This preserves whether a revision ever
governed the user's plan.

## Progress

After the first revision is active, a completed `focus_sessions` row contributes
its measured `actual_minutes` when it:

- belongs to the same owner;
- targets the plan's managed task;
- started no earlier than the plan's first activation; and
- has exact terminal status `completed`.

Active and abandoned sessions do not contribute. A completed linked session
updates derived progress but never completes the managed task, a block, or the
deadline plan implicitly. The user remains the authority for plan completion.
Existing Phase 3 terminal-focus immutability and target ownership checks remain
unchanged. Focus completed before first activation or against another task is
not discoverable as qualifying plan progress and must be entered deliberately
as prior credit if the user wants it included.

## Calendar And Busy-Time Use

A manual plan has no calendar dependency. An imported-event plan requires one
event that the user explicitly selected; the request pins its owner-scoped
event id and current source fingerprint. The user still chooses the plan kind,
title, deadline, and preparation estimate. Event-title matching or automatic
classification is forbidden.

Imported event data remains read-only. Re-import, disconnect, or local imported
data deletion never rewrites, completes, or deletes a confirmed deadline plan.
A stale or mismatched event fingerprint prevents a new event-derived proposal
until the user reloads current state.

Calendar busy-time consideration is a separate per-plan choice. It is off
unless the user enables it for that proposal. When enabled, the deterministic
planner first requires one connected owner source whose imported data has not
been deleted and whose `last_import_id` is non-null. It may use only `busy`
timed/all-day rows belonging to exactly that current import. Disconnected,
deleted, or never-imported availability is a conflict, not an empty calendar.
Here, `current import` means the latest completed file import recorded by the
app, not live provider state or a freshness-age guarantee. The student must
re-import after source-calendar changes; there is no background refresh.
The planner does not broaden consent, inspect hidden calendar fields, contact a
provider, or persist event content in plan blocks. The revision records
`use_calendar_availability`; its planning fingerprint covers the exact bounded
busy intervals consumed without claiming a separate provider/source
fingerprint. Manual commitments and already confirmed deadline blocks remain
capacity constraints independently of this optional calendar input.

## Deterministic Planning

The service captures one aware server instant, resolves the stored profile IANA
timezone once, and uses profile-local calendar arithmetic. Given the same
captured instant, strict request, current estimate, availability inputs, and
source fingerprints, it returns the same ordered blocks and planning
fingerprint. Exact request replay returns the already persisted revision rather
than recalculating against later context. The strict HTTP detail remains a read
of the plan's current projection, so a replay after a later successful operation
may expose that newer state instead of reproducing an obsolete response body.

Planning is bounded to at most 366 calendar days from `planning_start_on` to the
profile-local deadline day, plus the contract's text, minute, and 120-block
limits. The request includes `planning_start_on`, `preferred_session_minutes`
from 25 through 180, `max_daily_minutes` from 25 through 480 and no smaller
than the preferred session, and `buffer_days` from zero through seven. It
respects:

- the deadline and explicit planning window;
- the user's selected block duration and daily availability;
- fixed app commitments and confirmed preparation blocks; and
- current imported busy intervals only when explicitly enabled.

`max_daily_minutes` is always the cap for this plan revision. The user may also
set one nullable account-wide daily preparation budget in Settings. Without
that setting, the previous per-plan-only behavior remains unchanged. With it,
each new proposal subtracts every confirmed block from other plans on the same
profile-local date and may use only the smaller of the remaining account
capacity and this plan's remaining per-plan capacity. Confirmed blocks earlier
on the current local date still consume capacity even when their time interval
has already ended. Blocks from every plan remain non-overlapping independently
of either minute cap.

The revision's planning fingerprint also covers the current
`study_setup_revision` and recovery duration. Confirmation rechecks both under
the shared owner lock and uses full recovery ends in every competing-reservation
test. A Study edit makes a pending revision stale and an active plan visible
under Planner `Needs attention`; it never changes the active revision. Only a
fresh proposal followed by explicit confirmation can replace reservations.
When no Study rhythm is configured, all prior block-splitting and zero-recovery
behavior remains unchanged.

The ordered rule-based planning windows are frozen by
`best_energy_window`:

| Profile answer | First window | Fallback windows |
| --- | --- | --- |
| `early_morning` | 06:00–11:00 | 13:00–17:00, 18:00–21:00 |
| `morning` | 08:00–13:00 | 14:00–18:00, 18:00–21:00 |
| `afternoon` | 13:00–18:00 | 09:00–12:00, 18:00–21:00 |
| `evening` | 18:00–23:00 | 14:00–17:00, 09:00–12:00 |
| `variable` | 09:00–12:00 | 14:00–18:00, 18:00–21:00 |

The planner tries these windows in order after subtracting current time and
busy intervals. They are deterministic defaults, not AI-selected availability.

`buffer_days` counts complete profile-local calendar days that must remain free
immediately before the deadline day. For example, a value of one leaves the
whole preceding day clear, so the last preferred preparation day is two dates
before the deadline. A value of zero may use the deadline day up to the exact
aware `deadline_at`. Flutter labels these as clear days and normalizes a saved
past `planning_start_on` to the current device date when opening a new replan;
the backend still clamps effective planning to its profile-local current date.

DST gaps or ambiguous local wall times are rejected or avoided rather than
guessed. The planner has no LLM/provider call or model-provenance field; its
bounded input and deterministic planning fingerprint are the persisted truth.
Normal reads, calendar imports, Dashboard loads, scheduled refreshes, and focus
completion never generate or revise a plan.

## Account-Wide Capacity And Seven-Day Workload

The nullable `profiles.daily_preparation_budget_minutes` is explicit user input
from 25 through 480 in five-minute increments. It is a transparent scheduling
rule, not an effort estimate, inferred availability, recommendation, or LLM
output. `null` removes only the account-wide rule; every revision's explicit
`max_daily_minutes` still applies.

Changing the setting takes the same owner advisory lock as Deadline Planner
mutations. Confirmation rechecks the candidate revision plus active blocks from
other plans on each candidate local date while that lock is held. If the budget
or another plan changed after preview, confirmation fails with exact `409`
detail `Daily preparation budget is exceeded. Create a fresh preview.` and
retains the staged revision for review or cancellation. The user must create a
fresh preview; the backend does not silently shrink or move blocks.

Lowering or removing a budget never edits an existing active revision. Existing
dates above a newly lowered budget remain truthful overages marked `Needs
review`; explicit replanning is the only way to replace them. Qualifying Focus
time continues to reduce the plan's remaining effort at the next proposal, but
it does not silently release or rewrite an already confirmed reservation.

`GET /v1/deadline-plans/workload` is side-effect free and returns exactly seven
consecutive profile-local dates starting today under
`contract_version=preparation-workload-v1` and
`origin=authenticated_backend`. Each day reports active confirmed preparation
minutes, distinct active-plan count, nullable remaining account capacity,
explicit overage, and merged recurring `schedule_items` duration for that ISO
weekday. The latter is labelled `weekly setup commitments`: it is context, not
part of the preparation-budget arithmetic. A Setup commitment contributes only
on dates inside its optional inclusive validity range; older and undated rows
remain unbounded. Proposed blocks, task estimates,
Focus history, imported calendar busy rows, and live provider availability are
not included. The response therefore does not claim to be a complete free-time
or total-workload calculation.

`GET /v1/deadline-plans/workload/{local_date}` is a separate strict read under
`contract_version=preparation-workload-detail-v1`. Keeping it separate leaves
the exact `preparation-workload-v1` response compatible with existing strict
clients. `local_date` must be one of the current seven profile-local dates;
another date is `422` and does not broaden the projection into history. The
detail returns the current budget arithmetic plus at most 50 unique active-plan
contributions. Each contribution contains only the owner-scoped plan id,
current confirmed title, reserved minutes on that date, and active block count.
Contributions are ordered by reserved minutes descending, then case-insensitive
title and plan id. Their minute sum must equal the detail total.

For an over-budget date, `over_budget_minutes` is the exact minimum amount that
must leave that date to fit the current account rule. It does not prescribe
which plan to change or promise that a valid replan can move exactly that amount
without other changes: session size, busy intervals, buffers, and deadlines
still govern a new proposal. The read excludes proposed blocks, Focus history,
weekly Setup commitments, and imported-calendar availability. It performs no
mutation, recommendation, or LLM call.

## HTTP Boundary

All routes require the normal verified Supabase bearer token and derive the
owner only from that principal:

```text
GET  /v1/deadline-plans
GET  /v1/deadline-plans/workload
GET  /v1/deadline-plans/workload/{local_date}
GET  /v1/deadline-plans/{plan_id}
POST /v1/deadline-plans/proposals
POST /v1/deadline-plans/{plan_id}/confirm
POST /v1/deadline-plans/{plan_id}/complete
POST /v1/deadline-plans/{plan_id}/cancel
Authorization: Bearer <supabase_access_token>
```

GET is side-effect free. It never creates a task, revision, block, calendar
copy, notification, recommendation, or briefing. Unknown and other-owner ids
share the same not-found behavior.

Each POST contains one stable UUID `request_id` and the exact command-specific
payload. Proposal creation accepts only `request_id`, client-stable `plan_id`,
`base_revision`, `kind`, `title`, aware `deadline_at`,
`estimated_total_minutes`, `credited_prior_minutes`,
`preferred_session_minutes`, `max_daily_minutes`, `planning_start_on`,
`buffer_days`, `source_kind`, the source-specific calendar fields, and
`use_calendar_availability`. `source_kind` is exactly `manual` or
`calendar_event`; only the latter accepts `source_calendar_event_id` and one
lowercase SHA-256 `source_calendar_event_fingerprint`. Confirm, complete, and
cancel accept only `request_id` plus `expected_revision`; confirmation expects
the pending proposed revision, completion requires an active plan and expects
`current_revision`, and cancellation accepts either that active revision or a
draft plan's `latest_revision`. Unknown, explicit-null, coerced, whitespace-
normalized, out-of-range, or command-inapplicable fields are rejected.

The same request identity and exact payload replays the persisted operation
without another mutation or recalculation, then returns the plan's current
detail projection. This can be newer than the detail returned by the original
request.
Reuse with another owner, plan, operation, base revision, or payload is `409`
conflict.
An ambiguous Flutter result retains the exact submitted request for unchanged
retry or explicit reload. A stale base revision never overwrites newer state.

The workload routes use the separate strict responses described above. The
strict detail response exposes exactly one plan identity with both revision
counters, nullable
`active_revision`, nullable `pending_revision`, and derived `progress`, wrapped
with `contract_version=deadline-plan-v1` and
`origin=authenticated_backend`. A revision includes its exact timezone,
`best_energy_window`, source status, lowercase planning fingerprint, planned
and unscheduled minute totals, proposal-time tracked/remaining minutes, exact
lifecycle timestamps, and at most 120 blocks. The collection response returns
at most 50 details and fabricates neither an active nor a pending revision.

## Persistence And Authority

The canonical planning tables are:

- `deadline_plans`: owner, source, immutable original estimate and credited
  prior time, current lifecycle, managed-task identity, and active/pending
  revision projections;
- `deadline_plan_revisions`: immutable explicit estimate, planning inputs,
  source fingerprint, deterministic result, and confirmation state;
- `deadline_plan_blocks`: immutable dated blocks owned by one revision; and
- `deadline_plan_request_identities`: minimal backend anti-replay identity for
  owner, plan, operation, and request fingerprint.

`20260723120000_study_setup_v1.sql` adds nullable
`study_setup_revision` and zero-or-configured `recovery_minutes` to revisions,
plus `recovery_minutes` and `reserved_ends_at` to blocks. Existing blocks are
backfilled with zero recovery and their prior end. Study-aware proposal and
confirmation wrappers remain service-role-only and preserve the established
RPC signatures and retry identity.

The mutation RPCs take the shared owner advisory lock and apply request claim,
revision/block writes, first-confirm task creation, and plan projection changes
atomically. Composite owner references and database checks prevent cross-owner
plan, revision, block, task, or calendar linkage.

The optional account rule is stored on the owner profile. Only the verified
FastAPI/service-role path may call `set_daily_preparation_budget_v1`; direct
anonymous or authenticated updates to that profile column are revoked. The
confirmation trigger provides a database-boundary recheck under the same owner
lock, so concurrent plan confirmations or a concurrent budget update cannot
bypass the aggregate cap.

All four tables use forced RLS. Authenticated owners may read the intended plan,
revision, and block projections but cannot mutate them directly. The request
ledger is backend-only. `anon` has no access; service-role mutation is available
only through the reviewed backend workflow and service-role-only RPCs.

Account deletion cascades plan data. Account Export includes
`deadline_plans`, `deadline_plan_revisions`, and `deadline_plan_blocks` with
bounded owner-scoped rows. The opaque request ledger is named as an omitted
backend anti-replay ledger and exports no request fingerprint.

## Flutter Surface

The authenticated synced surface is `/preparation-plans`, titled
`Preparation plans`. Quick Action exposes `Plan exam or assignment`; an
eligible imported event exposes `Plan preparation`. Calendar navigation may
carry only the selected opaque event id. The destination reads its current
title, time, and source fingerprint through owner-scoped Calendar RLS before
prefilling them; the wizard still requires the user's explicit classification
and estimate.

Settings exposes the optional account-wide daily budget with explicit rule-based
copy and no AI claim. Today and Preparation plans show the authenticated seven-
day workload, including honest loading, unavailable, over-budget, and no-budget
states; guest/mock makes zero workload calls. A date with confirmed plans can
be expanded deliberately. Its independently loaded detail keeps loading,
failure, and changed-since-summary states visible, lists the contributing plans,
and states the exact minimum date overage when present. `Review plan` opens the
existing owner-scoped plan surface. For an active plan without a pending
revision, `Replan remaining time` first opens a compact review of the active
revision's saved estimate, credit, current tracked Focus, remaining effort,
deadline, split preferences, normalized planning start, imported-busy-time
choice, and current account budget. Opening this review sends no proposal and
moves no block. `Create preview with these values` deliberately sends the same
versioned proposal used by the full editor; the active reservations remain in
force until explicit confirmation. `Change values` reveals the existing
three-step editor. A stale or unavailable imported source or a passed deadline
disables the compact submit and requires that full review. Draft plans, plans
that already have a pending revision, and values retained after an ambiguous or
conflicting response continue directly in the full editor. The UI never chooses
which plan to sacrifice. The resulting preview shows total estimate, prior
spent, currently qualifying focus time, remaining minutes, dated staged blocks,
optional busy-time provenance, and any unallocated deficit before confirmation.
It names the fixed planning windows, the per-plan daily cap, the optional
account budget, and the manually imported availability boundary. Guest/mock
shows honest unavailability and makes zero planner calls.

An active plan with passed `missed` blocks shows the number of affected blocks
and still-uncredited minutes. `Replan remaining time` opens the existing staged
proposal flow from the current date. It does not mutate reservations in the
background, and previously completed qualifying focus remains credited to the
plan as a whole. The active warning remains visible while a replacement
revision is only an unconfirmed preview.

## Explicit Non-Claims

Deadline Planner V1 adds no:

- title inference, automatic exam detection, or automatic effort estimate;
- hidden proposal, confirmation, replanning, or completion;
- source-calendar write, provider OAuth, URL fetch, or background sync;
- notification generation, push/system delivery, or reminder guarantee;
- LLM call, Coach-controlled write, autonomous agent, or vector search;
- automatic task, plan, or block completion from a focus session; or
- deployed scheduler or background-mobile execution.

It does not claim remote migration state, production calendar availability, or
that the seven-day workload is a complete calendar/free-time model.

## Verification Contract

Focused backend, Flutter, migration, and browser coverage must prove:

- explicit estimate/prior-spent input and absence of inferred defaults;
- strict request/response parsing and bearer-derived ownership;
- deterministic block identity, ordering, totals, timezone/DST behavior,
  conflict avoidance, proposal-time focus accounting, the 366-day horizon,
  bounds, and honest unallocated minutes;
- nullable account-budget validation, exact idempotent save/removal, ambiguous-
  response reconciliation, direct-write denial, shared owner locking, other-
  plan capacity deduction including earlier same-day reservations, and a
  database confirmation conflict after a changed budget;
- staged revisions that cannot replace the active revision before confirm;
- separate current/latest revision counters, latest-based proposal concurrency,
  pending-based confirmation, active-only completion, and cancellation of both
  an active plan and a still-draft preview without creating a task;
- exact proposed/active/superseded timestamp semantics, including retained
  activation provenance for a formerly active revision;
- atomic first-confirm managed-task creation and stable task identity later;
- planner-only task edit/lifecycle authority, task-editor redirect, allowed
  open-task focus start, bounded later-confirm field updates, and atomic
  plan/task terminal projection;
- exact replay, request conflict, stale revision, response-loss retry, and
  concurrent-confirm convergence;
- exact Study-sized blocks, one final short remainder, honest unallocated
  gaps, full recovery conflicts, unchanged active-minute/budget arithmetic,
  stale confirmation after a Study edit, and no mutation of an active revision;
- completed post-activation linked focus progress without implicit completion;
- stable pagination past a 1,000-row PostgREST response cap for bounded Focus,
  recurring schedule, confirmed-block, and imported-busy projections;
- manual and explicitly selected imported-event sources, stale source
  fingerprint rejection, optional current-import-only busy-time use, explicit
  conflict for unavailable availability, and no title inference;
- read-only GET, no calendar/provider/schedule-item mutation, and no hidden
  generation from import, Dashboard, scheduler, or focus completion;
- forced-RLS owner reads, cross-owner isolation, rejected authenticated direct
  writes, backend-only ledger access, and guest/mock zero-call behavior;
- strict consecutive seven-day workload arithmetic, owner-local dates, merged
  recurring commitments, honest overage/no-budget/error states, and no imported-
  calendar or AI implication;
- strict `preparation-workload-detail-v1` parsing, current-seven-day bounds,
  owner/date-scoped active-block aggregation, exact contribution sums/order,
  cross-owner empty results, read-only retry/error/stale-summary behavior, and
  direct review/replan navigation without an automatic proposal or mutation;
- compact active-plan replanning without an open-time request, exact saved-value
  transfer with a today-normalized historical start, retained active
  reservations until confirmation, stale-source/passed-deadline guards,
  pending/retained-draft fallback to the full editor, and a deliberate
  `Change values` path;
- account export inclusion for plan/revision/block rows, explicit ledger
  omission, and full-account cascade; and
- usable retained drafts, review-before-confirmation, semantic controls, and
  narrow-screen/large-text layout for the wizard, compact replan review, and
  budget dialog/card.

These requirements define the verification boundary. Documentation or source
coverage alone is not a claim that the current checkout, local Supabase stack,
browser journey, remote project, or installed device has passed it.

On 2026-07-18 the final local migration/rollback smoke, full backend and Flutter
suites, and the non-reset combined browser journey completed against this
checkout. The browser run reported
`E2E browser smoke passed for e2e-1784397316@example.test`. This establishes only
the local deterministic boundary described above; it is not a remote migration,
provider-calendar, installed-device, notification, or long-term-outcome claim.

On 2026-07-19 the optional account-capacity migration was explicitly applied to
local Supabase without a reset. The complete FastAPI suite reported
`763 passed, 1 skipped`; the standard gate and non-reset database preflight each
passed all `601` Flutter tests with clean analysis and matching migration
history. The final combined browser run reported
`E2E browser smoke passed for e2e-1784448992@example.test`. It proves only the
local deterministic/RLS boundary described above and does not change any remote,
provider-calendar, installed-device, participant-study, notification, or long-
term-outcome non-claim.

The compatible workload-day detail follow-up completed locally on 2026-07-19
without a schema change. The complete FastAPI suite reported
`766 passed, 1 skipped`; the standard gate and non-reset Supabase verification
each passed `608` Flutter tests with clean analysis and matching migration
history. After the first browser attempt exposed and fixed an inner-Shell modal
barrier defect, the final combined run reported
`E2E browser smoke passed for e2e-1784465767@example.test`. This verifies only
the local strict detail/navigation boundary and does not alter the non-claims
above.

The compatible compact-replanning follow-up also completed locally on
2026-07-19 without an API, schema, RLS, or calculation change. The focused
Deadline Plans page suite reported `22 passed`; the standard gate passed all
`610` Flutter tests with clean analysis; and the final combined browser journey
reported `E2E browser smoke passed for e2e-1784475200@example.test`. It verifies
the compact zero-request review, full-editor escape path, staged semantics, and
the existing local planner/RLS lifecycle only. It is not participant, remote,
installed-device, provider-calendar, notification, or longitudinal evidence.
