# Planner V1 Mutation And Overview V2 Contract

Status: implemented, including `planner-overview-v2`, the unchanged
`planner-v1` mutations, Study Setup, shell-navigation, read-only
Exam-Week Outlook, optional Personal Learning timing, and focused Replanning
follow-ups, as of 2026-07-30.

Planner V1 is the authenticated, deterministic planning home for Tasks,
Habits, exam and assignment preparation, and manually fixed commitments. It
replaces Inbox in the Coach-enabled five-item app shell. Inbox remains available from
Settings and its persistence, generation, lifecycle, and delivery contracts are
unchanged. The later navigation follow-up replaces the redundant Settings shell
item with the gated Coach destination; Settings remains available from every
main page through the shared header action.

## Navigation And Surface

When the development Coach surface is enabled, the mobile and desktop
destinations are, in order: `Today`, `Insights`, `Quick actions`, `Planner`, and
`Coach`. Release builds, production, or an explicit disabled gate omit Coach
and do not restore Settings as a fallback shell item. Settings is opened from
the shared top-right action on Today, Insights, Quick actions, Planner, Coach,
and Settings. Planner orders its `Reload Planner` action before an optional
unread Coach result and Settings; the same action group remains visible in
locked, initial loading, overview-error, current, and stale-after-mutation
states. Settings is pushed so Back returns to Planner. `/preparation-plans` and `/habits` remain
compatible and select Planner in the shell; `/alerts` remains a compatible
Settings-owned route without selecting an unrelated shell destination. Quick
actions contains Morning, Evening, Habit Completion, and Focus. Today is an
execution surface and no longer exposes generic Task creation or
Habit-definition management.

An in-page Today CTA pushes Planner, so the shared top back control returns to
Today. Opening Planner from shell navigation replaces the destination and does
not fabricate back history. Direct Preparation deep links fall back to Planner.
The focused `/planner/replan?plan_id=<uuid>` route is not a second planning
engine; it renders one selected Preparation plan over the existing
proposal/confirmation APIs.

Planner renders:

1. `Add new`: Task, Habit, Exam, Assignment, and Fixed commitment;
2. `Needs attention`: current conflicts, exact unplaced minutes, stale
   calendar-bound or Study-bound previews, changed Study rhythms, and
   open/overdue course selection;
3. seven consecutive profile-local days;
4. `Ongoing preparation`;
5. a separate, initially collapsed `Habits` overview;
6. `Unscheduled Tasks`; and
7. collapsed completed and archived history.

Every pending create or update remains discoverable in a separate
`Pending previews` section derived from `action_plans` until the student
confirms it. Pending creates are not persisted Tasks or Habits. The Habit
header uses the exact summary
`N active · X unplanned`. It includes every active manual and Setup-owned Habit;
`scheduled` means that a positive active Habit slot exists, not merely that an
action-plan revision exists. Duration is nullable when no current persisted or
active-plan value exists. Setup-owned rows show `Managed in Setup`: title,
description, and cadence are readable but immutable in Planner, while duration
may be changed through a new preview carrying the original definition exactly.

`Unscheduled Tasks` includes only persisted open, non-Preparation Tasks with no
positive active Task-block reservation. It distinguishes missing scheduling
inputs, a released plan, genuine zero-placement capacity (`no_time_available`),
and a Task that has never been planned. A partially placed active plan remains
scheduled and reports its exact remaining active minutes once under
`Needs attention`. A confirmed zero-minute plan reloads as
`no_time_available`; pending creates never contaminate this list.
Every open `task_targets` row appears exactly once in `unscheduled_tasks` if
and only if it has no positive active reservation. Its reason is derived in
the fixed order released plan, missing inputs, zero-placement capacity, then
never planned. Every non-create Task plan must resolve to the current Task
snapshot or a lifecycle-consistent released/cancelled historical Task. An
inactive Habit with a plan follows the same history rule; an active plan cannot
be projected against an inactive Habit. The current and historical identity
sets remain disjoint within each target kind.

