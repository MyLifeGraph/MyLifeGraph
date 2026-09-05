#!/usr/bin/env bash
set -euo pipefail

groups=(source flutter backend)
if [[ "$#" -ne 0 ]]; then
  if [[ "$#" -ne 2 || "$1" != '--group' ]]; then
    echo 'Usage: verify_fast.sh [--group source|flutter|backend]' >&2
    exit 64
  fi
  case "$2" in
    source|flutter|backend) groups=("$2") ;;
    *) echo "Unknown verification group: $2" >&2; exit 64 ;;
  esac
fi

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

for group in "${groups[@]}"; do
  "run_${group}_checks" >"$VERIFY_TMP_DIR/$group.log" 2>&1 &
  printf -v "${group}_pid" '%s' "$!"
done

status=0
for group in "${groups[@]}"; do
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
