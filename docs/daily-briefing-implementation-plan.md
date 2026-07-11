# Daily Briefing Implementation Plan

This document turns the product idea of a daily decision cockpit into an
implementation plan. It is intentionally evaluation-oriented: each phase states
the product goal, the reasoning behind it, the required implementation work, and
the criteria for deciding whether the next step is worth building.

## Product Thesis

MyLifeGraph should not become only a habit tracker, task list, or chat surface.
The core product value should be:

> Help the user decide what to do today by combining goals, energy, stress,
> recovery, tasks, habits, and recent behavior into a small number of concrete
> next actions.

The product should answer one question better than a generic coach:

> What is the most sensible next step for me today, given my current state?

The first durable version should be deterministic and explainable. LLM wording,
calendar import, wearables, vector search, and autonomous agents can improve the
experience later, but they are not required for the first useful product loop.

## Product Positioning

MyLifeGraph should occupy the intersection between a daily planner, a state and
recovery guide, and a lightweight behavior coach. It should not try to beat a
dedicated task manager, habit tracker, wearable, journal, and chat assistant at
their complete feature sets.

The differentiating promise is:

> Turn the user's current capacity and real-life context into one realistic next
> action, then learn from what actually happened.

This positioning has practical consequences:

- The dashboard is a decision and execution surface, not a metric gallery.
- Habits support goals and the daily plan; they are not the product center.
- Insights should lead to a small experiment or changed decision, not only a
  chart.
- Coach chat explains or adapts an existing plan after the deterministic loop is
  useful; it does not substitute for that loop.
- Calendar and wearable integrations reduce capture effort later; neither is an
  onboarding requirement.

## Product Object Model

Keep these concepts distinct in the domain and persistence layers even when the
Today UI presents them together:

| Concept | Meaning | Lifetime | Expected user action |
| --- | --- | --- | --- |
| Goal | A desired outcome or direction | Weeks to months | Review, refine, complete, archive |
| Task | A finite action with an optional deadline and estimate | Hours to weeks | Start, complete, postpone, cancel |
| Habit | A recurring behavior with a cadence and flexible execution window | Weeks to months | Complete, skip intentionally, pause, adapt |
| Schedule item | A fixed commitment or reserved block | One occurrence or recurring | Attend, edit, remove |
| Focus session | Time spent executing a task, habit, or chosen action | Minutes to hours | Start, stop, finish, abandon |
| Recommendation | A temporary evidence-backed candidate proposed by the system | Hours to days | Accept, defer, reject, mark too much |
| Daily briefing | The editorial decision for today: mode, capacity, one primary action, and limited support actions | One day | Start, adjust, give feedback |

Rules:

- A recommendation must not silently become a user-owned task or habit.
- Creating or scheduling anything on the user's behalf requires an explicit
  confirmation until a later automation policy is deliberately introduced.
- A primary briefing action must point to an executable target such as a task,
  habit, focus session setup, or a bounded planning action.
- Completing a focus session does not automatically complete its linked task or
  habit unless the user confirms that outcome.
- The same real-world action should not be duplicated across task, habit, and
  schedule collections merely to make it visible in multiple screens.

## Current Foundation

The repository already contains most of the foundation needed for this slice:

- Structured onboarding through Intake V1.
- Canonical Supabase tables for logs, events, tasks, goals, habits, schedule
  items, recommendations, and user state snapshots.
- Deterministic `daily` and `weekly` snapshot generation in FastAPI.
- Deterministic recommendation generation and persistence.
- Best-effort snapshot refresh after key Supabase-backed writes.
- A backend-only scheduled daily refresh endpoint for cron-style execution.
- Flutter dashboard, canonical lightweight daily check-in, habit management,
  recommendation refresh, insights, and mock/guest paths.

The gap is not broad AI integration. The gap is turning these primitives into a
coherent daily product loop:

```text
lightweight capture
  -> compact daily state
  -> ranked daily mode and next actions
  -> user feedback
  -> better decisions tomorrow
```

The Source And Surface Truth slice now establishes the product-integrity
boundary for these primitives:

- Explicit local demo sessions are persistently labeled and remain off real
  recommendation and snapshot APIs.
- Real recommendation, dashboard, Insights, and Notifications failures stay
  errors instead of becoming mock content.
- The dashboard renders direct stored check-in fields, tasks, and commitments;
  proxy score and metric-gallery placeholders are removed.
- Coach and Deep Work previews, fake Settings controls, and Supabase-only guest
  habit actions are gated.
- Notification actions come only from a validated implemented-route allowlist.

Phase 0C now closes the remaining product-integrity gap. First-run Setup stores
only explicit answers, keeps named routines as candidates until cadence is
confirmed, supports typed local/authenticated prefill and retry, and reconciles
reviewable Setup-owned commitments in one per-user-serialized database
transaction without touching manual rows. Mock/demo auth boot remains local
across reload, and save errors distinguish editable rejection, conflict/reload,
and ambiguous exact retry.

Phase 1 now supplies the missing daily context. A typed Evening Shutdown and a
separate short Morning Calibration merge by ownership into one local-date
`DailyCaptureEntry`, persist structured state under
`daily_logs.metadata.captures`, retain numeric compatibility, and rebuild at
most four deterministic current-state events. Guest V2 storage preserves the
same contract while reading legacy V1 entries, authenticated capture refreshes
the explicit local snapshot date, and Dashboard mapping remains direct and
nullable. Phase 1 deliberately does not assign Daily Mode, rank actions,
persist a briefing, generate recommendations on save, or call an LLM. The next
gap was Phase 2's explainable deterministic daily state.

Phase 2 now interprets that context inside backend-owned snapshots. Its
additive `explainable-daily-state-v1` contract uses strict V2 parsing, a fixed
seven-day state lookback independent of the statistics window, cadence-aware
Evening/Morning freshness, explicit `missing`/`partial`/`current`/`stale`
quality, and recovery-first `push`/`steady`/`recover`/`plan` classification.
Risks and reasons carry field-level evidence and deterministic provenance;
capture free text and learned-baseline claims stay out. It does not rank an
action, persist a briefing, change the Dashboard into Today, or call an LLM.
The next gap is Phase 3's executable task, habit, focus, and bounded planning
contracts.

