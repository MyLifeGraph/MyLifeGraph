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

`USE_MOCK_DATA=true` is a deliberate whole-product local/demo boundary even if
the browser still has a Supabase auth session. Setup, daily capture, Dashboard,
Recommendations, Insights, and Notifications stay local, synced habits are
hidden, and snapshot refresh is skipped. Set it to `false` to exercise real
authenticated Supabase/FastAPI sources.
In mock/demo mode, auth boot also skips remote profile reads/creation and guest
check-in migration, then restores the locally applied Setup name and completion
state across reloads.

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
token verification and recommendation persistence. In real backend mode,
successful Intake V1 completion or edit also triggers a best-effort deterministic
recommendation refresh from the constant onboarding snapshot. Read the newest
Setup row with:

```bash
curl http://localhost:8000/v1/intake/setup \
  -H 'Authorization: Bearer <supabase_access_token>'
```

The normal result is the latest applied revision. If the newest row is pending,
the response includes that exact payload and request id so the client can retry
the same save; it must not be edited into a different request.

For a first save, use `base_revision=0` and keep the same `request_id` when
retrying after a timeout:

```bash
curl -X POST http://localhost:8000/v1/intake/complete \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"version":"intake-v1","request_id":"11111111-1111-4111-8111-111111111111","base_revision":0,"responses":{"primary_focus_areas":["focus"],"goals":[{"key":"22222222-2222-4222-8222-222222222222","title":"Protect focus time","status":"active"}],"friction_points":[],"weekday_shape":"school_or_work","best_energy_window":"morning","coaching_style":"direct","reminder_preference":{"enabled":true,"quiet_hours":{"starts_at":"21:00","ends_at":"07:00"}},"routines":[{"key":"33333333-3333-4333-8333-333333333333","title":"Walk after lunch","status":"candidate","cadence_confirmed":false,"frequency":null,"target":null}],"fixed_commitments":[],"calendar_connection_intent":"not_now"},"metadata":{"client":"curl"}}'
```

For an edit, load Setup first, send its `revision` as the next request's
`base_revision`, and use a new request id. Candidate routines must not include
frequency/target values until cadence is explicitly confirmed.

The Flutter save state distinguishes known rejection from an unknown result.
Client validation and HTTP 4xx responses leave the draft editable; 409 also
offers `Reload saved setup`. A timeout, transport failure, 5xx, or invalid
success envelope locks the exact submitted draft and request id for unchanged
retry or explicit reload.

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

```bash
curl -X POST http://localhost:8000/v1/snapshots/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"scope":"daily","window_days":7}'
```

The snapshot endpoint also accepts `"scope":"weekly"` and an optional
`"target_date":"YYYY-MM-DD"`. It derives the user from the bearer token and
uses the backend service-role key only inside FastAPI.

When FastAPI is running and Flutter is in real backend mode, a successful
canonical daily check-in calls the daily snapshot endpoint best-effort. Both
`/daily-check-in` and `/quick-mood-check-in` enter the same typed capture flow.
If FastAPI is down, the check-in save path still succeeds and the snapshot
refresh is skipped by the client.

Backend-only Supabase configuration for the AI service:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=<local service-role key from supabase status>
SUPABASE_TIMEOUT_SECONDS=10
SCHEDULED_REFRESH_TOKEN=<local scheduler token>
```

Keep `SUPABASE_SERVICE_ROLE_KEY` only in the FastAPI service environment. Do
not add it to Flutter `.env`, docs examples with real values, browser runtime
configuration, or committed files. Keep `SCHEDULED_REFRESH_TOKEN` backend-only
for local cron/scheduler tests.

The scheduler-triggered daily refresh endpoint is intentionally not a Flutter
client endpoint:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <local scheduler token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":7,"limit":100,"include_recommendations":false}'
```

It refreshes deterministic daily snapshots for onboarded non-guest profiles.
When `include_recommendations=true`, it also runs the deterministic
recommendation generator with LLM wording disabled.

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
20260710180000_atomic_intake_v1_setup_apply.sql
```

The latest migration installs the service-role-only
`apply_intake_v1_setup_revision` RPC. It serializes apply per user with a
transaction advisory lock and atomically commits preferences, Setup-owned
goals/habits/schedule/memory reconciliation, the canonical onboarding snapshot,
applied intake state, and profile projection. During schedule reconciliation it
removes only the exact unmarked legacy onboarding placeholder `Math`,
`Room 204`, Monday `08:15`-`09:45`; other manual or unmarked onboarding rows are
preserved.

The canonical app schema is snake_case. Legacy CamelCase tables are only used as
optional migration sources when they already exist.

For local Supabase-backed app testing:

1. Run `supabase start`.
2. Run `supabase db reset`.
3. Run `supabase status` and copy the local anon key into `.env`.
4. Set `USE_MOCK_DATA=false`, `SUPABASE_URL=http://127.0.0.1:54321`, and
   `SUPABASE_ANON_KEY=<local anon key>`.
