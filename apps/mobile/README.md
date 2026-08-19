# MyLifeGraph Mobile App

Flutter client for the AI Personal Coach / MyLifeGraph product.

Coach BYOK V3 is the current public surface. `coach-capabilities-v3`,
`coach-response-v3`, and `coach-history-v3` use
`free-coach-agent-prompt-v5`; stored V1/V2 responses remain readable. OpenAI
and Gemini keys are profile-scoped: Android uses encrypted device storage,
while web keeps keys only in tab memory. Capabilities tests a replacement
before it becomes active. Staging and production expose Coach only with exact
`COACH_SURFACE_ENABLED=true` and send keys only to a configured HTTPS AI URL.

The public-signup VPS pilot, explicit shared operator-provider proposal,
tagged-release flow, and signed-device acceptance are owned by
`../../docs/vps-pilot-release-plan.md`; most remain future work. The current
Flutter repository now accepts current Supabase publishable keys, binds hosted
builds to distinct exact staging/pilot project refs, rejects a pilot build
using a legacy key or staging URL, displays persistent `Staging · Test data`
identity in staging, and implements the versioned adult-participation flow.
Hosted auth shows the privacy notice and explicit 18-or-older checkbox before
account creation/Google OAuth; a short-lived choice may be committed only by
the authenticated backend, and an unaccepted synced account is routed to the
post-auth gate before Setup or product access. Guest mode is unavailable in
hosted builds. No separate remote real-data project or remote acceptance state
is implied by this source.

Feature code keeps its data and presentation internals private. Riverpod
factories or widgets that deliberately wire multiple features live under
`lib/composition`; feature application/domain contracts remain directly
importable. A source test rejects new cross-feature `data`/`presentation`
imports except for one documented embedded Focus-reflection UI seam, so
boundaries cannot drift silently. Shell destinations share one immutable
descriptor for labels, icons, active paths, and Coach visibility while
GoRouter routes remain explicit. This is direct Riverpod composition, not a DI
framework or barrel API.

## Recommended Local Run

From the repository root:

```bash
scripts/start_frontend.sh
```

This starts Flutter Web on:

```text
http://127.0.0.1:7357
```

Default behavior:

- `USE_MOCK_DATA=true`
- `APP_ENV=development`
- `AI_SERVICE_BASE_URL=http://localhost:8000`
- No Supabase credentials required
- Sign in through **Continue as guest**

## Direct Flutter Run

From this directory:

```bash
flutter pub get
flutter run -d web-server \
  --web-hostname 127.0.0.1 \
  --web-port 7357 \
  --dart-define=APP_ENV=development \
  --dart-define=USE_MOCK_DATA=true \
  --dart-define=AI_SERVICE_BASE_URL=http://localhost:8000
```

If you prefer Chrome:

```bash
flutter run -d chrome --web-port=7357 --dart-define=USE_MOCK_DATA=true
```

## Static Web Build

From the repository root:

```bash
MODE=static scripts/start_frontend.sh
```

Or manually:

```bash
flutter build web --debug --no-wasm-dry-run --dart-define=USE_MOCK_DATA=true
python3 -m http.server 7357 --bind 127.0.0.1 --directory build/web
```

## Runtime Defines

The app reads configuration from Dart defines in
`lib/core/config/app_config.dart`.

| Define | Default | Purpose |
| --- | --- | --- |
| `APP_ENV` | `development` | `development` is local; hosted builds accept exact `staging` or `pilot`. |
| `USE_MOCK_DATA` | `false` in code, `true` in scripts | Enables mock repository paths. |
| `SUPABASE_URL` | empty | Enables Supabase when paired with one compatible client key. |
| `SUPABASE_PUBLISHABLE_KEY` | empty | Current public `sb_publishable_` key for the Supabase client; required by pilot builds. |
| `SUPABASE_ANON_KEY` | empty | Legacy anon-JWT compatibility for local Supabase and bounded staging migration. |
| `STAGING_SUPABASE_PROJECT_REF` | empty | Exact non-secret staging ref; required by hosted staging and pilot builds. |
| `PILOT_SUPABASE_PROJECT_REF` | empty | Exact non-secret pilot ref; required by pilot builds and distinct from staging. |
| `PILOT_CONTACT_EMAIL` | empty | Required hosted project/incident contact rendered in the adult/privacy notice. |
| `AI_SERVICE_BASE_URL` | `http://localhost:8000` | FastAPI service base URL. |
| `COACH_SURFACE_ENABLED` | unset/fail-closed in release and production | Exact `true` explicitly exposes Coach; backend capability still controls sending. |
| `LEARNED_FOCUS_PLANNING_PILOT_ENABLED` | `false` | Exact `true` enables the development-only learned-timing Planner pilot; the backend must use the same flag. Production builds stay fail-closed. |

