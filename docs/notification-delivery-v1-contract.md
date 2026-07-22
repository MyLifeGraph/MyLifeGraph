# Notification Delivery V1 Contract

Notification Delivery V1 adds explicit consent, deterministic stored-item
generation, and foreground in-app delivery to the existing Inbox lifecycle. It
does not add browser, Android, email, push, or operating-system notifications.
The stored reminder preference from Setup is configuration input only and is
never interpreted as delivery permission.

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

Flutter uses bearer-derived FastAPI routes:

- `GET /v1/notifications/settings`
- `PATCH /v1/notifications/settings`

The patch accepts exactly one UUID request id, the loaded `updated_at`, the
explicit consent version, the three category flags, an optional complete
`HH:mm` quiet-hours pair, and a daily limit from 1 through 5. The service-role
RPC takes the owner advisory lock, rejects stale writes with `PT409`, and replays
the latest exact request. An ambiguous client result retains that exact request
for unchanged retry; a definitive conflict disables all edits and saves until a
successful reload. Intake Setup shares the preference row, so its trigger clears
the old delivery request identity on a real projection change and keeps
`updated_at` strictly monotone and no earlier than retained consent timestamps.

Disabling delivery does not delete stored Inbox rows. Re-enabling records a new
consent time. Changing categories while already disabled does not rewrite the
time at which consent was disabled.

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

1. `recovery_prompt` for a valid current `recover` Daily State. It suppresses
   the generic focus candidate for that date.
2. Otherwise `focus_prompt` for a briefing whose snapshot id and generation
   time match the current daily snapshot.
3. On Monday only, `weekly_summary` for the exact immediately completed ISO
   week. Generation reuses the Phase 8 read service, including its current
   source-fingerprint and snapshot check; an older or stale same-period review
   is not presented as current.

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
The bounded pending query filters by the currently enabled category codes before
ordering and limiting, so old rows from a disabled category cannot starve a
later allowed banner. The controller validates the category again before ack.
For a pending generated row Flutter calls:

`POST /v1/notifications/{notification_id}/delivery`

The owner-locked RPC checks that the row is generated, due, active, not already
dismissed, and still allowed by current consent, category, profile timezone,
and quiet hours. It then stamps `in_app_delivered_at`. Flutter displays the
banner only after a non-replayed receipt. Concurrent clients get one original
receipt and replayed receipts; replayed receipts are never displayed. If the
first HTTP result is lost, the retry returns a replay and the client conserves
at-most-once presentation rather than inventing delivery.

The banner and Inbox expose deterministic/no-LLM truth. `action_url` still goes
through the internal allowlist; generated rows use only Today or Weekly Review.
The fixed generic Today copy is `Today's overview is ready` / `Open Today to
review your schedule and actions.` Recovery copy similarly describes a gentler
overview and never exposes private capture details. It does not claim that the
app created, optimized, or chose a plan.

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

## Explicit Non-Claims

This contract does not claim remote Supabase verification, deployed scheduling,
background mobile execution, service workers, browser permission, FCM/APNs,
email/SMS, Android notification channels, snooze, provider delivery receipts,
or a production scheduler. It does not change the Controlled Coach provider or
model.
