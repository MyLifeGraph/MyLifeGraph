# Phase 10 Free Read-Only Coach Data Agent

## Status

The development-only Coach is implemented as a free-question, read-only
personal-data agent. The current Flutter surface no longer asks the user to
choose `Today`, `Patterns`, `Focus`, or `Review`, a time horizon, one Focus
session, prompt starter, or selected memory. One deliberate send contains only
the user's question and a retry-safe request id.

For a real local turn, FastAPI creates a fresh owner-only SQLite snapshot and
starts the logged-in local Codex CLI with one required stdio MCP server. The
agent can answer directly or use only `inspect_data`, `query_data`, and
`run_python`. FastAPI derives evidence and the compact tool trace from actual
execution; the model cannot supply either field.

The real provider remains local-development-only. Automated tests use the
deterministic fake provider and need no Codex login, network call, or OpenAI API
key. A current-machine live smoke remains separately opt-in and must not be
claimed unless it was actually run.

The earlier bounded `coach-request-v1|v2`, `coach-response-v1`,
`coach-history-v1`, context-options, and memory-selection records remain
readable for compatibility. Their newest provenance pair remains
`controlled-coach-prompt-v3`/`coach-context-v3`. The current app does not
expose or create those fixed-mode selections.

## Product Contract

The user asks an ordinary free-form question. `gpt-5.5` decides whether to:

- answer without inspecting personal data;
- inspect the catalog and available periods;
- combine one or more read-only SQL queries;
- use isolated Python for aggregation, a statistical check, or an internal
  plot;
- look for counterexamples or correct a false premise;
- explain which information is missing; or
- ask one concise clarifying question.

There is no request classifier and no requirement to produce a recommendation.
The final reply is plain English text. It may contain several reasoned
suggestions, but the Coach cannot execute, stage, or claim any product
mutation. `staged_suggestion` and visible analysis artifacts are absent from
the current response contract.

The answer must distinguish:

- observations directly supported by the snapshot;
- plausible but uncertain interpretations;
- information that is absent; and
- general explanation from model knowledge.

Observational product data does not justify causal, diagnostic, or medical
claims. Existing deterministic pre-provider and post-provider safety checks
remain authoritative.

## Runtime Topology

```text
Flutter Coach
  -> authenticated FastAPI coach-request-v3
  -> owner-locked retry claim and local-day budget
  -> fresh owner-only personal-snapshot-v1 SQLite file
  -> local Codex CLI: gpt-5.5, service_tier="fast", fast_mode=true
  -> required per-turn coach_data stdio MCP server
       -> inspect_data
       -> query_data
       -> run_python -> isolated Docker analysis container
  -> schema-validated model text
  -> backend-derived evidence, trace, and provenance
  -> atomic coach-response-v2 persistence
  -> SSE completed/failed event or non-streaming wrapper response
  -> snapshot, scripts, images, and temporary files deleted
```

The FastAPI process must run as the same Linux/WSL user whose Codex CLI login is
being used. OAuth material remains in that user's Codex home; it is not copied
to Flutter, Supabase, the repository, the snapshot, the MCP process, the
analysis container, or application logs.

The provider starts Codex in an empty private temporary working directory with
read-only sandboxing, no approvals, ephemeral execution, ignored user rules,
and a strict output schema. User-configured MCP servers, apps, plugins,
sub-agents, web search, shell execution, and file/product mutation are not
available to the turn. The single `coach_data` server is required; startup or
tool-configuration failure fails the turn.

## HTTP Contracts

All Coach routes require a valid bearer token for a canonical authenticated
non-guest profile. Guest/mock Flutter remains local and performs zero Coach
HTTP calls.

### Capabilities V2

`GET /v1/coach/capabilities` returns `coach-capabilities-v2`. It publishes:

- provider state and the exact configured provider;
- requested model and model source;
- `service_tier: "fast"` and `fast_mode: true` for
  `local_codex_oauth`;
- 2,000 message code points and 4,000 reply code points;
- the configured per-local-day allowance and remaining questions;
- at most 12 tool calls;
- a 180-second turn timeout;
- 5-second SQL and 30-second Python limits; and
- 50,000 snapshot rows and 8 MiB of serialized source data.

