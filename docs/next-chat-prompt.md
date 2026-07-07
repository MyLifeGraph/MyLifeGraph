# Next Chat Prompt

Use this prompt when starting a new implementation chat after the Daily
Briefing / Daily Decision Loop roadmap consolidation.

Recommended reasoning level: **high**. The next work crosses Flutter check-in
UX, Supabase metadata writes, deterministic snapshot generation, recommendation
ranking, guest/mock behavior, and tests.

Do not spawn multiple agents by default. Use subagents only when the work is
clearly separable, the write scopes do not overlap, and parallelism materially
reduces risk or time. For a narrow continuation, one main agent should usually
inspect, implement, verify, and update docs end to end.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

Use high reasoning. First read:

1. AGENTS.md
2. README.md
3. docs/architecture.md
4. docs/backend-roadmap.md
5. docs/daily-briefing-implementation-plan.md
6. docs/supabase-current-state.md
7. docs/local-dev.md
8. docs/verification.md

Goal: implement the next roadmap slice after Intake V1, controlled post-intake
deterministic recommendation refresh, authenticated snapshot aggregation, and
FastAPI-backed browser E2E coverage, without LLM. The current product priority
is the Daily Briefing / Daily Decision Loop: lightweight daily capture,
explainable daily state, Daily Mode, and a small number of ranked next actions.

Do not spawn multiple agents by default. Use subagents only if there are clearly
separable non-overlapping tasks that can run in parallel without blocking the
main implementation. If the slice is narrow, keep the work in one agent.

Focus on the smallest useful Daily Briefing foundation slice:

- Extend the daily/evening check-in path with stress source, stress
  controllability, stress intensity label, and optional gentle-tomorrow intent.
- Persist those fields in existing `daily_logs.metadata.stress` and mirror them
  into relevant `behavioral_events.metadata`; do not add schema columns unless
  the implementation genuinely needs them.
- Preserve the existing numeric `stress_level`, energy, mood, focus, and
  check-in behavior.
- Extend deterministic snapshot aggregation to summarize the new stress
  taxonomy and emit risk flags such as private/emotional stress,
  avoidable-pressure stress, low-control stress, overload, and recovery risk.
- Add or prepare a deterministic Daily Mode classifier with modes `push`,
  `steady`, `recover`, and `plan`.
- Private/emotional and low-control stress should reduce load and avoid
  aggressive productivity recommendations.

- Reuse the existing Supabase bearer-token auth dependency.
- Derive `user_id` from the verified backend principal only.
- Reuse existing `intake_responses` and `user_state_snapshots`.
- Preserve `POST /v1/snapshots/generate` behavior for deterministic `daily` and
  `weekly` snapshots.
- Preserve the existing best-effort daily refresh after Supabase-backed Daily
  Check-In, Quick Mood Check-In, dashboard task writes, and habit writes.
- Preserve the existing post-intake recommendation refresh behavior.
- Preserve the FastAPI-backed browser E2E coverage in `scripts/e2e_web.sh`.
- Do not build the full `daily_briefings` table/service until the missing
  capture and snapshot signals are in place.
- Deployed cron/job execution is still useful later, but should be evaluated
  against the Daily Briefing cadence, not treated as a standalone next slice.
- Do not add LLM providers.
- Do not require calendar connection.
- Preserve mock and guest mode.
- Keep service-role credentials backend-only.
- Update docs in the same change.

Preferred implementation sequence:

1. Inspect current Flutter Daily Check-In and Quick Mood Check-In flows,
   Supabase data sources, FastAPI snapshot aggregation, and recommendation
   rules.
2. Add the stress taxonomy to the smallest appropriate check-in/evening capture
   path, keeping the UI under a lightweight daily-capture burden.
3. Persist the new fields in metadata for guest/mock and Supabase-backed paths.
4. Extend snapshot aggregation with the new stress summaries and risk flags.
5. Add focused tests for private/emotional low-control stress, avoidable
   pressure, and no-regression guest/mock behavior.
6. Preserve mock and guest mode; do not trigger LLM or recommendation
   generation on dashboard load.
7. Run the lowest sufficient verification first, then broaden.
8. Report any verification that could not be run.

Do not implement the full Daily Briefing service, coach LLM, calendar import,
weekly planning, vector search, or background workers in this slice unless the
user explicitly changes scope.

Do not commit unless explicitly asked.
```
