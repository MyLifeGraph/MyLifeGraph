# MyLifeGraph AI Service

FastAPI service boundary for deterministic planning, learning, and Coach
workflows.

`APP_ENV` is a closed value: `development`, test-only `test`, `staging`, or
`pilot`. Unknown, case-folded, whitespace-padded, and premature `production`
values fail settings construction. The VPS preflight additionally requires
exact `pilot`, so a typo cannot bypass hosted project, participation, release,
or provider guards.

The current explicit-provider extension publishes `coach-request-v4`,
`coach-capabilities-v5`, `coach-response-v4`, and `coach-history-v4` with
`free-coach-agent-prompt-v5`. `X-MyLifeGraph-Coach-Provider` is required for
hosted V4 capability/response routes; `X-MyLifeGraph-Coach-Api-Key` accompanies
only OpenAI (`gpt-5.6-terra`) or Gemini (`gemini-3.6-flash`) BYOK. Keys are
request-local and are never persisted, logged, traced, or returned. History and
deletion never accept or need provider keys. V1-V3 rows remain compatible.
Hosted CORS allowlists both request headers and exposes bounded `Retry-After`.
The Gemini REST adapter pins `Api-Revision: 2026-05-20`, parses only the current
`steps` schema, carries its exact returned steps through stateless function
continuations, and uses the current text/JSON response-format shape. Mock
contract coverage is not a live-provider acceptance claim. Both BYOK adapters
enforce the 12-call allowance cumulatively before a parallel batch runs, retain
at most 512 KiB of tool-result history, bound step/content counts, and stream
provider responses through a 256-KiB decoded-body cap before JSON parsing.
Every OpenAI Responses or Gemini Interactions call also carries a provider-side
4,096-output-token ceiling, including all tool-loop continuations. This bounds
provider generation/cost before the local byte parser runs; it is not a promise
that every model will consume the allowance or report identical token usage.

Hosted HTTP uses one-worker route-class admission before application work:
client-IP rate limits and concurrency/body bounds cover readiness, reads,
mutations, and Coach separately; after Supabase has verified a bearer token,
the same controller applies a bearer-derived owner rate. `/v1/health` stays a
cheap unmetered liveness path, while `/v1/ready` is bounded because it performs
a Supabase probe. The in-memory counters are restart-local abuse protection,
not a user cap or durable Coach quota; Postgres remains the authority for
Coach budgets and replay.

The repository implements the default-off explicit
`operator_codex_pilot` adapter through a separately sandboxed Unix-socket
executor with durable local/global budgets; it does not make the same-user
development adapter deployable and is never a fallback. VPS/HTTPS and live
acceptance remain external work owned by
`../../docs/vps-pilot-release-plan.md`. Distinct staging/pilot project guards,
release identity, and current Supabase backend secret-key support are implemented
configuration boundaries. The current repository also implements strict
`pilot-participation-v1`: an authenticated raw principal may record the exact
`pilot-participation-notice-v1` through a service-role-only RPC, while normal
staging/pilot product dependencies require the backend-owned profile
version/time pair. Account export and deletion remain reachable for an
unaccepted authenticated account. The database-side
`pilot-participation-gate-v1` adds default-off restrictive RLS so public Data
API calls cannot bypass those app/service checks. Development remains ungated.
The staging-only fixture generator is implemented with preview/confirmation/
cleanup guards; a confirmed remote run and all deployment evidence remain
open.

## Current Status

- The service is optional for the default mock-data Flutter preview.
- `/v1/health` is cheap liveness and returns exact release SHA/tag. `/v1/ready`
  separately checks hosted release/config shape, composition, and a bounded
  live PostgREST probe without invoking a Coach provider. Hosted readiness also
  attests the exact participation and Account Deletion V2 database contracts,
  V1-delete revocation, and bounded pending-deletion age. The
  `hosted-database-contract-v1` seam compares the release manifest's exact
  ordered migration-prefix head/count/digest with Postgres; same-head history
  drift fails readiness. Its loopback-only form additionally returns the full
  database identity for protected promotion and compatible DB-ahead rollback.
- `GET /v1/intake/setup` reads the newest typed Setup row: the latest pending
  row for exact retry/resume, otherwise the latest applied revision.
  `POST /v1/intake/complete` handles both authenticated Intake V1 completion
  and later Setup edits.
