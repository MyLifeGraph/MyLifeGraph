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

Do not run destructive Supabase commands against a remote database. These
scripts are for the local Supabase stack from `supabase/config.toml`.

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

Current Flutter widget tests include:

- Auth gate renders.
- Guest can continue, complete onboarding, and reach the dashboard.
- Guest can complete a quick mood check-in and persist it locally in
  `shared_preferences`.

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
20260618170000_create_canonical_app_schema.sql
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

Use real Ubuntu-installed Node.js, npm, Supabase CLI, and Docker. If these tools
are installed through nvm, non-interactive agent shells may need an explicit
`PATH` or `NODE_BIN` override even when `node --version` works in the user's
interactive shell. Do not install replacement tool binaries into `.tools/`.

The script:

1. Uses the real Ubuntu Supabase CLI from `PATH`.
2. Starts the local Supabase stack and optionally runs `supabase db reset`.
3. Reads `API_URL`, `ANON_KEY`, and `SERVICE_ROLE_KEY` from
   `supabase status -o env` without printing key values.
4. Starts Flutter Web on `127.0.0.1:7357` with `USE_MOCK_DATA=false`.
5. Runs `e2e/web/smoke.mjs` with Playwright.

The script waits for the Flutter log line containing `is being served at` before
starting Playwright. A plain `curl` response from `/` is not enough, because
`flutter run -d web-server` can answer before the debug web bundle is ready; if
Playwright opens the page during that window, screenshots are often blank white.

The E2E Flutter process also passes `--dart-define=E2E_ENABLE_SEMANTICS=true`.
`apps/mobile/lib/main.dart` uses that test-only flag to keep Flutter Semantics
enabled, which gives Playwright stable text fields, buttons, and labels instead
of relying on canvas pixels.

The browser smoke creates a confirmed local Supabase Auth user through the local
admin API, signs in through the app, completes onboarding, saves a daily
check-in, saves a quick mood check-in, opens alerts, sends a coach message, and
then queries local Supabase REST with the local service-role key to assert that
`daily_logs`, `behavioral_events`, and `coach_messages` rows were created. The
daily and quick check-ins share one `daily_logs` row because that table is unique
by `(user_id, entry_date)`; the smoke uses `behavioral_events.source` to verify
that both check-in flows wrote their event signals.

The coach step uses the page's default prompt, sends it through the visible
coach send button, and verifies the persisted `coach_messages` row. This keeps
the assertion tied to persistence rather than canvas-rendered chat text.

`e2e/web/smoke.mjs` navigates Flutter routes through root hash URLs such as
`/#/auth` and `/#/daily-check-in`. This avoids direct deep-link requests against
the `flutter run -d web-server` development server, which does not provide a
production-style rewrite layer for every app path.

The service-role key is used only in the Node-side E2E process for local setup
and assertions. It must never be passed into Flutter or browser runtime
configuration.

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
E2E_RUN_ID=manual-001
```

Flutter Web logs for the E2E run are written to:

```text
.tools/e2e/flutter-web.log
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
Local service role key: available for Node-side assertions
```

If command output includes a key unexpectedly, redact it before sharing logs.

## Current Automation Gap

The repository now contains browser E2E automation, but it still depends on a
real Ubuntu Node.js 20+ installation, `npm`, Playwright browser installation,
Docker access, and a real Ubuntu `supabase` CLI on `PATH`.

Known harmless local E2E output includes Chromium WebGL performance warnings.
If the FastAPI AI service is not running, the browser can also log
`ERR_CONNECTION_REFUSED` for `AI_SERVICE_BASE_URL`; this is acceptable as long
as `scripts/e2e_web.sh` exits successfully and prints the browser smoke pass
message.

Still missing for broader product verification:

- CI wiring for the browser E2E command.
- Playwright trace artifact collection on failure.
- Dedicated database assertions for notifications, onboarding schedule items,
  and memory entries.
- Coverage for Google OAuth, mobile layout, and authenticated guest-data
  migration.

When changing E2E flows, keep `e2e/web/smoke.mjs`, `scripts/e2e_web.sh`, and
this document in sync.