### Current Surface Disposition

| Current surface | Keep | Change before relying on it |
| --- | --- | --- |
| Auth and guest entry | Yes | Local demo is labeled; mock/demo auth skips remote profile/data bootstrap and reloads local Setup, while canonical guest check-ins migrate best-effort only into a real non-demo account |
| Onboarding / Setup | Yes, Phase 0C complete | Progressive explicit input, typed prefill, atomic revision-safe save, differentiated retry/reload, and durable review are implemented |
| Dashboard | Yes | Direct source values are honest; evolve the sections into the decision-first Today surface after action contracts exist |
| Canonical daily capture | Yes, Phase 1 complete | Evening and Morning are separate typed flows over one ownership-merged daily entry; Phase 2 now interprets their freshness and stress context only inside backend snapshots |
| Legacy large Daily Check-In | Retired | `/daily-check-in` redirects to the canonical lightweight flow; do not recreate a competing form |
| Habit management/completion | Yes, authenticated only | Setup-owned habits are edited in Settings Setup and completed in Habit Completion; next correct cadence/progress, add skip/undo, and bring execution into Today |
| Insights correlations | Yes, as advanced exploration | Default to cautious actionable insight with evidence and confidence |
| Notifications | Read-only inbox | Structured internal actions are allowlisted; add preferences and durable read writes only with real contracts |
| Deep Work | Gated | Implement a real focus-session lifecycle before restoring the route |
| Coach | Gated | Restore only after a controlled authenticated backend exists |
| Settings | Honest minimum plus durable Setup | Read-only profile, Setup re-entry/review, session theme, and sign-out remain; add other controls only when durable |

## Guiding Principles

- Keep capture lightweight enough for daily use.
- Prefer correcting a prefilled summary over filling long forms.
- Use deterministic rules first so behavior is testable and explainable.
- Do not call an LLM on dashboard load.
- Do not require calendar import, wearables, or long journaling.
- Preserve mock and guest mode.
- Treat private or grief-related stress differently from ordinary workload.
- Keep the user's subjective control signal separate from raw stress intensity.
- Make feedback a first-class signal, not an afterthought.
- Never mix demo data into a real user's state without an explicit demo label.
- Never show a personalized score or recommendation without source, freshness,
  and sufficient input quality.
- Every visible primary control must work, persist correctly, and expose failure
  or rollback behavior.
- Prefer one useful action over a larger set of plausible suggestions.

## End-To-End User Operating Loop

This section is the product acceptance path. New work should be evaluated by
walking through it from the user's perspective, not only by verifying tables or
endpoints. It spans later phases and is not a claim that every listed output is
implemented today. Phase 1 ends at truthful Evening/Morning persistence and
snapshot refresh; Phase 2 adds backend snapshot Daily Mode, while ranked
actions and provisional/final briefings remain later phases.

### First Open

What the user does:

1. Chooses a real account or an explicitly labeled local demo/guest experience.
2. Sees what will be stored, what remains local, and that calendar/wearables are
   optional.
3. Completes a short progressive intake: current goal direction, main friction,
   typical day shape, energy window, and coaching preference.
4. Optionally names existing routines and fixed commitments.

What the app does:

- Stores only answers the user actually supplied; empty fields must not create
  invented goals, habits, or timetable blocks.
- Treats named existing habits as reviewable candidates before activating them.
- Creates an onboarding snapshot and conservative first recommendations from
  explicit answers only.
- Labels the first result as intake-based rather than implying learned history.
- Lands on a useful starting briefing or asks for one missing calibration signal;
  it does not land on an unexplained score or empty dashboard.

Target effort: under three minutes for the required path. Timetable detail,
additional habits, free text, and integrations remain progressive setup.

### First Useful Day

What the user does:

1. Gives current energy, sleep duration, and day shape in 10 to 20
   seconds.
2. Reviews today's mode, estimated capacity, primary action, reason, and at most
   two support actions.
3. Starts the primary action, replaces it, or marks it as inappropriate.

What the app does:

- Combines intake facts, open commitments, and morning calibration.
- Uses a conservative default mode when history is insufficient.
- Explains the strongest reason for the primary action in plain language.
- Makes the action executable with a direct command such as start focus, mark
  done, open task, log habit, or review priorities.
- Records acceptance or rejection without requiring another questionnaire.

### During The Day

What the user does:

- Completes, postpones, or cancels a task.
- Completes or intentionally skips a scheduled habit.
- Starts and stops a focus session linked to the current action.
- Uses a quick state check only when something materially changes.
- Selects `adjust today` when capacity or commitments change.

What the app does:

- Treats those existing actions as passive signals and avoids repeated forms.
- Refreshes the daily state best-effort after durable writes.
- Re-ranks only when the user asks, a material signal changes, or an explicit
  scheduling policy applies; normal reads do not generate.
- Preserves the user's current plan when backend refresh fails and clearly shows
  stale state instead of replacing it with demo data.

### Evening Shutdown

What the user does:

1. Confirms what was completed, postponed, or no longer relevant.
2. Reports mood, energy, stress intensity, stress source, controllability,
   friction, and a rough focus band.
3. Optionally chooses a likely priority and `make tomorrow gentler`.
4. Reviews a provisional tomorrow preview and closes the day.

What the app does:

- Saves the user's actual selections and never fixed example values.
- Updates the daily snapshot and prepares a provisional next-day state.
- Separates low-control/private stress from avoidable planning pressure.
- Carries unfinished work forward only with user confirmation or an explicit
  rollover preference.
- Does not punish an intentional recovery day with streak loss or aggressive
  productivity copy.

### Returning Morning

What the user does:

- Confirms or corrects the provisional plan with sleep, current energy, and day
  shape.

What the app does:

- Finalizes Daily Mode and capacity.
- Keeps the plan stable when the evening estimate still fits.
- Downgrades load when sleep, stress, or constraints changed.
- Shows what changed and why rather than silently replacing the plan.

### Weekly Review

This becomes useful only after the daily loop produces enough real outcomes.

What the user does:

