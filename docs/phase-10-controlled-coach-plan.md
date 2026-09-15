# Phase 10 Free Read-Only Coach Data Agent

Optional Android push uses an API-only Firebase credential. `FCM_*` is forbidden
in the separate executor environment, and the local development subprocess
allowlist excludes it. No Coach provider, model, tool or execution behavior is
changed by adding that secret-isolation guard.

Optional Health Connect observations are readable through the existing owner-only
`behavioral_events` snapshot source. Its catalog explicitly labels device-reported
calendar-day totals and forbids adding them to overlapping manual check-ins.
Only the public account consent preference is included; latest mutation replay
payloads are excluded. No provider authority, prompt version or tool changes.

After authenticated profile initialization, the client restores the device-local,
profile-scoped provider choice; without a saved choice it preselects Project Coach
(`Standard (provided)`). Only the provider name is saved in preferences, never a
key. The separate Gemini model choice is also profile-scoped and device-local.
Its compact dropdown offers 3.6, 3.7 and 3.8 Flash, retaining 3.8 as the default.
Changing the choice preserves the draft but clears exact-retry identity; no
question is sent automatically. Web keys remain tab-memory-only, so a restored BYOK choice can require key
entry after reload. Sign-out clears keys but retains this non-secret preference;
another account does not inherit it. Personal OpenAI/Gemini keys remain opt-in. Every request
still names its provider explicitly, with unchanged server admission and no
fallback. The selector remains available when capabilities fail, with or without
saved history. The chat has a fixed 8px top inset inside its outline.
Capability reads and sends await credential initialization, so the first read
already names the restored choice or Standard instead of racing the stored-key load. This wait does
not replace a subsequent explicit provider choice or bypass storage failures.

The composer model control opens a bottom sheet with all three provider options
directly selectable. Each option has independent Info opening its explanation
in a dialog without selecting that provider. Standard selection closes the sheet;
personal-key options retain the existing key test/save/delete controls inside it.
Errors remain visible above the chat. Opening the sheet or switching providers
never sends a question. Settings no longer duplicates these provider controls.

A provider change during an in-flight capability refresh clears the old budget
and queues a fresh read; the superseded result cannot restore the previous
provider's limits. Capability and completed-response identities must match the
explicit provider. Old upstream `account_limit` errors use provider-neutral
client copy, not Codex wording. Quotas remain unchanged: the non-operator
20-turn local-day limit is account-wide, while Standard has separate 5-per-user
and 15-global UTC-day dispatch limits. Gemini never dispatches through Codex.
Rejected BYOK selections (disabled provider or missing key) return unavailable
before probing any base provider. Their capability read must not ask Codex for
availability or forward its account-quota error under a Gemini identity.

Remaining turns sit beneath the selected model name in the composer control,
not in the page header, preserving room for the Coach title on narrow screens.
The count and its period tooltip retain the server-provided budget semantics.

The permanent chat outline starts below the fixed capability status card and
continues through the fixed bottom composer. Only the timeline scrolls within
the frame, including when messages exist. Opening or refreshing loaded history
positions it at the newest message; typing does not reset the scroll position.
A small circular down-arrow inside the timeline appears when more than 48px
remain below the viewport, returns to the latest message, and hides at the bottom.
The empty invitation adds one non-interactive example question. Optional Coach
information opens in a dialog so expanded copy cannot push the fixed panels away.
At very small remaining heights the composer participates in that same chat
viewport instead of creating another scroll region or clipping its controls.

An empty, successfully loaded chat shows a softly outlined
`Ask your coach anything` invitation with one example, without a redundant
empty-history notice. Loading, failed
history reads, active requests, and existing messages do not show that invitation.

## Explicit-provider V4 extension (current repository contract)

The additive `coach-language-v1` extension accepts `response_language: de` with
`language_contract: coach-language-v1` on `coach-request-v4`. Omitted language
defaults to English and preserves the existing body, prompt and message hash.
German changes only the trusted output-language instructions of the V5 base
prompt; its named extension is included in the prompt and request fingerprint.
User text, notes and tool output cannot choose or override response language.
The existing response/provenance shape, grants, quotas and stored messages remain
unchanged. The additive `coach_language_completion` migration is required so
completion accepts the existing German fingerprint; no table or public RPC
signature changes. The exact raw text is retained and changed-text/language
replays remain rejected. Deploy the
updated API before using German requests; older APIs reject the opt-in extension
rather than silently answering in a different language. Existing English clients
remain compatible. This is independent of the pending Gemini model rollout.

The Coach header flag toggles English/German directly and saves the preference
on the current device, separately from the Ultra Quick speaking-guide language.
Language is frozen for an in-flight or exact-retry request; a new question uses
the latest choice. Neither flag sends a request or translates existing history.

