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
- The FastAPI service exposes authenticated typed Setup read/completion/edit,
  deterministic recommendation endpoints, and deterministic snapshot refresh.
  Applying Intake V1 triggers a controlled recommendation refresh from the
  constant onboarding snapshot. Daily and weekly user-state snapshots can be
  refreshed without an LLM provider and now include an explainable
  deterministic Daily State with freshness, quality, risks, reasons, and a
  recovery-first Daily Mode. The dashboard includes a deliberate deterministic
  recommendation refresh action, and a backend-only scheduled endpoint can
  refresh onboarded non-guest profiles for cron-style runs.
- Insights includes deterministic correlation exploration for sleep, workload,
  stress, energy, mood, screen time, activity, steps, habits, recovery, and
  focus. It computes 7/14/30-day relationships in Flutter from existing
  Supabase rows or local mock time series, without LLM usage.
- Phase 0A, Honest Capture; Phase 0B, Source And Surface Truth; Phase 0C,
  First-Run And Setup Integrity; Phase 1, Lightweight Evening And Morning
  Capture; and Phase 2, Explainable Daily State, are implemented. Evening and
  Morning merge without erasing each other, remain local in guest/demo mode,
  and feed a strict backend-only state parser for real accounts. Setup remains
  progressive, revision-safe, reviewable, and atomically materialized through
  its unchanged service-role-only RPC. Phase 3, Executable Action And Habit
  Contracts, is next. See `docs/daily-briefing-implementation-plan.md` for the
  operating loop and roadmap.
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

`USE_MOCK_DATA=true` is an explicit local-demo boundary for product data
surfaces, including when a Supabase authentication session happens to exist.
Mock/demo auth boot avoids remote profile/data reads and restores the locally
applied Setup across reloads. Use `USE_MOCK_DATA=false` for authenticated
Supabase/FastAPI data.

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
- In real mode, structured Setup reads authenticated state through
  `GET /v1/intake/setup` and saves initial completion or edits through
  `POST /v1/intake/complete` using a stable request id and optimistic base
  revision. Guest or mock Setup follows the same typed semantics locally and
  never calls Supabase or FastAPI.
- Guest Setup is intentionally not copied into an account automatically. A
  newly authenticated account loads its own backend Setup; canonical guest
  check-ins are the only guest product data migrated best-effort today, and only
  for a real non-demo account with `USE_MOCK_DATA=false`.
- Blank optional Setup answers create no goals, habits, schedule items, or
  memories. Named routines remain candidates until cadence is confirmed;
  setup-owned records use deterministic identities and can be reviewed, edited,
  archived, paused, or removed without reconciling manual rows.
- Setup-owned habits are edited, paused, or archived through Settings Setup;
  active Setup habits still appear in Habit Completion. Generic Habit Management
  edits only manually managed habits.
- A rejected 4xx Setup save keeps the draft editable; 409 also prompts a server
  reload. Timeouts, 5xx failures, and invalid success envelopes have an unknown
  durable result, so the exact submitted draft is locked for unchanged retry or
  explicit reload.
- Evening Shutdown captures explicit mood, energy, stress intensity/source/
  controllability, focus band, main friction, tomorrow priority, and optional
  reflection, blocker, and gentle-tomorrow intent. Morning Calibration is a
  separate short flow for sleep hours, current energy, and day shape.
- Both captures merge under `daily_logs.metadata.captures` for the same user and
  date. Morning energy owns the compatible `energy_level` projection when
  present; Evening owns mood and stress, and Morning owns sleep. Linked
  `behavioral_events` are a dynamic, deterministically identified set of at
  most mood, energy, stress, and sleep events. Guest storage uses the same V2
  daily model while retaining V1 read/migration compatibility.
- The dashboard refresh action first refreshes the daily snapshot best-effort,
  then calls the deterministic recommendation generator with LLM wording
  disabled. Normal dashboard reads still do not generate recommendations.
- Supabase-backed Evening and Morning saves refresh the backend daily
  `user_state_snapshots` row best-effort for their explicit local
  `target_date`. Dashboard task status changes plus Quick Action habit creation,
  edits, active-state changes, and completions use the same refresh path after
  successful Supabase updates; guest/mock paths stay local.
- The additive `summary.daily_state` contract is
  `explainable-daily-state-v1`. It uses strict V2 parsing, a fixed seven-day
  state lookback separate from the requested statistics window, explicit
  `missing`/`partial`/`current`/`stale` quality, and recovery-first
  `push`/`steady`/`recover`/`plan` classification. It carries bounded evidence
  and provenance but excludes tomorrow-priority, reflection, and blocker text.
- Phase 1 does not assign Daily Mode, rank briefing actions, generate
  recommendations on capture save, or call an LLM. Phase 2 assigns Daily Mode
  only inside persisted backend snapshots; it still does not rank actions,
  mutate a plan, generate recommendations, or expose a Today UI. Dashboard
  capture cards show only direct nullable source values and persisted structured
  context.
- `POST /v1/scheduled/daily-refresh` is a backend-only scheduler endpoint
  protected by `X-Scheduled-Refresh-Token`; it must not be called from Flutter.

Important current caveat: the Flutter app targets the canonical snake_case
schema. A clean local Supabase reset should apply
`20260710180000_atomic_intake_v1_setup_apply.sql`, after the Phase 0C Intake
request/revision and profile-projection migrations. The latest migration adds a
service-role-only, transactionally locked RPC for atomic Setup materialization.
Remote projects still need to be inspected directly before relying on
`USE_MOCK_DATA=false`.

See `docs/supabase-current-state.md` before changing Supabase schema or relying
on real remote data.

For local product exploration with real Supabase-backed dashboards, seed three
local demo accounts:

```bash
npm run seed:demo
```

The script starts local Supabase if needed, refuses non-local Supabase URLs, and
creates repeatable student, worker, and recovery scenarios. Its typed Setup
rows include valid applied revisions with intentionally empty Setup-owned
optional collections; separately seeded scenario goals, habits, and commitments
remain `demo_seed` data. All demo accounts use the local-only password
`DemoPass123!`.

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

The browser E2E script starts local Supabase, starts FastAPI with local backend
Supabase settings, and runs Flutter Web. Its smoke path includes authenticated
Setup ownership/revision assertions, Evening/Morning merge assertions,
deterministic linked-event checks, snapshot refresh, recommendations, and core
app writes. Run the command before claiming the current checkout passes that
path.

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
