import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import {
  ALL_JOURNEYS,
  SMOKE_JOURNEYS,
  isKnownJourney,
  journeyTagPattern,
} from '../e2e/web/journey-manifest.mjs';
import { findE2eSplitContractErrors } from './check_e2e_split_contract.mjs';

function writeFixture(root, path, contents = '') {
  const target = join(root, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
}

test('journey manifest keeps exact full, smoke, and named selection', () => {
  assert.equal(new Set(ALL_JOURNEYS).size, 8);
  assert.equal(new Set(SMOKE_JOURNEYS).size, 4);
  assert.ok(SMOKE_JOURNEYS.every((name) => isKnownJourney(name)));
  const smokePattern = journeyTagPattern(SMOKE_JOURNEYS);
  assert.equal(smokePattern.test('@coach visible UI'), true);
  assert.equal(smokePattern.test('@account-controls visible UI'), false);
  assert.equal(isKnownJourney('legacy-full'), false);
});

test('E2E split guard rejects a legacy oracle and API-only journey', () => {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-e2e-split-'));
  try {
    for (const name of ALL_JOURNEYS) {
      writeFixture(
        root,
        `e2e/web/journeys/${name}.spec.mjs`,
        name === 'coach'
          ? `test('@${name} API only', async ({ page, e2e }) => {
              // await e2e.signInUi();
              const fake = 'expectFlutterText(page, "Visible")';
              await e2e.api.request('/v1/health');
            });`
          : `test('@${name} UI', async ({ page, e2e }) => {
              await e2e.signInUi();
              await expectFlutterText(page, 'Visible');
            });`,
      );
    }
    writeFixture(root, 'e2e/web/legacy-full.mjs', 'legacy');
    writeFixture(root, 'e2e/web/journey-manifest.mjs');
    writeFixture(
      root,
      'e2e/web/playwright.config.mjs',
      'ALL_JOURNEYS SMOKE_JOURNEYS journeyTagPattern full: undefined',
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
          error.includes('authenticate through Flutter'),
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
