# Local Product Completion Handoff

Status: execution handoff for finishing the complete product locally in WSL
before packaging a standalone Android production release. Internal contract
names such as `intake-v1`, `habit-v1`, or `coach-response-v1` are versioned API
and persistence contracts; they do not mean a demo, cheap edition, or reduced
quality target.

## Objective

Produce one locally complete, reproducible MyLifeGraph release-candidate
checkout in which every visible surface is either fully functional for its
declared scope or deliberately absent. The real local Coach must use the current
WSL user's authenticated Codex CLI. The deterministic product loop remains the
source of truth, and no personalized-looking fake output may replace a real
failure.

Android packaging comes after this local completion gate. The later Android
production architecture will replace the development-only local Codex transport
with a deployable server-side LLM provider; no model credential belongs in the
Flutter application.

## Current Checkout Truth

Updated on 2026-07-14:

- Repository: `/home/gregor/projects/ai-personal-coach`
- Branch: `new_backend_gh`, thirteen commits ahead of its recorded remote
  tracking branch at the start of the Notification slice.
- Current checkpoint HEAD: `f6e7b2b` (`feat: complete account controls and app
  hardening`). The working tree was clean before Notification Delivery V1 work.
- The checkpoint contains account timezone/export/deletion, password recovery,
  durable settings/theme, Skillset and offline truth, local stack/migration
  hardening, Android auth/signing guards, layout/accessibility coverage, and the
  controlled local Coach.
- Recorded checkpoint results: 684 Backend tests green with one opt-in skip,
  510 Flutter tests green, clean Flutter analysis, clean local Supabase
  migration verification, and a passing live `local_codex_oauth` Coach smoke
  with explicit `gpt-5.5` and no fallback.
- `20260714110000_account_export_lifestyle_entries_grant.sql` is applied to the
  local database. Android APK packaging remains environmentally blocked because
  WSL has no Android SDK/`ANDROID_HOME`; this is not a proved code defect.
- The current uncommitted slice adds Notification Delivery V1 and explicit
  Weekly Review action-authority copy. A subsequent review added the
  `20260714143000_notification_delivery_settings_guard.sql` follow-up plus
  recovery, weekly-freshness, polling, and conflict-state fixes. The current
  review tree has 721 Backend tests green with one opt-in skip, 524 Flutter tests
  green, clean Flutter analysis, and a passing `scripts/verify.sh`. After
  explicit permission,
  `20260714130000_notification_delivery_v1.sql` and the reviewed
  `20260714143000_notification_delivery_settings_guard.sql` follow-up were
  applied to the local stack without a reset; local history matches the
  repository. A rollback-only database guard smoke passed. The full non-reset
  browser journey passed on 2026-07-14 and reported
  `E2E browser smoke passed for e2e-1784046486@example.test`.
- The browser run exposed and fixed
  stale Inbox state after a foreground receipt; the Shell now reloads the
  stored Inbox when it emits a new banner. Review source, local migration, guard,
  and browser verification are now recorded above.
- No remote Supabase, deployment, Play Console, or production signing state has
  been inspected or changed.

The local full-product Coach path has already passed once on this machine:

```text
authenticated Flutter Web
  -> FastAPI Controlled Coach
  -> local_codex_oauth
  -> same Linux user's logged-in Codex CLI
  -> strict validated response and persistence
  -> visible Flutter answer/provenance
```

That run used an explicitly requested `gpt-5.5` with no fallback and logged no
question, assembled prompt, answer, raw CLI event, account identity, path,
token, `.env` value, or Supabase key. It proves this machine's local path, not a
deployable provider or another account. Re-run it on the final checkpoint before
calling the local Coach complete.

## Checkpoint And Overnight Boundary

An initial checkpoint commit is useful but is not a gate for safe unattended
work. Inspect and verify the complete current delta before changing it. If the
user later explicitly authorizes a local checkpoint commit, the intended message
is:

```text
feat: complete notification delivery and weekly review UX
```

Before that commit, run at minimum:

```bash
git diff --check
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh

cd services/ai_service
./.venv/bin/python -m pytest
```

