# Architecture

Android Focus Protection V1 adds a device-local adapter below the existing
Flutter Focus presentation. Supabase remains the session authority; Flutter
reconciles confirmed session identity and timing through an injectable channel,
while native preferences, Accessibility, Alarm, Boot, and AutomaticZenRule
components own only a temporary device lease. See
`docs/android-focus-protection-v1-contract.md`.

This document describes the current repository shape. It intentionally
distinguishes implemented behavior from planned backend integration. For the
target backend flow, product agents, LLM cost controls, and next implementation
sequence, see `docs/backend-roadmap.md`.

The current Setup-personalization boundary is defined in
`docs/setup-personalization-retirement-contract.md`. It supersedes older
descriptions of Setup Goals, focus areas, friction answers, coaching style, or
Setup-owned Reminder preferences.

## High-Level Shape

```text
Flutter app <-> Supabase Auth/Postgres
Flutter app <-> FastAPI AI service
Flutter app <-> local mock data and guest storage
FastAPI -> local Codex CLI/OAuth (explicit Phase 10 development adapter only)
```

The Flutter app is the main product surface. Supabase is the intended auth and
persistence backend. The FastAPI service is an independent AI boundary that
currently serves authenticated Intake V1 and deterministic recommendation
and daily-briefing workflows when backend Supabase settings are configured. It
also owns deterministic user-state snapshot aggregation plus the protected
scheduled preparation boundary for backend-generated daily state and briefings,
the bounded deterministic weekly-review boundary, and the optional bounded
read-only `.ics` import boundary.
It also owns the bounded authenticated Coach boundary. Only a deliberate
`POST /v1/coach/respond` may invoke a configured provider; capability, history,
memory, Dashboard, capture, action, scheduler, recommendation, and weekly-review
paths remain generation-free. The first real provider is explicitly enabled and
development-only; the CLI/OAuth process is not a new Flutter or Supabase
connection.

## Mobile App

The Flutter app uses feature-first clean architecture:

- `core` contains config, bootstrap, routing, network clients, Supabase access,
  the IANA timezone resolver, theme, and reusable widgets.
- `features/*/domain` contains entities and repository contracts.
- `features/*/data` contains mock data sources, Supabase data sources, and
  repository implementations.
- `features/*/application` contains orchestration that should not live in
  widgets.
- `features/*/presentation` contains pages, widgets, and providers that are
  private to that feature.
- `composition` contains app-level wiring whose dependency knowledge cannot
  belong to one feature without coupling that feature to its consumers.

Large feature pages keep orchestration in the page state and move cohesive
presentation units into feature-owned widget modules. Planner follows this
boundary explicitly: `planner_page.dart` owns Riverpod/navigation/mutation
coordination, `planner_sections.dart` owns read-only overview sections, and
`planner_dialogs.dart` owns draft collection and preview dialogs. Those widget
modules depend only on Planner/domain and shared presentation contracts; they
do not read providers or perform writes.

Cross-feature Riverpod factories, shared shell actions, and UI adapters that
combine two feature-owned contracts live in `composition`. This includes Auth,
profile-date, Capture, Dashboard, Deadline, Recommendation, Briefing, Weekly
Review, Notification, projection-refresh, and Today-command wiring. The guest Dashboard
snapshot adapter combines the Quick Action store with the Dashboard projection
there, while `DashboardRepositoryImpl` depends only on a snapshot-loader
function. Auth likewise receives a guest-capture migration callback instead of
importing Quick Action data sources.

An executable source guard rejects every new import from one feature into
another feature's `data` or `presentation` directory. Its one current exact
exception is the explicitly embedded Focus-reflection sheet in Evening
Capture. The entry carries a rationale and the guard fails if it becomes stale.
Cross-feature domain values and narrow application ports remain allowed; app
composition may know concrete implementations. No barrel layer or
dependency-injection framework is used.

`ApiClient` is the Flutter HTTP exception boundary. It translates Dio timeout,
connection, cancellation, response, and unknown failures into the small
framework-neutral `ApiFailure` value while retaining only the status code and
optional contract response data needed by a feature. Feature application,
domain, and presentation layers do not import Dio. They keep their own
conflict, stale-state, exact-retry, reload, and student-facing message rules;
the Coach data boundary additionally converts transport evidence into its
typed `CoachRemoteException`. Dio stream and cancellation types remain limited
to `core/network` and the Coach data implementation that owns SSE transport.

State management is Riverpod. Navigation is GoRouter. When the development
Coach surface gate is enabled, the shell navigation maps to Today, Insights,
central Quick actions, Planner, and Coach. Today, Insights, Quick actions,
Planner, Coach, and Settings share one top action group: an optional
page-specific action comes first, an unread local Coach result comes second,
and Settings comes last. Settings is pushed from that control instead of
occupying a redundant shell destination, so Back returns to the originating
main page. Its own Settings control remains visible, selected, and inert.
Settings-owned routes do not select an unrelated shell item. When the Coach
surface gate is off, its destination is omitted rather than replaced by
Settings. Stored Inbox is reached from Settings; `/alerts` remains a compatible
Settings-owned route. Auth, Setup, Capture, and other sub-routes do not inherit
the main-page action group.
One immutable Shell destination descriptor list owns each destination's label,
path, active nested paths, desktop/mobile icon variants, emphasis, and Coach
capability requirement. Desktop, mobile, and large-text compact navigation all
derive from that list; GoRouter route declarations remain explicit in the app
router.
In-page calls to action push GoRouter history. Shell destinations, auth
redirects, and completed flows replace it. `AppPage` owns the shared top-left
back control: it pops actual history and otherwise uses an explicit
feature-level fallback for direct deep links. A primary shell page opened by
shell navigation has no meaningless back affordance. Multi-step full-page
Capture flows consume Back internally before leaving their route; dialogs and
bottom sheets retain their own close actions.
Guest/demo sessions receive one persistent `Local demo` banner. The canned
Coach preview and direct Supabase message writer have been replaced by a typed
FastAPI Coach surface at `/coach`; `/more` aliases that route. Guest/mock renders
honest local unavailability and makes no Coach HTTP call.
`/deep-work` now serves the real linked focus lifecycle only when synced
execution is available; guest/demo sessions redirect to Quick Action.

Cross-feature cache effects after durable Flutter writes are composed through
one direct `ProjectionRefreshCoordinator`. A caller names the domain impact,
such as Daily Capture, Habit outcome/definition, Focus, Deadline Plan, Planner,
Setup, timezone, or preparation-budget change. Only the composition provider
maps that impact to Daily Snapshot refresh and Riverpod read-projection
invalidation. This is synchronous application orchestration, not a broadcast
event bus. The screen that owns Today or Planner still owns its controlled
reload and stale-after-mutation state; guest Capture invalidates local reads
without calling the backend.

Today Task/Habit writes are owned by the feature-local
`TodayCommandController` in `features/dashboard/application`. It depends only
on narrow Task/Habit command ports, the Dashboard repository contract, and the
typed projection-refresh callbacks. App composition adapts the concrete
Supabase sources to those ports. `dashboard_page.dart` retains dialogs,
navigation, Undo presentation, and student-facing messages, but it neither
constructs nor invokes a Supabase Task/Habit source. The former unreachable
inline Task editor and its inert edit/cancel/postpone callback chain were
removed; Task creation and editing continue through Planner. In-flight identity
locks, optimistic
status/outcome overlays, committed-versus-unconfirmed results, the single
post-write Today reload, and stale/reload-only state are independently testable
outside the widget. Composition captures the application-level coordinator for
each accepted command future. If the auto-disposed Today controller leaves the
route before a durable write completes, shared Snapshot refresh and foreign
read invalidation still finish; only controller-owned state and Today reload
are skipped.

Dashboard presentation is split by product responsibility rather than by an
arbitrary line limit. `TodayOverviewSections` owns capture streak, progress,
and agenda; `TodayTaskSections` and `TodayHabitSection` own their typed display
state and action callbacks; `DashboardMoreSection` owns the lazy workload,
Weekly Review, saved-signal, recommendation, feedback-history, and full-week
surface. `_DashboardHome` composes those section APIs instead of forwarding
each leaf callback and optimistic collection independently. Shared visual
primitives remain Dashboard-local and contain no feature command or data
access.

The Coach controller is app-scoped and bound to the currently eligible profile,
not to the lifetime of the Coach route. Its draft, retry request identity, and
active SSE subscription therefore survive shell navigation. Profile change,
logout, Coach-gate loss, or app-container teardown rebuilds/disposes that
boundary, clears its local draft/result notice, and cancels any active response.
A separate in-memory, profile/request-bound `completed|failed` notice drives
the shared headers and never calls the Coach API. A successful notice is read
only when the end marker after the latest reply and uncertainty is fully inside
the Coach scroll viewport. A failure is read at its error/retry marker or when
a subsequent retry starts. Opening Coach, seeing an older turn, or closing the
floating notice does not acknowledge it.

