# Next Chat Prompt

Use this prompt when starting a new implementation chat for the next backend
slice after Intake V1.

Recommended reasoning level: **high**. The next work crosses FastAPI,
recommendation generation, snapshots, Flutter refresh behavior, Supabase RLS,
and tests.

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

Goal: implement the next roadmap slice after Intake V1 and controlled
post-intake deterministic recommendation refresh, without LLM.

Do not spawn multiple agents by default. Use subagents only if there are clearly
separable non-overlapping tasks that can run in parallel without blocking the
main implementation. If the slice is narrow, keep the work in one agent.

Focus on a recurring snapshot aggregator:

- Reuse the existing Supabase bearer-token auth dependency.
- Derive `user_id` from the verified backend principal only.
- Use existing `intake_responses` and `user_state_snapshots`.
- Preserve the existing post-intake recommendation refresh behavior.
- Do not add LLM providers.
- Do not require calendar connection.
- Preserve mock and guest mode.
- Keep service-role credentials backend-only.
- Update docs in the same change.

Preferred implementation sequence:

1. Inspect current FastAPI intake/recommendation services and Flutter
   onboarding/recommendation refresh behavior.
2. Implement the smallest useful deterministic snapshot aggregator slice for
   `daily` and/or `weekly` `user_state_snapshots`.
3. Implement the backend service/repository changes with focused tests.
4. Wire Flutter only where a deliberate user-visible refresh or post-intake
   invalidation is needed.
5. Run the lowest sufficient verification first, then broaden.
6. Report any verification that could not be run.

Do not implement coach LLM, calendar import, weekly planning, vector search, or
background workers in this slice unless the user explicitly changes scope.

Do not commit unless explicitly asked.
```