The seven-day agenda distinguishes Setup commitments, manual fixed
commitments, Task blocks, Habit slots, Preparation blocks, and current imported
Calendar events with icon, text, and color. Imported events appear only when
the planning import is currently authoritative. Setup-owned definitions still
belong to Settings. Exam and Assignment creation continues through the strict
Deadline Planner boundary. Selecting `Exam` opens the existing single-plan
editor with Exam already fixed. Selecting `Assignment` opens the additive
`assignment-series-v1` editor with Assignment already fixed, 12 weekly
occurrences by default, and a bounded `2..20` count. Neither direct entry asks
the student to classify the item again or exposes prior-work controls.
On the destination page, the general `Plan preparation` action remains a real
choice: it offers both Exam and Assignment once, then dispatches to the same
single-plan or finite-series editor. A `kind` query used by a direct Planner
entry is consumed for that opening only and cannot narrow the later general
action.
Guest/demo renders an explicit unavailable state and makes no Planner request
or fabricated synchronized projection.

An Assignment Series is finite, not an unbounded recurrence. Its common
template produces one independent Preparation Plan per weekly occurrence, and
one explicit confirmation activates the whole series atomically. An occurrence
can later be edited alone; editing all future occurrences replaces future
deviations while retaining past/completed ones. Cancelling the future scope is
also atomic. Every existing occurrence retains its persisted Assignment kind
through edit, focused replan, and deep-link entry; existing Exam plans retain
Exam by the same rule. One-off work without preparation belongs in Tasks.

Planner's range remains seven consecutive profile-local dates starting with
its overview date. Its day cards and appointment rows use the same
feature-neutral presentation primitive as Today `Full week`; sharing that
primitive does not share read authority or date semantics. Today `Full week`
instead shows the containing Monday-through-Sunday calendar week, limits its
items to applicable Setup commitments and active-revision Preparation blocks,
and adds its own non-interactive completion/rating-status box. Planner behavior
and navigation are unchanged by that extraction.

Today and Planner use the same category semantics for both Add-new actions and
complete agenda rows: Task/Setup are brand-primary, Habit/Preparation are
information-secondary, Calendar is attention-tertiary, Focus is violet, and a
fixed commitment is danger. Exam and Assignment share Preparation color while
retaining different icons and labels.

Planner load failures use short outcome-first retry copy and never describe an
invented demo replacement. Exam-Week read-only copy says `current saved plan`
instead of exposing the internal `active revision` term. These wording changes
do not alter overview freshness, revision selection, or mutation authority.

The primary availability path is the weekly schedule entered in Setup. Each
recurring Setup commitment may carry inclusive optional `valid_from` and
`valid_until` dates for a semester or other bounded period; rows created before
this addition and rows without dates remain intentionally unbounded until they
are archived. Setup can duplicate a block for another weekday without copying
its identity. Calendar import is not requested during onboarding and remains an
optional, separate Settings integration.

When the overview has no Setup commitment in its visible week, no active weekly
or future one-off manual commitment, and no explicitly consented available
calendar source, Planner shows `Availability may be incomplete`. Before the
first automatic Task, Habit, Exam, or Assignment plan in that page session, it
offers Setup review or an explicit `Continue anyway`; unscheduled Task creation
is never blocked. This is an honest readiness warning, not proof that a
configured schedule is complete.

## Read And Mutation Boundary

Authenticated routes are:

- `GET /v1/planner/overview`
- `GET /v1/planner/preferences`
- `PATCH /v1/planner/preferences`
- `GET /v1/planner/action-plans/{plan_id}`
- `POST /v1/planner/action-plans/proposals`
- `POST /v1/planner/action-plans/{plan_id}/confirm`
- `POST /v1/planner/action-plans/{plan_id}/cancel`
- `POST /v1/planner/commitments`
- `PATCH /v1/planner/commitments/{commitment_id}`
- `POST /v1/planner/commitments/{commitment_id}/archive`

The Planner surface additionally consumes the bearer-owned finite-series
routes under its existing Preparation boundary:

