# Next Chat Prompt

Use this prompt when starting a new implementation chat for the next backend
slice.

Recommended reasoning level: **high**. The next work crosses schema, backend,
Flutter, auth, RLS, and tests. Use a lower level only for small follow-up edits.
Use the highest available level only if migration debugging or E2E failures
become the main task.

If the environment supports subagents, spawn a small coordinated set after all
agents have read the required docs. Do not spawn more than needed.

Suggested subagents:

- Schema/backend agent: Supabase migration, RLS, FastAPI intake models,
  repositories, and endpoint.
- Flutter agent: structured onboarding UI and real/mock/guest integration.
- Verification agent: unit tests, Flutter tests, local Supabase reset strategy,
  and E2E impact.
- Docs/security reviewer: keeps `AGENTS.md`, architecture, Supabase, and
  verification docs aligned and checks service-role/RLS boundaries.

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

Goal: implement the next roadmap slice, "Intake V1 without LLM".

Coordinate a small set of subagents if available:

- Schema/backend: migration, RLS, FastAPI models/repositories/service/route.
- Flutter: structured onboarding and real/mock/guest behavior.
- Verification: tests and local Supabase/E2E verification plan.
- Docs/security review: documentation and auth/service-role boundaries.

Implementation requirements:

- Add Supabase tables for `intake_responses` and `user_state_snapshots`.
- Add RLS and grants consistent with the canonical snake_case schema.
- Add authenticated FastAPI endpoint `POST /v1/intake/complete`.
- Reuse the existing Supabase bearer-token auth dependency.
- Derive `user_id` from the verified backend principal only.
- Store raw structured intake answers.
- Create an onboarding `user_state_snapshots` row.
- Create initial `goals`, notification preferences, and limited durable
  `memory_entries` from explicit structured answers.
- Do not add LLM providers.
- Do not require calendar connection.
- Preserve mock and guest mode.
- Keep service-role credentials backend-only.
- Update docs in the same change.

Preferred implementation sequence:

1. Inspect current schema, FastAPI patterns, Flutter onboarding, and tests.
2. Add the migration with the smallest safe schema.
3. Implement FastAPI intake models, repository, service, route, and tests.
4. Extend Flutter onboarding to submit intake in real mode and fallback locally
   in guest/mock mode.
5. Run the lowest sufficient verification first, then broaden.
6. Report any verification that could not be run.

Do not implement coach LLM, calendar import, weekly planning, vector search, or
background workers in this slice.

Do not commit unless explicitly asked.
```
