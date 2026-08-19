#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
VERIFY_TMP_DIR="$(mktemp -d /tmp/mylifegraph-verify-fast.XXXXXX)"

cleanup() {
  rm -rf "$VERIFY_TMP_DIR"
}
trap cleanup EXIT

if [[ -n "${AI_SERVICE_PYTHON:-}" ]]; then
  PYTHON_BIN="$AI_SERVICE_PYTHON"
elif [[ -x "$ROOT_DIR/services/ai_service/.venv/bin/python" ]]; then
  PYTHON_BIN="$ROOT_DIR/services/ai_service/.venv/bin/python"
else
  PYTHON_BIN="${PYTHON_BIN:-python3}"
fi

run_source_checks() {
  cd "$ROOT_DIR"
  bash -n scripts/start_frontend.sh
  bash -n scripts/lib/local_supabase_migrations.sh
  bash -n scripts/lib/local_supabase_database_safety.sh
  bash -n scripts/lib/goal_removal_migration_harness.sh
  bash -n scripts/lib/exam_plan_health_migration_harness.sh
  bash -n scripts/lib/multi_exam_plan_migration_harness.sh
  bash -n scripts/lib/recommendation_retirement_migration_harness.sh
  bash -n scripts/backup_local_supabase.sh
  bash -n scripts/reset_local_supabase.sh
  bash -n scripts/test_local_supabase_migrations.sh
  bash -n scripts/start_local_stack.sh
  bash -n scripts/test_start_local_stack.sh
  bash -n scripts/e2e_web.sh
  bash -n scripts/test_e2e_web_process_ownership.sh
  bash -n scripts/verify.sh
  bash -n scripts/verify_fast.sh
  bash -n scripts/verify_supabase_local.sh
  bash -n scripts/verify_web.sh
  bash -n scripts/verify_affected.sh
  bash -n scripts/vercel_build.sh
  bash -n scripts/update_python_requirements.sh
  bash -n scripts/cleanup_local_e2e_users.sh
  bash -n scripts/seed_demo_data.sh
  bash scripts/test_local_supabase_migrations.sh
  bash scripts/test_start_local_stack.sh
  bash scripts/test_e2e_web_process_ownership.sh

  node --check scripts/check_docs_consistency.mjs
  node --check scripts/check_docs_consistency.test.mjs
  node --check scripts/check_frontend_visual_contract.mjs
  node --check scripts/check_frontend_visual_contract.test.mjs
  node --check scripts/check_e2e_split_contract.mjs
  node --check scripts/check_e2e_split_contract.test.mjs
  node --check scripts/seed_demo_data.mjs
  node --check scripts/seed_demo_contract.mjs
  node --check scripts/seed_demo_contract.test.mjs
  node --check e2e/web/playwright.config.mjs
  node --check e2e/web/fixtures/e2e.fixture.mjs
  node --check e2e/web/support/api-client.mjs
  node --check e2e/web/support/db-client.mjs
  node --check e2e/web/support/duration-reporter.mjs
  node --check e2e/web/support/flutter-ui.mjs
  for spec in e2e/web/journeys/*.spec.mjs; do
    node --check "$spec"
  done
  node --check e2e/web/support/local-auth-users.mjs
  node --check scripts/cleanup_local_e2e_users.mjs
  node --check scripts/verify_affected.mjs
  node --check scripts/lib/supabase_deployment.mjs
  node --check scripts/write_hosted_flutter_defines.mjs
  node --check scripts/write_hosted_flutter_defines.test.mjs
  node --check scripts/verify_staging_remote.mjs
  node --check scripts/verify_staging_remote.test.mjs
  node --check scripts/staging_scenario_manifest.mjs
  node --check scripts/generate_staging_scenarios.mjs
  node --check scripts/generate_staging_scenarios.test.mjs
  node --test scripts/check_docs_consistency.test.mjs
  node --test scripts/check_frontend_visual_contract.test.mjs
  node --test scripts/check_e2e_split_contract.test.mjs
  node --test scripts/seed_demo_contract.test.mjs
  node --test e2e/web/support/local-auth-users.test.mjs
  node --test scripts/cleanup_local_e2e_users.test.mjs
  node --test scripts/verify_affected.test.mjs
  node --test scripts/write_hosted_flutter_defines.test.mjs
  node --test scripts/verify_staging_remote.test.mjs
  node --test scripts/generate_staging_scenarios.test.mjs
  node scripts/check_docs_consistency.mjs
  node scripts/check_frontend_visual_contract.mjs
  node scripts/check_e2e_split_contract.mjs

  python3 -m py_compile scripts/seed_student_feature_data.py
  python3 -m py_compile scripts/generate_brand_assets.py
  git diff --check
}

run_flutter_checks() {
  cd "$ROOT_DIR/apps/mobile"
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" analyze
  "$FLUTTER_BIN" test
}

run_backend_checks() {
  cd "$ROOT_DIR"
  "$PYTHON_BIN" -m compileall -q services/ai_service/app
  cd "$ROOT_DIR/services/ai_service"
  "$PYTHON_BIN" -m ruff check app tests
  "$PYTHON_BIN" -m pytest
}

run_source_checks >"$VERIFY_TMP_DIR/source.log" 2>&1 &
source_pid=$!
run_flutter_checks >"$VERIFY_TMP_DIR/flutter.log" 2>&1 &
flutter_pid=$!
run_backend_checks >"$VERIFY_TMP_DIR/backend.log" 2>&1 &
backend_pid=$!

status=0
for group in source flutter backend; do
  pid_variable="${group}_pid"
  pid="${!pid_variable}"
  if ! wait "$pid"; then
    status=1
  fi
  printf '\n== verify:fast %s ==\n' "$group"
  sed -n '1,$p' "$VERIFY_TMP_DIR/$group.log"
done

if [[ "$status" -ne 0 ]]; then
  echo "verify:fast failed." >&2
  exit "$status"
fi

echo "verify:fast passed."