- `GET /v1/deadline-plans/assignment-series`
- `GET /v1/deadline-plans/assignment-series/{series_id}`
- `POST /v1/deadline-plans/assignment-series/proposals`
- `POST /v1/deadline-plans/assignment-series/{series_id}/confirm`
- `POST /v1/deadline-plans/assignment-series/{series_id}/cancel-future`

Every route derives owner identity only from the bearer principal. All GETs are
side-effect free. A read may derive current conflict attention but never stores
a revision, moves a block, changes a target, or refreshes another product
projection. A new immutable revision exists only after an explicit proposal.

`GET /v1/planner/overview` returns `planner-overview-v2`; action-plan and
commitment mutation responses remain `planner-v1`. V2 removes the mixed
`unscheduled` array and returns strict `habits`, `task_targets`,
`unscheduled_tasks`, and compact `history` arrays. `task_targets` is the
read-only authoritative snapshot of every current open non-Preparation Task,
including scheduled Tasks; it does not create another visible Task section.
Every `unscheduled_tasks` row must match its `task_targets` snapshot exactly.
Both runtimes reject duplicate target plans and inconsistent Habit-plan,
pending-preview, active-slot, or unscheduled-Task relations. A persisted Task
cannot appear in both `task_targets` and Task history, and an active Habit
cannot also appear in Habit history. Every open Task without positive active
minutes appears exactly once in `unscheduled_tasks`; a positive active
reservation excludes it. The exact reason precedence is `released`,
`missing_scheduling_inputs`, `no_time_available`, then `not_planned`, and a
historical Task or Habit may reference only a matching released/cancelled plan.
Every persisted Task or Habit plan resolves to the matching current or
historical target snapshot. Action-plan status is itself a strict lifecycle: a
pending create is exempt from a persisted target only while it is `draft`, has
`current_revision = 0`, no active revision, and a latest proposed create
revision; released plans are `unscheduled` with only `target_released`, while
cancelled plans have revision zero, no active or pending revision, and no
attention reason. The only reverse-relation tombstone exception is that exact
cancelled shape with `latest_revision` inside the persisted `1..500` bound. An
actually released former active plan is `unscheduled` with `target_released`
and still requires its matching historical snapshot; every near shape fails
closed. The bounded `history` projection first keeps
every snapshot required by a plan relation, then fills the remaining positions
in repository `created_at`, identity order; more than 1,000 required snapshots
fails closed instead of returning a broken relation. Task and Habit identities
remain separate namespaces, so the same UUID across those two kinds is valid.

Flutter and FastAPI reject unknown keys, coerced identities/dates/times,
invalid unions, inconsistent minute totals, invalid lifecycle projections, and
calendar/source mismatches. Plan current/latest revisions and immutable
revisions are bounded at 500, proposal bases at 499, and confirm/cancel expected
revisions at 500, matching the SQL checks. An active plan contains an exact
`active` revision whose Task blocks or Habit slots are also `active`; pending
revision children are `proposed`. Ambiguous transport failure retains the exact
request identity and body for unchanged retry; an exact `409` requires reload
and a new preview. Before submission Flutter records one proposal-attempt
binding under the exact generated `request_id`; it contains the immutable
request body, retained draft owner, and exact source plan/revision for a stale
replacement. The visible header reload never replays the mutation. After an
ambiguous result it looks up only that request-bound attempt and compares its
plan, target, base-to-pending revision, operation, and complete target snapshot
with the freshly read pending revision. An exact match transfers the binding to
that one preview before retry state is cleared; a non-match binds nothing,
performs no global draft-candidate search, and replays no mutation. A failed
read keeps any required
exact-retry or conflict lock, and an ordinary error-free header reload remains
a simple overview read. When that fresh overview still
contains the same pending revision with a current target-, Calendar-,
timezone-, or Study-stale attention identity for that exact revision, opening
it offers `Create new preview` instead of another confirmation. Long-lived
persisted attention reasons describe older events and are suppressed while a
pending revision exists; only the current target version/lifecycle, Calendar
preference and import, profile timezone, and applicable Study revision decide
whether that pending preview is stale. With no pending revision, truthful
persisted attention remains visible. The replacement first opens the editor:
a persisted Task or manual Habit starts entirely from its current authoritative snapshot, never
from an older editable draft paired with a fresh timestamp. A Setup-owned Habit
uses the current immutable definition and timestamp while retaining only its
target-bound duration draft. A stale pending create has no persisted target;
the editor is prefilled from that preview as an explicitly reviewed new create
without `expected_updated_at`. Submission uses a new request identity and the
applicable latest base revision. It neither confirms nor cancels the stale
revision. A normal non-stale pending revision remains directly reviewable, and
an ambiguous result keeps its exact-retry path.

