# Today Overview V1 Contract

Status: implemented through the additive Today Overview V2 Planner projection,
the simplified supporting dashboard, and Daily Capture V5/V4 compatibility as
of 2026-08-05. The V1 endpoint remains available and unchanged.

Today Overview V1 replaces the briefing-first presentation on the `Today`
surface. Persisted `daily-briefing-v2` rows remain a backend-owned deterministic
input, but no generic Recommendation feed, Decision Feedback history, or
Briefing-derived notification source remains. The primary Today UI does not
present that ranking as a decision made for the user.

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
Standalone authenticated Habit actions resolve their target through the same
profile-timezone source, capture it before the write, and reuse it for the
snapshot refresh. Guest actions remain explicitly device-local. An invalid
authenticated profile timezone is an error, not permission to fall back to the
device date.

## Source Projection And Partial Failure

The response reads only owner-scoped persisted facts:

| Projection | Canonical source |
| --- | --- |
| check-ins and streak | `daily_logs` strict Daily Capture V2/V3/V4 metadata |
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
Daily Capture V2/V3/V4 branch for the same `entry_date`. Both may be entered at
any time and in either order, including both during the evening. Saving only one
capture never completes that date.

The validator reuses the strict Daily State capture parser, including contract
and branch identity, enums, numeric bounds, timestamps, V4 sleep-interval
integrity, and projected numeric-column agreement. Legacy numeric rows,
malformed structured metadata, and proxy columns do not count. Canonical
Morning/Evening persistence merges both kinds into the one current daily entry
instead of treating separate legacy rows as completion. The additive Morning
`sleep_quality` rating is validated when present. V2 Morning captures saved
before that field existed remain valid for streak compatibility; every new or
edited Morning capture requires it in Flutter.

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

- `Setup commitment`: recurring `schedule_items` that apply within their
  optional inclusive Setup validity dates, including intervals that cross
  midnight into the local day;
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

The complete actionable agenda row is a touch/semantics target. Preparation
rows in `upcoming`, `partial`, or `missed` state open scheduled Focus for their
exact block; fully credited rows still open the owning plan. Planner Task rows
open scheduled Focus for their exact block. Active Focus rows open the current
timer, while completed or abandoned rows load that exact session id and open
its new or existing reflection even outside recent history and independently
of the automatic prompt preference. Imported events and recurring Setup or
fixed commitments remain non-executable context.

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

1. profile-local date and source, with the shared optional unread-Coach and
   Settings header actions;
2. Check-in streak with Morning and Evening save state/actions;
3. green Today progress bar;
4. `Today at a glance` vertical agenda;
5. `Today's tasks`, followed by collapsed `Show all tasks`;
6. `Today's habits`;
7. a direct `Review your week` navigation entry, followed by the independently
   collapsed `Full week` section. The Weekly Review entry is omitted when its
   existing capability is unavailable.

The streak card includes a compact `Beat yesterday` inset. It independently
loads the latest saved check-in at or before the displayed profile-local Today
date and shows that row's date plus only values actually present among Mood,
Energy, Sleep duration, Sleep quality, and Stress. It calculates no delta,
improvement, score, or judgment. Loading, no-data, and error copy stays inside
the inset, so the streak and Morning/Evening actions remain usable.

Full week watches its narrow projection only while its accordion is open.
`Review your week` keeps its existing navigation and capability boundary but is
not wrapped in a second accordion.
Today no longer contains a `More` grouping, saved-signal
summary, or `7-day preparation load`. Planner also has no standalone workload
card; Preparation editors retain the summary read for the account budget.
The former generic
Recommendation and Decision Feedback accordions are retired rather than hidden
behind compatibility UI.

Explanatory copy is initially hidden behind an independent circled information
control beside each affected heading. This applies to the Today source/updated
line, the normal streak explanation, the progress-inclusion explanation,
`Today at a glance`, `Today's tasks`, `Show all tasks`, its expanded `Tasks`
subsection, `Today's habits`, and the Full-week accordion description.
The direct `Review your week` entry keeps its summary visible and has no
information control. Each disclosure has local, non-persisted state; several
may remain open at the same time, and a newly created Today route starts them
closed. Error, loading, result, unavailable, action, counter, progress, and
empty-state content remains visible according to its owning state and is never
gated by an information control.

An information click inside `Show all tasks` or a supporting accordion does not
toggle that accordion. In particular it does not begin Full-week loading; that
projection is watched only after its content accordion opens. Each information control is a keyboard-operable
button with a real 44×44 logical hit, focus, and semantics rectangle. Its visible
24×24 frame contains the unchanged 20×20 icon, exposes `expanded` semantics,
and uses the exact dynamic
label `Show information about <heading>` or
`Hide information about <heading>`. Closed descriptions are absent from the
accessibility tree. Open descriptions follow their heading and reveal through
the shared state-duration vertical size/opacity transition; Reduced Motion
makes the state change immediate. Non-interactive vertical layout padding keeps
the previous heading alignment. Accordion expansion and information disclosure
are separate sibling controls; neither action can trigger the other. Heading,
information control, Planner action, and accordion chevron wrap without hiding
an action at 320 logical pixels and 200-percent text.

