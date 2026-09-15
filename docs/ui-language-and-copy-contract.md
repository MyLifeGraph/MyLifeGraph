# UI Language And Copy Contract

Planner's compact view labels are `This week` and `Planning`. Task filtering
uses `Dated` / `Undated` because it reflects deadlines, not reservations.
Speech source labels are `Server` / `On-device`; Whisper Tiny and Base are
multilingual, not English-only variants. App-blocking rules use short labels
`During Focus`, `Weekly schedule`, `Always`, and `Block now`, with an explicit
overlap explanation in the editor. Actions retain accessible tooltips.

`Push reminders` is an optional Settings surface. Use `Important reminders`,
`Before bedtime`, `Today's deadlines`, `Important patterns` and `Quiet hours`.
The first opt-in explicitly names Google Firebase, device linkage and generic
copy; never describe OS permission as Cloud consent. Keep opt-out, unavailable
APK/server states and the two-per-24-hours / monthly-pattern limits clear.
Do not promise delivery after force-stop or while offline.

Health Connect uses `Connect`, `Sync now`, `Stop sharing` and `Delete imported data`.
The consent dialog names Cloud storage and selected Coach-provider access; Android
permission alone is not Cloud consent. Keep the seven-day foreground sync scope,
missing-data behavior, deletion distinction and errors visible. Imported sleep is
a calendar-day device observation, never a replacement for Morning check-in sleep.

Coach dictation uses `Dictate`, `Discard recording`, `Stop and review`, and `Send`.
The recording bar shows remaining seconds (`30s` down to `0s`) with the accessible
label `Recording. N seconds remaining`, then `Please wait…` while processing.
Before recording, explain the 30-second limit, server-side transcription,
non-persistence of audio, Stop to review versus explicit Send. Errors preserve typed text.
That acknowledgement is once per signed-in app session, not per recording;
sign-out/account change or full reload resets it. Countdown ticks do not
repeatedly interrupt screen-reader speech.

The empty invitation example is `For example: What patterns do you notice in
my week?`. It is static help, not a prompt button or a generated observation.

The empty Coach chat shows `Ask your coach anything` with one example question,
without a second empty-history notice. It is an empty-state invitation, not provider-readiness
or successful-history evidence when a load fails.

Supporting copy avoids repeating headings or immediately visible fields.
Settings section headings omit summary lists; individual options keep useful
help and state. Setup explains required inputs once in its hero and retains
field-level required/optional labels. Today keeps its independent information
controls with brief descriptions, including unchanged streak/progress rules.
Planner uses `Plan your tasks and study time`; preview/confirmation warnings,
calendar import limits, data-quality caveats, costs, consent, and save errors
remain available. These rules apply to both mobile and desktop.

Coach provider settings must state that provider requests may cost money and
that relevant read-only Coach query results are sent to the selected provider.
Non-demo Coach offers `Choose Coach` inline in ready and unavailable states.
Optional explanations use the `Coach modes` information control; selected-mode
cost/data-sharing copy, unavailability, limits, and key errors remain visible.
Web copy must say keys live only in the current tab and disappear on reload.
The non-secret Coach provider choice is saved separately per profile on this
device. Restoring a personal-key choice never implies its web key survived reload.
The chat's down-arrow uses the tooltip/accessibility label `Latest message`.
Failed replacement testing must explicitly say the previous key is unchanged.
Hosted mode selection uses `Project Coach`, `Use my OpenAI key`, and `Use my
Gemini key`. Project Coach copy states that the VPS creates a temporary
read-only app-data snapshot and restricted Coach tools send the question plus
only queried results to the shared pilot Codex account. It publishes the
5-per-account/15-global daily limits and never implies that a key or another
provider will be used after failure.
`provider_busy` says `Project Coach is busy. Retry manually when the countdown
ends.`; the countdown is visible, bounded, and never an automatic retry.

