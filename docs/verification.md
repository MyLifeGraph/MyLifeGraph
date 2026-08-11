# Verification And Agent Automation

Android Focus Protection adds Flutter domain/widget/lifecycle coverage, native
JVM lease/package/policy tests, and manifest/source guards. Run:

```bash
cd apps/mobile
/home/gregor/tools/flutter/bin/flutter analyze
/home/gregor/tools/flutter/bin/flutter test
cd android
ANDROID_HOME="$PWD/../../../.tools/android-sdk" \
ANDROID_SDK_ROOT="$PWD/../../../.tools/android-sdk" \
./gradlew testDebugUnitTest lintDebug
cd ..
/home/gregor/tools/flutter/bin/flutter build apk --debug
```

Real overlay, user/OEM Zen overrides, call/alarm policy, process death, and boot
still require the physical matrix in
`docs/android-focus-protection-v1-contract.md`.

This document is the shared runbook for automated checks. It describes what can
be verified by agents without manual app exploration, what requires local
tooling, and what remains future work.

The current Setup-personalization/friction retirement verification boundary is
`docs/setup-personalization-retirement-contract.md`. Historical results later in
this file remain records of their checkout; they do not redefine current
Capture V5, Daily State V3, Exam-Week Outlook V1, or Coach V3 expectations.

## Current Verified Baseline

The frontend information/copy consistency pass was reverified locally on
2026-08-11 without a schema or contract-version change. The final
`verify:fast` run passed the documentation, source/process/visual, Flutter
analysis, all 928 Flutter tests, and Python checks, including `1383 passed, 2
skipped` FastAPI tests. The focused shared-disclosure and Calendar command
passed 13 tests. The official profile-mode browser smoke passed all four
independent Setup, Auth/Capture/Today, Planner-confirmation, and fake-Coach
journeys and removed every temporary Auth identity.

A separate stable local-build smoke signed in as the seeded Maya student and
exercised Today, both Morning pages, Evening through the sleep-plan page,
Settings grouping, Calendar import, Reminder settings, Personal learning,
Weekly Review, and Today at 320 logical pixels. It opened the relevant
independent information disclosures without saving either draft, verified the
24×24 Today exception and standard 44×44 actions, checked dynamic Show/Hide and
expanded semantics, found no retired Morning interval instruction, and emitted
no browser page or console error. Reviewing its Settings, open-Calendar,
Weekly-Review, and 320-pixel Today screenshots found no presentation overflow.
That rendered smoke exposed and then reverified one shared fix: standard
information actions now introduce a distinct web semantics node instead of
merging the heading and visible card copy into the button. The browser sign-in
helper now follows the current `Sign in` label. No reset, migration application,
remote mutation, deployment, push, or final Capture save occurred.

The two-step Morning Check-in and five Capture information disclosures were
reverified locally on 2026-08-10 without a schema or contract-version change.
The focused Capture/widget/app integration command passed 33 tests. The final
`verify:fast` run passed all 15 documentation regressions, the
51-Markdown/75-route consistency inventory, source/process/visual guards,
clean Flutter analysis, all 923 Flutter tests, Python/Ruff/compile checks, and
`1383 passed, 2 skipped` FastAPI tests. A fresh debug Flutter Web build then
signed in as the seeded Maya student and exercised both Morning pages, initially
closed independent help, dynamic Show/Hide semantics, valid Next gating, and
exact clocks/target/quality/energy retention through Back. The smoke confirmed
the retired interval instruction was absent and deliberately did not invoke the
final save. Its temporary browser, script, and loopback frontend session were
removed. No reset, migration application, remote mutation, deployment, push,
installed-device check, or push/background-delivery claim occurred.

The finite Assignment Series and live-Coach working tree was fully reverified
locally on 2026-08-10. `verify:fast` passed all 15 documentation regressions,
the 51-Markdown/75-route consistency inventory, source/process/visual guards,
clean Flutter analysis, all 916 Flutter tests, Python/Ruff/compile checks, and
`1383 passed, 2 skipped` FastAPI tests. The local migration history matched the
repository. The physically isolated Goal transition harness passed 27
assertions, and the complete database gate passed 218 assertions across 12
pgTAP files, including the new series RLS, grant, replay, atomic confirmation,
future-edit, and cancellation checks. During implementation the reviewed
`20260810092841_finite_assignment_series_v1.sql` migration was applied through
the explicit `APPLY_MIGRATIONS=true` workflow; no database reset occurred.
The final `verify:full` run repeated Fast and database verification, built
Flutter Web, and passed all eight independent profile-mode browser journeys on
free loopback ports `7359` and `8002` without retry in 6.0 minutes. Every
registered E2E identity was removed (the account-deletion identity was already
absent as expected), and both checkout-owned test processes were cleaned up.

The checkout-owned loopback stack then served Flutter on `7357`, FastAPI on
`8000`, and the development-only `local_codex_oauth` provider with `gpt-5.5`.
A browser smoke signed in as the seeded Maya student, reached a ready Coach
surface, opened direct Assignment and Exam flows with fixed kinds, observed the
default 12 finite occurrences, and found no prior-work controls. No Maya data
was submitted to the external model. A separate disposable synthetic account
completed a real rendered Coach turn, and another disposable-account smoke
proposed independent Assignment plans, confirmed the series atomically, and
cancelled its future scope atomically with zero prior credit. Both disposable
accounts were removed. These checks establish only this local machine and
loopback checkout; they do not claim remote deployment or production provider
availability.

The seven pre-commit finding fixes, the surrounding Today Full-week working
tree, and the direct capability-gated Weekly Review entry were fully reverified
locally on 2026-08-05. The Affected dry run
classified the checkout as `config+core+docs+flutter+unknown` and selected
`verify:full`; the final
`bash scripts/verify_affected.sh --base-ref HEAD` invocation completed that
entire gate. Its source checks included the fail-closed E2E process-ownership
regressions. Documentation verification passed all 15 regressions and the
51-Markdown/70-route consistency inventory; Flutter analysis was clean and all
910 Flutter tests passed; FastAPI reported `1370 passed, 2 skipped`. Local
Supabase migration history matched the repository without applying SQL. The
physically isolated Goal transition harness passed 27 assertions, and the
complete local database gate passed 207 assertions across eleven pgTAP files.
The web build passed. Profile-mode E2E run `weekly-review-direct-20260805a` started
checkout-owned FastAPI and Flutter processes on free loopback ports `8002` and
`7359`, passed all eight independent journeys without retry in 6.1 minutes,
and cleaned up every registered test identity: eight were deleted by cleanup
and the account-controls identity was already absent after its tested permanent
deletion. The runner then cleaned up both owned application processes.
`git diff --check` passed; the staged diff was empty and the complete
unstaged/untracked inventory was reviewed. No reset, `APPLY_MIGRATIONS`, schema
or contract-version change, dependency upgrade, remote mutation, deployment,
push, installed-device check, or push/background-delivery claim occurred.

