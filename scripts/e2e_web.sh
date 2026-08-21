#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"

# Local E2E owns exact derived credentials. Refuse inherited backend keys from
# selecting a different project or leaking into unrelated child processes.
unset SUPABASE_SECRET_KEY SUPABASE_SERVICE_ROLE_KEY

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
FLUTTER_WEB_MODE="${FLUTTER_WEB_MODE:-profile}"
STATIC_SERVER_PYTHON="${STATIC_SERVER_PYTHON:-python3}"
NODE_BIN="${NODE_BIN:-node}"
SS_BIN="${SS_BIN:-ss}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-7357}"
APP_URL="${APP_URL:-http://$HOST:$PORT}"
AI_SERVICE_HOST="${AI_SERVICE_HOST:-127.0.0.1}"
AI_SERVICE_PORT="${AI_SERVICE_PORT:-8000}"
AI_SERVICE_BASE_URL="${AI_SERVICE_BASE_URL:-http://$AI_SERVICE_HOST:$AI_SERVICE_PORT}"
AI_SERVICE_START="${AI_SERVICE_START-true}"
HEADED="${HEADED-false}"
E2E_SEMANTICS_PRE_ENABLED="${E2E_SEMANTICS_PRE_ENABLED-true}"
E2E_SUITE="${E2E_SUITE-full}"
E2E_JOURNEY="${E2E_JOURNEY-}"
LEARNED_FOCUS_PLANNING_PILOT_ENABLED="${LEARNED_FOCUS_PLANNING_PILOT_ENABLED-true}"
RESET_DB="${RESET_DB-false}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS-false}"
SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"
E2E_RUN_ID="${E2E_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
SCHEDULED_REFRESH_TOKEN="${SCHEDULED_REFRESH_TOKEN:-local-e2e-scheduled-refresh-$E2E_RUN_ID}"
E2E_LOG_ROOT="$ROOT_DIR/.tools/e2e/runs"
E2E_RUN_DIR="$E2E_LOG_ROOT/$E2E_RUN_ID"
FLUTTER_LOG="$E2E_RUN_DIR/flutter-web.log"
AI_SERVICE_LOG="$E2E_RUN_DIR/ai-service.log"
SUPABASE_START_FAILURE_TAIL_LINES=200
SUPABASE_START_LOG=''

timer_now_ms() {
  date +%s%3N
}

emit_timing() {
  local phase="$1"
  local started_at="$2"
  local finished_at
  finished_at="$(timer_now_ms)"
  printf '[e2e:timing] {"phase":"%s","duration_ms":%d}\n' \
    "$phase" "$((finished_at - started_at))"
}

assert_port_free_for_start() {
  local label="$1"
  local port="$2"
  local listeners

  if ! command -v "$SS_BIN" >/dev/null 2>&1; then
    echo "Port inspection is unavailable as '$SS_BIN'; refusing to start $label." >&2
    exit 127
  fi
  if ! listeners="$("$SS_BIN" -H -ltn "sport = :$port" 2>&1)"; then
    echo "Port inspection failed for $label on port $port; refusing to start it." >&2
    exit 1
  fi
  if [[ -n "${listeners//[[:space:]]/}" ]]; then
    echo "Port $port is already occupied; refusing to reuse an unknown process for $label." >&2
    exit 1
  fi
}

wait_for_owned_http() {
  local label="$1"
  local url="$2"
  local pid="$3"
  local log_file="$4"
  local attempts="$5"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "$label exited before it became ready at $url. Recent log:" >&2
      tail -n 80 "$log_file" >&2 || true
      return 1
    fi
    if curl -fsS "$url" >/dev/null 2>&1; then
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        echo "$label exited while another process answered at $url. Recent log:" >&2
        tail -n 80 "$log_file" >&2 || true
        return 1
      fi
      sleep 0.25
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        echo "$label exited during readiness stabilization at $url. Recent log:" >&2
        tail -n 80 "$log_file" >&2 || true
        return 1
      fi
      return 0
    fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "$label exited before it became ready at $url. Recent log:" >&2
      tail -n 80 "$log_file" >&2 || true
      return 1
    fi
    sleep 1
  done

  echo "$label did not become ready at $url. Recent log:" >&2
  tail -n 80 "$log_file" >&2 || true
  return 1
}

cd "$ROOT_DIR"
mkdir -p "$SUPABASE_HOME"

local_supabase_validate_migration_flags \
  "$RESET_DB" "$APPLY_MIGRATIONS" false || exit $?
local_supabase_validate_boolean AI_SERVICE_START "$AI_SERVICE_START" || exit $?
local_supabase_validate_boolean HEADED "$HEADED" || exit $?
local_supabase_validate_boolean \
  E2E_SEMANTICS_PRE_ENABLED \
  "$E2E_SEMANTICS_PRE_ENABLED" || exit $?