## Runtime Configuration

The mobile app reads Dart defines through `AppConfig.fromEnvironment()`:

- `APP_ENV`
- `USE_MOCK_DATA`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `AI_SERVICE_BASE_URL`
- `COACH_SURFACE_ENABLED`

Supabase is initialized only when both Supabase values are non-empty. Without
them, the app can still run through local guest mode and mock data.

## Data Source Selection

Source selection is explicit rather than a recovery fallback:

1. Read app config, authenticated session, and Supabase availability from
   Riverpod providers.
2. Use local/mock data only when `USE_MOCK_DATA=true` or the current session is
   explicitly guest/demo.
3. Use Supabase/FastAPI sources for authenticated real accounts.
4. Treat missing real configuration, missing auth, invalid responses, and
   network failures as recoverable errors. Do not substitute personalized-looking
   mock content. A successful empty response remains a separate valid state.

Dashboard, Recommendations, Insights, and the Inbox follow this source
boundary. `AppSurfaceCapabilities` also uses it to hide Supabase-only task,
habit, and focus commands from local guests and to validate route capabilities.
Calendar import follows the same rule: a real authenticated account uses the
FastAPI-backed integration source, while guest/mock renders an honest local
state and makes no calendar API call.
Coach follows it too: `COACH_SURFACE_ENABLED` controls whether navigation is
shown and whether `/coach` remains accessible. It is fail-closed in every
release build and for `APP_ENV=production` unless the exact value `true` is
supplied. When the surface is enabled, a static real-account capability permits
backend access while the authenticated backend capability independently reports
`disabled|unavailable|ready` and controls sending. Provider outage does not hide
persisted history or memory controls.

The global offline banner observes network transport only. It does not claim
that Supabase or FastAPI is reachable, and synced writes are not queued for
later delivery. Guest/demo persistence can continue locally on the current
device; failed synced forms retain their own draft/retry behavior.

`USE_MOCK_DATA=true` wins over the presence of a Supabase client, access token,
or authenticated profile. Setup, canonical check-in, Dashboard,
Recommendations, Insights, and the Inbox stay on their local/demo sources,
and synced execution plus snapshot actions remain unavailable. This prevents a
partly real, partly demo session during local exploration. Auth boot also skips
remote profile reads/creation and guest check-in migration in this mode, then
overlays the locally applied Setup name and completion state so reload remains
local and consistent.

Canonical daily capture selects its store from the authenticated session.
Guest/demo sessions merge one typed local daily entry through
`shared_preferences`; real sessions write one complete branch through
`daily-capture-write-v1`. FastAPI derives the owner, and the owner-locked
`apply_daily_capture_branch_v1` RPC performs branch-local CAS, replay
fingerprinting, daily-row merge, and quick-check-in event projection in one
transaction. Flutter has no direct Daily Log or Behavioral Event write
authority. Other remote-only writes still show an in-app message when Supabase
is not configured.

## Canonical Daily Capture

`/quick-mood-check-in` is the Evening Shutdown implementation, and the legacy
`/daily-check-in` route redirects to it. `/morning-calibration` is a separate,
short Morning Calibration instead of another full daily form.

The current `daily-capture-v4` contract is:

- Typed `EveningShutdownDraft` and `MorningCalibrationDraft` values have stable
  capture ids through retry. `DailyCaptureEntry` is the one same-day aggregate.
- Evening is a three-page flow. Mood, energy, stress intensity, one local
  planned sleep start, and one `300..720` minute target on a 15-minute grid are
  required. The first visible target is 480 minutes; later forms prefill the
  newest valid Evening V4 plan.
  Stress source and controllability appear and become required together only
  at stress `5..10`; each source description is behind a separate accessible
  info control that does not change selection. Reflection and a specific
  blocker are optional and omitted when blank. Tomorrow priority is retired
  from the form and new writes, while a value on an existing branch is
  preserved. Primary and additional friction choices are retired. V2/V3
  captures remain readable, but their friction keys are ignored.
  A V4 merge preserves an untouched older opposite branch with its explicit
  branch version and `compatibility: true`; editing that branch upgrades it and
  requires its V4 fields. New captures do not write the retired
  `gentle_tomorrow` field, while old capture objects containing it remain
  readable. The form no longer asks the user to estimate a focus band:
  completed `focus_sessions` are the source of measured focus time.
- Morning requires aware estimated sleep-start/wake instants, their exact
  derived whole-minute duration and compatible sleep hours, the target used for
  that night, an independent whole-number `1..10` `sleep_quality` estimate,
  current energy, and `normal`, `constrained`, or `flexible` day shape. The
  interval is ordered, minute-aligned, and at most 16 hours. It is labelled as
  an estimated duration, does not repeat Evening questions, and explicitly
  states that it does not generate recommendations or create or change a plan.
  Older V2 Morning objects without `sleep_quality` remain readable; editing
  that Morning capture requires an explicit value before it can be saved.
- Same-day merge replaces only the submitted `metadata.captures.evening` or
  `.morning` object, preserving the other capture and unrelated metadata.
  Numeric compatibility projects mood and stress from Evening, sleep from
  Morning, and energy from Morning when present or Evening otherwise.
- Guest saves use a versioned V4 daily JSON object and remain readable on
  return. Legacy V1/V2/V3 guest JSON remains readable and is upgraded only
  through the same branch-compatible merge.
- Authenticated saves call
  `PUT /v1/daily-capture/{entry_date}/{morning|evening}` with the last-read
  identity of the branch being changed. Morning and Evening merge
  independently; same-branch version drift is `409`, and exact request replay
  does not write twice.
- The Capture RPC rebuilds the daily row and only `source = quick_check_in`
  events in the same transaction. Other Behavioral Events remain untouched.
  Authenticated callers keep owner reads but no direct DML on either table.
- Planned/estimated raw clocks remain only in Daily Log metadata. The
  compatible `sleep_hours` column and Sleep event contain the derived duration;
  event metadata, Daily State, recommendations, notifications, and Coach do not
  receive raw clocks or sleep-target provenance.
- The upsert clears legacy placeholder-only steps, activity, screen-time, focus,
  nutrition, and day-focus values because the canonical form does not collect
  them. It never converts a subjective focus answer into invented
  `focus_minutes`.
- Optional notes remain check-in context. They are not promoted to durable
  `memory_entries`, tasks, recommendations, schedule rows, or notification copy.
- A failed write keeps the draft and exposes retry; an in-flight save ignores a
  second submit. Successful real-account writes refresh the daily snapshot for
  the capture's explicit local `target_date` best-effort; guest/mock writes do
  not call Supabase or FastAPI.

Flutter resolves account-local calendar dates through one
`ProfileLocalDateSource`. It converts one captured instant with the
authenticated profile's IANA timezone and fails closed for an invalid account
timezone. Guest and no-account flows deliberately retain device-local dates.
Daily Capture identity, standalone Habit writes, Focus `entry_date`, Weekly
Review application refresh, recommendation refresh, and managed Preparation
refresh use that boundary; real timestamps remain independent UTC instants.
The inline Today handlers continue to use the exact `local_date` returned by
the Today projection.

The cross-feature write-authority, timezone/DST, observation-ordering, and
durable-mutation reload rules are defined together in
`docs/stabilization-consistency-contract.md`.

## Dashboard Source Contract

`DashboardSnapshot` carries an explicit `localDemo` or `account` origin, load
time, nullable latest check-in, true check-in streak, task rows, and schedule
entries. The Supabase mapper preserves stored mood, energy, sleep duration,
sleep quality, stress, focus, steps, activity, and screen-time values exactly
and reads only persisted Evening/Morning flags, focus band, stress context, and
day shape from metadata.
The guest mapper uses the same merged daily object. The UI shows only fields
that exist and labels the latest row by its real date; missing values do not
become zero, a mode, or a derived readiness score.

The former wellness/optimization/recovery score, fake steps, derived sleep,
invented screen time, hydration estimate, and schedule activity bars are
removed. Tasks retain their own description, deadline, priority, status, and
optional estimate; recommendation reasons are no longer copied into unrelated
task descriptions. Authenticated users can execute typed task commands from the
existing task section. The primary Today area now reads the strict owner-scoped
`today-overview-v2` contract through `GET /v1/today/overview-v2`; the V1 route
remains available for existing clients and its focused contract tests. It may
be removed only after an explicit API support decision establishes that no
supported client still depends on it; Flutter's exclusive V2 use is not by
itself sufficient evidence. FastAPI captures
one UTC instant, resolves the profile-local date, and isolates check-in, task,
habit, recurring Setup, confirmed Preparation, current imported Calendar, and
actual Focus reads. Normal load is GET-only and never generates or adjusts a
briefing or recommendation.

