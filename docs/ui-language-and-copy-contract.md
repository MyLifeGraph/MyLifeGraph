# UI Language And Copy Contract

Coach provider settings must state that provider requests may cost money and
that relevant read-only Coach query results are sent to the selected provider.
Web copy must say keys live only in the current tab and disappear on reload.
Failed replacement testing must explicitly say the previous key is unchanged.
Hosted mode selection uses `Project Coach`, `Use my OpenAI key`, and `Use my
Gemini key`. Project Coach copy states that the VPS creates a temporary
read-only app-data snapshot and restricted Coach tools send the question plus
only queried results to the shared pilot Codex account. It publishes the
5-per-account/15-global daily limits and never implies that a key or another
provider will be used after failure.
`provider_busy` says `Project Coach is busy. Retry manually when the countdown
ends.`; the countdown is visible, bounded, and never an automatic retry.

The implemented restore-safe hosted deletion flow states the exact irreversible
off-host-journal point and distinguishes `deletion_pending` from completed
deletion. Before that point, copy says deletion is paused and the account stays
signed in for the same-request retry. After durable journal acceptance, recovery
copy says the off-site journal is confirmed and the server keeps retrying until
the account is removed; a transient database failure is never presented as a
cancelled accepted deletion. This is current V2 source behavior, but it is not
hosted availability evidence until the external journal, backup, migration, and
deployment gates pass.

The public-pilot repository flow is adult-only and allows ordinary personal
use. Its implemented `pilot-participation-v1` /
`pilot-participation-notice-v1` pre-signup copy presents the privacy notice
before one explicit
`I confirm that I am 18 or older` acceptance, record the accepted notice
version/time through the backend after authentication but before product
access, and never ask for a birth date solely for this gate. Editable Auth
profile metadata must not be presented as proof of eligibility. The notice
must not describe real mood, sleep, stress, study, calendar, planning,
reflection, or Coach data as anonymous test data. A staging client containing
synthetic fixtures must display a persistent `Staging · Test data` identity and
must never be presented as the public pilot. Both surfaces are implemented in
the current Flutter source; that is not hosted legal review or deployment
evidence.

Status: implemented V1 product-copy contract for the current checkout,
including Coach V4 explicit-provider/busy behavior and shell behavior,
Exam-Week Outlook, and Personal Learning terminology.

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
| Existing-account authentication | Sign in |
| New-account authentication | Create account |

Versioned API and database names may remain technical. Do not leak those names
into a primary title, button, field label, or first-line error.

Within Morning check-in, use `Estimated sleep duration` for the duration
derived from the student's corrected estimated start/wake instants and
`Estimated sleep quality` for the separate required `1..10` subjective
measurement. Copy must state that neither is objective measurement, quality is
judged independently of duration, and neither value may be inferred from the
other.
Morning check-in presents one local draft in two steps. The first step uses
`MORNING · SLEEP`, `How did you sleep?`, 50-percent progress, and `Next`; the
second uses `MORNING · CHECK-IN`, `How are you starting today?`, 100-percent
progress, `Back`, and the final `Save morning check-in`. The first step does
not show quality, energy, or the save action. `Next` remains unavailable until
both estimated clocks and the sleep target form a complete valid branch. When
no duration can be calculated, the result area shows only `—`; the former
ordered-interval instruction is not shown. `Back` preserves every answer, and a
failed save leaves the full draft on the second step for an exact retry.

Three Morning explanations start hidden behind independent information
controls headed `Estimated sleep duration`, `Sleep target used for this night`,
and `Estimated sleep quality`. The target explanation remains dynamic: it says
whether the latest Evening plan supplied the starting value or no saved plan
was available. On Evening's sleep-plan step, the intent explanation headed
`Planned sleep time` and the first-value explanation headed
`Sleep duration target` also start hidden. The latter states that eight hours
is shown first and becomes the current plan only on save. Evening step headings,
optional-context copy, and the separate stress-source information control stay
visible or independently operable as before. All five new controls use the
exact semantics and tooltip labels `Show information about <heading>` and
`Hide information about <heading>`.

