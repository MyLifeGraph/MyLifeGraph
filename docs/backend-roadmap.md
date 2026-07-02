# Backend Roadmap

This document is the source of truth for the intended backend flow and the next
implementation sequence. It describes the target product architecture, the
background service roles, the data model direction, and how to keep LLM usage
low enough for multiple users.

## Product Goal

MyLifeGraph should become a personal coaching app that can start with a small
guided intake, learn from daily use, and produce useful recommendations without
calling an LLM for every screen load.

The backend direction is:

```text
Flutter app
  -> Supabase Auth
  -> Supabase Postgres for user-owned records
  -> FastAPI AI service for privileged and intelligence workflows
       -> deterministic services first
       -> optional job workers
       -> LLM provider only behind budgeted service boundaries
```

Flutter may write simple user-owned records directly through Supabase RLS:
profiles, check-ins, tasks, goals, habits, schedule items, notifications, and
coach messages. FastAPI owns workflows that need service-role access,
aggregation, generation, verification, cross-table reasoning, or any LLM call.

## Current Backend State

Already implemented:

- Supabase Auth and canonical snake_case app tables.
- Flutter mock and guest mode.
- Flutter Supabase-backed auth, onboarding, dashboard, notifications, check-ins,
  and coach-message persistence.
- FastAPI `/v1/health`.
- FastAPI authenticated recommendation endpoints:
  - `GET /v1/recommendations`
  - `POST /v1/recommendations/generate`
- Supabase bearer token verification in FastAPI when backend Supabase settings
  are configured.
- Deterministic recommendation generation from `daily_logs`,
  `behavioral_events`, and `tasks`.
- Recommendation verification, dedupe fingerprints, freshness checks, and
  persistence to `recommendations`.
- Flutter reads persisted recommendations through FastAPI in real backend mode
  and falls back to mock data for guest, mock, missing session, or network
  failure.
- `POST /v1/intake/complete`.
- Intake V1 without LLM:
  - `intake_responses` and `user_state_snapshots`.
  - Authenticated backend intake completion derived from the verified bearer
    token.
  - Structured Flutter onboarding with guest/mock preservation.
  - Initial goals, habits, schedule items, notification preferences, and durable
    memory entries from explicit structured answers.

Not yet implemented:

- A production background job queue or worker.
- Explicit recommendation refresh/generate UX.
- Recommendation generation triggered directly by intake completion.
- Real coach-response backend.
- LLM provider integration.
- Memory extraction beyond current direct writes.
- Weekly planning and weekly review.
- Calendar import.

## Architectural Principles

- Keep Supabase as the source of truth for auth and user-owned data.
- Keep the Supabase service-role key only in backend environments.
- Derive `user_id` on the backend from a verified Supabase bearer token.
- Never trust request-provided `user_id`.
- Use RLS on every exposed Supabase table.
- Prefer deterministic rules, cached summaries, and explicit jobs over live LLM
  calls.
- Never call an LLM on dashboard load.
- Never send full user history to an LLM.
- Calendar import is optional. It improves coaching quality, but it must not be
  required to start using the product.
- New backend work should preserve mock and guest mode.

## Target Backend Services

These are "agents" in the product sense. Implement them as explicit services,
repositories, and jobs, not as unconstrained autonomous LLM loops.

| Service | Trigger | Reads | Writes | LLM use |
| --- | --- | --- | --- | --- |
| Intake service | First completed onboarding | Intake payload, profile | `intake_responses`, `profiles`, `goals`, `habits`, `schedule_items`, `notification_preferences`, `memory_entries`, `user_state_snapshots` | None for v1 |
| Signal aggregator | Intake, daily check-in, task/habit changes, scheduled jobs | `daily_logs`, `behavioral_events`, `tasks`, `goals`, `habits`, `schedule_items`, `memory_entries` | `user_state_snapshots`, optional `ai_insights` | None by default |
| Recommendation service | Intake complete, explicit refresh, scheduled refresh | `user_state_snapshots`, `daily_logs`, `behavioral_events`, `tasks`, existing `recommendations` | `recommendations` | Optional wording only later |
| Recommendation verifier | Every generated recommendation | Candidate metadata, active recommendations | Accept/reject result | None |
| Coach service | User sends coach message | Recent messages, snapshots, selected memory | `coach_messages`, optional memory candidates | Yes, budgeted |
| Memory service | Check-ins, coach conversations, weekly review | Raw notes/messages, existing memory | `memory_entries` | Optional extraction only |
| Planning service | Weekly review, user request | Goals, tasks, habits, schedule, snapshots | `tasks`, `schedule_items`, `recommendations`, `coach_messages` | Optional for complex plans |
| Notification service | Schedule and event changes | Preferences, recommendations, deadlines | `notifications` | None |

