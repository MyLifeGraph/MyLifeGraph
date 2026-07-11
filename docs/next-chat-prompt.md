# Next Chat Prompt

Use this prompt when starting a new implementation chat after Phase 2,
Explainable Daily State.

Recommended reasoning level: **high**. This work makes future briefing targets
actually executable and recoverable. It must not jump ahead to action ranking,
a Today redesign, or an LLM.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

Use high reasoning. First read completely:

1. AGENTS.md
2. README.md
3. docs/architecture.md
4. docs/backend-roadmap.md
5. docs/daily-briefing-implementation-plan.md
6. docs/supabase-current-state.md
7. docs/local-dev.md
8. docs/verification.md

Goal: implement Phase 3, Executable Tasks, Habits, And Focus. Phase 0A, 0B,
0C, Phase 1, and Phase 2 are implemented. Preserve all of their contracts.

Phase 2 adds `summary.daily_state` and `signals.daily_state` under
`explainable-daily-state-v1` without schema changes. Its strict parser trusts
Phase 1 V2 captures only after identity, enum, numeric, timestamp, and projection
validation; legacy numeric fallback applies only when no V2 marker exists. It
uses a fixed seven-day state lookback separate from the requested statistics
window. Evening from the target date or previous date and Morning from the
target date define current cadence. Quality is missing, partial, current, or
stale. Daily Mode is recovery-first push, steady, recover, or plan with bounded
risks, reasons, evidence, provenance, and no capture free text or learned
baseline. The source marker remains snapshot-aggregator-v1; metadata carries
the Daily State contract and lookback. Top-level summary.risk_flags aliases the
current Daily State codes, summary.window_risk_flags retains window aggregate
flags, and recommended_next_focus is recovery-first from mode.

Do not change Phase 2 classification, freshness, evidence, recommendation
ranking, or its no-LLM/no-Today boundary as a side effect of Phase 3. Guest/mock
remains local. Phase 0C Setup request/base-revision/pending/applied semantics and
the service-role-only atomic Setup RPC remain unchanged.

Start by auditing the existing executable paths end to end:

1. Task status currently supports done/todo/cancelled from Dashboard but lacks a
   complete create/edit/postpone/cancel/undo contract and reliable estimates.
2. Habit Management currently creates/edits/pauses/restores manual habits;
   Habit Completion writes one daily value. Its seven-day count is not honest
   cadence-aware progress and has no intentional skip or undo.
3. Setup-owned active habits remain completable but their definition/lifecycle
   stays owned by Settings Setup. Generic Habit Management must not claim them.
4. Deep Work remains gated because no real focus-session lifecycle exists.
5. A future briefing needs typed action targets and commands whose handlers are
   real, durable, user-scoped, and recoverable.

Inspect at minimum:

- task domain/entity, Dashboard task mapper and status write path
- `habits`, `habit_logs`, their Supabase data sources, Setup ownership filters,
  current progress math, and Quick Action pages
- `focus_sessions` schema and any gated Deep Work implementation
- route/capability allowlists and notification action targets
- snapshot refresh entrypoints after successful task/habit writes
- current migrations, RLS/grants, Supabase-state docs, widget tests, and
  `e2e/web/smoke.mjs`

Write the Phase 3 object and command matrix before editing. At minimum decide:

- task commands: create, edit, complete, postpone, cancel, restore/undo
- task status/deadline/estimate validation and failed-write rollback
- habit cadence: daily, selected weekdays, or x-times-per-week
- habit daily outcome: completed, intentionally skipped, or still open
- habit progress/streak rules based on scheduled opportunities, not seven
  calendar days
- undo semantics for completion and skip
- Setup-owned versus manually managed habit ownership
- focus-session start, stop/finish, abandon, duration, and optional linked target
- stable action-target id, kind, command, target id, and bounded metadata
- unsupported command behavior: explicit unavailable/error, never enabled no-op

Required product contract:

- Every visible action must persist what its label promises and show rollback,
  retry, confirmation, or undo appropriate to its risk.
- Derive user identity from the authenticated Supabase session or verified
  backend principal. Never trust a request-provided user_id.
- Preserve manual rows and Setup ownership. Setup-owned habit definition and
  lifecycle remain in Settings Setup; active rows may be completed or skipped
  through the daily execution contract.
- Daily/scheduled habit progress is completed elapsed opportunities divided by
  elapsed scheduled opportunities. Weekly-target progress is completed divided
  by target for the current week. An intentional skip is neither completion nor
  a fabricated success.
- Recover mode or an explicit day pause may reduce streak pressure later, but
  Phase 3 must not fabricate completion or silently rewrite Phase 2 state.
- Do not encode skip through an undocumented `habit_logs.value` sentinel. If the
  current schema cannot represent explicit outcome safely, add the smallest
  migration with checks, indexes if needed, grants/RLS verification, repository
  coverage, local reset verification, and current documentation.
- Focus sessions must have a real lifecycle and timestamps. Finishing a focus
  session must not automatically complete a linked task or habit without an
  explicit user confirmation.
- Successful real task/habit/focus writes refresh the daily snapshot
  best-effort where the existing contract calls for it. Refresh failure must not
  roll back the durable original write. Guest/mock paths make no remote call.
- Keep recommendations read-only on normal Dashboard load. Phase 3 must not
  generate or rank recommendations, generate a briefing, or call an LLM.

Implementation guidance:

1. Prefer typed domain commands/results over page-local maps and booleans.
2. Keep persistence and ownership validation in data/repository boundaries, not
   in visual widgets.
3. Reuse existing canonical snake_case tables. Add schema only for a real
   contract gap, especially explicit habit outcome or focus linkage.
4. Make optimistic UI reversible. A failed write restores the persisted state
   and exposes a recoverable error.
5. Keep action targets independent of briefing ranking. Phase 3 proves that a
   command can execute; a later phase decides which action is primary.
6. Keep unknown future command values unsupported instead of mapping them to a
   generic route or no-op.
7. Preserve the gated Coach and keep Deep Work gated unless the real focus
   lifecycle is complete end to end.
8. Extend browser E2E with exact database assertions for the implemented task,
   habit, and focus outcomes, including undo and ownership preservation. Do not
   claim E2E passed unless it was run successfully in the current checkout.

Focused tests must cover:

- every task command, validation boundary, rollback, retry, and undo
- daily, selected-weekday, and weekly-target habit opportunities
- completion, intentional skip, still-open, pause/archive, and undo semantics
- week-boundary and timezone/date behavior without dividing by a fixed seven
- Setup-owned habit visibility and lifecycle ownership
- idempotent same-day habit outcome writes and no duplicate log rows
- focus start/finish/abandon, invalid transitions, duration, and linked-target
  ownership
- supported and unsupported typed action commands
- principal/user scoping and RLS/grant behavior for any changed schema
- best-effort snapshot refresh after durable real writes
- guest/mock locality with no Supabase, snapshot, recommendation, or LLM call
- preservation of the Phase 2 Daily State and recommendation candidate behavior

Run focused tests while implementing, then at minimum:

- Flutter analyze and the complete Flutter test suite
- the complete FastAPI test suite if backend code is touched
- `scripts/verify.sh`
- non-destructive local Supabase verification for client/schema integration
- a local reset only if a migration was intentionally added
- Browser E2E
- `git diff --check`

Update architecture, roadmap, Supabase-state, local-dev, verification, agent,
and continuation docs in the same change.

Do not implement briefing/action ranking, `daily_briefings`, the decision-first
Today dashboard, recommendation-ranking redesign, Coach/LLM, calendar import,
notifications expansion, weekly review, vector search, wearables, autonomous
workers, or remote production database changes in Phase 3.

Do not commit unless explicitly asked.
```
