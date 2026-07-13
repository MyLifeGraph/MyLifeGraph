# Phase 9 Calendar Import Contract

Status: implementation contract for the first bounded Phase 9 optional
integration. This slice imports a user-selected iCalendar file. It is not a
provider OAuth, background sync, or calendar-write contract.

## Scope

Phase 9 begins with one optional, explicit, read-only calendar source:

- an authenticated real-data user creates one `ical_file` import source after
  explicit consent;
- the user deliberately selects and imports a UTF-8 `.ics` file;
- FastAPI parses a bounded event window and persists only whitelisted event
  basics in dedicated backend-owned tables;
- imported events remain visibly `Imported · read-only` and never become
  `schedule_items`, tasks, goals, habits, recommendations, or briefings;
- disconnect stops further imports into that source but retains the imported
  copy;
- delete imported data removes the local event content and import history but
  never contacts or mutates the source calendar.

The standalone Setup, capture, Today, Weekly Review, Insights, task, habit, and
focus loops remain fully useful without this integration. Setup's existing
`calendar_connection_intent` answer is interest only. It is never consent and
must not create a connection or import data.

This slice adds no Google/Microsoft/Apple OAuth, provider access or refresh
token, arbitrary calendar URL fetch, webhook, incremental cursor, background
sync, provider write, LLM processing, notification, or deployed job. Supabase
Google sign-in authenticates the app only and is not calendar authorization.

## Contracts And Provenance

The public contract version is `calendar-import-v1`. Consent is the exact
`calendar-import-consent-v1` shape:

```json
{
  "consent_version": "calendar-import-consent-v1",
  "read_calendar_events": true,
  "store_event_basics": true,
  "provider_writes": false,
  "llm_processing": false
}
```

The backend records the server consent time. No omitted, false read/store, true
provider-write, true LLM-processing, unknown, null, or coerced field is accepted.
The Flutter consent checkbox starts unchecked even when Setup recorded calendar
interest.

Every returned connection and event identifies:

- `origin=authenticated_backend`;
- `source_kind=ical_file`;
- `contract_version=calendar-import-v1`;
- the user-chosen bounded source label;
- `provider_writes=false` and `llm_processed=false`.

Guest and mock sessions use an explicit local-demo state, make zero calendar API
calls, and never fabricate a connected source or imported event.

## HTTP Boundary

```text
GET    /v1/calendar-integrations
POST   /v1/calendar-integrations/connections
POST   /v1/calendar-integrations/connections/{connection_id}/imports
GET    /v1/calendar-integrations/connections/{connection_id}/events
POST   /v1/calendar-integrations/connections/{connection_id}/disconnect
DELETE /v1/calendar-integrations/connections/{connection_id}/imported-data?request_id=<uuid>
Authorization: Bearer <supabase_access_token>
```

Every route derives the owner from the verified bearer principal and rejects a
request-provided `user_id`. An unknown or other-owner connection is reported as
not found without revealing its existence.

Both GET routes are read-only. They never parse a file, contact an external
provider, generate a proposal, or change persistence. Normal Dashboard and
Settings loads never import.

### Public Response Envelopes

The connection read plus create, disconnect, and imported-data deletion return
exactly:

```json
{
  "contract_version": "calendar-import-v1",
  "origin": "authenticated_backend",
  "connection": null
}
```

`connection` is null only when no source exists. Otherwise it contains exactly
`id`, `contract_version`, `origin`, `source_kind`, `source_label`, `status`,
`consent`, `consented_at`, `connected_at`, `provider_writes`, and
`llm_processed`. `disconnected_at`, `imported_data_deleted_at`, and
`last_import` are present only when applicable; optional keys are omitted and
are never returned as explicit nulls. Internal replay or deletion counts do not
leak through this public envelope.

