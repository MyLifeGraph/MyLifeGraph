# Deadline Planner V1 Contract

Deadline Planner V1 turns one explicit exam or assignment occurrence plus the
user's own preparation estimate into a reviewable set of dated focus blocks.
The additive `assignment-series-v1` boundary creates a finite weekly sequence
of those independently manageable Assignment plans from one shared template.
Both paths are deterministic, authenticated, retry-safe, and no-LLM. They do
not infer that a calendar event is a deadline and never write to a source
calendar.

## Product Boundary

The user deliberately starts the flow from one of these entries:

- Planner `Add new` -> `Exam`, which opens a manual one-off Exam flow with the
  kind already fixed;
- Planner `Add new` -> `Assignment`, which opens a finite weekly Assignment
  Series flow with the kind already fixed; or
- `Plan preparation` on one explicitly selected imported calendar event.

The generic imported-event entry still asks the user to choose `exam` or
`assignment`, because that action has not already supplied a kind. A direct
Exam or Assignment entry must not ask for the same classification again.

Every new Preparation flow asks the user to enter:

- `estimated_total_minutes`, from 30 through 30,000.

Active preparation means deliberate working or study time, not elapsed days,
classes, breaks, or calendar occupancy. The backend never invents either value
from the title, event duration, event type, another user's data, or an LLM.
Suggested duration chips are UI shortcuts only: no value is submitted until the
user explicitly selects or enters it. The UI states that it cannot estimate
effort for the user and offers topics multiplied by sessions per topic and
minutes per session only as a transparent estimation aid.

The current Flutter surface exposes neither `No additional prior work`,
`Add prior work`, nor an entered-prior-credit summary. Every newly created
Exam and every Assignment Series occurrence submits
`credited_prior_minutes = 0`. Existing plans with a historical non-zero value
remain readable and retain that value silently in progress arithmetic; editing
them does not erase the durable credit merely because the control is hidden.

Progress reports `accounted_minutes` as the estimate-bounded sum of prior
credit and qualifying completed focus time, plus exact `remaining_minutes` and
a non-mutating `completion_suggested` flag. The original estimate and original
prior credit remain durable even after a later explicit revision changes the
current estimate. Actual time may exceed either estimate; it is not clamped or
rewritten to make the estimate appear accurate.

## Finite Assignment Series

`assignment-series-v1` represents recurring coursework that happens weekly but
has a known end. A new series contains `2..20` occurrences and defaults to 12 in
Flutter. Editing the remaining future scope accepts `1..20` occurrences. The
student supplies the next aware deadline; later deadlines keep the same
profile-local weekday and wall-clock time at seven-day intervals, including
across DST changes.

One series proposal carries a shared title, per-occurrence preparation
estimate, session length, daily cap, buffer, and optional imported-busy-time
choice. It creates one independent `deadline-plan-v1` Assignment plan and one
independent managed Task identity per occurrence. Each occurrence therefore
has its own Preparation blocks, progress, lifecycle, and focused single-plan
replanning path. A one-off item that needs no preparation plan belongs in
Tasks, not in an artificial one-occurrence Assignment Series.

The series lifecycle is revisioned and atomic:

1. A proposal stages the complete affected occurrence set and all of its
   independent Deadline Plan revisions without activating any of them.
2. One explicit series confirmation activates the whole staged set in one
   owner-locked database transaction. Partial confirmation is forbidden.
3. `Edit this occurrence` uses its normal independent Preparation Plan flow.
4. `Edit all future` creates a new shared series revision. It retains past and
   completed occurrences, while deliberately replacing every still-future
   occurrence with the new shared template, including any earlier individual
   deviation in that future scope.
5. `Cancel future assignments` atomically cancels only the future, incomplete
   occurrence plans and the series projection. Past or completed occurrences
   and their progress remain durable.

The series has exact `draft`, `active`, or `cancelled` status and immutable
`proposed`, `active`, or `superseded` revisions. Request identity, base/latest
revision, full payload fingerprint, occurrence positions, plan identities, and
deadlines are database-enforced. The series request ledger is service-role
only. Authenticated owners may read the series, revisions, and occurrence
membership but cannot mutate those tables directly.

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

