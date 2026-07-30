import { assertHttpStatus } from '../support/api-client.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@account-controls exports and permanently deletes only its own account', async ({
  e2e,
}) => {
  await e2e.completeSetup();
  const exported = assertHttpStatus(
    await e2e.api.request('/v1/account/export'),
    200,
    'account export',
  );
  expect(exported.headers.get('cache-control')).toBe('no-store');
  expect(exported.json?.contract_version).toBe('account-export-v2');
  expect(exported.json?.data?.profiles?.[0]?.id).toBe(
    e2e.identity.user.id,
  );

  const invalid = await e2e.api.request('/v1/account', {
    method: 'DELETE',
    body: { confirmation: 'delete' },
  });
  expect(invalid.status).toBe(422);
  expect((await e2e.admin.getUser(e2e.identity.user.id)).status).toBe(200);

  assertHttpStatus(
    await e2e.api.request('/v1/account', {
      method: 'DELETE',
      body: { confirmation: 'DELETE' },
    }),
    204,
    'account deletion',
  );
  expect((await e2e.admin.getUser(e2e.identity.user.id)).status).toBe(404);
});