The preceding local-database safety patch plus hardened Goal-removal and
observational Weekly Review working tree was fully reverified locally on
2026-08-05. Normal verification, stack start, and E2E reject reset delegation;
the dedicated reset wrapper passed its target-bound preview only, and its
destructive execution mode was not run. `npm run db:backup:local` created
`.tools/supabase-backups/mylifegraph-local-20260805T065833Z-2486678.dump`,
verified its SHA-256, and restored the complete custom archive in a physically
separate RAM-only Postgres container. The restored database matched the source's
four Auth users, four profiles, and latest migration `20260804192406`. No
owned disposable container remained. After backup, preview, the full database
gate, and browser cleanup, the normal local database still had four Auth users,
four profiles, and the same migration; Maya's exact seeded identity still had
one Auth row, one matching profile, and 43 Daily Log rows. The physically
isolated Goal transition harness passed `27` assertions including the
two-session lock-timeout, rollback, and retry path; the matching-history
final-state gate passed `207` assertions across eleven pgTAP files. The docs
source suite passed all `15` regressions and the final consistency inventory
covered 51 Markdown files and 70 FastAPI routes. `verify:fast` passed `859`
Flutter tests with clean analysis and reported `1370 passed, 2 skipped` for
FastAPI; the web build passed. The final `verify:full` run on free loopback
ports `7359` and `8002` repeated the Fast, database, and web gates and passed
all eight independent profile-mode browser journeys without retry in 6.1
minutes of test time. `git diff --check` passed; the staged diff was empty and
the complete unstaged/untracked inventory was reviewed. This evidence describes
only the local checkout, ignored local backup, and local Supabase instance. No
reset execution, new migration application, remote migration, restore,
deployment, push, or remote-state claim occurred.

The preceding hardened Goal-removal and observational Weekly Review working
tree was fully reverified locally on 2026-08-04. During development of the isolated
transition harness, Supabase CLI `2.107.0` treated a loopback `--db-url` as its
normal local target and recreated the normal local database through migration
`20260804102409`; its local rows were lost. The harness was consequently made
reset-free: it now creates an exact marked temporary database, bootstraps the
minimum Supabase substrate, applies version-bounded migrations with
`migration up --db-url`, and drops only that exact database in its trap. After
the incident and before applying the repository migrations, counts-only checks
reported `0` structural Goal rows, `0` dangling Weekly Reviews, and `0` V1
full-snapshot Coach turns. `APPLY_MIGRATIONS=true npm run verify:db` then
applied both Goal migrations without another reset. The isolated transition
harness passed `27` assertions, including the two-session lock-timeout,
rollback, and retry path; the matching-history final-state database gate passed
all `207` assertions across eleven pgTAP files. The focused migration source
suite reported `13 passed`, and all `13` documentation-consistency regressions
passed. `verify:fast` passed `859` Flutter tests with clean analysis and
reported `1370 passed, 2 skipped` for FastAPI; the source, visual, Ruff, and web
build checks passed. The first complete browser invocation was discarded
because pre-existing processes occupied ports `7357` and `8000`. The final
complete `verify:full` run on free loopback ports `7359` and `8002` repeated the
Fast, database, and web gates and passed all eight independent profile-mode
browser journeys without retry in 6.1 minutes of test time. This evidence
describes only the local checkout and local Supabase instance; no remote
migration or deployment was performed or inferred.

The preceding original Goal-removal and observational Weekly Review working
tree was fully reverified locally on 2026-08-04. Before its destructive
migration was applied, a counts-only inspection found zero Goal rows and zero
Goal-dependent derived, notification, feedback, memory, or Coach-history rows
requiring deletion; one surviving Weekly Review required the V2 upgrade and
carried one historical non-empty proposal array. The reviewed migration was
then applied without a reset. The post-apply check found the Goals table absent,
the surviving review at V2, and its historical proposal array preserved.
`verify:fast` passed `859` Flutter tests with clean analysis and reported `1364
passed, 2 skipped` for FastAPI; the documentation, visual, source, Ruff, and
diff checks also passed. The matching-history database gate passed all `207`
assertions across eleven pgTAP files, and the debug web build passed. A final
complete `verify:full` run on alternate loopback ports passed all eight
independent profile-mode browser journeys without retry in 6.0 minutes of test
time. This preceding evidence describes only that local checkout and local
Supabase instance.

The preceding local demo-seed compatibility working tree was verified on
2026-08-04. The focused precise-sleep contract suite reported `21 passed`, and
the changed Python files passed Ruff check, Ruff format, compilation, and diff
checks. A complete `npm run seed:demo` then recreated only the four named local
demo accounts and verified the enriched Student fixture: 43 Daily Capture days,
36 rated Focus days, a ready Sleep Recommendation, Calendar Import,
Preparation Plans, notifications, and Coach history. The loopback-only
`start:local:coach:fake` stack subsequently reached healthy FastAPI and Flutter
Web endpoints with deterministic Coach replies. This follow-up only passes the
persisted `capture_version` into the demo verifier's two shared sleep parsers
and adds a source-level caller-binding regression; no reset or migration
application was used, and the full pgTAP/web-build/browser gate was not
repeated.

The implementation commit immediately before that,
`e8014fbe4d913195b81e4be924df03a864b35e05` was reverified locally on
2026-08-04 with `verify:affected --base-ref origin/new_backend_gh`, which
classified the three committed branch changes as mixed and selected the
complete `verify:full` gate. `verify:fast` passed `869` Flutter tests with clean
analysis, FastAPI reported `1353 passed, 2 skipped`, and documentation, visual,
source, Ruff, and diff checks passed. The matching-history database gate passed
all `222` assertions across eleven pgTAP files without a reset or migration
application, and the debug web build passed. The fresh profile-mode browser
suite passed all eight independent journeys without retry in 6.1 minutes of
test time. Those journeys registered nine exact Auth users, deleted eight, and
confirmed the account-deletion subject already absent; the Personal Learning
journey covered the ready Sleep Recommendation card and removed its exact test
identity.

The preceding `fd1bcb24e272a6da429159ad8ee2d0e643963e89`
checkout ran `verify:affected --base-ref HEAD`, which selected the complete
`verify:full` gate. Its matching-history database gate passed all `222`
assertions across eleven pgTAP files without a reset, and the debug web build
passed. The first browser invocation was discarded because a
pre-existing Uvicorn process held port 8000 and prevented the checkout server
from binding. After that exact local process was stopped, the fresh full
profile-mode browser suite passed all eight independent journeys in 6.1 minutes
of test time. Those journeys registered nine exact Auth users, deleted eight,
confirmed the account-deletion subject already absent, and covered the ready
Sleep Recommendation card plus a persisted `daily-capture-v5` capture without
`day_shape`.

The preceding database-verification working tree was reverified locally on
2026-08-02. A fresh local reset applied the complete repository migration chain
documented in `docs/supabase-current-state.md`; the matching-history database
gate then passed all `213` assertions across eleven pgTAP files.
`verify:fast` reported `851` passing Flutter tests, clean Flutter analysis,
`1293 passed, 2 skipped` for FastAPI, and passing documentation, visual, source,
Ruff, and diff checks. The debug web build, Android unit/lint gate, and debug APK
passed. The focused `planner-confirm` profile-mode browser journey passed in
1:56 of test time and removed its exact Auth user. It first proved two
concurrent manual V2 starts produce exactly one success and one
`409 active_focus_session`, then used a real confirmed Preparation block to
confirm the planned-source snapshot, different actual start, server-side finish
with non-zero actual minutes, exact chosen-block credit, exact-session
reflection, and persisted reflection reload. The pgTAP suite separately proves
that a genuinely past `missed` Preparation block can start at a free current
instant, excludes only its own source block, and credits the chosen block
without changing total plan progression. `supabase db lint --local --schema
public,private --level warning --fail-on warning` returned an empty result with
no schema error or warning. The local security and performance advisors also
returned no issue. The cleanup pgTAP file separately proves the closed
canonical role wrapper, unchanged Account/Auth cascade, service-only grants,
and durable interrupted Coach replay plus its single usage-ledger fact.

