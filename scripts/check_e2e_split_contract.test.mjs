import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import { findE2eSplitContractErrors } from './check_e2e_split_contract.mjs';

function writeFixture(root, path, contents = '') {
  const target = join(root, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
}

test('E2E split guard rejects a legacy oracle and API-only journey', () => {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-e2e-split-'));
  try {
    for (const name of [
      'account-controls',
      'auth-capture-today',
      'coach',
      'personal-learning',
      'planner-confirm',
      'setup-onboarding',
    ]) {
      writeFixture(
        root,
        `e2e/web/journeys/${name}.spec.mjs`,
        name === 'coach'
          ? `test('@${name} API only', async ({ e2e }) => {});`
          : `test('@${name} UI', async ({ page, e2e }) => {
              await e2e.signInUi();
              await expectFlutterText(page, 'Visible');
            });`,
      );
    }
    writeFixture(root, 'e2e/web/legacy-full.mjs', 'legacy');
    writeFixture(
      root,
      'e2e/web/playwright.config.mjs',
      'setup-onboarding auth-capture-today planner-confirm coach full: undefined',
    );
    writeFixture(root, 'scripts/e2e_web.sh');
    writeFixture(root, 'scripts/verify_fast.sh');
    writeFixture(root, 'package.json');

    const errors = findE2eSplitContractErrors(root);
    assert.ok(errors.some((error) => error.includes('monolithic oracle')));
    assert.ok(
      errors.some(
        (error) =>
          error.includes('coach.spec.mjs') &&
          error.includes('browser page'),
      ),
    );
    assert.ok(
      errors.some(
        (error) =>
          error.includes('coach.spec.mjs') &&
          error.includes('Flutter assertion'),
      ),
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
