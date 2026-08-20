# Stabilization Write And Projection Consistency Contract

This contract records the post-product-review stabilization boundary introduced
by migrations `20260729120000_stabilization_write_authority.sql` and
`20260729130000_observed_projection_persistence.sql`, with the additive Daily
Capture V5 RPC replacement in
`20260804102409_daily_capture_v5_remove_day_shape.sql`. It replaces unsafe
Capture and account-setting writes, makes timezone-dependent planning
fail-closed, and defines how the app behaves after a durable mutation when a
read projection cannot be refreshed. It adds no Coach capability and no
automatic plan movement.

## Daily Capture Write Authority

Authenticated Morning and Evening writes use:

```text
PUT /v1/daily-capture/{entry_date}/{branch}
branch = morning | evening
```

The strict `daily-capture-write-v1` request contains `contract_version`, a UUID
`request_id`, `expected_capture`, and one complete current `daily-capture-v5`
branch. During the rolling upgrade, FastAPI and the merge RPC continue to accept
a complete strict `daily-capture-v4` branch; partial or mixed-version writes are
not accepted. V5 Morning requires estimated sleep start/wake, derived duration,
confirmed target, sleep quality, and current energy, and rejects `day_shape` as
an unexpected field.
`expected_capture` is either `null` for a branch that was absent at the last
successful read, or the exact `{capture_id, captured_at}` identity last read.
The response repeats the canonical branch identity, `updated_at`, and
`replayed`.

`apply_daily_capture_branch_v1` takes the shared owner advisory lock, claims
`daily_capture_request_identities`, locks the daily row, and compares only the
branch being written. Morning and Evening may therefore be merged in either
order. A different concurrent write to the same branch returns `PT409`; an
exact request replay returns its saved result without writing again. A reused
request id with a different fingerprint conflicts.

The container is monotone: once either the stored container or the submitted
branch is V5, `metadata.capture_version` remains `daily-capture-v5`. An
untouched V2–V4 opposite branch stays intact as explicit compatibility data;
editing it emits a strict V5 branch. A rollout V4 write inside an existing V5
container cannot downgrade the container and is retained with
`compatibility: true`. The migration replaces only the existing RPC and adds no
table, direct grant, or new write authority.

The same transaction rebuilds the canonical scalar `daily_logs` projection and
only the `behavioral_events` rows whose source is `quick_check_in`. Other
behavioral events are never deleted by Capture. Application roles retain owner
reads but have no direct `daily_logs` or `behavioral_events` DML. Guest Capture
remains local. Guest migration writes each available branch separately and
removes local data only after all available branches have been proven saved. A
complete V4 guest branch is converted to strict V5 before the authenticated
write, retaining capture identity and exact sleep evidence while dropping
compatibility and retired `day_shape` markers. Incomplete V2/V3 data is not
filled with guessed sleep instants or targets; a failed migration retains the
local guest payload for a later retry.
New event metadata carries the V5 capture version and never includes
`day_shape`; historical Daily Log JSON is not destructively rewritten.

Flutter does not save an authenticated branch when the current day could not be
read, because it then lacks a safe expected identity. A Morning save whose
previous Evening plan could not be loaded requires either a successful retry or
the explicit continue-without-plan choice. Drafts remain present after read or
write failure. Morning presents that one non-persisted draft across a sleep step
and a quality/energy step: `Next` and `Back` perform no write, and only the final
`Save morning check-in` submits the complete branch. A failed final write stays
on the second step and retains the capture id, request identity, expected
capture, and payload for exact retry. This presentation split adds no authority,
partial-write path, projection, or wire-format change.

## Revisioned Account Settings

The existing URLs now accept only strict V2 bodies:

| URL | Request contract | Response contract |
| --- | --- | --- |
| `PATCH /v1/account/profile` | `account-profile-update-v2` | `account-profile-v2` |
| `PATCH /v1/account/preparation-budget` | `account-preparation-budget-update-v2` | `account-preparation-budget-v2` |

