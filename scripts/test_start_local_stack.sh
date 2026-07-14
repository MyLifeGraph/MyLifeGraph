#!/usr/bin/env bash
set -euo pipefail

umask 077

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/mylifegraph-local-stack-test.XXXXXX)"
REPO="$TEST_ROOT/repo"
FAKE_BIN="$TEST_ROOT/fake-bin"
EVENTS="$TEST_ROOT/events.log"
OUTPUT="$TEST_ROOT/supervisor.log"

cleanup_test() {
  if [[ -n "${SUPERVISOR_PID:-}" ]] &&
    kill -0 "$SUPERVISOR_PID" >/dev/null 2>&1; then
    kill -TERM "$SUPERVISOR_PID" >/dev/null 2>&1 || true
    wait "$SUPERVISOR_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup_test EXIT

mkdir -p \
  "$REPO/scripts/lib" \
  "$REPO/scripts" \
  "$REPO/apps/mobile" \
  "$REPO/services/ai_service/app/ops" \
  "$FAKE_BIN"
cp "$SOURCE_ROOT/scripts/start_local_stack.sh" "$REPO/scripts/start_local_stack.sh"
cp "$SOURCE_ROOT/scripts/start_frontend.sh" "$REPO/scripts/start_frontend.sh"
cp "$SOURCE_ROOT/scripts/lib/local_supabase_migrations.sh" \
  "$REPO/scripts/lib/local_supabase_migrations.sh"
touch "$REPO/services/ai_service/app/ops/local_daily_refresh.py"
chmod 700 "$REPO/scripts/start_local_stack.sh" "$REPO/scripts/start_frontend.sh"

cat >"$FAKE_BIN/supabase" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'supabase home=%s command=' "$HOME" >>"$TEST_EVENT_FILE"
printf '%s ' "$@" >>"$TEST_EVENT_FILE"
printf '\n' >>"$TEST_EVENT_FILE"
case "${1:-}" in
  --version)
    printf '2.107.0\n'
    ;;
  start)
    ;;
  migration)
    if [[ "${2:-}" == "list" && "${3:-}" == "--local" ]]; then
      cat <<'MIGRATIONS'
  Local          | Remote         | Time (UTC)
 ----------------|----------------|---------------------
  20260714100000 | 20260714100000 | 2026-07-14 10:00:00
  20260714103000 | 20260714103000 | 2026-07-14 10:30:00
MIGRATIONS
    elif [[ "${2:-}" == "up" && "${3:-}" == "--local" ]]; then
      :
    else
      exit 91
    fi
    ;;
  status)
    [[ "${2:-}" == "-o" && "${3:-}" == "env" ]]
    cat <<'STATUS'
API_URL="http://127.0.0.1:54321"
ANON_KEY="fake-anon-key"
SERVICE_ROLE_KEY="fake-service-key"
STATUS
    ;;
  *)
    exit 90
    ;;
esac
EOF

cat >"$FAKE_BIN/ss" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_PORT_OCCUPIED:-false}" == "true" ]]; then
  printf 'LISTEN 0 128 127.0.0.1:8000 0.0.0.0:*\n'
fi
EOF

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl called\n' >>"$TEST_EVENT_FILE"
EOF

cat >"$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'codex command=' >>"$TEST_EVENT_FILE"
printf '%s ' "$@" >>"$TEST_EVENT_FILE"
printf '\n' >>"$TEST_EVENT_FILE"
printf 'private-preflight-marker\n'
printf 'private-preflight-marker\n' >&2
EOF

cat >"$FAKE_BIN/python" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-c" ]]; then
  printf 'token-generator called\n' >>"$TEST_EVENT_FILE"
  printf 'fake-scheduler-token\n'
  exit 0
fi

kind=unknown
if [[ "${1:-}" == "-m" && "${2:-}" == "uvicorn" ]]; then
  kind=backend
elif [[ "${1:-}" == "-m" && "${2:-}" == "app.ops.local_daily_refresh" ]]; then
  kind=runner
fi