- Reviews completed goal actions, carried tasks, habit opportunities, recovery
  days, and feedback on recommendations.
- Chooses which goal remains primary and which habit should stay, shrink, pause,
  or be replaced.

What the app does:

- Summarizes behavior without moralizing missed days.
- Separates scheduled opportunities, intentional skips, and uncompleted actions.
- Proposes at most one or two changes for the next week.
- Requires confirmation before changing habits, tasks, or schedule items.

### Recovery, Disruption, And Return After A Gap

When the user is ill, grieving, traveling, overloaded, or returning after missed
days, the app must not create a backlog of guilt.

- `recover` mode suspends stretch recommendations and highlights minimum viable
  commitments.
- The user can pause today, skip a habit intentionally, or reduce an action.
- Returning after a gap starts with current state and relevant open commitments,
  not a forced reconstruction of every missed day.
- Stale snapshots and briefings are labeled and refreshed deliberately.

## Progressive Product Intelligence

The app should become more capable as evidence accumulates. It must not imply a
learned baseline before one exists.

| Stage | Available evidence | What the app may do | What it must not claim |
| --- | --- | --- | --- |
| Start | Intake and current calibration | Intake-based recommendations, conservative Daily Mode, one explicit next action | Personal baseline, trend, correlation, optimized score |
| First week | Several check-ins and action outcomes | Recency-based adjustments, scheduled habit progress, simple workload and recovery flags | Stable long-term pattern or causal insight |
| Two-plus weeks | Repeated comparable signals | Emerging patterns with visible sample size and low/medium confidence | Medical conclusion or certainty from correlation |
| One-plus month | Daily and weekly outcomes plus feedback | Personal baselines, weekly adaptation, stronger ranking, habit change proposals | Unreviewed autonomous schedule or goal changes |
| Integration stage | Calendar or wearable data with consent | Lower-friction capture, better capacity estimates, conflict-aware proposals | Hidden provider writes or opaque data use |
| Coach stage | Stable snapshots, feedback, controlled memory | Explain, compare, answer follow-ups, stage bounded changes for approval | Acting as a doctor, therapist, or unrestricted autonomous agent |

Every briefing, recommendation, insight, and coach answer should expose or carry:

- `generated_at` and relevant date/period.
- Source kind such as explicit input, deterministic rule, integration, or model.
- Evidence references or a user-readable reason.
- Freshness/staleness state.
- Data-quality or confidence state when pattern claims are involved.
- Demo/mock provenance when applicable.

## Data Capture Cadence

The strongest capture rhythm is evening-first with a short morning calibration.

### Evening Shutdown

Goal: close the day while context is fresh, then produce a rough preview for
tomorrow.

Reasoning:

- The user can accurately report stress, mood, friction, focus, task reality,
  and unfinished work after living the day.
- Evening capture can prepare tomorrow without forcing a planning session in the
  morning.
- It gives the backend time to generate the next daily state before the user
  opens the app again.

Target effort: 60 to 90 seconds.

Required fields:

- Energy level.
- Stress intensity.
- Stress source.
- Stress controllability.
- Mood.
- Focus minutes or rough focus band.
- Main friction point.
- One likely priority for tomorrow.

Optional fields:

- Reflection note.
- "Make tomorrow gentler" preference.
- Specific blocker.

Current Phase 1 output:

- Persisted current-state context and the user's explicit likely priority.
- No provisional plan is generated. For authenticated real accounts, Phase 2
  now classifies an explainable backend Daily State best-effort after the
  write; the capture surface does not present that state as a briefing.

### Morning Calibration

Current goal: record sleep, current energy, and day shape without repeating the
Evening form. Adjusting a provisional plan begins only after explainable state
and briefing generation exist.

Reasoning:

- Sleep and current readiness are not known at evening shutdown.
- Morning capture must be short or it becomes a source of friction.
- This is where the app should finalize the daily mode.

Target effort: 10 to 20 seconds.

Required fields:

- Sleep hours in half-hour steps.
- Current energy.
- Day shape: normal, constrained, or flexible.

Current Phase 2 output for authenticated real accounts:

- Refreshed explainable backend Daily State and Daily Mode, best-effort.
- No ranked top action, capacity estimate, or plan mutation.

Target output after later briefing work:

- Ranked top action.
- Adjusted capacity estimate.

### During The Day

Goal: collect signals passively through actions the user already takes.

Reasoning:

- Midday forms are easy to ignore.
- Task updates, habit completions, focus sessions, quick state check-ins, and
  recommendation feedback are more reliable than repeated questionnaires.

Signals:

- Task completed, postponed, or ignored.
- Habit completed or skipped.
- Focus session started and ended.
- Quick mood check-in.
- Recommendation accepted, completed, dismissed, or marked as too much.
- Manual "adjust plan" action.

## Stress Taxonomy

Stress must be represented as more than one number. The app needs three
separate dimensions:

### Stress Intensity

How strong the stress felt.

Suggested UI:

```text
low / medium / high
```

The existing numeric `stress_level` can remain as the backend-compatible value.
The UI may map low, medium, and high to numeric bands.

### Stress Source

Why the stress happened.

Suggested categories:

| Source | Meaning | Product response |
| --- | --- | --- |
| workload | Too much work, meetings, deadlines, responsibility | Prioritize, reduce scope, protect focus |
| avoidable_pressure | Procrastination, late start, unclear next action, planning debt | Lower start friction, create earlier starts, reduce ambiguity |
| private_emotional | Conflict, family, grief, worry, relationship, personal event | Lower load, compassionate planning, avoid productivity pressure |
| physical_recovery | Poor sleep, illness, pain, exhaustion | Recovery mode, minimum viable commitments |
| external_environment | Travel, noise, interruptions, external constraints | Adapt schedule, reduce dependency on perfect conditions |

Reasoning:

- Workload stress and grief should not produce the same recommendation.
- Avoidable pressure is useful only if handled without blame.
- Physical recovery stress should often change the daily mode, not only produce
  another task.

### Stress Controllability

How much the user could influence the stress.

Suggested UI:

```text
hardly controllable / partly controllable / mostly controllable
```

Reasoning:

- Low controllability should shift the system toward support, simplification,
  and recovery.
