#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
bash -n scripts/start_frontend.sh
bash -n scripts/lib/local_supabase_migrations.sh
bash -n scripts/lib/local_supabase_database_safety.sh
bash -n scripts/lib/vercel_build_environment.sh
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
bash -n scripts/verify_source.sh
bash -n scripts/verify_supabase_local.sh
bash -n scripts/verify_web.sh
bash -n scripts/verify_affected.sh
bash -n scripts/vercel_build.sh
bash -n scripts/update_python_requirements.sh
bash -n scripts/cleanup_local_e2e_users.sh
bash -n scripts/seed_demo_data.sh
for vps_script in deploy/vps/bin/*.sh; do
  bash -n "$vps_script"
done
for backup_script in deploy/backup/bin/*.sh; do
  bash -n "$backup_script"
done
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
node --check scripts/verify_vercel_build_identity.mjs
node --check scripts/verify_vercel_build_identity.test.mjs
node --check scripts/write_web_csp.mjs
node --check scripts/write_web_csp.test.mjs
node --check scripts/vercel_build_config.test.mjs
node --check scripts/verify_staging_remote.mjs
node --check scripts/verify_staging_remote.test.mjs
node --check scripts/staging_scenario_manifest.mjs
node --check scripts/generate_staging_scenarios.mjs
node --check scripts/generate_staging_scenarios.test.mjs
node --check scripts/configure_pilot_participation_gate.mjs
node --check scripts/configure_pilot_participation_gate.test.mjs
node --check scripts/android_release_identity.mjs
node --check scripts/android_release_identity.test.mjs
node --check scripts/check_android_release_config.mjs
node --check scripts/check_android_release_config.test.mjs
node --check apps/mobile/web/turnstile_challenge.js
node --check scripts/turnstile_challenge.test.mjs
node --test scripts/check_docs_consistency.test.mjs
node --test scripts/check_frontend_visual_contract.test.mjs
node --test scripts/check_e2e_split_contract.test.mjs
node --test scripts/seed_demo_contract.test.mjs
node --test e2e/web/support/local-auth-users.test.mjs
node --test scripts/cleanup_local_e2e_users.test.mjs
node --test scripts/verify_affected.test.mjs
node --test scripts/verify_fast.test.mjs
node --test scripts/write_hosted_flutter_defines.test.mjs
node --test scripts/verify_vercel_build_identity.test.mjs
node --test scripts/write_web_csp.test.mjs
node --test scripts/vercel_build_config.test.mjs
node --test scripts/verify_staging_remote.test.mjs
node --test scripts/generate_staging_scenarios.test.mjs
node --test scripts/configure_pilot_participation_gate.test.mjs
node --test scripts/android_release_identity.test.mjs
node --test scripts/check_android_release_config.test.mjs
node --test scripts/turnstile_challenge.test.mjs
node scripts/check_docs_consistency.mjs
node scripts/check_frontend_visual_contract.mjs
node scripts/check_e2e_split_contract.mjs
node scripts/check_android_release_config.mjs

python3 -m py_compile scripts/seed_student_feature_data.py
python3 -m py_compile scripts/generate_brand_assets.py
python3 -m unittest discover -s deploy/vps/tests -p 'test_*.py'
python3 -m unittest discover -s deploy/backup/tests -p 'test_*.py'
git diff --check
