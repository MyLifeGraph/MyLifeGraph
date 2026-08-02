# Refactoring Execution Handoff

Status: TEMPORARY EXECUTION LEDGER

## Baseline

- Branch: `new_backend_gh`
- Review commit: `e5ff1fbc125b8094359bd8d1c6541151c11154e3`
- Baseline verification: `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter npm run verify:fast` passed on 2026-08-02 with clean Flutter analysis, 827 passing Flutter tests, and 1,166 passing FastAPI tests with two expected skips. Documentation, visual, source, Ruff, compile, and diff checks also passed.

This file is the only execution ledger for the behavior-preserving refactoring
sequence below. It is intentionally temporary and must not be linked from
`AGENTS.md` or another permanent routing document.

## Execution Protocol

Each tranche has exactly one state: `pending`, `in_progress`, `blocked`, or
`completed`.

1. A new chat implements exactly the first tranche whose state is `pending`, or
   continues the first `in_progress` or `blocked` tranche. It must not advance a
   later tranche or broaden the tranche while earlier work is open.
2. Before editing, read `AGENTS.md`, this file, and every feature contract or
   runbook required by either document for the tranche. Inspect the branch,
   HEAD, full working-tree and staged diffs, and untracked files.
3. Change the tranche to `in_progress` when implementation begins. Keep all
   public API, persisted wire-format, owner/RLS, grant, retry, lock-order,
   pagination-bound, and UI behavior described below unchanged.
4. Add or strengthen focused regression tests, run the tranche-specific checks,
   then run `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter npm run verify:fast`
   and `git diff --check`.
5. Only after all required checks pass, set the tranche to `completed`, record
   the exact result in its result field, and commit implementation, tests,
   required contract documentation, and this ledger update together using the
   prescribed subject.
6. A blocker leaves this file and the incomplete tranche in place. Record the
   evidence, set `blocked` only for a genuine impasse, and do not delete the
   ledger.
7. Existing unrelated working-tree changes belong to their author. Do not
   overwrite, discard, stage, or include them in a tranche commit.
8. Do not push, deploy, open a pull request, rewrite historical migrations,
   upgrade dependencies/SDKs, or remove legacy Coach endpoints as part of this
   sequence.

## Mandatory Deletion Contract

> Dieses Dokument ist temporär. Sobald alle Pflichttranchen als `completed` verifiziert und committed sind, muss derselbe Agent ohne zusätzlichen Nutzer-Prompt die vollständige Abschlussverifikation ausführen, dieses Dokument löschen, die Dokumentprüfung erneut ausführen und die Löschung separat committen. Solange eine Tranche offen, blockiert oder nicht verifiziert ist, darf die Datei nicht gelöscht werden.

After Tranche 10 is committed with every tranche marked `completed`, the same
chat must run this exact closeout sequence:

1. Run `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh`.
2. Delete this file.
3. Run `npm run verify:docs`,
   `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter npm run verify:fast`, and
   `git diff --check`.
4. Only when all checks are green, commit the deletion separately with
   `chore: remove completed refactoring handoff`.

## Tranche 1: Centralize Bounded Backend Repository Pagination

- State: `completed`
- Depends on: baseline ledger commit only.
- Goal: Extract a shared, bounded repository pagination primitive and use it for
  the existing semantically equivalent FastAPI repository page loops.
- Non-goals: Do not introduce a public cursor contract; do not convert every
  offset query to keyset pagination; do not alter Account Export or Coach
  Snapshot owner-data collection (Tranche 2); do not alter Calendar event
  cursors, scheduled-profile scan policy, Coach evidence caps, or service-level
  Today streak semantics.
- Affected subsystems: shared FastAPI repository infrastructure; Snapshot and
  Weekly Review stable keyset reads; Deadline Planner, Planner, and Today
  bounded offset reads; only other repository loops that already have the same
  ordering, page, and termination contract.
- Acceptance criteria:
  - one neutral helper owns page advancement, final-page detection, and maximum
    row enforcement for the migrated loops;
  - every caller retains its exact select/filter parameters, stable ordering,
    page size, maximum rows, returned row order, and exception type/message;
  - keyset callers keep their existing compound cursor filters and offset
    callers keep offsets; no endpoint payload or database contract changes;
  - focused tests cover empty, short, exact-page, multi-page, maximum-bound,
    malformed/overfull page, and transport-error behavior as applicable.