Morning check-in has no Day Shape/Tagesform question, label, saved summary, or
Dashboard detail. The Quick Actions subtitle is exactly
`Add sleep timing, sleep quality, and current energy`. The one-time Setup field
`Typical weekday` remains separate and unchanged.

## Quick Actions Copy

After a successful current-day capture read, the existing `Evening check-in`
and `Morning check-in` actions use the exact status `Completed today` for their
respective saved branch. A completed action remains an entry for editing that
branch. Quick actions does not repeat a detailed saved-signal summary, and it
must not infer completion while the current-day read is loading or unavailable.

## Today Copy

The primary Today surface uses these exact concepts:

- `Check-in streak` for consecutive dates with both saved check-ins;
- `Today's progress` and `x/y completed` for the transparent dynamic count;
- `Today at a glance` for the vertical agenda;
- `Setup commitment`, `Preparation`, `Calendar`, and `Focus` for agenda source
  categories;
- `Today's tasks`, `Show all tasks`, and `Today's habits` for execution;
- `Beat yesterday` for the compact latest-saved-check-in inset; and
- `Review your week` for the direct Weekly Review navigation entry; and
- `Full week` for the independently lazy supporting accordion.

The former generic `Recommendations` and `Decision feedback history` labels are
retired from Today. This does not rename the independent `Sleep Recommendation`
surface in Insights or ordinary Coach advice.

`Beat yesterday` names the existing compact inset but does not claim a delta or
improvement. It labels only available Mood, Energy, Sleep duration, Sleep
quality, and Stress values and includes the saved date. Under
`today-week-agenda-v1`, `Full week` is the profile-local `Monday–Sunday` agenda
across `Setup`, `Preparation`, `Calendar`,
`Focus`, `Planner Tasks`, `Habits`, and `Fixed commitments`. Empty days say
`Nothing scheduled.` only when their seven independent source states permit
that claim. With any unavailable source, an otherwise empty day instead says
`No items from available sources.` Every unavailable source is named in an
inline notice; its facts are omitted without hiding available siblings. A
route-wide load failure uses
`Full week unavailable` and offers only its week-scoped retry. Item labels may
use `In progress`, `Completed`, `Ended`, `Missed`, `Skipped`, `Open`,
`To do`, `Cancelled`, `Scheduled`, `Upcoming`, `Partially completed`,
`Confirmed`, or `Tentative` according to the source fact. The old
two-source `fullyRated`/rating-status Full-week language is retired and does not
alter Today at a glance.

The Today source/update line and ordinary explanations for streak, progress,
agenda, Task/Habit sections, `Show all tasks` plus its `Tasks` subsection, and
the Full-week accordion start hidden. Their adjacent circled
information controls use the exact semantics and tooltip labels
`Show information about <heading>` and `Hide information about <heading>`.
Opening information reveals the existing English copy; it does not replace or
delay an error, loading, unavailable, result, action, count, or empty-state
message and does not open the surrounding Task/supporting accordion. The
direct `Review your week` entry always shows its existing summary and has no
information control or collapsed wrapper. Every visible information icon is a
20-pixel glyph inside a 24-pixel frame and a real 44×44 button/semantics target;
the accordion header is an independent sibling control.

`today-overview-v2` may additionally label agenda rows `Task`, `Habit`, and
`Fixed commitment`. A scheduled Task or Habit still appears once in progress;
multiple blocks never imply multiple required actions.

## Planner Copy

The `exam-plan-health-v1` capacity surface name is `Exam Plan Health`. Its status labels
are `Healthy capacity`, `Plan soon`, `Capacity shortfall`, and
`Availability unknown`; status is never communicated by color alone. Use
`Exam Plan Health could not be loaded` for transport/contract failure and state
that it is not an Unknown capacity result. Copy must say that Health does not
replan automatically and must distinguish it from the sleep-focused
`Exam week outlook`. Planner's empty copy remains exactly
`Nothing currently needs review.` and appears only after both Planner and
Health attention are confirmed empty.

