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
  APP_RELEASE_TAG: 'v0.1.0-pilot.1-rc.1',
};
const taggedCheckout = { headSha: sha, tagType: 'tag', tagSha: sha };

test('pilot identity binds Vercel, protected main, SHA, and annotated RC tag', () => {
  assert.deepEqual(verifyVercelEnvironment(pilot, taggedCheckout), {
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
    assert.throws(() => verifyVercelEnvironment(environment, taggedCheckout));
  }
  assert.throws(() =>
    verifyVercelEnvironment(pilot, { ...taggedCheckout, tagType: 'commit' }),
  );
  assert.throws(() =>
    verifyVercelEnvironment(pilot, {
      ...taggedCheckout,
      tagSha: 'b'.repeat(40),
    }),
  );
});

test('staging identity is isolated to a non-main preview', () => {
  const staging = {
    ...pilot,
    APP_ENV: 'staging',
    VERCEL_ENV: 'preview',
    VERCEL_GIT_COMMIT_REF: 'staging-candidate',
  };
  assert.equal(
    verifyVercelEnvironment(staging, {
      headSha: sha,
      tagType: null,
      tagSha: null,
    }).appEnvironment,
    'staging',
  );
  assert.throws(() =>
    verifyVercelEnvironment(
      { ...staging, VERCEL_GIT_COMMIT_REF: 'main' },
      taggedCheckout,
    ),
  );
});
