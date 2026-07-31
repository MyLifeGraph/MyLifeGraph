# Exam-Week Outlook V1 Contract

Status: implemented repository boundary as of 2026-07-26.

This contract adds two related, deterministic capabilities:

1. `daily-capture-v4` records a student's planned sleep rhythm and their
   estimated sleep interval; and
2. `exam-week-outlook-v1` compares confirmed preparation demand with regular
   and hypothetically sleep-protected availability.

The result is a read-only Planner warning. It is not a sleep diagnosis, an
effort estimate, an automatic schedule change, or a notification.

## Daily Capture V4

Evening check-in adds one required sleep-planning step:

- `planned_sleep_time` is an exact local wall-clock value in `HH:mm` format;
- `sleep_target_minutes` is `300..720`, in 15-minute increments; and
- the first visible target is 480 minutes. It becomes the student's saved
  rhythm only after a successful Evening save.

After the first save, the newest valid Evening V4 branch supplies the visible
default for later Evening and Morning forms. It is a transparent latest-value
rule, not a separate profile, learned preference, or Study Setup revision.

Morning check-in requires:

- aware `estimated_sleep_started_at` and `woke_at` instants;
- their exact derived whole-minute `estimated_sleep_minutes`;
- compatible `sleep_hours = estimated_sleep_minutes / 60`;
- the `sleep_target_minutes` used for that night; and
- optional `source_evening_capture_id` when an Evening plan supplied the
  starting value.

The Morning UI labels the result `Estimated sleep duration` and says that the
times are self-estimates rather than objective measurement. The student may
correct both clocks and the target before saving. The interval must be ordered,
positive, minute-aligned, and no longer than 16 hours. Cross-midnight examples
such as 23:00–07:00 and same-date examples such as 02:00–10:00 both derive 480
minutes.

### Branch Compatibility

The daily container version is `daily-capture-v4`. Each structured branch also
has a `branch_version`.

A V4 save may preserve an untouched V2 or V3 opposite branch with:

- its original `branch_version`; and
- `compatibility: true`.

This is the only accepted mixed-version shape. Editing an older branch first
upgrades that branch to V4 and requires its new sleep fields. Merging Evening
never erases Morning or foreign top-level metadata, and merging Morning never
erases Evening. Existing V1 guest migration and readable V2/V3 rows remain
supported.

### Projection And Privacy Boundary

Raw planned/estimated clocks remain only in
`daily_logs.metadata.captures.evening|morning`. The compatible
`daily_logs.sleep_hours` column and the existing deterministic Sleep event
value use the derived duration.

Raw clocks, the sleep target, and the source Evening id are not copied into
Behavioral Event metadata, Daily State, recommendation context, notification
content, or Coach context. Those paths continue to receive only the compatible
numeric duration or an already-derived bounded fact. Account Export includes
the raw fields because it already exports the owner's complete `daily_logs`
rows.

`explainable-daily-state-v2` remains the snapshot response contract. Its parser
accepts V2, V3, V4, and explicit mixed compatibility branches. It validates V4
interval arithmetic before trusting the derived duration. Equivalent sleep
duration/quality inputs produce the same classification as their compatible
older representation. Today streak recognition likewise treats a valid V4
Morning or Evening branch as an explicit saved capture.

Daily State, this outlook, and `personal-patterns-v1` call the same strict V4
sleep parser. Personal Patterns may describe an observational sleep range, but
it cannot change this outlook's sleep target, protected interval, capacity, or
mode. Optional learned Focus timing affects only a newly requested
Planner/Deadline preview; this read-only simulation does not reorder or move
any block.

## Read-Only Endpoint

The authenticated endpoint is:

```text
GET /v1/deadline-plans/exam-week-outlook
```

Its strict response contract is `exam-week-outlook-v1`, with
`origin=authenticated_backend`. The owner comes only from the bearer principal;
there is no request owner field.

The response includes:

- one captured aware `generated_at`, profile `timezone`, and `local_date`;
- `mode`, `risk_level`, and `capacity_status`;
- the newest valid Evening V4 sleep plan, without raw sleep instants;
- at most the three newest valid Morning V4 sleep nights from the last seven
  profile-local dates, as derived minutes/target/shortfall only;
