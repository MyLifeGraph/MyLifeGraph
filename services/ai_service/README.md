# MyLifeGraph AI Service

FastAPI service boundary for recommendation and future ML workflows.

## Current Status

- The service is optional for the default mock-data Flutter preview.
- `/v1/health` returns a simple health response.
- `/v1/recommendations/preview` returns placeholder recommendations.
- Supabase settings are defined but not yet used for real data access.

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
curl -X POST http://localhost:8000/v1/recommendations/preview \
  -H 'Content-Type: application/json' \
  -d '{}'
```

## Environment

The service reads `.env` from `services/ai_service`:

```env
APP_ENV=development
API_PREFIX=/v1
ALLOWED_ORIGINS=http://127.0.0.1:7357,http://localhost:7357
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
```

Do not expose the Supabase service-role key to the Flutter app.
