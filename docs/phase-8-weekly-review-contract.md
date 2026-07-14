# Phase 8 Weekly Review Contract

Status: implementation contract for the bounded deterministic Phase 8 weekly
review. This contract builds on the Phase 3 Habit V1 command and recovery
semantics. It is not an autonomous planning contract.

## Scope

Phase 8 turns one explicit, completed profile-local ISO week into a short,
persisted review. It summarizes only durable facts, produces at most two
deterministic proposals, and leaves every user-owned goal, habit, task, and
schedule row unchanged until the user explicitly confirms an already supported
command.

The initial directly applicable proposal surface is deliberately narrow:

- `shrink`, `pause`, or `archive` one manually managed Habit V1 definition;
- apply through the existing owner-scoped Flutter Habit V1 data source;
- require the proposal's exact target `updated_at` before the change;
- use the existing exact requested-field/timestamp readback if the committed
  Supabase response is lost.

`keep` is an explanatory non-interactive note and makes no change. `replace`
and `defer` remain non-interactive staged suggestions on this surface.
Setup-owned habits and goals deep-link to Settings Setup with explicit no-auto-
apply copy and without a generic write. Goal, task, schedule, and replacement
mutations remain unavailable until each has a typed, atomic or otherwise
recoverable command.

Phase 8 does not add an LLM, Coach, calendar integration, notification,
background worker, deployed weekly schedule, or autonomous plan rewrite.

## Period Identity

The review period is an explicit completed ISO week in the profile's stored IANA
timezone:

- `period_key`: exact `IYYY-Www`, for example `2026-W28`;
- `week_start`: the ISO Monday;
- `week_end`: exactly six calendar days later;
- `timezone`: the IANA timezone used to resolve timestamp-backed facts.

Timestamp-backed task, feedback, and focus inputs use the profile-local Monday
start and following-Monday exclusive boundary converted to UTC. Date-backed
habit outcomes and daily snapshots use the exact seven local calendar dates.
The service must handle ISO-year and daylight-saving boundaries without using
server-local `date.today()`.

The endpoint rejects a malformed period, a non-ISO-week identity, or a week
that is not the latest completed week in the profile timezone. V1 deliberately
does not expose arbitrary review-history generation. A request never accepts
`user_id`; FastAPI derives the owner from the verified bearer principal.

## HTTP Boundary

```text
GET  /v1/weekly-reviews/{period_key}
GET  /v1/weekly-reviews/latest
POST /v1/weekly-reviews/generate
Authorization: Bearer <supabase_access_token>
```

Both `GET` routes are read-only. `latest` resolves the newest completed ISO week
in the profile timezone and is the Flutter entry point; the period route accepts
that same explicit V1 identity for stable rereads. They report `not_ready`,
`missing`, `current`, or `stale` and never
persists a review or changes a user-owned record.

`POST` accepts exactly:

```json
{
  "period_key": "2026-W28",
  "force": false
}
```

`force=false` returns an already-current review unchanged. Missing or stale
output is generated on the same `(user_id, period_key)` identity. `force=true`
deliberately recomputes that same identity. Generation persists derived review
output only; it never applies a proposal or changes a user-owned record.

Both routes return the same strict envelope:

```text
contract_version: weekly-review-v1
period_key
starts_on
ends_on
timezone
freshness: not_ready | missing | current | stale
needs_generation
stale_reasons: bounded machine-stable codes
review: WeeklyReview | null
```

`WeeklyReview` contains the stable id, `data_quality`, one
bounded narrative, structured facts, no more than two proposals, bounded
evidence, deterministic provenance, and generation/update timestamps.

## Persistence

`weekly_reviews` is backend-owned derived output:

- unique `(user_id, period_key)` identity;
- authenticated owners and admins may select;
- authenticated clients cannot insert, update, or delete;
- service role owns writes;
- RLS is enabled and forced.

Database checks require an exact ISO period/week match, a Monday-to-Sunday
window, a non-empty bounded timezone and narrative, known data quality, bounded
JSON objects/arrays, at most two proposals, at most 40 evidence references, and
a lowercase 64-character hexadecimal source fingerprint.

## Fact Semantics

The review uses one canonical, stably ordered, fully paginated fact load. A
repository must never treat a server-capped first page as the complete week.
The canonical source fingerprint covers only the fields used by the review and
is stored both in the table column and provenance.

The strict fact object contains exactly these nonnegative counters:

- `tasks`: `completed`, `carried`, `overdue_carried`, `cancelled`,
  `goal_linked_completed`;
- `habits`: `active`, `paused`, `archived`, `stable_definitions`,
  `changed_definitions`, `scheduled_opportunities`, `completed`, `skipped`,
  `missed`, `recovery_open`, `unknown`;
- `focus`: `completed_sessions`, `abandoned_sessions`, `active_sessions`,
  `actual_minutes`;
- `recovery`: `observed_days`, `recovery_days`, each bounded by seven;
- `feedback`: `total`, `done`, `later`, `not_helpful`, `too_much`,
  `does_not_fit`.

### Tasks And Goal Actions

- A completed task is a currently terminal `done` row whose authoritative
  `completed_at` falls inside the profile-local week.
- A carried task means only that the current durable row was open at the end of
  the reviewed week. It is not a claim that the user postponed or ignored it.
- A task completion that was later restored is absent from current durable
  terminal evidence and cannot be reconstructed.
- Goal-action attribution is accepted only when bounded task metadata points to
  a goal owned by the same user. Metadata alone is not trusted as ownership.
