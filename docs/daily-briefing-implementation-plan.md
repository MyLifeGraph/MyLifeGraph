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

## Current Foundation

The repository already contains most of the foundation needed for this slice:

- Structured onboarding through Intake V1.
- Canonical Supabase tables for logs, events, tasks, goals, habits, schedule
  items, recommendations, and user state snapshots.
- Deterministic `daily` and `weekly` snapshot generation in FastAPI.
- Deterministic recommendation generation and persistence.
- Best-effort snapshot refresh after key Supabase-backed writes.
- A backend-only scheduled daily refresh endpoint for cron-style execution.
- Flutter dashboard, check-in, quick mood, habit management, recommendation
  refresh, insights, and mock/guest paths.

The gap is not broad AI integration. The gap is turning these primitives into a
coherent daily product loop:

```text
lightweight capture
  -> compact daily state
  -> ranked daily mode and next actions
  -> user feedback
  -> better decisions tomorrow
```

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

Output:

- A rough next-day preview, clearly labeled as provisional.
- Example: "Tomorrow looks like a steady day. Keep one focus block and one
  small goal action. If sleep is poor, downgrade the second focus block."

### Morning Calibration

Goal: adjust the provisional evening plan based on sleep, current energy, and
day shape.

Reasoning:

- Sleep and current readiness are not known at evening shutdown.
- Morning capture must be short or it becomes a source of friction.
- This is where the app should finalize the daily mode.

Target effort: 10 to 20 seconds.

Required fields:

- Sleep quality or sleep hours.
- Current energy.
- Day shape: normal, constrained, or flexible.

Output:

- Final daily mode.
- Ranked top action.
- Adjusted capacity estimate.

### During The Day

Goal: collect signals passively through actions the user already takes.

Reasoning:

- Midday forms are easy to ignore.
- Task updates, habit completions, focus sessions, quick mood check-ins, and
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

## Required Backend Product Capability

### Daily Briefing Service

Add a FastAPI-owned service that turns snapshots and recommendations into one
ranked daily briefing.

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
- readiness_score numeric
- capacity_minutes int
- summary text
- top_recommendation_ids uuid[]
- evidence_refs jsonb
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

### Evening Shutdown Flow

Build or refactor a quick action for closing the day.

Must support:

- Energy.
- Mood.
- Stress intensity.
- Stress source.
- Stress controllability.
- Focus band.
- Main friction chip.
- Tomorrow priority selection.
- Optional reflection.
- Provisional tomorrow preview.

Reasoning:

- This is the main daily data capture moment.
- It should feel like confirming reality, not filling a form.

### Morning Calibration Flow

Add a short morning calibration surface.

Must support:

- Sleep quality or hours.
- Current energy.
- Day shape.
- Final daily mode.
- Top action.

Reasoning:

- Morning readiness can invalidate the evening plan.
- The user should never need to re-plan the whole day from scratch.

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

## Data Model Changes

Phase 1 can reuse existing tables by storing the new stress fields in
`daily_logs.metadata` and mirrored `behavioral_events.metadata`.

Suggested metadata shape:

```json
{
  "stress": {
    "intensity_label": "high",
    "source": "private_emotional",
    "controllability": "hardly_controllable",
    "gentle_tomorrow": true
  }
}
```

Reasoning:

- This avoids premature schema churn while validating the product model.
- `daily_logs.stress_level` remains available for existing analytics.

Add dedicated columns later only if the fields become stable and heavily
queried:

- `stress_source`
- `stress_controllability`
- `stress_intensity_label`

Add `recommendation_feedback` only when feedback needs history beyond the
current recommendation `status`.

Suggested future table:

```text
recommendation_feedback
- id uuid primary key
- user_id uuid references profiles(id)
- recommendation_id uuid references recommendations(id)
- feedback_type text
- metadata jsonb
- created_at timestamptz
```

## Implementation Phases

### Phase 0: Product Contract

Goal:

- Define the daily briefing contract before changing broad UI or schema.

Work:

- Add domain models for daily mode, stress taxonomy, and briefing payload.
- Document API shapes and mock data expectations.
- Decide whether the first slice stores briefings in a new table or derives
  them from snapshots and recommendations.

Evaluation:

- Can a developer explain exactly what the briefing returns?
- Can the UI be mocked without a backend?
- Are guest and real-backend behavior both defined?

### Phase 1: Lightweight Capture

Goal:

