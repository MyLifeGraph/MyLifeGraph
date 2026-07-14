# Phase 10 Controlled Coach Implementation Plan

Status: implemented at the repository boundary. This document now records the
locked Phase 10 contract and the separate verification limits. The opt-in
synthetic local Codex provider smoke passed on 2026-07-13 with explicitly
requested `gpt-5.5`. A focused Phase 10 fake-provider browser rerun and the
subsequent full non-destructive local-Supabase journey also passed in the
current checkout. The first full-product live-account acceptance also passed
non-destructively on 2026-07-13 in the working tree based on `b8c7935`:
authenticated Flutter -> FastAPI -> `local_codex_oauth` -> the same Linux
user's logged-in Codex CLI -> validated and persisted `coach-response-v1`.

## Implemented Boundary

The current checkout includes:

- strict authenticated capability, deliberate response, history/delete, and
  memory-selection HTTP models and Flutter parsers;
- a deterministic fake provider for standard tests and browser setup;
- the development-only `local_codex_oauth` provider with fixed non-shell argv,
  stdin prompt transport, per-request permission-`0700` workspace, ignored user
  configuration/rules, read-only sandbox, strict schema, feature disabling,
  allowlisted environment, bounded process I/O/events/time/concurrency, process-
  group termination, sanitized errors, and unexpected tool-event rejection;
- a deterministic 32 KiB `coach-context-v1` builder over owner-scoped current
  state, briefing, active goals/tasks/habits/focus, only a current weekly review,
  up to eight explicitly selected eligible memories, and up to six completed
  turns, with an exact source/count/freshness manifest;
- deterministic urgent-risk provider bypass and post-provider safety/
  uncertainty checks;
- `coach_requests`, `coach_usage_events`, and `coach_memory_selections`, plus
  request-linked `coach_messages`, forced RLS/grant hardening, and service-role-
  only atomic claim/complete/fail/select/delete RPCs;
- a follow-up owner-first advisory-lock wrapper around claim/complete/fail,
  aligned with history deletion so concurrent lifecycle paths do not acquire
  owner and request/row locks in inverse order;
- follow-up database guards that persist whether safety copy bypassed or
  replaced a provider response, make canonical profile identity/role authority
  backend-owned, remove legacy-role fallback and authenticated profile delete,
  and reserve onboarding eligibility projection for the backend Intake RPC;
- the typed `/coach` Flutter surface, `/more` compatibility alias, visible
  provider/model/prompt/context/data-use truth, preserved exact retry drafts,
  review-only suggestions, explicit memory selection, and conversation deletion;
  and
- an independent Flutter surface gate: release builds and
  `APP_ENV=production` hide navigation and redirect `/coach` to Settings unless
  `COACH_SURFACE_ENABLED=true` is supplied exactly. This opt-in exposes only the
  UI boundary; backend capability still controls whether sending is ready.

Pending claims store no message, only its fingerprint. Successful completion
atomically writes the full bounded user/assistant pair. Conversation deletion
removes messages and request content, leaves content-free request tombstones,
and retains append-only usage, so it does not reset the daily attempt budget or
allow request-id reinterpretation.

The additive hardening chain after the base Coach schema is:

- `20260713213000_phase_10_coach_lock_order_guard.sql` aligns public
  claim/complete/fail wrappers and history deletion on the owner-first lock;
- `20260713220000_phase_10_coach_safety_provenance_guard.sql` requires exact
  persisted `provider_called` provenance for model and deterministic-safety
  responses;
- `20260713223000_phase_10_profile_privilege_guard.sql` blocks application-role
  profile insertion and `role`/`auth_provider` mutation while preserving
  bounded non-identity profile edits;
- `20260713224500_phase_10_role_authority_guard.sql` removes legacy `"User"`
  fallback from role authority and revokes authenticated profile deletion; and
- `20260713230000_phase_10_onboarding_eligibility_guard.sql` revokes
  authenticated `onboarding_completed_at` updates and keeps that projection
  behind service-role/atomic Intake apply authority.

## Outcome