The current public contracts are `coach-capabilities-v5`,
`coach-response-v4`, and `coach-history-v4`, paired with
`coach-request-v4`, `personal-snapshot-v3`, and
`free-coach-agent-prompt-v5`. V4 keeps the message-only body and makes the
provider choice mandatory so the separately gated `operator_codex_pilot` mode
is represented honestly. Persisted V1/V2 responses and the V3 BYOK path remain
readable for rolling compatibility.

OpenAI BYOK uses the Responses API and exact `gpt-5.6-terra`; Gemini BYOK uses
the Interactions API with an explicitly selected `gemini-3.6-flash`,
`gemini-3.7-flash`, or `gemini-3.8-flash` (default). The REST adapter sends
`Api-Revision: 2026-05-20`, consumes the current `steps` timeline, preserves
every returned model/thought/function step during stateless tool continuation,
and uses the current text/JSON-schema response format. Both loops set
`store:false`, replay only the bounded current tool exchange, and expose
`inspect_data` and `query_data`. Contract fixtures reject the removed Gemini
`outputs` shape, but an authorized live Gemini smoke remains a release gate.
Both adapters reject a parallel batch before executing any call when the
cumulative 12-call allowance would be exceeded, cap retained tool-result
history at 512 KiB, and stream provider responses through a 256-KiB decoded
body limit before JSON parsing. Output/step and content-block counts are also
bounded; provider batching cannot turn a 12-call contract into extra SQL work.
The private development Codex adapter and the
separate pilot executor additionally expose isolated `run_python`.

The client supplies the explicit provider in
`X-MyLifeGraph-Coach-Provider`; only OpenAI/Gemini also supply a request-local
key in `X-MyLifeGraph-Coach-Api-Key`. FastAPI never persists or emits a key and
never falls back between modes. Coach capability/respond routes additionally
accept optional `X-MyLifeGraph-Coach-Model`, restricted to the three exact Gemini
IDs. Omission preserves the existing default. Claim/provenance records bind the
selected ID, and the client rejects a capability or response using another ID.
Deploy the additive 3.7 allowlist and updated API/client before using that model;
old clients cannot parse 3.7 history. This choice does not change Ultra Quick's
existing default-model extraction path. Hosted CORS allowlists these headers and exposes
the bounded `Retry-After` header. Service-role-only
`claim_coach_request_v8`, `complete_coach_request_v3`, and the operator
dispatch RPCs preserve advisory-lock order, retry identity, local/global
budgets, append-only usage, RLS, and grants.

Google HTTP-400 `API_KEY_INVALID` is recognized from at most 16 KiB of error
JSON (object or array). Only the fixed reason is retained; provider text and keys
are never logged or returned. It remains the compatible `provider_failure` SQL
code with a clear key-replacement message and `retryable:false`. Provider timeout,
quota and model-unavailable messages identify the selected provider, not local Codex.

## Status

The opt-in Windows Cloud-account launcher connects the local browser to the
existing Pilot API with its real Cloud bearer. Project Coach remains subject to
that API's normal explicit-provider admission and budgets; Development provider
guards are not relaxed. See `docs/local-dev.md` for the private loopback transport.

The Coach is implemented as a free-question, read-only personal-data agent.
The current Flutter surface no longer asks the user to
choose `Today`, `Patterns`, `Focus`, or `Review`, a time horizon, one Focus
session, prompt starter, or selected memory. One deliberate send contains only
the user's question and a retry-safe request id.

For every non-safety real turn, FastAPI creates a fresh owner-only SQLite
snapshot and derives evidence plus the compact tool trace from actual
execution; the model cannot supply either field. Request-scoped OpenAI and
Gemini BYOK providers may
use only `inspect_data` and `query_data` and receive bounded tool results rather
than the SQLite file. The private local Codex provider additionally starts one
required stdio MCP server and may use isolated `run_python`.

The current real-provider seams are OpenAI and Gemini with a user-supplied key,
the local-development-only Codex OAuth adapter, and the repository-implemented
`operator_codex_pilot` adapter. The operator path is disabled by default and
uses a distinct Unix-socket executor rather than giving FastAPI Codex OAuth or
Docker access. None of these seams has passed the full public-host acceptance
gate. Automated tests use deterministic fakes and need no Codex login, network
call, or live provider key. Live checks remain separately opt-in and must not
be claimed unless they were actually run.

The requested VPS CLI upgrade pins Codex 0.153.4 without changing the explicit
`gpt-5.5`/Fast selection. A content-hash-bound copy of the complete selected
model metadata now disables model-driven shell, apply-patch and tool-search
capabilities without replacing its reasoning, instruction or service-tier
metadata. Both Codex response paths additionally disable web search, planning
and user-input tools. Missing, changed or non-regular profile files fail before
CLI dispatch, including after cached readiness. Configuration requires the
documented explicit `gpt-5.5` model. Hosted CLI version pinning remains mandatory;
the optional local-development version setting is not proof of compatibility
with another CLI version.

