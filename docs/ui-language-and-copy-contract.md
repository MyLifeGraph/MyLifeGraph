# UI Language And Copy Contract

Status: implemented V1 product-copy contract, including the current
Coach-enabled shell, Exam-Week Outlook, and Personal Learning terminology, as
of 2026-07-26.

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

Within Morning check-in, use `Estimated sleep duration` for the duration
derived from the student's corrected estimated start/wake instants and
`Estimated sleep quality` for the separate required `1..10` subjective
measurement. Copy must state that neither is objective measurement, quality is
judged independently of duration, and neither value may be inferred from the
other.

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

When active, the read-only exam card appears after `Add new` and before
`Needs attention`. Use `Exam watch · next 14 days`, `Exam week`, or
`Exam plan overdue`; label assignments `Assignments counted in capacity`.
Capacity copy distinguishes `fits with sleep protected`, `fits only by using
the sleep window`, `does not fit before the warning buffer`, and `unknown`.
The sleep copy calls the newest saved value a `Sleep plan`, says protection is
hypothetical rather than a lock, and never claims fatigue, health, or predicted
performance. `Review plan` reads saved state; `Replan remaining time` opens a
review and does not imply that a preview or revision already exists.

When no current manual or consented availability source is visible, use
`Availability may be incomplete`, offer `Add weekly schedule`, and state that
calendar import stays optional. The automatic-planning interruption uses
`Review your availability` and `Continue anyway`; it must not claim either that
the schedule is complete or that an override makes conflicting time safe.

Do not title the overview `Today's decision`, label a recommendation `Primary
action`, claim a fixed number of daily steps, or imply the app chose the user's
day. A source failure says the affected section or `Progress unavailable` and
must not replace persisted facts with examples. A current Today overview alone
must not trigger a generic banner. Recovery and Weekly Review notifications use
fixed, destination-specific copy without private capture details.

## Personal Learning Copy

Settings uses one entry titled `Personal learning`; it is not a primary
navigation destination. The switches are `Ask after Focus sessions`,
`Analyze my study patterns`, and
`Prefer learned Focus times in new plans`. The last control must say that it is
optional, soft, applies only to new previews, and never moves existing plans.

The Focus sheet asks `How focused did the session feel?` and
`How much useful progress did you make?`, with plain-language anchors rather
than statistical terminology. `Not now` is neutral and a missing reflection is
never described as a low score. A failed save says that the terminal session
was retained and preserves the exact choices for retry.

Insights calls the card `Personal study pattern` and uses `Collecting`,
`Emerging`, `Stable`, or `Disabled`. Evidence copy always names the rated
sample, 90-day window, coverage, profile timezone, and limitations. Use
`associated with` or `observed`; never use `caused`, `optimal`, `ideal`,
medical advice, or predicted academic performance. Sleep descriptions never
change or recommend a sleep target. Planner preview provenance uses the compact
line `Learned timing applied · N rated sessions`; unavailable analysis states
`Personal pattern unavailable · Setup timing used`.

Advanced Insights uses `Previous-night sleep`,
`Previous-night sleep quality`, `Sleep shortfall`, `Morning energy`,
`Rated focus time`, `Planned focus time`, `Rated focus quality`,
`Rated useful progress`, and `Rated session completion`. Dashboard saved detail
uses `Previous-night sleep` and `Previous-night sleep quality`. A blocked
correlation says `Not compared · overlapping signals`; a 7–13-day coefficient
says `Early evidence`.

## Plain-language Rules

- State the user outcome before implementation detail.
- A retry message says: what happened, what input remains, and the next safe
  action.
- When authentication succeeds but its backend-owned profile is missing, say
  `Your sign-in succeeded, but this synced account could not be opened. No
  account data was changed. Sign out, then try again. If it continues, the
  account needs repair.` and offer `Sign out`. Do not present this invariant as
  wrong credentials or attempt a client-side profile repair.
- Use `Retry unchanged` only when the exact submitted payload is locked for an
  idempotent retry. Pair it with a plainly named reload action.
