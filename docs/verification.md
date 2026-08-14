# Verification And Agent Automation

This is the current runbook for choosing and running repository verification,
recording checkout evidence, understanding CI, and tracking present automation
gaps. Dated superseded results are preserved in
[Verification History](verification-history.md) with explicit historical
status; they never prove a later checkout.

Before running or claiming a gate, inspect the affected boundary and its owning
contract. Test source or a historical pass is not current evidence.

## Current Verified Baseline

The P7 generic Recommendation and Decision Feedback retirement working tree was
verified locally on 2026-08-14 against task base
`70828e1530a499a3663ea48dac622ea97aac8bd4`. Documentation consistency passed
for 52 Markdown files and 78 FastAPI routes; the Visual contract, Flutter
analysis, all 1,051 Flutter tests, the Flutter web build, Ruff, Python
compilation, and `1543 passed, 2 skipped` FastAPI tests passed. The physically
isolated Recommendation-retirement harness proved one real `55P03` rollback,
53 transition assertions, and 368 final-state assertions across 15 pgTAP files
while preserving a SHA-256 over every ordered normal-history `version`, `name`,
and `statements` fact. The reviewed P4, P5, and P7 migrations were subsequently
applied to the exact normal local database through the separate explicit apply
gate. A following default `npm run verify:db`, without apply authority,
confirmed matching history, every isolated harness, and all 368 normal pgTAP
assertions. All eight independent browser journeys then passed against that
same local checkout and removed their temporary Auth identities. No reset, remote mutation,
deployment, push, real model call, or installed-device check occurred.

The latest recorded lane evidence for this checkout is:

| Lane | Latest recorded evidence | Scope limit |
| --- | --- | --- |
| Docs, visual, Flutter, FastAPI, and web | On 2026-08-14, the P7 working tree passed Docs, Visual, Flutter analysis, all 1,051 Flutter tests, the web build, Ruff/compile, and `1543 passed, 2 skipped` FastAPI tests. | Local task-base working tree only. |
| Representative browser smoke | On 2026-08-11, all four profile-mode Setup, Auth/Capture/Today, Planner-confirmation, and fake-Coach journeys passed and removed their temporary Auth identities. | Deterministic local browser integration only. |
| Database transition/final state | On 2026-08-14, the isolated Goal, Exam Health, Multi-Exam, and P7 chains passed `27`, `6`, `104` twice, and `53 + 368` assertions. After the separately authorized normal apply, default `npm run verify:db` confirmed matching history and all 368 normal pgTAP assertions. | Physically isolated RAM-only transition targets plus the exact normal local database; no reset or remote state. |
| Full browser | On 2026-08-14, the full eight-journey profile-mode suite passed and removed every temporary Auth identity. | Deterministic local browser integration against the P7 working tree only. |
| Android source/build | On 2026-08-02, Android JVM/lint and debug APK gates passed. | No current installed-device or OEM behavior claim. |
| Local database safety | On 2026-08-05, a full archive restore-verification and the reset preview passed; destructive reset execution was not run. | The ignored local archive and exact local database only. |
| Demo seed | On 2026-08-04, the four local demo identities were recreated and the enriched Student fixture passed its focused verification. | Not a remote seed or full-product gate. |
| Real local Coach provider | On 2026-08-10, a disposable local account completed a rendered turn through the explicitly enabled `local_codex_oauth` path. | Exact machine, CLI, image, login, account, and date only; not a production provider. |

Product lanes above remain lane-specific evidence; they are not permission to
claim remote migration state, deployment, installed-device behavior,
push/background delivery, model availability for another account, participant
results, or longitudinal outcomes.

This section is the sole current source for exact test counts, commit ids, E2E
identities, and checkout evidence. Other current documents link here instead of
copying those values.

## Task Base And Affected Selection

Capture the task base before the first change:

```bash
git rev-parse HEAD
```

Run affected selection only with that captured commit:

```bash
npm run verify:affected -- --base-ref <task-base-ref>
```

The wrapper fails closed when `--base-ref` is absent or invalid. It combines
the committed diff from `<task-base-ref>` through current `HEAD` with staged,
unstaged, and untracked paths, classifies them, prints the selected gates, and
runs those gates. Passing `HEAD` covers only current working-tree changes; once
the task creates commits, it omits the earlier committed portion of the task.
Always retain the commit captured before work began.

Expected path selection is conservative:

- documentation-only paths select Docs and Visual;
- ordinary backend paths select Fast;
- ordinary Flutter paths select Fast and Web;
- Auth, routing, core, configuration, schema, mixed-stack, or unknown paths
  select Full.

