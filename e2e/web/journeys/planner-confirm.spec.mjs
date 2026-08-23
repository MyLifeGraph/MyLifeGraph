import { assertHttpStatus } from '../support/api-client.mjs';
import {
  enableFlutterSemantics,
  expectFlutterText,
  openFlutterRoute,
  scrollFlutterTextIntoView,
  waitForFlutterShell,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@planner-confirm proposes and confirms one immutable Task plan', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  await assertParallelManualFocusConflict(e2e);
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
  expect(
    confirmed.json?.plan?.active_revision?.task_blocks?.[0]?.id,
  ).toMatch(/^[0-9a-f-]{36}$/);

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
  await expectFlutterText(page, title);
  const cancelled = assertHttpStatus(
    await e2e.api.request(`/v1/planner/action-plans/${planId}/cancel`, {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        expected_revision: 1,
      },
    }),
    200,
    'release confirmed Planner reservation',
  );
  expect(cancelled.json?.plan?.status).toBe('unscheduled');

  const preparation = await createPreparationBlock(e2e, localDate);
  await openFlutterRoute(
    page,
    e2e.appUrl,
    `/deep-work?source_kind=deadline_plan_block&source_block_id=${preparation.blockId}`,
  );
  await expectFlutterText(page, 'Start a focus block');
  await expectFlutterText(page, preparation.title);
  await (await scrollFlutterTextIntoView(page, 'Start focus session')).click();
  await expectFlutterText(page, 'Focus active');

  const active = assertHttpStatus(
    await e2e.db.select(
      'focus_sessions?select=id,started_at,planned_minutes,status'
      + '&status=eq.active&order=started_at.desc&limit=1',
    ),
    200,
    'active scheduled Focus row',
  );
  expect(active.json).toHaveLength(1);
  const session = active.json[0];
  const source = assertHttpStatus(
    await e2e.db.select(
      'focus_session_schedule_sources?select=focus_session_id,source_kind,'
      + 'deadline_plan_block_id,original_starts_at,original_ends_at,'
      + `original_recovery_minutes&focus_session_id=eq.${session.id}`,
    ),
    200,
    'scheduled Focus provenance',
  );
  expect(source.json).toHaveLength(1);
  expect(source.json[0]).toMatchObject({
    focus_session_id: session.id,
    source_kind: 'deadline_plan_block',
    deadline_plan_block_id: preparation.blockId,
  });
  expect(new Date(source.json[0].original_starts_at).getTime()).toBe(
    new Date(preparation.originalStartsAt).getTime(),
  );
  expect(new Date(session.started_at).getTime()).not.toBe(
    new Date(source.json[0].original_starts_at).getTime(),
  );

  await page.waitForTimeout(61000);
  const terminal = assertHttpStatus(
    await e2e.api.request(`/v1/focus/sessions/${session.id}/finish`, {
      method: 'POST',
    }),
    200,
    'finish scheduled Focus',
  );
  expect(terminal.json).toMatchObject({
    id: session.id,
    status: 'completed',
    schedule_source: {
      source_kind: 'deadline_plan_block',
      block_id: preparation.blockId,
    },
  });
  expect(terminal.json.actual_minutes).toBeGreaterThanOrEqual(1);
  expect(new Date(terminal.json.ended_at).getTime()).toBeGreaterThanOrEqual(
    new Date(terminal.json.started_at).getTime(),
  );
  const credited = assertHttpStatus(
    await e2e.api.request(`/v1/deadline-plans/${preparation.planId}`),
    200,
    'credited Preparation plan',
  );
  const creditedBlock = credited.json?.active_revision?.blocks?.find(
    (block) => block.id === preparation.blockId,
  );
  expect(creditedBlock?.credited_tracked_minutes).toBe(
    terminal.json.actual_minutes,
  );
  expect(credited.json?.progress?.tracked_focus_minutes).toBe(
    terminal.json.actual_minutes,
  );

  await openFlutterRoute(
    page,
    e2e.appUrl,
    `/deep-work?session_id=${session.id}`,
  );
  await expectFlutterText(page, 'How focused did the session feel?');
  await page.getByLabel('Focus quality 4 of 5').click();
  await page.getByLabel('Useful progress 5 of 5').click();
  await (await scrollFlutterTextIntoView(page, 'Save reflection')).click();
  await expectFlutterText(page, 'Focus reflection saved.');

  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectFlutterText(page, 'Edit Focus reflection');
});

async function assertParallelManualFocusConflict(e2e) {
  const requestIds = [crypto.randomUUID(), crypto.randomUUID()];
  const starts = await Promise.all(
    requestIds.map((requestId) =>
      e2e.api.request('/v1/focus/sessions/start', {
        method: 'POST',
        body: {
          contract_version: 'focus-start-v2',
          request_id: requestId,
          source_kind: 'manual',
          planned_minutes: 5,
          recovery_minutes: 0,
          target_kind: null,
          target_id: null,
          label: 'Parallel start probe',
        },
      }),
    ),
  );
  expect(starts.map((result) => result.status).sort()).toEqual([200, 409]);
  const winner = starts.find((result) => result.status === 200);
  const conflict = starts.find((result) => result.status === 409);
  if (winner == null || conflict == null) {
    throw new Error('Parallel Focus starts did not split into success/conflict.');
  }
  expect(winner.json?.status).toBe('active');
  expect(conflict.json).toEqual({ detail: 'active_focus_session' });

  assertHttpStatus(
    await e2e.api.request(
      `/v1/focus/sessions/${winner.json.id}/abandon`,
      { method: 'POST' },
    ),
    200,
    'parallel manual Focus cleanup',
  );
}

async function createPreparationBlock(e2e, localDate) {
  const planId = crypto.randomUUID();
  const title = `Make-up Preparation ${planId.slice(0, 8)}`;
  const proposed = assertHttpStatus(
    await e2e.api.request('/v1/deadline-plans/proposals', {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: planId,
        base_revision: 0,
        kind: 'assignment',
        title,
        deadline_at: `${addDays(localDate, 4)}T12:00:00Z`,
        estimated_total_minutes: 30,
        credited_prior_minutes: 0,
        preferred_session_minutes: 30,
        max_daily_minutes: 120,
        planning_start_on: localDate,
        buffer_days: 0,
        source_kind: 'manual',
        use_calendar_availability: false,
      },
    }),
    200,
    'Preparation proposal',
  );
  expect(proposed.json?.pending_revision?.blocks).toHaveLength(1);

  const confirmed = assertHttpStatus(
    await e2e.api.request(`/v1/deadline-plans/${planId}/confirm`, {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        expected_revision: 1,
      },
    }),
    200,
    'Preparation confirmation',
  );
  const block = confirmed.json?.active_revision?.blocks?.[0];
  expect(block?.id).toMatch(/^[0-9a-f-]{36}$/);

  return {
    planId,
    blockId: block.id,
    title,
    originalStartsAt: block.starts_at,
  };
}

function addDays(isoDate, days) {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
