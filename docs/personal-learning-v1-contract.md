# Personal Learning V1 Contract

## Purpose

Personal Learning V1 adds a deterministic, user-controlled learning loop around
terminal Focus sessions. A user may reflect on a completed or abandoned session,
inspect transparent non-causal patterns, and separately allow a mature learned
time preference to softly order newly requested planning previews.

This contract does not add an LLM, change Coach, infer a new study rhythm,
change a sleep target or capacity, move a confirmed block, or make a provider
write.

## Contract versions

- `focus-reflection-v1` is the stored per-session reflection contract.
- `learning-preferences-v1` is the revisioned preference contract.
- `personal-patterns-v1` is the read-only evidence contract.

## Focus reflections

`focus_session_reflections` contains at most one current reflection for a Focus
session. Its owner must equal the Focus-session owner and the referenced session
must already be `completed` or `abandoned`.

Each reflection stores:

- `focus_quality` and `useful_progress`, each an integer from 1 through 5;
- zero through two distinct controlled obstacles from `tired`, `distracted`,
  `interrupted`, `unclear_goal`, `material_too_difficult`,
  `session_too_long`, `environment`, and `other`;
- exact contract version and created/updated timestamps.

The reflection is deliberately mutable and deletable. The referenced terminal
Focus session remains immutable. There is no backfill: an old terminal session
without a row is `missing`, never a zero score.

Authenticated owners may read, insert, correct, or delete their own rows through
forced RLS. Cross-owner linkage and rating/reason violations fail at the
database boundary. Guest and demo flows issue no reflection request.

The session transition is always persisted before a prompt opens. A reflection
failure cannot roll back the session transition. For a completed session,
recovery starts before the prompt and continues while it is open. The same
bottom sheet is used by the automatic terminal prompt and by `Rate`/`Edit` in
Focus history. Obstacles are offered only for an abandoned session or when
either rating is low. Active sessions, expired-but-unfinished timers, and
unstarted Planner blocks cannot be rated.

## Learning preferences

Every authenticated account resolves the following full state:

- `focus_reflection_prompt_enabled=true`;
- `personal_pattern_analysis_enabled=true`;
- `learned_focus_planning_enabled=false`;
- a monotone integer `revision`.

Learned Focus planning may be true only while personal pattern analysis is true.
Disabling analysis therefore also disables Planner use in the same atomic
revision.

`GET /v1/learning/preferences` is read-only and lazily returns the default state
when no stored projection exists. `PATCH /v1/learning/preferences` requires a
client `request_id`, the expected current revision, and the complete three-flag
state. The service-role-only database command serializes by owner, binds retry
identity to the full payload, and either applies the next revision or returns an
exact replay. A stale expected revision or reused request identity with a
different payload is a conflict.

`POST /v1/learning/focus-reflections/clear` requires a request id, exact
confirmation text `CLEAR`, and the expected preference revision. It serializes
by owner and returns the same deleted-count result on exact retry. Its backend
ledger is not user history and is omitted from Account Export.

Settings exposes one `Personal learning` entry for these controls and the
confirmed clear action. It does not create another primary navigation item.

## Personal patterns

`GET /v1/insights/personal-patterns` is side-effect free. It uses one captured
UTC instant, the profile IANA timezone, and the closed-open 90-day interval
ending at that instant. It never persists a pattern and never calls a model.
If analysis is disabled, it returns `disabled` before reading Focus or Daily
Capture history.

### Focus evidence

Only terminal sessions in the interval participate. Rated coverage is the
number of valid reflections divided by terminal sessions. The analysis uses:

- fixed local start windows `05–09`, `09–13`, `13–18`, and `18–23`;
- a separate `night` bucket for all other local starts;
- planned and actual minutes;
- the gap from the immediately preceding terminal session, including a
  deterministic under-two-hours group;
- terminal status, both ratings, and controlled obstacles.

Night sessions remain visible evidence but can never become the Planner
preference.

### Sleep and energy evidence

All consumers use the shared strict Daily Capture V4 parser. A Focus session may
use a valid V4 Morning sleep episode only when the episode `entry_date` equals
the session's profile-local start date and `woke_at` is no later than the
session start. There is no prior-day or 36-hour fallback. A session after
midnight therefore has no sleep values until that calendar day's valid Morning
capture exists. The episode contains estimated duration, explicit target
deviation, sleep quality, and Morning energy only when that capture was recorded
before the session.

For a sleep comparison, multiple sessions linked to the same episode collapse
to one daily observation so a single day cannot be multiplied. An Evening
capture recorded after a session is never treated as preceding evidence.
Sleep copy describes an observed association, not an optimum, diagnosis, or
cause.

### Maturity and learned timing

- Fewer than three rated sessions is `collecting`.
- Three or more exposes medians, completion rate, and coverage.
- `emerging` requires at least 14 ratings and at least five observations in
  every displayed comparison group.
- `stable` requires at least 20 ratings spanning at least 28 local dates.
- A Planner-ready preferred time window additionally requires at least ten
  distinct rated local dates in the window, ten comparator dates, at least 70%
  rated coverage, and the same useful-progress direction in both chronological
  halves.

The preferred group must have a useful-progress median at least 0.5 above its
comparator, a focus-quality median no more than 0.5 below it, and a completion
rate no more than ten percentage points below it. Ties are resolved by the
fixed window order, never by post-hoc bucket creation.

