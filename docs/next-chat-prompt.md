# Next Chat Prompt

Use this prompt when starting Phase 10 after bounded Calendar File Import.

Recommended reasoning level: **high**. The next slice should add one controlled,
authenticated explanation boundary without weakening the deterministic product
loop, exposing unbounded history, or applying suggestions automatically.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

First read AGENTS.md, README.md, docs/architecture.md,
docs/backend-roadmap.md, docs/daily-briefing-implementation-plan.md,
docs/phase-3-executable-actions-contract.md,
docs/phase-8-weekly-review-contract.md,
docs/phase-9-calendar-import-contract.md, docs/supabase-current-state.md,
docs/local-dev.md, and docs/verification.md.

Goal: implement the first bounded Phase 10 Controlled Coach slice.

Phases 0 through 9 are implemented. Today uses persisted deterministic daily
briefings, strict executable actions, bounded owner-scoped feedback, and useful
default Insights. Phase 7 provides a protected idempotent daily preparation
boundary but does not prove deployed cron or notification delivery. Phase 8
adds a strict completed-ISO-week review and confirmed manual Habit V1
adaptation only. Phase 9 adds one explicitly consented user-selected `.ics`
source with retry-safe import, imported/read-only provenance, and separate
disconnect/local-delete controls; it has no provider OAuth or writes and does
not feed calendar content into ranking or prompts. The combined local Phase 3
through Phase 9 browser journey passed non-destructively in the 2026-07-13 Phase
9 implementation checkout; later changes must establish their own result.

- Define one narrow authenticated Coach request/response, context, budget,
  provenance, retention, failure, and safety contract before choosing a model.
- Build context only from compact current snapshots, the persisted current
  briefing, selected reviewable memories, and a small recent message window.
  Never send full user history, imported calendar content, or hidden free text.
- Preserve the deterministic Today decision as source of truth. Coach may
  explain it or stage a bounded alternative; it must not silently regenerate a
  briefing, mutate a task/habit/schedule, or apply a weekly proposal.
- Keep task, habit, schedule, memory, and time-block suggestions staged for
  explicit review. Reuse a typed recoverable mutation only after its owning
  contract exists.
- Add explicit feature/budget flags, per-user usage limits, timeouts, model and
  prompt version provenance, uncertainty, and an honest unavailable state.
- Define wellness/medical boundaries and crisis-safe behavior without implying
  diagnosis, treatment, causation, or professional monitoring.
- Make memory used by Coach visible, selectable, editable, and deletable before
  claiming durable personalization. Do not extract/promote memory silently.
- Preserve guest/mock isolation, real/demo/integrated/model provenance, normal
  Dashboard GET-only behavior, Phase 2 Daily State, Phase 3 actions, Phase 6
  feedback, Phase 7 preparation, Phase 8 ownership/freshness, and Phase 9
  calendar privacy.
- Do not add autonomous agents, vector search, provider calendar writes,
  notification delivery, deployed cron, or unbounded conversation context as a
  side effect.
- Add focused backend, Flutter, schema/RLS/budget, safety, source-provenance,
  memory-control, and browser coverage. Keep docs current and establish a
  current-checkout result before claiming E2E.
```
