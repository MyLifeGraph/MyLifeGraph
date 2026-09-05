# Daily Briefing Implementation Plan

Coach V4 does not change Daily Briefing authority: provider tools may read
the authenticated owner's bounded projection, but no provider may create
or mutate briefings, recommendations, feedback, or any other product record.
The current Coach projection boundary is `coach-response-v4` with
`free-coach-agent-prompt-v5`.

Status: historical phase plan with a current product-disposition summary,
updated through Planner V1, Today Overview V2, Study Setup V1, and the Setup
personalization retirement, Daily Capture V4, and Exam-Week Outlook V1 on
2026-07-26, the shared Flutter profile-local date boundary on 2026-07-31, and
Daily Capture V5/Daily State V3 on 2026-08-04 and the generic Recommendation /
Decision Feedback retirement on 2026-08-14.
Detailed phase sections preserve their original implementation reasoning;
current surface authority lives in the linked contracts.

Current disposition overrides the historical phase text below: the generic
Today Recommendation feed, Recommendation refresh, and Decision Feedback are
retired end to end. `daily-briefing-v2` ranks without those sources,
`weekly-review-v3` has no Feedback facts, and Account Export is V5. Current
Coach turns use `free-coach-agent-prompt-v5` with
`personal-snapshot-v3`; persisted V4-prompt turns remain replay-compatible.
Sleep Recommendation, `ai_insights.recommendation`, recommendation Memories,
Skillset, and ordinary Coach advice remain distinct supported concepts.

`docs/setup-personalization-retirement-contract.md` is authoritative wherever
historical sections below mention Goals as an active product object, Setup
focus/friction/style/Reminder/context questions, Capture V2/V3 as the current
output, or Daily State V1 output. `docs/exam-week-outlook-v1-contract.md` is
authoritative for current Capture V5 sleep fields and the Planner outlook.

This document turns the product idea of a daily decision cockpit into an
implementation plan. It is intentionally evaluation-oriented: each phase states
the product goal, the reasoning behind it, the required implementation work, and
the criteria for deciding whether the next step is worth building.

## Product Thesis

MyLifeGraph should not become only a habit tracker, task list, or chat surface.
The core product value should be:

> Help the user decide what to do today by combining Tasks, energy, stress,
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
- Habits support the daily plan; they are not the product center.
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
| Task | A finite action with an optional deadline and estimate | Hours to weeks | Start, complete, postpone, cancel |
| Habit | A recurring behavior with a cadence and flexible execution window | Weeks to months | Complete, skip intentionally, pause, adapt |
| Schedule item | A fixed commitment or reserved block | One occurrence or recurring | Attend, edit, remove |
| Focus session | Time spent executing a task, habit, or chosen action | Minutes to hours | Start, stop, finish, abandon |
| Deadline plan | User-estimated preparation for one exam or assignment, versioned into dated blocks | Days to months | Propose, review, confirm, revise, complete, cancel |
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
- Canonical Supabase tables for logs, events, tasks, habits, schedule items,
  daily briefings, and user state snapshots. Goals, generic Recommendations,
  and Decision Feedback are absent from the current
  schema and export.
- Deterministic `daily` and `weekly` snapshot generation in FastAPI.
- Best-effort snapshot refresh after key Supabase-backed writes.
- A backend-only scheduled daily refresh endpoint for cron-style execution.
- Flutter dashboard, canonical lightweight daily check-in, habit management,
  insights and mock/guest paths.
- Phase 3 owner-scoped task commands, typed Habit V1 execution, a real focus
  lifecycle, and strict `executable-action-v1` targets. The complete command and
  recovery matrix lives in `docs/phase-3-executable-actions-contract.md`.

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
- Real recommendation, dashboard, Insights, and Inbox failures stay
  errors instead of becoming mock content.
- The dashboard renders direct stored check-in fields, tasks, and commitments;
  proxy score and metric-gallery placeholders are removed.
- Coach and the former placeholder Deep Work preview, fake Settings controls,
  and Supabase-only guest habit actions were gated. Phase 3 later restored only
  Deep Work through a real authenticated focus-session lifecycle.
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
most four deterministic current-state events. Guest V5 storage preserves the
same contract while reading and sanitizing legacy V1–V4 entries;
authenticated capture refreshes the explicit local snapshot date, and Dashboard
mapping remains direct and nullable. Phase 1 deliberately does not assign Daily
Mode, rank actions, persist a briefing, generate recommendations on save, or call
an LLM. The next gap was Phase 2's explainable deterministic daily state.
Flutter now derives authenticated Capture identity from one captured instant
and the session profile's IANA timezone through the shared
`ProfileLocalDateSource`; invalid account timezone data fails closed. Guest
Capture remains explicitly device-local.

Phase 2 now interprets that context inside backend-owned snapshots. Its current
`explainable-daily-state-v3` contract uses strict V2–V5 branch-compatible
capture parsing with joint V4/V5 container/branch identity and sleep-interval
validation plus friction and Day Shape
sanitization, a
fixed seven-day state lookback independent of the statistics window,
cadence-aware Evening/Morning freshness, explicit
`missing`/`partial`/`current`/`stale` quality, and recovery-first
`push`/`steady`/`recover`/`plan` classification.
Risks and reasons carry field-level evidence and deterministic provenance;
capture free text and learned-baseline claims stay out. It does not rank an
action, persist a briefing, change the Dashboard into Today, or call an LLM.

Phase 3 now closes the execution-contract gap. Tasks have recoverable typed
commands, Habit V1 distinguishes cadence and explicit outcomes, Deep Work owns
a real one-active-session focus lifecycle, and Flutter/FastAPI validate the same
strict action envelope. Response-loss reconciliation, database-locked habit
eligibility, immutable linked focus history, paginated/DST-safe habit progress,
complete paginated backend action windows, and start-day focus snapshot
attribution harden those contracts. Habit and focus facts are additive snapshot
inputs but do not change the Phase 2 Daily State result. Phase 3 does not rank actions,
persist a briefing, redesign Dashboard as Today, or call an LLM. The next gap is
Phase 4's deterministic briefing service.

### Current Surface Disposition

