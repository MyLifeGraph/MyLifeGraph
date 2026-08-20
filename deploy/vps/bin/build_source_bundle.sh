#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

fail() {
  printf 'Source bundle error: %s\n' "$1" >&2
  exit 1
}

[[ "$#" -eq 2 ]] || fail "usage: build_source_bundle.sh <rc-tag> <output-directory>"
release_tag="$1"
output_dir="$2"
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+-rc\.[0-9]+$ ]] ||
  fail "release tag must be an exact pilot RC tag"
[[ "$output_dir" = /* ]] || fail "output directory must be absolute"

cd "$ROOT_DIR"
[[ -z "$(git status --porcelain=v1)" ]] || fail "checkout must be clean"
[[ "$(git cat-file -t "refs/tags/$release_tag" 2>/dev/null || true)" == "tag" ]] ||
  fail "release tag must exist and be annotated"
release_sha="$(git rev-list -n 1 "$release_tag")"
[[ "$(git rev-parse HEAD)" == "$release_sha" ]] ||
  fail "HEAD must be the exact release tag SHA"
git rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1 ||
  fail "origin/main must exist; fetch and review remote state first"
git merge-base --is-ancestor "$release_sha" refs/remotes/origin/main ||
  fail "release tag must be contained in origin/main"

mkdir -p "$output_dir"
resolved_output="$(realpath -e "$output_dir")"
case "$resolved_output/" in
  "$ROOT_DIR"/*) fail "output directory must be outside the repository" ;;
esac

archive_name="mylifegraph-${release_tag}.tar.gz"
manifest_name="mylifegraph-${release_tag}.source.json"
archive_path="$resolved_output/$archive_name"
manifest_path="$resolved_output/$manifest_name"
[[ ! -e "$archive_path" && ! -e "$manifest_path" ]] ||
  fail "release artifacts already exist and are immutable"

temporary_archive="$(mktemp "$resolved_output/.${archive_name}.XXXXXX")"
cleanup() {
  rm -f -- "$temporary_archive"
}
trap cleanup EXIT

git archive \
  --format=tar.gz \
  --prefix="mylifegraph-${release_tag}/" \
  --output="$temporary_archive" \
  "$release_tag"
mv -- "$temporary_archive" "$archive_path"
commit_epoch="$(git show -s --format=%ct "$release_sha")"
created_at="$(python3 - "$commit_epoch" <<'PY'
from datetime import UTC, datetime
import sys

print(datetime.fromtimestamp(int(sys.argv[1]), UTC).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
python3 "$ROOT_DIR/deploy/vps/bin/release_manifest.py" create \
  --repo-root "$ROOT_DIR" \
  --archive "$archive_path" \
  --tag "$release_tag" \
  --sha "$release_sha" \
  --created-at "$created_at" \
  --output "$manifest_path"
chmod 0644 "$archive_path" "$manifest_path"
printf 'Created immutable source bundle: %s\n' "$archive_path"
printf 'Created source manifest: %s\n' "$manifest_path"
