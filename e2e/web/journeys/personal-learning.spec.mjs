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

  const patterns = assertHttpStatus(
    await e2e.api.request('/v1/insights/personal-patterns?window_days=90'),
    200,
    'Personal Learning patterns',
  );
  expect(patterns.json?.contract_version).toBe('personal-patterns-v1');

  await e2e.signInUi();
  await openFlutterRoute(page, e2e.appUrl, '/insights');
  await expectFlutterText(page, 'PERSONAL STUDY PATTERN');
  await expectFlutterText(page, '0 rated sessions');
  await expectFlutterText(page, '90-day window');
});