- Say `rule-based` for deterministic personalized calculations, `fixed text`
  for deterministic reminders, `example` for local demo data, and `preview`
  for a staged change that has not been applied.
- Daily briefings visibly say `Rule-based · not AI-written`. Stored Insight
  rows are called notes unless their individual source proves a narrower AI
  claim. The compact Today projection calls confirmed preparation reservations
  `7-day preparation load`; it does not combine them with current Task
  estimates or imply an immutable historical workload.
- Today and Planner name confirmed reservations `7-day preparation load`. The
  Preparation Plans page does not repeat a `Your next 7 days` card; it groups
  compact `Open plans` and `History` accordions instead. Recurring
  `schedule_items` are labelled `weekly setup commitments`; imported calendar
  busy time is not shown in that workload. The optional
  `Daily preparation budget` is described as an explicit
  account-wide transparent rule, not an AI estimate or inferred free time.
  Existing over-budget reservations say `Needs review` because changing the
  setting does not mutate them. Expanding that date may say `At least N must be
  redistributed on this date`; this is the exact rule overage, not an automatic
  choice of plan. `Review plan` navigates to saved details, while `Replan
  remaining time` opens only the selected plan in the focused staged flow. For an active plan with
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
- Coach answers are English-only in the current free-agent contract, including
  uncertainty text, even when the question or stored evidence is not English.
  A rejected provider-language response uses ordinary retry copy and is never
  shown as a partial answer.
- Do not use `generated`, `learned`, `optimized`, or `AI-powered` unless the
  current execution path and its visible provenance prove that claim.

## Capability Truth

- Real accounts do not show Skillset until a real producer and freshness
  contract exist. Demo Skillset data is labelled as an example.
- In-app reminders may show a foreground banner only while MyLifeGraph is open.
  The app does not claim browser, phone-system, email, push, background-mobile,
  or deployed delivery.
- Reminder configuration belongs to Settings, is not delivery consent, and is
  never changed by Setup.
- Coach is a development preview. Release builds and `APP_ENV=production` hide
  it regardless of Flutter defines. When enabled, `Coach` is the right shell
  destination; `Settings` remains the last top-right action on Today, Insights,
  Quick actions, Planner, Coach, and Settings and is not duplicated in the
  shell. Page-specific actions precede any unread Coach action and Settings.
  The local Codex path proves one developer machine only and is not a
  production provider.
- Current Coach uses `Ask anything`, `Your question`, and `Ask Coach`. It has no
  `Today`, `Patterns`, `Focus`, `Review`, horizon, session, prompt-starter,
  memory-selection, or structured suggestion controls. Older answers remain
  readable without recreating their fixed-mode controls.
- While a turn runs, use short allowlisted lifecycle copy such as
  `Preparing a private data snapshot …`, `Checking relevant history …`, or
  `Testing the data with isolated analysis …`, plus `Cancel analysis`. Never
  expose hidden reasoning, raw SQL/code, personal values, or model event text as
  transient status.
- A completed turn may show `Your Coach answer is ready.` from the shared
  unread Coach action. A non-Cancel failure may show
  `Coach could not finish the answer. Open Coach to review or retry.` Closing
  this floating message is not equivalent to reading the answer and neither
  message claims background or push delivery.
- The expandable answer label is `Data and analysis details`. It may show
  `Snapshot source coverage`, conservative source periods/counts, actual
  inspection/SQL/Python step summaries, limitations, uncertainty, and technical
  provenance. Coverage must not be described as the exact rows returned by one
  query or used in the answer. The live local provider label is exactly
  `gpt-5.5 · Fast configured`. It must not display a plot, chain-of-thought,
  invented evidence, or an executable app action.
- Coach answers use observational language, separate observed data from
  uncertain interpretation/missing information/general explanation, and never
  claim causation, diagnosis, automatic changes, or product mutation.

## Accessibility Copy Gate

Primary journeys must remain usable at 320 logical pixels and a 2.0 text scale.
Text may wrap and pages/dialogs may scroll; text must not be scaled down to hide
overflow. Controls need stable semantics that use the same student-facing name
as the visible label. Copy changes are incomplete until affected widget and
browser selectors are updated.
