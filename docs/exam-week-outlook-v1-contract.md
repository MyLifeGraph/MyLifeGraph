# Exam-Week Outlook V1 Contract

Status: implemented repository boundary, including finite Assignment Series
compatibility, as of 2026-08-10.

This contract adds two related, deterministic capabilities:

1. current `daily-capture-v5` records a student's planned sleep rhythm and their
   estimated sleep interval; and
2. `exam-week-outlook-v1` compares confirmed preparation demand with regular
   and hypothetically sleep-protected availability.

The result is a read-only Planner warning. It is not a sleep diagnosis, an
effort estimate, an automatic schedule change, or a notification.

## Daily Capture V5

Evening check-in adds one required sleep-planning step:

- `planned_sleep_time` is an exact local wall-clock value in `HH:mm` format;
- `sleep_target_minutes` is `300..720`, in 15-minute increments; and
- the first visible target is 480 minutes. It becomes the student's saved
  rhythm only after a successful Evening save.

The visible intent and first-value explanations on this Evening step start
closed behind independent inline information controls. The step heading and
the separate optional-context and stress-source help remain unchanged.

After the first save, the newest valid Evening V4/V5 branch supplies the visible
default for later Evening and Morning forms. It is a transparent latest-value
rule, not a separate profile, learned preference, or Study Setup revision.

Morning check-in requires:

- aware `estimated_sleep_started_at` and `woke_at` instants;
- their exact derived whole-minute `estimated_sleep_minutes`;
- compatible `sleep_hours = estimated_sleep_minutes / 60`;
- the `sleep_target_minutes` used for that night;
- independent whole-number `sleep_quality` and `current_energy` values from 1
  through 10; and
- optional `source_evening_capture_id` when an Evening plan supplied the
  starting value.

The Morning UI is one local draft across two pages. `MORNING · SLEEP` / `How did
you sleep?` shows 50-percent progress and owns both clocks, the derived
`Estimated sleep duration`, and the target. Only a complete valid interval and
target enable `Next`. `MORNING · CHECK-IN` / `How are you starting today?`
shows 100 percent and owns quality and energy. `Back` retains every answer, and
only `Save morning check-in` on the second page writes the branch; a failure
keeps that page, draft, capture identity, and payload available for retry.

The result area shows only `—` while no valid duration exists. The duration,
target-source, and quality explanations start closed independently behind
20-pixel information icons in 44×44 targets. Their semantics switch between
`Show information about <heading>` and `Hide information about <heading>`, and
their inline motion becomes immediate under Reduced Motion. The duration copy
says that the times are self-estimates rather than objective measurement. The
student may correct both clocks and the target before saving. The interval must
be ordered, positive, minute-aligned, and no longer than 16 hours.
Cross-midnight examples such as 23:00–07:00 and same-date examples such as
02:00–10:00 both derive 480 minutes.

### Branch Compatibility

The current daily container version is `daily-capture-v5`. Each structured branch also
has a `branch_version`.

A V5 save may preserve an untouched V2–V4 opposite branch with:

- its original `branch_version`; and
- `compatibility: true`.

This is the only accepted mixed-version shape. Editing an older branch first
upgrades that branch to V5 and requires its current sleep fields. Complete V4
branches remain writable during rollout but cannot downgrade a V5 container.
The shared precise-sleep parser receives both identities and rejects V5 inside a
V4 container as well as V4 inside V5 without exact `compatibility: true`.
V5 Morning rejects the retired `day_shape` field; a historical V4 value remains
compatibility data and is neither displayed nor evaluated. Merging Evening
never erases Morning or foreign top-level metadata, and merging Morning never
erases Evening. Existing V1 guest migration and readable V2–V4 rows remain
supported.

### Projection And Privacy Boundary

Raw planned/estimated clocks remain only in
`daily_logs.metadata.captures.evening|morning`. The compatible
`daily_logs.sleep_hours` column and the existing deterministic Sleep event
value use the derived duration.

Raw clocks, the sleep target, and the source Evening id are not copied into
Behavioral Event metadata, Daily State, general recommendation context,
notification content, or Coach context. Those paths continue to receive only
the compatible numeric duration or an already-derived bounded fact. The
separate consented read-only `sleep-recommendation-v1` analysis reads the valid
Morning episode directly to learn clock ranges but does not copy it elsewhere.
Account Export includes
the raw fields because it already exports the owner's complete `daily_logs`
rows.