## Verification Levels

Use the lowest level that covers the complete change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Docs | `npm run verify:docs` | Documentation tests, links, routes, current versions, owner coverage, current claims, and docs-impact rules. | No |
| Visual | `npm run verify:visual` | Frontend visual-system tests and source contract. | No |
| Affected | `npm run verify:affected -- --base-ref <task-base-ref>` | Classifies every task path and runs the required gates. | Depends on selected gates; never grants reset authority. |
| Fast | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:fast` | Docs/visual/source checks, complete Flutter analysis/tests, complete FastAPI checks, and diff hygiene. | No |
| Web | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:web` | Builds the Flutter debug web bundle. | No |
| Database | `npm run verify:db` | Requires matching local migration history, runs the isolated transition harness, then the complete pgTAP suite. | No |
| Reviewed migration apply | `APPLY_MIGRATIONS=true npm run verify:db` | Applies reviewed pending local SQL, rechecks history, then runs database verification. | May change or delete local rows. |
| Full | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:full` | Runs Fast, Database, Web, and all browser journeys. | No reset; browser tests create and remove exact local users. |
| Browser smoke | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:smoke` | Runs four representative independent UI journeys. | No reset; removes exact test users. |
| Browser full | `FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:full` | Runs all eight independent UI journeys. | No reset; removes exact test users. |
| Demo seed | `npm run seed:demo` | Recreates only the four named local demo accounts. | Destructive only to those local demo identities. |

`FLUTTER_BIN` falls back to `flutter` and may be set to another executable by
the caller. Do not document or commit a workstation-specific SDK path.

## Documentation And Visual Gates

Run the documentation gate for every repository documentation change:

```bash
npm run verify:docs
```

It runs the documentation regression tests and the live consistency checker.
The checker validates:

- Markdown links and anchors;
- the strict sorted `docs/current-contracts.json` schema;
- every registered code selector and owner version;
- exhaustive named Flutter/FastAPI version-pair coverage within the registry's
  scope;
- the latest migration owner;
- documented FastAPI routes and methods;
- centralization of current checkout evidence;
- known superseded current-state claims; and
- changed-code documentation ownership.

The docs-impact checker compares uncommitted local changes with `HEAD` by
default. CI supplies `DOCS_BASE_REF` so committed pull-request changes are also
included. For whole-task product-gate selection, use the captured task base with
the affected command above; these are related but distinct comparisons.

Run the visual contract separately when selected:

```bash
npm run verify:visual
```

It pins the local font/icon/brand foundation and rejects uncontrolled Material
icons, gradients, colors, radii, fonts, and route-local text styles. It does not
replace viewport screenshots, accessibility checks, or human visual review.
The hosted equivalent is the `docs-visual` job in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## Current Version Coverage

Exam Plan Health is tracked as shared named `exam-plan-health-v1`. Focused
verification covers strict FastAPI/Dart envelopes, exact threshold boundaries,
shared Exam priority and consumers, Focus/reservation arithmetic,
Calendar-window and DST Unknown behavior, owner-derived GET/preview routing,
untruncated one-RPC parsing, Flutter Guest/Mock zero-call guards, editor preview
generation races, Preparation values, Planner combined-empty semantics, Today
non-green filtering, transport-vs-Unknown copy, and 320 px/200% layout.
The focused boundary also covers block-linked versus proposal-time Focus
credit, retained 120-block exhaustion, previous-day overnight and DST anchors,
new/existing preview identity and base revision, Health independence from an
overfull legacy feed, Assignment Series exact-retry invalidation, and previous-
value Async loading/error states.

Multi-Exam balancing is tracked as shared named `multi-exam-plan-v1`.
Focused verification covers strict union/key/revision/change-axis parsing,
explicit target/revision binding, retain-and-supplement and target-only stages,
exact cardinality/tie ordering and search-limit failure, unchanged-plan
canonicalization, single-plan one-time adoption, batch list/detail/confirm/
cancel routing, immutable exact retry across same-principal refresh and
transient Auth error recovery, terminal
proposal replay conflict, stale/saved-refresh confirmation authority, all
competing batch-child mutation guards, shared mutation gating, deep-link/detail
recovery under failed/limited or late bounded feeds, selected-detail versus
list-detail success/error race ordering with source-bound retry authority,
fail-closed DST conversion, valid current-profile IANA confirmation authority,
Guest/Mock zero calls, and populated
narrow/large-text presentation. Backend API/service/repository tests cover
owner-derived identity, one-snapshot authority, total planner-evaluation bounds,
stable `55P03`/`40P01` conflict mapping, learned-timing permission/provenance
CAS, all-or-none result handling, and request replay.