An import returns the same non-null connection envelope plus required key
`import`. That summary contains exactly `id`, `imported_at`, `window`, `counts`,
and `source_fingerprint`. The window contains `starts_on`, exclusive
`ends_before`, and `timezone`. Event reads return exactly
`contract_version`, `origin`, `connection_id`, `events`, and, only when
applicable, `import_id` and `next_cursor`.

Each event contains `id`, `title`, optional `location`, `event_kind`,
`busy_status`, `event_status`, `event_timezone`, `timezone_source`,
`imported_at`, `last_seen_at`, `source_fingerprint`, and exact integration
`provenance`. A timed event additionally contains aware `starts_at` and
`ends_at` plus naive backend-owned `local_starts_at` and `local_ends_at`. An
all-day event contains `starts_on` and exclusive `ends_on` instead. External
UIDs, recurrence ids, raw import text, and inapplicable explicit-null fields are
never returned.

### Create Connection

The create body contains exactly:

```json
{
  "request_id": "11111111-1111-4111-8111-111111111111",
  "source_kind": "ical_file",
  "source_label": "Work calendar",
  "consent": {
    "consent_version": "calendar-import-consent-v1",
    "read_calendar_events": true,
    "store_event_basics": true,
    "provider_writes": false,
    "llm_processing": false
  }
}
```

The label is trimmed and contains 1 to 80 characters. V1 permits at most one
current source per user. That current row may be connected or disconnected with
retained imported data. The retained data must be deleted before another source
is created, so it never becomes hidden behind a newer connection. After that
deletion, a new current row may be created while the old minimal tombstone
remains for retry/audit. The singular GET returns the current row when one
exists, otherwise the newest tombstone.

`request_id` and a server-computed request fingerprint make create retry-safe.
The same request and payload returns the same connection while that connection
remains the current connected source. Once its lifecycle advances through
disconnect/delete or a newer current source exists, replay returns conflict and
requires a current-state reload. The same request id with different content
always returns conflict.

Creating a source does not import a file. `connected` means consent is active
and the source can accept deliberate file imports; it does not imply live
provider access or automatic sync.

### Import File

The import body contains exactly:

```json
{
  "request_id": "22222222-2222-4222-8222-222222222222",
  "calendar_text": "BEGIN:VCALENDAR\r\n...\r\nEND:VCALENDAR\r\n"
}
```

The source must be connected. The payload must be valid UTF-8 iCalendar text,
at most 512 KiB. One import may inspect at most 2,000 `VEVENT` components and
persist at most 500 accepted occurrences. Exceeding a bound rejects the complete
import rather than truncating it.

FastAPI resolves one profile-local import window from one aware server instant:

- starts on the profile-local date 14 days before import;
- ends at the exclusive profile-local date 91 days after import;
- uses the profile's valid stored IANA timezone;
- reports that exact date window and timezone in the result.

No client timezone or device-local conversion owns the window.

The same `(user_id, request_id)` plus exact connection and input fingerprint
replays the still-current persisted import without applying events again; its
original window and timezone stay pinned even across profile-local midnight or
a later profile-timezone edit. Reusing a request id with different content or
connection returns conflict. Retrying an older request after a newer import has
superseded it also returns conflict and requires a current-state reload, so an
old import summary is never paired with a newer connection projection. An
ambiguous client response retains the exact request id and selected file for
unchanged retry or explicit reload.

The import response reports bounded counts for accepted, cancelled,
out-of-window, unsupported-recurring, and invalid components. Invalid individual
components may be skipped only for documented component-level format or
timezone failures. A duplicate identity with different whitelisted content,
an invalid calendar envelope, or an exceeded safety bound rejects the entire
import and leaves the previous event set unchanged.

### Event Reads And Pagination

Event reads are connection-scoped and return at most 50 items. The backend uses
one stable canonical order and an opaque cursor tied to the current successful
import id. A cursor from an older import is stale and must be reloaded from the
first page; it must not silently skip or duplicate rows after replacement.