Both requests contain `contract_version`, UUID `request_id`, and
`expected_revision`. The profile request contains the complete IANA
`timezone`; the preparation request contains nullable
`daily_preparation_budget_minutes`. Responses contain the saved value, the new
revision, `updated_at`, and `replayed`.

`profiles.timezone_revision` and `profiles.preparation_budget_revision` start
at 1 for existing rows. The service-role-only owner-locked RPCs first recognize
an exact fingerprint replay and otherwise compare the expected revision.
Different changes from the same revision cannot both commit.
`account_setting_request_identities` is a backend-only anti-replay ledger. The
old preparation-budget RPC is no longer executable by application or
`service_role` callers.

Flutter has one profile-local date boundary for authenticated product-day
commands. It converts one captured instant using `profiles.timezone`, keeps
timestamp clocks separate, and does not silently substitute the device
timezone for invalid account data. Daily Capture identities, standalone Habit
targets and refreshes, Focus start metadata, Weekly Review application refresh,
Deadline planning start, and post-plan refresh use this
boundary. Today inline Task/Habit commands continue to use the exact date in
the loaded Today projection. Guest/no-account flows remain device-local by
design.

## Flutter Projection Impact Coordination

The coordinator treats `exam-plan-health-v1` as its own read projection.
Durable Deadline, completed Focus, Planner action/Habit/fixed-commitment,
Study Setup, profile-timezone, preparation-budget, and confirmed Calendar
import/disconnect/delete changes invalidate it. The Health editor preview is a
read and invalidates nothing. Late preview responses are generation-bound to
the exact editor fingerprint and are discarded after any relevant field
changes. Invalidation failure after a durable Calendar success is best effort
and never converts that success into an unsafe command replay.

Exam balancing has its own persisted mutation reconciliation under
`multi-exam-plan-v1`. Proposal binds the explicit expected plan revision and
owner-locked source digest; batch confirmation compares a post-proposal digest.
Transport/5xx ambiguity permits only an immutable exact retry, while `409`
staleness requires reload or a fresh preview. Its controller shares the
Preparation mutation gate with single plans and Assignment Series, and a saved
result whose projection refresh fails remains truthfully saved-but-stale.
Transient Auth loading/error states do not revoke a known principal or dispose
that principal's controller; only a later authoritative Auth value with a
different or absent principal may do so. Targeted batch detail and bounded-list
detail reads share generation/merge authority, so an older list completion
cannot erase or select over a newer explicit target. Their errors also remain
source-bound: list-detail failure exposes only the list reload, while a targeted
failure exposes a retry bound to that exact batch; either completion leaves an
unrelated error intact.

After a durable Flutter mutation, callers name one typed domain impact through
the app-level `ProjectionRefreshCoordinator`; they do not import and enumerate
foreign feature providers. The coordinator may refresh the affected profile
date's Daily Snapshot and always invalidates the mapped read caches even when
that refresh fails. It never retries or rolls back the durable write and is not
a broadcast event bus.

| Durable impact | Invalidated read projections |
| --- | --- |
| Daily Capture | latest Capture, Today, Today latest check-in, Daily Briefing, Exam Outlook |
| Habit outcome | Today, Today Full week, Daily Briefing |
| Habit definition/lifecycle | Today, Today Full week, Daily Briefing, Planner |
| Focus lifecycle | Today, Today Full week, Daily Briefing, Preparation Workload, Exam Outlook |
| Focus reflection | no Full-week invalidation; the agenda has no reflection/rating projection |
| Deadline Plan | Today, Today Full week, Daily Briefing, Planner, Preparation Workload, Exam Outlook |
| Planner | Today, Today Full week, Daily Briefing, Preparation Workload, Exam Outlook |
| Setup | Today, Today Full week, Daily Briefing, Planner, Preparation Workload, Exam Outlook |
| Timezone | every date-bound Capture, Today including latest check-in and Full week, Briefing, Planner, Workload, and Outlook read |
| Preparation budget | Preparation Workload |
| Calendar planning import | Today, Today Full week, Planner, Preparation Workload, and Exam Outlook |

