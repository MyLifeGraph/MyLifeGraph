# Next Chat Prompt

Use this prompt when starting a new implementation chat after the
FastAPI-backed browser E2E expansion.

Recommended reasoning level: **high**. The next work crosses FastAPI,
snapshot generation, recommendation refresh behavior, Flutter trigger points,
Supabase RLS, and tests.

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
5. docs/supabase-current-state.md
6. docs/local-dev.md
7. docs/verification.md

Goal: implement the next roadmap slice after Intake V1, controlled post-intake
deterministic recommendation refresh, authenticated snapshot aggregation, and
FastAPI-backed browser E2E coverage, without LLM.

Do not spawn multiple agents by default. Use subagents only if there are clearly
separable non-overlapping tasks that can run in parallel without blocking the
main implementation. If the slice is narrow, keep the work in one agent.

Focus on the next controlled snapshot refresh trigger after task or habit
changes:

- Reuse the existing Supabase bearer-token auth dependency.
- Derive `user_id` from the verified backend principal only.
- Reuse existing `intake_responses` and `user_state_snapshots`.
- Preserve `POST /v1/snapshots/generate` behavior for deterministic `daily` and
  `weekly` snapshots.
- Preserve the existing best-effort daily refresh after Supabase-backed Daily
  Check-In and Quick Mood Check-In.
- Preserve the existing post-intake recommendation refresh behavior.
- Preserve the FastAPI-backed browser E2E coverage in `scripts/e2e_web.sh`.
- Do not add LLM providers.
- Do not require calendar connection.
- Preserve mock and guest mode.
- Keep service-role credentials backend-only.
- Update docs in the same change.

Preferred implementation sequence:

1. Inspect current FastAPI intake, recommendation, and snapshot services plus
   Flutter task/habit write flows.
2. Choose the smallest controlled trigger: task completion/update, habit
   creation/update, or habit log completion.
3. Implement backend and/or Flutter wiring with focused tests.
4. Preserve mock and guest mode; do not trigger LLM or recommendation
   generation on dashboard load.
5. Run the lowest sufficient verification first, then broaden.
6. Report any verification that could not be run.

Do not implement coach LLM, calendar import, weekly planning, vector search, or
background workers in this slice unless the user explicitly changes scope.

Do not commit unless explicitly asked.
```