Under `multi-exam-plan-v1`, the action label is `Balance exam plans`. The flow requires an explicit Exam
selection and states that creating a preview moves nothing, sends no
notification, and changes no external calendar. A multi-plan review uses
`Confirm all` and `Discard`; a pending child says `Review exam balance` and
never presents the normal `Confirm plan` action. `Plan changed since preview`
is a stale conflict, while `Saved, but some views could not refresh` preserves a
durable mutation outcome. Avoid copy that promises automatic optimization.

Planner leads with `Add new`, followed by `Needs attention`, the next seven
days, `Ongoing preparation`, optional `Pending previews`, collapsed `Habits`,
`Unscheduled Tasks`, and collapsed history under `planner-overview-v2`. The
preview section contains every staged create and update and says
`Review every staged Task or Habit change before confirmation.` The
Habit summary is exactly `N active · X unplanned`; Setup-owned rows say
`Managed in Setup`. Empty attention is exactly
`Nothing currently needs review.` Use `preview`
for a staged Action Plan and `Confirm plan` only for the deliberate reservation
step. Unplaced time must use the exact remaining minutes. Conflicts say which
saved Setup, fixed-commitment, or current Calendar source now overlaps and that
nothing moves automatically. `No time was available within the current
planning limits.` is distinct from missing duration/deadline/session copy.
An invalid recurring wall time names the saved Habit time, weekly Setup time,
weekly fixed commitment, or affected combination, plus the affected local date
and wall time and whether it was ambiguous or nonexistent.
It says that only the invalid occurrence was omitted and that nothing moved
automatically; it must not describe the omission as a conflict.

After a conflict reload proves that the same exact pending preview is stale
from current Task/Habit target, Calendar import/preference, timezone, or Study
rhythm facts, the action is
`Create new preview`. For a persisted target, its explanation says the student
will review the latest saved details and that the old preview will be neither
confirmed nor cancelled. For a pending create, it truthfully says no saved Task
or Habit exists yet and that the preview values will be reviewed as a deliberate
new item. Ordinary pending previews continue to use `Review plan preview`;
ambiguous writes keep `Retry same change`.

Task copy must not suggest scheduling unless duration, exact deadline, and
preferred session length were explicitly entered. Calendar copy must say that
busy-time use is separately consented, read-only, based on the current imported
copy, and not live sync. Fixed commitments are authoritative only after the
user confirms them. Guest/demo copy states that synced Planner is unavailable
and must not display invented personalized blocks.

Direct `Add new` preparation actions preserve the chosen kind. Under
`assignment-series-v1`, Exam shows Exam as already selected; Assignment opens
`Add weekly assignments`, shows
`Assignment` with `Already selected for this preparation plan.`, defaults to
12, and labels the finite input `Number of weekly assignments (2–20)`. The
general Preparation Plans action asks `What are you preparing for?` and offers
`Exam` as one plan with one deadline and `Assignment` as a finite weekly series;
the selected editor does not ask for the kind again. The summary must make the
last weekly deadline visible. The shared estimate label is `Preparation
estimate for each assignment`; copy states that each occurrence gets its own
editable Preparation Plan.

Series lifecycle controls use `Create series preview`, `Confirm whole series`,
`Edit one`, `Edit all future`, and `Cancel future`. Copy must state before
proposal that nothing is reserved until the whole series is confirmed once,
and before a future-wide edit that it deliberately overwrites future
deviations while preserving older completed work. A partial-failure message
must say that no partial confirmation was kept.

Daily-cap defaults are presented as editable starting values, never inferred
effort. A new Exam starts at 120 minutes per day and a new Assignment or weekly
Assignment Series starts at 360; saved, retained, or manually entered values
stay visible unchanged. Optional `How new previews place time` methodology
says `A new or replanned Exam preview spreads its first sessions across
suitable days.` or `A new or replanned Assignment preview fills the earliest
suitable day before moving on.` It describes only the next preview and must not
claim that an older active revision was allocated by the current policy. It
must not imply automatic replanning, guaranteed free time, or background
calendar freshness.

Exam and Assignment surfaces do not show `No additional prior work`,
`Add prior work`, `Entered prior credit`, or another prior-work summary. They
show total estimate, linked/tracked Focus, and remaining preparation only.

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
The underlying existing response version is `personal-patterns-v1`.