- Capture the minimum signals needed for good daily decisions.

Work:

- Extend daily/evening check-in UX with stress source and controllability.
- Add morning calibration UX.
- Store new fields in metadata and behavioral events.
- Keep existing numeric stress, energy, mood, and focus fields compatible.

Evaluation:

- Can a user complete evening shutdown in under 90 seconds?
- Can morning calibration complete in under 20 seconds?
- Are private/emotional and low-control stress cases captured distinctly?
- Are tests covering mock/guest and Supabase-backed writes?

### Phase 2: Daily State Enhancement

Goal:

- Make snapshots aware of daily mode inputs.

Work:

- Extend snapshot aggregation with stress taxonomy summaries.
- Add risk flags for private/emotional stress, avoidable pressure,
  low-control stress, overload, and recovery risk.
- Add a deterministic daily mode classifier.

Evaluation:

- Do snapshots explain why a user is in push, steady, recover, or plan mode?
- Do tests cover each mode?
- Does high private/emotional stress reliably avoid productivity-heavy output?

### Phase 3: Briefing Service

Goal:

- Generate a single daily briefing from snapshots and ranked recommendations.

Work:

- Add `daily_briefings` migration if persistence is selected.
- Add repository, models, and FastAPI routes.
- Generate or refresh daily snapshot before briefing generation.
- Rank recommendation candidates into one primary action and limited secondary
  actions.
- Keep LLM wording disabled.

Evaluation:

- `GET /v1/briefings/today` does not generate by surprise.
- `POST /v1/briefings/generate` is deliberate and authenticated.
- Scheduled refresh can precompute briefings.
- Browser E2E can assert a persisted briefing after onboarding/check-in.

### Phase 4: Decision-First Dashboard

Goal:

- Make the first dashboard screen the daily operating cockpit.

Work:

- Show daily mode, top action, reason, and capacity/risk note above metrics.
- Move secondary recommendations below the primary action.
- Add clear feedback controls.
- Preserve current recommendation refresh behavior as a deliberate action.

Evaluation:

- First viewport answers "What should I do now?"
- No more than three primary decisions are shown.
- Feedback is possible without opening another form.
- Text fits on mobile and desktop.

### Phase 5: Feedback Loop

Goal:

- Use recommendation outcomes to improve future ranking.

Work:

- Persist feedback events.
- Include recent feedback in ranking.
- Deprioritize advice repeatedly marked as not helpful or too much.
- Promote recommendation types that are completed or accepted.

Evaluation:

- Repeated negative feedback changes future recommendations.
- Feedback does not erase evidence or corrupt recommendation history.
- Ranking remains explainable.

### Phase 6: Scheduled Daily Preparation

Goal:

- Make the app feel prepared when the user opens it in the morning.

Work:

- Wire deployed cron/job execution to the existing scheduled refresh foundation.
- Generate daily snapshots and briefings for onboarded non-guest profiles.
- Define refresh policy for evening shutdown, morning calibration, and
  significant daytime updates.

Evaluation:

- Morning dashboard usually has a fresh briefing without manual refresh.
- Scheduler failures are isolated per user.
- No LLM calls happen during scheduled deterministic refresh.

## Evaluation Checklist For Next Work

Before implementing a proposed slice, answer:

- Does this improve the daily decision loop?
- Does it reduce or preserve capture friction?
- Can it work without LLM usage?
- Can it work without calendar import or wearables?
- Does it preserve guest/mock mode?
- Does it distinguish private/emotional stress from workload stress?
- Does it handle low-control stress with lower load instead of pressure?
- Can the output be explained with evidence refs or snapshot signals?
- Can it be tested in Flutter widget tests, FastAPI tests, or browser E2E?
- Does it require schema changes, and if so, are docs and migrations included?

## Initial Recommendation

The next implementation slice should be Phase 1 plus the smallest part of Phase
2:

1. Add stress source and controllability to the daily/evening check-in path.
2. Add a short morning calibration path or mockable model if the UI scope is too
   large.
3. Persist the new fields in metadata without adding columns yet.
4. Extend snapshot aggregation to summarize the new stress dimensions.
5. Add tests proving private/emotional low-control stress leads to recovery or
   gentle planning signals.

Reasoning:

- This creates the most important missing signal before building a new briefing
  table.
- It is low-risk because it can use existing tables and metadata.
- It directly improves recommendation quality.
- It validates whether users can provide richer context without making capture
  feel heavy.