Supabase is initialized only when `SUPABASE_URL` and one compatible client key
are non-empty. A current key wins while a legacy key may remain configured
during rotation. Hosted URLs must be credential-free HTTPS roots matching the
exact environment ref; pilot requires the current key and both distinct refs.

`USE_MOCK_DATA=true` forces product data surfaces to local/demo sources even
when an authenticated Supabase session exists. Use `false` for real Setup,
Evening/Morning capture, Today, Planner, Insights, Inbox,
synced tasks/habits/focus sessions, Controlled Coach, and snapshot refresh
behavior. Mock/demo
auth boot skips remote profile access and overlays the locally applied Setup
name/completion state, so local Setup survives a browser reload.

For authenticated real accounts, Evening and Morning save through the strict
`daily-capture-write-v1` FastAPI boundary. Each branch carries a stable request
id and the last loaded branch identity, so Morning and Evening merge while a
same-branch stale write conflicts. A failed current-day read blocks Save and
keeps the draft; Morning also requires retry or explicit continuation when the
prior Evening plan is unavailable. Successful writes refresh the backend Daily
State best-effort. Morning keeps one local draft across a 50-percent Sleep page
and a 100-percent Check-in page; valid sleep details gate `Next`, `Back` retains
both pages, and only the final control calls the existing save boundary. A save
failure stays on the second page with the complete draft. Today reads the
strict read-only `today-overview-v2` projection: both-capture streak, dynamic
progress, the Setup/Preparation/Calendar/Focus plus Planner
Task/Habit/fixed-commitment agenda, Tasks, and Habits. The V1 route remains
available for older clients.
The latest saved check-in is loaded separately into the compact
`Beat yesterday` streak inset. `Review your week` is a direct
capability-gated navigation entry. The current profile-local
Monday-through-Sunday week is an independent, initially closed supporting
accordion and loads only while that accordion is open. The retired generic
Recommendation and Decision Feedback surfaces have no compatibility UI.
`Full week` uses the strict bearer-authenticated
`today-week-agenda-v1` FastAPI projection. Its exact seven days and wall-clock
labels come from the profile timezone on the server, and its Setup,
Preparation, Calendar, actual Focus, Planner Task, Habit-slot, and
fixed-commitment sources each retain independent `current|unavailable` truth.
Preparation includes canonical current-revision credited and remaining minutes;
only remaining work can start. Task and Habit actions remain lifecycle/date
bound, including a fresh profile-date check before Habit navigation.
Guest/mock builds a local empty week before authenticated transport and makes
zero product calls. Preparation workload remains in Planner and is no longer
repeated on Today. The persisted
deterministic briefing still exists for backend consumers,
but it is no longer presented as a decision made for the user. Capture itself
does not create or change a plan. Morning Calibration
therefore describes only what that save does.

Today keeps its source/update line and ordinary heading explanations initially
hidden behind independent circled information buttons. The shared core
disclosure is used for streak, progress, agenda, Today/all Tasks, Habits, and
the Full-week accordion. The direct `Review your week` entry instead keeps
its summary visible and has no information toggle. Opening information never
opens the surrounding accordion or starts its lazy provider; errors,
loading/results, actions, counts, and empty states remain immediately visible.
The local state resets with a new Today route. Every information button uses a
real 44×44 hit/focus/semantics target around a visible 24×24 frame and unchanged
20×20 icon, with dynamic Show/Hide labels, and changes immediately under
Reduced Motion. Accordion expansion is a separate sibling button, so neither
control triggers the other.

Daily Capture adapts that same core behavior for its five sleep explanations
with standard 44×44 controls. Calendar import, Reminder settings, Personal
learning, Weekly review, and Preparation plans use the standard form only for
optional methodology or limits. Consent, replacement/destructive consequences,
source and stale state, failures, retained drafts, and continuation actions
remain visible. All instances are independent, closed initially, keyboard
operable, and Reduced-Motion aware.

