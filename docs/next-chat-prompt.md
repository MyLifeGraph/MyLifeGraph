# Next Chat Prompt

Use this prompt when starting Phase 5 after the deterministic briefing backend.

Recommended reasoning level: **high**. This slice changes the primary product
surface, but it must consume the proven backend contract rather than redesign
ranking, execution, or persistence.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md, README.md, docs/architecture.md,
docs/backend-roadmap.md, docs/daily-briefing-implementation-plan.md,
docs/phase-3-executable-actions-contract.md, docs/supabase-current-state.md,
docs/local-dev.md, and docs/verification.md.

Goal: implement Phase 5, Decision-First Today Dashboard.

Phase 4 is implemented. FastAPI persists one `daily-briefing-v1` row per
user/profile-local date. `GET /v1/briefings/today` is read-only and reports
missing/current/stale truth. Deliberate `POST /v1/briefings/generate` refreshes
Daily State when needed, is idempotent unless forced, uses no LLM, and returns
one strict `executable-action-v1` primary action plus at most two support
actions. Numeric capacity stays null; the contract uses a bounded capacity
note. Phase 2 Daily State and Phase 3 execution semantics are unchanged.

Build the actual authenticated Today experience, not a marketing surface:

- Read the briefing without generating during normal page load.
- Put mode, freshness/data quality, capacity note, primary action, and its
  evidence-backed reason above secondary metrics.
- Dispatch the primary and support targets through the existing exhaustive
  `ExecutableActionDispatcher`; do not invent routes or duplicate command logic.
- Provide a deliberate refresh control that calls POST and preserves honest
  loading, missing, stale, and error states.
- Keep the current direct nullable check-in values and useful execution/history
  below the decision surface rather than removing source truth.
- Keep guest/mock mode explicitly local and do not call privileged briefing
  endpoints for it. Do not fabricate a personalized local briefing.
- Do not add decision feedback adaptation, Coach, calendar import, workers,
  planning commands, notifications, or an LLM in this slice.
- Add typed Flutter models/data source/repository/provider coverage, widget
  tests for all briefing states and action dispatch, and browser assertions for
  read-only load, deliberate generation, exact persisted identity, and a real
  executable primary target.
- Update architecture, local development, verification, roadmap, README, and
  AGENTS.md in the same change. Do not claim browser E2E unless it succeeds in
  the current checkout.
```
