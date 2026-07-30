import { assertHttpStatus } from '../support/api-client.mjs';
import {
  expectFlutterText,
  openFlutterRoute,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@planner-confirm proposes and confirms one immutable Task plan', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  const initial = assertHttpStatus(
    await e2e.api.request('/v1/planner/overview'),
    200,
    'initial Planner overview',
  );
  const localDate = initial.json?.local_date;
  expect(localDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);

  const planId = crypto.randomUUID();
  const taskId = crypto.randomUUID();
  const title = `Independent Planner ${planId.slice(0, 8)}`;
  const proposal = assertHttpStatus(
    await e2e.api.request('/v1/planner/action-plans/proposals', {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: planId,
        base_revision: 0,
        planning_start_on: localDate,
        target: {
          kind: 'task',
          operation: 'create',
          target_id: taskId,
          expected_updated_at: null,
          title,
          description: null,
          priority: 'high',
          estimated_minutes: 30,
          deadline_at: `${addDays(localDate, 4)}T12:00:00Z`,
          preferred_session_minutes: 30,
        },
      },
    }),
    200,
    'Planner proposal',
  );
  expect(proposal.json?.plan?.pending_revision).toMatchObject({
    revision: 1,
    target: { title, target_id: taskId },
  });

  const confirmed = assertHttpStatus(
    await e2e.api.request(`/v1/planner/action-plans/${planId}/confirm`, {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        expected_revision: 1,
      },
    }),
    200,
    'Planner confirmation',
  );
  expect(confirmed.json?.plan?.status).toBe('active');
  expect(confirmed.json?.plan?.active_revision?.revision).toBe(1);

  const current = assertHttpStatus(
    await e2e.api.request('/v1/planner/overview'),
    200,
    'confirmed Planner overview',
  );
  expect(
    current.json?.action_plans?.some(
      (plan) => plan.id === planId && plan.status === 'active',
    ),
  ).toBe(true);

  await e2e.signInUi();
  await openFlutterRoute(page, e2e.appUrl, '/planner');
  await expectFlutterText(page, 'Add new');
});

function addDays(isoDate, days) {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