- High controllability can produce planning, start-friction, or habit-design
  recommendations.
- This dimension prevents the app from moralizing unavoidable life events.

## Daily Mode

The daily briefing should assign one of four modes:

| Mode | When | Product behavior |
| --- | --- | --- |
| push | Good energy, manageable stress, clear high-value action | Protect focus and advance an important goal |
| steady | Normal capacity, no major risk flag | Keep a realistic plan and one meaningful next step |
| recover | Low energy, poor sleep, high private/emotional or physical stress | Reduce load and preserve minimum commitments |
| plan | Overdue tasks, avoidable pressure, unclear priorities, too much open work | Sort, choose, and reduce ambiguity before execution |

Reasoning:

- A mode gives the user a simple mental model for the day.
- It also constrains recommendation generation. Recovery days should not surface
  aggressive productivity advice.
- The mode should be explainable from snapshot signals and recent feedback.

## Habit Product Contract

Habits are useful only when they reduce decision friction and support a real
goal or recovery need. They should not become a second task list or a source of
streak pressure.

### Habit V1 Scope

The first coherent habit version should support binary completion with flexible
cadence:

- `daily` or specific weekdays.
- `x times per week` with a weekly target.
- Optional linked goal.
- Optional minimum version, for example `walk for 10 minutes`.
- Optional preferred execution window.
- Active, paused, and archived lifecycle.
- Daily outcome: completed, intentionally skipped, or still open.
- Undo for an accidental completion or skip.

Do not expose quantity targets such as glasses, pages, repetitions, or minutes
until `habit_logs` and progress calculations support them end to end. The current
single-row-per-habit/day shape is sufficient for binary V1, not arbitrary
multi-completion tracking.

### Progress And Streak Rules

- Daily/scheduled habits use completed opportunities divided by elapsed scheduled
  opportunities, not completed days divided by seven.
- Weekly habits show current-week progress as `completed / weekly target`.
- A weekly streak advances only when the weekly target is reached.
- An intentional skip is distinct from completion and failure.
- Recover mode or an explicit day pause may exclude a scheduled opportunity from
  streak pressure; it must never fabricate a completion.
- Overall adherence and recent direction are more important than an unbroken
  streak. Streaks should be optional secondary motivation.

### Habit Placement In The Experience

- Onboarding may collect existing routines, but the user confirms cadence before
  they become active habits.
- The Today surface shows only habits scheduled or deliberately selected for
  today.
- Habit management remains available for setup, but daily completion happens in
  the same Today flow as tasks and recommendations.
- A habit can become the primary action only when it is goal-relevant,
  time-appropriate, and compatible with Daily Mode.
- The weekly review proposes keeping, shrinking, pausing, or replacing a habit
  based on adherence and feedback; changes require confirmation.
- Start with one to three important habits. Do not encourage users to activate a
  large routine inventory during onboarding.

### Habit Data Direction

Use existing `habits.metadata` for early cadence details while the contract is
validated, for example:

```json
{
  "scheduled_weekdays": [1, 3, 5],
  "minimum_version": "Walk for 10 minutes",
  "preferred_window": "afternoon",
  "linked_goal_id": "uuid-or-null",
  "streak_enabled": true
}
```

Before supporting intentional skip in production, add an explicit log outcome
through a dedicated `status` column or another structured representation. Do
not overload an undocumented `habit_logs.value` sentinel. Any schema change must
include migration, RLS/grants verification, Supabase docs, repository tests, and
browser E2E coverage.

## Cross-Cutting Trust And Attention Contract

These rules apply to every phase because life, stress, and behavior data is
sensitive and daily capture is easy to abandon after one bad interaction.

### Capture Reliability

- A failed or timed-out write must keep the user's draft and offer a clear retry.
- Retry must be idempotent or deduplicated so one check-in does not become two
  daily records.
- The UI must not show a saved state until the durable guest or Supabase write
  has succeeded.
- If full offline sync is not implemented, say that a draft is pending locally;
  do not imply server persistence.
- A successful save should immediately affect the next relevant state or screen
  so the user can see that their input mattered.

### Notifications And Attention

- Start with explicit user-selected check-in and commitment reminders.
- Add a morning briefing-ready notification only after persisted briefings and
  scheduled preparation are reliable.
- Route each notification to the exact capture, task, habit, or briefing action;
  never to a generic dashboard with no obvious next step.
- Respect timezone, quiet hours, per-category opt-in, snooze, and a conservative
  daily frequency cap.
- Do not use streak-loss pressure or send another reminder after the user paused
  the day, intentionally skipped, or entered recover mode.
- Keep private stress, health, relationship, and free-text detail out of lock
  screen copy.
- Never send real notifications from demo state or silently enable a new category.

### Data And Automation Control

- Settings that claim export, delete, privacy, security, memory, or reminder
  behavior must be durable and verifiable before they are enabled.
- Account deletion and usable data export are production trust requirements, not
  decorative Settings rows.
- Users must be able to identify imported data and later disconnect and delete it.
- Any system-proposed task, habit, schedule, or memory change remains staged for
  review until an explicit automation policy is introduced and revocable.

## Required Backend Product Capability

### Daily Briefing Service

Add a FastAPI-owned service that turns snapshots and recommendations into one
ranked daily briefing.

The briefing should use a typed action contract rather than display-only labels:

```text
DailyAction
- id: stable action id within the briefing
- kind: task | habit | focus | planning | recovery
- title: user-visible action
- command: open_task | complete_task | log_habit | start_focus | review_plan |
  open_capture
- target_id: nullable id of the linked task, habit, recommendation, or focus setup
- estimated_minutes: nullable positive integer
- reason: one concise evidence-backed explanation
- recommendation_id: nullable source recommendation
- metadata: bounded structured command context
```

The Flutter layer should map supported `command` values to real handlers. An
unknown or unavailable command is an explicit unsupported/error state, never an
enabled no-op button.

Suggested endpoints:

```text
GET /v1/briefings/today
POST /v1/briefings/generate
```

`GET` reads the current briefing and reports whether generation is needed.
`POST` deliberately generates or refreshes the briefing.

Reasoning:

- Recommendations are individual candidates. A briefing is an editorial decision
  about today's mode, capacity, and top actions.
- Keeping this behind FastAPI allows service-role reads, cross-table reasoning,
  future scheduled jobs, and optional LLM wording later.

### Persistence

Add a dedicated table when the first backend briefing slice is implemented:

```text
daily_briefings
- id uuid primary key
- user_id uuid references profiles(id)
- briefing_date date
- mode text
- readiness_score numeric null
- capacity_minutes int null
- summary text
- primary_action jsonb
- support_actions jsonb
- recommendation_ids uuid[]
- evidence_refs jsonb
- provenance jsonb
- data_quality text
- metadata jsonb
- generated_at timestamptz
- updated_at timestamptz
- unique (user_id, briefing_date)
```

Reasoning:

- A briefing has identity beyond a list of recommendations.
- The app should be able to show the morning briefing immediately.
- A persisted row makes scheduled refresh, E2E assertions, debugging, and stale
  detection straightforward.
- `readiness_score` remains null until a validated baseline policy exists. Daily
  Mode and plain-language capacity can work without false numeric precision.

### Ranking

Create a deterministic ranking layer for candidate recommendations.

Inputs:

- Current daily snapshot.
- Latest onboarding and weekly snapshots.
- Open tasks.
- Active goals.
- Habit gaps.
- Recent stress source and controllability.
- Existing recommendation status and feedback.

Candidate score dimensions:

- Goal relevance.
- Urgency.
- Energy fit.
- Available time fit.
- Recovery risk.
- Habit consistency gap.
- User feedback fit.
- Evidence recency.

Reasoning:

- The product promise requires choosing, not listing.
- Ranking should be explainable and testable before LLM usage is introduced.

## Required Frontend Product Capability

### Product Integrity Gate

Before adding more prominent surfaces:

- Hide production navigation to no-op or canned-response features behind feature
  flags until they work end to end.
- Remove non-functional Quick Action entries or expose them only in an explicitly
  labeled design/demo mode.
- Keep both current routes on the implemented typed lightweight capture flow; do
  not reintroduce a fixed or competing Daily Check-In form.
- Show real-backend empty, stale, and error states instead of silently substituting
  personalized-looking mock data.
- Show only directly measured or honestly named derived metrics. Do not label a
  proxy as mood, sleep, steps, hydration, or screen time.
- Persist settings that claim to affect reminders, privacy, memory, profile, or
  security; otherwise omit or disable the control.
- Make destructive and optimistic actions recoverable through confirmation,
  rollback, or undo.

Mock and guest exploration can remain rich, but the whole session must be
recognizable as local/demo data and guest writes should affect subsequent guest
screens where the user expects feedback.

### Evening Shutdown Flow

The implemented Evening Shutdown quick action supports:

- Required energy, mood, stress intensity, stress source, stress
  controllability, focus band, main friction, and a short tomorrow priority.
- Optional reflection, specific blocker, and gentle-tomorrow intent; blank or
  false optionals are omitted rather than replaced with fallback content.
- Prefill and same-kind replacement without erasing a saved Morning
  Calibration.
- Capture copy that does not claim a learned baseline, ranked plan, diagnosis,
  or causation. An authenticated real save may refresh the separate Phase 2
  backend Daily State best-effort.

Reasoning:

- This is the main daily data capture moment.
- It should feel like confirming reality, not filling a form.
- A provisional tomorrow plan remains a later briefing concern; Phase 1 stores
  the explicit priority and context but does not rank or generate actions.

### Morning Calibration Flow

The implemented short Morning Calibration surface supports:

- Required sleep hours in half-hour steps, current energy, and day shape.
- Prefill and same-kind replacement without erasing saved Evening context.
- Honest current-state copy stating that capture does not generate
  recommendations or create or change a plan. Authenticated real saves may
  refresh the separate backend Daily State; guest/mock saves remain local.

Reasoning:

- Morning readiness can invalidate the evening plan.
- The user should never need to re-plan the whole day from scratch.
- Daily Mode now exists in Phase 2 backend snapshots; top-action selection
  begins only after executable Phase 3 targets and later briefing ranking exist.

### Dashboard Repositioning

Shift the dashboard top area from metric-first to decision-first.

Top screen should show:

- Today's mode.
- One primary action.
- One reason.
- One capacity or risk note.
- Secondary actions only after the primary action.

Reasoning:

- The highest-value moment is the first screen of the day.
- Too many cards dilute the product's decision-making value.

### Unified Today Execution

The dashboard should present one ordered Today plan rather than separate product
silos.

Must support:

- Start or open the primary action.
- Complete, postpone, replace, or mark the action as too much/not fitting.
- Show fixed commitments that constrain capacity.
- Show only today's relevant tasks and habits.
- Start a working focus session linked to a chosen action.
- Undo task and habit outcomes where practical.
- Trigger an explicit `adjust today` flow after a material state change.

The user should not have to visit separate management and completion pages for
ordinary daily execution. Dedicated setup/history pages may still exist.

### Recommendation Feedback

Every primary recommendation should support feedback:

- Done.
- Later.
- Not helpful.
- Too much today.
- Does not fit.

Reasoning:

- Feedback is how the app learns without requiring a long survey.
- It is also necessary to avoid repeating annoying or poorly timed advice.

### Insights Progression

- Default Insights should show one understandable observation, its evidence
  window, confidence/data-quality state, and one optional experiment.
- Correlation matrices, scatter plots, and multi-signal overlays are advanced
  exploration, not the primary coaching surface.
- Do not describe a relationship as causal.
- Do not rank many weak pairwise correlations into impressive-looking patterns
  without sufficient data and a confidence policy.

### Coach And Automation Gate

- Do not present canned responses as personalized AI coaching.
- Coach becomes production-visible only when it can use current snapshots,
  selected memories, and evidence-backed recommendations.
- Users must be able to view, correct, and delete coach memory.
- Any coach-proposed task, habit, or schedule change is staged for review before
  it is persisted.
- Health and stress guidance remains informational and must not claim diagnosis
  or treatment.

## Data Model Changes

Phase 1 reuses existing tables. It stores the two owned capture objects in
`daily_logs.metadata.captures` and mirrors event-relevant fields into
`behavioral_events.metadata`.

