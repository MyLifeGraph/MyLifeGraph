# Next Chat Prompt

Use this prompt when starting the Phase 4 implementation chat after Phase 3,
Executable Tasks, Habits, And Focus.

Recommended reasoning level: **high**. This work makes a deterministic editorial
decision from already trusted state and executable targets. It must not fold the
later Today redesign, feedback loop, or an LLM into the service contract.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

Use high reasoning. First read completely:

1. AGENTS.md
2. README.md
3. docs/architecture.md
4. docs/backend-roadmap.md
5. docs/daily-briefing-implementation-plan.md
6. docs/phase-3-executable-actions-contract.md
7. docs/supabase-current-state.md
8. docs/local-dev.md
9. docs/verification.md

Goal: implement Phase 4, Deterministic Briefing Service. Phase 0A, 0B, 0C,
Phase 1, Phase 2, and Phase 3 are implemented. Preserve all of their contracts.

Phase 2 owns `summary.daily_state` and `signals.daily_state` under
`explainable-daily-state-v1`. It uses strict Phase 1 V2 parsing, a fixed
seven-day state lookback, explicit Evening/Morning freshness,
missing/partial/current/stale quality, and recovery-first
push/steady/recover/plan classification. Risks, reasons, evidence, and
provenance are deterministic; capture free text and learned-baseline claims are
excluded. The source marker remains `snapshot-aggregator-v1`.

Phase 3 now provides:

- owner-scoped task create/edit/complete/postpone/cancel/restore/undo with
  validated estimates, stable create identity, retained failure state, and
  exact persisted reconciliation after an ambiguous response from every update
  including undo, plus best-effort snapshot refresh;
- Habit V1 daily, selected-ISO-weekday, and weekly-target cadence; explicit
  completed/skipped outcomes; derived open/missed state; cadence-aware progress
  and streaks; same-day undo; and separate manual versus Setup-owned lifecycle
  authority. Writes lock/revalidate current eligibility; reads paginate history
  beginning 370 calendar days before today; and `started_on` calendar math is
  DST-safe. Manual definition/lifecycle response loss requires exact readback;
  outcome/undo fixes one target date, proves the exact row or absence, and
  refreshes that date;
- a real one-active-session focus lifecycle with optional owned task or active
  habit linkage, measured finish/abandon duration, and no implicit target
  completion. Target validation locks the selected row, terminal response loss
  is reconciled exactly, every terminal-row update is rejected, target deletion
  is restricted, and refresh uses the persisted local start date with the same
  deterministic UTC legacy fallback in Flutter and FastAPI;
- parser-equivalent strict Flutter and FastAPI `executable-action-v1` targets.
  Explicit-null metadata fields, unsupported or mismatched commands fail
  explicitly, and `review_plan` remains unavailable;
- additive habit/focus snapshot summaries that do not change the Phase 2 Daily
  State result and are loaded through complete, stably ordered 1,000-row action
  windows; and
- migration `20260711120000_phase_3_executable_action_schema.sql`, which must be
  present in the local schema before exercising Phase 3 or Phase 4 candidates.

Do not change Phase 2 classification/freshness/evidence or Phase 3 task, habit,
focus, action-target, ownership, and refresh semantics as a side effect of
briefing work. Guest/mock remains local. Phase 0C Setup revisions and its
service-role-only atomic RPC remain unchanged. Normal Dashboard reads and
ordinary captures/actions must not generate recommendations or briefings.

Before editing, inspect the current snapshot, recommendation, executable-action,
auth, repository, router, migration, and E2E paths. If the current checkout has
not yet completed Phase 3 verification, establish the relevant focused checks
first. The browser source contains Phase 3 task/habit/focus response-loss cases
for habit/task create, habit outcome/undo, task completion/undo, and focus
start/finish, plus negative database assertions including terminal-focus
`updated_at`. Do not claim a current E2E pass unless the command succeeds in
this checkout.

Write the Phase 4 briefing contract and deterministic ranking matrix before
implementation. Decide at minimum:

- stable briefing contract version and one daily identity per user/local date;
- current, stale, missing, and error read states;
- one primary action and at most two ordered support actions;
- mode, bounded reason, capacity/time note, freshness, provenance, evidence
  references, and data-quality representation;
- candidate eligibility for open tasks, today's relevant habits, focus setup,
  implemented capture actions, and existing valid recommendations; the reserved
  recovery kind is not executable without a compatible command;
