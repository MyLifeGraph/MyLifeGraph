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

At the current review checkpoint, source verification passes with 721 Backend
tests plus one opt-in skip, 524 Flutter tests, clean analysis, and a clean
`scripts/verify.sh`. After explicit user permission, local migration
`20260714130000` and the reviewed
`20260714143000_notification_delivery_settings_guard.sql` follow-up were applied
without a reset; local history matches the repository. A rollback-only guard
smoke passed, and the full non-reset browser journey passed with
`E2E browser smoke passed for e2e-1784046486@example.test`.

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
3. Preserve and verify the implemented Notification Delivery V1 slice rather
   than rebuilding it: explicit consent separate from reminder preferences,
   deterministic fixed-copy generation, owner-locked timezone/quiet/category/
   cap/dedupe/provenance guards, the existing secret-safe 15-minute local
   runner, and acknowledged at-most-once Flutter foreground banners. Apply any
   future pending local migration only with explicit permission. Preserve the
   now-passing authenticated browser coverage for consent, rejection cases,
   dedupe, provenance, receipt, Inbox refresh, and replay suppression. Do not
   claim push/system or deployed delivery.
4. Preserve the Weekly Review action-authority cleanup: only confirmed manual
   shrink/pause/archive is labeled executable; Setup links explicitly apply
   nothing; staged replacement/defer and keep rows are non-interactive notes.
   Extend E2E if needed, but do not turn staged advice into an unreviewed
   mutation.
5. Re-inventory remaining visible controls after the Notification E2E. Every
   control must be a durable typed recoverable command, unmistakably read-only
   information, or absent. Do not make Coach suggestions mutate state without a
   separately reviewed confirmation/ownership/recovery contract.
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