Implemented metadata shape, abbreviated:

```json
{
  "capture_version": "daily-capture-v2",
  "captures": {
    "evening": {
      "capture_kind": "evening",
      "entry_date": "2026-07-10",
      "stress_intensity": 9,
      "stress_intensity_label": "high",
      "stress_source": "private_emotional",
      "stress_controllability": "hardly_controllable",
      "focus_band": "30_to_60_minutes",
      "main_friction": "emotional_load",
      "tomorrow_priority": "Keep the morning light"
    },
    "morning": {
      "capture_kind": "morning",
      "entry_date": "2026-07-10",
      "sleep_hours": 5.5,
      "current_energy": 3,
      "day_shape": "constrained"
    }
  }
}
```

Reasoning:

- This avoids premature schema churn while validating the product model.
- `daily_logs.stress_level` remains available for existing analytics.
- Morning energy takes precedence in `energy_level`; Evening owns mood and
  stress, Morning owns sleep, and absent fields stay null rather than becoming
  invented values.
- Events are a dynamic maximum of four deterministic current-state rows, not an
  append-only history of repeated same-day retries.

Phase 2 also reuses the existing `user_state_snapshots` JSONB columns. Its
abbreviated persisted shape is:

```json
{
  "summary": {
    "daily_state": {
      "contract_version": "explainable-daily-state-v1",
      "target_date": "2026-07-11",
      "mode": "recover",
      "data_quality": "current",
      "freshness": {
        "evening": {"state": "current", "age_days": 1},
        "morning": {"state": "current", "age_days": 0}
      },
      "risk_flags": ["private_emotional_stress", "low_sleep"],
      "reason_codes": ["recover_private_emotional_stress"],
      "provenance": {
        "kind": "deterministic",
        "basis": "explicit_capture",
        "baseline": "none"
      }
    },
    "risk_flags": ["private_emotional_stress", "low_sleep"],
    "window_risk_flags": []
  },
  "signals": {
    "daily_state": {
      "contract_version": "explainable-daily-state-v1",
      "risk_evidence": {
        "private_emotional_stress": [{
          "table": "daily_logs",
          "id": "daily-log-id",
          "field": "metadata.captures.evening.stress_source"
        }]
      },
      "reason_evidence": {
        "recover_private_emotional_stress": [{
          "table": "daily_logs",
          "id": "daily-log-id",
          "field": "metadata.captures.evening.stress_source"
        }]
      },
      "quality_issues": []
    }
  },
  "metadata": {
    "source": "snapshot-aggregator-v1",
    "daily_state_contract_version": "explainable-daily-state-v1",
    "state_lookback_days": 7,
    "window_days": 7
  }
}
```

The state lookback stays fixed at seven days even when `window_days` changes.
Top-level `summary.risk_flags` is a compatibility alias for current Daily State
risks; statistics-window risks remain separate in `summary.window_risk_flags`.
No capture free text appears in this snapshot contract.

Add dedicated columns later only if the fields become stable and heavily
queried:

- `stress_source`
- `stress_controllability`
- `stress_intensity_label`

Use the current recommendation `status` for the smallest interaction slice. Add
an append-only feedback table only when ranking needs outcome history across
briefings and action types.

Suggested future table:

```text
decision_feedback
- id uuid primary key
- user_id uuid references profiles(id)
- briefing_id uuid null references daily_briefings(id)
- recommendation_id uuid null references recommendations(id)
- action_id text null
- action_kind text null
- feedback_type text  # done | later | not_helpful | too_much | does_not_fit
- metadata jsonb
- created_at timestamptz
```

The backend must validate that referenced briefing/recommendation rows belong to
the authenticated user. Feedback is historical evidence and should not mutate or
erase the original recommendation reason.

## Implementation Phases

Each phase must deliver a coherent user-visible behavior. Do not declare a phase
complete because a table, endpoint, or screen exists in isolation.

### Phase 0: Product Integrity And Contracts

Goal:

- Ensure visible behavior is real and define the contracts later phases depend
  on.

Execute Phase 0 as three independently verifiable slices:

- **0A Honest Capture (complete):** exact user-controlled values, reliable
  persistence, and value-level tests.
- **0B Source And Surface Truth (complete):** explicit demo, empty, stale, and
  error states; no proxy metrics or enabled no-op features.
- **0C First-Run And Setup Integrity (complete):** progressive, editable,
  revision-safe setup without invented or duplicate commitments.

Work:

- Inventory production-visible routes, controls, metrics, settings, and fallback
  paths as functional, demo-only, or incomplete.
- Hide incomplete production features behind explicit feature flags.
- Maintain the completed canonical typed capture flow and its route
  consolidation while other product-integrity work proceeds.
- Preserve the draft after failed writes and make retry idempotent or
  deduplicated.
- Remove silent real-user fallback to personalized-looking mock recommendations.
- Remove or honestly rename proxy dashboard metrics.
- Fix task outcome initialization, failure rollback, and undo behavior before the
  Today plan depends on it.
- Keep Setup re-entry prefilled and idempotent. Blank answers create no fallback
  records, and named routines remain candidates until cadence is confirmed.
- Keep Setup-created goals, cadence-confirmed habits, and fixed commitments
  reviewable, editable, pausable/archivable, and removable before Daily Mode uses
  them; atomic reconciliation must continue to preserve manual rows. Keep
  Setup-owned habit editing in Settings Setup while allowing active completion.
- Define mock/guest behavior separately from real-backend empty/error behavior.

Evaluation:

- Does every visible production control work and persist as its label promises?
- Can a real account distinguish fresh, stale, empty, failed, and demo data?
- Does saving a check-in persist exactly what the user selected?
- Does a failed save preserve the draft, and can retry complete without a
  duplicate daily record?
- Do widget and browser tests verify values and outcomes, not only navigation?
- Can the user revisit setup without duplicate goals, habits, or commitments?
- Can a developer explain the object and action contracts without reading UI
  implementation details?

### Phase 1: Lightweight Evening And Morning Capture (Complete)

Goal:

- Capture the minimum signals needed for good daily decisions with low friction.

