# MyLifeGraph

Mobile-first foundation for an AI-powered personal coach and life graph product.

The repository currently contains a Flutter web/mobile client, a small FastAPI
AI-service boundary, and Supabase migrations/configuration. The most reliable
way to explore the product today is the Flutter app in mock-data guest mode.

## Current Status

- The Flutter app is the primary user experience.
- Mock/guest mode is the default local path and does not require Supabase keys.
- Supabase Auth and persistence are wired in the app. The canonical snake_case
  migrations create the current app tables, including Intake V1 tables, for
  local Supabase-backed testing.
- The FastAPI service exposes authenticated intake and deterministic
  recommendation endpoints plus a deterministic snapshot refresh endpoint.
  Completing Intake V1 now triggers a controlled deterministic recommendation
  refresh from the onboarding snapshot. Daily and weekly user-state snapshots
  can be refreshed through the backend without an LLM provider.
- Repository docs and scripts should be treated as the shared team source of
  truth. Do not depend on user-local Codex skills or machine-specific paths.

## Repository Structure

- `apps/mobile` - Flutter app with Riverpod state, GoRouter navigation,
  Supabase boundaries, mock data sources, and FastAPI client boundaries.
- `services/ai_service` - Python FastAPI service for recommendation and future
  ML workflows.
- `supabase` - Supabase config, PostgreSQL migrations, and RLS policies.
- `docs` - Architecture, local development, and Supabase status notes.
- `scripts` - Team-friendly helper scripts for local development.
- `AGENTS.md` - Repo-local instructions for coding agents.

## Quick Start

Prerequisites:

- Flutter SDK available on `PATH`, or set `FLUTTER_BIN=/path/to/flutter`.
- Python 3.11+ if you want to run the AI service or static web fallback.
- Node.js 20+ and npm for browser E2E.
- Supabase CLI and Docker for local Supabase-backed tests and browser E2E.

From a fresh clone:

```bash
cp .env.example .env
scripts/start_frontend.sh
```

Open:

```text
http://127.0.0.1:7357
```

Use **Continue as guest** in the app. This is the intended local path when no
Supabase credentials are configured.

If Flutter is not on `PATH`:

```bash
FLUTTER_BIN=/path/to/flutter scripts/start_frontend.sh
```

Static build fallback:

```bash
MODE=static scripts/start_frontend.sh
```

Windows PowerShell users can also run:

```powershell
apps\mobile\start_server_7357.ps1
```

## Runtime Configuration

The Flutter app reads runtime values from Dart defines. The repo script maps
matching environment variables into Dart defines:

```env
APP_ENV=development
USE_MOCK_DATA=true
SUPABASE_URL=
SUPABASE_ANON_KEY=
AI_SERVICE_BASE_URL=http://localhost:8000
```

Useful examples:

```bash
USE_MOCK_DATA=true scripts/start_frontend.sh
```

```bash
USE_MOCK_DATA=false \
SUPABASE_URL=https://your-project.supabase.co \
SUPABASE_ANON_KEY=your-anon-key \
scripts/start_frontend.sh
```

Never commit real Supabase keys.

## AI Service

The AI service is optional for the default mock-data app preview.

```bash
cd services/ai_service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Then check:

```bash
curl http://localhost:8000/v1/health
```

See `services/ai_service/README.md` for details.

## Supabase

Supabase is the intended auth and persistence backend. The current app supports:

- Guest mode without Supabase.
- Email/password auth through Supabase Auth.
- Google OAuth through Supabase Auth when OAuth is configured.
- Supabase-backed reads/writes for selected feature data when credentials and
  expected tables exist.
- Structured onboarding submits Intake V1 to FastAPI in real backend mode,
  creates first deterministic recommendations from the onboarding snapshot, and
  preserves local guest/mock behavior.
- Supabase-backed daily and quick mood check-ins refresh the backend daily
  `user_state_snapshots` row best-effort after writes; guest/mock check-ins stay
  local.

Important current caveat: the Flutter app targets the canonical snake_case
schema. A clean local Supabase reset should apply
`20260702195915_unique_user_state_snapshot_period.sql`, which adds the
snapshot-period unique index after the Intake V1 tables. Remote projects still
need to be inspected directly before relying on `USE_MOCK_DATA=false`.

See `docs/supabase-current-state.md` before changing Supabase schema or relying
on real remote data.

## Verification

Standard non-destructive checks:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

This runs Flutter dependency resolution, analysis, widget tests, Python compile
checks, shell syntax checks, and whitespace checks.

Flutter app, if running commands manually:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter build web --debug --no-wasm-dry-run
```

AI service:

```bash
cd services/ai_service
uvicorn app.main:app --reload --port 8000
curl http://localhost:8000/v1/health
./.venv/bin/python -m pytest
```

Local Supabase verification:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

Local Supabase reset and migration verification:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

`RESET_DB=true` destroys and recreates the local Supabase database only. It must
not be used against a remote database.

Browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

With a fresh local database:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

Use real Ubuntu-installed `node`, `npm`, `supabase`, and Docker for E2E. If
those tools are installed through `nvm`, make sure the shell running the command
has the nvm bin directory on `PATH`.

## Documentation Map

- `docs/local-dev.md` - Full local setup and troubleshooting.
- `docs/architecture.md` - Current architecture and data-flow overview.
- `docs/backend-roadmap.md` - Target backend flow, product agents, data model
  direction, LLM cost controls, and next implementation sequence.
- `docs/supabase-current-state.md` - Supabase auth, schema, RLS, and known gaps.
- `docs/verification.md` - Automated verification scripts and browser E2E.
- `docs/next-chat-prompt.md` - Ready-to-use prompt for continuing the next
  implementation slice in a new chat.
- `apps/mobile/README.md` - Flutter app commands and configuration.
- `services/ai_service/README.md` - FastAPI service setup and endpoints.
- `AGENTS.md` - Instructions for agents working in this repo.