- Focused tests: `tests/test_repository_pagination.py`,
  `tests/test_snapshot_aggregator.py`,
  `tests/test_weekly_review_repository.py`,
  `tests/test_deadline_plan_repository.py`, `tests/test_planner_repository.py`,
  and Today repository/service tests affected by the extracted helper.
- Commit subject: `refactor: centralize bounded repository pagination`
- Result: _Completed on 2026-08-02. Snapshot and Weekly Review retain their
  compound keyset reads; Deadline Planner, Planner, and Today retain their
  bounded offset reads and feature-specific overfull errors through one shared
  collector. The focused Ruff and 63-test repository suite passed. `npm run
  verify:docs`, `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter npm run
  verify:fast`, and `git diff --check` passed; the full gate included clean
  Flutter analysis/tests and the FastAPI suite with its two expected skips._

## Tranche 2: Share Owner Data Collection

- State: `completed`
- Depends on: Tranche 1 completed.
- Goal: Move Account Export and Coach Snapshot onto one neutral owner-data
  reader that captures source watermarks, loads bounded table pages with limited
  concurrency, and assembles output deterministically.
- Non-goals: Do not change the typed owner-data catalog, the exact 41-table
  Account Export or 37-table Coach Snapshot policies, field allowlists,
  exclusions, snapshot schema, export envelope, or introduce a transaction-wide
  point-in-time claim.
- Affected subsystems: `owner_data_catalog`, account repository/service,
  Coach snapshot builder, Supabase REST reads, export and snapshot limits.
- Acceptance criteria:
  - both consumers call one feature-neutral collector and neither imports the
    other's service implementation;
  - per-source watermarks are captured before row collection, source reads are
    bounded in parallel, and final tables follow catalog order regardless of
    completion order;
  - owner predicates, keyset cursor validation, 1,000-row pages, 10,000 rows per
    table, 50,000 total rows, 8 MiB, sanitization, and existing error semantics
    remain exact;
  - cancellation and a failed source cancel/settle sibling work without partial
    success escaping.
- Focused tests: `tests/test_account_repository.py`,
  `tests/test_account_service.py`, `tests/test_account_export_stream_bound.py`,
  `tests/test_coach_snapshot.py`, and `tests/test_owner_data_catalog.py`.
- Commit subject: `refactor: share owner data collection`
- Result: _Completed on 2026-08-02. Account Export and Coach Snapshot now use
  one neutral reader that captures every source watermark before bounded
  parallel row collection and preserves catalog order, exact limits,
  sanitization, and feature-specific errors. Failed and cancelled reads settle
  sibling work. The focused Ruff/format and 59-test suite, `npm run
  verify:docs`, `FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter npm run
  verify:fast`, and `git diff --check` passed; the full gate included clean
  Flutter analysis/tests and the complete backend suite with two expected
  skips._

## Tranche 3: Reuse Today And Planner Read Context

- State: `pending`
- Depends on: Tranche 2 completed.
- Goal: Introduce one request-local read context for Today/Planner shared source
  facts, remove duplicate profile, Habit, and Deadline loads, and run independent
  reads with bounded concurrency.
- Non-goals: Do not add cross-request caching; do not merge Today V1/V2 wire
  formats; do not change projection arithmetic, source isolation, mutation
  authority, or normal GET side-effect freedom.
- Affected subsystems: Today V1/V2 services and repository adapters, Planner
  overview service/builder, shared Deadline workload/availability inputs,
  application composition.
- Acceptance criteria:
  - duplicate profile/Habit/Deadline queries within one request are eliminated
    and observable in focused call-count tests;
  - independent loads are concurrency-limited and deterministic assembly order
    is unchanged;
  - Today V1 and V2 responses remain byte-compatible for the same inputs;
  - each existing Today source failure remains isolated to the same source and
    Planner errors retain the same public mapping.
- Focused tests: `tests/test_today_overview_service.py`,
  `tests/test_today_overview_api.py`, `tests/test_planner_service.py`,
  `tests/test_planner_api.py`, `tests/test_app_lifespan.py`, and application
  composition identity tests.
- Commit subject: `perf: reuse today and planner read context`
- Result: _Not started._

## Tranche 4: Extract Focus Session Lifecycle Controller

- State: `pending`
- Depends on: Tranche 3 completed.
- Goal: Move the Focus session lifecycle from the Flutter page into an explicit
  `FocusSessionController` or equivalent state machine and isolate Android
  Focus Protection reconciliation behind a narrow adapter.
- Non-goals: No visual redesign, copy change, route change, timing-rule change,
  backend schema/API change, or new Android protection authority.
