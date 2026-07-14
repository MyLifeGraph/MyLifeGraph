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
- Phase 3 snapshot inputs include explicit `habit_logs` outcomes and
  `focus_sessions`. Bounded habit/focus summaries, counts, minutes, and evidence
  use deterministic, stably ordered 1,000-row pagination through the complete
  window and remain additive; they do not change `summary.daily_state`,
  `signals.daily_state`, or the `snapshot-aggregator-v1` marker.
- FastAPI defines the strict, ranking-independent `executable-action-v1` model
  in parser parity with Flutter. Both reject unknown top-level/metadata fields,
  null/non-object metadata, explicit-null metadata fields, numeric coercion,
  invalid ISO dates, command/kind/target/linkage mismatch, unsupported routes,
  and per-command metadata leakage. `review_plan` remains explicitly
  unavailable. See
  `../../docs/phase-3-executable-actions-contract.md`.
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
- Recommendation context ignores terminal done/cancelled/archived tasks for
  overdue, workload, and focus-pressure candidates.
- `GET /v1/briefings/today` reads one persisted `daily-briefing-v1` decision;
  deliberate `POST /v1/briefings/generate` refreshes its exact profile-local
  date. Normal reads remain generation-free.
- Phase 7 extends the protected scheduled boundary to prepare daily snapshots
  and briefings for onboarded non-guest profiles. One UTC run instant determines
  each profile-local date; current pairs are write-free, while missing or stale
  state converges on the existing daily identities with isolated per-user stage
  results.
- Phase 8 exposes read-only completed-week review GETs and deliberate
  deterministic review generation under `weekly-review-v1`.
- Phase 9 exposes one optional `calendar-import-v1` `.ics` connection. Consent,
  file import, stable paginated event reads, disconnect, and local imported-data
  deletion are authenticated and owner scoped. One fingerprint-free backend
  request registry prevents UUID reuse across owners or operations. It has no
  provider credential, URL fetch, provider write, background sync, or LLM
  processing.
- Phase 10 exposes authenticated capability, deliberate response,
  history/delete, and explicit memory-selection contracts. Standard tests use
  the deterministic fake provider. The only real-model adapter is the strictly
  development-only `local_codex_oauth`, which invokes the current Linux user's
  manually authenticated Codex CLI without an application API key, tools, or
  model fallback. Only a deliberate Coach send may call it; all other service
  workflows remain deterministic/no-model. It is not a production provider.
  See `../../docs/phase-10-controlled-coach-plan.md`.
- `/v1/account/profile`, `/v1/account/export`, and `/v1/account` expose the
  bearer-derived V1 timezone, bounded JSON portability, and confirmed permanent
  deletion boundary. The client never supplies an owner id. See
  `../../docs/v1-account-controls-contract.md`.
- `POST /v1/notifications/{notification_id}/actions` exposes strict,
  bearer-derived `notification-lifecycle-v1` read/unread/dismiss commands
  through a retry-safe service-role RPC. It does not generate or deliver
  notifications. See `../../docs/notification-lifecycle-v1-contract.md`.
- The repository contains no deployed cron, background worker, Phase 7
  notification sender, vector search, autonomous agent, or deployable LLM
  provider.

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

Phase 3 action facts remain separate from Daily State. Snapshot summary and
signals expose completed/skipped habit outcomes plus focus
active/completed/abandoned counts and planned/actual minutes with bounded
evidence. Adding those rows must not alter the same capture inputs' mode,
quality, risks, or reasons. Focus repository reads use a broadened UTC range;
aggregation prefers valid persisted `metadata.entry_date` and falls back to
the UTC calendar date of `started_at` only for legacy/invalid metadata, matching
Flutter. Successful or exactly reconciled Flutter task/habit/focus writes
request the persisted target date's refresh best-effort. Habit outcome/undo
captures one stable target date, while focus transitions use the persisted
start date. The service does not generate recommendations during these writes.

Read today's persisted briefing without side effects:

```bash
curl http://localhost:8000/v1/briefings/today \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Deliberately generate or refresh it:

```bash
curl -X POST http://localhost:8000/v1/briefings/generate \
  -H 'Authorization: Bearer <supabase_access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"force":false}'
```

`force=false` returns a current row unchanged and prepares missing or stale
state. `force=true` deliberately recomputes the same `(user_id, briefing_date)`
identity. Dashboard normal load uses GET only.

Scheduler-triggered daily preparation uses a backend-only token and never
belongs in Flutter or browser runtime configuration:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <scheduled_refresh_token>' \
  -H 'Content-Type: application/json' \
  -d '{"window_days":7,"limit":100,"include_recommendations":false}'
```

