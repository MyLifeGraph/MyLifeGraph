import assert from 'node:assert/strict';
import test from 'node:test';

import {
  e2eUserSelectionFingerprint,
  listLocalAuthUsers,
  selectLegacyE2eUsers,
} from './cleanup_local_e2e_users.mjs';

const firstUser = {
  id: '11111111-1111-4111-8111-111111111111',
  email: 'e2e-old-run@example.test',
};
const secondUser = {
  id: '22222222-2222-4222-8222-222222222222',
  email: 'e2e-second.run@example.test',
};

test('selects only exact E2E identities and sorts the exact UUID set', () => {
  assert.deepEqual(
    selectLegacyE2eUsers([
      secondUser,
      { id: '33333333-3333-4333-8333-333333333333', email: 'student@example.test' },
      { id: '44444444-4444-4444-8444-444444444444', email: 'e2e-@example.test' },
      firstUser,
    ]),
    [firstUser, secondUser],
  );
});

test('binds confirmation to both exact ids and emails', () => {
  const original = e2eUserSelectionFingerprint([firstUser, secondUser]);
  assert.equal(
    original,
    e2eUserSelectionFingerprint([firstUser, secondUser]),
  );
  assert.notEqual(
    original,
    e2eUserSelectionFingerprint([
      firstUser,
      { ...secondUser, id: '55555555-5555-4555-8555-555555555555' },
    ]),
  );
});

test('paginates only on the validated loopback Auth admin endpoint', async () => {
  const calls = [];
  const firstPage = Array.from({ length: 1000 }, (_, index) => ({
    id: `user-${index}`,
    email: `person-${index}@example.test`,
  }));
  const fetchImpl = async (url) => {
    calls.push(url);
    const users = calls.length === 1 ? firstPage : [firstUser];
    return new Response(JSON.stringify({ users }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };

  const result = await listLocalAuthUsers({
    supabaseUrl: 'http://127.0.0.1:54321',
    serviceRoleKey: 'test-key',
    fetchImpl,
  });
  assert.equal(result.length, 1001);
  assert.deepEqual(calls, [
    'http://127.0.0.1:54321/auth/v1/admin/users?page=1&per_page=1000',
    'http://127.0.0.1:54321/auth/v1/admin/users?page=2&per_page=1000',
  ]);

  await assert.rejects(
    listLocalAuthUsers({
      supabaseUrl: 'https://project.supabase.co',
      serviceRoleKey: 'test-key',
      fetchImpl,
    }),
    /loopback/i,
  );
});