FastAPI constructs the proposal and its dated blocks as one validated typed
persistence value before crossing the repository boundary. It requires the
complete key set, exact block intervals, sequence bounds, timing provenance,
and minute fields before serializing the unchanged RPC JSON. This prevents
service/repository key drift without adding another application layer or
changing the database signature.

The orchestration and deterministic calculation are separate modules:
`deadline_plan_service.py` owns repository reads/writes and lifecycle flow,
while `deadline_plan_builder.py` owns block allocation, busy-time projection,
context fingerprints, DST-safe rounding, and response construction. The
service passes complete contexts into those pure helpers; the split introduces
no alternate proposal path and changes no HTTP, typed-write, or RPC payload.

Bounded Deadline repository reads use the shared repository page collector.
They retain their established offset queries, stable sort fields, 1,000-row
page size, per-source sentinel maximums, and exact overfull-response error.
This is an internal read-path boundary and does not introduce a public cursor.

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

The root plan kind is immutable after the plan identity exists. Every active
or pending revision must match that root `exam` or `assignment` kind, including
an independently edited Assignment Series occurrence. A proposal that supplies
a different kind fails before planning-context reads with `409` and the stable
detail `Deadline plan kind cannot be changed.`

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
The shared Availability grid keeps the complete busy-end precision when it
ceilings a free start. A source ending after an exact boundary, including by
seconds or microseconds, releases time only at the following five-minute
boundary; an exact boundary remains unchanged.

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
not qualifying plan progress. The current UI does not offer a manual
prior-credit adjustment for that time.

For newly completed scheduled Focus, credit remains total-preserving but is
block-aware. Minutes already captured by
`tracked_focus_minutes_at_proposal` are removed chronologically first. New
minutes carrying the current revision's Deadline block provenance fill that
block first; unlinked, older-revision, and overflow minutes then fill remaining
blocks chronologically. This changes no total plan progression and cannot
double-count a minute.

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

Allocation for each newly generated or explicitly replanned preview is
kind-specific while the public `deadline-plan-v1` request and response stay
unchanged. Exams use `spread_first`: their first preferred sessions are
distributed over the available runway before viable dates are reused.
Assignments use `earliest_clustered`: the earliest suitable local date is
filled before the planner advances to the next date. Older active revisions
retain their confirmed blocks, including legacy Assignment revisions that may
have been generated with spread-first placement, until the user confirms a new
preview. New Exam editors start
with a 120-minute per-plan daily cap; new one-off Assignment and Assignment
Series editors start with 360 minutes. Selecting a kind may update only an
untouched new-plan default. A manually edited cap and every value loaded from
an existing revision or retained failed draft remain unchanged.

The Assignment allocator still obeys the revision's stored daily cap, the
account-wide remaining preparation budget, all busy intervals, the 120-block
bound, and the exact remaining effort. Study focus and recovery keep their
established authority: only active Focus minutes consume either daily cap,
while the complete Focus-plus-recovery interval must fit and remains reserved.
The kind-derived allocation policy is part of the internal planning-fingerprint
input, but not the request fingerprint, persisted RPC payload shape, or public
V1 wire contract.

The revision's planning fingerprint also covers the current
`study_setup_revision` and recovery duration. Confirmation rechecks both under
the shared owner lock and uses full recovery ends in every competing-reservation
test. A Study edit makes a pending revision stale and an active plan visible
under Planner `Needs attention`; it never changes the active revision. Only a
fresh proposal followed by explicit confirmation can replace reservations.
When no Study rhythm is configured, all prior block-splitting and zero-recovery
behavior remains unchanged.

`planner-overview-v2` projects Preparation attention without changing the
public `deadline-plan-v1` payload. Active and pending revisions expose exact
unplaced minutes; persisted `timezone_changed`, `target_changed`, Calendar, and
Study reasons become stale-preview facts. Current overlaps distinguish Setup,
fixed commitment, and current Calendar import. Read-time facts replace generic
persisted conflict/unplaced duplicates and never replan or write.

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

