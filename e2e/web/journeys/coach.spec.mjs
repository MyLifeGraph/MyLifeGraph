import { assertHttpStatus } from '../support/api-client.mjs';
import {
  expectFlutterText,
  openFlutterRoute,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@coach persists a fake-provider turn and renders its history', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  const requestId = crypto.randomUUID();
  const message = `Independent read-only Coach ${requestId}`;
  const response = assertHttpStatus(
    await e2e.api.request('/v1/coach/respond', {
      method: 'POST',
      body: {
        contract_version: 'coach-request-v3',
        request_id: requestId,
        message,
      },
    }),
    200,
    'independent Coach response',
  );
  expect(response.json).toMatchObject({
    contract_version: 'coach-response-v2',
    request_id: requestId,
    provenance: {
      source: 'model',
      provider: 'fake',
      provider_called: true,
    },
  });

  const history = assertHttpStatus(
    await e2e.api.request('/v1/coach/history'),
    200,
    'independent Coach history',
  );
  expect(JSON.stringify(history.json)).toContain(message);

  await e2e.signInUi();
  await openFlutterRoute(page, e2e.appUrl, '/coach');
  await expectFlutterText(page, 'Ask anything');
  await expectFlutterText(page, message);
});
