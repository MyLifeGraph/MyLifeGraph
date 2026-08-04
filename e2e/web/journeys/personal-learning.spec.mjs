import { assertHttpStatus } from '../support/api-client.mjs';
import {
  expectFlutterText,
  openFlutterRoute,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@personal-learning updates preferences and renders transparent evidence', async ({
  page,
  e2e,
}) => {
  await e2e.completeSetup();
  const initial = assertHttpStatus(
    await e2e.api.request('/v1/learning/preferences'),
    200,
    'initial learning preferences',
  );
  expect(initial.json?.contract_version).toBe('learning-preferences-v1');

  const updated = assertHttpStatus(
    await e2e.api.request('/v1/learning/preferences', {
      method: 'PATCH',
      body: {
        request_id: crypto.randomUUID(),
        expected_revision: initial.json.revision,
        focus_reflection_prompt_enabled: true,
        personal_pattern_analysis_enabled: true,
        learned_focus_planning_enabled: true,
      },
    }),
    200,
    'updated learning preferences',
  );
  expect(updated.json).toMatchObject({
    contract_version: 'learning-preferences-v1',
    revision: initial.json.revision + 1,
    focus_reflection_prompt_enabled: true,
    personal_pattern_analysis_enabled: true,
    learned_focus_planning_enabled: true,
    replayed: false,
  });

  const planner = assertHttpStatus(
    await e2e.api.request('/v1/planner/overview'),
    200,
    'Planner local date for sleep evidence',
  );
  await seedSleepRecommendationEvidence(e2e, planner.json.local_date);

  const patterns = assertHttpStatus(
    await e2e.api.request('/v1/insights/personal-patterns'),
    200,
    'Personal Learning patterns',
  );
  expect(patterns.json?.contract_version).toBe('personal-patterns-v1');
  const sleep = assertHttpStatus(
    await e2e.api.request('/v1/insights/sleep-recommendation'),
    200,
    'Sleep recommendation',
  );
  expect(sleep.json).toMatchObject({
    contract_version: 'sleep-recommendation-v1',
    status: 'ready',
    reason: 'ready',
  });
  expect(sleep.json?.sample?.eligible_focus_days).toBe(30);

  await e2e.signInUi();
  await openFlutterRoute(page, e2e.appUrl, '/insights');
  await expectFlutterText(page, 'PERSONAL STUDY PATTERN');
  await expectFlutterText(page, 'SLEEP RECOMMENDATION');
  await expectFlutterText(page, 'Best-supported sleep window');
  await expectFlutterText(page, 'Sleep start');
  await expectFlutterText(page, 'Wake time');
  await expectFlutterText(page, 'Duration');
  await expectFlutterText(page, '30 rated sessions');
  await expectFlutterText(page, '90-day window');
});

async function seedSleepRecommendationEvidence(e2e, localEndDate) {
  const userId = e2e.identity.user.id;
  const dailyLogs = [];
  const sessions = [];
  const reflections = [];
  for (let index = 0; index < 30; index += 1) {
    const entryDate = addDays(localEndDate, index - 30);
    const candidate = index % 2 === 0;
    const wake = new Date(
      `${entryDate}T${candidate ? '06:00' : '08:30'}:00.000Z`,
    );
    const duration = candidate ? 480 : 450;
    const sleepStart = new Date(wake.getTime() - duration * 60_000);
    const captured = new Date(wake.getTime() + 10 * 60_000);
    const sessionStart = new Date(`${entryDate}T10:00:00.000Z`);
    const sessionEnd = new Date(sessionStart.getTime() + 45 * 60_000);
    const logId = crypto.randomUUID();
    const captureId = `e2e-morning-${crypto.randomUUID()}`;
    const sessionId = crypto.randomUUID();
    dailyLogs.push({
      id: logId,
      user_id: userId,
      entry_date: entryDate,
      sleep_hours: duration / 60,
      energy_level: candidate ? 8 : 6,
      source: 'quick_check_in',
      metadata: {
        capture_version: 'daily-capture-v5',
        captures: {
          morning: {
            branch_version: 'daily-capture-v5',
            capture_kind: 'morning',
            entry_date: entryDate,
            capture_id: captureId,
            captured_at: captured.toISOString(),
            sleep_hours: duration / 60,
            sleep_quality: candidate ? 8 : 6,
            current_energy: candidate ? 8 : 6,
            estimated_sleep_started_at: sleepStart.toISOString(),
            woke_at: wake.toISOString(),
            estimated_sleep_minutes: duration,
            sleep_target_minutes: 510,
          },
        },
      },
      created_at: captured.toISOString(),
      updated_at: captured.toISOString(),
    });
    sessions.push({
      id: sessionId,
      user_id: userId,
      started_at: sessionStart.toISOString(),
      ended_at: sessionEnd.toISOString(),
      planned_minutes: 45,
      actual_minutes: 45,
      label: candidate ? 'Supported sleep Focus' : 'Comparison sleep Focus',
      status: 'completed',
      created_at: sessionStart.toISOString(),
      updated_at: sessionEnd.toISOString(),
    });
    reflections.push({
      focus_session_id: sessionId,
      user_id: userId,
      contract_version: 'focus-reflection-v1',
      focus_quality: 4,
      useful_progress: candidate ? 5 : 3,
      obstacles: [],
      created_at: new Date(sessionEnd.getTime() + 60_000).toISOString(),
      updated_at: new Date(sessionEnd.getTime() + 60_000).toISOString(),
    });
  }
  for (const [table, rows] of [
    ['daily_logs', dailyLogs],
    ['focus_sessions', sessions],
    ['focus_session_reflections', reflections],
  ]) {
    assertHttpStatus(
      await e2e.serviceDb.mutate(table, {
        method: 'POST',
        body: rows,
        returnRepresentation: false,
      }),
      201,
      `seed ${table} sleep evidence`,
    );
  }
}

function addDays(value, amount) {
  const result = new Date(`${value}T12:00:00.000Z`);
  result.setUTCDate(result.getUTCDate() + amount);
  return result.toISOString().slice(0, 10);
}
