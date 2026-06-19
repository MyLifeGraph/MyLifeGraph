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
4. `docs/supabase-current-state.md` when touching Supabase, auth, data sources,
   or migrations

## Current State

MyLifeGraph is a Flutter web/mobile app with Supabase for auth and persistence
and a FastAPI service for future AI/recommendation workflows.

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

The migration
`supabase/migrations/20260618170000_create_canonical_app_schema.sql` creates the
canonical schema, applies RLS policies, and copies data from legacy CamelCase
tables when they exist. It intentionally does not drop legacy tables.

## Important Docs

- `docs/architecture.md` - system shape and current backend/frontend boundary.
- `docs/supabase-current-state.md` - canonical schema, legacy table mapping, and
  migration notes.
- `docs/local-dev.md` - local runbook for Flutter, Supabase, and FastAPI.
- `README.md` - high-level project overview.

## Local Supabase Workflow

Supabase CLI and Docker are required for local database testing.

From the repo root:

```bash
supabase start
supabase db reset
supabase status
```

`supabase db reset` must complete through:

```text
20260618170000_create_canonical_app_schema.sql
```

Expected local reset notices include skipped legacy CamelCase tables and
already-existing canonical tables. Those notices are normal. Errors are not.

Do not assume the live remote database state from migrations alone. Inspect it
through the Supabase dashboard, CLI, or connector before making claims about the
remote project.

Do not run destructive Supabase commands such as `supabase db reset` unless the
user explicitly asks for that operation or is actively working with you on local
database reset/debugging.

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

## Verification Commands

Run these after relevant changes:

```bash
cd apps/mobile
flutter analyze
flutter test
```

If Flutter is not on `PATH`, use:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/start_frontend.sh
/home/gregor/tools/flutter/bin/flutter analyze
/home/gregor/tools/flutter/bin/flutter test
```

From the repo root:

```bash
python3 -m compileall services/ai_service/app
git diff --check
```

For docs and shell scripts:

```bash
bash -n scripts/start_frontend.sh
```

If Supabase migrations changed and the CLI is available:

```bash
supabase db reset
```

## Documentation Requirement

Documentation must stay current. After any significant change to schema,
startup flow, configuration, architecture, environment variables, deployment, or
agent workflow, update the relevant docs in the same change.

At minimum:

- Schema or RLS changes: update `docs/supabase-current-state.md`.
- Backend/frontend boundary changes: update `docs/architecture.md`.
- Local setup or command changes: update `docs/local-dev.md`.
- Agent workflow or safety changes: update this `AGENTS.md`.

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