| Current surface | Keep | Change before relying on it |
| --- | --- | --- |
| Auth and guest entry | Yes | Local demo is labeled; mock/demo auth skips remote profile/data bootstrap and reloads local Setup, while canonical guest check-ins migrate best-effort only into a real non-demo account |
| Onboarding / Setup | Yes, Phase 0C complete | Progressive explicit input, typed prefill, atomic revision-safe save, differentiated retry/reload, and durable review are implemented |
| Today | Yes, Today Overview V2 current | A read-only owner-scoped overview shows streak, transparent progress, Setup/Planner/Preparation/Calendar/Focus agenda facts, and selected Tasks/Habits. The persisted briefing remains a backend input but its ranked action card is no longer the visible Today authority. |
| Canonical daily capture | Yes, Capture V5 current | Evening and Morning are separate typed flows over one ownership-merged daily entry. Authenticated writes use one backend-owned request ledger and branch-local compare-and-swap identity; a stale same-branch write conflicts without discarding the other branch. One framework-neutral V4/V5 contract validates current writes and supplies strict container-plus-branch sleep parsing to Daily State, Exam-Week Outlook, Personal Patterns, and Sleep Recommendation. Evening stores an explicit sleep plan; Morning stores corrected estimated sleep instants, derived duration, sleep quality, and energy without Day Shape. Complete V4 writes remain rollout-compatible and cannot downgrade V5. |
| Legacy large Daily Check-In | Retired | `/daily-check-in` redirects to the canonical lightweight flow; do not recreate a competing form |
| Habit management/completion | Yes, authenticated only | Habit V1 cadence, progress, streaks, explicit completion/skip, and undo are implemented; manual lifecycle stays in Habit Management, Setup-owned lifecycle stays in Settings Setup, and daily execution is available from Today Habits |
| Insights correlations | Yes | Default to one cautious observation; advanced correlations expose data sufficiency, source, and independent loading/error truth. Real accounts hide Skillset until a real producer exists; demo data is labelled as an example. |
| Inbox (`/alerts`) | Stored inbox with Lifecycle V1 | Structured internal links are allowlisted; read/unread/dismiss is durable and retry-safe, while stored preferences and rows still do not imply delivery |
| Deep Work | Yes, authenticated real-data mode | One active session, optional owned task/habit linkage, measured finish/abandon duration, and no implicit target completion are implemented; guest/mock redirects to Quick Action |
| Coach | Explicitly gated authenticated free-question agent | The route is fail-closed in release/production; capability/history reads are generation-free, backend `ready` gates sending, and each real turn is read-only over a temporary owner-only snapshot |
| Planner | Central authenticated planning home | Deterministic Task/Habit previews, Deadline Planner delegation, manual commitments, shared availability, conflict attention, explicit confirmation, and the read-only Exam-Week Outlook are implemented without hidden scheduling. |
| Study Setup | Optional Setup projection | Focus/recovery rhythm, preparation checklist, current/next semester, recovery reservations, and course-selection attention are implemented under the revisioned Setup authority. |
| Settings | Durable V1 controls | Profile, Setup and Study Setup review, account timezone, preparation budget, Inbox, reminders, bounded export, confirmed deletion, device-persisted theme, Calendar Import, and sign-out expose their actual persistence boundaries. Coach is a gated shell destination, not a Settings fallback. |

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
3. Completes a short progressive intake with typical weekday and best energy
   window.
4. Optionally adds a display name, routines, fixed commitments, or Study Setup.

What the app does:

- Stores only answers the user actually supplied; empty fields must not create
  invented Habits or timetable blocks.
- Treats named existing habits as reviewable candidates before activating them.
- Creates a compact onboarding snapshot without generating Recommendations.
- Lands on Today and asks for runtime calibration only where the product
  explicitly needs it; it does not present an intake-derived score.

Target effort: under three minutes for the required path. Timetable detail,
additional habits, Study Setup, and integrations remain progressive setup.
Reminder consent and delivery preferences remain independently owned by
Settings.

### First Useful Day

What the user does:

1. Gives current energy, sleep duration, and estimated sleep quality in 10 to 20
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
- Explicitly plans an exam or assignment by entering total active preparation
  time and prior credit, then reviews staged dated blocks before confirmation.
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
2. Reports mood, energy, and stress intensity. At medium/high stress, the flow
   also asks source and controllability.
3. Optionally records a reflection or specific blocker. The retired likely
   priority is not shown or newly written.
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

- Confirms or corrects the provisional plan with sleep duration and quality,
  and current energy.

What the app does:

- Finalizes Daily Mode and capacity.
- Keeps the plan stable when the evening estimate still fits.
- Downgrades load when sleep, stress, or constraints changed.
- Shows what changed and why rather than silently replacing the plan.

### Weekly Review

This becomes useful only after the daily loop produces enough real outcomes.

What the user does:

- Reviews completed and carried Tasks, Habit opportunities, recovery days, and
  feedback on recommendations.

What the app does:

- Summarizes behavior without moralizing missed days.
- Separates scheduled opportunities, intentional skips, and uncompleted actions.
- Reports data quality and freshness without proposing or applying changes.

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
| Start | Setup and current calibration | Conservative Daily Mode from runtime signals and one explicit next action when available | Personal baseline, trend, correlation, optimized score |
| First week | Several check-ins and action outcomes | Recency-based adjustments, scheduled habit progress, simple workload and recovery flags | Stable long-term pattern or causal insight |
| Two-plus weeks | Repeated comparable signals | Emerging patterns with visible sample size and low/medium confidence | Medical conclusion or certainty from correlation |
| One-plus month | Daily and weekly outcomes plus feedback | Personal baselines, observational weekly trends, stronger ranking | Unreviewed autonomous schedule changes |
| Integration stage | Calendar or wearable data with consent | Lower-friction capture, better capacity estimates, conflict-aware proposals | Hidden provider writes or opaque data use |
| Coach stage | Retained personal data in an ephemeral owner-only snapshot | Explain, compare, test assumptions, answer follow-ups, and state missing information through bounded read-only tools | Acting as a doctor/therapist, inventing causality, exposing hidden reasoning, or mutating product data |

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

- The user can accurately report stress, mood, task reality, and unfinished
  work after living the day.
- Evening capture can prepare tomorrow without forcing a planning session in the
  morning.
- It gives the backend time to generate the next daily state before the user
  opens the app again.

Target effort: under 90 seconds across three short pages.

Required fields:

- Energy level.
- Stress intensity.
- Mood.
- Planned local sleep start.
- Sleep-duration target.

Conditional fields at stress `5..10`:

- Stress source.
- Stress controllability.

Optional fields:

- Reflection note.
- Specific blocker.

Current Phase 1 output:

- Persisted current-state context. A legacy likely priority remains readable
  for compatibility but is not editable or newly written.
- No primary/additional friction field is persisted or evaluated.
- No provisional plan is generated. For authenticated real accounts, Phase 2
  now classifies an explainable backend Daily State best-effort after the
  write; the capture surface does not present that state as a briefing.

### Morning Calibration

Current goal: record corrected estimated sleep instants and their derived
duration plus independently estimated quality and current energy in two short
pages without repeating the Evening form. The first page owns the interval and
target; the second owns quality and energy. The complete draft stays local
through `Next` and `Back`, and persistence occurs only from the final save.
Adjusting a provisional plan begins only after explainable state and briefing
generation exist.

Reasoning:

- Sleep duration, sleep quality, and current readiness are not known at evening
  shutdown.
- Morning capture must be short or it becomes a source of friction.
- This is where the app should finalize the daily mode.

Target effort: 10 to 20 seconds.

Required fields:

- Estimated sleep start and wake time; their derived interval is positive and
  at most 16 hours.
- Sleep target used for this night.
- Estimated sleep quality, independently selected from `1..10`.
- Current energy.

