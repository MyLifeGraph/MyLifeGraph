# Verification And Agent Automation

Coach V4 changes require mocked provider contract tests (including
`store:false`, tool replay, invalid credentials/output, rate limits, timeout,
no fallback, parallel key isolation, pre-stream admission, durable global
budget races, and strict executor framing), Flutter credential lifecycle tests,
the local Supabase migration/pgTAP gate, and the normal affected selector. A
provider live turn, remote migration, target-host permissions, OAuth dashboard
change, hosted staging smoke, and installed-device smoke are separate evidence
and must not be inferred from repository tests.
The checked current prompt is `free-coach-agent-prompt-v5`.

This is the current runbook for choosing and running repository verification,
recording checkout evidence, understanding CI, and tracking present automation
gaps. Dated superseded results are preserved in
[Verification History](verification-history.md) with explicit historical
status; they never prove a later checkout.

Before running or claiming a gate, inspect the affected boundary and its owning
contract. Test source or a historical pass is not current evidence.

The future hosted acceptance sequence is centralized in
[VPS Pilot Release Plan](vps-pilot-release-plan.md). Its repository,
infrastructure, Supabase/Auth, provider, Vercel, Android, capacity, rollback,
and professor-handoff gates are requirements, not current pass evidence. That
future gate also requires distinct staging/pilot project identities,
publishable/secret-key compatibility, pilot-target denial in synthetic seed
tooling, and versioned 18-or-older acceptance. The local configuration and
hosted-build guards now cover the first two: pilot current-key enforcement,
exact URL/ref binding, and staging crossover denial have focused tests. Remote
key state, a confirmed remote scenario run, VPS deployment, and the hosted
shared Codex provider remain open. Repository source now contains the
default-off operator provider/executor, tagged deployment/rollback package,
signed-APK workflow, and encrypted-backup runner; none is live evidence. The
`staging-scenarios-v1` generator has
source/unit/preview coverage only. `pilot-participation-v1` /
`pilot-participation-notice-v1` adult acceptance and persistent staging
identity now exist in the working tree with focused unit/widget/source tests;
their normal-database and complete captured-base gates now pass as well. The hosted
participation browser flow and remote gates are not current baseline evidence.
The additive `pilot-participation-gate-v1` restrictive-RLS contract and its
operator check/enable tool pass source plus isolated/current local database
tests; exact enablement and attestation against the hosted project remain open.
The `hosted-database-contract-v1` source gate binds hosted readiness and VPS
promotion to the release's ordered migration-prefix head/count/digest and
derives the prepared-deletion guard from installed function definitions. Its
local unit/pgTAP evidence is not a claim about a hosted database.

## Current Verified Baseline

The current pull-request candidate's latest task base is
`675ff6ab3dd701e1221759a97dc8555d35779a16`, which contains the reviewed
promotion merge `f9198ce2a9560916e8d3c440ea31a6097a651fef` plus the bounded
Supabase-runner diagnostics, image-identity fixes, and checkout-complete CI
toolchains, including the shared exact ECR/GHCR allowlist for validated running
and explicitly requested isolated Postgres images. The post-base correction
pins every Android CI, staging, and release workflow to guarded Java 21. That
merge integrates
GitHub `main` commit `87277e704f318bc569d12c88d665759a22eda2f1`
without rewriting either history. Its captured-base selector chooses the Full
lane. The complete captured-base Full selector passed on 2026-08-21: Flutter analysis passed with
1,100 tests, FastAPI Ruff passed with 1,681 tests and 2 intentional skips, and
the debug web bundle built successfully. The source group in the same Fast run
passed the documentation, visual, E2E-split, VPS, backup, Vercel, Android,
Turnstile, staging, participation-operator, and local-safety gates. The normal
PostgreSQL 17 migration history already matched all 69 repository migrations;
the run neither reset the database nor applied SQL. The Database gate passed
against that normal PG17 state and the pinned isolated PG15/PG17 full chains,
including the PG17 owner/ACL restore and deletion replay. Full selector browser
run `20260821T142307Z-451605` passed all eight independent UI journeys without
retry and with exact run-owned Auth cleanup. This is a pass over the local
merge candidate selected from the captured base, not a tagged or deployed
release identity.
The former
2026-08-19 counts belong to the pre-Coach-V4/pre-hosting predecessor and are
retained only in
[Verification History](verification-history.md); they do not prove this tree.

