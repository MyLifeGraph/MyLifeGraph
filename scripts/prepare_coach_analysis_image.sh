#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_DIR="$ROOT_DIR/services/ai_service/coach_analysis"
DOCKER_BIN="${COACH_ANALYSIS_DOCKER_BIN:-docker}"
IMAGE_OVERRIDE="${COACH_ANALYSIS_IMAGE:-}"
IMAGE=""
REVISION_LABEL="org.mylifegraph.coach-analysis.revision"

fail() {
  printf 'Coach analysis image error: %s\n' "$1" >&2
  exit 1
}

[[ -f "$CONTEXT_DIR/Dockerfile" && -f "$CONTEXT_DIR/requirements.txt" && -f "$CONTEXT_DIR/runner.py" ]] ||
  fail "The Coach analysis image sources are incomplete."

resolved_docker_bin="$(command -v -- "$DOCKER_BIN" 2>/dev/null || true)"
[[ -n "$resolved_docker_bin" && -x "$resolved_docker_bin" ]] ||
  fail "Docker is unavailable. Install or start Docker before using the live Coach."
"$resolved_docker_bin" version >/dev/null 2>&1 ||
  fail "Docker is unavailable. Start Docker before using the live Coach."

expected_revision="$(
  python3 "$ROOT_DIR/services/ai_service/app/analysis_image.py" "$CONTEXT_DIR"
)"
[[ "$expected_revision" =~ ^[a-f0-9]{64}$ ]] ||
  fail "Could not fingerprint the Coach analysis image sources."

release_environment="$ROOT_DIR/.mylifegraph-executor-release.env"
if [[ -e "$release_environment" || -L "$release_environment" ]]; then
  [[ -f "$release_environment" && ! -L "$release_environment" ]] ||
    fail "The release image identity is not a regular file."
  mapfile -t release_lines < "$release_environment"
  [[ "${#release_lines[@]}" -eq 1 ]] ||
    fail "The release image identity has an invalid shape."
  expected_image="mylifegraph-coach-analysis:sha256-$expected_revision"
  [[ "${release_lines[0]}" == "COACH_ANALYSIS_IMAGE=$expected_image" ]] ||
    fail "The release image identity does not match its sources."
  if [[ -n "$IMAGE_OVERRIDE" && "$IMAGE_OVERRIDE" != "$expected_image" ]]; then
    fail "COACH_ANALYSIS_IMAGE cannot override the release image identity."
  fi
  IMAGE="$expected_image"
else
  IMAGE="${IMAGE_OVERRIDE:-mylifegraph-coach-analysis:1}"
fi
[[ "$IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,255}$ ]] ||
  fail "COACH_ANALYSIS_IMAGE is malformed."

current_revision="$(
  "$resolved_docker_bin" image inspect \
    --format "{{ index .Config.Labels \"$REVISION_LABEL\" }}" \
    "$IMAGE" 2>/dev/null || true
)"

if [[ "$current_revision" != "$expected_revision" ]]; then
  printf 'Preparing isolated Coach analysis image %s ...\n' "$IMAGE"
  "$resolved_docker_bin" build \
    --build-arg "COACH_ANALYSIS_REVISION=$expected_revision" \
    --tag "$IMAGE" \
    "$CONTEXT_DIR"
fi

verified_revision="$(
  "$resolved_docker_bin" image inspect \
    --format "{{ index .Config.Labels \"$REVISION_LABEL\" }}" \
    "$IMAGE" 2>/dev/null || true
)"
[[ "$verified_revision" == "$expected_revision" ]] ||
  fail "The prepared Coach analysis image does not match the repository sources."

printf 'Coach analysis image is ready: %s (%s).\n' \
  "$IMAGE" "${expected_revision:0:12}"