Phase 10 makes an authenticated Coach conversation locally testable without an
OpenAI API key. During development, FastAPI may invoke the
Codex CLI that is already installed and authenticated for the current Linux or
WSL user. That user's own ChatGPT subscription-backed Codex login supplies the
model access.

This is a local development adapter, not the production LLM architecture. A
future deployed service must use a separately approved server-side provider
and credential contract. The Flutter app, Supabase, repository, and browser
must never receive or copy Codex OAuth credentials.

The implemented slice is deliberately narrow:

- one explicit user submit to an authenticated Coach endpoint;
- one bounded `coach-context-v1` package built by FastAPI;
- one schema-validated `coach-response-v1` answer;
- visible data-use, model, prompt, freshness, and uncertainty provenance;
- no hidden state mutation, background call, or autonomous agent loop.

## Locked Product Decisions

1. The deterministic Daily State, persisted daily briefing, and Phase 3 action
   contracts remain the source of truth. Coach explains and helps the user
   think; it does not replace deterministic ranking.
2. The local provider is named `local_codex_oauth`. It is enabled only by an
   explicit development flag and an authenticated real Supabase session.
3. No OpenAI API key is required or accepted by this adapter. There is no
   Hermes dependency. FastAPI invokes the local `codex` executable directly.
4. Every developer authenticates Codex in their own Linux environment. A repo
   clone never inherits another person's login. A WSL user with Pro and a
   project partner with Plus each run their own `codex login`; actual model
   availability remains an account/CLI capability and is never promised by the
   repository.
5. A requested model may be configured locally. If it is unavailable, the
   request fails honestly. There is no silent model or API-key fallback.
   The preferred Phase 10 Coach model is `gpt-5.5`, provided the current Codex
   CLI/account exposes that exact id. It is the general text/reasoning default
   and fits nuanced conversation, planning, instruction following, and strict
   structured output better than a coding-focused Codex/Spark variant.
   `gpt-5.5-pro` is an optional later quality benchmark for unusually complex
   reflection or planning when latency and account limits are acceptable; it is
   not the interactive default. A partner may select a different model
   available to their own account without changing source code.
6. The backend has owner-scoped reach across the user's product data, but the
   model never gets database credentials, arbitrary SQL, or an unbounded table
   dump. Context is selected, compact, capped, and disclosed to the user.
7. Imported `.ics` event content is excluded from Phase 10 prompts. Phase 9 did
   not grant Coach consent merely because calendar import was consented to.
8. Coach calls occur only after a deliberate send action. Dashboard GET,
   captures, task/habit/focus writes, scheduled preparation, recommendation
   generation, and weekly review remain no-LLM paths.
9. Suggestions are review-only. Phase 10 must not directly create, edit,
   complete, postpone, archive, or delete a task, habit, schedule item, goal,
   memory, briefing, review, or calendar row.
10. No memory is inferred or promoted automatically. Only explicitly selected,
    reviewable memory may enter context.

## Runtime Topology

```text
Flutter Coach
  -> POST /v1/coach/respond with Supabase bearer token
  -> FastAPI derives user_id and loads bounded owner-scoped context
  -> LocalCodexCoachProvider starts local `codex exec`
  -> Codex CLI uses that Linux user's existing OAuth login
  -> FastAPI validates the model output and adds trusted provenance
  -> Flutter renders the answer, uncertainty, and "data used" manifest
```

OAuth terminates inside the locally installed Codex CLI. The application must
not read, print, upload, copy, or parse `~/.codex/auth.json` or equivalent auth
state. The FastAPI process must run as the same Linux user whose Codex CLI is
logged in, unless a separate deliberately configured service account is used.
Do not run the service as root merely to reach another user's auth files.

## Local Configuration Contract

The implementation adds these backend-only settings. They must not be
passed to Flutter as Dart defines:

```env
COACH_PROVIDER=disabled
LOCAL_CODEX_ENABLED=false
LOCAL_CODEX_BIN=codex
LOCAL_CODEX_MODEL=gpt-5.5
LOCAL_CODEX_TIMEOUT_SECONDS=45
LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20
```

The live local adapter is ready only when all of these are true:

