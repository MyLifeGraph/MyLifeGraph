# Agent Instructions

These instructions are for coding agents working in this repository. They are
repo-local and must not depend on any user-private Codex skill or machine-local
profile configuration.

This file is the required starting point for agents. Read it before making code
or schema changes, then consult the linked docs for more detail.

## Start Here

Read these files before making changes:

1. `README.md`
2. `docs/local-dev.md`
3. `docs/architecture.md`
4. `docs/backend-roadmap.md` before planning backend, AI, onboarding, or agent
   workflows
5. `docs/verification.md` before running or changing test automation
6. `docs/supabase-current-state.md` when touching Supabase, auth, data sources,
   or migrations

## Current State

MyLifeGraph is a Flutter web/mobile app with Supabase for auth and persistence
and a FastAPI service for authenticated deterministic recommendation workflows
and future AI integrations.

The app now targets a canonical snake_case Supabase schema. Older remote
databases may still contain legacy CamelCase tables such as `"User"`,
`"DailyLog"`, and `"Task"`, but new app code should use:

- `profiles`
- `daily_logs`
- `behavioral_events`
- `tasks`
- `schedule_items`
- `notifications`
- `coach_messages`
- `memory_entries`
- `ai_insights`
- `recommendations`
- `skillset_profiles`
- `notification_preferences`
- `goals`, `habits`, `habit_logs`, `focus_sessions`
- `intake_responses`, `user_state_snapshots`

The migration
`supabase/migrations/20260618170000_create_canonical_app_schema.sql` creates the
canonical schema, applies RLS policies, and copies data from legacy CamelCase
tables when they exist. It intentionally does not drop legacy tables. The
migration
`supabase/migrations/20260702092807_intake_v1_backend_foundation.sql` adds the
Intake V1 backend tables and RLS policies. The migration
`supabase/migrations/20260702195915_unique_user_state_snapshot_period.sql`
deduplicates `user_state_snapshots` by user/scope/period and adds the unique
index required for atomic backend upserts.

## Important Docs

- `docs/architecture.md` - system shape and current backend/frontend boundary.
- `docs/backend-roadmap.md` - target backend flow, product agents, data model
  direction, LLM cost controls, and the next implementation sequence.
- `docs/supabase-current-state.md` - canonical schema, legacy table mapping, and
  migration notes.
- `docs/local-dev.md` - local runbook for Flutter, Supabase, and FastAPI.
- `docs/verification.md` - automated checks, local Supabase verification, and
  current E2E gaps.
- `README.md` - high-level project overview.

## Next Implementation Direction

The **Intake V1 without LLM** foundation, controlled deterministic
recommendation refresh after authenticated intake, and the authenticated
deterministic snapshot aggregator endpoint now exist. Read
`docs/backend-roadmap.md` before planning the next backend, AI, onboarding, or
agent workflow.

Do not jump straight to broad LLM integration, calendar import, weekly planning,
vector search, or autonomous background agents. The next product slice should
build on the snapshot aggregator by wiring controlled refresh triggers after
task or habit changes, or by adding scheduled refresh. FastAPI-backed browser
E2E coverage for Intake V1, post-intake recommendations, and daily snapshot
refresh now exists.

The implemented post-intake refresh is backend-only and best-effort:

- `POST /v1/intake/complete` derives `user_id` from the verified Supabase
  bearer token.
- The intake service writes `intake_responses`, onboarding-owned records, and an
  onboarding `user_state_snapshots` row.
- It then calls the deterministic recommendation engine with no LLM usage.
- The recommendation engine reads recent `daily_logs`, `behavioral_events`,
  `tasks`, and latest `user_state_snapshots`, verifies candidates, dedupes by
  fingerprint, and persists accepted rows to `recommendations`.
- Normal dashboard reads through `GET /v1/recommendations` must still not
  generate recommendations.
- `POST /v1/snapshots/generate` derives `user_id` from the verified Supabase
  bearer token and creates or refreshes deterministic `daily` and `weekly`
  `user_state_snapshots`.
- Supabase-backed Daily Check-In and Quick Mood Check-In now call the daily
  snapshot refresh best-effort after successful writes. Guest/mock paths must
  remain local and must not call the AI service.

## Local Supabase Workflow