- affected active exams and assignments with remaining/scheduled/missed/
  simulated minute facts;
- bounded ordered `warning_codes`; and
- exact aggregate minute totals.

Evening and Morning rows whose `entry_date` is after the captured profile-local
`local_date` are excluded before the newest plan or recent nights are selected.

The GET performs only owner-scoped reads. It does not create a plan, revision,
block, task, preview, notification, briefing, or event, and it does not update a
last-viewed timestamp.

## Activation And Mode

Only an active exam with remaining preparation activates the surface:

- `exam_week`: deadline is 0 through 7 profile-local dates away;
- `watch`: deadline is 8 through 14 dates away;
- `overdue`: at least one qualifying exam date has passed; and
- `inactive`: no qualifying exam exists.

Active assignments never activate the mode. While a mode is active, assignments
with remaining work and deadlines through the same 14-day horizon participate
in the capacity calculation and appear as separately labelled consumers.

## Deterministic Capacity Simulation

The service reuses the existing bounded Availability engine without persisting
its simulated intervals. It considers:

- each active plan's current remaining minutes after explicit prior credit and
  qualifying linked completed Focus;
- uncredited missed blocks and uncredited future confirmed blocks;
- the revision's per-plan daily maximum;
- the optional account-wide daily preparation budget;
- Setup recurring commitments;
- confirmed Preparation blocks from every plan, including plans whose
  deadlines fall outside the outlook window;
- confirmed Planner Task blocks and Habit slots;
- authoritative one-off and weekly Planner commitments;
- configured Study recovery intervals; and
- current imported busy time only when the account's separate Planner
  availability consent is enabled.

The shared Availability grid keeps the complete busy-end precision. A source
ending after an exact boundary, including by seconds or microseconds, releases
simulated capacity only at the following five-minute boundary; an exact
boundary remains unchanged.

Future confirmed minutes on or before the warning buffer reduce the additional
gap that must be simulated. Missed minutes do not. Future blocks after the
warning buffer remain visible as a warning and do not weaken the recommended
buffer.

For warning purposes, an exam uses:

```text
recommended_buffer_days = max(saved_buffer_days, 1)
```

This does not alter the saved revision. Assignments retain their saved buffer.
Additional gaps are allocated sequentially by earliest deadline, then exam
before assignment at the same deadline, then canonical plan id.

Capacity is simulated twice:

1. with normal Availability; and
2. with the newest planned sleep window added as hypothetical busy time for
   each relevant night.

The sleep comparison uses the saved local start clock and target elapsed
minutes. A nonexistent or ambiguous DST start makes protected capacity
incomplete rather than silently choosing an instant.

Planner and Deadline proposal revisions also pin the profile
`timezone_revision`. Confirmation rechecks that identity under the existing
owner lock. A later timezone change never shifts confirmed blocks: active plans
gain `timezone_changed` attention, while open previews must be recreated.
Recurring Setup and Planner local times use the same round-trip resolver, so a
DST gap or fold makes only that source unavailable instead of guessing an
offset.

The exact fit states are:

- `fits_with_sleep_protected`: both simulations fit and all required
  availability inputs are current;
- `fits_only_using_sleep_window`: regular availability fits but the
  sleep-protected simulation does not;
- `does_not_fit_before_buffer`: even regular availability cannot place all
  additional work; and
- `unknown`: protected capacity cannot be proven, including a missing sleep
  plan or incomplete consented availability.

## Warnings And Risk

Warning codes are ordered and bounded to:

- `exam_overdue`;
- `missing_recommended_buffer`;
- `missed_preparation_blocks`;
- `remaining_work_does_not_fit`;
- `sleep_capacity_tradeoff`;
- `repeated_sleep_shortfall`;
- `sleep_plan_missing`;
- `capacity_incomplete`; and
- `pending_preview_sleep_overlap`.

Repeated shortfall means at least two of the latest three valid V4 Morning
nights, all within the last seven local dates, are each at least 60 minutes
below the target saved with that Morning. It raises the displayed risk exactly
one level and never changes a plan.

An overdue exam with remaining work or structurally unscheduled remaining work
is at least `high`. Missing recommended buffer, missed blocks, a sleep-capacity
tradeoff, a missing sleep plan, or a staged sleep overlap is `attention` unless
a stronger proven condition applies. Incomplete availability with no stronger
proven risk is `unknown`, never `on_track`.

