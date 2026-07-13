# Next Chat Prompt

Use this prompt to continue from the Phase 10 Controlled Coach implementation
checkpoint. Recommended reasoning level: **high**.

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md and every linked document required for backend, AI,
Supabase, Flutter, and verification work. Read
docs/phase-10-controlled-coach-plan.md completely. Run git status --short before
editing and preserve unrelated work.

Phase 10 Controlled Coach is implemented at the repository boundary. Do not
rebuild it from the old gated MorePage design. Inspect the current strict
FastAPI/Dart Coach contracts, owner-scoped context builder, fake provider,
development-only local_codex_oauth adapter, migration/RPCs, Flutter surface,
focused tests, and browser source before planning changes.

The current boundary must remain fixed:

- only a real authenticated account may use the FastAPI Coach path; guest/mock
  is honest local-unavailable and makes zero Coach HTTP calls;
- capability, history, and memory reads never generate; only a deliberate
  POST /v1/coach/respond may call one configured provider;
- coach-request-v1 uses one UUID, a trimmed maximum-2,000-code-point message,
  and today scope; completed replay is provider-free, one owner has at most one
  active request, and retained requests enforce the profile-local daily budget;
- coach-context-v1 is deterministic, owner scoped, capped at 32 KiB, and limited
  to current state/briefing, bounded active facts, only a current weekly review,
  explicitly selected eligible memories, and bounded completed history;
- imported calendar content, hidden capture/intake/notification free text,
  credentials, OAuth files, application secrets, raw history, and cross-user
  rows never enter model context;
- suggestions are review-only text and expose no command/apply endpoint;
- pending claims contain only a message fingerprint; successful completion
  atomically writes one bounded user/assistant pair and usage event;
- conversation deletion removes content but retains request tombstones and
  append-only usage, so it cannot reset budget or reinterpret an old request id;
- memory selection is separate from memory ownership/content and capped at
  eight; no automatic memory extraction exists;
- local_codex_oauth remains APP_ENV=development only, explicitly enabled,
  fixed-argv/non-shell, stdin-only, ephemeral/read-only/tool-free, bounded, and
  allowlisted. It never accepts an API key, Hermes, arbitrary CLI args, tools,
  search, plugins, MCP, writable access, model fallback, or copied OAuth state;
- gpt-5.5 is the preferred explicit Coach setting only when that local account
  exposes it. Unavailable login/model/tool-free capability remains honest;
- all normal tests and browser E2E use the deterministic fake provider and make
  no live model/network call.
- the additive Phase 10 hardening chain ends at
  20260713230000_phase_10_onboarding_eligibility_guard.sql after
  20260713220000_phase_10_coach_safety_provenance_guard.sql,
  20260713223000_phase_10_profile_privilege_guard.sql, and
  20260713224500_phase_10_role_authority_guard.sql;
  application roles cannot self-promote, delete/recreate the canonical profile,
  or write onboarding eligibility.

Start by establishing the current checkout's real status. Run focused FastAPI
Coach/migration/provider tests, Flutter Coach tests, Flutter analyze, standard
non-destructive verification, and git diff --check. Apply pending local
migrations with supabase migration up --local rather than resetting unless a
fresh local database is explicitly requested. Then run the fake-provider
browser journey if the local toolchain is available. Do not claim any command
passed until it actually completes in this checkout.

The skipped-by-default synthetic-context smoke is
services/ai_service/tests/test_local_codex_smoke.py and runs only with
RUN_LOCAL_CODEX_SMOKE=true plus explicit local-provider settings. It passed on
2026-07-13 with explicitly requested gpt-5.5 (1 passed), no fallback, and no
answer, prompt, or raw event stream logged. Real local PostgreSQL parallel
claim/completion/deletion smokes also passed without deadlock or timeout. A
focused Phase 10 fake-provider browser rerun and the subsequent full
non-destructive local-Supabase browser journey passed in the same current
checkout; the full run reported E2E browser smoke passed for
e2e-1783947134@example.test. E2E_PHASE10_ONLY=true with an existing eligible
principal's exact E2E_RUN_ID is diagnostic only and does not replace the full
run.

The previously open first full-product live-account criterion also passed
non-destructively on 2026-07-13 in the working tree based on b8c7935. The
existing onboarded local E2E principal authenticated through Flutter Web,
FastAPI reported ready `local_codex_oauth` with explicit `gpt-5.5`, and one
deliberate request returned a validated, UI-rendered, persisted
`coach-response-v1` with `provider_called=true`. The harness expanded data-use
and provider/model truth and logged no question, prompt, answer, raw event,
stderr, account identity, token, path, `.env` value, or Supabase key. The CLI
did not report a reliable selected-model field, so `model_reported` remained
null while `model_requested=gpt-5.5` stayed exact and no fallback occurred.
The remaining live acceptance item is a different Linux user cloning the repo,
logging in with their own eligible account, and completing the same path without
copied credentials. Do not claim that criterion until that separate user runs
it.

Never read, print, copy, parse, or commit ~/.codex/auth.json or equivalent OAuth
state. Do not automate login. A live request is separate, per-machine, and may
run only when explicitly opted in and already authenticated; it must expose no
prompt, raw CLI event, stderr, account identity, path, token, .env value, or
Supabase key. A successful local call does not prove another Plus/Pro account or
production readiness.

If verification finds a defect, fix the smallest owning contract and add a
regression test. Do not broaden Phase 10 into a deployable provider, API-key
fallback, autonomous agent, vector search, background message, model-controlled
tool/database access, automatic memory promotion, executable suggestion,
calendar prompt content, or notification delivery. Select any new product
slice only from a separately verified user need, and update docs with exact
current-checkout results.
```