Today leads with a strict both-capture streak and transparent dynamic progress,
then renders `Today at a glance` as a vertical agenda. Planner Task blocks,
Habit slots, and fixed commitments extend Setup/Preparation/Calendar/Focus
without adding block-level completion or duplicate target counts. All-day
events precede timed entries; overlaps remain separate. Selected Tasks and
Habits reuse the existing Phase 3 handlers for inline completion, skip, undo,
and Focus. Deadline Planner-managed tasks stay outside Today progress and
redirect to their owning Preparation plan. A counted-source failure makes progress explicitly
unavailable while unaffected agenda/sections remain usable. Actionable agenda
rows route by exact identity: scheduled Preparation/Planner Task blocks load
`GET /v1/focus/start-context/{source_kind}/{block_id}`, active Focus opens its
timer, and terminal Focus
loads its exact reflection. V2 Focus lifecycle writes use FastAPI service-only
RPCs and retain an optional immutable planned-source row. The authenticated
`GET /v1/focus/capabilities` read permits mixed-version fallback only for
manual V1 lifecycle writes after a definitive missing-route response; scheduled
or already persisted V2 sessions never downgrade. All daily and
learning projections continue to consume actual Focus timestamps. Workload, Weekly
review, saved signals, recommendations, decision-feedback history, and the full
week load lazily under `More`. The exact rules live in
`docs/today-overview-v1-contract.md`.

## Planner V1

Planner is the authenticated planning home for Tasks, Habits, exam/assignment
Preparation, and one-off or weekly fixed commitments. Flutter uses a strict
FastAPI controller/data boundary; guest/demo is a zero-call locked surface.
Task/Habit proposals are immutable previews and create or update their target
atomically only on confirmation. Existing targets remain unscheduled until the
user deliberately supplies the missing values and proposes a revision.
The asynchronous Planner service only loads the overview inputs; a pure
feature-local builder owns the seven-day, preparation, unscheduled/history, and
attention projection. Proposal persistence crosses the repository boundary as
one validated `PlannerProposalWrite`, so target identity, revision, Task
blocks, and Habit slots cannot drift as independent dictionaries.

The shared availability service composes Setup commitments, manual commitments,
active Planner reservations, active Preparation blocks, the current instant,
profile timezone/energy window, and optionally consented current `.ics` busy
time. Deadline Planner delegates its slot calculation to the same component and
reads the same Planner calendar preference. The database owner lock and
service-role RPCs recheck target version, current import, and every competing
reservation at confirmation. Fixed commitments are authoritative: conflicts
become attention facts and never trigger automatic movement.

Setup is the primary timetable input. A recurring Setup commitment may have
inclusive optional `valid_from`/`valid_until` semester bounds in its owned
metadata; undated and older rows remain unbounded. Planner surfaces an honest
readiness warning before automatic planning when it cannot see a weekly Setup
block, an active future manual commitment, or explicitly consented imported busy
time. Calendar import remains an optional Settings integration and is not an
onboarding prerequisite.

Optional Study Setup composes with this availability boundary without widening
it. A Planner Task uses the configured focus/recovery rhythm only after the
student explicitly enables `Use study rhythm`; Habits never do. Focus minutes
retain the existing planned-minute and budget arithmetic, while the full
recovery interval is unavailable for overlapping reservations. A changed Study
revision makes a pending rhythm-bound preview stale and marks an active
rhythm-bound plan for review, but never moves it.

The additive forced-RLS schema and exact routes are specified in
`docs/planner-v1-contract.md`; the Study extension is specified in
`docs/study-setup-v1-contract.md`.

Persisted `daily-briefing-v1` rows remain deterministic backend inputs for the
scheduler, reminder generation, Coach context, and historical feedback. The
Today UI no longer presents their ranking as a decision made for the user, and
Flutter has no direct `/v1/briefings/*` repository or provider: Today V2 is its
read authority and deliberate briefing generation remains backend-owned. This
client cleanup does not remove the persisted backend contract, scheduled
preparation, notification provenance, Coach context, or readable history. A
local guest dashboard derives only its real locally saved capture state and
otherwise shows honest empty sections; it does not call FastAPI/Supabase or
invent a personalized briefing, task, habit, or schedule.

Authenticated real accounts can open `/weekly-review` from Dashboard or a
strict `review_plan` action. Flutter reads the latest completed profile-local
ISO week without generation, preserves `not_ready`, missing, current, stale,
and error truth, and generates or refreshes only after an explicit control.
Only a manual Habit V1 shrink/pause/archive proposal can call an existing typed
Habit V1 command after exact before/after confirmation. Setup-owned changes
return to Settings Setup; staged replacement, task, or schedule proposals do
not mutate a record. The compatible `goal_linked_completed` fact is always
zero, and no Goal is loaded or proposed. Guest/mock sessions never call the
weekly-review API.

Insights has separate source boundaries. Stored `ai_insights` notes remain an
owner-scoped Supabase read, and guest/demo exploration uses labelled local
fixtures. For a real account, however, `Personal study pattern` and the
profile-local correlation points come only from the read-only
`GET /v1/insights/personal-patterns` FastAPI contract. Flutter no longer
reconstructs planned workload or Habit history from current rows. It analyzes
the returned measured Focus/reflection, preceding valid sleep, and eligible
Morning-energy points over the bounded 7/14/30/90-day views. Missing metrics
stay absent. This exploration uses no LLM and has no Planner authority; only the
separately gated Planner-ready preference in the backend response may influence
a deliberate new preview.

## Phase 3 Executable Actions

Phase 3 keeps simple user-owned mutations in typed Flutter/Supabase boundaries:

- `TaskSupabaseDataSource` resolves the authenticated user, scopes every read and
  update by both user and object id, and supports idempotent UUID-keyed create,
  edit, complete, postpone, cancel, restore, and immediate undo. Failed creates
  retain their draft/request id for retry. Every update, including edit,
  lifecycle transitions, restore, and undo, chooses a mutation timestamp and
  reconciles a lost committed response only when an exact owner-scoped
  timestamp/requested-field readback matches; concurrent divergence remains an
  error. Terminal actions are confirmed or expose undo.
- Habit V1 stores `daily`, selected ISO weekdays, or `weekly_target` cadence in
  bounded `habits.metadata` while retaining compatible `frequency`/`target`
  columns. Manual habits have active/paused/archived lifecycle. Today Habits
  persists exactly one explicit `completed` or `skipped` row per local date and
  deletes it for undo; open and missed opportunities remain derived. Setup-owned
  definitions/lifecycle stay in Settings Setup, but active rows share the daily
  outcome path. Manual edit/pause/archive/restore uses exact mutation readback
  after response loss. Outcome/undo captures its local target date before the
  write, proves the exact row or absence after response loss, and refreshes the
  same date. Paginated reads load all habits plus outcomes beginning 370
  calendar days before today. Manual creation persists local `started_on`, and
  date-component arithmetic keeps scheduled opportunities stable across DST
  boundaries. Account dates use the shared profile-local boundary; guest-only
  state uses the device calendar explicitly.
- `/deep-work` is a real focus-session screen for authenticated real accounts.
  It starts at most one active session, optionally links one owned open task or
  active habit, measures whole elapsed minutes at finish/abandon, and never
  completes the linked object automatically. Finish/abandon use exact terminal
  readback after a committed response loss. Target validation locks the chosen
  task/habit row. Terminal rows reject every update, including `updated_at`, and
  `ON DELETE RESTRICT` target FKs preserve their historical linkage. The UI
  reconstructs countdown, progress, and end time from persisted state after a
  reload, offers the latest/custom duration, and only after five completed
  sessions may show a reviewable median-duration suggestion. It infers no local
  time-of-day preference and changes no setting automatically. A new session's
  `metadata.entry_date` comes from its captured start instant in the
  authenticated profile timezone.

Flutter and FastAPI share a strict, ranking-independent
`executable-action-v1` envelope for `open_task`, `complete_task`, `log_habit`,
`start_focus`, `review_plan`, and `open_capture`. Kind/command/target and bounded
scalar metadata are validated; unknown combinations are rejected. Flutter and
FastAPI deliberately reject the same unknown top-level/metadata fields, null or
non-object metadata, explicit null metadata fields, coercible numbers, invalid
calendar dates, identifier normalization, duration/linkage bounds, and
command-specific metadata leakage. The former Flutter briefing dispatcher was
removed when Today Overview superseded the briefing-first card; current Today
Task, Habit, Focus, capture, and Weekly Review actions use their owning typed
controllers and routes directly. Phase 8 gives `review_plan` a real
authenticated `/weekly-review` navigation
handler; guest/mock and unsupported sessions stay unavailable, and dispatch
never generates or mutates. Phase 3 defines executable targets but does not select a primary action,
persist a briefing, redesign Dashboard as Today, generate recommendations during
normal writes, or call an LLM. The full contract is in
`docs/phase-3-executable-actions-contract.md`.

## Deadline Planner V1

