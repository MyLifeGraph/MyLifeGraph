# Backend v1 Implementation Plan

This document defines the smallest safe first backend implementation slice for
MyLifeGraph. It is a planning document only. It does not introduce backend code,
Flutter code, migrations, dependencies, or runtime behavior by itself.

## v1 Goal

Backend v1 establishes FastAPI as the authenticated intelligence boundary for
recommendations while keeping Supabase/Postgres as the source of truth and
Flutter as the main product surface.

The v1 slice must:

- Authenticate Flutter requests with the current Supabase session access token.
- Read recent user data from existing canonical snake_case Supabase tables.
- Generate deterministic recommendation candidates.
- Verify candidates for user scope, evidence, category, priority, confidence,
  dedupe fingerprint, and stale or duplicate recommendations.
- Persist verified recommendations in the existing `recommendations` table.
- Return recommendations to Flutter through FastAPI, not direct Flutter reads
  from Supabase.
- Keep mock and guest mode working in Flutter.
- Keep all real LLM usage disabled.

## v1 Non-Goals

v1 explicitly does not include:

- Real LLM calls.
- OpenRouter integration.
- Local model integration.
- Vector search.
- Background jobs.
- Autonomous or multi-agent backend workflows.
- Weekly planning implementation.
- Weekly review implementation.
- Coach chat implementation.
- LLM-assisted memory extraction.
- Memory writes.
- Full-history prompting.
- LLM calls on dashboard load.
- LLM calls on recommendation fetch.
- Broad schema migrations.
- Any schema migration unless later explicitly approved.

## Endpoint Contracts

All v1 endpoints live under the configured API prefix, currently `/v1`.

### `GET /v1/health`

Public health check.

Response:

```json
{
  "status": "ok"
}
```

### `GET /v1/recommendations`

Returns persisted recommendations for the authenticated user. This endpoint must
not generate recommendations automatically.

Authentication:

- Required: `Authorization: Bearer <supabase_access_token>`.
- `user_id` is derived from the verified token or Supabase user lookup.
- Request query/body `user_id` values are not accepted.

Response:

```json
{
  "items": [
    {
      "id": "uuid",
      "title": "Protect a morning focus block",
      "reason": "Recent focus evidence supports a protected planning block.",
      "action_label": "Schedule focus block",
      "category": "focus",
      "priority": "medium",
      "confidence": 0.82,
      "generated_at": "2026-06-22T10:15:00Z",
      "metadata": {
        "rule_id": "focus_protection",
        "fingerprint": "deterministic-v1:focus_protection:2026-W26:abc123",
        "evidence_refs": [],
        "period_key": "2026-W26",
        "source_engine_version": "deterministic-v1",
        "invalidation_dependencies": [],
        "deterministic_scores": {},
        "model": null
      }
    }
  ],
  "needs_generation": false,
  "generated_at": "2026-06-22T10:15:00Z",
  "period_key": "2026-W26",
  "stale_reason": null
}
```

Freshness policy:

- `period_key` is the current ISO week, for example `2026-W26`.
- Recommendations are stale if the newest generated recommendation is older
  than 7 days.
- Recommendations are stale if their metadata period is not the current ISO
  week.
- If no active persisted recommendations exist, `needs_generation` is `true`.

Allowed `stale_reason` values for v1:

- `null`
- `missing`
- `older_than_7_days`
- `period_mismatch`

### `POST /v1/recommendations/generate`

Generates deterministic recommendation candidates for the authenticated user,
verifies them, persists accepted candidates, and returns the current
recommendation object response.

Authentication:

- Required: `Authorization: Bearer <supabase_access_token>`.
- `user_id` is derived from the verified token or Supabase user lookup.
- Request body `user_id` values are not accepted.

Request body:

```json
{}
```

Response:

Same object shape as `GET /v1/recommendations`.

Flutter must not auto-call this endpoint on every dashboard load or every
recommendation fetch. It may be wired later to an explicit refresh action or a
controlled app workflow.

## Auth And JWT Plan

Flutter obtains the access token from the active Supabase session:

- Use the configured Supabase client.
- Read the current session.
- Extract `session.accessToken`.
- Attach it as `Authorization: Bearer <token>` for real FastAPI backend calls.

FastAPI uses a narrow auth dependency:

- Extract the `Authorization` header.
- Require the `Bearer` scheme.
- Validate the token through Supabase Auth user lookup or an isolated verifier
  abstraction.
- Derive `user_id` from the verified token/user.
- Reject missing, malformed, invalid, or expired tokens with `401`.
- Never trust `user_id` from request body, query parameters, or Flutter state.

Repository methods must require explicit `user_id`:

```python
async def list_recent_user_context(user_id: str) -> UserContext: ...
async def list_recommendations(user_id: str, period_key: str) -> list[...]: ...
async def upsert_recommendations(user_id: str, candidates: list[...]) -> list[...]: ...
```

Backend service-role access is allowed only after JWT verification. The
service-role key must stay in the FastAPI environment and must never be passed
to Flutter, browser code, docs examples, or chat output.

## Data Table Plan

Use existing canonical snake_case tables only.

Required v1 reads:

- `profiles` for user/profile existence checks if needed.
- `daily_logs` for recent sleep, mood, energy, stress, activity, focus, and
  reflection signals.
- `behavioral_events` for recent granular app and check-in signals.
- `recommendations` for existing recommendation freshness, duplicate checks,
  stale checks, and persisted output.

Optional read-only v1 context, only if trivial:

- `tasks` for active workload and near-deadline pressure.
- `schedule_items` for recurring schedule and focus-window context.
- `memory_entries` for existing context only.

v1 must not write to `memory_entries`.

No migration is planned for v1. `recommendations.metadata` carries all v1
recommendation provenance and dedupe fields.

## Deterministic Recommendation Rules

v1 categories are limited to:

- `focus`
- `recovery`
- `movement`
- `planning`

Rules should be deterministic, evidence-gated, and easy to test.

### `low_recovery_sleep`

- Category: `recovery`
- Evidence: at least two recent `daily_logs.sleep_hours` values below a chosen
  threshold, initially 6.5 hours, within the current period or trailing 7 days.
- Priority: `high` for three or more occurrences, otherwise `medium`.
- Confidence inputs: evidence count, recency, severity below threshold.

### `high_stress_low_energy`

- Category: `recovery`
- Evidence: at least three recent logs where stress is elevated and energy is
  low, or recent averages cross configured thresholds.
- Priority: `high` when stress severity is high, otherwise `medium`.
- Confidence inputs: sample size, average stress, average energy, recency.

### `focus_protection`

- Category: `focus`
- Evidence: low recent focus minutes, repeated context-switch style behavioral
  events, or open task pressure if `tasks` are included.
- Priority: `medium` by default, `high` only with strong deadline/workload
  evidence.
- Confidence inputs: evidence count, deadline proximity, recent focus trend.

### `movement_nudge`

- Category: `movement`
- Evidence: low `steps` or low `activity_level` for at least three recent logs.
- Priority: `low` or `medium`.
- Confidence inputs: evidence count, severity, recency.

### `planning_reset`

- Category: `planning`
- Evidence: missed or overdue tasks if `tasks` are included, or repeated
  reflection/check-in signals indicating planning friction.
- Priority: `medium`.
- Confidence inputs: evidence count, recency, task pressure.

Rules with insufficient evidence must produce no candidate.

## Metadata Contract

Each persisted v1 recommendation must include these fields in
`recommendations.metadata`:

```json
{
  "rule_id": "focus_protection",
  "fingerprint": "deterministic-v1:focus_protection:2026-W26:abc123",
  "evidence_refs": [
    {
      "table": "daily_logs",
      "id": "uuid",
      "field": "focus_minutes"
    }
  ],
  "period_key": "2026-W26",
  "source_engine_version": "deterministic-v1",
  "invalidation_dependencies": [
    "daily_logs.focus_minutes",
    "behavioral_events.event_type"
  ],
  "deterministic_scores": {
    "evidence_count": 3,
    "severity": 0.7,
    "recency": 0.9,
    "final": 0.82
  },
  "model": null
}
```