Personal Learning V1 may prepend one mature learned daytime window for a newly
requested or expressly re-requested preview only when both the account setting
and the development pilot gate are active. Setup windows remain the complete
fallback sequence, and all deadline, budget, Calendar, Recovery, Study rhythm,
current-time, and reservation rules remain authoritative. The learned window
does not change `preferred_session_minutes`, `max_daily_minutes`, or recovery.

Each immutable revision records additive timing provenance: `setup` or
`learned_personal_pattern`, the fixed window, evidence count/date interval and
fingerprint, plus whether unavailable evidence selected Setup or actual
allocation fell back after considering the learned window. Confirmation
requires the learned-use permission still to be active but deliberately does
not recalculate evidence; a changed pattern
affects only the next explicit preview. Confirmed blocks never move and receive
no pattern-change attention. See `docs/personal-learning-v1-contract.md`.

`buffer_days` counts complete profile-local calendar days that must remain free
immediately before the deadline day. For example, a value of one leaves the
whole preceding day clear, so the last preferred preparation day is two dates
before the deadline. A value of zero may use the deadline day up to the exact
aware `deadline_at`. Flutter labels these as clear days and normalizes a saved
past `planning_start_on` to the current profile-local date when opening a new
replan; the backend independently clamps effective planning to its
profile-local current date. The feature-local controller emits one app-level
typed Deadline Plan impact after every proven confirm, complete, or cancel
result, including a successful exact retry/replay; proposal previews emit none.
That single callback owns invalidation of Today, Today Full week, Daily
Briefing, Planner, Preparation Workload, and Exam Outlook reads. It refreshes
the Daily Snapshot with the same Flutter profile-date source rather than the
device calendar only when the returned plan has a managed Task. A draft-only
cancellation still invalidates those read projections but has no Task/date
impact. Refresh failure is best effort after the durable lifecycle result and
cannot turn it into a failed mutation or another exact retry. Deadline widgets
do not duplicate the callback or enumerate foreign providers.

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

The final `propose_deadline_plan_with_timing_v1` database boundary also locks an
existing owner-scoped draft or active root and treats its persisted `kind` as
immutable. A different proposal kind fails with SQLSTATE `PT409` and the stable
message `Deadline plan kind cannot be changed.` before a new request identity
or revision is written. Existing exact replays retain their established
identity/collision precedence, and the Assignment Series proposal RPC delegates
through this same guarded public function. The prior inner implementation is
not executable by application roles. Neither is the strict unguarded
`propose_deadline_plan_v1` body: `PUBLIC`, `anon`, `authenticated`, and
`service_role` have no direct `EXECUTE`. Both remain callable only inside the
postgres-owned `SECURITY DEFINER` chain, making the guarded timing wrapper the
sole application proposal entry point.

The optional account rule is stored on the owner profile. Only the verified
FastAPI/service-role path may call the revision-checked
`apply_account_preparation_budget_v2`; the old V1 setter and direct anonymous
or authenticated updates have no authority. The
confirmation trigger provides a database-boundary recheck under the same owner
lock, so concurrent plan confirmations or a concurrent budget update cannot
bypass the aggregate cap.

All four tables use forced RLS. Authenticated owners may read the intended plan,
revision, and block projections but cannot mutate them directly. The request
ledger is backend-only. `anon` has no access; service-role mutation is available
only through the reviewed backend workflow and service-role-only RPCs.

Account deletion cascades plan data. Account Export includes
`deadline_plans`, `deadline_plan_revisions`, and `deadline_plan_blocks` with
bounded owner-scoped rows. It also includes `assignment_series`,
`assignment_series_revisions`, and `assignment_series_revision_items`. The
opaque Deadline Plan and Assignment Series request ledgers are named as omitted
backend anti-replay ledgers and export no request fingerprint.

## Flutter Surface