`explainable-daily-state-v3` is the current snapshot response contract. Its parser
accepts V2 through V5 and explicit mixed compatibility branches. It validates V4/V5
interval arithmetic before trusting the derived duration. Equivalent sleep
duration/quality inputs produce the same classification as their compatible
older representation. Today streak recognition likewise treats a valid V4/V5
Morning or Evening branch as an explicit saved capture.

Daily State, this outlook, `personal-patterns-v1`, and
`sleep-recommendation-v1` call the same strict V4/V5 sleep parser. Personal
Patterns or Sleep Recommendation may describe an observational sleep range, but
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
- the newest valid Evening V4/V5 sleep plan, without raw sleep instants;
- at most the three newest valid Morning V4/V5 sleep nights from the last seven
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
An `assignment-series-v1` occurrence is an independent `deadline-plan-v1`
Assignment for this read. Only confirmed active occurrence plans participate;
the series projection and its pending future-wide preview are not additional
demand and require no extra Outlook read. Confirming, editing, or cancelling a
series invalidates/reloads the existing Deadline projection through the normal
Planner mutation impact, without giving this GET write authority.

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

The shared Availability function retains `spread_first` as its default, so this
read-only capacity simulation does not silently adopt a proposal-only policy.
Confirmed Assignment blocks created with Deadline Planner's internal
`earliest_clustered` policy still participate as authoritative busy time and
daily preparation minutes after explicit confirmation. This preserves the V1
Outlook calculation while allowing new Assignment proposals to cluster without
changing this response or adding a policy field.

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

Exam Plan Health is not this outlook. `exam-plan-health-v1` answers whether
remaining Exam preparation fits authoritative shared capacity and exposes
green/yellow/red/unknown reserve values. Exam Week Outlook continues to answer
the sleep- and exam-week question owned here. Planner and Today may show both,
but their headings and helper copy must keep those purposes distinct; a Health
transport failure is not an Outlook warning and Health `unknown` is not a
sleep-risk inference.

`multi-exam-plan-v1` may simulate and explicitly confirm a shared Exam
redistribution, but it does not consume or rewrite sleep plans and does not use
Outlook severity as an allocation input. A successful batch changes ordinary
confirmed Deadline revisions; the next Outlook read then derives from that new
state. Preview, stale failure, and discard leave Outlook unchanged.

Authenticated real accounts read the outlook only from Planner. The card is
placed after `Add new` and before `Needs attention`:

- `watch` is a compact 14-day warning;
- `exam_week` is visually emphasized;
- `overdue` is urgent;
- missing sleep plan links to Evening check-in; and
- each exam offers `Review plan` and `Replan remaining time`.

The separate Preparation Plans surface may start a kind-locked Exam from either
Planner's direct `Exam` action or its general `Plan preparation` chooser. That
chooser also routes `Assignment` to the finite weekly series editor, and a
previously consumed route kind cannot hide Exam from a later general choice.
This presentation routing does not broaden the Outlook read: only confirmed
independent Deadline Plan occurrences participate in its calculation.

`Review plan` opens existing saved Preparation details.
`Replan remaining time` pushes
`/planner/replan?plan_id=<uuid>`, which renders only that selected plan over the
existing saved-value review. It makes no proposal request until the student
explicitly chooses to create a preview, and the preview still requires explicit
confirmation. The existing plan's persisted root kind remains read-only through
that review, full editor, and deep-link entry; it cannot be changed from Exam to
Assignment or vice versa. Confirmation returns to Planner and reloads the
outlook; leaving an unconfirmed preview preserves it as staged.

Every proven Deadline confirm, complete, or cancel result, including a
successful exact retry, emits one controller-owned Deadline projection impact
that invalidates the Outlook read. Proposal previews emit none. A draft-only
cancellation carries no Daily Snapshot date, while a returned managed Task uses
the current profile-local date; a failed best-effort refresh never downgrades
the durable lifecycle result. The Planner or Deadline widgets do not duplicate
this invalidation.

The destination route continues to own that navigation and every provider or
mutation call after its internal presentation widgets are split into
feature-private parts. The split does not move the Outlook card out of Planner
or change its read-only behavior, order, focus handling, copy, semantics, or
responsive layout.

The card labels assignments as capacity consumers and states that it is
read-only. It is absent from Today, Inbox, notification generation, and guest/
demo surfaces. Guest/demo does not call the endpoint and does not fabricate an
outlook.