Supabase CLI and Docker are required for local database testing. Use real Ubuntu
tool installations; `supabase --version` and `docker --version` must work in the
Ubuntu shell. The preferred
agent-safe command is:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify_supabase_local.sh
```

This starts the local Supabase stack, redacts CLI key output, reads the local
anon key from `supabase status -o env`, and runs Flutter tests with
`USE_MOCK_DATA=false`.

If Node.js, npm, or Supabase CLI are installed through `nvm`, a non-interactive
agent shell may not inherit that `PATH` even though the commands work in the
user's interactive Ubuntu shell. In that case, source the real nvm environment
or pass a narrow `PATH`/`NODE_BIN` override. Do not install replacement Node or
Supabase binaries into `.tools/`.

For manual local Supabase inspection from the repo root:

```bash
supabase start
supabase status
```

Use the scripted `RESET_DB=true ... scripts/verify_supabase_local.sh` form when
you actually intend to run `supabase db reset`.

`supabase db reset` must complete through:

```text
20260702195915_unique_user_state_snapshot_period.sql
```

Expected local reset notices include skipped legacy CamelCase tables and
already-existing canonical tables. Those notices are normal. Errors are not.

Do not assume the live remote database state from migrations alone. Inspect it
through the Supabase dashboard, CLI, or connector before making claims about the
remote project.

Do not run destructive Supabase commands such as `supabase db reset` unless the
user explicitly asks for that operation or is actively working with you on local
database reset/debugging. Use the scripted form when a local reset is intended:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

Never paste or commit Supabase keys. For the Flutter app, only the local anon key
belongs in `.env`. Never use the service role key in the client.

## Local App Workflow

Create a local `.env` from `.env.example`:

```bash
cp .env.example .env
```

For local Supabase-backed testing:

```env
APP_ENV=development
USE_MOCK_DATA=false
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<local anon key from supabase status>
AI_SERVICE_BASE_URL=http://localhost:8000
```

Start Flutter:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/start_frontend.sh
```

Prefer the repo script over ad hoc Flutter commands. If Flutter is not on
`PATH`, ask for or infer a `FLUTTER_BIN` override instead of hard-coding a
machine-specific path in source files.

Open:

```text
http://127.0.0.1:7357
```

Manual smoke test after schema or Supabase-client changes:

- Register or sign in.
- Complete onboarding.
- Save a daily check-in.
- Save a quick mood check-in.
- Open dashboard.
- Open notifications.
- Send a coach message.

The browser smoke path is automated through Playwright in `scripts/e2e_web.sh`.
The widget tests still cover the faster guest auth, guest onboarding, and guest
quick mood check-in path. See `docs/verification.md` before changing or
claiming E2E coverage.

## Verification Commands

Run these after relevant changes:

```bash
cd apps/mobile
flutter analyze
flutter test
```

If Flutter is not on `PATH`, use:

```bash
cd apps/mobile
/home/gregor/tools/flutter/bin/flutter analyze
/home/gregor/tools/flutter/bin/flutter test
```

From the repo root:

```bash
python3 -m compileall services/ai_service/app
git diff --check
```

Or run the standard non-destructive verification bundle:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh
```

`scripts/verify.sh` runs shell syntax checks, Flutter dependency resolution,
Flutter analysis, Flutter widget tests, Python compile checks, and
`git diff --check`.

For docs and shell scripts:

```bash
bash -n scripts/start_frontend.sh
```

If Supabase migrations changed and a local reset is intended, use the scripted
reset form:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

Do not run a raw `supabase db reset` unless the user explicitly asks for that
operation or you are already debugging the local reset workflow with them.

For the local Supabase-backed preflight workflow:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

For the local Supabase reset workflow:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/verify_supabase_local.sh
```

For browser E2E:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter bash scripts/e2e_web.sh
```

Browser E2E also requires real Ubuntu Node.js 20+ and npm. Windows `npm`/`npx`
shims are not sufficient inside this WSL project.
If the interactive Ubuntu shell has Node/Supabase through nvm but the agent
shell cannot find them, run with the real nvm bin directory on `PATH` or set
`NODE_BIN`; keep using the actual installed tools.

For browser E2E with a fresh local database:

```bash
RESET_DB=true \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
bash scripts/e2e_web.sh
```

If browser E2E fails because the local database is behind repository migrations,
prefer applying pending local migrations with
`HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local`
before using `RESET_DB=true`. Use reset only when a fresh local database is
intended.

The E2E script may read the local service-role key from `supabase status -o env`
for FastAPI backend settings plus Node-side local test user creation and
database assertions. Never pass the service-role key into Flutter, browser code,
docs examples, or chat output.

## Documentation Requirement

Documentation must stay current. After any significant change to schema,
startup flow, configuration, architecture, environment variables, deployment, or
agent workflow, update the relevant docs in the same change.

At minimum:

- Schema or RLS changes: update `docs/supabase-current-state.md`.
- Backend/frontend boundary changes: update `docs/architecture.md`.
- Local setup or command changes: update `docs/local-dev.md`.
- Agent workflow or safety changes: update this `AGENTS.md`.
- Verification workflow changes: update `docs/verification.md` and link any
  changed commands from `docs/local-dev.md`.

Do not leave future agents to rediscover changed setup steps from terminal
history.

## Environment And Secrets

`.env` is intentionally ignored by git. Agents may technically read it in the
local workspace if needed to run the project, but must treat it as secret
material:

- Do not print `.env` contents in chat or logs.
- Do not commit `.env`.
- Do not copy keys into docs.
- Prefer asking the user to paste redacted command output.
- If a value is needed for a command, pass it through the existing scripts or
  environment, not through committed files.

Local Supabase anon keys are acceptable in `.env` for local development only.
Production service-role keys must never be used in the Flutter app.

## Working Tree Safety

This repo may contain user changes. Do not revert unrelated files. In
particular, dependency lockfiles may change after running package managers; call
that out clearly instead of silently discarding it.

Before broad edits, inspect `git status --short`. If a file already has changes,
read it carefully and work with those changes instead of overwriting them.
