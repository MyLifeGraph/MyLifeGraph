#!/usr/bin/env bash
set -euo pipefail

umask 077

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/mylifegraph-e2e-ownership-test.XXXXXX)"
REPO="$TEST_ROOT/repo"
FAKE_BIN="$TEST_ROOT/fake-bin"

cleanup_test() {
  rm -rf "$TEST_ROOT"
}
trap cleanup_test EXIT

mkdir -p \
  "$REPO/scripts/lib" \
  "$REPO/apps/mobile" \
  "$REPO/services/ai_service" \
  "$REPO/node_modules/playwright" \
  "$REPO/node_modules/.bin" \
  "$TEST_ROOT/tmp" \
  "$FAKE_BIN"
cp "$SOURCE_ROOT/scripts/e2e_web.sh" "$REPO/scripts/e2e_web.sh"
cp "$SOURCE_ROOT/scripts/lib/local_supabase_migrations.sh" \
  "$REPO/scripts/lib/local_supabase_migrations.sh"

cat >"$FAKE_BIN/supabase" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    printf '2.107.0\n'
    ;;
  start)
    printf 'supabase-start-log-mode=%s\n' \
      "$(stat -Lc %a "/proc/$$/fd/1")" >>"$TEST_EVENT_FILE"
    for ((line = 1; line <= ${FAKE_SUPABASE_START_LINES:-1}; line++)); do
      printf 'supabase-start-line-%03d\n' "$line"
    done
    if [[ "${FAKE_SUPABASE_START_FAIL:-false}" == "true" ]]; then
      printf 'Secret │ fake-local-secret │\n'
      exit 37
    fi
    ;;
  migration)
    [[ "${2:-}" == "list" && "${3:-}" == "--local" ]]
    cat <<'MIGRATIONS'
  Local          | Remote         | Time (UTC)
 ----------------|----------------|---------------------
  20260714100000 | 20260714100000 | 2026-07-14 10:00:00
MIGRATIONS
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
printf 'ss %s\n' "$*" >>"$TEST_EVENT_FILE"
port_filter="${*: -1}"
port="${port_filter##*:}"
if [[ "${FAKE_SS_FAIL_PORT:-}" == "$port" ]]; then
  exit 17
fi
if [[ "${FAKE_OCCUPIED_PORT:-}" == "$port" ]]; then
  printf 'LISTEN 0 128 127.0.0.1:%s 0.0.0.0:*\n' "$port"
fi
EOF

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >>"$TEST_EVENT_FILE"
if [[ "$*" == *'/v1/health'* && -n "${TEST_CURL_MARKER:-}" ]]; then
  touch "$TEST_CURL_MARKER"
fi
EOF

cat >"$FAKE_BIN/python" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-m" && "${2:-}" == "uvicorn" ]]; then
  printf 'backend-start\n' >>"$TEST_EVENT_FILE"
  if [[ "${FAKE_AI_MODE:-alive}" == "delayed_die" ]]; then
    while [[ ! -e "$TEST_CURL_MARKER" ]]; do
      sleep 0.01
    done
    sleep 0.05
    exit 23
  fi
  trap 'exit 0' TERM INT
  while :; do sleep 1; done
fi
exit 91
EOF

cat >"$FAKE_BIN/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter-start %s\n' "$*" >>"$TEST_EVENT_FILE"
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF

cat >"$FAKE_BIN/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$REPO/node_modules/.bin/playwright" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'playwright %s\n' "$*" >>"$TEST_EVENT_FILE"
EOF