local_supabase_validate_boolean \
  LEARNED_FOCUS_PLANNING_PILOT_ENABLED \
  "$LEARNED_FOCUS_PLANNING_PILOT_ENABLED" || exit $?
if [[ ! "$FLUTTER_WEB_MODE" =~ ^(debug|profile|release)$ ]]; then
  echo "FLUTTER_WEB_MODE must be debug, profile, or release." >&2
  exit 64
fi
if [[ "$FLUTTER_WEB_MODE" != "debug" ]] &&
  ! command -v "$STATIC_SERVER_PYTHON" >/dev/null 2>&1; then
  echo "Static-server Python is not available as '$STATIC_SERVER_PYTHON'." >&2
  exit 127
fi

if [[ ! "$E2E_RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,57}$ ]]; then
  echo "E2E_RUN_ID must contain 1-58 safe filename/email-token characters." >&2
  exit 64
fi

if [[ -e "$E2E_RUN_DIR" ]]; then
  echo "E2E_RUN_ID '$E2E_RUN_ID' already has an artifact directory." >&2
  echo "Choose a fresh run id; E2E run identities are never reused." >&2
  exit 64
fi
mkdir -p "$E2E_RUN_DIR"

if [[ ! "$E2E_SUITE" =~ ^(smoke|full)$ ]]; then
  echo "E2E_SUITE must be smoke or full." >&2
  exit 64
fi

if [[ -n "$E2E_JOURNEY" ]] &&
  ! "$NODE_BIN" "$ROOT_DIR/e2e/web/journey-manifest.mjs" "$E2E_JOURNEY"; then
  echo "E2E_JOURNEY must name one current Playwright journey." >&2
  exit 64
fi

if [[
  ( -z "$E2E_JOURNEY" && "$E2E_SUITE" == "full" ||
    "$E2E_JOURNEY" == "personal-learning" ) &&
  "$LEARNED_FOCUS_PLANNING_PILOT_ENABLED" != "true"
]]; then
  echo "Personal Learning browser coverage requires LEARNED_FOCUS_PLANNING_PILOT_ENABLED=true." >&2
  exit 64
fi

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
    -e 's#postgres(ql)?://[^[:space:]│]+#postgresql://<redacted>#g' \
    -e 's/(Publishable[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Access Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(Secret Key[[:space:]]*│[[:space:]]*)[^│]+/\1<redacted> /g' \
    -e 's/(KEY|SECRET|PASSWORD)=.*/\1=<redacted>/g'
}

cleanup() {
  local original_status=$?
  local cleanup_started_at
  cleanup_started_at="$(timer_now_ms)"
  trap - EXIT
  if [[ -n "${FLUTTER_PID:-}" ]] && kill -0 "$FLUTTER_PID" >/dev/null 2>&1; then
    kill "$FLUTTER_PID" >/dev/null 2>&1 || true
    wait "$FLUTTER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${AI_SERVICE_PID:-}" ]] && kill -0 "$AI_SERVICE_PID" >/dev/null 2>&1; then
    kill "$AI_SERVICE_PID" >/dev/null 2>&1 || true
    wait "$AI_SERVICE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${SUPABASE_START_LOG:-}" && -f "$SUPABASE_START_LOG" ]]; then
    rm -f -- "$SUPABASE_START_LOG"
    SUPABASE_START_LOG=''
  fi
  emit_timing "process_cleanup" "$cleanup_started_at"
  exit "$original_status"
}
trap cleanup EXIT

supabase_started_at="$(timer_now_ms)"
supabase_cli --version
SUPABASE_START_LOG="$(
  mktemp "${TMPDIR:-/tmp}/mylifegraph-e2e-supabase-start.XXXXXX"
)"
chmod 600 "$SUPABASE_START_LOG"
if ! supabase_cli start >"$SUPABASE_START_LOG" 2>&1; then
  printf '%s\n' \
    "Supabase local stack start failed; showing the final ${SUPABASE_START_FAILURE_TAIL_LINES} sanitized log lines." >&2
  tail -n "$SUPABASE_START_FAILURE_TAIL_LINES" "$SUPABASE_START_LOG" |
    sanitize_supabase_output >&2
  exit 1
fi
printf '%s\n' 'Supabase local stack started.'
rm -f -- "$SUPABASE_START_LOG"
SUPABASE_START_LOG=''

local_supabase_prepare_migration_state \
  "$RESET_DB" "$APPLY_MIGRATIONS" false
emit_timing "supabase" "$supabase_started_at"

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