Under `daily-capture-v5`, Evening
requires one planned local sleep time and a `300..720` minute target on a
15-minute grid. Its intent and first-value explanations start closed behind
independent information controls. Morning first records editable aware
estimated sleep-start/wake instants, derives and labels the `Estimated sleep
duration`, and retains the target used for that night. Its second page requires
a separate `1..10` estimated sleep-quality rating plus current energy. The
duration, target-source, and quality explanations start closed independently;
their 20-pixel information icons use normal 44×44 action targets, dynamic
`Show/Hide information about <heading>` semantics, and Reduced-Motion-aware
inline disclosure. It does not ask for Day Shape, and V5 rejects a
`day_shape` field. Evening pressure-source descriptions are available from a separate
accessible info control; the control never changes the selected source.
`Possible priority tomorrow` is no longer an editable Capture input and new
saves omit it, while a value already present on a legacy branch survives an
otherwise valid edit. V2/V3 branches remain readable and may stay explicit
compatibility branches until edited; V4 remains readable and writable during
the rolling upgrade. Editing emits V5, older opposite branches remain explicit
compatibility data, and an existing V5 container is never downgraded. A
best-effort authenticated migration converts complete V4 guest branches to
strict V5 and clears local guest data only after every branch write succeeds;
incomplete older sleep data is never guessed.
Guest/mock Today and capture stay local and make no authenticated request.
Quick actions does not repeat the saved capture details. After a successful
current-day read, each saved Evening or Morning branch marks its existing
action with `Completed today`; that action remains available to edit the saved
answers. Loading or failed reads do not infer a completion state.
After durable writes, feature callers send a typed domain impact to the
app-level projection coordinator instead of importing foreign Riverpod
providers. That composition boundary owns Daily Snapshot refresh and dependent
read-cache invalidation. Today and Planner retain their explicit controlled
reload/stale states, and guest Capture performs local invalidation without a
backend refresh.
Today Task/Habit execution additionally goes through a feature-local command
controller with narrow ports supplied by app composition. The Dashboard page
owns only navigation, Undo presentation, and visible messages;
command dedupe, optimistic overlays, durable-versus-unconfirmed outcomes, and
the reload-only stale state are tested without a widget or Supabase client.
An accepted command that commits after the Today route is disposed still
finishes the captured app-level Snapshot/foreign-projection refresh. It skips
only disposed controller state and its Today-owned reload, so the date-bound
auto-disposed provider is not retained.
Its home layout composes separate typed presentation sections for
streak/progress/agenda, Tasks, Habits, a direct Weekly Review entry, and three
independent supporting accordions. Task
creation/editing remains in Planner; an unreachable duplicate Today editor and
its inert edit/cancel/postpone wiring are not retained.

Planner additionally loads the strictly read-only
`exam-week-outlook-v1` projection for authenticated real accounts. An active
exam may show a 14-day watch, seven-day Exam week, or overdue card before
ordinary attention; assignments consume capacity but do not activate it. The
card can open existing review/replan navigation but never creates a preview,
changes a plan, adds a Today item, or generates a Notification. Guest/demo makes
no outlook request.

