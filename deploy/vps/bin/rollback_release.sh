#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${MYLIFEGRAPH_VPS_TEST_MODE:-}" == "1" ]]; then
  [[ "$#" -eq 2 ]] || {
    printf 'test usage: rollback_release.sh <known-good-rc-tag> <public-api-origin>\n' >&2
    exit 64
  }
  exec "$SCRIPT_DIR/promote_release.sh" "$1" "$2"
fi
[[ "$#" -eq 1 ]] || {
  printf 'usage: rollback_release.sh <known-good-rc-tag>\n' >&2
  exit 64
}
exec sudo -n /usr/local/libexec/mylifegraph/promote_release.sh "$1"