Flutter renders the backend-provided event-local date/time projection and IANA
timezone. It must not call `toLocal()` and silently substitute the browser or
device timezone.

## iCalendar V1 Boundary

The parser supports unfolded `VCALENDAR`/`VEVENT` content and persists only:

- `UID`;
- optional `RECURRENCE-ID` for an already expanded or overridden occurrence;
- `DTSTART` and `DTEND`;
- bounded `SUMMARY` and `LOCATION`;
- `STATUS`, `TRANSP`, and optional `LAST-MODIFIED` needed for read semantics.

Descriptions, attendees, organizer addresses, conferencing links, alarms,
attachments, and unknown provider payload are not persisted or copied into
snapshots, recommendations, prompts, logs, or provenance.

### Timed Events

- UTC values ending in `Z` are accepted as `UTC`.
- A date-time with a valid IANA `TZID` is resolved in that timezone.
- A floating date-time is resolved explicitly in the profile timezone and
  records that fallback.
- Start and end must form a positive interval and use a coherent timezone
  interpretation.
- Persisted UTC instants and event-local projections must round-trip to the same
  interval, including DST boundaries. Nonexistent or ambiguous local wall times
  are rejected rather than guessed.

### All-Day Events

- `VALUE=DATE` is stored as exact local `starts_on` and exclusive `ends_on`.
- A missing all-day end means one day.
- All-day values are never represented as fabricated midnight UTC instants.

### Recurrence And Cancellation

V1 does not implement an RRULE engine. A master containing `RRULE`, `RDATE`, or
`EXDATE` without an explicit `RECURRENCE-ID` is counted as
`unsupported_recurring` and is not imported. An explicitly materialized
occurrence with `RECURRENCE-ID`, `DTSTART`, and `DTEND` is accepted and uses the
recurrence identity rather than its possibly moved start time.

`STATUS:CANCELLED` is a tombstone, not a visible event. Reconciliation removes
the corresponding prior local occurrence. Only a completely parsed bounded
snapshot may remove prior events; a failed import performs no deletion.

## Deterministic Identity And Reconciliation

An event identity is derived from:

```text
calendar-import-v1 namespace
  + connection_id
  + exact UID
  + `single` or normalized RECURRENCE-ID
```

Moving or editing one occurrence keeps its app event id. The canonical event
fingerprint covers only persisted whitelisted fields. Identical duplicates in a
file are deduplicated; conflicting duplicates reject the import.

One service-role-only atomic database operation serializes import per connection
and performs all of the following or none:

1. validates the connected owner/source and exact request identity;
2. replays an existing matching import unchanged;
3. upserts the canonical bounded event set;
4. removes prior current-copy events that are absent or cancelled in the new
   complete bounded snapshot;
5. inserts one completed import identity and counts;
6. updates the connection's last successful import projection.

The operation cannot touch another user's connection or event. Composite owner
foreign keys keep duplicated `user_id` fields consistent even for privileged
backend writes.

## Persistence And RLS

Dedicated tables keep integration data separate from user-authored commitments:

- `calendar_connections`: consent, source identity, connected/disconnected
  state, and last successful import projection;
- `calendar_imports`: immutable retry identity, canonical source/request
  fingerprints, exact window, timezone, and bounded counts;
- `calendar_events`: the current whitelisted local imported copy;
- `calendar_request_identities`: a backend-only global UUID, owner,
  connection, operation, and timestamp registry. It stores no file bytes,
  calendar content, source fingerprint, or input fingerprint and prevents one
  request identity from being reinterpreted across owners or operations.

All four tables use forced RLS. Authenticated owners/admins may select connection
and event rows. Import history and the opaque request registry are backend-only
and do not expose internal identities or fingerprints through the Data API.
Authenticated clients cannot insert, update, or delete any integration table.
Service role owns bounded lifecycle writes; request identities are insert-only.
No anon access is granted.

