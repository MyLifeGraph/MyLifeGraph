# Phase 3 Executable Actions Contract

Status: implementation contract for Phase 3. This contract is deliberately
independent of briefing ranking and the future decision-first Today redesign.

## Scope And Boundaries

Phase 3 makes tasks, habits, and focus sessions executable, durable, scoped to
the authenticated user, and recoverable. It also defines the typed action
target that a later deterministic briefing may return.

Phase 3 does not rank actions, persist a daily briefing, redesign Dashboard as
Today, generate generic recommendations during normal writes, call an LLM, expose
Coach, import a calendar, or change the Phase 2 Daily State classifier.

Guest and mock sessions remain local and do not receive Supabase-backed task,
habit, focus, or snapshot commands.

Deadline Planner V1 later composes these primitives without widening them. Its
first explicit plan confirmation creates one planner-managed task, and its
progress reads qualifying completed focus sessions linked to that task. The
planner's proposal/revision/block lifecycle, retry ledger, and explicit
completion remain a separate `deadline-plan-v1` backend contract; Phase 3 does
not infer or generate them.

## Object And Command Matrix

| Object | Command | Valid source state | Durable effect | Recovery |
| --- | --- | --- | --- | --- |
| Task | `create` | none | Insert user-owned `todo` task with validated title, optional deadline, priority, description, and estimate | Retry reuses the client UUID; a read-after-loss retry converges on one row |
| Task | `edit` | `todo`, `in_progress`, or `done` | Replace only explicitly editable fields and `updated_at` | Exact requested-field/timestamp readback reconciles a committed response loss |
| Task | `complete` | `todo` or `in_progress` | Set `done` and `completed_at` | A lost response is reconciled by exact mutation timestamp/state; `restore` returns it to `todo` |
| Task | `postpone` | `todo` or `in_progress` | Move the deadline to a strictly later instant | Transition or deadline-undo loss is reconciled by exact mutation timestamp/deadline |
| Task | `cancel` | `todo` or `in_progress` | Set `cancelled` and `cancelled_at` | A lost response is reconciled by exact mutation timestamp/state; `restore` returns it to `todo` |
| Task | `restore` | `done` or `cancelled` | Set `todo`; clear `completed_at` and `cancelled_at` | Exact state/timestamp readback reconciles restore and direct undo response loss |
| Habit | `create` | none | Insert a manual active habit with one typed cadence | Retry reuses the client UUID and converges after an ambiguous committed response |
| Habit | `edit` | manual active or paused | Replace manual definition while preserving ownership metadata | Exact requested-field/timestamp readback reconciles a committed response loss |
| Habit | `pause` | manual active | Set inactive with a durable paused lifecycle marker | Exact lifecycle/timestamp readback reconciles loss; `restore` makes it active again |
| Habit | `archive` | manual active or paused | Set inactive with a durable archived lifecycle marker | Exact lifecycle/timestamp readback reconciles loss; `restore` returns it to active |
| Habit | `restore` | manual paused or archived | Return to active lifecycle | Exact lifecycle/timestamp readback reconciles a committed response loss |
| Habit | `complete_today` | active and scheduled/selectable today | Upsert one `completed` outcome for the captured local date | Exact date/status/value/note readback reconciles loss; `undo_today` deletes it |
| Habit | `skip_today` | active and scheduled/selectable today | Upsert one `skipped` outcome for the captured local date | Exact date/status/value/note readback reconciles loss; `undo_today` deletes it |
| Habit | `undo_today` | completed or skipped today | Delete the one captured-date outcome | Readback must prove absence after response loss; repeating undo is idempotent |
| Focus | `start` | no active session | Insert one active session with planned duration and at most one owned task or habit target | Stable session id plus active-session reload reconciles a committed response loss |
| Focus | `finish` | active | Set completed, end timestamp, and measured elapsed minutes | Exact readback reconciles a committed response loss; does not complete a linked target |
| Focus | `abandon` | active | Set abandoned, end timestamp, and measured elapsed minutes | Exact readback reconciles a committed response loss; does not mutate a linked target |

Every mutation derives `user_id` from the current Supabase session. Reads and
writes include both object id and resolved user id. Empty PostgREST update
results are treated as unavailable/invalid transitions, not success.

## Validation

### Tasks

- Trimmed title: 1-160 characters.
- Optional description: at most 2,000 characters.
- Priority: `low`, `medium`, `high`, or `critical`.
- Optional estimate: 5-480 minutes.
- Optional deadline must be a valid timestamp.
- Postpone requires a new deadline later than the current non-null deadline and
  later than now. A task without a deadline may be assigned a future deadline.