The preceding Observatory visual-material working tree was reverified locally on
2026-08-01 through implementation and cleanup. `verify:fast` reported `814`
passing Flutter tests, clean Flutter analysis, `1146 passed, 2 skipped` for
FastAPI, and passing documentation, visual, source, Ruff, and diff checks. The
debug web build passed. Repository/local migration history matched before the
full eight-journey Playwright gate, which passed against a statically served
profile-mode Flutter bundle in 4:14 of journeys and 4:14 runner time. Its specs
registered nine exact Auth users, deleted eight, and confirmed the
account-deletion subject already absent. A separate statically served
debug/mock Chromium probe selected the persisted Space appearance and passed
visual checks of Auth, Today, Planner, and Settings at 390×844. The previously
verified complete eight-file pgTAP suite remains at `150` assertions; this
presentation-only slice did not rerun or change database tests.

Earlier architecture-remediation checkpoints below are historical evidence for
their then-current checkout. The now-retired monolithic regression passed in
15:37 runner time with 14:48 of journeys, 49 pre-enabled Semantics checks with a
0.425-second maximum, and exact cleanup of all six registered users (five
deleted and the account-delete subject already absent). The final source and
diff checks were rerun after each subsequent remediation item.
After the application-owned Supabase HTTP pool was introduced, the six-spec
split browser smoke passed again in 1:56 runner time and 1:48 of journeys,
including exact per-spec Auth cleanup.
The Python dependency and lint remediation was then verified from a fresh
Python 3.12 virtual environment: the committed development lock installed with
hash enforcement, Ruff passed without modifying source, the complete backend
suite passed against that locked graph, and `verify:fast` passed with the same
then-current backend and Flutter counts. Regenerating both locks without
`--upgrade` retained their exact SHA-256 file digests.
The profile-local Flutter date boundary is covered by focused IANA
cross-midnight/DST, invalid-account-timezone, guest-device, standalone/embedded
Habit, Daily Capture, Focus, and Deadline tests. Clean analysis and all `734`
Flutter tests passed for this remediation item.
The Flutter transport boundary has focused timeout, connection/offline,
cancellation, response/status/body, authorization, conflict, and ambiguous
mutation-outcome coverage. Controller and widget suites retain the existing
Setup, Calendar, Planner, Deadline Planner, Notification, Account, Learning,
and Coach retry/reload semantics. A source test fails if any feature
application, domain, or presentation layer imports Dio. Clean analysis and all
`742` Flutter tests passed; the final `verify:fast` run also passed the
documentation, visual, source, diff, Ruff, and complete 1,121-passed/2-skipped
backend gates.

Before the P0 test-infrastructure work, the recorded warm timings were
25.08 seconds for the standard repository gate, 23.10 seconds for the old
Supabase preflight, 2:43 for focused Coach E2E, and 25:57 for full E2E. The P0
interfaces were then measured on the same machine: `verify:fast` passed in
27.29 seconds with the same 726 Flutter and 1,115 backend tests;
`verify:db` passed all 142 pgTAP assertions in 2.90 seconds even with
`FLUTTER_BIN` deliberately invalid; and the first and repeated debug web builds
passed in 27.38 and 27.31 seconds.

The P0 full browser run
`p0-full-20260730i` passed in 14:53 runner time, 11:03 faster than its recorded
25:57 baseline. Its 49 pre-enabled Semantics checks each completed in less
than 0.4 seconds after the Flutter shell. Exact cleanup registered six Auth
users, deleted five, accepted the one already removed by the account-deletion
journey, and read every identity back as absent.
The final focused Coach run `p0-coach-final-20260730` also passed in 1:36
runner time; all four Semantics checks were below 0.4 seconds and both exact
Auth users were removed.

The first split-suite baseline then passed all six serial tagged specs.
`split-final-20260730a` reported 1:56 runner time and 1:51 of journeys (about
2:17 including Supabase, FastAPI, and Flutter startup), and
`split-new-full-20260730a` reported 1:55. The unchanged detailed oracle
`split-legacy-20260730a` passed in 15:22 runner time, including 14:47 of
journeys, 49 pre-enabled Semantics checks with a 0.432-second maximum, and
exact cleanup of all six registered users. A non-destructive legacy-account
preview after those runs still found the same pre-existing 107 accounts and
fingerprint `e2e-users-107-02f006e46c6549ba`; none of the new run identities
remained, and the historical selection was not deleted.

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

The current repository migration boundary is owned by
`docs/supabase-current-state.md`. The scoped synchronization catalog in
`docs/current-contracts.json` records current named Flutter/FastAPI versions,
explicit exceptions, their exact code selectors, and their documentation
owners. Feature contracts remain the complete wire-format authority.

## Verification Levels