`deadline-plan-v1` is a separate authenticated FastAPI workflow for explicit
exam and assignment preparation. `/preparation-plans` asks the user for their
own `30..30000` minute total estimate and prior credit that will not otherwise
be credited, plus bounded session/per-plan-daily preferences. The surface shows
the deterministic ordered energy windows and latest-manual-import boundary.
`POST /v1/deadline-plans/proposals` persists an immutable
proposed revision with at most 120 deterministic dated blocks; it cannot replace
the active revision until the user confirms it. The first confirmation creates
one stable managed Phase 3 task with the plan id, and later confirmations retain
that identity. The planning window is at most 366 profile-local calendar days;
proposal concurrency follows the latest persisted revision while completion and
cancellation require the current active revision.
The Deadline service passes one validated `DeadlineProposalWrite` to its
repository rather than parallel proposal/block dictionaries. The read-only
Exam-Week calculation lives in a pure builder with no repository or service
access; the service retains only bounded input loading and error mapping.

The managed task is not generically editable. Task mutation/editor paths detect
its planner source and route back to `/preparation-plans`; only planner confirm,
complete, and cancel may update its bounded projection, with terminal plan/task
state committed atomically. Phase 3 focus may still target it while it is open.

Completed focus sessions linked to that task after activation contribute their
measured minutes to derived progress. They never complete a block, task, or plan
automatically. A proposal starts from a manual deadline or one imported event
the user explicitly selected; calendar availability is a separate per-plan
boolean and is valid only for a connected, non-deleted source with a current
import. Imported content stays read-only, and normal GET, calendar import,
Dashboard, scheduler, and focus completion paths never generate a proposal.
The full contract is in `docs/deadline-planner-v1-contract.md`.

When the optional Study focus rhythm exists, every new Deadline Planner
proposal uses it. Normal blocks have the exact focus duration, only the final
remainder may be shorter, and each block reserves the complete recovery period
without counting it as preparation or progress. The proposal freezes the Study
revision and confirmation rejects changed settings; existing active revisions
are never rewritten.

An optional nullable account-wide preparation budget lives on `profiles` and is
set only through a bearer-derived FastAPI account route plus service-role-only
RPC. Proposal generation deducts active blocks from other plans on every
profile-local date while retaining each revision's own daily cap. Budget writes
and plan mutations share the owner advisory lock; a database trigger rechecks
aggregate candidate-date minutes during proposed-to-active confirmation. A
changed budget can therefore reject confirmation without mutating the staged or
active revision. Existing active blocks are never silently moved when the
setting changes.

The side-effect-free `preparation-workload-v1` read projects seven consecutive
profile-local dates for Today and Planner. It reports active confirmed
preparation reservations and merged weekly `schedule_items` duration as separate
facts. It deliberately excludes proposed blocks, imported busy rows, live
provider state, task estimates, and Focus history, so the UI labels the latter
as weekly Setup commitments and does not present the projection as total free
time. Both this projection and block allocation remain deterministic/no-LLM.

`GET /v1/deadline-plans/exam-week-outlook` adds a separate read-only
`exam-week-outlook-v1` projection. An active exam with remaining work activates
`exam_week` at 0..7 local days, `watch` at 8..14, or `overdue`; assignments
within the horizon consume capacity but never activate it. The service reuses
the same Availability engine without storing simulated blocks, includes every
confirmed competing reservation in range, and compares normal capacity with a
hypothetical recurring busy interval from the newest valid Evening V4 plan.
The Planner-only card opens existing review/replan routes and cannot create or
confirm a preview. See `docs/exam-week-outlook-v1-contract.md`.

The compatible `preparation-workload-detail-v1` read is requested only after a
student expands one date from that summary. It accepts only a date in the
current profile-local seven-day window and aggregates active blocks by their
owner-scoped plan id. The response exposes only plan title, date-reserved
minutes, and block count, with exact sum/budget invariants; it does not return
block times or calendar content. Today and Planner use the same detail
boundary. Review navigation opens the existing plan, while replanning pushes
`/planner/replan?plan_id=<uuid>` and isolates that selected plan's existing
preview/confirmation workflow. Neither GET route has mutation or LLM authority.

## Authentication

The current auth modes are:

- Local guest session through `shared_preferences`.
- Supabase email/password auth.
- Supabase Google OAuth.

Guest sessions can complete onboarding locally. If a user later authenticates
with a real, non-demo Supabase account while `USE_MOCK_DATA=false`, canonical
guest check-ins are migrated best-effort into Supabase by the auth repository.
Guest Setup is intentionally not migrated: it remains local, while the real
account loads or creates its own authenticated backend Setup. Mock mode and
authenticated demo identities instead retain the local Setup across reload and
perform no remote profile/data bootstrap.

## First-Run And Setup Contract

Setup is one typed contract across first completion, re-entry, and review:

- Typical weekday and best energy window are the only required answers; display
  name is optional. Routines, fixed commitments, and Study Setup are progressive
  optional detail. Focus areas, Goals, friction points, coaching style, Reminder
  preference, and free-form context are retired. A compatibility normalizer
  accepts old `intake-v1` payloads but strips those keys before validation,
  comparison, and persistence. Weekly commitments may use optional inclusive
  semester dates and can be duplicated for another weekday. The legacy
  calendar-intent field remains a payload-compatibility value but is no longer
  presented in onboarding.
- Focus rhythm/start ritual and current/next semester planning are separate
  collapsed optional sections. Enabling Focus initializes 45 minutes plus 10
  minutes recovery and neutral preparation suggestions. New commitments may
  copy the current semester dates for review; existing commitments are never
  changed by later semester edits.
- Guest/demo sessions read and write the typed setup locally. Authenticated
  real-mode sessions read `GET /v1/intake/setup` and save through
  `POST /v1/intake/complete`; there is no direct Supabase fallback that can mark
  an incomplete backend intake as finished.
- New synced profiles retain the neutral database default `UTC`, but the first
  successful Setup save requires an explicit `Keep UTC` or `Review in Settings`
  choice. Editing an existing Setup and guest Setup do not add that prompt.
- The Setup read returns the newest `intake-v1` row. A newest `pending` row is
  exposed with its request id so the client can freeze edits and retry that exact
  operation; otherwise the read returns the latest applied revision.
- A stable `request_id` makes a retry the same operation. `base_revision`
  provides optimistic edit concurrency, while persisted intake revisions move
  from `pending` to `applied`.
- `profiles.setup_revision` is a monotonic projection guard. Profile completion
  and optional display-name projection update only for a newer applied revision,
  so stale workers cannot overwrite a newer Setup projection.
- After the pending revision is claimed, FastAPI calls one service-role-only
  database RPC. A transaction-scoped per-user advisory lock serializes workers;
  Setup-owned Habit/schedule/study/energy-memory reconciliation, the canonical
  onboarding snapshot, applied intake state, and profile projection either
  commit together or roll back together. The compatibility RPC parameters for
  Goals and notification preferences are ignored; Setup never changes or
  touches the user's Reminder settings.
- Activated habits, schedule items, and the best-energy memory receive
  deterministic UUIDv5 record ids plus server-authored setup ownership metadata.
  Reconciliation converges to the submitted applied revision, archives only
  Setup-owned Goals, and never archives or removes manual/other-source Goals or
  memories. The only legacy schedule exception deletes the exact unmarked
  onboarding placeholder `Math`, `Room 204`, Monday `08:15`-`09:45`; other
  manual and unmarked onboarding rows remain preserved.
- A named routine stays only in the intake response as a candidate. It becomes
  an active `habits` row only after explicit daily/weekly cadence confirmation.
- Settings links to the real Setup surface. Re-entry is prefilled and exposes
  loading, retryable error, edit, habit pause/archive, and fixed commitment
  removal behavior.
- Setup-owned habits are edited, paused, or archived only through this Settings
  Setup surface. Active Setup habits remain visible for completion, intentional
  skip, and undo in Today Habits; generic Habit Management lists only
  non-Setup-managed habits.
- Client-side and HTTP 4xx rejection keeps the draft editable; 409 additionally
  recommends reloading server state. A timeout, 5xx, transport failure, or
  invalid success envelope leaves persistence uncertain, so the submitted draft
  is locked for exact unchanged retry or explicit reload.

## Study Setup V1

The optional `responses.study_setup` Intake member is projected only from the
canonical applied Setup revision. `study_setup_profiles` is a forced-RLS,
owner-readable, backend-written projection; omitting Study Setup in a newer
confirmed revision removes it instead of inventing defaults. The same atomic
Intake RPC reconciles this row together with every existing Setup projection.

Focus start reads the projection directly for its default duration, ordered
active preparation items, and recovery duration. Checklist choices are
ephemeral. Recovery minutes are copied into the existing Focus metadata and a
completed session may start one skippable device-local countdown; there is no
recovery history table.

Planner derives profile-local open/overdue course-selection attention from the
next-semester window. That fact links to Settings Setup and does not create a
Task, Today item, Calendar row, or Notification. Exact shapes, planning
staleness, export/deletion authority, and non-claims live in
`docs/study-setup-v1-contract.md`.

## Supabase