- `APP_ENV=development`;
- `USE_MOCK_DATA=false` for the Flutter product source boundary;
- `COACH_PROVIDER=local_codex_oauth`;
- `LOCAL_CODEX_ENABLED=true`;
- FastAPI has valid local Supabase backend settings;
- the request contains a valid real-account Supabase bearer token;
- `LOCAL_CODEX_BIN` resolves to an executable;
- `codex login status` succeeds for the FastAPI Linux user.

`LOCAL_CODEX_MODEL=gpt-5.5` is the recommended Coach setting. When non-empty,
pass it as one `--model` argument and report it as `model_requested`. If the
local subscription does not expose it, return `unavailable_model`; never fall
back silently to Spark or another model. A developer may explicitly configure a
different locally available model. When the setting is deliberately empty, let
the CLI choose its default and report the exact truth as
`model_requested: null` and `model_source: cli_default`; do not invent a model
name. If the CLI exposes a reliable selected-model field in its machine output,
preserve that separately as `model_reported`.

### Model Choice Rationale

The Coach is a general-language reasoning workflow, not a software-engineering
agent. Its first model must prioritize conversational nuance, current-state
synthesis, cautious planning, instruction adherence, and reliable JSON over
coding-tool speed. The preferred order is therefore:

1. `gpt-5.5` for the normal interactive Coach.
2. An explicitly configured account-available general reasoning model when
   `gpt-5.5` is unavailable; this is a user choice, not automatic fallback.
3. `gpt-5.5-pro` only for a separately evaluated high-effort workflow, never as
   a hidden upgrade within an ordinary Coach turn.

Do not prefer `gpt-5.3-codex-spark` or another coding-focused Codex variant for
the Coach simply because the local bridge happens to be the Codex CLI. The CLI
is the authenticated transport in this development design; it does not make
the product workflow a coding task.

This choice was made from the locally bundled model-selection fallback available
on 2026-07-13 because external documentation lookup was explicitly excluded for
this handoff. Before a later production provider is selected, revalidate the
model separately under that provider's then-current supported catalog and
evaluation results.

The checked local CLI on 2026-07-13 was `codex-cli 0.144.1`. Its local help
exposed `codex login`, `codex login status`, and non-interactive `codex exec`
with model, read-only sandbox, ephemeral session, ignored user config, JSON
events, and output-schema options. Its local feature list also exposed enabled
`shell_tool` and `unified_exec` features. Implementation must feature-detect the
installed version and fail with a useful unavailable state rather than assuming
all future or older CLIs have identical flags or allowing a model-controlled
tool merely because one version names it differently.

Developer preflight is intentionally per machine:

```bash
codex --version
codex login
codex login status
```

The repository must never automate login, distribute OAuth files, or make a
real subscription call part of standard verification or CI.

## Provider Invocation Contract

The provider interface is independent of Codex.
`LocalCodexCoachProvider` is the only real-model adapter; tests use a fake
provider/process runner, while only an explicit per-machine request may use the
real CLI.

The subprocess wrapper must:

- use an argv array with `shell=False`; never accept raw extra CLI arguments
  from a request or environment string;
- send the prompt/context through stdin (`codex exec ... -`) so personal data
  is not placed in process arguments;
- use a new permission-`0700` empty temporary working directory for every
  request and remove it afterward;
- use `--ephemeral`, `--ignore-user-config`, `--sandbox read-only`,
  `--ask-for-approval never`, `--skip-git-repo-check`, and the empty directory
  as `--cd`;
- explicitly disable every available model-controlled shell, unified execution,
  app, browser/computer, plugin, multi-agent, image-generation, and search/tool
  feature. At minimum the checked CLI requires `--disable shell_tool` and
  `--disable unified_exec`; feature-detect the rest instead of assuming names;
- use a committed strict output JSON schema and parse machine-readable events;
- never use `--search`, `--add-dir`, a config profile, MCP configuration,
  plugin configuration, hooks, `danger-full-access`, or either dangerous bypass
  flag;
- pass only an allowlisted child environment needed by the CLI. In particular,
  do not inherit Supabase service-role/anon keys, scheduled tokens, application
  secrets, request headers, or the user's message as environment variables;