The intake and snapshot foundation now exists. Next backend work should wire
controlled recommendation refresh after intake and add a recurring signal
aggregator before coach, memory extraction, weekly planning, or LLM provider
work.

## User Start Flow

The user should not start with an empty dashboard and should not be forced to
connect a calendar. The intended first-run flow is:

1. Register, sign in, or continue as guest.
2. Complete a guided 5-minute intake.
3. Pick 1 to 3 goal areas.
4. Add optional habits or routines.
5. Set basic reminder preferences.
6. Optionally connect a calendar later.
7. Land on the dashboard with first recommendations or first next actions.

### Intake Questions

Use structured answers rather than free text wherever possible.

Required fields:

- Primary focus areas: `focus`, `energy`, `sleep`, `stress`, `planning`,
  `movement`.
- Top 1 to 3 goals.
- Current friction points.
- Typical weekday shape.
- Best energy window.
- Desired coaching style: direct, gentle, analytical, accountability-focused.
- Reminder preference and quiet hours.

Optional fields:

- Existing habits.
- Known fixed commitments.
- Free-form context note.
- Calendar connection intent.

### Calendar Policy

Calendar import is a quality booster, not an onboarding gate.

Implement later as:

- Optional connection after the first useful dashboard.
- Read/import into canonical schedule/calendar tables.
- User-visible controls for disconnecting and deleting imported data.
- No LLM processing of calendar content by default.

If calendar support is added, prefer dedicated tables such as
`calendar_connections` and `calendar_events` instead of overloading
`schedule_items` with provider sync state. `schedule_items` can still represent
stable user routines and app-authored planned blocks.

## Data Model Direction

The current canonical schema already has useful tables:

- `profiles`
- `daily_logs`
- `behavioral_events`
- `tasks`
- `schedule_items`
- `notifications`
- `coach_messages`
- `memory_entries`
- `ai_insights`
- `recommendations`
- `skillset_profiles`
- `notification_preferences`
- `goals`, `habits`, `habit_logs`, `focus_sessions`

The Intake V1 backend slice added the minimum missing state:

### `intake_responses`

Purpose: preserve the user's structured first-run answers and support future
schema versions without losing original intake context.

Implemented columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references profiles(id) on delete cascade`
- `version text not null default 'intake-v1'`
- `responses jsonb not null`
- `completed_at timestamptz not null default now()`
- `metadata jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`

Access:

- User can read own rows.
- User should not update old intake history directly.
- Backend service-role can insert after token verification.

### `user_state_snapshots`

Purpose: store compact user state that recommendation, coach, planning, and
memory flows can use without reading full history or building huge prompts.

Implemented columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references profiles(id) on delete cascade`
- `scope text not null check (scope in ('onboarding', 'daily', 'weekly'))`
- `period_key text not null`
- `summary jsonb not null`
- `signals jsonb not null default '{}'::jsonb`
- `source text not null default 'backend'`
- `generated_at timestamptz not null default now()`
- `metadata jsonb not null default '{}'::jsonb`

Indexes:

- `(user_id, scope, generated_at desc)`
- `(user_id, period_key)`

Access:

- User can read own snapshots if the UI needs them.
- Writes should be backend-owned.

### Later Tables

Do not add these in the first slice unless the implementation genuinely needs
them:

- `backend_jobs` for durable idempotent jobs and retries.
- `llm_usage_events` for per-user budget tracking.
- `calendar_connections` and `calendar_events` for provider sync.
- `memory_candidates` if memory extraction needs review before promotion to
  `memory_entries`.

