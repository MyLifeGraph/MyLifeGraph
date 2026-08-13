# Account Controls Contract

This document defines the first complete account-management boundary for a
real authenticated MyLifeGraph account. It covers profile timezone changes, an
optional account-wide daily preparation budget, portable JSON export, password
recovery, and permanent account deletion. Guest and mock sessions remain local
and never call these endpoints.

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

`PATCH /v1/account/profile` accepts only `account-profile-update-v2`:

```json
{
  "contract_version": "account-profile-update-v2",
  "request_id": "11111111-1111-4111-8111-111111111111",
  "expected_revision": 1,
  "timezone": "Europe/Berlin"
}
```

The strict `account-profile-v2` response contains the persisted timezone, its
new revision, `updated_at`, and `replayed`. The backend validates the trimmed
IANA name and derives the owner from the bearer. The owner-locked
`apply_account_timezone_v2` RPC first recognizes an exact full-payload replay,
then compares `profiles.timezone_revision`. Two different changes from the
same revision cannot both commit. Reusing a request id with another operation
or payload conflicts.

Changing timezone never rewrites captures, calendar events, active plan blocks,
or confirmed reservations. Open Planner and Deadline previews become
unconfirmable; active plans receive `timezone_changed` attention. This
timezone remains the authority for backend product-local dates. Authenticated
Data API callers have no direct timezone write privilege.
After a successful response Flutter updates the session profile and therefore
the single profile-local date source used by Capture, Habit, Focus, Weekly
Review, Today-adjacent refreshes, and Preparation. Invalid or missing
authenticated IANA timezone data fails closed; only guest/no-account behavior
uses the device-local calendar. A typed timezone-change impact invalidates all
date-bound Flutter reads without importing their feature providers into
Settings. A preparation-budget change invalidates only Preparation Workload;
neither cache operation resends the committed account-setting mutation.

## Daily Preparation Budget

The current budget is an authoritative daily cap for
`exam-plan-health-v1`. A successful budget mutation invalidates the local
Health projection; a timezone mutation also invalidates it because deadlines,
Calendar coverage, latest-safe dates, and recommendations are profile-local.
Neither account command persists Health output or triggers automatic
rescheduling.

`PATCH /v1/account/preparation-budget` accepts only
`account-preparation-budget-update-v2`:

```json
{
  "contract_version": "account-preparation-budget-update-v2",
  "request_id": "22222222-2222-4222-8222-222222222222",
  "expected_revision": 1,
  "daily_preparation_budget_minutes": 120
}
```

The value is either `null` or an integer from 25 through 480 in five-minute
increments. `null` removes the account-wide rule and preserves Deadline
Planner's per-plan daily caps. Any number is explicit user input: it is neither
an effort estimate nor inferred availability, and no LLM chooses or changes it.
The strict response repeats the persisted nullable field, its new
`preparation_budget_revision`, `updated_at`, and `replayed`.

FastAPI derives the profile id only from the verified bearer and calls the
service-role-only owner-locked `apply_account_preparation_budget_v2` RPC.
Anonymous and
authenticated Data API callers cannot update the profile column directly. The
old `set_daily_preparation_budget_v1` function is no longer executable. The V2
RPC takes the shared owner advisory lock used by Deadline Planner confirmation,
checks exact replay before expected revision, and makes a concurrent budget
update and confirmation serializable. The planner's database trigger then
rechecks aggregate active preparation on the candidate revision's local dates
before activation.

After an ambiguous result FastAPI retries the identical request id, expected
revision, and payload. An exact replay may converge to success; an unresolved
result returns explicit outcome-unknown `502`. Changing the setting never
mutates existing plan revisions. A lower value can therefore expose truthful
`Needs review` overages until the student explicitly replans.

The profile field is included in Account Export as part of the existing
owner-scoped `profiles` row. It grants no new direct profile mutation authority.

## Account Export

`GET /v1/account/export` is side-effect free and returns the strict
`account-export-v4` JSON envelope. It removes Goals from the former bounded
owner product set and includes: `profiles`, `notification_preferences`,
`learning_preferences`, `daily_logs`,
`behavioral_events`, `lifestyle_entries`, `tasks`, `schedule_items`,
`notifications`, `coach_messages`, `memory_entries`, `ai_insights`,
`recommendations`, `skillset_profiles`, `habits`, `habit_logs`,
`focus_sessions`, `focus_session_schedule_sources`,
`focus_session_reflections`, `intake_responses`,
`study_setup_profiles`,
`user_state_snapshots`, `daily_briefings`, `decision_feedback`,
`weekly_reviews`, `calendar_connections`,
`calendar_imports`, `calendar_events`, `coach_requests`, `coach_usage_events`,
`coach_memory_selections`, `deadline_plans`, `deadline_plan_revisions`, and
`deadline_plan_blocks`, `assignment_series`,
`assignment_series_revisions`, `assignment_series_revision_items`,
`planner_preferences`, `planner_action_plans`,
`planner_action_plan_revisions`, `planner_task_blocks`, `planner_habit_slots`,
and `planner_commitments`. It returns exact per-table record counts, an export
timestamp, bounds, and an explicit ledger policy. Calendar
connection/import and Coach request/usage rows use field allowlists so
backend-only details are not leaked. `notification_preferences` includes the
owner's current prompt flags, quiet hours, in-app delivery enabled/consent
state and timestamps, and daily notification limit; its backend request
identity and fingerprint remain excluded. The global `calendar_request_identities`,
`notification_action_requests`, `deadline_plan_request_identities`, and
`planner_request_identities`, `learning_request_identities`,
`daily_capture_request_identities`, and
`account_setting_request_identities`, and
`assignment_series_request_identities` anti-replay ledgers are deliberately
omitted and named in that policy. Deadline
plan, revision, block, and Assignment Series content rows remain bounded owner
product data; their opaque request fingerprints are not part of the export.
Private `multi-exam-plan-v1` batch/revision/item/link/request rows are derived
orchestration metadata rather than public owner-content tables and are omitted
from `account-export-v4`. The actual affected Exam content is already present
as Deadline plan/revision/block rows. Adding balance history would require a new
export contract version; V4 is not widened with a second shape.
Study Setup exports the
current owner projection only; transient preparation-checklist decisions and
local recovery countdown state do not exist in the export. Personal Learning
exports the current complete preference projection and raw owner reflection
rows; clearing reflection history removes only those reflection rows.