A pending preview remains staged. Its proposed blocks are checked only for
overlap with the hypothetical sleep intervals. The outlook neither regenerates
nor confirms it, and its active revision remains authoritative.

## Planner Surface

Authenticated real accounts read the outlook only from Planner. The card is
placed after `Add new` and before `Needs attention`:

- `watch` is a compact 14-day warning;
- `exam_week` is visually emphasized;
- `overdue` is urgent;
- missing sleep plan links to Evening check-in; and
- each exam offers `Review plan` and `Replan remaining time`.

`Review plan` opens existing saved Preparation details.
`Replan remaining time` pushes
`/planner/replan?plan_id=<uuid>`, which renders only that selected plan over the
existing saved-value review. It makes no proposal request until the student
explicitly chooses to create a preview, and the preview still requires explicit
confirmation. Confirmation returns to Planner and reloads the outlook; leaving
an unconfirmed preview preserves it as staged.

The card labels assignments as capacity consumers and states that it is
read-only. It is absent from Today, Inbox, notification generation, and guest/
demo surfaces. Guest/demo does not call the endpoint and does not fabricate an
outlook.

## Persistence And Non-Claims

This slice adds no table, column, RPC, migration, background job, or export
projection. It stores Capture V4 only in existing `daily_logs` metadata and
derives the outlook per GET.

The derivation is implemented as a pure builder over an aware captured instant,
the bounded planning context, typed Deadline details, and bounded Capture rows.
Repository reads and persistence-error mapping stay in the Deadline service;
the builder performs no I/O and is directly deterministic-testable.

It adds no:

- clinical sleep, fatigue, stress, or health diagnosis;
- hard sleep lock or automatic plan/revision/block mutation;
- inferred sleep preference from Notification quiet hours;
- automatic exam detection outside explicitly active exam plans;
- inferred effort, last-minute quota, or outcome prediction;
- Today item or Notification;
- Calendar/provider write, live sync, or new consent;
- LLM, Coach write, autonomous tool use, or deployed scheduler.

## Verification Boundary

Automated coverage must prove:

- required Evening plan values, first-visible 480-minute target, latest-value
  prefill, target grid, interval ordering, 16-hour bound, and 02:00–10:00 plus
  23:00–07:00 derivation;
- V2/V3/V4 parsing, explicit mixed-branch preservation, edit-time V4 upgrade,
  guest round-trip, raw-field isolation, compatible projections, shared-parser
  parity with Personal Patterns, and exact retry identity;
- unchanged Daily State V2 classification for equivalent derived sleep facts
  and V4-compatible Today streak recognition;
- exact mode boundaries, overdue behavior, assignment capacity, multiple plans,
  one-day exam warning buffer, missed/future blocks, deterministic ordering,
  account/per-plan limits, Study recovery, and all confirmed competitors;
- both fit simulations, missing sleep plan, DST gap/fold behavior, two-of-three
  repeated shortfall, exclusion of future Evening/Morning rows, incomplete
  calendar availability, and pending-preview overlap without mutation;
- strict bearer ownership, cross-owner isolation, a write-free GET, and guest/
  demo zero-call;
- Planner loading/error/watch/exam-week/overdue/unknown states, placement,
  navigation without proposal, narrow layout, and 200% text; and
- a real browser journey with V4 Evening/Morning capture, an active exam,
  competing assignment, Planner-only status, explicit replan navigation, and
  unchanged active revisions before confirmation.

That browser proof is the independent
`e2e/web/journeys/exam-week-outlook.spec.mjs` Playwright journey. It reads the
persisted plan/revision/block projections before and after opening and
cancelling the replan form, so visible navigation cannot silently satisfy the
contract by creating a preview.

Passing repository automation proves only this deterministic local boundary. It
does not prove remote deployment, provider freshness, installed-device
behavior, clinical value, academic outcomes, or long-term sleep behavior.

## Visual presentation

The outlook card uses the shared
[Frontend Visual System V2](frontend-visual-system-v2.md). Status colors remain
paired with text and icons; activation, capacity arithmetic, warnings, and the
read-only Planner boundary remain unchanged.
