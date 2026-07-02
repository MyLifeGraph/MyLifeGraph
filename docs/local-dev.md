# Local Development

This guide is written for a fresh clone. It avoids machine-specific paths and
does not assume any user-local Codex skills.

## Prerequisites

- Flutter SDK. Confirm with `flutter --version`.
- Python 3.11+ for the AI service and static web fallback.
- Node.js 20+ and npm for browser E2E. Confirm with `node --version` and
  `npm --version` in the Ubuntu shell.
- Optional: Supabase CLI and Docker for local Supabase work. Install the real
  Supabase CLI so `supabase --version` works in the Ubuntu shell; do not rely on
  a repo-local binary. Confirm Docker with `docker --version`.

If Node.js, npm, or Supabase CLI are installed through `nvm`, remember that
non-interactive agent shells may not source nvm automatically. In that case,
source nvm before running commands or pass a narrow override such as:

```bash
PATH=/path/to/nvm/versions/node/vXX/bin:$PATH \
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

Do not install tool binaries into `.tools/`; `.tools/` is only for ignored local
runtime state and artifacts.

If Flutter is not on `PATH`, set `FLUTTER_BIN` when running scripts:

```bash
FLUTTER_BIN=/path/to/flutter scripts/start_frontend.sh
```

## First Run

From the repository root:

```bash
cp .env.example .env
scripts/start_frontend.sh
```

Open:

```text
http://127.0.0.1:7357
```

Choose **Continue as guest**. The default local workflow uses mock data and does
not need Supabase.

## Environment

The root `.env.example` documents the shared local values:

```env
APP_ENV=development
USE_MOCK_DATA=true
SUPABASE_URL=
SUPABASE_ANON_KEY=
AI_SERVICE_BASE_URL=http://localhost:8000
```

The Bash and PowerShell start scripts pass these values into Flutter as Dart
defines.

## Frontend Script

Default Flutter web-server mode:

```bash
scripts/start_frontend.sh
```

Static build mode:

```bash
MODE=static scripts/start_frontend.sh
```

Useful overrides:

```bash
HOST=0.0.0.0 PORT=8080 scripts/start_frontend.sh
```

```bash
USE_MOCK_DATA=false \
SUPABASE_URL=https://your-project.supabase.co \
SUPABASE_ANON_KEY=your-anon-key \
scripts/start_frontend.sh
```

Windows PowerShell:

```powershell
apps\mobile\start_server_7357.ps1
```

The PowerShell script reads `.env`, builds Flutter Web, and serves `build\web`
on `127.0.0.1:7357`.

## AI Service

The AI service is optional for the default mock frontend.

```bash
cd services/ai_service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Health check:

```bash
curl http://localhost:8000/v1/health
```

Recommendation contract endpoints require an authenticated bearer token. PR1
defined the contract; backend Supabase settings are now required for real
token verification and recommendation persistence:

```bash
curl -X POST http://localhost:8000/v1/intake/complete \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"version":"intake-v1","responses":{"primary_focus_areas":["focus"],"goals":["Protect focus time"],"friction_points":["Context switching"],"weekday_shape":"school_or_work","best_energy_window":"morning","coaching_style":"direct","reminder_preference":{"enabled":true,"quiet_hours":{"starts_at":"21:00","ends_at":"07:00"}},"calendar_connection_intent":"not_now"},"metadata":{"client":"curl"}}'
```

```bash
curl http://localhost:8000/v1/recommendations \
  -H 'Authorization: Bearer <supabase_access_token>'
```

```bash
curl -X POST http://localhost:8000/v1/recommendations/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":28,"force":false,"allow_llm_wording":false}'
```