- The former generic Today Recommendation and Decision Feedback routes are
  retired. Their `recommendations`, `recommendations/generate`, and `feedback`
  endpoint names are not composed into the application. The independent
  `sleep-recommendation-v1` Insights route remains current.
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
  interval, expose canonical fully-credited and sub-five-minute blockers, and
  never fall back to an unproven direct start. The capability
  read lets a mixed-version client retain legacy manual V1 behavior only when
  the backend explicitly lacks V2; auth, network, and server failures never
  trigger that downgrade. See
  `../../docs/phase-3-executable-actions-contract.md`.
- FastAPI defines the strict, ranking-independent `executable-action-v1` model
  for persisted briefings. It rejects unknown top-level/metadata fields,
  null/non-object metadata, explicit-null metadata fields, numeric coercion,
  invalid ISO dates, command/kind/target/linkage mismatch, unsupported routes,
  and per-command metadata leakage. `review_plan` is a real authenticated
  navigation target for the read-only Weekly Review surface; dispatch never
  generates or applies a proposal. Current Flutter uses feature-owned commands
  and a shared version constant for compatible Focus metadata, with no general
  action-envelope parser or dispatcher. See
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
  preferences unchanged, and Setup completion generates no generic
  Recommendation. Snapshot generation reuses `user_state_snapshots`, excludes
  capture free text from Daily State, and does not require an LLM provider.
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
- `GET /v1/briefings/today` reads one persisted `daily-briefing-v2` decision;
  deliberate `POST /v1/briefings/generate` refreshes its exact profile-local
  date. Normal reads remain generation-free. The visible Today surface instead
  uses read-only `GET /v1/today/overview-v2` for its streak, exact progress,
  timeline, Tasks, Habits, and confirmed Planner blocks. The V1 route remains
  available for existing clients. Its lazy calendar-week companion is
  `GET /v1/today/week-agenda` under `today-week-agenda-v1`: seven exact
  profile-local days, seven independently fresh sources, and no write or
  generation. Neither read removes the internal briefing contract or writes
  product state.
- Phase 7 extends the protected scheduled boundary to prepare daily snapshots
  and briefings for onboarded non-guest profiles. One UTC run instant determines
  each profile-local date; current pairs are write-free, while missing or stale
  state converges on the existing daily identities with isolated per-user stage
  results.
- Phase 8 exposes read-only completed-week review GETs and deliberate,
  facts-only deterministic review generation under `weekly-review-v3`. New or
  refreshed reviews always store an empty proposal array.
- Phase 9 exposes the strict `calendar-import-v2` projection for one optional
  `.ics` connection. Consent, file import, stable paginated event reads,
  disconnect, and local imported-data deletion are authenticated and owner
  scoped. Each import records its profile-timezone revision and planning status.
  One fingerprint-free backend request registry prevents UUID reuse across
  owners or operations. It has no provider credential, URL fetch, provider
  write, background sync, or LLM processing.
- Planner exposes the strict `planner-overview-v2` read-only seven-day
  overview, while detail/mutation responses remain `planner-v1`, plus explicit
  preference, Task/Habit proposal/confirm/cancel, and fixed-commitment commands
  under `/v1/planner`. Immutable previews use shared deterministic availability
  with Deadline Planner and reserve nothing until owner-locked confirmation.
  Setup recurring commitments may use optional inclusive `valid_from` and
  `valid_until` dates. V2 separates all active Habits from persisted open
  unscheduled Tasks, returns authoritative `task_targets` snapshots for every
  current open non-Preparation Task including scheduled Tasks, leaves pending
  creates and updates in `action_plans`, and reports exact zero/partial placement and
  source-specific current conflicts. Existing targets remain unscheduled; GETs
  never create revisions. Both runtime validators require every unreserved open
  Task exactly once under `unscheduled_tasks`, use released/missing/no-time/
  not-planned reason precedence, and reject a persisted Task or Habit plan
  without the lifecycle-correct current or historical target snapshot.
  Historical Tasks and inactive Habits accept only released/cancelled plan
  lifecycles. Pending-create absence is limited to a draft, revision-zero plan
  whose latest proposed revision is the create; the sole terminal absence
  exception is the exact cancelled-create tombstone with current revision zero,
  a bounded latest revision from one through 500, no active/pending revision,
  and no attention reason. Released former active plans remain `unscheduled`
  with `target_released` and still require their historical target. Public
  proposal bases stop at 499; revisions, plan revision counters, and
  confirm/cancel expected revisions stop at 500. Active revisions and their
  Task-block/Habit-slot children must all carry the SQL `active` state.
  Required plan-linked history snapshots are kept
  before deterministic `created_at`/identity fill up to 1,000; an impossible
  relation fails closed. Pending staleness
  is recomputed from current target, Calendar, timezone, and Study facts rather
  than inherited from long-lived plan reasons. When both the
  account choice and development pilot gate are on,
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
  The service derives an internal allocation policy from immutable kind: Exams
  retain `spread_first`, while Assignments use `earliest_clustered`. The policy
  is covered by the planning fingerprint but not the request fingerprint or
  public/RPC payload. Both policies retain account/per-plan caps, busy-time,
  Study Focus/Recovery, remainder, block-bound, and DST authority.
  An existing plan's root kind is immutable: a proposal with a different kind
  returns `409` with `Deadline plan kind cannot be changed.` before planning
  context is loaded. The final service-role proposal RPC independently enforces
  the same rule for owner-scoped draft and active roots while retaining exact
  replay/collision precedence and the public signature used by Assignment
  Series. The service role cannot call the strict unguarded
  `propose_deadline_plan_v1` body directly; it has execute authority only on the
  guarded timing wrapper, whose postgres-owned implementation may invoke the
  base body internally.
  The nested `assignment-series-v1` routes add finite weekly Assignment
  list/detail/proposal/confirm/cancel-future behavior. A shared template stages
  independent Deadline Plans, then one owner-locked RPC confirms the complete
  series; future-wide edits retain past/completed occurrences and replace the
  future scope.