## Intake Completion Flow

Target endpoint:

```text
POST /v1/intake/complete
Authorization: Bearer <supabase_access_token>
```

Backend behavior:

1. Verify the bearer token through the existing FastAPI auth dependency.
2. Derive `user_id` from the verified principal.
3. Validate the intake payload with strict Pydantic models.
4. Insert one `intake_responses` row.
5. Upsert `profiles.onboarding_completed_at`.
6. Upsert initial `notification_preferences`.
7. Create `goals` from selected goals.
8. Create `habits` only for explicit user-selected habits.
9. Create `schedule_items` only for stable routines or fixed commitments.
10. Create a small number of `memory_entries` for durable preferences and goals.
11. Create an `onboarding` `user_state_snapshots` row.
12. Return the created snapshot summary and an empty recommendation list for
    now.

No LLM is required for v1 intake. If free text exists, store it as source
context and use deterministic categories first.

## Recommendation Flow

Current recommendation v1 already exists. The target flow after intake is:

1. User completes intake.
2. Backend creates a user state snapshot.
3. Recommendation service loads the snapshot plus recent user-owned rows.
4. Deterministic rules produce candidates.
5. Verifier rejects weak, duplicate, stale, invalid, or cross-user candidates.
6. Accepted recommendations are persisted.
7. Flutter reads them through `GET /v1/recommendations`.

The explicit generate UX should later call:

```text
POST /v1/recommendations/generate
```

Keep this as a deliberate action or controlled workflow. Do not call it on
every dashboard load.

## Coach Flow

Target endpoint, not implemented yet:

```text
POST /v1/coach/respond
Authorization: Bearer <supabase_access_token>
```

Target behavior:

1. Store the user message in `coach_messages`.
2. Build a compact context from:
   - recent `coach_messages`
   - latest `user_state_snapshots`
   - selected `memory_entries`
   - relevant active `recommendations`
3. Decide if a deterministic response is enough.
4. Call an LLM only when natural-language reasoning is needed.
5. Store the assistant response in `coach_messages`.
6. Optionally emit memory candidates, not direct high-confidence memory.

This should come after intake and recommendation refresh, because the coach
needs structured context to be useful and affordable.

## LLM Cost Control

Use these rules before adding any model provider:

- No LLM calls on dashboard load.
- No LLM calls for simple CRUD, check-ins, or deterministic recommendations.
- No full-history prompts.
- Build and reuse `user_state_snapshots`.
- Limit coach context to the latest compact snapshot, selected memories, and a
  small message window.
- Use idempotency keys for jobs that could retry.
- Track LLM usage per user before enabling broad access.
- Prefer small/cheap models for wording and extraction.
- Use larger models only for complex coach or weekly planning tasks.
- Cache or persist generated outputs.
- Add feature flags for every LLM-backed path.

## Immediate Implementation Plan

The next implementation should build on **Intake V1 without LLM**.

### Slice 1: Controlled Recommendation Refresh

- Trigger deterministic recommendation generation after explicit intake
  completion or behind a deliberate refresh action.
- Reuse existing recommendation verification and persistence.
- Avoid auto-generating on normal dashboard reads.
- Add tests that verify intake-derived snapshots can be used without trusting
  request-provided user IDs.

### Slice 2: Snapshot Aggregator

- Add a deterministic service that can create `daily` and `weekly`
  `user_state_snapshots` from recent check-ins, tasks, goals, habits, schedule
  items, and memory entries.
- Keep snapshots compact and avoid reading full user history for every request.
- Add backend tests for stale/missing data and user scoping.

### Slice 3: E2E Expansion

- Extend browser E2E to cover structured intake fields and persisted
  Supabase-backed rows when the AI service is part of the test run.
- Keep the current guest/mock widget smoke fast.
- Add FastAPI startup to E2E only when backend API behavior is asserted end to
  end.

## Out Of Scope For The Next Slice

- OpenAI/OpenRouter/local LLM integration.
- Real coach assistant replies.
- Calendar provider connection.
- Weekly planning or review.
- Vector search.
- Background workers unless implementation cannot stay simple without them.
- Remote production database claims without direct inspection.
