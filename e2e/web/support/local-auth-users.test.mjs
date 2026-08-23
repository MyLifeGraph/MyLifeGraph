import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createLocalAuthUserRegistry,
  requireLoopbackSupabaseUrl,
} from './local-auth-users.mjs';

const firstUserId = '11111111-1111-4111-8111-111111111111';
const secondUserId = '22222222-2222-4222-8222-222222222222';

test('requires an unauthenticated HTTP loopback Supabase URL', () => {
  assert.equal(
    requireLoopbackSupabaseUrl('http://127.0.0.1:54321/'),
    'http://127.0.0.1:54321',
  );
  assert.equal(
    requireLoopbackSupabaseUrl('http://localhost:54321'),
    'http://localhost:54321',
  );
  assert.throws(
    () => requireLoopbackSupabaseUrl('https://example.supabase.co'),
    /loopback/i,
  );
  assert.throws(
    () => requireLoopbackSupabaseUrl('http://user:password@localhost:54321'),
    /loopback/i,
  );
});

test('deletes only registered users and verifies their absence', async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, method: options.method ?? 'GET' });
    if (options.method === 'DELETE') {
      return new Response(null, { status: 204 });
    }
    return new Response('', { status: 404 });
  };
  const registry = createLocalAuthUserRegistry({
    supabaseUrl: 'http://127.0.0.1:54321',
    serviceRoleKey: 'test-key',
    fetchImpl,
  });
  registry.register(firstUserId);
  registry.register(firstUserId);
  registry.register(secondUserId);

  assert.deepEqual(await registry.cleanup(), {
    registered: 2,
    deleted: 2,
    alreadyAbsent: 0,
  });
  assert.deepEqual(
    calls.map(({ method, url }) => `${method} ${url}`),
    [
      `DELETE http://127.0.0.1:54321/rest/v1/focus_sessions?user_id=eq.${firstUserId}`,
      `DELETE http://127.0.0.1:54321/auth/v1/admin/users/${firstUserId}`,
      `GET http://127.0.0.1:54321/auth/v1/admin/users/${firstUserId}`,
      `DELETE http://127.0.0.1:54321/rest/v1/focus_sessions?user_id=eq.${secondUserId}`,
      `DELETE http://127.0.0.1:54321/auth/v1/admin/users/${secondUserId}`,
      `GET http://127.0.0.1:54321/auth/v1/admin/users/${secondUserId}`,
    ],
  );
});

test('accepts an already deleted registered user but fails a surviving user', async () => {
  let readBackStatus = 404;
  const fetchImpl = async (url, options = {}) => {
    if (url.includes('/rest/v1/focus_sessions')) {
      return new Response(null, { status: 204 });
    }
    if (options.method === 'DELETE') {
      return new Response('', { status: 404 });
    }
    return new Response('', { status: readBackStatus });
  };
  const registry = createLocalAuthUserRegistry({
    supabaseUrl: 'http://localhost:54321',
    serviceRoleKey: 'test-key',
    fetchImpl,
  });
  registry.register(firstUserId);
  assert.deepEqual(await registry.cleanup(), {
    registered: 1,
    deleted: 0,
    alreadyAbsent: 1,
  });

  readBackStatus = 200;
  await assert.rejects(registry.cleanup(), /remained readable/i);
});

test('rejects invalid user ids before any cleanup request', () => {
  const registry = createLocalAuthUserRegistry({
    supabaseUrl: 'http://localhost:54321',
    serviceRoleKey: 'test-key',
    fetchImpl: async () => {
      throw new Error('unexpected fetch');
    },
  });
  assert.throws(() => registry.register('e2e-user'), /invalid user UUID/i);
});