- Affected subsystems: Flutter Focus application/presentation state, Focus
  repository ports, reflection/recovery handoff, Android protection channel and
  reconciliation.
- Acceptance criteria:
  - start, restore, tick, finish, abandon, retry, result-unknown reconciliation,
    reflection, recovery, protection lease, and emergency release have explicit
    testable states/transitions outside the page;
  - page code owns widgets/dialogs/navigation only and delegates lifecycle work;
  - one-active-session, persisted start-date, planned-source V2 fallback rules,
    Retry, Back/navigation, and emergency behavior remain functionally exact;
  - Android protection failure never changes canonical synced Focus state.
- Focused tests: Focus controller/data-source/widget/reflection tests, Android
  Focus Protection Flutter tests, Android JVM lease/policy tests, Flutter
  analysis, and the relevant Android source guards.
- Commit subject: `refactor: extract focus session lifecycle controller`
- Result: _Not started._

## Tranche 5: Centralize Strict Flutter Contract Primitives

- State: `pending`
- Depends on: Tranche 4 completed.
- Goal: Provide shared strict Flutter JSON primitives for exact keys, UUIDs,
  timestamps/dates, lists, maps, scalar types, and numeric/string bounds, then
  migrate compatible model parsers.
- Non-goals: Do not centralize domain cross-field invariants, erase
  feature-specific exception types/messages, loosen explicit-null/coercion
  rejection, or split files solely because of complexity metrics.
- Affected subsystems: Flutter core contract parsing and the Intake, Deadline,
  Planner, Today, Weekly Review, Calendar, Notification, Coach, Learning, and
  Account domain/data parsers that duplicate identical primitives.
- Acceptance criteria:
  - shared helpers are framework-neutral and preserve exact rejection behavior;
  - domain-specific relationships stay beside their aggregate models;
  - large domain files are split only at existing aggregate boundaries and
    retain feature-private ownership;
  - parser regression tests cover unknown keys, missing keys, explicit null,
    booleans-as-numbers, invalid UUID/time/date, nested collection shapes, and
    every migrated bound.
- Focused tests: strict contract/model tests for every migrated feature plus a
  dedicated core parser test and `flutter analyze`.
- Commit subject: `refactor: centralize strict Flutter contract parsing`
- Result: _Not started._

## Tranche 6: Share Coach Turn Lifecycle Primitives

- State: `pending`
- Depends on: Tranche 5 completed.
- Goal: Move shared Coach claim/error state and eligibility, replay, completion,
  failure, and history helpers into a neutral internal module used by both
  legacy fixed-mode and current free-agent orchestration.
- Non-goals: Do not remove V1/V2 endpoints/history, merge provider adapters,
  change prompt/context provenance, change request/usage persistence, reorder
  owner/request locks, or add model/tool authority.
- Affected subsystems: Coach service and agent service, repository result
  mapping, lifecycle models, history deletion, application composition.
- Acceptance criteria:
  - duplicated lifecycle decisions have one neutral implementation while legacy
    context assembly and V3 snapshot/agent orchestration remain separate;
  - provider-called truth, exact replay, one pending turn, profile-local daily
    budget, terminal tombstones, and atomic usage/message behavior are exact;
  - V1–V3 persisted contract and public response fixtures are unchanged;
  - tests exercise both orchestrators against identical lifecycle scenarios.
- Focused tests: `tests/test_coach_service.py`,
  `tests/test_coach_agent_service.py`, `tests/test_coach_repository.py`,
  `tests/test_coach_agent_repository.py`, Coach API/model tests, and lock-order
  migration source guards.
- Commit subject: `refactor: share coach turn lifecycle primitives`
- Result: _Not started._

## Tranche 7: Centralize API Problem Translation

- State: `pending`
- Depends on: Tranche 6 completed.
- Goal: Introduce typed, feature-near HTTP problem translators and remove
  repeated FastAPI route exception boilerplate.
- Non-goals: No global catch-all exception handler, repository exception leakage,
  status/detail normalization, new error envelope, or authentication/security
  boundary change.
- Affected subsystems: FastAPI route modules and feature service error types.
- Acceptance criteria:
  - each migrated feature owns an exhaustive typed error-to-HTTP mapping close
    to its API boundary;
  - existing status codes, public `detail` strings/objects, headers, and
    unexpected-error behavior remain exact;
  - repository exceptions still cannot cross into `app/api`;
  - focused route tests compare the pre-existing public problem matrix.
- Focused tests: all migrated `test_*_api.py` modules, auth/dependency tests,
  route source-boundary tests, and the complete FastAPI suite.
