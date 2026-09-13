# Personal Learning V1 Contract

## Purpose

Personal Learning V1 adds a deterministic, user-controlled learning loop around
terminal Focus sessions. A user may reflect on a completed or abandoned session,
inspect transparent non-causal patterns, and separately allow a mature learned
time preference to softly order newly requested planning previews.

This contract does not itself add an LLM, infer a new study rhythm, change a
sleep target or capacity, move a confirmed block, or make a provider write.

## Contract versions

- `focus-reflection-v1` is the stored per-session reflection contract.
- `learning-preferences-v1` is the revisioned preference contract.
- `personal-patterns-v1` is the read-only evidence contract.
- `sleep-recommendation-v1` is the independent read-only learned sleep-window
  contract.

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

`today-week-agenda-v1` shows actual Focus-session lifecycle facts but does not
read reflection rows or derive a rating/`fullyRated` status. Saving, editing,
deleting, or clearing a reflection therefore does not invalidate Full week.
The Focus history and Today terminal-Focus action still open the exact existing
reflection, and all persistence, retry, deletion, learning, and audit semantics
below remain unchanged. This retirement affects only the former two-source
Full-week rating decoration; it does not remove `focus-reflection-v1`.

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
The switch summaries remain visible. Optional calculation methodology starts
closed behind the independent standard information control `How pattern
analysis works`; the analysis dependency, Planner pilot availability, sleep
non-effects, save/retry state, and confirmed clear consequence remain visible.

## Personal patterns

`GET /v1/insights/personal-patterns` is side-effect free. It uses one captured
UTC instant, the profile IANA timezone, and the closed-open 90-day interval
ending at that instant. It never persists a pattern and never calls a model.
If analysis is disabled, it returns `disabled` before reading Focus or Daily
Capture history.

That one instant is captured before any source load. Focus sessions count only
when terminal before it. Reflections require `created_at` before and
`updated_at` at or before it; Daily Logs require `updated_at` at or before it.
Facts exactly at the cutoff or modified after observation are conservatively
excluded, and the response limitation names the actual generated-at boundary.

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

All consumers use the shared strict Daily Capture V4/V5 parser. It validates the
container and branch versions together: V4-in-V4 and V5-in-V5 are valid matched
shapes, V4-in-V5 requires `compatibility: true`, and the reverse or an unmarked
mixed pair is rejected. A Focus session may use a valid Morning sleep episode
only when the episode `entry_date` equals
the session's profile-local start date and `woke_at` is no later than the
session start. There is no prior-day or 36-hour fallback. A session after
midnight therefore has no sleep values until that calendar day's valid Morning
capture exists. The episode contains estimated duration, explicit target
deviation, sleep quality, and Morning energy only when that capture was recorded
before the session. V4 remains readable with its historical `day_shape`; V5
neither accepts nor emits that field, and pattern analysis does not use it.
Current new capture branches use the named `daily-capture-v5` contract.

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
The default `Overview` tab groups Personal study pattern and Sleep recommendation;
guest/demo retains its observation and example profile there. `Advanced` directly
shows the existing correlation tools, or the sparse-signal explanation. Tab
switching retains selected signals, comparison pair, window and disclosure state.
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
At ordinary mobile text sizes, narrower labels/cells and tighter row spacing
reduce scrolling. Trend signals live in a collapsed multi-select disclosure,
preserving metric order, per-series colors, pair exclusions, and the final
selected signal. Normalization and evidence-timing explanations remain visible.

### Advanced Skillset display

Both viewport layouts use Compare, Top patterns, Trend overlay, Skillset,
Matrix, then Discovered tabs. Skillset remains selectable with sparse data.
Compare, Top patterns, Trend overlay, Skillset and Matrix expose the shared
7/14/30/90-day selection, including sparse states. Switching tabs retains it.
Discovered shows saved results independent of this window and has no selector.
It is a read-only presentation of recorded observations in the selected window,
not the legacy persisted Skillset profile or a personal-strength model.
The default dimensions are Sleep, Sport, Energy, Social activity, Learning,
and Concentration; Stress, Mood, Productivity, Motivation, and Discipline are
optional. Selection filters only the Insights display for the current account
session; it never hides Capture inputs or limits which values can be recorded.

Sleep uses sleep quality, Energy uses Morning energy (otherwise Evening), Concentration uses rated
Focus quality, and Productivity uses rated useful progress. Stress and Mood
use their own ratings when present in the existing report. Each displayed
value is the median of valid daily ratings in the selected window, divided by
its existing scale maximum for the radar (1–10 or 1–5); raw ratings, sources,
and observed-day counts remain available under collapsed Details. Radar axes
show their number and short dimension name. Stress is not inverted and explicitly
says lower is calmer. The display does not rank abilities or prescribe targets.
The additive `skillset-observations-v1` fields on Personal Patterns are
`skillset_version`, `skillset_capture_version`, and `skillset_points` (daily
date/value maps). They obey the existing analysis permission and window; the
existing pattern calculations, correlation points, fingerprint and Planner
preference remain unchanged. Valid check-ins contribute independently of Focus.
The service advertises `skillset-capture-v1` support before new clients expose
the optional Capture questions. Old servers remain usable without these fields.