- bound stdin, stdout, stderr, event count, and final reply size;
- enforce an async timeout, terminate the complete process group on timeout or
  client cancellation, and reap it;
- permit at most one in-flight turn per user and a small configured global
  concurrency;
- redact stderr and map failures to stable application error codes. Never send
  raw CLI diagnostics, account identity, paths, tokens, or prompt content to
  Flutter or normal logs.
- reject and terminate an invocation if its event stream contains any tool,
  command, file, browser, app, MCP, plugin, delegation, or approval event.

Ignoring user config prevents an individual's MCP servers, plugins, hooks, and
prompt customizations from changing application behavior while retaining the
CLI's own auth lookup. Explicit feature disabling is mandatory: if the installed
CLI cannot establish a tool-free invocation, capability is `unavailable` and no
personal context is sent. The empty work directory and read-only sandbox remain
defense in depth, not a production-grade isolation boundary for a same-user
agentic CLI. This limitation is why the adapter is development only. The prompt
must also tell Codex not to invoke tools, but prompt text alone must not be
described as a security control.

## HTTP Contract

The authenticated, model-call-free capability read is:

```text
GET /v1/coach/capabilities
```

It returns one honest state: `disabled`, `unavailable`, or `ready`, plus the
provider mode, configured model request, limits, and a sanitized reason code.
It must not return account identity, OAuth details, filesystem paths, or token
content. Capability checks must not make a model call.

The one deliberate response endpoint is:

```text
POST /v1/coach/respond
Authorization: Bearer <supabase_access_token>
```

Initial request shape:

```json
{
  "contract_version": "coach-request-v1",
  "request_id": "uuid",
  "message": "bounded user text",
  "context_scope": "today"
}
```

Rules:

- derive `user_id` exclusively from the verified bearer token;
- reject a body `user_id` and unknown or explicit-null fields;
- accept exactly one `today` scope in the first slice;
- cap `message` at 2,000 Unicode code points after trimming and reject blank
  input;
- make `request_id` retry-safe. A completed request returns the exact persisted
  result without a second provider call; an active request reports
  `in_progress`; a failed request stays failed and an explicit retry uses a new
  id;
- never hold a database transaction open while the CLI runs.

The HTTP response is backend-owned. The model returns only its answer fields;
FastAPI attaches request identity and provenance that the model cannot invent:

```json
{
  "contract_version": "coach-response-v1",
  "request_id": "uuid",
  "reply": "bounded validated text",
  "uncertainty": {
    "level": "low|medium|high",
    "reason": "bounded text"
  },
  "staged_suggestion": null,
  "safety": {
    "classification": "normal|sensitive|safety_redirect"
  },
  "used_context": [],
  "provenance": {
    "source": "model",
    "provider": "local_codex_oauth",
    "provider_mode": "local_development_only",
    "model_requested": null,
    "model_reported": null,
    "model_source": "cli_default|explicit",
    "prompt_version": "controlled-coach-prompt-v1",
    "context_version": "coach-context-v1",
    "generated_at": "RFC3339 UTC",
    "provider_called": true
  }
}
```

`staged_suggestion` may contain at most one review-only idea with a bounded
title and rationale. It must have no executable command or apply endpoint in
the first slice. Invalid, truncated, unknown-field, non-JSON, or oversized
model output is an unavailable response, never partially rendered as trusted
Coach content.

For `safety_redirect`, `provenance.provider_called` distinguishes the
deterministic pre-provider bypass (`false`) from backend safety copy that
replaces an unsafe provider result (`true`). The model cannot set either the
provenance source or this call truth.

## Context Contract: Full Reach, Minimal Disclosure

The implemented personalization is not a full database dump. FastAPI owns a
read-only `CoachContextRepository` that may reach relevant canonical tables for
the bearer-derived owner, then builds a deterministic compact package. The LLM
cannot query Supabase itself.

The first `today` package should contain only:

- profile-local date/timezone and explicit coaching preference, without email
  or auth/provider identifiers;
