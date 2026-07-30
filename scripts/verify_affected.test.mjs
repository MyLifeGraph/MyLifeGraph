import assert from 'node:assert/strict';
import test from 'node:test';

import {
  classifyAffectedPaths,
  classifyPath,
  selectCiGates,
} from './verify_affected.mjs';

test('classifies ordinary docs, backend, and Flutter changes narrowly', () => {
  assert.equal(classifyPath('docs/verification.md').category, 'docs');
  assert.deepEqual(
    classifyAffectedPaths(['docs/verification.md']).commands,
    ['verify:docs', 'verify:visual'],
  );
  assert.deepEqual(
    classifyAffectedPaths(['services/ai_service/app/main.py']).commands,
    ['verify:fast'],
  );
  assert.deepEqual(
    classifyAffectedPaths([
      'apps/mobile/lib/features/planner/presentation/planner_page.dart',
    ]).commands,
    ['verify:fast', 'verify:web'],
  );
});

test('escalates core, auth, routing, config, schema, and unknown changes', () => {
  for (const path of [
    'apps/mobile/lib/core/config/app_config.dart',
    'apps/mobile/lib/features/auth/data/auth_repository.dart',
    'apps/mobile/lib/core/routing/app_router.dart',
    'package-lock.json',
    'supabase/migrations/20260730000000_example.sql',
    'unclassified.file',
  ]) {
    assert.deepEqual(
      classifyAffectedPaths([path]).commands,
      ['verify:full'],
      path,
    );
  }
});

test('escalates cross-stack changes but ignores accompanying docs as a stack', () => {
  assert.equal(
    classifyAffectedPaths([
      'apps/mobile/lib/features/planner/presentation/planner_page.dart',
      'services/ai_service/app/main.py',
    ]).classification,
    'mixed',
  );
  assert.deepEqual(
    classifyAffectedPaths([
      'apps/mobile/lib/features/planner/presentation/planner_page.dart',
      'docs/planner-v1-contract.md',
    ]).commands,
    ['verify:fast', 'verify:web'],
  );
});

test('selects conditional CI web, database, and full-E2E gates', () => {
  assert.deepEqual(
    selectCiGates(
      classifyAffectedPaths([
        'apps/mobile/lib/features/planner/presentation/planner_page.dart',
      ]),
    ),
    { web: true, db: false, fullE2e: false },
  );
  assert.deepEqual(
    selectCiGates(
      classifyAffectedPaths([
        'supabase/migrations/20260730000000_example.sql',
      ]),
    ),
    { web: false, db: true, fullE2e: true },
  );
  assert.equal(
    selectCiGates(
      classifyAffectedPaths([
        'apps/mobile/lib/features/planner/presentation/planner_page.dart',
        'services/ai_service/app/main.py',
      ]),
    ).fullE2e,
    true,
  );
});
