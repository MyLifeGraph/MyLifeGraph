import { assertHttpStatus } from '../support/api-client.mjs';
import {
  expectFlutterText,
  openFlutterRoute,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@notification-lifecycle proves Inbox actions, replay, and owner isolation', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  const notificationId = crypto.randomUUID();
  const title = `Independent Inbox ${notificationId.slice(0, 8)}`;
  const createdAt = new Date(Date.now() - 60_000).toISOString();
  const inserted = await e2e.serviceDb.mutate('notifications', {
    method: 'POST',
    body: {
      id: notificationId,
      user_id: e2e.identity.user.id,
      title,
      message: 'Stored Inbox lifecycle integration item.',
      type: 'reminder',
      priority: 'high',
      is_read: false,
      read_at: null,
      dismissed_at: null,
      action_url: null,
      due_at: null,
      metadata: {
        source: 'playwright-independent-spec',
        contract_version: 'notification-lifecycle-v1',
      },
      created_at: createdAt,
      updated_at: createdAt,
    },
  });
  expect(inserted.status).toBe(201);
  expect(inserted.json).toHaveLength(1);
  expect(inserted.json[0]).toMatchObject({
    id: notificationId,
    user_id: e2e.identity.user.id,
    is_read: false,
    read_at: null,
    dismissed_at: null,
  });

  const ownerRead = await e2e.db.select(
    `notifications?select=id,user_id,title&id=eq.${notificationId}`,
  );
  expect(ownerRead.status).toBe(200);
  expect(ownerRead.json).toEqual([
    { id: notificationId, user_id: e2e.identity.user.id, title },
  ]);

  const forbiddenPatch = await e2e.db.mutate(
    `notifications?id=eq.${notificationId}`,
    {
      method: 'PATCH',
      body: { title: 'Forbidden direct update' },
    },
  );
  expect([401, 403]).toContain(forbiddenPatch.status);

  const other = await e2e.createAdditionalIdentity('notification-other');
  const otherRead = await other.db.select(
    `notifications?select=id&id=eq.${notificationId}`,
  );
  expect(otherRead.status).toBe(200);
  expect(otherRead.json).toEqual([]);

  await e2e.signInUi();
  await openFlutterRoute(page, e2e.appUrl, '/alerts');
  await expectFlutterText(page, 'Inbox');
  await expectFlutterText(page, title);

  const markReadResponsePromise = waitForAction(
    page,
    e2e.aiServiceBaseUrl,
    notificationId,
  );
  await page
    .getByRole('button', {
      name: `Mark read notification ${title}`,
      exact: true,
    })
    .click();
  const markReadResponse = await markReadResponsePromise;
  expect(markReadResponse.status()).toBe(200);
  const markReadRequest = markReadResponse.request().postDataJSON();
  expect(markReadRequest).toMatchObject({
    contract_version: 'notification-lifecycle-v1',
    command: 'mark_read',
  });
  expect(markReadRequest.request_id).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
  );
  expect(sameInstant(markReadRequest.expected_updated_at, createdAt)).toBe(
    true,
  );
  const markRead = await markReadResponse.json();
  expect(markRead).toMatchObject({
    contract_version: 'notification-lifecycle-v1',
    notification_id: notificationId,
    command: 'mark_read',
    is_read: true,
    dismissed_at: null,
    replayed: false,
  });
  expect(sameInstant(markRead.read_at, markRead.updated_at)).toBe(true);
  await page
    .getByRole('button', {
      name: `Mark unread notification ${title}`,
      exact: true,
    })
    .waitFor({ state: 'visible' });

  const replay = assertHttpStatus(
    await e2e.api.request(`/v1/notifications/${notificationId}/actions`, {
      method: 'POST',
      body: markReadRequest,
    }),
    200,
    'Notification exact replay',
  );
  expect(replay.json).toEqual({ ...markRead, replayed: true });

  const reinterpretation = assertHttpStatus(
    await e2e.api.request(`/v1/notifications/${notificationId}/actions`, {
      method: 'POST',
      body: {
        ...markReadRequest,
        command: 'mark_unread',
        expected_updated_at: markRead.updated_at,
      },
    }),
    409,
    'Notification request-id reinterpretation',
  );
  expect(reinterpretation.json?.detail).toBe(
    'Notification action request id was already used',
  );

  const foreignAction = await other.api.request(
    `/v1/notifications/${notificationId}/actions`,
    {
      method: 'POST',
      body: {
        contract_version: 'notification-lifecycle-v1',
        request_id: crypto.randomUUID(),
        command: 'mark_unread',
        expected_updated_at: markRead.updated_at,
      },
    },
  );
  expect(foreignAction.status).toBe(404);

  const forbiddenRpc = await e2e.db.mutate(
    'rpc/apply_notification_action_v1',
    {
      method: 'POST',
      body: {
        p_user_id: e2e.identity.user.id,
        p_notification_id: notificationId,
        p_request_id: crypto.randomUUID(),
        p_command: 'mark_unread',
        p_expected_updated_at: markRead.updated_at,
      },
    },
  );
  expect([401, 403, 404]).toContain(forbiddenRpc.status);

  const markUnreadResponsePromise = waitForAction(
    page,
    e2e.aiServiceBaseUrl,
    notificationId,
  );
  await page
    .getByRole('button', {
      name: `Mark unread notification ${title}`,
      exact: true,
    })
    .click();
  const markUnreadResponse = await markUnreadResponsePromise;
  expect(markUnreadResponse.status()).toBe(200);
  const markUnread = await markUnreadResponse.json();
  expect(markUnread).toMatchObject({
    notification_id: notificationId,
    command: 'mark_unread',
    is_read: false,
    read_at: null,
    dismissed_at: null,
    replayed: false,
  });
  await page
    .getByRole('button', {
      name: `Mark read notification ${title}`,
      exact: true,
    })
    .waitFor({ state: 'visible' });

  const dismissResponsePromise = waitForAction(
    page,
    e2e.aiServiceBaseUrl,
    notificationId,
  );
  await page
    .getByRole('button', {
      name: `Dismiss notification ${title}`,
      exact: true,
    })
    .click();
  const dismissResponse = await dismissResponsePromise;
  expect(dismissResponse.status()).toBe(200);
  const dismissed = await dismissResponse.json();
  expect(dismissed).toMatchObject({
    notification_id: notificationId,
    command: 'dismiss',
    is_read: true,
    replayed: false,
  });
  expect(sameInstant(dismissed.read_at, dismissed.updated_at)).toBe(true);
  expect(sameInstant(dismissed.dismissed_at, dismissed.updated_at)).toBe(true);
  await page
    .getByText(title, { exact: true })
    .waitFor({ state: 'hidden', timeout: 15_000 });

  const tombstone = await e2e.serviceDb.select(
    `notifications?select=id,title,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
  );
  expect(tombstone.status).toBe(200);
  expect(tombstone.json).toHaveLength(1);
  expect(tombstone.json[0]).toMatchObject({
    id: notificationId,
    title,
    is_read: true,
  });
  expect(sameInstant(tombstone.json[0].read_at, dismissed.read_at)).toBe(true);
  expect(
    sameInstant(tombstone.json[0].dismissed_at, dismissed.dismissed_at),
  ).toBe(true);

  await openFlutterRoute(page, e2e.appUrl, '/alerts');
  await expectFlutterText(page, 'Your inbox is empty.');
  await expect(page.getByText(title, { exact: true })).toHaveCount(0);
});

function waitForAction(page, aiServiceBaseUrl, notificationId) {
  return page.waitForResponse(
    (response) =>
      response.url() ===
        `${aiServiceBaseUrl}/v1/notifications/${notificationId}/actions` &&
      response.request().method() === 'POST',
    { timeout: 45_000 },
  );
}

function sameInstant(left, right) {
  return Date.parse(left) === Date.parse(right);
}
