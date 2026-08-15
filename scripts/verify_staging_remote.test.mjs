import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ExactRemoteAuthUsers,
  EXPECTED_MIGRATION,
  stagingTarget,
  stagingTargetFingerprint,
} from './verify_staging_remote.mjs';

const environment = {
  STAGING_PROJECT_REF: 'abcdefghijklmnopqrst',
  STAGING_SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co/',
  STAGING_AI_SERVICE_BASE_URL: 'https://coach-staging.example.test/',
};

test('staging target is exact, HTTPS-only, and fingerprint-bound', () => {
  const target = stagingTarget(environment);
  assert.deepEqual(target, {
    projectRef: 'abcdefghijklmnopqrst',
    supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
    aiServiceBaseUrl: 'https://coach-staging.example.test',
    expectedMigration: EXPECTED_MIGRATION,
  });
  assert.match(
    stagingTargetFingerprint(target),
    /^staging-target-[0-9a-f]{16}$/,
  );
  assert.notEqual(
    stagingTargetFingerprint(target),
    stagingTargetFingerprint({
      ...target,
      aiServiceBaseUrl: 'https://other.example.test',
    }),
  );
});

test('staging target rejects host mismatch and insecure endpoints', () => {
  assert.throws(
    () =>
      stagingTarget({
        ...environment,
        STAGING_PROJECT_REF: 'bbbbbbbbbbbbbbbbbbbb',
      }),
    /does not match/,
  );
  assert.throws(
    () =>
      stagingTarget({
        ...environment,
        STAGING_SUPABASE_URL: 'http://abcdefghijklmnopqrst.supabase.co',
      }),
    /HTTPS/,
  );
  assert.throws(
    () =>
      stagingTarget({
        ...environment,
        STAGING_AI_SERVICE_BASE_URL:
          'https://user:secret@coach-staging.example.test',
      }),
    /credential-free/,
  );
});

test('remote cleanup deletes and verifies only registered exact user ids', async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, method: options.method ?? 'GET' });
    return new Response(null, {
      status: options.method === 'DELETE' ? 204 : 404,
    });
  };
  const users = new ExactRemoteAuthUsers({
    supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
    serviceRoleKey: 'service-role-test-value',
    fetchImpl,
  });
  users.userIds.push('11111111-1111-4111-8111-111111111111');
  users.userIds.push('22222222-2222-4222-8222-222222222222');

  assert.equal(await users.cleanup(), 2);
  assert.deepEqual(
    calls.map(({ method, url }) => `${method} ${new URL(url).pathname}`),
    [
      'DELETE /auth/v1/admin/users/22222222-2222-4222-8222-222222222222',
      'GET /auth/v1/admin/users/22222222-2222-4222-8222-222222222222',
      'DELETE /auth/v1/admin/users/11111111-1111-4111-8111-111111111111',
      'GET /auth/v1/admin/users/11111111-1111-4111-8111-111111111111',
    ],
  );
});
