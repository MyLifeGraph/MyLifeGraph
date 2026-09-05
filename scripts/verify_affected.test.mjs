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
    ['verify:source', 'verify:backend'],
  );
  assert.deepEqual(
    classifyAffectedPaths([
      'apps/mobile/lib/features/planner/presentation/planner_page.dart',
    ]).commands,
    ['verify:source', 'verify:flutter', 'verify:web'],
  );
});

test('escalates core, auth, routing, config, schema, and unknown changes', () => {
  for (const path of [
    'apps/mobile/lib/core/config/app_config.dart',
    'apps/mobile/lib/features/auth/data/auth_repository.dart',
    'apps/mobile/lib/core/routing/app_router.dart',
    'package-lock.json',
    'deploy/vps/systemd/mylifegraph-api.service',
    'scripts/configure_pilot_participation_gate.mjs',
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
    ['verify:source', 'verify:flutter', 'verify:web'],
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

test('presentation constants narrow only local checks, including accompanying docs', () => {
  for (const name of ['app_spacing', 'app_radii']) {
    const path = `apps/mobile/lib/core/constants/${name}.dart`;
    const result = classifyAffectedPaths([path, 'docs/frontend-visual-system-v2.md']);
    assert.deepEqual(result.commands, ['verify:source', 'verify:flutter', 'verify:web']);
    assert.equal(result.classification, 'core+docs');
    assert.deepEqual(selectCiGates(result), { web: true, db: false, fullE2e: true });
    for (const broader of [
      'apps/mobile/lib/core/config/app_config.dart',
      'apps/mobile/lib/core/constants/new_constant.dart',
      'apps/mobile/lib/features/auth/data/auth_repository.dart',
      'services/ai_service/app/services/planner_service.py',
      'services/ai_service/app/api/routes/planner.py',
      'supabase/migrations/20260905000000_example.sql',
      'package.json',
      'unknown.file',
    ]) {
      assert.deepEqual(classifyAffectedPaths([path, broader]).commands, ['verify:full'], broader);
    }
  }
});

test('empty, ordinary backend and routing retain their previous CI gates', () => {
  const cases = [
    [[], [], { web: false, db: false, fullE2e: false }],
    [['services/ai_service/app/services/local_time.py'],
      ['verify:source', 'verify:backend'], { web: false, db: false, fullE2e: false }],
    [['services/ai_service/app/api/routes/planner.py'],
      ['verify:full'], { web: false, db: false, fullE2e: true }],
  ];
  for (const [paths, commands, ci] of cases) {
    const result = classifyAffectedPaths(paths);
    assert.deepEqual(result.commands, commands);
    assert.deepEqual(selectCiGates(result), ci);
  }
});