The authenticated synced surface is `/preparation-plans`, titled
`Preparation plans`. Planner's direct `Exam` and `Assignment` Add-new controls
open a kind-locked editor. The surface's general `Plan preparation` action asks
once between `Exam` and `Assignment`, then opens the kind-locked single Exam
editor or finite weekly Assignment Series editor respectively. A route-level
`kind` is a one-shot direct-entry command and must not constrain a later use of
that general action on the same page. An eligible imported event also exposes
`Plan preparation`; Calendar navigation may carry only the selected opaque
event id. The destination reads its current title, time, and source fingerprint
through owner-scoped Calendar RLS before prefilling them; only this event-source
entry keeps classification inside its prefilled plan editor. Every path
requires the student's estimate.

Editing or replanning any existing plan, including focused and direct deep-link
entry, shows the persisted root kind read-only and submits it unchanged. A new
generic Calendar-source proposal still offers the explicit kind choice.

The Assignment editor defaults to 12 weekly occurrences, shows the derived
last deadline, and allows 2 through 20 occurrences for a new series. Its one
preview and one confirmation cover the complete series. Series cards expose
editing of one occurrence, editing all future occurrences, and cancellation of
the future scope according to lifecycle. The Exam editor remains the
established single-plan flow. Neither editor renders prior-work input or
prior-credit summary copy.

Settings exposes the optional account-wide daily budget with explicit
rule-based copy and no AI claim. Planner shows the authenticated rolling
seven-day workload, including honest loading, unavailable, over-budget, and
no-budget states; guest/mock makes zero workload calls. A date with confirmed
plans can be expanded deliberately. Its independently loaded detail keeps
loading, failure, and changed-since-summary states visible, lists the
contributing plans, and states the exact minimum date overage when present.
Today does not call the workload or detail route. Its separate `Full week`
accordion projects the containing Monday-to-Sunday calendar week from
owner-scoped Setup commitments and active-revision Preparation blocks under the
Today contract.

Optional placement methodology is initially closed behind `How times are
placed` on an expanded plan. The compact saved-value replan review similarly
keeps `How the preview is calculated` closed. Both use the standard 44×44
information control. Current reservations, staged-preview status, source
changes, passed deadlines, automatic-change non-claims, confirmation
requirements, and retry actions remain visible outside the disclosures.
Student-facing load failures name the unavailable view and next action without
displaying backend, owner-scope, or contract diagnostics.

`/preparation-plans` itself is grouped into `Open plans` and compact `History`;
it does not repeat the seven-day workload card. Every plan is an accordion and
at most one selected or newly previewed plan is open. Collapsed rows expose only
status, Exam/Assignment type, title, and a short progress or attention summary.
Finish-by/timezone, timing rules, learned-timing provenance, progress, blocks,
and actions are visible only after expansion. A lifecycle failure stays inline
with the affected expanded plan. Successful completion collapses that same plan
as a visible Completed history row instead of replacing the scroll viewport.

The route library retains Riverpod reads, controller calls, mutation ownership,
and route navigation. Its feature-private plan-card, editor-sheet, and support
widget parts receive domain values and callbacks only; they do not access a
provider, repository, or persistence API. This source split changes no widget
order, focus behavior, retained editor/accordion state, copy, semantics, or
responsive layout.

`Review plan` opens the owner-scoped plan surface. `Replan remaining time` uses
`/planner/replan?plan_id=<uuid>` and renders only the selected plan. For an
active plan without a pending revision, it first opens a compact review of the
active revision's saved estimate, current tracked Focus, remaining
effort, deadline, split preferences, normalized planning start,
imported-busy-time choice, and current account budget. Opening this review sends
no proposal and moves no block. `Create preview with these values` deliberately
sends the same versioned proposal used by the full editor; the active
reservations remain in force until explicit confirmation. Leaving after
proposal creation intentionally preserves the staged preview. `Change values`
reveals the existing three-step editor. A stale/terminal/unavailable plan shows
an inline explanation and a route back to Planner. A stale or unavailable
imported source or a passed deadline disables the compact submit and requires
full review. Draft plans, plans that already have a pending revision, and values
retained after an ambiguous or conflicting response continue directly in the
full editor. The UI never chooses which plan to sacrifice. The resulting
preview shows total estimate, currently qualifying focus time,
remaining minutes, dated staged blocks, optional busy-time provenance, and any
unallocated deficit before confirmation. It names the fixed planning windows,
the per-plan daily cap, the optional account budget, and the manually imported
availability boundary. Confirmation returns to Planner and reloads Planner,
Exam Outlook, and relevant Today projections. Guest/mock shows honest
unavailability and makes zero planner calls.