Current 2026-08-21 repository evidence includes 15 VPS tests, 15 backup tests,
3 Vercel-release tests, 5 Android-release tests plus the static Android guard,
documentation consistency across 96 Markdown files and 82 FastAPI routes, the
complete Fast suites above, and the debug web build containing the Turnstile
assets. The tracked, checksum-verified Gradle 8.14 wrapper also completed the
Android `testDebugUnitTest` and `lintDebug` gate successfully on Java 21. The
Android source guard requires that same exact Java version in CI, staging, and
release workflows so Android 36/Robolectric tests cannot regress to the
unsupported Java 17 runner. The normal local
PostgreSQL 17 database and pinned, physically separate
RAM-only PostgreSQL 15 and 17 runs apply the complete 69-file repository chain.
The Recommendation transition suite passed 53 assertions on both pinned
majors, the real multi-session Coach harness passed global 15-of-16 dispatch
admission, 5-of-6 per-owner UTC admission, exact replay, and reconcile/delete
interleavings, and an intentionally compromised pre-existing
deletion-replayer role was refused before its first grant. After trusted
isolated cleanup, PG15 created the exact role without membership while PG17
created only its bootstrap-granted, ADMIN-only creator edge with `SET` and
`INHERIT` disabled. The complete final-state pgTAP corpus passed 475 assertions
in 23 files on pinned PG15, pinned PG17, and the normal PG17 database. The PG17
lane additionally passed a full owner/ACL-preserving dump/restore into a second
RAM-only target and a restored deletion replay. This is local
migration/concurrency/recovery evidence, not remote migration state.

A separate pre-migration rehearsal used the confirmed Staging PostgreSQL 17.6
source at its 59-migration
`20260815082606_coach_byok_completion_dispatch_v1.sql` boundary. It restored the
captured application plus managed Auth/Storage schema into a disposable PG17.6
target, applied the ten recovery migrations to the 69-file head, and matched
raw DDL plus ACLs against an independently migration-built PG17 reference. The
role guard and required deletion-replay transition also passed. This local,
ignored plaintext rehearsal set is pre-migration safety evidence only: it is
not an encrypted off-host Restic snapshot, contains no Management-API Auth
configuration inventory, and did not exercise an off-host deletion journal.

After that rehearsal, independent review, and the full local gate, the user
authorized the exact ten-migration Staging apply from migration-source commit
`2723ab641518e4cd4e68f2f0a45e055926f55f4b`. Supabase CLI 2.107.0 first
reconfirmed project ref `oscrunlndfrecjilojja`, the 59-migration remote
boundary, and an exact ten-file dry-run. The push completed through
`20260820200000_account_deletion_replayer_role_guard_v2.sql`; the post-push
linked listing matched all 69 repository versions and a new dry-run reported
the remote database up to date. A newly authenticated direct Supabase-MCP audit
then passed the PG17.6 Hosted Database Contract, prepared-deletion guard,
version-aware deletion-role attributes/membership, postgres global/public
default-ACL boundary, six-table explicit-grant set, and zero-row classic/vector
Storage inventory. It also confirmed that the participation gate remains off.
The aggregate MCP result is `post_migration_pass=true` and
`overall_pass=false` solely because the Advisor clear-flags are false. Provider
findings remain: leaked-password protection is disabled; 16
RLS-initplan performance warnings belong to retained legacy CamelCase policies;
and 29 unindexed-FK plus 70 unused-index notices are informational. This is
Staging database evidence only; no application, Auth-setting/provider, VPS,
Vercel, or public-pilot deployment is claimed.

