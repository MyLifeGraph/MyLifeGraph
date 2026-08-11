# Notification Delivery V1 Contract

Notification Delivery V1 adds explicit consent, deterministic stored-item
generation, and foreground in-app delivery to the existing Inbox lifecycle. It
does not add browser, Android, email, push, or operating-system notifications.
Reminder configuration belongs exclusively to Settings; Setup neither reads
nor writes it. Configuration is never interpreted as delivery permission.

Read `docs/notification-lifecycle-v1-contract.md` for read/unread/dismiss
behavior. Delivery acknowledgement never changes those lifecycle fields.

## Boundaries

- Authenticated real accounts only. Guest/demo is zero-call for settings,
  generation, polling, and acknowledgement.
- Explicit consent version: `in-app-notification-consent-v1`.
- Settings contract: `notification-settings-v1`.
- Generation provenance: `notification-generation-v1`.
- Foreground receipt: `in-app-notification-delivery-v1`.
- Deterministic fixed copy only. `llm_used=false` is persisted and validated.
- No capture, intake, Coach, memory, calendar-event, or other private free text
  is copied into notification title or body.
- Delivery is local foreground UI: Flutter shows an acknowledged banner only
  while the app is open. A stored Inbox row alone is not a delivery claim.

## Explicit Consent And Settings

Existing `notification_preferences.focus_prompts_enabled`,
`recovery_prompts_enabled`, `weekly_summary_enabled`, and quiet-hour values do
not enable delivery. The migration adds `in_app_delivery_enabled` with a
fail-closed `false` default plus exact consent version/timestamps, a daily limit,
and latest settings request identity. The follow-up guard stores a SHA-256 of
the full request, including `expected_updated_at`; a matching UUID with a
different base revision or payload is a conflict, not a replay.

`focus_prompts_enabled` remains in the settings wire contract and database for
stored-data and older-client compatibility. Current Flutter no longer exposes
that switch, treats `focus_prompt` as ineligible for foreground delivery, and
FastAPI no longer generates the redundant generic Today reminder.

Flutter uses bearer-derived FastAPI routes:

- `GET /v1/notifications/settings`
- `PATCH /v1/notifications/settings`

The patch accepts exactly one UUID request id, the loaded `updated_at`, the
explicit consent version, the three category flags, an optional complete
`HH:mm` quiet-hours pair, and a daily limit from 1 through 5. The service-role
RPC takes the owner advisory lock, rejects stale writes with `PT409`, and replays
the latest exact request. An ambiguous client result retains that exact request
for unchanged retry; a definitive conflict disables all edits and saves until a
successful reload. The settings RPC keeps `updated_at` strictly monotone and no
earlier than retained consent timestamps. A historical shared-writer trigger
still protects any legacy projection change, but the 2026-07-25 Setup
compatibility wrapper performs no preference write: Setup leaves the row and
its replay identity untouched.

Disabling delivery does not delete stored Inbox rows. Re-enabling records a new
consent time. Changing categories while already disabled does not rewrite the
time at which consent was disabled.

The foreground-only limitation and consent consequence remain visible beside
the switch. Optional channel limits and copy methodology start closed under the
independent standard information control `Delivery details`; that description
states that fixed templates exclude private check-in details. Hiding the
description never hides consent state, categories, quiet hours, daily cap,
save/retry state, or the fact that banners require the app to be open.

## Deterministic Generation

The protected daily-refresh endpoint accepts `include_notifications=true` only
for the current profile-local day. Notification backfills with an explicit
`target_date` are rejected. The local runner enables the flag and invokes the
same bounded endpoint every 15 minutes; deployed cron remains out of scope.
Missing/stale Phase 7 preparation remains eligible independently of delivery
consent. A fully current profile enters a notification-only runner batch only
when its separate in-app consent projection is active; consent-off current
profiles cannot consume the bounded current-delivery slots.

For each eligible onboarded non-guest profile, FastAPI loads owner-scoped
settings and exact current sources, then proposes at most two candidates:

1. `recovery_prompt` for a valid current `recover` Daily State.
2. On Monday only, `weekly_summary` for the exact immediately completed ISO
   week. Generation reuses the Phase 8 read service, including its current
   source-fingerprint and snapshot check; an older or stale same-period review
   is not presented as current.

