# Phase 8 Weekly Review Contract

Status: current implementation contract for the bounded, deterministic, and
strictly observational Weekly Review. It is not an autonomous planning or Habit
adaptation contract.

## Scope

Weekly Review turns one explicit, completed profile-local ISO week into a short
persisted account of durable facts. It never loads Goals, produces a new
proposal, applies an action, or changes a user-owned Task, Habit, schedule,
calendar, or plan.

The current contract is `weekly-review-v3`. Every generated or refreshed review
stores `proposals=[]`; Flutter renders no proposal controls. The Recommendation
and Decision Feedback retirement erases pre-cutover review content, so no old
Feedback facts or proposal prose crosses into the current review or Coach
context.

Weekly Review does not add an LLM, notification, background worker, deployed
weekly schedule, or autonomous plan rewrite.

## Period Identity

The review period is an explicit completed ISO week in the profile's stored IANA
timezone:

- `period_key`: exact `IYYY-Www`, for example `2026-W28`;
- `week_start`: the ISO Monday;
- `week_end`: exactly six calendar days later;
- `timezone`: the IANA timezone used to resolve timestamp-backed facts.

Timestamp-backed Task and Focus inputs use the profile-local Monday
start and following-Monday exclusive boundary converted to UTC. Date-backed
Habit outcomes and daily snapshots use the exact seven local calendar dates.
The service handles ISO-year and daylight-saving boundaries without using the
server-local date.

The endpoint rejects a malformed period, a non-ISO-week identity, or a week
that is not the latest completed week in the profile timezone. It does not
expose arbitrary review-history generation. A request never accepts `user_id`;
FastAPI derives the owner from the verified bearer principal.

## HTTP Boundary

```text
GET  /v1/weekly-reviews/{period_key}
GET  /v1/weekly-reviews/latest
POST /v1/weekly-reviews/generate
Authorization: Bearer <supabase_access_token>
```

Both `GET` routes are read-only. `latest` resolves the newest completed ISO
week in the profile timezone and is the Flutter entry point. The explicit
period route accepts that same identity for stable rereads. They report
`not_ready`, `missing`, `current`, or `stale` and never persist a review.

`POST` accepts exactly:

```json
{
  "period_key": "2026-W28",
  "force": false
}
```

`force=false` returns an already-current review unchanged. Missing or stale
output is generated on the same `(user_id, period_key)` identity. `force=true`
recomputes that identity. Generation persists derived review output only.

Both routes return the same strict envelope:

```text
contract_version: weekly-review-v3
period_key
starts_on
ends_on
timezone
freshness: not_ready | missing | current | stale
needs_generation
stale_reasons: bounded machine-stable codes
review: WeeklyReview | null
```

`WeeklyReview` contains the stable id, `data_quality`, one bounded narrative,
structured facts, the compatibility `proposals` array, bounded evidence,
deterministic provenance, and generation/update timestamps. A current V3 row
always has an empty proposal array.

## Persistence And Compatibility

`weekly_reviews` is backend-owned derived output:

- unique `(user_id, period_key)` identity;
- authenticated owners and admins may select;
- authenticated clients cannot insert, update, or delete;
- service role owns writes;
- RLS is enabled and forced.

Database checks require an exact ISO period/week match, a Monday-to-Sunday
window, a non-empty bounded timezone and narrative, known data quality, bounded
JSON objects/arrays, an empty proposal array, at most 40 evidence
references, and a lowercase 64-character hexadecimal source fingerprint.

Before P7, the Goal-removal migration updated then-surviving rows in place to V2 while
preserving their id, period, fingerprint, timestamps, and historical proposal
array. It removes `facts.tasks.goal_linked_completed` and updates provenance.
The backend persistence RPC rejects the retired counter and any non-empty
proposal array for a new or refreshed review. At that earlier boundary, a
deliberate refresh replaced a historical proposal array with `[]`.

Additive migration
`20260804192406_harden_goal_removal_dependencies.sql` did not update any
surviving Weekly Review. Before deletion it closed temporary dependency sets
across source snapshots, recommendation/briefing foreign identities, and
`decision_feedback` evidence. A review is retired when its source snapshot or
a referenced feedback row was missing or belonged to the Goal-derived deletion
set. A clean row retains its exact id, period, fingerprint, observation and
persistence timestamps, and historical proposal transport. Final assertions
rejected dangling snapshot/feedback references. The migration took the complete
cleanup table-lock set in alphabetical `SHARE ROW EXCLUSIVE` order with a
five-second timeout, so a concurrent writer causes a full rollback.

Additive migration
`20260813200057_retire_recommendations_and_decision_feedback.sql` deletes the
remaining Weekly Review content, installs the exact V3 facts/provenance checks,
and replaces the V2 writer with service-role-only
`persist_weekly_review_v3`. It preserves RLS/forced RLS and rejects structured
Recommendation or Feedback references without treating ordinary prose as a
reference. Current V3 parsers in FastAPI and Flutter reject every non-empty
proposal list; there is no post-P7 transport compatibility for old proposals.

## Fact Semantics

The review uses one canonical, stably ordered, fully paginated fact load. A
repository must never treat a server-capped first page as the complete week.
The canonical source fingerprint covers only fields used by the review and is
stored both in the table column and provenance.

The strict fact object contains exactly these nonnegative counters:

- `tasks`: `completed`, `carried`, `overdue_carried`, `cancelled`;
- `habits`: `active`, `paused`, `archived`, `stable_definitions`,
  `changed_definitions`, `scheduled_opportunities`, `completed`, `skipped`,
  `missed`, `recovery_open`, `unknown`;