An active plan with passed `missed` blocks shows the number of affected blocks
and still-uncredited minutes. A `missed` or `partial` block with at least five
minutes remaining also exposes scheduled Focus start at the actual current
time when the target and complete Focus-plus-recovery interval are still valid.
This makeup path preserves the original block and performs no replanning.
Every refreshed start context replaces the prior scheduled target and
revalidates the selected duration against current remaining minutes. A fully
credited block or one with fewer than five minutes left stays visible with its
canonical explanation and a disabled start; it does not render an empty or
out-of-range duration selection and does not claim that the session starts now.
`Replan remaining time` remains available and opens the existing staged
proposal flow from the current date. It does not mutate reservations in the
background, and previously completed qualifying focus remains credited to the
plan as a whole. The active warning remains visible while a replacement
revision is only an unconfirmed preview.

## Capacity-Based Exam Plan Health

`exam-plan-health-v1` is a separate, read-only capacity projection for every
active Exam whose profile-local deadline is no more than 366 days away. It is
served by `GET /v1/deadline-plans/exam-plan-health`; the Exam editor uses the
read-only `POST /v1/deadline-plans/exam-plan-health/preview` with the exact
unsaved editor values. The preview accepts only `kind: exam`, has no mutation
request id or request ledger, creates no revision or reservation, and never
replaces or invalidates the active GET projection.
For a new unsaved Exam it omits both `plan_id` and `base_revision`. For an
unconfirmed persisted Exam draft it also omits both and runs a new-plan
simulation without borrowing another plan's Focus facts or reservations. Only
an active Exam replan supplies both; the backend accepts them only when the
owner-filtered snapshot contains that active Exam, its current active revision
is intact, and `base_revision` equals the latest saved revision. An unknown,
cross-kind, cross-owner, or stale identity fails with `422` before simulation.
The preview deadline must be strictly future, within both the 366-day instant
and profile-local bounds, and on or after `planning_start_on`; the local planning
window itself may not exceed 366 days. Violations return stable `422` detail.

One owner-filtered, service-role-only
`get_exam_plan_health_snapshot_v1(uuid,timestamptz)` statement reads the
profile, current Study rhythm, all active Exams in the horizon, exact completed
Focus facts since activation including scheduled-block provenance, all active
confirmed Deadline/Planner/Setup
reservations, fixed commitments, and the applicable current Calendar import.
There is no 50-plan page limit and no application-side multi-read assembly.
The RPC is stable, persists no Health state, and is not executable by `anon` or
`authenticated`.

For each Exam the response gives remaining minutes and preferred-session
count, valid future reserved minutes, uncovered minutes, additional feasible
capacity, reserve minutes and full preferred sessions, latest safe start, and
a recommended start or a concrete reason why none is possible. Confirmed
Assignments and series occurrences remain capacity consumers. Exams share
capacity in deadline order, then larger remaining workload, then stable plan
id. Health models a possible replan with the current account-owned Planner
Calendar preference; the revision's saved value remains historical authority
for its already confirmed blocks. When the current preference is enabled, a
missing/stale import or an import whose inclusive `window_starts_on` and
exclusive `window_ends_before` do not cover the full planning interval returns
successful `unknown`, never false green. Invalid or ambiguous occurrence-local
DST availability is likewise `unknown`.
Future reserved minutes are the exact uncredited remainder of each active
block under the same block-aware credit rule as Deadline detail. Retained
blocks still consume their busy interval, account/per-plan daily caps, and one
of the revision's 120 block slots; only the remaining slots are available to
the feasibility probe. A previous-local-day recurring occurrence is resolved
only as an authority anchor when it overlaps the first candidate day. That
anchor is never bookable, and an invalid gap/fold occurrence makes Health
`unknown`.

Status precedence and thresholds are exact:

- overdue with remaining work is `red`, even when an authority is missing;
- otherwise missing required authority is `unknown`;
- negative reserve is `red`;
- only uncovered work can be `yellow`, when reserve is below 20 percent,
  below two complete preferred sessions, or latest safe start is at most seven
  profile-local days away; exact 20 percent and exact two sessions are not
  warnings, while exact seven days is;
- complete authority with no preceding condition is `green`.

A fully accounted Exam has no availability decision left: it remains green
even when its saved deadline is past or optional Calendar/recurrence authority
is unavailable. Its recommended start is profile-today and its latest-safe date
is normalized to no earlier than profile-today, so the two dates never make a
contradictory past-start claim.

The recommended start for new Exam values is no later than the date that
preserves both seven calendar days before latest safe start and at least 20
percent additional placeable Focus capacity. The saved Exam buffer is already
excluded from the feasible interval and therefore remains additional free
time. Recovery occupies calendar capacity but is never counted as Focus.
Elapsed or missed blocks cause a fresh calculation when the projection is
read; they do not themselves create a notification or move a block.

Preparation displays every status and all calculation values. Planner and
Today display only yellow, red, or unknown items. Transport/contract failure is
presented separately from an authoritative `unknown`. Focus, Deadline,
Planner, Setup, timezone, preparation-budget, and confirmed Calendar
import/disconnect/delete mutations invalidate the local projection; preview
reads do not. Successful Assignment Series confirm/cancel results, including
exact retries, use the same Deadline projection invalidation; proposals and
failed lifecycle calls do not. Guest/mock capability guards make zero authenticated Health
calls. No read sends a push, writes a warning, or confirms a replan.
Health actions and Planner/Today plan links use the owner-scoped targeted detail
read when the bounded legacy plan feed cannot supply the requested plan; a feed
failure therefore does not make an otherwise authorized Health review inert.

## Atomic Multi-Exam Balancing

`multi-exam-plan-v1` is an explicit, user-confirmed orchestration over existing
`deadline-plan-v1` revisions. Preparation exposes `Balance exam plans` only on
the normal page, requires the user to choose one active Exam, and submits that
plan id together with its exact latest saved revision. The command is a preview:
it does not move time, confirm a plan, notify the user, or write to an external
calendar. Assignments and all other confirmed consumers remain fixed capacity
inputs; every active Exam inside the complete 366-profile-local-day horizon is
both a consumer and a possible redistribution candidate.

The deterministic search runs in stages. It first keeps every still-valid,
future, uncredited target block and supplements only uncovered work. If that
does not fit, it redistributes the target Exam completely. Only then does it
enumerate additional colliding Exam subsets in exact increasing cardinality.
Every plan selected in a candidate subset is planned in deadline order, then by
larger remaining work, then stable plan id. Among feasible subsets of the same
minimal cardinality, less shifted Focus time wins, followed by later affected
deadlines and stable ids. The implementation proves the result within at most
eight actually changed plans and 100,000 planner evaluations. That evaluation
budget includes the initial retain-and-supplement probe, the target-only
redistribution probe, and every later collider subset; it is not merely a count
of subset-enumeration nodes. Exhausting either documented bound fails closed
with `balance_search_limit` instead of returning a heuristic choice. Plans
whose projected schedule is unchanged are removed from the result after
simulation.

The review uses multiset block signatures consisting of start, Focus end,
reserved recovery end, active minutes, and recovery minutes. Let `R` be exact
retained uncredited minutes, `O` the old uncredited total, and `N` the proposed
total. For unmatched totals `oldU = O - R` and `newU = N - R`, the disjoint
change axes are `shifted = min(oldU, newU)`, `removed = oldU - shifted`, and
`added = newU - shifted`. Therefore `O = R + shifted + removed` and
`N = R + shifted + added`; duplicate signatures are matched as a multiset and
partially credited old blocks contribute only their remaining minutes.

