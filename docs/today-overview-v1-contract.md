# Today Overview V1 Contract

Status: implemented as of 2026-07-21.

Today Overview V1 replaces the briefing-first presentation on the `Today`
surface. It does not remove `daily-briefing-v1`: persisted briefings remain a
backend input for deterministic notification generation, Coach context, and
historical feedback. The primary Today UI no longer presents that ranking as a
decision made for the user.

## Endpoint And Authority

Authenticated real accounts read:

`GET /v1/today/overview`

The response contract is `today-overview-v1`. The bearer principal is the only
source of owner identity. The route accepts no user id, date, query, or body and
performs no write, recommendation refresh, briefing generation, LLM call, or
notification generation. An invalid or unavailable profile timezone makes the
whole request unavailable; all other source families are isolated as described
below.

FastAPI captures one timezone-aware UTC instant, loads the profile's IANA
timezone, and derives one profile-local date. `generated_at`, `timezone`, and
`local_date` must agree. Flutter uses that returned date for the Today header
and outcome commands instead of independently choosing a device date.

## Source Projection And Partial Failure

The response reads only owner-scoped persisted facts:

| Projection | Canonical source |
| --- | --- |
| check-ins and streak | `daily_logs` exact Daily Capture V2 metadata |
| tasks | `tasks` |
| habits and outcomes | `habits`, `habit_logs` |
| recurring commitments | `schedule_items` |
| confirmed preparation | active `deadline_plans` and their active confirmed revision/blocks |
| imported events | the one connected, non-deleted current `calendar_imports` projection in `calendar_events` |
| actual focus | `focus_sessions` |

Each family has a `current` or `unavailable` source state. One failed family
does not erase usable independent sections. The UI shows an explicit error in
the affected section, and the timeline lists any source errors beside the
remaining entries. Empty current data and unavailable data are distinct.

## Check-In Streak

A completed streak day requires both one valid Morning and one valid Evening
Daily Capture V2 projection for the same `entry_date`. Both may be entered at
any time and in either order, including both during the evening. Saving only
one capture never completes that date.

The validator reuses the strict Daily State capture parser, including contract
identity, enums, numeric bounds, timestamps, and projected numeric-column
agreement. Legacy numeric rows, malformed V2 metadata, and proxy columns do not
count. Canonical Morning/Evening persistence merges both kinds into the one
current daily entry instead of treating separate legacy rows as completion.

Rows are read newest-first in bounded pages until the first date gap is known;
the calculation is not capped to a cosmetic 30- or 60-day window. An incomplete
current date gets grace: it does not extend the streak, but it also does not end
the completed run ending yesterday. The first incomplete prior date ends the
run. A complete current date extends it immediately.

## Today's Progress

The progress bar is a transparent completion count, not a readiness or
wellness score:

`total = 2 check-ins + Today tasks + Today habits + today's active confirmed preparation blocks`

Completed means:

- a persisted Morning or Evening capture, counted separately;
- a selected Today task whose status is `done`;
- a selected Today habit with explicit `completed` outcome;
- a confirmed preparation block whose derived state is `completed`.

A skipped habit, partial or missed preparation block, recurring Setup
commitment, imported event, actual Focus session, future task, and
planner-managed task do not count as completed progress. Calendar and Focus are
context, not obligations. If check-ins, tasks, habits, or preparation cannot be
loaded, `progress` is `null` and the exact unavailable counted-source list is
returned. The client revalidates the arithmetic before rendering it.

The denominator is dynamic. Copy must use `x/y completed`; it must not imply a
fixed twelve-step system when the account has a different number of actions.

## Today At A Glance Timeline

The compact vertical agenda combines four visibly distinct categories:

- `Setup commitment`: recurring `schedule_items`, including intervals that
  cross midnight into the local day;
- `Preparation`: blocks from active plans' active confirmed revisions, with
  existing `upcoming`, `partial`, `completed`, or `missed` state and credited
  tracked minutes;
- `Calendar`: current imported all-day or timed events, kept read-only with
  their source label;
