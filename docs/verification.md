# Verification And Agent Automation

This document is the shared runbook for automated checks. It describes what can
be verified by agents without manual app exploration, what requires local
tooling, and what remains future work.

The current Setup/Goal/friction verification boundary is
`docs/setup-personalization-retirement-contract.md`. Historical results later in
this file remain records of their checkout; they do not redefine current
Capture V4, Daily State V2, Exam-Week Outlook V1, or Coach V3 expectations.

## Current Verified Baseline

The post-review stabilization working tree was reverified locally on
2026-07-30. The complete FastAPI suite reported
`1115 passed, 2 skipped`; full Flutter verification reported `726` passing
tests and clean analysis. The frontend visual contract and documentation
consistency checks passed, and `git diff --check` was clean.

The final combined stabilization browser journey reported
`E2E browser smoke passed for e2e-1785377904@example.test`. It covered the
new Capture, account-setting, Calendar, Setup/Focus, Planner/Today,
Preparation accordion/replanning/completion/navigation, Coach V2 prompt
provenance, and notification retry and stale-projection boundaries in the
filled Student flow.

A fresh local database reset applied the complete migration chain through
`20260729160000_coach_english_prompt_v2.sql`. The current seven pgTAP files
passed all 142 tests and local migration history matched the repository.
The 14 real analysis-image integration tests passed in 3.03 seconds as
non-root with a mode-`0444` snapshot, actual SQL source attribution,
conservative Python full-snapshot-scope provenance, network/host/secret
isolation, and strict trusted-image validation. The prepared image revision was
`daf088985421`.

The latest focused Coach browser journey on this working tree reported
`Focused free Coach browser smoke passed for e2e-1785433298@example.test`.
It additionally held the V3 SSE request across Coach-to-Today navigation,
proved the exact draft in the eventual request payload, rendered the global
unread result, opened and closed its non-navigating message without consuming
the notice, and applied the short-answer viewport acknowledgement. The
separate long-answer widget path kept the notice until the end marker became
visible. An earlier subsequent same-date full non-reset journey reported
`E2E browser smoke passed for e2e-1785282054@example.test`. Together they
covered the exact V3 request, V2 response, capabilities/history/SSE contracts,
Cancel visibility, replay/conflict, reload, expandable snapshot-source coverage
and provenance, history deletion, guest/read-only boundaries, absence of fixed
Coach controls, and integration with the filled Student product flow.

The explicit per-machine live smoke also passed (`1 passed in 41.31s`) using
the current Linux user's ChatGPT-authenticated Codex CLI. Its strict invocation
selected `gpt-5.5`, configured `service_tier="fast"` and Fast mode, required
the single allowlisted data MCP, and completed `inspect_data` plus isolated
`run_python` against all three intended synthetic tables. The current CLI JSONL
did not emit a selected-model field, so `model_reported` truthfully remains
`null`; any emitted different model fails closed. Successful strict explicit
model selection, the no-fallback argv, completed multi-tool trace, and matching
full-snapshot read-scope provenance are the current-machine model-path evidence.
That provider smoke did not exercise FastAPI persistence or Flutter; the
deterministic API/browser journeys above supplied those separate checks.

This is local working-tree evidence only; all automation except the named
opt-in live smoke was deterministic. It does not establish remote migration
state, installed-device behavior, deployed scheduling, a production or
multi-user model provider, clinical or academic outcomes, longitudinal
results, another account's model availability, or participant evidence.

This section is the only source for the repository's current exact verification
counts, commit id, and E2E identity. Current docs link here instead of copying
those values. Dated evidence below is historical run history and does not prove
a later checkout.

The current repository migration boundary ends at
`20260729160000_coach_english_prompt_v2.sql`.

## Verification Levels

Use the lowest level that covers the change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Standard | `FLUTTER_BIN=/path/to/flutter scripts/verify.sh` | Non-destructive repo checks. | No |
| Local Supabase preflight | `FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Starts local Supabase, requires matching migration history, and runs tests with Supabase config. | No |
| Local Supabase migration apply | `APPLY_MIGRATIONS=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Explicitly applies reviewed pending SQL, verifies history, then runs tests. | May change or delete local rows |
| Local Supabase reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Recreates local DB, applies migrations, then runs tests. | Yes, local DB only |
| Browser E2E | `FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Requires matching local migration history, starts Flutter Web, drives Playwright, and checks uniquely named DB writes. | No reset; writes test rows |
| Personal Learning E2E | `E2E_PERSONAL_LEARNING_ONLY=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Runs the focused reflection, Evening edit, pattern, learned-Planner, export, clear, and account-cascade journey. | No reset; writes and then deletes one test account |
| Browser E2E with reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Recreates local DB, then runs browser E2E. | Yes, local DB only |
| Demo seed | `npm run seed:demo` | Starts local Supabase and replaces only the four named local demo accounts: one fresh Setup identity and three populated scenarios. | Demo accounts only |

Do not run destructive Supabase commands against a remote database. These
scripts are for the local Supabase stack from `supabase/config.toml`.

## Demo Seed

Manual product exploration can use local seeded accounts instead of hardcoded
mock data:

```bash
npm run seed:demo
```

This runs `scripts/seed_demo_data.sh`, which starts local Supabase, reads the
local service-role key from `supabase status -o env`, invokes
`scripts/seed_demo_data.mjs`, and then enriches the student scenario through
`scripts/seed_student_feature_data.py`. The Node and Python paths both reject
any API URL outside `http://127.0.0.1:54321` and
`http://localhost:54321`. The backend virtual environment must exist at
`services/ai_service/.venv`, or `PYTHON_BIN` must identify an equivalent
environment with the service requirements installed.

The seed is repeatable for the demo identities. It uses the reviewed local
full-account cascade to delete and recreate only the four named Auth users, so
immutable retry/usage ledgers cannot leak between runs. Rerunning it invalidates
an open demo-account session. `onboarding@example.test` stays incomplete in
`Europe/Berlin`; the command verifies its profile, default preference row, and
neutral Personal Learning defaults, plus its absence from every activity,
Setup, planning, Coach, and retry-ledger table. Each populated scenario's
Intake row is a valid applied revision with a stable request id and
intentionally empty optional Setup-owned collections. The seed creates no
active Goal row. Separately seeded habits and schedule rows retain `demo_seed`
ownership and are not presented as Setup materialization.

The student scenario then uses the production backend service classes to
persist and validate:

- 43 profile-local V4 capture days with derived sleep intervals and no
  friction: sleep stays within `435..510` minutes, sleep quality within `6..9`,
  energy within `5..8`, and stress within `3..8`; today's Morning is present
  and Evening intentionally remains open;
- seven historical daily snapshots, eight briefings, and all five
  decision-feedback outcomes;
- daily, selected-weekday, and weekly-target habits with complete, skipped,
  open, and missed opportunities plus completed, abandoned, and active Focus;
- 36 reflections across 36 distinct local Focus days, at least 90% coverage,
  and a stable Planner-ready `09–13` Personal Learning preference;
- one current Weekly Review with a directly reviewable pause proposal for the
  repeatedly skipped phone-away Habit;
- one consented current `.ics` import with timed, all-day, busy, free, and
  unsupported-recurrence coverage;
- two active Preparation Plans, one pending preview, account-wide capacity,
  and qualifying planner-linked Focus progress;
- explicit foreground-notification consent, manual Inbox lifecycle states,
  and at least one generated pending row; and
- two validated fake-provider Coach turns with two selected eligible memories.

The seed command verifies those minimums before succeeding. The default
local-only password is `DemoPass123!` for:

- `onboarding@example.test`
- `student@example.test`
- `worker@example.test`
- `recovery@example.test`

Override it with `DEMO_PASSWORD` when needed. Do not use this workflow for a
remote Supabase project.

## Standard Verification

From the repository root:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify.sh
```

The script runs:

- `node --test scripts/check_frontend_visual_contract.test.mjs`
- `node scripts/check_frontend_visual_contract.mjs`
- `node --test scripts/seed_demo_contract.test.mjs`
- `node --test scripts/check_docs_consistency.test.mjs`
- `node scripts/check_docs_consistency.mjs`
- `bash -n scripts/start_frontend.sh`
- syntax checks for the shared migration helper, local-stack supervisor, and
  their hermetic harnesses
- `bash scripts/test_local_supabase_migrations.sh`
- `bash scripts/test_start_local_stack.sh`
- syntax checks for the demo seed, browser smoke, and student feature enricher
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `python3 -m compileall services/ai_service/app`
- `git diff --check`

The post-review stabilization additionally requires the complete backend suite
and local database tests because the standard script does not run pytest or
pgTAP:

```bash
cd services/ai_service
./.venv/bin/python -m pytest