The primary Planner read is `planner-overview-v2`; proposal, confirm, cancel,
and commitment responses stay `planner-v1`. Its separate collapsed `Habits`
section reports `N active · X unplanned` across manual and Setup-owned Habits,
while `Unscheduled Tasks` contains only persisted open non-Preparation Tasks
without positive active reservations. The read also carries strict
`task_targets` snapshots for every current open non-Preparation Task, including
scheduled Tasks, so a replacement editor never rebases stale editable values
onto a current version. Every pending create and update appears in its own
preview section; creates remain absent from persisted target projections.
Setup-owned definitions render as readable immutable title, description, and
cadence with only duration editable; the exact current definition is
resubmitted. These rows are disabled while a mutation or required reload is in
flight. Before submission, the app binds the retained draft and exact stale
replacement source to the generated proposal `request_id`. Header reload never
replays a pending exact retry; after an ambiguous result its successful fresh
read looks up only that request-bound attempt and binds it only when the new
pending plan/revision and complete target snapshot match exactly. It then
clears the exact-retry, conflict, or mutation-error state without replay. A
mismatch binds nothing and triggers no global draft-candidate search; a failed
read retains any required exact-retry or conflict lock. An
ordinary reload remains read-only.
An exact proposal retry carries its original request and an explicit
success/ambiguous/conflict/deterministic outcome back to the page. Repeated
ambiguity keeps that one request binding. A retry `409` drops only that attempt
and its identity-owned stale-source draft; another deterministic rejection
drops the attempt but keeps the exact source draft editable. Confirmation also
removes an identity-owned source draft only when it has not since been replaced,
so a newer edit survives while a same-source unsent draft still follows its
own confirmation lifecycle.
After a successful conflict reload, a pending revision with an exact current
target-/Calendar-/timezone-/Study-stale attention identity offers
`Create new preview`; long-lived persisted stale reasons never attach to the
newest pending revision.
Persisted Task and manual-Habit replacements open the editor with the complete
current target snapshot; Setup uses its current immutable definition and only
retains the target-bound duration. A stale pending create opens as a reviewed
new Task or Habit with no saved-target timestamp. Replacement uses a new
proposal request and applicable latest base revision; it does not replay
confirm or cancel the old preview. Non-stale pending previews and ambiguous
exact retries keep their existing paths. Editable Task/manual-Habit drafts are
target-bound until proposal, request-bound while its outcome is ambiguous, and
exact-preview-bound afterwards; only their own confirmation clears them. Stale
replacement edits additionally remain bound to
the exact stale plan/revision through Availability Back or an ordinary proposal
failure and are invalidated by `409`. Setup retains duration only and can recover it from
a persisted pending target after cold start while using the fresh immutable
definition. Confirming the exact source preview also clears an unsent
replacement for that source; a foreign preview cannot. A committed mutation
whose Overview refresh fails exposes no
preview/success path and disables every derived Planner action until reload.
Invalid recurring Habit, Setup, or weekly fixed-commitment
wall-time occurrences arrive as source- and date-specific attention while valid
occurrences remain visible. Guest/demo keeps the existing zero-call lock.
The Dart contract parser mirrors SQL's 500-revision ceiling, the 499 proposal
base ceiling, the bounded cancelled tombstone shape, and exact active revision
plus active Task-block/Habit-slot states.

Planner `Add new` preserves the selected Preparation kind. `Exam` opens the
single-plan editor; `Assignment` opens `assignment-series-v1` with 12 weekly
occurrences by default and a 2-through-20 bound. The series preview shares one
template but every occurrence remains an independent Preparation Plan. The
student confirms the series once, may later edit one occurrence or all future
ones, and may cancel only the future scope. Past/completed occurrences survive
future-wide changes. Exam and Assignment editors expose no prior-work control
or prior-credit summary; newly created plans submit zero while legacy values
remain transport-compatible. Once a plan exists, its root Exam or Assignment
kind is shown read-only and remains fixed through occurrence edit, replan, and
deep-link entry. Only a new generic Calendar-source proposal keeps the kind
selector. A truly new Exam starts with 120 daily preparation minutes; a truly
new one-off Assignment or Assignment Series starts with 360. Generic Calendar
kind selection updates that value only while it is untouched. Existing
revisions, retained failed drafts, and manually entered daily caps are never
silently replaced. Expanded plan methodology explains that Exams spread their
first sessions while Assignments fill the earliest suitable date first only
for a new or explicitly replanned preview. It does not characterize the saved
blocks of an older active revision, which stay unchanged until a preview is
confirmed.

## Auth Modes

- Guest mode works without Supabase and stores session plus typed, revisioned
  Setup state locally. It never calls FastAPI or Supabase, and guest Setup is not
  copied automatically into an account later. Canonical guest captures are
  migrated best-effort only when real, non-demo authentication succeeds with
  `USE_MOCK_DATA=false`.
- Exact `staging` and `pilot` builds disable guest entry. They require
  `pilot-participation-v1` / `pilot-participation-notice-v1` before Setup or any
  synced product route. Eligibility comes only from the backend-owned profile
  version/time pair, never editable Auth metadata; no birth date is collected.
- Email/password auth requires Supabase configuration.
- Google auth requires Supabase configuration and redirect allowlist entries for
  `http://127.0.0.1:7357`, `http://localhost:7357`, and installed Android builds
  additionally require `com.mylifegraph.app://login-callback/`. Signup,
  recovery, and OAuth use that same Android callback. This repository contains
  no iOS runner, so native iOS callback support is not claimed.
- A real authenticated identity must already have the canonical profile created
  by the backend-owned Auth trigger. A missing profile fails closed with an
  explicit sign-out action; Flutter never attempts to insert or repair the
  protected profile.