Sport and Social contact use explicit Evening choices on 0–2 scales. Study
motivation uses an explicit Morning choice on 0–2. Capture stores these in an
optional, separately versioned namespace; skipping is not zero. There is no
duplicate Recovery axis. Learning is the completion percentage of terminal
Focus sessions whose immutable schedule source is `deadline_plan_block` (study
preparation); it needs at least three sessions. Discipline is an activity
regularity proxy, not a character judgment: the equal-weight mean of Focus
completion percentage and sport-positive days divided by explicitly sport-rated
days. Each component needs at least three observations; unavailable components
are omitted. Motivation and unreported days do not penalize it. Derived values
use whole-window totals, not medians of daily percentages; the info dialog
explains the formula. They never change schedules, goals or backend scores.

Missing/non-finite/
out-of-range ratings never become zero. At least three measured selected
dimensions are needed for a radar; fewer retain their values and empty guidance.
Unavailable dimensions are omitted from the polygon. Demo reports stay labelled
as examples; real accounts never fall back to the demo Skillset provider.
Mood and stress now use their own valid Evening check-in values in this separate
view. Legacy correlation semantics and the demo source are unchanged.

## Learned sleep recommendation

`GET /v1/insights/sleep-recommendation` is side-effect free and independent of
`GET /v1/insights/personal-patterns`. It captures one `generated_at` instant,
uses the profile IANA timezone, and recomputes a deterministic rolling 90-day
result on every read. It does not persist an analysis, call a model, change the
confirmed sleep target, alter Planner capacity, or update the Evening sleep
plan. A failure on this route cannot replace or suppress the Personal Study
Pattern response.

The response reports `disabled`, `collecting`, `unstable`, or `ready`, the typed
reason, calculation instant, timezone, UTC and local window boundaries, and a
sample containing valid nights, eligible Focus days, rated sessions, the
required 30 days, and progress `N/30`. Reasons are
`analysis_disabled`, `insufficient_eligible_days`, `no_recurring_pattern`,
`insufficient_comparison_days`, `mixed_morning_outcomes`,
`mixed_focus_outcomes`, `temporally_unstable_pattern`, or `ready`.

`personal_pattern_analysis_enabled` is the sole analysis-consent gate. When it
is off, the service returns `disabled` before loading Daily Capture or Focus
history; only preferences and the profile timezone are resolved so the response
can describe its boundary honestly. Guest/local-demo mode does not call this
endpoint and receives no synthetic recommendation.

### Eligible day and daily aggregation

One eligible profile-local date requires all of the following:

- one valid V4 or V5 Morning episode whose `captured_at` is in the exact
  closed-open interval `[generated_at - 90 days, generated_at)` and whose Daily
  Log has a valid aware `updated_at <= generated_at`; the estimated sleep start
  may precede the lower boundary;
- at least one terminal Focus session whose start is at or after both `woke_at`
  and the Morning `captured_at` instant; and
- one valid `focus-reflection-v1` for that session, created no earlier than the
  terminal session end and within the captured observation boundary.

Multiple rated sessions on one date count as one eligible day. Morning
readiness is the mean of sleep quality and current energy. Useful progress and
Focus quality are the within-day medians, and completion is the within-day
completed-session ratio. The cross-day comparison then uses medians of these
daily values, preventing a busy date from multiplying its influence.

### Candidate, comparison, and stability rules

A recurring candidate contains at least ten dates and has a total circular
sleep-start span, circular wake-time span, and duration span of at most 45
minutes each. Candidate dates must also share the same local wake-day offset:
`0` for wake on the sleep-start date or `1` for wake on the following local
date. Same-day and following-day episodes are never pooled. Dates outside the
candidate form the comparison and must also number at least ten. A candidate is
supported only when all of these median differences hold:

- Morning readiness is at least `+0.5`;
- sleep quality and Morning energy are each no worse than `-0.5`;
- useful Focus progress is at least `+0.5`;
- Focus quality is no worse than `-0.5`; and
- completion rate is no worse than `-0.10`.

The same directional support must repeat in both chronological halves of all
eligible dates, with at least five candidate and five comparison dates in each
half. If multiple candidates pass, deterministic precedence is Morning
readiness improvement, useful progress, Focus quality, completion rate,
candidate size, then stable sleep-start, wake-time, and duration ordering.