cd ../..
supabase db reset
supabase test db
```

The stabilization evidence must include branch-CAS Capture writes, revisioned
account settings, Setup-owned DML guards, timezone-bound Calendar/Planner
races, observed Snapshot/Weekly Review ordering, Berlin DST gap/fold and
cross-midnight cases, and Flutter durable-write/reload-failure states. The
strict source is `docs/stabilization-consistency-contract.md`. A Coach/LLM live
smoke is not required for this package.

The fast documentation-only command is:

```bash
npm run verify:docs
```

The frontend-only visual source contract is:

```bash
npm run verify:visual
```

It pins the local font/icon/brand foundation and rejects new uncontrolled
Material icons, gradients, colors, radii, fonts, and route-local text styles.
It complements rather than replaces viewport screenshots, accessibility
checks, and human visual review. See `docs/frontend-visual-system-v2.md`.

It checks local Markdown links and anchors; code-owned Capture, Daily State,
Coach, and Exam-Week Outlook versions; the newest migration references;
documented FastAPI routes; centralized verification evidence; known superseded
claims; and changed-code ownership by an appropriate contract or runbook.
Locally it compares uncommitted work with `HEAD`.
`.github/workflows/docs-consistency.yml` runs the same gate for pushes and pull
requests with `DOCS_BASE_REF` set to the event's base commit, so committed
branch changes receive the same docs-impact check.

FastAPI unit tests are run separately:

```bash
cd services/ai_service
./.venv/bin/python -m pytest
```

Use `python -m pytest` from an environment with `services/ai_service`
requirements installed if the local `.venv` does not exist.

Phase 10 follows that locked separation: every normal FastAPI, Flutter,
Supabase, and browser check uses an injected deterministic fake Coach provider.
Standard verification must never depend on a Codex installation, ChatGPT
subscription, OAuth login, live model, or external network call. The
development-only `local_codex_oauth` adapter is covered with fake process
runners. See `docs/phase-10-controlled-coach-plan.md`.

FastAPI tests cover authenticated Setup/Intake, deterministic recommendations,
and the snapshot aggregator endpoint. Setup coverage includes principal-derived
identity for both `GET /v1/intake/setup` and `POST /v1/intake/complete`, strict
structured item/cadence validation, zero materialized optional rows for blank
answers, idempotent request replay, stale base-revision conflicts, recovery from
partial repository failure, stable identities across edit, intentional removal,
preservation of non-Setup rows, stale-worker checks, and monotonic profile
projection through `profiles.setup_revision`. Atomic-apply coverage verifies one
service-role RPC for the complete projection, same-request worker convergence,
per-user serialization against a later revision, full rollback on ownership
collision, idempotent profile repair, and the exact-only legacy
`Math`/`Room 204`/Monday `08:15`-`09:45` cleanup. Snapshot tests verify
principal-derived `user_id`, request `user_id` rejection, scoped Supabase reads,
refreshing an existing `user_state_snapshots` row for the same period, and the
Phase 1 capture-date boundary. The snapshot repository reads `metadata` from
`daily_logs` and `behavioral_events`, widens the UTC event query safely, prefers
the explicit event `metadata.entry_date` for local-day filtering, excludes the
following local day, and retains a UTC fallback for legacy events without that
metadata. Current Intake tests additionally require retired legacy keys to be
accepted then stripped before comparison/storage, notification preferences to
remain unchanged, Setup-owned Goals to be archived without touching
manual/foreign Goals, only the intended Setup memories to be removed, and no
post-Setup Recommendation generation. Daily State V2 tests cover every active
capture taxonomy code; strict V2/V3/V4 branch identity, enum, numeric,
timestamp, sleep-interval, and projection validation with friction ignored;
unknown future metadata;
legacy-only fallback; separate seven-day state versus requested statistics
windows; Evening target/previous-day and Morning target-day freshness;
`missing`, `partial`, `current`, and `stale` quality; all four modes and
recovery-first conflict precedence; the active-Task requirement for `push`;
absence of friction risks/reasons/evidence; exact field-level evidence;
deterministic provenance; capture free-text exclusion; and stable daily/weekly
same-period recomputation. Recommendation tests prove no Goal/onboarding/
friction rule participates. Aggregator assertions also
keep `summary.risk_flags` as the current Daily State alias, preserve older
window flags under `summary.window_risk_flags`, and derive
`recommended_next_focus` recovery-first from mode.

Account-control tests additionally cover strict bearer-derived timezone updates,
IANA validation, cross-owner export rejection, pagination and size bounds,
sanitized/omitted ledgers, exact download headers, exact delete confirmation,
session-bound and refresh-resistant 15-minute `amr` freshness rejection before
service calls, service-role-only RPC grants, both Phase 3 restrict links,
focus-first deletion, and the profile-cascade postcondition. Flutter tests cover the exact export
envelope/count parser, platform save/share cancellation truth, dedicated mobile
temporary-source cleanup, password recovery state and password validation,
rejected versus outcome-unknown timezone updates, device-persisted theme,
Settings capability gates, typed recent-auth and ambiguous-deletion notices,
and local session cleanup after a completed account deletion.
The export path also proves receive-time cancellation above 8 MiB, invalid
UTF-8 rejection, defensive raw-byte ownership, and byte-for-byte preservation
of large integers and precise decimals through the platform saver boundary.
The export checks pin 1,000-row server pages and the Flutter-only two-minute
receive timeout so the documented 50,000-row edge is not forced through the
ordinary 20-second JSON request path.
Migration-source tests inventory every repo-created canonical product/ledger
table and pin the application privilege guard's current-role, legacy-table,
projection, default-privilege, Auth-trigger-function, Notification-index, and
six `NOT VALID` timestamp-check statements. Those static tests do not prove a
particular local or remote database grant catalog; the local migration/reset
workflow and direct database inspection establish applied state separately.
Phase 3 backend tests validate strict `executable-action-v1` parsing and reject
unknown/coerced top-level and metadata fields, null/non-object metadata,
explicit-null metadata fields, invalid calendar dates,
kind/command/target/linkage mismatch, focus duration bounds, unsupported routes,
and command-specific metadata leakage in parity with Flutter. Snapshot tests
cover explicit completed/skipped habit outcomes plus focus
status/planned/actual-minute summaries, input counts, and evidence; focus local
`metadata.entry_date` wins over `started_at` after a broadened UTC read, with
deterministic UTC legacy fallback. Repository tests load more than 1,000 rows
from both action tables and assert stable offsets through the final page. They
also assert byte-for-byte-equivalent Phase 2 Daily State semantics for the same
capture inputs. Recommendation tests exclude terminal
done/cancelled/archived tasks from overdue, workload, and focus-pressure
candidates.
Phase 4 briefing tests prove that normal GET is read-only; authenticated routes
derive identity only from the bearer principal; local profile timezone selects
the briefing date; current generation is idempotent; changed snapshots mark a
briefing stale; recovery/missing-data rules precede overdue pressure; completed
or unscheduled habits are excluded; and every returned action passes the strict
`executable-action-v1` model with at most two support actions and no LLM use.
Historical Phase 5 tests continue to prove the persisted briefing parser. The
retired briefing-first widget and production-unreachable dispatcher no longer
carry isolated Flutter tests. Today Overview V1 adds strict
FastAPI service/API tests for bearer ownership, profile-local dates, streaks
longer than one page, current-day grace, malformed/legacy capture exclusion,
task and habit selection, four-source timeline ordering, exact progress
arithmetic, and isolated source failures. Flutter tests repeat exact response
and nested-key validation, reject inconsistent progress, prove authenticated
GET versus local guest zero-call behavior, and cover section order, lazy `More`,
all-task expansion, source-error truth, and 320-pixel/2.0-text-scale rendering.
Phase 6 tests cover strict feedback parsing, exact owned-action validation,
idempotent request replay/conflict, authenticated GET/POST/DELETE, local-demo
isolation, 28-day context matching, decay/caps, unchanged original reasons, and
explicit feedback-ranking provenance. Insights tests prove insufficient versus
emerging/stronger observation labels, visible evidence windows, optional
bounded experiments, and non-causal copy. They also cover nullable persisted
confidence without a fabricated fallback, visible 7/14/30/90-day windows,
every directed switch among those windows with the exploration still open and
the page scroll position unchanged during and after loading,
stable pagination across all five Supabase fact sources, the explicit 10,000-row
per-source client ceiling, missing/error retry truth, and readable Light/Dark
panel colors.
Phase 7 scheduled-preparation tests cover the backend-only token guard and
strict bounded request, including the maximum-20 `profile_ids` operational
filter and explicit `target_date` backfill override. Repository tests prove
that the filter still intersects onboarded
non-guest profiles; one captured timezone-aware UTC run instant resolves exact
profile-local dates; missing snapshots, missing briefings, stale snapshot
provenance, current pairs, and invalid timezones remain distinct; and a current
pair is selected only when an explicit recommendation pass still needs retry.
Service tests prove pinned local dates across different timezones, write-free
current briefing preparation, generated/reused snapshot and
generated/refreshed/unchanged briefing results, sanitized snapshot/briefing/
recommendation/profile-date failure stages, continuation after one user's
failure, and optional deterministic recommendation refresh with LLM wording
disabled. The default scheduled path does not generate recommendations or call
an LLM.
Phase 8 tests cover strict `weekly-review-v1` request/response parsing,
principal-derived ownership, profile-local completed ISO weeks across year/DST
boundaries, read-only latest/period GET, idempotent same-row generation, and
canonical source-fingerprint staleness. Fact tests keep completed/carried tasks,
stable versus changed habit definitions, completed/skipped/missed/recovery-open/
unknown opportunities, focus, recovery days, and feedback distinct. Repository
tests require stable full pagination and exact user/date scoping. Proposal tests
cap deterministic output at two, require matching `too_much` evidence before
the initial weekly-target shrink rule, preserve Setup ownership, and never apply
a user-owned mutation during generation.
Phase 9 tests cover strict `calendar-import-v2` and
`calendar-import-consent-v1` parsing, bearer-derived ownership, connection
without import, create/import request replay and conflict, bounded `.ics`
parsing, profile-local windows, stable event and recurrence identities,
identical versus conflicting duplicates, exclusive all-day dates, aware timed
intervals, explicit unsupported recurrence, cancellation tombstones, and
atomic replacement only after a complete valid parse. Repository/API tests also
cover stable event pagination and concurrent stale-projection detection,
read-only GET, exact body-free delete, disconnect retention, local imported-data
deletion, schedule preservation, global cross-owner/operation request identity,
reliable `PT409` conflicts, forced-RLS owner reads, and rejection of
authenticated direct or cross-owner writes.
Deadline Planner V1 focused coverage must keep `deadline-plan-v1` strict across
Pydantic and Flutter, require the user's explicit estimate/prior credit, and
prove deterministic timezone-aware blocks, honest unscheduled minutes, staged-
versus-active revisions, the 366-day horizon, separate latest/current revision
semantics, task-free draft cancellation, and exact retry/conflict behavior,
including replay returning a newer current detail projection without repeating
the original mutation. `preparation-workload-v1` coverage must require exactly
seven consecutive profile-local dates, strict arithmetic and provenance, active
confirmed-reservation totals, distinct active-plan counts, merged recurring
Setup commitments, and honest no-budget/over-budget/error states without
implying imported calendar or AI coverage.
`exam-week-outlook-v1` coverage must separately prove exact profile-local
`exam_week`/`watch`/`overdue` boundaries, assignments as capacity consumers but
not activators, one warning-only exam buffer day, missed/future block
arithmetic, deterministic deadline/exam/id ordering, every confirmed competing
reservation, per-plan and account budgets, Study recovery, calendar consent,
regular versus sleep-protected fit, missing sleep plan, DST gap/fold
incompleteness, two-of-three recent shortfall, pending-preview overlap, bearer
ownership, and a write-free GET. Flutter must cover loading/error/all modes,
unknown capacity, card order, guest zero-call, navigation without proposal, and
320 px/200-percent text.
`preparation-workload-detail-v1` coverage must independently require a date in
that current seven-day profile-local window; exact owner/date active-block
filters; at most 50 unique plan/title/minute/block contributions whose sum
equals the total; strict budget arithmetic and response keys; an empty
cross-owner projection; honest loading, retry, and changed-summary states; and
320 px/200-percent text plus browser navigation into review/replanning without
an automatic proposal or mutation. The original seven-day response shape must
remain unchanged.
Service and
migration tests must cover first-confirm managed-task creation, stable task
identity, generic task mutation/editor rejection and redirect, allowed open-task
focus, exact later-confirm fields, atomic matching terminal projection, linked
completed-focus progress without implicit completion, optional calendar busy-
time use, stale selected-event fingerprints, forced RLS, global
request identity, conflict instead of empty availability for disconnected/
deleted/missing-current imports, account cascade, export inclusion, and omitted
ledger policy. They must also cover nullable account-budget bounds and five-
minute increments, exact save/removal and response-loss reconciliation, owner-
derived persistence, authenticated direct-write denial, the shared owner lock,
other-plan deduction including earlier same-day confirmed blocks, and
confirmation conflict when capacity changed after preview.
Normal GET, import, Dashboard, scheduler, and focus-completion paths must remain
free of hidden proposal writes.
Planner V1 focused coverage must prove strict Task/Habit proposal unions,
explicit scheduling inputs, exact five-minute slotting and unplaced minutes,
multi-block Tasks, all three Habit cadences over the bounded four-week preview,
DST-safe profile-local slots, and the shared Availability inputs across
Planner and Deadline Planner. Setup coverage must prove strict inclusive
semester bounds, persistence in owned schedule metadata, unchanged unbounded
legacy behavior, duplicate-with-new-identity UI, and exclusion of expired
commitments from Planner, Preparation workload, Today, and snapshot facts.
API/service tests must cover read-only overview
and detail GETs, seven consecutive local dates, explicit calendar consent and
current-import fingerprinting, source-stale and reservation conflicts, target
version conflicts, and preparation/manual/Setup/calendar/action-plan overlap.
Migration tests must cover forced RLS, owner isolation, global request replay,
concurrent confirmation, atomic target-plus-reservation activation,
authoritative commitment conflicts, lifecycle release, restore-without-slot
revival, and unchanged legacy Tasks/Habits. Flutter tests must cover the five
Coach-enabled main navigation targets, the hidden Coach/no-Settings-fallback
gate, Settings through the top-right Today control, Inbox under Settings,
Planner section order, all five create flows, preview/confirm, retained drafts,
guest zero-call, seven-day and preparation projections, availability-readiness
warning plus explicit override, calendar-intent omission from onboarding, and
320 px/200-percent text. Today V2 tests must prove
the three added block kinds, exact `scheduled_today`, one target per progress
denominator, and isolated source failures.

Study Setup V1 focused coverage must prove old Intake compatibility and strict
new focus/semester shapes; collapsed optional onboarding; 45/10 defaults;
Guest local round-trip; new-commitment-only semester prefill; atomic projection,
replay, omission, rollback, RLS, export, and deletion. Focus coverage must prove
planned-block/Study/recent/25-minute priority, transient checklist choices,
manual duration override, strict recovery metadata, and completed-only
restorable/skippable local countdown. Planner/Deadline coverage must prove exact
Study-sized blocks, one final short remainder, honest unscheduled gaps, full
recovery conflicts, unchanged active-minute/budget arithmetic, Task opt-in,
Habit exclusion, stale confirmation, active-plan attention, and profile-local
course-selection states with no Today/Calendar/Notification side effect. The
exact boundary is `docs/study-setup-v1-contract.md`.

Personal Learning V1 focused coverage must prove:

- SQL rating/obstacle bounds, one reflection per terminal session, composite
  owner linkage, active/cross-owner rejection, forced RLS, conflict updates,
  preference dependency, exact update replay, retry-safe confirmed clear,
  40-table export inclusion, ledger omission, and account cascade;
- backend disabled-before-evidence short-circuit, profile timezone and DST,
  strict shared V4 sleep parsing, exact local wake/Focus-date matching,
  sleep-before-session ordering, rejected prior-day 36-hour fallback,
  repeated-episode daily collapse, Morning capture-time ordering, every
  maturity state, low coverage, mixed halves, night exclusion, alternate safe
  window selection, and deterministic used-evidence fingerprints;
- Planner/Deadline learned-window free and busy ordering, Setup fallback on
  unavailable evidence, unchanged duration/Recovery, deadline/budget/Calendar
  conflicts, permission disable before confirmation, exact immutable
  provenance, and unchanged active plans; and
- Recommendation profile-local windows with future-row exclusion, real terminal
  Focus abandonment threshold, valid sleep quality/target-deviation input,
  exact strongest-field sleep/movement provenance, measured movement only, and
  atomic replacement of obsolete current cards while retaining history.

Flutter Personal Learning coverage additionally proves non-negative shortfall
derivation, planned/actual rated daily sums, the two centralized overlapping
pair blocks, exact 7/14-day evidence thresholds, descriptive-only sleep and
outcome pairs, Trend timing/normalization copy, complete metric labels,
Dashboard future-check-in exclusion, and the 320-pixel/200%-text matrix.
Exam-Week Outlook coverage rejects future Evening and Morning rows before
selection. Daily State regression coverage keeps Morning sleep current only on
the exact target date.

The exact boundary is `docs/personal-learning-v1-contract.md`.

Phase 10 focused backend source coverage is split across strict model/API,
service, snapshot, MCP, sandbox, migration, and local-provider tests. The
current boundary requires exact message-only V3 and V2 response/capability/
history/SSE shapes; owner-derived snapshot paging; no silent 10,000-table,
50,000-total, or 8 MiB truncation; scripted zero-tool and multi-tool provider
paths; backend-derived source coverage/trace; one active owner turn; exact
message replay; daily budget; deterministic safety; timeout/cancel/provider
failure; history tombstones; and authenticated mutation denial.

Snapshot/MCP tests must cover catalog/count/period/relationship/view truth,
sanitized retained detail, cross-owner rejection, prohibited auth/identity/
ledger fields, immutable SQL authorizer/progress/row/byte limits, exactly three
tools and 12 total calls, Python image arguments and limits, no network/secrets/
host access, single internal-image handling, prompt-injection authority
boundaries, and cleanup. Evidence tests must prove that inspection alone adds no
row coverage, SQL reports full accessed-source coverage separately from returned
row counts, and arbitrary successful Python records full-snapshot read scope.
Local-provider fake runners must assert required MCP configuration,
`gpt-5.5`, `service_tier="fast"`, Fast mode, no fallback, allowlisted child
environment, fixed non-shell argv, bounded output/process termination, and safe
activity. This source coverage is distinct from the opt-in live smoke.

The old longitudinal fixed-mode suite remains useful compatibility coverage for
readable V1/V2 history and deprecated endpoints; it does not define current
Flutter request behavior.
The follow-up migration contract test also checks that public
claim/complete/fail wrappers acquire the owner advisory lock before calling
their ungranted inner bodies, matching history-delete lock order. Additional
migration tests require exact provider-call safety provenance, backend-owned
profile identity fields, canonical-only role authority, rejected authenticated
profile deletion, backend-owned onboarding eligibility, and V2 history
deletion that neutralizes retained scope/parameters to `today` with `{}` so a
Focus UUID or Patterns horizon is not left in the tombstone. The additive V3
migration test must also prove message-only replay, exact V2 response/evidence/
trace/tier validation, V1/V2 compatibility, one owner turn, daily budget, V3
detail deletion, and service-role-only RPC authority. Historical real local
PostgreSQL parallel claim/completion/deletion smokes completed on 2026-07-13
without deadlock or timeout and converged on the expected message, usage, and
deletion outcomes; rerun for the V3 RPC chain before a current claim.

Current Flutter widget tests include:

- Auth gate renders.
- Guest can complete required-only progressive Setup, persist exact empty
  optionals, and reach the dashboard with only Typical weekday and Best energy,
  without a routine, note, or commitment.
- Typed Setup model/data-source tests cover stable item keys, candidate versus
  confirmed cadence, `request_id`/`base_revision` request JSON, authenticated
  setup reads, legacy-key sanitization, and invalid response/error propagation.
- Setup widget/repository coverage exercises guest and authenticated prefill,
  loading/error/retry, retained drafts and request ids, edit without duplicate
  records, ambiguous-failure retry locking, review lifecycle actions, and the
  real Settings Setup entry.
- Auth repository tests prove mock/demo authenticated boot skips remote profile
  access and guest migration, restores local Setup name/completion across reload,
  and never leaks a remote onboarding marker into local-demo state.
- Setup save-state tests keep validation and HTTP 4xx failures editable, make
  409 suggest reload, and lock timeout/5xx/malformed results to exact retry or
  explicit reload.
- Setup widget tests prove Focus Areas, Goals, Friction Points, Coaching Style,
  Reminder Preference, and More Context are absent. Repository/browser coverage
  proves a Setup edit leaves consent, categories, quiet hours, and daily cap
  unchanged.
- Capture-domain tests cover every bounded stress source, controllability,
  and day-shape value; rating, sleep clock/target/interval, date, and text
  boundaries; exact 02:00–10:00 and 23:00–07:00 derivation;
  omission of blank Evening optionals; and explicit inclusion of supplied
  reflection, priority, and blocker. Compatibility tests read V2/V3 friction
  and old `gentle_tomorrow` metadata, ignore/sanitize them, preserve an
  untouched older opposite branch explicitly, and require V4 fields when that
  branch is edited.
- Same-day merge tests cover Evening-then-Morning and Morning-then-Evening,
  replacing one branch without erasing the other, Morning-over-Evening energy
  precedence, removal of deliberately cleared optionals, preservation of
  foreign top-level metadata, and legacy V1 calendar-date compatibility.
- Capture payload tests assert one merged `daily_logs` row with
  `capture_version=daily-capture-v4`, nested `captures.evening|morning`, direct
  nullable compatibility values, and only explicitly available current
  `behavioral_events`. Raw estimated/planned clocks stay only in Daily Log
  metadata while `sleep_hours` and the Sleep event use the derived duration.
  Event identities remain stable across exact retry and
  event metadata mirrors capture kind/date plus the relevant stress, priority,
  and day-shape context without friction.
- Guest-store tests cover typed Evening/Morning JSON, both-order same-day merge,
  exact retry deduplication, V1 guest rows with an explicit local date, and
  recovery from corrupted local JSON.
- Evening widget tests cover required explicit selections, exact typed draft
  retention after failure, stable retry identity, prefilled re-entry with blank
  optionals still blank, absence of every friction control and the retired
  gentler control, preservation of Reflection/Priority/Specific Blocker, and
  suppression of a duplicate in-flight write.
- The guest app smoke completes distinctive required-only Evening Shutdown and
  Morning Calibration, persists one local merged day, reads Morning energy over
  Evening energy, and shows the exact saved summary on return.
- Guest sees only locally functional Quick Actions; Supabase-only Habit
  Completion and Habit Management are hidden and their direct routes redirect.
- The Intake API data source gets `GET /v1/intake/setup` and posts
  `POST /v1/intake/complete` with bearer auth and the structured revisioned
  payload; authenticated failure does not invoke the old direct-write fallback.
- The optimization repository keeps normal recommendation reads as `GET` only,
  and the deliberate refresh path posts `POST /v1/recommendations/generate`
  with bearer auth, `force=false`, and `allow_llm_wording=false`.
- Recommendation repository/provider tests prove that only explicit guest/demo
  sessions receive demo feeds, even with a leftover token. Real missing-config,
  missing-token, network, and malformed-response paths throw and never consult
  mock data; current/missing/stale feed metadata is preserved.
- Dashboard mapper/widget tests assert exact raw values, Phase 1 capture
  provenance and structured context, Morning energy precedence, honest
  empty/error states, local source labels, and the absence of former proxy
  metrics.
- Capability, Settings, and notification tests cover the real-account Coach
  route plus its gated fifth shell destination, redundant Settings-shell
  removal, guest/mock zero-call boundary, real synced Deep Work versus
  guest/mock redirect, unavailable guest/mock execution,
  persistent local-demo label, the strict `action_url` allowlist, original
  notification fields/read state, separate real empty/error states, strict
  due/dismiss visibility, lifecycle parser parity, confirmed read/unread/
  dismiss state, exact ambiguous retry, retained refresh data, accessibility,
  and 320 px/2x-text layout.
- Notification Delivery V1 model/repository/controller/widget tests keep saved
  reminder flags separate from explicit consent, validate generated provenance,
  stop consent-off before a pending-row query, filter disabled categories before
  the bounded query, retain an exact ambiguous settings retry, keep a definitive
  conflict locked through failed reloads, acknowledge before presentation,
  suppress receipt replays,
  render the explicit consent dialog/settings, and show one deterministic/no-
  LLM foreground banner. Weekly Review widget tests visibly distinguish direct
  manual actions from Setup guidance and non-executable staged suggestions.
- The Snapshot refresh service posts `POST /v1/snapshots/generate` with bearer
  auth in real backend mode, includes an explicit capture `target_date`, skips
  guest/mock/missing-token paths, and treats network failures as best-effort.
- Task, habit, and focus snapshot-refresh entrypoints route through the same
  authenticated daily behavior and preserve an explicit `target_date`. The
  focus page is implemented to pass its persisted start `entry_date` or legacy
  `started_at` date after start/finish/abandon.
- Guest can inspect the deterministic Insights correlation surface without
  requiring Supabase.
- The correlation analyzer covers positive, negative, missing, low-variation,
  and weak-relationship ranking behavior.
- The Insights repository keeps mock correlation data scoped to mock/guest mode
  and does not substitute demo correlations for empty or failing real Supabase
  reads.
- Source-boundary provider tests keep Setup, Evening/Morning capture, Dashboard,
  and Insights on local/demo sources when `USE_MOCK_DATA=true`, even if an
  authenticated Supabase session exists.
- Habit visibility tests exclude every Setup-managed habit from generic Habit
  Management while keeping active Setup habits in Habit Completion and hiding
  candidate/archived states.
- Executable task tests cover title/description/estimate validation, typed
  persistence mapping, owner-scoped create/edit/complete/postpone/cancel/
  restore transitions, stable create identity, undo data, retained failures,
  exact lifecycle shapes, and snapshot refresh boundaries.
- Habit V1 tests cover daily, selected ISO weekday, and weekly-target cadence;
  compatibility projections; completed/skipped/open/missed opportunity math;
  current ISO-week progress; completion streaks; same-day upsert/undo; manual
  lifecycle; Setup-owned execution authority; local `started_on`; and
  Europe/Berlin spring/fall DST calendar arithmetic.
- Focus tests cover planned-duration bounds, one optional owned target, active
  session parsing, measured whole-minute finish/abandon, terminal transitions,
  no implicit target completion, recent history, snapshot refresh, shared
  reflection prompting after finish/abandon, recovery continuing behind the
  prompt, retained retry choices, edit/skip behavior, terminal-only rating,
  Evening summary, guest zero-call, large text, and semantics.
- Executable action-target tests cover every supported kind/command matrix,
  strict top-level/metadata shapes and scalar types, exact ids/dates/durations,
  task/habit/focus/capture routes, `review_plan` metadata, and unsupported
  combinations. Current Today execution is covered by the owning feature and
  navigation tests rather than a dormant briefing dispatcher.
- Weekly Review tests cover strict nested parsing, `not_ready`/missing/current/
  stale/error/local-demo states, latest GET versus deliberate generate/refresh,
  separate weekly facts, the two-proposal cap, stale disabled controls, exact
  before/after confirmation, cancel with zero writes, Setup deep-link without a
  generic write, manual Habit V1 expected-timestamp application, and guest/mock
  API isolation.
- Calendar import tests cover strict nested consent/connection/import/event
  parsing, authenticated bearer requests, local-demo zero-call selection,
  unchecked consent, connection-without-import, retained exact retry identity,
  imported/read-only source labels, stable pagination, event-local timezone and
  all-day rendering, no event mutation controls, and the distinct disconnect,
  retained-data, delete, empty, and error states.
- Coach tests cover strict V2 capability/history/response/evidence/trace/
  provenance parsing, message-only V3 encoding, SSE
  started/activity/completed/failed parsing, cancellation, exact bearer calls,
  guest/mock zero HTTP, timeout-aware request-id/message retry, duplicate
  submit prevention, unavailable/rate-limit/error states, visible uncertainty
  and validated safety/provenance consistency, expandable snapshot-source
  coverage plus tool/limitation/Fast detail, mixed legacy/current history, and
  confirmed history deletion without direct Supabase writes. Widget assertions
  reject fixed mode/horizon/Focus, prompt-starter, memory-selection, structured
  suggestion, hidden reasoning, and plot surfaces. App-lifecycle tests also
  prove that draft/request identity and an active stream survive main-page
  navigation; success clears while failure/Cancel retain the draft; profile
  switch and app teardown clear notices and cancel the old controller; the
  shared six-page header orders page action, unread Coach, and Settings; the
  notice popup neither navigates nor reads; only the newest answer-end or
  failure/retry marker acknowledges; Settings Push/Back is preserved; and all
  icon targets stay at least 44 by 44 at 320 px/200-percent text.

These tests cover the default mock/guest product path. They do not prove real
Supabase registration, RLS, or browser behavior.

## Local Supabase Verification

From the repository root:

```bash
FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Runs Supabase with `HOME=.tools/supabase-home` and
   `SUPABASE_TELEMETRY_DISABLED=1` so the CLI does not need to write to the
   user's real home directory.