- Commit subject: `refactor: centralize API problem translation`
- Result: _Not started._

## Tranche 8: Layer Migration Verification

- State: `pending`
- Depends on: Tranche 7 completed.
- Goal: Centralize repeated SQL-source inspection helpers and clearly separate
  historical migration source guards from final-state database behavior checks.
- Non-goals: Do not edit historical migration SQL, reduce any grant/RLS/RPC/lock
  assertion, or replace executable final-state evidence with source-text checks.
- Affected subsystems: FastAPI migration tests, shared SQL test utilities,
  pgTAP/catalog/role verification, database verification documentation.
- Acceptance criteria:
  - one test utility owns migration loading and function/policy/grant extraction;
  - source guards state why historical text identity matters and final-state
    behavior tests prefer pgTAP or catalog/role assertions;
  - the complete existing migration test matrix remains represented;
  - no migration file changes and local migration history remains matching.
- Focused tests: all `tests/test_*_migration.py`, shared helper tests,
  `npm run verify:db`, `supabase migration list --local`, and relevant pgTAP
  files.
- Commit subject: `test: strengthen final-state database contract checks`
- Result: _Not started._

## Tranche 9: Split Large Flutter Presentation Components

- State: `pending`
- Depends on: Tranche 8 completed.
- Goal: Move already independent Insights and Deadline Planner presentation
  components into feature-private widget files; touch Onboarding only if a real
  independent component boundary exists.
- Non-goals: No redesign, copy, state, provider, navigation, semantics, or
  responsive behavior change; no cross-feature presentation imports.
- Affected subsystems: Insights and Deadline Planner Flutter presentation,
  optionally one independently proven Setup component.
- Acceptance criteria:
  - page files retain orchestration and extracted widgets remain feature-private
    and provider/write-free;
  - constructor surfaces stay cohesive rather than forwarding every leaf field;
  - existing visuals, focus/order, navigation, state retention, 320 px/200%
    text behavior, and accessibility semantics remain exact;
  - feature-boundary and visual source guards pass without new exceptions.
- Focused tests: Insights page/load-state tests, Deadline Planner page/widget
  tests, optional Setup widget tests only if touched, visual/feature-boundary
  source tests, and `flutter analyze`.
- Commit subject: `refactor: split large Flutter presentation components`
- Result: _Not started._

## Tranche 10: Centralize Current-State Metadata

- State: `pending`
- Depends on: Tranche 9 completed.
- Goal: Add `docs/current-contracts.json` as the machine-readable source for
  current contract versions and owning documents, update the docs checker to
  consume it, and reduce duplicated volatile current-state metadata.
- Non-goals: Do not weaken documentation ownership checks, remove historical
  evidence, change a product contract, add a permanent link to this ledger, or
  make `AGENTS.md` depend on machine-local configuration.
- Affected subsystems: documentation metadata, docs consistency checker/tests,
  `AGENTS.md`, `docs/supabase-current-state.md`, and known stale comments/small
  duplicate current-state passages.
- Acceptance criteria:
  - `docs/current-contracts.json` has a validated deterministic schema and names
    every current contract version plus its owning documents;
  - the docs checker derives version ownership from the JSON and requires the
    newest migration filename only in `docs/supabase-current-state.md`;
  - `AGENTS.md` retains stable safety/routing rules while volatile inventories
    are removed or routed to the metadata/current-state docs;
  - known stale comments and small duplicate passages are corrected without
    changing product behavior;
  - all ten tranche states, including this one, are `completed` in the commit,
    after which the Mandatory Deletion Contract is executed.
- Focused tests: `node --test scripts/check_docs_consistency.test.mjs`,
  `node scripts/check_docs_consistency.mjs`, `npm run verify:docs`, JSON parse/
  schema tests, link/anchor checks, and changed-doc ownership checks.
- Commit subject: `docs: centralize current contract metadata`
- Result: _Not started._

## Sequence-Wide Non-Goals And Invariants

- All tranches are behavior-preserving refactorings. Public APIs, database
  schema, persisted wire formats, and student-facing semantics remain unchanged.
- Historical migrations are immutable. Supabase RLS, explicit grants,
  service-role-only RPCs, advisory lock order, and retry ledgers are security
  boundaries, not cleanup opportunities.
- Flutter/Dart SDK and dependency upgrades are a separate compatibility project.
- Complexity values alone do not justify splitting a central validator or
  parser.
- Every tranche is one reviewable commit; the initial ledger and final ledger
  deletion are separate documentation commits.
