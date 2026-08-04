# MyLifeGraph Mobile App

Flutter client for the AI Personal Coach / MyLifeGraph product.

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
| `APP_ENV` | `development` | Environment label. |
| `USE_MOCK_DATA` | `false` in code, `true` in scripts | Enables mock repository paths. |
| `SUPABASE_URL` | empty | Enables Supabase when paired with anon key. |
| `SUPABASE_ANON_KEY` | empty | Public anon key for Supabase client. |
| `AI_SERVICE_BASE_URL` | `http://localhost:8000` | FastAPI service base URL. |
| `COACH_SURFACE_ENABLED` | unset/fail-closed in release and production | Exact `true` explicitly exposes Coach; backend capability still controls sending. |
| `LEARNED_FOCUS_PLANNING_PILOT_ENABLED` | `false` | Exact `true` enables the development-only learned-timing Planner pilot; the backend must use the same flag. Production builds stay fail-closed. |

Supabase is only initialized when both `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are non-empty.

`USE_MOCK_DATA=true` forces product data surfaces to local/demo sources even
when an authenticated Supabase session exists. Use `false` for real Setup,
Evening/Morning capture, Today, Planner, Recommendations, Insights, Inbox,
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
State best-effort. Today reads the strict read-only
`today-overview-v2` projection: both-capture streak, dynamic progress, the
Setup/Preparation/Calendar/Focus plus Planner Task/Habit/fixed-commitment
agenda, Tasks, and Habits. The V1 route remains available for older clients.
Supporting workload,
reviews, signals, recommendations, feedback history, and the full week remain
lazy. The persisted deterministic briefing still exists for backend consumers,
but it is no longer presented as a decision made for the user. Capture itself
does not generate recommendations or create/change a plan. Morning Calibration
therefore describes only what that save does. Under `daily-capture-v5`, Evening
requires one planned local sleep time and a `300..720` minute target on a
15-minute grid. Morning records editable aware estimated sleep-start/wake
instants, derives and labels the `Estimated sleep duration`, retains the target
used for that night, and separately requires a `1..10` estimated sleep-quality
rating plus current energy. It does not ask for Day Shape, and V5 rejects a
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
streak/progress/agenda, Tasks, Habits, and lazy supporting content. Task
creation/editing remains in Planner; an unreachable duplicate Today editor and
its inert edit/cancel/postpone wiring are not retained.

Planner additionally loads the strictly read-only
`exam-week-outlook-v1` projection for authenticated real accounts. An active
exam may show a 14-day watch, seven-day Exam week, or overdue card before
ordinary attention; assignments consume capacity but do not activate it. The
card can open existing review/replan navigation but never creates a preview,
changes a plan, adds a Today item, or generates a Notification. Guest/demo makes
no outlook request.

## Auth Modes

- Guest mode works without Supabase and stores session plus typed, revisioned
  Setup state locally. It never calls FastAPI or Supabase, and guest Setup is not
  copied automatically into an account later. Canonical guest captures are
  migrated best-effort only when real, non-demo authentication succeeds with
  `USE_MOCK_DATA=false`.
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
areas, Goals, friction, coaching style, Reminder preference, and free-form
context are retired Setup inputs. Weekly commitments can carry
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
back the durable write. Normal Dashboard reads do not generate recommendations,
and Phase 3 does not rank a briefing or call an LLM. See
`../../docs/phase-3-executable-actions-contract.md`.

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
  `?kind=exam|assignment` opens that create flow)
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

Student-facing category treatment is shared between Today and Planner: Task
and Setup use brand, Habit and Preparation use information, Calendar uses
attention, Focus uses violet, and fixed commitments use danger. Preparation
plans are grouped as `Open plans` and compact `History`; only the selected or
newly previewed accordion is expanded. In-page navigation pushes route history,
while shell destinations replace it. The shared top back control pops real
history and uses route-specific fallbacks for direct deep links.

The global offline banner reports only that no network transport is available;
it does not prove Supabase or FastAPI reachability. Synced writes are not queued.
Guest/demo local persistence continues on the current device while offline.

The synced-account JSON export is bounded and is not a backup, restore format,
or transaction-wide snapshot. Its strict client allowlist matches the complete
41-table backend contract, including scheduled Focus provenance. Web downloads
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
warning when returned. Wake time says `Same local day` for offset `0` and
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

Each `coach-response-v2` shows answer text and uncertainty. Flutter validates
the safety field and its consistency with provenance without rendering the raw
classification. An expandable `Data and analysis details` section renders
backend-owned `Snapshot source coverage`, conservative source periods/counts,
actual inspect/SQL/Python step summaries, limitations, and model/Fast
provenance. It does not present coverage as exact query-result or answer-support
rows, and it never renders plots, scripts, hidden reasoning, or an executable
action. Legacy `coach-response-v1` turns remain readable. Guest/mock remains
zero-call. See `../../docs/phase-10-controlled-coach-plan.md`.

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
merge, persistence, retry, and readback; source-aware dashboard/recommendation
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
