# Next Chat Prompt

Use this prompt to start Phase 10 after the Phase 9 checkpoint
`e014303 feat: add bounded calendar import` and the Phase 10 planning handoff.

Recommended reasoning level: **high**. This slice introduces the first real
model boundary and must keep authentication, personal context, subprocess
execution, persistence, and product mutations sharply separated.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md and every file it requires for backend/AI work. In
particular, read docs/phase-10-controlled-coach-plan.md completely before
planning or changing code. Also inspect the current gated Coach code, FastAPI
configuration/dependency patterns, canonical coach_messages/memory_entries
schema and RLS, and current test/E2E conventions. Run git status --short before
editing and preserve unrelated work.

Do not browse the internet or fetch external OpenAI documentation for this
task. Use the checked-in plan and locally installed CLI help only. Never read,
print, copy, parse, or commit ~/.codex/auth.json or any equivalent OAuth token
file. Never print .env or Supabase keys.

Goal: implement the first bounded Phase 10 Controlled Coach slice exactly as
specified in docs/phase-10-controlled-coach-plan.md.

The local test provider must use the current Linux/WSL user's own Codex CLI
OAuth login and ChatGPT subscription access. It must not require OPENAI_API_KEY,
Hermes, copied credentials, or direct browser/Flutter OAuth handling. A project
partner must be able to install the repo on Linux, run codex login for their own
eligible Plus/Pro account, and configure the same local provider without sharing
the original developer's auth state. Do not promise that a particular model is
available to every account.

Implement a provider abstraction plus a development-only
local_codex_oauth adapter. It is opt-in only when APP_ENV=development,
USE_MOCK_DATA=false, COACH_PROVIDER=local_codex_oauth, and
LOCAL_CODEX_ENABLED=true. Feature-detect the local CLI and expose an honest
disabled/unavailable/ready capability response. If LOCAL_CODEX_MODEL is set,
request exactly that model; if it is unavailable, return a sanitized error with
no silent fallback. If no model is set, report that the CLI default was used
without inventing its name. The preferred normal Coach model is gpt-5.5 because
this is a general conversational reasoning and structured-output workflow, not
a coding-agent task. Do not prefer gpt-5.3-codex-spark merely because Codex CLI
is the local authenticated transport. Treat an unavailable gpt-5.5 as an honest
configuration state; a partner may explicitly configure another model exposed
by their own account without a code change. Keep gpt-5.5-pro out of the normal
interactive path unless a later separate evaluation justifies its latency and
usage tradeoff for a high-effort workflow.

Invoke codex exec with a fixed argv and shell=False. Send personal prompt data
through stdin, run in a fresh empty permission-0700 temp directory, use
--ephemeral, --ignore-user-config, --sandbox read-only,
--ask-for-approval never, --skip-git-repo-check, and a committed strict output
schema. Explicitly disable every available model-controlled shell, unified
execution, app, browser/computer, plugin, multi-agent, image-generation, and
search/tool feature; the checked CLI exposes at least shell_tool and
unified_exec. If a CLI version cannot prove a tool-free invocation, report the
provider unavailable before sending context. Reject any unexpected tool event.
Never enable search, MCP, plugins, hooks, extra directories, writable or danger-
full-access sandboxes, or dangerous bypass flags. Pass an allowlisted child
environment that excludes every Supabase key, scheduled token, app secret,
request header, and prompt. Enforce input/output/event limits, one in-flight
turn per user, a small global concurrency, a hard timeout, process-group
termination, cleanup, and sanitized errors/logs. Treat this as a local
development adapter, not a production isolation boundary.

Add strict authenticated coach-request-v1 / coach-response-v1 models,
GET /v1/coach/capabilities, and deliberate POST /v1/coach/respond. Derive
user_id only from the Supabase bearer token, reject a request user_id and
unknown/null/coerced shapes, cap the user message, and make request_id retry-
safe without holding a DB transaction while the CLI runs. FastAPI—not the
model—must attach request identity, provider/model/prompt/context provenance,
generated_at, and the exact used-context manifest.

Build coach-context-v1 with the full-reach/minimal-disclosure rule. FastAPI may
read relevant owner-scoped canonical data, but the model gets no database
credentials, SQL, tools, or full-history dump. The first today scope contains
only the current compact snapshot/Daily State, current persisted briefing,
bounded active goals/tasks/habits/focus facts, an explicitly fresh latest weekly
review when useful, at most eight explicitly selected memories, and at most six
completed recent Coach turns. Apply stable ordering/category caps and a 32 KiB
total cap, and disclose omissions/counts. Exclude imported .ics content,
calendar event text, auth/email data, hidden capture/intake/notification free
text, app secrets, and cross-user rows. Treat every user-authored value as data,
not application instructions.

Keep deterministic Today and executable-action-v1 as source of truth. Coach may
explain and return at most one review-only staged text suggestion. It must not
generate on Dashboard/history/capability reads, mutate a briefing, or directly
create/edit/complete/delete any task, habit, focus, goal, schedule, memory,
review, feedback, recommendation, or calendar row. Add no background agent,
vector search, autonomous loop, provider failover, or API-key fallback.

Make memory use visible and explicit. Setup-owned memory remains owned/editable
through revisioned Setup; use a separate selection projection if necessary so a
Coach toggle cannot be overwritten by Setup apply. Add no automatic memory
extraction. Persist only validated bounded turns/provenance if the plan's
persistence requirements are satisfied, make history deletion explicit, and
remove/replace the current MorePage canned reply and direct
CoachSupabaseService.addMessage path so they cannot be accidentally ungated.

Add deterministic safety pre/post boundaries, required uncertainty for missing
or stale evidence, and an approved safety-redirect path. Do not claim diagnosis,
treatment, causation, professional monitoring, or emergency service. Never show
raw CLI stderr or fabricate a reply after failure.

Replace the gated Coach route with the typed FastAPI-backed surface only for a
real authenticated account whose capability is ready. Show the local-
development provider label, answer, uncertainty, freshness, model/provenance,
expandable Data used manifest, memory controls, preserved failed draft, honest
disabled/unavailable/rate-limit/error states, and history deletion. Guest/mock
must make zero Coach backend/model calls and receive no personalized-looking
fallback.

All normal automated tests and browser E2E must use an injected fake provider,
never a live OAuth account. Add exact subprocess tests for argv/stdin/temp-dir/
environment/cleanup/timeout/error mapping and prove no application secret enters
the child. Add strict parser, owner-scope, pagination/cap, context exclusion,
retry, usage/concurrency, memory/RLS, safety, Flutter state, and zero-hidden-call
coverage. A real subscription smoke is a separate opt-in path such as
RUN_LOCAL_CODEX_SMOKE=true, prints no personal prompt/events/tokens, and is never
required by CI or standard verification.

Run verification in proportion to every changed layer, including FastAPI tests,
Flutter analyze/test, git diff --check, local migration/RLS verification when
schema changes, and the fake-provider browser journey. Run one real local Codex
smoke only when the environment is explicitly enabled and authenticated; do not
attempt login automation. Update AGENTS.md, README, architecture, local-dev,
verification, Supabase current state, the Phase 10 plan, and next-chat handoff
to describe what is actually implemented and the exact current-checkout result.
Do not call Phase 10 complete merely because the live CLI answers once.
```