Today Full week is tracked as shared named `today-week-agenda-v1`. Focused
backend coverage proves bearer-derived ownership, exact profile-local
Monday-through-Sunday bounds, one call per source seam, dedicated bounded
owner/range queries and fixed non-rowwise relation reads, canonical
current-revision Preparation credit/lifecycle, current Calendar-import
authority, disconnected-empty and stale-unavailable behavior, all seven
categories/actions, independent partial failure, route-wide profile/timezone
`503`, and DST fold/gap behavior. Focused Flutter coverage proves the strict
temporal envelope including overflow-component rejection and valid fractional
offset timestamps, the identity/action/status union, no device-local time
conversion, guest zero calls, lazy open/retry, midnight-safe Habit navigation,
source-partial rendering, current action mapping, whole-row actionable
semantics and two-pixel schedule-row/accordion keyboard focus rings,
two/two-and-a-half-card mobile widths,
weekend clamp, day snap and week bounds, the 208-pixel seven-column threshold,
dense 320 px/200-percent layout, refresh mapping, and independent 44/24-pixel
information/accordion controls. The old two-source rating/`fullyRated` week
projection is not compatibility behavior; Today at a glance remains unchanged.

The generic Today Recommendation and Decision Feedback retirement is verified
across FastAPI route composition, strict scheduler input, Briefing V2, Weekly
Review V3, Account Export V5, Personal Snapshot V3, Coach prompt V4/context V3,
Flutter provider/surface absence, notification source parsing, and preserved
Sleep Recommendation/Skillset/Insight/Memory/controlled-Coach concepts. The
isolated migration proof uses two owners, a real concurrent lock timeout with
SQLSTATE `55P03`, rollback residue checks, exact structured sanitization,
content-free Coach tombstones with usage retention, current writer/grant/RLS
checks, and the complete final-state pgTAP suite. Historical immutable
Recommendation transition tests remain source evidence but are not current
product-surface evidence.

`docs/current-contracts.json` is authoritative for exact sources and owners.
This runbook retains the following compact current coverage because each listed
boundary explicitly owns verification requirements:

| Boundary | Current version |
| --- | --- |
| Account export | `account-export-v5` |
| Assignment series | `assignment-series-v1` |
| Calendar import | `calendar-import-v2` |
| Calendar consent | `calendar-import-consent-v1` |
| Coach snapshot | `personal-snapshot-v3` |
| Coach prompt | `free-coach-agent-prompt-v4` |
| Daily briefing | `daily-briefing-v2` |
| Daily Capture | `daily-capture-v5` |
| Daily State | `explainable-daily-state-v3` |
| Deadline Plan | `deadline-plan-v1` |
| Exam-Week Outlook | `exam-week-outlook-v1` |
| Executable action | `executable-action-v1` |
| Multi-Exam Plan | `multi-exam-plan-v1` |
| Personal Patterns | `personal-patterns-v1` |
| Planner mutations | `planner-v1` |
| Planner overview | `planner-overview-v2` |
| Preparation workload | `preparation-workload-v1` |
| Preparation workload detail | `preparation-workload-detail-v1` |
| Sleep recommendation | `sleep-recommendation-v1` |
| Today week agenda | `today-week-agenda-v1` |
| Weekly Review | `weekly-review-v3` |

Feature contracts remain the complete wire-format and compatibility authority.

## Fast Verification

Run the standard non-destructive source gate from the repository root:

```bash
FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run verify:fast
```

`npm run verify` and `scripts/verify.sh` are compatible aliases. Fast runs the
documentation and visual gates, shell/source contract tests, Flutter dependency
resolution, clean Flutter analysis and the complete Flutter suite, Python
compilation, non-mutating Ruff, the complete FastAPI pytest suite, and
`git diff --check`. Its independent source, Flutter, and backend groups may run
concurrently.

For a focused Deadline allocation diagnostic before the selected gate, run:

```bash
cd services/ai_service
./.venv/bin/python -m pytest -q \
  tests/test_planning_availability.py \
  tests/test_deadline_plan_service.py \
  tests/test_assignment_series_service.py
cd ../../apps/mobile
"${FLUTTER_BIN:-flutter}" test test/deadline_plans_page_test.dart
```