Supabase owns the planned production auth, PostgreSQL persistence, and RLS
surface. The canonical application schema is now snake_case and centered on:

- `profiles` for public user profile, role, provider, timezone, onboarding
  state, and the monotonic Setup projection revision.
- `daily_logs` for one daily summary row per user/date.
- `behavioral_events` for granular AI signal history.
- `tasks`, `schedule_items`, `notifications`, and `coach_messages` for the
  current product workflows.
- `memory_entries`, `ai_insights`, `recommendations`, and
  `skillset_profiles` for AI-generated context and output.
- `goals` as a retained compatibility/export table with no active product
  evaluation; `habits`, `habit_logs`, and `focus_sessions` for executable
  habit-outcome and focus workflows.
- `intake_responses` and `user_state_snapshots` for revisioned typed Setup
  history and compact backend-owned user state.
- `study_setup_profiles` for the optional current applied focus/semester Setup
  projection; authenticated owners read it and only the Intake backend writes.
- `daily_briefings` for one persisted deterministic decision per user/local
  date; authenticated users may read their row, while FastAPI owns writes.
- `decision_feedback` for retry-safe owner-scoped outcome/preference events;
  users may read/delete history while FastAPI validates and inserts it.
- `weekly_reviews` for one backend-owned deterministic completed-ISO-week
  review per user/period; authenticated owners may read but only FastAPI writes.
- `calendar_connections`, `calendar_imports`, and `calendar_events` for one
  explicitly consented `.ics` source, immutable retry identities, and the
  current whitelisted read-only local event copy. A backend-only
  `calendar_request_identities` registry prevents request reinterpretation
  across owners and operations without retaining content fingerprints. These
  tables remain separate from app-authored `schedule_items`.
- `coach_requests` for message-free pending claims, retry/lease state, bounded
  validated response/provenance, and deletion tombstones;
  `coach_usage_events` for retained append-only per-request outcomes/counters;
  and `coach_memory_selections` for explicit owner-scoped Coach use without
  rewriting `memory_entries`. Completed turns use exactly one bounded user and
  assistant `coach_messages` pair linked to the request.
- `deadline_plans`, `deadline_plan_revisions`, and `deadline_plan_blocks` for
  owner-scoped lifecycle, immutable proposal/activation history, and dated app-
  owned reservations; `deadline_plan_request_identities` is the backend-only
  global anti-replay ledger. These rows never become provider-calendar writes
  or recurring `schedule_items`.
- `planner_preferences`, `planner_action_plans`,
  `planner_action_plan_revisions`, `planner_task_blocks`,
  `planner_habit_slots`, and `planner_commitments` for the central staged
  planning surface; `planner_request_identities` is its backend-only replay
  ledger.

Legacy CamelCase tables such as `"User"`, `"DailyLog"`, and `"Task"` may still
exist in older remote projects. The canonical migration copies data from those
tables when present, but new Flutter code should target the snake_case tables.

See `docs/supabase-current-state.md` for the exact current schema caveat.

## FastAPI AI Service

The AI service lives in `services/ai_service`.

Current responsibilities:

- Serve `/v1/health`.
- Serve authenticated Setup read at `GET /v1/intake/setup` and Intake V1
  completion/edit at `POST /v1/intake/complete`.
- Serve authenticated recommendation contract endpoints at
  `/v1/recommendations` and `/v1/recommendations/generate`.
- Serve authenticated deterministic snapshot refresh at
  `/v1/snapshots/generate`.
- Serve scheduler-triggered deterministic daily preparation at
  `/v1/scheduled/daily-refresh` with a backend-only scheduled refresh token.
- Serve authenticated retry-safe stored-Inbox lifecycle at
  `POST /v1/notifications/{notification_id}/actions`; owner-scoped
  read/unread/dismiss mutations use one service-role-only RPC and never imply
  notification generation or delivery.
- Serve bearer-derived notification settings and foreground acknowledgement.
  The protected daily refresh may request deterministic generation; its
  database boundary revalidates explicit consent, timezone/local date, quiet
  hours, category, daily cap, and dedupe under the owner lock.
- Serve read-only latest/explicit weekly-review GETs plus deliberate
  `POST /v1/weekly-reviews/generate` under `weekly-review-v1`.
- Serve authenticated calendar connection/read endpoints plus deliberate file
  import, disconnect, and imported-data deletion under `calendar-import-v2`.
  The service parses bounded caller-selected UTF-8 `.ics` text; it does not
  fetch arbitrary URLs, hold provider credentials, or write to a calendar.
  Only `planning_status=current` is eligible read-only Planner busy time.
- Serve read-only deadline-plan GETs plus deliberate proposal, confirm,
  complete, and cancel commands under `deadline-plan-v1`. The service uses the
  stored profile timezone and deterministic availability inputs, holds the
  active revision until explicit confirm, creates the managed task only during
  first confirm, enforces the 366-day horizon and current-import availability,
  owns every later managed-task/terminal projection, and never calls an LLM or
  notification/provider API.
- Serve authenticated `coach-capabilities-v2`, message-only
  `coach-request-v3`, `coach-response-v2`, `coach-history-v2`, and the
  `started|activity|completed|failed` streaming route. The non-streaming respond
  route remains a V3 wrapper and accepts old V1/V2 requests for compatibility.
- Claim one retry-safe free question, create a fresh owner-only SQLite snapshot,
  run deterministic safety and a required three-tool read-only MCP agent, and
  atomically persist the answer with backend-derived evidence, bounded trace,
  service-tier truth, and retained usage. Fixed-mode V1/V2 history remains
  readable; failed/deleted requests remain terminal, and history deletion does
  not free budget.
- Keep recommendation generation behind a service boundary.
- Verify bearer tokens through an isolated auth verifier when Supabase backend
  settings are configured.
- Claim revisioned structured intake responses, then call the service-role-only
  `apply_intake_v1_setup_revision` RPC. Its per-user advisory transaction lock
  atomically reconciles cadence-confirmed habits, schedule items, Study Setup,
  and the best-energy memory; archives Setup-owned Goals; upserts the compact
  `setup:intake-v1` onboarding snapshot; marks the intake applied; and advances
  the profile projection only from its canonical stored response. It does not
  change notification preferences.
- Load recent user-scoped data from `daily_logs`, `behavioral_events`, and
  `tasks` plus latest `user_state_snapshots`, run the deterministic v1
  recommendation engine, and persist verified recommendations to
  `recommendations`.
- Create or refresh compact `daily` and `weekly` `user_state_snapshots` from
  recent `daily_logs`, `behavioral_events`, `tasks`, `habits`, explicit
  `habit_logs`, `focus_sessions`, `schedule_items`, and `memory_entries` without
  reading full history.
- Parse the same strict `executable-action-v1` envelope as Flutter so persisted
  briefings cannot return unknown commands, mismatched target kinds, nested
  metadata, or unsafe routes. `GET /v1/briefings/today` reads that decision and
  deliberate `POST /v1/briefings/generate` ranks or refreshes it.
- Add `summary.daily_state` and `signals.daily_state` under the
  `explainable-daily-state-v2` contract. The parser trusts V2/V3/V4 capture
  metadata only after strict identity, branch-compatibility, type, enum, numeric,
  timestamp, sleep-interval, and projection checks, ignores all friction keys,
  and sanitizes readable V1 state. Legacy numeric fallback applies only when no
  structured capture marker exists.
- Compute Daily State from a fixed seven-day lookback independent of the
  requested statistics window. Evening on the target date or previous date is
  current; Morning is current only on the target date. Quality is explicit as
  `missing`, `partial`, `current`, or `stale`.
- Classify `push`, `steady`, `recover`, or `plan` with recovery safeguards before
  planning or push rules. `push` requires an active Task. Persist machine-stable
  non-friction risks/reasons, field-level evidence, deterministic provenance,
  and no learned-baseline claim. Very low
  current sleep quality may select recovery despite sufficient duration;
  moderately low quality prevents `push`. Capture free text is excluded from
  summary, signals, and snapshot metadata.
- Load capture metadata with daily rows and events. Event queries use a broadened
  UTC read window, then prefer the explicit local `metadata.entry_date` during
  in-memory filtering and fall back to `occurred_at` for legacy events.
- Do not generate Recommendations during Setup completion. Runtime
  Recommendations remain deliberate and use current Tasks, check-ins, and other
  live state rather than retired onboarding personalization.
- Support a deliberate dashboard recommendation refresh action that first
  refreshes the daily snapshot best-effort, then calls the deterministic
  recommendation generate endpoint with LLM wording disabled.
- Support a bounded scheduler-triggered preparation pass that finds onboarded
  non-guest profiles, pins one local date per profile from one UTC run instant,
  and prepares deterministic daily snapshots plus persisted briefings. Current
  pairs are write-free; missing prerequisites and stale briefings converge on
  their existing daily identities. Recommendations remain disabled by default,
  and explicit opt-in still forces LLM wording off.