5. Start the frontend with `scripts/start_frontend.sh`.
6. Smoke test registration or sign-in, required-only Setup, Setup re-entry/edit/
   review, the canonical daily check-in, habit management, habit completion, the
   source-aware dashboard, Notifications, and Coach/Deep Work compatibility
   redirects.

Do not infer remote Supabase state from local migrations. Verify the remote
project through the Supabase dashboard, CLI, or connector before using it for
real data.

## Demo Data

For local Supabase-backed product exploration, seed repeatable demo accounts:

```bash
npm run seed:demo
```

Equivalent direct command:

```bash
bash scripts/seed_demo_data.sh
```

The script:

- starts the local Supabase stack if needed;
- reads the local service-role key from `supabase status -o env` without
  printing it;
- refuses to run unless the API URL is `http://127.0.0.1:54321` or
  `http://localhost:54321`;
- creates or updates three confirmed local Auth users;
- writes one typed applied Setup revision per user with a stable request UUID
  and intentionally empty optional Setup-owned collections, while leaving
  separately seeded `demo_seed` objects non-Setup-owned;
- replaces their demo app rows in `daily_logs`, `behavioral_events`, `tasks`,
  `schedule_items`, `habits`, `habit_logs`, `notifications`, `ai_insights`,
  `memory_entries`, `recommendations`, `coach_messages`,
  `intake_responses`, and `user_state_snapshots`.

Demo logins:

| Scenario | Email | Password |
| --- | --- | --- |
| Student focus | `student@example.test` | `DemoPass123!` |
| Busy worker | `worker@example.test` | `DemoPass123!` |
| Recovery builder | `recovery@example.test` | `DemoPass123!` |

Override the local demo password for a fresh seed run with:

```bash
DEMO_PASSWORD='AnotherLocalPassword123!' npm run seed:demo
```

After seeding, start Flutter in real local mode:

```bash
USE_MOCK_DATA=false \
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_ANON_KEY=<local anon key from supabase status> \
FLUTTER_BIN=/path/to/flutter \
scripts/start_frontend.sh
```

Open `http://127.0.0.1:7357`, sign in with one of the demo accounts, and compare
Dashboard, Notifications, Insights, and Habits across scenarios. Coach and Deep
Work remain gated until their backend/action contracts are implemented.
Seeded recommendations are visible through the FastAPI recommendation endpoint
when the AI service is running with the same local Supabase project settings;
without FastAPI, an authenticated account shows a recoverable recommendation
error and never substitutes local mock recommendations.

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
./.venv/bin/python -m pytest
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

The E2E script starts local Supabase, starts the FastAPI AI service with the
local Supabase backend settings, starts Flutter Web on `http://127.0.0.1:7357`,
creates a confirmed local test user through the local Supabase admin API, signs
in through the app, completes required-only Setup, exercises retry/edit/review
and ownership-safe reconciliation, saves check-ins, opens Notifications, and
asserts exact local database identities and values.

By default the script starts FastAPI on `http://127.0.0.1:8000`. Useful AI
service overrides:

```bash
AI_SERVICE_PORT=8001
AI_SERVICE_BASE_URL=http://127.0.0.1:8001
AI_SERVICE_PYTHON=/path/to/python
AI_SERVICE_START=false
```

By default the script always starts FastAPI from the current checkout. It does
not reuse an already-running service on the same port; stop that service or set
`AI_SERVICE_PORT` to a free port. Use `AI_SERVICE_START=false` only when you
intentionally want to reuse a compatible FastAPI process that is already running
with local `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` settings.

The local service-role key is used only inside FastAPI and the Node E2E process
for local test setup and assertions. It is not passed to Flutter.
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
- If E2E database assertions say `intake_responses` or
  `user_state_snapshots` are missing, apply pending local migrations with
  `HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local`
  or run the fresh local DB flow with `RESET_DB=true`.
- If the AI service exits early during E2E, inspect
  `.tools/e2e/ai-service.log` and confirm `services/ai_service` dependencies are
  installed. If the log says the address is already in use, stop the stale
  service or set `AI_SERVICE_PORT` to a free port.
- If Flutter Web exits early during E2E, inspect `.tools/e2e/flutter-web.log`.
- Chromium WebGL performance warnings during E2E are expected in headless/local
  runs.
