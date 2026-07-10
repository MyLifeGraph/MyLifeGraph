# Next Chat Prompt

Use this prompt when starting a new implementation chat after Phase 0C,
First-Run And Setup Integrity.

Recommended reasoning level: **high**. This work crosses the canonical Flutter
capture draft, guest persistence, Supabase daily rows/events, time-of-day
semantics, and sensitive stress context.

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

Goal: implement Phase 1, Lightweight Evening And Morning Capture. Phase 0A,
0B, and 0C are complete: daily values are exact and retry-safe; demo and real
sources never mix; unsupported surfaces are gated; and Setup is progressive,
prefilled, revision-safe, ownership-scoped, and reviewable. Preserve all of
that. Guest Setup intentionally remains local when the user later authenticates;
do not add an automatic Setup migration while implementing Phase 1. Canonical
guest check-ins keep their existing best-effort auth migration.
Authenticated Setup apply is already atomic and per-user serialized through the
service-role-only database RPC. Mock/demo auth boot must remain free of remote
profile/data bootstrap and keep local Setup across reload. Preserve the existing
save-state split: 4xx stays editable, 409 offers reload, and ambiguous failures
require exact unchanged retry or reload. Setup-owned habits remain editable only
through Settings Setup and completable through Habit Completion.

Start by walking these journeys for guest and authenticated accounts:

1. Complete Evening Shutdown with only required answers in under 90 seconds.
2. Leave every optional note, blocker, and gentle-tomorrow field blank.
3. Record high workload/mostly-controllable stress and high private-emotional/
   hardly-controllable stress as distinct structured states.
4. Retry after a failed or timed-out save without losing the draft or creating
   another daily row/event set.
5. Re-open the same day's evening capture, see exact saved values prefilled,
   edit them, and replace the current state intentionally.
6. Complete a 10-to-20-second Morning Calibration with sleep, current energy,
   and normal/constrained/flexible day shape, including when no prior evening
   shutdown exists.

Inspect at minimum:

- the typed quick-check-in draft/domain model and guest/Supabase stores
- `quick_mood_check_in_page.dart` and Quick Action routing/providers
- `daily_logs` and `behavioral_events` payload mapping
- Dashboard reads of the latest check-in
- snapshot refresh triggers after successful real writes
- relevant migrations/RLS, backend snapshot inputs, Flutter tests, and
  `e2e/web/smoke.mjs`

Required product contract:

- Evening Shutdown captures mood, energy, stress intensity, stress source,
  stress controllability, a rough focus band, main friction, and one likely
  priority for tomorrow. Reflection, a specific blocker, and `make tomorrow
  gentler` are optional.
- Morning Calibration captures sleep quality or hours, current energy, and day
  shape only. It must not repeat the full evening form.
- Stress source is one of `workload`, `avoidable_pressure`,
  `private_emotional`, `physical_recovery`, or `external_environment`.
- Stress controllability is one of `hardly_controllable`,
  `partly_controllable`, or `mostly_controllable`.
- Persist structured Phase-1 fields in `daily_logs.metadata` and mirror the
  relevant values into linked `behavioral_events.metadata` first. Keep existing
  numeric mood/energy/stress/sleep compatibility.
- Use one explicit merge contract for evening and morning writes to the same
  `(user_id, entry_date)` row. Morning calibration must not erase evening
  context, and an evening edit must not erase morning fields accidentally.
- Store only explicit answers. Blank optional values remain absent/null and do
  not become fallback text, memory entries, tasks, recommendations, or schedule
  items.
- Guest/demo writes stay local and change subsequent guest reads. They never
  call Supabase, FastAPI, recommendation generation, or snapshot refresh.
- Authenticated write failures retain the exact draft and expose retry. The UI
  must not claim success before persistence; retry remains idempotent.
- Sensitive stress detail stays out of notification copy and is not promoted to
  durable coaching memory in this slice.
- First results remain current-state observations. Do not claim a learned
  baseline, diagnosis, causation, or Daily Mode.

Implementation guidance:

1. Write the current read/write matrix for the canonical daily row, four linked
   events, guest JSON, Dashboard mapper, and snapshot trigger before editing.
2. Define typed Evening Shutdown and Morning Calibration drafts plus an explicit
   same-day merge policy. Avoid parallel legacy forms.
3. Add the stress taxonomy, focus band, friction, tomorrow priority, optional
   reflection/blocker, gentle-tomorrow intent, capture kind, and capture time to
   bounded metadata with strict validation.
4. Extend the existing guest and Supabase stores. Preserve the stable capture
   identity, one daily row, and replacement/deduplication guarantees.
5. Build progressive evening UI and a separate short morning route/state. Reuse
   shared controls where useful without merging the two experiences into one
   long questionnaire.
6. Keep successful authenticated snapshot refresh best-effort. Do not add an
   LLM call or generate recommendations on normal read/save.
7. Add value-level tests for both capture kinds, optional blanks, every stress
   category/controllability enum, same-day merge in both orders, prefill/edit,
   failed save/retry, guest locality, and authenticated error behavior.
8. Extend Playwright E2E with distinctive evening and morning values and exact
   database assertions for one daily row, linked event metadata, merge
   preservation, and same-day retry deduplication.
9. Run focused tests, full Flutter/Python suites, `scripts/verify.sh`, local
   Supabase verification if schema changes, and browser E2E. Update all docs.

Prefer metadata over new columns for Phase 1 unless query/index requirements
make a migration demonstrably necessary. If schema changes, include migration,
RLS/grants verification, Supabase docs, local reset verification, and browser
assertions.

Do not implement Daily Mode, briefing persistence/ranking, Habit V1 cadence,
focus sessions, Coach/LLM, calendar import, wearables, weekly review, vector
search, notifications, or background workers in this slice.

Do not commit unless explicitly asked.
```