FastAPI owns one pooled `httpx.AsyncClient` for Supabase Auth and REST during
its application lifespan. One typed `ApplicationComposition` builds the
repository/service graph over that shared `SupabaseRestClient` and reuses the
same Snapshot, Briefing, Weekly Review, Recommendation, Learning, learned-
timing, Deadline, Planner, Today, Scheduled, Notification, Account, and Coach
collaborators where their contracts overlap. Router modules retain explicit
FastAPI endpoints and error mapping; asynchronous dependency functions only
select a typed service from that graph and construct no repository or
transport. Tests override those dependency function objects rather than named
`app.state` service fields. Shutdown closes the pool exactly once. Missing
backend Supabase configuration creates neither a pool nor a graph and retains
the existing fail-closed unauthorized/service-unavailable behavior. Repository
protocols and direct unit-level service/repository injection remain unchanged;
the graph is application-lifespan scoped, not a process-global service
locator.

FastAPI routes depend only on service-level errors and models; repository
exception types do not cross into `app/api`. Daily Capture V4 parsing and
new-write validation share the framework-neutral
`app/contracts/daily_capture_v4.py` boundary, so repositories and deterministic
read builders do not import a service module. Planner and Deadline orchestration
likewise remain in `planner_service.py` and `deadline_plan_service.py`, while
their deterministic projection/availability builders live in
`planner_builder.py` and `deadline_plan_builder.py`. The development-only local
Codex adapter separates process limits/termination (`bounded_process.py`) and
strict event validation (`codex_events.py`) from provider command composition.

Flutter reads persisted recommendations through `GET /v1/recommendations` when
`USE_MOCK_DATA=false`, Supabase is configured, and a real Supabase session
access token is available. The app attaches that token as a bearer token for the
FastAPI request. The typed response preserves provenance, `needs_generation`,
generation time, period key, and current/missing/older/period-mismatch freshness.
Guest/mock sessions receive a visibly labeled local demo feed. Missing real
configuration or auth, network failures, and invalid envelopes propagate as
errors and never read mock recommendations. Flutter does not automatically call
`POST /v1/recommendations/generate` during a normal read.
Authenticated Intake V1 completion writes no Recommendation. Normal dashboard
reads also never generate recommendations. The dashboard refresh command is the
explicit user-visible path:
it calls `POST /v1/recommendations/generate` with `allow_llm_wording=false`
after a best-effort daily snapshot refresh, then reloads persisted
recommendations. A failed refresh retains the previously displayed feed and
shows a recoverable failure; local demo sessions do not call the backend.
Persisted recommendation `action_label` values are rendered as informational
"Suggested next step" text, not as controls. Current Today Overview actions
come from owner-scoped Today data and invoke the existing Task, Habit, Focus,
capture, and Weekly Review flows directly. Persisted `daily-briefing-v1`
targets remain validated backend data but are not rendered as an executable
briefing card.

Snapshot refresh is a deliberate authenticated backend action through
`POST /v1/snapshots/generate`. The request can select `daily` or `weekly`
scope and an optional target date, but the backend always derives `user_id` from
the verified bearer token. If a snapshot already exists for the same
`user_id`, `scope`, and `period_key`, the backend updates it instead of
inserting another row. The existing `snapshot-aggregator-v1` source marker stays
stable; metadata records `daily_state_contract_version` and the fixed state
lookback separately from `window_days`. Top-level `summary.risk_flags` aliases
the current Daily State codes; the older statistics-window flags remain under
`summary.window_risk_flags`. `recommended_next_focus` is derived recovery-first
from Daily Mode rather than letting overdue work override recovery.
Phase 3 adds `summary.habits.outcome_counts`,
`summary.focus_sessions`, matching signal counts/status counts, and bounded
evidence references. These action facts are additive inputs for briefing
selection. The repository paginates habit-log and focus-session windows in stable
1,000-row pages, so server response caps cannot silently truncate counts or
minutes. Tests require `summary.daily_state` and `signals.daily_state` to remain
byte-for-byte equivalent when action rows are added or removed.

Flutter triggers the `daily` snapshot refresh best-effort after successful or
exactly reconciled Supabase-backed Evening/Morning, task, habit, and focus
writes. Capture calls send their explicit local entry date. Habit outcome/undo
captures and refreshes one stable target date. New focus rows persist their
local start `metadata.entry_date`; start/finish/abandon refresh that date. The
migration backfills missing legacy dates from the UTC calendar date of
`started_at`, which Flutter and FastAPI also use for invalid/missing metadata.
FastAPI applies the same rule after widening its focus UTC read window, so a new
session ending after midnight remains on its explicit local start day. The
trigger is guarded by runtime config, Supabase configuration, a real session,
and an access token. Guest/mock/missing-token paths and AI-service failures do
not block or roll back the original write.

Scheduled preparation is backend-only. `POST /v1/scheduled/daily-refresh`
requires `X-Scheduled-Refresh-Token` and captures one aware UTC instant for the
run. The service-role repository lists only onboarded non-guest profiles and
derives each profile's `briefing_date` with its IANA timezone. A request may
optionally supply `target_date` as an explicit backfill override.

Selection compares the exact local-date snapshot with the briefing's source
snapshot id and generation time. A missing snapshot is generated once; an
existing snapshot is reused when only its briefing is missing; a stale briefing
is updated against the exact snapshot; and an already-current pair performs no
write. Unique `(user_id, scope, period_key)` and `(user_id, briefing_date)`
identities make retries converge. A token holder may narrow an operational retry
with at most 20 `profile_ids`; those ids are still intersected with eligible
profiles and never bypass onboarding or guest exclusion. Per-user results expose
the local date, selection reason, snapshot/briefing ids and statuses, and a
sanitized failing stage (`profile_date`, `snapshot`, `briefing`, or
`recommendations`). One user's failure does not stop the rest of the bounded
batch.

Recommendation generation is disabled by default. Explicit
`include_recommendations=true` remains deterministic and forces LLM wording off;
snapshot and briefing preparation never call an LLM. This endpoint is not a
Flutter or browser runtime endpoint, and normal Dashboard load remains GET-only.
The repository contains no deployed cron manifest or production worker. The
local stack runner requests current-day deterministic notification generation
every 15 minutes, and Flutter can acknowledge/show a foreground banner after
separate consent. That local path must not be described as deployed scheduling,
push, browser, Android, or background-mobile delivery.
The target selector still prepares missing/stale Phase 7 state for eligible
profiles, but includes a fully current profile in a notification-only batch only
when the dedicated consent row is active.

Weekly review is authenticated but not scheduled. FastAPI resolves one
completed ISO week from the profile timezone, loads exact durable facts with
stable pagination, computes a canonical SHA-256 source fingerprint, and
persists one `(user_id, period_key)` review only on deliberate generation.
Read-only GET recomputes freshness without changing the row. The existing
generic weekly snapshot is supporting evidence, not a historical ledger:
task undo/restore and habit definition revisions cannot be reconstructed, so
those limitations stay explicit and affected habit opportunities become
unknown. Generation never applies a proposal or mutates a user-owned object.

Flutter Setup sends the structured Intake V1 payload to
`POST /v1/intake/complete` only in real backend mode with a Supabase access
token and loads the newest Setup row through `GET /v1/intake/setup`. A pending
row resumes only with its original request id; otherwise the row is the latest
applied revision. Guest and mock paths keep the same typed setup locally and do
not require the AI service. Rejected 4xx saves remain editable, with reload
recommended for 409. An ambiguous timeout, 5xx, transport error, or invalid
response keeps the exact submitted draft and request id locked for unchanged
retry or explicit reload; no failure falls back to direct profile/timetable
writes or claims completion.

Current limitation: JWT verification is isolated behind the FastAPI auth
dependency and currently calls Supabase Auth's user endpoint with the configured
backend Supabase credentials. The repository still does not contain production
credentials, and the live remote database must be inspected directly before
making claims about deployed data.

### Implemented Phase 10 Free Read-Only Coach Boundary

The exact contract is
`docs/phase-10-controlled-coach-plan.md`. Its real provider is a local
development adapter, not a deployed service:

```text
authenticated free question
  -> retry-safe owner claim and local-day budget
  -> fresh owner-only personal SQLite snapshot
  -> local `codex exec`: gpt-5.5 + explicit Fast
  -> required per-turn stdio MCP
       -> inspect_data
       -> bounded read-only query_data
       -> isolated no-network run_python
  -> schema-validated text
  -> backend-derived evidence/trace/provenance
  -> atomic response/history/usage persistence
```

Flutter sends only its normal Supabase bearer token. OAuth stays inside the
current Linux user's Codex installation and is never copied into Flutter,
Supabase, the snapshot, the MCP server, the Python container, Git, or logs.
Every developer signs in independently. The provider requires exactly
`gpt-5.5`, `service_tier="fast"`, and `fast_mode=true` for every agent turn.
Missing model/Fast support or a different reported model fails closed; there is
no model or standard-tier fallback.