- `focus`: `completed_sessions`, `abandoned_sessions`, `active_sessions`,
  `actual_minutes`;
- `recovery`: `observed_days`, `recovery_days`, each bounded by seven.

### Tasks

- A completed Task is a currently terminal `done` row whose authoritative
  `completed_at` falls inside the profile-local week.
- A carried Task is a current durable row that was open at the end of the
  reviewed week. It is not a claim that the student postponed or ignored it.
- A completion later restored to an open state is absent from current durable
  terminal evidence and cannot be reconstructed.
- Retired Goal metadata is ignored and is not reconstructed as a fact.

### Habit Opportunities

Habit facts keep these states separate:

- scheduled opportunity;
- explicit `completed` outcome;
- explicit intentional `skipped` outcome;
- elapsed scheduled opportunity with no row (`missed`);
- unknown opportunity where a stable cadence yields a countable slot but its
  Daily State evidence is missing;
- overlap with a valid persisted recovery day.

A definition changed during or after the week is reported through
`changed_definitions`. Because the former cadence/lifecycle is unavailable, the
review does not invent a numeric opportunity count for that definition.

Daily and selected-weekday cadence partitions stable elapsed scheduled dates.
For `weekly_target`, completions and explicit skip dates remain separate from
the remaining target units; the service does not invent an exact day for a
flexible weekly slot. Legacy `started_on` fallback is resolved consistently in
the profile timezone.

Recovery overlap never fabricates a completion or erases an intentional skip.
It remains explanatory evidence only.

### Focus And Recovery

- Focus uses persisted local `metadata.entry_date`, with the established UTC
  `started_at` fallback only for legacy or invalid metadata.
- A recovery day is counted only from a valid persisted daily snapshot whose
  historical `explainable-daily-state-v1`/V2 or current
  `explainable-daily-state-v3` target date matches that local day and whose mode
  is `recover`.
- Missing daily snapshots remain missing evidence; averages do not fabricate a
  recovery day.

`data_quality` is `insufficient`, `partial`, or `sufficient`; it is independent
of proposals and distinct from freshness. Missing coverage and every known
limitation remain visible in facts and provenance.

The narrative describes only observed counts, recovery coverage, and known
limitations. Skipped Habits and high or low completion may change reported
facts but never produce adaptation language or an action recommendation.

## Freshness

Generation captures one `source_observed_at` before its first source read.
Repositories use lexicographic keyset pagination with their established sort
fields and `id` as the tie-breaker, excluding rows created or changed after
that boundary. Generation stores a SHA-256 fingerprint of the canonical source
facts. `GET` recomputes that fingerprint without writing:

- equal fingerprint: `current`;
- changed source facts: `stale` with bounded reason codes;
- no persisted row: `missing`.

Habit outcomes, Task state changes, Focus completion, or a
valid Daily State replacement can make a review stale. Stale facts remain
visible. Flutter places the deliberate update action with the facts; there are
no proposal controls.

`persist_weekly_review_v3` takes the owner and review-row locks, requires the
referenced weekly Snapshot still to be current, rejects a candidate observed
before the stored review, and binds exact Snapshot identity and provenance.
After persistence, FastAPI reloads Snapshot, Review, and source context.
`current` is returned only when they still match; a concurrent later fact makes
the result honestly `stale`.

## Executable Action Boundary

The strict `executable-action-v1` shape is unchanged: a `review_plan` target may
navigate an authenticated real-data user to `/weekly-review`. The dispatcher
calls a typed injected handler and propagates failures. Guest/mock and
unavailable synced sessions remain explicitly unavailable. Dispatching the
action only opens the review and never generates, confirms, or applies
anything.

Weekly Review is an in-page destination. The shared Back action pops its actual
pushed origin and falls back to Today for a direct deep link. Navigation alone
never refreshes a review.

## Verification Contract

Focused backend, Flutter, migration, and browser coverage must prove:

- profile-local ISO-week and DST boundaries;
- strict V3 model parsing and owner-derived identity;
- read-only GET and idempotent same-row POST;
- exact completed, carried, completed/skipped/missed/unknown, Focus, and
  recovery facts without the retired Goal counter or Feedback family;
- fully paginated stable source reads;
- no generated proposals for skips or high Habit completion;
- exact rejection of non-empty proposals and retired structured sources;
- retirement-migration erasure of old review content and exactly typed Briefing
  notifications, while current Weekly Review notifications remain intact;
- source-change-to-stale transition and fact refresh;
- missing, stale, retry, error, and guest states;
- authenticated owner-only reads and rejection of direct writes;
- absent Goals schema, policy, grants, Setup parameter, and active data paths.

Documentation or source assertions do not establish an E2E pass. Run the
current-checkout browser command before claiming the journey passed.

Flutter Weekly Review models reuse framework-neutral strict primitives for
exact keys, objects, strings, integers, local dates, and aware timestamps.

## Visual Presentation

Weekly Review uses the shared
[Frontend Visual System V2](frontend-visual-system-v2.md). Facts, freshness,
empty/error/guest states, and the update action remain usable with large text.
No adjustment card, confirmation dialog, or proposal action is displayed. The
review narrative and labelled data quality stay visible; optional methodology
starts closed under `How this review is created`. Current/stale status uses the
shared status pill, stale guidance uses the shared state panel, and fact groups
use shared surfaces. The header stacks without overflow at 320 logical pixels
and 200-percent text. The disclosure never hides stale state or the deliberate
update action.