At most three patterns are returned in this order: Focus timing, sleep, then
session length or spacing. The response always includes its sample size,
profile-local date interval, coverage, limitations, and a deterministic
evidence fingerprint.

Insights replaces the generic observation for real accounts with one
`Personal study pattern` card supporting collecting, emerging, stable,
disabled, and error states. Expanded evidence cannot grant Planner authority.
Advanced correlations remain exploratory and use profile-timezone backend
points; unsupported reconstructed Planner and Habit histories are excluded.
Flutter presents target-based sleep as non-negative `Sleep shortfall` while
retaining the signed API property for compatibility. Previous-night sleep,
sleep quality, and Morning energy share the local wake/Focus date. Planned and
actual rated Focus minutes are daily sums; ratings and completion are daily
averages across rated sessions.

Pearson coefficients require seven shared local dates. Seven through thirteen
dates are visibly restrained `Early evidence`; rankings, Top Patterns, and
strong color weighting require at least fourteen. The only signal pairs not
compared are sleep duration with sleep shortfall, and Activity with Steps,
because each pair overlaps. Those cells are neutral, non-selectable, omitted
from rankings and scatterplots, and cannot be selected together in the trend
overlay. The default real-account comparison is Previous-night sleep with
Rated useful progress; demo falls back to Previous-night sleep with Rated focus
time.

Trend copy states that sleep belongs to the local wake/Focus date, Focus values
contain rated sessions only, and every curve is normalized relative to its own
range. A 7-day experiment may appear only for an explicitly allowlisted,
controllable factor-to-outcome pair. Sleep associations and outcome-to-outcome
pairs stay descriptive.
The correlation matrix keeps its row labels fixed while only the data grid
scrolls horizontally. Row and column labels wrap without ellipsis, and their
cells expand with text scaling so the complete metric names remain readable on
desktop and at the supported 320-pixel/200%-text boundary.

## Optional Planner use

Learned timing has two independent gates:

1. the account preference `learned_focus_planning_enabled`; and
2. the deployment feature flag for the pilot.

When both gates are on and the current evidence is Planner-ready, shared
availability softly orders free starts in this sequence:

1. the learned fixed local window;
2. the explicit Setup energy window;
3. the existing remaining fallback windows.

This order never overrides current time, deadline, daily or account budget,
fixed or imported busy time, recovery, confirmed preparation, or another
reservation. A preference may not strand minutes that the ordinary allocator
could place, so all existing fallback candidates remain available.

It applies only while generating a newly requested or explicitly re-requested
Task, Exam, or Assignment preview. Habits, commitments, active revisions, and
confirmed blocks are unchanged. Explicit session duration, Study rhythm, and
recovery remain authoritative.

Planner and Deadline revision provenance records:

- `source` as `setup` or `learned_personal_pattern`;
- the used fixed window, evidence count and date interval;
- the deterministic evidence fingerprint;
- whether unavailable/ineligible evidence selected Setup from the start, or a
  learned preference was considered but actual allocation used a Setup window.

The preview shows either `Learned timing applied · N rated sessions` or a
compact learned-considered/Setup-fallback line. Confirmation
rechecks all existing invariants and requires the user preference and deployment
gate still to be enabled when the preview claims learned timing. Recomputed
evidence never rewrites the immutable preview or blocks it merely because the
pattern changed. If pattern loading fails during proposal, planning continues
with Setup ordering and a visible fallback warning.

## Recommendation cleanup follow-up

This is a separate deterministic segment and does not grant Personal Patterns
or Decision Feedback new authority.

Recommendation generation resolves its rolling dates in the profile timezone,
excludes `daily_logs.entry_date` after that profile-local date, and reads current
structured facts. The Focus rule uses real terminal sessions:
an intentionally short completed session is not a failure, and a warning
requires at least three terminal sessions in 14 days with at least two
abandonments. The sleep rule uses a valid V4 sleep-quality estimate or explicit
target deviation instead of a fixed 6.5-hour cutoff alone. Recovery and movement
still count a matching date once. When both fields trigger on that date, its
evidence reference deterministically names the stronger normalized trigger:
sleep quality or sleep shortfall, and Steps or Activity. Movement candidates
exist only for actually measured activity or steps and name fixed thresholds,
never a personal baseline.

A deliberate refresh verifies the complete new candidate set and invokes one
service-role-only transaction. Prior `new` rows are retained as dismissed
history, accepted decisions remain untouched, and only the new set becomes the
current feed. An empty set therefore removes obsolete current cards without
deleting history.

Existing Decision Feedback API, rows, export, and deletion remain compatible.
The Dashboard history entry is rendered only when rows exist. No new feedback
buttons are exposed until a later redesign can show their ranking effect.

## Export, deletion, logging, and rollout

Account Export includes `focus_session_reflections` and
`learning_preferences`. It omits the backend-only learning request ledger under
the existing explicit ledger policy. Permanent account deletion cascades both
product tables through canonical ownership. Clearing reflections deletes only
reflection rows.

Application logs may contain contract version, response status, counts, and a
bounded failure stage. They must not contain raw ratings or obstacle values.

Release order is reflection collection, then read-only Insights, then Planner
use behind the additional feature flag after a minimum 28-day pilot. Explicit
crossover experiments, recovery-outcome learning, automatic sleep-target
changes, historical Habit/workload optimization, and Coach integration are
outside V1.