The resulting raw data-agent request has six tools: the three Coach data tools and
three built-in MCP resource helpers. Only `inspect_data`, `query_data` and
`run_python` have successful data-operation authority. The sole Coach server
advertises no resources and rejects resource list/template/read methods,
including `file://` URIs, without reading files or touching the snapshot/trace.
Existing strict event rejection and read-only sandboxing remain unchanged;
resource-helper attempts can fail a turn, and this is not a claim that only
three tool names are visible. Do not substitute hooks as the security boundary:
Codex hook errors can fail open. Offline acceptance remains distinct from
authenticated provider and target-host acceptance; keep the shared provider
disabled until those gates pass.
The legacy response path configures no MCP server and retains its separate
tool-free behavior; it receives the same built-in restrictions.

FastAPI now resolves its Supabase persistence credential from the current
`SUPABASE_SECRET_KEY` name with a legacy service-role fallback; the current key
wins during rotation. Hosted `staging` and `pilot` startup also bind the
Supabase URL to the expected project ref, and `pilot` requires the current
secret format. This configuration does not make the private same-user Codex
adapter a hosted provider: it still requires exact `APP_ENV=development`.
Hosted shared turns instead require exact `staging|pilot`,
`OPERATOR_CODEX_PILOT_ENABLED=true`, a dedicated executor UID, a
peer-authenticated Unix socket, a checksum-pinned Codex binary, and the exact
executor-owned rootless Docker socket. The Codex child environment is
allowlisted and excludes current and legacy Supabase backend-key names, so
neither persistence credential crosses the provider boundary.

The bounded controlled `coach-request-v1|v2` / `coach-response-v1` service
remains backend-supported for ordinary Coach advice. Its newest provenance pair
is `controlled-coach-prompt-v3`/`coach-context-v3`. The current Flutter surface
does not expose fixed-mode selections, but P7 does not revoke those backend
writers. Pre-cutover Coach content is erased and its request/usage identities
remain as content-free tombstones.

## Product Contract

The user asks an ordinary free-form question. The explicitly selected provider
decides whether to:

- answer without inspecting personal data;
- inspect the catalog and available periods;
- combine one or more read-only SQL queries;
- when either explicit Codex mode is selected, use isolated Python for
  aggregation, a statistical check, or an internal plot;
- look for counterexamples or correct a false premise;
- explain which information is missing; or
- ask one concise clarifying question.

There is no request classifier and no requirement to produce a recommendation.
The final reply is plain English text by default, or German with the explicit
language extension. It may contain several reasoned
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
  -> authenticated FastAPI coach-request-v4 plus explicit provider header
  -> message-only safety check
  -> pre-stream provider admission (or deterministic safety bypass)
  -> owner-locked retry claim and local-day budget
  -> fresh owner-only personal-snapshot-v3 SQLite file
  -> explicitly selected provider
       -> OpenAI gpt-5.6-terra or Gemini gemini-3.8-flash with request BYOK
            -> inspect_data and query_data through bounded FastAPI tool results
       -> local Codex CLI: gpt-5.5, Fast, development only
            -> required per-turn coach_data stdio MCP server
            -> inspect_data, query_data, isolated-Docker run_python
       -> operator_codex_pilot: API -> bounded peer-UID Unix socket
            -> dedicated mylifegraph-coach -> pinned Codex + rootless Docker
            -> one-use reservation + durable UTC-day dispatch ledger
  -> schema-validated model text
  -> backend-derived evidence, trace, and provenance
  -> atomic coach-response-v4 persistence
  -> SSE completed/failed event or non-streaming wrapper response
  -> snapshot, scripts, images, and temporary files deleted
