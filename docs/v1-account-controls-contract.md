# V1 Account Controls Contract

This document defines the first complete account-management boundary for a
real authenticated MyLifeGraph account. It covers profile timezone changes,
portable JSON export, password recovery, and permanent account deletion. Guest
and mock sessions remain local and never call these endpoints.

## Trust Boundary

- Every FastAPI account endpoint requires the normal verified Supabase bearer
  token. The owner id is derived only from that principal and is never accepted
  from a Flutter request body or query parameter.
- Flutter exposes the controls only when a real authenticated Supabase session
  and synced-product capability are present.
- FastAPI uses the service-role client only after bearer verification. The
  Flutter client never receives a service-role credential or direct authority
  to mutate protected account state.
- Network, configuration, persistence, invalid-response, and cancellation
  outcomes stay distinct from success. Guest/mock never receives fabricated
  synced-account results.
- `notifications`, `ai_insights`, `recommendations`, and `skillset_profiles`
  are authenticated read-only Data API projections. Notification Lifecycle V1
  later added explicit FastAPI/service-role read/unread/dismiss commands without
  restoring direct authenticated DML.

## Profile Timezone

`PATCH /v1/account/profile` accepts exactly:

```json
{"timezone":"Europe/Berlin"}
```

The backend accepts a trimmed stable IANA timezone name, validates it with the
runtime timezone database, updates only the principal's `profiles` row, and
returns exactly the persisted timezone. This timezone controls backend-owned
product-local date resolution for briefings, weekly reviews, calendar import,
scheduling, Deadline Planner proposals, and Coach budgets. The current Flutter
capture flows still derive
their explicit capture date from the device-local clock; changing the account
timezone does not retroactively reinterpret or silently move those rows.
Authenticated Data API callers have no direct `profiles.timezone` update
privilege. New canonical and still-present legacy Auth projections default to
`UTC`; the migration does not rewrite any existing user's selected timezone.
An ambiguous PATCH is retried once with the same idempotent value. Only an exact
retry representation or persisted-value readback may then converge to success;
an unresolved outcome is an explicit `502`.

## Account Export

`GET /v1/account/export` is side-effect free and returns the strict
`account-export-v1` JSON envelope. It includes bounded owner rows from these 31
V1 product tables: `profiles`, `notification_preferences`, `daily_logs`,
`behavioral_events`, `lifestyle_entries`, `tasks`, `schedule_items`,
`notifications`, `coach_messages`, `memory_entries`, `ai_insights`,
`recommendations`, `skillset_profiles`, `goals`, `habits`, `habit_logs`,
`focus_sessions`, `intake_responses`, `user_state_snapshots`, `daily_briefings`,
`decision_feedback`, `weekly_reviews`, `calendar_connections`,
`calendar_imports`, `calendar_events`, `coach_requests`, `coach_usage_events`,
`coach_memory_selections`, `deadline_plans`, `deadline_plan_revisions`, and
`deadline_plan_blocks`. It returns exact per-table record counts, an export
timestamp, bounds, and an explicit ledger policy. Calendar
connection/import and Coach request/usage rows use field allowlists so
backend-only details are not leaked. The global `calendar_request_identities`,
`notification_action_requests`, and `deadline_plan_request_identities` anti-
replay ledgers are deliberately omitted and named in that policy. Deadline
plan, revision, and block rows remain bounded owner product data; their opaque
request fingerprints are not part of the export.

`20260714110000_account_export_lifestyle_entries_grant.sql` gives only the
verified-bearer FastAPI path's `service_role` client the missing `SELECT` grant
on `lifestyle_entries`; Flutter and anonymous callers gain no new table
authority.

The V1 bounds are 10,000 rows per table, 50,000 rows overall, and 8 MiB of JSON.
Exceeding a bound is an explicit `413`, never a silently truncated export.
Supabase pages are stream-bounded before JSON materialization, and cumulative
JSON growth is checked before retaining each row. Reads use immutable keyset
cursors plus a server-derived upper watermark per table, avoiding offset skips
and excluding normal later inserts. These separate reads are intentionally not
a cross-table point-in-time transaction snapshot.
The backend requests at most 1,000 bounded rows per page, so the 50,000-row
contract edge does not devolve into thousands of serial REST round trips.
Responses use `Cache-Control: no-store` and a download filename. Flutter
uses a dedicated two-minute response wait for this materialized endpoint, then
validates the complete envelope and record counts before presenting it. The
bounded Supabase reader parses decimal values without binary floating-point
rounding, the backend serializes those values losslessly, and Flutter saves the
validated original UTF-8 response bytes so large integers and precise decimals
are not changed by a decode/re-encode cycle. Web
uses a browser download and desktop uses a cancellable save-location dialog; a
cancelled destination writes no application-selected file. Android hands a
dedicated temporary source file to the platform share sheet, deletes that
source best-effort after the handoff, and clears stale files from its dedicated
cache root before the next export. The share plugin or operating system may
retain a protected cache copy until its own cleanup, so dismissing the share
sheet is reported separately from a desktop/web cancellation. The code has an
iOS share path, but this repository has no iOS runner and makes no installed-iOS
acceptance claim.