- `Focus`: actual active, completed, or abandoned Focus intervals.

All-day imported events appear first. Timed entries follow by start instant;
same-time entries use a stable category/title/id tie-break. Overlapping entries
remain separate adjacent facts and are not silently moved or merged. Category
color is reinforced by icon and text: teal/primary for Setup, blue/secondary
for Preparation, amber/tertiary for Calendar, and an accessible purple for
Focus.

Preparation entries may open their owning plan. An upcoming or partial block
may start Focus on its stable managed task. Imported events and recurring Setup
commitments remain non-executable context.

## Task And Habit Selection

`Today's tasks` includes non-planner tasks that are:

- open and due or overdue on the profile-local date;
- `in_progress`, regardless of deadline;
- `done` with `completed_at` on the profile-local date.

Deadline Planner-managed tasks are excluded from Today selection and progress
because their execution authority belongs to Preparation Plans. They remain visible in
`Show all tasks`, where editing redirects to the owning plan. Future, undated,
completed, and cancelled tasks also remain available in that expansion. Inline
complete/undo and Focus actions reuse the existing Task/Focus contracts; no new
write path is introduced. Creating a future or undated task expands the full
list so the saved result does not appear to vanish.

`Today's habits` includes active daily habits, selected-weekday habits scheduled
for the local weekday, and weekly-target habits while their completed outcome
count is below target. The section shows the exact saved completed/skipped
outcome and exposes complete, skip, or undo through the existing Habit V1
commands. Skipped outcomes stay distinct from completion.

## Flutter Surface Order

The primary Today order is:

1. profile-local date and source;
2. Check-in streak with Morning and Evening save state/actions;
3. green Today progress bar;
4. `Today at a glance` vertical agenda;
5. `Today's tasks`, followed by collapsed `Show all tasks`;
6. `Today's habits`;
7. collapsed `More`.

`More` lazily loads Preparation workload, Weekly review, saved check-in signals,
rule-based recommendations, decision-feedback history, and the full week. A
normal collapsed Today load does not request those supporting projections.

Guest/demo builds the same conceptual overview from local capture storage. It
performs no authenticated Today, Supabase, briefing, recommendation, or
preparation request and does not fabricate tasks, blocks, streak days, or a
personalized decision.

## Additive Today Overview V2

Planner V1 adds the parallel read-only endpoint
`GET /v1/today/overview-v2` with contract `today-overview-v2`. The V1 endpoint
and response remain available unchanged for existing clients. The current
Flutter app consumes V2.

V2 adds three timed agenda categories from the current Planner read:

- confirmed `task_block` rows with their Task identity and minutes;
- confirmed recurring `habit_slot` occurrences with their Habit identity and
  minutes; and
- active one-off or weekly `manual_commitment` occurrences.

It also adds `scheduled_today` to Task and Habit projections and a separate
Planner source state. A future or undated open Task with one or more blocks
today is selected exactly once with reason `scheduled_today`. Multiple blocks
do not increase the denominator. A scheduled active Habit is included once,
and its saved outcome remains the only completion authority. Manual commitments
and all Planner blocks are agenda context and never add a block-level done
state.

FastAPI and Flutter both require scheduled target flags to match agenda target
identities and require each Planner block's stated minutes to match its exact
interval. If the Planner projection fails or changes incompatibly while Today
loads, its independent source state is unavailable and no Planner block is
fabricated. Other usable Today sources remain visible; progress is unavailable
when scheduled target selection cannot be proven.

## Bounds And Non-Claims

Backend parsers reject unknown/coerced contract shapes and cap task, habit,
timeline, focus, calendar, and paginated fact reads. Flutter repeats exact key,
enum, timestamp, identity, source-state, and progress checks. A malformed
response is an error, not partial invented content.

Today Overview does not infer free time, reschedule overlaps, complete a plan
from tracked minutes, write to imported calendars, turn Focus into an
obligation, learn from check-in free text, generate an AI plan, or claim that
the app made a daily decision. It is a deterministic read projection over the
user's saved facts plus existing derived preparation state.