Use the lowest level that covers the change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Fast | `FLUTTER_BIN=/path/to/flutter npm run verify:fast` | Docs/visual and source checks, clean Flutter analysis and complete Flutter tests, complete pytest, compile, and diff checks. | No |
| Affected | `npm run verify:affected -- --base-ref <ref>` | Conservatively selects gates from all committed, working-tree, and untracked paths; core/Auth/routing/config/schema/mixed/unknown changes escalate to full. | Depends on selected gate |
| Web build | `FLUTTER_BIN=/path/to/flutter npm run verify:web` | Builds the Flutter debug web bundle. | No |
| Local Supabase preflight | `npm run verify:db` | Starts local Supabase, requires matching migration history, runs the physically isolated transition harness, and runs the complete pgTAP suite without Flutter. | No |
| Local Supabase migration apply | `APPLY_MIGRATIONS=true npm run verify:db` | Explicitly applies reviewed pending SQL, verifies history, then runs pgTAP. | May change or delete local rows |
| Local Supabase backup | `npm run db:backup:local` | Creates a full custom dump and publishes it only after a successful restore in a separate RAM-only Postgres container. | No source mutation; writes sensitive ignored backup artifacts |
| Local Supabase reset preview | `npm run db:reset:local` | Validates and displays the exact local target plus a content-bound confirmation token. | No |
| Guarded local Supabase reset | Exact `RESET_DB=true RESET_DB_CONFIRMATION=... npm run db:reset:local` command printed by a fresh preview | Restore-verifies a full backup, refuses target drift, then invokes only `db reset --local`. | Yes, exact local DB only |
| Full | `FLUTTER_BIN=/path/to/flutter npm run verify:full` | Runs fast, database, web-build, and full browser E2E gates. | No reset; E2E writes and removes exact test users |
| Browser smoke | `FLUTTER_BIN=/path/to/flutter npm run e2e:web:smoke` | Runs four representative tagged UI journeys serially with independent accounts. | No reset; removes each spec's exact users |
| Browser full | `FLUTTER_BIN=/path/to/flutter npm run e2e:web:full` | Runs all eight independent Playwright UI journeys. | No reset; removes each spec's exact users |
| Focused browser journey | `E2E_JOURNEY=coach FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Runs one named current journey for diagnosis; any journey filename without `.spec.mjs` is accepted. | No reset; removes the spec's exact users |
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
intentionally empty optional Setup-owned collections. The seed creates no Goal
data. Separately seeded habits and schedule rows retain `demo_seed`
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
- one current facts-only Weekly Review with an empty proposal array;
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

## Fast Verification

From the repository root:

```bash
FLUTTER_BIN=/path/to/flutter npm run verify:fast
```

The compatible `npm run verify` and `scripts/verify.sh` aliases run the same
gate. Its independent source, Flutter, and backend groups run concurrently. It
runs:

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
- the complete `flutter test` suite
- `python3 -m compileall services/ai_service/app`
- the non-mutating `python -m ruff check app tests` backend gate
- the complete `python -m pytest` suite
- `git diff --check`

The documentation checker validates the strict, sorted
`docs/current-contracts.json` schema, reads every declared code symbol or
literal locator, compares it with the catalog version, and checks that every
listed owner names that version. `coverage: shared_named` entries are discovered
from named version constants shared by production Flutter and FastAPI; the
checker fails when the catalog omits the contract or one of those declarations.
`coverage: explicit` records the deliberate single-runtime or literal-based
exceptions. This makes the catalog exhaustive for its declared scope without
hard-coding feature paths in the checker.

Only `docs/supabase-current-state.md` is required to name the latest repository
migration. A migration diff must also update this verification owner and the
affected feature contract, but it updates `AGENTS.md` only when the stable agent
workflow or a safety rule changes. Other current documents route readers to the
Supabase owner instead of duplicating the moving filename.

Database integration is deliberately separate: `npm run verify:db` runs
migration-history checks plus pgTAP and never repeats Flutter tests.

The stabilization evidence must include branch-CAS Capture writes, revisioned
account settings, Setup-owned DML guards, timezone-bound Calendar/Planner
races, observed Snapshot/Weekly Review ordering, Berlin DST gap/fold and
cross-midnight cases, Flutter profile/device date disagreement, and durable-
write/reload-failure states. The
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

It checks local Markdown links and anchors; cataloged code-owned contract
versions and shared Flutter/FastAPI declaration coverage; the newest migration
references; documented FastAPI routes; centralized verification evidence;
known superseded claims; and changed-code ownership by an appropriate contract
or runbook.
Locally it compares uncommitted work with `HEAD`.
`.github/workflows/docs-consistency.yml` runs the same gate for pushes and pull
requests with `DOCS_BASE_REF` set to the event's base commit, so committed
branch changes receive the same docs-impact check.

FastAPI unit tests are run separately:

```bash
cd services/ai_service
./.venv/bin/python -m ruff check app tests
./.venv/bin/python -m pytest
```

Use `python -m pytest` from an environment with `services/ai_service`
requirements installed if the local `.venv` does not exist. CI and clean
environments install the committed `requirements-dev.txt` with
`--require-hashes`; direct dependency ranges remain in `pyproject.toml` and are
advanced only through the documented deliberate lock-update workflow.

Phase 10 follows that locked separation: every normal FastAPI, Flutter,
Supabase, and browser check uses an injected deterministic fake Coach provider.
Standard verification must never depend on a Codex installation, ChatGPT
subscription, OAuth login, live model, or external network call. The
development-only `local_codex_oauth` adapter is covered with fake process
runners. See `docs/phase-10-controlled-coach-plan.md`.

FastAPI tests cover authenticated Setup/Intake, deterministic recommendations,
and the snapshot aggregator endpoint. The feature-owned API problem-translation
suite enumerates the exact public status/detail/header matrix, including the
structured Intake and Coach details. Source-boundary coverage additionally
rejects repository imports anywhere under `app/api`, while route tests continue
to exercise authentication, request validation, operation-specific catches,
and the Coach's established sanitized unexpected-error behavior. Setup coverage
includes principal-derived
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
metadata. Current Intake tests additionally require supported retired legacy
keys to be accepted then stripped before comparison/storage,
`responses.goals` to be rejected, notification preferences to remain unchanged,
and no post-Setup Recommendation generation. Daily State V2 tests cover every active
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
rejected versus outcome-unknown timezone updates, device-persisted
Dark/Light/Space appearance with ordered writes and rollback,
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
GET versus local guest zero-call behavior, and cover section order, the absent
`More` and Today workload surfaces, the five-value `Beat yesterday` inset,
the direct capability-gated Weekly Review entry, independently and
simultaneously open remaining supporting accordions, all-task expansion,
source-error truth, and 320-pixel/2.0-text-scale rendering. The feature-local
information-disclosure coverage checks every affected collapsible description
as initially absent, while the Weekly Review summary remains visible without
an information control; it also checks individual and simultaneous open/close
state, keyboard activation through Enter and Space, dynamic expanded Show/Hide
semantics,
exact 24×24 click/hover/focus/semantics rectangles around 20×20 icons,
non-interactive alignment padding, immediately adjacent miss behavior, hidden
accessibility content, state-token animation, immediate Reduced Motion, and
Dark/Light/Space narrow large-text layout. Separate provider-call assertions
prove that information clicks do not open `Show all tasks` or any supporting
accordion and do not start Recommendations, feedback, or Full-week lazy reads;
ordinary accordion toggles retain that authority.
Full-week projector/source tests cover the containing profile-local
Monday-through-Sunday week, all seven including empty days, inclusive Setup
validity, stable ordering, owner/date/block bounds, exact scheduled-Focus
associations, multiple terminal sessions, missing/invalid reflections, partial
rating failure, sorted 100/100/40 association batches, one global 500-row
association sentinel, rejected cross-batch duplicate sessions, Setup-only
partial truth at the 241st transformed Preparation block without a rating read,
and guest zero-call behavior. Deadline controller tests cover one impact for
initial lifecycle success and exact retry, no preview impact, draft cancellation
without a Snapshot date, and refresh-failure isolation. Quick-Mood widget tests
hold Reflection save/delete writes open, dismiss the sheet before success, and
prove one Full-week invalidation with no late Snackbar; refresh failure remains
isolated. Shared day-card widget tests cover
all four status semantics, non-interactive status boxes, retained row
navigation, category versus neutral completion colors in Dark/Light/Space, and
large-text narrow layout; Planner widget coverage remains the regression gate
for its rolling seven-day behavior.
Feature-local controller tests separately cover every Today Task command port,
Habit outcome targeting, in-flight deduplication, unconfirmed write failures,
durable-write/failed-reload optimism, reload-only recovery, and invalid
non-account projections. A source guard keeps concrete Task/Habit data sources
out of Dashboard presentation. Focused section-widget tests exercise the typed
streak/progress/agenda, Task, Habit, and independent supporting-content boundaries
independently of the page. A source assertion keeps those sections composed
outside `dashboard_page.dart`, bounds the home constructor surface, and rejects
the removed unreachable Task editor and page-local recommendation section.
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
Phase 8 tests cover strict `weekly-review-v2` request/response parsing,
principal-derived ownership, profile-local completed ISO weeks across year/DST
boundaries, read-only latest/period GET, idempotent same-row generation, and
canonical source-fingerprint staleness. Fact tests keep completed/carried tasks,
stable versus changed habit definitions, completed/skipped/missed/recovery-open/
unknown opportunities, focus, recovery days, and feedback distinct. Repository
tests require stable full pagination and exact user/date scoping. Generation
tests prove that `too_much`, `not_helpful`, skips, and high completion still
produce `proposals=[]`; forced refresh clears a historical proposal array.
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
Pydantic and Flutter, require the user's explicit estimate, prove that new UI
proposals use zero prior credit while legacy non-zero values remain readable,
and
prove deterministic timezone-aware blocks, honest unscheduled minutes, staged-
versus-active revisions, the 366-day horizon, separate latest/current revision
semantics, task-free draft cancellation, and exact retry/conflict behavior,
including replay returning a newer current detail projection without repeating
the original mutation. Focused persistence tests must prove that the composite
Deadline write serializes the exact RPC proposal/block shape and that missing
or invalid interval fields fail before repository I/O.
`assignment-series-v1` coverage must prove strict Pydantic/Flutter transport,
bearer-derived ownership, direct Add-new kind locking, default 12, new `2..20`
and future-edit `1..20` bounds, profile-local weekly wall-clock cadence across
DST, and absence of prior-work controls/copy. Service and database tests must
prove independent plan/managed-Task identities, complete typed proposal
preparation before one repository call, one atomic whole-series confirmation,
no individual plan persistence outside that transaction, exact retry/conflict,
future-wide replacement of deviations while retaining past/completed plans,
and atomic future cancellation with no partial lifecycle state.
`preparation-workload-v1` coverage must require exactly
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
320 px/200-percent text. The pure outlook builder must also be exercised
directly, without a repository or service facade, using identical inputs twice.
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
explicit scheduling inputs, exact five-minute slotting, seconds/microseconds
free-start ceiling without busy overlap, and unplaced minutes,
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
The pure overview builder must be tested directly, and typed proposal-write
tests must reject mismatched target identity/kind, skipped revision numbers,
and simultaneous Task/Habit persistence payloads before repository I/O.
Migration tests must cover forced RLS, owner isolation, global request replay,
concurrent confirmation, atomic target-plus-reservation activation,
authoritative commitment conflicts, lifecycle release, restore-without-slot
revival, and unchanged legacy Tasks/Habits. Flutter tests must cover the five
Coach-enabled main navigation targets, the hidden Coach/no-Settings-fallback
gate, Settings through the top-right Today control, Inbox under Settings,
Planner section order, all five create flows, preview/confirm, retained drafts,
guest zero-call, seven-day and preparation projections, availability-readiness
warning plus explicit override, calendar-intent omission from onboarding, and
320 px/200-percent text. Auth coverage must prove that a missing canonical
profile performs one read, makes no repair write, preserves the backend-owned
identity boundary, distinguishes the failure from wrong credentials, and
offers sign-out. Today V2 tests must prove
the three added block kinds, exact `scheduled_today`, one target per progress
denominator, and isolated source failures.

Supabase client/lifespan coverage must prove that normal FastAPI operation
reuses one application-owned HTTP pool across Auth and repository operations,
shutdown closes it exactly once, direct unit-client substitution remains
available, and missing backend configuration stays fail-closed. Route source
must not construct a new settings-derived Supabase transport per request.
Composition coverage additionally proves that shared Deadline/Planner/Today
and Snapshot/Briefing/Scheduled collaborators are identical application-owned
instances, router source constructs no Supabase repository, and API tests
override asynchronous typed dependency callables rather than named
`app.state` service or verifier fields.

Owner-data policy coverage must compare the typed catalog with all 51
repo-owned public tables created by migration history, reject duplicate or
missing entries, and independently prove the exact 43-table
`account-export-v4` Account Export,
five sanitized export sources, eight named anti-replay omissions, and 39-table
Coach Snapshot. Account Export, repository, API, deletion/privilege migration,
Coach Snapshot, and Coach agent tests must continue to prove owner filtering,
field sanitization, bounded failure, cleanup, ledger exclusion, and account
cascade. Coach Snapshot source must not import Account Service implementation
helpers.

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
  43-table export inclusion, ledger omission, and account cascade;
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

- App appearance tests cover all three persisted values, unknown-value Dark
  fallback, slow restore, rapid ordered selection, failed-write rollback, the
  320-pixel/200-percent Settings dialog, three-theme contrast, Space-only
  ripple/glow, clear-material density, HUD depth edges, opaque High Contrast,
  one responsive shell-navigation blur and blur-free cards, responsive local
  portrait/landscape deep-field assets, deterministic stars, active lifecycle
  animation, paused lifecycle, frozen Reduced Motion, and two frozen Space
  reference goldens. The clear-material contrast test uses an all-white source
  bound, which is conservatively brighter than any scrimmed backdrop pixel.
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
- Capture-domain tests cover every bounded stress source and controllability;
  rating, sleep clock/target/interval, date, and text
  boundaries; exact 02:00–10:00 and 23:00–07:00 derivation;
  omission of blank Evening optionals; and explicit inclusion of supplied
  reflection, priority, and blocker. Compatibility tests read V2/V3 friction
  and old `gentle_tomorrow` metadata, ignore/sanitize them, preserve an
  untouched older opposite branch explicitly, accept a complete V4 rollout
  write, require V5 fields when a branch is edited, reject `day_shape` on V5,
  prove a V5 container is never downgraded, convert complete V4 guest branches
  to strict V5 for account migration, and refuse to guess incomplete V2/V3
  sleep fields.
- Same-day merge tests cover Evening-then-Morning and Morning-then-Evening,
  replacing one branch without erasing the other, Morning-over-Evening energy
  precedence, removal of deliberately cleared optionals, preservation of
  foreign top-level metadata, and legacy V1 calendar-date compatibility.
- Capture payload tests assert one merged `daily_logs` row with
  `capture_version=daily-capture-v5`, nested `captures.evening|morning`, direct
  nullable compatibility values, and only explicitly available current
  `behavioral_events`. Raw estimated/planned clocks stay only in Daily Log
  metadata while `sleep_hours` and the Sleep event use the derived duration.
  Event identities remain stable across exact retry and
  event metadata mirrors capture kind/date plus relevant stress and retained
  priority context without friction or Day Shape.
- Guest-store tests cover typed Evening/Morning JSON, both-order same-day merge,
  exact retry deduplication, V1 guest rows with an explicit local date, and
  recovery from corrupted local JSON.
- Evening widget tests cover required explicit selections, exact typed draft
  retention after failure, stable retry identity, prefilled re-entry with blank
  optionals still blank, absence of every friction control and the retired
  gentler control, preservation of Reflection/Priority/Specific Blocker,
  suppression of a duplicate in-flight write, both initially closed sleep-plan
  explanations, independent expansion, and 320-pixel/200-percent-text Reduced
  Motion layout.
- Morning widget tests cover the 50/100-percent two-step flow, invalid and
  incomplete sleep/target gating, final-only save, exact Back retention, saved
  and older compatible prefill, second-step write failure and exact retry,
  absence of the retired interval instruction, all three initially closed and
  independent explanations, and 320-pixel/200-percent-text Reduced Motion
  layout.
- Shared Capture information-control tests prove a 44×44 target and 20-pixel
  icon, closed-tree absence, dynamic Show/Hide semantics and expanded state,
  independent instances, Enter/Space keyboard operation, and immediate Reduced
  Motion transitions.
- Quick actions widget tests cover no saved branch, each single saved branch,
  both saved branches, accessible completed-edit actions, status-free
  loading/error states, and 320-pixel layout at 200% text.
- The guest app smoke completes distinctive required-only Evening Shutdown and
  both pages of Morning Calibration, persists only from the final Morning
  action into one local merged day, reads Morning energy over Evening energy,
  and shows `Completed today` on both matching Quick actions without a duplicate
  saved-signal summary on return.
- Sleep Recommendation service/API tests cover the exact 29/30-day boundary,
  per-day aggregation, the exact closed-open Morning capture boundary, required
  observed Daily Log timestamps, invalid wake/capture/reflection ordering, V4
  compatibility inside a V5 container, rejection of reversed or unmarked V4/V5
  identities, same-day versus following-day wake grouping, midnight/DST clocks,
  invalid-timezone error mapping, typed unstable outcomes, chronological-half
  confirmation, one/fourteen/fifteen-minute outward duration rounding, the
  below-target warning, and consent-driven history non-reading. Flutter contract
  tests reject missing or inconsistent warning evidence, invalid status/reason,
  window, date, and evidence relationships and accept the zero lower rounded
  boundary. Widget tests cover both exact wake-day labels,
  loading/error/disabled/collecting/unstable/ready card states, narrow
  320-pixel/200%-text layout, independent Personal Study Pattern failure behavior,
  and zero guest endpoint calls.
  These checks validate `sleep-recommendation-v1` independently from the
  existing `personal-patterns-v1` contract.
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
- The Flutter feature-boundary source test resolves relative and package
  imports and rejects one feature importing another feature's `data` or
  `presentation` internals. The exact Evening-Capture/Focus-sheet exception
  includes a rationale, must remain observable, and becomes a test failure when
  stale. Composition-provider tests additionally prove local
  Dashboard/Capture/Insights selection after their factories moved to the
  app-level composition directory.
- Shell tests prove that one immutable destination descriptor owns unique
  labels and paths, nested-route selection, responsive icon variants,
  Quick-action emphasis, and Coach capability visibility. Widget coverage
  retains keyboard operation, replacement navigation, large-text compact
  labels, settings-owned unselected routes, and both responsive layouts.
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
  separate weekly facts, historical proposal parsing without rendering or
  execution controls, facts-adjacent update, and guest/mock API isolation.
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
npm run verify:db
```

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Runs Supabase with `HOME=.tools/supabase-home` and
   `SUPABASE_TELEMETRY_DISABLED=1` so the CLI does not need to write to the
   user's real home directory.