The endpoint captures one UTC `run_at`, derives each eligible profile's local
`briefing_date`, and reports per-user snapshot, briefing, and failure-stage
outcomes. It generates a missing snapshot, reuses an existing snapshot when only
the briefing is missing, refreshes a stale briefing against its exact source,
and performs no write for a current pair. `target_date` is available only as an
explicit backfill override.

A privileged operational retry can be narrowed to at most 20 eligible profiles:

```bash
curl -X POST http://localhost:8000/v1/scheduled/daily-refresh \
  -H 'X-Scheduled-Refresh-Token: <scheduled_refresh_token>' \
  -H 'Content-Type: application/json' \
  -d '{"profile_ids":["11111111-1111-4111-8111-111111111111"],"window_days":7,"limit":1,"include_recommendations":false}'
```

The filter never bypasses onboarding or guest exclusion. Failures are isolated
per profile and identify `profile_date`, `snapshot`, `briefing`, or optional
`recommendations` as the stage. Recommendation generation is off by default;
explicit `include_recommendations=true` remains deterministic and forces LLM
wording off. Scheduled snapshot/briefing preparation never calls an LLM. This is
an invocable backend endpoint, not evidence of deployed cron or notifications.

Read Phase 8 review state without generation, or deliberately generate the
latest completed profile-local ISO week:

```text
GET  /v1/weekly-reviews/latest
GET  /v1/weekly-reviews/{period_key}
POST /v1/weekly-reviews/generate
```

Phase 9 calendar import uses these bearer-authenticated endpoints:

```text
GET    /v1/calendar-integrations
POST   /v1/calendar-integrations/connections
POST   /v1/calendar-integrations/connections/{connection_id}/imports
GET    /v1/calendar-integrations/connections/{connection_id}/events
POST   /v1/calendar-integrations/connections/{connection_id}/disconnect
DELETE /v1/calendar-integrations/connections/{connection_id}/imported-data?request_id=<uuid>
```

Create requires the exact `calendar-import-consent-v1` read/store consent.
Creating a connection never imports. Import accepts one stable request id and a
bounded UTF-8 `calendar_text`; the same exact request replays without applying
events again only while that import remains connected/current. GET is
side-effect free. Disconnect retains the local read-only copy; delete is a
separate body-free post-disconnect local operation and never changes
`schedule_items` or a source calendar. Reusing any calendar request UUID across
an owner, connection, or lifecycle operation returns conflict. See
`../../docs/phase-9-calendar-import-contract.md`.

Phase 10 Coach uses these bearer-authenticated endpoints:

```text
GET    /v1/coach/capabilities
POST   /v1/coach/respond
GET    /v1/coach/history
DELETE /v1/coach/history
GET    /v1/coach/memories
POST   /v1/coach/memories/{memory_id}/selection
DELETE /v1/coach/memories/{memory_id}/selection
```

Stored Inbox lifecycle uses one bearer-authenticated endpoint:

```text
POST /v1/notifications/{notification_id}/actions
```

The strict request contains one UUID, `mark_read|mark_unread|dismiss`, and the
loaded row's aware `expected_updated_at`. Exact replay is mutation-free;
request-id reinterpretation or stale state is `409`, a foreign row is the same
owner-safe `404`, and two unresolved persistence attempts are explicit `502`.
Direct authenticated Notification DML remains forbidden.

V1 account controls are authenticated and owner-derived:

```text
PATCH  /v1/account/profile
GET    /v1/account/export
DELETE /v1/account
```

The delete body must be exactly `{"confirmation":"DELETE"}`. The same verified
bearer session must also contain recognized, non-refresh Supabase `amr`
authentication evidence no more than 15 minutes old; missing, stale, invalid,
refresh-only, or materially future evidence fails closed with `403` before the
delete service runs. Do not exercise deletion against anything except an
intentionally disposable account.

Capability, history, and memory operations never call a model. Respond accepts
only strict `coach-request-v1` with one UUID, a trimmed message of at most 2,000
Unicode code points, and `context_scope=today`. It builds at most 32 KiB of
owner-scoped current context, returns strict `coach-response-v1`, and exposes
exact source counts/freshness plus provider/model/prompt/context provenance.
Completed same-id replay does not call the provider again; changed input with
the same id conflicts; failed/deleted ids remain terminal. One owner has at most
one live claim and the default retained attempt limit is 20 per profile-local
day.