Implemented:

- Separate typed Evening Shutdown and Morning Calibration flows with retained
  drafts, prefill, recoverable save errors, and stable retry identity.
- Same-day merge ownership: a submitted capture replaces only its own
  `metadata.captures` object and preserves the other kind.
- Numeric projection keeps Morning energy over Evening energy, Evening mood and
  stress, Morning sleep, and nullable unmeasured focus minutes.
- Supabase replaces the linked source-owned event set with a dynamic maximum of
  four deterministic mood/energy/stress/sleep ids and mirrored bounded metadata.
- Guest storage writes V2 daily JSON, reads V1 JSON, changes later guest reads,
  and retains the existing best-effort migration into a real non-demo account.
- Authenticated writes refresh the exact local `target_date`; backend event
  filtering prefers `metadata.entry_date` after a broadened UTC read and falls
  back to the timestamp for legacy rows.
- Dashboard reads direct nullable numeric and structured capture values. No
  Daily Mode, action ranking, recommendation generation, or LLM was added.

Evaluation:

- Can Evening Shutdown complete in under 90 seconds?
- Can Morning Calibration complete in under 20 seconds?
- Are private/emotional and low-control stress captured distinctly?
- Can the user skip optional detail without invented fallback values?
- Are guest/mock and Supabase-backed writes covered?

### Phase 2: Explainable Daily State (Complete)

Goal:

- Make snapshots represent current state and explain a conservative Daily Mode.

Implemented:

- Added `summary.daily_state` and `signals.daily_state` under
  `explainable-daily-state-v1` without changing schema or capture ownership.
- Added strict V2 parsing for capture identity, types, enums, bounded numbers,
  timestamps, and numeric projections. Legacy numeric fallback is accepted only
  when no V2 marker exists; malformed V2 does not regain trust through columns.
- Added a fixed seven-day state lookback independent of the requested
  statistics window. Evening is current from the target date or previous date;
  Morning only from the target date.
- Added `missing`, `partial`, `current`, and `stale` quality plus bounded stress,
  recovery, workload, planning, capacity, and calibration risk flags.
- Added deterministic, recovery-first `push`, `steady`, `recover`, and `plan`
  classification with machine-stable reasons, user-readable non-clinical copy,
  field-level evidence, provenance, and no learned-baseline claim.
- Excluded tomorrow-priority, reflection, and blocker text from snapshot
  summary, signals, evidence, quality issues, and metadata.
- Preserved same-period upsert identity, `snapshot-aggregator-v1`, guest/mock
  locality, best-effort refresh, recommendation ranking, and no-LLM behavior.
  Snapshot metadata records the contract/lookback; top-level
  `summary.risk_flags` aliases current Daily State risks,
  `summary.window_risk_flags` retains window risks, and
  `recommended_next_focus` is recovery-first from mode.

Evaluation:

- Do tests cover every mode, insufficient data, stale capture, and conflicting
  signals?
- Does the snapshot explain the strongest reasons for its mode?
- Does high private/emotional stress reliably reduce load?
- Can state be recomputed idempotently for the same user and period?

### Phase 3: Executable Tasks, Habits, And Focus (Next)

Goal:

- Give a future briefing reliable actions it can point to.

Work:

- Add coherent task create/edit/complete/postpone/cancel behavior with estimates
  where capacity planning needs them.
- Implement Habit V1 cadence, correct daily/weekly progress, intentional skip,
  pause, and undo according to the Habit Product Contract.
- Add any required habit-log outcome migration with RLS, repository, and E2E
  coverage.
- Make daily habit completion available from a Today-oriented surface, not only a
  separate management flow.
- Implement a real focus-session lifecycle linked to an action, or keep the focus
  preview out of production navigation.
- Define action targets and commands that a briefing can invoke without no-op
  buttons.

Evaluation:

- Is every action target directly startable or openable?
- Does a weekly habit report `completed / target` correctly?
- Are scheduled opportunities, skips, misses, and completions distinct?
- Can accidental task/habit outcomes be undone?
- Do failed writes rollback optimistic UI or show a recoverable error?

### Phase 4: Deterministic Briefing Service

Goal:

- Produce one daily editorial decision from state and executable candidates.

Work:

- Add `daily_briefings` persistence if needed for morning availability, stale
  detection, scheduling, and E2E assertions.
- Add repository, models, and authenticated `GET /v1/briefings/today` plus
  deliberate `POST /v1/briefings/generate` routes.
- Refresh or validate daily state before generation.
- Rank one primary action and at most two support actions by goal relevance,
  urgency, energy fit, time fit, recovery risk, feedback, and evidence recency.
- Include mode, capacity, reason, provenance, evidence refs, freshness, and action
  targets.
- Keep LLM wording disabled.

Evaluation:

- Does `GET` remain read-only and report stale/missing state?
- Does `POST` derive user identity from the bearer principal?
- Does every returned action point to a real executable target?
- Does insufficient data yield a conservative useful briefing?
- Can browser E2E assert the briefing after capture and state refresh?

### Phase 5: Decision-First Today Dashboard

Goal:

- Make the first screen the daily operating cockpit.

Work:

- Show Daily Mode, primary action, reason, time/capacity note, and freshness above
  secondary metrics.
- Add start, done, later, replace, too much, and does-not-fit controls.
- Show fixed commitments and only today's relevant tasks and habits.
- Add `adjust today` for material state or schedule changes.
- Keep advanced metrics and history below the execution surface.
- Preserve deliberate refresh without generating on normal dashboard reads.

Evaluation:

- Does the first viewport answer what to do now and why?
- Can the user begin the primary action in at most two interactions?
- Are no more than three decision items emphasized?
- Does feedback work without another long form?
- Does mobile and desktop layout preserve readable, non-overlapping actions?

### Phase 6: Feedback And Useful Insights

Goal:

- Learn from outcomes and turn patterns into cautious experiments.

Work:

- Persist recommendation and briefing feedback history.
- Use recent feedback in ranking without erasing original evidence.
- Deprioritize advice repeatedly marked not helpful, too much, or irrelevant.
- Replace the default analytics-heavy Insights entry with one observation,
  evidence window, confidence/data-quality label, and optional experiment.