The same header controls remain available during the initial Today loading and
load-error states. The local unread Coach control does not generate, reload, or
acknowledge a Coach turn; it only presents the current in-memory notice.

Guest/demo builds the same conceptual overview from local capture storage. It
performs no authenticated Today, Supabase, briefing, or preparation request and
does not fabricate tasks, blocks, streak days, or a personalized decision.

## Latest Check-In And Full-Week Projections

The authenticated latest-check-in read resolves the bearer owner's profile id,
filters `daily_logs.user_id` to that owner, applies
`entry_date <= displayed_local_date`, orders newest first, and requests at most
one row. The compact mapper accepts only the existing Dashboard projections;
malformed or unavailable data is not replaced with demo content. Guest/demo
selects from local capture storage and makes zero Supabase calls. Its Full-week
accordion constructs a local seven-day empty projection without building
authenticated transport or issuing a FastAPI request.

`Full week` is the strict read-only `today-week-agenda-v1` projection from
`GET /v1/today/week-agenda`. The bearer principal and authoritative profile
timezone determine the current Monday-through-Sunday week; the response always
contains those seven ordered profile-local dates, including empty days. The
wire carries server-derived `local_date`, `local_starts_at`, and
`local_ends_at`; Flutter never re-derives them from browser or device time.
Profile or timezone failure is route-wide `503`. All other reads are seven
independent `current|unavailable` sources: Setup, Preparation, current Calendar
import, actual Focus sessions, Planner Tasks, materialized Habit slots, and
fixed commitments. A source failure keeps the other six authoritative facts
visible and names only the unavailable source; it never becomes fabricated
empty data.

Each source is evaluated through one dedicated owner-filtered seam per request,
with fixed bounded batched subreads where related identities or lifecycle facts
must be joined; no read scales row-by-row. The projection never uses Planner's
rolling overview or the sentinel-limited Deadline list as an input. Calendar
facts are current only when the connected owner's
`last_import_id` resolves to a `calendar_imports` row whose `planning_status` is
`current`; disconnected Calendar is a current empty source, while a stale or
invalid planning import is unavailable. Setup, Calendar, and fixed timed facts
are clipped into every overlapped profile-local day with stable occurrence ids.
Preparation and Planner Task blocks retain their stored `local_date`; Habits
use their materialized occurrence date; Focus prefers `metadata.entry_date`
and uses the UTC calendar date of its aware `started_at` only as the established
legacy/invalid-metadata fallback. Ambiguous or nonexistent recurring wall time
fails only its owning source. Cross-midnight and DST-fold intervals remain
ordered by aware instants.

Static Setup, Calendar, and fixed-commitment rows expose no action. Preparation
reuses the canonical Deadline credit allocation across the complete current
revision, including proposal-time credit, source-bound Focus, and generic
chronological overflow. Its block state is therefore exact
`upcoming|partial|completed|missed`; only a block with at least five remaining
minutes may revalidate the current start context. A completed Preparation plan
opens its plan. Open Planner Task blocks revalidate the current start context;
done or cancelled Task facts are static. Active
Focus resumes and terminal Focus opens reflection. A Habit action exists only
for the exact current profile-local date because the existing Habit mutation is
date-less; it re-reads that profile date immediately before navigation, and a
midnight change instead asks for a Full-week reload. All other week Habit rows
are static. These actions reuse their
owning Focus, Deadline, Task, and Habit contracts and add no mutation route.

Full week loads only when its accordion opens. Mobile shows two and one-half
day cards at normal width/text scale and exactly two at the narrow/large-text
breakpoint; initial position keeps Today visible while clamping Saturday or
Sunday so two real cards remain. Horizontal movement snaps by one day and
cannot pass Monday or Sunday. Web switches to seven columns only when all seven
cards can retain at least 208 logical pixels; otherwise it uses the same
bounded horizontal strip. Day cards grow with content rather than clipping a
dense agenda. Only Full week may escape Today's compact content width.

The application-level projection coordinator invalidates `Beat yesterday`
after a durable Daily Capture change. Habit outcome/definition, Today Task or
Habit, generic Planner, Setup, Deadline Planner, Focus lifecycle,
profile-timezone, Calendar, and preparation-budget impacts invalidate Full
week as applicable. These invalidations refresh reads only and never replay the
originating mutation.
Evening Capture captures the coordinator before opening a Focus-reflection
sheet and invokes it from each successful save/delete callback. The invalidation
therefore still occurs exactly once if the sheet or page is dismissed while the
write is in flight; dismissal controls only whether success Snackbar copy is
shown. A failed best-effort invalidation does not turn the durable reflection
write into an error.

## Additive Today Overview V2