Memory selection is explicit, separate from memory content/Setup ownership, and
capped at eight eligible rows. Conversation deletion is body-free: it removes
message/response content but retains content-free request tombstones and
append-only usage events, so it neither resets the daily limit nor permits
request-id reinterpretation. Coach returns at most one review-only text
suggestion and has no mutation command.

## Environment

The service reads `.env` from `services/ai_service`:

```env
APP_ENV=development
USE_MOCK_DATA=true
API_PREFIX=/v1
ALLOWED_ORIGINS=http://127.0.0.1:7357,http://localhost:7357
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_TIMEOUT_SECONDS=10
SCHEDULED_REFRESH_TOKEN=
COACH_PROVIDER=disabled
COACH_FAKE_PROVIDER_ENABLED=false
LOCAL_CODEX_ENABLED=false
LOCAL_CODEX_BIN=codex
LOCAL_CODEX_MODEL=gpt-5.5
LOCAL_CODEX_TIMEOUT_SECONDS=45
LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20
LOCAL_CODEX_GLOBAL_CONCURRENCY=2
```

Do not expose the Supabase service-role key to the Flutter app. It belongs only
in the backend service environment. Keep `SCHEDULED_REFRESH_TOKEN` backend-only
as well; it authorizes scheduler-triggered refresh runs.

Coach is off by default. Standard automation may explicitly use
`COACH_PROVIDER=fake` with `COACH_FAKE_PROVIDER_ENABLED=true`. The real local
adapter additionally requires `APP_ENV=development`, `USE_MOCK_DATA=false`,
`COACH_PROVIDER=local_codex_oauth`, `LOCAL_CODEX_ENABLED=true`, valid backend
Supabase settings, an executable CLI, and an existing login for the FastAPI
Linux user. An empty `LOCAL_CODEX_MODEL` truthfully selects the CLI default;
otherwise the exact configured model is requested with no fallback.

Codex OAuth remains private CLI state; the service may run sanitized
help/feature/login capability commands but must never read or copy an auth file.
Its child environment is allowlisted and excludes the Supabase service-role key
and every other application secret. The adapter is rejected outside development
and is not a deployment design.

From the repository root, `scripts/start_local_stack.sh` is the supported local
supervisor for Supabase, FastAPI, Flutter, and the scheduled preparation loop.
It derives the local service-role key and a run-scoped scheduler token only in
memory. The loop invokes `python -m app.ops.local_daily_refresh --loop`, accepts
only a loopback FastAPI URL, disables redirects/proxies, and prints only
aggregate counts. Use `python -m app.ops.local_daily_refresh --once` inside an
already configured backend environment for an explicit one-shot run.

The Setup apply RPC comes from
`20260710180000_atomic_intake_v1_setup_apply.sql`. Execute is revoked from
`public`, `anon`, and `authenticated` and granted only to `service_role`. Its
only legacy cleanup exception removes the exact unmarked onboarding placeholder
`Math` / `Room 204` / Monday `08:15`-`09:45`; all other unmarked or manual
schedule rows remain outside Setup ownership.

Phase 3 client and snapshot behavior requires
`20260711120000_phase_3_executable_action_schema.sql`. It adds bounded task
estimates and terminal timestamps, authoritative completed/skipped habit-log
status, and the real focus lifecycle/link fields plus database constraints and
ownership/transition guards. Habit outcomes lock/revalidate active weekday
eligibility; focus target validation locks the selected task/habit row; every
terminal focus update is rejected; linked-target deletion is restricted; and
exact lifecycle/one-active constraints remain database-owned. Missing legacy
focus entry dates are backfilled from the UTC date of `started_at`, matching the
Flutter/FastAPI fallback.
Existing table RLS/grants remain unchanged. Positive legacy habit values
normalize to completion; the migration rejects ambiguous rows with missing
status and `value <= 0` instead of inventing skip intent.

Controlled Coach persistence requires
`20260713200000_phase_10_controlled_coach.sql` plus
`20260713213000_phase_10_coach_lock_order_guard.sql`, followed by
`20260713220000_phase_10_coach_safety_provenance_guard.sql`,
`20260713223000_phase_10_profile_privilege_guard.sql`,
`20260713224500_phase_10_role_authority_guard.sql`, and
`20260713230000_phase_10_onboarding_eligibility_guard.sql`. The first adds backend-owned
`coach_requests`, `coach_usage_events`, and `coach_memory_selections`; exact
request-linked V1 message pairs; hardened forced RLS/grants for messages and
memories; and service-role-only atomic claim, complete, fail, selection, and
history-delete RPCs. Apply it non-destructively with `supabase migration up
--local` when pending. The guard keeps those public signatures and makes
claim/complete/fail take the same owner-first advisory lock as history delete.
The additive guards persist exact provider-call truth for safety redirects,
make profile identity and onboarding eligibility backend-owned, remove legacy
`"User"` role fallback and authenticated profile deletion, and retain
service-role/atomic Intake authority. Real local PostgreSQL parallel
claim/completion/deletion smokes completed on 2026-07-13 without deadlock or
timeout and converged on the expected state.