Today-originated Task/Habit writes deliberately exclude Today from coordinator
invalidation because Today performs exactly one owned reload and must retain
its prior projection on failure. They still invalidate Full week, and a
Today-originated Task also invalidates Planner and its availability consumers.
Planner similarly owns its updated/reloaded overview in its controller. Guest Daily Capture uses the same local
invalidation mapping but skips the authenticated Daily Snapshot refresh.

Deadline lifecycle writes are a controller-owned specialization of this rule:
every proven confirm, complete, or cancel result, including exact retry, emits
one Deadline impact; previews emit none. Composition adds a profile date only
for a returned managed Task, and a refresh error cannot downgrade durable
success. Evening Capture captures the coordinator before opening its embedded
Focus-reflection sheet and invokes the Focus-reflection impact inside successful
save/delete callbacks, so dismissal affects only Snackbar presentation and not
Full-week invalidation.

`account-export-v6` preserves the established owner-data set minus Goals,
generic Recommendations, and Decision Feedback, while retaining the three
owner-content finite Assignment Series projections. Its exact catalog contains
41 tables and retains the 10,000
rows-per-table, 50,000 total-row, and 8 MiB bounds. It explicitly omits
`daily_capture_request_identities` and
`account_setting_request_identities`, `assignment_series_request_identities`,
and the previously omitted backend anti-replay ledgers.

## Timezone-Bound Planning And Calendar Imports

New Planner and Deadline proposals persist the profile
`timezone_revision`. Proposal and confirmation recheck that revision inside
their existing owner lock. A timezone change:

- invalidates open previews for confirmation;
- adds `timezone_changed` attention to active plans;
- never moves, reinterprets, or regenerates an active block.

Calendar import uses `calendar-import-v2`. A new import supplies the profile
timezone and timezone revision observed before the request. After request
claim, the import RPC rechecks both under the owner lock. Completed exact
replays remain replayable.

Every import has one persisted planning status:

- `not_imported`
- `current`
- `profile_timezone_changed`
- `disconnected`
- `deleted`

Only `current` events are Planner busy time. A retained import whose stored
import timezone differs from the profile starts as
`profile_timezone_changed`; matching historical imports may be bound to the
current revision. Disconnect and local deletion remain separate, readable
lifecycle states.

The `planner-overview-v2` reload projection uses that same status for displayed
Calendar facts and source-specific conflicts. It derives scheduled Task/Habit
state from positive active reservations, preserves confirmed zero-placement as
`no_time_available`, and reports a partial active plan's exact remaining
minutes once. Persisted `target_released`, generic conflict, and unplaced reason
codes cannot create a second read-time attention item.

## Setup-Owned And Manual Row Integrity

Database triggers prevent application roles from creating Setup/Intake
management markers or directly updating, unmarking, or deleting a Setup-owned
Habit or Schedule Item. The service-role Setup Apply transaction is the sole
write authority for those projections.

Manual Task and Habit creation uses `insert`, not payload-updating `upsert`.
Each new row stores an immutable creation request identity and payload
fingerprint. After an ambiguous result or unique conflict, Flutter reads the
existing row. The current row is accepted only when the creation identity
matches; it is returned as it exists now. A late retry therefore cannot erase
later edits or reactivate an archived Habit.

## DST-Safe Local Time

Setup and recurring Planner wall times use the shared local-time resolver. It
tests both PEP 495 folds through a UTC round trip and accepts exactly one UTC
mapping. A nonexistent spring-forward time or ambiguous fall-back time raises
`LocalTimeResolutionError` with the local date, wall time, and source identity.
No offset is guessed.

Intervals whose end wall time is at or before their start continue on the next
local date, then both boundaries are resolved independently. Proposal and
confirmation fail closed on an invalid source. Planner reports attention;
Today marks only the affected source unavailable and retains independent
sources.

