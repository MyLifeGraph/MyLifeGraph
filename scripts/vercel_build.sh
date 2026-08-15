#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.0}"
MLG_FLUTTER_CACHE_ROOT="${VERCEL_CACHE_DIR:-/tmp/mylifegraph-vercel-cache}/flutter"
MLG_FLUTTER_HOME="${MLG_FLUTTER_CACHE_ROOT}/${FLUTTER_VERSION}"

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  if [ ! -x "${MLG_FLUTTER_HOME}/bin/flutter" ]; then
    rm -rf "${MLG_FLUTTER_HOME}"
    mkdir -p "${MLG_FLUTTER_CACHE_ROOT}"
    git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git "${MLG_FLUTTER_HOME}"
  fi

  export PATH="${MLG_FLUTTER_HOME}/bin:${PATH}"
  FLUTTER_BIN="${MLG_FLUTTER_HOME}/bin/flutter"
fi

"${FLUTTER_BIN}" --version
"${FLUTTER_BIN}" config --enable-web

cd apps/mobile

"${FLUTTER_BIN}" pub get
MLG_DEFINES_FILE="$(mktemp)"
trap 'rm -f "${MLG_DEFINES_FILE}"' EXIT
export MLG_DEFINES_FILE
node -e 'const fs=require("fs"); fs.writeFileSync(process.env.MLG_DEFINES_FILE, JSON.stringify({APP_ENV:process.env.APP_ENV||"production",USE_MOCK_DATA:process.env.USE_MOCK_DATA||"false",SUPABASE_URL:process.env.SUPABASE_URL||"",SUPABASE_ANON_KEY:process.env.SUPABASE_ANON_KEY||"",AI_SERVICE_BASE_URL:process.env.AI_SERVICE_BASE_URL||"",COACH_SURFACE_ENABLED:process.env.COACH_SURFACE_ENABLED||""}))'
"${FLUTTER_BIN}" build web --release --no-wasm-dry-run --base-href=/ \
  --dart-define-from-file="${MLG_DEFINES_FILE}"