- `done` owns only `completed_at`, `cancelled` owns only `cancelled_at`, and
  nonterminal states own neither. The database rejects every other lifecycle
  shape.
- Every task update, including edit, complete, postpone, cancel, restore, and
  direct undo, uses optimistic `updated_at` matching plus a client-chosen
  mutation timestamp. After an ambiguous transport/response failure, an
  owner-scoped read is accepted only when that timestamp and every requested
  persisted field match exactly; any different concurrent write remains a
  recoverable conflict.
- Unknown status or command values are unsupported.
- A Deadline Planner managed task is created only by the verified backend's
  first-confirm transaction with `task.id = deadline_plan.id`,
  `estimated_minutes = null`, and exact `deadline-plan-v1` provenance. Generic
  task edit, complete, postpone, cancel, restore, and ordinary editor paths must
  reject this source and route the user to `/preparation-plans`; focus start may
  still target the open task. Later plan confirmation may update exactly title,
  deadline, and `updated_at` while it is open. Only explicit plan complete or
  cancel may atomically project the managed task to matching `done`/`cancelled`
  state and terminal timestamp. No generic task command may replace that
  authority or erase terminal user state.
- The `planner-overview-v2` unscheduled-Task projection excludes these exact
  Deadline-managed sources (`source` or metadata contract version
  `deadline-plan-v1`) so Preparation work cannot re-enter the ordinary Task
  editor. A positive active Task block also excludes an open Task; partial
  remainder stays Planner attention rather than a second executable target.

### Habits

Habit V1 supports exactly these cadences:

- `daily`: one scheduled opportunity every local calendar day.
- `weekdays`: one opportunity on each selected ISO weekday, with at least one
  and at most seven unique weekdays.
- `weekly_target`: one binary completion per local date, with a target of 1-7
  completions in the current ISO week.

The canonical `habits.frequency` compatibility projection is `daily` for daily
and selected-weekday cadence, and `weekly` for weekly target cadence. Typed
cadence details live in `habits.metadata` under contract version
`habit-v1`.

Every active manual or Setup-owned Habit appears once in the
`planner-overview-v2` Habit summary. It is `scheduled` only with a positive
active Habit slot. Pending creation remains an unconfirmed Planner preview and
does not fabricate a Habit row or executable action.

An outcome is one of `completed`, `skipped`, or open. Open means no row exists
for that local date. Completion uses `value = 1`; skip uses `value = 0`; the
explicit `habit_logs.status` is authoritative. Repeated same-day writes upsert
the same `(habit_id, entry_date)` row.

The UI captures one local target date before awaiting an outcome or undo write.
Persistence, response-loss readback, and best-effort snapshot refresh all use
that same date even if the clock crosses midnight. Outcome reconciliation
requires the exact status, compatibility value, and normalized note on that
date; undo reconciliation requires that the row is absent. Manual habit edit,
pause, archive, and restore use the same exact owner-scoped mutation-timestamp
and requested-field readback rule as tasks.

Daily and selected-weekday progress is:

```text
completed elapsed scheduled opportunities / elapsed scheduled opportunities
```

The current local date is an elapsed opportunity once it is scheduled, even
while still open. A skipped opportunity remains in the denominator and never
enters the numerator. A missed opportunity is a past scheduled date without a
row. Weekly-target progress is:

```text
completed dates in the current ISO week / weekly target
```

Skip is reported separately and never fabricated as completion. A completion
streak counts consecutive completed scheduled opportunities (or consecutive
met weekly targets); an open, missed, or skipped required opportunity does not
advance it.

Setup-owned active habits remain available for completion, skip, and undo.
Their definition, pause, archive, and restore commands remain owned by Settings
Setup and are excluded from generic Habit Management.

The database revalidates every habit-log insert or update, not only the Flutter
precheck. It locks the owned habit row `FOR NO KEY UPDATE`, requires active
lifecycle and non-candidate/non-archived Setup state, and rejects a selected-
weekday outcome whose `entry_date` is not scheduled. This closes stale-read
races with concurrent pause/archive/cadence changes. Weekly-target and daily
cadence remain selectable on every local date.

