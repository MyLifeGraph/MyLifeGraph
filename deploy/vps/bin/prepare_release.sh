#!/bin/bash
set -Eeuo pipefail

umask 027
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_MODE="${MYLIFEGRAPH_VPS_TEST_MODE:-}"

fail() {
  printf 'Release preparation error: %s\n' "$1" >&2
  exit 1
}

verify_root_owned_helper() {
  local helper="$1"
  [[ -e "$helper" && ! -L "$helper" && "$(stat -c '%u' "$helper")" -eq 0 ]] ||
    fail "installed release helper ownership is invalid"
  local helper_mode
  helper_mode="$(stat -c '%a' "$helper")"
  (( (8#$helper_mode & 022) == 0 )) ||
    fail "installed release helper is group/other writable"
}

if [[ "$(id -u)" -eq 0 ]]; then
  [[ "$TEST_MODE" != "1" ]] ||
    fail "test mode is forbidden for privileged release preparation"
  PYTHON_BIN=/usr/bin/python3.12
  SETPRIV_BIN=/usr/bin/setpriv
  BUILD_USER=mylifegraph-build
  BUILD_ROOT=/srv/mylifegraph-build
  RELEASE_ROOT=/srv/mylifegraph
  [[ "$(realpath -e "$SCRIPT_DIR")" == "/usr/local/libexec/mylifegraph" ]] ||
    fail "privileged preparation must use the installed helper suite"
  for helper in "$SCRIPT_DIR" "$SCRIPT_DIR/prepare_release.sh" \
    "$SCRIPT_DIR/analysis_image_revision.py" \
    "$SCRIPT_DIR/release_manifest.py" "$SCRIPT_DIR/release_tree.py"; do
    verify_root_owned_helper "$helper"
  done
  [[ -x "$SETPRIV_BIN" ]] || fail "setpriv is unavailable"
  BUILD_UID="$(id -u "$BUILD_USER")" || fail "release build user is missing"
  BUILD_GID="$(id -g "$BUILD_USER")" || fail "release build group is missing"
  [[ "$BUILD_UID" =~ ^[1-9][0-9]*$ && "$BUILD_GID" =~ ^[1-9][0-9]*$ ]] ||
    fail "release build identity is invalid"
  [[ "$(id -G "$BUILD_USER")" == "$BUILD_GID" ]] ||
    fail "release build user must have no supplementary groups"
  [[ "$(stat -c '%a:%U:%G' "$BUILD_ROOT")" == "710:root:$BUILD_USER" ]] ||
    fail "release build workspace mode or ownership is invalid"
  pgrep -u "$BUILD_UID" >/dev/null 2>&1 &&
    fail "release build user already owns a running process"
else
  [[ "$TEST_MODE" == "1" ]] ||
    fail "production release preparation must run as root"
  PYTHON_BIN="${MYLIFEGRAPH_PYTHON_BIN:-}"
  SETPRIV_BIN=""
  BUILD_UID="$(id -u)"
  BUILD_GID="$(id -g)"
  RELEASE_ROOT="${MYLIFEGRAPH_ROOT:-}"
  BUILD_ROOT="${MYLIFEGRAPH_BUILD_ROOT:-$RELEASE_ROOT/.build-work}"
fi

run_clean() {
  if [[ "$TEST_MODE" == "1" ]]; then
    "$@"
  else
    /usr/bin/env -i PATH="$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 "$@"
  fi
}

run_build() {
  local status=0
  if [[ "$TEST_MODE" == "1" ]]; then
    /usr/bin/env -i PATH="$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
      PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1 "$@" || status=$?
  else
    /usr/bin/env -i PATH="$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
      PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1 \
      "$SETPRIV_BIN" --no-new-privs --bounding-set=-all \
      --inh-caps=-all --ambient-caps=-all --clear-groups \
      --regid "$BUILD_GID" --reuid "$BUILD_UID" -- "$@" || status=$?
    pkill -KILL -u "$BUILD_UID" >/dev/null 2>&1 || true
    pgrep -u "$BUILD_UID" >/dev/null 2>&1 &&
      fail "release build process survived its bounded step"
  fi
  return "$status"
}

analysis_image_environment() {
  local source_root="$1"
  local revision
  revision="$(
    run_clean "$PYTHON_BIN" \
      "$SCRIPT_DIR/analysis_image_revision.py" \
      "$source_root/services/ai_service/coach_analysis"
  )"
  [[ "$revision" =~ ^[0-9a-f]{64}$ ]] ||
    fail "analysis image revision is invalid"
  printf 'COACH_ANALYSIS_IMAGE=mylifegraph-coach-analysis:sha256-%s' "$revision"
}

[[ "$#" -eq 2 ]] || fail "usage: prepare_release.sh <source-archive> <source-manifest>"
[[ ! -L "$1" && ! -L "$2" ]] || fail "release input paths must not be symlinks"
[[ "$RELEASE_ROOT" = /* ]] || fail "MYLIFEGRAPH_ROOT must be absolute"
if [[ "$RELEASE_ROOT" != "/srv/mylifegraph" ]]; then
  [[ "$TEST_MODE" == "1" ]] ||
    fail "a nonstandard root is allowed only in explicit test mode"
  [[ "$RELEASE_ROOT" == /tmp/mylifegraph-vps-test.* ]] ||
    fail "test root must use the bounded /tmp/mylifegraph-vps-test.* prefix"
fi
if [[ "$TEST_MODE" == "1" ]]; then
  [[ "$BUILD_ROOT" == "$RELEASE_ROOT/.build-work" ]] ||
    fail "test build root must remain below the bounded test root"
  mkdir -p "$BUILD_ROOT"
fi
if [[ "$TEST_MODE" != "1" ]]; then
  [[ -d /srv && ! -L /srv && "$(stat -c '%U' /srv)" == "root" ]] ||
    fail "/srv must be a root-owned real directory"
  srv_mode="$(stat -c '%a' /srv)"
  (( (8#$srv_mode & 022) == 0 )) || fail "/srv must not be group/other writable"
  [[ "$(stat -c '%a:%U:%G' "$RELEASE_ROOT")" == "750:root:mylifegraph-release" ]] ||
    fail "release root mode or ownership is invalid"
  [[ "$(stat -c '%a:%U:%G' "$RELEASE_ROOT/incoming")" == "700:root:root" ]] ||
    fail "release incoming directory mode or ownership is invalid"
fi

lock_path="$RELEASE_ROOT/.prepare.lock"
if [[ -e "$lock_path" || -L "$lock_path" ]]; then
  [[ -f "$lock_path" && ! -L "$lock_path" ]] || fail "preparation lock is invalid"
  if [[ "$TEST_MODE" != "1" ]]; then
    [[ "$(stat -c '%u' "$lock_path")" -eq 0 ]] ||
      fail "preparation lock must be root-owned"
  fi
fi
exec 9>"$lock_path"
flock -n 9 || fail "another release preparation is active"

archive="$(realpath -e "$1")"
manifest="$(realpath -e "$2")"
for input in "$archive" "$manifest"; do
  [[ -f "$input" && ! -L "$input" ]] || fail "release input must be a regular file"
  if [[ "$TEST_MODE" != "1" ]]; then
    [[ "$(dirname "$input")" == "/srv/mylifegraph/incoming" ]] ||
      fail "release inputs must be installed in the root-private incoming directory"
    [[ "$(stat -c '%a:%U:%G:%h' "$input")" == "400:root:root:1" ]] ||
      fail "release inputs must be single-link root-owned mode 0400 files"
  fi
done
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python 3.12 is unavailable"
command -v tar >/dev/null 2>&1 || fail "tar is unavailable"

run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" verify \
  --archive "$archive" \
  --manifest "$manifest"
release_tag="$(
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name release_tag
)"
release_sha="$(
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name release_sha
)"
release_migration_head="$(
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name migration_head
)"
release_migration_count="$(
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name migration_count
)"
release_migration_identity_sha256="$(
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name migration_identity_sha256
)"
expected_release_environment="$(
  printf 'APP_BUILD_SHA=%s\nAPP_RELEASE_TAG=%s\nAPP_MIGRATION_HEAD=%s\nAPP_MIGRATION_COUNT=%s\nAPP_MIGRATION_IDENTITY_SHA256=%s' \
    "$release_sha" "$release_tag" "$release_migration_head" \
    "$release_migration_count" "$release_migration_identity_sha256"
)"
releases_dir="$RELEASE_ROOT/releases"
target="$releases_dir/$release_tag"
mkdir -p "$releases_dir"

manifest_digest="$(sha256sum "$manifest" | awk '{print $1}')"
if [[ -e "$target" || -L "$target" ]]; then
  [[ -d "$target" && ! -L "$target" ]] ||
    fail "existing release target is not a real directory"
  recorded="$target/.mylifegraph-source-manifest.json"
  [[ -f "$recorded" ]] || fail "existing release has no source manifest"
  [[ "$(sha256sum "$recorded" | awk '{print $1}')" == "$manifest_digest" ]] ||
    fail "existing release has a different immutable manifest"
  [[ -f "$target/.mylifegraph-release.env" ]] ||
    fail "existing release has no runtime identity"
  [[ "$(cat "$target/.mylifegraph-release.env")" == "$expected_release_environment" ]] ||
    fail "existing release runtime identity differs from its manifest"
  expected_executor_environment="$(analysis_image_environment "$target")"
  [[ -f "$target/.mylifegraph-executor-release.env" ]] ||
    fail "existing release has no executor image identity"
  [[ "$(cat "$target/.mylifegraph-executor-release.env")" == "$expected_executor_environment" ]] ||
    fail "existing release executor image identity differs from its sources"
  tree_args=(verify --release "$target")
  if [[ "$TEST_MODE" == "1" ]]; then
    tree_args+=(--test-mode)
  fi
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_tree.py" "${tree_args[@]}"
  [[ -x "$target/services/ai_service/.venv/bin/python" ]] ||
    fail "existing release is incomplete"
  printf 'Release is already prepared: %s\n' "$target"
  exit 0
fi

job_root="$(mktemp -d "$BUILD_ROOT/job.${release_tag}.XXXXXX")"
chown root:"$BUILD_GID" "$job_root" 2>/dev/null || true
chmod 0750 "$job_root"
cleanup() {
  case "$job_root" in
    "$BUILD_ROOT"/job.*) rm -rf -- "$job_root" ;;
    *) printf 'Refusing unsafe cleanup path.\n' >&2 ;;
  esac
}
trap cleanup EXIT

tar --extract --gzip --file "$archive" --directory "$job_root" \
  --no-same-owner --no-same-permissions
source_dir="$job_root/mylifegraph-$release_tag"
[[ -d "$source_dir/services/ai_service" ]] || fail "archive extraction is incomplete"
chown -hR root:"$BUILD_GID" "$source_dir" 2>/dev/null || true
chmod -R u=rX,g=rX,o= "$source_dir"
chmod u+w "$source_dir/services/ai_service"
mkdir "$source_dir/services/ai_service/.venv"
chmod u-w "$source_dir/services/ai_service"
chown "$BUILD_UID:$BUILD_GID" "$source_dir/services/ai_service/.venv"
chmod 0700 "$source_dir/services/ai_service/.venv"

run_build "$PYTHON_BIN" -m venv "$source_dir/services/ai_service/.venv"
run_build "$source_dir/services/ai_service/.venv/bin/python" -m pip install \
  --disable-pip-version-check \
  --require-hashes \
  --requirement "$source_dir/services/ai_service/requirements.txt"
run_build /usr/bin/env \
  PYTHONPYCACHEPREFIX="$source_dir/services/ai_service/.venv/pycache" \
  "$source_dir/services/ai_service/.venv/bin/python" -m compileall -q \
  "$source_dir/services/ai_service/app"
(
  cd "$source_dir/services/ai_service"
  run_build /usr/bin/env APP_ENV=development USE_MOCK_DATA=true \
    ./.venv/bin/python -c \
    'from app.main import create_app; assert create_app().docs_url == "/docs"'
)

# Generated identity files are written only after all untrusted build steps
# have ended. The candidate could write only its virtualenv, never these files
# or the archive-derived source and migrations.
chmod u+w "$source_dir"
cp -- "$manifest" "$source_dir/.mylifegraph-source-manifest.json"
printf '%s\n' "$expected_release_environment" > "$source_dir/.mylifegraph-release.env"
expected_executor_environment="$(analysis_image_environment "$source_dir")"
printf '%s\n' "$expected_executor_environment" \
  > "$source_dir/.mylifegraph-executor-release.env"
run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" verify \
  --archive "$archive" \
  --manifest "$source_dir/.mylifegraph-source-manifest.json"

if [[ "$TEST_MODE" == "1" ]]; then
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_tree.py" seal \
    --release "$source_dir" --test-mode
else
  chown -hR root:mylifegraph-release "$source_dir"
  chmod -R u=rX,g=rX,o= "$source_dir"
  run_clean "$PYTHON_BIN" "$SCRIPT_DIR/release_tree.py" seal --release "$source_dir"
  chown root:mylifegraph-release "$source_dir/.mylifegraph-tree.sha256"
  chmod 0440 "$source_dir/.mylifegraph-tree.sha256"
fi
mv -- "$source_dir" "$target"
trap - EXIT
rmdir -- "$job_root"
printf 'Prepared release without binding a live port: %s\n' "$target"
