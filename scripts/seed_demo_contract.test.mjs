import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ONBOARDING_DEMO,
  ONBOARDING_EMPTY_TABLES,
  assertFreshOnboardingProjection,
} from './seed_demo_contract.mjs';

const freshProfile = {
  email: 'onboarding@example.test',
  timezone: 'Europe/Berlin',
  role: 'user',
  auth_provider: 'email',
  onboarding_completed_at: null,
  setup_revision: 0,
  daily_preparation_budget_minutes: null,
};
const defaultLearningPreference = {
  contract_version: 'learning-preferences-v1',
  revision: 0,
  focus_reflection_prompt_enabled: true,
  personal_pattern_analysis_enabled: true,
  learned_focus_planning_enabled: false,
};

test('onboarding demo identity is a real empty Setup account', () => {
  assert.deepEqual(ONBOARDING_DEMO, {
    key: 'onboarding',
    email: 'onboarding@example.test',
    displayName: null,
    timezone: 'Europe/Berlin',
    seedProductData: false,
  });
  assert.equal(new Set(ONBOARDING_EMPTY_TABLES).size, ONBOARDING_EMPTY_TABLES.length);
  assert.ok(ONBOARDING_EMPTY_TABLES.includes('intake_responses'));
  assert.ok(ONBOARDING_EMPTY_TABLES.includes('coach_requests'));
  assert.ok(ONBOARDING_EMPTY_TABLES.includes('planner_request_identities'));

  assert.doesNotThrow(() =>
    assertFreshOnboardingProjection({
      profile: freshProfile,
      notificationPreferenceCount: 1,
      learningPreference: defaultLearningPreference,
      nonEmptyTables: [],
    }),
  );
});

test('onboarding demo invariant rejects completion or retained product data', () => {
  assert.throws(
    () =>
      assertFreshOnboardingProjection({
        profile: {
          ...freshProfile,
          onboarding_completed_at: '2026-07-28T08:00:00.000Z',
        },
        notificationPreferenceCount: 1,
        learningPreference: defaultLearningPreference,
        nonEmptyTables: [],
      }),
    /not in its fresh state/,
  );
  assert.throws(
    () =>
      assertFreshOnboardingProjection({
        profile: freshProfile,
        notificationPreferenceCount: 1,
        learningPreference: defaultLearningPreference,
        nonEmptyTables: ['tasks'],
      }),
    /contains product data in: tasks/,
  );
});
