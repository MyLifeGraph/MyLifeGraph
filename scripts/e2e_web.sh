#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
NODE_BIN="${NODE_BIN:-node}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-7357}"
APP_URL="${APP_URL:-http://$HOST:$PORT}"
AI_SERVICE_HOST="${AI_SERVICE_HOST:-127.0.0.1}"
AI_SERVICE_PORT="${AI_SERVICE_PORT:-8000}"
AI_SERVICE_BASE_URL="${AI_SERVICE_BASE_URL:-http://$AI_SERVICE_HOST:$AI_SERVICE_PORT}"
AI_SERVICE_START="${AI_SERVICE_START-true}"
HEADED="${HEADED-false}"
E2E_PHASE10_ONLY="${E2E_PHASE10_ONLY-false}"
SCHEDULED_REFRESH_TOKEN="${SCHEDULED_REFRESH_TOKEN:-local-e2e-scheduled-refresh-${E2E_RUN_ID:-$$}}"
RESET_DB="${RESET_DB-false}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS-false}"
SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"
E2E_LOG_DIR="$ROOT_DIR/.tools/e2e"
FLUTTER_LOG="$E2E_LOG_DIR/flutter-web.log"
AI_SERVICE_LOG="$E2E_LOG_DIR/ai-service.log"

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME" "$E2E_LOG_DIR"

local_supabase_validate_migration_flags \
  "$RESET_DB" "$APPLY_MIGRATIONS" true || exit $?
local_supabase_validate_boolean AI_SERVICE_START "$AI_SERVICE_START" || exit $?
local_supabase_validate_boolean HEADED "$HEADED" || exit $?
local_supabase_validate_boolean E2E_PHASE10_ONLY "$E2E_PHASE10_ONLY" || exit $?

if command -v supabase >/dev/null 2>&1; then
  SUPABASE_BIN="$(command -v supabase)"
else
  echo "Supabase CLI is not available." >&2
  echo "Install the Supabase CLI in Ubuntu and make 'supabase --version' work." >&2
  exit 127
fi

if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
  echo "Node.js is not available as '$NODE_BIN'." >&2
  echo "Install Node.js in Ubuntu and make 'node --version' work." >&2
  exit 127
fi

if [[ ! -d "$ROOT_DIR/node_modules/playwright" ]]; then
  echo "Playwright is not installed in node_modules." >&2
  echo "Run: npm install" >&2
  echo "Then install a browser if needed: npx playwright install chromium" >&2
  exit 127
fi

supabase_cli() {
  HOME="$SUPABASE_HOME" SUPABASE_TELEMETRY_DISABLED=1 "$SUPABASE_BIN" "$@"
}

sanitize_supabase_output() {
  sed -E \
    -e 's/(Publishable[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Access Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

cleanup() {
  if [[ -n "${FLUTTER_PID:-}" ]] && kill -0 "$FLUTTER_PID" >/dev/null 2>&1; then
    kill "$FLUTTER_PID" >/dev/null 2>&1 || true
    wait "$FLUTTER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${AI_SERVICE_PID:-}" ]] && kill -0 "$AI_SERVICE_PID" >/dev/null 2>&1; then
    kill "$AI_SERVICE_PID" >/dev/null 2>&1 || true
    wait "$AI_SERVICE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

supabase_cli --version
if ! start_output="$(supabase_cli start 2>&1)"; then
  printf '%s\n' "$start_output" | sanitize_supabase_output >&2
  exit 1
fi
printf '%s\n' "$start_output" | sanitize_supabase_output

local_supabase_prepare_migration_state \
  "$RESET_DB" "$APPLY_MIGRATIONS" true

status_output="$(supabase_cli status -o env)"
api_url="$(printf '%s\n' "$status_output" | awk -F= '$1 == "API_URL" {gsub(/"/, "", $2); print $2; exit}')"
local_anon_key="$(printf '%s\n' "$status_output" | awk -F= '$1 == "ANON_KEY" {gsub(/"/, "", $2); print $2; exit}')"
local_service_role_key="$(printf '%s\n' "$status_output" | awk -F= '$1 == "SERVICE_ROLE_KEY" {gsub(/"/, "", $2); print $2; exit}')"

if [[ -z "$api_url" || -z "$local_anon_key" || -z "$local_service_role_key" ]]; then
  echo "Could not read local Supabase API URL or keys from 'supabase status -o env'." >&2
  exit 2
fi

echo "Supabase local API: $api_url"
echo "Local anon key: available"
echo "Local service role key: available for backend and Node-side assertions"

