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

## Auth Modes

- Guest mode works without Supabase and stores session/onboarding state locally.
- Email/password auth requires Supabase configuration.
- Google auth requires Supabase configuration and OAuth redirect settings for
  `http://127.0.0.1:7357` and `http://localhost:7357`.

## Main Routes

- `/auth`
- `/onboarding`
- `/dashboard`
- `/insights`
- `/quick-action`
- `/quick-mood-check-in`
- `/alerts`
- `/daily-check-in`
- `/deep-work`
- `/coach`
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

The widget test suite currently verifies the auth gate, guest onboarding to the
dashboard, and guest quick mood check-in persistence. These are widget-level
smoke tests, not browser E2E tests.

Browser E2E lives at the repository root:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

For local Supabase reset E2E, service-role handling, artifacts, and known
headless browser warnings, use `docs/verification.md` as the source of truth.

Android builds require Android Studio or Android SDK command-line tools.