Daily State validation accepts historical V1/V2 and current
`explainable-daily-state-v3`. Notification generation uses only the validated
date and mode; it does not read or restore retired Day Shape context or
`constrained_capacity`.

A current daily briefing alone creates no notification. On an ordinary steady
day without a current Monday review, generation returns `no_candidate`.

The database RPC revalidates the profile timezone, local date, active explicit
consent, current category flag, quiet hours, daily limit, and owner-scoped
generation key while holding the owner lock. Dedupe keys are stable per
category/local date or weekly period, with an owner-unique partial index. Quiet
hours can cross midnight; equal legacy endpoints conservatively mean an all-day
quiet window. Incomplete legacy pairs are normalized to no quiet window before
the pair constraint is installed.

Generated rows persist bounded provenance: origin, category, reason code,
profile timezone, source kind/id/time, local delivery date, sensitive-copy
exclusion, and no-LLM truth. Source content is not persisted in provenance.
Generated rows count toward the local-date cap even if later dismissed, so
dismissal cannot create delivery churn.

## Foreground In-App Delivery

Flutter polls only for an authenticated real account. It first reads current
delivery settings; consent-off performs no pending-row query or acknowledgement.
The bounded pending query filters by the currently deliverable recovery and
weekly category codes before ordering and limiting. Legacy `focus_prompt` rows
remain readable in Inbox/export history but cannot starve or become a current
foreground banner. The controller validates the category again before ack.
For a pending generated row Flutter calls:

`POST /v1/notifications/{notification_id}/delivery`

The owner-locked RPC checks that the row is generated, due, active, not already
dismissed, and still allowed by current consent, category, profile timezone,
and quiet hours. It then stamps `in_app_delivered_at`. Flutter displays the
banner only after a non-replayed receipt. Concurrent clients get one original
receipt and replayed receipts; replayed receipts are never displayed. If the
first HTTP result is lost, the retry returns a replay and the client conserves
at-most-once presentation rather than inventing delivery.

The banner and Inbox expose the positive provenance `Rule-based reminder`.
Persisted and validated `llm_used=false` remains the underlying generation
truth, but the student UI does not repeat a prototype-style AI disclaimer on
each item. `action_url` still goes through the internal allowlist; newly
generated rows use Today for recovery or Weekly Review for the exact completed
week.
An actionable foreground banner uses a compact destination-specific label such
as `Open Today`; both that action and the banner body open the same allowlisted
route. The matching Inbox card uses the same destination label. Opening either
surface performs navigation only and does not imply a read, dismiss, generation,
or delivery mutation.
Those in-page internal actions push route history; the destination's shared
Back action therefore returns to the originating banner or Inbox surface. Shell
navigation still replaces history. This changes no lifecycle or delivery
receipt. Recovery copy describes a gentler overview and never exposes private
capture details. It does not claim that the app created, optimized, or chose a
plan. The former `Today's overview is ready` generic copy is retired.

## Authority And Data Lifecycle

- `notification_preferences` remains authenticated owner-readable but direct
  application-role mutation is revoked; Flutter settings write through
  FastAPI/service role only.
- `notifications` remains authenticated owner-readable and backend-owned for
  writes. Existing lifecycle actions remain the only read/unread/dismiss path.
- All three new RPCs are `service_role` only with a safe search path.
- Account export already includes the preference and notification tables, so
  the new columns require no omitted ledger or export-table-count change.
- Account deletion continues to cascade these rows with the existing owner
  data.

Notification settings, lifecycle, and foreground-delivery routes now delegate
their operation-specific service failures to typed feature-owned HTTP problem
translators. Existing not-found, conflict, outcome-unknown, unavailable status/
detail pairs and all consent, owner-lock, and acknowledgement authority remain
unchanged.

## Explicit Non-Claims

This contract does not claim remote Supabase verification, deployed scheduling,
background mobile execution, service workers, browser permission, FCM/APNs,
email/SMS, Android notification channels, snooze, provider delivery receipts,
or a production scheduler. It does not change the Controlled Coach provider or
model.

## Visual presentation

Inbox and notification controls use the shared
[Frontend Visual System V2](frontend-visual-system-v2.md). The migration changes
only presentation; consent, deterministic generation, quiet hours, caps,
foreground delivery, retry identity, and mutation authority remain unchanged.
Inbox grouping uses a shared subtle surface and Settings help uses the standard
44×44 information disclosure.
