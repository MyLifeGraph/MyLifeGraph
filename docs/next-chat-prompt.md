# Next Chat Prompt

Use this prompt when starting Phase 7 after Feedback And Useful Insights.

Recommended reasoning level: **high**. This slice turns the existing protected
refresh endpoint into reliable daily preparation without hiding generation or
introducing autonomous product changes.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md, README.md, docs/architecture.md,
docs/backend-roadmap.md, docs/daily-briefing-implementation-plan.md,
docs/phase-3-executable-actions-contract.md, docs/supabase-current-state.md,
docs/local-dev.md, and docs/verification.md.

Goal: implement Phase 7, Scheduled Daily Preparation.

Phases 0 through 6 are implemented. Today consumes one persisted deterministic
briefing, executes strict actions, records bounded owner-scoped feedback, and
explains feedback influence through `feedback-ranking-v1`. Insights defaults to
one cautious observation; correlation analytics remain advanced exploration.

- Extend the existing protected scheduled refresh boundary instead of adding an
  unrelated worker abstraction.
- Prepare daily snapshots and persisted briefings for onboarded non-guest users
  according to each profile timezone and local briefing date.
- Define idempotent missing/stale/current behavior and isolate one user's failure
  from the rest of the batch.
- Keep all scheduled generation deterministic, no-LLM, bounded, observable, and
  safe to retry.
- Preserve normal Dashboard GET-only behavior and explicit user adjustment.
- Do not generate recommendations, mutate tasks/habits/goals, or send
  notifications unless the Phase 7 contract explicitly requires and tests it.
- If notification preparation is included, make it opt-in, honor quiet hours and
  frequency caps, deep-link to an exact action, and exclude sensitive state.
- Do not add Coach, calendar import, weekly planning, vector search, autonomous
  changes, or an LLM.
- Add focused backend/schema/client tests only where the contract requires them,
  full verification, browser evidence, and current documentation.
- Do not claim deployed cron wiring unless the deployment target is directly
  configured and inspected; a locally verified scheduler endpoint is not a
  production deployment claim.
```