The hosted deletion flow states the exact irreversible durable-journal point
and distinguishes `deletion_pending` from completed deletion. Before that
point, copy says deletion is paused and the account stays signed in for the
same-request retry. After durable journal acceptance, recovery copy says
`Your deletion request has been durably recorded. The server will keep retrying
until the account is removed.` This wording applies to both the private VPS file
journal and the S3 journal; it promises neither off-site storage nor restore
support. A transient database failure is never presented as a cancelled accepted
deletion. This is current V2 source behavior, not hosted availability evidence;
applicable journal-profile, migration and deployment gates still require proof.

The public-pilot repository flow keeps its stated adult audience and allows
ordinary personal use. Its `pilot-participation-v1` /
`pilot-participation-notice-v1` confirmation is optional for the current small
pilot. Auth keeps the privacy link without a prerequisite checkbox. Settings
shows `Pilot confirmation (optional)` to unconfirmed authenticated hosted users.
The existing page says `Optional. You can use the app without this confirmation.`
and allows leaving; `Save confirmation` still requires the explicit `I confirm
that I am 18 or older` checkbox. A failed save must say the app remains usable
and confirmation can be retried later. No skipped step is described as accepted.

When `PILOT_PARTICIPATION_REQUIRED=true`, the existing pre-signup acknowledgement
and post-auth prerequisite remain in force. Only a deliberate authenticated
command records the notice version/time. Neither mode asks for a birth date
solely for confirmation. Editable Auth profile metadata must not be presented
as proof of eligibility. The notice must not describe real mood, sleep, stress, study, calendar, planning,
reflection, or Coach data as anonymous test data. A staging client containing
synthetic fixtures must display a persistent `Staging · Test data` identity and
must never be presented as the public pilot. Both surfaces are implemented in
the current Flutter source; that is not hosted legal review or deployment
evidence.

Status: implemented V1 product-copy contract for the current checkout,
including Coach V4 explicit-provider/busy behavior and shell behavior,
Exam-Week Outlook, and Personal Learning terminology.

## Supported Language

Setup groups its inputs under `Required setup` and `Optional setup`. Optional
sections use short previews; Routines explains that new entries are candidates
until a schedule is set and activation is explicit. Condensed Study Setup copy
must retain recovery-reservation, local-only/unscored start-checklist, and
no-automatic-task/calendar/notification meanings. `Include in start ritual`
labels the checkbox through tooltip and item-specific semantics; it is not
completion or a recorded score. Direct icon controls retain the tooltips
`Move up`, `Move down`, and `Remove preparation item`. Compact remove and
duplicate icons retain their existing action text as tooltips.
The routine field uses `Schedule`; its activation prerequisite remains in the
visible section guidance. `Setup summary` describes the complete setup state
being saved and keeps manually created items separate. Semester date controls
retain their start/end or opens/closes labels, with `Not set` for an unset date.

The V1 product interface supports English, with two narrow opt-in exceptions:
Coach replies/uncertainty/safety text and Ultra Quick's speaking guide support
German. A compact flag toggles each independently and persists on this device;
English is the default. Existing navigation and technical labels remain English.
User-entered text may of course
use any language, but navigation, controls, validation, empty states, and help
copy are English. App-wide German localization is not implemented or claimed.

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
`Sleep quality` for the separate required `1..10` subjective
measurement. Copy must state that neither is objective measurement, quality is
judged independently of duration, and neither value may be inferred from the
other. Visible Morning clock labels are `Sleep start` and `Wake time`; they
open a time picker and do not show preset chips. Compact minus/plus controls
move each entered clock 30 minutes earlier/later, with a visible `30m` step.
Unset clocks disable these shortcuts rather than inventing a time. Unset clocks and an
uncalculable duration show only `—` beside the label, not a status card.
Morning check-in presents one local draft in two steps. The first step uses
`MORNING · SLEEP`, `How did you sleep?`, 50-percent progress, and `Next`; the
second uses `MORNING · CHECK-IN`, `How are you starting today?`, 100-percent
progress, `Back`, and the final `Save morning check-in`. The first step does
not show quality, energy, or the save action. `Next` remains unavailable until
both estimated clocks and the sleep target form a complete valid branch. When
no duration can be calculated, the compact duration value shows only `—`; the
former ordered-interval instruction is not shown. `Back` preserves every
answer, and a failed save leaves the full draft on the second step for an
exact retry. Chosen `1..10` ratings stay visible beside their labels as
`n / 10` or `—`; they do not repeat `Choose a value to continue.`

