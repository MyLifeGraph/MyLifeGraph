# Next Chat Prompt

Use this prompt when starting Phase 8 after the minimal Scheduled Daily
Preparation backend.

Recommended reasoning level: **high**. This slice should turn one bounded week
of explicit outcomes into a short review and at most one or two user-confirmed
adaptations without becoming an autonomous planner.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md, README.md, docs/architecture.md,
docs/backend-roadmap.md, docs/daily-briefing-implementation-plan.md,
docs/phase-3-executable-actions-contract.md, docs/supabase-current-state.md,
docs/local-dev.md, and docs/verification.md.

Goal: implement Phase 8, Bounded Weekly Review And Habit Adaptation.

Phases 0 through 6 are implemented. Today consumes one persisted deterministic
briefing, executes strict actions, records bounded owner-scoped feedback, and
explains feedback influence through `feedback-ranking-v1`. Insights defaults to
one cautious observation; correlation analytics remain advanced exploration.
The minimal Phase 7 backend is also implemented: the protected scheduled
endpoint pins one aware run instant, resolves eligible profile-local dates,
handles missing/stale/current snapshot and briefing state idempotently, supports
bounded `profile_ids`, and isolates per-user failures. It sends no notifications
and does not prove deployed cron wiring.

- Start by auditing the implemented weekly snapshot, goal, task, Habit V1,
  focus-session, briefing, and decision-feedback contracts. Define one narrow
  weekly-review contract before choosing persistence or UI shape.
- Pin the review to an explicit profile-local ISO week and a bounded evidence
  window. Summarize only durable facts: completed and carried tasks, scheduled
  habit opportunities, completed/skipped/missed outcomes, focus sessions,
  recovery-mode days, and relevant feedback.
- Keep completion, intentional skip, missed opportunity, paused/archived state,
  and recovery day distinct. Do not moralize gaps or fabricate outcomes.
- Produce at most one or two deterministic, evidence-backed proposals. Each
  proposal must state why it exists, what record it would affect, and whether it
  is keep, shrink, pause, replace, archive, or defer.
- Require explicit confirmation before changing any goal, habit, task, or
  schedule row. A review read/generation path must never mutate user-owned
  records. Confirmed changes must use typed owner-scoped commands, be retry-safe,
  and expose partial/ambiguous failure honestly.
- Preserve ownership boundaries. Setup-owned habit definitions and lifecycle
  remain managed through Settings Setup; a weekly review may stage or deep-link
  an eligible change but must not silently transfer ownership to generic Habit
  Management.
- Keep `review_plan` unavailable until this slice provides a real bounded
  surface and exhaustive dispatcher behavior. Do not enable it as a route-only
  no-op.
- Keep the implementation deterministic and no-LLM. Do not add Coach, calendar
  import, vector search, broad memory extraction, an autonomous planner, or
  unreviewed schedule/goal changes.
- Preserve normal Dashboard GET-only behavior, deliberate daily adjustment,
  guest/mock locality, Phase 2 Daily State, Phase 3 executable actions, Phase 6
  feedback provenance, and Phase 7 scheduled preparation semantics.
- Do not add or claim notification delivery, a production worker, or deployed
  cron wiring as part of weekly review.
- Add focused backend, Flutter, repository/schema, and browser assertions in
  proportion to the chosen contract. Keep documentation current and establish a
  current-checkout verification result before claiming E2E completion.
```