The read failure says that capacity and sleep context could not be loaded and
offers another load; it does not narrate placeholder or inference internals.
Read-only help refers to the student's `current saved plan`, not an `active
revision`, while the persisted revision authority remains unchanged.

## Persistence And Non-Claims

The Outlook itself adds no table, column, RPC, migration, background job, or
export projection. Current Capture V5 and readable V4 sleep inputs remain only
in existing `daily_logs` metadata, and the outlook is derived per GET. The later
V5 migration replaces the Capture merge RPC only; it adds no Outlook storage.

The derivation is implemented as a pure builder over an aware captured instant,
the bounded planning context, typed Deadline details, and bounded Capture rows.
Repository reads and persistence-error mapping stay in the Deadline service;
the builder performs no I/O and is directly deterministic-testable.

Those bounded Deadline source reads use the shared repository offset-page
collector. Existing owner predicates, stable ordering, page and row limits,
and the exact overfull-response failure remain unchanged; the outlook exposes
no pagination cursor.

Scheduled Focus makeup and source-aware block credit change only the underlying
active Deadline detail after an actual session completes. They do not change
this endpoint's contract, mode activation, sleep simulation, warning rules, or
read-only authority; the outlook continues to consume the same total remaining
and block-state projection.

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

- Flutter parsing may reuse framework-neutral exact-key, nested collection,
  scalar, UUID, date, and aware-timestamp primitives without changing the
  feature-owned capacity arithmetic, mode/warning relationships, or V1 shape;

- required Evening plan values, first-visible 480-minute target, latest-value
  prefill, target grid, interval ordering, 16-hour bound, and 02:00–10:00 plus
  23:00–07:00 derivation; the two-page Morning gate, retained Back/error draft,
  final-only save and exact retry; all five initially closed independent
  Capture explanations with keyboard/semantics coverage; and 320-pixel,
  200-percent-text, and Reduced-Motion behavior;
- V2/V3/V4 parsing, explicit mixed-branch preservation, V4-to-V5 edit and guest
  migration, guest round-trip, raw-field isolation, compatible projections,
  current V5 plus explicit V4-in-V5 shared-parser parity with Personal Patterns,
  rejection of reversed and unmarked V4/V5 pairs, and exact retry identity;
- unchanged Daily State V2 classification for equivalent derived sleep facts
  and V4-compatible Today streak recognition;
- exact mode boundaries, overdue behavior, assignment capacity, multiple plans,
  one-day exam warning buffer, missed/future blocks, deterministic ordering,
  account/per-plan limits, Study recovery, all confirmed competitors, and the
  unchanged spread-first default for this simulation when proposal allocation
  adds an explicit kind-specific option;
- both fit simulations, missing sleep plan, DST gap/fold behavior, two-of-three
  repeated shortfall, exclusion of future Evening/Morning rows, incomplete
  calendar availability, and pending-preview overlap without mutation;
- strict bearer ownership, cross-owner isolation, a write-free GET, and guest/
  demo zero-call;
- Planner loading/error/watch/exam-week/overdue/unknown states, placement,
  navigation without proposal, immutable existing-plan kind, narrow layout,
  and 200% text;
- one Outlook invalidation after each successful Deadline lifecycle result and
  exact retry, none after proposal preview, no Snapshot date for draft cancel,
  and durable success when refresh fails; and
- a real browser journey with V4 Evening/Morning capture, an active exam,
  competing assignment, Planner-only status, explicit replan navigation, and
  unchanged active revisions before confirmation.

That browser proof is the independent
`e2e/web/journeys/exam-week-outlook.spec.mjs` Playwright journey. It reads the
persisted plan/revision/block projections before and after opening and
cancelling the replan form, so visible navigation cannot silently satisfy the
contract by creating a preview.

The outlook capacity algorithm remains its existing pure builder. Deadline
plan orchestration now imports its own deterministic projection/block helpers
from `deadline_plan_builder.py`; neither module performs repository I/O. This
module split changes no activation window, timezone, sleep protection,
availability, capacity, or response contract.

The read route delegates its existing Deadline service failures to the typed
Deadline HTTP problem translator. Its not-found/conflict statuses and details,
read-only authority, and unexpected-error behavior remain unchanged.

Passing repository automation proves only this deterministic local boundary. It
does not prove remote deployment, provider freshness, installed-device
behavior, clinical value, academic outcomes, or long-term sleep behavior.

## Visual presentation

The outlook card uses the shared
[Frontend Visual System V2](frontend-visual-system-v2.md). Status colors remain
paired with text and icons; activation, capacity arithmetic, warnings, and the
read-only Planner boundary remain unchanged.