Habit and log reads are paginated deterministically (500 habits per page and
1,000 outcomes per page) rather than silently truncating a large account. The
client loads outcomes beginning 370 calendar days before today for
progress/streak logic.
New manual habits persist a local calendar `metadata.started_on`; progress uses
that date instead of re-deriving creation day from a UTC timestamp. Calendar-day
iteration and differences use date components, so Europe/Berlin 23/25-hour DST
transition days still count as one scheduled day.
For an authenticated account, `today`, `started_on`, the exact outcome target,
and its post-write snapshot refresh are resolved through the profile's IANA
timezone. The target is captured before asynchronous work and reused unchanged.
Guest-only data uses the device calendar deliberately; an invalid account
timezone never triggers that fallback.

### Focus Sessions

- Planned duration: 5-240 minutes.
- At most one active focus session per user.
- At most one linked target: an owned task or an owned active habit.
- A task target must be `todo` or `in_progress`.
- A habit target must be active and not candidate/archived Setup state.
- A task-provided initial target is applied once. After finish or abandon, the
  next composer resets to an independent block instead of silently reusing the
  prior linkage.
- Finish and abandon operate only on the user's currently active session.
- `actual_minutes` is elapsed wall-clock whole minutes, never planned time.
- `metadata.entry_date` is derived from the captured start instant in the
  authenticated profile timezone; it is not derived later from the device
  timezone.
- A committed finish/abandon response loss succeeds only when an owner-scoped
  readback matches the requested terminal status, exact end instant, and exact
  measured duration. A different terminal transition remains an error.
- After completion or abandonment, every update to the focus history row is
  rejected, including metadata, identifiers, and `updated_at`. Task and habit
  target foreign keys use `ON DELETE RESTRICT`, so deleting a linked target
  cannot erase or detach historical attribution.
- For an active Deadline Planner plan, only a completed session linked to its
  stable managed task and started no earlier than first activation contributes
  measured `actual_minutes` to derived plan progress. Active or abandoned
  sessions do not contribute. A qualifying session still never completes a
  block, managed task, or plan; explicit planner completion remains required.

The database enforces the planned-duration bounds, single-active-session
invariant, exact lifecycle shape, linked-target ownership/availability,
immutable start and terminal history, and restricted target deletion. Target
validation locks the selected task or habit row so availability cannot change
between validation and the focus write. Application validation provides a
recoverable error before a write whenever possible.

Study Setup V1 extends only Focus start defaults and metadata, not the Phase 3
command set or lifecycle. A selected Planner/Preparation block duration takes
priority, followed by the saved Study duration, the latest terminal session,
and the 25-minute fallback. Saved active preparation items appear as a
transient Ready/Not-needed checklist with an explicit skip; choices are never
stored. A manual session may override its duration once.

Scheduled Focus uses the additive `focus-start-v2` backend path. A session may
retain one immutable `focus_session_schedule_sources` row pointing to its
Deadline or Planner Task block and snapshotting the original Focus interval and
recovery. The server supplies the actual start and terminal instants. The
selected target and recovery remain fixed; the student may shorten only the
remaining block duration. The complete actual Focus-plus-recovery interval must
be free of active Focus, Setup/fixed commitments, active Planner/Preparation
reservations, Habit slots, and current consented Calendar busy time. The chosen
source block alone is excluded, and adjacent half-open boundaries are allowed.
Missing current Calendar truth fails closed. Manual Quick Action starts retain
their existing behavior. Flutter first reads the authenticated strict
`focus-capabilities-v1` contract. Only a definitive `404` for that side-effect-
free capability route selects the legacy direct path for a manual V1 start or
an already stored V1 lifecycle write; auth, network, malformed-response, and
server failures remain honest errors. Scheduled starts never use that fallback,
and a stored `focus-session-v2` row always requires the backend for terminal
server-time truth.

Each scheduled-context load is authoritative for both target and remaining
duration. Flutter replaces a stale selected target, clamps an invalid prior
duration back to the current remainder, rejects invalid setter values, and
requires both values to remain valid before start. Canonical completed
(`source_fully_credited`) and sub-five-minute
(`source_remaining_too_short`) contexts render as blocked inline states without
an empty duration control or a `starts now` claim. Start still records the
actual server instant for either a past or future source interval while the
immutable source row retains the planned origin.

`request_id` is also the Focus session id. Exact content replay returns the
same `focus-session-v2` row; different content returns
`409 focus_request_conflict`. Reflection, local-day assignment, Today, and
Personal Learning continue to use only actual
`started_at`, `ended_at`, and `actual_minutes`; planned provenance is display
and credit-routing context only.