- Phase 10 exposes authenticated free-question capability, streaming and
  non-streaming response, and mixed legacy/current history/delete contracts.
  Each non-safety V4 turn creates a fresh owner-only SQLite snapshot.
  Request-scoped OpenAI/Gemini BYOK receives bounded inspect/query results; the
  development-only `local_codex_oauth` and separate default-off pilot executor
  additionally receive isolated Python through a required MCP and require
  `gpt-5.5` with Fast explicitly configured. FastAPI derives
  conservative snapshot-source coverage, actual trace, and provider provenance.
  No provider falls back to another. Current Flutter has no fixed mode, horizon,
  Focus, prompt, memory-selection, or structured-suggestion flow; readable
  V1-V3 response history remains compatible. Hosted release acceptance remains
  open.
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
  `account-export-v6`, and `/v1/account` remains the confirmed permanent
  `account-deletion-v2` boundary; `GET /v1/account/deletion` returns strict
  `account-deletion-status-v2`. The client supplies only a stable retry UUID,
  never an owner id. Hosted deletion must first append the
  `account-deletion-journal-v2` KMS/Object-Lock receipt, then the reconciler
  converges any durable pending state. The runtime can write but cannot list,
  read, decrypt, or replay journal objects.
  `POST /v1/account/pilot-participation` accepts only the exact versioned
  18-or-older self-attestation and derives its owner from the verified bearer;
  it stores no birth date and ignores editable Auth metadata for eligibility.
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
`coach_analysis/requirements.in` owns the exact direct analysis inputs and
`coach_analysis/requirements.txt` locks their complete image graph with hashes.
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

OpenAPI docs are available only in exact `APP_ENV=development`; staging and
pilot disable them, while `production` and unknown labels fail startup:

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

Read the current profile-local Monday-through-Sunday agenda without side
effects:

```bash
curl http://localhost:8000/v1/today/week-agenda \
  -H 'Authorization: Bearer <supabase_access_token>'
```

`today-week-agenda-v1` returns seven ordered days plus separate
`current|unavailable` states for Setup, Preparation, Calendar, Focus, Planner
Tasks, Habits, and fixed commitments. The bearer principal owns every bounded
source seam and its fixed batched relation reads; none scale per item.
Preparation reuses canonical current-revision Focus credit and exposes exact
planned, credited, and remaining minutes with lifecycle-bound actions. Calendar
events are projected only when `last_import_id` resolves to the
same owner's `planning_status=current` import; disconnected Calendar is a
current empty source, while stale planning data is unavailable. Profile or
timezone authority failure is route-wide `503`. All local date/time strings
are server-derived in the profile timezone. The endpoint never calls Planner
Overview or the bounded Deadline list and never mutates or generates state.

Personal Learning uses these bearer-authenticated contracts:

```text
GET    /v1/learning/preferences
PATCH  /v1/learning/preferences
POST   /v1/learning/focus-reflections/clear
GET    /v1/insights/personal-patterns
GET    /v1/insights/sleep-recommendation
```