Fingerprint generation must be isolated behind a helper so it can later map to
a real indexed column without rewriting business logic.

The verifier must reject candidates that have:

- Missing or invalid `rule_id`.
- Missing `fingerprint`.
- Missing evidence.
- Category outside the v1 allowed set.
- Priority outside `low`, `medium`, `high`, `critical`.
- Confidence outside `0..1`.
- A duplicate active fingerprint.
- A stale period key.
- A `user_id` mismatch.

## Backend Module Structure

v1 should keep the backend small:

```text
services/ai_service/app/
  api/
    deps/
      auth.py
    routes/
      health.py
      recommendations.py
  clients/
    supabase.py
  core/
    config.py
  models/
    recommendations.py
    user_context.py
  repositories/
    recommendation_repository.py
    user_context_repository.py
  services/
    recommendation_engine.py
    recommendation_fingerprint.py
    recommendation_verifier.py
```

No real LLM provider is needed in v1. If a later implementation needs an
abstraction for tests or future extension, it should be limited to an interface,
`DisabledLLMProvider`, and `FakeLLMProvider`.

## Flutter Integration Plan

Flutter keeps the existing mock and guest behavior.

Real backend mode:

- Use Supabase-authenticated session state.
- Attach the Supabase access token to FastAPI requests.
- Read recommendations from `GET /v1/recommendations`.
- Map the object response `items` into the existing recommendation domain
  entities.
- Surface `needs_generation` only through an explicit product decision, not
  automatic dashboard generation.

Flutter must not:

- Read backend-generated recommendations directly from Supabase in v1.
- Receive or store the service-role key.
- Auto-call `POST /v1/recommendations/generate` on each dashboard load.
- Break `USE_MOCK_DATA=true` or local guest mode.

## Testing Strategy

Use the smallest verification level that covers each change.

Backend unit tests:

- Deterministic rule scoring.
- Ranking.
- Fingerprint generation.
- Duplicate detection.
- Stale checks.
- Verifier rejection cases.

FastAPI tests:

- Missing token returns `401`.
- Invalid token returns `401`.
- Verified token derives `user_id`.
- Request body cannot override `user_id`.
- `GET /v1/recommendations` returns the object contract.
- `POST /v1/recommendations/generate` persists only verified candidates.

Repository tests:

- Repository calls require explicit `user_id`.
- Queries are scoped to `user_id`.
- Service-role access is only used behind verified backend code paths.

Flutter tests only when Flutter files change:

- Mock/guest mode still returns mock recommendations.
- Real mode attaches bearer token.
- Real mode maps FastAPI object responses.

Verification commands:

- `python3 -m compileall services/ai_service/app`
- Backend tests once added.
- Flutter tests only for Flutter changes.
- `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh` before
  merging a complete slice.
- Supabase local preflight only when real Supabase integration changes.
- Browser E2E only when end-to-end app behavior changes.

## PR-Sized Sequence

### PR 1: Backend API and auth contract

- Add the narrow auth dependency.
- Add recommendation response DTOs with object response shape.
- Replace preview-oriented route design with v1 endpoint contracts.
- Use mocked auth/repositories in tests.
- No real Supabase persistence yet.
- No Flutter changes.

### PR 2: Deterministic engine and verifier

- Add user-context models.
- Add deterministic rules.
- Add fingerprint helper.
- Add verifier.
- Add unit tests for scoring, ranking, dedupe, and stale checks.

### PR 3: Supabase repository integration

- Add backend Supabase client boundary.
- Read recent canonical user context.
- Read and persist `recommendations`.
- Keep all repository methods explicitly scoped by verified `user_id`.
- Run local Supabase preflight if real Supabase calls are exercised.

### PR 4: Flutter read integration

- Attach Supabase access token to FastAPI requests in real backend mode.
- Read from `GET /v1/recommendations`.
- Preserve mock and guest mode.
- Do not auto-call generate.

### PR 5: Optional explicit generate UX

