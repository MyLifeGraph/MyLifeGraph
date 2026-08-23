#!/usr/bin/env bash
set -Eeuo pipefail

usage="$(df -P / | awk 'NR == 2 {gsub(/%/, "", $5); print $5}')"
[[ "$usage" =~ ^[0-9]+$ && "$usage" -le 100 ]] || {
  printf '{"status":"error","code":"disk_measurement_failed"}\n' >&2
  exit 1
}

level="ok"
exit_status=0
if ((usage >= 90)); then
  level="critical"
  exit_status=2
elif ((usage >= 80)); then
  level="error"
  exit_status=1
elif ((usage >= 70)); then
  level="warning"
fi
printf '{"status":"%s","root_disk_percent":%d}\n' "$level" "$usage"
exit "$exit_status"