First-run Setup requires only Typical weekday and Best energy window, with an
optional display name, routines, fixed commitments, and Study Setup. Focus
areas, friction, coaching style, Reminder preference, and free-form context are
retired Setup inputs; Goals are absent from the current model and schema. Weekly commitments can carry
optional inclusive semester dates and can be duplicated for another weekday;
without dates they repeat until archived. Calendar import is not asked during
onboarding and remains an optional Settings integration. `/onboarding?edit=1`
loads the saved typed state with loading/error/retry behavior. Authenticated real-mode
reads use `GET /v1/intake/setup`; completion and edits use
`POST /v1/intake/complete` with a stable request id and base revision. Blank
optionals create nothing, and
named routines stay candidates until cadence is confirmed. If the newest read
is pending, editing is locked and the original payload/request id is retried.
For save failures, ordinary 4xx responses leave the draft editable, 409 also
offers a reload, and an ambiguous timeout/5xx/invalid response locks the exact
submitted payload for unchanged retry or reload. Settings exposes the durable
Setup re-entry and review path. Setup-owned habits can be edited only there;
active Setup habits remain completable/skippable/undoable through Today Habits
and are excluded from generic Habit Management.

## Phase 3 Executable Actions

Authenticated real accounts now have:

- typed task create/edit/complete/postpone/cancel/restore/undo with optional
  deadlines and `5..480` minute estimates;
- Habit V1 daily, selected-weekday, or weekly-target cadence, explicit
  completion/skip/undo, cadence-aware progress, and manual
  active/paused/archived lifecycle;
- one active focus session at a time, optionally linked to an owned open task or
  active habit, with measured finish/abandon outcomes; and
- exact response-loss reconciliation for every task update including undo,
  every manual habit edit/lifecycle update, habit outcome/undo, and focus
  finish/abandon;
- paginated Habit V1 outcome reads starting 370 calendar days before today and
  DST-safe local progress based on persisted `metadata.started_on`; and
- strict `executable-action-v1` parsing in parity with FastAPI, including
  unknown-field, non-object metadata and explicit-null metadata-field,
  non-integer, invalid-date, linkage, and per-command metadata rejection.
  Unsupported commands are unavailable rather than routed to a no-op.

Every successful real action write refreshes the daily snapshot best-effort.
An exactly reconciled committed write does too. Habit outcome/undo captures one
target date before awaiting persistence, reconciles the exact row or absence,
and refreshes that same date. Focus refresh uses the persisted local start
`entry_date`; legacy/invalid metadata uses the UTC calendar date of `started_at`,
never the later finish/abandon clock. The database locks and revalidates habit
lifecycle/cadence and focus targets, rejects every update to terminal focus
rows, and restricts deletion of linked targets. Refresh failure does not roll
back the durable write. Normal Dashboard reads do not rank a briefing or call
an LLM. See
`../../docs/phase-3-executable-actions-contract.md`.

Scheduled Focus reloads use the newest backend context for target, recovery,
and remaining duration. Completed or sub-five-minute sources stay visible with
an inline explanation, no invalid duration selector, no `starts now` claim, and
a disabled Start action. Eligible past and future sources still start at the
actual backend time while retaining their original planned interval.

## Main Routes

With the development Coach surface enabled, the five shell destinations are
Today, Insights, Quick actions, Planner, and Coach. Those pages plus Settings
share a top action group with optional page action, unread Coach result, and
Settings in that order. Settings is pushed so Back returns to the originating
page; Inbox remains under Settings. A disabled Coach gate omits the fifth
destination rather than restoring Settings; Settings-owned routes such as
`/alerts` leave the shell destinations unselected.

- `/auth`
- `/auth/recovery` (Supabase password-recovery event only)
- `/pilot/privacy` (public and Settings-reachable hosted privacy notice)
- `/pilot/participation` (authenticated hosted pre-product acceptance gate)
- `/onboarding` (`?edit=1` re-enters the durable Setup flow)
- `/dashboard`
- `/insights`
- `/quick-action`
- `/quick-mood-check-in` (typed Evening Shutdown)
- `/morning-calibration` (short typed Morning Calibration)
- `/habit-completion` (Today Habits for authenticated real accounts)
- `/planner` (central authenticated Task/Habit/Preparation/commitment planning;
  guest/demo remains a zero-call locked surface)