3. Starts the local Supabase stack.
4. Redacts Supabase keys from CLI output.
5. Reads `API_URL` and `ANON_KEY` from `supabase status -o env` without printing
   the key.
6. Runs Flutter tests from `apps/mobile` with:

```env
USE_MOCK_DATA=false
SUPABASE_URL=<local API URL>
SUPABASE_ANON_KEY=<local anon key>
```

With the default `RESET_DB=false` and `APPLY_MIGRATIONS=false`, the script runs
`supabase migration list --local` and requires every repository/DB history row
to match. It never applies pending SQL automatically. A mismatch fails before
reading client configuration or running Flutter tests and explains the two
explicit choices.

After reviewing the pending SQL and affected local rows, apply intentionally:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

The script warns that this may change or delete local rows, runs
`migration up --local`, and verifies history again before continuing. An empty,
unknown, or non-boolean flag value is rejected. `APPLY_MIGRATIONS=true` and
`RESET_DB=true` are mutually exclusive.

## Local Supabase Reset

Run this only when a local database reset is intended:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh
```

This executes:

```bash
supabase db reset
```

Expected successful reset output applies migrations through:

```text
20260725120000_retire_setup_goals_and_friction.sql
```

Expected notices include skipped legacy CamelCase tables and already-existing
canonical objects. Those notices are normal. Errors are not normal.

The application-table privilege guard must leave `anon` with no repo-owned
product/ledger table privileges and remove authenticated `TRUNCATE`,
`REFERENCES`, and `TRIGGER` without erasing intended table-specific DML.
Backend projections stay authenticated read-only, optional legacy tables stay
mutation-frozen, and future public tables created by `postgres` inherit the
fail-closed defaults. Existing Auth triggers must still fire even though their
security-definer functions are no longer reusable by application or service
roles. Its Notification-ledger index and six `NOT VALID` timestamp-order checks
must exist; `NOT VALID` intentionally means old rows were not scanned, while
new and updated rows are constrained.

The Phase 3 migration backfills and constrains task, habit-log, and focus rows,
including missing focus `metadata.entry_date` from the UTC date of `started_at`.
It normalizes positive legacy habit values to completion and deliberately fails
if a legacy habit log has no status and `value <= 0`, because that row cannot be
interpreted honestly as completion or intentional skip. Inspect and resolve
such local data before retrying. The reset also installs exact task lifecycle,
locked active/weekday habit eligibility, bounded focus lifecycle, locked target
validation, one-active, all-update terminal immutability, and restrict-delete
target constraints/triggers. Existing local stacks may apply reviewed pending
migrations explicitly with:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
scripts/verify_supabase_local.sh
```

