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
- `GET/PATCH /v1/learning/preferences` exposes the revisioned complete
  `learning-preferences-v1` state, and
  `POST /v1/learning/focus-reflections/clear` is the retry-safe confirmed bulk
  deletion boundary. Individual reflection CRUD remains owner-scoped through
  Supabase forced RLS.
- `GET /v1/insights/personal-patterns` returns side-effect-free
  `personal-patterns-v1` evidence from a fixed profile-timezone 90-day window.
  It shares strict Daily Capture V4/V5 sleep parsing with Daily State and
  Exam-Week Outlook. The parser validates container and branch identity together
  and accepts mixed V4-in-V5 only with explicit compatibility. It never calls a
  model and loads no behavioral evidence when analysis is disabled.
- `GET /v1/insights/sleep-recommendation` independently returns
  `sleep-recommendation-v1`. It recomputes a deterministic 90-day result with
  disabled, collecting, unstable, or ready status; a ready result requires at
  least 30 eligible Morning-plus-rated-Focus days and never persists or applies
  a sleep window. Morning inclusion uses the exact closed-open `captured_at`
  boundary and a valid observed Daily Log timestamp. Same-day and following-day
  wakes remain separate candidate groups and return `wake_day_offset=0|1`.
  Outward 15-minute duration rounding can represent a positive sub-15-minute
  source interval with a zero lower window boundary; generated model failures
  remain bounded data errors rather than untyped route failures.
  Disabled analysis returns before sleep or Focus history is loaded; invalid
  profile timezones map to the bounded `503` route problem.
- `/v1/snapshots/generate` creates or refreshes deterministic `daily` or
  `weekly` user-state snapshots from recent user-owned signals. Their additive
  `summary.daily_state` uses the `explainable-daily-state-v3` contract for
  capture freshness, data quality, bounded risks/reasons, evidence, provenance,
  and recovery-first Daily Mode classification. V3 removes Day Shape context,
  `constrained_capacity`, and the former Day-Shape gate for `push`; V1/V2 stays
  readable.
- Phase 3 snapshot inputs include explicit `habit_logs` outcomes and
  `focus_sessions`. Bounded habit/focus summaries, counts, minutes, and evidence
  use deterministic, stably ordered 1,000-row pagination through the complete
  window and remain additive; they do not change `summary.daily_state`,
  `signals.daily_state`, or the `snapshot-aggregator-v1` marker.
- Focus V2 exposes
  authenticated `GET /v1/focus/capabilities`,
  `GET /v1/focus/start-context/{source_kind}/{block_id}`, and
  `POST /v1/focus/sessions/start`,
  `POST /v1/focus/sessions/{session_id}/finish`, and
  `POST /v1/focus/sessions/{session_id}/abandon`. Manual starts remain
  compatible; scheduled starts bind one immutable Planner/Deadline block
  origin, use actual backend timestamps, check the complete Focus-plus-recovery
  interval, and never fall back to an unproven direct start. The capability
  read lets a mixed-version client retain legacy manual V1 behavior only when
  the backend explicitly lacks V2; auth, network, and server failures never
  trigger that downgrade. See
  `../../docs/phase-3-executable-actions-contract.md`.
- FastAPI defines the strict, ranking-independent `executable-action-v1` model
  in parser parity with Flutter. Both reject unknown top-level/metadata fields,
  null/non-object metadata, explicit-null metadata fields, numeric coercion,
  invalid ISO dates, command/kind/target/linkage mismatch, unsupported routes,
  and per-command metadata leakage. `review_plan` is a real authenticated
  navigation target for the read-only Weekly Review surface; dispatch never
  generates or applies a proposal. See
  `../../docs/phase-3-executable-actions-contract.md`.