Backend-only Supabase configuration for the AI service:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=<local service-role key from supabase status>
SUPABASE_TIMEOUT_SECONDS=10
```

Keep `SUPABASE_SERVICE_ROLE_KEY` only in the FastAPI service environment. Do
not add it to Flutter `.env`, docs examples with real values, browser runtime
configuration, or committed files.

## Supabase

Supabase is optional for mock mode. To work on local Supabase you need the real
Supabase CLI and Docker available in the Ubuntu shell.

Manual commands:

```bash
supabase start
supabase db reset
```

Read `docs/supabase-current-state.md` first. `supabase db reset` is a local
destructive reset and should complete through:

```text
20260702092807_intake_v1_backend_foundation.sql
```

The canonical app schema is snake_case. Legacy CamelCase tables are only used as
optional migration sources when they already exist.

For local Supabase-backed app testing:

1. Run `supabase start`.
2. Run `supabase db reset`.
3. Run `supabase status` and copy the local anon key into `.env`.
4. Set `USE_MOCK_DATA=false`, `SUPABASE_URL=http://127.0.0.1:54321`, and
   `SUPABASE_ANON_KEY=<local anon key>`.
5. Start the frontend with `scripts/start_frontend.sh`.
6. Smoke test registration or sign-in, onboarding, daily check-in, quick mood
   check-in, dashboard, notifications, and coach message send.

Do not infer remote Supabase state from local migrations. Verify the remote
project through the Supabase dashboard, CLI, or connector before using it for
real data.

Automated local preflight without resetting the database:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

Automated local reset and test run:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The script runs Supabase with telemetry disabled, redacts keys from output,
reads the local anon key from `supabase status -o env`, and runs Flutter tests
with `USE_MOCK_DATA=false`.

## Verification

Flutter:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter build web --debug --no-wasm-dry-run
```

AI service:

```bash
cd services/ai_service
python -m compileall app
pytest
```

All standard non-destructive checks from the repository root:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

Local Supabase preflight and reset workflow:

```bash
RESET_DB=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

`RESET_DB=true` is required intentionally because `supabase db reset` destroys
and recreates the local database. The script still requires the Supabase CLI and
Docker to be available to the same shell that runs it. It reads the local anon
key from `supabase status` without printing the key.

For details on what each script verifies and what is still not automated, read
`docs/verification.md`.

Browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

Browser E2E with a fresh local database:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

The E2E script starts local Supabase, starts Flutter Web on
`http://127.0.0.1:7357`, creates a confirmed local test user through the local
Supabase admin API, signs in through the app, completes onboarding, saves
check-ins, opens alerts, sends a coach message, and asserts local database rows
were created.

The local service-role key is used only inside the Node E2E process for local
test setup and assertions. It is not passed to Flutter.
This automated browser smoke covers the manual Supabase-backed smoke path for
the listed screens. Keep manual testing for flows not listed in
`docs/verification.md`.

## Troubleshooting

- If `flutter` is not found, install Flutter or set `FLUTTER_BIN`.
- If port `7357` is already in use, open `http://127.0.0.1:7357` first to see
  whether the app is already running.
- A `HEAD /` request may not prove the Flutter web-server is broken. Test with
  a normal browser request or `curl http://127.0.0.1:7357/`.
- If Supabase auth buttons fail, confirm `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  and provider redirect URLs.
- If real Supabase reads return empty data, confirm the authenticated user and
  expected tables exist.
- If `scripts/verify_supabase_local.sh` cannot connect to Docker, rerun it in an
  environment with Docker socket access.
- If `scripts/verify_supabase_local.sh` says Supabase CLI is missing, install
  the real Supabase CLI in Ubuntu so `supabase --version` works.
- If `scripts/e2e_web.sh` says Node.js is missing, install real Node.js in
  Ubuntu so `node --version` works.
- If `scripts/e2e_web.sh` says Playwright is missing, run `npm install`.
- If Playwright cannot find a browser, run `npx playwright install chromium` or
  set `CHROME_BIN=/path/to/chrome`.
- If Flutter Web exits early during E2E, inspect `.tools/e2e/flutter-web.log`.
- Chromium WebGL performance warnings during E2E are expected in headless/local
  runs. A browser `ERR_CONNECTION_REFUSED` for the AI service can also appear
  when `AI_SERVICE_BASE_URL` points at `localhost:8000` and the FastAPI service
  is not running; treat the script exit code and DB assertions as authoritative.