The fake and disabled providers report Fast as not applicable. Readiness is
fail-closed. A different model, an unavailable `gpt-5.5`, rejected Fast
configuration, missing CLI/login, absent analysis image, non-development
runtime, mock-data mode, or missing backend persistence produces honest
disabled/unavailable capability.

### Request V3

`POST /v1/coach/respond` and `POST /v1/coach/respond/stream` accept:

```json
{
  "contract_version": "coach-request-v3",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "message": "What changed in my focus consistency this semester?"
}
```

Unknown fields, blank messages, invalid UUIDs, or more than 2,000 Unicode code
points fail strict validation. There is no scope or period field.

The non-streaming route is the compatibility wrapper used by focused tests and
older clients. It also continues to accept the old strict V1/V2 requests through
the legacy service. New Flutter sends V3 through the streaming route.

### SSE

The streaming route uses `text/event-stream` and emits only:

- `started`, containing request identity and contract version;
- zero or more allowlisted `activity` messages such as
  `Preparing a private data snapshot …` or
  `Testing the data with isolated analysis …`;
- one `completed` event containing the full response; or
- one `failed` event containing the strict safe error.

Activity is a compact lifecycle signal, not hidden reasoning. Disconnecting or
pressing Cancel cancels the running request, terminates the provider process,
records an interrupted failure when possible, and cleans all turn-local files.

### Response V2

Successful current turns return:

```json
{
  "contract_version": "coach-response-v2",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "reply": "Your directly observed focus duration became more consistent...",
  "uncertainty": {
    "level": "medium",
    "reason": "There are only four completed sessions before March."
  },
  "safety": {
    "classification": "normal"
  },
  "evidence": [
    {
      "source": "focus_sessions",
      "record_count": 18,
      "period_start": "2026-01-18T09:00:00+00:00",
      "period_end": "2026-07-24T15:30:00+00:00"
    }
  ],
  "agent_trace": {
    "tool_call_count": 2,
    "steps": [
      {
        "sequence": 1,
        "tool": "inspect_data",
        "status": "completed",
        "summary": "Inspected the data catalog.",
        "row_count": null,
        "duration_ms": 4
      },
      {
        "sequence": 2,
        "tool": "query_data",
        "status": "completed",
        "summary": "Ran read-only SQL and returned 18 row(s).",
        "row_count": 18,
        "duration_ms": 9
      }
    ],
    "limitations": []
  },
  "provenance": {
    "source": "model",
    "provider": "local_codex_oauth",
    "provider_mode": "local_development_only",
    "model_requested": "gpt-5.5",
    "model_reported": "gpt-5.5",
    "model_source": "explicit",
    "prompt_version": "free-coach-agent-prompt-v2",
    "context_version": "personal-snapshot-v1",
    "generated_at": "2026-07-28T12:00:00Z",
    "provider_called": true,
    "service_tier": "fast",
    "service_tier_status": "configured",
    "fast_mode": true,
    "snapshot_row_count": 142,
    "snapshot_bytes": 87412
  }
}
```

There is no `staged_suggestion`, fixed context manifest, or chat artifact. The
model produces only `reply`, `uncertainty`, and `safety`. FastAPI reads the MCP
trace and snapshot catalog to produce the backend-owned `evidence` field, agent
trace, tool status, and provenance. Despite its contract name, `evidence` is
conservative snapshot-source coverage: its counts and periods describe the full
accessed snapshot source, not the exact rows that supported a sentence or that
one SQL query returned. An `inspect_data` call discovers schema and coverage but
does not by itself contribute row evidence. A successful SQL step contributes
the complete catalog count/period for each source it accessed, while the step's
separate `row_count` is the number of returned rows. Because arbitrary Python
table attribution is not trusted, a successful Python step records
`personal_snapshot` coverage for the entire read-only snapshot.

`GET /v1/coach/history` returns `coach-history-v2`. Each turn has the original
message and either a readable legacy `coach-response-v1` or current
`coach-response-v2`. The current UI renders both but exposes no historical mode
controls.