Permanent account deletion requires
`20260713233000_v1_account_delete.sql`. Its exact-confirmation RPC is
service-role-only, removes the owner's restrict-linked focus history before
deleting `auth.users`, and verifies the canonical profile/product cascade in
the same transaction. FastAPI additionally requires session-bound Supabase JWT
`amr` sign-in evidence no more than 15 minutes old before invoking that RPC; a
refresh-only or stale session receives `403` without a database mutation.

Stored-Inbox lifecycle requires
`20260714100000_notification_lifecycle_v1.sql`, followed by
`20260714110000_account_export_lifestyle_entries_grant.sql`. The latter adds
only the missing service-role `lifestyle_entries` read grant needed by the
existing Account Export V1 contract; the preceding privilege guard closes
unintended authority across every repo-owned product/ledger table: `anon` is
fail-closed, authenticated `TRUNCATE`/`REFERENCES`/`TRIGGER` is removed while
intended DML remains, backend projections stay read-only, and optional legacy
tables stay frozen. It also hardens future `postgres` public-table defaults,
prevents application and service roles from reusing the installed Auth trigger
functions without removing their triggers, and adds the Notification-ledger
child index plus non-validating timestamp-order checks for new or updated rows.

JWT verification is isolated in the FastAPI auth dependency. Tests inject fake
verifiers and repositories, so production or remote Supabase credentials are not
required for the unit test suite. Intake tests cover authenticated read/save,
blank optional materialization, candidate cadence validation, request replay,
stale revision conflicts, convergent retry/edit identities, lifecycle removal,
and preservation of non-Setup-owned rows. Phase 3 tests cover strict executable
action parser parity, explicit habit/focus snapshot summaries and local-date
filtering, preservation of Phase 2 Daily State behavior, and terminal-task
exclusion from recommendation pressure. Phase 4 through Phase 7 coverage adds
strict persisted briefings, profile-local scheduled dates, missing/stale/current
write behavior, bounded targeted retry, per-user failure isolation, and default
no-recommendation/no-LLM preparation. Phase 8/9 coverage adds weekly-review
freshness/proposals plus strict calendar consent, retry-safe `.ics` identity,
timezone/all-day/recurrence/cancellation handling, stable event pagination,
disconnect/delete separation, schedule preservation, and RLS ownership. A
documented test suite alone is not a pass claim. The combined Phase 3 through
Phase 9 browser journey passed non-destructively in the 2026-07-13 Phase 9
implementation checkout; run it again after later changes to establish their
current result.

Phase 10 tests use fake services/providers/process runners. They do not require
Codex, OAuth, a subscription, or network access. A focused Phase 10 browser
rerun and the subsequent full non-destructive local-Supabase journey passed in
the 2026-07-13 current checkout with the deterministic fake provider. The full
run reported `E2E browser smoke passed for e2e-1783947134@example.test`; see
`../../docs/verification.md` for the diagnostic-only focused rerun command.
The separate synthetic-context live smoke is skipped by default and runs only
after explicit local-provider setup and login:

```bash
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

On 2026-07-13 that smoke completed with the explicitly requested `gpt-5.5`
model (`1 passed`), with no fallback and no answer, prompt, or raw event stream
logged. This records only the tested machine/CLI/login/account and is not a
deployable-provider or another-developer availability claim. The browser
results likewise establish neither remote Supabase nor production readiness.

The separate authenticated product-path acceptance also passed on this machine
on 2026-07-13: Flutter Web authenticated an existing onboarded local principal,
this service reported ready `local_codex_oauth` with explicit `gpt-5.5`, and one
deliberate send returned and persisted a strict `coach-response-v1` with model
provenance and `provider_called=true`. No fake provider or fallback was enabled,
and the harness logged no question, assembled prompt, answer, raw event stream,
stderr, account identity, path, token, `.env` value, or Supabase key. The CLI
did not emit a reliable selected-model field, so `model_reported` remained
`null`. Another Linux user's independent clone/login run remains unverified.

Run service tests with:

```bash
pytest
```
