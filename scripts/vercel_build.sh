#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_CACHE_ROOT="${VERCEL_CACHE_DIR:-$HOME/.cache}/flutter"
FLUTTER_HOME="${FLUTTER_CACHE_ROOT}/${FLUTTER_VERSION}"

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
    rm -rf "${FLUTTER_HOME}"
    mkdir -p "${FLUTTER_CACHE_ROOT}"
    git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git "${FLUTTER_HOME}"
  fi

  export PATH="${FLUTTER_HOME}/bin:${PATH}"
  FLUTTER_BIN="${FLUTTER_HOME}/bin/flutter"
fi

"${FLUTTER_BIN}" --version
"${FLUTTER_BIN}" config --enable-web

cd apps/mobile

RESOLVED_SUPABASE_URL="${SUPABASE_URL:-${VITE_SUPABASE_URL:-${NEXT_PUBLIC_SUPABASE_URL:-}}}"
RESOLVED_SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-${VITE_SUPABASE_ANON_KEY:-${NEXT_PUBLIC_SUPABASE_ANON_KEY:-${NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:-}}}}}"

if [ -n "${RESOLVED_SUPABASE_URL}" ] && [ -n "${RESOLVED_SUPABASE_ANON_KEY}" ]; then
  echo "Supabase config detected for Flutter build."
else
  echo "Supabase config missing for Flutter build; auth providers will be disabled."
fi

"${FLUTTER_BIN}" pub get
"${FLUTTER_BIN}" build web --release --no-wasm-dry-run --base-href=/ \
  --dart-define=APP_ENV="${APP_ENV:-production}" \
  --dart-define=USE_MOCK_DATA="${USE_MOCK_DATA:-true}" \
  --dart-define=SUPABASE_URL="${RESOLVED_SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${RESOLVED_SUPABASE_ANON_KEY}" \
  --dart-define=AI_SERVICE_BASE_URL="${AI_SERVICE_BASE_URL:-}"