`DELETE /v1/coach/history` remains body-free. It removes user and assistant
message content and clears persisted V3 evidence/trace/service-tier detail while
retaining request tombstones and usage accounting. It conflicts while a turn is
active.

The context-options and memory-selection endpoints remain only for pre-V3
compatibility. The current Flutter client does not call them.

## Personal Snapshot Contract

FastAPI builds a new `personal-snapshot-v1` SQLite file for each non-safety
turn. It takes bounded export watermarks first, paginates every source with an
explicit owner filter, verifies cursor order and ownership again, and only then
writes the file. Account Export and Coach Snapshot use the same neutral
owner-data reader: all table-local watermarks finish before row collection,
independent sources load through a bounded task pool, and the resulting tables
remain in catalog order regardless of completion order. A source failure or
request cancellation cancels and settles sibling reads without exposing a
partial snapshot. Another owner's row fails the turn.

The snapshot includes the retained relevant product projections available
through the account-export boundary:

- profile timezone and planning/setup projections, excluding email, role, and
  auth-provider fields;
- notification and learning preferences;
- Setup/Intake and Study Setup;
- Daily Capture, behavioral, and lifestyle entries including retained notes;
- Tasks, Habits, outcomes, Focus sessions, and Focus reflections;
- schedule items and stored Inbox rows;
- Planner commitments, Action Plans, revisions, Task blocks, and Habit slots;
- Deadline/Preparation plans, revisions, and blocks;
- calendar connection/import summaries and imported event content, without
  credentials;
- Daily State snapshots, briefings, decision feedback, and Weekly Reviews;
- Insights, Recommendations, skillset projections, goals, and memories; and
- earlier Coach user/assistant messages.

The snapshot excludes `coach_requests`, `coach_usage_events`,
`coach_memory_selections`, authentication records, service keys, provider
internals, request-identity ledgers, operational retry state, and all other
users.

Snapshot participation is a separate field in the shared typed owner-data
catalog; it is not inferred from Account Export inclusion. This keeps the three
Coach operational tables exportable under their existing contract while
excluding them from the 37-table personal snapshot. Snapshot serialization
uses a neutral lossless-JSON helper and does not import Account Service
implementation details.

Each product table has sanitized typed columns when available plus `row_json`
containing the complete sanitized source row. `_coach_catalog` describes every
table, available columns, record count, and observed period. A separate
relationship catalog and read-only helper views make common time-series,
terminal Focus/reflection, and planning joins discoverable. Empty sources are
represented honestly.

The initial Account Export limits apply without silent truncation:

- at most 10,000 rows per source table;
- at most 50,000 rows across the snapshot; and
- at most 8 MiB of serialized sanitized source data.

Exceeding any boundary fails with `snapshot_too_large`. The snapshot is created
in a private directory, made read-only before the provider starts, and removed
in `finally` handling after completion, failure, timeout, or cancellation.

## Read-Only Tool Contract

The per-turn stdio MCP server exposes exactly three tools.

### `inspect_data`

Returns the catalog, descriptions, counts, periods, relationships, tables, and
views. It accepts no arguments and performs no mutation.

### `query_data`

Accepts one SQL string beginning with `SELECT` or `WITH`. SQLite is opened with
`mode=ro`, `immutable=1`, `query_only=ON`, and `trusted_schema=OFF`. An
authorizer permits only read/select/function operations and rejects DML, DDL,
`ATTACH`, transactions, writable pragmas, and extension/file-write functions.
There is no multi-statement execution.

Each query has a five-second progress deadline, at most 500 returned rows, and
a bounded 256 KiB result. Truncation is explicit in the tool result.

### `run_python`

Accepts one bounded Python program. It starts
`mylifegraph-coach-analysis:1` with:

- no network;
- no secrets or inherited backend environment;
- a non-root `65532:65532` user;
- read-only root filesystem;
- all Linux capabilities dropped and `no-new-privileges`;
- only `/data/personal.sqlite` mounted read-only;
- a 64 MiB temporary filesystem;
- one CPU, 512 MiB RAM, no swap growth, and at most 64 processes;
- a 30-second timeout and bounded output; and
- isolated Python with Pandas, NumPy, SciPy, Statsmodels, and Matplotlib.