3. Starts the local Supabase stack.
4. Redacts Supabase keys and database credentials from CLI output.
5. Requires repository and local migration history to match.
6. Runs the isolated two-migration Goal-removal/locking harness described
   below.
7. Runs the complete final-state pgTAP suite against the normal local database.

With the default `RESET_DB=false` and `APPLY_MIGRATIONS=false`, the script runs
`supabase migration list --local` and requires every repository/DB history row
to match. It never applies pending SQL automatically. A mismatch fails before
pgTAP and explains the two explicit choices.

Migration verification has two deliberately separate layers:

- `services/ai_service/tests/test_*_migration.py` uses
  `tests/migration_source.py` for historical source guards. Those tests protect
  rollout-sensitive file identity such as an exact wrapper, declaration, lock
  order, policy, or grant in the migration where it was introduced.
- `supabase/tests/*.sql` proves the final state after the complete chain is
  applied. Current RLS mode, catalog objects, effective role privileges,
  installed triggers, constraints, and database behavior must be asserted
  there with pgTAP/catalog/role checks rather than inferred from source text.

Neither layer substitutes for the other: historical source identity supports
safe rolling upgrades, while the applied database is authoritative for current
behavior and authority.

The Goal-removal follow-up adds a third, migration-transition layer through
`scripts/lib/goal_removal_migration_harness.sh`. It starts an
ownership-labelled, physically separate Postgres container with a read-only
root, bounded RAM-only data directories, no normal Supabase volume, and a
random loopback-only port. Inside that container it creates only the exact
database `mylifegraph_goal_removal_migration_test`, bootstraps the minimal local
Supabase-owned Auth/extension substrate, and uses `migration up --db-url` to
reach the state immediately before
`20260804150153_remove_goals_and_make_weekly_review_observational.sql`. Filled
fixtures are loaded before the original migration; a current V2 Coach fixture
is loaded between the original and follow-up migrations. A second PostgreSQL
session then holds a real Task writer lock. The first follow-up attempt must hit
its five-second `lock_timeout`, record no migration history, change no fixture,
and leave no helper; after lock release the same migration must pass, followed
by the dedicated pgTAP assertions. An exit trap force-removes only the
ownership-labelled disposable container, including on failure, and normal
migration history is compared around every isolated stage.