- `/habits` (compatible manual Habit V1 route with Planner selected)
- `/preparation-plans` (compatible Preparation route with Planner selected;
  `?kind=exam` opens a kind-locked single Exam flow and `?kind=assignment`
  opens a kind-locked finite weekly Assignment Series flow; the page's general
  `Plan preparation` action always offers both kinds and dispatches to those
  same flows, even after a route-level kind was consumed;
  `?balance_id=<uuid>` opens one owner-scoped Exam-balance review independently
  of the bounded history feed)
- `/planner/replan?plan_id=<uuid>` (focused saved-value review, staged preview,
  and explicit confirmation for exactly one Preparation plan)
- `/weekly-review` (authenticated, completed-week review)
- `/alerts` (Settings-owned stored Inbox with authenticated
  read/unread/dismiss lifecycle; notification generation/delivery contracts are
  unchanged)
- `/notifications` (compatibility redirect to `/alerts`)
- `/daily-check-in` (redirects to Evening Shutdown)
- `/deep-work` (real focus lifecycle for authenticated real accounts; local
  guest/demo redirects to Quick Action)
- `/coach` (typed free read-only Coach; hidden/redirected in production and
  release unless explicitly enabled; guest/mock makes zero Coach HTTP calls)
- `/more` (compatibility alias to `/coach`)
- `/settings`
- `/settings/notifications` (foreground in-app consent, categories, quiet hours,
  and daily cap)
- `/settings/integrations/calendar` (optional authenticated `.ics` import)

Preparation owns the complete `exam-plan-health-v1` display: all active Exams,
all four icon/text status pills, remaining/session/reserved/uncovered/capacity/
reserve values, and recommended/latest-safe starts. The Exam editor's
`Check Exam Plan Health` action posts the exact current values without saving;
new editors and saved unconfirmed drafts omit persistence identity, while only
an active-plan editor sends its plan and base revision for backend
ownership/current-revision validation. Any editor change invalidates an
in-flight result by generation. Preparation renders this projection
independently of the legacy plan feed's loading/error state and uses the
owner-scoped detail read when a Health action or Planner/Today deep link targets
a plan outside that feed. Planner and Today reuse the guarded provider only for
non-green attention. Today additionally requires an account-origin projection
before watching it. Guest/mock returns before an authenticated repository call,
and transport errors are rendered separately from `Availability unknown`.
Refresh loading/error remains visible even when Riverpod retains older green
or empty Health data. Planner uses the shared wrapping status pill and does not
show its combined calm state while Health is refreshing. Confirming or
cancelling an Assignment Series, including an exact retry, invalidates Health
and the other Deadline-owned projections only after proven success.

Preparation also owns the separate strict `multi-exam-plan-v1` Flutter layer:
domain union, repository/data source, controller/provider, and review widgets.
`Balance exam plans` appears only on the normal Preparation page and requires an
explicit active Exam selection; Health supplies the visible recommended/latest
safe context, but the server revalidates the target and expected plan revision.
The copy states that previewing moves nothing and sends no notification or
calendar update. A no-change result stays explanatory, one changed plan adopts
the already persisted Deadline V1 revision exactly once, and two or more
changed plans open a batch review with only `Confirm all` or `Discard`.

Batch detail is the authority for child links. Until it loads successfully, a
possible child card fails closed against normal single-plan confirmation; a
known child offers `Review exam balance`. Mutation state and its immutable
request body survive navigation, same-principal Auth/profile/token refresh,
transient Auth loading/error states, and provider rebuilds, and drive one exact
retry after an ambiguous 5xx or transport failure. While that retry is pending,
feed/detail loads and navigation to
another batch are blocked. A `409` stale response keeps the readable review:
confirmation remains disabled until a fresh authoritative list-plus-detail read
succeeds, while `Discard` remains available for the stale proposed batch. A
targeted detail read remains independent of bounded or failed history, remains
visible when the legacy feed returns its item-limit error, and a late list or
list-detail response cannot evict or retarget it. List-detail failures and
targeted-detail failures remain separately source-bound: a list completion
cannot clear another balance's targeted error, and only the exact failed target
offers `Retry preview`. Deadline, Assignment Series, and Exam-balance
commands share one mutation gate. Preview reconciliation refreshes only local
Deadline/batch state; confirmed/cancelled lifecycle writes emit the broader
projection impact. A durable result whose refresh fails is reported as saved
with stale projections, never as an unknown write outcome. Display and editor
conversion use only a valid current profile IANA timezone; missing/invalid
timezone data disables `Confirm all` while preserving `Discard`, and DST gaps
and folds fail closed instead of falling back to revision or device time.
Status/action
semantics, full-width `Confirm all`/`Discard` controls, and complete labels
remain usable at 320 px and 200% text. Guest/mock returns before constructing
authenticated transport and performs zero balance calls.