printf '%s service=%s token=%s anon=%s provider=%s local=%s fake=%s\n' \
  "$kind" \
  "${SUPABASE_SERVICE_ROLE_KEY:+set}" \
  "${SCHEDULED_REFRESH_TOKEN:+set}" \
  "${SUPABASE_ANON_KEY:+set}" \
  "${COACH_PROVIDER:-unset}" \
  "${LOCAL_CODEX_ENABLED:-unset}" \
  "${COACH_FAKE_PROVIDER_ENABLED:-unset}" \
  >>"$TEST_EVENT_FILE"

trap 'printf "%s terminated\\n" "$kind" >>"$TEST_EVENT_FILE"; exit 0' TERM INT
while :; do
  sleep 1
done
EOF

cat >"$FAKE_BIN/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pub" && "${2:-}" == "get" ]]; then
  printf 'flutter-pub-get called\n' >>"$TEST_EVENT_FILE"
  exit 0
fi

printf 'frontend service=%s token=%s anon=%s mock=%s coach=%s\n' \
  "${SUPABASE_SERVICE_ROLE_KEY:+set}" \
  "${SCHEDULED_REFRESH_TOKEN:+set}" \
  "${SUPABASE_ANON_KEY:+set}" \
  "${USE_MOCK_DATA:-unset}" \
  "${COACH_SURFACE_ENABLED:-unset}" \
  >>"$TEST_EVENT_FILE"
trap 'printf "frontend terminated\\n" >>"$TEST_EVENT_FILE"; exit 0' TERM INT
while :; do
  sleep 1
done
EOF

