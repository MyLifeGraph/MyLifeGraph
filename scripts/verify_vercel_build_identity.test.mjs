import assert from 'node:assert/strict';
import test from 'node:test';

import { verifyVercelEnvironment } from './verify_vercel_build_identity.mjs';

const sha = 'a'.repeat(40);
const pilot = {
  VERCEL: '1',
  VERCEL_ENV: 'production',
  VERCEL_GIT_REPO_OWNER: 'MyLifeGraph',
  VERCEL_GIT_REPO_SLUG: 'MyLifeGraph',
  VERCEL_GIT_COMMIT_SHA: sha,
  VERCEL_GIT_COMMIT_REF: 'main',
  APP_ENV: 'pilot',
  APP_BUILD_SHA: sha,
  APP_RELEASE_TAG: `main-${sha}`,
};
const checkout = { headSha: sha };

test('pilot identity binds Vercel production to protected main and its SHA', () => {
  assert.deepEqual(verifyVercelEnvironment(pilot, checkout), {
    appEnvironment: 'pilot',
    appSha: sha,
    ref: 'main',
  });
  for (const environment of [
    { ...pilot, VERCEL: '' },
    { ...pilot, VERCEL_ENV: 'preview' },
    { ...pilot, VERCEL_GIT_COMMIT_REF: 'feature' },
    { ...pilot, VERCEL_GIT_COMMIT_SHA: 'b'.repeat(40) },
    { ...pilot, VERCEL_GIT_REPO_OWNER: 'attacker' },
  ]) {
    assert.throws(() => verifyVercelEnvironment(environment, checkout));
  }
  assert.throws(() =>
    verifyVercelEnvironment(
      { ...pilot, APP_RELEASE_TAG: `main-${'b'.repeat(40)}` },
      checkout,
    ),
  );
});

test('staging identity is isolated to a non-main preview', () => {
  const staging = {
    ...pilot,
    APP_ENV: 'staging',
    VERCEL_ENV: 'preview',
    VERCEL_GIT_COMMIT_REF: 'staging-candidate',
    APP_RELEASE_TAG: `preview-${sha}`,
  };
  assert.equal(
    verifyVercelEnvironment(staging, checkout).appEnvironment,
    'staging',
  );
  assert.throws(() =>
    verifyVercelEnvironment(
      { ...staging, VERCEL_GIT_COMMIT_REF: 'main' },
      checkout,
    ),
  );
  assert.throws(() =>
    verifyVercelEnvironment(
      { ...staging, APP_RELEASE_TAG: `preview-${'b'.repeat(40)}` },
      checkout,
    ),
  );
});
