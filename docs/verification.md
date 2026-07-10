# Verification And Agent Automation

This document is the shared runbook for automated checks. It describes what can
be verified by agents without manual app exploration, what requires local
tooling, and what remains future work.

## Verification Levels

Use the lowest level that covers the change.

| Level | Command | Purpose | Destructive |
| --- | --- | --- | --- |
| Standard | `FLUTTER_BIN=/path/to/flutter scripts/verify.sh` | Non-destructive repo checks. | No |
| Local Supabase preflight | `FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Starts local Supabase and runs tests with Supabase config. | No |
| Local Supabase reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter scripts/verify_supabase_local.sh` | Recreates local DB, applies migrations, then runs tests. | Yes, local DB only |
| Browser E2E | `FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Starts local Supabase, starts Flutter Web, drives Playwright, and checks DB writes. | No |
| Browser E2E with reset | `RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh` | Recreates local DB, then runs browser E2E. | Yes, local DB only |
| Demo seed | `npm run seed:demo` | Starts local Supabase and seeds repeatable demo users/data for manual exploration. | No |

Do not run destructive Supabase commands against a remote database. These
scripts are for the local Supabase stack from `supabase/config.toml`.

## Demo Seed

Manual product exploration can use local seeded accounts instead of hardcoded
mock data:

```bash
npm run seed:demo
```

This runs `scripts/seed_demo_data.sh`, which starts local Supabase, reads the
local service-role key from `supabase status -o env`, and invokes
`scripts/seed_demo_data.mjs`. The Node script rejects any API URL outside
`http://127.0.0.1:54321` and `http://localhost:54321`.

The seed is idempotent for the demo accounts. It keeps the local Auth users,
updates their password and metadata, clears their app rows, and recreates the
scenario data. Each Intake row is a valid applied revision with a stable request
id and intentionally empty optional Setup-owned collections. Separately seeded
goals, habits, and schedule rows retain `demo_seed` ownership and are not
presented as Setup materialization. The default local-only password is
`DemoPass123!` for:

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

- `bash -n scripts/start_frontend.sh`
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `python3 -m compileall services/ai_service/app`
- `git diff --check`

FastAPI unit tests are run separately:

```bash
cd services/ai_service
./.venv/bin/python -m pytest
```

Use `python -m pytest` from an environment with `services/ai_service`
requirements installed if the local `.venv` does not exist.

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
and refreshing an existing `user_state_snapshots` row for the same period.
Scheduled refresh tests
cover the backend-only token guard, onboarded non-guest profile selection,
per-user failure isolation, deterministic daily snapshot refresh, and optional
deterministic recommendation refresh without LLM wording.

Current Flutter widget tests include:

- Auth gate renders.
- Guest can complete required-only progressive Setup, persist exact empty
  optionals, and reach the dashboard without an invented goal, friction,
  routine, note, or commitment.
- Typed Setup model/data-source tests cover stable item keys, candidate versus
  confirmed cadence, `request_id`/`base_revision` request JSON, authenticated
  setup reads, and invalid response/error propagation.
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
- Guest can select distinctive mood, energy, sleep, stress, and context values,
  persist the exact typed check-in locally, and read the saved summary on return.
- Check-in mapper tests assert the exact `daily_logs` payload and four linked
  `behavioral_events`, including source, units, metadata, and nulling of
  uncollected legacy placeholder fields.
- Guest-store tests cover exact JSON, one-entry-per-day retry deduplication, and
  recovery from corrupted local JSON.
- Check-in widget tests cover required explicit selections, draft retention after
  failure, stable retry, and suppression of a duplicate in-flight save.
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
- Dashboard mapper/widget tests assert exact raw values, honest empty/error
  states, local source labels, and the absence of former proxy metrics.
- Capability, Settings, and notification tests cover the gated Coach/Deep Work/
  guest-Habit routes, persistent local-demo label, strict `action_url` allowlist,
  original notification fields/read state, and separate real empty/error states.
- The Snapshot refresh service posts `POST /v1/snapshots/generate` with bearer
  auth in real backend mode, skips guest/mock/missing-token paths, and treats
  network failures as best-effort.
- Task and habit snapshot refresh service entrypoints route through the same
  authenticated daily snapshot refresh behavior. The active dashboard task
  status, Quick Action habit management writes, and Quick Action habit
  completion writes use those entrypoints.
- Guest can inspect the deterministic Insights correlation surface without
  requiring Supabase.
