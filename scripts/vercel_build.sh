#!/usr/bin/env bash
set -Eeuo pipefail

# No frontend dependency, tool bootstrap, define helper, or compiler process may
# inherit backend-only credentials from a misconfigured build environment.
source scripts/lib/vercel_build_environment.sh

readonly FLUTTER_VERSION='3.44.0'
readonly FLUTTER_COMMIT='559ffa3f75e7402d65a8def9c28389a9b2e6fe42'
readonly FLUTTER_ARCHIVE_SHA256='e1ec95e6c550458a34de93580cb85dac24da0e9bedb9bb42811f050ac5a0c7d5'
readonly FLUTTER_ARCHIVE_URL='https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.0-stable.tar.xz'
readonly MLG_FLUTTER_CACHE_ROOT='.vercel/cache/flutter'
readonly MLG_FLUTTER_ARCHIVE="${MLG_FLUTTER_CACHE_ROOT}/flutter-${FLUTTER_VERSION}.tar.xz"

[[ "${VERCEL:-}" == '1' ]] || {
  printf 'Vercel build error: VERCEL must be exactly 1.\n' >&2
  exit 1
}
for tool in node git curl sha256sum tar; do
  resolved="$(command -v -- "${tool}" 2>/dev/null || true)"
  [[ "${resolved}" == /* && -x "${resolved}" ]] || {
    printf 'Vercel build error: required system tool is unavailable: %s.\n' "${tool}" >&2
    exit 1
  }
  resolved="$(/usr/bin/readlink -f -- "${resolved}")"
  case "${resolved}" in
    "${PWD}"/*|/tmp/*|/var/tmp/*|/home/*)
      printf 'Vercel build error: refusing an untrusted system tool path: %s.\n' "${tool}" >&2
      exit 1
      ;;
  esac
  tool_uid="$(/usr/bin/stat -c '%u' -- "${resolved}")"
  tool_mode="$(/usr/bin/stat -c '%a' -- "${resolved}")"
  [[ "${tool_uid}" == '0' && "${tool_mode}" =~ ^[0-7]{3,4}$ ]] || {
    printf 'Vercel build error: system tool ownership is invalid: %s.\n' "${tool}" >&2
    exit 1
  }
  (( (8#${tool_mode} & 022) == 0 )) || {
    printf 'Vercel build error: system tool is group/world writable: %s.\n' "${tool}" >&2
    exit 1
  }
  tool_parent="${resolved%/*}"
  while [[ -n "${tool_parent}" ]]; do
    parent_uid="$(/usr/bin/stat -c '%u' -- "${tool_parent}")"
    parent_mode="$(/usr/bin/stat -c '%a' -- "${tool_parent}")"
    [[ "${parent_uid}" == '0' && "${parent_mode}" =~ ^[0-7]{3,4}$ ]] || {
      printf 'Vercel build error: system tool parent ownership is invalid: %s.\n' "${tool}" >&2
      exit 1
    }
    (( (8#${parent_mode} & 022) == 0 )) || {
      printf 'Vercel build error: system tool parent is group/world writable: %s.\n' "${tool}" >&2
      exit 1
    }
    [[ "${tool_parent}" == '/' ]] && break
    tool_parent="${tool_parent%/*}"
    [[ -n "${tool_parent}" ]] || tool_parent='/'
  done
  printf -v "${tool^^}_BIN" '%s' "${resolved}"
done
PATH='/usr/local/bin:/usr/bin:/bin'
export PATH

build_home="$(mktemp -d /tmp/mylifegraph-vercel-home.XXXXXX)"
readonly VERCEL_BUILD_HOME="${build_home}"
VERCEL_BUILD_PATH='/usr/local/bin:/usr/bin:/bin'
readonly VERCEL_PUB_CACHE="${PWD}/.vercel/cache/pub"
export VERCEL_BUILD_HOME VERCEL_BUILD_PATH VERCEL_PUB_CACHE
archive_tmp=""
sdk_tmp=""
defines_file=""
cleanup() {
  if [[ -n "${archive_tmp}" ]]; then rm -f -- "${archive_tmp}"; fi
  if [[ -n "${defines_file}" ]]; then rm -f -- "${defines_file}"; fi
  if [[ -n "${sdk_tmp}" ]]; then
    case "${sdk_tmp}" in
      /tmp/mylifegraph-vercel-flutter.*) rm -rf -- "${sdk_tmp}" ;;
      *) printf 'Refusing unsafe Flutter temp cleanup.\n' >&2 ;;
    esac
  fi
  if [[ -n "${build_home}" ]]; then
    case "${build_home}" in
      /tmp/mylifegraph-vercel-home.*) rm -rf -- "${build_home}" ;;
      *) printf 'Refusing unsafe Flutter HOME cleanup.\n' >&2 ;;
    esac
  fi
}
trap cleanup EXIT
vercel_run_public "${NODE_BIN}" scripts/verify_vercel_build_identity.mjs

mkdir -p "${MLG_FLUTTER_CACHE_ROOT}"
if ! printf '%s  %s\n' "${FLUTTER_ARCHIVE_SHA256}" "${MLG_FLUTTER_ARCHIVE}" |
  vercel_run_clean "${SHA256SUM_BIN}" --check --strict --status 2>/dev/null; then
  archive_tmp="$(mktemp "${MLG_FLUTTER_CACHE_ROOT}/.flutter-archive.XXXXXX")"
  vercel_run_clean "${CURL_BIN}" --disable --silent --show-error --fail --location \
    --output "${archive_tmp}" "${FLUTTER_ARCHIVE_URL}"
  printf '%s  %s\n' "${FLUTTER_ARCHIVE_SHA256}" "${archive_tmp}" |
    vercel_run_clean "${SHA256SUM_BIN}" --check --strict
  mv -- "${archive_tmp}" "${MLG_FLUTTER_ARCHIVE}"
  archive_tmp=""
fi

sdk_tmp="$(mktemp -d /tmp/mylifegraph-vercel-flutter.XXXXXX)"
vercel_run_clean "${TAR_BIN}" -xJf "${MLG_FLUTTER_ARCHIVE}" -C "${sdk_tmp}"
readonly MLG_FLUTTER_HOME="${sdk_tmp}/flutter"
readonly FLUTTER_BIN="${MLG_FLUTTER_HOME}/bin/flutter"
[[ -x "${FLUTTER_BIN}" ]] || {
  printf 'Vercel build error: pinned Flutter archive is incomplete.\n' >&2
  exit 1
}
[[ "$(vercel_run_clean "${GIT_BIN}" -C "${MLG_FLUTTER_HOME}" rev-parse HEAD)" == "${FLUTTER_COMMIT}" ]] || {
  printf 'Vercel build error: Flutter archive commit differs from the pin.\n' >&2
  exit 1
}

VERCEL_BUILD_PATH="${MLG_FLUTTER_HOME}/bin:/usr/local/bin:/usr/bin:/bin"
export VERCEL_BUILD_PATH
vercel_run_public "${FLUTTER_BIN}" --version
vercel_run_public "${FLUTTER_BIN}" config --enable-web

cd apps/mobile

vercel_run_public "${FLUTTER_BIN}" pub get --enforce-lockfile
defines_file="$(mktemp)"
vercel_run_public "${NODE_BIN}" ../../scripts/write_hosted_flutter_defines.mjs "${defines_file}"
vercel_run_public "${FLUTTER_BIN}" build web --release --no-wasm-dry-run --base-href=/ \
  --no-web-resources-cdn --csp \
  --dart-define-from-file="${defines_file}"
cd ../..
vercel_run_public "${NODE_BIN}" scripts/write_web_csp.mjs apps/mobile/build/web/index.html
