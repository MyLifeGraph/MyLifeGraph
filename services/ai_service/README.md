# MyLifeGraph AI Service

FastAPI service boundary for recommendation and future ML workflows.

## Current Status

- The service is optional for the default mock-data Flutter preview.
- `/v1/health` returns a simple health response.
- `GET /v1/intake/setup` reads the newest typed Setup row: the latest pending
  row for exact retry/resume, otherwise the latest applied revision.
  `POST /v1/intake/complete` handles both authenticated Intake V1 completion
  and later Setup edits.
- `/v1/recommendations` and `/v1/recommendations/generate` expose the
  authenticated backend v1 recommendation contract.
- `/v1/snapshots/generate` creates or refreshes deterministic `daily` or
  `weekly` user-state snapshots from recent user-owned signals. Their additive
  `summary.daily_state` uses the `explainable-daily-state-v1` contract for
  capture freshness, data quality, bounded risks/reasons, evidence, provenance,
  and recovery-first Daily Mode classification.
- With backend Supabase settings configured, bearer tokens are verified through
  Supabase Auth. Setup uses idempotent request ids, optimistic revisions,
  pending/applied state, deterministic UUIDv5 record ids, and server ownership
  metadata to reconcile only explicit Setup-owned records. Blank optionals
  materialize nothing; named routines remain response-only candidates until
  cadence is confirmed; manual rows are preserved. The profile projection uses
  monotonic `profiles.setup_revision`, so an older worker cannot overwrite a
  newer applied Setup projection. The service passes the claimed canonical row
  into the service-role-only `apply_intake_v1_setup_revision` RPC. A per-user
  advisory transaction lock serializes workers, while preferences, Setup-owned
  goal/habit/schedule/memory reconciliation, the constant onboarding snapshot,
  applied intake state, and profile projection commit atomically. Recommendation
  endpoints load recent user-scoped app data from canonical snake_case tables,
  verify deterministic recommendations, and persist accepted results to
  `recommendations`. Snapshot generation reuses `user_state_snapshots`, keeps
  recommendation rules unchanged, excludes capture free text from Daily State,
  and does not require an LLM provider.
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
curl http://localhost:8000/v1/intake/setup \
  -H 'Authorization: Bearer <supabase_access_token>'
```

```bash
curl -X POST http://localhost:8000/v1/intake/complete \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"version":"intake-v1","request_id":"11111111-1111-4111-8111-111111111111","base_revision":0,"responses":{"primary_focus_areas":["focus"],"goals":[{"key":"22222222-2222-4222-8222-222222222222","title":"Protect focus time","status":"active"}],"friction_points":[],"weekday_shape":"school_or_work","best_energy_window":"morning","coaching_style":"direct","reminder_preference":{"enabled":true,"quiet_hours":{"starts_at":"21:00","ends_at":"07:00"}},"routines":[],"fixed_commitments":[],"calendar_connection_intent":"not_now"},"metadata":{"client":"curl"}}'
```

Reuse `request_id` for a retry. For a new edit, load Setup first, send the
current `revision` as `base_revision`, and generate a new request id. The backend
derives `user_id` only from the verified bearer principal.

If the read status is `pending`, keep its payload and `request_id` unchanged and
retry that operation; do not start a new edit until it is applied or reloaded.
Applied replays are idempotent and may only repair the newest revision's missing
profile projection.

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
that include `user_id`. Phase 1 capture supplies its explicit local
`target_date`; snapshot event reads include metadata, use a widened UTC window,
and prefer `metadata.entry_date` when assigning an event to that local day.

`window_days` controls the existing statistical summary window. Explainable
Daily State independently loads a fixed seven-day state window. It treats an
Evening capture on the target date or previous date as current and a Morning
capture only on the target date as current. Complete current Evening plus
Morning yields `current`; one usable current branch or current legacy numeric
input yields `partial`; older usable input yields `stale`; and no trusted input
yields `missing`. V2 rows are parsed strictly and never fall back to projected
numbers when their V2 marker or branch is malformed. Legacy numeric fallback is
used only when no V2 marker exists.

The source marker remains `snapshot-aggregator-v1`. Snapshot metadata adds
`daily_state_contract_version=explainable-daily-state-v1` and
`state_lookback_days=7`. The result stays additive under `summary.daily_state`
and `signals.daily_state`; no schema migration is required. Top-level
`summary.risk_flags` aliases the current Daily State codes,
`summary.window_risk_flags` retains statistics-window flags, and
`recommended_next_focus` follows recovery-first mode precedence.

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

The Setup apply RPC comes from
`20260710180000_atomic_intake_v1_setup_apply.sql`. Execute is revoked from
`public`, `anon`, and `authenticated` and granted only to `service_role`. Its
only legacy cleanup exception removes the exact unmarked onboarding placeholder
`Math` / `Room 204` / Monday `08:15`-`09:45`; all other unmarked or manual
schedule rows remain outside Setup ownership.

JWT verification is isolated in the FastAPI auth dependency. Tests inject fake
verifiers and repositories, so production or remote Supabase credentials are not
required for the unit test suite. Intake tests cover authenticated read/save,
blank optional materialization, candidate cadence validation, request replay,
stale revision conflicts, convergent retry/edit identities, lifecycle removal,
and preservation of non-Setup-owned rows.

Run service tests with:

```bash
pytest
```