These files cover kind-specific placement, budget/busy/recovery/remainder/DST
constraints, series windows, internal fingerprinting, and Flutter default/value
retention. A focused pass is diagnostic and does not replace Fast, Web, or the
task-base affected gate.

For a focused Planner Overview V2 diagnostic, run:

```bash
cd services/ai_service
./.venv/bin/python -m pytest -q \
  tests/test_planner_service.py \
  tests/test_planner_api.py \
  tests/test_planner_repository.py \
  tests/test_today_overview_service.py
cd ../../apps/mobile
"${FLUTTER_BIN:-flutter}" analyze
"${FLUTTER_BIN:-flutter}" test \
  test/planner_contract_test.dart \
  test/planner_page_test.dart
```

This pair covers the strict V2 projection and cross-runtime parser, the
unchanged V1 mutation seam, Planner/Today integration, guest call suppression,
bidirectional Task lifecycle/reason relations, current-fact pending staleness,
target-/preview-bound draft cleanup, post-mutation projection locks, and narrow
large-text presentation. Changes limited to those application and
documentation boundaries do not select the database lane because Overview V2
adds no schema, migration, RLS, grant, or RPC; the captured task-base affected
gate remains authoritative if another changed path broadens that scope.

For a focused Today Week Agenda diagnostic, run:

```bash
cd services/ai_service
./.venv/bin/python -m pytest -q \
  tests/test_today_week_agenda_repository.py \
  tests/test_today_week_agenda_service.py \
  tests/test_today_week_agenda_api.py \
  tests/test_today_overview_service.py \
  tests/test_today_overview_api.py
cd ../../apps/mobile
"${FLUTTER_BIN:-flutter}" test \
  test/dashboard_full_week_api_test.dart \
  test/app_schedule_day_card_test.dart \
  test/dashboard_sections_test.dart \
  test/dashboard_page_test.dart \
  test/projection_refresh_coordinator_test.dart
```

The focused run verifies contract/projection/query/action/layout boundaries but
does not replace full Flutter analysis/tests, FastAPI Ruff/compilation/tests,
Docs, Visual, Web, or the task-base affected selector.

Database integration is deliberately separate. A deterministic fake Coach
provider/process seam is mandatory for standard verification; Fast must not
depend on Codex installation, OAuth, model access, subscription status, or an
external network call.

## Local Supabase Verification

The pending Exam Plan Health migration has an additional dedicated
`scripts/lib/exam_plan_health_migration_harness.sh` path. The harness proves
that its target is the physically isolated RAM-only container, applies the full
migration chain there, runs `supabase/tests/exam_plan_health_v1_test.sql`, and
compares the normal local migration history before and after. It never applies
the pending migration to the normal local database. The pgTAP contract checks
service-role-only execution, the inclusive 366-day Exam horizon, exact Focus
credit, confirmed consumer inclusion, and authenticated denial. This isolated
gate is wired into the migration-aware fast/local verification scripts; a
normal local apply still requires the repository's separate explicit opt-in.

The Multi-Exam migration has its own
`scripts/lib/multi_exam_plan_migration_harness.sh` full-chain proof. It uses the
same labeled RAM-only isolation and history-before/after checks, then runs
`supabase/tests/multi_exam_plan_v1_test.sql`. Each of its 104-assertion passes
is run twice against the same isolated database to prove fixture cleanup and
repeatability. The assertions cover the five
private tables, forced RLS and least privilege, composite ownership and bounds,
referencing indexes, service-role-only public RPCs, ungranted inner helpers,
canonical context and learned-timing marker sources, the shared owner-lock
triggers on legacy direct-write authorities, real concurrent Proposal/Task and
Confirm/Habit owner-lock exclusion, explicit committed-fixture/helper cleanup,
owner/request/row-lock order, and failure-reentrant cleanup of its fixed test
owner, helpers, and login. Its second sessions use an expiring test login with
a random SCRAM secret held only in `pg_temp`: normal non-superuser verification
connects through the server interface where password authentication is
required, while the physically isolated superuser target uses its allowed
loopback path. The login receives only exact execution of the Proposal and
Confirm RPCs plus its private fixture/helpers; it never receives
`service_role`. No credential is hard-coded, printed, or retained. If the test
must install `dblink`, the same transaction persists a marker bound to the
extension OID, owner, schema, and version. Cleanup drops an extension without
`CASCADE` only when that exact marker validates; a markerless pre-existing
extension is preserved, and a later run repairs an interrupted marker-owned
installation. Coverage also includes
append-only identity, all single-plan proposal/replan/confirm/complete/cancel
batch-child guards, exact batch replay, cancel cleanup, preference/pilot stale
confirmation, cancel-only-staged semantics, the disjoint
retained/shifted/removed/added review math, and a transactional two-Exam
proposal/stale-confirm/cancel/re-proposal/atomic-confirm lifecycle. The harness
never applies the migration to the normal local database and does not claim
remote state.