chmod 700 "$FAKE_BIN"/*

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq -- "$pattern" "$file"; then
    printf 'Expected %q in %s\n' "$pattern" "$file" >&2
    sed -n '1,240p' "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    printf 'Did not expect %q in %s\n' "$pattern" "$file" >&2
    exit 1
  fi
}

wait_for_event() {
  local pattern="$1"
  local attempt
  for ((attempt = 1; attempt <= 200; attempt++)); do
    if [[ -f "$EVENTS" ]] && grep -Fq -- "$pattern" "$EVENTS"; then
      return 0
    fi
    if ! kill -0 "$SUPERVISOR_PID" >/dev/null 2>&1; then
      printf 'Supervisor exited before event %q.\n' "$pattern" >&2
      sed -n '1,240p' "$OUTPUT" >&2 || true
      exit 1
    fi
    sleep 0.05
  done
  printf 'Timed out waiting for event %q.\n' "$pattern" >&2
  exit 1
}

export TEST_EVENT_FILE="$EVENTS"
PATH="$FAKE_BIN:$PATH" \
AI_SERVICE_PYTHON="$FAKE_BIN/python" \
FLUTTER_BIN="$FAKE_BIN/flutter" \
LOCAL_CODEX_BIN="$FAKE_BIN/codex" \
LOCAL_STACK_COACH_PROVIDER=local_codex_oauth \
LOCAL_STACK_READY_ATTEMPTS=2 \
"$REPO/scripts/start_local_stack.sh" >"$OUTPUT" 2>&1 &
SUPERVISOR_PID=$!

wait_for_event 'backend service=set token=set anon= provider=local_codex_oauth local=true fake=false'
wait_for_event 'runner service= token=set anon= provider=unset local=unset fake=unset'
wait_for_event 'frontend service= token= anon=set mock=false coach=true'

kill -TERM "$SUPERVISOR_PID"
set +e
wait "$SUPERVISOR_PID"
supervisor_status=$?
set -e
SUPERVISOR_PID=
[[ "$supervisor_status" -eq 143 ]] || {
  printf 'Expected supervisor status 143, got %s.\n' "$supervisor_status" >&2
  exit 1
}

assert_contains "$EVENTS" "supabase home=$REPO/.tools/supabase-home command=start "
assert_contains "$EVENTS" 'supabase home='
assert_contains "$EVENTS" 'command=migration list --local '
assert_contains "$EVENTS" 'command=status -o env '
assert_contains "$EVENTS" 'codex command=--version '
assert_contains "$EVENTS" 'codex command=login status '
assert_contains "$EVENTS" 'backend terminated'
assert_contains "$EVENTS" 'runner terminated'
assert_contains "$EVENTS" 'frontend terminated'
assert_not_contains "$EVENTS" 'reset'
assert_not_contains "$EVENTS" 'stop'
assert_not_contains "$EVENTS" 'command=migration up --local '
assert_not_contains "$OUTPUT" 'fake-service-key'
assert_not_contains "$OUTPUT" 'fake-scheduler-token'
assert_not_contains "$OUTPUT" 'private-preflight-marker'

for log_file in ai-service.log daily-refresh.log flutter-web.log; do
  mode="$(stat -c '%a' "$REPO/.tools/local-stack/$log_file")"
  [[ "$mode" == "600" ]] || {
    printf 'Expected mode 600 for %s, got %s.\n' "$log_file" "$mode" >&2
    exit 1
  }
done

NEGATIVE_EVENTS="$TEST_ROOT/negative-events.log"
export TEST_EVENT_FILE="$NEGATIVE_EVENTS"

set +e
PATH="$FAKE_BIN:$PATH" \
AI_SERVICE_PYTHON="$FAKE_BIN/python" \
FLUTTER_BIN="$FAKE_BIN/flutter" \
LOCAL_STACK_FRONTEND_HOST=0.0.0.0 \
"$REPO/scripts/start_local_stack.sh" >"$TEST_ROOT/non-loopback.log" 2>&1
non_loopback_status=$?

PATH="$FAKE_BIN:$PATH" \
AI_SERVICE_PYTHON="$FAKE_BIN/python" \
FLUTTER_BIN="$FAKE_BIN/flutter" \
LOCAL_STACK_COACH_PROVIDER=other \
"$REPO/scripts/start_local_stack.sh" >"$TEST_ROOT/provider.log" 2>&1
provider_status=$?

PATH="$FAKE_BIN:$PATH" \
AI_SERVICE_PYTHON="$FAKE_BIN/python" \
FLUTTER_BIN="$FAKE_BIN/flutter" \
FAKE_PORT_OCCUPIED=true \
"$REPO/scripts/start_local_stack.sh" >"$TEST_ROOT/occupied.log" 2>&1
occupied_status=$?

PATH="$FAKE_BIN:$PATH" \
AI_SERVICE_PYTHON="$FAKE_BIN/python" \
FLUTTER_BIN="$FAKE_BIN/flutter" \
APPLY_MIGRATIONS=yes \
"$REPO/scripts/start_local_stack.sh" >"$TEST_ROOT/migration-flag.log" 2>&1
migration_flag_status=$?

PATH="$FAKE_BIN:$PATH" \
AI_SERVICE_PYTHON="$FAKE_BIN/python" \
FLUTTER_BIN="$FAKE_BIN/flutter" \
RESET_DB=true \
"$REPO/scripts/start_local_stack.sh" >"$TEST_ROOT/reset-forbidden.log" 2>&1
reset_forbidden_status=$?
set -e

[[ "$non_loopback_status" -eq 1 ]]
[[ "$provider_status" -eq 1 ]]
[[ "$occupied_status" -eq 1 ]]
[[ "$migration_flag_status" -eq 2 ]]
[[ "$reset_forbidden_status" -eq 2 ]]
assert_contains "$TEST_ROOT/non-loopback.log" 'must be a loopback host'
assert_contains "$TEST_ROOT/provider.log" 'must be disabled, fake, or local_codex_oauth'
assert_contains "$TEST_ROOT/occupied.log" 'already occupied; refusing to reuse an unknown process'
assert_contains "$TEST_ROOT/migration-flag.log" 'must be exactly true or false'
assert_contains "$TEST_ROOT/reset-forbidden.log" 'this command never resets the database'
if [[ -f "$NEGATIVE_EVENTS" ]]; then
  assert_not_contains "$NEGATIVE_EVENTS" 'command=start '
fi

printf 'start_local_stack hermetic tests passed\n'