Set `LEARNED_FOCUS_PLANNING_PILOT_ENABLED=true` in FastAPI and the matching
Flutter Dart define only for development, test, or staging verification. The
account Planner switch is still independent and default-off. Both runtimes
force the deployment gate off in the public `pilot` environment.

Planner Overview V2 and Planner V1 mutations use these bearer-authenticated
reads and deliberate commands:

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

Overview assembly preserves a Deadline-source conflict as the existing Planner
HTTP `409` problem and its detail, including the shared Today/Planner read
context. It does not expose an unhandled `500` or truncate an inconsistent
Deadline projection to make the overview appear complete.

The V2 overview omits only an individual recurring Habit, Setup, or weekly
manual fixed-commitment occurrence whose profile-local wall time is ambiguous
or nonexistent. It retains other valid occurrences and reports one deduplicated
source/date/reason-specific read-only attention item for each affected Action or
Preparation Plan; it never turns the invalid occurrence into a conflict or
moves a saved reservation. Its 366 reservation days use only one preceding and
one following read-only spill anchor (at most 368 authoritative local days),
without generating candidates on either anchor. Persisted open Task versus Task-history identities
and active-Habit versus Habit-history identities are pairwise disjoint, while
Task and Habit UUID namespaces remain independent.

Deadline Planner and its strictly read-only workload/outlook projections use:

```text
GET    /v1/deadline-plans
GET    /v1/deadline-plans/exam-week-outlook
GET    /v1/deadline-plans/exam-plan-health
POST   /v1/deadline-plans/exam-plan-health/preview
GET    /v1/deadline-plans/exam-balances
GET    /v1/deadline-plans/exam-balances/{balance_id}
POST   /v1/deadline-plans/exam-balances/proposals
POST   /v1/deadline-plans/exam-balances/{balance_id}/confirm
POST   /v1/deadline-plans/exam-balances/{balance_id}/cancel
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

The shared named `exam-plan-health-v1` GET and editor-preview POST are both
side-effect-free capacity reads. The preview body contains only exact Exam
editor values and no mutation request id. A new preview omits `plan_id` and
`base_revision`; an unconfirmed persisted draft is simulated the same way and
does not borrow another plan's Focus or reservations. Only an active Exam
replan supplies both fields and is rejected with `422` unless they bind to the
bearer owner's active Exam and latest saved revision. The deadline must be
strictly future and no more than 366 elapsed and profile-local days away;
`planning_start_on` may not follow the local deadline or make the planning
window exceed 366 days.
FastAPI derives the owner from the
bearer and obtains one untruncated, point-in-time snapshot through the
service-role-only `get_exam_plan_health_snapshot_v1` RPC. Missing required
Calendar/recurrence authority returns an `unknown` item; it is not converted to
a route failure or false green. Neither route writes Health state, creates a
notification, reserves time, or replans.
The snapshot includes ordered completed Focus facts with scheduled Deadline
block provenance. Health subtracts exact per-block credit from future reserved
minutes while retained blocks continue to consume busy time, daily caps, and
the revision's finite block count.

The shared named `multi-exam-plan-v1` endpoints require an explicit active Exam
id and expected latest plan revision. Proposal takes one owner-locked 366-day
source snapshot and performs deterministic retain-and-supplement, target-only
redistribution, then exact minimal-cardinality collider search. It returns a
strict `no_change | single_plan | multi_exam_batch` union. One changed plan is
already persisted through the existing Deadline V1 proposal flow; two to eight
changed plans are reviewed and confirmed/cancelled only as one batch. Batch
confirm is atomic, and normal child proposal/replan, confirm, complete, and
cancel mutations return `409` while that batch is pending. Exact request replay
is stable while its proposal remains pending; replaying the original proposal
after later confirm/cancel returns a defined `409` conflict instead of a
malformed terminal projection. Confirmation checks the current owner-locked
context plus learned-timing pilot/permission/provenance marker, while stale
cancellation may still discard only staged proposals. Postgres `55P03` and
retryable `40P01` failures map to the same stable HTTP conflict boundary.
Direct Profile, Schedule, Focus, Learning Preference, Task, and Habit writers
take the same owner lock before their row/lifecycle triggers; Task/Habit
reservation release therefore cannot interleave with batch digest validation.
List/detail/proposal/confirm/cancel derive the owner from the bearer principal.
No route auto-confirms, sends a notification, or writes to an external
calendar.

Batch storage is private derived orchestration metadata exposed only through
service-role RPC projections. Actual plan content remains in existing Deadline
revisions/blocks. This boundary does not change the shapes or versions of
`account-export-v6` or `personal-snapshot-v3`.

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
  -d '{"window_days":7,"limit":100}'
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
  -d '{"profile_ids":["11111111-1111-4111-8111-111111111111"],"window_days":7,"limit":1}'
```

