#!/bin/bash
set -Eeuo pipefail

umask 027
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_MODE="${MYLIFEGRAPH_VPS_TEST_MODE:-}"

fail() {
  printf 'Release promotion error: %s\n' "$1" >&2
  exit 1
}

run_python() {
  if [[ "$TEST_MODE" == "1" ]]; then
    "$@"
  else
    /usr/bin/env -i PATH="$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 "$@"
  fi
}

verify_root_owned_helper() {
  local helper="$1"
  [[ -e "$helper" && ! -L "$helper" && "$(stat -c '%u' "$helper")" -eq 0 ]] ||
    fail "installed helper ownership is invalid"
  local helper_mode
  helper_mode="$(stat -c '%a' "$helper")"
  (( (8#$helper_mode & 022) == 0 )) ||
    fail "installed helper is group/other writable"
}

if [[ "$(id -u)" -eq 0 ]]; then
  [[ "$TEST_MODE" != "1" ]] ||
    fail "test mode is forbidden for the privileged helper"
  [[ "$#" -eq 1 ]] || fail "usage: promote_release.sh <rc-tag>"
  RELEASE_ROOT=/srv/mylifegraph
  SYSTEMCTL_BIN=/usr/bin/systemctl
  PYTHON_BIN=/usr/bin/python3.12
  HEALTH_ATTEMPTS=24
  HEALTH_DELAY_SECONDS=5
  HEALTH_CHECK_SCRIPT="$SCRIPT_DIR/health_check.py"
  RELEASE_TREE_SCRIPT="$SCRIPT_DIR/release_tree.py"
  [[ "$(realpath -e "$SCRIPT_DIR")" == "/usr/local/libexec/mylifegraph" ]] ||
    fail "privileged promotion must use the installed helper suite"
  for helper in "$SCRIPT_DIR" "$SCRIPT_DIR/promote_release.sh" \
    "$SCRIPT_DIR/health_check.py" "$SCRIPT_DIR/release_manifest.py" \
    "$SCRIPT_DIR/release_tree.py" "$SCRIPT_DIR/validate_public_origin.py"; do
    verify_root_owned_helper "$helper"
  done

  caddy_environment=/etc/mylifegraph/caddy.env
  [[ -f "$caddy_environment" && ! -L "$caddy_environment" ]] ||
    fail "root-owned Caddy environment is missing"
  [[ "$(stat -c '%u' "$caddy_environment")" -eq 0 ]] ||
    fail "Caddy environment must be root-owned"
  caddy_mode="$(stat -c '%a' "$caddy_environment")"
  (( (8#$caddy_mode & 022) == 0 )) ||
    fail "Caddy environment must not be group/other writable"
  host_count="$(grep -c '^MYLIFEGRAPH_API_HOST=' "$caddy_environment" || true)"
  [[ "$host_count" -eq 1 ]] ||
    fail "Caddy environment must define MYLIFEGRAPH_API_HOST exactly once"
  public_host="$(sed -n 's/^MYLIFEGRAPH_API_HOST=//p' "$caddy_environment")"
  public_origin="$(run_python "$PYTHON_BIN" "$SCRIPT_DIR/validate_public_origin.py" --host "$public_host")" ||
    fail "configured public API host is invalid"
else
  [[ "$TEST_MODE" == "1" ]] || fail "production promotion must run through sudo"
  [[ "$#" -eq 2 ]] ||
    fail "test usage: promote_release.sh <rc-tag> <public-api-origin>"
  RELEASE_ROOT="${MYLIFEGRAPH_ROOT:-}"
  SYSTEMCTL_BIN="${MYLIFEGRAPH_SYSTEMCTL_BIN:-}"
  PYTHON_BIN="${MYLIFEGRAPH_PYTHON_BIN:-python3}"
  HEALTH_ATTEMPTS="${MYLIFEGRAPH_HEALTH_ATTEMPTS:-1}"
  HEALTH_DELAY_SECONDS="${MYLIFEGRAPH_HEALTH_DELAY_SECONDS:-0}"
  HEALTH_CHECK_SCRIPT="${MYLIFEGRAPH_HEALTH_CHECK_SCRIPT:-}"
  RELEASE_TREE_SCRIPT="${MYLIFEGRAPH_RELEASE_TREE_SCRIPT:-$SCRIPT_DIR/release_tree.py}"
  public_origin="$2"
  run_python "$PYTHON_BIN" "$SCRIPT_DIR/validate_public_origin.py" \
    --origin "$public_origin" >/dev/null || fail "test public API origin is invalid"
fi

release_tag="$1"
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+-rc\.[0-9]+$ ]] ||
  fail "release tag must be an exact pilot RC tag"
[[ "$RELEASE_ROOT" = /* ]] || fail "MYLIFEGRAPH_ROOT must be absolute"
if [[ "$RELEASE_ROOT" != "/srv/mylifegraph" ]]; then
  [[ "$TEST_MODE" == "1" ]] ||
    fail "a nonstandard root is allowed only in explicit test mode"
  [[ "$RELEASE_ROOT" == /tmp/mylifegraph-vps-test.* ]] ||
    fail "test root must use the bounded /tmp/mylifegraph-vps-test.* prefix"
fi
if [[ "$HEALTH_CHECK_SCRIPT" != "$SCRIPT_DIR/health_check.py" ]]; then
  [[ "$TEST_MODE" == "1" ]] ||
    fail "a custom health checker is allowed only in explicit test mode"
  [[ "$HEALTH_CHECK_SCRIPT" == /tmp/mylifegraph-vps-test.* ]] ||
    fail "test health checker must use the bounded test prefix"
fi
if [[ "$RELEASE_TREE_SCRIPT" != "$SCRIPT_DIR/release_tree.py" ]]; then
  [[ "$TEST_MODE" == "1" ]] ||
    fail "a custom tree verifier is allowed only in explicit test mode"
  [[ "$RELEASE_TREE_SCRIPT" == /tmp/mylifegraph-vps-test.* ]] ||
    fail "test tree verifier must use the bounded test prefix"
fi
[[ "$SYSTEMCTL_BIN" = /* && -x "$SYSTEMCTL_BIN" ]] ||
  fail "systemctl executable is invalid"
[[ "$PYTHON_BIN" = /* && -x "$PYTHON_BIN" ]] || fail "Python executable is invalid"
[[ "$HEALTH_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail "health attempts are invalid"
[[ "$HEALTH_DELAY_SECONDS" =~ ^[0-9]+$ ]] || fail "health delay is invalid"

verify_release_tree() {
  local release="$1"
  local tree_args=(verify --release "$release")
  if [[ "$TEST_MODE" == "1" ]]; then
    tree_args+=(--test-mode)
  fi
  if ! run_python "$PYTHON_BIN" "$RELEASE_TREE_SCRIPT" "${tree_args[@]}"; then
    printf 'Release promotion error: prepared release tree verification failed\n' >&2
    return 1
  fi
}

if [[ "$TEST_MODE" != "1" ]]; then
  [[ "$(stat -c '%U:%G:%a' "$RELEASE_ROOT")" == "root:mylifegraph-release:750" ]] ||
    fail "release root ownership or mode is invalid"
  [[ "$(stat -c '%U:%G:%a' "$RELEASE_ROOT/releases")" == "root:mylifegraph-release:750" ]] ||
    fail "release directory ownership or mode is invalid"
  for link_name in current previous; do
    link_path="$RELEASE_ROOT/$link_name"
    if [[ -e "$link_path" || -L "$link_path" ]]; then
      [[ -L "$link_path" && "$(stat -c '%u' "$link_path")" -eq 0 ]] ||
        fail "$link_name must be a root-owned symlink"
    fi
  done
fi

target="$RELEASE_ROOT/releases/$release_tag"
manifest="$target/.mylifegraph-source-manifest.json"
[[ -d "$target" && ! -L "$target" && -f "$manifest" && ! -L "$manifest" ]] ||
  fail "prepared release is missing"
verify_release_tree "$target" || fail "candidate release tree is invalid"
release_sha="$(
  run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name release_sha
)"
manifest_tag="$(
  run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name release_tag
)"
[[ "$manifest_tag" == "$release_tag" ]] || fail "installed manifest tag differs"
release_migration_head="$(
  run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name migration_head
)"
release_migration_count="$(
  run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name migration_count
)"
release_migration_identity_sha256="$(
  run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field \
    --manifest "$manifest" --name migration_identity_sha256
)"
DELETION_RECOVERY_BOUNDARY="20260820170000_account_deletion_recovery_v2.sql"
PARTICIPATION_GATE_BOUNDARY="20260820150000_pilot_participation_rls_gate_v1.sql"
HOSTED_DATABASE_ATTESTATION_BOUNDARY="20260820190000_hosted_database_contract_v1.sql"

run_systemctl() {
  if [[ "$TEST_MODE" == "1" ]]; then
    "$SYSTEMCTL_BIN" "$@"
  else
    /usr/bin/env -i PATH="$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
      "$SYSTEMCTL_BIN" "$@"
  fi
}

switch_link() {
  local link_name="$1"
  local link_target="$2"
  local link_path="$RELEASE_ROOT/$link_name"
  local temporary="$RELEASE_ROOT/.${link_name}.new.$$"
  if [[ -e "$link_path" || -L "$link_path" ]]; then
    [[ -L "$link_path" ]] || return 1
  fi
  ln -s -- "$link_target" "$temporary" || return 1
  if ! mv -Tf -- "$temporary" "$link_path"; then
    unlink "$temporary" 2>/dev/null || true
    return 1
  fi
}

restart_runtime() {
  run_systemctl stop mylifegraph-api.service || return 1
  run_systemctl stop mylifegraph-coach-executor.service || return 1
  run_systemctl stop mylifegraph-coach-executor.socket || return 1
  run_systemctl start mylifegraph-coach-executor.socket || return 1
  run_systemctl start mylifegraph-coach-executor.service || return 1
  run_systemctl start mylifegraph-api.service || return 1
  run_systemctl is-active --quiet mylifegraph-coach-executor.socket || return 1
  run_systemctl is-active --quiet mylifegraph-coach-executor.service || return 1
  run_systemctl is-active --quiet mylifegraph-api.service || return 1
}

check_release() {
  local tag="$1"
  local sha="$2"
  local migration_head="$3"
  local migration_count="$4"
  local migration_identity_sha256="$5"
  local attempt
  for ((attempt = 1; attempt <= HEALTH_ATTEMPTS; attempt++)); do
    if run_python "$PYTHON_BIN" "$HEALTH_CHECK_SCRIPT" \
      --base-url http://127.0.0.1:8000 \
      --expected-sha "$sha" \
      --expected-tag "$tag" \
      --expected-migration-head "$migration_head" \
      --expected-migration-count "$migration_count" \
      --expected-migration-identity-sha256 "$migration_identity_sha256" &&
      run_python "$PYTHON_BIN" "$HEALTH_CHECK_SCRIPT" \
        --base-url "$public_origin" \
        --expected-sha "$sha" \
        --expected-tag "$tag" \
        --expected-migration-head "$migration_head" \
        --expected-migration-count "$migration_count" \
        --expected-migration-identity-sha256 "$migration_identity_sha256"; then
      return 0
    fi
    if ((attempt < HEALTH_ATTEMPTS)); then
      sleep "$HEALTH_DELAY_SECONDS"
    fi
  done
  return 1
}

read_database_contract() {
  local migration_head="$1"
  local migration_count="$2"
  local migration_identity_sha256="$3"
  run_python "$PYTHON_BIN" "$HEALTH_CHECK_SCRIPT" \
    --base-url http://127.0.0.1:8000 \
    --expected-migration-head "$migration_head" \
    --expected-migration-count "$migration_count" \
    --expected-migration-identity-sha256 "$migration_identity_sha256" \
    --database-contract-only
}

lock_path="$RELEASE_ROOT/.deploy.lock"
if [[ -e "$lock_path" || -L "$lock_path" ]]; then
  [[ -f "$lock_path" && ! -L "$lock_path" ]] || fail "deployment lock is invalid"
  if [[ "$TEST_MODE" != "1" ]]; then
    [[ "$(stat -c '%u' "$lock_path")" -eq 0 ]] || fail "deployment lock is not root-owned"
  fi
fi
exec 9>"$lock_path"
flock -n 9 || fail "another release operation is active"

old_target=""
old_tag=""
old_sha=""
old_migration_head=""
actual_db_migration_head=""
actual_db_migration_count=""
actual_db_migration_identity_sha256=""
rollback_compatible=1
current_link="$RELEASE_ROOT/current"
if [[ -e "$current_link" || -L "$current_link" ]]; then
  [[ -L "$current_link" ]] || fail "current is not a symlink"
  old_target="$(readlink -f "$current_link")"
  [[ "$old_target" == "$RELEASE_ROOT/releases/"* && -d "$old_target" && ! -L "$old_target" ]] ||
    fail "current symlink escapes the release directory"
  verify_release_tree "$old_target" || fail "current release tree is invalid"
  old_manifest="$old_target/.mylifegraph-source-manifest.json"
  old_tag="$(run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field --manifest "$old_manifest" --name release_tag)"
  old_sha="$(run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field --manifest "$old_manifest" --name release_sha)"
  old_migration_head="$(run_python "$PYTHON_BIN" "$SCRIPT_DIR/release_manifest.py" field --manifest "$old_manifest" --name migration_head)"
fi
[[ "$old_target" != "$target" ]] || fail "requested release is already current"
if [[ -n "$old_migration_head" && ( "$old_migration_head" > "$HOSTED_DATABASE_ATTESTATION_BOUNDARY" || "$old_migration_head" == "$HOSTED_DATABASE_ATTESTATION_BOUNDARY" ) ]]; then
  database_contract="$(read_database_contract \
    "$release_migration_head" "$release_migration_count" \
    "$release_migration_identity_sha256")" ||
    fail "current runtime cannot attest the database migration head"
  IFS=$'\t' read -r actual_db_migration_head actual_db_migration_count \
    actual_db_migration_identity_sha256 <<<"$database_contract"
else
  actual_db_migration_head="$release_migration_head"
  actual_db_migration_count="$release_migration_count"
  actual_db_migration_identity_sha256="$release_migration_identity_sha256"
fi
[[ "$actual_db_migration_head" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]] ||
  fail "attested database migration head is invalid"
[[ "$actual_db_migration_count" =~ ^[1-9][0-9]*$ ]] ||
  fail "attested database migration count is invalid"
[[ "$actual_db_migration_identity_sha256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "attested database migration identity is invalid"
[[ "$release_migration_head" < "$actual_db_migration_head" || "$release_migration_head" == "$actual_db_migration_head" ]] ||
  fail "target release requires migrations that are not attested"
if [[ "$release_migration_head" == "$actual_db_migration_head" ]]; then
  [[ "$release_migration_count" == "$actual_db_migration_count" &&
    "$release_migration_identity_sha256" == "$actual_db_migration_identity_sha256" ]] ||
    fail "target release migration inventory differs from the attested database"
fi
if [[ -n "$old_migration_head" && "$release_migration_head" > "$old_migration_head" ]]; then
  [[ "$release_migration_head" == "$actual_db_migration_head" ]] ||
    fail "forward promotion does not match the attested database head"
fi
if [[ -n "$old_migration_head" ]]; then
  for compatibility_boundary in \
    "$PARTICIPATION_GATE_BOUNDARY" \
    "$DELETION_RECOVERY_BOUNDARY" \
    "$HOSTED_DATABASE_ATTESTATION_BOUNDARY"; do
    if [[ "$old_migration_head" > "$compatibility_boundary" || "$old_migration_head" == "$compatibility_boundary" ]]; then
      [[ "$release_migration_head" > "$compatibility_boundary" || "$release_migration_head" == "$compatibility_boundary" ]] ||
        fail "rollback target predates an irreversible hosted database boundary"
    elif [[ "$release_migration_head" > "$compatibility_boundary" || "$release_migration_head" == "$compatibility_boundary" ]]; then
      rollback_compatible=0
    fi
  done
fi

switch_attempted=0
promotion_committed=0

stop_runtime_safely() {
  run_systemctl stop mylifegraph-api.service >/dev/null 2>&1 || true
  run_systemctl stop mylifegraph-coach-executor.service >/dev/null 2>&1 || true
  run_systemctl stop mylifegraph-coach-executor.socket >/dev/null 2>&1 || true
}

rollback_on_exit() {
  local status="$?"
  trap - EXIT
  if [[ "$status" -eq 0 || "$switch_attempted" -ne 1 || "$promotion_committed" -eq 1 ]]; then
    exit "$status"
  fi

  set +e
  printf 'Promotion failed after the current-link boundary; recovering.\n' >&2
  local rollback_ok=1
  if [[ -n "$old_target" && "$rollback_compatible" -eq 1 ]]; then
    verify_release_tree "$old_target" || rollback_ok=0
    if [[ "$rollback_ok" -eq 1 ]]; then
      switch_link current "$old_target" || rollback_ok=0
    fi
    if [[ "$rollback_ok" -eq 1 ]]; then
      [[ "$(readlink -f "$current_link" 2>/dev/null)" == "$old_target" ]] ||
        rollback_ok=0
    fi
    if [[ "$rollback_ok" -eq 1 ]]; then
      verify_release_tree "$old_target" || rollback_ok=0
    fi
    if [[ "$rollback_ok" -eq 1 ]]; then
      restart_runtime || rollback_ok=0
    fi
    if [[ "$rollback_ok" -eq 1 ]]; then
      check_release "$old_tag" "$old_sha" "$actual_db_migration_head" \
        "$actual_db_migration_count" \
        "$actual_db_migration_identity_sha256" || rollback_ok=0
    fi
  else
    rollback_ok=0
  fi

  if [[ "$rollback_ok" -eq 1 ]]; then
    printf 'Prior release was restored and verified.\n' >&2
  else
    stop_runtime_safely
    current_target="$(readlink -f "$current_link" 2>/dev/null || true)"
    if [[ "$current_target" == "$target" && -L "$current_link" ]]; then
      unlink "$current_link" || true
    fi
    if [[ -n "$old_target" ]]; then
      if [[ "$rollback_compatible" -eq 0 ]]; then
        printf 'Prior release predates an irreversible hosted database boundary; runtime was stopped for fix-forward recovery.\n' >&2
      else
        printf 'Automatic rollback failed; runtime was stopped for operator recovery.\n' >&2
      fi
    else
      printf 'First deployment failed; runtime was stopped and the candidate link removed.\n' >&2
    fi
  fi
  exit "$status"
}
trap rollback_on_exit EXIT

if [[ -n "$old_target" ]]; then
  switch_link previous "$old_target" || fail "previous link switch failed"
fi
# The privileged parent and release directories make this verification stable;
# repeat it at the final switch boundary and again before any unit sees the link.
verify_release_tree "$target" || fail "candidate changed before promotion"
switch_attempted=1
switch_link current "$target" || fail "current link switch failed"
[[ "$(readlink -f "$current_link")" == "$target" ]] || fail "current link switch failed"
verify_release_tree "$target" || fail "candidate changed after promotion"

if restart_runtime && check_release "$release_tag" "$release_sha" \
  "$actual_db_migration_head" "$actual_db_migration_count" \
  "$actual_db_migration_identity_sha256"; then
  promotion_committed=1
  printf 'Release promoted and verified: %s\n' "$release_tag"
  exit 0
fi
fail "candidate failed runtime or health verification"