- Add an explicit refresh/generate action only if approved by product.
- Keep dashboard/recommendation loads read-only.
- Use browser E2E only if the end-to-end user behavior changes.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| Service-role misuse | Verify JWT first, derive `user_id` server-side, require explicit `user_id` in repositories, test cross-user isolation. |
| Duplicate recommendations | Use metadata fingerprint and active-status checks before insert. |
| Stale recommendations | Enforce current ISO week and 7-day freshness policy. |
| Weak or unverifiable evidence | Verifier rejects candidates without concrete `evidence_refs`. |
| Category drift | Restrict v1 categories to `focus`, `recovery`, `movement`, and `planning`. |
| Flutter guest/mock regression | Keep mock/guest branches first and test them when Flutter changes. |
| Scope creep | Keep LLM, vector, background, weekly, chat, and memory-write work out of v1. |
| Future fingerprint indexing | Isolate fingerprint generation so metadata storage can later move to an indexed column. |

## Exact First PR Scope

The first PR should establish only the backend API/auth contract.

In scope:

- Auth dependency skeleton.
- Token extraction and verifier abstraction.
- Verified user context object.
- Recommendation object response DTO.
- `GET /v1/recommendations` route contract.
- `POST /v1/recommendations/generate` route contract.
- Mocked repository/engine dependencies for route tests.
- Tests for auth and response shape.

Out of scope:

- Real Supabase repository implementation.
- Real deterministic rule implementation.
- Flutter changes.
- Migrations.
- Dependency additions unless tests cannot be written without explicit approval.

## Exact First PR Files Likely Touched

Likely files:

- `services/ai_service/app/core/config.py`
- `services/ai_service/app/api/routes/recommendations.py`
- `services/ai_service/app/models/recommendations.py`
- `services/ai_service/app/api/deps/__init__.py`
- `services/ai_service/app/api/deps/auth.py`
- `services/ai_service/tests/`

Possibly touched only if explicitly approved:

- `services/ai_service/requirements.txt`
- `services/ai_service/pyproject.toml`

## Exact First PR Verification Commands

For PR 1:

```bash
python3 -m compileall services/ai_service/app
pytest services/ai_service/tests
git diff --check
```

If backend test dependencies are not yet available and dependency changes are
not approved, run:

```bash
python3 -m compileall services/ai_service/app
git diff --check
```

## Decisions Already Resolved

- v1 uses no real LLM.
- Flutter reads recommendations through FastAPI, not directly from Supabase.
- `POST /v1/recommendations/generate` exists.
- Flutter does not auto-call generate on every dashboard or recommendation
  load.
- `GET /v1/recommendations` returns an object containing `items`,
  `needs_generation`, `generated_at`, `period_key`, and `stale_reason`.
- Freshness uses the current ISO week period key.
- Recommendations are stale if older than 7 days or not in the current period.
- JWT validation uses a narrow FastAPI auth dependency.
- FastAPI derives `user_id` from verified auth and never trusts request-provided
  `user_id`.
- Backend may use service-role access only after JWT verification.
- Service-role credentials never reach Flutter.
- v1 categories are `focus`, `recovery`, `movement`, and `planning`.
- v1 writes no memory entries.
- v1 does not implement weekly planning or weekly review.
- v1 does not include OpenRouter, local model, vector, or background job work.
- v1 does not create a schema migration unless later explicitly approved.
- `recommendations.metadata` carries rule, fingerprint, evidence, period,
  engine version, invalidation, deterministic score, and `model: null` fields.

## Decisions Still Open

- Whether `POST /v1/recommendations/generate` is developer-only at first or
  exposed through an explicit user refresh action.
- Exact numeric thresholds for each deterministic rule.
- Maximum number of recommendations returned by `GET /v1/recommendations`.
- Whether dismissed recommendations suppress the same fingerprint for only the
  current period or for a longer cooldown.
- Whether optional `tasks`, `schedule_items`, and `memory_entries` reads are
  included in v1 or deferred until after the first daily-log/event rules land.
- Whether JWT validation should start with Supabase Auth user lookup or a local
  isolated verifier implementation.
