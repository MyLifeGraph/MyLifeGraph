import { assertHttpStatus } from '../support/api-client.mjs';
import {
  clickFlutterText,
  expectFlutterText,
  openFlutterRoute,
  scrollFlutterTextIntoView,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@exam-week-outlook renders a read-only Planner outlook and replan entry', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  const initial = assertHttpStatus(
    await e2e.api.request('/v1/planner/overview'),
    200,
    'Exam-week local date',
  );
  const localDate = initial.json?.local_date;
  expect(localDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);

  const eveningCaptureId = `exam-evening-${crypto.randomUUID()}`;
  const capturedAt = new Date().toISOString();
  assertHttpStatus(
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
          capture_id: eveningCaptureId,
          captured_at: capturedAt,
          mood: 7,
          energy: 6,
          stress_intensity: 3,
          stress_intensity_label: 'low',
          planned_sleep_time: '23:00',
          sleep_target_minutes: 480,
        },
      },
    }),
    200,
    'Exam-week Evening V4 capture',
  );

  const wokeAt = new Date(Date.now() - 60 * 60 * 1000);
  const sleepStartedAt = new Date(wokeAt.getTime() - 330 * 60 * 1000);
  assertHttpStatus(
    await e2e.api.request(`/v1/daily-capture/${localDate}/morning`, {
      method: 'PUT',
      body: {
        contract_version: 'daily-capture-write-v1',
        request_id: crypto.randomUUID(),
        expected_capture: null,
        capture: {
          branch_version: 'daily-capture-v4',
          capture_kind: 'morning',
          entry_date: localDate,
          capture_id: `exam-morning-${crypto.randomUUID()}`,
          captured_at: capturedAt,
          sleep_hours: 5.5,
          sleep_quality: 4,
          current_energy: 5,
          day_shape: 'constrained',
          estimated_sleep_started_at: sleepStartedAt.toISOString(),
          woke_at: wokeAt.toISOString(),
          estimated_sleep_minutes: 330,
          sleep_target_minutes: 480,
          source_evening_capture_id: eveningCaptureId,
        },
      },
    }),
    200,
    'Exam-week Morning V4 capture',
  );

  const exam = await createConfirmedDeadlinePlan(e2e, {
    kind: 'exam',
    title: `Independent exam ${crypto.randomUUID().slice(0, 8)}`,
    localDate,
    deadlineDate: addDays(localDate, 7),
    estimatedTotalMinutes: 180,
  });
  const assignment = await createConfirmedDeadlinePlan(e2e, {
    kind: 'assignment',
    title: `Independent assignment ${crypto.randomUUID().slice(0, 8)}`,
    localDate,
    deadlineDate: addDays(localDate, 6),
    estimatedTotalMinutes: 60,
  });

  const outlook = assertHttpStatus(
    await e2e.api.request('/v1/deadline-plans/exam-week-outlook'),
    200,
    'Exam-week outlook',
  ).json;
  expect(outlook).toMatchObject({
    contract_version: 'exam-week-outlook-v1',
    origin: 'authenticated_backend',
    local_date: localDate,
    mode: 'exam_week',
    current_sleep_plan: {
      planned_sleep_time: '23:00',
      sleep_target_minutes: 480,
    },
  });
  expect(outlook.recent_sleep_nights).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        estimated_sleep_minutes: 330,
        sleep_target_minutes: 480,
      }),
    ]),
  );
  expect(outlook.exams).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        plan_id: exam.planId,
        active_revision: 1,
        days_remaining: 7,
      }),
    ]),
  );
  expect(outlook.assignments).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        plan_id: assignment.planId,
        active_revision: 1,
        remaining_minutes: 60,
      }),
    ]),
  );
  expect(JSON.stringify(outlook)).not.toContain(
    'estimated_sleep_started_at',
  );
  expect(JSON.stringify(outlook)).not.toContain('"woke_at"');

  const before = await persistedDeadlineState(e2e, [
    exam.planId,
    assignment.planId,
  ]);

  await e2e.signInUi();
  await expectFlutterText(page, 'Today at a glance');
  await expect(page.getByText('Exam week', { exact: true })).toHaveCount(0);

  await openFlutterRoute(page, e2e.appUrl, '/planner');
  await expectFlutterText(page, 'Exam week');
  await scrollFlutterTextIntoView(page, exam.title, { maxSteps: 20 });
  await expectFlutterText(page, exam.title);
  await expectFlutterText(page, assignment.title);
  await expectFlutterText(page, 'Assignments counted in capacity');
  await expectFlutterText(page, 'Sleep plan 23:00');
  await expectFlutterText(
    page,
    'Read-only outlook. Opening this card neither creates a preview nor changes your current saved plan.',
  );
  await scrollFlutterTextIntoView(page, 'Replan remaining time', {
    maxSteps: 12,
  });
  await expectFlutterText(page, 'Review plan');
  await clickFlutterText(page, 'Replan remaining time');
  await expectFlutterText(page, 'Replan remaining preparation');
  await expectFlutterText(page, 'Create preview with these values');
  await clickFlutterText(page, 'Cancel');
  await expectFlutterText(page, 'Preparation plans');

  const after = await persistedDeadlineState(e2e, [
    exam.planId,
    assignment.planId,
  ]);
  expect(after).toBe(before);
});

async function createConfirmedDeadlinePlan(
  e2e,
  { kind, title, localDate, deadlineDate, estimatedTotalMinutes },
) {
  const planId = crypto.randomUUID();
  const proposed = assertHttpStatus(
    await e2e.api.request('/v1/deadline-plans/proposals', {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: planId,
        base_revision: 0,
        kind,
        title,
        deadline_at: `${deadlineDate}T12:00:00Z`,
        estimated_total_minutes: estimatedTotalMinutes,
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
    `${kind} proposal`,
  );
  expect(proposed.json?.plan).toMatchObject({
    id: planId,
    status: 'draft',
    kind,
    title,
  });
  expect(proposed.json?.pending_revision?.revision).toBe(1);

  const confirmed = assertHttpStatus(
    await e2e.api.request(`/v1/deadline-plans/${planId}/confirm`, {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        expected_revision: 1,
      },
    }),
    200,
    `${kind} confirmation`,
  );
  expect(confirmed.json?.plan).toMatchObject({
    id: planId,
    status: 'active',
    kind,
    title,
    current_revision: 1,
    latest_revision: 1,
  });
  expect(confirmed.json?.active_revision?.revision).toBe(1);
  return { planId, title };
}

async function persistedDeadlineState(e2e, planIds) {
  const encodedIds = planIds.join(',');
  const paths = [
    `deadline_plans?select=id,status,current_revision,latest_revision,updated_at&id=in.(${encodedIds})&order=id.asc`,
    `deadline_plan_revisions?select=plan_id,revision,state,activated_at,superseded_at&plan_id=in.(${encodedIds})&order=plan_id.asc,revision.asc`,
    `deadline_plan_blocks?select=id,plan_id,revision,reservation_state,starts_at,ends_at,reserved_ends_at,planned_minutes&plan_id=in.(${encodedIds})&order=plan_id.asc,revision.asc,sequence.asc`,
  ];
  const results = await Promise.all(paths.map((path) => e2e.db.select(path)));
  for (const result of results) expect(result.status).toBe(200);
  return JSON.stringify(results.map((result) => result.json));
}

function addDays(isoDate, days) {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