Review all untracked files and the complete diff. Do not reset, restore, discard,
or rewrite the working tree. If commit authorization is absent or Git requires
interactive approval, keep implementing and verifying safe in-scope slices and
leave the exact commit boundary documented.

The overnight chat may create local fix/feature commits only when a user message
explicitly authorizes them and the environment permits the Git write without
another interactive approval. Missing commit approval must never stop unrelated
safe code, tests, or verification.

## Completion Definition

The local product is complete only when all of these are true:

1. One command or one documented short sequence starts local Supabase, verifies
   exact local migration history, starts FastAPI, and starts Flutter in
   real-data mode without printing secrets.
2. Registration, Setup, daily capture, Today, task/habit/focus, feedback,
   Weekly Review, Insights, Skillset, Calendar file import, Coach, Inbox,
   settings, export, recovery, and account deletion pass their declared local
   contracts.
3. The real Coach works through the current user's own Codex login and keeps the
   strict data-use, safety, retry, memory, history, and no-mutation boundaries.
4. Notification preferences, creation, Inbox lifecycle, scheduling, quiet
   hours, deduplication, and supported local delivery behavior are implemented
   rather than inferred from stored rows.
5. Scheduled daily preparation actually runs through a documented local
   scheduler/harness and exposes failures; endpoint availability alone is not
   described as automation.
6. Every visible Weekly Review proposal either executes through an exact typed,
   confirmed, recoverable command or is clearly a non-actionable explanation.
   Do not present an apparent action that only says it may exist later.
7. Empty, loading, stale, offline, invalid-data, error, retry, and ambiguous
   write states remain honest across every visible surface.
8. Full non-reset browser E2E and all standard suites pass on the final commit.
9. A complete manual local acceptance run records exact results for remaining
   flows that browser automation does not cover.

This completion definition does not require live Google/Microsoft/Apple
Calendar synchronization when the visible product explicitly offers bounded
Calendar file import. It also does not require an offline write queue unless the
product claims one. Declared scope must be complete; speculative integrations
do not become blockers merely because they are technically possible.

## Phase 0: Audit The Current Hardening Checkpoint

Do this before building on the current delta; it does not require a commit:

1. Read `AGENTS.md` and every required document.
2. Inspect `git status --short --branch`, the complete diff, and every untracked
   file.
3. Reject credentials, generated artifacts, debug bypasses, or unrelated work.
4. Run `git diff --check`, `scripts/verify.sh`, and the complete FastAPI suite.
5. Record the exact verified boundary. Commit locally only after explicit user
   authorization, and never push.

## Phase 1: Re-Establish The Complete Deterministic Product Loop

Use only the repository's local Supabase stack. The non-reset E2E may create its
unique local test users and rows, but must not reset the database:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
  scripts/verify_supabase_local.sh

FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
  bash scripts/e2e_web.sh
