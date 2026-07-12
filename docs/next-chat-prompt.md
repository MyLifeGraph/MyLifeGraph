# Next Chat Prompt

Use this prompt when starting Phase 6 after the decision-first Today Dashboard.

Recommended reasoning level: **high**. This slice introduces durable preference
history into deterministic ranking and must not erase evidence or overfit one
click.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md, README.md, docs/architecture.md,
docs/backend-roadmap.md, docs/daily-briefing-implementation-plan.md,
docs/phase-3-executable-actions-contract.md, docs/supabase-current-state.md,
docs/local-dev.md, and docs/verification.md.

Goal: implement Phase 6, Feedback And Useful Insights.

Phases 0 through 5 are implemented. Today reads one persisted strict
`daily-briefing-v1` decision without generation on normal load, preserves
missing/current/stale/error/demo truth, deliberately adjusts with `force=true`,
and dispatches current `executable-action-v1` targets through Phase 3 handlers.

Define the feedback contract before schema or UI work:

- Use bounded append-only events tied to the authenticated owner, briefing,
  recommendation when present, stable action id/kind, and exact feedback type.
- Support done, later, not_helpful, too_much, and does_not_fit semantics without
  confusing execution outcome with preference feedback.
- Keep original briefing/recommendation reason, provenance, and score evidence
  immutable; feedback is additional historical evidence.
- Scope effects by recency and relevant context such as Daily Mode, action kind,
  estimate, and rule/category. One click must not create a permanent global ban.
- Make feedback contribution bounded, deterministic, versioned, testable, and
  explainable in the resulting briefing provenance.
- Preserve recovery-first safeguards and urgent facts ahead of preference fit.
- Let users correct/delete their feedback history under owner-scoped RLS.
- Replace the default Insights entry with one cautious observation, visible
  evidence window, confidence/data-quality state, and optional bounded
  experiment; keep correlation exploration advanced and never claim causation.
- Keep normal Dashboard GET read-only. Do not add Coach, calendar, workers,
  notifications, autonomous changes, or an LLM.
- Add migration/RLS/grants when the contract justifies persistence, strict
  backend/Flutter models, focused tests, full verification, and browser evidence.
- Update architecture, roadmap, local-dev, verification, README, and AGENTS.md.
  Do not claim browser E2E unless it succeeds in the current checkout.
```
