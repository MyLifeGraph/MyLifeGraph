#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'VPS preflight error: %s\n' "$1" >&2
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

for command in python3.12 caddy systemctl systemd-analyze ss curl jq flock tar sha256sum setpriv pgrep pkill; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done
[[ -x /usr/local/libexec/mylifegraph-disk-monitor ]] ||
  fail "versioned disk monitor is not installed"
helper_dir=/usr/local/libexec/mylifegraph
for helper in prepare_release.sh promote_release.sh health_check.py analysis_image_revision.py release_manifest.py release_tree.py validate_public_origin.py install_codex_cli.py; do
  helper_path="$helper_dir/$helper"
  [[ -f "$helper_path" && ! -L "$helper_path" && -x "$helper_path" ]] ||
    fail "release helper is not installed: $helper"
  [[ "$(stat -c '%U:%G' "$helper_path")" == "root:root" ]] ||
    fail "release helper is not root-owned: $helper"
  helper_mode="$(stat -c '%a' "$helper_path")"
  (( (8#$helper_mode & 022) == 0 )) ||
    fail "release helper is group/other writable: $helper"
done
build_uid="$(id -u mylifegraph-build)" || fail "release build user is missing"
build_gid="$(id -g mylifegraph-build)" || fail "release build group is missing"
[[ "$build_uid" -gt 0 && "$build_gid" -gt 0 ]] ||
  fail "release build identity is invalid"
[[ "$(id -G mylifegraph-build)" == "$build_gid" ]] ||
  fail "release build user must have no supplementary groups"
[[ "$(getent passwd mylifegraph-build | cut -d: -f6-7)" == "/nonexistent:/usr/sbin/nologin" ]] ||
  fail "release build user must be locked to a nonexistent home"
[[ "$(stat -c '%a:%U:%G' /srv/mylifegraph-build)" == "710:root:mylifegraph-build" ]] ||
  fail "release build workspace ownership/mode is invalid"
pgrep -u "$build_uid" >/dev/null 2>&1 &&
  fail "release build user must be idle outside preparation"
codex_manifest="$helper_dir/manifests/codex-cli.json"
[[ -f "$codex_manifest" && ! -L "$codex_manifest" ]] ||
  fail "Codex installer manifest is not installed"
[[ "$(stat -c '%U:%G:%a' "$codex_manifest")" == "root:root:444" ]] ||
  fail "Codex installer manifest ownership/mode is invalid"

[[ -r /etc/os-release ]] || fail "OS release metadata is unavailable"
[[ "$(config_value APP_ENV /etc/mylifegraph/api.env)" == "pilot" ]] ||
  fail "VPS api.env must use exact APP_ENV=pilot"
python3 - /etc/mylifegraph/api.env <<'PY'
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

path = Path(sys.argv[1])
values = {}
for line in path.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    if key in values:
        raise SystemExit(f"duplicate protected API setting: {key}")
    values[key] = value

required = {
    "ACCOUNT_DELETION_JOURNAL_S3_URL",
    "ACCOUNT_DELETION_JOURNAL_S3_REGION",
    "ACCOUNT_DELETION_JOURNAL_S3_ACCESS_KEY_ID",
    "ACCOUNT_DELETION_JOURNAL_S3_SECRET_ACCESS_KEY",
    "ACCOUNT_DELETION_JOURNAL_S3_KMS_KEY_ARN",
}
if any(not values.get(name) for name in required):
    raise SystemExit("hosted deletion journal configuration is incomplete")
region = values["ACCOUNT_DELETION_JOURNAL_S3_REGION"]
parsed = urlsplit(values["ACCOUNT_DELETION_JOURNAL_S3_URL"])
host = parsed.hostname or ""
if (
    parsed.scheme != "https"
    or parsed.username is not None
    or parsed.password is not None
    or parsed.port is not None
    or parsed.path not in {"", "/"}
    or parsed.query
    or parsed.fragment
    or re.fullmatch(
        rf"[a-z0-9][a-z0-9-]{{1,61}}[a-z0-9]\.s3\.{re.escape(region)}\.amazonaws\.com",
        host,
    ) is None
):
    raise SystemExit("hosted deletion journal S3 URL is invalid")
if re.fullmatch(
    r"[A-Z0-9]{16,128}",
    values["ACCOUNT_DELETION_JOURNAL_S3_ACCESS_KEY_ID"],
) is None:
    raise SystemExit("hosted deletion journal access key id is invalid")
secret = values["ACCOUNT_DELETION_JOURNAL_S3_SECRET_ACCESS_KEY"]
if not 40 <= len(secret) <= 256 or secret.strip() != secret:
    raise SystemExit("hosted deletion journal secret shape is invalid")
kms = values["ACCOUNT_DELETION_JOURNAL_S3_KMS_KEY_ARN"]
if re.fullmatch(
    rf"arn:aws:kms:{re.escape(region)}:[0-9]{{12}}:key/[0-9a-f-]{{36}}",
    kms,
) is None:
    raise SystemExit("hosted deletion journal KMS ARN is invalid")
PY
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] ||
  fail "the reviewed baseline is Ubuntu 24.04"

cpu_count="$(getconf _NPROCESSORS_ONLN)"
memory_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
free_kib="$(df -Pk /srv/mylifegraph | awk 'NR == 2 {print $4}')"
[[ "$cpu_count" -ge 4 ]] || fail "fewer than four online CPU cores"
[[ "$memory_kib" -ge 7340032 ]] || fail "less than 7 GiB RAM"
[[ "$free_kib" -ge 15728640 ]] || fail "less than 15 GiB free release disk"
timedatectl show -p NTPSynchronized --value | grep -qx yes ||
  fail "NTP is not synchronized"

caddy_version="$(caddy version | sed -n 's/^v\([0-9][0-9.]*\).*/\1/p')"
python3 - "$caddy_version" <<'PY'
import sys
parts = tuple(int(value) for value in sys.argv[1].split("."))
if parts < (2, 10, 0):
    raise SystemExit("Caddy 2.10 or newer is required")
PY

systemd-analyze verify \
  /etc/systemd/system/mylifegraph-api.service \
  /etc/systemd/system/mylifegraph-coach-executor.socket \
  /etc/systemd/system/mylifegraph-coach-executor.service \
  /etc/systemd/system/mylifegraph-disk-monitor.service \
  /etc/systemd/system/mylifegraph-disk-monitor.timer
caddy adapt --config /etc/caddy/Caddyfile --validate >/dev/null

if ss -ltnH 'sport = :8000' | awk '{print $4}' | grep -Evq '^127\.0\.0\.1:8000$|^\[::1\]:8000$'; then
  fail "port 8000 has a non-loopback listener"
fi
if ss -ltnH | awk '{print $4}' | grep -Eq ':(2375|2376)$'; then
  fail "a Docker TCP API is listening"
fi

printf '{"status":"ok","cpu":%d,"memory_kib":%d,"root_free_kib":%d,"caddy":"%s"}\n' \
  "$cpu_count" "$memory_kib" "$free_kib" "$caddy_version"
