#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_supabase_migrations.sh"

SUPABASE_HOME="$ROOT_DIR/.tools/supabase-home"
LOG_DIR="$ROOT_DIR/.tools/local-stack"
AI_SERVICE_LOG="$LOG_DIR/ai-service.log"
SCHEDULER_LOG="$LOG_DIR/daily-refresh.log"
FRONTEND_LOG="$LOG_DIR/flutter-web.log"

FRONTEND_HOST="${LOCAL_STACK_FRONTEND_HOST:-127.0.0.1}"
FRONTEND_PORT="${LOCAL_STACK_FRONTEND_PORT:-7357}"
AI_SERVICE_HOST="${LOCAL_STACK_AI_HOST:-127.0.0.1}"
AI_SERVICE_PORT="${LOCAL_STACK_AI_PORT:-8000}"
COACH_PROVIDER_MODE="${LOCAL_STACK_COACH_PROVIDER:-disabled}"
SCHEDULER_INTERVAL_SECONDS="${LOCAL_STACK_REFRESH_INTERVAL_SECONDS:-900}"
READY_ATTEMPTS="${LOCAL_STACK_READY_ATTEMPTS:-120}"
RESET_DB="${RESET_DB-false}"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS-false}"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
AI_SERVICE_PYTHON="${AI_SERVICE_PYTHON:-$ROOT_DIR/services/ai_service/.venv/bin/python}"
LOCAL_CODEX_BIN="${LOCAL_CODEX_BIN:-codex}"
# Preserve an explicitly empty value: that is the provider contract for asking
# the CLI to choose its own model while reporting `model_requested: null`.
LOCAL_CODEX_MODEL="${LOCAL_CODEX_MODEL-gpt-5.5}"

# A caller cannot inject backend credentials into unrelated child processes.
# The local values used below are derived afresh and remain unexported shell
# variables until they are scoped to the exact backend/runner command.
unset SUPABASE_SERVICE_ROLE_KEY SCHEDULED_REFRESH_TOKEN

declare -a CHILD_PIDS=()
SHUTTING_DOWN=false

fail() {
  printf 'Local stack error: %s\n' "$1" >&2
  exit 1
}

is_loopback_host() {
  case "$1" in
    127.0.0.1 | localhost | ::1) return 0 ;;
    *) return 1 ;;
  esac
}