| Lane | Latest recorded evidence | Scope limit |
| --- | --- | --- |
| Current VPS/backup/Vercel/Android source gates | Final local rerun passed on 2026-08-21: VPS 15, backup 15, Vercel 3, Android 5 plus its static guard; Docs passed across 96 Markdown files and 82 FastAPI routes. The checksum-verified tracked Gradle 8.14 wrapper also passed `testDebugUnitTest` and `lintDebug`. | Templates/unit and local JVM/lint checks only; no VPS, cloud, signing-key, APK-device, or physical Focus Protection execution. |
| Current Flutter/FastAPI/Web | Captured-base Full passed Flutter analysis and 1,100 tests plus FastAPI Ruff and 1,681 tests/2 skips; the debug web build passed. Full browser run `20260821T142307Z-451605` passed 8/8 journeys without retry and with exact cleanup. | Local browser/fake-provider evidence only; no hosted public-origin or real-provider claim. |
| Current database | Normal PG17 plus pinned RAM-only PG15/PG17 69-migration runs passed both 53-assertion transition proofs, hostile pre-role refusal/safe clean retry, real multi-session Coach races, and 23-file/475-assertion final-state pgTAP on 2026-08-21; PG17 also passed full owner/ACL restore and deletion replay. The exact ten-file Staging push then advanced the linked project from 59 to the matching 69-migration head. | Hosted evidence is limited to the explicitly inspected Staging database; no encrypted off-host restore/replay or real-data pilot-project claim. |
| Pre-migration Staging restore | Confirmed PG17.6/59-migration Staging dump restored to disposable PG17.6, advanced to 69, matched strict DDL/ACL reference, and passed role/deletion-recovery postconditions. | Local ignored plaintext rehearsal only; no off-host Restic, Management-API Auth-config inventory, or deletion-journal replay claim. |
| Historical browser/Android/local-provider/staging | See Verification History and the dated remote staging section below. | Historical evidence only; never a claim about this checkout. |

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
| Database | `npm run verify:db` | Requires matching local migration history, runs the isolated transition harnesses including the pinned PG17 migration/restore/replay lane, then the complete normal-local pgTAP suite. | No |
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
Review V3, Account Export V6, Personal Snapshot V3, Coach prompt V4/context V3,
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
| Account export | `account-export-v6` |
| Assignment series | `assignment-series-v1` |
| Calendar import | `calendar-import-v2` |
| Calendar consent | `calendar-import-consent-v1` |
| Coach snapshot | `personal-snapshot-v3` |
| Coach prompt | `free-coach-agent-prompt-v5` |
| Coach request | `coach-request-v4` |
| Coach response | `coach-response-v4` |
| Coach capabilities | `coach-capabilities-v5` |
| Coach history | `coach-history-v4` |
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
`"$user", public, extensions` session semantics. The gate runs the complete
chain on pinned `public.ecr.aws/supabase/postgres:15.8.1.085` and
`public.ecr.aws/supabase/postgres:17.6.1.113`, independent of the normal local
major. PG16+ full-chain harnesses keep bootstrap superuser OID 10 separate from
a non-superuser `postgres` migration identity with `CREATEROLE`. The PG17 lane
verifies the automatic ADMIN-only creator edge, runs the complete 23-file pgTAP
corpus, then full-dumps the final database, restores it with owners/ACLs into a
second RAM-only PG17 target, and executes one restored deletion replay before
cleanup. The proof never applies the erase migration to the normal local
database and grants no remote authority.

The local harness refuses to download either compatibility image implicitly.
Fresh database CI obtains PG17 through the configured normal Supabase start and
explicitly pulls the pinned PG15 tag before invoking the same gate.

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

During database verification and browser E2E, `supabase start` writes its raw
progress to a mode-`0600` temporary log. A successful start emits one stable
marker; a failed start emits only the final 200 sanitized lines and preserves
the CLI failure. The raw log is trap-cleaned. This keeps GitHub Actions log
backpressure from turning a successful multi-image pull into a false failure
while retaining bounded diagnostics. Running-target validation and explicit
isolated-image requests share one allowlist for only the official ECR and GHCR
Supabase Postgres namespaces. Expected lock-timeout classification in the
isolated Goal transition uses baseline runner text tools and has no optional
`rg` dependency.

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
source/build commands use a caller-provided Flutter executable with fallback.
The Gradle 8.14 launcher scripts and wrapper JAR are tracked, so a fresh CI
checkout can run the JVM/lint gate. `verify:android-release` rejects an ignored
or missing wrapper, a wrapper JAR that differs from Gradle's published SHA-256,
or wrapper properties with missing, commented, duplicate, unexpected, or
mismatched active values. It also requires exactly one active Java 21 pin in
each Android CI, staging, and release workflow. Git pins the Unix launcher to
LF, the Windows launcher to CRLF, and the wrapper JAR to binary treatment:

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
- Current publishable and legacy anon keys are valid client configuration but
  still credentials in chat and logs. Current backend secret keys and legacy
  service-role JWTs remain FastAPI/Node-only and are stripped from Flutter
  build/start child environments.
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