- the exact current daily snapshot and `explainable-daily-state-v1` summary;
- the current persisted `daily-briefing-v1`, including freshness and evidence;
- bounded active goal, task, habit, and current/recent focus summaries needed
  to explain today's decision;
- the latest completed weekly review only when its freshness is explicit;
- at most eight explicitly Coach-selected memory entries;
- at most six prior completed Coach turns, capped again by total characters.

Caps and stable ordering must be constants in the contract. The serialized
context should be capped at 32 KiB before provider invocation. When facts do not
fit, truncate deterministically and disclose counts in `used_context`. Do not
let the model claim it saw rows that were omitted.

Excluded in v1:

- Supabase tokens, service-role credentials, email, auth metadata, internal
  roles, or cross-user rows;
- raw full history and arbitrary SQL/tool access;
- Phase 9 imported calendar event title, description, location, attendees, or
  raw `.ics` content;
- check-in context notes, intake free text, notification bodies, or other
  hidden free text unless a later explicit consent contract names it;
- archived/deleted objects except when an exact current contract needs a
  non-sensitive status count;
- raw deterministic prompt internals or secrets in model-visible provenance.

User text, task titles, goal titles, and memory content are untrusted data, not
system instructions. Serialize them as typed JSON inside explicit data
delimiters and keep application instructions outside that data envelope.

The current memory-selection repository excludes every `type=preference` row.
Intake's hidden context note and coaching-style memory share that type without a
stable sensitivity discriminator, so Phase 10 does not guess from titles or
content. The structured coaching preference comes from the bounded onboarding
snapshot projection instead.

Future Coach modes may add bounded historical retrieval across more of the life
graph. They must add an explicit scope, source allowlist, limits, consent where
needed, and user-visible data-use manifest. Do not solve this with vector search
or direct model tools in the first slice.

## Memory And Retention

Coach memory and chat history are separate:

- Setup-owned memory remains owned by revisioned Settings Setup. Coach may
  reference it only after a separate user selection; toggling Coach use must not
  rewrite Setup metadata or transfer ownership.
- `coach_memory_selections` is the separate owner-scoped projection; no flag is
  stored inside metadata that Setup apply replaces.
- The user can inspect every selected memory and remove it from Coach context.
  Editing/deleting Setup-owned content routes to Setup; future manual Coach
  memory needs its own explicit edit/delete contract.
- Phase 10 does not extract memory candidates from conversation and does not
  silently update strength, evidence, or `last_seen_at`.

The implementation persists validated user/assistant turns in
`coach_messages` under a retry-safe request identity and bounded backend-owned
response/provenance contract. Flutter no longer inserts canned user or
assistant rows directly. Authenticated owners read history through FastAPI and
delete it through the explicit body-free endpoint; model/provider writes go
through FastAPI. The assembled prompt, copied snapshot, and raw CLI event stream
are not persisted. A pending claim stores only a message fingerprint, and
successful atomic completion stores the bounded pair, compact context manifest,
validated response metadata, and usage counters. Delete removes message/
response content while retaining content-free request tombstones and append-only
usage.

`--ephemeral` prevents this application invocation from deliberately creating a
resumable Codex session. It does not by itself define OpenAI service retention,
which remains outside the repository's control and must not be misrepresented
in product copy.

## Safety Contract

The Coach is informational planning and reflection support. It must not claim
diagnosis, treatment, causation, certainty, professional monitoring, or an
emergency response service.

Implement deterministic pre- and post-provider safety boundaries:

- an urgent-risk path bypasses ordinary planning language and returns approved
  safety-oriented copy directing the user toward immediate human/local
  emergency support;
- the model may not turn sparse mood, sleep, stress, or behavior data into a
  medical conclusion;
- uncertainty is required when evidence is missing, partial, stale, or
  conflicting;
- provider failure must never fabricate reassurance or imply a human reviewed
  the message;
- safety copy and tests must be locale-aware before production claims are made.

Safety checks must be tested independently of a live model. Do not rely only on
the system prompt or the model's own classification.

## Usage And Failure Truth

Even when a subscription rather than an API bill supplies access, the app needs
bounded use:

- default maximum 20 successful/attempted turns per user per local day;
- one in-flight request per user and a small global concurrency cap;
- bounded request, context, output, and timeout values;
- usage recorded without storing full prompts;
- stable errors for disabled provider, missing CLI, not logged in, unavailable
  model, rate limit/account limit, timeout, invalid output, safety redirect, and
  generic provider failure.

Flutter must keep `disabled`, `unavailable`, `loading`, `ready`, `rate_limited`,
and `error` distinct. It must retain the unsent/failed draft and never replace a
real failure with the old canned response or demo content. Guest/mock mode shows
an honest local-unavailable Coach state and makes zero backend/model calls.

## Flutter Slice

The gated canned Coach implementation and direct Supabase writer are replaced
rather than merely removing the route redirect.

The first usable surface:

- be exposed only when the independent surface gate is enabled;
- let an authenticated real account inspect persisted history and capability
  truth while the provider is disabled or unavailable, while only a backend
  `ready` capability enables sending;
- show guest/mock unavailability locally with zero Coach HTTP calls when a
  development build deliberately exposes the surface;
- explain that the active provider is a local development connection;
- load persisted validated history without generating a reply;
- send only through FastAPI with a fresh retry-safe request id;
- show the answer, uncertainty, freshness, local-provider/model provenance, and
  expandable `Data used` manifest;
- show selected memories with inspect/deselect and correct Setup ownership
  routing;
- present any suggestion as review-only text with no apply action;
- preserve the draft on timeout/error and prevent double submit;
- expose delete-history and memory-control actions;
- never write directly to `coach_messages` from Flutter.

The existing `MorePage` canned string and `CoachSupabaseService.addMessage`
path are not an implementation foundation. Remove or replace them so they
cannot be accidentally ungated.

## Implementation Order Used

1. Freeze strict Python and Dart request/response/context models and the model
   output JSON schema.
2. Add backend settings and an injectable `CoachProvider` interface with a fake
   provider for tests.
3. Implement the hardened local Codex subprocess adapter and capability check.
4. Add owner-scoped context loading, stable caps/order, memory selection, usage,
   retry identity, and any required migration/RLS hardening.
5. Add `GET /v1/coach/capabilities`, history/memory-control reads, deletion, and
   `POST /v1/coach/respond`.
6. Replace the gated/canned Flutter Coach with the real typed FastAPI boundary.
7. Add unit, repository, widget, migration/RLS, subprocess, and browser tests.
8. Run the standard checks and local Supabase E2E with the fake provider.
9. Run one explicitly opt-in manual real-Codex smoke locally; do not include it
   in CI or claim it for a partner/account that was not tested.
10. Update all affected docs and record exact current-checkout verification.

## Verification Contract

Default automated tests must never require network access, a ChatGPT account,
or a real Codex login. Provide a fake executable/provider fixture that proves:

- exact argv, no shell, stdin-only prompt delivery, isolated work directory,
  allowed environment, no application secrets, and cleanup;
- required tool-feature disabling, unavailable behavior when tool-free mode
  cannot be established, and rejection of every unexpected tool event;
- valid schema parsing plus unknown/null/coerced/oversized/truncated rejection;
- timeout/process-group termination and sanitized stderr;
- missing binary, unauthenticated CLI, unavailable model, rate-limit, and
  non-zero-exit mapping;
- owner-derived context and zero cross-user data;
- stable pagination, ordering, caps, manifest counts, and 32 KiB limit;
- no imported calendar content or hidden capture/intake free text in context;
- no model call on capabilities, GET/history, Dashboard, capture, CRUD,
  scheduled, recommendation, or weekly-review paths;
- request replay returns the same completed turn without a second fake call;
- one in-flight request per user and bounded usage;
- memory selection, Setup ownership, history deletion, and RLS;
- safety bypass and unsafe/invalid model-output rejection;
- Flutter guest/mock isolation, honest unavailable/error states, preserved
  draft, provenance/data-use display, and no direct Supabase Coach write.

