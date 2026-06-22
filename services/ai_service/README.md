# MyLifeGraph AI Service

FastAPI service boundary for recommendation and future ML workflows.

## Current Status

- The service is optional for the default mock-data Flutter preview.
- `/v1/health` returns a simple health response.
- `/v1/recommendations` and `/v1/recommendations/generate` expose the
  authenticated backend v1 recommendation contract.
- With backend Supabase settings configured, bearer tokens are verified through
  Supabase Auth, recent user-scoped app data is loaded from canonical
  snake_case tables, deterministic recommendations are verified, and accepted
  results are persisted to `recommendations`.
- The service does not call LLMs, OpenRouter, local models, vector search, or
  background jobs.

## Setup

```bash
cd services/ai_service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Windows PowerShell:

```powershell
cd services\ai_service
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

```bash
uvicorn app.main:app --reload --port 8000
```

OpenAPI docs are available in non-production environments:

```text
http://localhost:8000/docs
```

## Endpoints

```bash
curl http://localhost:8000/v1/health
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

## Environment

The service reads `.env` from `services/ai_service`:

```env
APP_ENV=development
API_PREFIX=/v1
ALLOWED_ORIGINS=http://127.0.0.1:7357,http://localhost:7357
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_TIMEOUT_SECONDS=10
```

Do not expose the Supabase service-role key to the Flutter app. It belongs only
in the backend service environment.

JWT verification is isolated in the FastAPI auth dependency. Tests inject fake
verifiers and repositories, so production or remote Supabase credentials are not
required for the unit test suite.