- With backend Supabase settings configured, bearer tokens are verified through
  Supabase Auth. One FastAPI-lifespan-owned `httpx.AsyncClient` is reused for
  those Auth lookups and all Supabase REST repositories and is closed once at
  shutdown. One typed application composition root builds and shares the
  repository/service graph over that client; explicit router dependencies only
  select services from the graph. Tests override those dependency functions
  directly, without named service fields in app state. Missing configuration
  remains fail-closed, and unit tests may still inject verifiers, services,
  repositories, or direct short-lived clients. Setup uses idempotent request
  ids, optimistic revisions,
  pending/applied state, deterministic UUIDv5 record ids, and server ownership
  metadata to reconcile only explicit Setup-owned records. Blank optionals
  materialize nothing; named routines remain response-only candidates until
  cadence is confirmed; manual rows are preserved. The profile projection uses
  monotonic `profiles.setup_revision`, so an older worker cannot overwrite a
  newer applied Setup projection. The service passes the claimed canonical row
  into the service-role-only `apply_intake_v1_setup_revision` RPC. A per-user
  advisory transaction lock serializes workers, while Setup-owned
  Habit/schedule/Study/energy-memory reconciliation, the compact
  onboarding snapshot, applied intake state, and profile projection commit
  atomically. The current RPC has no Goal parameter, leaves notification
  preferences unchanged, and Setup completion generates no Recommendation. Recommendation
  endpoints load recent user-scoped app data from canonical snake_case tables,
  verify deterministic recommendations, and persist accepted results to
  `recommendations`. Snapshot generation reuses `user_state_snapshots`, keeps
  recommendation rules unchanged, excludes capture free text from Daily State,
  and does not require an LLM provider.
- API routes catch only their operation-specific service failures and delegate
  HTTP translation to typed, feature-owned modules under `app/api/problems`.
  Those mappings preserve the existing status, detail, header, and unexpected-
  error behavior; request-shape and security failures remain at their owning
  route or dependency. Concrete repository errors terminate at their owning
  service. Pure Daily Capture V4/V5 parsing and current-write validation lives in
  `app/contracts/daily_capture_v4.py`, avoiding repository-to-service
  dependencies and keeping saved compatibility branches readable by the same strict
  contract.
- Planner and Deadline service modules own I/O orchestration; deterministic
  overview, projection, availability, block, and serialization helpers live in
  `planner_builder.py` and `deadline_plan_builder.py`. Local Codex command
  composition is similarly separated from bounded subprocess lifecycle in
  `providers/bounded_process.py` and event/output validation in
  `providers/codex_events.py`. Existing service/provider import paths remain
  compatible for callers and tests.
- Recommendation context ignores terminal done/cancelled/archived tasks for
  overdue and workload candidates. Focus warnings use real terminal sessions
  and require at least three sessions plus two abandonments in 14 days; a short
  completed session is not automatically insufficient. Future Daily Log dates
  are excluded. Sleep uses valid V4 quality/target deviation and movement
  requires measured values; when two fields trigger on one date, evidence names
  the stronger normalized field. A deliberate refresh atomically replaces the
  prior current `new` set while retaining history.
- `GET /v1/briefings/today` reads one persisted `daily-briefing-v1` decision;
  deliberate `POST /v1/briefings/generate` refreshes its exact profile-local
  date. Normal reads remain generation-free. The visible Today surface instead
  uses read-only `GET /v1/today/overview-v2` for its streak, exact progress,
  timeline, Tasks, Habits, and confirmed Planner blocks. The V1 route remains
  available for existing clients; neither read removes the internal briefing
  contract or writes product state.
- Phase 7 extends the protected scheduled boundary to prepare daily snapshots
  and briefings for onboarded non-guest profiles. One UTC run instant determines
  each profile-local date; current pairs are write-free, while missing or stale
  state converges on the existing daily identities with isolated per-user stage
  results.
- Phase 8 exposes read-only completed-week review GETs and deliberate,
  facts-only deterministic review generation under `weekly-review-v2`. New or
  refreshed reviews always store an empty proposal array.
- Phase 9 exposes the strict `calendar-import-v2` projection for one optional
  `.ics` connection. Consent, file import, stable paginated event reads,
  disconnect, and local imported-data deletion are authenticated and owner
  scoped. Each import records its profile-timezone revision and planning status.
  One fingerprint-free backend request registry prevents UUID reuse across
  owners or operations. It has no provider credential, URL fetch, provider
  write, background sync, or LLM processing.