- The correlation analyzer covers positive, negative, missing, low-variation,
  and weak-relationship ranking behavior.
- The Insights repository keeps mock correlation data scoped to mock/guest mode
  and does not substitute demo correlations for empty or failing real Supabase
  reads.
- Source-boundary provider tests keep Setup, canonical check-in, Dashboard, and
  Insights on local/demo sources when `USE_MOCK_DATA=true`, even if an
  authenticated Supabase session exists.
- Habit visibility tests exclude every Setup-managed habit from generic Habit
  Management while keeping active Setup habits in Habit Completion and hiding
  candidate/archived states.

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

Without `RESET_DB=true`, the script does not reset the database. It is useful as
a Docker/Supabase/toolchain preflight plus app test run.

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
20260710180000_atomic_intake_v1_setup_apply.sql
```

Expected notices include skipped legacy CamelCase tables and already-existing
canonical objects. Those notices are normal. Errors are not normal.

The reset destroys and recreates the local Supabase database. It must not be
used for a remote project.

## Browser E2E

Browser E2E is implemented with Playwright:

```bash
npm install
npx playwright install chromium
FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

For a fresh local database before the browser run:

```bash
RESET_DB=true FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
```

If an existing local database is behind the repository migrations, apply pending
local migrations before running the smoke:

```bash
HOME=.tools/supabase-home SUPABASE_TELEMETRY_DISABLED=1 supabase migration up --local
```

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
   local Supabase settings.
5. Starts Flutter Web on `127.0.0.1:7357` with `USE_MOCK_DATA=false` and
   `AI_SERVICE_BASE_URL` pointing at the local FastAPI service.
6. Runs `e2e/web/smoke.mjs` with Playwright.

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
owned records; one explicit goal, routine candidate, and fixed commitment;
retry after a response is lost; prefilled edit with stable identity; cadence
confirmation; and review actions that archive/pause/remove Setup-owned rows.
Node-side fixtures include manual rows, and database assertions require those
rows to survive reconciliation unchanged.

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

The smoke then creates a habit through Habit Management, follows
`/daily-check-in` into the canonical lightweight capture, saves distinctive
check-in values twice for the same day, logs the managed habit completion, uses
the dashboard refresh action, opens Notifications, and verifies the gated Coach
and Deep Work compatibility redirects. It still asserts deterministic
post-intake recommendations, exact `daily_logs` and linked behavioral events,
`habit_logs`, and backend-refreshed daily snapshots. Mood `2`, energy `9`, sleep
`5.5`, stress `8`, the trimmed note, and exactly four same-day
`quick_check_in` events remain value-level checks. Manual refresh requests to
`/v1/snapshots/generate` and `/v1/recommendations/generate` are observed and
their deterministic payloads asserted.

`e2e/web/smoke.mjs` navigates Flutter routes through root hash URLs such as
`/#/auth` and `/#/daily-check-in`. This avoids direct deep-link requests against
the `flutter run -d web-server` development server, which does not provide a
production-style rewrite layer for every app path.

The service-role key is used only in the Node-side E2E process for local setup
and assertions and in the FastAPI process for backend persistence. It must never
be passed into Flutter or browser runtime configuration.

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
E2E_RUN_ID=manual-001
```

By default, `scripts/e2e_web.sh` starts FastAPI from the current checkout and
does not reuse an arbitrary service that is already listening on the same port.
If the port is occupied, stop that service or set `AI_SERVICE_PORT` to a free
port. Use `AI_SERVICE_START=false` only when you intentionally want to reuse a
compatible FastAPI process that is already running with the same local Supabase
project settings.

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

## Current Automation Gap

The repository now contains browser E2E automation, but it still depends on a
real Ubuntu Node.js 20+ installation, `npm`, Playwright browser installation,
Docker access, and a real Ubuntu `supabase` CLI on `PATH`.

Known harmless local E2E output includes Chromium WebGL performance warnings.
The FastAPI AI service must be healthy for the browser smoke to pass.

Still missing for broader product verification:

- CI wiring for the browser E2E command.
- Playwright trace artifact collection on failure.
- Dedicated database assertions for notifications, notification preferences,
  and non-Setup memory behavior beyond the current Setup ownership/snapshot
  checks.
- Coverage for Google OAuth, mobile layout, and best-effort authenticated guest
  check-in migration. Guest Setup intentionally has no automatic account
  migration.

When changing E2E flows, keep `e2e/web/smoke.mjs`, `scripts/e2e_web.sh`, and
this document in sync.
