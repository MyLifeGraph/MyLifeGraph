#!/usr/bin/env bash
set -euo pipefail

# No frontend dependency, tool bootstrap, define helper, or compiler process may
# inherit backend-only credentials from a misconfigured build environment.
unset SUPABASE_SECRET_KEY SUPABASE_SERVICE_ROLE_KEY SCHEDULED_REFRESH_TOKEN

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
node ../../scripts/write_hosted_flutter_defines.mjs "${MLG_DEFINES_FILE}"
"${FLUTTER_BIN}" build web --release --no-wasm-dry-run --base-href=/ \
  --dart-define-from-file="${MLG_DEFINES_FILE}"
