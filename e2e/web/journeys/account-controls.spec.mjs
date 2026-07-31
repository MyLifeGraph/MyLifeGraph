import {
  clickFlutterText,
  expectFlutterText,
  fillFlutterField,
  openFlutterRoute,
  scrollFlutterTextIntoView,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@account-controls exports and permanently deletes through Settings', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  await e2e.signInUi();
  await openFlutterRoute(page, e2e.appUrl, '/settings');
  await expectFlutterText(page, 'Settings');
  await expectFlutterText(page, 'Synced account');

  const exportResponsePromise = page.waitForResponse(
    (response) =>
      response.url() === `${e2e.aiServiceBaseUrl}/v1/account/export` &&
      response.request().method() === 'GET',
    { timeout: 45000 },
  );
  const downloadPromise = page.waitForEvent('download', { timeout: 45000 });
  await scrollFlutterTextIntoView(page, 'Export data');
  await clickFlutterText(page, 'Export data');
  const [exportResponse, download] = await Promise.all([
    exportResponsePromise,
    downloadPromise,
  ]);
  expect(exportResponse.status()).toBe(200);
  expect(exportResponse.headers()['cache-control']).toBe('no-store');
  expect(exportResponse.headers()['content-disposition']).toBe(
    'attachment; filename="mylifegraph-account-export.json"',
  );
  const exportBytes = await exportResponse.body();
  const exported = JSON.parse(exportBytes.toString('utf8'));
  expect(exported.contract_version).toBe('account-export-v2');
  expect(exported.data?.profiles?.[0]?.id).toBe(
    e2e.identity.user.id,
  );
  expect(download.suggestedFilename()).toMatch(
    /^mylifegraph-export-\d{4}-\d{2}-\d{2}\.json$/,
  );
  expect(await download.failure()).toBeNull();
  const downloadStream = await download.createReadStream();
  expect(downloadStream).not.toBeNull();
  const chunks = [];
  for await (const chunk of downloadStream) chunks.push(Buffer.from(chunk));
  expect(Buffer.concat(chunks).equals(exportBytes)).toBe(true);
  await expectFlutterText(page, 'Account export saved.');

  await scrollFlutterTextIntoView(page, 'Delete account');
  await clickFlutterText(page, 'Delete account');
  await expectFlutterText(page, 'Delete account permanently?');
  await fillFlutterField(page, 'Type DELETE to confirm', 'DELETE');
  const deleteResponsePromise = page.waitForResponse(
    (response) =>
      response.url() === `${e2e.aiServiceBaseUrl}/v1/account` &&
      response.request().method() === 'DELETE',
    { timeout: 45000 },
  );
  await clickFlutterText(page, 'Delete account', { match: 'last' });
  const deleteResponse = await deleteResponsePromise;
  expect(deleteResponse.status()).toBe(204);
  expect(deleteResponse.request().postDataJSON()).toEqual({
    confirmation: 'DELETE',
  });
  expect((await deleteResponse.body()).length).toBe(0);
  await page.waitForURL('**/#/auth**', { timeout: 45000 });
  await expectFlutterText(page, 'Account and canonical synced data deleted.');
  expect((await e2e.admin.getUser(e2e.identity.user.id)).status).toBe(404);
});