FastAPI exports relevant retained data through the owner-filtered Account
Export paging boundary. The snapshot covers Setup, Daily Capture, Tasks,
Habits/outcomes, Focus/reflections, Planner, Preparation, Calendar, Weekly
Reviews, Insights, Recommendations, Memories, and earlier Coach messages,
including retained detail text. It excludes authentication, email/role/provider
identity, credentials, provider internals, anti-replay/usage/selection ledgers,
operational state, and other owners. It contains an explanatory catalog,
relationships, record counts, periods, and helper views. It fails instead of
truncating beyond 10,000 rows per table, 50,000 rows total, or 8 MiB.

Codex runs in a private empty directory with read-only sandboxing, no approvals,
ignored user configuration/rules, bounded environment/output/time, and one
required MCP server. No user MCP, app, plugin, web, shell, sub-agent, filesystem
mutation, or product-mutation authority reaches the turn. The MCP exposes only:

- catalog/coverage inspection;
- immutable SQLite `SELECT`/`WITH` with authorizer, progress deadline, and
  row/byte caps; and
- Python in a pinned Docker image with no network or secrets, non-root user,
  read-only root and snapshot mount, temporary-space/CPU/RAM/PID/output/time
  limits, and scientific Python libraries.

Python may return an internal plot to the model. Neither plot nor script is
stored or shown. Snapshot, trace, process workspaces, plots, and other temporary
files are deleted after completion, failure, timeout, or cancellation. All free
text and calendar values are untrusted data, never instructions.

The HTTP boundary is message-only `coach-request-v3`,
`coach-response-v2`, `coach-capabilities-v2`, `coach-history-v2`, and a
`started|activity|completed|failed` SSE stream. The current agent pair is
`free-coach-agent-prompt-v2` with `personal-snapshot-v1`; stored V1 prompt
responses and exact replay remain valid. V2 makes English the non-overridable
output language for reply and uncertainty. FastAPI rejects clearly German
provider output as retryable `invalid_output` before persistence. Activity is
allowlisted lifecycle copy rather than hidden reasoning; a real client
disconnect or explicit cancel terminates the turn. Flutter shell navigation
keeps the app-scoped subscription attached and is not a disconnect. The
non-streaming route wraps the same service. Old fixed-mode V1/V2
request and response shapes, context options, and memory-selection endpoints
remain readable/available for compatibility but current Flutter does not call
or display them. Their newest paired provenance remains
`controlled-coach-prompt-v3`/`coach-context-v3`; current V3 uses the free-agent
prompt and personal snapshot instead. Focused API tests and readable stored
V1/V2 history still exercise this boundary, so removal requires an explicit
support-window/data-migration decision rather than inference from current
Flutter call sites.

The model returns only reply, uncertainty, and safety. FastAPI derives
conservative snapshot-source coverage in the `evidence` field, actual
inspection/SQL/Python steps, limitations, model/Fast provenance, and snapshot
size. Inspection alone contributes no row coverage; SQL has separate
returned-row counts; arbitrary successful Python is attributed to the full
snapshot. The current answer has no structured suggestion or visible artifact.
Existing safety checks may bypass or replace the provider, and no response can
execute an app action.

One owner may have one pending turn and, by default, 20 newly started questions
per profile-local day. A turn allows at most 12 tools and 180 seconds; SQL and
Python have shorter limits. Exact request-id/message replay returns the terminal
result without another call. History deletion removes message and V3
evidence/trace detail but retains usage and tombstones, so budget and identity
cannot be reset.

All standard tests use an injected fake provider. The opt-in live smoke is
machine/account/image specific and is the only valid evidence that a current
CLI login accepted `gpt-5.5` Fast and completed a multi-tool question. It is not
CI, FastAPI persistence, Flutter presentation, production readiness, or
evidence about another developer's account. Deterministic API/browser tests
cover persistence and UI behavior separately.

### Revisioned Account Controls

The exact boundary is `docs/v1-account-controls-contract.md`. Real authenticated
accounts use bearer-derived FastAPI routes for revision-checked, retry-safe
IANA timezone and daily preparation-budget changes,
an optional bounded account-wide daily preparation rule, a strict bounded
`account-export-v2` JSON portability export, and permanent deletion.
Password reset and confirmation resend remain Supabase Auth operations with a
dedicated recovery-event route in Flutter. Guest/mock sessions make no account
API calls.

Export reads only owner-filtered canonical product tables, including the
current Study Setup and Personal Learning projections, applies field
allowlists to backend-owned Calendar/Coach ledgers, names the anti-replay ledger
it omits, includes Deadline Planner plan/revision/block rows while omitting its
request ledger, and fails rather than truncating at a V1 bound. The exact
41-table set includes `learning_preferences`, `focus_session_reflections`, and
`focus_session_schedule_sources`, while the learning request ledger is
explicitly omitted. FastAPI's typed owner-data catalog is the single code owner for all 48
repo-owned public tables: each entry separately declares Account Export and
Coach Snapshot participation, the bounded read shape when applicable, and the
human-readable snapshot description. A focused migration-history completeness
test fails when a newly created repo table has no deliberate policy. Flutter
validates the
entire envelope and counts before saving. Full deletion requires exact typed
confirmation and one service-role-only database RPC. The RPC locks the existing
owner workflows, removes restrict-linked focus history, deletes the Auth user,
and verifies the profile/product cascade in one transaction. The client then
clears its local session even if the deleted remote session can no longer be
signed out normally.

## Personal Learning V1

The exact boundary is `docs/personal-learning-v1-contract.md`. A terminal
Focus transition commits first; an optional shared Flutter sheet then creates
or edits one owner-scoped reflection without changing the immutable session.
Completed-session recovery starts before the sheet and continues behind it.
Focus history and the last Evening page expose the same reflection record;
guest/demo paths stay zero-call.

FastAPI owns revisioned learning settings and the side-effect-free
`GET /v1/insights/personal-patterns` aggregator. When analysis is disabled, it
returns before loading Focus or Capture evidence. Otherwise it parses a fixed
rolling 90-day window exclusively in the profile timezone, joins each rated
terminal session to only a preceding valid V4 sleep episode, collapses repeated
sleep-episode use, and emits fixed-window observational comparisons with sample,
coverage, maturity, limits, and deterministic fingerprint. Daily State,
Exam-Week Outlook, and Personal Patterns share one strict Daily Capture V4
sleep parser. Authenticated V4 writes use that same contract module for complete
branch validation, including exact rating ranges, stress label/context,
minute-aligned sleep intervals, day shape, and bounded optional fields before
repository I/O.

Real-account Insights replaces the generic observation with this backend
contract. Advanced correlation uses the response's profile-local points and no
longer reconstructs planned-work or Habit history from current rows. Local demo
keeps bounded labelled mock exploration. Neither surface grants Planner
authority.

The optional Planner bridge has two gates: the complete account preference and
`LEARNED_FOCUS_PLANNING_PILOT_ENABLED` in both FastAPI and Flutter. When current
evidence is Planner-ready, shared availability tries the learned daytime window
before Setup energy ordering while retaining every ordinary fallback. Busy
time, current time, deadline, budget, Recovery, Calendar, Study rhythm, and
reservation constraints remain authoritative. Only deliberate new or replan
previews for Tasks, Exams, and Assignments carry the immutable evidence
provenance; that provenance also records when actual allocation had to use a
Setup window. Habits, commitments, active revisions, and confirmed blocks are
never changed.

Recommendation generation now loads profile-local structured terminal Focus
and valid V4 sleep evidence. Focus pressure requires at least three terminal
sessions and two abandonments in 14 days; intentionally short completed
sessions are not treated as failure. Movement rules require actual measurements
and state fixed thresholds. The service-role replacement RPC atomically retires
the previous `new` feed and inserts the verified current set, preserving
accepted and historical rows even when the new set is empty.

## Security Posture

- Supabase RLS is enabled and forced where migrations touch tables.
- User-owned tables scope access by `auth.uid()` or admin role helpers.
- Supabase service-role secrets are not used by the mobile app.
- The atomic Setup apply RPC revokes execute from `public`, `anon`, and
  `authenticated`; only the FastAPI service-role client can invoke it.
- Canonical profile identity and eligibility are backend-owned. Application
  roles cannot insert/delete profiles, change `role` or `auth_provider`, or
  write `onboarding_completed_at`; authorization reads only `profiles` and
  never falls back to a mutable legacy `"User"` row. The service-role Intake
  apply path retains the authority needed to project onboarding state.
- Flutter treats an authenticated identity without that canonical profile as an
  explicit invariant failure. It performs one owner-scoped profile read, makes
  no client repair write, and offers sign-out before another sign-in attempt.
- Phase 3 preserves existing table RLS/grants. A locked habit trigger rejects
  cross-user, inactive, paused/archived/candidate, and unscheduled selected-
  weekday outcomes. Focus triggers reject invalid links and every update to a
  terminal row; direct helper execution is revoked from app roles. Restricted
  target FKs preserve history, and a partial unique index permits at most one
  active focus session per user.