Three Morning explanations start hidden behind independent information
controls headed `Estimated sleep duration`, `Sleep target used for this night`,
and `Sleep quality`. The target explanation remains dynamic: it says
whether the latest Evening plan supplied the starting value or no saved plan
was available. On Evening's sleep-plan step, the intent explanation headed
`Planned sleep time` and the first-value explanation headed
`Sleep duration target` also start hidden. The latter states that eight hours
is shown first and becomes the current plan only on save. Evening Mood, Energy
left, and Stress ratings use the same compact value-beside-label pattern.
Evening step headings, optional-context copy, and the separate stress-source
information control stay visible or independently operable as before. All five
new controls use the exact semantics and tooltip labels
`Show information about <heading>` and `Hide information about <heading>`.

Morning check-in has no Day Shape/Tagesform question, label, saved summary, or
Dashboard detail. The Quick Actions subtitle is exactly
`Add sleep timing, sleep quality, and current energy`. The one-time Setup field
`Typical weekday` remains separate and unchanged.

## Quick Actions Copy

After a successful current-day capture read, the existing `Morning check-in`
and `Evening check-in` actions appear in that order and use the exact status
`Completed today` for their respective saved branch. A completed action remains an entry for editing that
branch. Quick actions does not repeat a detailed saved-signal summary, and it
must not infer completion while the current-day read is loading or unavailable.

## Today Copy

The primary Today surface uses these exact concepts:

- `Check-in streak` for consecutive dates with both saved check-ins;
- `Today's progress` and `x/y completed` for the transparent dynamic count;
- `Today's schedule` for the vertical timed agenda;
- `Setup commitment`, `Preparation`, `Calendar`, and `Focus` for agenda source
  categories;
- `Tasks due today`, `All tasks`, and `Habits for today` for execution;
- `Beat yesterday` for the compact latest-saved-check-in inset; and
- `Weekly review` for the direct Weekly Review navigation entry; and
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

The redundant Today source/update line and All tasks explanation are omitted.
All tasks expands directly to task rows without a second Tasks heading.
Ordinary explanations for streak, progress, agenda, due tasks, Habits, and
the Full-week accordion start hidden. Their adjacent circled
information controls use the exact semantics and tooltip labels
`Show information about <heading>` and `Hide information about <heading>`.
Opening information reveals the existing English copy; it does not replace or
delay an error, loading, unavailable, result, action, count, or empty-state
message and does not open the surrounding Task/supporting accordion. The
direct `Weekly review` entry always shows its existing summary and has no
information control or collapsed wrapper. Every visible information icon is a
20-pixel glyph inside a 24-pixel frame and a real 44×44 button/semantics target;
the accordion header is an independent sibling control.

`today-overview-v2` may additionally label agenda rows `Task`, `Habit`, and
`Fixed commitment`. A scheduled Task or Habit still appears once in progress;
multiple blocks never imply multiple required actions.

## Planner Copy

Planner and Insights omit generic introductory subtitles in their page headers.
Contextual evidence, preview warnings and explicit confirmation copy remain.

Plan lifecycle actions use `Edit plan`, `Complete`, and `Cancel` in one row,
with full-action tooltips and icons above the labels. `Complete` still means
preparation completion; `Cancel` preserves history and is not permanent deletion.
Drafts retain `Discard preview`; preview confirmation remains a separate action.

Preparation keeps status-dependent warnings and exact plan values visible.
Detailed Focus-credit mechanics belong in the existing planning disclosure;
the visible start hint is `Start a block to focus on its remaining time.`
Short preview copy must still distinguish staged from currently reserved time.