The filter never bypasses onboarding or guest exclusion. Failures are isolated
per profile and identify `profile_date`, `snapshot`, or `briefing` as the
stage. Retired recommendation scheduler fields are rejected as unknown input.
`include_notifications=true` requests the exact current profile-
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

Account controls are authenticated and owner-derived:

```text
POST   /v1/account/pilot-participation
PATCH  /v1/account/profile
PATCH  /v1/account/preparation-budget
GET    /v1/account/export
GET    /v1/account/deletion
DELETE /v1/account
```

The V2 delete body must be exactly
`{"contract_version":"account-deletion-v2","deletion_id":"<uuidv4>","confirmation":"DELETE"}`.
The same verified
bearer session must also contain recognized, non-refresh Supabase `amr`
authentication evidence no more than 15 minutes old; missing, stale, invalid,
refresh-only, or materially future evidence fails closed with `403` before the
delete service runs. Success is `200`; durable or still-appending work is
`202 deletion_pending` and must be retried with the same UUID. Do not exercise
deletion against anything except an intentionally disposable account.

History reads never call a model. Capability may make only a bounded readiness
probe to the explicitly selected provider. Current hosted respond accepts
strict `coach-request-v4` with one UUID and a trimmed free question of at most
2,000 Unicode code points. There is no scope or time parameter:

```json
{
  "contract_version": "coach-request-v4",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "message": "What changed in my focus consistency this semester?"
}
```

The non-streaming route awaits the same agent service and still dispatches old
V1/V2 bodies through the legacy service plus V3 BYOK compatibility. The
streaming route accepts V3/V4 and emits `started`, allowlisted `activity`, and
one `completed|failed` SSE event. Client disconnect cancels the turn.

Each non-safety V4 turn creates a fresh owner-only
`personal-snapshot-v3` SQLite database from the relevant Account Export table
set under `free-coach-agent-prompt-v5`. Goals, generic Recommendations,
Decision Feedback, and Weekly Review proposals are excluded from that snapshot.
The prompt's non-overridable output
rule requires English for both the reply and uncertainty explanation regardless
of the question or stored-data language. Clearly German provider output is
rejected as retryable `invalid_output` before an assistant message is stored.
Exact V1 prompt replays remain valid. The snapshot contains sanitized retained
Setup/Capture/Task/Habit/Focus/Planner/
Preparation/Calendar/Review/Insight/Memory/Coach detail plus a
catalog, relationships, counts, periods, and helper views. It excludes auth,
profile email/role/provider identity, credentials, cross-user rows,
Coach request/usage/selection ledgers, provider internals, and operational
request ledgers. The turn fails rather than truncates beyond 10,000 rows per
table, 50,000 total, or 8 MiB.

Each local/operator Codex provider's required per-turn stdio MCP exposes exactly:

- `inspect_data`;
- `query_data`, one immutable SQLite `SELECT|WITH` with authorizer,
  five-second progress limit, 500-row limit, and 256 KiB result limit; and
- `run_python`, 30 seconds in the content-validated local `:1` image or the
  release-owned `sha256-<revision>` image with no network/secrets, non-root
  user, read-only root/snapshot, dropped capabilities,
  bounded temp space, one CPU, 512 MiB RAM, 64 PIDs, and bounded output.

OpenAI/Gemini BYOK exposes only `inspect_data` and `query_data` through bounded
FastAPI tool-result calls; it receives neither the SQLite file nor Python. The
overall turn is limited to 12 tool calls and 180 seconds. At most one Codex
Python plot may be returned to that model, but it is not stored or
returned to Flutter.
All free text is untrusted data, not tool instructions. There is no shell, web,
app, plugin, sub-agent, host-file, Supabase, or product mutation tool.

For non-safety turns, provider admission completes before the streaming route
commits SSE. BYOK/local work acquires the bounded process slot; Project Coach
reserves one opaque executor token over the Unix socket. That reservation is a
capacity-only operation with no CLI probe and is bounded by FastAPI to one
second; provider readiness is checked separately before a dispatch record.
Busy is HTTP
`429 provider_busy` with `Retry-After: 15` and consumes neither request identity
nor budget. After the request claim and immediately before executor dispatch,
the service-role RPC increments one user-independent UTC-day aggregate and
records one owner-linked dispatch in the same transaction. Exact replay does
not increment. Account deletion may remove the personal dispatch but cannot
reset the aggregate or recover shared capacity. A startup reconciliation marks
expired ambiguous dispatches as accounted interruptions, so the same request
cannot call Codex twice. The
owner-visible request terminal write is confirmed before the private dispatch
is terminalized; an ambiguous completion/failure response leaves the dispatch
open for that reconciliation instead of guessing a terminal state.

