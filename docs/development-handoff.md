# Development and service handoff

This is the current product and operations map for maintainers and coding agents.
It describes the checked-out implementation, not an assertion that every commit
is deployed. Exact release identities, migration observations and check
results belong in [Verification](verification.md#current-verified-baseline).

## Current delivery boundary

- The source contains the follow-ups prepared on `fix/coach-german-completion`.
  Inspect GitHub release/commit identities and Verification before equating a
  checkout with Vercel, the VPS or an installed APK.
- The last recorded release already includes English/German Coach, Ultra Quick
  Check-in, optional Skillset capture, Health Connect, Android push, on-device
  speech and combined Android app-blocking rules. Device acceptance remains separate.
- The subsequent German Coach completion migration was recorded as applied to
  Pilot. The newer Gemini model-selection migration is prepared locally, not
  recorded as applied. See the [schema owner](supabase-current-state.md) and
  Verification; inspect actual migration history before any future apply.
- New provider-isolation fixes and non-Focus-day sleep-duration coverage require
  the updated API. Gemini's additional model choice also needs compatible SQL
  and clients. A local UI restart cannot deploy these backend changes.
- Historical installation procedures below are not instructions to bootstrap an
  already running host again. Current release maintenance uses immutable bundles,
  reviewed additive migrations and the existing signing identity.

## Feature and interface map

| Area | Current implementation | Detail owner |
| --- | --- | --- |
| Auth | Larger heading, concise introduction, directly visible email fields; centered when it fits, scrollable for keyboard/errors/consent. Existing Google/email/recovery/CAPTCHA flows retained. | [Flutter](../apps/mobile/README.md), [Copy](ui-language-and-copy-contract.md) |
| Morning | Compact heading and `Save`, 30-minute clock shortcuts alongside the picker; Study motivation remains available independently of Insights selection. | [Daily Capture](daily-briefing-implementation-plan.md) |
| Evening | Compact heading and `Save`; Sport/Social match influence-button sizes. First selecting a source highlights it and reveals a chevron; re-tapping opens/closes its borderless Specific blocker input. Header and input share width/outline with different theme surfaces; Info stays outside. Changing selection collapses the input without clearing its text. Hover never implies another selection. | [Daily Capture](daily-briefing-implementation-plan.md), [Visual](frontend-visual-system-v2.md) |
| Ultra Quick | Morning/Evening speaking guides appear immediately while the transcript is empty and remain during recording, in the selected English/German language. Existing review and final Save remain mandatory. | [Daily Capture](daily-briefing-implementation-plan.md) |
| Today | Clearer pending/completed check-in styling, without changing labels, streaks or completion authority. | [Today](today-overview-v1-contract.md) |
| Planner | Mobile/tablet retain `This week` / `Planning`; desktop restores calendar left, Add below and summaries right. Compact outlined `+ Add`, header Import, full-width mobile Planning Add, scrollable calendar content and retained Days/List selection. Busy-time preference stays in Planning on mobile. | [Planner](planner-v1-contract.md), [Flutter](../apps/mobile/README.md) |
| Shell | Deliberate horizontal root-page swipes; Planner Add opens only from an upward swipe on bottom navigation/Plus. Button and swipe transitions follow tab order in both directions; nested scrollers, editing, subpages and reduced motion remain respected. | [Flutter routes](../apps/mobile/README.md#main-routes), [Visual](frontend-visual-system-v2.md) |
| Coach UI | Quota moved beneath composer model name to avoid narrow-header clipping. Existing language, dictation and provider controls remain. | [Coach](phase-10-controlled-coach-plan.md) |
| Coach correctness | Reject stale/mismatched capability/provider responses; refresh the latest selected provider after an in-flight refresh. A rejected BYOK configuration no longer probes the base Codex provider. Quotas and no-fallback policy unchanged. | [Coach](phase-10-controlled-coach-plan.md) |
| Gemini | Saved per-profile device model choice; exact model header through local proxy/API and bound to request/retry/provenance. Bounded invalid-key classification replaces misleading generic local-provider copy. Catalog entries are not proof that a user's Google key can access them. | [Coach](phase-10-controlled-coach-plan.md), [API](../services/ai_service/README.md) |
| Speech/Settings | Coach's model picker shows all on-device models inline, also on reopening, with Android bottom-safe-area clearance and separate Selected/Downloaded labels. Redundant Coach/Speech entries removed from Settings; Coach retains all controls. | [Coach](phase-10-controlled-coach-plan.md#flutter-contract) |
| Insights Past | New tab between Skillset and Matrix, existing daily signals, adjacent equal 7/14/30-day periods including today or Monday–today versus last Monday–Sunday. Exact ranges, units, data gaps and collapsed Details; no correlation/formula changes. | [Personal Learning](personal-learning-v1-contract.md#past-period-comparison) |
| Data compatibility | Additive Morning `sleep_hours` observation includes non-Focus days in Past. German V4 completion fingerprint fix and separate Gemini allowlist extension preserve existing grants, locks, retries and stored records. | [Schema](supabase-current-state.md), [Architecture](architecture.md) |
| Verification/tooling | Targeted regression coverage, updated labels/layout expectations, migration-restore inventory expectations and local model-header forwarding. Exact completed checks and remaining gates stay in Verification. | [Verification](verification.md#current-verified-baseline) |

## Data flow and feature boundaries

### Setup, daily check-ins and Ultra Quick

Setup groups Required and Optional sections; optional editors keep their original
fields, validation, expanders and save semantics. Start ritual items put text,
include state, reorder and delete in one compact row. Setup-owned commitments
remain separate from manually created Planner items. See [Study Setup](study-setup-v1-contract.md)
and [Setup compatibility](setup-personalization-retirement-contract.md).

Morning captures sleep timing, sleep quality, current energy and optional study
motivation. The clock picker and 30-minute shortcuts edit the same draft values.
Evening captures mood, remaining energy, stress, sleep planning and conditional
stress source/influence, with separate optional reflection, sport and social
contact. Specific blocker remains the same optional saved note, not a second
rating or a new per-source database field. UI folding never erases it.

Authenticated Save uses the existing Capture controller, FastAPI validation and
owner-locked Supabase RPC; failures retain exact retry identity. Neither the
Skills display filter nor a collapsed optional section removes collected data.
Manual required fields, revision/timezone checks, streaks and projections remain
owned by [Daily Capture](daily-briefing-implementation-plan.md) and
[Stabilization](stabilization-consistency-contract.md).

Ultra Quick offers Morning, Evening and Quick note. Its speaking guide is visible
before focus and while recording; the saved English/German flag controls guide
language. Speech produces a transcript, then a deliberate model request produces
only a proposed draft. Review/correction and normal Save remain mandatory; missing
required values cannot become a partial completed check-in. Quick note is separate
optional Coach context and never increments a streak or invents numeric ratings.

### Today, Planner and calendar

Today consumes authenticated overview/agenda facts, not a second scheduling
engine. Tasks use the same completion/restore commands as Planner; All tasks has
independent Dated/Undated filters, initially both enabled. A deadline is not the
same as a reserved time block. Habits retain their own occurrence/outcome rules.
Completed schedule rows are disclosed separately; read failures remain visible.

Planner has Days/List plus retained active day. Mobile/tablet separate calendar
(`This week`) and supporting controls (`Planning`); desktop keeps calendar and Add
left, summaries right. Unscheduled Task completion and confirmed removal reuse
the existing Task port; removal means cancellation, with restore still available.
Adding/editing a Task, Habit, Exam, Assignment or Fixed commitment keeps each
existing wizard, validation and explicit preview/confirmation boundary.

Calendar import is a user-selected `.ics` file, with explicit consent and source
controls. Google sign-in does not grant Calendar access. Busy-time inclusion
only affects eligible future planning calculations; import never silently moves
confirmed reservations. Study preparation linked to an imported event still
requires user-defined workload and explicit plan confirmation. Exam effort
presets/custom Focus blocks edit inputs, not scheduling rules. See
[Planner](planner-v1-contract.md), [Deadline planning](deadline-planner-v1-contract.md)
and [Calendar import](phase-9-calendar-import-contract.md).

### Insights and optional watch data

Overview contains descriptive Personal Study Pattern and Sleep Recommendation.
Advanced contains Compare, Top patterns, Trend overlay, Skillset, Past, Matrix
and Discovered. Relevant shared period controls remain visible; overflow arrows
expose horizontally offscreen tabs on pointer and touch layouts.

Skillset offers radar or bars and persisted dimension selection. Raw manual
ratings and optional motivation/sport/social values remain distinct from labelled
window-derived Learning/Discipline summaries. Missing data stays missing, not zero.
Past compares adjacent equal 7/14/30-day windows including today, or this Monday
through today against all of last Monday–Sunday. Both modes align chart positions
without reclassifying dates or changing correlation formulas. Morning sleep-hours
coverage includes days without a Focus session. See [Personal Learning](personal-learning-v1-contract.md).

Watch import is Android Health Connect, not direct Garmin login/API. The user
first permits the watch vendor to share with Health Connect, then separately
grants Android reads and MyLifeGraph Cloud consent. The bound device uploads
source-tagged daily steps and sleep-session totals through `/v1/health-connect`.
Imports become owner-only behavioral facts available to export and Coach, never
overwrite manual Morning ratings, and are not double-counted with them. Stop
sharing disables upload; Delete imports removes only this source. No heart-rate,
location or silent background-health permission is implemented.

### Coach, speech and Android protection

Coach is a read-only assistant: its selected Standard/OpenAI/Gemini provider may
inspect bounded owner data but cannot complete Tasks, alter plans, save check-ins
or mutate account settings. Language/provider/model choices are restored per
their documented scope; provider changes discard stale capability and retry
state, never route Gemini through Standard as fallback. The composer contains
model controls, speech source, microphone and Send; history is a chat timeline
with newest-message positioning and an unobtrusive return-to-bottom action.
Uncertainty presentation is a readable confidence cue, not a factual guarantee.

BYOK keys remain on the client and in the single HTTPS API request. Web keys are
tab-memory-only; Android uses encrypted local storage. No key enters Supabase,
logs, snapshots or provider-choice preferences. Provider model labels describe
the configured allowlist, not an entitlement or promise of Google availability.
Account-wide and Standard dispatch limits remain distinct; changing model/language
does not reset budgets. See [Coach authority and replay](phase-10-controlled-coach-plan.md).

Speech is independent of the Coach model. Server uses the bounded Parakeet V3
sidecar; Android On-device uses explicit checksummed downloads and local decode.
Selection is remembered, installed files are separately identified, and no local
failure silently uploads audio. X discards, Stop inserts text, Send transcribes
then submits through normal validation. Acknowledgement is per signed-in session;
microphone permission remains separate. The countdown and live level bars do not
persist audio. See [speech operations](../services/speech_service/README.md).

Android Focus Protection is local Accessibility-based blocking, not Cloud access
control. Each app can combine Focus, weekly intervals, always and temporary rules
with OR semantics. Overnight periods belong to the start weekday. Master disable,
essential-app exclusions and emergency release remain authoritative. Notification
silencing follows only the real Focus lease. App selection supports collapse,
deselect all and a fixed installed-social-app preset. No calendar/Focus records
are fabricated by standalone blocking. See [Focus Protection](android-focus-protection-v1-contract.md).

### Inbox, in-app reminders and push

Inbox lives beside Settings in main-page headers. A row or Open icon follows
its allowlisted target; Read/Unread and Dismiss remain separate lifecycle actions.
Stored Inbox entries are not proof of notification delivery. Foreground banners
and Android push have separate explicit settings/consents. Push uses the existing
API worker and FCM, not Firebase database/compute; notification attempts are
session/device-bound, deduplicated and privacy-minimal. See
[Inbox lifecycle](notification-lifecycle-v1-contract.md) and
[delivery/anti-spam](notification-delivery-v1-contract.md).

## Runtime service inventory

| Component | Responsibility and data boundary | Configuration/runbook |
| --- | --- | --- |
| Flutter web / Android | Shared product UI. Guest stays local; authenticated accounts use their own Cloud data. Android-only integrations are not promised on web. | [Client](../apps/mobile/README.md) |
| Supabase Cloud | Auth, profiles, canonical Postgres data, RLS and privileged owner-checked RPCs. Frontend receives only the publishable key; server credentials stay backend-only. | [Schema/Auth](supabase-current-state.md) |
| Google OAuth | Identity provider configured through Supabase Auth and its Google Cloud OAuth client. This is separate from Gemini API keys, Firebase delivery and Google Calendar synchronization. | [Auth architecture](architecture.md#authentication), [Google/Supabase reference](https://supabase.com/docs/guides/auth/social-login/auth-google) |
| Cloudflare Turnstile | Hosted authentication CAPTCHA. Exact permitted hostnames and same-origin challenge flow; secret belongs to Auth configuration, not Flutter. | [Auth architecture](architecture.md#authentication), [Local/hosted configuration](local-dev.md) |
| Vercel | Builds/hosts Flutter web. Production `main` uses Pilot; branch Preview uses Staging. Frontend environment, project identity, public origin and redirect hosts must match. | [Local/hosted configuration](local-dev.md) |
| VPS FastAPI | Authenticated product commands, deterministic analyses, read-only Coach orchestration and optional push worker. One existing API service, not a second database. | [API](../services/ai_service/README.md), [VPS operations](../deploy/vps/README.md) |
| Caddy / HTTPS | Public reverse proxy to loopback API and the exact speech route. Coach executor remains on a private Unix socket; no public model port is required. | [VPS operations](../deploy/vps/README.md), [Speech](../services/speech_service/README.md) |
| Project Coach / Codex | Dedicated isolated executor, private provider login and rootless analysis container. Owner-only snapshot; no product writes. Separate user/global budgets and concurrency limits. | [Coach](phase-10-controlled-coach-plan.md), [VPS roles](../deploy/vps/PROJECT_ADMIN.md) |
| OpenAI / Gemini BYOK | User-selected paid provider, request-scoped key, bounded inspection/SQL tool results. Web keys live only in the current tab; Android uses encrypted local storage. Keys are not stored in Supabase, logs or snapshots. | [Coach](phase-10-controlled-coach-plan.md) |
| Server speech | Independent `mylifegraph-speech.service`: Parakeet TDT 0.6B V3 INT8, loopback inference, bounded in-memory audio, no recording persistence. | [Speech install/rollback](../services/speech_service/README.md) |
| On-device speech | Android downloads checksummed Whisper Tiny/Base multilingual or Parakeet V3 models, persists selected source/model and runs locally. No automatic server fallback or upload for on-device recordings. | [Coach/Speech](phase-10-controlled-coach-plan.md#flutter-contract) |
| Firebase / FCM | Android push delivery only; Spark/no linked billing. Existing VPS evaluates rules; Firebase is not the app database or backend compute. | [Push delivery](notification-delivery-v1-contract.md) |
| Android Health Connect | Optional consented foreground steps/sleep import, including data Garmin Connect makes available there. Source-tagged Cloud observations; no Garmin OAuth/developer API and no replacement of manual check-ins. | [Health Connect](health-connect-v1-contract.md) |
| Android Focus Protection | Device-local Accessibility blocking, Focus/weekly/always/temporary per-app rules, and Focus-only notification silencing. Rules combine; no synthetic Focus or Cloud records. | [Focus Protection](android-focus-protection-v1-contract.md) |
| GitHub Actions / Releases | CI, protected branches, signed Android builds and tagged release artifacts. An APK uses its compiled endpoints and does not load its UI from Vercel. | [Release workflows](../.github/workflows), [VPS release flow](../deploy/vps/README.md#build-and-release-flow) |
| Local laptop / optional dev VM | Supported Cloud frontend launcher for fast testing; separate guest and full local-stack workflows remain available. Do not restart a retired VM development stack or its migration-retry loop as a prerequisite for Cloud UI work. | [Local development](local-dev.md#personal-windows-browser-with-existing-cloud-accounts) |

## Push, import and model limits

- Android push: grouped due-today Tasks, a fresh reliable learned bedtime and a
  rare stable Focus-timing pattern. Explicit consent, category switches, quiet
  hours, two attempts per 24 hours and a 30-day pattern cooldown prevent spam.
  FCM acceptance is not proof of phone delivery. Web push is not implemented.
- Calendar is explicit read-only `.ics` import. Treating an import as busy only
  constrains new planning after confirmed import/consent; no Google live sync,
  provider writes or automatic rescheduling are implemented.
- Standard Coach and BYOK budgets differ; the general account allowance is
  shared, not an extra resettable balance for each model. Speech has its own
  bounded admission. See the [capacity assessment](architecture.md#concurrent-user-capacity-source-level-assessment)
  before increasing worker counts or admitting simultaneous model requests.
- Flag choices translate Coach responses and Ultra Quick speaking guides,
  not the whole application. Canonical Capture keys, required fields, Streak
  and correlation semantics remain unchanged.

## Secrets and safe continuation

- Protected GitHub environment `pilot-release` contains
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
  and `ANDROID_KEY_PASSWORD`. Workflows also inject
  `FIREBASE_ANDROID_CONFIG_BASE64` (public Android client configuration).
  Never paste values into this document or replace the signing identity casually.
- The private FCM sender credential is backend-only in protected API
  configuration (`FCM_CREDENTIALS_JSON`). Provider OAuth belongs only to its
  dedicated executor; agents must not read or copy the OAuth file.
- Google OAuth and Turnstile secrets remain in their provider/Auth dashboards;
  local `.env`, device stores and ignored operator files are not source artifacts.
- Start the laptop preview with `node scripts/start_cloud_frontend.mjs` after
  stopping only its existing launcher/Flutter process. It binds loopback web
  7357 and proxy 8003. Dart changes require a real Flutter restart here.
- A future release must review all dirty/untracked paths, run the appropriate
  captured-base checks, verify pending SQL against the actual target, then use
  the existing main/tag/CI/promotion workflow with explicit authorization.
  Do not rerun historical VPS bootstrap, reset data, copy demo credentials to
  public docs, or overwrite another maintainer's checkout.

The owner documents remain authoritative for details. This index intentionally
does not duplicate the complete schema inventory, private host addresses, test
counts or live deployment identifiers.