Preparation lists name the profile timezone once in `Study blocks`; each row
separates date and time without repeating the zone. Keep year, cross-date end
dates, recovery reservation ends, status and tracked minutes explicit.

Creation forms use `How often?` for Habit cadence. Preparation's `Custom`
Focus choice names minutes and its existing 25–180 range. Hour chips are input
shortcuts, never recommended workload. All preview and confirmation warnings stay.

Planner Task and fixed-commitment time pickers reject an unresolvable local
selection with `This time is skipped or repeated by a clock change. Choose
another time.` Retained values stay visible; no adjusted time is silently saved.

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

On mobile Planner leads with the next seven days, followed by `Add new`,
`Needs attention`, `Ongoing preparation`, optional `Pending previews`, collapsed `Habits`,
`Unscheduled Tasks`, and collapsed history under `planner-overview-v2`. Desktop
places the agenda first, with creation/preferences and right-hand summaries below it.
`Days` and `List` remain labelled toggle actions at all widths. No sample
appointment is added to fill the fixed-height Days frame. Its empty label remains
`No planned or fixed items.`; more items remain accessible by scrolling. No
reference-only success claim or invented habit streak is shown. The
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

An unknown Series save instead says `Could not confirm the series save` and
keeps submitted values locked behind `Retry unchanged`; it must not claim that
the save failed or offer to discard the unresolved request. Definite rejection
says `Could not update the series`, uses the existing specific Preparation
conflict guidance, and keeps entered values available for review. The error is
visible even when no saved Series card exists.

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
Insights groups summaries under the default `Overview` tab and exploratory
correlations under `Advanced`. No extra introduction or Advanced accordion is
needed; existing evidence warnings, metric names and controls remain unchanged.
Advanced includes `Skillset` between `Trend overlay` and `Matrix`, on mobile
and desktop. Its compact `Dimensions` multi-select defaults to Sleep, Sport,
Energy, Social activity, Learning, and Concentration. `Your signals` identifies
the read-only radar: numbered short names label its axes; source labels, raw
scales and day counts are retained under the initially collapsed `Details`.
Missing dimensions say `No data`, never a low ability score. Unsupported concepts
are not inferred from loosely related metrics. Stress says lower is calmer.
The compact view icons have `Radar chart` and `Bar chart` tooltips. Both views
retain the same data and Details. A failed local preference write is disclosed,
not reported as saved. Coach uncertainty uses explicitly labelled
`Low uncertainty`, `Medium uncertainty`, or `High uncertainty` with the original
reason. Semantic color/icons supplement these words; high uncertainty means
less confidence and no level guarantees correctness.
Ultra Quick Check-in uses the compact choices `Morning`, `Evening`, `Quick note`.
Morning/Evening speaking guides follow manual-form order with blank values,
`… / 10` ratings, named optional choices, and conditional stress context.
They are display-only hints while empty and remain visible during recording;
the guide is never prefilled as user input.
`Review fields` means an uncommitted proposal, followed by the existing required
form and final save. `Save note` is separate optional context, not a check-in.
Recording/transcription never claims completion. Errors retain the text and
give a manual form alternative; note deletion requires confirmation.

Evening shows its optional choices directly at the end of the context step;
Morning shows its optional choice directly too. Choice copy is `Sport today` (None,
Light, Intense), `Social contact` (Little, Some, Lots), and `Study motivation (optional)`
(Low, Medium, High). Discipline is an explained activity-regularity percentage,
not a personality assessment; Learning is completed study Focus sessions.

The independent Insights card is titled `Sleep recommendation`. Non-ready
states use `No stable window yet` with `Disabled`, `Collecting N/30`, or
`Unstable`; ready uses `Best-supported sleep window` and `Ready`. Its three
metric labels are exactly `Sleep start`, `Wake time`, and `Duration`, without
a separate same-day/next-day caption. Clock-window values and day-offset
interpretation are unchanged. Result copy may say
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

