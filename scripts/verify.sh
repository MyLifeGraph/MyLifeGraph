#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

cd "$ROOT_DIR"

bash -n scripts/start_frontend.sh

cd "$ROOT_DIR/apps/mobile"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test

cd "$ROOT_DIR"
python3 -m compileall services/ai_service/app
git diff --check
