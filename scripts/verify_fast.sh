#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
VERIFY_TMP_DIR="$(mktemp -d /tmp/mylifegraph-verify-fast.XXXXXX)"

cleanup() {
  rm -rf "$VERIFY_TMP_DIR"
}
trap cleanup EXIT

if [[ -n "${AI_SERVICE_PYTHON:-}" ]]; then
  PYTHON_BIN="$AI_SERVICE_PYTHON"
elif [[ -x "$ROOT_DIR/services/ai_service/.venv/bin/python" ]]; then
  PYTHON_BIN="$ROOT_DIR/services/ai_service/.venv/bin/python"
else
  PYTHON_BIN="${PYTHON_BIN:-python3}"
fi

run_source_checks() {
  bash "$ROOT_DIR/scripts/verify_source.sh"
}

run_flutter_checks() {
  cd "$ROOT_DIR/apps/mobile"
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" analyze
  "$FLUTTER_BIN" test
}

run_backend_checks() {
  cd "$ROOT_DIR"
  "$PYTHON_BIN" -m compileall -q services/ai_service/app
  cd "$ROOT_DIR/services/ai_service"
  "$PYTHON_BIN" -m ruff check app tests
  "$PYTHON_BIN" -m pytest
}

run_source_checks >"$VERIFY_TMP_DIR/source.log" 2>&1 &
source_pid=$!
run_flutter_checks >"$VERIFY_TMP_DIR/flutter.log" 2>&1 &
flutter_pid=$!
run_backend_checks >"$VERIFY_TMP_DIR/backend.log" 2>&1 &
backend_pid=$!

status=0
for group in source flutter backend; do
  pid_variable="${group}_pid"
  pid="${!pid_variable}"
  if ! wait "$pid"; then
    status=1
  fi
  printf '\n== verify:fast %s ==\n' "$group"
  sed -n '1,$p' "$VERIFY_TMP_DIR/$group.log"
done

if [[ "$status" -ne 0 ]]; then
  echo "verify:fast failed." >&2
  exit "$status"
fi

echo "verify:fast passed."
