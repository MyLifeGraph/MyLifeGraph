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
user explicitly selects or enters it.

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
events.

If all requested preparation time cannot fit before the deadline, the proposal
returns the exact unallocated minutes for explicit review. It never hides the
deficit, schedules work after the deadline, or fabricates available time.

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
unchanged.

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

DST gaps or ambiguous local wall times are rejected or avoided rather than
guessed. The planner has no LLM/provider call or model-provenance field; its
bounded input and deterministic planning fingerprint are the persisted truth.
Normal reads, calendar imports, Dashboard loads, scheduled refreshes, and focus
completion never generate or revise a plan.

## HTTP Boundary

All routes require the normal verified Supabase bearer token and derive the
owner only from that principal:

```text
GET  /v1/deadline-plans
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

The strict detail response exposes exactly one plan identity with both revision
counters, nullable
`active_revision`, nullable `pending_revision`, and derived `progress`, wrapped
with `contract_version=deadline-plan-v1` and
`origin=authenticated_backend`. A revision includes its exact timezone,
`best_energy_window`, source status, lowercase planning fingerprint, planned
and unscheduled minute totals, proposal-time tracked/remaining minutes, exact
lifecycle timestamps, and at most 120 blocks. The collection response returns
at most 50 details and fabricates neither an active nor a pending revision.

## Persistence And Authority

The canonical tables are:

- `deadline_plans`: owner, source, immutable original estimate and credited
  prior time, current lifecycle, managed-task identity, and active/pending
  revision projections;
- `deadline_plan_revisions`: immutable explicit estimate, planning inputs,
  source fingerprint, deterministic result, and confirmation state;
- `deadline_plan_blocks`: immutable dated blocks owned by one revision; and
- `deadline_plan_request_identities`: minimal backend anti-replay identity for
  owner, plan, operation, and request fingerprint.

The mutation RPCs take the shared owner advisory lock and apply request claim,
revision/block writes, first-confirm task creation, and plan projection changes
atomically. Composite owner references and database checks prevent cross-owner
plan, revision, block, task, or calendar linkage.

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

The preview shows total estimate, prior spent, currently qualifying focus time,
remaining minutes, dated staged blocks, optional busy-time provenance, and any
unallocated deficit before confirmation. Guest/mock shows honest unavailability
and makes zero planner calls.

An active plan with passed `missed` blocks shows the number of affected blocks
and still-uncredited minutes. `Replan remaining time` opens the existing staged
proposal flow from the current date. It does not mutate reservations in the
background, and previously completed qualifying focus remains credited to the
plan as a whole.

## Explicit Non-Claims

Deadline Planner V1 adds no:

- title inference, automatic exam detection, or automatic effort estimate;
- hidden proposal, confirmation, replanning, or completion;
- source-calendar write, provider OAuth, URL fetch, or background sync;
- notification generation, push/system delivery, or reminder guarantee;
- LLM call, Coach-controlled write, autonomous agent, or vector search;
- automatic task, plan, or block completion from a focus session; or
- deployed scheduler or background-mobile execution.

It does not claim remote migration state or production calendar availability.

## Verification Contract

Focused backend, Flutter, migration, and browser coverage must prove:

- explicit estimate/prior-spent input and absence of inferred defaults;
- strict request/response parsing and bearer-derived ownership;
- deterministic block identity, ordering, totals, timezone/DST behavior,
  conflict avoidance, proposal-time focus accounting, the 366-day horizon,
  bounds, and honest unallocated minutes;
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
- completed post-activation linked focus progress without implicit completion;
- manual and explicitly selected imported-event sources, stale source
  fingerprint rejection, optional current-import-only busy-time use, explicit
  conflict for unavailable availability, and no title inference;
- read-only GET, no calendar/provider/schedule-item mutation, and no hidden
  generation from import, Dashboard, scheduler, or focus completion;
- forced-RLS owner reads, cross-owner isolation, rejected authenticated direct
  writes, backend-only ledger access, and guest/mock zero-call behavior;
- account export inclusion for plan/revision/block rows, explicit ledger
  omission, and full-account cascade; and
- usable retained drafts, review-before-confirmation, semantic controls, and
  narrow-screen/large-text layout.

These requirements define the verification boundary. Documentation or source
coverage alone is not a claim that the current checkout, local Supabase stack,
browser journey, remote project, or installed device has passed it.

On 2026-07-18 the final local migration/rollback smoke, full backend and Flutter
suites, and the non-reset combined browser journey completed against this
checkout. The browser run reported
`E2E browser smoke passed for e2e-1784397316@example.test`. This establishes only
the local deterministic boundary described above; it is not a remote migration,
provider-calendar, installed-device, notification, or long-term-outcome claim.