`POST /v1/deadline-plans/exam-balances/proposals` returns the strict union
`no_change | single_plan | multi_exam_batch`. A single actually changed plan is
persisted through the existing Deadline V1 proposal flow and returned for
one-time client adoption; the client must not issue a second proposal. Two to
eight changed plans are stored as one batch and are read through the bounded
list and owner-scoped detail endpoints. Only batch-level `confirm` and `cancel`
commands are available. Confirmation activates all children in one transaction
or none, while cancellation supersedes only the proposed child revisions and
never mutates an active plan. A linked child cannot be changed through the
normal single-plan proposal/replan or complete/cancel paths, and it cannot be
confirmed through the single-plan endpoint. Those wrappers return a stable
`409` while a batch is pending; their ungranted inner chains preserve
Assignment Series and batch orchestration. Its Preparation card links to the
batch review instead.

Revision identity distinguishes `active_revision`, `base_revision`, and
`proposed_revision`. The base is the latest saved revision and the proposal is
exactly base plus one, so a cancelled batch may legitimately leave latest above
active and a later preview can advance again. Proposal requests bind
`expected_plan_revision`; confirm/cancel requests bind the batch revision.
Owner, request, batch/revision, sorted plan, and dependent-row locks have one
fixed order. Immutable request fingerprints plus an append-only request ledger
make exact proposal/confirm/cancel retries replay-safe. Proposal takes an
owner-locked context snapshot, verifies the client snapshot fingerprint, and
stores a fresh post-proposal confirmation fingerprint. Confirm recomputes that
fingerprint under the same owner lock and fails stale when Focus progress,
timezone, Study rhythm, preparation budget, Planner Calendar preference/import,
plan revision, reservation, Task/Habit/fixed commitment, or applicable
Calendar-event facts changed. A separate learned-timing marker binds the
backend pilot flag, the owner-locked learning preference revision/flags, and
the active Exam timing provenance used by the simulation. A pilot change,
opt-out, or marker change therefore makes confirmation stale; learned
provenance cannot outlive its permission. Cancel remains possible when context
is stale. A replay of the original proposal request after its single or batch
preview was confirmed or cancelled returns the stable `409` problem `Original
Exam balance proposal is no longer pending.` rather than attempting to parse a
terminal row as a new proposal result. Legacy owner-writable Profile, Schedule,
Focus, Learning Preference, Task, and Habit rows serialize through the same
owner advisory lock before their existing row guards and writes. Task/Habit
locks run before the reservation-release lifecycle triggers, so an allowed
direct mutation cannot race between fingerprint validation and batch commit.
Lock-not-available
`55P03` and retryable deadlock `40P01` results map to the same stable conflict
boundary rather than leaking as server errors.

Batch rows live in `private` as derived orchestration metadata. Only bounded
service-role RPC projections cross the FastAPI boundary; forced RLS, explicit
least-privilege grants, composite owner foreign keys, and the single-plan child
guard remain database authority. Actual user plan content continues to live in
the existing Deadline revision and block tables already covered by
`account-export-v4` and `personal-snapshot-v2`. The private batch bookkeeping is
intentionally absent from those public shapes; this feature does not reuse a
version with a second shape. Any future export/snapshot projection belongs to a
new contract version.

## Read-Only Exam-Week Outlook

`GET /v1/deadline-plans/exam-week-outlook` is an additive
`exam-week-outlook-v1` read over confirmed Deadline Planner state. It does not
change `deadline-plan-v1`, proposal fingerprints, lifecycle RPCs, or task
authority.

An active exam with remaining work activates `exam_week` at 0..7 profile-local
days, `watch` at 8..14, and `overdue` after its date. Assignments do not
activate the mode but consume the same bounded simulated capacity. For this
warning only, each exam uses at least one clear buffer day. The saved revision
and its blocks remain unchanged.

The read reuses deterministic Availability twice: normally, then with the
newest valid Evening V4/V5 planned sleep interval added as hypothetical busy time.
It includes all confirmed competing blocks in the simulation range, even when
their plans' deadlines are outside the card's horizon. Pending revisions remain
staged and are checked only for a visible sleep overlap. Opening the GET or its
Planner card never creates a proposal, and an explicit replan still follows the
existing preview/confirmation flow.