This is not a non-destructive claim: migration SQL may change or delete local
rows even when it does not reset the entire database.

Use the reset form to prove the complete migration chain from an empty local
database; do not use it merely because a reviewed migration is pending.

The reset destroys and recreates the local Supabase database. It must not be
used for a remote project.

## Browser E2E

Browser E2E is implemented with Playwright:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

This is the normal non-reset database path: the script starts or reuses the
repository's local Supabase stack, skips `supabase db reset`, inspects
`supabase migration list --local`, and fails when repository and database
history differ. It never applies pending SQL automatically. The smoke still
writes a uniquely named local Auth user and its test rows. Do not set
`RESET_DB=true` unless recreating the local database is explicitly intended.

Phase 10 can be run narrowly for diagnosis with a fresh unique run id:

```bash
E2E_PHASE10_ONLY=true \
E2E_RUN_ID=<new-unique-e2e-run-id> \
FLUTTER_BIN=/path/to/flutter \
bash scripts/e2e_web.sh
```

This mode creates and signs in a confirmed `e2e-<run-id>@example.test`
principal, applies only its minimal prerequisite Setup projection, resets only
its Coach E2E state, and repeats the fake-provider Coach UI/API/RLS assertions.
Reusing an id fails closed when that local email already exists. Its UI path
also retains a draft across Coach/Today navigation,
holds the SSE request while navigating away, verifies completion without a
Flutter disconnect, exercises the unread header message without navigation or
acknowledgement, and confirms acknowledgement only after the newest answer end
is reached. It does not exercise the normal Setup UI, capture, executable
actions, briefing, feedback, weekly review, or calendar import. Treat it as a
focused diagnosis path, never as a substitute for the full command.