The Recommendation/Decision Feedback erase migration has the dedicated
`scripts/lib/recommendation_retirement_migration_harness.sh` full-chain proof.
It uses the same labeled RAM-only isolation and compares a deterministic
SHA-256 over every ordered normal-history `version`, `name`, and `statements`
fact after each stage, applies filled two-owner fixtures, forces a
concurrent-writer `55P03` timeout and verifies full rollback/no helper residue,
then succeeds and runs 53
transition assertions plus the complete final-state pgTAP suite. Its disposable
bootstrap mirrors normal Supabase `service_role BYPASSRLS` and
`"$user", public, extensions` session semantics. The proof never applies the
erase migration to the normal local database and grants no remote authority.

Read `docs/supabase-current-state.md` and
`docs/local-database-safety.md` before database work. Inspect installed CLI
flags with `--help` instead of guessing them.

The normal gate is:

```bash
npm run verify:db
```

It uses the real Supabase CLI and Docker, starts or reuses the local stack,
redacts keys and database credentials, requires repository and local migration
history to match, runs the physically isolated Goal-removal transition harness,
and runs the complete final-state pgTAP suite. It never resets the normal local
database or applies pending SQL automatically.

Migration verification has separate complementary layers:

- Python source guards preserve rollout-sensitive historical migration text.
- The isolated transition harness proves the bounded multi-migration and lock
  behavior in a separate Postgres process with no normal Supabase volume.
- `supabase/tests/*.sql` proves the final applied schema, RLS, grants, triggers,
  constraints, and database behavior.

The Deadline Plan kind-authority coverage pairs a source guard for wrapper
signature, lock/replay ordering, inner/base-function authority, and Assignment
Series delegation with final-state pgTAP for denied direct service-role base
execution, draft and active mismatches, unchanged roots/request ledgers, valid
same-kind writes, and exact replay. The
scheduled-Focus pgTAP also starts and finishes both missed and upcoming
Deadline blocks at supplied server time while proving immutable planned origin,
terminal replay, and exactly-once remaining-minute credit.

A history mismatch fails before pgTAP. After reviewing the pending SQL and
affected local rows, apply it intentionally only with:

```bash
APPLY_MIGRATIONS=true npm run verify:db
```

That operation may change or delete local rows. It is not a reset and must not
be described as non-destructive.

### Backup And Reset Boundary

Normal verification, local-stack, and E2E commands reject `RESET_DB=true` and
have no reset branch. Create a full restore-verified archive with:

```bash
npm run db:backup:local
```

If the user explicitly intends to destroy the exact normal local database,
start with the non-destructive preview:

```bash
npm run db:reset:local
```

Only the content-bound command printed by that fresh preview may execute. The
wrapper creates and restore-verifies another complete backup, rejects target
drift, and invokes only `supabase db reset --local`. Raw reset, `--db-url`
reset, `--linked` reset, a temporary database inside the normal cluster, and
remote reset are forbidden. Follow `docs/local-database-safety.md` for recovery
and approval hygiene.

## Browser E2E

Install the committed Node dependencies and Playwright browser when needed:

```bash
npm install
npx playwright install chromium
```

Run either the representative or complete suite:

```bash
FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:smoke
FLUTTER_BIN="${FLUTTER_BIN:-flutter}" npm run e2e:web:full
```

The smoke runs Setup, Auth/Capture/Today, Planner confirmation, and fake Coach.
The full suite adds Exam-Week Outlook, Notification Lifecycle, Account Controls,
and Personal Learning. `e2e/web/journey-manifest.mjs` is the canonical journey
registry. Every spec owns a fresh account and exact cleanup; cleanup failure
fails an otherwise passing run. Old E2E identities are outside normal cleanup
and use the separate fingerprint-confirmed `npm run e2e:cleanup:local` flow.

The runner requires matching migration history and never applies SQL or resets
automatically. It starts checkout-owned loopback FastAPI and Flutter processes,
uses the deterministic fake Coach provider, keeps service-role and scheduler
credentials out of Flutter, and writes run-specific logs/screenshots/traces
under `.tools/e2e/runs/<run-id>/`.

