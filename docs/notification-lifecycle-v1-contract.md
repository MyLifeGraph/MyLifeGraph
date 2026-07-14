# Notification Lifecycle V1 Contract

This document defines the first durable lifecycle boundary for stored Inbox
items. It covers reading visible rows, marking them read or unread, and
dismissing them. It does not itself define notification generation, scheduling,
or permission consent; the later local foreground boundary is specified
separately in `docs/notification-delivery-v1-contract.md`.

## Trust Boundary

- Only a real authenticated, non-demo account may mutate a stored Inbox item.
- Flutter reads owner-visible `notifications` rows directly through Supabase,
  but sends every lifecycle command to FastAPI with the current bearer token.
- FastAPI derives `user_id` only from the verified bearer principal. No request
  body, path, or query field may select another owner.
- FastAPI is the only application boundary allowed to call the service-role RPC.
  `anon` and `authenticated` retain no direct insert, update, delete, or
  truncate authority on `notifications`.
- The subsequent application-table privilege guard also removes reusable
  `REFERENCES` and `TRIGGER` authority, makes `anon` fail closed across the
  complete repo-owned table surface, and leaves the intended owner read plus
  FastAPI/service-role lifecycle boundary unchanged.
- Guest and mock/demo modes use only local example rows, expose no lifecycle
  buttons, and make no Supabase or FastAPI notification call.

## Visible Inbox Read

The authenticated Inbox reads at most the latest 30 owner rows where:

- `dismissed_at` is null; and
- `due_at` is null or no later than the captured current UTC instant.

Rows are ordered by `created_at` descending. The UI reports that its counts
cover only those loaded rows. A stored row proves only that an Inbox item
exists; it does not prove that a Web, local, push, email, or other notification
was delivered.

The strict row projection includes `id`, visible copy and category fields,
`action_url`, `created_at`, `updated_at`, `is_read`, `read_at`, `dismissed_at`,
and `due_at`. Unknown, missing, malformed, naive-timestamp, or internally
inconsistent rows fail the real-data load instead of becoming mock content.
Only the existing internal route allowlist may turn `action_url` into an Open
button.

## Lifecycle Endpoint

`POST /v1/notifications/{notification_id}/actions` accepts exactly:

```json
{
  "contract_version": "notification-lifecycle-v1",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "command": "mark_read",
  "expected_updated_at": "2026-07-14T08:30:00Z"
}
```

`request_id` is a client-generated UUID. `command` is exactly `mark_read`,
`mark_unread`, or `dismiss`. `expected_updated_at` is the timezone-aware value
from the row on which the user acted. Unknown or coerced fields are rejected.

The exact success response is:

```json
{
  "contract_version": "notification-lifecycle-v1",
  "notification_id": "22222222-2222-4222-8222-222222222222",
  "command": "mark_read",
  "is_read": true,
  "read_at": "2026-07-14T08:31:00Z",
  "dismissed_at": null,
  "updated_at": "2026-07-14T08:31:00Z",
  "replayed": false
}
```

Response timestamps are timezone-aware. `is_read` is true exactly when
`read_at` is non-null, and neither lifecycle timestamp may be newer than
`updated_at`. A dismiss response is always read and has a non-null
`dismissed_at`.

## Command Semantics

| Command | Durable result |
| --- | --- |
| `mark_read` | An active unread row becomes read and receives matching `read_at` and `updated_at`; an already-read active row is an idempotent no-op. |
| `mark_unread` | An active read row becomes unread, clears `read_at`, and advances `updated_at`; an already-unread active row is an idempotent no-op. |
| `dismiss` | The row remains as a read tombstone, receives `dismissed_at`, and disappears from normal Inbox reads. It is not hard-deleted. |

Every state-changing timestamp is strictly later than the row's prior
`updated_at`, including when the database clock would otherwise compare equal.
The schema keeps `is_read`, `read_at`, and `dismissed_at` consistent. Existing
read rows receive a deterministic `read_at` backfill from their previously
persisted update or creation time before those constraints are enabled.

## Retry, Replay, And Conflict Rules

The database keeps one global service-role-only
`notification_action_requests` row per `request_id`. It stores request identity
and the exact result projection, but no notification title or message.

- An exact replay of owner, notification, command, and expected timestamp
  returns the stored result with `replayed=true` and performs no second
  mutation.
- Reusing a request id with any different identity is `409`.
- A current row whose `updated_at` no longer equals `expected_updated_at` is
  `409`; the client must reload before acting on the new state.
- A dismissed row is not reinterpreted by a new request and returns `409`.
- A missing or foreign-owned notification is the same owner-safe `404`.
- FastAPI retries one ambiguous service-role call with the exact same request.
  Two unresolved transport, upstream `5xx`, or invalid-response outcomes become
  explicit outcome-unknown `502`.
- Configuration or non-ambiguous persistence unavailability is `503`; it is
  never reported as a successful local mutation.

Flutter keeps the item and shows a row-scoped pending/error state. An ambiguous
outcome permits only the exact stored request to be retried. A definite
conflict offers reload so the stale expected timestamp is not silently
overwritten. Dismissal removes the card only after a validated success result.

The RPC takes the existing owner workflow advisory lock before its request and
row locks. Full-account deletion takes the same owner-first boundary, and the
ledger's composite notification-owner foreign key cascades with its owning
notification.

## Account Export And Deletion

The visible `notifications` rows, including lifecycle timestamps, remain part
of the bounded 28-table `account-export-v1` payload. The backend-only
`notification_action_requests` anti-replay ledger is explicitly named as
omitted, just like the Calendar request-identity ledger. Its omission does not
change the exported table count.

Permanent account deletion cascades both stored notifications and their action
request identities in the same owner-locked account-deletion workflow.

## Explicit Non-Claims

- This contract does not generate an Inbox row.
- Existing Setup reminder preferences are not delivery permission and must not
  silently authorize a future delivery channel.
- Notification Delivery V1 separately defines explicit in-app consent,
  timezone/quiet/category/cap/dedupe guards, local generation, and foreground
  acknowledgement. This lifecycle contract still implies none of those merely
  from a stored row or lifecycle action.
- Browser/system Web notifications, Android notification permission, FCM,
  push-token storage, email, and background delivery remain unimplemented.
- A repository migration is not claimed to be applied to any remote Supabase
  project.

## Verification Boundary

Standard tests cover strict FastAPI and Flutter envelopes, state invariants,
owner derivation, exact ambiguous replay, conflict/error mapping, retained
loaded data, row-scoped retry, loading/empty/error states, accessibility, due
filtering, migration grants, forced RLS, and account export/deletion policy.
Local Supabase and browser verification must additionally prove all three
commands, exact replay, request-id reinterpretation conflict, owner isolation,
direct authenticated DML rejection, dismiss persistence, and disappearance on
reload before this slice is called end-to-end complete.