The selected recovery duration is copied to
`focus_sessions.metadata.recovery_minutes`. Completing, but not abandoning, the
session starts a skippable device-local countdown that can be restored while
unexpired. There is no recovery row or completion fact, and recovery contributes
to neither Focus/Task/Deadline progress nor any preparation budget. The exact
extension is in `docs/study-setup-v1-contract.md`.

## Executable Action Target V1

The stable, ranking-independent command envelope is:

```text
ExecutableActionTarget
- contract_version: executable-action-v1
- id: stable string derived from command and target
- kind: task | habit | focus | planning | recovery | capture
- command: open_task | complete_task | log_habit | start_focus |
  review_plan | open_capture
- target_id: nullable UUID/string required by target-specific commands
- estimated_minutes: nullable integer in 1-480
- metadata: bounded structured context
```

Allowed metadata keys are `entry_date`, `focus_minutes`, `habit_outcome`,
`route`, `source`, and `target_kind`. Values must be scalar strings, integers,
or booleans; nested payloads and unknown keys are rejected.

Command compatibility:

| Command | Required kind/target | Phase 3 handler |
| --- | --- | --- |
| `open_task` | task plus task id | Open the durable task editor |
| `complete_task` | task plus task id | Execute typed task completion |
| `log_habit` | habit plus habit id | Open or execute today's habit outcome |
| `start_focus` | focus; optional owned task/habit context in bounded metadata | Open the real focus-session flow |
| `review_plan` | planning, optional target | Phase 8 opens the real authenticated `/weekly-review` surface; dispatch itself never generates or applies |
| `open_capture` | capture plus implemented route | Open Evening Shutdown or Morning Calibration only |

The briefing-first Flutter consumer originally used an exhaustive
`ExecutableActionDispatcher`. Today Overview superseded that card; both the
unreachable dispatcher and the unconsumed general Dart envelope parser, with
their isolated tests, have been removed. Current Today Task, Habit, Focus,
Capture, and Weekly Review controls call their owning typed controllers or
routes directly and retain explicit guest/mock capability handling.

The strict envelope remains the persisted backend briefing boundary. FastAPI
rejects unknown top-level or metadata fields, null/non-object metadata,
explicit-null metadata fields, coercible or fractional numbers,
whitespace-normalized identifiers, invalid ISO calendar dates, command-specific
metadata leakage, mismatched kind/target/linkage, and a focus estimate outside
5-240. Unknown commands never become a generic route or enabled no-op.

Flutter keeps the named `executableActionContractVersion` in the Actions domain
and uses it for the compatible manual Focus `metadata.action_target` write.
Its value and stored envelope remain unchanged; this shared version does not
require a second parser without a consumer.

The bounded planning surface and its mutation limits are defined in
`docs/phase-8-weekly-review-contract.md`. Task/schedule/replacement changes are
not made executable merely because Weekly Review navigation exists.
Deadline Planner V1 likewise adds no new `executable-action-v1` command or
metadata key: `/preparation-plans` is a deliberate product surface governed by
`docs/deadline-planner-v1-contract.md`, not an implicit Dashboard mutation.

## Refresh And Failure Semantics

Completed Focus actual minutes and active future reservations are distinct
inputs to `exam-plan-health-v1`: actual minutes are credited exactly once from
the completed session, while future block minutes only reduce uncovered work.
Task, Habit, fixed-commitment, and Setup schedule mutations invalidate Health
because they consume shared availability. No Focus command writes a Health
status, sends an alert, or automatically replans after a miss.

`multi-exam-plan-v1` remains outside `executable-action-v1`. Focus completion
facts and Task/Habit/fixed-commitment occupancy participate only as read inputs
to its owner-locked digest and exact simulation. A batch confirmation activates
existing Deadline-managed Task projections atomically through Deadline
authority; it does not add a generic action command or start Focus.
Direct authenticated Task and Habit lifecycle writes take that same owner
advisory lock in an alphabetically first `BEFORE` trigger. Their existing
future-reservation release remains an `AFTER` effect and therefore cannot run
between a Multi-Exam digest check and its atomic commit.

- A successful or exactly reconciled real task, habit, or focus write triggers
  daily snapshot refresh best-effort.
- Flutter routes the downstream read-cache impact through one typed app
  composition service. Habit outcome, Habit definition, Today-owned Task, and
  Focus lifecycle changes remain distinct impacts; feature callers do not
  enumerate Dashboard, Briefing, Planner, Workload, or Outlook providers.