```

Review pending local migrations, then use the explicit documented
`APPLY_MIGRATIONS=true` path only when its possible local-row changes are
intended. Never add `RESET_DB=true`. A current result must cover Setup revision/ownership, capture
merge and Daily State, Today generation/read boundaries, task/habit/focus
recovery, feedback, Weekly Review, Calendar import, fake-provider Coach,
account-control contracts, and RLS.

If a product defect appears, fix the smallest owning contract, add the
regression test, rerun the focused suite, then rerun the full browser journey.
Do not confuse an unavailable tool or port with a product defect.

## Phase 2: Make The Real Local Coach A Normal Supported Local Mode

The Coach already has the correct local architecture. Finish it as a
reproducible developer/product mode rather than replacing it:

1. Confirm `codex login status` for the same non-root WSL user that runs
   FastAPI. Never read or copy the OAuth file.
2. Keep the backend-only configuration:

```env
APP_ENV=development
USE_MOCK_DATA=false
COACH_PROVIDER=local_codex_oauth
LOCAL_CODEX_ENABLED=true
LOCAL_CODEX_MODEL=gpt-5.5
LOCAL_CODEX_TIMEOUT_SECONDS=45
LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20
LOCAL_CODEX_GLOBAL_CONCURRENCY=2
```

3. Keep Flutter in real Supabase mode and explicitly expose the development
   Coach surface. Do not send any Codex credential or backend service key to
   Flutter.
4. Run the deterministic fake-provider suites first.
5. Run the opt-in synthetic local-Codex smoke without logging content.
6. Run one full authenticated Flutter-to-live-Coach turn on a disposable local
   user and verify UI rendering, history, memory selection, request replay,
   deletion/tombstones, used-data manifest, uncertainty, provider truth, and
   retained usage accounting.
7. Exercise disabled, missing-login, unavailable-model, timeout, invalid-output,
   rate-limit, safety-bypass, and stale/missing-context states with fakes.

Use the explicitly configured model that the current account actually exposes.
Do not introduce a silent fallback or destabilize the working local path merely
to chase a newer model name.

## Phase 3: Complete Notifications Instead Of Treating Inbox Rows As Delivery

This is the largest proven visible product gap. Implement it as independently
reviewable slices:

### 3A. Durable Inbox Lifecycle

Implemented at the `notification-lifecycle-v1` boundary.

- typed mark-read/unread, dismiss/delete, and supported action commands;
- owner-scoped RLS and exact retry/ambiguous-write handling;
- loading, empty, error, retry, and offline truth;
- existing strict internal deep-link allowlist retained;
- widget, repository, migration/RLS, and browser assertions.

### 3B. Notification Generation Policy

Implemented in the current Notification Delivery V1 slice with explicit
consent, fixed no-LLM copy, timezone/quiet/category/cap/dedupe guards, and
bounded provenance. The base migration is applied to the authorized local stack;
the review follow-up is also applied without a reset, and the full non-reset
browser journey passes on that schema.

- backend-owned generation from explicit preferences and supported events;
- profile timezone and quiet hours;
- category opt-in, conservative daily cap, stable identity, deduplication, and
  retry safety;
- no private stress, health, relationship, or free-text content in delivery
  copy;
- no demo-user delivery and no streak-pressure language;
- exact source/provenance and a visible reason for each generated item.

### 3C. Local Scheduling And Delivery

Implemented in the current slice through the existing secret-safe 15-minute
local runner and acknowledged at-most-once Flutter foreground banners. This is
not Android/push/background delivery.

The notification-only current-target selector is consent-aware so bounded
runner slots are not consumed by fully current consent-off profiles. Missing or
stale Phase 7 preparation remains independently eligible.

- invoke generation/preparation from a documented local scheduler or runner;
- expose run status and per-user failure stage;
- implement the declared local Web/in-app delivery behavior completely;
- keep later Android FCM/device delivery behind its own provider/token contract.

Do not call notification preferences or stored notification rows a working
delivery system before 3A-3C pass end to end.

## Phase 4: Make Daily Preparation Actually Run Locally

Reuse `POST /v1/scheduled/daily-refresh`; do not create a competing generation
path.

- add a secret-safe local runner and documented WSL scheduling option;
- use one backend-only scheduled-refresh token;
- preserve profile-local dates, missing/stale/current selection, idempotency,
  bounded targeting, per-user failure isolation, and no-LLM behavior;
- make local operation observable without logging keys or personal content;
- verify a repeated current run is write-free;
- connect notification generation only after Phase 3's preference, copy,
  dedupe, and delivery contracts exist.

This completes local automation. A production cron platform remains an Android
deployment task, not a hidden assumption.

## Phase 5: Close Remaining Visible Action Gaps

Weekly Review now labels direct manual habit operations as executable, Setup
links as guidance that applies nothing, and staged replacements/defer or keep
proposals as non-interactive suggestion/no-write notes. The current slice adds
widget coverage for that authority boundary; the final E2E inventory remains
part of release acceptance.

Inventory the final UI again after Notifications and scheduling. For each
visible button, menu entry, proposal, and setting, prove one of:

- durable typed command with success, error, retry, and recovery;
- read-only information whose copy and affordance are unmistakably read-only;
- intentionally absent from the product.

Pay particular attention to:

- Weekly Review replacement, defer, goal, task, and schedule proposals;
- Coach review-only suggestions;
- Calendar imported/read-only controls;
- recommendation feedback versus executable Today actions;
- account export/share cancellation and permanent deletion;
- Setup ownership versus generic Habit/Goal management.

If the product displays a proposal as something the user can apply, add a
confirmed exact command with ownership, concurrency, rollback/readback, and E2E
coverage. If it is advice only, remove action styling and say so clearly. Coach
suggestions remain non-mutating unless a separately reviewed command contract is
introduced.

## Phase 6: One-Command Full Local Stack And Manual Acceptance

Provide a secret-safe local run path that:

- starts or reuses local Supabase;
- fails closed on migration-history differences and applies pending SQL only
  with explicit `APPLY_MIGRATIONS=true` after warning that rows may change or
  be deleted;
- reads local keys without printing them;
- starts FastAPI with either fake or explicitly enabled local-Codex Coach;
- starts Flutter with `USE_MOCK_DATA=false`;
- waits for health/readiness and reports ports/processes;
- cleans up only processes it started;
- never automates `codex login` and never reads OAuth files.

Then walk the complete user journey manually in addition to automation:

```text
registration -> Setup -> Evening -> Morning -> Today
-> task/habit/focus -> feedback -> Weekly Review
-> Insights/Skillset -> Calendar import -> Notifications
-> live Coach -> export -> recovery -> disposable-account deletion
```

Also test process restart, network loss, stale data, retry, small viewports,
keyboard, large text, light/dark theme, and browser reload/session restoration.

## Phase 7: Freeze The Local Release Candidate

On the final checkout:

- run `scripts/verify.sh`;
- run the full FastAPI suite;
- run non-reset local Supabase verification;
- run full non-reset browser E2E;
- run the fake-provider Coach boundary;
- run the explicit live-Coach smoke/product turn separately;
- run the Flutter Web release build;
- run `git diff --check` and confirm a clean working tree;
- record exact command results and create a local release-candidate commit/tag
  only when explicitly authorized.

No test result from an older intermediate checkout proves the final commit.

## After Local Completion: Standalone Android Production

Only then move to the independent Android production work:

1. install Android SDK/platform tools and prove debug APK/device behavior;
2. deploy Supabase migrations and HTTPS FastAPI to an approved staging
   environment;
3. add a deployable server-side LLM provider behind the existing
   `CoachProvider` seam, with API key, billing, quotas, safety, privacy, and
   observability kept outside Flutter;
4. configure Android auth callbacks, Google OAuth package/certificate identity,
   and later FCM/device tokens;
5. run emulator and physical-device acceptance;
6. configure protected upload signing and build an Android App Bundle;
7. complete privacy policy, Data Safety, external account-deletion page, store
   assets, internal testing, closed testing, and only then production review.

The local Codex/Pro path can remain an excellent development and personal test
provider. It cannot make a shipped Android app independent of the WSL machine;
the mobile client must call a reachable backend with a deployable provider.

## Authorization Boundary

Allowed for an explicitly authorized unattended local completion chat:

- repository code/test/doc edits;
- reviewed local migrations only after explicit authorization for their
  possible local-row changes;
- unique local E2E users/rows;
- deterministic fake-provider tests;
- an explicitly requested local live-Coach smoke using the already logged-in
  current WSL user, with the repository's no-content logging safeguards;
- local commits when the opening prompt explicitly authorizes them and the tool
  environment does not require another interactive approval.

Not allowed without fresh explicit authorization:

- database reset or destructive local cleanup;
- remote Supabase inspection/migration/mutation;
- deployment, push, pull request, Play upload, or publication;
- signing-key or credential creation/copying/disclosure;
- reading/copying Codex OAuth state or automating login;
- live account deletion except an explicitly approved disposable local account;
- broad autonomous agents, vector search, direct model database/tools, hidden
  memory extraction, or silent state-changing Coach suggestions.

## Required Completion Report

Report exact local commits, commands and results, real-Coach provider/model
truth, notification and scheduler behavior actually exercised, full E2E result,
manual journey result, remaining external blockers, and a strict distinction
between a product defect and an unavailable device/credential/deployment.
