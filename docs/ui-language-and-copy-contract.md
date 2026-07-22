# UI Language And Copy Contract

Status: implemented V1 product-copy contract as of 2026-07-18.

## Supported Language

The V1 product interface supports English only. User-entered text may of course
use any language, but navigation, controls, validation, empty states, and help
copy are English. German localization is not currently implemented or claimed.

Adding German later requires Flutter localization resources, locale selection
or system-locale behavior, translated semantics and validation copy, and widget
tests for both English and German. Translating a few visible strings is not
enough to advertise German support.

## Canonical Surface Names

Use these names in student-facing UI and presentation material:

| Purpose | Visible name |
| --- | --- |
| Daily decision surface | Today |
| Capture/action launcher | Quick actions |
| End-of-day capture | Evening check-in |
| Start-of-day capture | Morning check-in |
| Timed work | Focus |
| Central planning | Planner |
| Exam and assignment preparation | Preparation plans |
| Weekly reflection | Weekly review |
| Imported calendar copy | Calendar |
| Stored notices | Inbox |
| Patterns and correlations | Insights |
| Development conversation surface | Coach |
| Durable preferences and account controls | Settings |

Versioned API and database names may remain technical. Do not leak those names
into a primary title, button, field label, or first-line error.

## Today Copy

The primary Today surface uses these exact concepts:

- `Check-in streak` for consecutive dates with both saved check-ins;
- `Today's progress` and `x/y completed` for the transparent dynamic count;
- `Today at a glance` for the vertical agenda;
- `Setup commitment`, `Preparation`, `Calendar`, and `Focus` for agenda source
  categories;
- `Today's tasks`, `Show all tasks`, `Today's habits`, and `More` for the
execution/support boundary.

`today-overview-v2` may additionally label agenda rows `Task`, `Habit`, and
`Fixed commitment`. A scheduled Task or Habit still appears once in progress;
multiple blocks never imply multiple required actions.

## Planner Copy

Planner leads with `Add new`, followed by `Needs attention`, the next seven
days, `Ongoing preparation`, `Unscheduled`, and collapsed history. Use `preview`
for a staged Action Plan and `Confirm plan` only for the deliberate reservation
step. Unplaced time must use the exact remaining minutes. Conflicts say which
saved source now overlaps and that nothing moves automatically.

Task copy must not suggest scheduling unless duration, exact deadline, and
preferred session length were explicitly entered. Calendar copy must say that
busy-time use is separately consented, read-only, based on the current imported
copy, and not live sync. Fixed commitments are authoritative only after the
user confirms them. Guest/demo copy states that synced Planner is unavailable
and must not display invented personalized blocks.

Do not title the overview `Today's decision`, label a recommendation `Primary
action`, claim a fixed number of daily steps, or imply the app chose the user's
day. A source failure says the affected section or `Progress unavailable` and
must not replace persisted facts with examples. Notification fixed copy uses
`Today's overview is ready` and invites the user to review their schedule and
actions.

## Plain-language Rules

- State the user outcome before implementation detail.
- A retry message says: what happened, what input remains, and the next safe
  action.
- Use `Retry unchanged` only when the exact submitted payload is locked for an
  idempotent retry. Pair it with a plainly named reload action.
- Say `rule-based` for deterministic personalized calculations, `fixed text`
  for deterministic reminders, `example` for local demo data, and `preview`
  for a staged change that has not been applied.
- Daily briefings visibly say `Rule-based · not AI-written`. Stored Insight
  rows are called notes unless their individual source proves a narrower AI
  claim. Preparation load is named `Current planned workload` because it combines
  saved schedule durations, task estimates, and active preparation reservations,
  and because active revisions can replace the projection; it is not presented
  as immutable historical load.
- The Deadline Planner's separate `Your next 7 days` card names only confirmed
  preparation reservations as preparation load. Recurring `schedule_items` are
  labelled `weekly setup commitments`; imported calendar busy time is not shown
  there. The optional `Daily preparation budget` is described as an explicit
  account-wide transparent rule, not an AI estimate or inferred free time.
  Existing over-budget reservations say `Needs review` because changing the
  setting does not mutate them. Expanding that date may say `At least N must be
  redistributed on this date`; this is the exact rule overage, not an automatic
  choice of plan. `Review plan` navigates to saved details, while `Replan
  remaining time` only opens the existing staged flow. For an active plan with
  no pending preview, its compact review uses `Replan remaining preparation`,
  `Create preview with these values`, and `Change values`. It states that the
  current reservations remain active until confirmation and that the
  calculation is rule-based rather than AI-generated. A stale source or passed
  finish-by time must explain why the compact action is unavailable. The detail
  must also say that nothing changes automatically.
- State whether a change is automatic, requires confirmation, or cannot change
  data. Do not imply that a preview or recommendation already changed a plan.
- Keep provider names, model names, contract versions, source manifests, and
  diagnostics secondary or expandable.
- Do not use `generated`, `learned`, `optimized`, or `AI-powered` unless the
  current execution path and its visible provenance prove that claim.

## Capability Truth

- Real accounts do not show Skillset until a real producer and freshness
  contract exist. Demo Skillset data is labelled as an example.
- In-app reminders may show a foreground banner only while MyLifeGraph is open.
  The app does not claim browser, phone-system, email, push, background-mobile,
  or deployed delivery.
- A Setup reminder preference is not delivery consent.
- Coach is a development preview. Release builds and `APP_ENV=production` hide
  it regardless of Flutter defines. The local Codex path proves one developer
  machine only and is not a production provider.

## Accessibility Copy Gate

Primary journeys must remain usable at 320 logical pixels and a 2.0 text scale.
Text may wrap and pages/dialogs may scroll; text must not be scaled down to hide
overflow. Controls need stable semantics that use the same student-facing name
as the visible label. Copy changes are incomplete until affected widget and
browser selectors are updated.