This harness intentionally does not invoke `db reset --db-url` or create a
temporary database inside the normal cluster. With Supabase CLI `2.107.0`, a
loopback reset URL can be classified as the normal local stack and recreate the
wrong database. A separate Postgres process/storage boundary plus
version-bounded `migration up --db-url` provides the empty-chain transition
without granting reset authority over the normal local database. Exact
container restrictions, TLS compatibility, gateway scoping, cleanup, and
rollback rules are owned by `docs/local-database-safety.md`.

After reviewing the pending SQL and affected local rows, apply intentionally:

```bash
APPLY_MIGRATIONS=true npm run verify:db
```

The script warns that this may change or delete local rows, runs
`migration up --local`, and verifies history again before continuing. An empty,
unknown, or non-boolean flag value is rejected. Normal verification rejects
`RESET_DB=true` regardless of the migration-apply flag.

## Local Supabase Reset

Normal verification, stack start, and E2E do not have reset authority. Supplying
`RESET_DB=true` to any of them fails before a database command runs.

First create a full backup whenever broad local data work warrants one:

```bash
npm run db:backup:local
```

The backup is published under `.tools/supabase-backups/` only after the complete
custom-format archive restores successfully in a physically separate RAM-only
Postgres container and its Auth-user count, profile count, and latest migration
match the source.

If a reset is explicitly intended, run the non-destructive preview:

```bash
npm run db:reset:local
```

The preview validates the project/container/image/database identity and prints
counts, database size, latest migration, and a token derived from those facts
plus the current WAL position. It does not create a backup or change data. Copy
only the exact execution command printed by that preview. The executing wrapper
requires both `RESET_DB=true` and the fresh `RESET_DB_CONFIRMATION`, creates and
restore-verifies another full backup, and captures the fingerprint again. Any
write during backup makes the token stale and aborts before reset while
retaining the verified archive.

Only an unchanged target reaches the sole supported destructive CLI call:

```text
supabase db reset --local
```

Raw reset, reset with `--db-url`, and reset with `--linked` are forbidden in
repository automation. The wrapper accepts only the exact local project and
requires migration history to match after the CLI succeeds. A successful reset
applies every migration through the current repository boundary named in
`docs/supabase-current-state.md`.

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
such local data before retrying. A fresh chain also installs exact task lifecycle,
locked active/weekday habit eligibility, bounded focus lifecycle, locked target
validation, one-active, all-update terminal immutability, and restrict-delete
target constraints/triggers. Existing local stacks may apply reviewed pending
migrations explicitly with:

```bash
APPLY_MIGRATIONS=true npm run verify:db
```

This is not a non-destructive claim: migration SQL may change or delete local
rows even when it does not reset the entire database.

Use the guarded reset only when destruction of the exact normal local database
is intended; do not use it merely because a reviewed migration is pending.
Backup retention, incident recovery, external approval hygiene, and coherent
source rollback are specified in `docs/local-database-safety.md`. Nothing in
this workflow grants remote or linked reset authority.

## Browser E2E