Student-facing category treatment is shared between Today and Planner: Task
and Setup use brand, Habit and Preparation use information, Calendar uses
attention, Focus uses violet, and fixed commitments use danger. Preparation
plans are grouped as `Open plans` and compact `History`; only the selected or
newly previewed accordion is expanded. In-page navigation pushes route history,
while shell destinations replace it. The shared top back control pops real
history and uses route-specific fallbacks for direct deep links.

Planner's rolling `Next seven days` and Today's calendar-week `Full week` use
the same feature-neutral day-card and appointment-row primitive but never share
read authority. Full week is lazy and renders all seven
`today-week-agenda-v1` categories with per-source partial failure. Preparation
and Task rows open the current scheduled-start context; active Focus resumes,
terminal Focus opens reflection, completed Preparation opens its plan, and only
the exact current profile-date Habit is actionable. Setup, Calendar, fixed
commitments, and non-current Habit dates are static facts. The client displays
wire-local dates/times without `.toLocal()` conversion.

At normal mobile size the strip shows two full cards plus half of the next; at
the named narrow/large-text breakpoint it shows exactly two. Saturday/Sunday
initial positions clamp so two real days remain, scrolling snaps one day at a
time and cannot pass week bounds. A seven-column layout activates only when
every card retains at least 208 logical pixels. Dense cards grow without fixed
height, and only Full week may use the wider page surface.

Deadline confirm/complete/cancel success, including exact retry, emits one
controller-owned projection impact; proposal previews emit none, and only a
returned managed Task adds the profile date for Daily Snapshot refresh. Focus
lifecycle changes invalidate Full week; reflection-only changes do not because
the replacement agenda carries no rating projection. A refresh failure stays
best effort and does not rewrite the mutation outcome.

The global offline banner reports only that no network transport is available;
it does not prove Supabase or FastAPI reachability. Synced writes are not queued.
Guest/demo local persistence continues on the current device while offline.

The synced-account JSON export is bounded and is not a backup, restore format,
or transaction-wide snapshot. Its strict `account-export-v5` client allowlist
matches the complete 41-table backend contract after Recommendation and
Decision Feedback retirement, including scheduled Focus and finite Assignment
Series provenance. Web downloads
and desktop saves use a chosen destination. Android uses the platform share
sheet; the app removes its own
dedicated temporary source best-effort, while the plugin or operating system
may retain a protected cache copy until its cleanup. The source has an iOS
branch, but this repository has no iOS runner or installed-iOS acceptance claim.
Permanent deletion requires typed confirmation and session-bound Supabase
sign-in evidence no more than 15 minutes old. A stale or refresh-only session
stays signed in and receives an explicit sign-out/sign-in instruction.

Insights shows the Skill profile only in explicitly local/demo mode and labels
it as example data. Real accounts neither load nor render `skillset_profiles`
because no trusted producer currently exists.
Real-account Insights loads `personal-patterns-v1` and
`sleep-recommendation-v1` independently. The Sleep Recommendation card is
directly below Personal Study Pattern and owns loading, disabled, collecting,
unstable, ready, and route-error states without replacing the existing card.
Ready renders Sleep start, Wake time, and Duration plus a below-confirmed-target
warning only when the parsed raw median is below the parsed confirmed target.
The V1 parser rejects inconsistent status/reason, 90-day window, sample,
evidence, or warning relationships and accepts a zero lower duration boundary
created by outward rounding. Wake time says `Same local day` for offset `0` and
`Following local day` for offset `1`; it has no apply action. Guest/local demo
returns before
resolving the sleep API data source, so it makes zero endpoint calls and receives
no synthetic sleep history.
Correlation exploration offers only bounded 7/14/30/90-day windows and pages
every contributing Supabase source with a hard explicit row ceiling; it neither
labels a silently truncated result as all-time nor allocates unbounded history.

Phase 10 is a typed authenticated free-question FastAPI Coach. Flutter never
handles the developer's Codex OAuth login, snapshot, SQL, Python container, or
model credential. It loads capability and mixed legacy/current history without
generating. The Coach page has `Ask anything`, one free question field, Send,
explicit history deletion, and Cancel only while analysis is running. It has no
Today/Patterns/Focus/Review, horizon, Focus-session, prompt-starter,
memory-selection, or structured suggestion controls.

