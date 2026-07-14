#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

cd "$ROOT_DIR"

bash -n scripts/start_frontend.sh
bash -n scripts/lib/local_supabase_migrations.sh
bash -n scripts/test_local_supabase_migrations.sh
bash -n scripts/start_local_stack.sh
bash -n scripts/test_start_local_stack.sh
bash -n scripts/e2e_web.sh
bash -n scripts/verify_supabase_local.sh
bash -n scripts/seed_demo_data.sh
bash scripts/test_local_supabase_migrations.sh
bash scripts/test_start_local_stack.sh
node --check scripts/seed_demo_data.mjs
node --check e2e/web/smoke.mjs

cd "$ROOT_DIR/apps/mobile"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test

cd "$ROOT_DIR"
python3 -m compileall services/ai_service/app
git diff --check