The independent Insights card is titled `Sleep recommendation`. Non-ready
states use `No stable window yet` with `Disabled`, `Collecting N/30`, or
`Unstable`; ready uses `Best-supported sleep window` and `Ready`. Its three
metric labels are exactly `Sleep start`, `Wake time`, and `Duration`, with
`Same local day` on wake time when `wake_day_offset=0` and
`Following local day` when `wake_day_offset=1`. Result copy may say
`associated with` and
must not say optimal, ideal, caused, or medically recommended. The
below-target warning is exactly `This observed duration is below your median
confirmed sleep target. Your target has not been changed.` There is no apply,
adopt, or automation button.

The card-local failure title is `Sleep evidence is temporarily unavailable.`
and explains that the existing personal study pattern remains available and no
fallback window was created. Its control says `Retry sleep recommendation`.
Guest/demo mode does not show the card or invent a result.
The card validates `sleep-recommendation-v1` before rendering any state.

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
- Say `rule-based` for deterministic personalized calculations, `fixed template`
  for deterministic reminders, `example` for local demo data, and `preview`
  for a staged change that has not been applied.
- Do not repeat prototype-oriented self-defence such as `not AI-written`, `No
  demo values substituted`, or `No empty state assumed`. Where the distinction
  matters, use the positive provenance `Rule-based`, `Fixed template`, or
  `Example`; errors state the affected outcome, whether the student's saved
  data or draft remains, and the next safe action.
- Vendor names, runtime topology, source ownership, contract versions, and raw
  exception detail do not belong in primary student copy. Authentication uses
  `Sign in` and `Create account`; synced-feature failures say what is
  unavailable without asking the student to configure Supabase or a backend.
- Stored Insight rows are called notes unless their individual source proves a
  narrower AI claim. Planner calls its compact confirmed preparation reservations
  `7-day preparation load`; it does not combine them with current Task
  estimates or imply an immutable historical workload. Today does not repeat
  this workload card.
- The Preparation Plans page does not repeat a `Your next 7 days` card; it groups
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
  current reservations remain active until confirmation and names the
  calculation's fixed planning rules. A stale source or passed
  finish-by time must explain why the compact action is unavailable. The detail
  must also say that nothing changes automatically.
- Exam-balance list-detail failures offer `Retry Exam balances`; a targeted
  detail failure alone says `Requested Exam balance unavailable` and offers
  `Retry preview` for that exact balance. An unrelated source completion never
  clears or retargets the other's visible error.
- State whether a change is automatic, requires confirmation, or cannot change
  data. Do not imply that a preview or recommendation already changed a plan.
- Keep provider names, model names, contract versions, source manifests, and
  diagnostics secondary or expandable.
- Hide only optional explanation behind an information control. Consent,
  destructive or replacement consequences, current/stale/error state, required
  source truth, and the action needed to continue remain visible. Information
  controls start closed, operate independently, and use `Show/Hide information
  about <heading>` semantics.
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
- Deterministic generated Inbox items and banners use the compact provenance
  `Rule-based reminder`. Reminder Settings may explain fixed templates and the
  exclusion of private check-in details behind optional information; it does
  not repeat an AI disclaimer on each item.
- Coach is exposed in `staging`, `pilot`, and `production` only when
  `COACH_SURFACE_ENABLED` is exactly `true`; without that explicit gate it is
  hidden. In development, an explicit value wins and an unset release build
  stays hidden. When enabled, `Coach` is the right shell destination;
  `Settings` remains the last top-right action on Today, Insights, Quick
  actions, Planner, Coach, and Settings and is not duplicated in the shell.
  Page-specific actions precede any unread Coach action and Settings. Surface
  visibility does not prove provider readiness. Hosted users must explicitly
  choose Project Coach or one personal OpenAI/Gemini key. Both strategies still
  need public release gates; the local same-user Codex path proves one
  developer machine only and is not a production provider.
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
  query or used in the answer. The live local/operator Codex label is exactly
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