- Planner V1 exposes a read-only seven-day overview and detail plus explicit
  preference, Task/Habit proposal/confirm/cancel, and fixed-commitment commands
  under `/v1/planner`. Immutable previews use shared deterministic availability
  with Deadline Planner and reserve nothing until owner-locked confirmation.
  Setup recurring commitments may use optional inclusive `valid_from` and
  `valid_until` dates. Existing targets remain unscheduled; GETs never create
  revisions. When both the account choice and development pilot gate are on,
  mature Personal Learning timing softly precedes Setup timing only for new
  Task previews; all ordinary availability fallbacks remain. Calendar import
  remains optional and outside onboarding. See
  `../../docs/planner-v1-contract.md` and
  `../../docs/personal-learning-v1-contract.md`.
- Deadline Planner V1 exposes bearer-owned exam/assignment plan reads,
  workload/detail reads, and explicit proposal/confirmation/lifecycle commands
  under `/v1/deadline-plans`. The separate
  `GET /v1/deadline-plans/exam-week-outlook` is strictly read-only and compares
  ordinary availability with the newest valid Evening V4 sleep interval
  hypothetically protected. Assignments consume capacity without activating its
  watch/exam-week/overdue mode; no read creates a preview or changes a plan. See
  `../../docs/deadline-planner-v1-contract.md` and
  `../../docs/exam-week-outlook-v1-contract.md`.
  Planner overview and Exam-Week assembly are pure builders behind the
  asynchronous service facades. Planner and Deadline proposals cross their
  repository boundaries as validated composite write models rather than
  parallel raw dictionaries; the existing RPC JSON remains unchanged.
  The nested `assignment-series-v1` routes add finite weekly Assignment
  list/detail/proposal/confirm/cancel-future behavior. A shared template stages
  independent Deadline Plans, then one owner-locked RPC confirms the complete
  series; future-wide edits retain past/completed occurrences and replace the
  future scope.
- Phase 10 exposes authenticated free-question capability, streaming and
  non-streaming response, and mixed legacy/current history/delete contracts.
  Each V3 turn creates a fresh owner-only SQLite snapshot and gives the local
  agent exactly three required MCP tools: inspect, bounded immutable SQL, and
  isolated Python. FastAPI derives conservative snapshot-source coverage,
  actual trace, and provenance. Standard tests use the fake provider; the only
  real adapter is development-only
  `local_codex_oauth`, which requires `gpt-5.5` with Fast explicitly configured
  and never falls back. Current Flutter has no fixed mode, horizon, Focus,
  prompt, memory-selection, or structured-suggestion flow; readable V1/V2
  history remains compatible. It is not a production provider.
  See `../../docs/phase-10-controlled-coach-plan.md`.
- `PUT /v1/daily-capture/{entry_date}/{branch}` is the sole authenticated
  Capture writer. `daily-capture-write-v1` combines request replay with
  branch-local compare-and-swap and transactionally refreshes the Daily Log and
  `quick_check_in` event projection. Current strict branches are
  `daily-capture-v5`; complete V4 branches remain accepted for rolling clients.
  V5 Morning rejects `day_shape`, and neither a V4 rollout write nor an older
  opposite branch can downgrade an existing V5 container.
- `/v1/account/profile` and `/v1/account/preparation-budget` use strict V2
  request ids and independent expected revisions. `/v1/account/export` returns
  `account-export-v4`, and `/v1/account` remains the confirmed permanent
  deletion boundary. The client never supplies an owner id.
  See `../../docs/v1-account-controls-contract.md`.
- `POST /v1/notifications/{notification_id}/actions` exposes strict,
  bearer-derived `notification-lifecycle-v1` read/unread/dismiss commands
  through a retry-safe service-role RPC. It does not generate or deliver
  notifications. See `../../docs/notification-lifecycle-v1-contract.md`.