- recovery-first ranking and exclusion of terminal/unavailable targets;
- deterministic tie-breaking and idempotent regeneration;
- exact `executable-action-v1` validation before returning an action;
- insufficient-data behavior that remains conservative and useful;
- GET read-only versus deliberate POST generation behavior;
- whether `daily_briefings` persistence is genuinely required for stable daily
  identity, morning availability, scheduling, stale detection, or exact E2E.

Required API/product contract:

- `GET /v1/briefings/today` derives the user from the verified bearer token and
  reads only. It never generates a briefing or recommendation and must report
  missing/stale/error honestly.
- `POST /v1/briefings/generate` derives the same principal, is deliberate and
  authenticated, and deterministically creates or replaces the user's target
  date briefing without duplicates.
- Return exactly one primary action when a safe executable candidate exists and
  no more than two support actions. Never pad with invented commitments.
- Every action target must pass the Phase 3 strict parser and correspond to a
  currently available owner-scoped command. No generic fallback route or
  enabled no-op is allowed.
- Recovery risk and low-quality/stale evidence constrain ambition before
  urgency or productivity ranking. The briefing may explain Phase 2 state but
  must not recalculate or rewrite it.
- Recommendations remain candidates, not silently created tasks, habits, or
  schedule items. User-owned commitments require confirmation.
- LLM wording remains disabled. Do not add a provider abstraction merely for
  future use.
- Guest/mock behavior stays explicitly local/demo and makes no privileged
  FastAPI/Supabase command unless a separate honest local briefing contract is
  deliberately implemented.
- Persistence, if added, must use the smallest canonical migration with RLS,
  grants, unique daily identity, repository tests, local reset verification,
  Supabase docs, and exact browser assertions.

Implementation guidance:

1. Prefer strict Pydantic/domain models and an explicit deterministic ranking
   service over page-local maps or a generic agent loop.
2. Reuse compact snapshots and bounded current records. Do not read or send full
   user history.
3. Keep candidate loading, eligibility, scoring, tie-breaking, verification,
   and persistence as inspectable stages.
4. Make provenance and evidence reference the source snapshot/records without
   persisting sensitive capture free text.
5. Preserve recommendation read/generate endpoints and fingerprints unless a
   narrowly demonstrated integration change is needed.
6. Do not redesign Dashboard as Today in this phase. A minimal client/repository
   integration may prove the API contract, but Phase 5 owns the decision-first
   screen and feedback controls.
7. Keep scheduled briefing generation out unless the persisted contract and
   idempotency are already proven; deployed cron wiring is not the product goal.

Focused tests must cover:

- strict briefing request/response parsing and unknown-field rejection;
- principal-derived identity and request `user_id` rejection;
- GET read-only behavior with current/stale/missing/error states;
- deliberate POST generation, same-user/local-date idempotency, and user
  scoping;
- candidate eligibility across tasks, scheduled habits, focus, and capture;
  recovery constraints plus terminal/unavailable exclusion;
- all Daily Modes, insufficient/stale evidence, recovery-first precedence, and
  deterministic tie-breaking;
- one primary plus at most two support actions with no fabricated padding;
- exact valid `executable-action-v1` envelopes and explicit unsupported
  `review_plan` behavior, preserving Flutter/FastAPI parser parity;
- provenance, freshness, evidence refs, sensitive-text exclusion, and bounded
  payload size;
- preservation of Phase 2 Daily State and Phase 3 response reconciliation,
  locked habit eligibility, immutable focus history, local start-date snapshot,
  pagination/DST, and action-dispatch semantics;
- no recommendation or briefing generation on normal Dashboard reads or
  ordinary capture/task/habit/focus writes;
- guest/mock locality and no LLM call;
- migration/RLS/grants/unique-identity behavior if persistence is added; and
- browser evidence for read-only GET, deliberate POST, exact ranked targets,
  user scoping, freshness, and idempotency.

Run focused tests while implementing, then at minimum:

- Flutter analyze and the complete Flutter test suite if Flutter is touched;
- the complete FastAPI test suite;
- `FLUTTER_BIN=/path/to/flutter scripts/verify.sh`;
- non-destructive local Supabase verification;
- `HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local`
  when a migration is pending;
- `RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh`
  only when proving an intentionally added migration from a fresh local DB;
- Browser E2E for the current checkout; and
- `git diff --check`.

Update architecture, roadmap, Supabase-state, local-dev, verification, agent,
service, and continuation docs in the same change.

Do not implement the Phase 5 decision-first Today/Dashboard redesign or its
start/done/later/replace/too-much feedback, Phase 6 decision-feedback learning,
bounded planning, Coach/LLM, calendar import, notification expansion, weekly
review, vector search, wearables, autonomous workers, deployed cron, or remote
production database changes in Phase 4.

Do not commit unless explicitly asked.
```