The Sleep page shows 50-percent progress and enables `Next` only for a complete
valid interval and target. The Check-in page shows 100 percent; a failed save
stays there with the exact draft and retry identity. The duration,
target-source, and quality explanations are initially closed independent inline
information areas. Evening uses the same disclosure behavior for its planned
sleep intent and first-visible target explanation, while its headings,
optional-context copy, and stress-source help remain visible or separately
controlled.

The earlier per-day Day Shape selection is retired. Current V5 writes reject
`day_shape`; historical V2–V4 capture data remains readable but is not shown or
used in classification.

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
| push | Good energy, manageable stress, clear high-value action | Protect focus and advance an important Task |
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
routine or recovery need. They should not become a second task list or a source of
streak pressure.

### Habit V1 Scope

The implemented coherent habit version supports binary completion with flexible
cadence:

- `daily` or specific ISO weekdays.
- `x times per week` with a weekly target from 1 to 7.
- Active, paused, and archived lifecycle for manual habits.
- Setup-owned definition/lifecycle changes through Settings Setup while active
  Setup habits share daily execution.
- Daily outcome: completed, intentionally skipped, or open; a past scheduled
  open opportunity is derived as missed.
- Same-day undo for an accidental completion or skip.

Minimum versions and preferred execution windows remain future extensions;
Goal linking is retired and is not part of the validated Habit V1 contract.

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
- A habit can become the primary action only when it is context-relevant,
  time-appropriate, and compatible with Daily Mode.
- The Weekly Review reports Habit outcomes and limitations without proposing or
  applying a definition change.
- Start with one to three important habits. Do not encourage users to activate a
  large routine inventory during onboarding.

### Habit Data Direction

Phase 3 stores validated cadence details in `habits.metadata` under
`contract_version: habit-v1`, for example:

```json
{
  "contract_version": "habit-v1",
  "cadence": "weekdays",
  "scheduled_weekdays": [1, 3, 5]
}
```

The compatibility `habits.frequency` projection remains `daily` for daily and
selected-weekday cadence and `weekly` for weekly-target cadence. The Phase 3
migration adds authoritative `habit_logs.status` with only `completed` or
`skipped`; `value` remains a checked compatibility projection of 1 or 0. Open
means no same-day row exists, and miss is derived from an elapsed scheduled
opportunity without a row. Positive legacy values normalize to completion; the
migration refuses ambiguous legacy rows with a missing status and `value <= 0`
instead of inventing a skip. Existing RLS/grants remain in force and ownership
is additionally guarded at the database boundary. The write trigger locks the
habit row and revalidates active lifecycle, Setup state, and selected weekday,
so a concurrent pause/archive/cadence edit cannot admit a stale outcome.

Flutter paginates habits in 500-row pages and outcomes beginning 370 calendar
days before today in 1,000-row pages. New manual rows persist local
`metadata.started_on`; progress/streak iteration uses calendar-date components,
not fixed 24-hour durations, so DST transitions do not shift opportunities.
Manual definition/lifecycle updates reconcile committed response loss only by
exact owner-scoped mutation readback. Outcome/undo captures its local target
date before awaiting persistence, proves the exact row or absence after loss,
and refreshes that same date.

## Cross-Cutting Trust And Attention Contract

These rules apply to every phase because life, stress, and behavior data is
sensitive and daily capture is easy to abandon after one bad interaction.

### Capture Reliability

- A failed or timed-out write must keep the user's draft and offer a clear retry.
- Retry must be idempotent or deduplicated so one check-in does not become two
  daily records.
- Authenticated Save is unavailable until the current synchronized branch
  identity has loaded. Morning separately requires either a readable prior
  Evening plan or explicit one-time continuation without it.
- Only `PUT /v1/daily-capture/{entry_date}/{morning|evening}` may persist a real
  account Capture. The backend transaction merges the branch, refreshes the
  canonical Daily Log projection, and replaces only its `quick_check_in`
  Behavioral Events.
- The UI must not show a saved state until the durable guest or Supabase write
  has succeeded.
- If full offline sync is not implemented, say that a draft is pending locally;
  do not imply server persistence.
- A successful save should immediately affect the next relevant state or screen
  so the user can see that their input mattered.

### Future Delivery And Attention

The current `/alerts` surface is a stored Inbox over rows with durable
read/unread/dismiss tombstones under
`docs/notification-lifecycle-v1-contract.md`. Notification Delivery V1 now adds
the separate local foreground boundary in
`docs/notification-delivery-v1-contract.md`:

- Existing reminder preferences do not grant delivery; dedicated consent
  defaults off and is explicitly confirmed in Flutter.
- The local scheduler can create fixed, non-LLM recovery and exact-week
  items with timezone, quiet-hour, category, local-day cap, dedupe, provenance,
  and sensitive-copy guards revalidated in the database.
- Missing/stale daily preparation stays independent of consent; only actively
  consented fully current profiles consume notification-only runner slots.
- An open authenticated Flutter app acknowledges a due row before showing one
  at-most-once in-app banner. Guest/demo makes no delivery call.

Still future:

- Start with explicit user-selected check-in and commitment reminders.
- Add user-selected check-in/commitment reminder identities only under a new
  directly verified source contract; the current slice uses recovery and
  completed-week sources only. A current briefing alone creates no reminder.
- Route each notification to the exact capture, task, habit, or briefing action;
  never to a generic dashboard with no obvious next step.
- Snooze and every push/browser/Android/background delivery channel remain
  absent; local foreground delivery already respects timezone, quiet hours,
  per-category flags, and a conservative daily cap.
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

The briefing must wrap the implemented Phase 3 action envelope rather than
invent another command shape or return display-only labels:

```text
BriefingAction
- target: ExecutableActionTarget (`executable-action-v1`)
- title: user-visible action
- reason: one concise evidence-backed explanation
- recommendation_id: nullable source recommendation

ExecutableActionTarget
- contract_version: executable-action-v1
- id: stable command/target identity
- kind: task | habit | focus | planning | recovery | capture
- command: open_task | complete_task | log_habit | start_focus |
  review_plan | open_capture
- target_id: nullable target governed by the command matrix
- estimated_minutes: nullable integer from 1 to 480
- metadata: bounded command-specific scalar context; allowed fields are
  entry_date, focus_minutes, habit_outcome, route, source, and target_kind
```

FastAPI rejects unknown fields and incompatible kind, command, target, route,
estimate, or metadata combinations, including null/non-object metadata,
explicit-null fields, numeric coercion, invalid ISO dates, and focus linkage.
A briefing must run that strict validation before returning an action. Flutter
keeps the shared version for compatible Focus metadata, but no longer has a
consumer for the generic envelope parser. Its current typed controls open
`/weekly-review` directly without generating or applying a proposal. The reserved `recovery` kind has no executable command yet
and may not become an enabled no-op.

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

Add a dedicated table only when the first backend briefing slice demonstrates a
need for stable daily identity, morning availability, scheduling, stale
detection, or exact E2E persistence assertions:

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
- Habit gaps.
- Recent stress source and controllability.
- Existing recommendation status and feedback.

