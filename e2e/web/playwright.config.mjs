import path from 'node:path';

import { defineConfig } from 'playwright/test';

const suite = process.env.E2E_SUITE ?? 'full';
const suiteGrep = {
  smoke:
    /@(auth-capture-today|planner-confirm|authority|account-controls|coach|personal-learning)\b/,
  'new-full':
    /@(auth-capture-today|planner-confirm|authority|account-controls|coach|personal-learning)\b/,
  full: undefined,
};
if (!(suite in suiteGrep)) {
  throw new Error(`Unknown E2E_SUITE: ${suite}`);
}

const artifactDir = path.resolve(
  process.env.E2E_ARTIFACT_DIR ?? '.tools/e2e/playwright',
);

export default defineConfig({
  testDir: './journeys',
  outputDir: path.join(artifactDir, 'playwright'),
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30 * 60 * 1000,
  globalTimeout: 45 * 60 * 1000,
  expect: { timeout: 15000 },
  grep: suiteGrep[suite],
  reporter: [
    ['line'],
    ['./support/duration-reporter.mjs'],
  ],
  use: {
    headless: process.env.HEADED !== 'true',
    viewport: { width: 1280, height: 960 },
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },
});