`today-week-agenda-v1` applies that isolation across seven independently named
sources. Its profile/timezone boundary is the only route-wide failure. Calendar
is authoritative only when the connected owner's last import still has
`planning_status=current`; a stale import makes only Calendar unavailable in
both the day overview and week agenda. The server transports profile-local
dates and wall-clock strings directly so Flutter does not introduce a second
device-timezone projection.

The Planner Overview read is resilient across its bounded recurrence horizon.
If a confirmed Habit slot, applicable weekly Setup row, or weekly manual fixed
commitment has one ambiguous or nonexistent occurrence, only that occurrence is
omitted. Other resolvable occurrences and conflict checks remain current. Each
affected Action or Preparation Plan receives one deduplicated read-only
attention item naming every affected source kind, the local date and wall time,
resolution reason, and explicit no-automatic-move truth; the invalid occurrence
is never projected as a conflict.

## Observed Projection Consistency

Personal Patterns captures one aware `generated_at` before loading any source.
Its 90-day window is closed-open. Focus sessions must have ended before the
cutoff; reflections require `created_at < generated_at` and
`updated_at <= generated_at`; Daily Logs require
`updated_at <= generated_at`. Cutoff-equal or later-modified facts are excluded
and the limitation text describes the actual observation boundary.

Sleep Recommendation uses the same captured-instant and closed-open 90-day
rules on its independent read route. A Morning fact is included only when
`generated_at - 90 days <= captured_at < generated_at`, its Daily Log has a
valid aware `updated_at <= generated_at`, and `woke_at < generated_at`; the
estimated sleep start may be earlier than the lower boundary. It recomputes
without persistence, reads strict V4/V5 Morning compatibility branches, and
requires each rated Focus session to start after wake and Morning capture.
Same-day and following-local-day wake offsets remain separate candidate groups.
With Personal Pattern analysis disabled it returns before any sleep or Focus
history read. Invalid profile timezones fail through the bounded card-local
error path, and that error does not replace Personal Patterns.
Its exact response version is `sleep-recommendation-v1`.

Weekly Review and its Snapshot reads use lexicographic keyset pagination with
the established sort fields plus `id` as the tie-breaker. Each generation
captures one `source_observed_at` before its first read and excludes later
created or changed facts.

`user_state_snapshots.source_observed_at` and
`weekly_reviews.source_observed_at` are internal persistence ordering fields.
`persist_user_state_snapshot_v2` replaces a period only when the candidate
observed later and always returns the row that actually won.
`persist_weekly_review_v2` takes the owner/row lock and verifies the current
weekly Snapshot identity and provenance before it persists a non-older
candidate.

After persistence, services reload the Snapshot, Review, and relevant source
context. They return `freshness = current` only while the identity and
fingerprint still match; otherwise they return `stale`. This is optimistic
observation consistency, not a claim of a historical multi-read database
snapshot.

## Flutter Durable-Mutation States

Planner uses `current`, `refreshingAfterMutation`, and
`staleAfterMutation`. Mutation outcomes separately report `committed` and
`projectionCurrent`. After a committed write and failed overview reload, the
old overview stays visible, all derived mutation controls are disabled, and
the app shows `Change saved. Planner could not reload.` The only retry reloads
the overview; it never resends the mutation. A committed proposal or
confirmation cannot open a preview or success path until that reload proves
the exact persisted result. Before submission Flutter records the exact
proposal body and retained/source-draft identities under the generated
`request_id`. For an ambiguous proposal, reload consults only that request-bound
attempt and binds it after a freshly read pending plan matches its plan/target
identity, base-to-pending revision, operation, and complete target snapshot;
otherwise it binds nothing before clearing retry state. No global retained-draft
candidate search participates. Pending-preview staleness is recalculated from
current target, Calendar/import preference, timezone, and Study revision;
persisted reasons from older revisions remain history rather than a freshness
claim about the newest pending proposal.
Exact retry returns its original mutation identity with a classified outcome.
Repeated ambiguity retains the same proposal-attempt binding; a definitive
conflict removes only the attempt's identity-owned source replacement, while an
ordinary deterministic rejection removes the attempt and leaves the exact
source draft editable. Confirmation likewise uses identity ownership, so an
edit that replaced the bound draft cannot be erased by the older preview's
completion.