An exact proposal retry returns the outcome classification together with the
original request identity instead of consulting a now-cleared mutation slot.
Another ambiguous result keeps the same attempt. A definitive `409` removes
that request attempt and removes its source-replacement draft only when the
currently stored draft is the identical one owned by the attempt. An ordinary
deterministic non-conflict rejection removes the request attempt but retains
the exact source draft for editing. Successful confirmation applies the same
identity check: a newer replacement for that source survives, while an unsent
replacement for the confirmed source preview itself is still cleared.

Task and manual-Habit editable values are retained by target before a proposal
and by exact plan/revision after a proposal; they are never global drafts. A
stale-replacement edit is separately bound to the exact stale plan/revision and
target version (or exact create preview), so Availability Back and an ordinary
proposal failure reopen only that replacement. A `409` invalidates that binding.
Confirmation clears only its own exact preview binding and its exact source
replacement, including deferred and exact-retry confirmation. Confirmation of
the source preview also clears an unsent replacement bound to that same
plan/revision; an unrelated confirmation cannot clear either. A `409` reload
never pairs retained editable Task/manual-Habit values with a newer target
version. Setup-owned Habits retain only duration by target; after a cold start,
a stale replacement may take that duration from its persisted pending target
while title, description, cadence, and timestamp come from the fresh Setup
snapshot.

Inside FastAPI, overview assembly is a deterministic pure builder over one
repository context and the current Deadline projection. The service performs
the reads but does not interleave I/O with attention or day-item calculation.
Proposal writes use one strict typed persistence object that binds target kind
and identity, the exactly next revision, and the mutually exclusive Task-block
or Habit-slot payload. This changes no HTTP or database contract.

The Planner overview captures one UTC instant and uses a request-local read
context. A direct Planner read owns that context; Today V2 supplies its existing
context so both projections reuse the profile timezone, active Habits, and
Deadline projection. Planner adds the inactive-Habit complement before applying
its unchanged all-Habit bound and ordering. Other independent reads run with a
fixed concurrency bound. The context is settled at request end, never cached
across requests, and does not change source errors or their HTTP translation.

That boundary is physical as well as conceptual: `planner_service.py` contains
repository orchestration and mutation sequencing, while `planner_builder.py`
contains overview/projection/availability and serialization helpers. Shared
Planner error types remain stable through the service facade. In Flutter,
`planner_page.dart` coordinates state and navigation, while feature-owned
section and dialog modules render projections and collect drafts without
reading providers or writing data.

Bounded Planner repository reads use the shared repository page collector while
retaining offset pagination, every owner/filter parameter, stable ordering,
1,000-row pages, per-source sentinel maximums, and the existing Planner-specific
overfull-response error. No cursor is added to an HTTP contract.

All Planner routes now share one exhaustive typed service-error-to-HTTP
translator. The operation catch boundary and existing not-found, conflict, and
validation statuses/details remain unchanged; repository exceptions still stop
below `app/api`.

## Deterministic Availability

One shared availability component is used by Planner Task/Habit proposals and
Deadline Planner proposals. It resolves one profile IANA timezone and handles
the current instant, DST-safe intervals, the explicit Setup energy window, and
these busy sources:

- recurring Setup `schedule_items`;
- active one-off and weekly manual commitments;
- confirmed Planner Task blocks and recurring Habit slots;
- active Deadline Planner preparation blocks; and
- only after the separate Planner preference is enabled, busy events from the
  connected current, non-deleted `.ics` import.