The complete Capture V4/V5, fit, warning, risk, DST, Planner placement, ownership,
and non-claim rules are in `docs/exam-week-outlook-v1-contract.md`.

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

- Flutter parsing may reuse framework-neutral exact-key, object/list, scalar,
  UUID, date/time, timestamp, and bound primitives while Deadline revision,
  Assignment Series, block, progress, workload, and source relationships remain
  feature-owned;

- explicit estimate input, fixed direct-entry kind, zero prior credit for every
  new plan, silent legacy-credit compatibility, and absence of an inferred
  effort default;
- new-series default 12, strict `2..20` creation and `1..20` future-edit
  bounds, weekly profile-local wall-clock cadence across DST, independent plan
  and managed-Task identities, and one complete atomic confirmation;
- individual occurrence editing, future-wide template replacement that retains
  past/completed occurrences while replacing future deviations, and atomic
  future cancellation without partial series state;
- strict request/response parsing and bearer-derived ownership;
- immutable root kind across edit, occurrence, replan, and deep-link paths,
  exact early `409` rejection of a tampered kind, and revision/root parser
  parity;
- deterministic block identity, ordering, totals, timezone/DST behavior,
  conflict avoidance, proposal-time focus accounting, the 366-day horizon,
  bounds, and honest unallocated minutes;
- unchanged Exam spread-first placement, earliest-date Assignment clustering,
  120/360 untouched new-plan defaults, retained manual/existing/retry caps, and
  allocation-policy inclusion in only the internal planning fingerprint;
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
- exactly-once central projection impact for successful confirm, complete,
  active/draft cancel, and exact lifecycle retry, no impact for a proposal
  preview, and durable success retained when refresh fails;
- exact Study-sized blocks, one final short remainder, honest unallocated
  gaps, full recovery conflicts, unchanged active-minute/budget arithmetic,
  stale confirmation after a Study edit, and no mutation of an active revision;
- completed post-activation linked focus progress without implicit completion;
- missed and upcoming scheduled Focus at the actual server instant with
  immutable source origin, refreshed duration/target validation, safe
  completed/sub-five-minute states, and exactly-once block credit on terminal
  replay;
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
- total 100,000-evaluation Multi-Exam search bounding, minimal changed-set
  selection, atomic batch confirm/cancel, all competing child-mutation guards,
  terminal original-proposal replay conflict, owner-locked learned-timing
  permission/provenance CAS, and stable lock/deadlock conflicts;
- immutable Flutter retry identity across same-principal refresh and transient
  Auth loading/error states, strict
  request/response relationship checks, authoritative-confirm versus
  stale-cancel behavior, targeted detail survival under failed/late history,
  including a selected detail outside the bounded feed and a late list-detail
  completion, source-bound list versus exact-target error/retry races,
  preview-only versus lifecycle refresh, valid current-profile IANA
  timezone as a confirmation prerequisite with DST gap/fold rejection, and
  populated 320 px/200% review semantics;
- account export inclusion for plan/revision/block rows, explicit ledger
  omission, and full-account cascade; and
- usable retained drafts, review-before-confirmation, semantic controls, and
  narrow-screen/large-text layout for the wizard, compact replan review, and
  budget dialog/card.

These requirements define the verification boundary. Documentation or source
coverage alone is not a claim that the current checkout, local Supabase stack,
browser journey, remote project, or installed device has passed it.

Exact current results and dated implementation history live in
[Current Verified Baseline](verification.md#current-verified-baseline) and
[Verification History](verification-history.md), respectively. Those local
deterministic records do not establish remote migration state,
provider-calendar behavior, installed-device behavior, notification delivery,
participant evidence, or long-term outcomes.

Deadline route service failures now use one typed feature-owned HTTP problem
translator while each operation retains its exact catch set. Existing not-
found, conflict, and validation statuses/details and all unexpected-error
behavior remain unchanged.

## Visual presentation

Deadline Planner uses the shared
[Frontend Visual System V2](frontend-visual-system-v2.md). The presentation
migration leaves proposal identity, revisions, confirmation, reservations,
managed-task ownership, and measured progress unchanged.
