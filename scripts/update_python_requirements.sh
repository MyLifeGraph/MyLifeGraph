#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DIR="$ROOT_DIR/services/ai_service"
PYTHON_BIN="${PYTHON_BIN:-python3}"
EXPECTED_PIP_TOOLS_VERSION="7.5.1"

if [[ "$#" -gt 1 || ("$#" -eq 1 && "$1" != "--upgrade") ]]; then
  echo "Usage: scripts/update_python_requirements.sh [--upgrade]" >&2
  exit 2
fi

python_version="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$python_version" != "3.12" ]]; then
  echo "Python 3.12 is required to update the AI service requirement locks." >&2
  exit 1
fi

pip_tools_version="$(
  "$PYTHON_BIN" -c \
    'from importlib.metadata import version; print(version("pip-tools"))' \
    2>/dev/null || true
)"
if [[ "$pip_tools_version" != "$EXPECTED_PIP_TOOLS_VERSION" ]]; then
  echo \
    "Install pip-tools==$EXPECTED_PIP_TOOLS_VERSION in the selected Python environment." \
    >&2
  exit 1
fi

compile_args=(
  --generate-hashes
  --resolver=backtracking
  --strip-extras
)
if [[ "${1:-}" == "--upgrade" ]]; then
  compile_args+=(--upgrade)
fi

cd "$SERVICE_DIR"
"$PYTHON_BIN" -m piptools compile \
  "${compile_args[@]}" \
  --output-file=requirements.txt \
  pyproject.toml
"$PYTHON_BIN" -m piptools compile \
  "${compile_args[@]}" \
  --extra=test \
  --output-file=requirements-dev.txt \
  pyproject.toml
"$PYTHON_BIN" -m piptools compile \
  "${compile_args[@]}" \
  --output-file=coach_analysis/requirements.txt \
  coach_analysis/requirements.in