- Keep matrix, scatter, and multi-signal exploration in an advanced view.

Evaluation:

- Does repeated feedback change future ranking deterministically?
- Are pattern claims labeled emerging or stronger according to available data?
- Does every default insight suggest a bounded user choice rather than claim
  causation?

### Phase 7: Scheduled Daily Preparation

Goal:

- Make the app prepared when the user opens it without hiding generation.

Work:

- Wire deployed cron/job execution to the existing scheduled refresh foundation.
- Generate daily snapshots and persisted briefings for onboarded non-guest
  profiles.
- Define refresh policy for Evening Shutdown, Morning Calibration, material
  daytime changes, and stale periods.
- Isolate failures per user and keep all scheduled generation deterministic.
- Respect each user's timezone when selecting the briefing date.
- Add only opt-in briefing-ready or explicit check-in reminders, with quiet
  hours, snooze, frequency caps, and deep links to the exact action.
- Keep sensitive state out of notification copy and suppress pressure-oriented
  reminders in recover or paused-day state.

Evaluation:

- Is a fresh morning briefing normally available without manual refresh?
- Are stale or failed briefings visibly distinguishable?
- Are retries idempotent and free of LLM calls?
- Do notifications arrive in the correct local window, open the intended action,
  and remain silent for disabled categories, demo state, and quiet hours?

### Phase 8: Weekly Review And Habit Adaptation

Goal:

- Help the user improve the system instead of merely accumulate history.

Work:

- Summarize goal actions, task rollover, scheduled habit opportunities, recovery
  days, and recommendation feedback.
- Propose at most one or two plan or habit adaptations.
- Let users keep, shrink, pause, replace, or archive habits and goals.
- Require confirmation before applying changes.

Evaluation:

- Can the user finish the review in a few minutes?
- Are skips and recovery days treated differently from unaddressed commitments?
- Do confirmed changes improve the following week's briefing inputs?

### Phase 9: Optional Integrations

Goal:

- Reduce manual capture after the standalone loop has proven useful.

Work:

- Add calendar read/import first with clear source and disconnect/delete controls.
- Stage proposed time blocks before any provider write.
- Add wearable or platform health signals only with explicit consent and clear
  provenance.
- Reconcile duplicates instead of creating parallel schedule or activity rows.

Evaluation:

- Does the app remain fully usable without an integration?
- Can users see, disconnect, and delete imported data?
- Do integrations reduce capture effort without making recommendations opaque?

### Phase 10: Controlled Coach

Goal:

- Add conversational explanation and adaptation after the deterministic product
  loop works.

Work:

- Add authenticated coach response service with budget and feature flags.
- Build context from compact snapshots, current briefing, selected memories, and
  a bounded message window.
- Let users view, edit, and delete memory used for coaching.
- Stage task, habit, or schedule proposals for explicit review.
- Add wellness/medical boundaries and source-aware responses.

Evaluation:

- Does Coach answer from actual current state and disclose uncertainty?
- Can the user inspect and control memory?
- Are all state-changing suggestions reviewed before persistence?
- Does Coach add value beyond the existing briefing instead of restating it?

## Evaluation Checklist For Next Work

Before implementing a proposed slice, answer:

- Which exact moment in the End-To-End User Operating Loop improves?
- Is every visible control in scope functional, durable, and recoverable?
- Is the source real, demo, derived, integrated, or model-generated, and can the
  user tell?
- Does the behavior work with insufficient or stale data?
- Are Goal, Task, Habit, Focus, Recommendation, and Briefing semantics preserved?
- Does this reduce or preserve capture friction?
- Can it work without an LLM, calendar, or wearable?
- Does it preserve a clearly labeled guest/demo experience?
- Does it distinguish private/emotional stress from workload stress?
- Does low-control stress lower load instead of increasing pressure?
- Does recover mode avoid streak punishment and stretch recommendations?
- Can output be explained with evidence and freshness?
- Are optimistic and destructive actions reversible or recoverable?
- Can widget, backend, and browser E2E tests prove the user outcome?
- If schema changes, are migration, RLS/grants, docs, and local verification
  included?

## Product Success Measures

Use these to evaluate product slices; raw screen count, notification opens, and
streak length are not sufficient success measures.

- Time from first open to first useful briefing.
- Morning Calibration completion time and completion rate.
- Evening Shutdown completion time and completion rate.
- Percentage of briefings with a started, completed, deferred, or explicitly
  rejected primary action.
- Helpfulness and `too much` rates by Daily Mode and recommendation type.
- Percentage of outputs with valid provenance, freshness, and evidence.
- Seven-day and thirty-day return rate after receiving a useful briefing.
- Habit adherence across scheduled opportunities, including intentional skips,
  rather than raw unbroken streaks.

## Current Recommendation

**Phase 0A, Phase 0B, Phase 0C, Phase 1, and Phase 2 are complete.** Real and
demo source states remain distinct; Setup is revision-safe and atomically
reconciled; Evening/Morning provide exact ownership-merged context; and the
backend now turns trusted current capture state into freshness, quality,
recovery-first Daily Mode, bounded risks/reasons, evidence, and provenance.
Malformed V2 never becomes trusted legacy input, free text remains excluded,
and same-period refresh converges without duplicate snapshots. Phase 2 does not
rank actions, persist a briefing, expose a Today UI, generate recommendations,
or call an LLM.

The next implementation should be **Phase 3: Executable Tasks, Habits, And
Focus**:

1. Define stable action targets and commands for tasks, habits, focus sessions,
   and bounded planning before any briefing ranks them.
2. Complete task create/edit/complete/postpone/cancel and recoverable outcome
   behavior where the Today loop needs it.
3. Implement honest Habit V1 cadence, scheduled opportunities, intentional
   skip, progress, streak, and undo semantics; add schema only if an explicit
   outcome cannot be represented safely otherwise.
4. Implement a real focus-session lifecycle linked to an action, or keep the
   preview gated.

Phase 3 must preserve the Phase 2 Daily State contract and still must not add
briefing ranking, `daily_briefings`, the decision-first Today dashboard, Coach,
calendar import, or an LLM.