For a fresh local database before the browser run:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

If an existing local database differs from repository migrations, review the
pending SQL and affected local rows before opting into application:

```bash
APPLY_MIGRATIONS=true \
FLUTTER_BIN=/path/to/flutter \
bash scripts/e2e_web.sh
```

This may change or delete local rows. The script verifies history again before
starting FastAPI, Flutter, or Playwright.

The full E2E command enables
`LEARNED_FOCUS_PLANNING_PILOT_ENABLED=true` in both FastAPI and Flutter for the
test process. It finishes and rates Focus, edits the rating from Evening, loads
a stable profile-timezone pattern fixture, enables the separate Settings
permission, proves a learned free window and a busy-window Setup fallback, and
checks export/deletion. This test-only gate does not change normal or production
defaults.

Use real Ubuntu-installed Node.js, npm, Supabase CLI, and Docker. If these tools
are installed through nvm, non-interactive agent shells may need an explicit
`PATH` or `NODE_BIN` override even when `node --version` works in the user's
interactive shell. Do not install replacement tool binaries into `.tools/`.

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Starts the local Supabase stack and optionally runs `supabase db reset`.
3. Reads `API_URL`, `ANON_KEY`, and `SERVICE_ROLE_KEY` from
   `supabase status -o env` without printing key values.
4. Starts the FastAPI AI service on `127.0.0.1:8000` by default with backend
   local Supabase settings, a run-scoped scheduled-refresh token, and
   `COACH_PROVIDER=fake` plus `COACH_FAKE_PROVIDER_ENABLED=true`. Standard E2E
   never contacts a live Codex account.
5. Starts Flutter Web on `127.0.0.1:7357` with `USE_MOCK_DATA=false` and
   `AI_SERVICE_BASE_URL` pointing at the local FastAPI service.
6. Passes the same token only to the Node assertion process and runs
   `e2e/web/smoke.mjs` with Playwright. The token is never passed to Flutter.

The script waits for the Flutter log line containing `is being served at` before
starting Playwright. A plain `curl` response from `/` is not enough, because
`flutter run -d web-server` can answer before the debug web bundle is ready; if
Playwright opens the page during that window, screenshots are often blank white.

The E2E Flutter process also passes `--dart-define=E2E_ENABLE_SEMANTICS=true`.
`apps/mobile/lib/main.dart` uses that test-only flag to keep Flutter Semantics
enabled, which gives Playwright stable text fields, buttons, and labels instead
of relying on canvas pixels.

The browser smoke creates a confirmed local Supabase Auth user through the local
admin API and walks the Phase 0C Setup journeys before continuing through the
existing product smoke. It covers required-only completion with zero optional
owned records; one routine candidate and fixed commitment; retry after a
response is lost; prefilled edit with stable identity; cadence confirmation;
and review actions that pause/remove Setup-owned rows. It asserts the retired
controls and JSON keys are absent, post-Setup Recommendations remain absent,
the energy memory is retained, a legacy Setup Goal is archived, and a manual
Goal survives unchanged. A personalized Reminder row is compared exactly
before/after Setup edits.

After the Phase 3 action journeys, the smoke also exercises Phase 4 directly
through authenticated FastAPI calls. It proves that the first briefing GET is
read-only and missing, deliberate POST persists exactly one owner/local-date
row, response and JSONB action payloads match, every returned target is an
implemented strict command, and a repeated `force=false` request preserves the
same id and timestamps.
It then opens Dashboard and proves Phase 5 normal load issues no briefing POST,
renders the exact persisted primary title, dispatches the returned real command,
and sends exactly `{"force":true}` only after `Adjust today`, preserving the
same daily briefing identity.
Phase 6 then records `too_much` through Today, asserts the exact owner-scoped
database row and ranking provenance after adjustment, opens history, deletes the
entry, and proves a subsequent generation returns to zero feedback influence.
It also proves Insights begins with one cautious observation and keeps the
correlation controls inside explicit advanced exploration.

The Phase 7 portion calls the protected scheduler only with the uniquely named
E2E profile through the bounded `profile_ids` filter; it does not run an
unscoped batch against unrelated local accounts. It compares the scheduler's
captured UTC `run_at` with the profile timezone, requires the exact local
briefing date, and accepts only a missing snapshot or missing briefing as the
first preparation reason. Database assertions prove one exact daily snapshot
and one exact briefing identity, deterministic/no-LLM provenance, and exact
source-snapshot id and timestamp linkage. A repeated scheduled request must
process zero users and leave both rows and timestamps unchanged. The subsequent
Dashboard path remains GET-only; the E2E scheduler token stays outside Flutter.

The Phase 8 portion seeds one completed profile-local ISO week with exact task,
manual and Setup-owned habit, habit-outcome, focus, daily-state, and
decision-feedback rows. Latest GET must report missing without a write;
deliberate generation must persist exactly one owner/period review whose facts,
fingerprint, no-LLM provenance, and at-most-two proposals match the response.
A repeated read remains write-free. Cancelling the before/after dialog changes
nothing; confirming the eligible manual weekly-target shrink must preserve the
habit identity/ownership/logs, use its exact expected timestamp, and make the
old review stale. Setup-owned review navigation must not write a Habit or Goal,
and the compatible `goal_linked_completed` counter must remain zero. Deliberate
refresh reuses the same weekly review identity. Authenticated REST
assertions use a second principal to prove owner-only SELECT and rejection of
direct review-table writes/cross-owner habit changes.

The Phase 9 source portion starts from an exact empty read, confirms explicit
read/store consent, and proves that connection alone creates no import/event.
It imports bounded `.ics` fixtures with duplicate, all-day, timezone-aware,
materialized recurrence, unsupported recurrence, and cancellation cases;
asserts stable retry/event identities plus paginated read-only provenance; and
keeps `schedule_items` byte-for-byte unchanged. Separate confirmations prove
disconnect retains the stale local copy while delete removes imported event
content and retains only its bounded `deleted` audit row. The opaque
fingerprint-free request ledger rejects reuse across operations and owners;
exact completed replays remain valid after disconnect, supersession, or local
deletion, while a non-current import never supplies Planner busy time. DELETE
rejects a body. A second principal checks owner-only visibility and rejected
direct/cross-owner writes. Guest/mock coverage remains zero-call.
The complete combined browser command passed these assertions non-destructively
in the 2026-07-13 Phase 9 implementation checkout.

Deadline Planner interaction coverage is currently split honestly across two
layers. Flutter widget tests drive the calendar prefill and three-step wizard,
require explicit exam/assignment and distinctive total/prior inputs, inspect the
staged preview, confirm explicitly, retain and rebase a draft after `409`, and
exercise the narrow/large-text layout. They also prove that an active plan with
no pending preview first opens a zero-request compact review, copies every saved
proposal value while normalizing a historical start to today, preserves current
reservations until confirmation, rejects passed deadlines and stale calendar
sources, and exposes the full editor deliberately. Pending previews and retained
conflict drafts remain on the full-editor path. They additionally cover Settings
budget save/removal, the 320-pixel/200-percent dialog and seven-day card,
account-cap deduction, and truthful loading/error/overage states. The
browser/database journey creates and activates the lifecycle through the
authenticated API, then verifies the real
Flutter active-plan surface, managed-task/focus behavior, no `schedule_items` or
imported-event mutation, owner/cross-owner authority, Account Export inclusion/
cascade, and guest zero-call. It also sets and reads the budget through the
authenticated product boundary, rejects direct profile mutation and request-
provided identity, validates the strict seven-day workload, proves a stale
preview cannot confirm after the budget is lowered, restores the setting, and
checks Today/Preparation plans without broadening calendar claims. It does not
currently claim that Playwright submits the wizard itself. It does verify the
compact replan review, its no-automatic-change copy, the deliberate transition
to the full editor, and modal cancellation; a single end-to-end browser wizard
submission remains additional coverage rather than evidence already supplied by
the API-seeded journey.

The Phase 10 browser source uses only the deterministic fake provider. The
current design asserts generation-free capability/history reads, message-only
V3 streaming, safe activity, Cancel, a fixed direct answer with empty
source-coverage/tool trace, exact persisted message/request/usage/response
identity, same-id replay without another durable turn, changed-message
conflict, mixed legacy/current history, deterministic safety bypass, expandable
UI provenance, conversation deletion with retained tombstones/usage, owner-only
reads, rejected authenticated mutations, and guest/mock zero calls. It also
asserts that the current page has no fixed mode, horizon, Focus selector, prompt
starter, memory selection, structured suggestion, or plot. Service/unit
fixtures separately exercise scripted non-empty SQL/Python traces.

Historical note: focused and full fixed-mode fake-provider browser runs passed
on 2026-07-13. They do not prove the free-agent stream, snapshot, trace, Cancel,
or current UI. Run the current source before making a current-checkout claim.

