#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ROOT_DIR/.env"
  set +a
fi

APP_DIR="${AI_PERSONAL_COACH_APP_DIR:-$ROOT_DIR/apps/mobile}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-7357}"
USE_MOCK_DATA="${USE_MOCK_DATA:-true}"
APP_ENV="${APP_ENV:-development}"
AI_SERVICE_BASE_URL="${AI_SERVICE_BASE_URL:-http://localhost:8000}"
MODE="${MODE:-flutter}"

SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

cd "$APP_DIR"

"$FLUTTER_BIN" pub get

common_defines=(
  "--dart-define=APP_ENV=$APP_ENV"
  "--dart-define=USE_MOCK_DATA=$USE_MOCK_DATA"
  "--dart-define=AI_SERVICE_BASE_URL=$AI_SERVICE_BASE_URL"
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
)

echo "Starting MyLifeGraph frontend at http://$HOST:$PORT"
echo "Mode: $MODE"
echo "Mock data: $USE_MOCK_DATA"

if [[ "$MODE" == "static" ]]; then
  "$FLUTTER_BIN" build web --debug --no-wasm-dry-run "${common_defines[@]}"
  python3 -m http.server "$PORT" --bind "$HOST" --directory build/web
else
  "$FLUTTER_BIN" run -d web-server \
    --web-hostname "$HOST" \
    --web-port "$PORT" \
    "${common_defines[@]}"
fi