- `GET/PATCH /v1/notifications/settings` and
  `POST /v1/notifications/{notification_id}/delivery` expose the separate
  explicit foreground-delivery boundary. The protected daily refresh may
  create fixed deterministic/no-LLM rows with timezone, quiet-hour, category,
  cap, dedupe, and provenance guards. See
  `../../docs/notification-delivery-v1-contract.md`.
- The repository contains no deployed cron, production/background notification
  worker, push/system delivery, vector search, autonomous agent, or deployable
  LLM provider.

## Setup

```bash
cd services/ai_service
python -m venv .venv
source .venv/bin/activate
python -m pip install --require-hashes -r requirements-dev.txt
```

`pyproject.toml` owns the direct compatibility ranges.
`requirements.txt` is the committed, hashed runtime lock;
`requirements-dev.txt` is the committed, hashed runtime plus pytest/Ruff lock.
CI and release-style installs must consume the appropriate lock with
`--require-hashes`; they must not resolve directly from the open ranges. The
equivalent project extra `.[test]` is metadata for dependency authorship, not
the reproducible CI install path.

To update the locks deliberately, use Python 3.12 and the pinned generator:

```bash
python -m pip install pip-tools==7.5.1
PYTHON_BIN=python scripts/update_python_requirements.sh --upgrade
```

Run that command from the repository root, review all version changes, then run
the complete backend tests and fast verification. Omitting `--upgrade`
regenerates the current resolution without intentionally advancing compatible
packages. This keeps security and compatibility updates explicit instead of
freezing them indefinitely or changing them implicitly on every CI run.

Windows PowerShell:

```powershell
cd services\ai_service
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --require-hashes -r requirements-dev.txt
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
  -d '{"version":"intake-v1","request_id":"11111111-1111-4111-8111-111111111111","base_revision":0,"responses":{"weekday_shape":"school_or_work","best_energy_window":"morning","routines":[],"fixed_commitments":[]},"metadata":{"client":"curl"}}'
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
yields `missing`. V2–V5 capture rows are parsed strictly with friction and Day
Shape ignored; V4/V5 additionally validate branch compatibility and sleep-plan/
estimated-interval projections. A malformed structured marker or branch never
falls back to projected numbers. Legacy numeric fallback is used only when no
structured capture marker exists.
Current Morning `sleep_quality` is separate
from `sleep_hours`: a very low `1..10` estimate can select recovery despite
sufficient duration, and moderately low quality prevents `push`. Older V2
Morning branches without the additive field remain compatible.

The source marker remains `snapshot-aggregator-v1`. Snapshot metadata adds
`daily_state_contract_version=explainable-daily-state-v3` and
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

Read the current Today overview without side effects:

```bash
curl http://localhost:8000/v1/today/overview \
  -H 'Authorization: Bearer <supabase_access_token>'
```

The app uses the additive V2 read with confirmed Planner blocks and exact
scheduled-target selection:

```bash
curl http://localhost:8000/v1/today/overview-v2 \
  -H 'Authorization: Bearer <supabase_access_token>'