A single manifest journey may be selected through the focused command described
by `docs/local-dev.md`. Focused execution is diagnostic and never substitutes
for the selected smoke or full gate. If a fresh normal database is genuinely
required, finish the separate guarded reset workflow first and then run the
ordinary E2E command without reset authority.

## Android Verification

For Android Focus Protection or Android platform changes, use the SDK setup and
physical matrix in `docs/android-focus-protection-v1-contract.md`. The local
source/build commands use a caller-provided Flutter executable with fallback:

```bash
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
cd apps/mobile
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test
cd android
ANDROID_HOME="$PWD/../../../.tools/android-sdk" \
ANDROID_SDK_ROOT="$PWD/../../../.tools/android-sdk" \
./gradlew testDebugUnitTest lintDebug
cd ..
"$FLUTTER_BIN" build apk --debug
```

JVM, lint, and APK success does not prove Accessibility blocking, DND/OEM
behavior, calls/alarms, process death, boot, or an installed-device layout.

## Phase 10 Provider Verification

Standard FastAPI, Flutter, database, and browser checks use fakes. The separate
real-model smoke is optional, explicit, network/account dependent, and skipped
by default:

```bash
npm run prepare:coach-analysis
cd services/ai_service
RUN_LOCAL_CODEX_SMOKE=true ./.venv/bin/python -m pytest -q \
  tests/test_local_codex_smoke.py
```

A valid result must prove the contract's exact model and Fast configuration,
required MCP startup, multi-tool synthetic-data execution, and matching
backend-derived trace/source scope. It must not print the prompt, answer, OAuth
state, account data, raw event stream, stderr, paths, or tokens. It proves only
the exact machine, CLI, image, login, account, and date. It does not prove
FastAPI persistence, Flutter presentation, production readiness, or another
developer's availability. Missing capability is an honest failure, never a
reason to add a key, model fallback, or standard-tier downgrade.

## Demo Seed

For repeatable local real-data exploration:

```bash
npm run seed:demo
```

The seed refuses non-loopback Supabase URLs and recreates only the four named
local demo accounts. It verifies the incomplete Setup account and the populated
Student, Worker, and Recovery scenarios. Rerunning invalidates their existing
sessions. The command is not authorized for a remote project and does not
replace browser or product verification.

## Secrets And Logs

- Never paste, print, or commit Supabase keys, database passwords, scheduler
  tokens, bearer tokens, `.env` contents, or Codex OAuth state.
- Local anon keys are valid client configuration but still credentials in chat
  and logs; service-role keys remain FastAPI/Node-only.
- Sanitized `codex login status` is the maximum routine OAuth inspection. Never
  read or copy `~/.codex/auth.json`.
- Use run-specific ignored artifacts under `.tools/`; do not install replacement
  tool binaries there.
- Redact any unexpected credential output before sharing logs.

## Continuous Integration Gates

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) defines the current
hosted workflow:

- `docs-visual` always runs documentation and visual contracts;
- Flutter/Android and complete FastAPI suites run on pull requests;
- path classification adds a web build for Flutter changes;
- schema/database paths add a fresh local migration chain and pgTAP;
- Auth, routing, schema, core/configuration, unknown, or cross-stack changes add
  full browser E2E; and
- scheduled/manual workflow runs execute full browser E2E.

Fresh hosted runners obtain an empty local stack through normal startup. CI does
not set `RESET_DB=true` and cannot call the guarded reset execution path. A local
run is evidence only for the local checkout; do not report a hosted pull-request
gate until that hosted job succeeds.

## Current Automation Gaps

- Hosted CI evidence must come from GitHub; repository source or a local run
  proves only that the workflow is defined.
- There is no deployed scheduler/cron or production background worker.
- Notification Delivery has no Android/system, push, browser, email, or
  background-mobile channel; physical foreground acceptance remains useful.
- Installed-device Google OAuth/recovery, device-specific layout/accessibility,
  and best-effort authenticated guest-capture migration still need manual
  acceptance.
- Calendar coverage uses selected local `.ics` bytes, not provider OAuth,
  refresh/revocation, URL fetch, live sync, provider writes, or native picker
  behavior.
- The Coach's real provider remains local-development-only; another Linux user,
  production isolation/provider, and autonomous answer-quality evaluation are
  not established by deterministic tests.
- The manual student usability study and longitudinal product-outcome evidence
  remain unrun.

When changing browser flows, keep the journey manifest, Playwright config,
fixtures/specs, split-contract guard, runner, local-development guide, and this
runbook aligned.