A ready response exposes sleep-start, wake-time, and duration windows. Each is
the candidate's 25th through 75th percentile, rounded outward to 15-minute
boundaries, and may be no wider than 60 minutes. Clock intervals explicitly
carry next-day offsets so midnight crossings and DST-resolved source instants
are not guessed. `recommendation.wake_day_offset` is exactly `0` or `1` and
describes the local date relation of the selected source episodes. The response
also contains the full candidate/comparator
evidence deltas, two-half confirmation, raw median duration, median confirmed
target, and a deterministic evidence fingerprint.

Source sleep intervals remain strictly positive. When a lower duration
percentile is between one and fourteen minutes, outward rounding deliberately
produces a `0`-minute lower window boundary and a positive upper boundary; the
raw median remains at least one minute. This boundary representation must not
raise an untyped route error.

The raw supported duration is not clamped to the confirmed sleep target. When
it is shorter, `warning=below_confirmed_sleep_target` makes that discrepancy
visible without changing either value. Product language says “best-supported
sleep window” and “associated with”; it never claims a medical optimum,
diagnosis, causality, or automatic plan change.

Insights renders a separate `Sleep recommendation` card immediately below
`Personal study pattern`. Collecting and unstable states both say `No stable
window yet` while explaining their distinct reason; disabled, loading, and
route-error states are local to the card. Ready shows the three readable values
`Sleep start`, `Wake time`, and `Duration`, plus the below-target warning when
applicable. Mobile presents compact label/value rows, falling back to stacked
text for narrow widths or large text; desktop retains three columns.
Mobile values share a left-aligned start column with wrapping room for long
duration ranges, including two-digit hours; minutes are never ellipsized.
Status, warnings and expandable evidence remain intact. The standalone wake-day caption
is omitted; parsed day offsets and clock-window labels remain unchanged.
Flutter parses the raw median and confirmed target and rejects a V1
response whose warning, status/reason, 90-day window, sample, or evidence bounds
are inconsistent. It has no apply or automation control.

## Optional Planner use

Exam Plan Health is deliberately deterministic rather than learned.
`exam-plan-health-v1` consumes current authoritative availability and Study
rhythm but does not read reflection ratings, personal-pattern confidence, or
LLM advice, and it writes no learning evidence. Personal Learning therefore
cannot turn unknown capacity green or silently alter the recommended start.

Multi-Exam balancing is likewise deterministic. `multi-exam-plan-v1` does not
rank colliders from reflection ratings, personal-pattern confidence, Coach
text, or an LLM. Saved learned-timing authority may influence ordinary
availability only through the already bounded planning marker captured in the
context digest. Batch persistence separately records a learned-timing marker
covering the backend pilot flag, the locked learning-preference
revision/flags, and active Exam timing provenance. Changing the pilot,
disabling either consent flag, or changing that provenance makes confirmation
stale rather than rewriting it; the learning-preference writer participates in
the same owner advisory lock as proposal and confirmation.

Learned timing has two independent gates:

1. the account preference `learned_focus_planning_enabled`; and
2. the deployment feature flag for the pilot.

The deployment flag is available only for development, test, and staging
verification. Both FastAPI and Flutter force it off in the public `pilot`
environment even when configured true; the account preference alone can never
enable learned timing there.

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
raw observational pattern changed. The persisted pilot/permission and active
Exam provenance marker is different: a change there always requires a fresh
batch preview. If pattern loading fails during proposal, planning continues
with Setup ordering and a visible fallback warning.

## Recommendation retirement boundary

The former generic Recommendation generator/feed and Decision Feedback stack
are retired. Personal Patterns and learned Planner timing gain no replacement
write or ranking authority from that removal. The independent
`sleep-recommendation-v1` observation, `ai_insights.recommendation`, Memory type
`recommendation`, Skillset, and ordinary Coach advice remain unchanged. None of
those preserved concepts may recreate the retired Today feed or feedback API.

Flutter Skillset examples use the shared `isLocalDemo` capability, including
anonymous-provider sessions, and the local example source directly. A real or
missing session outside explicit mock mode cannot load the example. There is no
Flutter Skillset Supabase loader; persisted rows remain in the owner export and
Coach snapshot catalogs.

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
changes, and historical Habit/workload optimization remain outside V1.

The later Controlled Coach longitudinal extension reuses only bounded current
reflection facts and the existing analysis preference; it does not change this
90-day Insights contract, learn a Planner preference, or write Personal
Learning state. Disabling personal pattern analysis blocks broad Coach
`Patterns`, while an explicit single-session `Focus` or fixed two-week `Review`
request remains a separate deliberate Coach action. See
`docs/phase-10-controlled-coach-plan.md`.