The staging-APK, signed-pilot-APK, and pilot-backup workflows pin every
third-party Action to an immutable full commit SHA while retaining the reviewed
major version as an inline comment. Updating one of those SHAs is a separate
supply-chain review; a moving major tag is not accepted in these
credential-bearing workflows.

## Current Automation Gaps

- Hosted CI evidence must come from GitHub; repository source or a local run
  proves only that the workflow is defined.
- VPS/HTTPS/tagged-release, rollback, permission, monitoring, and signed-Android
  artifacts have static/unit rehearsal coverage only. Their target-host,
  certificate, signed-secret, physical-device, and promotion gates have no
  current deployment evidence. Static rehearsal binds each release to a
  deterministic analysis-image tag, seals the complete prepared tree, rejects
  post-seal mutation before promotion, and restores the prior tag on symlink
  rollback; actual root ownership and retained-image availability still require
  VPS evidence.
- There is no deployed scheduler/cron or production background worker.
- Notification Delivery has no Android/system, push, browser, email, or
  background-mobile channel; physical foreground acceptance remains useful.
- Installed-device Google OAuth/recovery, device-specific layout/accessibility,
  and best-effort authenticated guest-capture migration still need manual
  acceptance.
- Calendar coverage uses selected local `.ics` bytes, not provider OAuth,
  refresh/revocation, URL fetch, live sync, provider writes, or native picker
  behavior.
- OpenAI/Gemini BYOK adapters are covered by deterministic HTTP mocks but have
  no live-key turn. The local Codex provider remains development-only. The
  separate `coach-executor` protocol, admission, permission templates, and
  deterministic failure paths are implemented, but no target-host UID/socket/
  rootless-Docker/login smoke or autonomous answer-quality evaluation exists.
- Hosted Turnstile acquisition/reset/cancel/error source now covers each
  protected email Auth operation on web and Android, but the real widget,
  domain, Supabase provider/secret, browser, accessibility, and physical-device
  acceptance remain unverified. Release-day Google OAuth/redirect settings are
  also external gates. Shared-provider global admission/budget and invalid-BYOK
  no-fallback have deterministic repository coverage but remain unverified
  through public origins.
- No separate real-data pilot Supabase project or remote current-key rotation is
  repository-proven. Local code now supports publishable/secret keys and exact
  staging/pilot crossover guards plus source-level visible staging identity,
  versioned 18-or-older acceptance, and a hard-allowlisted staging scenario
  generator. Normal local migration evidence, confirmed remote fixture
  creation/cleanup, remote migration, and public-origin acceptance remain
  absent.
- Pre-stream HTTP 429 admission, same-id retry without claim/budget, executor
  reservation cleanup, and race/disconnect behavior are implemented and
  deterministically tested. The global UTC-day aggregate is tested to survive
  owner/account deletion while personal dispatch linkage cascades; public/VPS
  acceptance remains open.
- An inert protected GitHub workflow can create encrypted checksum-verified
  Restic snapshots, enforce empty Storage, retain 7 daily/4 weekly, and call an
  off-host heartbeat. No storage account/credentials, real backup snapshot,
  isolated database restore, deletion replay, API/TLS monitor, or tested alert
  exists yet.
- `account-deletion-v2`, `account-deletion-status-v2`, the
  `account-deletion-journal-v2` writer/exporter, dedicated-role replay, and
  watermark checks exist in source. No real object-locked journal, encrypted
  snapshot, isolated database restore/replay, or recovery cutoff has passed;
  an older backup must not be opened as if post-backup deletions were already
  preserved.
- The manual student usability study and longitudinal product-outcome evidence
  remain unrun.

When changing browser flows, keep the journey manifest, Playwright config,
fixtures/specs, split-contract guard, runner, local-development guide, and this
runbook aligned.