The Setup assertions inspect exact `request_id`, base/revision, applied state,
stable materialized ids, server ownership metadata, record counts, and the
constant onboarding snapshot identity. A named unconfirmed routine must remain
only in `intake_responses`; it must not appear as an active daily habit. Replaying
one request must return the same result without another revision or owned row,
while a real edit advances the revision and preserves stable record ids. After
the UI journeys, two simultaneous authenticated POSTs with the same new request
id must both return the same applied revision, produce exactly one
`intake_responses` row, and advance `profiles.setup_revision` only once. This
exercises the migrated advisory-lock RPC against real local PostgreSQL rather
than only the in-memory concurrency tests.

The smoke then creates a habit through Habit Management and follows
`/daily-check-in` into the canonical Evening Shutdown at
`/quick-mood-check-in`. It records distinctive mood `2`, Evening energy `9`,
stress `8`, private/emotional hardly-controllable stress, reflection, and
specific blocker. Every primary/additional friction control and
the removed gentler and tomorrow-priority controls are asserted absent. The
saved branch must omit a new `tomorrow_priority` value. Playwright lets the first
`daily-capture-write-v1` PUT commit but drops its browser response, verifies
that the exact draft remains available, then retries the byte-equivalent
request and requires `replayed=true` without creating another daily row or
event set.

The browser first saves Evening sleep start `23:00` with an eight-hour target.
The same user then completes `/morning-calibration` after correcting the
estimated start to `00:00`, selecting wake `05:30`, and observing the derived
5.5-hour duration, with Morning energy `4` and constrained day shape. Database assertions require
exactly one `(user_id, entry_date)` row with
`metadata.capture_version=daily-capture-v4`, both nested V4 capture branches,
aware raw Morning instants, exact 330-minute arithmetic, the target/source
identity, and raw-field absence from linked event metadata,
absent blank optional keys, mood/stress from Evening, sleep from Morning, and
Morning energy taking precedence in `energy_level`. It requires every friction
key to be absent from the daily row, events, Daily State, and Coach context. The
smoke reopens Evening, checks its saved state, edits stress to
workload/mostly-controllable and the priority, and requires the exact Morning
capture identity and values to remain.

Linked current-event assertions require three explicit events after
Evening-only and exactly four after Morning merge and Evening edit. All final
events share the daily-log id, have unique deterministic ids, carry the correct
numeric value/unit, and mirror their relevant `capture_kind`, `entry_date`,
capture id/time, stress taxonomy, priority, or day-shape
metadata. Capture success sends `POST /v1/snapshots/generate` with the explicit
local `target_date`; the committed-response failure does not. Normal capture is
also observed to make no browser request to
`POST /v1/recommendations/generate` and to leave Setup revisions/profile
projection plus unrelated task, Goal, habit, schedule, memory, notification,
and recommendation identities unchanged.

The browser also inspects each Phase 2 snapshot response. Evening-only
private/emotional, hardly-controllable stress must produce partial `recover`
state with exact source risks. Adding target-day Morning sleep `5.5`, energy
`4`, and constrained day shape must produce current `recover` state. Editing
Evening to workload/mostly-controllable must keep the same snapshot id, add
workload risks, remove stale private/low-control risks, retain recovery because
of current compound signals, and persist exactly one target-period row. The
assertions require `explainable-daily-state-v2`, deterministic/no-baseline
provenance, field-level non-friction evidence for the daily log, and absence of
both original and edited free text from summary and signals.

The Deadline Planner browser lifecycle also confirms one exam seven local days
away plus one same-window competing assignment. Planner alone must show the
Exam week/sleep/capacity card. The journey opens `Replan remaining time` only to
the saved-value review, submits no proposal, and compares plan/revision/block
state before and after the GET and navigation.

After the Phase 1/2 assertions, the Phase 3 browser journey completes, undoes,
skips, and undoes a manual habit; completes and undoes an active Setup-owned
habit without mutating its definition; and asserts one explicit outcome row at
most per habit/local date. It creates and edits one typed task without changing
identity, postpones and undoes the deadline, completes/restores, and
cancels/restores while checking exact status, estimate, and terminal timestamp
rows. Habit and task creates deliberately lose one committed HTTP response, then
prove that retained drafts and stable request ids converge on one row. Habit
outcome and undo each lose a committed response; reconciliation must prove the
exact row or its absence for the target date captured before the write, and
refresh that same date.

The journey then starts and finishes a task-linked focus session, proves that
the task was not completed implicitly, and starts/abandons an independent
session. Database assertions cover one active session at a time, terminal
timestamps, measured whole elapsed minutes, target linkage, and no remaining
active row. Focus start also loses one committed response and must reconcile the
same active session before refreshing its persisted start date. Task completion,
task undo, and focus finish each lose a committed transition response and must
accept the exact stored result without a second transition. Negative database
checks reject a task terminal without its timestamp, a second active focus
session, terminal-focus lifecycle, `entry_date`, and `updated_at` rewrites, an
out-of-range focus duration, and outcomes for an inactive or unscheduled
selected-weekday habit. A refreshed daily snapshot must contain the explicit
habit/focus input counts and neutral summaries while preserving the Phase 2
Daily State, and observed task/habit/focus writes must make no
recommendation-generate request.
The smoke then uses deliberate recommendation refresh and exercises Inbox
(`/alerts`) through one real unread/read/unread/dismiss lifecycle. It checks
the exact FastAPI payload/result, persisted tombstone and three-row retry
ledger, exact replay, request-id reinterpretation conflict, foreign-owner 404,
owner/cross-owner SELECT, direct authenticated DML rejection, ledger
invisibility, due filtering, and dismissal after reload. It then exercises the
Controlled Coach journey against the deterministic fake provider, verifies real
Deep Work, and checks the explicit payloads of manual snapshot/recommendation
requests. Source coverage is not a current-checkout pass.

These assertions are present in `e2e/web/smoke.mjs`; run one of the commands in
this section to establish pass/fail for the current checkout. Documentation of
the path is not evidence that a current full browser run passed.

`e2e/web/smoke.mjs` navigates Flutter routes through root hash URLs such as
`/#/auth`, `/#/daily-check-in`, and `/#/morning-calibration`. This avoids direct
deep-link requests against the `flutter run -d web-server` development server,
which does not provide a production-style rewrite layer for every app path.

The service-role key is used only in the Node-side E2E process for local setup
and assertions and in the FastAPI process for backend persistence. It must never
be passed into Flutter or browser runtime configuration.

The E2E script generates a local scheduled-refresh token unless an override is
provided. It passes that token only to FastAPI and the Node assertion process,
does not print it, and never exposes it through Flutter configuration.

The canonical schema grants app-table privileges to `service_role` so these
local REST assertions can query rows after RLS-protected browser writes.

Useful overrides:

```bash
NODE_BIN=/path/to/node
CHROME_BIN=/path/to/chrome
HEADED=true
HOST=127.0.0.1
PORT=7357
APP_URL=http://127.0.0.1:7357
AI_SERVICE_HOST=127.0.0.1
AI_SERVICE_PORT=8001
AI_SERVICE_BASE_URL=http://127.0.0.1:8001
AI_SERVICE_PYTHON=/path/to/python
AI_SERVICE_START=false
SCHEDULED_REFRESH_TOKEN=local-e2e-override
E2E_RUN_ID=manual-001
```

By default, `scripts/e2e_web.sh` starts FastAPI from the current checkout and
does not reuse an arbitrary service that is already listening on the same port.
If the port is occupied, stop that service or set `AI_SERVICE_PORT` to a free
port. Use `AI_SERVICE_START=false` only when you intentionally want to reuse a
compatible FastAPI process that is already running with the same local Supabase
project settings and scheduled-refresh token.

Flutter Web logs for the E2E run are written to:

```text
.tools/e2e/flutter-web.log
```

FastAPI logs for the E2E run are written to:

```text
.tools/e2e/ai-service.log
```

On browser failure, Playwright saves a screenshot named:

```text
.tools/e2e/failure-<run-id>.png
```

`.tools/` is ignored by git.

## Phase 10 Provider Verification

The current pair under verification is `free-coach-agent-prompt-v2` with
`personal-snapshot-v1`; stored V1 prompt responses and exact replay remain
valid. Phase 10 keeps two strictly separate paths:

1. The default deterministic path uses a fake provider/process runner in
   pytest, Flutter tests, and the browser environment. It covers strict
   V3/V2/capabilities/history/SSE envelopes; scripted direct zero-tool and
   multi-tool execution paths; snapshot-wide source windows; SQL/Python
   mechanics; empty coverage; retry; one pending turn; local-day budget;
   cancellation; timeout; provider/model/Fast/image failure; snapshot overflow;
   history deletion; and guest zero calls. Scripted responses do not prove
   autonomous tool choice, hypothesis quality, false-premise correction, or
   honest clarifying behavior. Prompt tests verify that these behaviors are
   required, while real-model evaluation is needed to assess them.

   Security coverage must prove that the snapshot is owner-only and excludes
   auth, secrets, provider internals, and ledgers; SQL cannot write, attach,
   change state, or load extensions; and Python cannot reach the network, host
   files, Supabase, OAuth, secrets, or mutation paths. Prompt injections in
   Setup, notes, memories, calendar content, and prior chat must not add tools
   or permissions. Trace/source coverage must reconcile with actual MCP JSONL
   rather than model output: inspection alone adds no row coverage, SQL reports
   full accessed-source coverage separately from returned-row counts, and
   successful arbitrary Python records the full snapshot read scope. Snapshot,
   script, plot, trace, container, and process workspaces must be cleaned after
   every terminal path.

   The browser harness must cover an authenticated onboarding-empty API path
   without invented personal history plus the populated Student UI, alongside
   reload/history compatibility, safe compact activity, Cancel, expandable
   snapshot-source coverage/steps/limitations/Fast provenance, no plot, and the
   absence of fixed mode/horizon/Focus/prompt/memory/suggestion controls. These
   deterministic API/browser paths, rather than the provider-only smoke below,
   prove persistence and presentation.