A deliberate send streams strict `coach-request-v3` through SSE. The controller
accepts only `started`, safe `activity`, `completed`, or `failed`; cancellation
closes the stream. Timeout-aware retry preserves the exact request id and
message, while editing rotates identity. Double submit is disabled. The
profile-bound controller is app-scoped: draft, request identity, and a running
stream survive main-page navigation, while logout, profile switch, Coach-gate
loss, and app teardown clear/cancel them.

Completed turns and non-Cancel failures create only an in-memory unread result.
The shared header opens its English success/failure message without navigating
or marking it read. Success is acknowledged only when the end of the newest
reply and uncertainty is visible in the Coach viewport; failures are
acknowledged at the error/retry end marker or when a subsequent retry starts.

Each current `coach-response-v3` shows answer text and uncertainty. Flutter
validates
the safety field and its consistency with provenance without rendering the raw
classification. An expandable `Data and analysis details` section renders
backend-owned `Snapshot source coverage`, conservative source periods/counts,
actual inspect/SQL/Python step summaries, limitations, and provider/model/tier
provenance. It does not present coverage as exact query-result or answer-support
rows, and it never renders plots, scripts, hidden reasoning, or an executable
action. Persisted `coach-response-v1|v2` turns remain readable. Guest/mock
remains zero-call. See `../../docs/phase-10-controlled-coach-plan.md`.

## Verify

```bash
flutter analyze
flutter test
flutter build web --debug --no-wasm-dry-run
```

From the repository root, prefer the shared verification bundle:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

The widget test suite covers the auth gate; required-only guest Setup; typed
prefill, edit, retry, and review behavior; exact same-day Evening/Morning
merge, persistence, retry, and readback; source-aware Dashboard and Full Week
states; route capability gates; durable Settings Setup entry; and strict
notification action routing. Focused domain tests now cover strict action-target
parsing, task validation/undo, all Habit V1 cadence/outcome calculations, and
focus lifecycle invariants. Coach tests cover strict V3/V2/capability/history/
SSE parsing, authenticated requests, guest/mock zero HTTP, retry/cancellation,
capability/error/rate-limit states, mixed legacy history, visible evidence/
trace/Fast detail, absence of fixed-mode/memory/suggestion/plot UI, and history
deletion. Lifecycle tests cover route-persistent draft/request identity and
streaming, profile/app teardown, unread success/failure notices, exact
viewport acknowledgement, Settings Push/Back, and 320 px/200-percent header
layout. Browser E2E additionally covers authenticated
Setup revisions,
identity/ownership-safe reconciliation, exact Phase 1 capture metadata and
deduplicated linked signals, authenticated target-date refreshes, exact Phase 2
Daily State response/persistence, and same-period recomputation. The Phase 3
task/habit/focus journeys now include exact rows, committed-response-loss cases
for habit/task create, habit outcome/undo, task completion/undo, and focus
start/finish, plus negative lifecycle/range/cadence and terminal-focus
`updated_at` assertions in `e2e/web/smoke.mjs`. They must not be claimed as
passed in a later checkout until that checkout's full run succeeds. Exact
current results and the separate per-machine live-provider boundary live in
[Current Verified Baseline](../../docs/verification.md#current-verified-baseline).
Another Linux user's independent clone/login acceptance remains open.

Browser E2E lives at the repository root:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

For local Supabase reset E2E, service-role handling, artifacts, and known
headless browser warnings, use `docs/verification.md` as the source of truth.

Android builds require Android Studio or Android SDK command-line tools. Debug
builds use debug signing. A distributable release intentionally fails until an
ignored `android/key.properties` supplies `storePassword`, `keyPassword`,
`keyAlias`, and `storeFile` for a private release keystore; release never falls
back to the debug key.

## Visual presentation

Student-facing presentation follows
[`docs/frontend-visual-system-v2.md`](../../docs/frontend-visual-system-v2.md).
This changes typography, icons, surfaces, motion, and platform branding only;
the mobile product flows and data authority described here remain unchanged.

Settings visibly groups its existing rows under Profile, Planning and learning,
Tools and connections, and Account and appearance. Student-facing auth uses
`Sign in` and `Create account`; routine failures are provider-neutral,
outcome-first, and never render raw transport or contract exceptions. Shared
status pills and surfaces own semantic state, while category accents remain
non-semantic.
