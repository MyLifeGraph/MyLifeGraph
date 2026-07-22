# MyLifeGraph Mobile App

Flutter client for the AI Personal Coach / MyLifeGraph product.

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

Supabase is only initialized when both `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are non-empty.

`USE_MOCK_DATA=true` forces product data surfaces to local/demo sources even
when an authenticated Supabase session exists. Use `false` for real Setup,
Evening/Morning capture, Today, Planner, Recommendations, Insights, Inbox,
synced tasks/habits/focus sessions, Controlled Coach, and snapshot refresh
behavior. Mock/demo
auth boot skips remote profile access and overlays the locally applied Setup
name/completion state, so local Setup survives a browser reload.

For authenticated real accounts, successful Evening/Morning writes refresh the
backend Daily State best-effort. Today reads the strict read-only
`today-overview-v2` projection: both-capture streak, dynamic progress, the
Setup/Preparation/Calendar/Focus plus Planner Task/Habit/fixed-commitment
agenda, Tasks, and Habits. The V1 route remains available for older clients.
Supporting workload,
reviews, signals, recommendations, feedback history, and the full week remain
lazy. The persisted deterministic briefing still exists for backend consumers,
but it is no longer presented as a decision made for the user. Capture itself
does not generate recommendations or create/change a plan. Morning Calibration
therefore describes only what that save does. Guest/mock Today and capture stay
local and make no authenticated request.

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

First-run Setup uses explicit required selections and progressive optional
goals, routines, context, and fixed commitments. `/onboarding?edit=1` loads the
saved typed state with loading/error/retry behavior. Authenticated real-mode
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

The five shell destinations are Today, Insights, Quick actions, Planner, and
Settings. Inbox is reached from Settings; compatible `/alerts` links keep
Settings selected.

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
- `/weekly-review` (authenticated, completed-week review)
- `/alerts` (Settings-owned stored Inbox with authenticated
  read/unread/dismiss lifecycle; notification generation/delivery contracts are
  unchanged)
- `/notifications` (compatibility redirect to `/alerts`)
- `/daily-check-in` (redirects to Evening Shutdown)
- `/deep-work` (real focus lifecycle for authenticated real accounts; local
  guest/demo redirects to Quick Action)
- `/coach` (typed Controlled Coach; hidden/redirected in production and release
  unless explicitly enabled; guest/mock makes zero Coach HTTP calls)
- `/more` (compatibility alias to `/coach`)
- `/settings`
- `/settings/integrations/calendar` (optional authenticated `.ics` import)

The global offline banner reports only that no network transport is available;
it does not prove Supabase or FastAPI reachability. Synced writes are not queued.
Guest/demo local persistence continues on the current device while offline.

The synced-account JSON export is bounded and is not a backup, restore format,
or transaction-wide snapshot. Web downloads and desktop saves use a chosen
destination. Android uses the platform share sheet; the app removes its own
dedicated temporary source best-effort, while the plugin or operating system
may retain a protected cache copy until its cleanup. The source has an iOS
branch, but this repository has no iOS runner or installed-iOS acceptance claim.
Permanent deletion requires typed confirmation and session-bound Supabase
sign-in evidence no more than 15 minutes old. A stale or refresh-only session
stays signed in and receives an explicit sign-out/sign-in instruction.

Insights visibly consumes the strict latest `skillset_profiles` row. Missing or
malformed real rows remain an explicit retryable state; no demo profile is
substituted into a real account.
Correlation exploration offers only bounded 7/14/30/90-day windows and pages
every contributing Supabase source with a hard explicit row ceiling; it neither
labels a silently truncated result as all-time nor allocates unbounded history.

Phase 10 replaces the gated canned `MorePage`/direct Supabase message path with
a typed authenticated FastAPI Coach boundary. Flutter does not handle the
developer's Codex OAuth login or receive any model credential. It loads
capability, validated history, and eligible memory without generating; sends
only a strict deliberate `coach-request-v1`; and shows uncertainty, safety,
provider/model/prompt/context provenance, exact `Data used` counts/freshness,
and at most one review-only suggestion. Memory selection/deselection is explicit
and underlying Setup/manual content stays unchanged. Failed/ambiguous sends keep
the draft and exact retry identity when needed; double submit is disabled.
Conversation deletion is explicit. Guest/mock remains zero-call. See
`../../docs/phase-10-controlled-coach-plan.md`.

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
focus lifecycle invariants. Controlled Coach tests cover strict nested parsing,
authenticated request methods/bodies/timeouts, guest/mock zero HTTP, controller
retry/cancellation, capability/error/rate-limit states, visible provenance/data
use, memory control, and conversation deletion. Browser E2E additionally covers authenticated
Setup revisions,
identity/ownership-safe reconciliation, exact Phase 1 capture metadata and
deduplicated linked signals, authenticated target-date refreshes, exact Phase 2
Daily State response/persistence, and same-period recomputation. The Phase 3
task/habit/focus journeys now include exact rows, committed-response-loss cases
for habit/task create, habit outcome/undo, task completion/undo, and focus
start/finish, plus negative lifecycle/range/cadence and terminal-focus
`updated_at` assertions in `e2e/web/smoke.mjs`. They must not be claimed as
passed in a later checkout until that checkout's full run succeeds. In the
2026-07-13 current checkout, a focused Phase 10 rerun and the subsequent full
non-destructive local browser journey passed with the fake provider. The
focused mode is diagnostic only. A separate authenticated Flutter-to-FastAPI-to-
`local_codex_oauth` live turn also passed on this machine with explicit
`gpt-5.5`, validated UI rendering and provenance, and persisted authenticated
history; no question, prompt, or answer content was logged. Another Linux
user's independent clone/login acceptance remains open. See
`../../docs/verification.md`.

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