2. `services/ai_service/tests/test_local_codex_smoke.py` is the deliberately
   separate per-machine real-model smoke. It is skipped unless
   `RUN_LOCAL_CODEX_SMOKE=true` and must print no personal question/answer,
   prompt, OAuth/account data, paths, raw JSON events, stderr, or tokens. Build
   the analysis image first and run it only with the explicit local provider
   settings and an existing login:

```bash
npm run prepare:coach-analysis
```

```bash
cd services/ai_service
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

The opt-in smoke proves only the provider path on the exact machine, CLI
version, account, and model tested at that time. A valid current smoke must
prove strict explicit `gpt-5.5` selection with no fallback, reject any different
reported model, configure `service_tier="fast"` plus Fast mode, require MCP
startup, and run one complex synthetic-data question through multiple allowed
tools with matching trace and full-snapshot read-scope provenance. Current
Codex JSONL may omit the selected model field; that omission must remain
`model_reported=null`, not be fabricated. It does not prove FastAPI persistence,
Flutter presentation, autonomous answer quality, availability for another
account, or production readiness. Missing login/model/Fast/image, rate/account
limit, invalid output, or timeout is an honest failure, never a reason to add an
API key, model fallback, or standard-tier downgrade.

Historical result, not current-agent evidence: on 2026-07-13 the old
synthetic-context smoke completed
against the explicitly requested `gpt-5.5` model (`1 passed`), with no fallback
and no answer, prompt, OAuth/account data, or raw event stream logged.
It did not use the personal snapshot, required data MCP, Fast configuration, or
isolated Python and therefore does not satisfy the current live criterion.

Recorded full-product local result on 2026-07-13 in the working tree based on
`b8c7935`: an existing onboarded local E2E principal authenticated through
Flutter Web, loaded a ready `local_codex_oauth` capability from FastAPI, and
deliberately received one validated and persisted `coach-response-v1` through
the same Linux user's logged-in Codex CLI. The configured request was exactly
`gpt-5.5`, no fake provider or fallback was enabled, and persisted provenance
reported `source=model`, `provider_called=true`,
`controlled-coach-prompt-v1`, and `coach-context-v1`. The CLI did not provide a
reliable selected-model event, so `model_reported` truthfully remained `null`.
Flutter rendered the response, expanded `Data used`, and expanded provider/model
truth; authenticated history returned the exact turn. The harness logged only
sanitized contract/provenance/count results, never the question, assembled
prompt, answer, raw event stream, stderr, account identity, path, token, `.env`
value, or Supabase key.

That historical live manifest included current profile and daily snapshot; a stale daily
briefing; current goals, tasks, habits, and focus sessions; and explicitly
omitted the stale weekly review. No memory was selected and no previous
completed turn entered context. It proves only the retired fixed-context
product path on that machine. The current multi-tool V3/Fast result is recorded
in the baseline above; separate clone/setup/login acceptance with another Linux
user remains open.

Keep the smoke out of the standard verification-level table and CI. It is an
explicit account/network action, not a prerequisite for deterministic checks.

## Local Tool State

The scripts use a local CLI home at:

```text
.tools/supabase-home
```

This directory is ignored through `.tools/`. It may contain CLI state and must
not be committed. Do not install tool binaries into `.tools/`; install real
Ubuntu tools so commands such as `supabase --version`, `node --version`,
`npm --version`, and `npx --version` work in the Ubuntu shell.

## Secrets And Logs

Do not paste, print, or commit Supabase keys. Local anon keys may be used by the
Flutter client for local development, but they should still be treated as
credentials in chat and logs.

`scripts/verify_supabase_local.sh` and `scripts/e2e_web.sh` intentionally print
availability messages instead of key values:

```text
Local anon key: available
Local service role key: available for backend and Node-side assertions
```

If command output includes a key unexpectedly, redact it before sharing logs.

Codex OAuth state is also secret. Verification may run sanitized commands such
as `codex login status`, but must never read, print, copy, snapshot, or attach
`~/.codex/auth.json` or equivalent CLI state. The Phase 10 child process must
receive an allowlisted environment rather than inheriting FastAPI's Supabase
service-role key or other backend secrets.

## Current Automation Gap

The repository now contains browser E2E automation, but it still depends on a
real Ubuntu Node.js 20+ installation, `npm`, Playwright browser installation,
Docker access, and a real Ubuntu `supabase` CLI on `PATH`.

The combined Phase 3/4/5/6/7/8/9 browser journey first passed in the Phase 9
implementation checkout. A focused Phase 10 run and the subsequent full
Phase 3-through-10 journey passed without a database reset against local Supabase in
the recorded 2026-07-13 checkout. Later changes must establish their own full
result with the browser command above; the focused mode is diagnostic only, and
the `RESET_DB=true` form is reserved for proving the migration chain from a
fresh database. The full journey
includes committed-response-loss for habit/task create, habit
outcome/undo, task completion/undo, and focus start/finish, plus negative
lifecycle/range/active-target/weekday-cadence checks and terminal-focus
`updated_at` mutation. Phase 8 adds a second principal for weekly-review RLS and
one cross-owner habit attempt; it still does not directly exercise restrict-
delete FKs. It also does not seed more than one habit/log page to prove
the browser pagination boundary or carry a focus session across local midnight
to assert the refresh date in-browser. Backend repository tests separately
cover more than 1,000 habit-log and focus-session rows. Do not infer the other
paths merely from the same-user UI journey.

Phase 7 targeted scheduled-preparation, Phase 8 bounded weekly-review, and Phase
9 bounded calendar-import assertions passed as part of that non-destructive
2026-07-13 browser run. They verify only the local test stack and uniquely named
E2E profile. They do not establish remote database state, deployed cron
execution, production token configuration, weekly scheduling, notification
delivery, or autonomous planning.

Notification Delivery V1 currently has focused backend contract/repository/
service/API/scheduler/migration tests and Flutter parser/controller/settings/
Inbox/banner tests. The browser source now also encodes explicit UI consent,
settings replay/conflict, scheduler generation, privacy-safe provenance,
dedupe, category/quiet/cap rejection, foreground receipt, Inbox truth, and
receipt replay suppression. After explicit authorization,
`20260714130000_notification_delivery_v1.sql` was applied to the local stack and
the reviewed `20260714143000_notification_delivery_settings_guard.sql` follow-up
was subsequently applied without a reset. Local history matches the repository.
A rollback-only database smoke verified exact replay, expected-revision
conflict, Setup-style monotone timestamps, consent ordering, and identity
invalidation. The full non-reset current-checkout browser journey passed on
2026-07-14 with
`E2E browser smoke passed for e2e-1784046486@example.test`. That run exercised
the real local Flutter -> FastAPI -> Supabase consent, deterministic generation,
policy rejection, foreground receipt, banner, Inbox refresh/provenance, dedupe,
and replay boundaries. It exposed and fixed a stale Inbox provider after a
foreground receipt before the recorded passing rerun.
Focused source tests also cover recovery opt-out suppression, Phase 8
fingerprint freshness,
request-exact Settings replay, monotone cross-writer revisions, category
starvation, and the reload-required Flutter state.

The Phase 8 pass also does not establish complete task-transition history,
historical habit-definition revisions, or remote RLS state.

Phase 9 source coverage is not a real Google/Microsoft/Apple Calendar test. It
uses selected local `.ics` bytes and does not establish provider OAuth, token
refresh/revocation, arbitrary URL fetch, incremental/background sync, provider
writes, mobile-native file-picker behavior, or remote RLS state.

Deadline Planner source coverage likewise does not establish long-term study
outcomes, a live provider calendar, notifications, background replanning,
remote migration/RLS state, or an installed-device pass. No passing browser or
local migration result should be recorded until the full current-checkout
commands complete after the new migration is applied.

Those local commands completed on 2026-07-18. A rollback-only database smoke
verified manual and current-calendar proposal/confirmation, active-Focus and
stale-Focus guards, exact collection/detail projection, and a 1,202-block
projection without PostgREST truncation. The complete AI-service suite reported
`745 passed, 1 skipped`; the final standard source gate reported a clean Flutter
analysis and `579` passing Flutter tests. The final post-polish non-reset
combined browser run reported
`E2E browser smoke passed for e2e-1784404040@example.test`. That is evidence for
the recorded local 2026-07-18 checkout only and does not expand any of the non-claims
above. The manual five-student usability study remains not run.

The subsequent five-agent compressed persona walkthrough on 2026-07-18 is
documented in
`docs/synthetic-student-persona-simulation-2026-07-18.md`. It produced code-
backed findings, not participant or two-month evidence. After its fixes, the
changed-area suites reported `63` Flutter tests and `14` focused Deadline
Planner backend tests; the complete FastAPI suite reported
`748 passed, 1 skipped`. The standard gate and non-reset local Supabase check
each passed all `591` Flutter tests with clean analysis and matching local
migration history. The full non-reset browser journey reported
`E2E browser smoke passed for e2e-1784413991@example.test`. These results apply
only to this local checkout and do not change the manual/external gaps below.

The optional account-wide preparation-capacity follow-up completed on
2026-07-19. The complete FastAPI suite reported `763 passed, 1 skipped`; the
standard gate and subsequent non-reset local Supabase preflight each passed all
`601` Flutter tests with clean analysis and matching migration history through
`20260719120000_account_preparation_budget_v1.sql`. The full non-reset browser
journey reported
`E2E browser smoke passed for e2e-1784448992@example.test`. It covered the exact
budget Settings request, authenticated direct-write rejection, strict seven-day
workload, cross-plan deduction, a budget change between preview and confirm,
retained staged state after exact `409`, Today/Preparation-plans rendering,
cross-owner isolation, export, and guest zero-call. This remains local evidence;
the five-student study is still unrun and no remote, installed-device,
background-delivery, production-provider, localization, or longitudinal claim
is added.

The compatible actionable workload-day follow-up also completed locally on
2026-07-19. Its focused backend suite reported `27 passed`; the complete FastAPI
suite reported `766 passed, 1 skipped`. After a browser-discovered nested-modal
navigation defect was fixed, the standard gate and non-reset local Supabase
verification each passed all `608` Flutter tests with clean analysis and
matching migration history. The final full non-reset browser journey reported
`E2E browser smoke passed for e2e-1784465767@example.test`. It covered strict
owner/date detail arithmetic, cross-owner emptiness, on-demand Flutter detail,
exact overage copy, staged replan entry, and a root modal barrier that prevents
Shell navigation from stealing `Cancel`. This is local evidence only; the
five-student study and all remote, installed-device, background-delivery,
production-provider, localization, and longitudinal checks remain unrun.

The compact existing-plan replanning follow-up completed locally on 2026-07-19
without backend or schema changes. The focused Deadline Plans page suite passed
`22` tests; the standard gate passed all `610` Flutter tests with clean
analysis; and the final full non-reset browser journey reported
`E2E browser smoke passed for e2e-1784475200@example.test`. Two preceding
attempts exposed Flutter Web text input racing ahead of app-state propagation;
the shared browser helper was hardened to commit clearing, pace retries, and
verify two blur/refocus cycles before the final passing run. The final journey
covered the compact no-request review, deliberate full-editor transition,
cancel behavior, exact input persistence, and the existing planner/RLS
lifecycle. This remains local automated evidence; the participant study and
all remote, device, delivery, production-provider, localization, and
longitudinal checks remain unrun.

Planner V1 completed locally on 2026-07-22. The complete FastAPI suite reported
`793 passed, 1 skipped`; the final standard source gate passed migration safety,
clean Flutter analysis, all `632` Flutter tests, Python compilation, and diff
checks. Local Supabase history matched the repository through
`20260722120000_planner_v1.sql`. The final non-reset combined browser journey
reported `E2E browser smoke passed for e2e-1784749089@example.test`. It covered
split Task and Habit confirmation, one-off and weekly commitments, the Planner
and Today projections, Inbox only through Settings, central Calendar busy-time
consent shared with Deadline Planner, strict Account Export inclusion/ledger
omission, and account deletion. This is local checkout evidence only; it does
not establish remote migration state, live calendar sync, deployed scheduling,
background replanning, notifications beyond the existing contract, or manual
student-usability results.

The manual-timetable-first follow-up completed locally on 2026-07-22 with one
function-only guard migration and no new table or column. Focused
Setup/Planner/availability/migration coverage reported `101` backend and `36`
Flutter tests. The complete FastAPI suite reported `803 passed, 1 skipped`; the
standard source gate passed clean Flutter analysis, all `635` Flutter tests,
Python compilation, migration safety, and diff checks. Local Supabase
verification confirmed repository migration history through
`20260722234000_setup_commitment_validity_guards.sql` and repeated all `635`
Flutter tests successfully. Rolled-back SQL smokes proved Task and 28-day Habit
confirmation change from no conflict to conflict only when the Setup validity
range applies. The final non-reset browser journey reported
`E2E browser smoke passed for e2e-1784756190@example.test`; it also asserted the
Setup semester-date/duplicate controls and absence of the former calendar-intent
prompt before completing the existing Planner, Today, optional Calendar,
export, and account-deletion paths. This proves the local checkout only; it does
not establish remote state or complete real-world timetable data.

The now-superseded Evening friction follow-up completed locally on 2026-07-23
without a schema change. It is retained only as historical checkout evidence;
current tests require friction-free Capture V3. The complete FastAPI suite
reported `813 passed, 1 skipped`; the
standard source gate passed migration safety, clean Flutter analysis, all `637`
Flutter tests, Python compilation, and diff checks. The final non-reset browser
journey reported
`E2E browser smoke passed for e2e-1784801994@example.test`. It asserted the
removed gentler control, explicit `No major friction`, exactly two selected
additional frictions through response loss/retry and re-entry/edit, exact daily
row and event metadata, and the Daily State rule that only the primary friction
drives mode. Browser-discovered duplicate/stale semantics actions in capture
chips were removed by merging labels with the native selectable controls. This
is local checkout evidence only and does not add longitudinal or manual
student-usability evidence.

The Morning sleep-quality follow-up completed locally on 2026-07-23 without a
schema change. The focused Daily State and Coach suite reported `140 passed`;
the complete FastAPI suite reported `827 passed, 1 skipped`, and the standard
source gate passed migration safety, clean Flutter analysis, all `639` Flutter
tests, Python compilation, and diff checks. The final non-reset browser journey
reported
`E2E browser smoke passed for e2e-1784806592@example.test`. It asserted the
required independent `Estimated sleep quality` answer, exact merged
`sleep_quality` metadata and event provenance, dashboard rendering, and a
separate `low_sleep_quality` Daily State signal. Unit coverage additionally
proves that eight hours with very poor reported quality still selects recovery,
while older Morning V2 rows without the additive field remain readable and
must supply it when explicitly resaved. This remains local checkout evidence;
it does not infer objective sleep quality, add a wearable source, or establish
longitudinal or manual student-usability results.

Study Setup V1 completed locally on 2026-07-23. A fresh local database reset
applied the full migration chain through
`20260723120000_study_setup_v1.sql`; a rollback-only SQL smoke separately
proved atomic Intake projection and omission, revision replay, Owner RLS,
service-role authority, stale-setting rejection, and full rollback. The
complete FastAPI suite reported `857 passed, 1 skipped`; the final standard
source gate passed migration safety, clean Flutter analysis, all `656` Flutter
tests, Python compilation, and diff checks. The final combined browser journey
reported `E2E browser smoke passed for e2e-1784831721@example.test`. It covered
the collapsed optional Setup sections and 45/10 defaults, exact Guest and
authenticated persistence, the transient Focus checklist and recovery
countdown, exact Study-sized Planner/Deadline blocks and a short final
remainder, recovery conflicts and unchanged study budgets, Study revision
attention, profile-local course-selection attention and Settings navigation,
Account Export inclusion, and account deletion. The journey exposed and fixed
one real allocator defect: a final short remainder could previously backfill
ahead of full Study blocks and violate recovery ordering. It also hardened
Flutter Web semantics selection for exact choices and native checkboxes. This
is local checkout evidence only; it adds no automatic replanning, provider
calendar write, Notification/Today side effect, installed-device result,
longitudinal outcome, or manual student-usability evidence.

The shell-navigation follow-up completed locally on 2026-07-23 without a
backend or schema change. The focused Shell/guest suites reported `19` passing
tests, the final Shell rerun reported `9` passing tests, and the standard
non-destructive source gate passed migration safety, clean Flutter analysis,
all `657` Flutter tests, Python compilation, and diff checks. Browser source was
changed to enter Coach through the gated shell destination, but a full browser
journey had not yet tested that selector.

The repository cleanup follow-up completed locally on 2026-07-23. It removed
production-unreachable Flutter briefing/dispatcher scaffolding and its isolated
tests, removed the unused Cupertino icon dependency, aligned current docs, and
added the no-authority-change RLS performance migration. The standard source
gate passed migration safety, clean Flutter analysis, all `642` remaining
Flutter tests, Python compilation, shell/Node syntax, and diff checks. The
complete FastAPI suite reported `861 passed, 1 skipped`; `pip check` found no
broken requirements. Local migration history matched through
`20260723200707_optimize_canonical_rls_policies.sql`, and the local Supabase
advisor reported no issues after previously reporting 17 Auth-initplan and 60
duplicate-permissive-policy warnings. A full browser journey subsequently
reached the late Coach section after exercising the preceding real-account,
Planner, Calendar, Notification, retry, and RLS paths, then exposed that Flutter
Web does not publish the persistent shell navigation as Playwright-addressable
Semantics DOM. The E2E source restored the stable direct `/coach` route while
the shell behavior remains covered by nine widget/Semantics tests. The focused
Phase 10 browser rerun then passed for `e2e-1784837771@example.test`; the full
combined journey was not restarted after that selector-only correction.

The Setup-personalization retirement completed locally on 2026-07-25. A fresh
database reset applied the full migration chain through
`20260725120000_retire_setup_goals_and_friction.sql`; all 29 rollback-only
pgTAP assertions passed, including filled-data cleanup, repeat cleanup,
Reminder preservation, owner/grant boundaries, and paired Coach V1/V2 replay.
The complete FastAPI suite reported `848 passed, 1 skipped`; the standard
source gate passed migration safety, clean Flutter analysis, all `646` Flutter
tests, Python compilation, and diff checks. The updated demo seed verified 21
daily logs, eight briefings, four focus sessions, five calendar events, three
preparation plans, and two Coach turns without retired personalization fields.
The final combined browser journey reported
`E2E browser smoke passed for e2e-1784985824@example.test`. Database lint
reported no finding in the new migration; its remaining output is limited to
the existing legacy `public."User"` reference and `legacy_index` warnings in
the account-deletion RPC.

Daily Capture V4 and Exam-Week Outlook V1 completed locally across
2026-07-25–26 without a schema change. The exact final result is retained only
in [Current Verified Baseline](#current-verified-baseline). The run covered the
Evening sleep plan, corrected Morning interval, active exam plus competing
assignment, Planner-only outlook, explicit replan navigation, and unchanged
active plan/revision/block rows before confirmation. The GET remained read-only
and no migration, Notification, Today item, or automatic plan change was added.

Phase 10 has focused fake-provider/process-runner, strict contract, service,
migration, repository, controller, and widget tests in the checkout. Its
focused browser path and subsequent full fake-provider browser journey passed
in the recorded 2026-07-13 checkout. The development-only local Codex OAuth
adapter's opt-in synthetic-context smoke and the separate authenticated
Flutter-to-live-Codex product path also passed on this machine with explicit
`gpt-5.5`; these results establish neither remote state, another account's
availability, nor production readiness. Multi-developer acceptance still needs
one different Linux user to clone, authenticate their own eligible account, and
complete the documented path without copied credentials.

Known harmless local E2E output includes Chromium WebGL performance warnings.
The FastAPI AI service must be healthy for the browser smoke to pass.

Still missing for broader product verification:

- CI wiring for the browser E2E command.
- Playwright trace artifact collection on failure.
- Deployed scheduler/cron wiring and monitoring; the repository verifies the
  protected preparation endpoint, not any production invocation platform.
- Android/system notification delivery is not part of Notification Delivery V1
  and remains absent; physical-device foreground acceptance is still useful.
- Installed-device Google OAuth/recovery acceptance, a complete physical-device
  layout/accessibility pass, and best-effort authenticated guest check-in
  migration. Widget tests cover the critical 320 px/text-scale surfaces, but
  do not replace device acceptance. Guest Setup intentionally has no automatic
  account migration.

When changing E2E flows, keep `e2e/web/smoke.mjs`, `scripts/e2e_web.sh`, and
this document in sync.