The `coach-executor` process accepts only bounded capability/reserve/release/
execute frames from the configured API UID verified by `SO_PEERCRED`. It owns
the exact pinned Codex binary, OAuth home, rootless Docker socket, and temporary
snapshot. The API owns Supabase/application secrets and cannot use either
executor credential. Core `/health` and `/ready` do not probe this provider;
authenticated Coach capability reports its separate state.

`coach-response-v4` contains reply, uncertainty, safety, backend-derived
snapshot-source coverage in the `evidence` field, actual tool
steps/limitations, and exact provider/model/tier/snapshot provenance. Coverage
counts and periods describe each full accessed snapshot source, not exact supporting
or SQL-returned rows. `inspect_data` alone adds no row coverage. A SQL step
records its returned-row count separately, while successful arbitrary Python is
conservatively attributed to the full `personal_snapshot` because table-level
Python claims are not trusted. The model produces only reply/uncertainty/safety.
No structured suggestion or artifact exists.

Exact same-id/message/provider replay does not call the provider; changed input
conflicts, and failed/deleted ids remain terminal. One owner has at most one
pending turn. Non-operator modes allow 20 newly started questions per
profile-local day; Project Coach allows 5 per UTC day and a durable global
maximum of 15 dispatches per UTC day. Its separate UTC budget field is not
affected by profile-timezone edits; the request `local_date` remains a
profile-local history fact. Tool calls do not consume extra question budget.

Conversation deletion is body-free. It removes messages and V3/V4 evidence,
trace, and tier content while retaining request tombstones, append-only usage,
and operator dispatch accounting, so it cannot reset budget or reinterpret
identity. `coach-history-v4` returns current `coach-response-v4` plus readable
legacy V1-V3 turns.

## Environment

The service reads `.env` from `services/ai_service`:

```env
APP_ENV=development
APP_BUILD_SHA=
APP_RELEASE_TAG=
APP_MIGRATION_HEAD=
APP_MIGRATION_COUNT=0
APP_MIGRATION_IDENTITY_SHA256=
USE_MOCK_DATA=true
API_PREFIX=/v1
ALLOWED_ORIGINS=http://127.0.0.1:7357,http://localhost:7357
SUPABASE_URL=
STAGING_SUPABASE_PROJECT_REF=
PILOT_SUPABASE_PROJECT_REF=
SUPABASE_SECRET_KEY=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_TIMEOUT_SECONDS=10
SCHEDULED_REFRESH_TOKEN=
COACH_PROVIDER=disabled
COACH_FAKE_PROVIDER_ENABLED=false
COACH_BYOK_PROVIDERS=
OPERATOR_CODEX_PILOT_ENABLED=false
COACH_EXECUTOR_SOCKET_PATH=/run/mylifegraph-coach/executor.sock
COACH_EXECUTOR_ALLOWED_API_UID=0
COACH_OPERATOR_MODEL=gpt-5.5
COACH_OPERATOR_REQUESTS_PER_USER_PER_DAY=5
COACH_OPERATOR_GLOBAL_REQUESTS_PER_DAY=15
COACH_OPERATOR_GLOBAL_CONCURRENCY=1
COACH_OPERATOR_RETRY_AFTER_SECONDS=15
LOCAL_CODEX_ENABLED=false
LOCAL_CODEX_BIN=codex
LOCAL_CODEX_EXPECTED_VERSION=
LOCAL_CODEX_MODEL=gpt-5.5
LOCAL_CODEX_TIMEOUT_SECONDS=45
COACH_AGENT_TIMEOUT_SECONDS=180
COACH_ANALYSIS_DOCKER_BIN=docker
COACH_ANALYSIS_DOCKER_HOST=
COACH_ANALYSIS_IMAGE=mylifegraph-coach-analysis:1
LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20
LOCAL_CODEX_GLOBAL_CONCURRENCY=2
COACH_EVIDENCE_TIMEOUT_SECONDS=15
COACH_EVIDENCE_GLOBAL_CONCURRENCY=4
PUBLIC_ADMISSION_WAIT_MILLISECONDS=50
PUBLIC_READY_IP_REQUESTS_PER_MINUTE=60
PUBLIC_READY_CONCURRENCY=4
PUBLIC_READ_IP_REQUESTS_PER_MINUTE=300
PUBLIC_READ_OWNER_REQUESTS_PER_MINUTE=180
PUBLIC_READ_CONCURRENCY=32
PUBLIC_MUTATION_IP_REQUESTS_PER_MINUTE=120
PUBLIC_MUTATION_OWNER_REQUESTS_PER_MINUTE=60
PUBLIC_MUTATION_CONCURRENCY=8
PUBLIC_COACH_IP_REQUESTS_PER_MINUTE=60
PUBLIC_COACH_OWNER_REQUESTS_PER_MINUTE=12
PUBLIC_COACH_CONCURRENCY=4
```