The algorithm uses five-minute block boundaries, never overlaps a busy source,
never plans before the captured current instant, and is bounded to 366
profile-local days. It does not inspect Calendar titles or infer duration,
deadline, cadence, priority, or effort.
Free-start ceiling keeps the complete busy-end precision: a source that ends
after an exact grid boundary, including by seconds or microseconds, releases
time only at the following five-minute boundary. Exact grid boundaries remain
unchanged.

For Task previews only, Personal Learning V1 may add one soft first window
before the Setup ordering when the user enabled learned planning, the
development pilot flag is active, and current `personal-patterns-v1` evidence
is Planner-ready. The fixed learned windows are `05–09`, `09–13`, `13–18`, and
`18–23`; night can never be selected. Subtracting that learned interval from
the ordinary Setup sequence retains every fallback, so learned timing cannot
strand otherwise placeable minutes. Habits and commitments never consume this
preference.

The immutable Task revision stores `setup|learned_personal_pattern`, the used
window, evidence count/date interval/fingerprint, whether allocation actually
used a Setup fallback, and an explicit unavailable-service warning.
Confirmation rechecks the account permission and deployment gate when the
preview claims learned timing, but does not recompute or reinterpret its
evidence. Pattern changes never mark an active plan for attention or move a
confirmed block. See
`docs/personal-learning-v1-contract.md`.

Recurring Setup rows apply only on their matching weekday and within their
inclusive optional validity dates. The same rule is used by Planner,
Preparation planning and workload, Today, and current snapshot schedule facts.

The Planner calendar preference is a one-time explicit read-only consent. It is
also the availability preference used by Deadline Planner. A preview records
the current import identity. Confirmation rechecks preference state and the
exact current import; a disconnect, delete, or replacement yields `409` and
leaves an active revision unchanged. Calendar rows are displayed read-only only
while the import remains current; consent independently decides whether those
current rows are planning busy time.

`Needs attention` suppresses duplicate persisted `target_released`,
`unplaced_minutes`, and generic conflict rows when a more precise V2 projection
owns the fact. Current overlaps carry one explicit source: `setup`,
`fixed_commitment`, or `calendar`, with copy that says nothing moved
automatically. Preparation plans use the same origins and also surface active
or pending unplaced minutes plus `timezone_changed`, `target_changed`, Calendar,
and Study staleness. Empty state copy is exactly
`Nothing currently needs review.`

The bounded read-time recurrence scan omits only a Habit, weekly Setup, or
weekly manual fixed-commitment occurrence whose wall time is nonexistent or
ambiguous in the profile timezone. It retains every independently resolvable
occurrence and reports one deduplicated `stale_preview` item per affected Action
or Preparation Plan, naming every affected source kind plus the local date,
wall time, and resolution reason. An omitted occurrence is not a conflict and
no reservation moves automatically. Candidate reservations remain limited to
exactly 366 profile-local days. Read-only authoritative materialization adds
only the preceding and following spill day (at most 368 distinct local days)
so a first- or final-day cross-midnight reservation can still detect Setup,
fixed-commitment, and current Calendar overlaps; spill anchors never generate
an additional Task, Habit, or Preparation candidate.

## Task And Habit Plans

An Action Plan has one `task` or `habit` target and immutable numbered
revisions. A Task is schedulable only when the user supplied all three values:
total duration, an exact aware deadline, and preferred session length. Without
all three, confirmation atomically creates or updates the Task under
`Unscheduled` and reserves no time. A long Task may be split into bounded
blocks. Minutes that cannot fit the five-minute grid or available intervals are
returned exactly as `unscheduled_minutes`.

A Habit requires an explicit duration per occurrence plus a Daily, selected
weekday, or weekly-target cadence. Its proposed weekly wall-clock slots must
fit every occurrence in the next 28 days. Confirmation makes those slots
stable; later one-off conflicts appear under `Needs attention` and never move a
slot automatically. Existing manual or Setup-owned active Habits can be timed,
but Planner cannot alter a Setup-owned title, description, or cadence.

