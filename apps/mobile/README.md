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
check-in, Dashboard, Recommendations, Insights, Notifications, synced habits,
and snapshot refresh behavior. Mock/demo auth boot skips remote profile access
and overlays the locally applied Setup name/completion state, so local Setup
survives a browser reload.

## Auth Modes

- Guest mode works without Supabase and stores session plus typed, revisioned
  Setup state locally. It never calls FastAPI or Supabase, and guest Setup is not
  copied automatically into an account later. Canonical guest check-ins are
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
active Setup habits remain completable through Habit Completion and are excluded
from generic Habit Management.

## Main Routes

- `/auth`
- `/onboarding` (`?edit=1` re-enters the durable Setup flow)
- `/dashboard`
- `/insights`
- `/quick-action`
- `/quick-mood-check-in` (canonical daily capture implementation)
- `/alerts`
- `/daily-check-in` (redirects to the canonical capture implementation)
- `/deep-work` (compatibility redirect to `/alerts`; preview is gated)
- `/coach` (compatibility redirect to `/dashboard`; preview is gated)
- `/settings`

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
prefill, edit, retry, and review behavior; exact canonical check-in
persistence/readback; source-aware dashboard/recommendation states; route
capability gates; durable Settings Setup entry; and strict notification action
routing. Browser E2E additionally covers authenticated Setup revisions,
identity/ownership-safe reconciliation, exact Supabase rows, linked signals,
authenticated refreshes, and compatibility redirects.

Browser E2E lives at the repository root:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

For local Supabase reset E2E, service-role handling, artifacts, and known
headless browser warnings, use `docs/verification.md` as the source of truth.

Android builds require Android Studio or Android SDK command-line tools.