```

Personal Learning uses these bearer-authenticated contracts:

```text
GET    /v1/learning/preferences
PATCH  /v1/learning/preferences
POST   /v1/learning/focus-reflections/clear
GET    /v1/insights/personal-patterns
GET    /v1/insights/sleep-recommendation
```

Set `LEARNED_FOCUS_PLANNING_PILOT_ENABLED=true` in FastAPI and the matching
Flutter Dart define only for the development pilot. The account Planner switch
is still independent and default-off. Production Flutter builds stay
fail-closed.

Planner V1 uses these bearer-authenticated reads and deliberate commands:

```text
GET    /v1/planner/overview
GET    /v1/planner/preferences
PATCH  /v1/planner/preferences
GET    /v1/planner/action-plans/{plan_id}
POST   /v1/planner/action-plans/proposals
POST   /v1/planner/action-plans/{plan_id}/confirm
POST   /v1/planner/action-plans/{plan_id}/cancel
POST   /v1/planner/commitments
PATCH  /v1/planner/commitments/{commitment_id}
POST   /v1/planner/commitments/{commitment_id}/archive
```

Deadline Planner and its strictly read-only workload/outlook projections use:

```text
GET    /v1/deadline-plans
GET    /v1/deadline-plans/exam-week-outlook
GET    /v1/deadline-plans/workload
GET    /v1/deadline-plans/workload/{local_date}
GET    /v1/deadline-plans/{plan_id}
GET    /v1/deadline-plans/assignment-series
GET    /v1/deadline-plans/assignment-series/{series_id}
POST   /v1/deadline-plans/proposals
POST   /v1/deadline-plans/assignment-series/proposals
POST   /v1/deadline-plans/assignment-series/{series_id}/confirm
POST   /v1/deadline-plans/assignment-series/{series_id}/cancel-future
POST   /v1/deadline-plans/{plan_id}/confirm
POST   /v1/deadline-plans/{plan_id}/complete
POST   /v1/deadline-plans/{plan_id}/cancel
```

The outlook GET derives its owner only from the bearer principal and performs no
write. Planner and Deadline Planner proposals remain staged until their separate
confirmation command succeeds.

Read today's persisted internal briefing without side effects:

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
identity. Today normal load does not call either briefing route; it uses only
the overview GET above until a lazy supporting section is opened.

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
explicit backfill override and cannot be combined with notification generation.

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
wording off. `include_notifications=true` requests the exact current profile-
local day only; the local runner enables it every 15 minutes. Missing/stale
Phase 7 preparation remains eligible, but a fully current notification-only
target must already have active separate in-app consent. Database guards then
recheck consent/category/quiet/cap/dedupe outcomes. This is not evidence of
deployed cron, push, browser, Android, or background delivery.

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

Responses use `calendar-import-v2`. Create requires the exact
`calendar-import-consent-v1` read/store consent. Creating a connection never
imports. Import accepts one stable request id and a bounded UTF-8
`calendar_text`; the same exact request remains replayable without applying
events again after supersession, disconnect, deletion, or a profile-timezone
change. GET is side-effect free. Disconnect retains the local read-only copy;
delete removes event content but retains a bounded `deleted` import audit.
Neither changes `schedule_items` or a source calendar. Reusing any calendar
request UUID across an owner, connection, or lifecycle operation returns
conflict. See
`../../docs/phase-9-calendar-import-contract.md`.

Phase 10 Coach uses these bearer-authenticated endpoints:

```text
GET    /v1/coach/capabilities
POST   /v1/coach/respond
POST   /v1/coach/respond/stream
GET    /v1/coach/history
DELETE /v1/coach/history
```

`GET /context-options` and the memory-selection routes remain for pre-V3
clients only. Current Flutter does not call them. The newest compatible
fixed-mode rows retain paired
`controlled-coach-prompt-v3`/`coach-context-v3` provenance.

Stored Inbox lifecycle uses one bearer-authenticated endpoint:

```text
POST /v1/notifications/{notification_id}/actions
```

The strict request contains one UUID, `mark_read|mark_unread|dismiss`, and the
loaded row's aware `expected_updated_at`. Exact replay is mutation-free;
request-id reinterpretation or stale state is `409`, a foreign row is the same
owner-safe `404`, and two unresolved persistence attempts are explicit `502`.
Direct authenticated Notification DML remains forbidden.

Foreground notification settings and receipts use:

```text
GET   /v1/notifications/settings
PATCH /v1/notifications/settings
POST  /v1/notifications/{notification_id}/delivery
```

The PATCH requires dedicated consent, a UUID request identity, and the loaded
settings timestamp. The receipt is at-most-once: Flutter presents only a
non-replayed acknowledgement after current consent/category/quiet/due checks.

V1 account controls are authenticated and owner-derived:

```text
PATCH  /v1/account/profile
PATCH  /v1/account/preparation-budget
GET    /v1/account/export
DELETE /v1/account
```

The delete body must be exactly `{"confirmation":"DELETE"}`. The same verified
bearer session must also contain recognized, non-refresh Supabase `amr`
authentication evidence no more than 15 minutes old; missing, stale, invalid,
refresh-only, or materially future evidence fails closed with `403` before the
delete service runs. Do not exercise deletion against anything except an
intentionally disposable account.

Capability and history reads never call a model. Current respond accepts strict
`coach-request-v3` with one UUID and a trimmed free question of at most 2,000
Unicode code points. There is no scope or time parameter:

```json
{
  "contract_version": "coach-request-v3",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "message": "What changed in my focus consistency this semester?"
}
```

The non-streaming route awaits the same agent service and still dispatches old
V1/V2 bodies through the legacy service for compatibility. The streaming route
accepts V3 only and emits `started`, allowlisted `activity`, and one
`completed|failed` SSE event. Client disconnect cancels the turn.

Each non-safety V3 turn creates a fresh owner-only
`personal-snapshot-v2` SQLite database from the relevant Account Export table
set under `free-coach-agent-prompt-v3`. Goals and Weekly Review proposals are
excluded from that snapshot. The prompt's non-overridable output
rule requires English for both the reply and uncertainty explanation regardless
of the question or stored-data language. Clearly German provider output is
rejected as retryable `invalid_output` before an assistant message is stored.
Exact V1 prompt replays remain valid. The snapshot contains sanitized retained
Setup/Capture/Task/Habit/Focus/Planner/
Preparation/Calendar/Review/Insight/Recommendation/Memory/Coach detail plus a
catalog, relationships, counts, periods, and helper views. It excludes auth,
profile email/role/provider identity, credentials, cross-user rows,
Coach request/usage/selection ledgers, provider internals, and operational
request ledgers. The turn fails rather than truncates beyond 10,000 rows per
table, 50,000 total, or 8 MiB.

The required per-turn stdio MCP exposes exactly:

- `inspect_data`;
- `query_data`, one immutable SQLite `SELECT|WITH` with authorizer,
  five-second progress limit, 500-row limit, and 256 KiB result limit; and
- `run_python`, 30 seconds in `mylifegraph-coach-analysis:1` with no network/
  secrets, non-root user, read-only root/snapshot, dropped capabilities,
  bounded temp space, one CPU, 512 MiB RAM, 64 PIDs, and bounded output.

The overall turn is limited to 12 tool calls and 180 seconds. At most one
internal Python plot may be returned to the model, but it is not stored or
returned to Flutter.
All free text is untrusted data, not tool instructions. There is no shell, web,
app, plugin, sub-agent, host-file, Supabase, or product mutation tool.

`coach-response-v2` contains reply, uncertainty, safety, backend-derived
snapshot-source coverage in the `evidence` field, actual tool
steps/limitations, and exact model/Fast/snapshot provenance. Coverage counts
and periods describe each full accessed snapshot source, not exact supporting
or SQL-returned rows. `inspect_data` alone adds no row coverage. A SQL step
records its returned-row count separately, while successful arbitrary Python is
conservatively attributed to the full `personal_snapshot` because table-level
Python claims are not trusted. The model produces only reply/uncertainty/safety.
No structured suggestion or artifact exists.

Exact same-id/message replay does not call the provider; changed message
conflicts, and failed/deleted ids remain terminal. One owner has at most one
pending turn and, by default, 20 newly started questions per profile-local day.
Tool calls do not consume extra question budget.

Conversation deletion is body-free. It removes messages and V3 evidence/trace/
tier content while retaining request tombstones and append-only usage, so it
cannot reset budget or reinterpret identity. `coach-history-v2` returns both
readable legacy `coach-response-v1` and current `coach-response-v2` turns.

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
COACH_AGENT_TIMEOUT_SECONDS=180
COACH_ANALYSIS_DOCKER_BIN=docker
COACH_ANALYSIS_IMAGE=mylifegraph-coach-analysis:1
LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20
LOCAL_CODEX_GLOBAL_CONCURRENCY=2
COACH_EVIDENCE_TIMEOUT_SECONDS=15
COACH_EVIDENCE_GLOBAL_CONCURRENCY=4
```

