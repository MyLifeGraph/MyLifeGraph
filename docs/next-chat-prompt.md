# Next Chat Prompt

Use this prompt when starting Phase 9 after bounded Weekly Review and confirmed
manual Habit V1 adaptation.

Recommended reasoning level: **high**. The next slice should reduce capture
friction through one optional, consented integration without introducing hidden
provider writes or making the standalone loop dependent on external data.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md, README.md, docs/architecture.md,
docs/backend-roadmap.md, docs/daily-briefing-implementation-plan.md,
docs/phase-3-executable-actions-contract.md,
docs/phase-8-weekly-review-contract.md, docs/supabase-current-state.md,
docs/local-dev.md, and docs/verification.md.

Goal: implement the first bounded Phase 9 optional-integration slice.

Phases 0 through 8 are implemented. Today uses persisted deterministic daily
briefings, strict executable actions, bounded owner-scoped feedback, and useful
default Insights. Phase 7 provides a protected idempotent daily preparation
boundary but does not prove deployed cron or notification delivery. Phase 8
adds a strict completed-ISO-week review, exact source fingerprints, at most two
deterministic proposals, and confirmed manual Habit V1 shrink/pause/archive
only. Setup ownership remains in Setup; compound changes remain staged.

- Start by defining one narrow consent, connection, import identity, provenance,
  disconnect, and deletion contract before choosing provider code or UI.
- Prefer calendar read/import first. Do not add provider writes in the same
  slice. Imported events must remain visibly distinguishable from manual and
  Setup-owned schedule rows.
- Keep the app fully useful without an integration. Connection must be optional
  and must not gate Setup, capture, Today, Weekly Review, or Insights.
- Stage proposed time blocks before any user-owned or provider mutation. Never
  create or modify commitments solely because an external event exists.
- Define deterministic deduplication, retry identity, pagination, timezone, and
  recurring-event boundaries. Do not create parallel duplicates on re-import.
- Give users visible disconnect and imported-data deletion controls. Persist
  any Settings control that claims to affect consent, sync, privacy, or data
  removal.
- Keep credentials and refresh tokens backend-only. Flutter must never receive
  a service-role key or provider secret.
- Preserve explicit real/demo/integrated provenance, honest empty/stale/error
  states, normal Dashboard GET-only behavior, Phase 2 Daily State, Phase 3
  action semantics, Phase 6 feedback, Phase 7 scheduled preparation, and Phase
  8 review ownership/freshness.
- Do not add Coach, an LLM provider, vector search, autonomous scheduling,
  notification delivery, or deployed cron as a side effect.
- Add focused backend, Flutter, schema/RLS, disconnect/delete, deduplication,
  and browser coverage in proportion to the contract. Keep docs current and
  establish a current-checkout verification result before claiming E2E.
```
