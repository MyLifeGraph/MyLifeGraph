#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF=""
DRY_RUN=false
JSON=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --base-ref)
      if [[ "$#" -lt 2 ]]; then
        echo "--base-ref requires a Git ref." >&2
        exit 64
      fi
      BASE_REF="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --json)
      JSON=true
      shift
      ;;
    *)
      echo "Unknown verify:affected argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$BASE_REF" ]]; then
  echo "--base-ref <ref> is required." >&2
  exit 64
fi

cd "$ROOT_DIR"
git rev-parse --verify "${BASE_REF}^{commit}" >/dev/null

changed_paths_file="$(mktemp /tmp/mylifegraph-affected.XXXXXX)"
cleanup() {
  rm -f "$changed_paths_file"
}
trap cleanup EXIT

{
  git diff --name-only --diff-filter=ACMRD "${BASE_REF}...HEAD"
  git diff --name-only --diff-filter=ACMRD
  git diff --cached --name-only --diff-filter=ACMRD
  git ls-files --others --exclude-standard
} | sed '/^$/d' | sort -u >"$changed_paths_file"

if [[ "$JSON" == "true" ]]; then
  node scripts/verify_affected.mjs --json <"$changed_paths_file"
else
  node scripts/verify_affected.mjs --human <"$changed_paths_file"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  exit 0
fi

mapfile -t commands < <(
  node scripts/verify_affected.mjs --commands <"$changed_paths_file"
)
for command in "${commands[@]}"; do
  npm run "$command"
done
