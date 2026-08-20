#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'Permission verification error: %s\n' "$1" >&2
  exit 1
}

config_value() {
  local key="$1"
  local file="$2"
  local count
  count="$(grep -c "^${key}=" "$file" || true)"
  [[ "$count" -eq 1 ]] || fail "$file must define $key exactly once"
  sed -n "s/^${key}=//p" "$file"
}

[[ "$(id -u)" -eq 0 ]] || fail "run this check as root"
for user in deploy mylifegraph-api coach-executor; do
  id "$user" >/dev/null 2>&1 || fail "missing runtime user: $user"
done
[[ "$(id -u mylifegraph-api)" != "$(id -u coach-executor)" ]] ||
  fail "API and executor must have distinct UIDs"
[[ "$(stat -c '%a:%U:%G' /etc/mylifegraph/api.env)" == "640:root:mylifegraph-api" ]] ||
  fail "api.env mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /etc/mylifegraph/executor.env)" == "640:root:coach-executor" ]] ||
  fail "executor.env mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /srv/mylifegraph)" == "750:root:mylifegraph-release" ]] ||
  fail "release root mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /srv/mylifegraph/releases)" == "750:root:mylifegraph-release" ]] ||
  fail "release directory mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /srv/mylifegraph/incoming)" == "700:root:root" ]] ||
  fail "release incoming mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /var/lib/mylifegraph-api)" == "750:mylifegraph-api:mylifegraph-api" ]] ||
  fail "API state directory mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /var/lib/mylifegraph-coach)" == "700:coach-executor:coach-executor" ]] ||
  fail "executor state directory mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /var/lib/mylifegraph-coach/codex-home)" == "700:coach-executor:coach-executor" ]] ||
  fail "Codex home mode or ownership is wrong"
[[ "$(stat -c '%a:%U:%G' /var/lib/mylifegraph-coach/tmp)" == "700:coach-executor:coach-executor" ]] ||
  fail "executor temporary directory mode or ownership is wrong"
runuser -u deploy -- test ! -w /srv/mylifegraph ||
  fail "deploy can modify the release root or current symlink"
runuser -u deploy -- test ! -w /srv/mylifegraph/releases ||
  fail "deploy can create an unsealed release"
runuser -u deploy -- test ! -r /srv/mylifegraph/incoming ||
  fail "deploy can read root-private release inputs"
runuser -u deploy -- test ! -w /srv/mylifegraph/incoming ||
  fail "deploy can replace root-private release inputs"

api_uid="$(id -u mylifegraph-api)"
executor_uid="$(id -u coach-executor)"
[[ "$(config_value COACH_EXECUTOR_ALLOWED_API_UID /etc/mylifegraph/executor.env)" == "$api_uid" ]] ||
  fail "executor peer UID does not match mylifegraph-api"
expected_runtime_dir="/run/user/$executor_uid"
[[ "$(config_value XDG_RUNTIME_DIR /etc/mylifegraph/executor.env)" == "$expected_runtime_dir" ]] ||
  fail "executor XDG runtime directory does not match coach-executor"
[[ "$(config_value COACH_ANALYSIS_DOCKER_HOST /etc/mylifegraph/executor.env)" == "unix://$expected_runtime_dir/docker.sock" ]] ||
  fail "executor Docker host does not match coach-executor"
if grep -q '^COACH_ANALYSIS_IMAGE=' /etc/mylifegraph/executor.env; then
  fail "mutable executor.env must not select an analysis image"
fi

runuser -u mylifegraph-api -- test -r /etc/mylifegraph/api.env ||
  fail "API user cannot read api.env"
runuser -u mylifegraph-api -- test ! -r /etc/mylifegraph/executor.env ||
  fail "API user can read executor.env"
runuser -u coach-executor -- test -r /etc/mylifegraph/executor.env ||
  fail "executor cannot read executor.env"
runuser -u coach-executor -- test ! -r /etc/mylifegraph/api.env ||
  fail "executor can read api.env"
runuser -u deploy -- test ! -r /etc/mylifegraph/api.env ||
  fail "deploy user can read api.env"
runuser -u deploy -- test ! -r /etc/mylifegraph/executor.env ||
  fail "deploy user can read executor.env"
runuser -u mylifegraph-api -- test ! -x /var/lib/mylifegraph-coach/codex-home ||
  fail "API user can traverse the Codex home"
runuser -u coach-executor -- test ! -x /var/lib/mylifegraph-api ||
  fail "executor can traverse API state"
docker_socket="/run/user/$(id -u coach-executor)/docker.sock"
[[ -S "$docker_socket" ]] || fail "executor rootless Docker socket is missing"
[[ "$(stat -c '%U' "$docker_socket")" == "coach-executor" ]] ||
  fail "rootless Docker socket has the wrong owner"
if runuser -u mylifegraph-api -- python3 -c \
  'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])' \
  "$docker_socket" 2>/dev/null; then
  fail "API user can connect to the executor Docker socket"
fi
runuser -u mylifegraph-api -- test -r /srv/mylifegraph/current/services/ai_service/app/main.py ||
  fail "API user cannot read the current release"
runuser -u coach-executor -- test -r /srv/mylifegraph/current/services/ai_service/app/main.py ||
  fail "executor cannot read the current release"
runuser -u mylifegraph-api -- test ! -w /srv/mylifegraph/current ||
  fail "API user can modify the current release"
runuser -u coach-executor -- test ! -w /srv/mylifegraph/current ||
  fail "executor can modify the current release"
executor_release_env=/srv/mylifegraph/current/.mylifegraph-executor-release.env
[[ -f "$executor_release_env" && ! -L "$executor_release_env" ]] ||
  fail "release-owned executor image identity is missing"
image_identity="$(config_value COACH_ANALYSIS_IMAGE "$executor_release_env")"
[[ "$image_identity" =~ ^mylifegraph-coach-analysis:sha256-[0-9a-f]{64}$ ]] ||
  fail "release-owned executor image identity is invalid"
runuser -u coach-executor -- test -r "$executor_release_env" ||
  fail "executor cannot read its release image identity"
runuser -u coach-executor -- test ! -w "$executor_release_env" ||
  fail "executor can modify its release image identity"
printf 'Runtime permission matrix passed.\n'
