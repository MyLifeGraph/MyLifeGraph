#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

cd "$ROOT_DIR/apps/mobile"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build web --debug --no-wasm-dry-run
