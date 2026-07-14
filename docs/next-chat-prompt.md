# Next Chat Prompt

This run may start from a verified but uncommitted working tree. A missing Git
approval must not block safe implementation or verification. Use this prompt in
the new chat.
Recommended reasoning level: **high**.

```text
We are in /home/gregor/projects/ai-personal-coach. The user's goal is to finish
the complete product locally in WSL first, including the real Coach through
their own already authenticated Codex CLI. Android packaging and a deployable
API-backed LLM provider come only after the local release candidate is complete.
This is not a reduced demo target.

First read AGENTS.md completely and every document it requires for all Flutter,
backend, Supabase, product, Coach, notification, scheduling, account-control,
and verification work you will touch. Then read
docs/local-product-completion-handoff.md completely. Treat its completion
definition, phase order, and authorization boundary as the execution contract.
Run git status --short --branch before editing and preserve all user work.

Verify HEAD, the complete working tree, and all untracked files without assuming
that a checkpoint commit exists. If uncommitted work remains, do not discard it.
Run the applicable verification and continue safe work; if Git itself requires a
new interactive approval, leave an exact commit boundary and continue other
in-scope work rather than idling.

Work autonomously through as much of the handoff as the environment permits:

1. Re-establish the complete deterministic local product loop with standard
   verification, the full FastAPI suite, non-reset local Supabase verification,
   and the full non-reset browser E2E. The user authorizes uniquely named local
   E2E users and rows, but not RESET_DB=true or supabase db reset.
2. Make the real local Coach a reproducible supported local mode. Run fake
   provider coverage first, then the explicitly opt-in synthetic and full
   product live-Coach checks through the current WSL user's existing `codex
   login`. Never read/copy OAuth files or log the question, prompt, answer, raw
   events, account identity, paths, tokens, environment values, or Supabase
   keys. Use the exact configured model the account exposes and never add a
   silent fallback.
3. Close the proven Notification gap in separate reviewable slices: durable
   Inbox lifecycle, preference-aware backend generation, timezone/quiet-hour/
   cap/deduplication policy, and honest local scheduled delivery. Add migration,
   RLS, backend, Flutter, and browser regression coverage.
4. Make the existing protected daily-preparation endpoint actually run through
   a secret-safe documented local WSL scheduler/runner. Preserve idempotency,
   local dates, bounded targeting, per-user failure isolation, and no-LLM
   behavior.
5. Re-inventory every visible action and close remaining apparent-action gaps,
   especially Weekly Review proposals. Every visible control must be a durable
   typed recoverable command, unmistakably read-only information, or absent.
   Do not make Coach suggestions mutate state without a separately reviewed
   confirmation/ownership/recovery contract.
6. Provide a secret-safe one-command or short-sequence full local start path,
   then exercise the complete manual user journey and resilience/accessibility
   matrix from the handoff.
7. Rerun every final gate on the exact final checkout. Fix proved defects in
   the smallest owning contract with regression tests. Prepare small local
   commit boundaries after green slices, but commit only when the user has
   explicitly authorized Git writes. Do not push.

Keep going while safe in-scope work remains. Do not stop after analysis or one
passing suite. Distinguish product defects from environment/tool blockers and do
not claim a manual, live-provider, scheduler, delivery, or E2E result unless it
actually ran on the final relevant checkout.

Do not reset any database, inspect/mutate remote Supabase, deploy, push, open a
PR, publish, create/copy credentials or signing keys, automate login, read OAuth
files, or delete a non-disposable account. Do not broaden the product into
vector search, autonomous agents, model-controlled database/tools, hidden
memory extraction, live calendar-provider sync, or Android production work
during this local completion run.

Finish with exact commit ids, test/E2E/build results, live-Coach truth,
notification/scheduler behavior actually proven, manual acceptance results,
and the remaining external Android/deployment gates.
```
