#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  override_names=(
    AI_PERSONAL_COACH_APP_DIR FLUTTER_BIN HOST PORT USE_MOCK_DATA APP_ENV
    COACH_SURFACE_ENABLED LEARNED_FOCUS_PLANNING_PILOT_ENABLED
    AI_SERVICE_BASE_URL MODE SUPABASE_URL SUPABASE_PUBLISHABLE_KEY
    SUPABASE_ANON_KEY STAGING_SUPABASE_PROJECT_REF PILOT_SUPABASE_PROJECT_REF
  )
  declare -A shell_overrides=()
  for name in "${override_names[@]}"; do
    if [[ -v $name ]]; then
      shell_overrides["$name"]="${!name}"
    fi
  done
  set -a
  # shellcheck source=/dev/null
  . "$ROOT_DIR/.env"
  set +a
  for name in "${!shell_overrides[@]}"; do
    printf -v "$name" '%s' "${shell_overrides[$name]}"
    export "$name"
  done
fi

# A frontend dependency or build hook must not inherit backend-only material,
# even if a caller accidentally placed it in the shared root environment.
unset SUPABASE_SECRET_KEY SUPABASE_SERVICE_ROLE_KEY SCHEDULED_REFRESH_TOKEN

APP_DIR="${AI_PERSONAL_COACH_APP_DIR:-$ROOT_DIR/apps/mobile}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-7357}"
USE_MOCK_DATA="${USE_MOCK_DATA:-true}"
APP_ENV="${APP_ENV:-development}"
COACH_SURFACE_ENABLED="${COACH_SURFACE_ENABLED:-}"
LEARNED_FOCUS_PLANNING_PILOT_ENABLED="${LEARNED_FOCUS_PLANNING_PILOT_ENABLED:-false}"
AI_SERVICE_BASE_URL="${AI_SERVICE_BASE_URL:-http://localhost:8000}"
MODE="${MODE:-flutter}"

SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
STAGING_SUPABASE_PROJECT_REF="${STAGING_SUPABASE_PROJECT_REF:-}"
PILOT_SUPABASE_PROJECT_REF="${PILOT_SUPABASE_PROJECT_REF:-}"

cd "$APP_DIR"

"$FLUTTER_BIN" pub get

common_defines=(
  "--dart-define=APP_ENV=$APP_ENV"
  "--dart-define=USE_MOCK_DATA=$USE_MOCK_DATA"
  "--dart-define=AI_SERVICE_BASE_URL=$AI_SERVICE_BASE_URL"
  "--dart-define=COACH_SURFACE_ENABLED=$COACH_SURFACE_ENABLED"
  "--dart-define=LEARNED_FOCUS_PLANNING_PILOT_ENABLED=$LEARNED_FOCUS_PLANNING_PILOT_ENABLED"
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
  "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
  "--dart-define=STAGING_SUPABASE_PROJECT_REF=$STAGING_SUPABASE_PROJECT_REF"
  "--dart-define=PILOT_SUPABASE_PROJECT_REF=$PILOT_SUPABASE_PROJECT_REF"
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