Candidate score dimensions:

- Task relevance.
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

- Three short pages instead of one page per answer.
- Required energy, mood, and stress intensity; stress source and controllability
  are a paired conditional question at stress `5..10`.
- No tomorrow-priority input. New saves omit it; a retained legacy value
  survives an otherwise valid edit. Measured focus comes from completed Focus
  sessions instead of another self-estimate.
- Optional reflection and specific blocker; blank optionals are omitted rather
  than replaced with fallback content. The former gentle-tomorrow switch is
  retired and no longer written; legacy metadata containing it stays readable.
- A required `HH:mm` planned sleep start and `300..720` minute target on a
  15-minute grid. Eight hours is visible first but becomes personal only on
  save; the newest valid Evening V4 value prefills later forms.
- The intent and first-visible-target explanations start closed behind
  independent inline information controls. Step headings, optional context,
  and the separate stress-source help remain visible or independently
  operable.
- On the last page, an optional `Today's Focus sessions` row reports terminal
  sessions as rated or still open and reuses the terminal-only Focus reflection
  sheet for `Rate`/`Edit`. It is supplementary context, not another navigation
  destination, and guest/demo makes no synced request.
- Prefill and same-kind replacement without erasing a saved Morning
  Calibration.
- Capture copy that does not claim a learned baseline, ranked plan, diagnosis,
  or causation. An authenticated real save may refresh the separate Phase 2
  backend Daily State best-effort.

Reasoning:

- This is the main daily data capture moment.
- It should feel like confirming reality, not filling a form.
- A provisional tomorrow plan remains a later briefing concern; Phase 1 stores
  current context but does not rank or generate actions.

### Morning Calibration Flow

The implemented short Morning Calibration surface supports:

- A 50-/100-percent two-page draft. Sleep requires aware estimated
  sleep-start/wake instants, exact whole-minute derived duration no longer than
  16 hours, and the target used for that night; Check-in requires an independent
  whole-number `1..10` estimated sleep-quality rating and current energy. There
  is no Day Shape field.
- `Next` validates only the complete Sleep page, `Back` retains every answer,
  and only `Save morning check-in` on the second page persists. Save failure
  retains the complete second-page draft for unchanged retry.
- Initially closed, independently expandable measurement/source explanations
  for estimated duration, target, and quality. The same reusable Capture
  control hides the two Evening sleep-plan explanations without changing its
  existing step headings or context help.
- Prefill and same-kind replacement without erasing saved Evening context.
- Honest current-state copy stating that capture does not generate
  recommendations or create or change a plan. Authenticated real saves may
  refresh the separate backend Daily State; guest/mock saves remain local.

Reasoning:

- Morning readiness can invalidate the evening plan.
- The user should never need to re-plan the whole day from scratch.
- Daily Mode now exists in Phase 2 backend snapshots and executable targets in
  Phase 3; top-action selection begins with the Phase 4 briefing service.

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
- The implemented Coach is visible only to authenticated real-data sessions and
  may send only when its backend capability is ready. Each free question gets a
  fresh owner-only personal snapshot and only read-only catalog, SQL, and
  isolated-Python tools.
- Do not classify questions into Today, Patterns, Focus, or Review. The agent
  may answer directly, test a premise, report missing data, or ask a concise
  clarifying question.
- Earlier memory selection and fixed-mode history remain readable only for
  compatibility. Current Coach has no memory selector, structured suggestion,
  or product apply action.
- Any task, habit, schedule, calendar, notification, memory, or planning idea
  remains plain text; Coach cannot stage, persist, or claim the change.
- The expandable answer detail comes from actual backend tool execution and
  may show sources, periods, counts, SQL/Python steps, limitations, and
  provenance, never chain-of-thought or plots.
- Health and stress guidance remains informational and must not claim diagnosis
  or treatment.

## Data Model Changes

Phase 1 reuses existing tables. It stores the two owned capture objects in
`daily_logs.metadata.captures` and mirrors event-relevant fields into
`behavioral_events.metadata`.

Implemented metadata shape, abbreviated:

```json
{
  "capture_version": "daily-capture-v5",
  "captures": {
    "evening": {
      "branch_version": "daily-capture-v5",
      "capture_kind": "evening",
      "entry_date": "2026-07-10",
      "stress_intensity": 9,
      "stress_intensity_label": "high",
      "stress_source": "private_emotional",
      "stress_controllability": "hardly_controllable",
      "planned_sleep_time": "23:00",
      "sleep_target_minutes": 480
    },
    "morning": {
      "branch_version": "daily-capture-v5",
      "capture_kind": "morning",
      "entry_date": "2026-07-10",
      "estimated_sleep_started_at": "2026-07-09T22:00:00Z",
      "woke_at": "2026-07-10T03:30:00Z",
      "estimated_sleep_minutes": 330,
      "sleep_target_minutes": 480,
      "source_evening_capture_id": "previous-evening-capture-id",
      "sleep_hours": 5.5,
      "sleep_quality": 3,
      "current_energy": 3
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
- Sleep quality is bounded Morning metadata mirrored onto existing
  Morning-origin events; it does not create a fifth event or overwrite sleep
  duration.

Phase 2 also reuses the existing `user_state_snapshots` JSONB columns. Its
abbreviated persisted shape is:

```json
{
  "summary": {
    "daily_state": {
      "contract_version": "explainable-daily-state-v3",
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
      "contract_version": "explainable-daily-state-v3",
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
    "daily_state_contract_version": "explainable-daily-state-v3",
    "state_lookback_days": 7,
    "window_days": 7
  }
}
```

The state lookback stays fixed at seven days even when `window_days` changes.
Top-level `summary.risk_flags` is a compatibility alias for current Daily State
risks; statistics-window risks remain separate in `summary.window_risk_flags`.
No capture free text appears in this snapshot contract.

Deadline Planner V1 uses dedicated backend-owned tables because immutable
revision history, staged-versus-active truth, dated reservations, request
replay, and account export do not fit recurring `schedule_items` or task
metadata safely:

```text
deadline_plans
deadline_plan_revisions
deadline_plan_blocks
deadline_plan_request_identities  # backend-only anti-replay ledger
```

The first three are owner-readable/exported product data. The request ledger is
forced-RLS backend-only and explicitly omitted from Account Export. A confirmed
plan owns one stable managed task; focus remains in `focus_sessions` and is
counted only as derived post-activation progress.

Add dedicated columns later only if the fields become stable and heavily
queried:

- `stress_source`
- `stress_controllability`
- `stress_intensity_label`

The current recommendation `action_label` is informational suggested-next-step
copy, not an executable control. Today execution uses the owning Task, Habit,
Focus, capture, and Weekly Review flows from the read-only overview; persisted
briefing targets are not rendered as controls. Recommendation `status` remains
historical state; Phase 6's append-only feedback table owns briefing outcome
evidence across action types.

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
- Keep Setup-created cadence-confirmed habits and fixed commitments reviewable,
  editable, pausable/archivable, and removable before Daily Mode uses them;
  atomic reconciliation must continue to preserve manual rows. Reject Goal
  input. Keep Setup-owned habit editing in Settings Setup while allowing active
  completion.
- Define mock/guest behavior separately from real-backend empty/error behavior.

Evaluation:

- Does every visible production control work and persist as its label promises?
- Can a real account distinguish fresh, stale, empty, failed, and demo data?
- Does saving a check-in persist exactly what the user selected?
- Does a failed save preserve the draft, and can retry complete without a
  duplicate daily record?
- Do widget and browser tests verify values and outcomes, not only navigation?
- Can the user revisit setup without duplicate habits or commitments and
  without changing Reminder settings?
- Can a developer explain the object and action contracts without reading UI
  implementation details?

### Phase 1: Lightweight Evening And Morning Capture (Complete)

Goal:

- Capture the minimum signals needed for good daily decisions with low friction.

Implemented:

- Separate typed Evening Shutdown and Morning Calibration flows with retained
  drafts, prefill, recoverable save errors, and stable retry identity.
- Morning is split into Sleep and Check-in pages with 50-/100-percent progress,
  local `Next`/`Back`, and one final persistence action. Three Morning and two
  Evening sleep explanations are initially closed behind independent accessible
  information controls.
- Morning requires sleep duration and an independent `1..10` estimated sleep
  quality. Older V2 Morning branches without the additive field remain
  readable and require a value only when that Morning capture is resaved.
- Evening requires mood, energy, and stress, conditionally requires stress
  source/controllability, and stores no friction-selection fields.
- Same-day merge ownership: a submitted capture replaces only its own
  `metadata.captures` object and preserves the other kind.
- Numeric projection keeps Morning energy over Evening energy, Evening mood and
  stress, Morning sleep, and nullable unmeasured focus minutes.
- Supabase replaces the linked source-owned event set with a dynamic maximum of
  four deterministic mood/energy/stress/sleep ids and mirrored bounded metadata.
- Guest storage writes V3 daily JSON, sanitizes V1/V2 JSON on read, and retains
  the existing best-effort migration into a real non-demo account.
- Authenticated writes refresh the exact local `target_date`; backend event
  filtering prefers `metadata.entry_date` after a broadened UTC read and falls
  back to the timestamp for legacy rows.
- Flutter sends the typed Daily Capture impact through app composition, which
  invalidates latest Capture, Today, persisted Briefing, and Exam Outlook
  reads. Guest Capture performs the same local invalidation without a backend
  Snapshot refresh.
- Authenticated Flutter draft identity and the read target use one shared
  profile-timezone date source. Guest/no-account drafts deliberately use the
  device calendar, and invalid authenticated timezone data never falls back to
  it.
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
  `explainable-daily-state-v3` without changing schema or capture ownership.
- Added strict V2–V5 capture parsing for identity, types, enums, bounded
  numbers, timestamps, interval arithmetic, and numeric projections. The V4/V5
  sleep branch now uses the same parser module as Exam-Week Outlook and
  Personal Patterns, so those consumers cannot silently disagree on validity.
  Friction and Day Shape fields are ignored. V3 removes
  `constrained_capacity` and the Day-Shape gate for `push` while current
  consumers retain readable V1/V2 snapshots.
  Legacy numeric fallback is accepted only when no structured marker exists;
  malformed structured capture does not regain trust through columns.
- Added a fixed seven-day state lookback independent of the requested
  statistics window. Evening is current from the target date or previous date;
  Morning only from the target date.
- Added `missing`, `partial`, `current`, and `stale` quality plus bounded stress,
  recovery, workload, planning, capacity, and calibration risk flags.
- Added deterministic, recovery-first `push`, `steady`, `recover`, and `plan`
  classification with machine-stable reasons, user-readable non-clinical copy,
  field-level evidence, provenance, and no learned-baseline claim.
- Added sleep-quality-aware recovery guards: very low current quality can
  select `recover` despite sufficient duration, while moderately low quality
  prevents `push`.
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

### Phase 3: Executable Tasks, Habits, And Focus (Complete)

Goal:

- Give a future briefing reliable actions it can point to.

Implemented:

- Added owner-scoped task create/edit/complete/postpone/cancel/restore/undo with
  bounded fields, stable create ids, retained drafts, confirmation, and
  best-effort snapshot refresh after a successful durable write. Every update,
  including direct undo, reconciles an ambiguous committed response only by
  exact mutation timestamp plus all requested persisted fields.
- Added Habit V1 daily, selected-ISO-weekday, and weekly-target cadence;
  cadence-aware progress/streaks; explicit completed/skipped outcomes; derived
  open/missed states; and same-day undo. Manual lifecycle and Setup-owned
  definition authority remain separate while both share execution. Reads are
  paginated from 370 calendar days before today, and `started_on` plus
  calendar-date arithmetic make opportunity math DST-safe. Manual
  edit/lifecycle updates use exact response-loss readback; outcome/undo captures
  one target date, proves the exact row or absence, and refreshes that date.
- Added `habit_logs.status` plus checked compatibility values and ownership
  enforcement. A locked trigger rechecks active lifecycle and selected-weekday
  cadence. The migration deliberately rejects ambiguous legacy non-positive rows
  rather than fabricating skip intent.
- Added a Today Habits execution surface and a real authenticated `/deep-work`
  flow with one active session, optional owned task/habit link, measured
  finish/abandon duration, locked target validation, exact response-loss
  reconciliation, rejection of every terminal-row update, `ON DELETE RESTRICT`
  target attribution, and no implicit linked-target completion. New rows persist
  their local start date; the migration backfills legacy gaps from `started_at`
  UTC, matching the Flutter/FastAPI fallback and refresh date.
- Added parser-equivalent strict Flutter and FastAPI `executable-action-v1`
  validation, including explicit-null metadata-field rejection, and typed
  Flutter dispatch. `review_plan` remained explicitly unavailable in Phase 3;
  Phase 8 later supplies its bounded synced navigation surface. The unused
  Flutter parser and dispatcher were subsequently removed; backend validation
  and compatible Focus provenance remain.
- Added explicit habit-outcome and focus-session snapshot summaries while
  paginating complete backend action windows in stably ordered 1,000-row pages,
  keeping the Phase 2 Daily State output unchanged, and leaving recommendation
  generation outside ordinary action writes.

The browser E2E source injects response loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish. Its negative writes
include terminal-focus `updated_at` mutation. Phase 8 adds bounded weekly review,
and Phase 9 adds bounded calendar-import ownership and recovery assertions. The
combined Phase 3 through Phase 9 journey passed non-destructively in the
2026-07-13 Phase 9 implementation checkout. Later changes must establish their
own current-checkout pass before claiming E2E.
Phase 10 browser source uses the deterministic fake provider and covers the
free-question response/stream/replay/safety/history/RLS/UI boundary. A current
checkout must rerun it before claiming the new snapshot, trace/provenance,
cancellation, and no-fixed-mode behavior. Earlier fixed-context browser and
live-model results do not verify this agent path.

The complete object/command/validation/recovery contract is in
`docs/phase-3-executable-actions-contract.md`.

Evaluation:

- Is every action target directly startable or openable?
- Does a weekly habit report `completed / target` correctly?
- Are scheduled opportunities, skips, misses, and completions distinct?
- Can accidental task/habit outcomes be undone?
- Do failed writes rollback optimistic UI or show a recoverable error?
- Do ambiguous committed transitions succeed only after exact persisted
  reconciliation, and do divergent writes remain errors?
- Before claiming full Phase 3 browser completion, has the local Supabase E2E
  run succeeded for exact rows, response-loss cases, and negative database
  writes? Source coverage alone is not a pass.

### Phase 4: Deterministic Briefing Service (Implemented)

Goal:

- Produce one daily editorial decision from state and executable candidates.

Implemented:

- Added `daily_briefings` persistence for morning availability, stale
  detection, scheduling, and E2E assertions.
- Added repository, strict models, and authenticated `GET /v1/briefings/today` plus
  deliberate `POST /v1/briefings/generate` routes.
- Refreshes or validates daily state before generation.
- Ranks one primary action and at most two support actions by relevance,
  urgency, energy fit, time fit, recovery risk, current outcome state, and
  evidence recency. Decision feedback is not yet available and remains a later
  phase input.
- Includes mode, capacity note, reason, provenance, evidence refs, freshness, and action
  targets.
- Keeps LLM usage disabled and numeric capacity null until a validated policy exists.
- Keeps normal Dashboard reads generation-free; Phase 5 consumes the result
  without changing Phase 2 or Phase 3 semantics.

Evaluation:

- Does `GET` remain read-only and report stale/missing state?
- Does `POST` derive user identity from the bearer principal?
- Does every returned action point to a real executable target?
- Does insufficient data yield a conservative useful briefing?
- Can browser E2E assert the briefing after capture and state refresh?

### Phase 5: Decision-First Today Dashboard (Implemented)

Goal:

- Make the first screen the daily operating cockpit.

Implemented:

- Show Daily Mode, primary action, reason, time/capacity note, and freshness above
  secondary metrics.
- Dispatch current primary/support actions through the existing strict Phase 3
  handlers; outcome and preference feedback history remains Phase 6.
- Keep fixed commitments, tasks, habits, and direct nullable check-in truth below
  the ranked decision surface.
- Add `adjust today` for material state or schedule changes.
- Keep advanced metrics and history below the execution surface.
- Preserve deliberate refresh without generating on normal dashboard reads.

Evaluation:

- Does the first viewport answer what to do now and why?
- Can the user begin the primary action in at most two interactions?
- Are no more than three decision items emphasized?
- Does action execution reuse durable command contracts without a parallel path?
- Does mobile and desktop layout preserve readable, non-overlapping actions?

Current presentation update (2026-08-14): the persisted Phase 4 briefing
remains an internal backend input, but the generic Phase 6
Recommendation/Feedback loop is retired and the
visible briefing-first card described in this historical phase is superseded by
Today Overview. Today no longer labels a ranked recommendation as a decision
made for the user. Flutter therefore has no direct briefing repository/provider
or `/v1/briefings/*` call path; backend persistence, scheduled preparation,
Account Export, and Coach context remain implemented. `GET /v1/today/overview`
retains the compatible V1 read; Planner
adds `GET /v1/today/overview-v2` with Setup, Planner, Preparation, Calendar,
Focus, Task, Habit, and fixed-commitment facts. The visible streak card adds a
narrow latest-check-in read. Weekly Review is a direct capability-gated
navigation entry. The current calendar week is the only supporting accordion
and loads only when opened. Neither Planner nor Today has a standalone
preparation-workload card; Preparation editors retain the workload summary
read for the account budget.
Read `docs/today-overview-v1-contract.md`, `docs/planner-v1-contract.md`, and
`docs/study-setup-v1-contract.md` before changing this surface.

### Phase 6: Feedback And Useful Insights (Historical; Feedback Retired)

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

### Phase 7: Scheduled Daily Preparation (Minimal Backend Implemented)

Goal:

- Make the app prepared when the user opens it without hiding generation.

Implemented backend contract:

- Extended the existing token-protected `POST /v1/scheduled/daily-refresh`
  boundary; no unrelated worker or user-facing generation path was added.
- Captures one timezone-aware run instant and resolves every onboarded non-guest
  profile to its stored-IANA-timezone local briefing date. An explicit
  `target_date` remains a deterministic operator/test override, and an invalid
  timezone fails only that profile.
- Selects missing daily snapshots, missing daily briefings, and briefings stale
  against their source snapshot id or generation timestamp. Current pairs are
  normally omitted; optional deterministic recommendation retry may select a
  current pair while reusing its briefing unchanged.
- Generates a missing snapshot exactly once, reuses an existing snapshot, and
  creates or refreshes the stable `(user_id, briefing_date)` briefing. One
  bounded post-persist convergence retry handles a concurrent snapshot change.
- Isolates failures per user, caps concurrent preparation, and returns bounded
  profile-date, snapshot, briefing, or recommendation stage results. A bounded
  `profile_ids` UUID list can target an eligible subset without bypassing
  onboarding or non-guest checks.
- Keeps scheduled work deterministic and no-LLM. Normal Dashboard load remains
  GET-only, ordinary capture/action writes do not generate briefings, and user
  adjustment remains deliberate.

Deliberately not claimed:

- No deployed cron/job has been configured or inspected; the repository now
  provides the protected callable backend boundary only.
- No deployed/background, push, browser, Android, email, or check-in reminder is
  configured. The local runner and foreground in-app path cover explicit
  consent, fixed copy, quiet hours, category flags, cap, dedupe, and allowlisted
  Today/Weekly Review links only. Snooze remains future work.

Evaluation:

- Does an invoked scheduled run prepare a fresh profile-local morning briefing
  without a user-triggered POST?
- Are stale or failed briefings visibly distinguishable?
- Are retries idempotent and free of LLM calls?
- Before any notification work is claimed, does it honor opt-in, the correct
  local window, exact deep links, disabled/demo state, quiet hours, and
  sensitive-copy restrictions?

### Phase 8: Observational Weekly Review (Implemented)

Goal:

- Help the user improve the system instead of merely accumulate history.

Implemented:

- One strict `weekly-review-v3` review is pinned to an explicit completed
  profile-local ISO week. Latest/period GET remains read-only; deliberate POST
  upserts one backend-owned derived identity.
- Exact facts distinguish current durable completed and carried tasks,
  completed/skipped/missed/unknown habit opportunities, focus, valid persisted
  recovery days. Known task-history and changed-cadence gaps remain
  limitations instead of reconstructed events.
- A canonical source fingerprint exposes stale evidence. Generation persists
  only the facts-only review with `proposals=[]`; it never changes a user-owned
  record or calls an LLM.
- Proposal arrays are empty and no Weekly Review command can apply one.
- `review_plan` opens the real authenticated weekly-review surface without
  generating or applying by itself. Guest/mock remains local and review-free.

Evaluation:

- Can the user finish the review in a few minutes?
- Are skips and recovery days treated differently from unaddressed commitments?
- Do confirmed changes improve the following week's briefing inputs?

### Phase 9: Optional Integrations (First Bounded Slice Implemented)

Goal:

- Reduce manual capture after the standalone loop has proven useful.

Implemented first slice:

- One optional authenticated `ical_file` source requires explicit
  `calendar-import-consent-v1`; onboarding does not ask for calendar interest,
  and any legacy Setup interest value never counts as consent.
- A deliberate bounded UTF-8 `.ics` upload persists only whitelisted basics in
  dedicated read-only integration rows. Stable connection/import/event and
  recurrence-occurrence identities reconcile retries and duplicate input.
- Timed, all-day, cancellation, invalid, and unsupported recurrence cases stay
  explicit. Event reads are stable and paginated, and every row carries
  imported/read-only provenance.
- Disconnect retains and marks the local copy stale; confirmed deletion removes
  imported local events/history while preserving manual and Setup-owned
  commitments.
- There is no provider OAuth/token, arbitrary URL fetch, provider write,
  background sync, RRULE expansion, LLM processing, or automatic time-block
  proposal/application. Deadline Planner V1 is the separate recoverable
  contract for a user-selected event and retains explicit staging and confirm.

Still later:

- Live calendar-provider connections and carefully bounded sync.
- Wearable or platform health signals with separate explicit consent and
  provenance.

Evaluation:

- Does the app remain fully usable without an integration?
- Can users see, disconnect, and delete imported data?
- Do integrations reduce capture effort without making recommendations opaque?

### Deadline Planner V1: Explicit Exam And Assignment Preparation

Goal:

- Reserve realistic preparation time early while keeping effort estimates and
  every activation under user control.

Contract:

- The user explicitly supplies `exam|assignment`, title, aware deadline,
  `30..30000` active-preparation minutes, prior credit, planning start, session/
  daily bounds, and `0..7` buffer days within a 366-day planning horizon.
- A manual source or one explicitly selected imported event may be used. Title
  inference is forbidden; imported busy intervals are a separate per-plan
  opt-in and remain read-only.
- Each deliberate request creates an immutable proposed revision with at most
  120 deterministic dated blocks and honest unscheduled minutes. The active
  revision stays authoritative until exact confirmation. Proposal edits match
  the latest persisted revision; completion and cancellation after activation
  require the current active revision. A still-draft plan may also be cancelled
  at its latest revision to discard its pending preview and proposed
  reservations without ever creating a managed task.
- First confirmation atomically creates the stable managed Phase 3 task.
  Completed post-activation focus linked to it contributes measured progress
  but never completes the plan.
- Generic Task edit/lifecycle/editor paths reject the managed source. Focus may
  target it while open; later confirm owns title/deadline projection and plan
  complete/cancel atomically own its matching terminal state.
- GET and all unrelated product paths are side-effect free. There is no LLM,
  notification, provider write, background sync, or hidden generation.
- The compatible on-demand workload-day detail is limited to the current
  seven-day profile-local view. It explains active plan minute/block
  contributions and exact overage without selecting a plan; review and replan
  remain deliberate existing flows.
- The additive Exam-Week Outlook is one Planner-only read: an active exam
  activates 14-day watch/seven-day exam-week/overdue modes, while assignments
  only consume capacity. It simulates remaining gaps through shared
  Availability normally and with the newest saved sleep plan hypothetically
  protected. Missing or DST-ambiguous sleep context stays unknown. It stores no
  simulation and opens only the existing explicit replan review.

Evaluation:

- Does the plan reflect the user's estimate rather than an inferred workload?
- Can response loss, stale revision, and concurrent confirmation converge
  without replacing a newer active plan?
- Are manual commitments, confirmed blocks, optional busy intervals, timezone,
  DST, block bounds, and an impossible capacity deficit represented honestly?
- Does linked focus change progress without stealing lifecycle authority?

### Phase 10: Free Read-Only Coach Data Agent (Implemented Repository Boundary)

Goal:

- Add open-ended conversational analysis after the deterministic product loop
  works without granting mutation authority.

Implemented:

- Added authenticated `coach-request-v4`, `coach-response-v4`,
  `coach-capabilities-v5`, `coach-history-v4`, history deletion, and SSE
  lifecycle contracts with one in-flight request per owner, a retained
  profile-local daily question budget, and safe feature flags.
- Replaced Today/Patterns/Focus/Review, horizons, Focus selection, prompt
  starters, memory selection, and structured suggestions with one free field.
- Builds a fresh immutable owner-only SQLite snapshot for each non-safety turn
  from retained relevant Setup, Capture, action, planning, calendar, review,
  insight, memory, and Coach data. It includes catalog,
  relationship, count, period, and helper-view metadata under
  `free-coach-agent-prompt-v5`/`personal-snapshot-v3`, while excluding auth,
  secrets, cross-user, anti-replay, provider, and operational rows.
- Reuses Account Export's 10,000-per-table, 50,000-total, and 8 MiB limits and
  reports overflow instead of truncating.
- Gives request-scoped OpenAI/Gemini BYOK providers bounded catalog-inspection
  and immutable-SQL results without the SQLite file. Local/operator Codex use
  one required per-turn stdio MCP and additionally receive Python in a
  no-network, non-root, read-only Docker sandbox. A turn has 12 tools/180
  seconds; SQL/Python have shorter limits. Internal plots are temporary and
  never visible.
- Lets the agent answer directly, combine queries, use Python only through a
  Codex adapter, test or correct a premise, explain absent information,
  or ask a concise question. Stored free text is untrusted data, never
  instructions.
- Adds deterministic pre/post wellness safety boundaries, urgent provider
  bypass, explicit uncertainty, non-causal/diagnostic rules, and source-aware
  responses.
- Adds request-scoped OpenAI `gpt-5.6-terra` and Gemini
  `gemini-3.6-flash` user-key adapters plus an injectable
  `local_codex_oauth` provider that invokes the current Linux/WSL user's
  explicitly enabled, already authenticated Codex CLI, plus a default-off
  `operator_codex_pilot` path through a separate peer-UID executor. Keys and
  OAuth state are not persisted by FastAPI, and no provider falls back.
- Requires `gpt-5.5`, `service_tier="fast"`, and Fast mode on every Codex turn.
  Model/tier rejection fails honestly with no model or
  standard-tier fallback.
- Derives conservative accessed-source coverage, agent tool trace, snapshot
  size, and provider/model/tier provenance from actual backend execution;
  inspection alone adds no row coverage, SQL keeps returned rows separate,
  arbitrary Python records full-snapshot scope, and the model owns only reply,
  uncertainty, and safety.
- Streams safe lifecycle activity and supports cancellation without showing
  hidden reasoning. Temporary snapshot, scripts, plots, and workspaces are
  removed after every terminal path.
- Keeps compatible V1-V3 response history and legacy context/memory routes
  readable while current Flutter uses request/response/capability/history V4.
  The newest legacy fixed-mode provenance pair remains
  `controlled-coach-prompt-v3`/`coach-context-v3`.
- Adds database follow-up guards for exact provider-call safety provenance,
  owner-first Coach lock order, backend-owned profile identity and onboarding
  eligibility, canonical-only role authority, V4 evidence/trace/tier truth,
  pre-stream admission, and durable operator dispatch accounting.

Current evaluation boundary:

- Does Coach answer from actual current state and disclose uncertainty?
- Can it challenge a false premise and explain empty or sparse data?
- Do actual evidence and tool steps reconcile with the snapshot and trace?
- Can SQL/Python/prompt injection reach no mutation, network, secret, or host
  authority?
- Are all state-changing suggestions plain text and explicitly non-executable?
- Does Coach add value beyond the existing briefing instead of restating it?
- Do OpenAI/Gemini BYOK, private local Codex, and Project Coach each expose only
  their declared tools and preserve the no-fallback/key-retention boundary?
- Can two Linux developers use their own eligible Codex logins without copying
  credentials while disabled/login/model/Fast/image failures remain honest?

The exact provider, context, subprocess, retention, safety, UI, verification,
and acceptance contract is fixed in
`docs/phase-10-controlled-coach-plan.md`. Standard verification uses the fake
provider. A valid current live claim requires a newly recorded multi-tool turn
that reports `gpt-5.5` with Fast configured; earlier fixed-context live results
do not verify the free-agent snapshot/MCP path. No local result proves another
account, remote state, or production readiness.

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

The capability-truth and plain-language polish batches are implemented in
their owning notification, UI-copy, Setup-retirement, Coach, and visual
contracts. Today Overview V2, central Planner V1, and Study Setup V1 are also
implemented. The next product slice must come from a newly verified need or the
still-unrun moderated student study; this historical phase plan does not
nominate another feature by default.

**Phase 0A, Phase 0B, Phase 0C, Phase 1, Phase 2, and Phase 3 are complete.**
Real and demo source states remain distinct; Setup is revision-safe and
atomically reconciled; Evening/Morning provide exact ownership-merged context;
and the backend turns trusted current capture state into freshness, quality,
recovery-first Daily Mode, bounded risks/reasons, evidence, and provenance.
Tasks, Habit V1, focus sessions, and strict executable action targets now have
durable and recoverable contracts, including exact ambiguous-write readback,
locked eligibility, immutable focus history, strict backend action validation, and DST-safe local
dates. Explicit habit/focus facts enrich snapshot summaries without changing
the Phase 2 classifier. Ordinary writes do not rank actions, persist a
briefing, or call an LLM.

Phase 4 is implemented behind the strict `daily-briefing-v2` contract. It
persists one stable row per user/local date, keeps GET read-only, refreshes or
validates Daily State only on deliberate generation, ranks strict executable
targets recovery-first, and carries freshness, provenance, bounded evidence,
and no-LLM attribution.

Phase 5's persisted briefing parser and backend contract remain implemented.
The former Flutter briefing-first card and production-unreachable Phase 3
dispatcher were retired after Today Overview became the current read-only
presentation. Current execution uses the owning Task, Habit, Focus, capture,
and Weekly Review flows directly.

The former Phase 6 generic Recommendation and Decision Feedback stack is
retired. Its tables, routes, Flutter surfaces, ranking inputs, scheduler stage,
and stored Briefing/Weekly/Coach content are removed. Insights still defaults
to one cautious observation with evidence window, confidence/data-quality
state, and optional bounded experiment; analytics remain advanced exploration.

The minimal Phase 7 backend is implemented. The protected scheduled boundary
pins one run instant, selects eligible profiles by local date and
missing/stale/current state, prepares deterministic snapshots and persisted
briefings idempotently, supports bounded `profile_ids`, and isolates per-user
failures. Notification Delivery V1 extends only the local runner with explicit
current-day deterministic generation and a foreground Flutter receipt/banner;
it does not make Dashboard reads generate or prove deployed cron/push delivery.

Phase 8 is implemented with bounded persisted ISO-week facts and explicit
freshness. New or refreshed rows carry `proposals=[]`; historical arrays remain
transport-readable but invisible and non-executable. It does not reconstruct
missing Task or Habit-definition history.

The first bounded Phase 9 integration is implemented as an explicit `.ics`
file import. It remains independent of the standalone product loop, preserves
imported/read-only provenance, reconciles stable identities, and separates
disconnect from local imported-data deletion. It does not make imported events
briefing inputs or user-owned commitments.

Deadline Planner V1 adds a separate explicit preparation loop. It persists the
user's estimate and prior credit, keeps proposed and active revisions distinct,
and creates staged dated app-owned blocks only on deliberate proposal; explicit
confirmation alone makes them active.
Staged blocks are created by deliberate proposal and become active only on
confirmation. Calendar source/availability use remains opt-in and availability
requires a connected current import; focus progress is measured but never
completes the plan. Its verification requirements are defined in
`docs/deadline-planner-v1-contract.md`; source text alone is not a passing run.

Planner V1 adds the central explicit Task/Habit/fixed-commitment planning home
and the additive Today Overview V2 read. Study Setup V1 keeps optional rhythm,
recovery, checklist, and semester facts under revisioned Setup authority and
binds them to planning only under the documented opt-in rules. Neither feature
moves an active reservation or infers missing scheduling input automatically.

Phase 10 is implemented as an authenticated, budgeted, free-question,
source-aware read-only data agent. It uses a fresh bounded owner-only snapshot,
provider-scoped read-only tools, backend-derived conservative source
coverage/trace, and validated V3 history with no executable suggestion. Live
provider calendar sync/writes, product mutation, broad autonomous changes,
deployed/background delivery or scheduling, vector search, automatic memory
extraction, and unbounded snapshots/tools remain separate later concerns. The
real paths are request-scoped OpenAI/Gemini BYOK plus the explicitly enabled
`gpt-5.5` Fast local Codex OAuth development adapter defined in
`docs/phase-10-controlled-coach-plan.md`. Implemented adapters do not establish
hosted release acceptance or universal subscription/model availability.
Select later work from a separately verified user need rather than broadening
Coach automatically.

## Visual presentation

Daily Capture and Today presentation use the shared
[Frontend Visual System V2](frontend-visual-system-v2.md). The visual migration
does not alter capture fields, briefing generation, ranking, copy truth, or the
read/write boundary described in this plan.

Their feature adapters delegate optional explanatory text to the shared core
information disclosure. Today, Morning, and Evening now share a real 44×44
hit/focus/semantics target around the visible 24×24 information frame and
20×20 icon. The separate Daily Capture choice-info control uses the same
geometry without changing its selection. The five independent sleep
explanations remain closed initially. Save failures use provider-neutral copy,
keep the complete draft, and do not expose storage or transport configuration.
Consent, validation, step progress, and the final save authority remain visible
and unchanged.
