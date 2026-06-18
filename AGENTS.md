# Agent Instructions

These instructions are for coding agents working in this repository. They are
repo-local and must not depend on any user-private Codex skill or machine-local
profile configuration.

## Start Here

Read these files before making changes:

1. `README.md`
2. `docs/local-dev.md`
3. `docs/architecture.md`
4. `docs/supabase-current-state.md` when touching Supabase, auth, data sources,
   or migrations

## Running The Project

Use the repo script:

```bash
scripts/start_frontend.sh
```

Default URL:

```text
http://127.0.0.1:7357
```

Default local mode is mock data plus guest auth. Tell users to choose
**Continue as guest** unless they provide Supabase credentials.

If Flutter is not on `PATH`, ask for or infer a `FLUTTER_BIN` override instead
of hard-coding a machine-specific path.

## Environment

Use `.env.example` as the template. Never commit real Supabase credentials.

Important values:

- `USE_MOCK_DATA=true` for the reliable local path.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` enable the Flutter Supabase client.
- `AI_SERVICE_BASE_URL=http://localhost:8000` points to the FastAPI service.

## Supabase Rules

- Do not assume the live remote database state from migrations alone.
- Do not run destructive Supabase commands such as `supabase db reset` unless
  the user explicitly asks for that operation.
- Read `docs/supabase-current-state.md` before editing migrations.
- The repo currently has two schema families: app-facing CamelCase tables and
  newer snake_case life-graph tables.

## Verification

For Flutter changes:

```bash
cd apps/mobile
flutter analyze
flutter test
```

For AI service changes:

```bash
cd services/ai_service
python -m compileall app
```

For docs and scripts:

```bash
bash -n scripts/start_frontend.sh
```

## Working Tree Safety

This repo may contain user changes. Do not revert unrelated files. In
particular, dependency lockfiles may change after running package managers; call
that out clearly instead of silently discarding it.