- Embedded Today Task/Habit execution uses narrow application command ports.
  The controller owns in-flight dedupe, optimistic overlays,
  committed-versus-unconfirmed results, and stale/reload-only state; the
  Dashboard widget does not construct or invoke either concrete Supabase data
  source.
- Standalone Today Habits and Habit management resolve their concrete data
  sources through app composition providers. Their presentation pages do not
  import or construct the Supabase source, map read/write failures to retained-
  data guidance, and remain usable at 320 logical pixels with 200-percent text.
- The read-only `today-week-agenda-v1` action union reuses these same execution
  seams. Preparation and Planner Task blocks carry their exact source kind/id
  into a fresh start-context read; active Focus resumes and terminal Focus opens
  reflection. A Habit action is emitted only for the exact current profile-local
  date because the existing Habit command is date-less. Other Habit dates and
  Setup/Calendar/fixed-commitment facts remain static. No Week Agenda action
  adds a write endpoint or weakens owner/date authority.
- Habit outcome/undo captures one local target date before its write, uses that
  date for exact response-loss reconciliation, and refreshes that same date.
- Focus start persists its local `metadata.entry_date`. Start, finish, and
  abandon refresh that persisted start date. Legacy/invalid metadata falls back
  in Flutter and FastAPI to the UTC calendar date of persisted `started_at`.
  Crossing midnight does not move a new focus fact to the terminal day.
- The migration backfills a missing legacy focus `metadata.entry_date`
  deterministically from the UTC calendar date of `started_at`.
- Backend focus reads use a broadened UTC window, prefer a valid persisted
  `metadata.entry_date` for local-day filtering, and fall back to `started_at`
  UTC date only for legacy/invalid metadata.
- Backend habit-log and focus-session inputs paginate in stably ordered
  1,000-row pages until a short page, so snapshot counts and minutes cover the
  complete requested action-fact window. A shared repository page collector now
  owns advancement and final-page detection while retaining the compound
  keyset filter, `id` tie-breaker, owner/date filters, and validation errors.
- Snapshot refresh failure never rolls back the original durable write.
- Normal Dashboard reads do not generate derived advice.
- Task/habit/focus writes never generate generic Recommendations or call an LLM.
- Finishing a linked focus session may change a later read of Deadline Planner
  progress, but does not generate a revision, move a dated block, complete the
  plan, or call a planner mutation. Replanning always requires a deliberate
  proposal followed by explicit confirmation.
- UI success is shown only after the durable response or exact owner-scoped
  reconciliation proves the requested write.
- Risky terminal actions provide confirmation or a direct undo.
- Failed writes retain editor input and the last persisted list projection.

## Verification Contract

Required focused coverage includes every command and transition; task and focus
validation; all three habit cadences; scheduled opportunity, completion, skip,
miss, undo, streak, ISO-week, DST-safe calendar arithmetic, `started_on`, Habit
parser parity, Setup ownership, direct feature commands, strict backend action
envelopes, user scoping, idempotency, snapshot
refresh, and guest/mock locality.

Study Focus coverage additionally proves duration priority, configured and
empty checklists, partial/all/remaining skip, absence of ritual history, manual
duration override, strict recovery metadata, completed-only countdown,
restoration, expiry, and explicit skip.

Scheduled Focus coverage additionally proves refreshed duration/target
authority, invalid-setter rejection, completed and sub-five-minute UI safety,
past/future actual-time starts, immutable origin, and exactly-once source credit
under terminal replay.

The browser E2E source asserts exact database rows for task
create/edit/postpone/undo, complete/restore, and cancel/restore; manual and
Setup-owned habit execution, skip and undo without duplicate logs; and focus
start/finish/abandon with owned linkage and no implicit target completion. The
source also injects committed response loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish. Negative database
writes cover invalid task lifecycle, duplicate active focus, every terminal
focus update including `updated_at`, focus duration, inactive habit, and
unscheduled selected-weekday outcomes. These assertions define required
coverage; they are not a claim that the current checkout's full browser run
passed.

Deadline Planner integration coverage must additionally prove stable managed-
task identity, rejection/redirect of every generic task mutation/editor path,
allowed focus start only while the managed task is open, exact planner-owned
field and terminal projections, completed post-activation linked-focus
accounting, exclusion of active/abandoned/pre-activation sessions, and absence
of implicit block/task/plan completion. Those requirements extend the
verification boundary; they do not claim a current test run passed.