For a create proposal, the Task/Habit does not exist until confirmation. The
database transaction creates the target and activates its reservations
together. For updates, confirmation rechecks the exact target `updated_at` and
eligible lifecycle before updating the target and activating the revision.
Concurrent confirms serialize on the shared owner lock and cannot reserve the
same time.

Blocks have only proposal/reservation lifecycle; they have no competing done
state. Task status and Habit outcomes remain authoritative. A block can start
Focus, but Focus does not complete its target. Task completion/cancellation and
Habit pause/archive release future reservations through database lifecycle
guards. Undo or restore never resurrects released slots; the target returns to
`Unscheduled` and requires a new proposal. Explicit Action Plan cancellation
also releases reservations while retaining an already-created target.

An ordinary Task proposal includes an explicit `use_study_rhythm` boolean,
defaulting to false. When true, a current Study focus rhythm is required and
its focus duration replaces the ordinary preferred-session choice. Each normal
Task block is exactly that duration; only the last remainder may be shorter.
Every block also reserves the complete Study recovery period. Recovery is busy
time but is excluded from Task minutes and daily preparation capacity. Habit
proposals cannot use this option.

A Study-bound revision freezes `study_setup_revision` and
`recovery_minutes`; its blocks expose `recovery_minutes` and
`reserved_ends_at`. The fingerprint and confirmation guard cover those values
and the complete reserved interval. Changing or removing the rhythm invalidates
a pending preview and marks an active Study Task under `Needs attention`;
explicit proposal and confirmation are still required before any reservation
changes.

## Fixed Commitments And Conflicts

Manual commitments are either one aware start/end interval or one weekly
weekday plus local start/end wall time. Create, edit, and archive are
owner-locked and retry-safe. The review step names visible overlapping Task,
Habit, or Preparation plans. Saving is nevertheless allowed because a fixed
commitment is authoritative.

The mutation marks overlapping Action Plans for attention. Read-time detection
also checks future active Task dates, recurring Habit occurrences, and active
Preparation blocks, including relevant conflicts beyond the visible seven-day
agenda. It only reports attention; no background revision or automatic move is
created. Archiving frees the commitment interval and clears only conflict facts
that no longer apply.

## Persistence And Authority

`20260722120000_planner_v1.sql` adds:

- `planner_preferences`
- `planner_action_plans`
- `planner_action_plan_revisions`
- `planner_task_blocks`
- `planner_habit_slots`
- `planner_commitments`
- `planner_request_identities`

`20260722234000_setup_commitment_validity_guards.sql` adds the private inclusive
Setup-date predicate and applies it to the existing Planner Task/Habit and
Deadline Planner confirmation guards. It adds no table or column. The guarded
function replacement aborts if an expected protected RPC definition has
drifted, rather than silently weakening confirmation.

`20260723120000_study_setup_v1.sql` extends immutable Task revisions and blocks
with Study revision/recovery truth and wraps proposal/confirmation with exact
rhythm and full-reservation checks. Existing revisions retain null Study
revision and zero recovery. Existing blocks are backfilled with zero recovery
and a reserved end equal to their focus end.

The first six tables are authenticated owner/admin read projections with
forced RLS and backend-owned writes. The global request ledger is service-role
only. Service-role RPCs take the established owner advisory lock before the
request lock, bind request ids to complete fingerprints, and atomically enforce
revision, target, calendar, and competing-reservation preconditions. Existing
Tasks, Habits, Deadline Plans, Setup commitments, and imported Calendar rows are
not migrated or automatically scheduled.

Account Export includes the six user-content tables and the separate Study
Setup projection, while intentionally omitting the anti-replay ledger. Profile
deletion cascades all Planner and Study state. Direct application-role Planner
writes remain forbidden.

The overview computes course-selection attention from the profile-local date
and the next semester's inclusive window. Before the window or after explicit
semester-wide completion there is no item; during it the item is open and after
it the item is overdue. Its target is Settings Study Setup. This read creates
no Task, Today item, Calendar row, or Notification.

## Exam-Week Outlook