fastapi_started_at="$(timer_now_ms)"
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
  assert_port_free_for_start "AI service" "$AI_SERVICE_PORT"
  APP_ENV=development \
  API_PREFIX=/v1 \
  USE_MOCK_DATA=false \
  ALLOWED_ORIGINS="$APP_URL,http://localhost:$PORT" \
  SUPABASE_URL="$api_url" \
  SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
  SCHEDULED_REFRESH_TOKEN="$SCHEDULED_REFRESH_TOKEN" \
  COACH_PROVIDER=fake \
  COACH_FAKE_PROVIDER_ENABLED=true \
  LEARNED_FOCUS_PLANNING_PILOT_ENABLED="$LEARNED_FOCUS_PLANNING_PILOT_ENABLED" \
  "$AI_SERVICE_PYTHON" -m uvicorn app.main:app \
    --host "$AI_SERVICE_HOST" \
    --port "$AI_SERVICE_PORT" \
    >"$AI_SERVICE_LOG" 2>&1 &
  AI_SERVICE_PID="$!"
  cd "$ROOT_DIR"

  if ! wait_for_owned_http \
    "AI service" \
    "$AI_SERVICE_BASE_URL/v1/health" \
    "$AI_SERVICE_PID" \
    "$AI_SERVICE_LOG" \
    60; then
    echo "Choose a free AI_SERVICE_PORT; the E2E runner will not reuse an unknown process." >&2
    echo "Set AI_SERVICE_START=false only to intentionally reuse a compatible already-running service." >&2
    exit 1
  fi
else
  echo "Skipping AI service startup because AI_SERVICE_START=false."
  if ! curl -fsS "$AI_SERVICE_BASE_URL/v1/health" >/dev/null 2>&1; then
    echo "AI_SERVICE_START=false requires a healthy compatible AI service at $AI_SERVICE_BASE_URL." >&2
    exit 1
  fi
fi
emit_timing "fastapi" "$fastapi_started_at"

flutter_started_at="$(timer_now_ms)"
cd "$ROOT_DIR/apps/mobile"
flutter_define_args=(
  --dart-define=APP_ENV=development
  --dart-define=USE_MOCK_DATA=false
  --dart-define=SUPABASE_URL="$api_url"
  --dart-define=SUPABASE_ANON_KEY="$local_anon_key"
  --dart-define=AI_SERVICE_BASE_URL="$AI_SERVICE_BASE_URL"
  --dart-define=COACH_SURFACE_ENABLED=true
  --dart-define=LEARNED_FOCUS_PLANNING_PILOT_ENABLED="$LEARNED_FOCUS_PLANNING_PILOT_ENABLED"
  --dart-define=E2E_ENABLE_SEMANTICS=true
)
if [[ "$FLUTTER_WEB_MODE" == "debug" ]]; then
  assert_port_free_for_start "Flutter Web" "$PORT"
  "$FLUTTER_BIN" run -d web-server \
    --debug \
    --web-hostname "$HOST" \
    --web-port "$PORT" \
    "${flutter_define_args[@]}" \
    >"$FLUTTER_LOG" 2>&1 &
  FLUTTER_PID="$!"
else
  "$FLUTTER_BIN" build web \
    "--$FLUTTER_WEB_MODE" \
    "${flutter_define_args[@]}" \
    >"$FLUTTER_LOG" 2>&1
  assert_port_free_for_start "Flutter Web" "$PORT"
  "$STATIC_SERVER_PYTHON" -m http.server "$PORT" \
    --bind "$HOST" \
    --directory "$ROOT_DIR/apps/mobile/build/web" \
    >>"$FLUTTER_LOG" 2>&1 &
  FLUTTER_PID="$!"
fi

cd "$ROOT_DIR"
echo "Waiting for Flutter Web at $APP_URL"
if ! wait_for_owned_http \
  "Flutter Web server" \
  "$APP_URL/" \
  "$FLUTTER_PID" \
  "$FLUTTER_LOG" \
  120; then
  exit 1
fi
emit_timing "flutter" "$flutter_started_at"

runner_started_at="$(timer_now_ms)"
set +e
APP_URL="$APP_URL" \
SUPABASE_URL="$api_url" \
SUPABASE_ANON_KEY="$local_anon_key" \
SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
AI_SERVICE_BASE_URL="$AI_SERVICE_BASE_URL" \
SCHEDULED_REFRESH_TOKEN="$SCHEDULED_REFRESH_TOKEN" \
E2E_SEMANTICS_PRE_ENABLED="$E2E_SEMANTICS_PRE_ENABLED" \
E2E_ARTIFACT_DIR="$E2E_RUN_DIR" \
E2E_RUN_ID="$E2E_RUN_ID" \
E2E_SUITE="$E2E_SUITE" \
E2E_JOURNEY="$E2E_JOURNEY" \
"$ROOT_DIR/node_modules/.bin/playwright" test \
  --config e2e/web/playwright.config.mjs
runner_status=$?
set -e
emit_timing "runner" "$runner_started_at"
exit "$runner_status"
