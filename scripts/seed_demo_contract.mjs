export const ONBOARDING_DEMO = Object.freeze({
  key: 'onboarding',
  email: 'onboarding@example.test',
  displayName: null,
  timezone: 'Europe/Berlin',
  seedProductData: false,
});

export const ONBOARDING_EMPTY_TABLES = Object.freeze([
  'daily_logs',
  'behavioral_events',
  'lifestyle_entries',
  'tasks',
  'schedule_items',
  'notifications',
  'notification_action_requests',
  'coach_messages',
  'memory_entries',
  'ai_insights',
  'skillset_profiles',
  'habits',
  'habit_logs',
  'focus_sessions',
  'focus_session_reflections',
  'intake_responses',
  'study_setup_profiles',
  'user_state_snapshots',
  'daily_briefings',
  'weekly_reviews',
  'calendar_connections',
  'calendar_imports',
  'calendar_events',
  'calendar_request_identities',
  'coach_requests',
  'coach_usage_events',
  'coach_memory_selections',
  'deadline_plans',
  'deadline_plan_revisions',
  'deadline_plan_blocks',
  'deadline_plan_request_identities',
  'planner_preferences',
  'planner_action_plans',
  'planner_action_plan_revisions',
  'planner_task_blocks',
  'planner_habit_slots',
  'planner_commitments',
  'planner_request_identities',
  'learning_request_identities',
]);

export function assertFreshOnboardingProjection({
  profile,
  notificationPreferenceCount,
  learningPreference,
  nonEmptyTables,
}) {
  if (
    !profile ||
    profile.email !== ONBOARDING_DEMO.email ||
    profile.timezone !== ONBOARDING_DEMO.timezone ||
    profile.role !== 'user' ||
    profile.auth_provider !== 'email' ||
    profile.onboarding_completed_at !== null ||
    profile.setup_revision !== 0 ||
    profile.daily_preparation_budget_minutes !== null
  ) {
    throw new Error('The onboarding demo profile is not in its fresh state.');
  }
  if (notificationPreferenceCount !== 1) {
    throw new Error(
      'The onboarding demo must have exactly one default notification preference row.',
    );
  }
  if (
    !learningPreference ||
    learningPreference.contract_version !== 'learning-preferences-v1' ||
    learningPreference.revision !== 0 ||
    learningPreference.focus_reflection_prompt_enabled !== true ||
    learningPreference.personal_pattern_analysis_enabled !== true ||
    learningPreference.learned_focus_planning_enabled !== false
  ) {
    throw new Error(
      'The onboarding demo must have exactly one default Personal Learning preference row.',
    );
  }
  if (nonEmptyTables.length > 0) {
    throw new Error(
      `The onboarding demo contains product data in: ${nonEmptyTables.join(', ')}.`,
    );
  }
}
