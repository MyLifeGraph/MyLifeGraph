# Planner V1 Contract

Status: implemented as of 2026-07-22.

Planner V1 is the authenticated, deterministic planning home for Tasks,
Habits, exam and assignment preparation, and manually fixed commitments. It
replaces Inbox in the five-item app shell. Inbox remains available from
Settings and its persistence, generation, lifecycle, and delivery contracts are
unchanged.

## Navigation And Surface

The mobile and desktop destinations are, in order: `Today`, `Insights`, `Quick
actions`, `Planner`, and `Settings`. `/preparation-plans` and `/habits` remain
compatible and select Planner in the shell; `/alerts` remains compatible and
selects Settings. Quick actions contains Morning, Evening, Habit Completion,
and Focus. Today is an execution surface and no longer exposes generic Task
creation or Habit-definition management.

Planner renders:

1. `Add new`: Task, Habit, Exam, Assignment, and Fixed commitment;
2. `Needs attention`: current conflicts, exact unplaced minutes, and stale
   calendar-bound previews;
3. seven consecutive profile-local days;
4. `Ongoing preparation`;
5. `Unscheduled`; and
6. collapsed completed and archived history.

The seven-day agenda distinguishes Setup commitments, manual fixed
commitments, Task blocks, Habit slots, Preparation blocks, and current imported
Calendar events with icon, text, and color. Setup-owned definitions still
belong to Settings. Exam and Assignment creation continues through the strict
Deadline Planner V1 flow. Guest/demo renders an explicit unavailable state and
makes no Planner request or fabricated synchronized projection.

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

Every route derives owner identity only from the bearer principal. All GETs are
side-effect free. A read may derive current conflict attention but never stores
a revision, moves a block, changes a target, or refreshes another product
projection. A new immutable revision exists only after an explicit proposal.

Flutter and FastAPI reject unknown keys, coerced identities/dates/times,
invalid unions, inconsistent minute totals, invalid lifecycle projections, and
calendar/source mismatches. Ambiguous transport failure retains the exact
request identity and body for unchanged retry; an exact `409` requires reload
and a new preview.

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

Recurring Setup rows apply only on their matching weekday and within their
inclusive optional validity dates. The same rule is used by Planner,
Preparation planning and workload, Today, and current snapshot schedule facts.

The Planner calendar preference is a one-time explicit read-only consent. It is
also the availability preference used by Deadline Planner. A preview records
the current import identity. Confirmation rechecks preference state and the
exact current import; a disconnect, delete, or replacement yields `409` and
leaves an active revision unchanged. Calendar rows are displayed read-only even
when they are not consented as planning busy time.

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

The first six tables are authenticated owner/admin read projections with
forced RLS and backend-owned writes. The global request ledger is service-role
only. Service-role RPCs take the established owner advisory lock before the
request lock, bind request ids to complete fingerprints, and atomically enforce
revision, target, calendar, and competing-reservation preconditions. Existing
Tasks, Habits, Deadline Plans, Setup commitments, and imported Calendar rows are
not migrated or automatically scheduled.

Account Export includes the six user-content tables and intentionally omits
the anti-replay ledger. Profile deletion cascades all Planner state. Direct
application-role Planner writes remain forbidden.

## Today Overview V2

`GET /v1/today/overview` remains `today-overview-v1` for existing clients.
`GET /v1/today/overview-v2` adds current Planner Task blocks, Habit slots, and
manual commitments to the agenda plus `scheduled_today` on Task/Habit
projections. Multiple Task blocks select the Task once and never add another
progress denominator item. Habit slots likewise do not duplicate a Habit.
Planner blocks remain agenda context; Task status, Habit outcome, check-ins, and
Preparation state keep the exact V1 progress authority.

Planner failure is isolated with its own source state. Independent Today facts
remain visible, while progress is unavailable when scheduled target selection
cannot be proven. Flutter and FastAPI both verify that every
`scheduled_today` target has a matching agenda block and that block duration
matches its interval.

## Non-Claims

Planner V1 adds no LLM planning, hidden generation, background scheduler,
automatic replanning, Calendar write or live sync, provider OAuth, Task/Habit
completion inference, notification generation, push delivery, or Setup-owned
definition mutation. It does not claim that energy windows predict performance
or that imported Calendar data is complete availability.