The runner exposes a read-only SQLite helper and captures at most one bounded
PNG plot for the model's internal analysis. Plots are not persisted in
Supabase, returned in `coach-response-v2`, or shown in Flutter. The temporary
container and all turn files are removed after the turn.

All three tools append backend-readable JSONL facts to the private trace file.
There are at most 12 calls total, including failed calls. Tool output and all
free text are untrusted data and cannot add tools or permissions.

## Provider And Fast Contract

The real provider is exactly `local_codex_oauth`. It invokes:

- model `gpt-5.5`;
- `service_tier="fast"`; and
- `[features].fast_mode=true`.

These settings are passed explicitly for every agent turn. The provider checks
that the installed CLI exposes Fast configuration and rejects a reported model
other than `gpt-5.5`. There is no automatic model fallback and no silent
standard-tier downgrade. User-visible provenance is
`gpt-5.5 · Fast configured`.

Fast mode is currently documented by OpenAI as roughly 1.5 times the speed and,
for ChatGPT login, 2.5 times the credits. That is an operational tradeoff for
this local preview, not a product guarantee.

The normal turn limit is 180 seconds. The existing global local-provider
semaphore orders low-concurrency local requests. Per-user persistence allows at
most one pending turn and 20 newly started user questions per profile-local
day by default. Tool calls do not consume additional user-request budget.

The provider implementation keeps three explicit internal boundaries:
`local_codex.py` composes and preflights fixed command arguments,
`bounded_process.py` owns no-shell subprocess execution, byte/event limits,
timeouts, and process-group termination, and `codex_events.py` owns the strict
allowlisted event/output state machine and failure classification. The latter
two receive no Settings, Supabase client, request repository, or owner data.
This split changes no CLI arguments, tool allowlist, model/tier check, output
schema, cleanup, timeout, or persisted provenance.

## Persistence And Replay

Migration
`20260728160000_free_read_only_coach_agent_v1.sql` is additive. It:

- admits `coach-request-v3` while retaining V1/V2 rows;
- adds bounded evidence, agent trace, tool-count, and service-tier columns;
- validates the exact `coach-response-v2` and trusted provenance pairing;
- adds the service-role-only `claim_coach_request_v3` and
  `complete_coach_request_v2` RPCs;
- binds V3 replay to owner, request id, and message fingerprint only;
- preserves owner-before-request lock order, one pending owner turn, terminal
  replay behavior, and the local-day budget; and
- extends history deletion to remove V3 detail without resetting usage or
  request identities.

Migration `20260729160000_coach_english_prompt_v2.sql` is also additive. It
admits paired `free-coach-agent-prompt-v1|v2` provenance, exposes only the
service-role-only `claim_coach_request_v4`, and advances only a newly claimed
pending request to V2. An existing V1 request or terminal response keeps its
original prompt provenance on exact replay.

Migration `20260802111518_privileged_function_lint_cleanup.sql` redefines the
same service-role-only `claim_coach_request_v3` contract with a
`pg_catalog, pg_temp` search path and `PERFORM` for the intentionally discarded
expiry-failure result. Request validation, owner/request/row lock order,
interrupted state, usage-ledger truth, replay output, signature, and grants are
unchanged.

Application roles receive no new Coach write authority. Authenticated owners
retain only the intended bounded reads. The FastAPI service role remains the
only normal claim/complete/fail/delete mutation path.

FastAPI composes one neutral internal Coach turn lifecycle for both the legacy
fixed-mode service and the current free-agent service. It owns account
eligibility, claim/replay state translation, atomic completion/failure
confirmation, the shared 50-turn history bound, and history deletion conflict
handling. Legacy context assembly and current V3 snapshot/tool orchestration
remain separate, including their persisted response and tombstone semantics.

Retrying the same V3 request id and exact message replays the stored terminal
result. Reusing that id with another message conflicts. A completed, failed,
deleted, or still-active request is never reinterpreted as a new question.
Expired leases are accounted as interrupted failures before retry state is
returned.

