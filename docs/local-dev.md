# Local Development

This guide is written for a fresh clone. It avoids machine-specific paths and
does not assume any user-local Codex skills.

## Prerequisites

- Flutter SDK. Confirm with `flutter --version`.
- Python 3.11+ for the AI service and static web fallback.
- Optional: Supabase CLI and Docker for local Supabase work.

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

Recommendation preview:

```bash
curl -X POST http://localhost:8000/v1/recommendations/preview \
  -H 'Content-Type: application/json' \
  -d '{}'
```

## Supabase

Supabase is optional for mock mode. To work on local Supabase you need the
Supabase CLI and Docker:

```bash
supabase start
supabase db reset
```

Read `docs/supabase-current-state.md` first. The migrations currently do not
fully create every app-facing CamelCase table expected by the Flutter app.

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
```

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