For an authenticated account with Deadline Planner capability, Today may read
`exam-plan-health-v1` independently of `today-overview-v2`. It renders a
separate Exam Plan Health section only when yellow, red, or unknown items
exist; green results remain in Preparation. Loading and transport/contract
failure are not rendered as authoritative `unknown`, and the copy distinguishes
this capacity projection from the sleep-focused Exam Week Outlook. Guest/mock
or local-demo Today never watches the authenticated Health repository.

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

## Mutation-Date And Reload Boundary

Authenticated Task and Habit mutations derive their target date only from the
displayed `DashboardSnapshot.localDate`; device time is not a fallback. While
the write and subsequent Snapshot/Today refresh are in flight, all Task/Habit
actions are locked. If the write committed but the refresh fails, Flutter keeps
the optimistic saved state, disables old projection controls, and shows
`Saved; Today could not reload.` Its retry performs only a read. The app-level
projection coordinator refreshes the Daily Snapshot and invalidates foreign
Briefing/Planner/Workload/Outlook dependencies, but deliberately does not
invalidate Today for these inline writes. Today owns exactly one repository
reload so an automatic provider rebuild cannot consume or obscure the explicit
stale-after-mutation result.

Route disposal does not cancel an already accepted durable write. When its
command port later proves the write committed, the captured app-lifespan
projection coordinator still refreshes the Snapshot and invalidates foreign
dependencies. A disposed Today controller performs no controller-owned state
write, repository reload, or supporting-Today invalidation, and reports the
projection as not current to its awaiting caller. This avoids both a stale
shared projection after navigation and retention of a date-bound Today
controller.

The feature-local `TodayCommandController` owns Task/Habit in-flight locks,
optimistic overlays, committed-versus-unconfirmed outcomes, and the
`current | refreshingAfterMutation | staleAfterMutation` lifecycle. It receives
narrow command ports from app composition; Dashboard presentation contains no
concrete Supabase Task/Habit source access. Navigation to managed Preparation,
Undo presentation, and student-facing copy remain UI responsibilities. Task
creation and editing stay in Planner; the former unreachable duplicate Today
editor and its inert edit/cancel/postpone callback path are not retained.

The Today surface order is composed from independently testable presentation
sections with typed state/action inputs: streak/progress/agenda, Tasks, Habits,
a direct Weekly Review entry, and three independent supporting accordions. The
latest-check-in inset and each lazy supporting projection fail independently.
The page does not forward every leaf callback or
optimistic collection through one large home-widget constructor. This boundary
changes merge locality and test scope only; it does not add a second read model,
command bus, or different student-visible order.

## Bounds And Non-Claims

Backend parsers reject unknown/coerced contract shapes and cap task, habit,
timeline, focus, calendar, and paginated fact reads. Flutter repeats exact key,
enum, timestamp, identity, source-state, and progress checks. A malformed
response is an error, not partial invented content.

The Flutter Today mapper reuses framework-neutral strict primitives for those
exact keys, objects/lists, scalars, UUIDs, dates, timestamps, and bounds.
Selection, progress, source isolation, and cross-field consistency remain
feature-owned with the same V2 wire shape and typed contract errors.

The bounded Today repository sources use the shared repository page collector
with their existing offset queries. Owner predicates, stable ordering,
1,000-row pages, source-specific sentinel maximums, and the exact Today
overfull-response error remain unchanged; the separate streak reader keeps its
own gap-driven paging semantics.

Each Today request owns one short-lived read context. V1 uses it for its direct
read; V2 passes the same context through the V1 and Planner projections so the
profile timezone, active Habit definitions and logs, and current Deadline
projection are loaded once. Independent source families run with a fixed
concurrency bound, while response assembly order, per-source failure isolation,
and both wire contracts remain unchanged. The context is settled at request end
and is never reused as a cross-request cache.
The internal Planner branch now validates `planner-overview-v2`; Today keeps
its own public wire version and continues to consume only Planner day/action
facts. The new Habit and unscheduled-Task overview arrays do not alter Today
selection, create duplicate progress targets, or add another authenticated
guest/mock read.
Today orders its local view of the shared active Habit rows by the established
`updated_at DESC, id ASC` key; it does not mutate the shared value or Planner's
separate `created_at ASC, id ASC` view.

The Today route now obtains the shared application-lifespan Supabase client
instead of opening a transport per request. The read remains owner-scoped,
GET-only, bounded, source-isolated, and free of generation or mutation.

Both Today overview routes now delegate their existing service-unavailable
failure to one typed feature-owned HTTP problem translator. The `503` detail,
source-isolation rules, and unexpected-error behavior remain unchanged.

Today Overview does not infer free time, reschedule overlaps, complete a plan
from tracked minutes, write to imported calendars, turn Focus into an
obligation, learn from check-in free text, generate an AI plan, or claim that
the app made a daily decision. It is a deterministic read projection over the
user's saved facts plus existing derived preparation state.

The separate `exam-week-outlook-v1` projection is Planner-only. Today does not
request it, render its risk/sleep status, add it to progress, or create an
agenda/Notification fact from it.