Planner also owns presentation of the separate read-only
`exam-week-outlook-v1` response. The card is placed after `Add new` and before
ordinary `Needs attention`; it is absent when `mode=inactive`. Only an active
exam with remaining work activates `watch`, `exam_week`, or `overdue`.
Assignments within the horizon are labelled capacity consumers and cannot
activate the card.

The outlook reuses shared Availability without creating Planner or Preparation
reservations. It compares regular capacity with the newest Evening V4 sleep
plan hypothetically protected and reports missing/incomplete inputs rather than
inventing availability. `Review plan` reuses the Preparation surface;
`Replan remaining time` pushes the focused
`/planner/replan?plan_id=<uuid>` route for the selected plan only. Opening
either the card or saved-value replan review submits no proposal and leaves the
active revision unchanged. Confirmation returns to Planner and refreshes
Planner, Exam Outlook, and relevant Today projections.

Guest/demo does not request or fabricate this projection. It is not a Today,
course-selection, Inbox, or Notification attention item. The exact derivation,
warning, risk, DST, privacy, and verification rules live in
`docs/exam-week-outlook-v1-contract.md`.

## Today Overview V2

`GET /v1/today/overview` remains `today-overview-v1` for existing clients.
`GET /v1/today/overview-v2` adds current Planner Task blocks, Habit slots, and
manual commitments to the agenda plus `scheduled_today` on Task/Habit
projections. Multiple Task blocks select the Task once and never add another
progress denominator item. Habit slots likewise do not duplicate a Habit.
Planner blocks remain agenda context; Task status, Habit outcome, check-ins, and
Preparation state keep the exact V1 progress authority.

An actionable Planner Task block opens the scheduled Focus composer with its
stable block id. Backend context owns the task, original interval, recovery,
remaining duration, and actual-time collision decision; Flutter does not fall
back to an unproven direct Task start if V2 context is unavailable. Starting
Focus does not move or mutate the Planner block.

Planner failure is isolated with its own source state. Independent Today facts
remain visible, while progress is unavailable when scheduled target selection
cannot be proven. Flutter and FastAPI both verify that every
`scheduled_today` target has a matching agenda block and that block duration
matches its interval.

## Stabilized Time And Client Projection

Planner proposals and confirmations bind the current profile
`timezone_revision`. A timezone edit invalidates open previews and adds
`timezone_changed` attention to active plans without moving blocks. Setup and
recurring wall times resolve only when a UTC round trip produces exactly one
instant; nonexistent or ambiguous DST times fail closed with source-specific
attention, including cross-midnight intervals.

Flutter keeps `current`, `refreshingAfterMutation`, and
`staleAfterMutation` projection states. A durable mutation followed by a
failed overview reload leaves the old overview visible but disables every
derived mutation control, including attention, agenda, Preparation, preview,
Task/Habit, and replan actions. A committed proposal or confirmation exposes
neither a preview dialog nor success action until the refreshed overview proves
the exact result. `Reload Planner` performs only the read and never replays the
committed mutation. The shared unread Coach and Settings header
controls do not change this projection or call a Planner/Coach endpoint.
After a successful Planner mutation, the Planner controller owns its overview
state while the app-level projection coordinator invalidates affected Today,
Daily Briefing, Preparation Workload, and Exam Outlook reads. Planner callers
do not enumerate those foreign providers, and this cache coordination never
replays the mutation.

Flutter Planner models reuse framework-neutral strict primitives for exact
keys, objects/lists, scalars, UUIDs, local dates/times, aware timestamps, and
bounds. Availability, target, revision, reservation, and mutation-state
relationships remain feature-owned with the same error and wire contracts.

## Non-Claims

Planner V1 adds no LLM planning, hidden generation, background scheduler,
automatic replanning, Calendar write or live sync, provider OAuth, Task/Habit
completion inference, notification generation, push delivery, or Setup-owned
definition mutation. It does not claim that energy windows predict performance
or that imported Calendar data is complete availability.

## Visual presentation

Planner uses the shared [Frontend Visual System V2](frontend-visual-system-v2.md).
Time-block presentation and semantic states do not alter previews,
confirmations, availability, reservations, commitment ownership, or Today
projection rules.