chmod 700 "$FAKE_BIN"/* "$REPO/node_modules/.bin/playwright"

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq -- "$pattern" "$file"; then
    printf 'Expected %q in %s\n' "$pattern" "$file" >&2
    sed -n '1,240p' "$file" >&2 || true
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    printf 'Did not expect %q in %s\n' "$pattern" "$file" >&2
    sed -n '1,240p' "$file" >&2 || true
    exit 1
  fi
}

run_case() {
  local name="$1"
  local expected_status="$2"
  shift 2
  CASE_EVENTS="$TEST_ROOT/$name.events"
  CASE_OUTPUT="$TEST_ROOT/$name.output"
  local marker="$TEST_ROOT/$name.curl"
  : >"$CASE_EVENTS"

  set +e
  env -i \
    PATH="$FAKE_BIN:/usr/local/bin:/usr/bin:/bin" \
    TMPDIR="$TEST_ROOT/tmp" \
    TEST_EVENT_FILE="$CASE_EVENTS" \
    TEST_CURL_MARKER="$marker" \
    AI_SERVICE_PYTHON="$FAKE_BIN/python" \
    FLUTTER_BIN="$FAKE_BIN/flutter" \
    NODE_BIN="$FAKE_BIN/node" \
    SS_BIN="$FAKE_BIN/ss" \
    FLUTTER_WEB_MODE=debug \
    E2E_SUITE=smoke \
    E2E_RUN_ID="$name" \
    "$@" \
    "$REPO/scripts/e2e_web.sh" >"$CASE_OUTPUT" 2>&1
  local status=$?
  set -e
  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'Case %s expected status %s, got %s.\n' \
      "$name" "$expected_status" "$status" >&2
    sed -n '1,240p' "$CASE_OUTPUT" >&2 || true
    exit 1
  fi
  if find "$TEST_ROOT/tmp" -mindepth 1 -print -quit | grep -q .; then
    printf 'Case %s left a Supabase start log behind.\n' "$name" >&2
    find "$TEST_ROOT/tmp" -mindepth 1 -maxdepth 1 -print >&2
    exit 1
  fi
}

run_case fastapi-occupied 1 FAKE_OCCUPIED_PORT=8000
assert_contains "$CASE_OUTPUT" 'Supabase local stack started.'
assert_not_contains "$CASE_OUTPUT" 'supabase-start-line-001'
assert_contains "$CASE_EVENTS" 'supabase-start-log-mode=600'
assert_contains "$CASE_OUTPUT" \
  'Port 8000 is already occupied; refusing to reuse an unknown process for AI service.'
assert_contains "$CASE_EVENTS" 'sport = :8000'
assert_not_contains "$CASE_EVENTS" 'backend-start'
assert_not_contains "$CASE_EVENTS" 'flutter-start'

run_case flutter-occupied 1 FAKE_OCCUPIED_PORT=7357
assert_contains "$CASE_OUTPUT" \
  'Port 7357 is already occupied; refusing to reuse an unknown process for Flutter Web.'
assert_contains "$CASE_EVENTS" 'sport = :8000'
assert_contains "$CASE_EVENTS" 'sport = :7357'
assert_contains "$CASE_EVENTS" 'backend-start'
assert_not_contains "$CASE_EVENTS" 'flutter-start'

run_case delayed-backend-exit 1 FAKE_AI_MODE=delayed_die
assert_contains "$CASE_OUTPUT" \
  'AI service exited during readiness stabilization'
assert_contains "$CASE_EVENTS" 'backend-start'
assert_not_contains "$CASE_EVENTS" 'flutter-start'

run_case failed-port-check 1 FAKE_SS_FAIL_PORT=8000
assert_contains "$CASE_OUTPUT" \
  'Port inspection failed for AI service on port 8000'
assert_not_contains "$CASE_EVENTS" 'backend-start'

run_case explicit-fastapi-reuse 0 \
  AI_SERVICE_START=false \
  FAKE_OCCUPIED_PORT=8000
assert_not_contains "$CASE_EVENTS" 'sport = :8000'
assert_contains "$CASE_EVENTS" 'sport = :7357'
assert_not_contains "$CASE_EVENTS" 'backend-start'
assert_contains "$CASE_EVENTS" 'flutter-start'
assert_contains "$CASE_EVENTS" 'playwright test'

run_case supabase-start-failure 1 \
  FAKE_SUPABASE_START_FAIL=true \
  FAKE_SUPABASE_START_LINES=205
assert_contains "$CASE_OUTPUT" \
  'Supabase local stack start failed; showing the final 200 sanitized log lines.'
assert_not_contains "$CASE_OUTPUT" 'supabase-start-line-001'
assert_contains "$CASE_OUTPUT" 'supabase-start-line-007'
assert_contains "$CASE_OUTPUT" 'supabase-start-line-205'
assert_contains "$CASE_OUTPUT" 'Secret │ <redacted>'
assert_contains "$CASE_EVENTS" 'supabase-start-log-mode=600'
assert_not_contains "$CASE_EVENTS" 'backend-start'
assert_not_contains "$CASE_EVENTS" 'flutter-start'

printf 'e2e_web process-ownership tests passed\n'
