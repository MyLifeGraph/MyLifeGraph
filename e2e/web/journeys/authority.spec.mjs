import { JsonHttpClient } from '../support/api-client.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@authority keeps owner rows and protected routes isolated', async ({
  e2e,
}) => {
  await e2e.completeSetup();
  const secondary = await e2e.createAdditionalIdentity('authority-secondary');

  const ownProfile = await e2e.db.select(
    `profiles?select=id,role&id=eq.${e2e.identity.user.id}`,
  );
  expect(ownProfile.status).toBe(200);
  expect(ownProfile.json).toEqual([
    { id: e2e.identity.user.id, role: 'user' },
  ]);

  const hiddenPrimary = await secondary.db.select(
    `profiles?select=id,role&id=eq.${e2e.identity.user.id}`,
  );
  expect(hiddenPrimary.status).toBe(200);
  expect(hiddenPrimary.json).toEqual([]);

  const forbiddenRoleChange = await e2e.db.mutate(
    `profiles?id=eq.${e2e.identity.user.id}`,
    {
      method: 'PATCH',
      body: { role: 'admin' },
    },
  );
  expect([401, 403]).toContain(forbiddenRoleChange.status);

  const anonymous = new JsonHttpClient({
    baseUrl: e2e.aiServiceBaseUrl,
  });
  const protectedOverview = await anonymous.request('/v1/planner/overview');
  expect([401, 403]).toContain(protectedOverview.status);
});