Hosted pilot uses the current `SUPABASE_SECRET_KEY`; local Supabase and staged
migration may retain `SUPABASE_SERVICE_ROLE_KEY`. When both exist the current
key wins. Staging may temporarily use the legacy key, while pilot requires a
current `sb_secret_` value. Never expose either backend key to Flutter. Hosted
startup also requires the exact environment project ref and rejects a crossed
URL or equal staging/pilot refs. Keep `SCHEDULED_REFRESH_TOKEN` backend-only as
well; it authorizes scheduler-triggered refresh runs.
Hosted CORS accepts exactly one canonical HTTPS hostname origin with no path,
port, credentials, wildcard, IP literal, whitespace, or second preview origin.
Local/test runtimes retain the documented loopback list.
The VPS Caddy boundary rejects bodies above 1 MiB; FastAPI further caps Coach
bodies at 32 KiB and all other mutations at 1 MiB, including chunked requests.

Coach is off by default. Standard automation may explicitly use
`COACH_PROVIDER=fake` with `COACH_FAKE_PROVIDER_ENABLED=true`. The real local
adapter additionally requires `APP_ENV=development`, `USE_MOCK_DATA=false`,
`COACH_PROVIDER=local_codex_oauth`, `LOCAL_CODEX_ENABLED=true`, valid backend
Supabase settings, an executable CLI, and an existing login for the FastAPI
Linux user. Current agent capability requires
`LOCAL_CODEX_MODEL=gpt-5.5`, explicit Fast support, Docker, and the pinned
analysis image. Empty or another model is unavailable; there is no CLI-default,
model, or standard-tier fallback for V4.

Codex OAuth remains private CLI state; the service may run sanitized
help/feature/login capability commands but must never read or copy an auth file.
Its child environment is allowlisted and excludes the Supabase service-role key
and every other application secret. The Codex child also receives neither the
Docker endpoint nor rootless runtime directory; its built-in shell/exec features
are disabled, while only the fixed MCP subprocess receives the exact analysis
socket setting. The adapter is rejected outside development and is not a
deployment design.

Hosted Project Coach is instead enabled only in exact `staging|pilot` with
`OPERATOR_CODEX_PILOT_ENABLED=true`; `production` stays fail-closed. The API
environment contains only the executor socket and public limits. The executor
environment separately requires one numeric non-root API UID, an absolute
checksum-pinned Codex binary/version, exact
`unix:///run/user/<executor-uid>/docker.sock`, matching `XDG_RUNTIME_DIR`, and
an allowlisted environment without Supabase/application secrets. Templates and
the operational sequence live under `deploy/vps/`. Hosted executor startup
accepts only the generated
`mylifegraph-coach-analysis:sha256-<64-hex-revision>` identity loaded after the
mutable executor environment; the local `:1` tag remains development-only.

Prepare the content-labelled analysis image explicitly from the repository
root:

```bash
npm run prepare:coach-analysis
```

The image uses an immutable official-Python base digest, binary-only installs
from the complete hash lock in `coach_analysis/requirements.txt`, and a stable
content revision over Dockerfile, lock, and runner. Regenerate the lock only
through `scripts/update_python_requirements.sh` and review it as separate
compatibility/security work. A prepared VPS release derives a unique image tag
from that revision and retains the previous release's image so application
rollback cannot silently bind old code to a newer mutable tag.

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

Personal Learning persistence historically introduced
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
provenance, the later-retired atomic Recommendation replacement, compatible fixed-mode
Coach V2 replay, and message-only V3 evidence/trace/Fast-tier persistence.
Account Export
includes the two owner-content projections and omits the backend retry ledger
explicitly.