Auth introduces `Sign in to sync your personal data.` in synced-only mode, or
`Sign in to sync, or try a local demo.` otherwise. The guest action explains
`Local demo. Setup stays here; check-ins may transfer on sign-in.` Google needs
no repeated subtitle. Full privacy disclosures and authentication errors remain
available; the checkbox still explains recorded notice/time and no birth date.

Android Focus protection names app-blocking modes `Focus sessions`, `Weekly
schedule`, and `Always block`. Weekly selection confirms days/times in one
compact sheet and names device time plus next-day end where relevant.
`Silence during Focus` explicitly distinguishes DND from independent app blocks.
Permission disclosures and warnings stay visible; `Privacy & limits` holds
the full explanation. Package identifiers remain available as app-label tooltips.

- State the user outcome before implementation detail.
- Calendar `Plan study time` follows Event, Study time, then the generated
  preview. Prefilled fields stay under `Edit event details`; optional controls
  stay under `Adjust plan`. Other preparation entries retain three input steps.
  The preview/confirmation distinction and source warnings remain visible.
- The Calendar-linked preparation page names the selected event first. `All
  plans` separates other plans from this event. `Enough study time?` shows Exam
  capacity; `Redistribute study time` offers an explicit multi-Exam preview.
  Both are directly visible with short outcome-first or empty-state copy.
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
  narrower AI claim. Planner and Today have no standalone preparation-workload
  card. Preparation editors use the summary to read the account budget, without
  presenting it as a complete availability or historical-workload model.
- The Preparation Plans page groups compact `Open plans` and `History`
  accordions. The optional
  `Daily preparation budget` is described as an explicit
  account-wide transparent rule, not an AI estimate or inferred free time.
  Changing the setting does not mutate existing reservations.
  `Review plan` navigates to saved details, while `Replan
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

- Real accounts do not load persisted Skillset profiles without a trusted
  producer/freshness contract. The separate Advanced Skillset radar uses only
  current measured report ratings, not a personal-ability score. Legacy demo
  Skillset data and demo radar reports are labelled as examples.
- In-app reminders may show a foreground banner only while MyLifeGraph is open.
  The app does not claim browser, phone-system, email, push, background-mobile,
  or deployed delivery.
- Reminder configuration belongs to Settings, is not delivery consent, and is
  never changed by Setup.
- Deterministic generated Inbox items and banners use the compact provenance
  `Rule-based reminder`. Reminder Settings may explain fixed templates and the
  exclusion of private check-in details behind optional information; it does
  not repeat an AI disclaimer on each item.
- Inbox introduction: `Latest 30 items · counts cover this list.` Demo uses
  `Local examples · not synced or sent. Counts cover up to 30 shown items.`
  Compact icon actions retain read/unread, dismiss and destination tooltips;
  stored items and counters do not claim delivery.
- Coach is exposed in `staging`, `pilot`, and `production` only when
  `COACH_SURFACE_ENABLED` is exactly `true`; without that explicit gate it is
  hidden. In development, an explicit value wins and an unset release build
  stays hidden. When enabled, `Coach` is the right shell destination;
  `Settings` remains the last top-right action on Today, Insights, Quick
  actions, Planner, Coach, and Settings and is not duplicated in the shell.
  Page-specific actions precede any unread Coach action, Inbox and Settings. Surface
  visibility does not prove provider readiness. Project Coach is preselected as
  `Standard (provided)`; alternatives are `OpenAI (your key)` and
  `Gemini (your key)`. Selecting a provider does not send a question. Both strategies still
  need public release gates; the local same-user Codex path proves one
  developer machine only and is not a production provider.
- Current Coach uses `Your question` in a bottom composer and an icon labelled
  `Send` (or `Retry unchanged` for exact retry). User and Coach messages share
  one oldest-first chat; there is no separate `Conversation history` section.
  The composer model icon is labelled `Choose Coach` and opens provider/key
  controls in a dialog with `Done`. Coach explanations remain there; optional
  Coach modes information uses `Close`. Errors stay visible above the frame.
  Loaded history opens at its newest message.
  `Delete conversation`, cancellation, uncertainty, and details remain. It has no
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