## Safety And Trust Boundaries

- Setup text, notes, memories, imported calendar content, earlier chat, SQL
  values, and Python output are data, never instructions.
- `free-coach-agent-prompt-v2` requires English in every visible response field
  regardless of the question or stored-data language. Clearly German reply or
  uncertainty output fails as retryable `invalid_output` and is not stored as
  an assistant message.
- The agent receives no service-role credential, Supabase URL, OAuth file,
  general host filesystem, host shell, network tool, app, plugin, sub-agent, or
  mutation endpoint.
- Direct deterministic safety redirects may bypass snapshot/provider creation.
  Post-provider safety may replace unsafe model text while retaining truthful
  `provider_called`.
- The final reply contains no chain-of-thought. SSE activity and persisted
  traces expose only tool names, completion state, bounded summaries, counts,
  durations, data ranges, and limitations.
- Model-produced evidence, counts, tool traces, provenance, or mutation claims
  are ignored because those fields are backend-owned.
- The Coach is informational. It must not claim causal, diagnostic, or medical
  certainty from these observational records.

## Flutter Contract

Coach remains the fifth development-gated shell destination. Today, Insights,
Quick actions, Planner, Coach, and Settings share the same top action group:
page-specific actions such as Refresh first, an unread Coach result second, and
Settings last. Settings is pushed so Back returns to the originating main page;
on Settings its filled control remains visible, selected, and does not push
again. Loading, empty, and error states retain the same actions. Sub-pages,
Auth, Setup, and Capture flows remain outside this header contract. Release
builds and `APP_ENV=production` hide Coach regardless of Flutter defines.

Flutter Coach contract models and SSE envelopes reuse framework-neutral strict
key, object, text, integer, UUID, and aware-timestamp primitives. Coach-specific
provenance, safety, trace, evidence, replay, and feature error rules remain in
the Coach layer; persisted V1/V2 history and current wire formats are unchanged.

The profile-bound Coach controller lives for the app session rather than the
Coach route. Its draft is the field's source of truth, and its request id and
active SSE subscription survive navigation among shell pages. Success clears
the draft; failure and explicit Cancel retain it. Logout, profile change,
loss of Coach eligibility, and app teardown dispose the controller, cancel an
active response, and clear all local draft/answer/notice state. Flutter route
navigation alone does not close the SSE stream. The backend contract remains
unchanged: a real disconnect or explicit Cancel may still terminate the turn.

A separate in-memory `CoachTurnNotice` contains only profile id, request id, and
`completed|failed`. It is never persisted and never initiates an API request.
Successful turns and non-user-cancel failures show a Coach icon with `!` on all
six covered pages. The icon opens a dismissible floating message without
navigating:

- success: `Your Coach answer is ready.`;
- failure:
  `Coach could not finish the answer. Open Coach to review or retry.`.

Closing that message leaves the unread icon intact. Opening Coach also does not
read it. For the latest successful response, an invisible marker follows Reply
and Uncertainty and precedes the optional `Data and analysis details`.
Scroll/layout notifications acknowledge the exact notice only when that marker
is fully within the current scroll viewport; a short fully visible response is
therefore read after its first layout. Historical turns, the start of a long
answer, and expansion of later analysis details do not acknowledge it. The
failure marker follows the visible error and retry copy; reaching it or
starting a subsequent retry acknowledges the failure. Explicit Cancel creates no
notice.

Header controls have 44 by 44 logical-pixel targets, keyboard focus, unique
tooltips/semantics, and wrapping layout that remains usable at 320 logical
pixels with 200-percent text.

Inside Coach, the current surface contains:

- capability/status and remaining-question truth;
- persisted conversation history;
- one free text field and Send;
- a Cancel action only while a stream is active;
- short safe activity text;
- Clear history; and
- an expandable `Data & analysis` section below each current answer.

The detail section labels the backend-owned `evidence` rows as
`Snapshot source coverage`. It shows conservative source periods/counts,
SQL/Python/inspection steps, limitations, and technical provenance. It does
not imply that every covered row was returned by a query or used in the prose,
and it does not show plots, raw hidden reasoning, mode controls, time-horizon
controls, Focus selectors, prompt buttons, memory selectors, or structured
action cards.