- Personal Learning uses a composite session/owner foreign key, a locked
  terminal-session trigger, forced owner RLS, and service-role-only revisioned
  settings/clear commands. The retry ledger is not readable by application
  roles, and raw reflection values are excluded from logs.
- `weekly_reviews` uses forced RLS, authenticated owner/admin SELECT only, and
  service-role writes. FastAPI scopes every privileged source query by the
  bearer-derived owner. Confirmed manual habit changes reuse authenticated
  Habit V1 ownership and optimistic timestamp checks.
- Calendar integration tables use forced RLS and backend-owned writes.
  FastAPI derives the owner before connect/import/disconnect/delete, and the
  schema prevents privileged cross-owner child rows.
- Deadline Planner tables use forced RLS and backend-owned mutations. Public
  routes derive the owner from the bearer principal; owner-locked RPCs bind
  global request identity, payload fingerprint, plan revision, blocks, and the
  first managed task atomically. Authenticated direct writes and request-ledger
  reads are forbidden. The optional profile preparation-budget column is also
  authenticated read-only; its service-role-only setter and proposed-to-active
  block trigger use the same owner lock to prevent concurrent aggregate-cap
  bypass.
- `notifications` remains authenticated read-only through the Data API.
  Lifecycle DML is available only through bearer-derived FastAPI and the
  owner-locked service-role `apply_notification_action_v1` RPC; its retry
  ledger is forced-RLS and unavailable to application roles.
- `notification_preferences` delivery fields are authenticated read-only and
  default fail-closed. Settings, deterministic generated-row creation, and
  foreground receipts use three owner-locked service-role-only RPCs. Flutter
  presents a banner only after the receipt RPC revalidates current consent,
  category, due time, timezone, and quiet hours. Settings replay fingerprints
  the expected revision and complete payload; the shared Setup writer
  invalidates that identity and cannot regress the preference revision.
- `20260714103000_application_table_privilege_guard.sql` closes table-level
  authority that RLS does not cover across every repo-owned product and ledger
  table. `anon` is fail-closed; authenticated `TRUNCATE`, `REFERENCES`, and
  `TRIGGER` are removed while intended table-specific DML is preserved; and
  backend projections remain authenticated read-only. Optional legacy tables
  are frozen and future `postgres`-created public tables inherit the same safe
  defaults. The installed Auth triggers remain active, but application and
  service roles cannot reuse their security-definer functions on another
  table. Notification child lookup and non-validating timestamp-order checks
  complete the guard without treating unverified legacy rows as clean.
- `20260714110000_account_export_lifestyle_entries_grant.sql` adds the missing
  `service_role`-only `SELECT` grant for the legacy-but-canonical
  `lifestyle_entries` table. Account Export V1 reads it even when it is empty;
  authenticated and anonymous application permissions remain unchanged.
- Mobile config uses Dart defines so credentials are not hard-coded in source.
- Production AI endpoints validate Supabase bearer tokens before reading user
  data or invoking privileged backend workflows when backend Supabase settings
  are configured.
- Phase 10 local Codex auth remains per-Linux-user CLI state. It must
  never be copied into Flutter, Supabase, `.env`, Git, logs, fixtures, or a
  subprocess environment alongside backend service credentials.
- Phase 10 Coach tables use forced RLS. Authenticated users may read only their
  own validated message, memory, and selection projections; request, usage,
  response, selection, and deletion mutations are service-role-only RPC work.
  Pending claims contain only a message fingerprint, not the message itself.
- V1 account profile/export/delete routes derive identity only from the verified
  bearer principal. The full-delete RPC is executable only by `service_role`,
  requires exact confirmation, and verifies the profile cascade before success.

## Known Gaps

- Coach is now a typed FastAPI surface for authenticated real accounts, with
  `/more` as a compatibility alias. Its backend capability may still report
  disabled or unavailable; production hides the surface unless explicitly
  enabled, and guest/mock makes zero Coach HTTP calls. Deep
  Work is available only to authenticated real accounts with synced execution
  capability. Settings exposes durable timezone, export and confirmed deletion
  for synced accounts, device-persisted theme, the durable Setup entry, optional
  Calendar Import and gated Coach entries, and sign-out.
- Inbox is a strict stored-item view. Original `type`, `priority`, read state,
  and supported `action_url` are shown; authenticated real accounts use the
  FastAPI `notification-lifecycle-v1` boundary to mark rows read/unread or keep
  a dismiss tombstone. Guest/mock stays local and zero-call. Explicit in-app
  consent now permits only fixed deterministic current briefing/recovery and
  exact completed-week items. The local runner creates bounded stored rows and
  an open authenticated Flutter app may acknowledge/show one at-most-once
  foreground banner. Recovery mode suppresses focus even when the recovery
  category is off, and weekly copy reuses the full Phase 8 source-fingerprint
  freshness check. Pending polling filters currently disabled categories before
  its bounded query. Existing reminder preferences alone grant no delivery;
  push/system delivery and deployed scheduling remain absent.
- Phase 4 persists one deterministic daily briefing per user/local date and
  ranks only strict Phase 3 targets. `GET /v1/briefings/today` is read-only and
  reports missing/current/stale state; deliberate
  `POST /v1/briefings/generate` refreshes the daily snapshot when generation is
  needed and upserts the same daily identity. Phase 5 consumes this strict
  contract in Flutter: a normal
  Dashboard read never posts, stale actions are disabled until deliberate
  `force=true` adjustment, and current primary/support actions reuse Phase 3
  handlers. Phase 6 adds `/v1/feedback` GET/POST/DELETE, exact owned-action
  validation, and a deterministic 28-day `feedback-ranking-v1` contribution.
  Original action reasons remain immutable; bounded contribution and reason
  codes are additive briefing provenance. Insights starts with one cautious
  observation and keeps full correlation analytics as advanced exploration.
- Phase 8 persists a deterministic weekly review only after explicit
  generation. `review_plan` is a real synced navigation handler, not an enabled
  no-op. Direct apply remains limited to manual Habit V1 shrink/pause/archive.
  Setup ownership stays in Setup, while replacement/task/schedule changes
  remain staged. Goals are inactive and the retained V1 goal-linked fact is
  always zero. There is no task-transition or habit-definition history claim.
- Phase 9 accepts one explicitly consented, user-selected `.ics` source for a
  real account. Connection alone imports nothing; a bounded deliberate import
  reconciles stable event identities and exposes imported/read-only provenance.
  Disconnect retains the local copy, and confirmed deletion removes only local
  imported data. There is no provider OAuth, URL fetch, recurrence engine,
  provider write, background sync, or hidden calendar-driven ranking change.
  Deadline Planner may use only one explicitly selected event as a source and,
  when the user enables it for that plan, current imported busy intervals as
  deterministic capacity input. It performs no event-title inference or source
  write and adds no notification delivery.
- The remote Production project may still contain legacy CamelCase tables until
  the canonical schema migration has been applied and verified.
- The repository does not contain real Supabase credentials.
- The only real-model adapter is `local_codex_oauth`, and it is disabled by
  default, development-only, and same-Linux-user. Its one required per-turn MCP
  is limited to personal snapshot inspection, immutable SQL, and isolated
  Python; it has no general shell/web/app/plugin/sub-agent or mutation tools.
  This is not evidence of a production provider, subscription entitlement,
  universal model/Fast availability, or server deployment. No API-key, model,
  tier, or provider fallback exists.
- Daily and weekly snapshot aggregation exists behind an authenticated backend
  endpoint, and daily capture plus task/habit/focus writes trigger daily refresh
  best-effort. The protected scheduled endpoint can prepare profile-local daily
  snapshots and briefings, but there is no deployed cron configuration or
  production background worker in this repository.
- Focused Flutter/FastAPI tests cover Phase 3 contracts, parser parity, DST-safe
  calendar math, and focus local-day filtering. The browser smoke contains exact
  task/habit/focus rows; response-loss paths for habit/task create, habit
  outcome/undo, task completion/undo, and focus start/finish; and negative
  database lifecycle/range/cadence assertions including terminal-focus
  `updated_at`. The journey also covers Phase 8 weekly-review and Phase 9
  bounded calendar-import ownership and recovery boundaries. The combined Phase
  3 through Phase 9 journey passed non-destructively in the 2026-07-13 Phase 9
  implementation checkout. Later changes must establish their own
  current-checkout pass before claiming E2E.
- Explicit local demo mode remains the no-credentials exploration path and is
  labeled throughout the shell.
- The repository records one successful opt-in synthetic local Codex smoke for
  this machine and `gpt-5.5`, one successful authenticated Flutter-to-live-
  Codex product turn, plus focused and full current-checkout local browser
  passes with the deterministic fake provider. Standard automation remains
  fake-provider-only, and these checks do not establish remote state, another
  developer's account, or production readiness.