validate_port() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ || ${#value} -gt 5 ]] ||
    ((10#$value < 1 || 10#$value > 65535)); then
    fail "$name must be an integer from 1 to 65535."
  fi
}

validate_positive_integer() {
  local name="$1"
  local value="$2"
  local maximum="$3"
  if [[ ! "$value" =~ ^[0-9]+$ || ${#value} -gt 5 ]] ||
    ((10#$value < 1 || 10#$value > maximum)); then
    fail "$name must be an integer from 1 to $maximum."
  fi
}

url_host() {
  if [[ "$1" == "::1" ]]; then
    printf '[::1]'
  else
    printf '%s' "$1"
  fi
}

validate_local_supabase_url() {
  local value="${1%/}"
  local authority port

  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
  [[ "$value" != *'@'* && "$value" != *'?'* && "$value" != *'#'* ]] || return 1
  [[ "$value" == http://* ]] || return 1
  authority="${value#http://}"
  [[ "$authority" != */* ]] || return 1

  if [[ "$authority" =~ ^127\.0\.0\.1:([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
  elif [[ "$authority" =~ ^localhost:([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
  elif [[ "$authority" =~ ^\[::1\]:([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  [[ "$port" =~ ^[0-9]+$ && ${#port} -le 5 ]] &&
    ((10#$port >= 1 && 10#$port <= 65535))
}

resolve_executable() {
  local configured="$1"
  local resolved
  [[ -n "$configured" && "$configured" != *$'\n'* && "$configured" != *$'\r'* ]] ||
    return 1
  resolved="$(command -v -- "$configured" 2>/dev/null || true)"
  [[ -n "$resolved" && -x "$resolved" ]] || return 1
  printf '%s' "$resolved"
}

read_status_value() {
  local status="$1"
  local wanted="$2"
  local line key value

  while IFS= read -r line; do
    key="${line%%=*}"
    if [[ "$key" == "$wanted" ]]; then
      value="${line#*=}"
      if [[ ${#value} -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:${#value}-2}"
      fi
      printf '%s' "$value"
      return 0
    fi
  done <<<"$status"
  return 1
}

port_is_occupied() {
  local port="$1"
  local listeners
  if ! listeners="$("$SS_BIN" -H -ltn "sport = :$port" 2>/dev/null)"; then
    fail "Could not inspect local listening ports safely."
  fi
  [[ -n "$listeners" ]]
}

wait_for_http() {
  local label="$1"
  local url="$2"
  local pid="$3"
  local attempt

  for ((attempt = 1; attempt <= READY_ATTEMPTS; attempt++)); do
    if "$CURL_BIN" --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
      "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      fail "$label exited before becoming ready. Inspect its private log in $LOG_DIR."
    fi
    sleep 1
  done
  fail "$label did not become ready. Inspect its private log in $LOG_DIR."
}

cleanup() {
  local exit_code=$?
  local pid attempt

  if [[ "$SHUTTING_DOWN" == "true" ]]; then
    return
  fi
  SHUTTING_DOWN=true
  trap - EXIT INT TERM

  for pid in "${CHILD_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM -- "-$pid" >/dev/null 2>&1 ||
        kill -TERM "$pid" >/dev/null 2>&1 || true
    fi
  done

  for ((attempt = 1; attempt <= 50; attempt++)); do
    local any_running=false
    for pid in "${CHILD_PIDS[@]:-}"; do
      if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
        any_running=true
        break
      fi
    done
    [[ "$any_running" == "false" ]] && break
    sleep 0.1
  done

  for pid in "${CHILD_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill -KILL -- "-$pid" >/dev/null 2>&1 ||
        kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "$pid" ]]; then
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done

  unset local_service_role_key scheduler_token status_output local_anon_key
  if ((${#CHILD_PIDS[@]} > 0)); then
    printf 'Local app processes stopped. Local Supabase was left running for reuse.\n'
  fi
  exit "$exit_code"
}

on_interrupt() {
  exit 130
}

on_terminate() {
  exit 143
}

trap cleanup EXIT
trap on_interrupt INT
trap on_terminate TERM

is_loopback_host "$FRONTEND_HOST" ||
  fail "LOCAL_STACK_FRONTEND_HOST must be a loopback host."
is_loopback_host "$AI_SERVICE_HOST" ||
  fail "LOCAL_STACK_AI_HOST must be a loopback host."
validate_port "LOCAL_STACK_FRONTEND_PORT" "$FRONTEND_PORT"
validate_port "LOCAL_STACK_AI_PORT" "$AI_SERVICE_PORT"
FRONTEND_PORT="$((10#$FRONTEND_PORT))"
AI_SERVICE_PORT="$((10#$AI_SERVICE_PORT))"
[[ "$FRONTEND_PORT" != "$AI_SERVICE_PORT" ]] ||
  fail "Frontend and FastAPI ports must differ."
validate_positive_integer \
  "LOCAL_STACK_REFRESH_INTERVAL_SECONDS" "$SCHEDULER_INTERVAL_SECONDS" 86400
validate_positive_integer "LOCAL_STACK_READY_ATTEMPTS" "$READY_ATTEMPTS" 600
local_supabase_validate_migration_flags \
  "$RESET_DB" "$APPLY_MIGRATIONS" false || exit $?

case "$COACH_PROVIDER_MODE" in
  disabled | fake | local_codex_oauth) ;;
  *)
    fail "LOCAL_STACK_COACH_PROVIDER must be disabled, fake, or local_codex_oauth."
    ;;
esac

[[ "$LOCAL_CODEX_MODEL" != *$'\n'* && "$LOCAL_CODEX_MODEL" != *$'\r'* ]] ||
  fail "LOCAL_CODEX_MODEL contains invalid characters."

SUPABASE_BIN="$(resolve_executable supabase)" ||
  fail "Supabase CLI is not available in PATH."
CURL_BIN="$(resolve_executable curl)" || fail "curl is not available in PATH."
SS_BIN="$(resolve_executable ss)" || fail "ss is not available in PATH."
SETSID_BIN="$(resolve_executable setsid)" || fail "setsid is not available in PATH."
AI_SERVICE_PYTHON="$(resolve_executable "$AI_SERVICE_PYTHON")" ||
  fail "The configured FastAPI Python executable is unavailable."
FLUTTER_BIN="$(resolve_executable "$FLUTTER_BIN")" ||
  fail "The configured Flutter executable is unavailable."
[[ -f "$ROOT_DIR/services/ai_service/app/ops/local_daily_refresh.py" ]] ||
  fail "The local daily-refresh runner module is missing."
[[ -x "$ROOT_DIR/scripts/start_frontend.sh" ]] ||
  fail "The existing frontend start script is unavailable."

resolved_codex_bin="$LOCAL_CODEX_BIN"
if [[ "$COACH_PROVIDER_MODE" == "local_codex_oauth" ]]; then
  resolved_codex_bin="$(resolve_executable "$LOCAL_CODEX_BIN")" ||
    fail "Local Codex CLI is not available. Run codex login manually as this WSL user."
  "$resolved_codex_bin" --version >/dev/null 2>&1 ||
    fail "Local Codex CLI preflight failed."
  "$resolved_codex_bin" login status >/dev/null 2>&1 ||
    fail "Codex is not logged in for this WSL user. Run codex login manually."
fi

if port_is_occupied "$AI_SERVICE_PORT"; then
  fail "FastAPI port $AI_SERVICE_PORT is already occupied; refusing to reuse an unknown process."
fi
if port_is_occupied "$FRONTEND_PORT"; then
  fail "Frontend port $FRONTEND_PORT is already occupied; refusing to reuse an unknown process."
fi

if [[ -f "$ROOT_DIR/.env" ]] &&
  grep -Eq \
    '^[[:space:]]*(export[[:space:]]+)?(SUPABASE_SERVICE_ROLE_KEY|SCHEDULED_REFRESH_TOKEN)[[:space:]]*=' \
    "$ROOT_DIR/.env"; then
  fail "Root .env must not define backend-only service or scheduler credentials."
fi

mkdir -p "$SUPABASE_HOME" "$LOG_DIR"
chmod 700 "$SUPABASE_HOME" "$LOG_DIR"
: >"$AI_SERVICE_LOG"
: >"$SCHEDULER_LOG"
: >"$FRONTEND_LOG"
chmod 600 "$AI_SERVICE_LOG" "$SCHEDULER_LOG" "$FRONTEND_LOG"

supabase_cli() {
  HOME="$SUPABASE_HOME" SUPABASE_TELEMETRY_DISABLED=1 "$SUPABASE_BIN" "$@"
}

supabase_cli --version >/dev/null 2>&1 || fail "Supabase CLI preflight failed."
supabase_cli start >/dev/null 2>&1 ||
  fail "Local Supabase could not start or be reused. No CLI output was printed to avoid key leakage."
printf 'Local Supabase is available.\n'

if ! local_supabase_prepare_migration_state \
  "$RESET_DB" "$APPLY_MIGRATIONS" false; then
  fail "Local Supabase migration preflight failed."
fi

if ! status_output="$(supabase_cli status -o env 2>/dev/null)"; then
  fail "Local Supabase status is unavailable."
fi
api_url="$(read_status_value "$status_output" API_URL || true)"
local_anon_key="$(read_status_value "$status_output" ANON_KEY || true)"
local_service_role_key="$(read_status_value "$status_output" SERVICE_ROLE_KEY || true)"

[[ -n "$api_url" && -n "$local_anon_key" && -n "$local_service_role_key" ]] ||
  fail "Local Supabase did not return the required in-memory configuration."
validate_local_supabase_url "$api_url" ||
  fail "Supabase CLI returned a non-loopback or malformed API URL."
api_url="${api_url%/}"

scheduler_token="$("$AI_SERVICE_PYTHON" -c \
  'import secrets; print(secrets.token_urlsafe(48))')"
[[ -n "$scheduler_token" && "$scheduler_token" != *$'\n'* ]] ||
  fail "Could not create an in-memory scheduler token."

frontend_url_host="$(url_host "$FRONTEND_HOST")"
ai_url_host="$(url_host "$AI_SERVICE_HOST")"
APP_URL="http://$frontend_url_host:$FRONTEND_PORT"
AI_SERVICE_BASE_URL="http://$ai_url_host:$AI_SERVICE_PORT"
ALLOWED_ORIGINS="$APP_URL,http://127.0.0.1:$FRONTEND_PORT,http://localhost:$FRONTEND_PORT"

coach_fake_enabled=false
local_codex_enabled=false
if [[ "$COACH_PROVIDER_MODE" == "fake" ]]; then
  coach_fake_enabled=true
elif [[ "$COACH_PROVIDER_MODE" == "local_codex_oauth" ]]; then
  local_codex_enabled=true
fi

(
  cd "$ROOT_DIR/services/ai_service"
  APP_ENV=development \
    API_PREFIX=/v1 \
    USE_MOCK_DATA=false \
    ALLOWED_ORIGINS="$ALLOWED_ORIGINS" \
    SUPABASE_URL="$api_url" \
    SUPABASE_SERVICE_ROLE_KEY="$local_service_role_key" \
    SCHEDULED_REFRESH_TOKEN="$scheduler_token" \
    COACH_PROVIDER="$COACH_PROVIDER_MODE" \
    COACH_FAKE_PROVIDER_ENABLED="$coach_fake_enabled" \
    LOCAL_CODEX_ENABLED="$local_codex_enabled" \
    LOCAL_CODEX_BIN="$resolved_codex_bin" \
    LOCAL_CODEX_MODEL="$LOCAL_CODEX_MODEL" \
    exec "$SETSID_BIN" "$AI_SERVICE_PYTHON" -m uvicorn app.main:app \
      --host "$AI_SERVICE_HOST" \
      --port "$AI_SERVICE_PORT" \
      >>"$AI_SERVICE_LOG" 2>&1
) &
AI_SERVICE_PID=$!
CHILD_PIDS+=("$AI_SERVICE_PID")

wait_for_http "FastAPI" "$AI_SERVICE_BASE_URL/v1/health" "$AI_SERVICE_PID"
printf 'FastAPI is ready at %s.\n' "$AI_SERVICE_BASE_URL"

(
  cd "$ROOT_DIR/services/ai_service"
  SCHEDULED_REFRESH_TOKEN="$scheduler_token" \
    LOCAL_DAILY_REFRESH_BASE_URL="$AI_SERVICE_BASE_URL" \
    exec "$SETSID_BIN" "$AI_SERVICE_PYTHON" \
      -m app.ops.local_daily_refresh \
      --loop \
      --interval-seconds "$SCHEDULER_INTERVAL_SECONDS" \
      >>"$SCHEDULER_LOG" 2>&1
) &
SCHEDULER_PID=$!
CHILD_PIDS+=("$SCHEDULER_PID")

(
  cd "$ROOT_DIR"
  unset SUPABASE_SERVICE_ROLE_KEY SCHEDULED_REFRESH_TOKEN
  APP_ENV=development \
    USE_MOCK_DATA=false \
    SUPABASE_URL="$api_url" \
    SUPABASE_ANON_KEY="$local_anon_key" \
    AI_SERVICE_BASE_URL="$AI_SERVICE_BASE_URL" \
    COACH_SURFACE_ENABLED=true \
    HOST="$FRONTEND_HOST" \
    PORT="$FRONTEND_PORT" \
    FLUTTER_BIN="$FLUTTER_BIN" \
    exec "$SETSID_BIN" "$ROOT_DIR/scripts/start_frontend.sh" \
      >>"$FRONTEND_LOG" 2>&1
) &
FRONTEND_PID=$!
CHILD_PIDS+=("$FRONTEND_PID")

# The supervisor no longer needs copies once the exact children have inherited
# their scoped values. The anon key is publishable local client configuration.
unset local_service_role_key scheduler_token status_output

wait_for_http "Flutter Web" "$APP_URL/" "$FRONTEND_PID"
printf 'Flutter Web is ready at %s.\n' "$APP_URL"
printf 'Coach provider: %s\n' "$COACH_PROVIDER_MODE"
case "$COACH_PROVIDER_MODE" in
  disabled)
    printf '%s\n' \
      'Coach replies are off for this run. Use `npm run start:local:coach` for live local replies or `npm run start:local:coach:fake` for fixed test replies.'
    ;;
  fake)
    printf '%s\n' \
      'Coach replies use fixed deterministic test content; no live model is contacted.'
    ;;
  local_codex_oauth)
    printf '%s\n' \
      'Coach replies use this Linux user'\''s explicitly enabled local Codex login.'
    ;;
esac
printf 'Private logs: %s\n' "$LOG_DIR"
printf 'Press Ctrl+C to stop app processes. Local Supabase will remain running.\n'

set +e
wait -n "${CHILD_PIDS[@]}"
child_status=$?
set -e
fail "A managed local process exited unexpectedly with status $child_status. Inspect $LOG_DIR."