Do not expose the Supabase service-role key to the Flutter app. It belongs only
in the backend service environment. Keep `SCHEDULED_REFRESH_TOKEN` backend-only
as well; it authorizes scheduler-triggered refresh runs.

Coach is off by default. Standard automation may explicitly use
`COACH_PROVIDER=fake` with `COACH_FAKE_PROVIDER_ENABLED=true`. The real local
adapter additionally requires `APP_ENV=development`, `USE_MOCK_DATA=false`,
`COACH_PROVIDER=local_codex_oauth`, `LOCAL_CODEX_ENABLED=true`, valid backend
Supabase settings, an executable CLI, and an existing login for the FastAPI
Linux user. Current agent capability requires
`LOCAL_CODEX_MODEL=gpt-5.5`, explicit Fast support, Docker, and the pinned
analysis image. Empty or another model is unavailable; there is no CLI-default,
model, or standard-tier fallback for V3.

Codex OAuth remains private CLI state; the service may run sanitized
help/feature/login capability commands but must never read or copy an auth file.
Its child environment is allowlisted and excludes the Supabase service-role key
and every other application secret. The adapter is rejected outside development
and is not a deployment design.

Prepare the content-labelled analysis image explicitly from the repository
root:

```bash
npm run prepare:coach-analysis
```