```

For the current private local adapter only, FastAPI must run as the same
Linux/WSL user whose Codex CLI login is being used. OAuth material remains in
that user's Codex home; it is not copied to Flutter, Supabase, the repository,
the snapshot, the MCP process, the analysis container, or application logs.
This same-UID local-development arrangement is not the VPS boundary. The
repository now provides the separate executor identity, strict framed protocol,
and deployment templates; only target-host installation and live acceptance
remain outside repository evidence.

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

### Capabilities V5

`GET /v1/coach/capabilities` returns `coach-capabilities-v5` for the current
explicit selection. It publishes:

- provider state, provider mode, and the exact selected/configured provider;
- requested model and model source;
- `inspect_data|query_data` for OpenAI/Gemini BYOK and those tools plus
  `run_python` for private local Codex;
- `service_tier: "fast"` and `fast_mode: true` for local/operator Codex;
  BYOK reports those fields as not applicable;
- 2,000 message code points and 4,000 reply code points;
- 20 per-local-day turns for BYOK/local or 5 operator turns, plus the
  operator-only 15-dispatch UTC-day global limit and remaining values;
- at most 12 tool calls;
- a 180-second turn timeout;
- 5-second SQL and 30-second Python limits; and
- 50,000 snapshot rows and 8 MiB of serialized source data.

The fake and disabled providers report Fast as not applicable. Readiness is
fail-closed. BYOK requires an allowlisted provider and a request-local key; the
local adapter additionally requires exact `gpt-5.5`, Fast configuration,
CLI/login, analysis image, and a development runtime. The operator capability
comes only from the executor and never from core readiness. Any failed
prerequisite produces an honest disabled/unavailable capability.

### Request V4

`POST /v1/coach/respond` and `POST /v1/coach/respond/stream` accept:

```json
{
  "contract_version": "coach-request-v4",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "message": "What changed in my focus consistency this semester?"
}
```

Unknown fields, blank messages, invalid UUIDs, or more than 2,000 Unicode code
points fail strict validation. There is no scope or period field.

The non-streaming route is the compatibility wrapper used by focused tests and
older clients. It also continues to accept strict V1/V2 requests through the
legacy service and message-only V3 for rolling BYOK clients. New hosted Flutter
sends V4 through the streaming route and refuses to send until a mode is
selected.

### SSE

The streaming route uses `text/event-stream` and emits only:

- `started`, containing request identity and contract version;
- zero or more allowlisted `activity` messages such as
  `Preparing a private data snapshot …` or
  `Testing the data with isolated analysis …`;
- one `completed` event containing the full response; or
- one `failed` event containing the strict safe error.

Activity is a compact lifecycle signal, not hidden reasoning. Disconnecting or
pressing Cancel cancels the running provider call, terminates its local process
when one exists, records an interrupted failure when possible, and cleans all
turn-local files.

Provider admission happens before `StreamingResponse` commits headers or emits
`started`. A non-safety operator turn first acquires a one-use executor
reservation; ordinary providers acquire their bounded in-process slot. A busy
turn returns HTTP `429 provider_busy` with `Retry-After: 15`, consumes no
request identity or budget, and can be retried manually with the same id and
message. The deterministic safety bypass claims and accounts the ordinary
owner request but consumes neither a provider reservation nor global operator
budget.

### Response V4

Successful current turns return:

```json
{
  "contract_version": "coach-response-v4",
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
    "provider": "operator_codex_pilot",
    "provider_mode": "operator_subscription_pilot",
    "model_requested": "gpt-5.5",
    "model_reported": "gpt-5.5",
    "model_source": "explicit",
    "prompt_version": "free-coach-agent-prompt-v5",
    "context_version": "personal-snapshot-v3",
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

`GET /v1/coach/history` returns `coach-history-v4`. Current turns use
`coach-response-v4`; persisted controlled `coach-response-v1` and free-agent
V2/V3 turns remain readable. The current UI renders compatible history but
exposes no historical mode controls.

`DELETE /v1/coach/history` remains body-free. It removes user and assistant
message content and clears persisted V3/V4 evidence/trace/service-tier detail
while retaining request tombstones, operator dispatch accounting, and usage
accounting. It conflicts while a turn is active.

The context-options and memory-selection endpoints remain only for pre-V3
compatibility. The current Flutter client does not call them.

## Personal Snapshot Contract

FastAPI builds a new `personal-snapshot-v3` SQLite file for each non-safety
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
- Daily State snapshots, briefings, and Weekly Reviews;
- Insights, skillset projections, and memories; and
- earlier Coach user/assistant messages.

Goals, generic Recommendations, and Decision Feedback are absent from the source
catalog. Current Weekly Review V3 rows carry no Feedback facts or proposals.

Current normalized Daily State context accepts historical V1/V2 and current
`explainable-daily-state-v3`, but exposes the V3 shape: no Day Shape field,
`constrained_capacity` risk, or retired Day-Shape reason/evidence. Historical
Daily Capture JSON can still appear only as explicitly untrusted owner data in
the full personal snapshot; it is not promoted into Coach instructions.
The bounded typed Daily Log evidence projection admits `sleep_quality` only
from a valid current V4 branch, a current V5 branch, or an explicit V4
compatibility branch inside V5. It drops mixed-version identities, raw clocks,
capture ids, and Capture free text.

The snapshot excludes `coach_requests`, `coach_usage_events`,
`coach_memory_selections`, authentication records, service keys, provider
internals, request-identity ledgers, operational retry state, and all other
users.

Snapshot participation is a separate field in the shared typed owner-data
catalog; it is not inferred from Account Export inclusion. This keeps the three
Coach operational tables exportable under their existing contract while
excluding them from the 37-table personal snapshot. The snapshot includes the
finite Assignment Series identity/revision/membership projections so the Coach
can describe confirmed coursework cadence without gaining mutation authority.
Private `multi-exam-plan-v1` batch metadata is derived retry/orchestration state
and is absent from `personal-snapshot-v3`; confirmed child content remains
visible through the existing Deadline plan/revision/block projection. Exposing
balance history would require a new snapshot contract version rather than a V2
shape change.
Snapshot serialization
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

OpenAI/Gemini BYOK expose only the bounded `inspect_data` and `query_data`
results through their provider APIs. Each local/operator Codex turn starts one
required stdio MCP server that exposes exactly three tools.

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

Accepts one bounded Python program. It starts the content-validated local
`mylifegraph-coach-analysis:1` image or the hosted release-owned
`mylifegraph-coach-analysis:sha256-<revision>` image with:

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
Supabase, returned in `coach-response-v4`, or shown in Flutter. The temporary
container and all turn files are removed after the turn.

All three tools append backend-readable JSONL facts to the private trace file.
There are at most 12 calls total, including failed calls. Every OpenAI/Gemini
provider request in the stateless tool loop has a server-side 4,096-output-token
ceiling; the independent 256-KiB decoded-response cap protects local parsing
after generation. Tool output and all
free text are untrusted data and cannot add tools or permissions.

## Provider Contracts

The current cloud providers are request-scoped `openai` and `gemini` adapters
behind the empty-by-default `COACH_BYOK_PROVIDERS` allowlist. They require a
user-supplied key, use exact `gpt-5.6-terra` and `gemini-3.8-flash`
respectively, set `store:false`, expose only inspect/query tools, and never
persist a key or fall back to another provider.

The additive Gemini 3.8 migration admits 3.8 alongside 3.6 in the existing
private response validator and both internal claim paths. Old 3.6 rows retain
their original provenance; requested/reported model mismatches remain invalid.
Wire versions are unchanged. Deploy the compatible client, then migration, then
API; older clients that only accept 3.6 need updating before using Gemini 3.8.
No operator/Standard or OpenAI behavior changes. The official model identifier
is documented in [Google's model reference](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash).

The private development provider is exactly `local_codex_oauth`. It invokes:

- model `gpt-5.5`;
- `service_tier="fast"`; and
- `[features].fast_mode=true`.

These settings are passed explicitly for every agent turn. The provider checks
that the installed CLI exposes Fast configuration and rejects a reported model
other than `gpt-5.5`. There is no automatic model fallback and no silent
standard-tier downgrade. User-visible provenance is
`gpt-5.5 · Fast configured`.

The hosted pilot provider is exactly `operator_codex_pilot` with mode
`operator_subscription_pilot`. FastAPI holds no Codex state and cannot use the
analysis daemon. It talks only to `mylifegraph-coach` over a length-prefixed Unix
socket. Linux `SO_PEERCRED` admits one configured non-root API UID; the protocol
accepts only capability, reserve, release, and one-use execute frames with
fixed byte/deadline/schema bounds. The executor alone owns the pinned Codex
binary, OAuth home, rootless Docker socket, and temporary snapshot. A 240-second
lease encloses the 180-second turn. Disconnect, timeout, malformed frames,
wrong peer UID, duplicate reservation use, or executor loss fail closed.
`reserve` is a capacity-only operation and performs no potentially slow CLI
probe, so FastAPI bounds the pre-stream decision to one second. Provider/model/
login/image readiness remains an explicit capability/turn check after the slot
is owned and before any dispatch is recorded.

The 2026-08-19 compatibility spike inspected the published, pinned
`openai-codex==0.147.0` Python SDK without adding it to this service. Its public
surface has read-only sandboxing, structured output, Fast/model parameters,
streaming, and interruption, but it necessarily launches the same version's
explicitly experimental `codex app-server`; its environment option also merges
with the parent environment. The spike therefore failed the agreed
non-experimental/child-isolation gate, and the already bounded `codex exec`
adapter remains authoritative.

Fast mode is currently documented by OpenAI as roughly 1.5 times the speed and,
for ChatGPT login, 2.5 times the credits. That is an operational tradeoff for
this local preview, not a product guarantee.

The normal turn limit is 180 seconds. The existing global local-provider
semaphore orders low-concurrency local requests. Per-user persistence allows at
most one pending turn and 20 newly started questions per profile-local day for
non-operator modes. Operator turns allow 5 per UTC day and at most 15 durably
recorded dispatches per UTC day across the pilot. The separate
`operator_budget_utc_date` preserves the profile-local conversation
`local_date` while preventing timezone changes from minting another operator
allowance. Tool calls do not
consume additional user-request budget. A serialized global-limit race is
persisted as terminal `provider_limit`, mapped to 429 in both HTTP and SSE
clients, and never falls through to an unconfirmed pending request.

The provider implementation keeps three explicit internal boundaries:
`local_codex.py` composes and preflights fixed command arguments,
`bounded_process.py` owns no-shell subprocess execution, byte/event limits,
timeouts, and process-group termination, and `codex_events.py` owns the strict
allowlisted event/output state machine and failure classification. The latter
two receive no Settings, Supabase client, request repository, or owner data.
The Codex child receives neither `DOCKER_HOST` nor `XDG_RUNTIME_DIR`; built-in
shell and unified-exec tools are disabled. Only the required `coach_data` MCP
subprocess receives the exact rootless socket and fixed analysis-image inputs.
This split changes no CLI arguments, tool allowlist, model/tier check, output
schema, cleanup, timeout, or persisted provenance.

The analysis image now pins the exact multi-architecture Python base-image
digest and installs a complete pip-compiled dependency graph with required
hashes and binary-only resolution. Its capability revision uses one stable,
path-independent content fingerprint over the Dockerfile, dependency lock, and
runner. Building through `current` and executing through its resolved release
path therefore produce the same identity, while any effective image-input
change invalidates the old image. VPS releases additionally derive a unique
`sha256-<revision>` image tag, load it from release-owned environment after
mutable configuration, and retain the prior tag so rollback restores code and
analysis runtime together.

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

Migration
`20260813200057_retire_recommendations_and_decision_feedback.sql` erases stored
Coach messages/selections and content-tombstones every existing request while
retaining append-only usage identity. New free-agent claims use the
service-role-only `claim_coach_request_v6` and exact V4/V3 prompt/snapshot pair;
V5 and older free-agent claim wrappers are no longer executable. Controlled
Coach V1/V2 claims, response-v1 completion, failure, and history deletion stay
service-role-only and functional. Current evidence and used-context validators
reject structured Recommendation or Decision Feedback sources.

Migration `20260819203000_coach_operator_pilot_v1.sql` is additive. It admits
the named V4 request/response/capability/history family and exact operator
provider/mode provenance while retaining V1-V3 rows. It adds
`provider_dispatch_required`, service-role-only `claim_coach_request_v8` and
`complete_coach_request_v3`, and forced-RLS
`coach_operator_daily_budgets`/`coach_operator_dispatches`. The first is a
user-independent one-row-per-UTC-day aggregate that survives account deletion;
the second is owner-linked anti-replay metadata and cascades with its request.
Application roles have no access, reservations are unique, the UTC-day limit
is serialized and incremented transactionally before dispatch, exact replay
does not increment, terminal transitions are replay-safe, and startup
reconciliation turns an expired dispatched request into an accounted
interruption. User-visible outcomes remain in
`coach_usage_events`, so the strict 41-table `account-export-v6` shape is not
widened.

FastAPI confirms the owner-visible request completion or failure before it
terminalizes the private dispatch row. If that persistence response is
ambiguous, the dispatch deliberately remains `dispatched`; startup
reconciliation reads the durable request truth and closes the ledger without a
second provider call.

Application roles receive no new Coach write authority. Authenticated owners
retain only the intended bounded reads. The FastAPI service role remains the
only normal claim/complete/fail/delete mutation path.

FastAPI composes one neutral internal Coach turn lifecycle for both the legacy
fixed-mode service and the current free-agent service. It owns account
eligibility, claim/replay state translation, atomic completion/failure
confirmation, the shared 50-turn history bound, and history deletion conflict
handling. Legacy context assembly and current V4 snapshot/tool orchestration
remain separate, including their persisted response and tombstone semantics.

Retrying the same V4 request id, exact message, and provider replays the stored
terminal result. Reusing that id with another message or provider conflicts. A
completed, failed, deleted, or still-active request is never reinterpreted as a
new question. Expired leases are accounted as interrupted failures before
retry state is returned. A recorded operator dispatch is never repeated after
an ambiguous API/executor crash and always continues to consume global budget.

## Safety And Trust Boundaries

- Setup text, notes, memories, imported calendar content, earlier chat, SQL
  values, and Python output are data, never instructions.
- Compatible `free-coach-agent-prompt-v4` and current
  `free-coach-agent-prompt-v5` require English in every visible response field
  unless a V4 request explicitly activates `coach-language-v1` for German.
  That extension changes reply/uncertainty and deterministic safety language,
  not clinical/causal, mutation, tool or data-access restrictions. Default English is enforced
  regardless of the question or stored-data language. In English mode, clearly
  German reply or uncertainty output fails as retryable `invalid_output`; in
  German mode clearly English prose is likewise rejected. Rejected output is not stored as
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

The discreet Coach composer source icon manages one
device-persisted selection: Server (default), or a downloaded on-device model.
On-device inference is supported in the 64-bit Android app, not Flutter web.
On-device shows the complete model list in the same sheet, including when a
saved local selection is reopened. Selected/Downloaded labels distinguish the
active source from installed files. Web exposes the catalog but disables download/activation.
The speech sheet uses the root overlay above app navigation, preserves Android's
bottom safe inset and scroll on short screens or with enlarged text.
The fixed multilingual catalog contains Whisper Tiny, Whisper Base and
Parakeet TDT 0.6B V3, INT8 ONNX via pinned `sherpa_onnx` 1.13.8.
Model files download only on explicit request from fixed Hugging Face revisions;
each file is size-bounded and SHA256-verified before activation. Model weights
are private app files, not bundled in the APK. Downloads can be cancelled and
unused models removed. Parakeet's approximately 670 MB download needs more
memory; installation alone does not prove acceptable latency on a given phone.

The selected source is captured before recording. Server and on-device audio
disclosures have separate memory-only acknowledgements for the signed-in
session. Local inference runs outside the UI isolate, accepts the same bounded
PCM, and sends neither bearer token nor audio to a server. Recognized text is
shared only through the existing deliberate submission flow. Missing local
files, errors and cancellation never silently fall back to Server. Removing
the active model requires explicitly choosing another source first. Cancelling
discards a late native result; an already-running native decode finishes and
frees its model before another decode is admitted. No background recording,
Coach-provider change, account-schema change or server deployment is added.

Optional [dictation](../services/speech_service/README.md) adds a microphone
immediately before Send. Recording requires an explicit audio-data notice and
microphone permission, is capped at 30 seconds, and inserts recognized text into
the existing draft. Existing text is preserved; an overlong combined draft is
rejected without truncation.
Android declares audio and the recorder service's optional notification
capability. The latter declaration does not request/grant permission or enable
OS notification delivery; the existing foreground-only recording flow remains.
The source-specific audio-data notice is acknowledged once per signed-in app session, in memory
only; route revisits retain it, while sign-out/profile change or a full app
reload resets it. Declining never records consent. OS/browser microphone
permission remains independent. A seconds-remaining label and PCM-level bars
fill the recording bar. Display-only logarithmic scaling makes normal speech
visible; silence stays flat. Reduced motion disables interpolation, not live
level feedback. Audio sent for transcription is unchanged. No extra audio
capture, persistent storage, or backend change is introduced.
During recording the input becomes a compact bar:
X discards, square Stop transcribes into the draft, and explicit Send transcribes
then invokes the existing send flow, subject to current Coach availability and
limits. Automatic stop never sends. While transcribing, only discard is enabled.
If sending becomes unavailable, recognized text stays in the draft.
Cancel, leaving the route, backgrounding or
profile changes discard local recording state. Guest/mock cannot upload audio.
The independent sidecar does not change Coach provider, history or reply contracts.
Dictation transport lives in Coach data behind a cancellable domain request and
the shared `ApiClient` exception boundary. The recording widget does not import
Dio. Existing PCM/text/time limits and bearer delivery are unchanged. Native
upload options disable redirects; web retains browser-managed redirect behavior
and requires the canonical endpoint. Late replies and errors after discard or account change
cannot replace the current draft or display a stale error.
Composer Enter (including the mobile keyboard Send action) invokes the existing
guarded send flow; Shift+Enter remains multiline editing. Active IME composition
does not trigger hardware-key submission. Recording Stop remains draft-only;
recording Send requests transcription followed by the same guarded send flow.

Authenticated non-mock `development` sessions and authenticated Android sessions
with a selected, installed on-device model may dictate/edit a draft independently
of Coach availability. Hosted Server-source and guest/mock gates are unchanged;
unavailable Coach responses remain blocked in every environment. Local speech
does not imply an offline Coach or bypass account/session requirements.

Coach remains the fifth explicitly gated shell destination. Today, Insights,
Quick actions, Planner, Coach, and Settings share the same top action group:
page-specific actions such as Refresh first, an unread Coach result, Inbox, and
Settings last. Settings is pushed so Back returns to the originating main page;
on Settings the redundant self-link is omitted while the unread result and
Back remain available. Loading, empty, and error states retain their page's
same actions. Sub-pages,
Auth, Setup, and Capture flows remain outside this header contract. In
`staging`, `pilot`, and `production`, including release builds, Coach is visible only
when `COACH_SURFACE_ENABLED=true`; route visibility does not make a provider
ready. Development retains its documented explicit/debug defaults and unknown
environment labels fail closed.

The separate `daily-capture-draft-v1` operation reuses provider admission,
reservations and durable per-user/global quotas, not the ordinary chat prompt.
It supplies a minimal empty snapshot and an extraction-only prompt. The strict
proposal is returned in memory for manual review; Capture remains read-only to
the Coach. Claim/completion persist only purpose-bound hashes and metadata, no
transcript, values, excerpts or chat messages. Draft bookkeeping is excluded
from chat history and personal snapshots. Success consumes the shared Coach
allowance. An exact completed request without its in-memory result returns
`draft_expired`; only a new explicit user request may use a new identity.
Existing chat replies, history compatibility and provider selection stay unchanged.
Successful draft content is deliberately discarded into the existing deleted
content state, with completed usage retained and operator dispatch finalized
atomically. This leaves no message-less completed chat row for an older API to
misread after rollback. It is not a failed request or a quota refund.

Flutter Coach contract models and SSE envelopes reuse framework-neutral strict
key, object, text, integer, UUID, and aware-timestamp primitives. Answers use a
compact Low/Medium/High uncertainty status pill with semantic color and an icon;
the original reason remains visible before the read marker. High uncertainty
means less certain. Colors/icons supplement text and never guarantee correctness.
This presentation does not change response/history contracts. Coach-specific
provenance, safety, trace, evidence, replay, and feature error rules remain in
the Coach layer; V4 is synchronized by named constants while persisted V1-V3
history stays readable.

The hosted Coach provider menu requires one deliberate mode selection: `Project Coach`,
`Use my OpenAI key`, or `Use my Gemini key`. Project Coach never reads or
stores a key. BYOK keys remain isolated per provider, tab-memory-only on web
and encrypted device-local on Android. A failed mode never changes providers.
Non-demo Coach keeps the model selector in the composer, including when ready.
It opens the direct-choice sheet described above. Unavailable and rate-limit states stay visible;
provider/key changes refresh availability. Key fields appear only for BYOK.
Optional explanations use Info; short cost/data-sharing copy stays visible.
Settings keeps its existing controls; the authenticated default remains Standard.
For `provider_busy`, Flutter preserves the exact request id/message, shows the
bounded server countdown, and enables only a manual retry after it expires.

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

The compact capability card omits a redundant ready heading and uses a labelled
cloud-off icon when unavailable; a generic information icon is not used as an
error state. Ordinary unavailable/failure copy is outcome-first and does not
expose provider configuration, transport dumps, or raw contract exceptions.

The remaining-question count appears compactly beside the Coach title, with
its complete daily/UTC meaning in a tooltip. Ready status needs no separate
card; errors, unavailable states and test-provider disclosures remain visible.
The composer is one compact surface with an unframed full-width input above its
model-selection, microphone and Send toolbar. The input grows upward from one
to five lines, then scrolls internally. The existing selection dialog, draft, recording,
retry and cancel actions are unchanged.

Inside Coach, the current surface contains:

- capability/status and remaining-question truth;
- one chronological chat timeline, oldest turns first, with current/history
  turns deduplicated by request id and separate user/Coach message surfaces;
- a fixed bottom composer with one free text field and an icon labelled `Send`;
- the pending user message during analysis;
- a Cancel action only while a stream is active;
- a Coach reply placeholder after the pending user message, with a spinner and
  short safe activity text; Cancel stays in the composer;
- `Delete conversation` with the existing confirmation; and
- an expandable `Data & analysis` section below each current answer.

The detail section labels the backend-owned `evidence` rows as
`Snapshot source coverage`. It shows conservative source periods/counts,
SQL/Python/inspection steps, limitations, and technical provenance. It does
not imply that every covered row was returned by a query or used in the prose,
and it does not show plots, raw hidden reasoning, mode controls, time-horizon
controls, Focus selectors, prompt buttons, memory selectors, or structured
action cards.

The existing Coach UI remains English. The header language flag controls only
new reply/uncertainty and deterministic safety text, not technical trace labels.

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

- a scalable operator API-key/provider and billing strategy; the subscription-
  backed executor is a bounded, revocable pilot mode rather than a production
  fallback;
- scalable remote snapshot and sandbox workers;
- a distributed multi-instance queue or cancellation control plane;
- push/background Coach turns;
- writable or executable Coach actions;
- persisted or user-visible analysis plots; and
- automatic planning, calendar, notification, task, habit, or memory mutation.

The repository implementation keeps the future provider seam visible without
claiming that a Codex OAuth process is a production multi-user service. The
complete release sequence and remaining external gates are owned by
`docs/vps-pilot-release-plan.md`. Repository tests now cover the explicit
operator choice, durable budgets, pre-stream busy behavior, bounded executor,
kill switch, and no-fallback rule. They do not prove account/terms permission,
VPS identities and rootless Docker, live OAuth/model availability, HTTPS,
capacity, or public deployment. The operator gate therefore stays off until
those approvals and target-host checks pass; running an Internet service as
`APP_ENV=development` remains forbidden.