if [[ "$AI_SERVICE_START" == "true" ]]; then
  if [[ -n "${AI_SERVICE_PYTHON:-}" ]]; then
    if ! command -v "$AI_SERVICE_PYTHON" >/dev/null 2>&1; then
      echo "AI service Python is not available as '$AI_SERVICE_PYTHON'." >&2
      exit 127
    fi
  else
    if [[ -x "$ROOT_DIR/services/ai_service/.venv/bin/python" ]]; then
      AI_SERVICE_PYTHON="$ROOT_DIR/services/ai_service/.venv/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
      AI_SERVICE_PYTHON="$(command -v python3)"
    else
      echo "Python 3 is not available for the AI service." >&2
      exit 127
    fi
  fi

  echo "Starting AI service from this checkout at $AI_SERVICE_BASE_URL"
  cd "$ROOT_DIR/services/ai_service"
  APP_ENV=development \
  API_PREFIX=/v1 \
  USE_MOCK_DATA=false \
  ALLOWED_ORIGINS="$APP_URL,http://localhost:$PORT" \
  SUPABASE_URL="$api_url" \
  SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
  SCHEDULED_REFRESH_TOKEN="$SCHEDULED_REFRESH_TOKEN" \
  COACH_PROVIDER=fake \
  COACH_FAKE_PROVIDER_ENABLED=true \
  "$AI_SERVICE_PYTHON" -m uvicorn app.main:app \
    --host "$AI_SERVICE_HOST" \
    --port "$AI_SERVICE_PORT" \
    >"$AI_SERVICE_LOG" 2>&1 &
  AI_SERVICE_PID="$!"
  cd "$ROOT_DIR"

  ai_service_ready=false
  for _ in {1..60}; do
    if curl -fsS "$AI_SERVICE_BASE_URL/v1/health" >/dev/null 2>&1; then
      ai_service_ready=true
      break
    fi
    if ! kill -0 "$AI_SERVICE_PID" >/dev/null 2>&1; then
      echo "AI service exited early. Recent log:" >&2
      tail -n 80 "$AI_SERVICE_LOG" >&2 || true
      echo "If another service is already using $AI_SERVICE_BASE_URL, stop it or set AI_SERVICE_PORT to a free port." >&2
      echo "Set AI_SERVICE_START=false only to intentionally reuse a compatible already-running service." >&2
      exit 1
    fi
    sleep 1
  done

  if [[ "$ai_service_ready" != "true" ]]; then
    echo "AI service did not become ready at $AI_SERVICE_BASE_URL. Recent log:" >&2
    tail -n 80 "$AI_SERVICE_LOG" >&2 || true
    exit 1
  fi
else
  echo "Skipping AI service startup because AI_SERVICE_START=false."
  if ! curl -fsS "$AI_SERVICE_BASE_URL/v1/health" >/dev/null 2>&1; then
    echo "AI_SERVICE_START=false requires a healthy compatible AI service at $AI_SERVICE_BASE_URL." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR/apps/mobile"
USE_MOCK_DATA=false \
APP_ENV=development \
SUPABASE_URL="$api_url" \
SUPABASE_ANON_KEY="$local_anon_key" \
AI_SERVICE_BASE_URL="$AI_SERVICE_BASE_URL" \
"$FLUTTER_BIN" run -d web-server \
  --web-hostname "$HOST" \
  --web-port "$PORT" \
  --dart-define=APP_ENV=development \
  --dart-define=USE_MOCK_DATA=false \
  --dart-define=SUPABASE_URL="$api_url" \
  --dart-define=SUPABASE_ANON_KEY="$local_anon_key" \
  --dart-define=AI_SERVICE_BASE_URL="$AI_SERVICE_BASE_URL" \
  --dart-define=COACH_SURFACE_ENABLED=true \
  --dart-define=E2E_ENABLE_SEMANTICS=true \
  >"$FLUTTER_LOG" 2>&1 &
FLUTTER_PID="$!"

cd "$ROOT_DIR"
echo "Waiting for Flutter Web at $APP_URL"
flutter_ready=false
for _ in {1..120}; do
  if grep -q "is being served at" "$FLUTTER_LOG" &&
    curl -fsS "$APP_URL/" >/dev/null 2>&1; then
    flutter_ready=true
    break
  fi
  if ! kill -0 "$FLUTTER_PID" >/dev/null 2>&1; then
    echo "Flutter Web server exited early. Recent log:" >&2
    tail -n 80 "$FLUTTER_LOG" >&2 || true
    exit 1
  fi
  sleep 1
done

if [[ "$flutter_ready" != "true" ]]; then
  echo "Flutter Web did not become ready at $APP_URL. Recent log:" >&2
  tail -n 80 "$FLUTTER_LOG" >&2 || true
  exit 1
fi

APP_URL="$APP_URL" \
SUPABASE_URL="$api_url" \
SUPABASE_ANON_KEY="$local_anon_key" \
SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
AI_SERVICE_BASE_URL="$AI_SERVICE_BASE_URL" \
SCHEDULED_REFRESH_TOKEN="$SCHEDULED_REFRESH_TOKEN" \
E2E_ARTIFACT_DIR="$E2E_LOG_DIR" \
E2E_RUN_ID="${E2E_RUN_ID:-$(date +%s)}" \
"$NODE_BIN" e2e/web/smoke.mjs