From the repository root, `npm run start:local:coach` verifies the image label
and builds it when missing or stale. Runtime Python analysis starts it with
networking disabled.

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

`20260804150153_remove_goals_and_make_weekly_review_observational.sql` replaces
that backend-only Setup RPC with a Goal-free signature, removes the Goals table
without `CASCADE`, cleans structurally Goal-dependent data, upgrades surviving
reviews to V2, and admits the current Coach prompt/snapshot pair while retaining
valid historical pairs.

Personal Learning persistence requires
`20260726120000_personal_learning_v1.sql`, followed by
`20260726150000_learned_focus_planning_v1.sql`,
`20260726170000_recommendation_refresh_v2.sql`,
`20260726180000_learned_focus_planning_rpc_guard.sql`,
`20260726190000_planning_confirmation_timestamp_guard.sql`, and
`20260726200000_learned_timing_setup_fallback_provenance.sql`.
Controlled Coach longitudinal context then requires
`20260728120000_coach_longitudinal_context_v1.sql`; the free read-only agent
then requires `20260728160000_free_read_only_coach_agent_v1.sql`. Together they
add forced-RLS terminal Focus reflections, revisioned settings and retry
identities, immutable Planner/Deadline timing provenance, strict replay-safe
delegation, monotone confirmation timestamps, truthful allocation-fallback
provenance, atomic current-Recommendation replacement, compatible fixed-mode
Coach V2 replay, and message-only V3 evidence/trace/Fast-tier persistence.
Account Export
includes the two owner-content projections and omits the backend retry ledger
explicitly.

The typed `app/owner_data_catalog.py` module is the single backend inventory for
all repo-owned public tables. It derives the exact 43-table Account Export and
39-table personal Coach Snapshot from separate per-table policies, including
owner/cursor/watermark read shapes, sanitized export allowlists, omissions, and
snapshot descriptions. A focused test compares that inventory with every
public table created by the migration history, so a new table cannot silently
miss both privacy decisions. Shared lossless serialization lives in
`app/core/lossless_json.py`; Coach Snapshot no longer imports a private Account
Service helper.

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
`20260713230000_phase_10_onboarding_eligibility_guard.sql`, followed by the
longitudinal compatibility and
`20260728160000_free_read_only_coach_agent_v1.sql` migrations. The first adds backend-owned
`coach_requests`, `coach_usage_events`, and `coach_memory_selections`; exact
request-linked V1 message pairs; hardened forced RLS/grants for messages and
memories; and service-role-only atomic claim, complete, fail, selection, and
history-delete RPCs. Apply it non-destructively with `supabase migration up
--local` when pending. The guard keeps those public signatures and makes
claim/complete/fail take the same owner-first advisory lock as history delete.
The additive guards persist exact provider-call truth for safety redirects,
make profile identity and onboarding eligibility backend-owned, remove legacy
`"User"` role fallback and authenticated profile deletion, and retain
service-role/atomic Intake authority. The final migration adds V3 claim/V2
completion validators and RPCs plus evidence, agent-trace, tool-count, and Fast
tier fields while retaining V1/V2 rows and application-role denial. Historical real local PostgreSQL parallel
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
`20260714130000_notification_delivery_v1.sql` then adds the separate consent,
generated-row provenance/dedupe, and foreground receipt fields plus three
owner-locked service-role-only RPCs.
`20260714143000_notification_delivery_settings_guard.sql` follows with a full
Settings request fingerprint and a shared-writer revision trigger, so Intake
Setup cannot regress consent timestamp ordering or leave a stale replay identity.