Browser E2E is implemented with Playwright:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter npm run e2e:web:smoke
FLUTTER_BIN=/path/to/flutter npm run e2e:web:full
```

The smoke runs these four representative, tagged wiring specs with one
Playwright worker:

- `@setup-onboarding`;
- `@auth-capture-today`;
- `@planner-confirm`;
- `@coach`.

Each spec receives a separately created account and an exact `finally`
cleanup. `e2e:web:full` runs all eight independent journeys and adds
`@exam-week-outlook`, `@notification-lifecycle`, `@account-controls`, and
`@personal-learning`. Every retained browser assertion crosses the Flutter UI
boundary and checks a user-visible result. The Exam-Week and Notification
journeys also retain the bounded persistence/replay/owner assertions needed to
prove that the visible control operated on the intended durable contract.
Exhaustive HTTP validation, owner derivation, RLS, privilege, cascade, and
database-constraint matrices remain in pytest and pgTAP, where they are faster
and more precisely isolated.

`e2e/web/journey-manifest.mjs` is the canonical registry for the eight full and
four smoke journeys. Playwright selection, named-journey shell validation, the
split-contract guard, and its fixture test consume that registry instead of
maintaining separate regex/list copies. Adding or retiring a journey therefore
requires one manifest edit plus the corresponding spec and documentation; the
guard still rejects missing/unregistered specs, a returned monolith, or a
journey without real Flutter authentication and a visible assertion.

This is the normal non-reset database path: the script starts or reuses the
repository's local Supabase stack, has no `supabase db reset` branch, inspects
`supabase migration list --local`, and fails when repository and database
history differ. It never applies pending SQL automatically. The suites write
only run-unique local Auth users and their test rows. `RESET_DB=true` is rejected
before a database command runs.
Run ids may contain the documented uppercase safe characters. Supabase
normalizes Auth email addresses to lowercase, so persisted-email assertions use
that canonical value rather than the unnormalized input token.

One journey can be run narrowly for diagnosis with a fresh unique run id:

```bash
E2E_JOURNEY=coach \
E2E_RUN_ID=<new-unique-e2e-run-id> \
FLUTTER_BIN=/path/to/flutter \
bash scripts/e2e_web.sh
```

`E2E_JOURNEY` accepts any name registered in
`e2e/web/journey-manifest.mjs` (the matching spec filename without
`.spec.mjs`). Every invocation must use a fresh run id. Reusing one fails closed
when its run-specific artifact directory already exists, even though successful
cleanup removed the Auth principal. A focused path never substitutes for the
full command.

If the browser suite genuinely needs a fresh normal local database, stop and
complete the separate guarded reset workflow first. Then run the ordinary E2E
command without `RESET_DB=true`; destructive database setup is never combined
with the browser runner.

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
test process. The current `@personal-learning` journey enables the separate
Settings permissions and renders the transparent empty 90-day evidence state.
Focus reflection, mature learned-window ordering, and Setup-fallback behavior
remain covered by focused Flutter, pytest, and pgTAP tests rather than being
claimed by that browser journey. The test-only flag does not change normal or
production defaults.

Use real Ubuntu-installed Node.js, npm, Supabase CLI, and Docker. If these tools
are installed through nvm, non-interactive agent shells may need an explicit
`PATH` or `NODE_BIN` override even when `node --version` works in the user's
interactive shell. Do not install replacement tool binaries into `.tools/`.

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Starts the local Supabase stack, rejects reset authority, and requires
   matching migration history before starting application processes.
3. Reads `API_URL`, `ANON_KEY`, and `SERVICE_ROLE_KEY` from
   `supabase status -o env` without printing key values.
4. Starts the FastAPI AI service on `127.0.0.1:8000` by default with backend
   local Supabase settings, a run-scoped scheduled-refresh token, and
   `COACH_PROVIDER=fake` plus `COACH_FAKE_PROVIDER_ENABLED=true`. Standard E2E
   never contacts a live Codex account.
5. Starts Flutter Web on `127.0.0.1:7357` with `USE_MOCK_DATA=false` and
   `AI_SERVICE_BASE_URL` pointing at the local FastAPI service.
6. Passes the same token only to the Playwright fixture. The runner loads
   `e2e/web/journeys/*.spec.mjs` through
   `e2e/web/fixtures/e2e.fixture.mjs`. The token is never passed to Flutter.

In the default profile mode, the script waits synchronously for
`flutter build web --profile` to finish, starts a static server for that
completed bundle, and then polls `/` with process-liveness checks. In diagnostic
debug mode it starts `flutter run -d web-server` and uses the same bounded HTTP
and liveness loop. Browser-side shell and Semantics helpers then wait for the
actual Flutter DOM before interacting; readiness is not inferred from a stale
log line.

The E2E Flutter process also passes `--dart-define=E2E_ENABLE_SEMANTICS=true`.
`apps/mobile/lib/main.dart` uses that test-only flag to keep Flutter Semantics
enabled, which gives Playwright stable text fields, buttons, and labels instead
of relying on canvas pixels. The standard runner builds a profile-mode web app
and serves its completed static bundle so serial independent browser contexts
do not depend on a debug DWDS connection while development-only feature gates
remain testable. `FLUTTER_WEB_MODE=debug` and `release` remain diagnostic
overrides. The
standard runner also sets
`E2E_SEMANTICS_PRE_ENABLED=true`: after each Flutter shell it waits at most one
second for a real `flt-semantics` node and never waits for or clicks the
placeholder. The placeholder/accessibility-button fallback remains only for
deliberately reused, manually started builds with
`E2E_SEMANTICS_PRE_ENABLED=false`.

All Auth UUIDs created during a run are registered immediately. The runner's
`finally` block deletes only those exact users through the local Admin API,
after the exact focus-history prerequisite, and reads them back as absent.
This is rejected for every non-loopback or credential-bearing Supabase URL.
Normal cleanup never resets the database and never discovers users by email
prefix. If a passing journey cannot clean up, the run fails; if the journey
already failed, its original error remains primary and the cleanup error is
reported additionally.

Historical E2E accounts are intentionally outside that registry. The separate
command below is preview-only by default and prints a fingerprint bound to the
current exact UUID/email selection:

```bash
npm run e2e:cleanup:local
```

Only an explicit rerun with `--confirm <printed-fingerprint>` deletes that
still-current selection, and the command also rejects non-loopback Supabase.

The current browser layer deliberately stays at the user-visible integration
boundary. Its eight independent journeys prove:

- incomplete-account sign-in, required Setup submission, persisted Intake
  projection, and navigation to Today;
- authenticated Evening persistence followed by the exact saved check-in state
  in Today, including an initially absent agenda explanation that becomes
  visible only through its accessible information button whose closed and open
  Semantics DOM rectangles are exactly 24×24;
- Planner proposal/confirmation followed by the exact plan title in Flutter;
- V4 Evening/Morning sleep facts plus confirmed Exam and competing Assignment
  state followed by a Planner-only Exam-Week card and non-mutating replan entry;
- stored Inbox mark-read, mark-unread, and dismiss controls, including exact
  replay, request-id conflict, direct-write denial, owner isolation, durable
  tombstone, and disappearance after Flutter reload;
- fake-provider Coach persistence followed by the exact message in Coach
  history;
- Settings-driven account export, byte-identical browser download, confirmed
  deletion, sign-out, and user-visible completion; and
- enabled Personal Learning preferences followed by a seeded 90-day Personal
  Pattern and ready Sleep Recommendation in Insights.

The former all-in-one browser source also mixed UI wiring with lower-level
contract assertions. Those assertions were retained at their narrowest useful
test boundary before the monolith was removed:

| Concern previously mixed into browser E2E | Current authoritative evidence |
| --- | --- |
| Setup validation, retry identity, revisions, ownership, and atomic apply | `test_intake_api.py`, `test_intake_service.py`, `test_intake_repository.py`, `setup_controller_test.dart`, plus the `@setup-onboarding` UI journey |
| Daily Capture V5 validation/V4 rollout compatibility, branch merge, retry reconciliation, `explainable-daily-state-v3`, and Today mapping | `test_daily_capture_api.py`, `test_snapshot_daily_state.py`, `quick_check_in_data_source_test.dart`, capture page/widget tests, `stabilization_write_authority_test.sql`, plus `@auth-capture-today` |
| Task, Habit, and Focus lifecycle constraints | `test_executable_actions.py`, executable-action Flutter tests, and migration contract tests |
| Briefing, recommendation, and weekly-review determinism/replay | `test_briefing_service.py`, `test_weekly_review_service.py`, their API/repository tests, and corresponding Flutter widget/controller tests |
| Calendar parsing, reconciliation, consent, identity, and isolation | `test_calendar_ical_parser.py`, Calendar API/service/repository/migration tests, and Calendar Flutter page/repository tests |
| Notification lifecycle, delivery policy, conflicts, and Inbox behavior | Notification API/service/repository/migration tests, `notifications_page_test.dart`/`notification_delivery_test.dart`, plus `@notification-lifecycle` for the visible stored-Inbox lifecycle |
| Deadline and central Planner calculations, writes, conflicts, and rendering | Deadline/Planner model, service, repository, API, migration, and Flutter page tests, plus `@planner-confirm` and the read-only `@exam-week-outlook` integration |
| Coach safety, budget, evidence, persistence, and read-only authority | Coach API/service/repository/evidence/migration tests, Coach Flutter tests, plus `@coach` |
| Personal Learning evidence, independent Sleep Recommendation, preferences, clearing, learned timing, and RLS | Personal-pattern/learning/sleep-recommendation API/service/repository tests, `personal_learning_v1_test.sql`, Flutter Learning/Insights tests, plus `@personal-learning` |
| Account export/deletion contracts and authority | Account API/service/repository/migration tests and Settings widget/repository tests, plus `@account-controls` |
| Global owner isolation, role authority, direct-DML denial, and protected-route authentication | `test_auth.py`, owner-derived API tests, privilege/RLS migration tests, and `supabase/tests/profile_authority_test.sql`; `@notification-lifecycle` additionally proves the owner boundary for its visible row actions |

The source guard `scripts/check_e2e_split_contract.mjs` fails if the retired
monolith or transitional commands return, if an expected journey disappears,
or if a journey no longer authenticates through Flutter and makes a
user-visible assertion. Authentication/assertion markers in comments or string
literals do not satisfy the guard. The Flutter helper navigates through root hash URLs
such as `/#/auth` and `/#/planner`, avoiding unsupported development-server
deep-link rewrites.

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
SS_BIN=/path/to/ss
FLUTTER_WEB_MODE=profile
STATIC_SERVER_PYTHON=python3
SCHEDULED_REFRESH_TOKEN=local-e2e-override
E2E_RUN_ID=manual-001
E2E_SEMANTICS_PRE_ENABLED=true
E2E_SUITE=smoke
E2E_JOURNEY=coach
```

By default, `scripts/e2e_web.sh` starts FastAPI from the current checkout and
does not reuse an arbitrary service that is already listening on the same port.
Immediately before starting FastAPI and immediately before starting the Flutter
web server it runs fail-closed `ss -H -ltn "sport = :<port>"` checks. A missing,
non-executable, failed, or non-empty check aborts instead of selecting another
port. `SS_BIN` exists for hermetic runner tests and defaults to `ss`.
`AI_SERVICE_START=false` skips only the FastAPI ownership check and startup; it
is the sole explicit reuse path, and Flutter still requires a free port. Use it
only when intentionally reusing a compatible FastAPI process with the same
local Supabase settings and scheduled-refresh token.

Owned-process readiness checks the child PID before and after the successful
HTTP response and again after a short stability interval. A delayed bind failure
therefore cannot become ready merely because another process answers the URL.
`scripts/test_e2e_web_process_ownership.sh`, run by `verify:fast`, covers both
occupied ports, a failed `ss` invocation, delayed child death with a foreign
HTTP answer, and the explicit FastAPI reuse exception.

Flutter Web logs for the E2E run are written to:

```text
.tools/e2e/runs/<run-id>/flutter-web.log
```

FastAPI logs for the E2E run are written to:

```text
.tools/e2e/runs/<run-id>/ai-service.log
```

On a split-spec failure, Playwright retains both artifacts below that spec's
run-specific output directory:

```text
.tools/e2e/runs/<run-id>/playwright/<spec-output>/trace.zip
.tools/e2e/runs/<run-id>/playwright/<spec-output>/test-failed-1.png
```

The runner prints machine-readable `[e2e:timing]` JSON for Supabase, FastAPI,
Flutter, Semantics, journeys, exact-user cleanup, the Playwright runner,
and process cleanup. The split reporter additionally emits one
`[e2e:test-timing]` JSON record per spec. `.tools/` is ignored by git.

## Phase 10 Provider Verification

The current pair under verification is `free-coach-agent-prompt-v3` with
`personal-snapshot-v2`; stored V1/V2 prompt responses and exact replay remain
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
fresh-chain proof is a separate guarded local reset followed by ordinary
verification, never an E2E flag. The full journey
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
fingerprint freshness, retirement of the generic Today candidate and legacy
focus banner delivery,
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

## Continuous Integration Gates

`.github/workflows/ci.yml` runs documentation/visual contracts, clean Flutter
analysis plus the complete Flutter suite, Android JVM tests plus `lintDebug`,
and the complete FastAPI pytest suite on every pull request. Path
classification adds a debug web build for Flutter changes and a fresh ephemeral
local migration chain plus pgTAP for Supabase, migration, or database-test
changes. Full browser E2E runs nightly, on manual dispatch, and for Auth,
routing, schema, core/configuration, unknown, or cross-stack pull-request
changes. No local Git hook is required or installed.

Fresh GitHub runners obtain an empty local stack through `supabase start`; the
database and E2E jobs do not set `RESET_DB=true` and cannot call the guarded
reset execution path. They then use the same matching-history verification and
physically isolated transition harness as local development. CI freshness is a
property of the ephemeral runner, not permission to add reset authority back to
`verify:db` or E2E.

The same conservative rules are available locally through
`npm run verify:affected -- --base-ref <ref>`. CI failure artifacts are retained
from the run-specific E2E directory. A local workflow run is evidence for the
checkout only; a hosted PR job must itself succeed before it is reported as a
successful PR gate.

Still missing for broader product verification:

- Hosted PR evidence for the new conditional jobs; the workflow is defined,
  but a local run cannot establish that GitHub-hosted gates passed.
- Deployed scheduler/cron wiring and monitoring; the repository verifies the
  protected preparation endpoint, not any production invocation platform.
- Android/system notification delivery is not part of Notification Delivery V1
  and remains absent; physical-device foreground acceptance is still useful.
- Installed-device Google OAuth/recovery acceptance, a complete physical-device
  layout/accessibility pass, and best-effort authenticated guest check-in
  migration. Widget tests cover the critical 320 px/text-scale surfaces, but
  do not replace device acceptance. Guest Setup intentionally has no automatic
  account migration.

When changing E2E flows, keep `e2e/web/playwright.config.mjs`, the fixtures and
tagged specs below `e2e/web/`, `scripts/check_e2e_split_contract.mjs`,
`scripts/e2e_web.sh`, and this document in sync.