The browser journey is configured to use the deterministic fake provider.
`services/ai_service/tests/test_local_codex_smoke.py` is the separate
real-subscription smoke; it is skipped unless `RUN_LOCAL_CODEX_SMOKE=true`, uses
only synthetic context, and must print no prompt or CLI event stream. On
2026-07-13 that smoke completed against the explicitly requested `gpt-5.5`
model (`1 passed`), with no fallback and no answer, prompt, or raw event stream
logged. The result is specific to that machine, CLI, login, and account.

The follow-up lock-order migration also passed real local PostgreSQL parallel
claim/completion/deletion smokes: the operations converged to the exact message,
usage, and deletion outcomes without deadlock or timeout.

Browser verification passed in two layers on 2026-07-13. First,
`E2E_PHASE10_ONLY=true` with the existing `E2E_RUN_ID=1783945829` repeated the
Coach UI/API/RLS journey as a focused diagnostic. Then the full non-destructive
current-checkout command ran against local Supabase with the deterministic fake
provider and reported
`E2E browser smoke passed for e2e-1783947134@example.test`. The focused mode
requires an existing eligible E2E principal and omits the earlier product
phases; it is not a replacement for the full run.

The previously open first live-account product-path criterion passed on
2026-07-13 with that existing onboarded local E2E principal. FastAPI ran with
`COACH_PROVIDER=local_codex_oauth`, the fake provider disabled, and explicit
`LOCAL_CODEX_MODEL=gpt-5.5`; Flutter ran with `USE_MOCK_DATA=false`. The UI
authenticated, reported the provider ready, deliberately sent one request, and
rendered the validated answer plus expanded `Data used` and provider/model
truth. The response recorded `source=model`,
`provider=local_codex_oauth`, `provider_called=true`, the exact prompt/context
versions, normal safety, and medium uncertainty. The CLI did not emit a
reliable `model_reported` field, so that value remained `null`; the exact
configured request remained `gpt-5.5` with no fallback.

The used-context manifest included profile `1/1`, daily snapshot `1/1`, stale
daily briefing `1/1`, goals `2/2`, tasks `2/2`, habits `2/2`, and focus sessions
`3/3`. It excluded the stale weekly review (`0/1`) and had no selected memory or
prior completed turn (`0/0` each). The authenticated history endpoint returned
the exact persisted turn. The harness validated reply bounds and UI rendering
without printing the question, assembled prompt, answer, raw CLI events,
stderr, account identity, token, path, `.env` value, or Supabase key.

Focused Python and Flutter tests plus migration contract tests exist in the
checkout, but source coverage is not a pass claim. Record actual commands and
results only after they run in the current checkout.

## Phase 10 Acceptance Criteria

The repository implementation covers the contract below, and the first
end-to-end live-account criterion is now verified on this machine. The
synthetic provider smoke alone did not establish that result; the separate
Flutter/FastAPI product-path run recorded above did. One live-account criterion
remains open, so Phase 10's full multi-developer acceptance is not complete:

- **Verified on this machine, 2026-07-13:** a real authenticated local user can
  deliberately receive one validated Coach answer through their own logged-in
  Codex CLI without an API key;
- **Open:** another Linux user can clone the repo, log in with their own eligible
  account, and use the same documented setup without copied credentials;
- disabled, missing-login, unavailable-model, timeout, invalid-output, and
  account-limit states are honest and recoverable;
- the user can see which compact product sources and memories were used;
- no cross-user row, application secret, imported calendar content, hidden free
  text, or direct database credential enters the model input;
- no Coach response can silently mutate product state;
- standard tests pass entirely with a fake provider and the real local smoke is
  explicitly opt-in;
- documentation calls the adapter local-development-only and makes no deployed
  availability, production security, or universal Plus/Pro model claim.

## Explicitly Later

- a deployable API/provider adapter and production secret/billing policy;
- mobile-device execution without a developer Linux host;
- provider failover or API-key fallback;
- multiple specialized autonomous agents;
- background Coach messages or notification delivery;
- vector search or model-controlled database tools;
- imported calendar content in prompts;
- automatic memory extraction/promotion;
- executable task/habit/goal/schedule changes from Coach;
- clinical, diagnostic, therapeutic, or emergency-monitoring features.
