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
| Exam and assignment preparation | Preparation plans |
| Weekly reflection | Weekly review |
| Imported calendar copy | Calendar |
| Stored notices | Inbox |
| Patterns and correlations | Insights |
| Development conversation surface | Coach |
| Durable preferences and account controls | Settings |

Versioned API and database names may remain technical. Do not leak those names
into a primary title, button, field label, or first-line error.

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