## Password Recovery

Email login exposes a non-enumerating reset request. Registration exposes a
confirmation-email resend. Supabase owns the reset token and link. Flutter
enters the dedicated recovery route only after Supabase emits a password
recovery auth event, requires a matching password of at least eight characters,
updates it through Supabase Auth, and then leaves recovery state. Cancelling
clears the local auth session and returns to login.

Web recovery returns to the allowlisted local origin. Installed Android signup,
recovery, and OAuth return through
`com.mylifegraph.app://login-callback/`; the remote Supabase project must
allowlist that exact callback. Native iOS callback handling is outside the
current repository boundary.

## Permanent Deletion

`DELETE /v1/account` accepts only the exact body:

```json
{"confirmation":"DELETE"}
```

Flutter requires the same typed confirmation. FastAPI calls only the
service-role-only `delete_account_v1` RPC. Before that RPC is called, the
same verified Supabase bearer JWT must contain a valid `session_id` and a
recognized, non-refresh Authentication Methods Reference (`amr`) timestamp no
more than 15 minutes old. The JWT is accepted by Supabase Auth before these
bounded claims are read; its `sub` must match that verified user. Missing,
stale, invalid, refresh-only, or materially future evidence returns `403`
without starting deletion. A different session's recent account sign-in cannot
satisfy the guard, and a token refresh does not replace the original session
authentication timestamp. Flutter keeps the session open and asks the user to
sign out, sign in again, and return to the deletion control.

The RPC validates the owner and confirmation, takes the existing owner workflow
advisory locks in fixed order, locks Calendar request identities before their
connection rows, serializes Deadline Planner requests under the same owner lock,
locks the Auth and profile rows, and write-blocks every mapped
CamelCase legacy table before cleanup. It removes the two Phase 3
`ON DELETE RESTRICT` focus links and all provably owner-mapped legacy rows before
deleting `auth.users`. The existing `auth.users -> profiles -> owned product
rows` foreign-key cascade removes deadline plans, immutable revisions/blocks,
and their retry ledger in the same database transaction, and both canonical and
legacy postconditions are checked before the exact typed result is returned.

An exact `deleted` or idempotent `not_found` RPC result returns `204` without a
separate fallible profile read. After a transport, retryable `5xx`, JSON, or
shape-ambiguous outcome, FastAPI replays the same retry-safe RPC once. Its locks
serialize that replay behind any still-running first transaction. If the replay
is also unresolved, FastAPI returns explicit outcome-unknown `502` rather than
claiming either success or failure from an MVCC profile read.

Normal task/habit deletion semantics remain unchanged. Only this full-account
RPC may remove focus history before deleting its targets. After a confirmed
backend deletion, Flutter clears local auth state even if a remote sign-out can
no longer find the deleted user.

The account-deletion migration also revokes application-role mutation of all
known CamelCase tables. Those tables have no canonical profile FK, so this
prevents an already-issued JWT from recreating legacy owner rows after Auth
deletion.

## Explicit Non-Claims

- The app does not claim that a repository migration is already applied to a
  remote Supabase project.
- Export is a bounded user-data portability feature, not a legal-compliance
  certification, a database backup/restore format, or a cross-table
  point-in-time snapshot. Concurrent updates or deletions can still be reflected
  between its table reads.
- A mobile share handoff cannot promise immediate erasure of plugin- or
  operating-system-managed protected cache copies. The app removes only its own
  dedicated temporary source best-effort.
- Account deletion is permanent and has no undo, retention recovery, or remote
  provider-calendar deletion behavior.
- Guest data has no synced account to export or delete. Guest Setup is not
  silently migrated into a later account.

## Verification Boundary

Standard tests cover strict models, owner derivation, ambiguous-operation
replay, streamed export bounds/ownership/keyset behavior, migration grants,
Calendar/Deadline Planner/focus/legacy lock ordering, planner product-row
inclusion and ledger omission, full planner cascade, legacy mutation freeze,
Flutter contract parsing, recovery state, theme persistence, and account-
control widgets. A live
deletion requires an intentionally disposable local account and must never be
performed as part of a non-destructive audit or against an unconfirmed remote
project.
