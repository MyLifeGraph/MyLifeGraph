# MyLifeGraph AI Service

FastAPI service boundary for recommendation and future ML workflows.

## Current Status

- The service is optional for the default mock-data Flutter preview.
- `/v1/health` returns a simple health response.
- `/v1/intake/complete` exposes the authenticated Intake V1 completion
  workflow.
- `/v1/recommendations` and `/v1/recommendations/generate` expose the
  authenticated backend v1 recommendation contract.
- `/v1/snapshots/generate` creates or refreshes deterministic `daily` or
  `weekly` user-state snapshots from recent user-owned signals.
- With backend Supabase settings configured, bearer tokens are verified through
  Supabase Auth. Intake writes structured answers, onboarding state, goals,
  habits, schedule items, notification preferences, memory entries, and an
  onboarding snapshot. Recommendation endpoints load recent user-scoped app data
  from canonical snake_case tables, verify deterministic recommendations, and
  persist accepted results to `recommendations`. Snapshot generation reuses the
  existing `user_state_snapshots` table and does not require an LLM provider.
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

```bash
curl -X POST http://localhost:8000/v1/snapshots/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"scope":"daily","window_days":7}'
```

Use `"scope":"weekly"` to refresh the ISO-week snapshot for the target date.
The backend derives `user_id` from the bearer token and rejects request bodies
that include `user_id`.

Scheduler-triggered daily refresh uses a backend-only token and never belongs
in Flutter or browser runtime configuration:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <scheduled_refresh_token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":7,"limit":100,"include_recommendations":false}'
```

Set `include_recommendations` to `true` only for a deliberate deterministic
recommendation refresh pass. LLM wording remains disabled.

## Environment

The service reads `.env` from `services/ai_service`:

```env
APP_ENV=development
API_PREFIX=/v1
ALLOWED_ORIGINS=http://127.0.0.1:7357,http://localhost:7357
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_TIMEOUT_SECONDS=10
SCHEDULED_REFRESH_TOKEN=
```

Do not expose the Supabase service-role key to the Flutter app. It belongs only
in the backend service environment. Keep `SCHEDULED_REFRESH_TOKEN` backend-only
as well; it authorizes scheduler-triggered refresh runs.

JWT verification is isolated in the FastAPI auth dependency. Tests inject fake
verifiers and repositories, so production or remote Supabase credentials are not
required for the unit test suite.

Run service tests with:

```bash
pytest
```