Database checks enforce contract/source/status enums, consent flags, bounded
labels and text, exact timed versus all-day shapes, positive intervals, IANA
timezone text bounds, event/import counts, lowercase SHA-256 fingerprints, and
connection/import/event ownership consistency.

## Disconnect And Delete

Disconnect and deletion are separate explicit confirmations.

Disconnect sends the exact JSON body `{"request_id":"<uuid>"}`. Imported-data
deletion sends no body and requires the exact UUID query
`?request_id=<uuid>`; this keeps the existing client DELETE boundary explicit
and retry-safe. Unknown query/body fields are rejected.

Disconnect:

- changes the source to `disconnected` exactly once;
- records the stable request identity and server time;
- rejects future imports before parsing their payload;
- retains imported events and labels them disconnected/stale;
- never changes a source calendar.

Delete imported data:

- is allowed only after disconnect in V1;
- hard-deletes local `calendar_events` and `calendar_imports` for that source;
- clears last-import content/fingerprints and records deletion time/request;
- preserves the minimal connection/consent tombstone for retry and audit;
- never deletes manual or Setup-owned `schedule_items`;
- never calls a provider.

Both operations are owner-scoped and idempotent. A response loss is reconciled
from the exact stored request/state; Flutter must not claim success before the
durable state is returned or reloaded.

Both mutation requests contain exactly one stable identity:

```json
{
  "request_id": "33333333-3333-4333-8333-333333333333"
}
```

Reusing that request id for a different owner, connection, or operation is a
conflict rather than permission to reinterpret the earlier request.

## UI And Product Isolation

Settings exposes `Calendar import (optional)` for every session. Guest/demo
opens an honest local page with no network access. A real account sees:

- not connected;
- connected but never imported;
- connected with a current successful import, including an honest empty state;
- disconnected with retained stale events;
- imported data deleted;
- transport or strict-contract error, which never becomes disconnected/demo.

The page requires explicit consent, shows selected-file and import progress,
keeps the selected bytes/request id after an ambiguous result, and confirms
disconnect/delete consequences. Every event carries an `Imported · read-only`
label, source label, local date/time, timezone, and import freshness. No event
edit, provider delete, or provider-write control exists.

Calendar state uses an independent provider. A calendar failure cannot fail or
replace Dashboard, Setup, capture, Today briefing, Weekly Review, Insights,
manual commitments, tasks, habits, or focus state.

## Staged Time Blocks

Imported events are context only in this first slice. No time block is created
or proposed automatically. If a future slice derives a block, it must use a
separate `staged_only` proposal with source fingerprint and explicit review.
There is no apply button until one-off app-owned schedule blocks have a typed,
recoverable mutation contract. Provider calendar writes remain outside Phase 9.

## Verification Contract

Focused backend, Flutter, migration, and browser coverage must prove:

- bearer-derived ownership and strict consent/request parsing;
- Setup calendar interest does not connect or consent;
- create/import retry identity and conflict behavior;
- bounded parsing, timezone/DST and exclusive all-day semantics;
- stable single/recurrence occurrence ids, duplicate handling, cancellation,
  and explicit unsupported recurrence counts;
- atomic replacement only after a complete valid parse;
- stable paginated reads and stale-cursor rejection;
- read-only GET and zero hidden imports/provider writes;
- disconnect-retains versus delete-local-data behavior;
- preservation of manual and Setup-owned schedule rows;
- forced-RLS owner reads and rejection of direct/cross-owner writes;
- guest/mock zero-call isolation and honest empty/error states;
- visible imported/read-only provenance and absence of event mutation controls.

Unit fixtures may provide `.ics` text directly. Browser E2E may upload a local
fixture file; it must not require or claim a real provider account. Source or
documentation assertions alone do not establish a current-checkout E2E pass.
The complete combined Phase 3 through Phase 9 browser journey passed this
contract non-destructively in the 2026-07-13 Phase 9 implementation checkout.