The table list, owner key, bounded cursor/watermark read shape, sanitized-export
decision, omission decision, and separate Coach Snapshot participation are
derived from the typed FastAPI owner-data catalog. Every repo-owned public
table, including an operational ledger that participates in neither output,
must have exactly one catalog entry. The export response contract uses the
exact 43-table V4 shape above; the new disclosure is limited to the three
owner-content Assignment Series projections and does not include its request
ledger. Flutter's strict export allowlist uses the same catalog
order, including `focus_session_schedule_sources`, before it accepts the record
counts or saves the original response bytes.

`20260714110000_account_export_lifestyle_entries_grant.sql` gives only the
verified-bearer FastAPI path's `service_role` client the missing `SELECT` grant
on `lifestyle_entries`; Flutter and anonymous callers gain no new table
authority.

The V4 bounds remain 10,000 rows per table, 50,000 rows overall, and 8 MiB of
JSON.
Exceeding a bound is an explicit `413`, never a silently truncated export.
Supabase pages are stream-bounded before JSON materialization, and cumulative
JSON growth is checked before retaining each row. Reads use immutable keyset
cursors plus a server-derived upper watermark per table, avoiding offset skips
and excluding normal later inserts. These separate reads are intentionally not
a cross-table point-in-time transaction snapshot. The neutral owner-data reader
captures every table-local watermark before starting row collection, then loads
independent tables through a bounded task pool. Page order remains keyset order,
the final envelope remains catalog ordered regardless of completion order, and
failure or cancellation cancels and settles sibling reads before returning.
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

The student-facing account entry names its modes `Sign in` and `Create account`.
Recovery is presented on a shared raised surface, keeps validation and completion
feedback visible, and maps missing configuration or OAuth failures to
provider-neutral guidance. It never renders Supabase, transport, status-code,
or raw contract detail even though Supabase remains the technical token owner.

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

Migration `20260802111518_privileged_function_lint_cleanup.sql` redefines the
same service-role-only Account Delete RPC without its redundant declared loop
index. The three integer `FOR` loops still use their identical automatically
scoped index, and confirmation, locks, dynamic legacy validation/deletion,
canonical/Auth cascade, result, fixed search path, signature, and grants remain
unchanged.

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
- The preparation budget is a transparent limit over confirmed Deadline
  Planner reservations, not a prediction of capacity, a complete calendar/free-
  time calculation, or authority to rewrite existing plans.
- Guest data has no synced account to export or delete. Guest Setup is not
  silently migrated into a later account.

## Verification Boundary

Standard tests cover strict models, owner derivation, ambiguous-operation
replay, exact nullable budget persistence/readback, five-minute bounds, direct
profile-write denial, shared owner locking, streamed export bounds/ownership/
keyset behavior, migration grants, Calendar/Deadline Planner/focus/legacy lock
ordering, planner product-row inclusion and ledger omission, full planner
cascade, legacy mutation freeze, Flutter contract parsing, recovery state,
theme persistence, and account-control widgets including 320-pixel/200-percent
text scaling. A live
deletion requires an intentionally disposable local account and must never be
performed as part of a non-destructive audit or against an unconfirmed remote
project.

The Flutter account parsers reuse framework-neutral strict primitives for
exact keys, string-keyed objects, aware timestamps, and integer bounds. Account
export table/count equality, ledger policy, byte/row ceilings, and typed account
errors remain feature-owned; this changes no V2 wire value or rejection.

The FastAPI route now obtains the application-lifespan-owned Supabase client
instead of constructing a transport per request. This changes only connection
reuse: bearer-derived ownership, streamed bounds, retry behavior, service-role
authority, and every account RPC contract above are unchanged.

The HTTP layer also depends only on account-service failures. Supabase/REST and
RPC-specific repository exceptions are translated inside `AccountService` to
not-found, conflict, outcome-unknown, unavailable, or export-too-large service
outcomes before the route maps them to status codes. This is a layering change
only; it does not broaden retries, expose provider detail, or alter any owner,
watermark, page, JSON, CAS, or deletion boundary.

The route delegates those service outcomes to typed, operation-specific
account problem translators. The established status codes, public details,
export headers, recent-authentication guard, and unexpected-error behavior are
unchanged.
