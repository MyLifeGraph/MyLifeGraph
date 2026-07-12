# Phase 3 Executable Actions Contract

Status: implementation contract for Phase 3. This contract is deliberately
independent of briefing ranking and the future decision-first Today redesign.

## Scope And Boundaries

Phase 3 makes tasks, habits, and focus sessions executable, durable, scoped to
the authenticated user, and recoverable. It also defines the typed action
target that a later deterministic briefing may return.

Phase 3 does not rank actions, persist a daily briefing, redesign Dashboard as
Today, generate recommendations during normal writes, call an LLM, expose
Coach, import a calendar, or change the Phase 2 Daily State classifier.

Guest and mock sessions remain local and do not receive Supabase-backed task,
habit, focus, or snapshot commands.

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
- A committed finish/abandon response loss succeeds only when an owner-scoped
  readback matches the requested terminal status, exact end instant, and exact
  measured duration. A different terminal transition remains an error.
- After completion or abandonment, every update to the focus history row is
  rejected, including metadata, identifiers, and `updated_at`. Task and habit
  target foreign keys use `ON DELETE RESTRICT`, so deleting a linked target
  cannot erase or detach historical attribution.

The database enforces the planned-duration bounds, single-active-session
invariant, exact lifecycle shape, linked-target ownership/availability,
immutable start and terminal history, and restricted target deletion. Target
validation locks the selected task or habit row so availability cannot change
between validation and the focus write. Application validation provides a
recoverable error before a write whenever possible.

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
| `review_plan` | planning, optional target | Explicitly unavailable until a bounded planning surface exists |
| `open_capture` | capture plus implemented route | Open Evening Shutdown or Morning Calibration only |

Flutter's exhaustive `ExecutableActionDispatcher` accepts only an already
validated target and delegates supported commands to injected, command-specific
handlers. It returns an explicit unavailable result for `review_plan` and for
synced commands outside a real authenticated session; it does not swallow
handler failures.

The Flutter and FastAPI parsers intentionally enforce the same boundary:
unknown top-level or metadata fields, null/non-object metadata, explicit-null
metadata fields, coercible or fractional numbers, whitespace-normalized
identifiers, invalid ISO calendar dates, command-specific metadata leakage,
mismatched kind/target/linkage, and a focus estimate outside 5-240 all fail. The
two exact capture routes and `target_kind` linkage rules are identical on both
sides.

An unknown command, invalid kind/target combination, unavailable capability,
or invalid metadata value produces an explicit unsupported result. It never
maps to a generic route or enabled no-op.

## Refresh And Failure Semantics

- A successful or exactly reconciled real task, habit, or focus write triggers
  daily snapshot refresh best-effort.
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
  complete requested action-fact window.
- Snapshot refresh failure never rolls back the original durable write.
- Normal Dashboard reads remain read-only for recommendations.
- Task/habit/focus writes never generate recommendations or call an LLM.
- UI success is shown only after the durable response or exact owner-scoped
  reconciliation proves the requested write.
- Risky terminal actions provide confirmation or a direct undo.
- Failed writes retain editor input and the last persisted list projection.

## Verification Contract

Required focused coverage includes every command and transition; task and focus
validation; all three habit cadences; scheduled opportunity, completion, skip,
miss, undo, streak, ISO-week, DST-safe calendar arithmetic, `started_on`, parser
parity, Setup ownership, action dispatch, user scoping, idempotency, snapshot
refresh, and guest/mock locality.

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
