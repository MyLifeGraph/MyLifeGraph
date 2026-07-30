import {
  expectFlutterText,
} from '../support/flutter-ui.mjs';
import { assertHttpStatus } from '../support/api-client.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@auth-capture-today signs in, persists Evening, and renders Today', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  const planner = assertHttpStatus(
    await e2e.api.request('/v1/planner/overview'),
    200,
    'Planner date source',
  );
  const localDate = planner.json?.local_date;
  expect(localDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);

  const captureId = `spec-evening-${crypto.randomUUID()}`;
  const capture = assertHttpStatus(
    await e2e.api.request(`/v1/daily-capture/${localDate}/evening`, {
      method: 'PUT',
      body: {
        contract_version: 'daily-capture-write-v1',
        request_id: crypto.randomUUID(),
        expected_capture: null,
        capture: {
          branch_version: 'daily-capture-v4',
          capture_kind: 'evening',
          entry_date: localDate,
          capture_id: captureId,
          captured_at: new Date().toISOString(),
          mood: 7,
          energy: 6,
          stress_intensity: 3,
          stress_intensity_label: 'Low',
          planned_sleep_time: '23:00',
          sleep_target_minutes: 480,
        },
      },
    }),
    200,
    'Evening capture',
  );
  expect(capture.json).toMatchObject({
    contract_version: 'daily-capture-write-v1',
    branch: 'evening',
    capture_id: captureId,
    replayed: false,
  });

  assertHttpStatus(
    await e2e.api.request('/v1/snapshots/generate', {
      method: 'POST',
      body: { scope: 'daily', window_days: 7, target_date: localDate },
    }),
    200,
    'daily snapshot refresh',
  );
  const today = assertHttpStatus(
    await e2e.api.request('/v1/today/overview-v2'),
    200,
    'Today overview after capture',
  );
  expect(today.json?.contract_version).toBe('today-overview-v2');
  const persisted = await e2e.db.select(
    `daily_logs?select=entry_date,metadata&entry_date=eq.${localDate}`,
  );
  expect(persisted.status).toBe(200);
  expect(JSON.stringify(persisted.json)).toContain(captureId);

  await e2e.signInUi();
  await expectFlutterText(page, 'Today at a glance');
});