Today derives authenticated Task/Habit mutation dates only from
`DashboardSnapshot.localDate`. After a durable write it refreshes the Snapshot
through the coordinator, then reloads Today Overview itself while all actions
remain locked. Foreign dependent reads are invalidated without triggering a
second Today load. A failed reload preserves the optimistic saved state, shows
`Saved; Today could not reload.`, and offers a reload-only retry.
This lifecycle is owned by the feature-local `TodayCommandController`, not
widget-local sets or concrete Supabase calls. Its narrow Task/Habit ports return
only after their existing exact reconciliation rules have proved a write; a
thrown or unavailable result remains uncommitted. A successful port result
stays committed even if projection refresh fails, and `reloadToday` performs no
command call. If navigation disposes Today while the durable command is still
in flight, the completed command still invokes the captured application-level
projection coordinator. The disposed controller skips only its own optimistic
state and Today repository reload; it neither dereferences a disposed provider
ref nor suppresses Snapshot refresh and foreign projection invalidation.

Notification lifecycle rows enter `committedRequiresReload` after every proven
success, including replay. The row remains visible and locked until a reload
proves a projection at least as new as the result, or proves a dismissed row
absent. Retry reloads Inbox only.

Study Setup load state is `configured`, `notConfigured`, or `unavailable`.
Unavailable settings do not hide an active session or history, but they block a
new session. The explicit `Continue without saved Study Setup` choice applies
only to that start and uses the latest sensible Focus duration or 25 minutes,
zero recovery, and no checklist. It does not write Settings.

A scheduled Focus reload treats its backend start context as authoritative.
The controller replaces the scheduled target, revalidates the duration against
the new remainder, and clears no validation conflict through an invalid setter.
Completed and sub-five-minute contexts remain readable, disabled inline states
instead of constructing invalid selection controls.

Capture errors use error presentation and retry controls rather than success
styling. Setup maps HTTP, transport, and contract failures through one
student-safe message boundary; internal URLs, status codes, Dio output, causes,
and contract diagnostics are not rendered. Calendar connection identity and
status wrap into a stacked layout at narrow width and large text. All visible
copy introduced here is English.

The shared Flutter API client normalizes Dio failures before they reach feature
application code. Timeout, connection/offline, cancellation, HTTP response,
authorization, conflict, and server/unknown-outcome evidence therefore remains
distinguishable without exposing Dio exceptions outside core/data transport
code. Planner, Deadline Planner, Setup, Calendar, Notification, Account,
Learning, and Coach continue to own their established feature-specific
exact-retry, stale/reload, conflict-detail, and safe-copy behavior.

## Verification Boundary

The stabilization is covered by:

- pgTAP for V5/V4 branch merge, monotone containers, CAS/replay/transactional
  events, Setup DML bypasses,
  revisioned settings, timezone guards, Calendar race handling, and ledger
  privileges;
- FastAPI tests for the strict V5 Capture route and V4 rollout compatibility,
  learned Sleep Recommendation maturity/ordering/stability, account and Calendar V2
  contracts, keyset/observation ordering, final freshness, Personal Pattern
  cutoffs, and Berlin gap/fold/cross-midnight resolution;
- Flutter tests for V5 serialization, legacy branch upgrade, removed Day Shape
  input/display, every independent Sleep Recommendation card state, creation
  replay, Capture/Setup errors, projection locks,
  Planner/Today durable-success reload failure, the three Study Setup states,
  Notification replay/reload, profile/device cross-midnight and DST date
  resolution, shared embedded/standalone Habit targets, managed-plan refresh
  dates and exact lifecycle-retry impact, dismissed-sheet Reflection
  invalidation, transport-neutral API failure mapping, the Dio feature-layer source
  guard, and narrow large-text layouts.

An external Coach/LLM smoke is outside this stabilization boundary.