The typed `app/owner_data_catalog.py` module is the single backend inventory for
all repo-owned public tables. It derives the exact 41-table Account Export and
37-table personal Coach Snapshot from separate per-table policies, including
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
service-role/atomic Intake authority. The free-agent migration adds V3 claim/V2
completion validators and RPCs plus evidence, agent-trace, tool-count, and Fast
tier fields while retaining V1/V2 rows and application-role denial.

`20260819203000_coach_operator_pilot_v1.sql` then adds V4
request/response/provider constraints, `provider_dispatch_required`,
service-role-only V8 claim/V3 completion, and the forced-RLS append-only
`coach_operator_daily_budgets` aggregate plus owner-linked
`coach_operator_dispatches` table and record/finish/reconcile RPCs. Exact
dispatch replay increments once; account deletion cascades personal linkage
without resetting the global day count. Both ledgers are backend-only;
owner-visible outcomes remain in usage rows, so Account Export remains the
strict 41-table V6 shape. Historical real local PostgreSQL parallel
claim/completion/deletion smokes completed on 2026-07-13 without deadlock or
timeout and converged on the expected state.

Permanent account deletion begins with the owner-locked implementation from
`20260713233000_v1_account_delete.sql`, but the current public boundary is
`20260820170000_account_deletion_recovery_v2.sql`. V2 records a minimal recovery
intent, accepts only a write-only encrypted `account-deletion-journal-v2`
receipt, revokes direct service-role V1 execution, and exposes service-only
prepare/accept/complete/status/reconcile RPCs. Restore replay is granted only
to the dedicated non-login database role. FastAPI additionally requires
session-bound Supabase JWT `amr` sign-in evidence no more than 15 minutes old;
a refresh-only or stale session receives `403` without starting the flow.

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
preferences, no post-Setup generic Recommendation generation, and preservation of
non-Setup-owned rows. Daily State tests cover strict V2/V3/V4 parsing, explicit
mixed-branch compatibility, V4 sleep-interval validation, friction sanitization,
and the V2 output contract. Phase 3 tests cover strict executable
action parsing, explicit habit/focus snapshot summaries and local-date
filtering and preservation of Phase 2 Daily State behavior. Phase 4 through
Phase 7 coverage adds
strict persisted briefings, profile-local scheduled dates, missing/stale/current
write behavior, bounded targeted retry, per-user failure isolation, and no-LLM
preparation. Phase 8/9 coverage adds Weekly Review V3 empty-only proposal
parity plus strict calendar consent, retry-safe `.ics` identity,
timezone/all-day/recurrence/cancellation handling, stable event pagination,
disconnect/delete separation, schedule preservation, and RLS ownership.
Deadline Planner/Planner coverage includes proposal/confirmation/lifecycle,
workload, preparation-budget, shared Availability, and strict read-only
Exam-Week Outlook tests. Allocation coverage separately proves unchanged Exam
spreading; Assignment earliest-date clustering; account, daily, busy,
Focus/Recovery, remainder, and DST limits; series occurrence windows; Flutter
120/360 defaults and saved/manual retention; and planning/request fingerprint
separation. Personal Learning tests cover terminal reflection
guards, preference replay/dependency, disabled short-circuit, profile
timezone/DST, sleep assignment/deduplication, every maturity gate,
half-consistency, night exclusion, deterministic fingerprints, learned
free/busy/fallback ordering and confirmation permission. P7 coverage additionally
proves absent retired routes/scheduler fields, Briefing V2, Weekly Review V3,
Export V6/Snapshot V3/Prompt V4, preserved independent concepts, and the
isolated erase/rollback/final-state database contract. A documented test suite
alone is not a pass claim.
Exact current results live in
[Current Verified Baseline](../../docs/verification.md#current-verified-baseline).

Phase 10 tests use fake services/providers/process runners. They cover V4
request/SSE and V1-V3 compatibility, snapshot, provider-specific tools,
SQL/Python isolation, strict executor protocol/peer/reservation behavior,
pre-stream admission, local/global races, trace/source-scope derivation,
replay/budget/cancel/delete, and current no-fixed-mode UI without requiring
Codex, OAuth, a subscription, or network access. Scripted provider
responses prove strict envelopes and execution-path handling, not autonomous
model tool choice, false-premise judgment, or answer quality. See
[the current verification runbook](../../docs/verification.md) for the
diagnostic-only focused rerun command and
[Verification History](../../docs/verification-history.md) for superseded
deterministic evidence.
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
