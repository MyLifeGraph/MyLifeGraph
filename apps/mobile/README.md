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

Supabase is only initialized when both `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are non-empty.

`USE_MOCK_DATA=true` forces product data surfaces to local/demo sources even
when an authenticated Supabase session exists. Use `false` for real Setup,
Evening/Morning capture, Dashboard, Recommendations, Insights, Notifications,
synced tasks/habits/focus sessions, and snapshot refresh behavior. Mock/demo
auth boot skips remote profile access and overlays the locally applied Setup
name/completion state, so local Setup survives a browser reload.

For authenticated real accounts, successful Evening/Morning writes refresh the
backend Daily State best-effort. That snapshot may classify a deterministic
Daily Mode, but the current Flutter surface does not display a Today plan or
generate recommendations. Morning Calibration therefore describes only what it
does locally: it records current state and does not generate recommendations or
create or change a plan. Guest/mock capture remains local and makes no snapshot
request.

## Auth Modes

- Guest mode works without Supabase and stores session plus typed, revisioned
  Setup state locally. It never calls FastAPI or Supabase, and guest Setup is not
  copied automatically into an account later. Canonical guest captures are
  migrated best-effort only when real, non-demo authentication succeeds with
  `USE_MOCK_DATA=false`.
- Email/password auth requires Supabase configuration.
- Google auth requires Supabase configuration and OAuth redirect settings for
  `http://127.0.0.1:7357` and `http://localhost:7357`.

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

- `/auth`
- `/onboarding` (`?edit=1` re-enters the durable Setup flow)
- `/dashboard`
- `/insights`
- `/quick-action`
- `/quick-mood-check-in` (typed Evening Shutdown)
- `/morning-calibration` (short typed Morning Calibration)
- `/habit-completion` (Today Habits for authenticated real accounts)
- `/habits` (manual Habit V1 management for authenticated real accounts)
- `/alerts`
- `/daily-check-in` (redirects to Evening Shutdown)
- `/deep-work` (real focus lifecycle for authenticated real accounts; local
  guest/demo redirects to Quick Action)
- `/coach` (compatibility redirect to `/dashboard`; preview is gated)
- `/settings`

Phase 10 will replace the gated canned `MorePage`/direct Supabase message path
with a typed authenticated FastAPI Coach boundary. Flutter will not handle the
developer's Codex OAuth login or receive any model credential; it will only show
the backend's honest local-provider capability, answer, provenance, data-use,
memory, and failure states. Guest/mock will remain zero-call. See
`../../docs/phase-10-controlled-coach-plan.md`; none of that provider behavior
is active in the current checkout.

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
focus lifecycle invariants. Browser E2E additionally covers authenticated
Setup revisions,
identity/ownership-safe reconciliation, exact Phase 1 capture metadata and
deduplicated linked signals, authenticated target-date refreshes, exact Phase 2
Daily State response/persistence, and same-period recomputation. The Phase 3
task/habit/focus journeys now include exact rows, committed-response-loss cases
for habit/task create, habit outcome/undo, task completion/undo, and focus
start/finish, plus negative lifecycle/range/cadence and terminal-focus
`updated_at` assertions in `e2e/web/smoke.mjs`. They must not be claimed as
passed until the current-checkout run succeeds.

Browser E2E lives at the repository root:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

For local Supabase reset E2E, service-role handling, artifacts, and known
headless browser warnings, use `docs/verification.md` as the source of truth.

Android builds require Android Studio or Android SDK command-line tools.