- There is no Phase 8 task-transition or goal-history reconstruction.

### Habit Opportunities

Habit facts keep these states separate:

- scheduled opportunity;
- explicit `completed` outcome;
- explicit intentional `skipped` outcome;
- elapsed scheduled opportunity with no row (`missed`);
- unknown opportunity where a stable cadence yields a countable slot but its
  Daily State evidence is missing;
- overlap with a valid persisted recovery day.

A definition changed during or after the week is reported separately through
`changed_definitions`. Because the former cadence/lifecycle is unavailable, the
review does not invent a numeric opportunity count for that definition.

Daily and selected-weekday cadence partitions stable elapsed scheduled dates.
For `weekly_target`, completions and explicit skip dates remain separate from
the remaining target units; the service must not invent an exact scheduled day
for a flexible weekly slot.

The current habit row cannot reconstruct an earlier cadence or pause/archive
instant. A definition changed during or after the reviewed period is marked
unknown for affected opportunity math and is not eligible for an automatic
adaptation proposal. Legacy `started_on` fallback is resolved consistently in
the profile timezone.

Recovery overlap never fabricates a completion or erases an intentional skip.
It is separate explanatory evidence and prevents punitive proposal wording.

### Focus, Recovery, And Feedback

- Focus uses the persisted local `metadata.entry_date`, with the existing UTC
  `started_at` fallback only for legacy or invalid metadata.
- A recovery day is counted only from a valid persisted daily snapshot whose
  strict `explainable-daily-state-v1` target date matches that local day and
  whose mode is `recover`.
- Missing daily snapshots remain missing evidence; averages do not fabricate a
  recovery day.
- Decision feedback is historical preference evidence. `feedback_type=done`
  never substitutes for a task, habit, or focus outcome.

`data_quality` is `insufficient`, `partial`, or `sufficient`; it is distinct
from review freshness. Missing coverage and every known limitation remain
visible in structured facts and provenance.

## Proposal Contract

Every proposal has a stable deterministic id, an operation, user-visible title
and reason, target identity, application mode, exact expected target timestamp,
bounded evidence, and an explicit before/after change:

```json
{
  "before": {
    "lifecycle": "active",
    "cadence": {
      "kind": "weekly_target",
      "weekly_target": 4,
      "scheduled_weekdays": []
    }
  },
  "after": {
    "lifecycle": "active",
    "cadence": {
      "kind": "weekly_target",
      "weekly_target": 3,
      "scheduled_weekdays": []
    }
  }
}
```

Nullable cadence fields remain present in the strict JSON contract. `after` may
be null only for a staged-only `replace` or `defer` proposal. `keep` has equal
before and after state.

Direct manual-habit application requires all of the following:

- `application_mode=direct_habit`;
- an active, manually managed owned Habit V1 target;
- unchanged `expected_updated_at`;
- a complete valid before/after Habit V1 shape;
- explicit user confirmation in a before/after dialog.

Cancel performs no write. On confirmation, Flutter reuses the Phase 3 typed
habit edit/lifecycle command; the review API does not mutate the habit. A stale
target is a conflict, not permission to overwrite. An ambiguous committed
response succeeds only after the existing exact owner-scoped requested-field
and mutation-timestamp readback.

Setup-owned targets use `application_mode=settings_setup`. Staged proposals use
`application_mode=staged_only`. Neither path may call the generic manual Habit
V1 updater. Flutter renders staged-only and `keep` rows without an action
control; their authority label states that Weekly Review cannot execute them.

One initial deterministic shrink rule may propose reducing a stable manual
weekly target by one when the week has full valid daily-state coverage, exactly
bounded durable outcomes, and matching recent `too_much` feedback for the real
habit action. Misses alone must not be interpreted as consent to reduce a
cadence.

## Freshness

Generation stores a SHA-256 fingerprint of the canonical source facts. `GET`
recomputes that fingerprint without writing:

- equal fingerprint: `current`;
- changed source facts or target definition: `stale` with bounded reason codes;
- no persisted row: `missing`.

Habit application, outcome correction, feedback deletion, task state change,
or valid daily-state replacement can therefore make a review stale. Stale facts
remain visible but proposal controls are disabled until a deliberate refresh.

## Executable Action Boundary

Phase 8 gives `review_plan` a real bounded surface. The strict
`executable-action-v1` shape is unchanged: a planning/review target may navigate
an authenticated real-data user to `/weekly-review`. The dispatcher calls a
typed injected handler and propagates failures. Guest/mock and unavailable
synced sessions remain explicitly unavailable. Dispatching `review_plan` opens
the review; it never generates, confirms, or applies a proposal by itself.

## Verification Contract

Focused backend, Flutter, migration, and browser coverage must prove:

- profile-local ISO-week and DST boundaries;
- strict model parsing and owner-derived identity;
- read-only GET and idempotent same-row POST;
- exact completed, carried, completed/skipped/missed/unknown, focus, recovery,
  and feedback facts;
- fully paginated stable source reads;
- deterministic proposal cap, ordering, and evidence;
- source change to stale transition;
- confirmation cancel with zero writes;
- exact manual Habit V1 application and response-loss reconciliation;
- Setup deep-link with zero direct target writes;
- guest/mock isolation;
- authenticated owner-only review reads and rejection of direct review writes.

Documentation or source assertions do not establish an E2E pass. Run the
current-checkout browser command before claiming the Phase 8 journey passed.
