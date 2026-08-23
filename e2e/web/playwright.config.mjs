import path from 'node:path';

import { defineConfig } from 'playwright/test';

import {
  ALL_JOURNEYS,
  SMOKE_JOURNEYS,
  journeyTagPattern,
} from './journey-manifest.mjs';

const suite = process.env.E2E_SUITE ?? 'full';
const suiteGrep = {
  smoke: journeyTagPattern(SMOKE_JOURNEYS),
  full: undefined,
};
if (!(suite in suiteGrep)) {
  throw new Error(`Unknown E2E_SUITE: ${suite}`);
}
const journey = process.env.E2E_JOURNEY ?? '';
const knownJourneys = new Set(ALL_JOURNEYS);
if (journey !== '' && !knownJourneys.has(journey)) {
  throw new Error(`Unknown E2E_JOURNEY: ${journey}`);
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
  grep: journey === '' ? suiteGrep[suite] : new RegExp(`@${journey}\\b`),
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