All visible Coach UI and model-facing reply copy is English.

## Local Preparation

Build the pinned analysis image explicitly before a presentation:

```bash
npm run prepare:coach-analysis
```

The local Coach stack command verifies the image revision and builds it when it
is missing or stale:

```bash
npm run start:local:coach
```

The normal deterministic path remains:

```bash
npm run start:local:coach:fake
```

The live command additionally requires a current `codex login`, a CLI version
that supports `gpt-5.5` Fast configuration and required stdio MCP servers,
Docker, local Supabase, applied migrations, and the development Coach surface
gate. See [Local Development](local-dev.md) for the complete runbook.

## Verification Contract

Standard deterministic automation must prove:

- strict scripted direct-answer paths can finish with zero tool calls;
- scripted multi-tool traces can combine SQL calls and represent full retained
  source periods;
- the isolated Python tool supports statistical code and one internal plot
  without a visible artifact;
- SQL cannot write, attach, change pragmas, load extensions, or bypass limits;
- Python cannot reach the network, host files, Supabase, Codex OAuth, service
  secrets, or product mutation paths;
- prompt injection embedded in Setup, notes, memories, and calendar content
  cannot add tools or authority;
- tool count, query/result/output limits, cancellation, timeout, provider
  errors, missing/stale image, oversized snapshots, replay conflicts, one
  active turn, daily budget, and history deletion fail safely;
- conservative source coverage and trace are derived from actual MCP records:
  inspection alone adds no row coverage, SQL has separate returned-row counts,
  and Python records full-snapshot read scope;
- the authenticated onboarding-empty API path answers without inventing
  personal history, while the seeded student account renders honestly; reload
  retains current and legacy history; and
- the UI has no fixed mode, horizon, Focus, prompt-starter, memory-selection, or
  staged-action surface;
- draft and retry identity survive shell navigation, an active stream completes
  away from Coach without cancellation, and profile/app teardown still
  cancels and clears local state; and
- every covered page/state retains the ordered accessible header actions,
  Settings push/Back works, the popup does not consume or navigate, and only
  the latest answer-end or failure/retry marker acknowledges its exact notice.

Standard tests use the deterministic fake provider. They do not prove a real
model, autonomous tool choice, false-premise judgment, semantic quality, OAuth
login, Fast acceptance, Docker daemon, or external service. The system-prompt
tests enforce instructions for missing information, counterexamples, and
clarifying questions; only a real-model evaluation can assess how well a model
follows them.

The opt-in live smoke must record current-machine evidence that:

- Codex accepted a strict explicit `gpt-5.5` invocation with no fallback, and
  any reported model matched it;
- Fast was explicitly configured and not downgraded;
- the required data MCP started;
- a complex synthetic-data question completed through multiple allowed tools;
  and
- the emitted tool trace and source-scope provenance match that provider
  execution.

This provider smoke does not pass through FastAPI persistence or Flutter.
Deterministic API/browser tests separately prove request replay, persisted
response/history, deletion, budget behavior, and the expandable UI.

Coach service factories and bearer verification now share the single
application-lifespan-owned Supabase HTTP pool. This is transport reuse only:
provider selection, owner locks, snapshots, evidence limits, budgets, retry
identity, cancellation, deletion, and read-only tool authority are unchanged.

The Coach API's structured service, invalid-request, and sanitized unavailable
problems now live in its feature-owned HTTP translator. The existing JSON/SSE
detail objects, status codes, deliberate unexpected-error sanitization, and
stream failure behavior are unchanged; no global exception handler is added.

## Explicitly Later

- a production Responses API provider and deployable credential strategy;
- scalable remote snapshot and sandbox workers;
- deployed multi-user concurrency, queues, and cancellation control plane;
- push/background Coach turns;
- writable or executable Coach actions;
- persisted or user-visible analysis plots; and
- automatic planning, calendar, notification, task, habit, or memory mutation.

This local architecture keeps the future provider seam visible without claiming
that a local Codex OAuth process is a production multi-user service.