JWT verification is isolated in the FastAPI auth dependency. Tests inject fake
verifiers and repositories, so production or remote Supabase credentials are not
required for the unit test suite. Client/lifespan tests additionally prove one
shared Supabase transport across operations, exact once-only shutdown, and the
unconfigured fail-closed boundary. Intake tests cover authenticated read/save,
blank optional materialization, candidate cadence validation, request replay,
stale revision conflicts, convergent retry/edit identities, lifecycle removal,
legacy-key stripping, `responses.goals` rejection, unchanged Reminder
preferences, no post-Setup Recommendation generation, and preservation of
non-Setup-owned rows. Daily State tests cover strict V2/V3/V4 parsing, explicit
mixed-branch compatibility, V4 sleep-interval validation, friction sanitization,
and the V2 output contract. Phase 3 tests cover strict executable
action parser parity, explicit habit/focus snapshot summaries and local-date
filtering, preservation of Phase 2 Daily State behavior, and terminal-task
exclusion from recommendation pressure. Phase 4 through Phase 7 coverage adds
strict persisted briefings, profile-local scheduled dates, missing/stale/current
write behavior, bounded targeted retry, per-user failure isolation, and default
no-recommendation/no-LLM preparation. Phase 8/9 coverage adds weekly-review
freshness/proposals plus strict calendar consent, retry-safe `.ics` identity,
timezone/all-day/recurrence/cancellation handling, stable event pagination,
disconnect/delete separation, schedule preservation, and RLS ownership.
Deadline Planner/Planner coverage includes proposal/confirmation/lifecycle,
workload, preparation-budget, shared Availability, and strict read-only
Exam-Week Outlook tests. Personal Learning tests cover terminal reflection
guards, preference replay/dependency, disabled short-circuit, profile
timezone/DST, sleep assignment/deduplication, every maturity gate,
half-consistency, night exclusion, deterministic fingerprints, learned
free/busy/fallback ordering, confirmation permission, and atomic
Recommendation replacement. A documented test suite alone is not a pass claim.
Exact current results live in
[Current Verified Baseline](../../docs/verification.md#current-verified-baseline).

Phase 10 tests use fake services/providers/process runners. They cover the V3
request/SSE, snapshot, three-tool MCP, SQL/Python isolation, trace/source-scope
derivation, replay/budget/cancel/delete, and current no-fixed-mode UI without
requiring Codex, OAuth, a subscription, or network access. Scripted provider
responses prove strict envelopes and execution-path handling, not autonomous
model tool choice, false-premise judgment, or answer quality. See
`../../docs/verification.md` for historical deterministic evidence and the
diagnostic-only focused rerun command.
The separate live multi-tool smoke is skipped by default and runs only after
explicit local-provider setup, image preparation, and login:

```bash
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

Any current live claim must verify strict `gpt-5.5` selection, explicit Fast
configuration, required MCP startup, and matching multi-tool trace/source-scope
provenance. It is specific to its tested machine, CLI, image, login, account,
and date; it is not a persistence, API, Flutter UI, deployable-provider, or
another-developer availability claim. Deterministic API/browser tests
separately cover persisted response/history behavior and presentation.

Run service tests with:

```bash
pytest
```
