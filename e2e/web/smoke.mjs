import { chromium } from 'playwright';

const required = [
  'APP_URL',
  'AI_SERVICE_BASE_URL',
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SCHEDULED_REFRESH_TOKEN',
];

for (const name of required) {
  if (!process.env[name]) {
    throw new Error(`${name} is required`);
  }
}

const appUrl = process.env.APP_URL.replace(/\/$/, '');
const aiServiceBaseUrl = process.env.AI_SERVICE_BASE_URL.replace(/\/$/, '');
const supabaseUrl = process.env.SUPABASE_URL.replace(/\/$/, '');
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const scheduledRefreshToken = process.env.SCHEDULED_REFRESH_TOKEN;
const headed = process.env.HEADED === 'true';
const runId = process.env.E2E_RUN_ID ?? `${Date.now()}`;
const phase10Only = process.env.E2E_PHASE10_ONLY === 'true';
const coachAttemptId = phase10Only
  ? `${runId}-${process.pid}-${Date.now()}`
  : runId;
const artifactDir = process.env.E2E_ARTIFACT_DIR ?? '.tools/e2e';
const email = `e2e-${runId}@example.test`;
const password = `E2e-${runId}-password`;
const setupGoalTitle = `E2E protect focus ${runId}`;
const editedSetupGoalTitle = `E2E protect focus deeply ${runId}`;
const setupRoutineTitle = `E2E lunch walk candidate ${runId}`;
const setupCommitmentTitle = `E2E project lab ${runId}`;
const editedSetupCommitmentTitle = `E2E project studio ${runId}`;
const manualGoalTitle = `E2E manual goal ${runId}`;
const manualHabitTitle = `E2E manual paused habit ${runId}`;
const manualScheduleTitle = `E2E manual schedule ${runId}`;
const legacyExplicitScheduleTitle = `E2E legacy explicit schedule ${runId}`;
const managedHabitTitle = `E2E managed habit ${runId}`;
const setupExecutionHabitTitle = `E2E setup execution habit ${runId}`;
const phase3TaskTitle = `E2E executable task ${runId}`;
const eveningTomorrowPriority = `E2E protect a calm morning ${runId}`;
const editedEveningTomorrowPriority =
  `E2E finish the smallest useful draft ${runId}`;
const eveningAdditionalFrictions = ['interruptions', 'hard_to_start'];
const coachMemoryTitle = `E2E bounded Coach memory ${runId}`;
const coachApiMessage = `E2E explain one bounded next step ${runId}`;
const coachUiMessage = `E2E UI Coach question ${runId}`;
const coachSafetyMessage =
  `E2E safety check ${runId}: I am in immediate danger and might hurt myself.`;
const notificationLifecycleTitle = `E2E inbox lifecycle ${runId}`;
const notificationFutureTitle = `E2E future inbox item ${runId}`;
const plannerTaskTitle = `E2E split Planner task ${runId}`;
const plannerHabitTitle = `E2E Planner habit ${runId}`;
const plannerOneOffTitle = `E2E one-time commitment ${runId}`;
const plannerWeeklyTitle = `E2E weekly commitment ${runId}`;
const accountExportV1TableNames = [
  'profiles',
  'notification_preferences',
  'daily_logs',
  'behavioral_events',
  'lifestyle_entries',
  'tasks',
  'schedule_items',
  'notifications',
  'coach_messages',
  'memory_entries',
  'ai_insights',
  'recommendations',
  'skillset_profiles',
  'goals',
  'habits',
  'habit_logs',
  'focus_sessions',
  'intake_responses',
  'study_setup_profiles',
  'user_state_snapshots',
  'daily_briefings',
  'decision_feedback',
  'weekly_reviews',
  'calendar_connections',
  'calendar_imports',
  'calendar_events',
  'coach_requests',
  'coach_usage_events',
  'coach_memory_selections',
  'deadline_plans',
  'deadline_plan_revisions',
  'deadline_plan_blocks',
  'planner_preferences',
  'planner_action_plans',
  'planner_action_plan_revisions',
  'planner_task_blocks',
  'planner_habit_slots',
  'planner_commitments',
];
const accountExportV1SanitizedTables = [
  'calendar_connections',
  'calendar_imports',
  'calendar_events',
  'coach_requests',
  'coach_usage_events',
];
const accountExportV1OmittedTables = {
  calendar_request_identities: 'backend_only_anti_replay_ledger',
  notification_action_requests: 'backend_only_anti_replay_ledger',
  deadline_plan_request_identities: 'backend_only_anti_replay_ledger',
  planner_request_identities: 'backend_only_anti_replay_ledger',
};

const browser = await chromium.launch({
  headless: !headed,
  executablePath: process.env.CHROME_BIN || undefined,
});

let page;
try {
  await assertAiServiceHealthy();
  if (phase10Only) {
    const accessToken = await signInAccessToken('focused Phase 10 browser run');
    const userId = await authenticatedUserId(accessToken);
    await resetCoachE2EState(userId);
    page = await browser.newPage({ viewport: { width: 1280, height: 960 } });
    page.on('pageerror', (error) => {
      console.error(`[browser page error] ${error.message}`);
    });
    page.on('console', (message) => {
      if (['error', 'warning'].includes(message.type())) {
        console.error(`[browser ${message.type()}] ${message.text()}`);
      }
    });
    await page.goto(appRoute('/auth'), { waitUntil: 'domcontentloaded' });
    await waitForFlutterShell(page);
    await enableFlutterSemantics(page);
    await fillByLabelOrPlaceholder(page, 'Email', email, 0);
    await fillByLabelOrPlaceholder(page, 'Password', password, 1);
    await clickByText(page, 'Login', { match: 'last' });
    await page.waitForURL('**/#/dashboard', { timeout: 45000 });
    await assertControlledCoach(page, userId);
    console.log(`Focused Phase 10 browser smoke passed for ${email}`);
  } else {
  const user = await createConfirmedUser();
  await patchRows(
    `profiles?id=eq.${user.id}`,
    { timezone: 'Europe/Berlin' },
    'E2E profile timezone',
  );
  page = await browser.newPage({
    viewport: { width: 1280, height: 960 },
  });

  page.on('pageerror', (error) => {
    console.error(`[browser page error] ${error.message}`);
  });
  page.on('console', (message) => {
    if (['error', 'warning'].includes(message.type())) {
      console.error(`[browser ${message.type()}] ${message.text()}`);
    }
  });

  await page.goto(appRoute('/auth'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Build your day-aware coach');

  await fillByLabelOrPlaceholder(page, 'Email', email, 0);
  await fillByLabelOrPlaceholder(page, 'Password', password, 1);
  await clickByText(page, 'Login', { match: 'last' });

  await expectText(page, 'Required setup');
  await clickChoiceChip(page, 'Focus');
  await clickChoiceChip(page, 'Planning');
  await selectDropdownOption(
    page,
    'Typical weekday required',
    'School or work blocks',
  );
  await selectDropdownOption(page, 'Best energy window required', 'Morning');
  await selectDropdownOption(page, 'Coaching style required', 'Direct');
  await clickChoiceChip(page, 'Prefer no reminders');
  await scrollFlutterPage(page, 1100);
  await toggleSetupSection(page, 'Focus setup', 'Use a study rhythm');
  await page
    .getByLabel('Use a study rhythm', { exact: false })
    .first()
    .click();
  await expectText(page, '45 minutes');
  await expectText(page, '10 minutes');
  await expectText(page, 'Start ritual');
  await scrollUntilTextInViewport(page, 'Save setup', {
    deltaY: 900,
    buttonFirst: true,
  });
  await clickByText(page, 'Save setup');

  await page.waitForURL('**/#/dashboard');
  await expectText(page, 'Today at a glance');
  await waitForRows(
    `intake_responses?select=id,request_id,base_revision,revision,state,version,responses,metadata&user_id=eq.${user.id}&order=revision.asc`,
    (rows) =>
      rows.length === 1 &&
      rows[0].version === 'intake-v1' &&
      rows[0].state === 'applied' &&
      rows[0].base_revision === 0 &&
      rows[0].revision === 1 &&
      typeof rows[0].request_id === 'string' &&
      rows[0].metadata?.source === 'onboarding' &&
      arraysEqual(rows[0].responses?.primary_focus_areas, [
        'focus',
        'planning',
      ]) &&
      arraysEqual(rows[0].responses?.goals, []) &&
      arraysEqual(rows[0].responses?.friction_points, []) &&
      arraysEqual(rows[0].responses?.routines, []) &&
      arraysEqual(rows[0].responses?.fixed_commitments, []) &&
      rows[0].responses?.study_setup?.focus_rhythm?.focus_minutes === 45 &&
      rows[0].responses?.study_setup?.focus_rhythm?.recovery_minutes === 10 &&
      arraysEqual(
        rows[0].responses?.study_setup?.focus_rhythm?.preparation_items?.map(
          (item) => item.label,
        ),
        [
          'Water',
          'Small snack',
          'Bathroom',
          'Flight or focus mode',
          'Study materials',
        ],
      ) &&
      !Object.hasOwn(
        rows[0].responses?.study_setup ?? {},
        'semester_planning',
      ) &&
      !Object.hasOwn(rows[0].responses ?? {}, 'calendar_connection_intent'),
    'applied revision 1 with exact Focus setup defaults',
  );
  await waitForRows(
    `study_setup_profiles?select=user_id,contract_version,focus_minutes,recovery_minutes,preparation_items,current_semester,next_semester,setup_revision&user_id=eq.${user.id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].contract_version === 'study-setup-v1' &&
      rows[0].focus_minutes === 45 &&
      rows[0].recovery_minutes === 10 &&
      arraysEqual(
        rows[0].preparation_items?.map((item) => item.label),
        [
          'Water',
          'Small snack',
          'Bathroom',
          'Flight or focus mode',
          'Study materials',
        ],
      ) &&
      rows[0].preparation_items?.every(
        (item) =>
          typeof item.key === 'string' &&
          item.active === true,
      ) &&
      rows[0].current_semester === null &&
      rows[0].next_semester === null &&
      rows[0].setup_revision === 1,
    'Study Setup projection at revision 1',
  );
  await waitForRows(
    `user_state_snapshots?select=id,scope,period_key,summary,signals,metadata&user_id=eq.${user.id}&scope=eq.onboarding`,
    (rows) =>
      rows.length === 1 &&
      rows[0].period_key === 'setup:intake-v1' &&
      rows[0].summary?.coaching_style === 'direct' &&
      arraysEqual(rows[0].summary?.goals, []) &&
      arraysEqual(rows[0].summary?.friction_points, []) &&
      rows[0].metadata?.source === 'intake-v1' &&
      rows[0].metadata?.revision === 1,
    'constant onboarding setup snapshot after revision 1',
  );
  await waitForRows(
    `profiles?select=id,onboarding_completed_at,setup_revision&id=eq.${user.id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].onboarding_completed_at != null &&
      rows[0].setup_revision === 1,
    'profile projection at setup revision 1',
  );
  await assertNoSetupOwnedRows(user.id, 'revision 1 empty optionals');
  await waitForRows(
    `recommendations?select=id,title,category,status,metadata&user_id=eq.${user.id}&status=in.(new,accepted)`,
    (rows) =>
      rows.some(
        (row) =>
          row.category === 'focus' &&
          row.metadata?.model === null &&
          row.metadata?.source_engine_version === 'deterministic-v1',
      ) &&
      rows.some(
        (row) =>
          row.category === 'planning' &&
          row.metadata?.model === null &&
          row.metadata?.source_engine_version === 'deterministic-v1',
      ),
    'deterministic recommendations generated after intake',
  );

  await page.goto(appRoute('/settings'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByText(page, 'Setup and commitments');
  await expectText(page, 'Review your setup');
  await expectText(page, 'School or work blocks');
  await expectText(page, 'Morning');
  await expectText(page, 'Direct');
  await expectText(page, 'Prefer no reminders');

  const [legacyDefaultSchedule, legacyExplicitSchedule] = await insertRows(
    'schedule_items',
    [
      {
        user_id: user.id,
        title: 'Math',
        location: 'Room 204',
        weekday: 1,
        starts_at: '08:15',
        ends_at: '09:45',
        source: 'onboarding',
        metadata: {},
      },
      {
        user_id: user.id,
        title: legacyExplicitScheduleTitle,
        location: 'Room E2E legacy',
        weekday: 2,
        starts_at: '10:00',
        ends_at: '11:00',
        source: 'onboarding',
        metadata: {},
      },
    ],
  );

  await toggleSetupSection(page, 'Goals and friction', 'Add goal');
  await clickByText(page, 'Add goal');
  await fillByLabelOrPlaceholder(page, 'Goal title', setupGoalTitle, 1);
  await expectFieldValue(page, 'Goal title', setupGoalTitle, 1);
  await page.keyboard.press('Tab');
  await page.waitForTimeout(250);
  await scrollFlutterPage(page, 700);
  await toggleSetupSection(page, 'Routines', 'Add routine candidate');
  await scrollFlutterPage(page, 700);
  await clickByText(page, 'Add routine candidate');
  await fillByLabelOrPlaceholder(page, 'Routine name', setupRoutineTitle, 3);
  await expectFieldValue(page, 'Routine name', setupRoutineTitle, 3);
  await page.keyboard.press('Tab');
  await page.waitForTimeout(250);
  await scrollFlutterPage(page, 700);
  await toggleSetupSection(
    page,
    'Fixed commitments',
    'Add fixed commitment',
  );
  await scrollFlutterPage(page, 700);
  await clickByText(page, 'Add fixed commitment');
  await fillByLabelOrPlaceholder(page, 'Title', setupCommitmentTitle, 4);
  await fillByLabelOrPlaceholder(page, 'Location optional', 'Room E2E', 5);
  await selectDropdownOption(page, 'Weekday', 'Monday');
  await fillByLabelOrPlaceholder(page, 'Starts (HH:mm)', '14:15', -2);
  await fillByLabelOrPlaceholder(page, 'Ends (HH:mm)', '15:45', -1);
  await expectFieldValue(page, 'Title', setupCommitmentTitle, 4);
  await expectFieldValue(page, 'Location optional', 'Room E2E', 5);
  await expectFieldValue(page, 'Starts (HH:mm)', '14:15', -2);
  await expectFieldValue(page, 'Ends (HH:mm)', '15:45', -1);
  await expectText(page, 'Semester dates optional');
  await expectText(page, 'Valid from');
  await expectText(page, 'Valid until');
  await expectText(page, 'Duplicate for another day');
  if (
    (await page
      .getByText('Calendar connection optional', { exact: true })
      .count()) !== 0
  ) {
    throw new Error('Setup must not request calendar interest.');
  }
  await page.keyboard.press('Tab');
  await page.waitForTimeout(250);
  await scrollFlutterPage(page, 1800);

  let lostSavePayload;
  const intakeCompleteUrl = `${aiServiceBaseUrl}/v1/intake/complete`;
  const loseAppliedResponse = async (route) => {
    if (route.request().method() !== 'POST') {
      await route.continue();
      return;
    }
    lostSavePayload = route.request().postDataJSON();
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Setup response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    await route.abort('failed');
  };
  await page.route(intakeCompleteUrl, loseAppliedResponse);
  await clickByText(page, 'Save setup');
  await expectText(page, 'Setup was not saved. Your draft is still here.');
  await page.unroute(intakeCompleteUrl, loseAppliedResponse);
  await waitForRows(
    `intake_responses?select=id,request_id,base_revision,revision,state,responses,metadata&user_id=eq.${user.id}&order=revision.asc`,
    (rows) =>
      rows.length === 2 &&
      rows[1].state === 'applied' &&
      rows[1].base_revision === 1 &&
      rows[1].revision === 2 &&
      rows[1].request_id === lostSavePayload?.request_id &&
      rows[1].responses?.goals?.[0]?.title === setupGoalTitle &&
      rows[1].responses?.routines?.[0]?.title === setupRoutineTitle &&
      rows[1].responses?.routines?.[0]?.status === 'candidate' &&
      rows[1].responses?.routines?.[0]?.cadence_confirmed === false &&
      !Object.hasOwn(rows[1].responses?.routines?.[0] ?? {}, 'frequency') &&
      !Object.hasOwn(rows[1].responses?.routines?.[0] ?? {}, 'target') &&
      rows[1].responses?.fixed_commitments?.[0]?.title ===
        setupCommitmentTitle,
    'server-committed revision 2 after lost browser response',
  );

  const retryResponsePromise = waitForAiPost(
    page,
    '/v1/intake/complete',
    'idempotent setup retry',
  );
  await clickByText(page, 'Retry unchanged');
  const retryResponse = await retryResponsePromise;
  const retryPayload = retryResponse.request().postDataJSON();
  if (
    retryPayload.request_id !== lostSavePayload?.request_id ||
    retryPayload.base_revision !== 1 ||
    stableJson(retryPayload) !== stableJson(lostSavePayload)
  ) {
    throw new Error(
      `Setup retry changed the exact locked submission. First ${JSON.stringify(lostSavePayload)}, retry ${JSON.stringify(retryPayload)}`,
    );
  }
  await page.waitForURL('**/#/settings');
  await expectText(page, 'Settings');

  const revision2Rows = await fetchRows(
    `intake_responses?select=id,request_id,base_revision,revision,state,responses,metadata&user_id=eq.${user.id}&order=revision.asc`,
    'setup revisions after retry',
  );
  if (
    revision2Rows.length !== 2 ||
    revision2Rows.filter((row) => row.request_id === retryPayload.request_id)
      .length !== 1
  ) {
    throw new Error(
      `Retry duplicated its intake revision: ${JSON.stringify(revision2Rows)}`,
    );
  }
  const revision2 = revision2Rows.find((row) => row.revision === 2);
  const goalKey = revision2?.responses?.goals?.[0]?.key;
  const routineKey = revision2?.responses?.routines?.[0]?.key;
  const commitmentKey = revision2?.responses?.fixed_commitments?.[0]?.key;
  if (!goalKey || !routineKey || !commitmentKey) {
    throw new Error(`Revision 2 lost setup keys: ${JSON.stringify(revision2)}`);
  }
  const setupGoalsAtRevision2 = await fetchRows(
    `goals?select=id,title,status,metadata&user_id=eq.${user.id}`,
    'setup goal at revision 2',
  );
  const setupGoalAtRevision2 = setupGoalsAtRevision2.find(
    (row) => row.metadata?.managed_by === 'setup',
  );
  if (
    !setupGoalAtRevision2 ||
    setupGoalAtRevision2.title !== setupGoalTitle ||
    setupGoalAtRevision2.status !== 'active' ||
    setupGoalAtRevision2.metadata?.source !== 'intake-v1' ||
    setupGoalAtRevision2.metadata?.setup_state !== 'active' ||
    setupGoalAtRevision2.metadata?.setup_item_id !== goalKey ||
    setupGoalAtRevision2.metadata?.revision !== 2
  ) {
    throw new Error(
      `Unexpected revision 2 setup goal: ${JSON.stringify(setupGoalsAtRevision2)}`,
    );
  }
  const setupSchedulesAtRevision2 = await fetchRows(
    `schedule_items?select=id,title,location,weekday,starts_at,ends_at,source,metadata&user_id=eq.${user.id}`,
    'setup commitment at revision 2',
  );
  const setupScheduleAtRevision2 = setupSchedulesAtRevision2.find(
    (row) => row.metadata?.managed_by === 'setup',
  );
  if (
    !setupScheduleAtRevision2 ||
    setupScheduleAtRevision2.title !== setupCommitmentTitle ||
    setupScheduleAtRevision2.location !== 'Room E2E' ||
    setupScheduleAtRevision2.weekday !== 1 ||
    !String(setupScheduleAtRevision2.starts_at).startsWith('14:15') ||
    !String(setupScheduleAtRevision2.ends_at).startsWith('15:45') ||
    setupScheduleAtRevision2.source !== 'onboarding' ||
    setupScheduleAtRevision2.metadata?.source !== 'intake-v1' ||
    setupScheduleAtRevision2.metadata?.setup_state !== 'active' ||
    setupScheduleAtRevision2.metadata?.setup_item_id !== commitmentKey ||
    setupScheduleAtRevision2.metadata?.revision !== 2
  ) {
    throw new Error(
      `Unexpected revision 2 setup commitment: ${JSON.stringify(setupSchedulesAtRevision2)}`,
    );
  }
  if (
    setupSchedulesAtRevision2.some(
      (row) => row.id === legacyDefaultSchedule.id,
    ) ||
    !setupSchedulesAtRevision2.some(
      (row) =>
        row.id === legacyExplicitSchedule.id &&
        row.title === legacyExplicitScheduleTitle &&
        row.source === 'onboarding',
    )
  ) {
    throw new Error(
      `Legacy default cleanup changed the wrong schedules: ${JSON.stringify(setupSchedulesAtRevision2)}`,
    );
  }
  await assertRows(
    `habits?select=id,title,active,metadata&user_id=eq.${user.id}`,
    (rows) => !rows.some((row) => row.metadata?.managed_by === 'setup'),
    'no habit row for a routine candidate',
  );

  await clickByText(page, 'Setup and commitments');
  await expectText(page, 'Review your setup');
  await expectText(page, setupGoalTitle);
  await scrollFlutterPage(page, 700);
  await expectText(page, setupRoutineTitle);
  await scrollFlutterPage(page, 1400);
  await expectText(page, setupCommitmentTitle);
  await scrollFlutterPage(page, -2800);
  // Flutter Web does not automatically scroll its internal viewport when
  // Playwright focuses a semantics node near the fold. Keep the existing goal
  // editor clear of the required-setup dropdown before editing it.
  await scrollFlutterPage(page, 500);
  await fillByLabelOrPlaceholder(page, 'Goal title', editedSetupGoalTitle, 1);
  await scrollFlutterPage(page, 700);
  await selectDropdownOption(
    page,
    'Cadence (required before activation)',
    'Weekly',
  );
  // A Flutter Web dropdown overlay can remain visually open after its
  // semantics option reports the click. Close any retained overlay before the
  // adjacent numeric field is focused.
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  await fillByLabelOrPlaceholder(page, 'Weekly target (1–7)', '3', 4);
  await selectDropdownOption(page, 'Routine status', 'Active');
  await scrollFlutterPage(page, 1000);
  await fillByLabelOrPlaceholder(
    page,
    'Title',
    editedSetupCommitmentTitle,
    0,
  );
  await scrollFlutterPage(page, 1400);
  await clickByText(page, 'Save setup');
  await page.waitForURL('**/#/settings');
  await expectText(page, 'Settings');

  await waitForRows(
    `intake_responses?select=id,request_id,base_revision,revision,state,responses&user_id=eq.${user.id}&order=revision.asc`,
    (rows) =>
      rows.length === 3 &&
      rows[2].state === 'applied' &&
      rows[2].base_revision === 2 &&
      rows[2].revision === 3 &&
      rows[2].responses?.goals?.[0]?.key === goalKey &&
      rows[2].responses?.goals?.[0]?.title === editedSetupGoalTitle &&
      rows[2].responses?.routines?.[0]?.key === routineKey &&
      rows[2].responses?.routines?.[0]?.status === 'active' &&
      rows[2].responses?.routines?.[0]?.cadence_confirmed === true &&
      rows[2].responses?.routines?.[0]?.frequency === 'weekly' &&
      rows[2].responses?.routines?.[0]?.target === 3 &&
      rows[2].responses?.fixed_commitments?.[0]?.key === commitmentKey &&
      rows[2].responses?.fixed_commitments?.[0]?.title ===
        editedSetupCommitmentTitle,
    'applied setup revision 3 with stable keys and confirmed routine',
  );
  const setupGoalsAtRevision3 = await fetchRows(
    `goals?select=id,title,status,metadata&user_id=eq.${user.id}`,
    'setup goal after revision 3 edit',
  );
  const setupGoalAtRevision3 = setupGoalsAtRevision3.find(
    (row) => row.metadata?.managed_by === 'setup',
  );
  const setupSchedulesAtRevision3 = await fetchRows(
    `schedule_items?select=id,title,source,metadata&user_id=eq.${user.id}`,
    'setup commitment after revision 3 edit',
  );
  const setupScheduleAtRevision3 = setupSchedulesAtRevision3.find(
    (row) => row.metadata?.managed_by === 'setup',
  );
  if (
    setupGoalAtRevision3?.id !== setupGoalAtRevision2.id ||
    setupGoalAtRevision3?.title !== editedSetupGoalTitle ||
    setupScheduleAtRevision3?.id !== setupScheduleAtRevision2.id ||
    setupScheduleAtRevision3?.title !== editedSetupCommitmentTitle
  ) {
    throw new Error(
      `Setup edit replaced stable DB identity. Goals ${JSON.stringify(setupGoalsAtRevision3)}, schedules ${JSON.stringify(setupSchedulesAtRevision3)}`,
    );
  }
  const setupHabitsAtRevision3 = await fetchRows(
    `habits?select=id,title,frequency,target,active,metadata&user_id=eq.${user.id}`,
    'active setup habit at revision 3',
  );
  const setupHabitAtRevision3 = setupHabitsAtRevision3.find(
    (row) => row.metadata?.managed_by === 'setup',
  );
  if (
    !setupHabitAtRevision3 ||
    setupHabitAtRevision3.title !== setupRoutineTitle ||
    setupHabitAtRevision3.frequency !== 'weekly' ||
    setupHabitAtRevision3.target !== 3 ||
    setupHabitAtRevision3.active !== true ||
    setupHabitAtRevision3.metadata?.setup_item_id !== routineKey ||
    setupHabitAtRevision3.metadata?.revision !== 3
  ) {
    throw new Error(
      `Unexpected activated setup habit: ${JSON.stringify(setupHabitsAtRevision3)}`,
    );
  }

  const [manualGoal] = await insertRows('goals', [
    {
      user_id: user.id,
      title: manualGoalTitle,
      status: 'active',
      metadata: { source: 'manual-e2e' },
    },
  ]);
  const [manualHabit] = await insertRows('habits', [
    {
      user_id: user.id,
      title: manualHabitTitle,
      frequency: 'daily',
      target: 1,
      active: false,
      metadata: { source: 'manual-e2e' },
    },
  ]);
  const [manualSchedule] = await insertRows('schedule_items', [
    {
      user_id: user.id,
      title: manualScheduleTitle,
      weekday: 5,
      starts_at: '17:00',
      ends_at: '18:00',
      source: 'manual',
      metadata: { source: 'manual-e2e' },
    },
  ]);

  await clickByText(page, 'Setup and commitments');
  await expectText(page, 'Review your setup');
  await expectText(page, editedSetupGoalTitle);
  await scrollFlutterPage(page, 700);
  await expectText(page, setupRoutineTitle);
  await scrollFlutterPage(page, 1400);
  await expectText(page, editedSetupCommitmentTitle);
  await scrollFlutterPage(page, -2800);
  await selectDropdownOption(page, 'Goal status', 'Archived');
  await scrollFlutterPage(page, 700);
  await selectDropdownOption(page, 'Routine status', 'Archived');
  await scrollFlutterPage(page, 1200);
  await selectDropdownOption(page, 'Commitment status', 'Archived');
  await scrollFlutterPage(page, 1600);
  await clickByText(page, 'Save setup');
  await page.waitForURL('**/#/settings');
  await expectText(page, 'Settings');

  await waitForRows(
    `intake_responses?select=id,base_revision,revision,state,responses&user_id=eq.${user.id}&order=revision.asc`,
    (rows) =>
      rows.length === 4 &&
      rows[3].state === 'applied' &&
      rows[3].base_revision === 3 &&
      rows[3].revision === 4 &&
      rows[3].responses?.goals?.[0]?.status === 'archived' &&
      rows[3].responses?.routines?.[0]?.status === 'archived' &&
      rows[3].responses?.fixed_commitments?.[0]?.status === 'archived',
    'applied revision 4 archives setup-owned records',
  );
  await assertRows(
    `goals?select=id,title,status,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.id === setupGoalAtRevision2.id &&
          row.status === 'archived' &&
          row.metadata?.setup_state === 'archived' &&
          row.metadata?.revision === 4,
      ) &&
      rows.some(
        (row) =>
          row.id === manualGoal.id &&
          row.title === manualGoalTitle &&
          row.status === 'active' &&
          row.metadata?.source === 'manual-e2e',
      ),
    'archived setup goal and preserved manual goal',
  );
  await assertRows(
    `habits?select=id,title,frequency,target,active,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.id === setupHabitAtRevision3.id &&
          row.active === false &&
          row.metadata?.setup_state === 'archived' &&
          row.metadata?.revision === 4,
      ) &&
      rows.some(
        (row) =>
          row.id === manualHabit.id &&
          row.title === manualHabitTitle &&
          row.active === false &&
          row.metadata?.source === 'manual-e2e',
      ),
    'archived setup habit and preserved manual habit',
  );
  await assertRows(
    `schedule_items?select=id,title,source,metadata&user_id=eq.${user.id}`,
    (rows) =>
      !rows.some((row) => row.id === setupScheduleAtRevision2.id) &&
      rows.some(
        (row) =>
          row.id === legacyExplicitSchedule.id &&
          row.title === legacyExplicitScheduleTitle &&
          row.source === 'onboarding',
      ) &&
      rows.some(
        (row) =>
          row.id === manualSchedule.id &&
          row.title === manualScheduleTitle &&
          row.source === 'manual' &&
          row.metadata?.source === 'manual-e2e',
      ),
    'removed setup commitment and preserved manual and explicit legacy schedules',
  );
  await waitForRows(
    `profiles?select=id,setup_revision&id=eq.${user.id}`,
    (rows) => rows.length === 1 && rows[0].setup_revision === 4,
    'profile projection at setup revision 4',
  );

  await page.goto(appRoute('/habits'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Habit management');
  await clickByText(page, 'Add habit');
  await fillByLabelOrPlaceholder(page, 'Title', managedHabitTitle, 0);
  await fillByLabelOrPlaceholder(
    page,
    'Description optional',
    'Created through browser smoke',
    1,
  );
  let lostHabitCreateResponseCount = 0;
  const loseCommittedHabitCreateResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'POST' || lostHabitCreateResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Habit response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostHabitCreateResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/habits**',
    loseCommittedHabitCreateResponse,
  );
  await clickByText(page, 'Save habit');
  await expectText(page, 'Could not add habit. Your draft is retained.');
  await clickByText(page, 'Retry');
  await expectText(page, 'Habit added.');
  await page.unroute(
    '**/rest/v1/habits**',
    loseCommittedHabitCreateResponse,
  );
  if (lostHabitCreateResponseCount !== 1) {
    throw new Error('Habit response-loss path was not exercised exactly once.');
  }
  await waitForRows(
    `habits?select=id,title,frequency,target,active,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.title === managedHabitTitle &&
          row.frequency === 'daily' &&
          row.target === 1 &&
          row.active === true &&
          row.metadata?.source === 'flutter-habit-management-v1' &&
          row.metadata?.contract_version === 'habit-v1' &&
          row.metadata?.cadence === 'daily' &&
          row.metadata?.lifecycle === 'active',
      ),
    'habit row created from Habit management',
  );
  const managedHabitRows = await fetchRows(
    `habits?select=id,title,frequency,target,active,metadata&user_id=eq.${user.id}&title=eq.${encodeURIComponent(managedHabitTitle)}`,
    'managed Phase 3 habit identity',
  );
  if (managedHabitRows.length !== 1) {
    throw new Error(
      `Expected one managed Phase 3 habit: ${JSON.stringify(managedHabitRows)}`,
    );
  }
  const managedHabit = managedHabitRows[0];
  const [setupExecutionHabit] = await insertRows('habits', [
    {
      user_id: user.id,
      title: setupExecutionHabitTitle,
      frequency: 'daily',
      target: 1,
      active: true,
      metadata: {
        source: 'intake-v1',
        managed_by: 'setup',
        setup_state: 'active',
        setup_item_id: crypto.randomUUID(),
        revision: 4,
        contract_version: 'habit-v1',
        cadence: 'daily',
      },
    },
  ]);
  const setupExecutionHabitDefinition = JSON.stringify({
    title: setupExecutionHabit.title,
    frequency: setupExecutionHabit.frequency,
    target: setupExecutionHabit.target,
    active: setupExecutionHabit.active,
    metadata: setupExecutionHabit.metadata,
  });

  const captureSideEffectsBefore = await captureSideEffectIds(user.id);
  const captureSnapshotRequests = [];
  const captureRecommendationGenerateRequests = [];
  const captureRequestObserver = (request) => {
    if (request.method() !== 'POST') {
      return;
    }
    if (request.url() === `${aiServiceBaseUrl}/v1/snapshots/generate`) {
      captureSnapshotRequests.push(request);
    }
    if (request.url() === `${aiServiceBaseUrl}/v1/recommendations/generate`) {
      captureRecommendationGenerateRequests.push(request);
    }
  };
  page.on('request', captureRequestObserver);

  let lostDailyLogPayload;
  let lostDailyLogResponseCount = 0;
  const loseCommittedDailyLogResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'POST' || lostDailyLogResponseCount > 0) {
      await route.continue();
      return;
    }
    lostDailyLogPayload = request.postDataJSON();
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Evening response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostDailyLogResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/daily_logs**',
    loseCommittedDailyLogResponse,
  );

  await page.goto(appRoute('/daily-check-in'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await page.waitForURL('**/#/quick-mood-check-in');
  await clickByRoleName(page, 'button', 'evening mood 2 of 10');
  await clickByRoleName(page, 'button', 'evening energy 9 of 10');
  await clickByRoleName(page, 'button', 'evening stress 8 of 10');
  await clickByText(page, 'Next');
  await clickScrolledByLabel(page, 'primary friction emotional_load');
  await assertFlutterTextAbsent(
    page,
    'Make tomorrow gentler',
    'removed Evening gentler control',
  );
  await clickScrolledByLabel(page, 'additional friction interruptions');
  await expectText(page, '1 of 2 selected.');
  await clickScrolledByLabel(page, 'additional friction hard_to_start');
  await expectText(
    page,
    '2 of 2 selected. Remove one to choose another.',
  );
  await clickScrolledByLabel(page, 'stress source private_emotional');
  await expectText(
    page,
    '2 of 2 selected. Remove one to choose another.',
  );
  await clickScrolledByLabel(
    page,
    'stress influence hardly_controllable',
  );
  await expectText(
    page,
    '2 of 2 selected. Remove one to choose another.',
  );
  await stabilizeLabeledControl(
    page,
    'Possible priority tomorrow (optional)',
  );
  await fillByLabelOrPlaceholder(
    page,
    'Possible priority tomorrow (optional)',
    `  ${eveningTomorrowPriority}  `,
    0,
  );
  await expectText(
    page,
    '2 of 2 selected. Remove one to choose another.',
  );
  await clickByText(page, 'Save evening check-in');
  await expectText(
    page,
    'Could not save. Your answers are still here. Try again.',
  );
  await page.unroute(
    '**/rest/v1/daily_logs**',
    loseCommittedDailyLogResponse,
  );

  if (lostDailyLogResponseCount !== 1 || !lostDailyLogPayload) {
    throw new Error('The committed daily_logs response loss was not exercised.');
  }
  const lostDailyLogRow = Array.isArray(lostDailyLogPayload)
    ? lostDailyLogPayload[0]
    : lostDailyLogPayload;
  const captureEntryDate = lostDailyLogRow?.entry_date;
  const eveningCaptureId =
    lostDailyLogRow?.metadata?.captures?.evening?.capture_id;
  if (!captureEntryDate || !eveningCaptureId) {
    throw new Error(
      `Lost daily_logs payload had no Phase 1 identity: ${JSON.stringify(lostDailyLogPayload)}`,
    );
  }

  const dailyCaptureSelect =
    'id,entry_date,source,sleep_hours,energy_level,stress_level,mood_score,' +
    'mood_label,steps,activity_level,screen_time_hours,focus_minutes,' +
    'nutrition_notes,day_focus,reflection,metadata';
  const dailyCapturePath =
    `daily_logs?select=${dailyCaptureSelect}&user_id=eq.${user.id}` +
    `&entry_date=eq.${captureEntryDate}`;
  await waitForRows(
    dailyCapturePath,
    (rows) =>
      rows.length === 1 &&
      hasExactPhaseOneDailyRow(rows[0], {
        entryDate: captureEntryDate,
        eveningCaptureId,
        stressSource: 'private_emotional',
        stressControllability: 'hardly_controllable',
        tomorrowPriority: eveningTomorrowPriority,
        expectMorning: false,
      }),
    'one committed required-only evening check-in row after lost response',
  );

  const eveningRetrySnapshotPromise = waitForAiPost(
    page,
    '/v1/snapshots/generate',
    'Evening retry snapshot refresh',
  );
  await clickByText(page, 'Save evening check-in');
  const eveningRetrySnapshotResponse = await eveningRetrySnapshotPromise;
  assertJsonPayload(
    eveningRetrySnapshotResponse.request(),
    {
      scope: 'daily',
      window_days: 7,
      target_date: captureEntryDate,
    },
    'Evening retry snapshot refresh payload',
  );
  await expectText(page, 'Today at a glance');
  await waitForRows(
    dailyCapturePath,
    (rows) =>
      rows.length === 1 &&
      hasExactPhaseOneDailyRow(rows[0], {
        entryDate: captureEntryDate,
        eveningCaptureId,
        stressSource: 'private_emotional',
        stressControllability: 'hardly_controllable',
        tomorrowPriority: eveningTomorrowPriority,
        expectMorning: false,
      }),
    'one evening check-in row after exact retry',
  );
  const eveningOnlyRows = await fetchRows(
    dailyCapturePath,
    'evening check-in row after retry',
  );
  const dailyLogId = eveningOnlyRows[0].id;
  const eveningDailyState = await assertPhaseTwoDailyStateResponse(
    eveningRetrySnapshotResponse,
    {
      mode: 'recover',
      dataQuality: 'partial',
      eveningFreshness: 'current',
      morningFreshness: 'missing',
      stressIntensity: 8,
      stressSource: 'private_emotional',
      stressControllability: 'hardly_controllable',
      mainFriction: 'emotional_load',
      additionalFrictions: eveningAdditionalFrictions,
      expectedRisks: [
        'private_emotional_stress',
        'low_controllability',
        'high_stress',
      ],
      forbiddenRisks: ['workload_pressure'],
      evidenceDailyLogId: dailyLogId,
      forbiddenTexts: [eveningTomorrowPriority],
    },
  );
  await waitForRows(
    `behavioral_events?select=id,daily_log_id,event_type,value,unit,source,metadata&daily_log_id=eq.${dailyLogId}&source=eq.quick_check_in`,
    (rows) =>
      hasExactEveningOnlyEvents(rows, {
        dailyLogId,
        entryDate: captureEntryDate,
        eveningCaptureId,
        stressSource: 'private_emotional',
        stressControllability: 'hardly_controllable',
        tomorrowPriority: eveningTomorrowPriority,
      }),
    'three deduplicated current events after Evening retry',
  );

  await page.goto(appRoute('/morning-calibration'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByRoleName(page, 'button', 'morning sleep 5.5 h');
  await clickByRoleNameUntilText(
    page,
    'button',
    'morning sleep quality 3 of 10',
    '3 / 10',
  );
  await clickByRoleNameUntilText(
    page,
    'button',
    'morning energy 4 of 10',
    '4 / 10',
  );
  await clickScrolledByLabel(page, 'day shape constrained');
  const morningSnapshotResponse = await clickAndWaitForAiPost(
    page,
    '/v1/snapshots/generate',
    'morning check-in snapshot refresh',
    'Save morning check-in',
  );
  assertJsonPayload(
    morningSnapshotResponse.request(),
    {
      scope: 'daily',
      window_days: 7,
      target_date: captureEntryDate,
    },
    'morning check-in snapshot refresh payload',
  );
  const morningDailyState = await assertPhaseTwoDailyStateResponse(
    morningSnapshotResponse,
    {
      mode: 'recover',
      dataQuality: 'current',
      eveningFreshness: 'current',
      morningFreshness: 'current',
      stressIntensity: 8,
      stressSource: 'private_emotional',
      stressControllability: 'hardly_controllable',
      mainFriction: 'emotional_load',
      additionalFrictions: eveningAdditionalFrictions,
      sleepHours: 5.5,
      sleepQuality: 3,
      currentEnergy: 4,
      dayShape: 'constrained',
      expectedRisks: [
        'private_emotional_stress',
        'low_controllability',
        'low_sleep',
        'low_sleep_quality',
        'constrained_capacity',
      ],
      forbiddenRisks: ['workload_pressure'],
      evidenceDailyLogId: dailyLogId,
      forbiddenTexts: [eveningTomorrowPriority],
    },
  );
  if (morningDailyState.snapshotId !== eveningDailyState.snapshotId) {
    throw new Error(
      `Morning refresh replaced the daily snapshot identity: ${JSON.stringify({ eveningDailyState, morningDailyState })}`,
    );
  }
  await expectText(page, 'Today at a glance');

  await waitForRows(
    dailyCapturePath,
    (rows) =>
      rows.length === 1 &&
      hasExactPhaseOneDailyRow(rows[0], {
        entryDate: captureEntryDate,
        eveningCaptureId,
        stressSource: 'private_emotional',
        stressControllability: 'hardly_controllable',
        tomorrowPriority: eveningTomorrowPriority,
        expectMorning: true,
      }),
    'one merged Evening and Morning daily row',
  );
  let mergedCaptureRows = await fetchRows(
    dailyCapturePath,
    'merged Evening and Morning daily row',
  );
  const morningCaptureId =
    mergedCaptureRows[0].metadata?.captures?.morning?.capture_id;
  if (!morningCaptureId) {
    throw new Error(
      `Merged daily row has no Morning capture id: ${JSON.stringify(mergedCaptureRows)}`,
    );
  }
  await waitForRows(
    `behavioral_events?select=id,daily_log_id,event_type,value,unit,source,metadata&daily_log_id=eq.${dailyLogId}&source=eq.quick_check_in`,
    (rows) =>
      hasExactPhaseOneEvents(rows, {
        dailyLogId,
        entryDate: captureEntryDate,
        eveningCaptureId,
        morningCaptureId,
        stressSource: 'private_emotional',
        stressControllability: 'hardly_controllable',
        tomorrowPriority: eveningTomorrowPriority,
      }),
    'four exact merged current events after morning check-in',
  );

  await page.goto(appRoute('/quick-mood-check-in'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(
    page,
    "Today's evening check-in is loaded. Saving updates only these evening answers.",
  );
  await clickByText(page, 'Next');
  await clickScrolledByLabel(page, 'stress source workload');
  await clickScrolledByLabel(
    page,
    'stress influence mostly_controllable',
  );
  await expectText(
    page,
    '2 of 2 selected. Remove one to choose another.',
  );
  await stabilizeLabeledControl(
    page,
    'Possible priority tomorrow (optional)',
  );
  await fillByLabelOrPlaceholder(
    page,
    'Possible priority tomorrow (optional)',
    editedEveningTomorrowPriority,
    0,
  );
  await expectFieldValue(page, 'Reflection (optional)', '', 0);
  await expectFieldValue(page, 'Specific blocker (optional)', '', 1);
  const eveningEditSnapshotPromise = waitForAiPost(
    page,
    '/v1/snapshots/generate',
    'Evening edit snapshot refresh',
  );
  await clickByText(page, 'Save evening check-in');
  const eveningEditSnapshotResponse = await eveningEditSnapshotPromise;
  assertJsonPayload(
    eveningEditSnapshotResponse.request(),
    {
      scope: 'daily',
      window_days: 7,
      target_date: captureEntryDate,
    },
    'Evening edit snapshot refresh payload',
  );
  const editedDailyState = await assertPhaseTwoDailyStateResponse(
    eveningEditSnapshotResponse,
    {
      mode: 'recover',
      dataQuality: 'current',
      eveningFreshness: 'current',
      morningFreshness: 'current',
      stressIntensity: 8,
      stressSource: 'workload',
      stressControllability: 'mostly_controllable',
      mainFriction: 'emotional_load',
      additionalFrictions: eveningAdditionalFrictions,
      sleepHours: 5.5,
      sleepQuality: 3,
      currentEnergy: 4,
      dayShape: 'constrained',
      expectedRisks: [
        'workload_pressure',
        'high_stress',
        'low_sleep',
        'low_sleep_quality',
        'constrained_capacity',
      ],
      forbiddenRisks: [
        'private_emotional_stress',
        'low_controllability',
      ],
      evidenceDailyLogId: dailyLogId,
      forbiddenTexts: [
        eveningTomorrowPriority,
        editedEveningTomorrowPriority,
      ],
    },
  );
  if (editedDailyState.snapshotId !== eveningDailyState.snapshotId) {
    throw new Error(
      `Evening edit replaced the daily snapshot identity: ${JSON.stringify({ eveningDailyState, editedDailyState })}`,
    );
  }
  await expectText(page, 'Today at a glance');
  await scrollUntilTextInViewport(page, 'More', {
    deltaY: 500,
    buttonFirst: true,
  });
  await clickByText(page, 'More');
  await expectText(page, 'Latest check-in');
  await expectText(page, 'Morning energy');
  await expectText(page, '4/10');
  await expectText(page, '5.5 h');
  await expectText(page, 'Sleep quality');
  await expectText(page, '3/10');

  await waitForRows(
    dailyCapturePath,
    (rows) =>
      rows.length === 1 &&
      hasExactPhaseOneDailyRow(rows[0], {
        entryDate: captureEntryDate,
        eveningCaptureId,
        morningCaptureId,
        stressSource: 'workload',
        stressControllability: 'mostly_controllable',
        tomorrowPriority: editedEveningTomorrowPriority,
        expectMorning: true,
      }),
    'one merged daily row after Evening edit',
  );
  mergedCaptureRows = await fetchRows(
    dailyCapturePath,
    'merged daily row after Evening edit',
  );
  if (
    mergedCaptureRows[0].metadata?.captures?.morning?.capture_id !==
    morningCaptureId
  ) {
    throw new Error(
      `Evening edit replaced the Morning capture: ${JSON.stringify(mergedCaptureRows)}`,
    );
  }
  await waitForRows(
    `behavioral_events?select=id,daily_log_id,event_type,value,unit,source,metadata&daily_log_id=eq.${dailyLogId}&source=eq.quick_check_in`,
    (rows) =>
      hasExactPhaseOneEvents(rows, {
        dailyLogId,
        entryDate: captureEntryDate,
        eveningCaptureId,
        morningCaptureId,
        stressSource: 'workload',
        stressControllability: 'mostly_controllable',
        tomorrowPriority: editedEveningTomorrowPriority,
      }),
    'four deduplicated current events after Evening edit',
  );

  page.off('request', captureRequestObserver);
  if (captureSnapshotRequests.length !== 3) {
    throw new Error(
      `Expected three successful capture snapshot refreshes, got ${captureSnapshotRequests.length}.`,
    );
  }
  if (captureRecommendationGenerateRequests.length !== 0) {
    throw new Error(
      `Normal capture generated recommendations: ${captureRecommendationGenerateRequests.map((request) => request.url()).join(', ')}`,
    );
  }
  const captureSideEffectsAfter = await captureSideEffectIds(user.id);
  if (
    JSON.stringify(captureSideEffectsAfter) !==
    JSON.stringify(captureSideEffectsBefore)
  ) {
    throw new Error(
      `Blank capture optionals materialized unrelated rows. Before ${JSON.stringify(captureSideEffectsBefore)}, after ${JSON.stringify(captureSideEffectsAfter)}`,
    );
  }
  await assertRows(
    `intake_responses?select=id,revision,state&user_id=eq.${user.id}&version=eq.intake-v1&order=revision.asc`,
    (rows) =>
      rows.length === 4 &&
      rows[3].revision === 4 &&
      rows[3].state === 'applied',
    'unchanged Setup revisions after Phase 1 capture',
  );
  await assertRows(
    `profiles?select=id,setup_revision&id=eq.${user.id}`,
    (rows) => rows.length === 1 && rows[0].setup_revision === 4,
    'unchanged Setup projection after Phase 1 capture',
  );
  await waitForRows(
    `user_state_snapshots?select=id,scope,period_key,summary,signals,metadata&user_id=eq.${user.id}&scope=eq.daily&period_key=eq.${captureEntryDate}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].metadata?.source === 'snapshot-aggregator-v1' &&
      rows[0].metadata?.daily_state_contract_version ===
        'explainable-daily-state-v1' &&
      rows[0].summary?.daily_state?.mode === 'recover' &&
      rows[0].summary?.daily_state?.data_quality === 'current' &&
      rows[0].summary?.daily_state?.context?.stress?.source === 'workload' &&
      rows[0].summary?.daily_state?.context?.stress?.controllability ===
        'mostly_controllable' &&
      rows[0].summary?.daily_state?.context?.sleep_hours === 5.5 &&
      rows[0].summary?.daily_state?.context?.sleep_quality === 3 &&
      rows[0].summary?.daily_state?.context?.current_energy === 4 &&
      rows[0].summary?.daily_state?.context?.day_shape === 'constrained' &&
      rows[0].summary?.daily_state?.risk_flags?.includes('low_sleep') &&
      rows[0].summary?.daily_state?.risk_flags?.includes(
        'low_sleep_quality',
      ) &&
      rows[0].summary?.daily_state?.risk_flags?.includes(
        'workload_pressure',
      ) &&
      !rows[0].summary?.daily_state?.risk_flags?.includes(
        'private_emotional_stress',
      ) &&
      !JSON.stringify(rows[0]).includes(eveningTomorrowPriority) &&
      !JSON.stringify(rows[0]).includes(editedEveningTomorrowPriority) &&
      rows[0].signals?.input_counts?.daily_logs >= 1 &&
      rows[0].signals?.input_counts?.behavioral_events >= 4,
    'one daily snapshot refreshed from merged Phase 1 capture',
  );

  const dailySnapshotBeforeActions =
    await latestDailySnapshotGeneratedAt(user.id);
  const actionRecommendationRequests = [];
  const actionRequestObserver = (request) => {
    if (
      request.method() === 'POST' &&
      request.url() === `${aiServiceBaseUrl}/v1/recommendations/generate`
    ) {
      actionRecommendationRequests.push(request);
    }
  };
  page.on('request', actionRequestObserver);

  await page.goto(appRoute('/habit-completion'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Today habits');
  let lostHabitOutcomeResponseCount = 0;
  const loseCommittedHabitOutcomeResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'POST' || lostHabitOutcomeResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Habit outcome response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostHabitOutcomeResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/habit_logs**',
    loseCommittedHabitOutcomeResponse,
  );
  await clickByRoleName(
    page,
    'button',
    `Complete habit ${managedHabitTitle}`,
  );
  await expectText(page, 'Habit completed.');
  await page.unroute(
    '**/rest/v1/habit_logs**',
    loseCommittedHabitOutcomeResponse,
  );
  if (lostHabitOutcomeResponseCount !== 1) {
    throw new Error(
      'Habit outcome response-loss path was not exercised exactly once.',
    );
  }
  await waitForRows(
    `habit_logs?select=id,habit_id,entry_date,status,value,updated_at&user_id=eq.${user.id}&habit_id=eq.${managedHabit.id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].entry_date === captureEntryDate &&
      rows[0].status === 'completed' &&
      rows[0].value === 1 &&
      isIsoTimestamp(rows[0].updated_at),
    'one explicit completed Habit V1 outcome',
  );
  let lostHabitUndoResponseCount = 0;
  const loseCommittedHabitUndoResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'DELETE' || lostHabitUndoResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Habit undo response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostHabitUndoResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/habit_logs**',
    loseCommittedHabitUndoResponse,
  );
  await clickByRoleName(
    page,
    'button',
    `Undo habit ${managedHabitTitle}`,
  );
  await expectText(page, 'Habit outcome undone.');
  await page.unroute(
    '**/rest/v1/habit_logs**',
    loseCommittedHabitUndoResponse,
  );
  if (lostHabitUndoResponseCount !== 1) {
    throw new Error(
      'Habit undo response-loss path was not exercised exactly once.',
    );
  }
  await waitForRows(
    `habit_logs?select=id&user_id=eq.${user.id}&habit_id=eq.${managedHabit.id}`,
    (rows) => rows.length === 0,
    'Habit V1 completion undo restores open state',
  );
  await clickByRoleName(
    page,
    'button',
    `Skip habit ${managedHabitTitle}`,
  );
  await waitForRows(
    `habit_logs?select=id,habit_id,entry_date,status,value&user_id=eq.${user.id}&habit_id=eq.${managedHabit.id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].entry_date === captureEntryDate &&
      rows[0].status === 'skipped' &&
      rows[0].value === 0,
    'one explicit intentionally skipped Habit V1 outcome',
  );
  await clickByRoleName(
    page,
    'button',
    `Undo habit ${managedHabitTitle}`,
  );
  await waitForRows(
    `habit_logs?select=id&user_id=eq.${user.id}&habit_id=eq.${managedHabit.id}`,
    (rows) => rows.length === 0,
    'Habit V1 skip undo restores open state',
  );

  await clickByRoleName(
    page,
    'button',
    `Complete habit ${setupExecutionHabitTitle}`,
  );
  await waitForRows(
    `habit_logs?select=id,habit_id,entry_date,status,value&user_id=eq.${user.id}&habit_id=eq.${setupExecutionHabit.id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'completed' &&
      rows[0].value === 1,
    'active Setup-owned habit is executable',
  );
  const setupExecutionHabitAfterOutcome = await fetchRows(
    `habits?select=id,title,frequency,target,active,metadata&id=eq.${setupExecutionHabit.id}`,
    'Setup-owned habit definition after daily execution',
  );
  if (
    setupExecutionHabitAfterOutcome.length !== 1 ||
    JSON.stringify({
      title: setupExecutionHabitAfterOutcome[0].title,
      frequency: setupExecutionHabitAfterOutcome[0].frequency,
      target: setupExecutionHabitAfterOutcome[0].target,
      active: setupExecutionHabitAfterOutcome[0].active,
      metadata: setupExecutionHabitAfterOutcome[0].metadata,
    }) !== setupExecutionHabitDefinition
  ) {
    throw new Error(
      `Daily execution changed a Setup-owned definition: ${JSON.stringify(setupExecutionHabitAfterOutcome)}`,
    );
  }
  await clickByRoleName(
    page,
    'button',
    `Undo habit ${setupExecutionHabitTitle}`,
  );
  await waitForRows(
    `habit_logs?select=id&user_id=eq.${user.id}&habit_id=eq.${setupExecutionHabit.id}`,
    (rows) => rows.length === 0,
    'Setup-owned habit outcome undo restores open state',
  );

  await page.goto(appRoute('/planner'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByRoleName(page, 'button', 'Task');
  await fillByLabelOrPlaceholder(page, 'Title *', phase3TaskTitle, 0);
  await fillByLabelOrPlaceholder(
    page,
    'Description (optional)',
    'Distinctive Phase 3 browser task',
    1,
  );
  await selectDropdownOption(page, 'Priority', 'High');
  await clickByText(page, 'Save as unscheduled');
  await expectText(page, 'Review plan preview');
  await expectText(page, 'No time is reserved in this preview.');
  await clickByText(page, 'Confirm plan');
  await expectText(page, 'Saved under Unscheduled.');
  const phase3TaskRows = await waitForRows(
    `tasks?select=id,title,description,status,priority,deadline,estimated_minutes,completed_at,cancelled_at,source,metadata&user_id=eq.${user.id}&title=eq.${encodeURIComponent(phase3TaskTitle)}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].description === 'Distinctive Phase 3 browser task' &&
      rows[0].status === 'todo' &&
      rows[0].priority === 'high' &&
      rows[0].deadline === null &&
      rows[0].estimated_minutes === null &&
      rows[0].completed_at === null &&
      rows[0].cancelled_at === null &&
      rows[0].source === 'planner-v1' &&
      rows[0].metadata?.source === 'planner-v1' &&
      rows[0].metadata?.contract_version === 'executable-task-v1' &&
      isUuid(rows[0].metadata?.planner_plan_id) &&
      rows[0].metadata?.preferred_session_minutes === null,
    'explicitly unscheduled Task confirmed through Planner',
  );
  const phase3TaskId = phase3TaskRows[0].id;
  if (!isUuid(phase3TaskId)) {
    throw new Error(`Task did not use a client-stable UUID: ${phase3TaskId}`);
  }

  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await scrollUntilTextInViewport(page, 'Show all tasks', {
    deltaY: 500,
    buttonFirst: true,
  });
  await clickByText(page, 'Show all tasks');
  await scrollUntilTextInViewport(page, phase3TaskTitle, { deltaY: 400 });

  let lostTaskTransitionResponseCount = 0;
  const loseCommittedTaskTransitionResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'PATCH' || lostTaskTransitionResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Task transition response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostTaskTransitionResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/tasks**',
    loseCommittedTaskTransitionResponse,
  );
  await scrollFlutterPage(page, 1600);
  await clickByRoleName(
    page,
    'button',
    `Complete task ${phase3TaskTitle}`,
  );
  await expectText(page, 'Task completed.');
  await page.unroute(
    '**/rest/v1/tasks**',
    loseCommittedTaskTransitionResponse,
  );
  if (lostTaskTransitionResponseCount !== 1) {
    throw new Error(
      'Task transition response-loss path was not exercised exactly once.',
    );
  }
  await waitForRows(
    `tasks?select=id,status,completed_at,cancelled_at&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'done' &&
      isIsoTimestamp(rows[0].completed_at) &&
      rows[0].cancelled_at === null,
    'task completion writes terminal state and timestamp',
  );
  let lostTaskUndoResponseCount = 0;
  const loseCommittedTaskUndoResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'PATCH' || lostTaskUndoResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Task undo response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostTaskUndoResponseCount += 1;
    await route.abort('failed');
  };
  await page.route('**/rest/v1/tasks**', loseCommittedTaskUndoResponse);
  await clickByText(page, 'Undo', { match: 'last' });
  await expectText(page, 'Task change undone.');
  await page.unroute('**/rest/v1/tasks**', loseCommittedTaskUndoResponse);
  if (lostTaskUndoResponseCount !== 1) {
    throw new Error(
      'Task undo response-loss path was not exercised exactly once.',
    );
  }
  await waitForRows(
    `tasks?select=id,status,completed_at,cancelled_at&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'todo' &&
      rows[0].completed_at === null &&
      rows[0].cancelled_at === null,
    'task completion undo restores todo',
  );

  await assertInsertRejected(
    'tasks',
    [
      {
        id: crypto.randomUUID(),
        user_id: user.id,
        title: 'Invalid terminal task shape',
        status: 'done',
        priority: 'low',
        source: 'e2e-negative-check',
      },
    ],
    'task terminal state without its timestamp',
    'tasks_lifecycle_shape_check',
  );

  await scrollFlutterPage(page, 1600);
  await clickByRoleName(
    page,
    'button',
    `Focus on ${phase3TaskTitle}`,
  );
  await page.waitForURL('**/#/deep-work?target_kind=task&target_id=*');
  await expectText(page, 'Focus session');
  let lostFocusStartResponseCount = 0;
  const loseCommittedFocusStartResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'POST' || lostFocusStartResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Focus response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostFocusStartResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/focus_sessions**',
    loseCommittedFocusStartResponse,
  );
  await clickByText(page, 'Start focus session');
  await expectText(page, 'Prepare to focus');
  await expectText(
    page,
    'These choices are only for this start. They are not saved or evaluated.',
  );
  await clickByText(page, 'Skip remaining and start');
  await expectText(page, 'Focus session started.');
  await page.unroute(
    '**/rest/v1/focus_sessions**',
    loseCommittedFocusStartResponse,
  );
  if (lostFocusStartResponseCount !== 1) {
    throw new Error('Focus response-loss path was not exercised exactly once.');
  }
  const activeFocusRows = await waitForRows(
    `focus_sessions?select=id,status,started_at,ended_at,planned_minutes,actual_minutes,task_id,habit_id,metadata,updated_at&user_id=eq.${user.id}&status=eq.active`,
    (rows) =>
      rows.length === 1 &&
      rows[0].planned_minutes === 45 &&
      rows[0].task_id === phase3TaskId &&
      rows[0].habit_id === null &&
      rows[0].ended_at === null &&
      rows[0].actual_minutes === null &&
      rows[0].metadata?.recovery_minutes === 10 &&
      rows[0].metadata?.contract_version === 'focus-session-v1' &&
      rows[0].metadata?.action_target?.contract_version ===
        'executable-action-v1' &&
      rows[0].metadata?.action_target?.kind === 'focus' &&
      rows[0].metadata?.action_target?.command === 'start_focus' &&
      rows[0].metadata?.action_target?.estimated_minutes === 45 &&
      rows[0].metadata?.action_target?.target_id === phase3TaskId &&
      rows[0].metadata?.action_target?.metadata?.target_kind === 'task' &&
      rows[0].metadata?.action_target?.metadata?.focus_minutes === 45,
    'one task-linked active focus session',
  );
  const completedFocusId = activeFocusRows[0].id;
  await assertInsertRejected(
    'focus_sessions',
    [
      {
        id: crypto.randomUUID(),
        user_id: user.id,
        status: 'active',
        started_at: new Date().toISOString(),
        planned_minutes: 25,
        metadata: { source: 'e2e-negative-check' },
      },
    ],
    'second active focus session',
    'focus_sessions_one_active_per_user_idx',
  );
  let lostFocusFinishResponseCount = 0;
  const loseCommittedFocusFinishResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'PATCH' || lostFocusFinishResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Focus finish response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostFocusFinishResponseCount += 1;
    await route.abort('failed');
  };
  await page.route(
    '**/rest/v1/focus_sessions**',
    loseCommittedFocusFinishResponse,
  );
  await clickByText(page, 'Finish focus session');
  await expectText(
    page,
    'Focus session finished. Recovery started; linked actions were not completed automatically.',
  );
  await expectText(page, 'Recovery break');
  await expectText(
    page,
    'This local countdown is not a focus session and does not add progress or preparation time.',
  );
  await page.unroute(
    '**/rest/v1/focus_sessions**',
    loseCommittedFocusFinishResponse,
  );
  if (lostFocusFinishResponseCount !== 1) {
    throw new Error(
      'Focus finish response-loss path was not exercised exactly once.',
    );
  }
  await waitForRows(
    `focus_sessions?select=id,status,started_at,ended_at,planned_minutes,actual_minutes,task_id,habit_id&user_id=eq.${user.id}&id=eq.${completedFocusId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'completed' &&
      isIsoTimestamp(rows[0].ended_at) &&
      Number.isInteger(rows[0].actual_minutes) &&
      rows[0].actual_minutes >= 0 &&
      rows[0].task_id === phase3TaskId,
    'focus finish records measured duration',
  );
  await assertRows(
    `tasks?select=id,status&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) => rows.length === 1 && rows[0].status === 'todo',
    'focus finish does not complete its linked task',
  );
  await assertPatchRejected(
    `focus_sessions?id=eq.${completedFocusId}`,
    {
      ended_at: new Date(
        Date.parse(activeFocusRows[0].started_at) + 60_000,
      ).toISOString(),
      actual_minutes: 1,
    },
    'terminal focus lifecycle mutation',
    'A terminal focus session is immutable.',
  );
  await assertPatchRejected(
    `focus_sessions?id=eq.${completedFocusId}`,
    {
      metadata: {
        source: 'e2e-negative-check',
        entry_date: '2099-01-01',
      },
    },
    'terminal focus snapshot-date mutation',
    'A terminal focus session is immutable.',
  );
  await assertPatchRejected(
    `focus_sessions?id=eq.${completedFocusId}`,
    { updated_at: new Date().toISOString() },
    'terminal focus audit-timestamp mutation',
    'A terminal focus session is immutable.',
  );

  await clickByText(page, 'Skip recovery');
  await expectText(page, 'Independent focus block');
  await clickByText(page, 'Start focus session');
  await expectText(page, 'Prepare to focus');
  await clickByText(page, 'Skip remaining and start');
  const secondFocusRows = await waitForRows(
    `focus_sessions?select=id,status,planned_minutes,task_id,habit_id,metadata&user_id=eq.${user.id}&status=eq.active`,
    (rows) =>
      rows.length === 1 &&
      rows[0].planned_minutes === 45 &&
      rows[0].task_id === null &&
      rows[0].habit_id === null &&
      rows[0].metadata?.recovery_minutes === 10,
    'one independent active focus session after prior finish',
  );
  await clickByText(page, 'Abandon');
  await clickByText(page, 'Abandon session');
  await waitForRows(
    `focus_sessions?select=id,status,ended_at,actual_minutes&user_id=eq.${user.id}&id=eq.${secondFocusRows[0].id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'abandoned' &&
      isIsoTimestamp(rows[0].ended_at) &&
      Number.isInteger(rows[0].actual_minutes) &&
      rows[0].actual_minutes >= 0,
    'focus abandon records terminal lifecycle',
  );
  await assertRows(
    `focus_sessions?select=id&user_id=eq.${user.id}&status=eq.active`,
    (rows) => rows.length === 0,
    'no active focus session after abandon',
  );
  await assertInsertRejected(
    'focus_sessions',
    [
      {
        id: crypto.randomUUID(),
        user_id: user.id,
        status: 'active',
        started_at: new Date().toISOString(),
        planned_minutes: 4,
        metadata: { source: 'e2e-negative-check' },
      },
    ],
    'focus duration below the contract minimum',
    'focus_sessions_planned_minutes_check',
  );

  const inactiveHabitId = crypto.randomUUID();
  await insertRows('habits', [
    {
      id: inactiveHabitId,
      user_id: user.id,
      title: 'Inactive negative-check habit',
      frequency: 'daily',
      target: 1,
      active: false,
      metadata: {
        source: 'e2e-negative-check',
        lifecycle: 'paused',
      },
    },
  ]);
  await assertInsertRejected(
    'habit_logs',
    [
      {
        id: crypto.randomUUID(),
        user_id: user.id,
        habit_id: inactiveHabitId,
        entry_date: captureEntryDate,
        status: 'completed',
        value: 1,
      },
    ],
    'outcome for an inactive habit',
    'Habit log target is unavailable for this user and date.',
  );
  await deleteRows(
    `habits?id=eq.${inactiveHabitId}`,
    'inactive negative-check habit',
  );

  const currentIsoWeekday = ((new Date(
    `${captureEntryDate}T12:00:00Z`,
  ).getUTCDay() + 6) % 7) + 1;
  const otherIsoWeekday = currentIsoWeekday === 7 ? 1 : currentIsoWeekday + 1;
  const unscheduledHabitId = crypto.randomUUID();
  await insertRows('habits', [
    {
      id: unscheduledHabitId,
      user_id: user.id,
      title: 'Unscheduled negative-check habit',
      frequency: 'daily',
      target: 1,
      active: true,
      metadata: {
        source: 'e2e-negative-check',
        contract_version: 'habit-v1',
        cadence: 'weekdays',
        scheduled_weekdays: [otherIsoWeekday],
        lifecycle: 'active',
      },
    },
  ]);
  await assertInsertRejected(
    'habit_logs',
    [
      {
        id: crypto.randomUUID(),
        user_id: user.id,
        habit_id: unscheduledHabitId,
        entry_date: captureEntryDate,
        status: 'completed',
        value: 1,
      },
    ],
    'outcome outside the selected-weekday cadence',
    'Habit log target is unavailable for this user and date.',
  );
  await deleteRows(
    `habits?id=eq.${unscheduledHabitId}`,
    'unscheduled negative-check habit',
  );

  await waitForRows(
    `user_state_snapshots?select=id,scope,generated_at,summary,signals,metadata&user_id=eq.${user.id}&scope=eq.daily`,
    (rows) =>
      rows.some(
        (row) =>
          row.metadata?.source === 'snapshot-aggregator-v1' &&
          row.metadata?.daily_state_contract_version ===
            'explainable-daily-state-v1' &&
          row.summary?.daily_state?.mode === 'recover' &&
          row.summary?.daily_state?.data_quality === 'current' &&
          row.summary?.daily_state?.risk_flags?.includes('low_sleep') &&
          row.summary?.daily_state?.risk_flags?.includes(
            'low_sleep_quality',
          ) &&
          row.summary?.daily_state?.risk_flags?.includes(
            'workload_pressure',
          ) &&
          row.signals?.input_counts?.focus_sessions >= 2 &&
          row.summary?.focus_sessions?.status_counts?.completed >= 1 &&
          row.summary?.focus_sessions?.status_counts?.abandoned >= 1 &&
          Date.parse(row.generated_at) > dailySnapshotBeforeActions,
      ),
    'daily snapshot refresh includes neutral Phase 3 execution inputs',
  );
  page.off('request', actionRequestObserver);
  if (actionRecommendationRequests.length !== 0) {
    throw new Error(
      `Phase 3 action writes generated recommendations: ${actionRecommendationRequests.map((request) => request.url()).join(', ')}`,
    );
  }
  await assertRows(
    `profiles?select=id,setup_revision&id=eq.${user.id}`,
    (rows) => rows.length === 1 && rows[0].setup_revision === 4,
    'Phase 3 execution leaves the Setup revision unchanged',
  );

  await assertDeterministicDailyBriefing(user.id);
  await assertTodayOverview(user.id);

  const recommendationsBeforeManualRefresh =
    await activeDeterministicRecommendations(user.id);
  const dailySnapshotBeforeRecommendationRefresh =
    await latestDailySnapshotGeneratedAt(user.id);
  const dashboardBriefingPosts = [];
  const dashboardBriefingObserver = (request) => {
    if (
      request.method() === 'POST' &&
      request.url() === `${aiServiceBaseUrl}/v1/briefings/generate`
    ) {
      dashboardBriefingPosts.push(request);
    }
  };
  page.on('request', dashboardBriefingObserver);
  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Check-in streak');
  await expectText(page, "Today's progress");
  await expectText(page, 'Today at a glance');
  await expectText(page, "Today's tasks");
  await expectText(page, "Today's habits");
  await page.waitForTimeout(500);
  page.off('request', dashboardBriefingObserver);
  if (dashboardBriefingPosts.length !== 0) {
    throw new Error(
      `Normal Today load generated a briefing: ${dashboardBriefingPosts.map((request) => request.url()).join(', ')}`,
    );
  }

  await assertBoundedWeeklyReview(page, user.id);
  await assertDeadlinePlanner(page, user.id);
  await assertCentralPlanner(page, user.id);
  await assertBoundedCalendarImport(user.id);
  await assertCalendarImportUi(page, user.id);
  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await scrollUntilTextInViewport(page, 'More', {
    deltaY: 500,
    buttonFirst: true,
  });
  await clickByText(page, 'More');
  await scrollUntilTextInViewport(page, 'Refresh recommendations', {
    deltaY: 500,
    buttonFirst: true,
  });
  const [manualSnapshotResponse, manualRecommendationResponse] =
    await Promise.all([
      waitForAiPost(page, '/v1/snapshots/generate', 'manual snapshot refresh'),
      waitForAiPost(
        page,
        '/v1/recommendations/generate',
        'manual recommendation refresh',
      ),
      clickByText(page, 'Refresh recommendations'),
    ]);
  assertJsonPayload(
    manualSnapshotResponse.request(),
    {
      scope: 'daily',
      window_days: 7,
      target_date: captureEntryDate,
    },
    'manual snapshot refresh payload',
  );
  assertJsonPayload(
    manualRecommendationResponse.request(),
    {
      window_days: 28,
      force: false,
      allow_llm_wording: false,
    },
    'manual recommendation refresh payload',
  );
  await expectText(page, 'Recommendations checked.');
  await waitForRows(
    `user_state_snapshots?select=id,scope,generated_at,signals,metadata&user_id=eq.${user.id}&scope=eq.daily`,
    (rows) =>
      rows.some(
        (row) =>
          row.metadata?.source === 'snapshot-aggregator-v1' &&
          Date.parse(row.generated_at) >
            dailySnapshotBeforeRecommendationRefresh,
      ),
    'daily snapshot refreshed by manual recommendation refresh',
  );
  await waitForRows(
    `recommendations?select=id,title,category,status,metadata&user_id=eq.${user.id}&status=in.(new,accepted)`,
    (rows) =>
      rows.length >= recommendationsBeforeManualRefresh.length &&
      rows.some(
        (row) =>
          row.category === 'focus' &&
          row.metadata?.model === null &&
          row.metadata?.source_engine_version === 'deterministic-v1',
      ) &&
      rows.some(
        (row) =>
          row.category === 'planning' &&
          row.metadata?.model === null &&
          row.metadata?.source_engine_version === 'deterministic-v1',
      ),
    'deterministic recommendations after manual refresh',
  );

  await page.goto(appRoute('/insights'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'ONE OBSERVATION');
  await expectText(page, 'Keep gathering comparable days');
  await expectText(page, 'Advanced correlation exploration');
  await clickByText(page, 'Advanced correlation exploration');
  await expectText(page, 'Compare');

  await assertNotificationLifecycle(page, user.id);
  await assertNotificationDelivery(page, user.id);

  await assertControlledCoach(page, user.id);

  await page.goto(appRoute('/deep-work'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await page.waitForURL('**/#/deep-work');
  await expectText(page, 'Focus session');

  await assertRows(
    dailyCapturePath,
    (rows) =>
      rows.length === 1 &&
      hasExactPhaseOneDailyRow(rows[0], {
        entryDate: captureEntryDate,
        eveningCaptureId,
        morningCaptureId,
        stressSource: 'workload',
        stressControllability: 'mostly_controllable',
        tomorrowPriority: editedEveningTomorrowPriority,
        expectMorning: true,
      }),
    'one final daily_logs row with exact merged Phase 1 values',
  );

  await assertRows(
    `behavioral_events?select=id,daily_log_id,event_type,value,unit,source,metadata&daily_log_id=eq.${dailyLogId}&source=eq.quick_check_in`,
    (rows) =>
      hasExactPhaseOneEvents(rows, {
        dailyLogId,
        entryDate: captureEntryDate,
        eveningCaptureId,
        morningCaptureId,
        stressSource: 'workload',
        stressControllability: 'mostly_controllable',
        tomorrowPriority: editedEveningTomorrowPriority,
      }),
    'four exact final linked current events for Phase 1 capture',
  );

  await assertConcurrentSetupReplay(user.id);

  console.log(`E2E browser smoke passed for ${email}`);
  }
} catch (error) {
  if (page) {
    const screenshotPath = `${artifactDir}/failure-${runId}.png`;
    try {
      await page.screenshot({ path: screenshotPath, fullPage: true });
      console.error(`Saved failure screenshot to ${screenshotPath}`);
    } catch (screenshotError) {
      console.error(`Could not save failure screenshot: ${screenshotError}`);
    }
  }
  throw error;
} finally {
  await browser.close();
}

async function assertAiServiceHealthy() {
  const response = await fetch(`${aiServiceBaseUrl}/v1/health`);
  if (!response.ok) {
    throw new Error(
      `AI service is not healthy: ${response.status} ${await response.text()}`,
    );
  }
}

async function createConfirmedUser() {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        display_name: 'E2E Browser User',
      },
    }),
  });

  if (!response.ok) {
    throw new Error(
      `Could not create local auth user: ${response.status} ${await response.text()}`,
    );
  }

  return response.json();
}

async function assertConcurrentSetupReplay(userId) {
  const revisions = await fetchRows(
    `intake_responses?select=request_id,revision,state,responses&user_id=eq.${userId}&version=eq.intake-v1&order=revision.asc`,
    'setup revisions before concurrent replay',
  );
  const latest = revisions.at(-1);
  if (revisions.length !== 4 || latest?.revision !== 4 || latest.state !== 'applied') {
    throw new Error(
      `Concurrent replay requires applied revision 4: ${JSON.stringify(revisions)}`,
    );
  }

  const tokenResponse = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        apikey: supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    },
  );
  if (!tokenResponse.ok) {
    throw new Error(
      `Could not sign in for concurrent setup replay: ${tokenResponse.status} ${await tokenResponse.text()}`,
    );
  }
  const accessToken = (await tokenResponse.json()).access_token;
  if (typeof accessToken !== 'string' || accessToken.length === 0) {
    throw new Error('Concurrent setup replay sign-in returned no access token.');
  }

  const requestId = crypto.randomUUID();
  const payload = {
    version: 'intake-v1',
    request_id: requestId,
    base_revision: 4,
    responses: latest.responses,
    metadata: { client: 'e2e-concurrency', source: 'setup-review' },
  };
  const post = () =>
    fetch(`${aiServiceBaseUrl}/v1/intake/complete`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
  const concurrentResponses = await Promise.all([post(), post()]);
  const responseBodies = await Promise.all(
    concurrentResponses.map(async (response) => ({
      status: response.status,
      body: await response.json(),
    })),
  );
  if (
    responseBodies.some(
      ({ status, body }) =>
        status !== 200 ||
        body.revision !== 5 ||
        body.request_id !== requestId ||
        body.status !== 'applied',
    )
  ) {
    throw new Error(
      `Concurrent setup replay did not converge: ${JSON.stringify(responseBodies)}`,
    );
  }

  await waitForRows(
    `intake_responses?select=request_id,revision,state&user_id=eq.${userId}&version=eq.intake-v1&order=revision.asc`,
    (rows) =>
      rows.length === 5 &&
      rows.filter((row) => row.request_id === requestId).length === 1 &&
      rows[4].revision === 5 &&
      rows[4].state === 'applied',
    'one canonical revision after concurrent same-request workers',
  );
  await waitForRows(
    `profiles?select=id,setup_revision&id=eq.${userId}`,
    (rows) => rows.length === 1 && rows[0].setup_revision === 5,
    'profile projection after concurrent same-request workers',
  );
}

function appRoute(path) {
  return `${appUrl}/#${path}`;
}

async function enableFlutterSemantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  try {
    await placeholder.click({ force: true, timeout: 10000 });
  } catch (_) {
    try {
      await page
        .getByRole('button', { name: /enable accessibility/i })
        .click({ timeout: 2000 });
    } catch (_) {
      // Flutter Web only shows the semantics placeholder before semantics are on.
    }
  }
}

async function waitForFlutterShell(page) {
  await page.locator('flt-glass-pane, flutter-view').first().waitFor({
    state: 'attached',
    timeout: 90000,
  });
}

async function scrollFlutterPage(page, deltaY) {
  const root = page.locator('flt-glass-pane, flutter-view').first();
  const box = await root.boundingBox();
  if (box) {
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  } else {
    await page.mouse.move(640, 480);
  }

  const step = deltaY > 0 ? 700 : -700;
  for (let remaining = Math.abs(deltaY); remaining > 0; remaining -= Math.abs(step)) {
    await page.mouse.wheel(0, step);
    await page.waitForTimeout(100);
  }
}

async function scrollFlutterPagePrecisely(page, deltaY) {
  const root = page.locator('flt-glass-pane, flutter-view').first();
  const box = await root.boundingBox();
  if (box) {
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  } else {
    await page.mouse.move(640, 480);
  }
  await page.mouse.wheel(0, deltaY);
  await page.waitForTimeout(100);
}

async function clickChoiceChip(page, label) {
  const labelPattern = new RegExp(
    `^${escapeRegExp(label)}(?:\\s+(?:selected|not selected|checked|unchecked))?$`,
    'i',
  );
  const candidates = [
    page.getByRole('button', { name: label, exact: true }).first(),
    page.getByRole('checkbox', { name: label, exact: true }).first(),
    page.getByLabel(label, { exact: true }).first(),
    page.getByText(label, { exact: true }).first(),
    page.getByRole('button', { name: labelPattern }).first(),
    page.getByRole('checkbox', { name: labelPattern }).first(),
    page.getByLabel(labelPattern).first(),
  ];

  let lastError;
  for (const candidate of candidates) {
    try {
      await candidate.click({ timeout: 5000 });
      await page.waitForTimeout(200);
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(`Could not select choice ${label}: ${lastError}`);
}

async function checkSemanticCheckbox(page, checkbox, label) {
  await checkbox.scrollIntoViewIfNeeded({ timeout: 5000 });
  await page.waitForTimeout(200);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    if (await checkbox.isChecked()) {
      return;
    }
    // Flutter can rebuild a semantics node between Playwright's actionability
    // check and its coordinate click. Dispatch the action on the re-resolved
    // semantic checkbox so a visible, enabled control is not treated as
    // unclickable merely because its hit-test rectangle went stale.
    await checkbox.evaluate((element) => element.click());
    await page.waitForTimeout(250);
  }
  throw new Error(`Checkbox ${JSON.stringify(label)} was not checked.`);
}

async function toggleSetupSection(page, title, expandedControl) {
  const titlePattern = new RegExp(`^${escapeRegExp(title)}`, 'i');
  const candidates = [
    page.getByRole('button', { name: titlePattern }).first(),
    page.getByLabel(titlePattern).first(),
    page.getByText(title, { exact: true }).first(),
  ];

  let lastError;
  for (const candidate of candidates) {
    try {
      await candidate.click({ timeout: 5000 });
      await page.waitForTimeout(250);
      await expectText(page, expandedControl);
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(`Could not toggle setup section ${title}: ${lastError}`);
}

async function selectDropdownOption(page, label, option) {
  const labelPattern = new RegExp(
    `^${escapeRegExp(label)}(?:$|\\s)`,
    'i',
  );
  const candidates = [
    page.getByRole('button', { name: labelPattern }).first(),
    page.getByLabel(labelPattern).first(),
  ];
  let opened = false;
  for (const candidate of candidates) {
    try {
      await candidate.click({ timeout: 2500 });
      opened = true;
      break;
    } catch (_) {
      // Try the next accessible DropdownButton representation.
    }
  }

  if (!opened) {
    const labelNode = page.getByText(label, { exact: true }).first();
    try {
      await labelNode.waitFor({ state: 'visible', timeout: 2500 });
      const followingButton = labelNode.locator(
        'xpath=following::*[@role="button"][1]',
      );
      await followingButton.click({ timeout: 2500 });
      opened = true;
    } catch (_) {
      try {
        const box = await labelNode.boundingBox({ timeout: 2500 });
        if (box) {
          await page.mouse.click(box.x + 24, box.y + box.height + 18);
          opened = true;
        }
      } catch (_) {
        // The label may be visual-only while the selected value is semantic.
      }
    }
  }

  if (!opened) {
    throw new Error(`Could not open dropdown: ${label}`);
  }

  const optionPattern = new RegExp(`^${escapeRegExp(option)}$`, 'i');
  const optionCandidates = [
    page.getByRole('menuitem', { name: optionPattern }).last(),
    page.getByRole('option', { name: optionPattern }).last(),
    page.getByLabel(optionPattern).last(),
    page.getByText(option, { exact: true }).last(),
  ];
  for (const candidate of optionCandidates) {
    try {
      await candidate.click({ timeout: 1000 });
      await page.waitForTimeout(150);
      return;
    } catch (_) {
      // Flutter's open DropdownButton menu may remain canvas-only in semantics.
    }
  }

  const options = dropdownOptions(label);
  const optionIndex = options.indexOf(option);
  if (optionIndex < 0) {
    throw new Error(`No keyboard option map for ${label}: ${option}`);
  }
  await page.keyboard.press('Home');
  for (let index = 0; index < optionIndex; index += 1) {
    await page.keyboard.press('ArrowDown');
  }
  await page.keyboard.press('Enter');
  await page.waitForTimeout(200);
}

function dropdownOptions(label) {
  const values = {
    'Typical weekday required': [
      'Not set',
      'School or work blocks',
      'Flexible schedule',
      'Split day',
      'Shift based',
    ],
    'Best energy window required': [
      'Not set',
      'Early morning',
      'Morning',
      'Afternoon',
      'Evening',
      'It varies',
    ],
    'Coaching style required': [
      'Not set',
      'Direct',
      'Gentle',
      'Analytical',
      'Accountability',
    ],
    Weekday: [
      'Not set',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ],
    'Cadence (required before activation)': ['Not set', 'Daily', 'Weekly'],
    'Goal status': ['Active', 'Paused', 'Archived'],
    'Routine status': ['Candidate', 'Active', 'Paused', 'Archived'],
    'Commitment status': ['Active', 'Archived'],
    'Task priority': ['Low', 'Medium', 'High', 'Critical'],
  }[label];
  return values ?? [];
}

async function fillByLabelOrPlaceholder(page, label, value, fallbackIndex) {
  const labelPattern = new RegExp(
    `^${escapeRegExp(label)}(?:$|\\s)`,
    'i',
  );
  const candidates = [
    page.getByLabel(labelPattern),
    page.getByPlaceholder(label, { exact: true }),
    page.getByRole('textbox', { name: labelPattern }),
  ];

  for (const locator of candidates) {
    try {
      await fillLocatorWithValue(page, locator, value);
      return;
    } catch (_) {
      // Try the next accessible representation.
    }
  }

  const textboxes = page.getByRole('textbox');
  const textboxCount = await textboxes.count();
  const resolvedIndex =
    fallbackIndex < 0 ? textboxCount + fallbackIndex : fallbackIndex;
  if (resolvedIndex >= 0 && textboxCount > resolvedIndex) {
    await fillLocatorWithValue(page, textboxes.nth(resolvedIndex), value);
    return;
  }

  throw new Error(`Could not fill field: ${label}`);
}

async function stabilizeLabeledControl(page, label) {
  const labelPattern = new RegExp(
    `^${escapeRegExp(label)}(?:$|\\s)`,
    'i',
  );
  const locator = page.getByLabel(labelPattern).first();
  await locator.scrollIntoViewIfNeeded({ timeout: 5000 });
  await page.waitForTimeout(500);
}

async function expectFieldValue(page, label, value, fallbackIndex) {
  const labelPattern = new RegExp(
    `^${escapeRegExp(label)}(?:$|\\s)`,
    'i',
  );
  const candidates = [
    page.getByLabel(labelPattern),
    page.getByPlaceholder(label, { exact: true }),
    page.getByRole('textbox', { name: labelPattern }),
  ];

  for (const locator of candidates) {
    try {
      await locator.click({ timeout: 1500 });
      if (await locatorHasValue(page, locator, value)) {
        return;
      }
    } catch (_) {
      // Try the next accessible representation.
    }
  }

  const textboxes = page.getByRole('textbox');
  const textboxCount = await textboxes.count();
  const resolvedIndex =
    fallbackIndex < 0 ? textboxCount + fallbackIndex : fallbackIndex;
  if (resolvedIndex >= 0 && textboxCount > resolvedIndex) {
    const fallback = textboxes.nth(resolvedIndex);
    await fallback.click({ timeout: 2500 });
    if (await locatorHasValue(page, fallback, value)) {
      return;
    }
  }

  throw new Error(`Field ${label} did not retain exact value ${value}`);
}

async function fillLocatorWithValue(page, locator, value) {
  for (const delay of [15, 30]) {
    try {
      await fillFocusedLocator(page, locator);
      await page.waitForTimeout(150);
      await page.keyboard.type(value, { delay });
      await page.waitForTimeout(200);
      if (await locatorRetainsValueAfterBlur(page, locator, value)) {
        return;
      }
    } catch (_) {
      // Retry once more slowly before trying a directly fillable input.
    }
  }

  await locator.fill(value, { timeout: 2500 });
  await page.waitForTimeout(200);
  if (!(await locatorRetainsValueAfterBlur(page, locator, value))) {
    throw new Error('Focused element did not receive text input');
  }
}

async function locatorRetainsValueAfterBlur(page, locator, value) {
  for (let check = 0; check < 2; check += 1) {
    await page.keyboard.press('Tab');
    await page.waitForTimeout(250);
    await locator.click({ timeout: 2500 });
    if (!(await locatorHasValue(page, locator, value))) {
      return false;
    }
  }
  return true;
}

async function fillFocusedLocator(page, locator) {
  await locator.click({ timeout: 2500 });
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await page.keyboard.press('Backspace');
}

async function clickByRoleName(page, role, name) {
  const locator = page.getByRole(role, { name, exact: true }).first();
  try {
    await locator.click({ timeout: 5000 });
  } catch (_) {
    await locator.click({ timeout: 2500, force: true });
  }
}

async function clickScrolledByLabel(page, name) {
  const choice = () => page.getByLabel(name, { exact: true }).first();
  await choice().scrollIntoViewIfNeeded({ timeout: 5000 });
  await page.waitForTimeout(350);
  // Dispatch the Flutter semantics action directly. A coordinate click can
  // briefly use a pre-scroll hit-test rectangle and mutate a neighbouring
  // choice even though Playwright resolved the intended semantics node.
  await choice().evaluate((element) => element.click());
  await page.waitForTimeout(250);
  const selectableState = await choice().evaluate((element) => ({
    checked: element.getAttribute('aria-checked'),
    pressed: element.getAttribute('aria-pressed'),
    selected: element.getAttribute('aria-selected'),
  }));
  const exposesSelection = Object.values(selectableState).some(
    (value) => value !== null,
  );
  if (
    exposesSelection &&
    !Object.values(selectableState).some((value) => value === 'true')
  ) {
    // Re-resolve after the Flutter semantics rebuild, then retry once.
    await choice().evaluate((element) => element.click());
    await page.waitForTimeout(250);
    const selected = await choice().evaluate(
      (element) =>
        element.getAttribute('aria-checked') === 'true' ||
        element.getAttribute('aria-pressed') === 'true' ||
        element.getAttribute('aria-selected') === 'true',
    );
    if (!selected) {
      throw new Error(`Choice ${JSON.stringify(name)} was not selected.`);
    }
  }
}

async function clickByRoleNameUntilText(page, role, name, expectedText) {
  let lastError;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await clickByRoleName(page, role, name);
    try {
      await expectText(page, expectedText);
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

async function locatorHasValue(page, locator, value) {
  try {
    return (await locator.inputValue({ timeout: 500 })) === value;
  } catch (_) {
    return activeElementHasValue(page, value);
  }
}

async function activeElementHasValue(page, value) {
  return page.evaluate((expected) => {
    const element = document.activeElement;
    if (!element || !('value' in element)) {
      return false;
    }
    return element.value === expected;
  }, value);
}

async function clickByText(page, text, options = {}) {
  const match = options.match ?? 'first';
  const button = page.getByRole('button', { name: text, exact: true });
  const buttonTarget = match === 'last' ? button.last() : button.first();
  try {
    await buttonTarget.click({ timeout: 5000 });
    return;
  } catch (_) {
    try {
      await buttonTarget.click({ timeout: 2500, force: true });
      return;
    } catch (_) {
      // Flutter can merge a ListTile title and subtitle into one button name.
    }
  }

  const partialButton = page.getByRole('button', {
    name: new RegExp(escapeRegExp(text), 'i'),
  });
  const partialButtonTarget =
    match === 'last' ? partialButton.last() : partialButton.first();
  try {
    await partialButtonTarget.click({ timeout: 5000 });
    return;
  } catch (_) {
    try {
      await partialButtonTarget.click({ timeout: 2500, force: true });
      return;
    } catch (_) {
      // Fall back to text matching for non-button controls.
    }
  }

  const exact = page.getByText(text, { exact: true });
  const exactTarget = match === 'last' ? exact.last() : exact.first();
  try {
    await exactTarget.click({ timeout: 5000 });
    return;
  } catch (_) {
    try {
      await exactTarget.click({ timeout: 2500, force: true });
      return;
    } catch (_) {
      // Try a partial text match last.
    }
    const partial = page.getByText(text);
    const partialTarget = match === 'last' ? partial.last() : partial.first();
    try {
      await partialTarget.click({ timeout: 5000 });
    } catch (_) {
      await partialTarget.click({ timeout: 2500, force: true });
    }
  }
}

async function textLocatorInViewport(page, text, { buttonFirst = false } = {}) {
  const partialButton = page.getByRole('button', {
    name: new RegExp(escapeRegExp(text), 'i'),
  });
  const candidates = buttonFirst
    ? [
        page.getByRole('button', { name: text, exact: true }),
        partialButton,
        page.getByText(text, { exact: true }),
        page.getByText(text),
        page.getByLabel(text, { exact: false }),
      ]
    : [
        page.getByText(text, { exact: true }),
        page.getByText(text),
        page.getByLabel(text, { exact: false }),
        page.getByRole('button', { name: text, exact: true }),
        partialButton,
      ];
  const viewport = page.viewportSize();
  for (const candidate of candidates) {
    const count = await candidate.count();
    for (let index = 0; index < count; index += 1) {
      const locator = candidate.nth(index);
      const box = await locator.boundingBox().catch(() => null);
      if (
        box &&
        box.width > 0 &&
        box.height > 0 &&
        (!viewport || (box.y < viewport.height && box.y + box.height > 0))
      ) {
        return locator;
      }
    }
  }
  return null;
}

async function scrollUntilTextInViewport(
  page,
  text,
  {
    deltaY = 700,
    maxSteps = 20,
    buttonFirst = false,
    precise = false,
  } = {},
) {
  for (let step = 0; step <= maxSteps; step += 1) {
    const locator = await textLocatorInViewport(page, text, { buttonFirst });
    if (locator) return locator;
    if (step < maxSteps) {
      await (precise
        ? scrollFlutterPagePrecisely(page, deltaY)
        : scrollFlutterPage(page, deltaY));
    }
  }
  throw new Error(`Could not bring ${text} into the Flutter viewport.`);
}

async function expectText(page, text) {
  try {
    await page.getByText(text).first().waitFor({
      state: 'visible',
      timeout: 7500,
    });
  } catch (_) {
    // Flutter can merge a card's descendant text into one semantics label.
    await page.getByLabel(text, { exact: false }).first().waitFor({
      state: 'visible',
      timeout: 7500,
    });
  }
}

async function assertFlutterTextAbsent(page, text, description) {
  const exactTextCount = await page.getByText(text, { exact: true }).count();
  const mergedLabelCount = await page
    .getByLabel(text, { exact: false })
    .count();
  if (exactTextCount !== 0 || mergedLabelCount !== 0) {
    throw new Error(
      `Unexpected ${description}: text=${exactTextCount}, semantics=${mergedLabelCount}`,
    );
  }
}

async function assertRows(path, predicate, description) {
  const rows = await fetchRows(path, description);
  if (!predicate(rows)) {
    throw new Error(
      `Did not find expected ${description}. Rows: ${JSON.stringify(rows)}`,
    );
  }
}

async function waitForRows(path, predicate, description) {
  const deadline = Date.now() + 30000;
  let lastRows = [];

  while (Date.now() < deadline) {
    lastRows = await fetchRows(path, description);
    if (predicate(lastRows)) {
      return lastRows;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  throw new Error(
    `Timed out verifying ${description}. Rows: ${JSON.stringify(lastRows)}`,
  );
}

async function waitForAiPost(page, path, description) {
  const response = await page.waitForResponse(
    (candidate) =>
      candidate.url() === `${aiServiceBaseUrl}${path}` &&
      candidate.request().method() === 'POST',
    { timeout: 45000 },
  );

  if (!response.ok()) {
    throw new Error(
      `Unexpected ${description} response: ${response.status()} ${await response.text()}`,
    );
  }

  return response;
}

async function clickAndWaitForAiPost(
  page,
  path,
  description,
  buttonText,
) {
  let lastError;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const responsePromise = page.waitForResponse(
      (candidate) =>
        candidate.url() === `${aiServiceBaseUrl}${path}` &&
        candidate.request().method() === 'POST',
      { timeout: attempt === 0 ? 15000 : 45000 },
    );
    if (attempt === 0) {
      await clickByText(page, buttonText);
    } else {
      const button = page
        .getByRole('button', { name: buttonText, exact: true })
        .first();
      await button.scrollIntoViewIfNeeded({ timeout: 5000 });
      await button.evaluate((element) => element.click());
    }
    try {
      const response = await responsePromise;
      if (!response.ok()) {
        throw new Error(
          `Unexpected ${description} response: ${response.status()} ${await response.text()}`,
        );
      }
      return response;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

async function assertPhaseTwoDailyStateResponse(response, expected) {
  const payload = await response.json();
  const state = payload?.summary?.daily_state;
  const stateSignals = payload?.signals?.daily_state;
  if (!state || !stateSignals) {
    throw new Error(
      `Snapshot response has no Phase 2 daily state: ${JSON.stringify(payload)}`,
    );
  }
  const exactValues = {
    mode: state.mode,
    dataQuality: state.data_quality,
    eveningFreshness: state.freshness?.evening?.state,
    morningFreshness: state.freshness?.morning?.state,
    stressIntensity: state.context?.stress?.intensity,
    stressSource: state.context?.stress?.source,
    stressControllability: state.context?.stress?.controllability,
    mainFriction: state.context?.main_friction,
    additionalFrictions: state.context?.additional_frictions,
    sleepHours: state.context?.sleep_hours,
    sleepQuality: state.context?.sleep_quality,
    currentEnergy: state.context?.current_energy,
    dayShape: state.context?.day_shape,
  };
  for (const [key, expectedValue] of Object.entries(expected)) {
    if (
      key in exactValues &&
      expectedValue !== undefined &&
      (Array.isArray(expectedValue)
        ? !arraysEqual(exactValues[key], expectedValue)
        : exactValues[key] !== expectedValue)
    ) {
      throw new Error(
        `Unexpected Phase 2 ${key}. Expected ${JSON.stringify(expectedValue)}, got ${JSON.stringify(exactValues[key])}. State: ${JSON.stringify(state)}`,
      );
    }
  }
  const riskCodes = new Set(state.risk_flags ?? []);
  for (const code of expected.expectedRisks ?? []) {
    if (!riskCodes.has(code)) {
      throw new Error(
        `Missing Phase 2 risk ${code}: ${JSON.stringify(state)}`,
      );
    }
  }
  for (const code of expected.forbiddenRisks ?? []) {
    if (riskCodes.has(code)) {
      throw new Error(
        `Stale Phase 2 risk ${code} survived recomputation: ${JSON.stringify(state)}`,
      );
    }
  }
  if (
    state.contract_version !== 'explainable-daily-state-v1' ||
    stateSignals.contract_version !== 'explainable-daily-state-v1' ||
    state.provenance?.kind !== 'deterministic' ||
    state.provenance?.baseline !== 'none'
  ) {
    throw new Error(
      `Unexpected Phase 2 provenance: ${JSON.stringify({ state, stateSignals })}`,
    );
  }
  const evidenceRows = [
    ...Object.values(stateSignals.risk_evidence ?? {}).flat(),
    ...Object.values(stateSignals.reason_evidence ?? {}).flat(),
  ];
  if (
    expected.evidenceDailyLogId &&
    !evidenceRows.some(
      (ref) =>
        ref?.table === 'daily_logs' &&
        ref?.id === expected.evidenceDailyLogId &&
        typeof ref?.field === 'string',
    )
  ) {
    throw new Error(
      `Phase 2 evidence does not reference daily log ${expected.evidenceDailyLogId}: ${JSON.stringify(stateSignals)}`,
    );
  }
  const serialized = JSON.stringify({ state, stateSignals });
  for (const text of expected.forbiddenTexts ?? []) {
    if (text && serialized.includes(text)) {
      throw new Error(
        `Sensitive capture text leaked into Phase 2 state: ${JSON.stringify(text)}`,
      );
    }
  }
  return { snapshotId: payload.snapshot_id, state, stateSignals };
}

function assertJsonPayload(request, expected, description) {
  const payload = request.postData() ? JSON.parse(request.postData()) : {};
  const expectedKeys = Object.keys(expected).sort();
  const payloadKeys = Object.keys(payload).sort();
  const keysMatch =
    JSON.stringify(payloadKeys) === JSON.stringify(expectedKeys);
  const valuesMatch = expectedKeys.every((key) => payload[key] === expected[key]);
  if (!keysMatch || !valuesMatch) {
    throw new Error(
      `Unexpected ${description}. Expected ${JSON.stringify(expected)}, got ${JSON.stringify(payload)}`,
    );
  }
}

function arraysEqual(actual, expected) {
  return (
    Array.isArray(actual) &&
    JSON.stringify(actual) === JSON.stringify(expected)
  );
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function hasExactPhaseOneDailyRow(row, expected) {
  const captures = row.metadata?.captures;
  const evening = captures?.evening;
  const morning = captures?.morning;
  const captureKeys =
    captures && typeof captures === 'object'
      ? Object.keys(captures).sort()
      : [];
  const expectedCaptureKeys = expected.expectMorning
    ? ['evening', 'morning']
    : ['evening'];
  const hasExpectedMorning = expected.expectMorning
    ? morning?.capture_kind === 'morning' &&
      morning?.entry_date === expected.entryDate &&
      (!expected.morningCaptureId ||
        morning?.capture_id === expected.morningCaptureId) &&
      isIsoTimestamp(morning?.captured_at) &&
      morning?.sleep_hours === 5.5 &&
      morning?.sleep_quality === 3 &&
      morning?.current_energy === 4 &&
      morning?.day_shape === 'constrained'
    : morning === undefined;

  return (
    Boolean(row.id) &&
    row.entry_date === expected.entryDate &&
    row.source === 'quick_check_in' &&
    row.sleep_hours === (expected.expectMorning ? 5.5 : null) &&
    row.energy_level === (expected.expectMorning ? 4 : 9) &&
    row.stress_level === 8 &&
    row.mood_score === 2 &&
    row.mood_label === 'very_low' &&
    row.steps === null &&
    row.activity_level === null &&
    row.screen_time_hours === null &&
    row.focus_minutes === null &&
    row.nutrition_notes === null &&
    row.day_focus === null &&
    row.reflection === null &&
    row.metadata?.capture_version === 'daily-capture-v2' &&
    !Object.hasOwn(row.metadata ?? {}, 'context_note') &&
    arraysEqual(captureKeys, expectedCaptureKeys) &&
    evening?.capture_kind === 'evening' &&
    evening?.entry_date === expected.entryDate &&
    evening?.capture_id === expected.eveningCaptureId &&
    isIsoTimestamp(evening?.captured_at) &&
    evening?.mood === 2 &&
    evening?.energy === 9 &&
    evening?.stress_intensity === 8 &&
    evening?.stress_intensity_label === 'high' &&
    evening?.stress_source === expected.stressSource &&
    evening?.stress_controllability === expected.stressControllability &&
    !Object.hasOwn(evening ?? {}, 'focus_band') &&
    evening?.main_friction === 'emotional_load' &&
    arraysEqual(
      evening?.additional_frictions,
      eveningAdditionalFrictions,
    ) &&
    evening?.tomorrow_priority === expected.tomorrowPriority &&
    !Object.hasOwn(evening ?? {}, 'reflection_note') &&
    !Object.hasOwn(evening ?? {}, 'specific_blocker') &&
    !Object.hasOwn(evening ?? {}, 'gentle_tomorrow') &&
    hasExpectedMorning
  );
}

function hasExactEveningOnlyEvents(rows, expected) {
  return hasExactCaptureEvents(rows, expected, {
    energy: 9,
    eventTypes: ['energy', 'mood', 'stress'],
    expectMorning: false,
  });
}

function hasExactPhaseOneEvents(rows, expected) {
  return hasExactCaptureEvents(rows, expected, {
    energy: 4,
    eventTypes: ['energy', 'mood', 'sleep', 'stress'],
    expectMorning: true,
  });
}

function hasExactCaptureEvents(rows, expected, contract) {
  if (
    rows.length !== contract.eventTypes.length ||
    rows.some(
      (row) =>
        !row.id ||
        row.daily_log_id !== expected.dailyLogId ||
        row.source !== 'quick_check_in' ||
        row.metadata?.capture_version !== 'daily-capture-v2' ||
        row.metadata?.entry_date !== expected.entryDate ||
        !isIsoTimestamp(row.metadata?.captured_at),
    ) ||
    new Set(rows.map((row) => row.id)).size !== contract.eventTypes.length ||
    new Set(rows.map((row) => row.daily_log_id)).size !== 1
  ) {
    return false;
  }

  const expectedSignals = [
    `energy:${contract.energy}:score_0_10`,
    'mood:2:score_0_10',
    ...(contract.expectMorning ? ['sleep:5.5:hours'] : []),
    'stress:8:score_0_10',
  ].sort();
  const actualSignals = rows
    .map((row) => `${row.event_type}:${Number(row.value)}:${row.unit}`)
    .sort();
  if (!arraysEqual(actualSignals, expectedSignals)) {
    return false;
  }

  const byType = Object.fromEntries(rows.map((row) => [row.event_type, row]));
  const eveningTypes = contract.expectMorning
    ? ['mood', 'stress']
    : ['mood', 'energy', 'stress'];
  if (
    eveningTypes.some((type) => {
      const metadata = byType[type]?.metadata;
      return (
        metadata?.capture_kind !== 'evening' ||
        metadata?.capture_id !== expected.eveningCaptureId ||
        Object.hasOwn(metadata ?? {}, 'focus_band') ||
        metadata?.main_friction !== 'emotional_load' ||
        !arraysEqual(
          metadata?.additional_frictions,
          eveningAdditionalFrictions,
        ) ||
        metadata?.tomorrow_priority !== expected.tomorrowPriority ||
        Object.hasOwn(metadata ?? {}, 'gentle_tomorrow')
      );
    })
  ) {
    return false;
  }

  const stressMetadata = byType.stress?.metadata;
  if (
    stressMetadata?.stress_intensity_label !== 'high' ||
    stressMetadata?.stress_source !== expected.stressSource ||
    stressMetadata?.stress_controllability !==
      expected.stressControllability
  ) {
    return false;
  }

  if (!contract.expectMorning) {
    return true;
  }
  return ['energy', 'sleep'].every((type) => {
    const metadata = byType[type]?.metadata;
    return (
      metadata?.capture_kind === 'morning' &&
      metadata?.capture_id === expected.morningCaptureId &&
      metadata?.day_shape === 'constrained' &&
      metadata?.sleep_quality === 3
    );
  });
}

function isIsoTimestamp(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function isoDateInTimeZone(value, timeZone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    })
      .formatToParts(new Date(value))
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function latestCompletedIsoWeek(timeZone) {
  const localToday = isoDateInTimeZone(new Date().toISOString(), timeZone);
  const today = new Date(`${localToday}T00:00:00Z`);
  const isoWeekday = today.getUTCDay() === 0 ? 7 : today.getUTCDay();
  const currentWeekStart = addUtcDays(localToday, -(isoWeekday - 1));
  const endsOn = addUtcDays(currentWeekStart, -1);
  const startsOn = addUtcDays(endsOn, -6);
  return {
    periodKey: isoPeriodKey(startsOn),
    startsOn,
    endsOn,
  };
}

function isoPeriodKey(dateValue) {
  const date = new Date(`${dateValue}T00:00:00Z`);
  const isoWeekday = date.getUTCDay() === 0 ? 7 : date.getUTCDay();
  date.setUTCDate(date.getUTCDate() + 4 - isoWeekday);
  const isoYear = date.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const week = Math.ceil(((date - yearStart) / 86400000 + 1) / 7);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

function addUtcDays(dateValue, days) {
  const date = new Date(`${dateValue}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function isoTimestampOnDate(dateValue, timeValue) {
  return `${dateValue}T${timeValue}Z`;
}

function isUuid(value) {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

function isUuidV5(value) {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

function isCanonicalUuid(value) {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

async function captureSideEffectIds(userId) {
  const tables = [
    'tasks',
    'goals',
    'habits',
    'schedule_items',
    'memory_entries',
    'notifications',
    'recommendations',
  ];
  const rowsByTable = await Promise.all(
    tables.map((table) =>
      fetchRows(
        `${table}?select=id&user_id=eq.${userId}`,
        `${table} rows around Phase 1 capture`,
      ),
    ),
  );
  return Object.fromEntries(
    tables.map((table, index) => [
      table,
      rowsByTable[index].map((row) => row.id).sort(),
    ]),
  );
}

async function activeDeterministicRecommendations(userId) {
  return fetchRows(
    `recommendations?select=id,category,status,metadata&user_id=eq.${userId}&status=in.(new,accepted)`,
    'active deterministic recommendations',
  );
}

async function latestDailySnapshotGeneratedAt(userId) {
  const rows = await fetchRows(
    `user_state_snapshots?select=generated_at&user_id=eq.${userId}&scope=eq.daily&order=generated_at.desc&limit=1`,
    'latest daily snapshot timestamp',
  );
  if (rows.length === 0) {
    return 0;
  }
  return Date.parse(rows[0].generated_at);
}

async function assertNotificationLifecycle(page, userId) {
  const notificationId = crypto.randomUUID();
  const futureNotificationId = crypto.randomUUID();
  const createdAt = new Date(Date.now() - 60_000).toISOString();
  const futureDueAt = new Date(Date.now() + 86_400_000).toISOString();
  const inserted = await insertRows('notifications', [
    {
      id: notificationId,
      user_id: userId,
      title: notificationLifecycleTitle,
      message: 'Stored Inbox lifecycle verification item.',
      type: 'reminder',
      priority: 'high',
      is_read: false,
      action_url: '/dashboard',
      due_at: null,
      metadata: {
        source: 'e2e',
        contract_version: 'notification-lifecycle-v1',
      },
      created_at: createdAt,
      updated_at: createdAt,
    },
    {
      id: futureNotificationId,
      user_id: userId,
      title: notificationFutureTitle,
      message: 'This future Inbox item must remain hidden.',
      type: 'reminder',
      priority: 'low',
      is_read: false,
      action_url: null,
      due_at: futureDueAt,
      metadata: { source: 'e2e-future' },
      created_at: createdAt,
      updated_at: createdAt,
    },
  ]);
  const initial = inserted.find((row) => row.id === notificationId);
  if (
    !initial ||
    initial.is_read !== false ||
    initial.read_at !== null ||
    initial.dismissed_at !== null ||
    !sameInstant(initial.updated_at, createdAt)
  ) {
    throw new Error(
      `Notification lifecycle fixture has an invalid initial state: ${JSON.stringify(inserted)}`,
    );
  }

  const accessToken = await signInAccessToken('Notification lifecycle');
  await page.goto(appRoute('/alerts'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Inbox');
  await expectText(page, notificationLifecycleTitle);
  await assertFlutterTextAbsent(
    page,
    notificationFutureTitle,
    'future-due notification in the Inbox',
  );

  const markReadResponsePromise = waitForNotificationAction(
    page,
    notificationId,
    'mark-read lifecycle action',
  );
  await clickByRoleName(
    page,
    'button',
    `Mark read notification ${notificationLifecycleTitle}`,
  );
  const markReadResponse = await markReadResponsePromise;
  const markReadRequest = assertNotificationActionRequest(
    markReadResponse.request(),
    {
      notificationId,
      command: 'mark_read',
      expectedUpdatedAt: createdAt,
    },
    'mark-read lifecycle request',
  );
  const markRead = assertNotificationActionResponse(
    await markReadResponse.json(),
    {
      notificationId,
      command: 'mark_read',
      replayed: false,
      expectedUpdatedAt: createdAt,
    },
    'mark-read lifecycle response',
  );
  if (!sameInstant(markRead.read_at, markRead.updated_at)) {
    throw new Error('Mark-read did not persist matching lifecycle timestamps.');
  }
  await page
    .getByRole('button', {
      name: `Mark unread notification ${notificationLifecycleTitle}`,
      exact: true,
    })
    .waitFor({ state: 'visible' });
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, markRead.read_at) &&
      rows[0].dismissed_at === null &&
      sameInstant(rows[0].updated_at, markRead.updated_at),
    'persisted mark-read notification lifecycle',
  );

  const replayResponse = await notificationActionRequest(
    accessToken,
    notificationId,
    markReadRequest,
  );
  if (!replayResponse.ok) {
    throw new Error(
      `Exact notification replay failed: ${replayResponse.status} ${await replayResponse.text()}`,
    );
  }
  const replay = assertNotificationActionResponse(
    await replayResponse.json(),
    {
      notificationId,
      command: 'mark_read',
      replayed: true,
      expectedUpdatedAt: createdAt,
    },
    'exact notification lifecycle replay',
  );
  if (
    !sameInstant(replay.read_at, markRead.read_at) ||
    replay.dismissed_at !== null ||
    !sameInstant(replay.updated_at, markRead.updated_at)
  ) {
    throw new Error('Exact notification replay changed the persisted result.');
  }

  const reinterpretation = await notificationActionRequest(
    accessToken,
    notificationId,
    {
      ...markReadRequest,
      command: 'mark_unread',
      expected_updated_at: markRead.updated_at,
    },
  );
  const reinterpretationText = await reinterpretation.text();
  let reinterpretationBody = null;
  try {
    reinterpretationBody = JSON.parse(reinterpretationText);
  } catch (_) {
    // The exact JSON detail assertion below reports the raw response.
  }
  if (
    reinterpretation.status !== 409 ||
    reinterpretationBody?.detail !==
      'Notification action request id was already used'
  ) {
    throw new Error(
      `Notification request-id reinterpretation was not rejected exactly: ${reinterpretation.status} ${reinterpretationText}`,
    );
  }
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, markRead.read_at) &&
      rows[0].dismissed_at === null &&
      sameInstant(rows[0].updated_at, markRead.updated_at),
    'unchanged notification after request-id reinterpretation conflict',
  );

  const staleAction = await notificationActionRequest(
    accessToken,
    notificationId,
    {
      contract_version: 'notification-lifecycle-v1',
      request_id: crypto.randomUUID(),
      command: 'mark_unread',
      expected_updated_at: createdAt,
    },
  );
  const staleActionText = await staleAction.text();
  let staleActionBody = null;
  try {
    staleActionBody = JSON.parse(staleActionText);
  } catch (_) {
    // The exact JSON detail assertion below reports the raw response.
  }
  if (
    staleAction.status !== 409 ||
    staleActionBody?.detail !== 'Notification changed since it was loaded'
  ) {
    throw new Error(
      `Stale notification action was not rejected exactly: ${staleAction.status} ${staleActionText}`,
    );
  }
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, markRead.read_at) &&
      rows[0].dismissed_at === null &&
      sameInstant(rows[0].updated_at, markRead.updated_at),
    'unchanged notification after stale timestamp conflict',
  );

  const ownerRead = await authenticatedRestRequest(
    `notifications?select=id,user_id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    accessToken,
  );
  if (
    !ownerRead.response.ok ||
    ownerRead.rows?.length !== 1 ||
    ownerRead.rows[0].user_id !== userId
  ) {
    throw new Error(
      `Notification owner read failed: ${ownerRead.response.status} ${ownerRead.text}`,
    );
  }
  const forbiddenPatch = await authenticatedRestRequest(
    `notifications?id=eq.${notificationId}`,
    accessToken,
    {
      method: 'PATCH',
      body: { title: 'Forbidden direct Notification update' },
    },
  );
  if (forbiddenPatch.response.ok) {
    throw new Error('Authenticated direct Notification UPDATE was accepted.');
  }
  await assertRows(
    `notifications?select=id,title,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === notificationLifecycleTitle &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, markRead.read_at) &&
      rows[0].dismissed_at === null &&
      sameInstant(rows[0].updated_at, markRead.updated_at),
    'unchanged notification after forbidden direct update',
  );
  const forbiddenLedgerRead = await authenticatedRestRequest(
    `notification_action_requests?select=request_id&request_id=eq.${markReadRequest.request_id}`,
    accessToken,
  );
  if (forbiddenLedgerRead.response.ok) {
    throw new Error('Authenticated Notification retry-ledger SELECT was accepted.');
  }

  const secondaryEmail = `e2e-notification-other-${runId}@example.test`;
  const secondaryPassword = `E2e-notification-other-${runId}-password`;
  const secondary = await createConfirmedUserWithCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    displayName: 'E2E Notification Other User',
  });
  const secondaryToken = await signInCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    context: 'Notification secondary principal',
  });
  const secondaryRead = await authenticatedRestRequest(
    `notifications?select=id&id=eq.${notificationId}`,
    secondaryToken,
  );
  if (!secondaryRead.response.ok || secondaryRead.rows?.length !== 0) {
    throw new Error(
      `Notification RLS exposed an owner row: ${secondaryRead.response.status} ${secondaryRead.text}`,
    );
  }
  const foreignAction = await notificationActionRequest(
    secondaryToken,
    notificationId,
    {
      contract_version: 'notification-lifecycle-v1',
      request_id: crypto.randomUUID(),
      command: 'mark_unread',
      expected_updated_at: markRead.updated_at,
    },
  );
  if (foreignAction.status !== 404) {
    throw new Error(
      `Cross-owner notification action was not owner-safe 404: ${foreignAction.status} ${await foreignAction.text()}`,
    );
  }
  if (!isCanonicalUuid(secondary.id)) {
    throw new Error('Notification secondary user has no canonical UUID.');
  }

  const forbiddenDirectRpc = await authenticatedRestRequest(
    'rpc/apply_notification_action_v1',
    secondaryToken,
    {
      method: 'POST',
      body: {
        p_user_id: userId,
        p_notification_id: notificationId,
        p_request_id: crypto.randomUUID(),
        p_command: 'mark_unread',
        p_expected_updated_at: markRead.updated_at,
      },
    },
  );
  if (forbiddenDirectRpc.response.ok) {
    throw new Error(
      'Authenticated user directly invoked the service-role Notification RPC.',
    );
  }
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, markRead.read_at) &&
      rows[0].dismissed_at === null &&
      sameInstant(rows[0].updated_at, markRead.updated_at),
    'unchanged notification after forbidden direct RPC invocation',
  );

  const markUnreadResponsePromise = waitForNotificationAction(
    page,
    notificationId,
    'mark-unread lifecycle action',
  );
  await clickByRoleName(
    page,
    'button',
    `Mark unread notification ${notificationLifecycleTitle}`,
  );
  const markUnreadResponse = await markUnreadResponsePromise;
  const markUnreadRequest = assertNotificationActionRequest(
    markUnreadResponse.request(),
    {
      notificationId,
      command: 'mark_unread',
      expectedUpdatedAt: markRead.updated_at,
    },
    'mark-unread lifecycle request',
  );
  const markUnread = assertNotificationActionResponse(
    await markUnreadResponse.json(),
    {
      notificationId,
      command: 'mark_unread',
      replayed: false,
      expectedUpdatedAt: markRead.updated_at,
    },
    'mark-unread lifecycle response',
  );
  await page
    .getByRole('button', {
      name: `Mark read notification ${notificationLifecycleTitle}`,
      exact: true,
    })
    .waitFor({ state: 'visible' });
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === false &&
      rows[0].read_at === null &&
      rows[0].dismissed_at === null &&
      sameInstant(rows[0].updated_at, markUnread.updated_at),
    'persisted mark-unread notification lifecycle',
  );

  const dismissResponsePromise = waitForNotificationAction(
    page,
    notificationId,
    'dismiss lifecycle action',
  );
  await clickByRoleName(
    page,
    'button',
    `Dismiss notification ${notificationLifecycleTitle}`,
  );
  const dismissResponse = await dismissResponsePromise;
  const dismissRequest = assertNotificationActionRequest(
    dismissResponse.request(),
    {
      notificationId,
      command: 'dismiss',
      expectedUpdatedAt: markUnread.updated_at,
    },
    'dismiss lifecycle request',
  );
  const dismissed = assertNotificationActionResponse(
    await dismissResponse.json(),
    {
      notificationId,
      command: 'dismiss',
      replayed: false,
      expectedUpdatedAt: markUnread.updated_at,
    },
    'dismiss lifecycle response',
  );
  if (
    !sameInstant(dismissed.read_at, dismissed.updated_at) ||
    !sameInstant(dismissed.dismissed_at, dismissed.updated_at)
  ) {
    throw new Error('Dismiss did not persist one exact lifecycle timestamp.');
  }
  await page
    .getByText(notificationLifecycleTitle, { exact: true })
    .waitFor({ state: 'hidden' });
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, dismissed.read_at) &&
      sameInstant(rows[0].dismissed_at, dismissed.dismissed_at) &&
      sameInstant(rows[0].updated_at, dismissed.updated_at),
    'persisted dismissed notification tombstone',
  );

  const historicalReplayResponse = await notificationActionRequest(
    accessToken,
    notificationId,
    markReadRequest,
  );
  if (!historicalReplayResponse.ok) {
    throw new Error(
      `Historical notification replay failed: ${historicalReplayResponse.status} ${await historicalReplayResponse.text()}`,
    );
  }
  const historicalReplay = assertNotificationActionResponse(
    await historicalReplayResponse.json(),
    {
      notificationId,
      command: 'mark_read',
      replayed: true,
      expectedUpdatedAt: createdAt,
    },
    'historical notification lifecycle replay',
  );
  if (
    !sameInstant(historicalReplay.read_at, markRead.read_at) ||
    historicalReplay.dismissed_at !== null ||
    !sameInstant(historicalReplay.updated_at, markRead.updated_at)
  ) {
    throw new Error(
      'Historical notification replay did not return the exact stored result.',
    );
  }
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, dismissed.read_at) &&
      sameInstant(rows[0].dismissed_at, dismissed.dismissed_at) &&
      sameInstant(rows[0].updated_at, dismissed.updated_at),
    'unchanged dismissed notification after historical replay',
  );
  await assertRows(
    `notification_action_requests?select=request_id,user_id,notification_id,contract_version,command,expected_updated_at,result_is_read,result_read_at,result_dismissed_at,result_updated_at&notification_id=eq.${notificationId}&order=created_at.asc`,
    (rows) =>
      rows.length === 3 &&
      rows.every(
        (row) =>
          row.user_id === userId &&
          row.notification_id === notificationId &&
          row.contract_version === 'notification-lifecycle-v1',
      ) &&
      rows[0].request_id === markReadRequest.request_id &&
      rows[0].command === 'mark_read' &&
      sameInstant(rows[0].expected_updated_at, createdAt) &&
      rows[0].result_is_read === true &&
      sameInstant(rows[0].result_read_at, markRead.read_at) &&
      rows[0].result_dismissed_at === null &&
      sameInstant(rows[0].result_updated_at, markRead.updated_at) &&
      rows[1].request_id === markUnreadRequest.request_id &&
      rows[1].command === 'mark_unread' &&
      sameInstant(rows[1].expected_updated_at, markRead.updated_at) &&
      rows[1].result_is_read === false &&
      rows[1].result_read_at === null &&
      rows[1].result_dismissed_at === null &&
      sameInstant(rows[1].result_updated_at, markUnread.updated_at) &&
      rows[2].request_id === dismissRequest.request_id &&
      rows[2].command === 'dismiss' &&
      sameInstant(rows[2].expected_updated_at, markUnread.updated_at) &&
      rows[2].result_is_read === true &&
      sameInstant(rows[2].result_read_at, dismissed.read_at) &&
      sameInstant(rows[2].result_dismissed_at, dismissed.dismissed_at) &&
      sameInstant(rows[2].result_updated_at, dismissed.updated_at),
    'three exact Notification lifecycle request identities',
  );

  const dismissedAction = await notificationActionRequest(
    accessToken,
    notificationId,
    {
      contract_version: 'notification-lifecycle-v1',
      request_id: crypto.randomUUID(),
      command: 'mark_read',
      expected_updated_at: dismissed.updated_at,
    },
  );
  const dismissedActionText = await dismissedAction.text();
  let dismissedActionBody = null;
  try {
    dismissedActionBody = JSON.parse(dismissedActionText);
  } catch (_) {
    // The exact JSON detail assertion below reports the raw response.
  }
  if (
    dismissedAction.status !== 409 ||
    dismissedActionBody?.detail !== 'Notification is already dismissed'
  ) {
    throw new Error(
      `Dismissed notification did not reject a new command exactly: ${dismissedAction.status} ${dismissedActionText}`,
    );
  }
  await assertRows(
    `notifications?select=id,is_read,read_at,dismissed_at,updated_at&id=eq.${notificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].is_read === true &&
      sameInstant(rows[0].read_at, dismissed.read_at) &&
      sameInstant(rows[0].dismissed_at, dismissed.dismissed_at) &&
      sameInstant(rows[0].updated_at, dismissed.updated_at),
    'unchanged tombstone after dismissed notification conflict',
  );

  await assertRows(
    `notifications?select=id,title,message,type,priority,is_read,read_at,dismissed_at,action_url,due_at,metadata,created_at,updated_at&id=eq.${futureNotificationId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === notificationFutureTitle &&
      rows[0].message === 'This future Inbox item must remain hidden.' &&
      rows[0].type === 'reminder' &&
      rows[0].priority === 'low' &&
      rows[0].is_read === false &&
      rows[0].read_at === null &&
      rows[0].dismissed_at === null &&
      rows[0].action_url === null &&
      sameInstant(rows[0].due_at, futureDueAt) &&
      stableJson(rows[0].metadata) === stableJson({ source: 'e2e-future' }) &&
      sameInstant(rows[0].created_at, createdAt) &&
      sameInstant(rows[0].updated_at, createdAt),
    'unchanged hidden future-due notification',
  );

  await page.goto(appRoute('/alerts'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Inbox');
  await expectText(page, 'Your inbox is empty.');
  await assertFlutterTextAbsent(
    page,
    notificationLifecycleTitle,
    'dismissed notification after Inbox reload',
  );
  await assertFlutterTextAbsent(
    page,
    notificationFutureTitle,
    'future-due notification after Inbox reload',
  );

  await assertDisposableAccountExportAndDeletion({
    mainPage: page,
    mainUserId: userId,
    mainNotificationId: notificationId,
    mainFutureNotificationId: futureNotificationId,
    user: secondary,
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    accessToken: secondaryToken,
  });
}

async function assertNotificationDelivery(page, userId) {
  const accessToken = await signInAccessToken('Notification delivery');
  const initialResponse = await notificationSettingsRequest(
    accessToken,
    'GET',
  );
  const initialText = await initialResponse.text();
  let initialSettings;
  try {
    initialSettings = JSON.parse(initialText);
  } catch (_) {
    initialSettings = null;
  }
  if (initialResponse.status !== 200) {
    throw new Error(
      `Initial Notification settings failed: ${initialResponse.status} ${initialText}`,
    );
  }
  assertNotificationSettingsResponse(initialSettings, {
    enabled: false,
    replayed: false,
  });
  if (
    initialSettings.categories.focus_prompt !== false ||
    initialSettings.categories.recovery_prompt !== false ||
    initialSettings.categories.weekly_summary !== false
  ) {
    throw new Error(
      `No-reminders Setup preference changed unexpectedly: ${initialText}`,
    );
  }
  await assertRows(
    `notification_preferences?select=user_id,in_app_delivery_enabled,in_app_delivery_consent_version,in_app_delivery_consented_at,in_app_delivery_disabled_at,focus_prompts_enabled,recovery_prompts_enabled,weekly_summary_enabled,daily_notification_limit,updated_at&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].in_app_delivery_enabled === false &&
      rows[0].in_app_delivery_consent_version === null &&
      rows[0].in_app_delivery_consented_at === null &&
      rows[0].in_app_delivery_disabled_at === null &&
      rows[0].focus_prompts_enabled === false &&
      rows[0].recovery_prompts_enabled === false &&
      rows[0].weekly_summary_enabled === false &&
      rows[0].daily_notification_limit === 2,
    'fail-closed in-app consent separate from No-reminders Setup preferences',
  );

  const settingsGetPromise = page.waitForResponse(
    (candidate) =>
      candidate.url() === `${aiServiceBaseUrl}/v1/notifications/settings` &&
      candidate.request().method() === 'GET' &&
      candidate.ok(),
    { timeout: 45000 },
  );
  await page.goto(appRoute('/settings/notifications'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await settingsGetPromise;
  await expectText(page, 'In-app reminders');
  await expectText(page, 'Banners only while the app is open');
  await expectText(
    page,
    'Shows a banner only while MyLifeGraph is open. This is separate from your saved reminder preference.',
  );
  await page
    .getByLabel('Allow in-app banners', { exact: false })
    .first()
    .click();
  await page.getByLabel('Recovery prompt', { exact: false }).first().click();
  await scrollUntilTextInViewport(page, 'Save in-app reminders', {
    deltaY: 650,
    buttonFirst: true,
  });
  await clickByText(page, 'Save in-app reminders');
  await expectText(page, 'Allow in-app banners?');
  await expectText(
    page,
    'Your Setup preference did not turn these on.',
  );
  const settingsPatchPromise = page.waitForResponse(
    (candidate) =>
      candidate.url() === `${aiServiceBaseUrl}/v1/notifications/settings` &&
      candidate.request().method() === 'PATCH',
    { timeout: 45000 },
  );
  await clickByText(page, 'Allow while open');
  const settingsPatchResponse = await settingsPatchPromise;
  if (!settingsPatchResponse.ok()) {
    throw new Error(
      `Notification consent save failed: ${settingsPatchResponse.status()} ${await settingsPatchResponse.text()}`,
    );
  }
  const consentRequest = settingsPatchResponse.request().postDataJSON();
  const expectedSettingsKeys = [
    'categories',
    'consent_version',
    'contract_version',
    'daily_limit',
    'expected_updated_at',
    'in_app_delivery_enabled',
    'quiet_hours',
    'request_id',
  ];
  if (
    stableJson(Object.keys(consentRequest).sort()) !==
      stableJson(expectedSettingsKeys) ||
    consentRequest.contract_version !== 'notification-settings-v1' ||
    !isUuid(consentRequest.request_id) ||
    !sameInstant(
      consentRequest.expected_updated_at,
      initialSettings.updated_at,
    ) ||
    consentRequest.in_app_delivery_enabled !== true ||
    consentRequest.consent_version !== 'in-app-notification-consent-v1' ||
    stableJson(consentRequest.categories) !==
      stableJson({
        focus_prompt: false,
        recovery_prompt: true,
        weekly_summary: false,
      }) ||
    consentRequest.quiet_hours !== null ||
    consentRequest.daily_limit !== 2
  ) {
    throw new Error(
      `Notification consent request was not exact: ${JSON.stringify(consentRequest)}`,
    );
  }
  const consentSettings = await settingsPatchResponse.json();
  assertNotificationSettingsResponse(consentSettings, {
    enabled: true,
    replayed: false,
    categories: consentRequest.categories,
    quietHours: null,
    dailyLimit: 2,
  });
  await expectText(page, 'In-app reminder settings saved.');

  const replayResponse = await notificationSettingsRequest(
    accessToken,
    'PATCH',
    consentRequest,
  );
  const replayText = await replayResponse.text();
  const replaySettings = JSON.parse(replayText);
  if (replayResponse.status !== 200) {
    throw new Error(
      `Exact Notification settings replay failed: ${replayResponse.status} ${replayText}`,
    );
  }
  assertNotificationSettingsResponse(replaySettings, {
    enabled: true,
    replayed: true,
    categories: consentRequest.categories,
    quietHours: null,
    dailyLimit: 2,
  });
  if (!sameInstant(replaySettings.updated_at, consentSettings.updated_at)) {
    throw new Error(
      `Exact Notification settings replay changed the row: ${replayText}`,
    );
  }
  const conflictingResponse = await notificationSettingsRequest(
    accessToken,
    'PATCH',
    { ...consentRequest, daily_limit: 3 },
  );
  const conflictingText = await conflictingResponse.text();
  let conflictingBody = null;
  try {
    conflictingBody = JSON.parse(conflictingText);
  } catch (_) {
    // The exact assertion below reports the raw response.
  }
  if (
    conflictingResponse.status !== 409 ||
    conflictingBody?.detail !==
      'Notification settings request id was already used'
  ) {
    throw new Error(
      `Reinterpreted Notification settings identity was not rejected: ${conflictingResponse.status} ${conflictingText}`,
    );
  }

  const deliveryResponsePromise = page.waitForResponse(
    (candidate) =>
      candidate.url().startsWith(`${aiServiceBaseUrl}/v1/notifications/`) &&
      candidate.url().endsWith('/delivery') &&
      candidate.request().method() === 'POST',
    { timeout: 45000 },
  );
  const generated = await scheduledRefreshRequest({
    profile_ids: [userId],
    window_days: 7,
    limit: 1,
    include_recommendations: false,
    include_notifications: true,
  });
  const generatedResult = generated.results?.[0];
  if (
    !isIsoTimestamp(generated.run_at) ||
    generated.target_date !== null ||
    generated.processed !== 1 ||
    generated.succeeded !== 1 ||
    generated.failed !== 0 ||
    generatedResult?.user_id !== userId ||
    generatedResult?.status !== 'succeeded' ||
    !['stale_briefing', 'notification_delivery'].includes(
      generatedResult?.selection_reason,
    ) ||
    generatedResult?.notification_status !== 'created' ||
    generatedResult?.notification_created_count !== 1 ||
    generatedResult?.notification_duplicate_count !== 0 ||
    generatedResult?.failed_stage !== null ||
    generatedResult?.error !== null
  ) {
    throw new Error(
      `Scheduled Notification generation violated its result contract: ${JSON.stringify(generated)}`,
    );
  }

  const deliveryResponse = await deliveryResponsePromise;
  if (!deliveryResponse.ok()) {
    throw new Error(
      `Foreground Notification receipt failed: ${deliveryResponse.status()} ${await deliveryResponse.text()}`,
    );
  }
  const deliveryRequest = deliveryResponse.request().postDataJSON();
  const receipt = await deliveryResponse.json();
  if (
    stableJson(deliveryRequest) !==
      stableJson({
        contract_version: 'in-app-notification-delivery-v1',
      }) ||
    receipt.contract_version !== 'in-app-notification-delivery-v1' ||
    !isUuidV5(receipt.notification_id) ||
    receipt.channel !== 'in_app' ||
    !isIsoTimestamp(receipt.delivered_at) ||
    receipt.replayed !== false
  ) {
    throw new Error(
      `Foreground Notification receipt was not exact: ${JSON.stringify({ deliveryRequest, receipt })}`,
    );
  }
  await expectText(page, 'A gentler overview is ready');
  await expectText(page, 'In-app · fixed text · not AI-written');

  const generatedRows = await fetchRows(
    `notifications?select=id,user_id,title,message,type,priority,is_read,read_at,dismissed_at,action_url,due_at,metadata,generation_key,generation_category,delivery_date,in_app_delivered_at,created_at,updated_at&id=eq.${receipt.notification_id}`,
    'generated and acknowledged in-app Notification',
  );
  const generatedRow = generatedRows[0];
  if (
    generatedRows.length !== 1 ||
    generatedRow.user_id !== userId ||
    generatedRow.title !== 'A gentler overview is ready' ||
    generatedRow.message !==
      'Open Today to review a manageable schedule and actions. No private check-in details are included here.' ||
    generatedRow.type !== 'coaching' ||
    generatedRow.priority !== 'medium' ||
    generatedRow.is_read !== false ||
    generatedRow.read_at !== null ||
    generatedRow.dismissed_at !== null ||
    generatedRow.action_url !== '/dashboard' ||
    generatedRow.generation_key !==
      `notification-generation-v1:recovery_prompt:${generatedResult.briefing_date}` ||
    generatedRow.generation_category !== 'recovery_prompt' ||
    generatedRow.delivery_date !== generatedResult.briefing_date ||
    generatedRow.metadata?.contract_version !== 'notification-generation-v1' ||
    generatedRow.metadata?.origin !== 'deterministic_backend' ||
    generatedRow.metadata?.category !== 'recovery_prompt' ||
    generatedRow.metadata?.reason_code !== 'current_recovery_mode' ||
    generatedRow.metadata?.delivery_date !== generatedResult.briefing_date ||
    generatedRow.metadata?.timezone !== 'Europe/Berlin' ||
    generatedRow.metadata?.source_kind !== 'daily_state' ||
    typeof generatedRow.metadata?.source_id !== 'string' ||
    !isIsoTimestamp(generatedRow.metadata?.source_generated_at) ||
    generatedRow.metadata?.sensitive_copy_excluded !== true ||
    generatedRow.metadata?.llm_used !== false ||
    !sameInstant(generatedRow.in_app_delivered_at, receipt.delivered_at) ||
    !sameInstant(generatedRow.created_at, generatedRow.due_at) ||
    !sameInstant(generatedRow.updated_at, generatedRow.created_at)
  ) {
    throw new Error(
      `Generated Notification row or provenance was invalid: ${JSON.stringify(generatedRows)}`,
    );
  }
  const serializedGeneratedRow = JSON.stringify(generatedRow);
  for (const privateText of [
    editedEveningTomorrowPriority,
    'workload',
    'mostly_controllable',
  ]) {
    if (serializedGeneratedRow.includes(privateText)) {
      throw new Error(
        `Generated Notification leaked private source content: ${JSON.stringify(privateText)}`,
      );
    }
  }

  const repeated = await scheduledRefreshRequest({
    profile_ids: [userId],
    window_days: 7,
    limit: 1,
    include_recommendations: false,
    include_notifications: true,
  });
  const repeatedResult = repeated.results?.[0];
  if (
    repeated.processed !== 1 ||
    repeated.succeeded !== 1 ||
    repeated.failed !== 0 ||
    repeatedResult?.selection_reason !== 'notification_delivery' ||
    repeatedResult?.notification_status !== 'duplicate' ||
    repeatedResult?.notification_created_count !== 0 ||
    repeatedResult?.notification_duplicate_count !== 1
  ) {
    throw new Error(
      `Repeated Notification generation was not deduplicated: ${JSON.stringify(repeated)}`,
    );
  }
  await assertRows(
    `notifications?select=id,generation_key,in_app_delivered_at&user_id=eq.${userId}&generation_key=eq.${encodeURIComponent(generatedRow.generation_key)}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === generatedRow.id &&
      sameInstant(rows[0].in_app_delivered_at, receipt.delivered_at),
    'one stable generated Notification after scheduler replay',
  );

  const receiptReplayResponse = await notificationDeliveryRequest(
    accessToken,
    generatedRow.id,
  );
  const receiptReplayText = await receiptReplayResponse.text();
  const receiptReplay = JSON.parse(receiptReplayText);
  if (
    receiptReplayResponse.status !== 200 ||
    receiptReplay.contract_version !== 'in-app-notification-delivery-v1' ||
    receiptReplay.notification_id !== generatedRow.id ||
    receiptReplay.channel !== 'in_app' ||
    receiptReplay.replayed !== true ||
    !sameInstant(receiptReplay.delivered_at, receipt.delivered_at)
  ) {
    throw new Error(
      `In-app receipt replay changed delivery identity: ${receiptReplayResponse.status} ${receiptReplayText}`,
    );
  }

  let currentSettings = consentSettings;
  currentSettings = await updateNotificationSettingsForE2e(
    accessToken,
    currentSettings,
    {
      categories: {
        focus_prompt: false,
        recovery_prompt: false,
        weekly_summary: false,
      },
    },
  );
  const categoryRejected = await notificationGenerationRpcForE2e({
    userId,
    generatedRow,
    generationKey: `notification-generation-v1:e2e-category:${runId}`,
  });
  if (stableJson(categoryRejected) !== stableJson({ status: 'category_disabled' })) {
    throw new Error(
      `Disabled Notification category was not rejected: ${JSON.stringify(categoryRejected)}`,
    );
  }

  currentSettings = await updateNotificationSettingsForE2e(
    accessToken,
    currentSettings,
    {
      categories: {
        focus_prompt: false,
        recovery_prompt: true,
        weekly_summary: false,
      },
      quietHours: { starts_at: '00:00', ends_at: '00:00' },
    },
  );
  const quietRejected = await notificationGenerationRpcForE2e({
    userId,
    generatedRow,
    generationKey: `notification-generation-v1:e2e-quiet:${runId}`,
  });
  if (stableJson(quietRejected) !== stableJson({ status: 'quiet_hours' })) {
    throw new Error(
      `All-day Notification quiet window was not enforced: ${JSON.stringify(quietRejected)}`,
    );
  }

  currentSettings = await updateNotificationSettingsForE2e(
    accessToken,
    currentSettings,
    { quietHours: null, dailyLimit: 1 },
  );
  const capRejected = await notificationGenerationRpcForE2e({
    userId,
    generatedRow,
    generationKey: `notification-generation-v1:e2e-cap:${runId}`,
  });
  if (stableJson(capRejected) !== stableJson({ status: 'daily_limit' })) {
    throw new Error(
      `Notification local-date cap was not enforced: ${JSON.stringify(capRejected)}`,
    );
  }
  const duplicateBeforePolicy = await notificationGenerationRpcForE2e({
    userId,
    generatedRow,
    notificationId: crypto.randomUUID(),
    generationKey: generatedRow.generation_key,
  });
  if (
    duplicateBeforePolicy.status !== 'duplicate' ||
    duplicateBeforePolicy.notification_id !== generatedRow.id
  ) {
    throw new Error(
      `Existing Notification identity did not win retry dedupe: ${JSON.stringify(duplicateBeforePolicy)}`,
    );
  }

  const directPreferenceWrite = await authenticatedRestRequest(
    `notification_preferences?user_id=eq.${userId}`,
    accessToken,
    { method: 'PATCH', body: { in_app_delivery_enabled: false } },
  );
  if (directPreferenceWrite.response.ok) {
    throw new Error(
      `Authenticated Flutter authority unexpectedly mutated Notification delivery settings: ${directPreferenceWrite.text}`,
    );
  }

  currentSettings = await updateNotificationSettingsForE2e(
    accessToken,
    currentSettings,
    { dailyLimit: 2 },
  );
  assertNotificationSettingsResponse(currentSettings, {
    enabled: true,
    replayed: false,
    categories: {
      focus_prompt: false,
      recovery_prompt: true,
      weekly_summary: false,
    },
    quietHours: null,
    dailyLimit: 2,
  });

  await page.goto(appRoute('/alerts'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Inbox');
  await expectText(page, generatedRow.title);
  await expectText(page, 'Fixed text · not AI-written');
  await expectText(
    page,
    `Based on your current check-in state for ${generatedRow.delivery_date} in Europe/Berlin.`,
  );
  await assertFlutterTextAbsent(
    page,
    notificationLifecycleTitle,
    'dismissed lifecycle item beside generated Notification',
  );
  await assertFlutterTextAbsent(
    page,
    notificationFutureTitle,
    'future-due item beside generated Notification',
  );
}

async function createDisposableDeadlinePlanForExport({ userId, accessToken }) {
  const localToday = isoDateInTimeZone(
    new Date().toISOString(),
    'Europe/Berlin',
  );
  const planId = crypto.randomUUID();
  const title = `E2E disposable export exam ${runId}`;
  const deadlineAt = `${addUtcDays(localToday, 8)}T12:00:00Z`;
  const proposalRequestId = crypto.randomUUID();
  const proposalBody = {
    request_id: proposalRequestId,
    plan_id: planId,
    base_revision: 0,
    kind: 'exam',
    title,
    deadline_at: deadlineAt,
    estimated_total_minutes: 90,
    credited_prior_minutes: 15,
    preferred_session_minutes: 30,
    max_daily_minutes: 60,
    planning_start_on: localToday,
    buffer_days: 1,
    source_kind: 'manual',
    use_calendar_availability: false,
  };
  const proposedResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: proposalBody },
  );
  assertDeadlinePlanApiStatus(
    proposedResult,
    200,
    'disposable export deadline proposal',
  );
  const proposed = assertDeadlinePlanEnvelope(
    proposedResult.json,
    'disposable export deadline proposal',
  );
  const blockIds = proposed.pending_revision?.blocks.map((block) => block.id);
  if (
    proposed.plan.id !== planId ||
    proposed.plan.status !== 'draft' ||
    proposed.pending_revision?.revision !== 1 ||
    proposed.pending_revision?.remaining_minutes_at_proposal !== 75 ||
    !Array.isArray(blockIds) ||
    blockIds.length < 1
  ) {
    throw new Error(
      `Disposable export Deadline Planner proposal is invalid: ${proposedResult.text}`,
    );
  }
  const confirmRequestId = crypto.randomUUID();
  const confirmedResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: confirmRequestId, expected_revision: 1 },
    },
  );
  assertDeadlinePlanApiStatus(
    confirmedResult,
    200,
    'disposable export deadline confirmation',
  );
  const confirmed = assertDeadlinePlanEnvelope(
    confirmedResult.json,
    'disposable export deadline confirmation',
  );
  if (
    confirmed.plan.status !== 'active' ||
    confirmed.plan.managed_task_id !== planId ||
    confirmed.active_revision?.revision !== 1 ||
    Object.hasOwn(confirmed, 'pending_revision')
  ) {
    throw new Error(
      `Disposable export Deadline Planner confirmation is invalid: ${confirmedResult.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,user_id,title,status,estimated_minutes,source,metadata&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === title &&
      rows[0].status === 'todo' &&
      rows[0].estimated_minutes === null &&
      rows[0].source === 'deadline-plan-v1' &&
      stableJson(rows[0].metadata) ===
        stableJson({
          contract_version: 'deadline-plan-v1',
          managed_by: 'deadline-planner',
          plan_id: planId,
        }),
    'disposable export managed task',
  );
  await assertRows(
    `deadline_plan_request_identities?select=request_id,user_id,plan_id,operation&user_id=eq.${userId}&plan_id=eq.${planId}&order=created_at.asc`,
    (rows) => {
      const byRequestId = new Map(rows.map((row) => [row.request_id, row]));
      return (
        rows.length === 2 &&
        byRequestId.get(proposalRequestId)?.operation === 'proposal' &&
        byRequestId.get(confirmRequestId)?.operation === 'confirm' &&
        rows.every((row) => row.user_id === userId && row.plan_id === planId)
      );
    },
    'disposable export Deadline Planner ledger before omission',
  );
  return {
    planId,
    title,
    deadlineAt,
    revision: 1,
    blockIds,
    proposalRequestId,
    confirmRequestId,
  };
}

async function assertDisposableAccountExportAndDeletion({
  mainPage,
  mainUserId,
  mainNotificationId,
  mainFutureNotificationId,
  user,
  emailAddress,
  passwordValue,
  accessToken,
}) {
  const userId = user?.id;
  if (!isCanonicalUuid(userId)) {
    throw new Error('Disposable account-control user has no canonical UUID.');
  }

  await waitForRows(
    `profiles?select=id,email,role,auth_provider,onboarding_completed_at&id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === userId &&
      rows[0].email === emailAddress &&
      rows[0].role === 'user' &&
      rows[0].auth_provider === 'email' &&
      rows[0].onboarding_completed_at === null,
    'disposable account profile created by the Auth trigger',
  );
  await waitForRows(
    `notification_preferences?select=user_id&user_id=eq.${userId}`,
    (rows) => rows.length === 1 && rows[0].user_id === userId,
    'disposable account Notification preferences created by the Auth trigger',
  );

  const fixtureNow = Date.now();
  const onboardedAt = new Date(fixtureNow).toISOString();
  const focusEndedAt = new Date(fixtureNow - 2 * 60_000).toISOString();
  const focusStartedAt = new Date(
    fixtureNow - 12 * 60_000,
  ).toISOString();
  const notificationCreatedAt = new Date(
    fixtureNow - 60_000,
  ).toISOString();
  const taskId = crypto.randomUUID();
  const focusId = crypto.randomUUID();
  const notificationId = crypto.randomUUID();
  const actionRequestId = crypto.randomUUID();
  const taskTitle = `E2E disposable account task ${runId}`;
  const notificationTitle = `E2E disposable account export ${runId}`;

  await patchRows(
    `profiles?id=eq.${userId}`,
    {
      timezone: 'Europe/Berlin',
      onboarding_completed_at: onboardedAt,
      updated_at: onboardedAt,
    },
    'disposable account-control profile eligibility',
  );
  const deadlinePlanFixture = await createDisposableDeadlinePlanForExport({
    userId,
    accessToken,
  });
  await insertRows('tasks', [
    {
      id: taskId,
      user_id: userId,
      title: taskTitle,
      description: 'Cascade verification target.',
      status: 'todo',
      priority: 'medium',
      deadline: null,
      estimated_minutes: 10,
      completed_at: null,
      cancelled_at: null,
      source: 'manual',
      metadata: { source: 'e2e-account-delete' },
      created_at: focusStartedAt,
      updated_at: focusStartedAt,
    },
  ]);
  await insertRows('focus_sessions', [
    {
      id: focusId,
      user_id: userId,
      task_id: taskId,
      habit_id: null,
      status: 'completed',
      started_at: focusStartedAt,
      ended_at: focusEndedAt,
      planned_minutes: 10,
      actual_minutes: 10,
      label: 'Disposable account restrict cleanup',
      metadata: {
        source: 'e2e-account-delete',
        entry_date: isoDateInTimeZone(focusStartedAt, 'Europe/Berlin'),
      },
      created_at: focusStartedAt,
      updated_at: focusEndedAt,
    },
  ]);
  const [notification] = await insertRows('notifications', [
    {
      id: notificationId,
      user_id: userId,
      title: notificationTitle,
      message: 'This tombstone must be exported while its retry ledger is omitted.',
      type: 'reminder',
      priority: 'medium',
      is_read: false,
      action_url: '/settings',
      due_at: null,
      metadata: {
        source: 'e2e-account-delete',
        contract_version: 'notification-lifecycle-v1',
      },
      created_at: notificationCreatedAt,
      updated_at: notificationCreatedAt,
    },
  ]);
  if (
    notification?.id !== notificationId ||
    notification.is_read !== false ||
    notification.read_at !== null ||
    notification.dismissed_at !== null ||
    !sameInstant(notification.updated_at, notificationCreatedAt)
  ) {
    throw new Error(
      `Disposable Notification fixture is invalid: ${JSON.stringify(notification)}`,
    );
  }

  const dismissRequest = {
    contract_version: 'notification-lifecycle-v1',
    request_id: actionRequestId,
    command: 'dismiss',
    expected_updated_at: notification.updated_at,
  };
  const dismissResponse = await notificationActionRequest(
    accessToken,
    notificationId,
    dismissRequest,
  );
  if (!dismissResponse.ok) {
    throw new Error(
      `Disposable Notification dismiss failed: ${dismissResponse.status} ${await dismissResponse.text()}`,
    );
  }
  const dismissed = assertNotificationActionResponse(
    await dismissResponse.json(),
    {
      notificationId,
      command: 'dismiss',
      replayed: false,
      expectedUpdatedAt: notification.updated_at,
    },
    'disposable account Notification dismiss response',
  );
  if (
    !sameInstant(dismissed.read_at, dismissed.updated_at) ||
    !sameInstant(dismissed.dismissed_at, dismissed.updated_at)
  ) {
    throw new Error(
      'Disposable account dismiss did not persist one exact lifecycle timestamp.',
    );
  }
  await assertRows(
    `notification_action_requests?select=request_id,user_id,notification_id,command,expected_updated_at,result_is_read,result_read_at,result_dismissed_at,result_updated_at&request_id=eq.${actionRequestId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].request_id === actionRequestId &&
      rows[0].user_id === userId &&
      rows[0].notification_id === notificationId &&
      rows[0].command === 'dismiss' &&
      sameInstant(rows[0].expected_updated_at, notification.updated_at) &&
      rows[0].result_is_read === true &&
      sameInstant(rows[0].result_read_at, dismissed.read_at) &&
      sameInstant(rows[0].result_dismissed_at, dismissed.dismissed_at) &&
      sameInstant(rows[0].result_updated_at, dismissed.updated_at),
    'disposable account Notification retry ledger before export',
  );

  const authUserBeforeDelete = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${userId}`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );
  if (!authUserBeforeDelete.ok) {
    throw new Error(
      `Disposable Auth user was unavailable before deletion: ${authUserBeforeDelete.status}`,
    );
  }

  const accountContext = await browser.newContext({
    viewport: { width: 1280, height: 960 },
    acceptDownloads: true,
  });
  const accountPage = await accountContext.newPage();
  accountPage.on('pageerror', (error) => {
    console.error(`[account-controls page error] ${error.message}`);
  });
  accountPage.on('console', (message) => {
    if (['error', 'warning'].includes(message.type())) {
      console.error(
        `[account-controls ${message.type()}] ${message.text()}`,
      );
    }
  });

  try {
    await accountPage.goto(appRoute('/auth'), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterShell(accountPage);
    await enableFlutterSemantics(accountPage);
    await fillByLabelOrPlaceholder(accountPage, 'Email', emailAddress, 0);
    await fillByLabelOrPlaceholder(
      accountPage,
      'Password',
      passwordValue,
      1,
    );
    await clickByText(accountPage, 'Login', { match: 'last' });
    await accountPage.waitForURL('**/#/dashboard', { timeout: 45000 });

    await accountPage.goto(appRoute('/settings'), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterShell(accountPage);
    await enableFlutterSemantics(accountPage);
    await expectText(accountPage, 'Settings');
    await expectText(accountPage, 'Synced account');
    const exportResponsePromise = accountPage.waitForResponse(
      (candidate) =>
        candidate.url() === `${aiServiceBaseUrl}/v1/account/export` &&
        candidate.request().method() === 'GET',
      { timeout: 45000 },
    );
    // A failed API response deliberately produces no browser download. Keep
    // that listener handled, but inspect the HTTP result first so an export
    // regression fails with the backend status/body instead of a 45-second
    // download timeout.
    const downloadPromise = accountPage
      .waitForEvent('download', { timeout: 45000 })
      .catch(() => null);
    await clickByText(accountPage, 'Export data');
    const exportResponse = await exportResponsePromise;
    if (exportResponse.status() !== 200) {
      throw new Error(
        `Unexpected account export response: ${exportResponse.status()} ${await exportResponse.text()}`,
      );
    }
    if (
      !exportResponse.headers()['content-type']?.startsWith(
        'application/json',
      ) ||
      exportResponse.headers()['cache-control'] !== 'no-store' ||
      exportResponse.headers()['content-disposition'] !==
        'attachment; filename="mylifegraph-account-export.json"'
    ) {
      throw new Error(
        `Unexpected account export response: ${exportResponse.status()} ${JSON.stringify(exportResponse.headers())}`,
      );
    }
    const download = await downloadPromise;
    if (download === null) {
      throw new Error('Account export returned no browser download.');
    }
    const exportBytes = await exportResponse.body();
    let exportPayload;
    try {
      exportPayload = JSON.parse(exportBytes.toString('utf8'));
    } catch (_) {
      throw new Error('Account export response was not UTF-8 JSON.');
    }
    assertDisposableAccountExportPayload(exportPayload, {
      userId,
      taskId,
      focusId,
      notificationId,
      dismissed,
      deadlinePlanFixture,
    });

    const downloadFailure = await download.failure();
    if (downloadFailure !== null) {
      throw new Error(`Account export download failed: ${downloadFailure}`);
    }
    if (
      !/^mylifegraph-export-\d{4}-\d{2}-\d{2}\.json$/.test(
        download.suggestedFilename(),
      )
    ) {
      throw new Error(
        `Unexpected account export filename: ${download.suggestedFilename()}`,
      );
    }
    const downloadStream = await download.createReadStream();
    if (downloadStream === null) {
      throw new Error('Account export download returned no byte stream.');
    }
    const downloadChunks = [];
    for await (const chunk of downloadStream) {
      downloadChunks.push(Buffer.from(chunk));
    }
    const downloadedBytes = Buffer.concat(downloadChunks);
    if (!downloadedBytes.equals(exportBytes)) {
      throw new Error(
        'Flutter Web account export bytes differ from the validated backend response.',
      );
    }
    await expectText(accountPage, 'Account export saved.');

    await clickByText(accountPage, 'Delete account');
    await expectText(accountPage, 'Delete account permanently?');
    await fillByLabelOrPlaceholder(
      accountPage,
      'Type DELETE to confirm',
      'DELETE',
      0,
    );
    const deleteResponsePromise = accountPage.waitForResponse(
      (candidate) =>
        candidate.url() === `${aiServiceBaseUrl}/v1/account` &&
        candidate.request().method() === 'DELETE',
      { timeout: 45000 },
    );
    await clickByText(accountPage, 'Delete account', { match: 'last' });
    const deleteResponse = await deleteResponsePromise;
    let deletePayload;
    try {
      deletePayload = deleteResponse.request().postDataJSON();
    } catch (_) {
      deletePayload = null;
    }
    const deleteBytes = await deleteResponse.body();
    if (
      deleteResponse.status() !== 204 ||
      stableJson(deletePayload) !== stableJson({ confirmation: 'DELETE' }) ||
      deleteBytes.length !== 0
    ) {
      throw new Error(
        `Unexpected account deletion response: ${deleteResponse.status()} ${JSON.stringify(deletePayload)} bytes=${deleteBytes.length}`,
      );
    }
    await accountPage.waitForURL('**/#/auth**', { timeout: 45000 });
    await expectText(accountPage, 'Account and canonical synced data deleted.');
  } catch (error) {
    try {
      await accountPage.screenshot({
        path: `${artifactDir}/failure-${runId}-account-controls.png`,
        fullPage: true,
      });
    } catch (_) {
      // The original assertion is more useful than a screenshot failure.
    }
    throw error;
  } finally {
    await accountContext.close();
  }

  const authUserAfterDelete = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${userId}`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );
  if (authUserAfterDelete.status !== 404) {
    throw new Error(
      `Deleted Auth user is still available: ${authUserAfterDelete.status}`,
    );
  }

  const deletedLogin = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        apikey: supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email: emailAddress, password: passwordValue }),
    },
  );
  if (deletedLogin.ok) {
    throw new Error('Deleted disposable account could still sign in.');
  }

  const cascadeChecks = [
    [
      `profiles?select=id&id=eq.${userId}`,
      'deleted disposable profile',
    ],
    [
      `notification_preferences?select=user_id&user_id=eq.${userId}`,
      'deleted disposable Notification preferences',
    ],
    [
      `tasks?select=id,user_id&id=eq.${taskId}`,
      'deleted disposable task',
    ],
    [
      `tasks?select=id,user_id&id=eq.${deadlinePlanFixture.planId}`,
      'deleted disposable Deadline Planner managed task',
    ],
    [
      `focus_sessions?select=id,user_id,task_id&id=eq.${focusId}`,
      'deleted disposable restrict-linked focus history',
    ],
    [
      `notifications?select=id,user_id&id=eq.${notificationId}`,
      'deleted disposable Notification tombstone',
    ],
    [
      `notification_action_requests?select=request_id,user_id,notification_id&request_id=eq.${actionRequestId}`,
      'deleted disposable Notification retry ledger',
    ],
    [
      `deadline_plans?select=id,user_id&id=eq.${deadlinePlanFixture.planId}`,
      'deleted disposable Deadline Planner identity',
    ],
    [
      `deadline_plan_revisions?select=id,user_id,plan_id&plan_id=eq.${deadlinePlanFixture.planId}`,
      'deleted disposable Deadline Planner revisions',
    ],
    [
      `deadline_plan_blocks?select=id,user_id,plan_id&plan_id=eq.${deadlinePlanFixture.planId}`,
      'deleted disposable Deadline Planner blocks',
    ],
    [
      `deadline_plan_request_identities?select=request_id,user_id,plan_id&plan_id=eq.${deadlinePlanFixture.planId}`,
      'deleted disposable Deadline Planner retry ledger',
    ],
  ];
  for (const [path, description] of cascadeChecks) {
    await assertRows(path, (rows) => rows.length === 0, description);
  }

  await assertRows(
    `profiles?select=id&id=eq.${mainUserId}`,
    (rows) => rows.length === 1 && rows[0].id === mainUserId,
    'preserved main E2E profile after disposable account deletion',
  );
  await assertRows(
    `notifications?select=id,user_id,is_read,read_at,dismissed_at,due_at&id=in.(${mainNotificationId},${mainFutureNotificationId})`,
    (rows) => {
      const lifecycle = rows.find((row) => row.id === mainNotificationId);
      const future = rows.find(
        (row) => row.id === mainFutureNotificationId,
      );
      return (
        rows.length === 2 &&
        lifecycle?.user_id === mainUserId &&
        lifecycle.is_read === true &&
        lifecycle.read_at !== null &&
        lifecycle.dismissed_at !== null &&
        future?.user_id === mainUserId &&
        future.is_read === false &&
        future.read_at === null &&
        future.dismissed_at === null &&
        future.due_at !== null
      );
    },
    'preserved main E2E Notification rows after disposable account deletion',
  );
  await expectText(mainPage, 'Inbox');
}

function assertDisposableAccountExportPayload(
  payload,
  {
    userId,
    taskId,
    focusId,
    notificationId,
    dismissed,
    deadlinePlanFixture,
  },
) {
  const expectedTopLevelKeys = [
    'contract_version',
    'data',
    'exported_at',
    'ledger_policy',
    'limits',
    'record_counts',
  ];
  const expectedTableKeys = [...accountExportV1TableNames].sort();
  const expectedRecordCounts = Object.fromEntries(
    accountExportV1TableNames.map((tableName) => [tableName, 0]),
  );
  Object.assign(expectedRecordCounts, {
    profiles: 1,
    notification_preferences: 1,
    tasks: 2,
    notifications: 1,
    focus_sessions: 1,
    deadline_plans: 1,
    deadline_plan_revisions: 1,
    deadline_plan_blocks: deadlinePlanFixture.blockIds.length,
  });
  if (
    payload === null ||
    typeof payload !== 'object' ||
    Array.isArray(payload) ||
    stableJson(Object.keys(payload).sort()) !==
      stableJson(expectedTopLevelKeys) ||
    payload.contract_version !== 'account-export-v1' ||
    !isIsoTimestamp(payload.exported_at) ||
    !/(Z|[+-]\d{2}:\d{2})$/.test(payload.exported_at) ||
    payload.data === null ||
    typeof payload.data !== 'object' ||
    Array.isArray(payload.data) ||
    payload.record_counts === null ||
    typeof payload.record_counts !== 'object' ||
    Array.isArray(payload.record_counts) ||
    stableJson(Object.keys(payload.data).sort()) !==
      stableJson(expectedTableKeys) ||
    stableJson(Object.keys(payload.record_counts).sort()) !==
      stableJson(expectedTableKeys)
  ) {
    throw new Error(
      `Account export has an invalid V1 envelope: ${JSON.stringify(payload)}`,
    );
  }
  if (stableJson(payload.record_counts) !== stableJson(expectedRecordCounts)) {
    throw new Error(
      `Account export has unexpected owner-row counts: ${JSON.stringify(payload.record_counts)}`,
    );
  }
  for (const tableName of accountExportV1TableNames) {
    if (
      !Array.isArray(payload.data[tableName]) ||
      !Number.isInteger(payload.record_counts[tableName]) ||
      payload.record_counts[tableName] !== payload.data[tableName].length
    ) {
      throw new Error(
        `Account export count mismatch for ${tableName}: ${JSON.stringify(payload.record_counts[tableName])}`,
      );
    }
  }
  if (
    Object.keys(accountExportV1OmittedTables).some(
      (tableName) =>
        Object.hasOwn(payload.data, tableName) ||
        Object.hasOwn(payload.record_counts, tableName),
    ) ||
    stableJson(payload.ledger_policy) !==
      stableJson({
        sanitized_tables: accountExportV1SanitizedTables,
        omitted_tables: accountExportV1OmittedTables,
      }) ||
    stableJson(payload.limits) !==
      stableJson({
        max_rows_per_table: 10000,
        max_total_rows: 50000,
        max_json_bytes: 8 * 1024 * 1024,
      })
  ) {
    throw new Error(
      `Account export has an invalid ledger or limit policy: ${JSON.stringify(payload)}`,
    );
  }

  const profileRows = payload.data.profiles;
  const preferenceRows = payload.data.notification_preferences;
  const taskRows = payload.data.tasks;
  const focusRows = payload.data.focus_sessions;
  const notificationRows = payload.data.notifications;
  const deadlinePlanRows = payload.data.deadline_plans;
  const deadlineRevisionRows = payload.data.deadline_plan_revisions;
  const deadlineBlockRows = payload.data.deadline_plan_blocks;
  const exportedNotification = notificationRows[0];
  const manualTask = taskRows.find((row) => row.id === taskId);
  const managedTask = taskRows.find(
    (row) => row.id === deadlinePlanFixture.planId,
  );
  const exportedPlan = deadlinePlanRows[0];
  const exportedRevision = deadlineRevisionRows[0];
  const expectedBlockIds = [...deadlinePlanFixture.blockIds].sort();
  const exportedBlockIds = deadlineBlockRows
    .map((row) => row.id)
    .sort();
  if (
    profileRows.length !== 1 ||
    profileRows[0].id !== userId ||
    profileRows[0].daily_preparation_budget_minutes !== null ||
    preferenceRows.length !== 1 ||
    preferenceRows[0].user_id !== userId ||
    taskRows.length !== 2 ||
    manualTask?.user_id !== userId ||
    managedTask?.user_id !== userId ||
    managedTask?.title !== deadlinePlanFixture.title ||
    managedTask?.status !== 'todo' ||
    managedTask?.source !== 'deadline-plan-v1' ||
    stableJson(managedTask?.metadata) !==
      stableJson({
        contract_version: 'deadline-plan-v1',
        managed_by: 'deadline-planner',
        plan_id: deadlinePlanFixture.planId,
      }) ||
    focusRows.length !== 1 ||
    focusRows[0].id !== focusId ||
    focusRows[0].user_id !== userId ||
    focusRows[0].task_id !== taskId ||
    notificationRows.length !== 1 ||
    exportedNotification.id !== notificationId ||
    exportedNotification.user_id !== userId ||
    exportedNotification.is_read !== true ||
    !sameInstant(exportedNotification.read_at, dismissed.read_at) ||
    !sameInstant(
      exportedNotification.dismissed_at,
      dismissed.dismissed_at,
    ) ||
    !sameInstant(exportedNotification.updated_at, dismissed.updated_at) ||
    deadlinePlanRows.length !== 1 ||
    exportedPlan.id !== deadlinePlanFixture.planId ||
    exportedPlan.user_id !== userId ||
    exportedPlan.status !== 'active' ||
    exportedPlan.current_revision !== deadlinePlanFixture.revision ||
    exportedPlan.latest_revision !== deadlinePlanFixture.revision ||
    exportedPlan.managed_task_id !== deadlinePlanFixture.planId ||
    deadlineRevisionRows.length !== 1 ||
    exportedRevision.user_id !== userId ||
    exportedRevision.plan_id !== deadlinePlanFixture.planId ||
    exportedRevision.revision !== deadlinePlanFixture.revision ||
    exportedRevision.state !== 'active' ||
    exportedRevision.estimated_total_minutes !== 90 ||
    exportedRevision.credited_prior_minutes !== 15 ||
    exportedRevision.remaining_minutes_at_proposal !== 75 ||
    exportedRevision.planned_minutes +
        exportedRevision.unscheduled_minutes !==
      75 ||
    stableJson(exportedBlockIds) !== stableJson(expectedBlockIds) ||
    deadlineBlockRows.some(
      (row) =>
        row.user_id !== userId ||
        row.plan_id !== deadlinePlanFixture.planId ||
        row.revision !== deadlinePlanFixture.revision ||
        row.reservation_state !== 'active',
    )
  ) {
    throw new Error(
      `Account export lost owned rows or Notification lifecycle state: ${JSON.stringify({
        profiles: profileRows,
        notification_preferences: preferenceRows,
        tasks: taskRows,
        focus_sessions: focusRows,
        notifications: notificationRows,
        deadline_plans: deadlinePlanRows,
        deadline_plan_revisions: deadlineRevisionRows,
        deadline_plan_blocks: deadlineBlockRows,
      })}`,
    );
  }
}

async function waitForNotificationAction(page, notificationId, description) {
  const response = await page.waitForResponse(
    (candidate) =>
      candidate.url() ===
        `${aiServiceBaseUrl}/v1/notifications/${notificationId}/actions` &&
      candidate.request().method() === 'POST',
    { timeout: 45000 },
  );
  if (!response.ok()) {
    throw new Error(
      `Unexpected ${description} response: ${response.status()} ${await response.text()}`,
    );
  }
  return response;
}

function assertNotificationActionRequest(
  request,
  { notificationId, command, expectedUpdatedAt },
  description,
) {
  const payload = request.postData() ? JSON.parse(request.postData()) : {};
  const expectedKeys = [
    'command',
    'contract_version',
    'expected_updated_at',
    'request_id',
  ];
  if (
    stableJson(Object.keys(payload).sort()) !== stableJson(expectedKeys) ||
    payload.contract_version !== 'notification-lifecycle-v1' ||
    payload.command !== command ||
    !isUuid(payload.request_id) ||
    !sameInstant(payload.expected_updated_at, expectedUpdatedAt) ||
    !request.url().endsWith(`/v1/notifications/${notificationId}/actions`)
  ) {
    throw new Error(
      `Unexpected ${description}: ${JSON.stringify(payload)}`,
    );
  }
  return payload;
}

function assertNotificationActionResponse(
  payload,
  { notificationId, command, replayed, expectedUpdatedAt },
  description,
) {
  const expectedKeys = [
    'command',
    'contract_version',
    'dismissed_at',
    'is_read',
    'notification_id',
    'read_at',
    'replayed',
    'updated_at',
  ];
  const readExpected = command !== 'mark_unread';
  const dismissedExpected = command === 'dismiss';
  if (
    payload === null ||
    typeof payload !== 'object' ||
    Array.isArray(payload) ||
    stableJson(Object.keys(payload).sort()) !== stableJson(expectedKeys) ||
    payload.contract_version !== 'notification-lifecycle-v1' ||
    payload.notification_id !== notificationId ||
    payload.command !== command ||
    payload.is_read !== readExpected ||
    payload.replayed !== replayed ||
    (readExpected ? !isIsoTimestamp(payload.read_at) : payload.read_at !== null) ||
    (dismissedExpected
      ? !isIsoTimestamp(payload.dismissed_at)
      : payload.dismissed_at !== null) ||
    !isIsoTimestamp(payload.updated_at) ||
    !instantIsAfter(payload.updated_at, expectedUpdatedAt) ||
    (payload.read_at !== null &&
      instantIsAfter(payload.read_at, payload.updated_at)) ||
    (payload.dismissed_at !== null &&
      instantIsAfter(payload.dismissed_at, payload.updated_at))
  ) {
    throw new Error(
      `Unexpected ${description}: ${JSON.stringify(payload)}`,
    );
  }
  return payload;
}

async function notificationActionRequest(accessToken, notificationId, body) {
  return fetch(
    `${aiServiceBaseUrl}/v1/notifications/${notificationId}/actions`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
}

async function notificationSettingsRequest(accessToken, method, body) {
  return fetch(`${aiServiceBaseUrl}/v1/notifications/settings`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

function assertNotificationSettingsResponse(
  payload,
  {
    enabled,
    replayed,
    categories,
    quietHours,
    dailyLimit,
  },
) {
  const expectedKeys = [
    'categories',
    'consent_version',
    'consented_at',
    'contract_version',
    'daily_limit',
    'disabled_at',
    'in_app_delivery_enabled',
    'quiet_hours',
    'replayed',
    'updated_at',
  ];
  if (
    payload === null ||
    typeof payload !== 'object' ||
    Array.isArray(payload) ||
    stableJson(Object.keys(payload).sort()) !== stableJson(expectedKeys) ||
    payload.contract_version !== 'notification-settings-v1' ||
    payload.in_app_delivery_enabled !== enabled ||
    payload.replayed !== replayed ||
    !isIsoTimestamp(payload.updated_at) ||
    typeof payload.categories !== 'object' ||
    payload.categories === null ||
    Array.isArray(payload.categories) ||
    stableJson(Object.keys(payload.categories).sort()) !==
      stableJson(['focus_prompt', 'recovery_prompt', 'weekly_summary']) ||
    !Object.values(payload.categories).every((value) => typeof value === 'boolean') ||
    (categories !== undefined &&
      stableJson(payload.categories) !== stableJson(categories)) ||
    (quietHours !== undefined &&
      stableJson(payload.quiet_hours) !== stableJson(quietHours)) ||
    (dailyLimit !== undefined && payload.daily_limit !== dailyLimit) ||
    !Number.isInteger(payload.daily_limit) ||
    payload.daily_limit < 1 ||
    payload.daily_limit > 5 ||
    (payload.quiet_hours !== null &&
      (typeof payload.quiet_hours !== 'object' ||
        stableJson(Object.keys(payload.quiet_hours).sort()) !==
          stableJson(['ends_at', 'starts_at']) ||
        !/^\d{2}:\d{2}$/.test(payload.quiet_hours.starts_at) ||
        !/^\d{2}:\d{2}$/.test(payload.quiet_hours.ends_at))) ||
    (enabled
      ? payload.consent_version !== 'in-app-notification-consent-v1' ||
        !isIsoTimestamp(payload.consented_at) ||
        payload.disabled_at !== null
      : payload.consented_at === null
        ? payload.consent_version !== null || payload.disabled_at !== null
        : payload.consent_version !== 'in-app-notification-consent-v1' ||
          !isIsoTimestamp(payload.consented_at) ||
          !isIsoTimestamp(payload.disabled_at))
  ) {
    throw new Error(
      `Notification settings response violated its contract: ${JSON.stringify(payload)}`,
    );
  }
}

async function updateNotificationSettingsForE2e(
  accessToken,
  current,
  changes,
) {
  const categories = changes.categories ?? current.categories;
  const quietHours = Object.hasOwn(changes, 'quietHours')
    ? changes.quietHours
    : current.quiet_hours;
  const dailyLimit = changes.dailyLimit ?? current.daily_limit;
  const body = {
    contract_version: 'notification-settings-v1',
    request_id: crypto.randomUUID(),
    expected_updated_at: current.updated_at,
    in_app_delivery_enabled:
      changes.enabled ?? current.in_app_delivery_enabled,
    consent_version: 'in-app-notification-consent-v1',
    categories,
    quiet_hours: quietHours,
    daily_limit: dailyLimit,
  };
  const response = await notificationSettingsRequest(
    accessToken,
    'PATCH',
    body,
  );
  const text = await response.text();
  let payload = null;
  try {
    payload = JSON.parse(text);
  } catch (_) {
    // The status assertion below reports the raw response.
  }
  if (response.status !== 200) {
    throw new Error(
      `Notification settings E2E update failed: ${response.status} ${text}`,
    );
  }
  assertNotificationSettingsResponse(payload, {
    enabled: body.in_app_delivery_enabled,
    replayed: false,
    categories,
    quietHours,
    dailyLimit,
  });
  return payload;
}

async function notificationDeliveryRequest(accessToken, notificationId) {
  return fetch(
    `${aiServiceBaseUrl}/v1/notifications/${notificationId}/delivery`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contract_version: 'in-app-notification-delivery-v1',
      }),
    },
  );
}

async function notificationGenerationRpcForE2e({
  userId,
  generatedRow,
  generationKey,
  notificationId = crypto.randomUUID(),
}) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/create_generated_notification_v1`,
    {
      method: 'POST',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_user_id: userId,
        p_notification_id: notificationId,
        p_generation_key: generationKey,
        p_category: 'recovery_prompt',
        p_delivery_date: generatedRow.delivery_date,
        p_run_at: generatedRow.created_at,
        p_timezone: generatedRow.metadata.timezone,
        p_title: 'E2E policy guard candidate',
        p_message: 'This fixed E2E candidate must remain policy controlled.',
        p_type: 'coaching',
        p_priority: 'medium',
        p_action_url: '/dashboard',
        p_reason_code: 'e2e_policy_guard',
        p_source_kind: generatedRow.metadata.source_kind,
        p_source_id: generatedRow.metadata.source_id,
        p_source_generated_at: generatedRow.metadata.source_generated_at,
      }),
    },
  );
  const text = await response.text();
  let payload = null;
  try {
    payload = JSON.parse(text);
  } catch (_) {
    // The status assertion below reports the raw response.
  }
  if (!response.ok) {
    throw new Error(
      `Notification generation policy RPC failed: ${response.status} ${text}`,
    );
  }
  return payload;
}

function sameInstant(left, right) {
  const leftNanos = isoInstantNanoseconds(left);
  const rightNanos = isoInstantNanoseconds(right);
  return leftNanos !== null && rightNanos !== null && leftNanos === rightNanos;
}

function instantIsAfter(left, right) {
  const leftNanos = isoInstantNanoseconds(left);
  const rightNanos = isoInstantNanoseconds(right);
  return leftNanos !== null && rightNanos !== null && leftNanos > rightNanos;
}

function isoInstantNanoseconds(value) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) {
    return null;
  }
  const match = value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$/,
  );
  if (!match) {
    return null;
  }
  const [, year, month, day, hour, minute, second, fraction = '', zone] =
    match;
  const localMillis = Date.UTC(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    Number(second),
  );
  let offsetMinutes = 0;
  if (zone !== 'Z') {
    const sign = zone[0] === '+' ? 1 : -1;
    offsetMinutes =
      sign * (Number(zone.slice(1, 3)) * 60 + Number(zone.slice(4, 6)));
  }
  const epochMillis = localMillis - offsetMinutes * 60_000;
  return (
    BigInt(epochMillis) * 1_000_000n +
    BigInt(fraction.padEnd(9, '0'))
  );
}

async function assertBoundedWeeklyReview(page, userId) {
  await scrollUntilTextInViewport(page, 'More', {
    deltaY: 500,
    buttonFirst: true,
  });
  await clickByText(page, 'More');
  await expectText(page, 'Review your week');
  const timezone = 'Europe/Berlin';
  const period = latestCompletedIsoWeek(timezone);
  const createdBeforeWeek = isoTimestampOnDate(
    addUtcDays(period.startsOn, -7),
    '08:00:00',
  );
  const monday = period.startsOn;
  const tuesday = addUtcDays(monday, 1);
  const wednesday = addUtcDays(monday, 2);
  const thursday = addUtcDays(monday, 3);
  const friday = addUtcDays(monday, 4);
  const manualHabitId = crypto.randomUUID();
  const setupHabitId = crypto.randomUUID();
  const goalId = crypto.randomUUID();
  const completedTaskId = crypto.randomUUID();
  const carriedTaskId = crypto.randomUUID();
  const focusId = crypto.randomUUID();
  const briefingId = crypto.randomUUID();
  const manualHabitTitle = `E2E weekly target ${runId}`;
  const setupHabitTitle = `E2E weekly setup habit ${runId}`;
  const stableHabitUpdatedAt = createdBeforeWeek;

  await insertRows('goals', [
    {
      id: goalId,
      user_id: userId,
      title: `E2E weekly goal ${runId}`,
      status: 'active',
      progress: 10,
      metadata: { source: 'manual-e2e-phase-8' },
      created_at: createdBeforeWeek,
      updated_at: createdBeforeWeek,
    },
  ]);
  await insertRows('tasks', [
    {
      id: completedTaskId,
      user_id: userId,
      title: `E2E weekly completed task ${runId}`,
      status: 'done',
      priority: 'high',
      deadline: null,
      completed_at: isoTimestampOnDate(tuesday, '12:00:00'),
      cancelled_at: null,
      source: 'manual',
      metadata: { goal_id: goalId, source: 'manual-e2e-phase-8' },
      created_at: createdBeforeWeek,
      updated_at: isoTimestampOnDate(tuesday, '12:00:00'),
    },
    {
      id: carriedTaskId,
      user_id: userId,
      title: `E2E weekly carried task ${runId}`,
      status: 'todo',
      priority: 'medium',
      deadline: isoTimestampOnDate(friday, '09:00:00'),
      completed_at: null,
      cancelled_at: null,
      source: 'manual',
      metadata: { source: 'manual-e2e-phase-8' },
      created_at: createdBeforeWeek,
      updated_at: createdBeforeWeek,
    },
  ]);
  await insertRows('habits', [
    {
      id: manualHabitId,
      user_id: userId,
      title: manualHabitTitle,
      frequency: 'weekly',
      target: 4,
      active: true,
      metadata: {
        source: 'flutter-habit-management-v1',
        contract_version: 'habit-v1',
        cadence: 'weekly_target',
        lifecycle: 'active',
        started_on: addUtcDays(monday, -14),
      },
      created_at: createdBeforeWeek,
      updated_at: stableHabitUpdatedAt,
    },
    {
      id: setupHabitId,
      user_id: userId,
      title: setupHabitTitle,
      frequency: 'weekly',
      target: 4,
      active: true,
      metadata: {
        source: 'intake-v1',
        managed_by: 'setup',
        setup_state: 'active',
        setup_item_id: crypto.randomUUID(),
        revision: 4,
        contract_version: 'habit-v1',
        cadence: 'weekly_target',
        started_on: addUtcDays(monday, -14),
      },
      created_at: createdBeforeWeek,
      updated_at: createdBeforeWeek,
    },
  ]);
  await insertRows('habit_logs', [
    {
      user_id: userId,
      habit_id: manualHabitId,
      entry_date: monday,
      status: 'completed',
      value: 1,
      created_at: isoTimestampOnDate(monday, '18:00:00'),
      updated_at: isoTimestampOnDate(monday, '18:00:00'),
    },
    {
      user_id: userId,
      habit_id: manualHabitId,
      entry_date: thursday,
      status: 'completed',
      value: 1,
      created_at: isoTimestampOnDate(thursday, '18:00:00'),
      updated_at: isoTimestampOnDate(thursday, '18:00:00'),
    },
    {
      user_id: userId,
      habit_id: setupHabitId,
      entry_date: monday,
      status: 'completed',
      value: 1,
      created_at: isoTimestampOnDate(monday, '18:05:00'),
      updated_at: isoTimestampOnDate(monday, '18:05:00'),
    },
    {
      user_id: userId,
      habit_id: setupHabitId,
      entry_date: thursday,
      status: 'completed',
      value: 1,
      created_at: isoTimestampOnDate(thursday, '18:05:00'),
      updated_at: isoTimestampOnDate(thursday, '18:05:00'),
    },
  ]);
  await insertRows('focus_sessions', [
    {
      id: focusId,
      user_id: userId,
      status: 'completed',
      started_at: isoTimestampOnDate(wednesday, '10:00:00'),
      ended_at: isoTimestampOnDate(wednesday, '10:25:00'),
      planned_minutes: 30,
      actual_minutes: 25,
      distractions: 0,
      social_media_warning: false,
      metadata: { entry_date: wednesday, source: 'manual-e2e-phase-8' },
      created_at: isoTimestampOnDate(wednesday, '10:00:00'),
      updated_at: isoTimestampOnDate(wednesday, '10:25:00'),
    },
  ]);

  await upsertRows(
    'user_state_snapshots',
    Array.from({ length: 7 }, (_, index) => {
      const entryDate = addUtcDays(monday, index);
      return {
        id: crypto.randomUUID(),
        user_id: userId,
        scope: 'daily',
        period_key: entryDate,
        summary: {
          daily_state: {
            contract_version: 'explainable-daily-state-v1',
            target_date: entryDate,
            mode: entryDate === friday ? 'recover' : 'steady',
            data_quality: 'current',
          },
        },
        signals: {},
        source: 'backend',
        generated_at: isoTimestampOnDate(entryDate, '19:00:00'),
        metadata: {
          source: 'snapshot-aggregator-v1',
          daily_state_contract_version: 'explainable-daily-state-v1',
          target_date: entryDate,
          window_days: 7,
          state_lookback_days: 7,
        },
      };
    }),
    'user_id,scope,period_key',
  );
  await insertRows('daily_briefings', [
    {
      id: briefingId,
      user_id: userId,
      briefing_date: wednesday,
      mode: 'steady',
      summary: 'E2E weekly review feedback source',
      primary_action: {
        target: {
          contract_version: 'executable-action-v1',
          id: `log_habit:${manualHabitId}:${wednesday}`,
          kind: 'habit',
          command: 'log_habit',
          target_id: manualHabitId,
          metadata: {
            entry_date: wednesday,
            habit_outcome: 'completed',
            source: 'daily-briefing-v1',
          },
        },
        title: manualHabitTitle,
        reason: 'E2E weekly review feedback evidence',
        evidence_refs: [],
      },
      support_actions: [],
      evidence_refs: [],
      provenance: {
        engine: 'deterministic',
        contract_version: 'daily-briefing-v1',
        llm_used: false,
      },
      data_quality: 'current',
      metadata: {
        contract_version: 'daily-briefing-v1',
        capacity_note: 'A bounded E2E week.',
      },
      generated_at: isoTimestampOnDate(wednesday, '07:00:00'),
      created_at: isoTimestampOnDate(wednesday, '07:00:00'),
      updated_at: isoTimestampOnDate(wednesday, '07:00:00'),
    },
  ]);
  await insertRows('decision_feedback', [
    {
      user_id: userId,
      request_id: crypto.randomUUID(),
      briefing_id: briefingId,
      action_id: `log_habit:${manualHabitId}:${wednesday}`,
      action_kind: 'habit',
      feedback_type: 'too_much',
      context_mode: 'steady',
      rule_key: 'habit_due',
      metadata: {
        contract_version: 'decision-feedback-v1',
        briefing_date: wednesday,
      },
      created_at: isoTimestampOnDate(wednesday, '20:00:00'),
    },
    {
      user_id: userId,
      request_id: crypto.randomUUID(),
      briefing_id: briefingId,
      action_id: `log_habit:${setupHabitId}:${wednesday}`,
      action_kind: 'habit',
      feedback_type: 'too_much',
      context_mode: 'steady',
      rule_key: 'habit_due',
      metadata: {
        contract_version: 'decision-feedback-v1',
        briefing_date: wednesday,
      },
      created_at: isoTimestampOnDate(wednesday, '20:05:00'),
    },
  ]);

  const accessToken = await signInAccessToken('Phase 8 weekly review');
  const weeklySnapshot = await briefingRequest(
    '/v1/snapshots/generate',
    accessToken,
    { scope: 'weekly', target_date: period.endsOn, window_days: 7 },
  );
  if (
    weeklySnapshot.scope !== 'weekly' ||
    weeklySnapshot.period_key !== period.periodKey
  ) {
    throw new Error(
      `Phase 8 weekly snapshot prerequisite is invalid: ${JSON.stringify(weeklySnapshot)}`,
    );
  }

  const reviewPath =
    `weekly_reviews?select=id&user_id=eq.${userId}` +
    `&period_key=eq.${period.periodKey}`;
  await assertRows(
    reviewPath,
    (rows) => rows.length === 0,
    'Phase 8 review missing before read-only GET',
  );
  const missing = await briefingRequest(
    '/v1/weekly-reviews/latest',
    accessToken,
  );
  if (
    missing.contract_version !== 'weekly-review-v1' ||
    missing.period_key !== period.periodKey ||
    missing.starts_on !== period.startsOn ||
    missing.ends_on !== period.endsOn ||
    missing.timezone !== timezone ||
    missing.freshness !== 'missing' ||
    missing.needs_generation !== true ||
    missing.stale_reasons?.length !== 0 ||
    missing.review !== null
  ) {
    throw new Error(
      `Read-only latest weekly review did not report missing truth: ${JSON.stringify(missing)}`,
    );
  }
  await assertRows(
    reviewPath,
    (rows) => rows.length === 0,
    'read-only latest weekly review GET creates no row',
  );

  await page.goto(appRoute('/weekly-review'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'No weekly review yet');
  const generateResponsePromise = waitForAiPost(
    page,
    '/v1/weekly-reviews/generate',
    'deliberate weekly review generation',
  );
  await clickByText(page, 'Create weekly review');
  const generateResponse = await generateResponsePromise;
  assertJsonPayload(
    generateResponse.request(),
    { period_key: period.periodKey, force: false },
    'deliberate weekly review generation payload',
  );
  const generated = await generateResponse.json();
  await expectText(page, 'Up to date');
  const review = generated.review;
  const manualProposal = review?.proposals?.find(
    (proposal) =>
      proposal.target_id === manualHabitId &&
      proposal.operation === 'shrink',
  );
  const setupProposal = review?.proposals?.find(
    (proposal) => proposal.target_id === setupHabitId,
  );
  if (
    generated.freshness !== 'current' ||
    generated.needs_generation !== false ||
    !['partial', 'sufficient'].includes(review?.data_quality) ||
    !isUuid(review?.id) ||
    !Array.isArray(review?.proposals) ||
    review.proposals.length > 2 ||
    review?.facts?.tasks?.completed !== 1 ||
    review?.facts?.tasks?.carried !== 1 ||
    review?.facts?.tasks?.overdue_carried !== 1 ||
    review?.facts?.tasks?.goal_linked_completed !== 1 ||
    review?.facts?.habits?.scheduled_opportunities !== 8 ||
    review?.facts?.habits?.completed !== 4 ||
    review?.facts?.habits?.skipped !== 0 ||
    review?.facts?.habits?.missed !== 2 ||
    review?.facts?.habits?.recovery_open !== 2 ||
    review?.facts?.habits?.unknown !== 0 ||
    review?.facts?.focus?.completed_sessions !== 1 ||
    review?.facts?.focus?.actual_minutes !== 25 ||
    review?.facts?.recovery?.observed_days !== 7 ||
    review?.facts?.recovery?.recovery_days !== 1 ||
    review?.facts?.feedback?.total !== 2 ||
    review?.facts?.feedback?.too_much !== 2 ||
    review?.provenance?.engine !== 'deterministic' ||
    review?.provenance?.contract_version !== 'weekly-review-v1' ||
    review?.provenance?.source_snapshot_id !== weeklySnapshot.snapshot_id ||
    review?.provenance?.baseline !== 'none' ||
    review?.provenance?.llm_used !== false ||
    !/^[0-9a-f]{64}$/.test(
      review?.provenance?.source_fingerprint ?? '',
    ) ||
    manualProposal?.application_mode !== 'direct_habit' ||
    manualProposal?.ownership !== 'manual' ||
    Date.parse(manualProposal?.expected_updated_at) !==
      Date.parse(stableHabitUpdatedAt) ||
    manualProposal?.change?.before?.cadence?.kind !== 'weekly_target' ||
    manualProposal?.change?.before?.cadence?.weekly_target !== 4 ||
    manualProposal?.change?.after?.cadence?.weekly_target !== 3 ||
    setupProposal?.application_mode !== 'settings_setup' ||
    setupProposal?.ownership !== 'setup'
  ) {
    throw new Error(
      `Generated Phase 8 weekly review violates its exact contract: ${JSON.stringify(generated)}`,
    );
  }

  const persistedRows = await fetchRows(
    `weekly_reviews?select=id,period_key,week_start,week_end,timezone,data_quality,narrative,facts,proposals,evidence_refs,provenance,source_fingerprint,generated_at,updated_at&user_id=eq.${userId}&period_key=eq.${period.periodKey}`,
    'persisted Phase 8 weekly review',
  );
  if (
    persistedRows.length !== 1 ||
    persistedRows[0].id !== review.id ||
    persistedRows[0].week_start !== period.startsOn ||
    persistedRows[0].week_end !== period.endsOn ||
    persistedRows[0].timezone !== timezone ||
    persistedRows[0].source_fingerprint !==
      review.provenance.source_fingerprint ||
    stableJson(persistedRows[0].facts) !== stableJson(review.facts) ||
    stableJson(persistedRows[0].proposals) !==
      stableJson(review.proposals) ||
    stableJson(persistedRows[0].evidence_refs) !==
      stableJson(review.evidence_refs) ||
    stableJson(persistedRows[0].provenance) !==
      stableJson(review.provenance)
  ) {
    throw new Error(
      `Persisted Phase 8 weekly review does not match its response: ${JSON.stringify(persistedRows)}`,
    );
  }
  await assertWeeklyReviewDatabaseConstraints({
    userId,
    period,
    review,
    manualProposal,
  });

  const repeated = await briefingRequest(
    `/v1/weekly-reviews/${period.periodKey}`,
    accessToken,
  );
  if (
    repeated.freshness !== 'current' ||
    repeated.review?.id !== review.id ||
    repeated.review?.generated_at !== review.generated_at ||
    repeated.review?.updated_at !== review.updated_at
  ) {
    throw new Error(
      `Idempotent weekly review GET changed the row: ${JSON.stringify(repeated)}`,
    );
  }

  await assertWeeklyReviewRls({
    ownerAccessToken: accessToken,
    userId,
    reviewId: review.id,
    periodKey: period.periodKey,
    period,
    review,
    habitId: manualHabitId,
    expectedHabitTarget: 4,
  });

  const setupBefore = await fetchRows(
    `habits?select=id,title,frequency,target,active,metadata,updated_at&id=eq.${setupHabitId}`,
    'Setup-owned habit before weekly review UI',
  );
  await page.goto(appRoute('/weekly-review'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Weekly review');
  await expectText(page, manualHabitTitle);
  await expectText(page, setupHabitTitle);

  await clickByText(page, 'Open Setup (no auto-apply)');
  await page.waitForURL('**/#/onboarding?edit=1');
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Review your setup');
  await assertRows(
    `habits?select=id,title,frequency,target,active,metadata,updated_at&id=eq.${setupHabitId}`,
    (rows) => stableJson(rows) === stableJson(setupBefore),
    'weekly review Setup navigation performs no generic habit write',
  );
  await page.goto(appRoute('/weekly-review'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, manualHabitTitle);

  await clickByText(page, 'Apply change');
  await expectText(page, 'Apply this habit change?');
  await clickByText(page, 'Keep current');
  await assertRows(
    `habits?select=id,target,updated_at&id=eq.${manualHabitId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].target === 4 &&
      Date.parse(rows[0].updated_at) === Date.parse(stableHabitUpdatedAt),
    'cancelled weekly proposal performs no habit write',
  );

  let lostWeeklyHabitPatchCount = 0;
  const loseWeeklyHabitPatchResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'PATCH' || lostWeeklyHabitPatchCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Weekly habit response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostWeeklyHabitPatchCount += 1;
    await route.abort('failed');
  };
  await page.route('**/rest/v1/habits**', loseWeeklyHabitPatchResponse);
  await clickByText(page, 'Apply change');
  await expectText(page, 'Apply this habit change?');
  await clickByText(page, 'Apply change', { match: 'last' });
  await expectText(page, 'Habit change saved.');
  await waitForRows(
    `habits?select=id,title,frequency,target,active,metadata,updated_at&id=eq.${manualHabitId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === manualHabitTitle &&
      rows[0].frequency === 'weekly' &&
      rows[0].target === 3 &&
      rows[0].active === true &&
      rows[0].metadata?.source === 'flutter-habit-management-v1' &&
      rows[0].metadata?.contract_version === 'habit-v1' &&
      rows[0].metadata?.cadence === 'weekly_target' &&
      rows[0].metadata?.lifecycle === 'active' &&
      Date.parse(rows[0].updated_at) > Date.parse(stableHabitUpdatedAt),
    'confirmed weekly proposal applies one exact manual Habit V1 shrink',
  );
  await page.unroute('**/rest/v1/habits**', loseWeeklyHabitPatchResponse);
  if (lostWeeklyHabitPatchCount !== 1) {
    throw new Error(
      'Weekly habit response-loss path was not exercised exactly once.',
    );
  }
  await assertRows(
    `habit_logs?select=habit_id,entry_date,status,value&habit_id=eq.${manualHabitId}&order=entry_date.asc`,
    (rows) =>
      rows.length === 2 &&
      rows.every((row) => row.status === 'completed' && row.value === 1),
    'weekly habit adaptation preserves historical outcomes',
  );
  await assertRows(
    `habits?select=id,title,frequency,target,active,metadata,updated_at&id=eq.${setupHabitId}`,
    (rows) => stableJson(rows) === stableJson(setupBefore),
    'confirmed manual weekly proposal preserves Setup-owned definition',
  );

  const stale = await briefingRequest(
    `/v1/weekly-reviews/${period.periodKey}`,
    accessToken,
  );
  if (
    stale.freshness !== 'stale' ||
    stale.needs_generation !== true ||
    stale.review?.id !== review.id ||
    !stale.stale_reasons?.includes('source_facts_changed') ||
    stale.review?.updated_at !== review.updated_at
  ) {
    throw new Error(
      `Applied weekly proposal did not make the old review stale: ${JSON.stringify(stale)}`,
    );
  }
  await page.goto(appRoute('/weekly-review'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Weekly review');
  await expectText(page, 'Needs update');
  const staleApplyButtons = page.getByRole('button', {
    name: 'Apply change',
    exact: true,
  });
  if ((await staleApplyButtons.count()) > 0) {
    for (let index = 0; index < (await staleApplyButtons.count()); index++) {
      if (await staleApplyButtons.nth(index).isEnabled()) {
        throw new Error('A stale weekly proposal remained executable.');
      }
    }
  }

  const refreshResponsePromise = waitForAiPost(
    page,
    '/v1/weekly-reviews/generate',
    'deliberate weekly review refresh',
  );
  await clickByText(page, 'Update weekly review');
  const refreshResponse = await refreshResponsePromise;
  assertJsonPayload(
    refreshResponse.request(),
    { period_key: period.periodKey, force: true },
    'deliberate weekly review refresh payload',
  );
  const refreshed = await refreshResponse.json();
  if (
    refreshed.freshness !== 'current' ||
    refreshed.review?.id !== review.id ||
    refreshed.review?.provenance?.source_fingerprint ===
      review.provenance.source_fingerprint ||
    Date.parse(refreshed.review?.updated_at) <= Date.parse(review.updated_at)
  ) {
    throw new Error(
      `Weekly review refresh did not reuse its identity with new facts: ${JSON.stringify(refreshed)}`,
    );
  }

  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
}

async function assertDeadlinePlanner(page, userId) {
  const accessToken = await signInAccessToken('Deadline Planner V1');
  const localToday = isoDateInTimeZone(
    new Date().toISOString(),
    'Europe/Berlin',
  );
  const planId = crypto.randomUUID();
  const title = `E2E statistics exam ${runId}`;
  const deadlineDate = addUtcDays(localToday, 12);
  const deadlineAt = `${deadlineDate}T12:00:00Z`;
  const initialTaskRows = await fetchRows(
    `tasks?select=id&user_id=eq.${userId}`,
    'Deadline Planner task baseline',
  );
  const scheduleBefore = await calendarScheduleSnapshot(userId);

  const initialWorkloadResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/workload',
    accessToken,
  );
  assertDeadlinePlanApiStatus(
    initialWorkloadResult,
    200,
    'initial preparation workload',
  );
  assertPreparationWorkload(initialWorkloadResult.json, {
    budget: null,
    context: 'initial preparation workload',
  });

  await page.goto(appRoute('/settings'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await scrollUntilTextInViewport(page, 'Daily preparation budget', {
    maxSteps: 12,
  });
  await clickByText(page, 'Daily preparation budget');
  await expectText(page, 'This is a transparent rule, not an AI estimate.');
  await fillByLabelOrPlaceholder(
    page,
    'Total preparation minutes per day',
    '120',
    0,
  );
  const budgetSavePromise = page.waitForResponse(
    (candidate) =>
      candidate.url() ===
        `${aiServiceBaseUrl}/v1/account/preparation-budget` &&
      candidate.request().method() === 'PATCH',
    { timeout: 45000 },
  );
  await clickByText(page, 'Save budget');
  const budgetSaveResponse = await budgetSavePromise;
  if (!budgetSaveResponse.ok()) {
    throw new Error(
      `Preparation budget save failed: ${budgetSaveResponse.status()} ${await budgetSaveResponse.text()}`,
    );
  }
  const budgetSaveBody = budgetSaveResponse.request().postDataJSON();
  const budgetSaveResult = await budgetSaveResponse.json();
  if (
    stableJson(budgetSaveBody) !==
      stableJson({ daily_preparation_budget_minutes: 120 }) ||
    stableJson(budgetSaveResult) !==
      stableJson({ daily_preparation_budget_minutes: 120 })
  ) {
    throw new Error(
      `Preparation budget transport was not exact: ${stableJson({ budgetSaveBody, budgetSaveResult })}`,
    );
  }
  await expectText(
    page,
    '2h total per day across confirmed preparation plans.',
  );
  await assertRows(
    `profiles?select=id,daily_preparation_budget_minutes&id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].daily_preparation_budget_minutes === 120,
    'saved account-wide preparation budget',
  );
  const directBudgetWrite = await authenticatedRestRequest(
    `profiles?id=eq.${userId}`,
    accessToken,
    {
      method: 'PATCH',
      body: { daily_preparation_budget_minutes: 480 },
    },
  );
  if (directBudgetWrite.response.ok) {
    throw new Error(
      `Authenticated direct preparation-budget write was accepted: ${directBudgetWrite.text}`,
    );
  }
  const savedWorkloadResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/workload',
    accessToken,
  );
  assertDeadlinePlanApiStatus(
    savedWorkloadResult,
    200,
    'saved preparation workload',
  );
  assertPreparationWorkload(savedWorkloadResult.json, {
    budget: 120,
    context: 'saved preparation workload',
  });

  const initial = await deadlinePlanApiRequest(
    '/v1/deadline-plans',
    accessToken,
  );
  assertDeadlinePlanApiStatus(initial, 200, 'initial deadline plan read');
  const initialFeed = assertDeadlinePlanCollection(
    initial.json,
    'initial deadline plan read',
  );
  if (initialFeed.plans.length !== 0) {
    throw new Error(
      `Fresh E2E account unexpectedly has preparation plans: ${initial.text}`,
    );
  }
  await assertRows(
    `deadline_plans?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'read-only initial Deadline Planner GET',
  );

  const proposalRequestId = crypto.randomUUID();
  const proposalBody = {
    request_id: proposalRequestId,
    plan_id: planId,
    base_revision: 0,
    kind: 'exam',
    title,
    deadline_at: deadlineAt,
    estimated_total_minutes: 180,
    credited_prior_minutes: 30,
    preferred_session_minutes: 50,
    max_daily_minutes: 100,
    planning_start_on: localToday,
    buffer_days: 2,
    source_kind: 'manual',
    use_calendar_availability: false,
  };
  for (const [body, description] of [
    [
      Object.fromEntries(
        Object.entries(proposalBody).filter(
          ([key]) => key !== 'estimated_total_minutes',
        ),
      ),
      'proposal without an explicit user estimate',
    ],
    [
      {
        ...proposalBody,
        request_id: crypto.randomUUID(),
        credited_prior_minutes: proposalBody.estimated_total_minutes,
      },
      'proposal whose prior credit consumes the estimate',
    ],
    [
      {
        ...proposalBody,
        request_id: crypto.randomUUID(),
        user_id: userId,
      },
      'proposal with a request-provided owner',
    ],
    [
      {
        ...proposalBody,
        request_id: crypto.randomUUID(),
        deadline_at: `${addUtcDays(localToday, 367)}T12:00:00Z`,
      },
      'proposal beyond the 366-day horizon',
    ],
  ]) {
    const rejected = await deadlinePlanApiRequest(
      '/v1/deadline-plans/proposals',
      accessToken,
      { method: 'POST', body },
    );
    assertDeadlinePlanApiStatus(rejected, 422, description);
  }
  await assertRows(
    `deadline_plans?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'invalid Deadline Planner requests create no plan',
  );

  const cancelledDraftPlanId = crypto.randomUUID();
  const cancelledDraftProposalRequestId = crypto.randomUUID();
  const cancelledDraftBody = {
    ...proposalBody,
    request_id: cancelledDraftProposalRequestId,
    plan_id: cancelledDraftPlanId,
    title: `E2E disposable preparation draft ${runId}`,
    estimated_total_minutes: 60,
    credited_prior_minutes: 0,
    preferred_session_minutes: 30,
    max_daily_minutes: 60,
    buffer_days: 1,
  };
  const disposableDraftResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: cancelledDraftBody },
  );
  assertDeadlinePlanApiStatus(
    disposableDraftResult,
    200,
    'disposable deadline draft proposal',
  );
  const disposableDraft = assertDeadlinePlanEnvelope(
    disposableDraftResult.json,
    'disposable deadline draft proposal',
  );
  const disposableDraftBlockCount =
    disposableDraft.pending_revision?.blocks.length;
  if (
    disposableDraft.plan.status !== 'draft' ||
    disposableDraft.plan.current_revision !== 0 ||
    disposableDraft.plan.latest_revision !== 1 ||
    Object.hasOwn(disposableDraft.plan, 'managed_task_id') ||
    disposableDraft.pending_revision?.revision !== 1 ||
    !Number.isInteger(disposableDraftBlockCount) ||
    disposableDraftBlockCount < 1
  ) {
    throw new Error(
      `Disposable Deadline Planner draft is invalid: ${disposableDraftResult.text}`,
    );
  }
  const cancelledDraftRequestId = crypto.randomUUID();
  const cancelledDraftRequest = {
    request_id: cancelledDraftRequestId,
    expected_revision: 1,
  };
  const cancelledDraftResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${cancelledDraftPlanId}/cancel`,
    accessToken,
    { method: 'POST', body: cancelledDraftRequest },
  );
  assertDeadlinePlanApiStatus(
    cancelledDraftResult,
    200,
    'explicit draft deadline cancellation',
  );
  const cancelledDraft = assertDeadlinePlanEnvelope(
    cancelledDraftResult.json,
    'explicit draft deadline cancellation',
  );
  if (
    cancelledDraft.plan.status !== 'cancelled' ||
    cancelledDraft.plan.current_revision !== 0 ||
    cancelledDraft.plan.latest_revision !== 1 ||
    !isIsoTimestamp(cancelledDraft.plan.cancelled_at) ||
    Object.hasOwn(cancelledDraft.plan, 'managed_task_id') ||
    Object.hasOwn(cancelledDraft, 'active_revision') ||
    Object.hasOwn(cancelledDraft, 'pending_revision') ||
    cancelledDraft.progress.estimated_total_minutes !== 60 ||
    cancelledDraft.progress.credited_prior_minutes !== 0 ||
    cancelledDraft.progress.tracked_focus_minutes !== 0
  ) {
    throw new Error(
      `Draft cancellation fabricated activation or a managed task: ${cancelledDraftResult.text}`,
    );
  }
  const cancelledDraftReplay = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${cancelledDraftPlanId}/cancel`,
    accessToken,
    { method: 'POST', body: cancelledDraftRequest },
  );
  assertDeadlinePlanApiStatus(
    cancelledDraftReplay,
    200,
    'draft deadline cancellation replay',
  );
  if (
    stableJson(cancelledDraftReplay.json) !==
    stableJson(cancelledDraftResult.json)
  ) {
    throw new Error(
      `Draft cancellation replay changed terminal state: ${cancelledDraftReplay.text}`,
    );
  }
  await assertRows(
    `deadline_plans?select=id,status,current_revision,latest_revision,managed_task_id,first_activated_at,cancelled_at&user_id=eq.${userId}&id=eq.${cancelledDraftPlanId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'cancelled' &&
      rows[0].current_revision === 0 &&
      rows[0].latest_revision === 1 &&
      rows[0].managed_task_id === null &&
      rows[0].first_activated_at === null &&
      rows[0].cancelled_at !== null,
    'cancelled draft Deadline Planner identity',
  );
  await assertRows(
    `deadline_plan_revisions?select=revision,state,activated_at,superseded_at&user_id=eq.${userId}&plan_id=eq.${cancelledDraftPlanId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].revision === 1 &&
      rows[0].state === 'superseded' &&
      rows[0].activated_at === null &&
      rows[0].superseded_at !== null,
    'cancelled draft supersedes its pending revision',
  );
  await assertRows(
    `deadline_plan_blocks?select=id,reservation_state&user_id=eq.${userId}&plan_id=eq.${cancelledDraftPlanId}`,
    (rows) =>
      rows.length === disposableDraftBlockCount &&
      rows.every((row) => row.reservation_state === 'superseded'),
    'cancelled draft releases proposed reservations',
  );
  await assertRows(
    `tasks?select=id&user_id=eq.${userId}&id=eq.${cancelledDraftPlanId}`,
    (rows) => rows.length === 0,
    'cancelled draft creates no managed task',
  );

  const proposed = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: proposalBody },
  );
  assertDeadlinePlanApiStatus(proposed, 200, 'manual deadline proposal');
  const draft = assertDeadlinePlanEnvelope(
    proposed.json,
    'manual deadline proposal',
  );
  if (
    draft.plan.id !== planId ||
    draft.plan.status !== 'draft' ||
    draft.plan.kind !== 'exam' ||
    draft.plan.title !== title ||
    Object.hasOwn(draft.plan, 'managed_task_id') ||
    draft.plan.original_estimated_total_minutes !== 180 ||
    draft.plan.original_credited_prior_minutes !== 30 ||
    draft.plan.current_revision !== 0 ||
    draft.plan.latest_revision !== 1 ||
    Object.hasOwn(draft, 'active_revision') ||
    draft.pending_revision?.revision !== 1 ||
    draft.pending_revision?.base_revision !== 0 ||
    draft.pending_revision?.state !== 'proposed' ||
    draft.pending_revision?.tracked_focus_minutes_at_proposal !== 0 ||
    draft.pending_revision?.remaining_minutes_at_proposal !== 150 ||
    draft.pending_revision?.planned_minutes +
        draft.pending_revision?.unscheduled_minutes !==
      150 ||
    draft.pending_revision?.blocks.length < 1 ||
    draft.progress.estimated_total_minutes !== 180 ||
    draft.progress.credited_prior_minutes !== 30 ||
    draft.progress.tracked_focus_minutes !== 0 ||
    draft.progress.accounted_minutes !== 30 ||
    draft.progress.remaining_minutes !== 150 ||
    draft.progress.completion_suggested !== false
  ) {
    throw new Error(
      `Manual Deadline Planner proposal is not a staged explicit estimate: ${proposed.text}`,
    );
  }
  const proposedBlockIds = draft.pending_revision.blocks.map(
    (block) => block.id,
  );

  const proposalReplay = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: proposalBody },
  );
  assertDeadlinePlanApiStatus(
    proposalReplay,
    200,
    'exact deadline proposal replay',
  );
  assertDeadlinePlanEnvelope(
    proposalReplay.json,
    'exact deadline proposal replay',
  );
  if (stableJson(proposalReplay.json) !== stableJson(proposed.json)) {
    throw new Error(
      `Exact Deadline Planner proposal replay changed persisted output: ${proposalReplay.text}`,
    );
  }
  const proposalConflict = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: { ...proposalBody, title: `${title} changed` },
    },
  );
  assertDeadlinePlanApiStatus(
    proposalConflict,
    409,
    'deadline proposal request-id reinterpretation',
  );
  const staleInitialBase = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: { ...proposalBody, request_id: crypto.randomUUID() },
    },
  );
  assertDeadlinePlanApiStatus(
    staleInitialBase,
    409,
    'stale initial deadline base revision',
  );
  await assertRows(
    `deadline_plans?select=id,user_id,status,kind,title,managed_task_id,original_estimated_total_minutes,original_credited_prior_minutes,current_revision,latest_revision&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'draft' &&
      rows[0].managed_task_id === null &&
      rows[0].original_estimated_total_minutes === 180 &&
      rows[0].original_credited_prior_minutes === 30 &&
      rows[0].current_revision === 0 &&
      rows[0].latest_revision === 1,
    'persisted staged Deadline Planner identity',
  );
  await assertRows(
    `deadline_plan_revisions?select=plan_id,revision,base_revision,state,estimated_total_minutes,credited_prior_minutes,tracked_focus_minutes_at_proposal,remaining_minutes_at_proposal,planned_minutes,unscheduled_minutes,activated_at,superseded_at&user_id=eq.${userId}&plan_id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].revision === 1 &&
      rows[0].base_revision === 0 &&
      rows[0].state === 'proposed' &&
      rows[0].planned_minutes + rows[0].unscheduled_minutes === 150 &&
      rows[0].activated_at === null &&
      rows[0].superseded_at === null,
    'immutable proposed Deadline Planner revision',
  );
  await assertRows(
    `deadline_plan_blocks?select=id,revision,sequence,reservation_state,planned_minutes&user_id=eq.${userId}&plan_id=eq.${planId}&order=sequence.asc`,
    (rows) =>
      rows.length === proposedBlockIds.length &&
      rows.every(
        (row, index) =>
          row.id === proposedBlockIds[index] &&
          row.revision === 1 &&
          row.sequence === index + 1 &&
          row.reservation_state === 'proposed',
      ) &&
      rows.reduce((sum, row) => sum + row.planned_minutes, 0) ===
        draft.pending_revision.planned_minutes,
    'deterministic proposed Deadline Planner blocks',
  );
  await assertRows(
    `tasks?select=id&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) => rows.length === 0,
    'proposal creates no managed task before confirmation',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'manual Deadline Planner proposal',
  );

  const confirmRequestId = crypto.randomUUID();
  const confirmBody = {
    request_id: confirmRequestId,
    expected_revision: 1,
  };
  const crossOperationConfirm = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: proposalRequestId, expected_revision: 1 },
    },
  );
  assertDeadlinePlanApiStatus(
    crossOperationConfirm,
    409,
    'deadline request id reused across proposal and confirmation',
  );
  await assertRows(
    `tasks?select=id&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) => rows.length === 0,
    'cross-operation deadline conflict remains staged',
  );
  const confirmedResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    { method: 'POST', body: confirmBody },
  );
  assertDeadlinePlanApiStatus(
    confirmedResult,
    200,
    'first deadline confirmation',
  );
  const confirmed = assertDeadlinePlanEnvelope(
    confirmedResult.json,
    'first deadline confirmation',
  );
  if (
    confirmed.plan.status !== 'active' ||
    confirmed.plan.managed_task_id !== planId ||
    confirmed.plan.current_revision !== 1 ||
    confirmed.plan.latest_revision !== 1 ||
    confirmed.active_revision?.revision !== 1 ||
    confirmed.active_revision?.state !== 'active' ||
    !isIsoTimestamp(confirmed.active_revision?.activated_at) ||
    Object.hasOwn(confirmed, 'pending_revision')
  ) {
    throw new Error(
      `First Deadline Planner confirmation is not active: ${confirmedResult.text}`,
    );
  }
  const confirmReplay = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    { method: 'POST', body: confirmBody },
  );
  assertDeadlinePlanApiStatus(confirmReplay, 200, 'deadline confirm replay');
  assertDeadlinePlanEnvelope(confirmReplay.json, 'deadline confirm replay');
  if (stableJson(confirmReplay.json) !== stableJson(confirmedResult.json)) {
    throw new Error(
      `Deadline confirmation replay changed persisted state: ${confirmReplay.text}`,
    );
  }
  const confirmConflict = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { ...confirmBody, expected_revision: 2 },
    },
  );
  assertDeadlinePlanApiStatus(
    confirmConflict,
    409,
    'deadline confirm request-id reinterpretation',
  );

  const managedTasks = await fetchRows(
    `tasks?select=id,user_id,title,status,deadline,estimated_minutes,completed_at,cancelled_at,source,metadata&user_id=eq.${userId}&id=eq.${planId}`,
    'first Deadline Planner managed task',
  );
  const managedTask = managedTasks[0];
  if (
    managedTasks.length !== 1 ||
    managedTask.id !== planId ||
    managedTask.user_id !== userId ||
    managedTask.title !== title ||
    managedTask.status !== 'todo' ||
    !sameInstant(managedTask.deadline, deadlineAt) ||
    managedTask.estimated_minutes !== null ||
    managedTask.completed_at !== null ||
    managedTask.cancelled_at !== null ||
    managedTask.source !== 'deadline-plan-v1' ||
    stableJson(managedTask.metadata) !==
      stableJson({
        contract_version: 'deadline-plan-v1',
        managed_by: 'deadline-planner',
        plan_id: planId,
      })
  ) {
    throw new Error(
      `Deadline Planner managed task projection is invalid: ${JSON.stringify(managedTasks)}`,
    );
  }

  const budgetConflictPlanId = await assertPreparationBudgetConfirmationGuard({
    accessToken,
    userId,
    proposalBody,
  });

  await assertDeadlinePlannerFlutterSurface({
    page,
    accessToken,
    planId,
    title,
    activeRevision: confirmed.active_revision,
  });

  await assertDeadlinePlannerRls({
    ownerAccessToken: accessToken,
    userId,
    planId,
    revision: 1,
    blockId: confirmed.active_revision.blocks[0].id,
    claimedRequestId: proposalRequestId,
    proposalBody,
  });

  const directTaskMutation = await authenticatedRestRequest(
    `tasks?id=eq.${planId}`,
    accessToken,
    { method: 'PATCH', body: { title: 'Authenticated task rewrite' } },
  );
  if (directTaskMutation.response.ok) {
    throw new Error(
      `Generic task authority changed a planner-managed task: ${directTaskMutation.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,title,status,deadline&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === title &&
      rows[0].status === 'todo' &&
      sameInstant(rows[0].deadline, deadlineAt),
    'managed task rejects generic mutation',
  );

  const firstActivation = confirmed.active_revision.activated_at;
  const activeFocusId = crypto.randomUUID();
  const activeStartedAt = new Date(
    Math.max(Date.now(), Date.parse(firstActivation) + 1000),
  ).toISOString();
  const activeFocus = await authenticatedRestRequest(
    'focus_sessions',
    accessToken,
    {
      method: 'POST',
      body: {
        id: activeFocusId,
        user_id: userId,
        task_id: planId,
        habit_id: null,
        status: 'active',
        started_at: activeStartedAt,
        ended_at: null,
        planned_minutes: 25,
        actual_minutes: null,
        label: 'E2E planner focus start',
        metadata: {
          source: 'e2e-deadline-plan',
          entry_date: isoDateInTimeZone(activeStartedAt, 'Europe/Berlin'),
        },
        created_at: activeStartedAt,
        updated_at: activeStartedAt,
      },
    },
  );
  if (
    !activeFocus.response.ok ||
    activeFocus.rows?.length !== 1 ||
    activeFocus.rows[0].id !== activeFocusId ||
    activeFocus.rows[0].task_id !== planId ||
    activeFocus.rows[0].status !== 'active'
  ) {
    throw new Error(
      `Open planner-managed task rejected an owned focus start: ${activeFocus.response.status} ${activeFocus.text}`,
    );
  }
  const activeEndedAt = new Date(
    Date.parse(activeStartedAt) + 60_000,
  ).toISOString();
  const finishedFocus = await authenticatedRestRequest(
    `focus_sessions?id=eq.${activeFocusId}&user_id=eq.${userId}&status=eq.active`,
    accessToken,
    {
      method: 'PATCH',
      body: {
        status: 'completed',
        ended_at: activeEndedAt,
        actual_minutes: 1,
        updated_at: activeEndedAt,
      },
    },
  );
  if (
    !finishedFocus.response.ok ||
    finishedFocus.rows?.length !== 1 ||
    finishedFocus.rows[0].status !== 'completed' ||
    finishedFocus.rows[0].actual_minutes !== 1
  ) {
    throw new Error(
      `Planner-linked focus finish failed: ${finishedFocus.response.status} ${finishedFocus.text}`,
    );
  }
  const completedFocusId = crypto.randomUUID();
  const completedStartedAt = new Date(
    Date.parse(activeEndedAt) + 1000,
  ).toISOString();
  const completedEndedAt = new Date(
    Date.parse(completedStartedAt) + 34 * 60_000,
  ).toISOString();
  const abandonedFocusId = crypto.randomUUID();
  const abandonedStartedAt = new Date(
    Date.parse(completedEndedAt) + 1000,
  ).toISOString();
  const abandonedEndedAt = new Date(
    Date.parse(abandonedStartedAt) + 20 * 60_000,
  ).toISOString();
  const preActivationFocusId = crypto.randomUUID();
  const preActivationStartedAt = new Date(
    Date.parse(firstActivation) - 20 * 60_000,
  ).toISOString();
  const preActivationEndedAt = new Date(
    Date.parse(firstActivation) - 5 * 60_000,
  ).toISOString();
  await insertRows('focus_sessions', [
    {
      id: preActivationFocusId,
      user_id: userId,
      task_id: planId,
      habit_id: null,
      status: 'completed',
      started_at: preActivationStartedAt,
      ended_at: preActivationEndedAt,
      planned_minutes: 15,
      actual_minutes: 15,
      label: 'E2E planner pre-activation history',
      metadata: {
        source: 'e2e-deadline-plan',
        entry_date: isoDateInTimeZone(
          preActivationStartedAt,
          'Europe/Berlin',
        ),
      },
      created_at: preActivationStartedAt,
      updated_at: preActivationEndedAt,
    },
    {
      id: completedFocusId,
      user_id: userId,
      task_id: planId,
      habit_id: null,
      status: 'completed',
      started_at: completedStartedAt,
      ended_at: completedEndedAt,
      planned_minutes: 35,
      actual_minutes: 34,
      label: 'E2E planner measured progress',
      metadata: {
        source: 'e2e-deadline-plan',
        entry_date: isoDateInTimeZone(completedStartedAt, 'Europe/Berlin'),
      },
      created_at: completedStartedAt,
      updated_at: completedEndedAt,
    },
    {
      id: abandonedFocusId,
      user_id: userId,
      task_id: planId,
      habit_id: null,
      status: 'abandoned',
      started_at: abandonedStartedAt,
      ended_at: abandonedEndedAt,
      planned_minutes: 20,
      actual_minutes: 20,
      label: 'E2E planner abandoned time',
      metadata: {
        source: 'e2e-deadline-plan',
        entry_date: isoDateInTimeZone(abandonedStartedAt, 'Europe/Berlin'),
      },
      created_at: abandonedStartedAt,
      updated_at: abandonedEndedAt,
    },
  ]);

  const progressedResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}`,
    accessToken,
  );
  assertDeadlinePlanApiStatus(
    progressedResult,
    200,
    'deadline progress after linked focus',
  );
  const progressed = assertDeadlinePlanEnvelope(
    progressedResult.json,
    'deadline progress after linked focus',
  );
  const firstProgressedBlock = progressed.active_revision.blocks[0];
  const expectedFirstProgressedState =
    firstProgressedBlock.credited_tracked_minutes ===
    firstProgressedBlock.planned_minutes
      ? 'completed'
      : 'partial';
  if (
    progressed.plan.status !== 'active' ||
    progressed.progress.tracked_focus_minutes !== 35 ||
    progressed.progress.accounted_minutes !== 65 ||
    progressed.progress.remaining_minutes !== 115 ||
    progressed.progress.completion_suggested !== false ||
    progressed.active_revision.blocks.reduce(
      (sum, block) => sum + block.credited_tracked_minutes,
      0,
    ) !== 35 ||
    firstProgressedBlock.credited_tracked_minutes <= 0 ||
    firstProgressedBlock.state !== expectedFirstProgressedState
  ) {
    throw new Error(
      `Pre-activation/abandoned focus accounting changed plan authority: ${progressedResult.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,status,completed_at,cancelled_at&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'todo' &&
      rows[0].completed_at === null &&
      rows[0].cancelled_at === null,
    'linked focus never completes the managed task',
  );

  const secondProposalRequestId = crypto.randomUUID();
  const secondTitle = `E2E statistics exam adjusted ${runId}`;
  const secondDeadlineAt = `${addUtcDays(localToday, 14)}T12:00:00Z`;
  const secondProposalBody = {
    ...proposalBody,
    request_id: secondProposalRequestId,
    base_revision: 1,
    title: secondTitle,
    deadline_at: secondDeadlineAt,
    estimated_total_minutes: 240,
    credited_prior_minutes: 40,
    preferred_session_minutes: 45,
    max_daily_minutes: 90,
  };
  const secondProposalResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: secondProposalBody },
  );
  assertDeadlinePlanApiStatus(
    secondProposalResult,
    200,
    'active deadline replan proposal',
  );
  const stagedReplan = assertDeadlinePlanEnvelope(
    secondProposalResult.json,
    'active deadline replan proposal',
  );
  if (
    stagedReplan.plan.status !== 'active' ||
    stagedReplan.plan.current_revision !== 1 ||
    stagedReplan.plan.latest_revision !== 2 ||
    stagedReplan.active_revision?.revision !== 1 ||
    stagedReplan.pending_revision?.revision !== 2 ||
    stagedReplan.pending_revision?.base_revision !== 1 ||
    stagedReplan.pending_revision?.title !== secondTitle ||
    stagedReplan.pending_revision?.tracked_focus_minutes_at_proposal !== 35 ||
    stagedReplan.pending_revision?.remaining_minutes_at_proposal !== 165 ||
    stagedReplan.progress.estimated_total_minutes !== 180 ||
    stagedReplan.progress.tracked_focus_minutes !== 35
  ) {
    throw new Error(
      `Replan replaced active revision before confirmation: ${secondProposalResult.text}`,
    );
  }
  const secondProposalReplay = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: secondProposalBody },
  );
  assertDeadlinePlanApiStatus(
    secondProposalReplay,
    200,
    'exact active replan replay',
  );
  if (
    stableJson(secondProposalReplay.json) !==
    stableJson(secondProposalResult.json)
  ) {
    throw new Error(
      `Exact active replan replay changed staged state: ${secondProposalReplay.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,title,deadline,status&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === title &&
      sameInstant(rows[0].deadline, deadlineAt) &&
      rows[0].status === 'todo',
    'pending revision leaves managed task on active projection',
  );

  const currentInsteadOfLatest = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: { ...secondProposalBody, request_id: crypto.randomUUID() },
    },
  );
  assertDeadlinePlanApiStatus(
    currentInsteadOfLatest,
    409,
    'current revision cannot replace latest pending revision',
  );

  const thirdProposalRequestId = crypto.randomUUID();
  const finalTitle = `E2E statistics exam final ${runId}`;
  const finalDeadlineAt = `${addUtcDays(localToday, 16)}T12:00:00Z`;
  const thirdProposalBody = {
    ...secondProposalBody,
    request_id: thirdProposalRequestId,
    base_revision: 2,
    title: finalTitle,
    deadline_at: finalDeadlineAt,
    estimated_total_minutes: 210,
    credited_prior_minutes: 35,
  };
  const thirdProposalResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: thirdProposalBody },
  );
  assertDeadlinePlanApiStatus(
    thirdProposalResult,
    200,
    'replacement pending deadline proposal',
  );
  const replacementPending = assertDeadlinePlanEnvelope(
    thirdProposalResult.json,
    'replacement pending deadline proposal',
  );
  if (
    replacementPending.plan.current_revision !== 1 ||
    replacementPending.plan.latest_revision !== 3 ||
    replacementPending.active_revision?.revision !== 1 ||
    replacementPending.pending_revision?.revision !== 3 ||
    replacementPending.pending_revision?.base_revision !== 2 ||
    replacementPending.pending_revision?.tracked_focus_minutes_at_proposal !==
      35 ||
    replacementPending.pending_revision?.remaining_minutes_at_proposal !== 140
  ) {
    throw new Error(
      `Latest-based replacement proposal is invalid: ${thirdProposalResult.text}`,
    );
  }
  await assertRows(
    `deadline_plan_revisions?select=revision,state,activated_at,superseded_at&user_id=eq.${userId}&plan_id=eq.${planId}&order=revision.asc`,
    (rows) =>
      rows.length === 3 &&
      rows[0].state === 'active' &&
      rows[0].activated_at !== null &&
      rows[0].superseded_at === null &&
      rows[1].state === 'superseded' &&
      rows[1].activated_at === null &&
      rows[1].superseded_at !== null &&
      rows[2].state === 'proposed' &&
      rows[2].activated_at === null &&
      rows[2].superseded_at === null,
    'pending replacement preserves active and superseded provenance',
  );
  await assertRows(
    `deadline_plan_blocks?select=revision,reservation_state&user_id=eq.${userId}&plan_id=eq.${planId}&order=revision.asc,sequence.asc`,
    (rows) =>
      rows.length ===
        replacementPending.active_revision.blocks.length +
          stagedReplan.pending_revision.blocks.length +
          replacementPending.pending_revision.blocks.length &&
      rows.every((row) =>
        row.revision === 1
          ? row.reservation_state === 'active'
          : row.revision === 2
            ? row.reservation_state === 'superseded'
            : row.revision === 3 &&
              row.reservation_state === 'proposed',
      ),
    'pending replacement keeps only active reservations committed',
  );

  const finalConfirmRequestId = crypto.randomUUID();
  const finalConfirmBody = {
    request_id: finalConfirmRequestId,
    expected_revision: 3,
  };
  const finalConfirmResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    { method: 'POST', body: finalConfirmBody },
  );
  assertDeadlinePlanApiStatus(
    finalConfirmResult,
    200,
    'replacement deadline confirmation',
  );
  const finalConfirmed = assertDeadlinePlanEnvelope(
    finalConfirmResult.json,
    'replacement deadline confirmation',
  );
  if (
    finalConfirmed.plan.status !== 'active' ||
    finalConfirmed.plan.managed_task_id !== planId ||
    finalConfirmed.plan.original_estimated_total_minutes !== 180 ||
    finalConfirmed.plan.original_credited_prior_minutes !== 30 ||
    finalConfirmed.plan.current_revision !== 3 ||
    finalConfirmed.plan.latest_revision !== 3 ||
    finalConfirmed.active_revision?.revision !== 3 ||
    finalConfirmed.active_revision?.title !== finalTitle ||
    Object.hasOwn(finalConfirmed, 'pending_revision') ||
    finalConfirmed.progress.estimated_total_minutes !== 210 ||
    finalConfirmed.progress.credited_prior_minutes !== 35 ||
    finalConfirmed.progress.tracked_focus_minutes !== 35 ||
    finalConfirmed.progress.remaining_minutes !== 140
  ) {
    throw new Error(
      `Confirmed replacement revision is invalid: ${finalConfirmResult.text}`,
    );
  }
  await assertRows(
    `deadline_plan_revisions?select=revision,state,activated_at,superseded_at&user_id=eq.${userId}&plan_id=eq.${planId}&order=revision.asc`,
    (rows) =>
      rows.length === 3 &&
      rows[0].state === 'superseded' &&
      rows[0].activated_at !== null &&
      rows[0].superseded_at !== null &&
      rows[1].state === 'superseded' &&
      rows[1].activated_at === null &&
      rows[1].superseded_at !== null &&
      rows[2].state === 'active' &&
      rows[2].activated_at !== null &&
      rows[2].superseded_at === null,
    'confirmed replacement keeps activation provenance',
  );
  await assertRows(
    `deadline_plan_blocks?select=revision,reservation_state&user_id=eq.${userId}&plan_id=eq.${planId}&order=revision.asc,sequence.asc`,
    (rows) =>
      rows.length ===
        replacementPending.active_revision.blocks.length +
          stagedReplan.pending_revision.blocks.length +
          replacementPending.pending_revision.blocks.length &&
      rows.every((row) =>
        row.revision === 3
          ? row.reservation_state === 'active'
          : [1, 2].includes(row.revision) &&
            row.reservation_state === 'superseded',
      ),
    'replacement confirmation switches reservation authority atomically',
  );
  await assertRows(
    `tasks?select=id,title,deadline,status,estimated_minutes,source,metadata&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === planId &&
      rows[0].title === finalTitle &&
      sameInstant(rows[0].deadline, finalDeadlineAt) &&
      rows[0].status === 'todo' &&
      rows[0].estimated_minutes === null &&
      rows[0].source === 'deadline-plan-v1' &&
      stableJson(rows[0].metadata) ===
        stableJson({
          contract_version: 'deadline-plan-v1',
          managed_by: 'deadline-planner',
          plan_id: planId,
        }),
    'stable managed task after replacement confirmation',
  );

  const completeRequestId = crypto.randomUUID();
  const completeBody = {
    request_id: completeRequestId,
    expected_revision: 3,
  };
  const completedResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/complete`,
    accessToken,
    { method: 'POST', body: completeBody },
  );
  assertDeadlinePlanApiStatus(
    completedResult,
    200,
    'explicit deadline completion',
  );
  const completed = assertDeadlinePlanEnvelope(
    completedResult.json,
    'explicit deadline completion',
  );
  if (
    completed.plan.status !== 'completed' ||
    !isIsoTimestamp(completed.plan.completed_at) ||
    Object.hasOwn(completed.plan, 'cancelled_at') ||
    completed.plan.current_revision !== 3 ||
    completed.plan.latest_revision !== 3 ||
    completed.active_revision?.revision !== 3
  ) {
    throw new Error(
      `Explicit Deadline Planner completion is invalid: ${completedResult.text}`,
    );
  }
  const completeReplay = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/complete`,
    accessToken,
    { method: 'POST', body: completeBody },
  );
  assertDeadlinePlanApiStatus(
    completeReplay,
    200,
    'deadline completion replay',
  );
  if (stableJson(completeReplay.json) !== stableJson(completedResult.json)) {
    throw new Error(
      `Deadline completion replay changed terminal state: ${completeReplay.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,status,completed_at,cancelled_at,title,deadline&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'done' &&
      sameInstant(rows[0].completed_at, completed.plan.completed_at) &&
      rows[0].cancelled_at === null &&
      rows[0].title === finalTitle &&
      sameInstant(rows[0].deadline, finalDeadlineAt),
    'atomic matching plan/task completion',
  );
  await assertRows(
    `deadline_plan_blocks?select=revision,reservation_state&user_id=eq.${userId}&plan_id=eq.${planId}`,
    (rows) =>
      rows.length > 0 &&
      rows.every((row) => row.reservation_state === 'superseded'),
    'explicit completion releases every retained reservation revision',
  );

  const rejectedTerminalFocusId = crypto.randomUUID();
  const rejectedTerminalFocus = await authenticatedRestRequest(
    'focus_sessions',
    accessToken,
    {
      method: 'POST',
      body: {
        id: rejectedTerminalFocusId,
        user_id: userId,
        task_id: planId,
        status: 'active',
        started_at: new Date().toISOString(),
        planned_minutes: 25,
        label: 'Must not start on a terminal plan',
        metadata: {
          source: 'e2e-deadline-plan',
          entry_date: localToday,
        },
      },
    },
  );
  if (rejectedTerminalFocus.response.ok) {
    throw new Error('Terminal planner-managed task accepted a new focus start.');
  }
  await assertRows(
    `focus_sessions?select=id&id=eq.${rejectedTerminalFocusId}`,
    (rows) => rows.length === 0,
    'terminal planner-managed task rejects focus start',
  );

  const requestIds = new Map([
    [proposalRequestId, 'proposal'],
    [confirmRequestId, 'confirm'],
    [secondProposalRequestId, 'proposal'],
    [thirdProposalRequestId, 'proposal'],
    [finalConfirmRequestId, 'confirm'],
    [completeRequestId, 'complete'],
  ]);
  await assertRows(
    `deadline_plan_request_identities?select=request_id,user_id,plan_id,operation&user_id=eq.${userId}&plan_id=eq.${planId}&order=created_at.asc,request_id.asc`,
    (rows) =>
      rows.length === requestIds.size &&
      rows.every(
        (row) =>
          row.user_id === userId &&
          row.plan_id === planId &&
          requestIds.get(row.request_id) === row.operation,
      ),
    'minimal unique Deadline Planner request identities',
  );
  const finalFeedResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans',
    accessToken,
  );
  assertDeadlinePlanApiStatus(finalFeedResult, 200, 'final deadline plan feed');
  const finalFeed = assertDeadlinePlanCollection(
    finalFeedResult.json,
    'final deadline plan feed',
  );
  const finalPlansById = new Map(
    finalFeed.plans.map((detail) => [detail.plan.id, detail]),
  );
  if (
    finalFeed.plans.length !== 3 ||
    finalPlansById.get(planId)?.plan.status !== 'completed' ||
    finalPlansById.get(cancelledDraftPlanId)?.plan.status !== 'cancelled' ||
    finalPlansById.get(cancelledDraftPlanId)?.plan.current_revision !== 0 ||
    finalPlansById.get(budgetConflictPlanId)?.plan.status !== 'cancelled' ||
    finalPlansById.get(budgetConflictPlanId)?.plan.current_revision !== 0
  ) {
    throw new Error(
      `Deadline Planner collection lost terminal plan truth: ${finalFeedResult.text}`,
    );
  }
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'complete Deadline Planner lifecycle',
  );
  const finalTasks = await fetchRows(
    `tasks?select=id&user_id=eq.${userId}`,
    'Deadline Planner final task set',
  );
  if (
    finalTasks.length !== initialTaskRows.length + 1 ||
    !finalTasks.some((row) => row.id === planId)
  ) {
    throw new Error(
      `Deadline Planner did not retain exactly one stable managed task: ${JSON.stringify(finalTasks)}`,
    );
  }
}

async function assertPreparationBudgetConfirmationGuard({
  accessToken,
  userId,
  proposalBody,
}) {
  const planId = crypto.randomUUID();
  const proposal = {
    ...proposalBody,
    request_id: crypto.randomUUID(),
    plan_id: planId,
    kind: 'assignment',
    title: `E2E account capacity preview ${runId}`,
    estimated_total_minutes: 120,
    credited_prior_minutes: 0,
    preferred_session_minutes: 50,
    max_daily_minutes: 100,
  };
  const proposedResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: proposal },
  );
  assertDeadlinePlanApiStatus(
    proposedResult,
    200,
    'account-capacity proposal',
  );
  const proposed = assertDeadlinePlanEnvelope(
    proposedResult.json,
    'account-capacity proposal',
  );
  if (
    proposed.plan.status !== 'draft' ||
    proposed.pending_revision?.blocks.length < 1
  ) {
    throw new Error(
      `Account-capacity proposal has no staged blocks: ${proposedResult.text}`,
    );
  }
  const activeRows = await fetchRows(
    `deadline_plan_blocks?select=local_date,planned_minutes&user_id=eq.${userId}&reservation_state=eq.active`,
    'active preparation capacity baseline',
  );
  const activeByDay = new Map();
  for (const row of activeRows) {
    activeByDay.set(
      row.local_date,
      (activeByDay.get(row.local_date) ?? 0) + row.planned_minutes,
    );
  }
  const candidateByDay = new Map();
  for (const block of proposed.pending_revision.blocks) {
    candidateByDay.set(
      block.local_date,
      (candidateByDay.get(block.local_date) ?? 0) + block.planned_minutes,
    );
  }
  for (const [localDate, candidateMinutes] of candidateByDay) {
    const total = (activeByDay.get(localDate) ?? 0) + candidateMinutes;
    if (total > 120) {
      throw new Error(
        `Proposal exceeded the account-wide daily preparation budget on ${localDate}: ${total}`,
      );
    }
  }

  const ownerFieldRejected = await deadlinePlanApiRequest(
    '/v1/account/preparation-budget',
    accessToken,
    {
      method: 'PATCH',
      body: {
        daily_preparation_budget_minutes: 25,
        user_id: userId,
      },
    },
  );
  assertDeadlinePlanApiStatus(
    ownerFieldRejected,
    422,
    'request-provided preparation-budget owner',
  );
  const lowered = await deadlinePlanApiRequest(
    '/v1/account/preparation-budget',
    accessToken,
    {
      method: 'PATCH',
      body: { daily_preparation_budget_minutes: 25 },
    },
  );
  assertDeadlinePlanApiStatus(lowered, 200, 'lowered preparation budget');
  if (lowered.json?.daily_preparation_budget_minutes !== 25) {
    throw new Error(`Lowered budget result is invalid: ${lowered.text}`);
  }
  const loweredWorkloadResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/workload',
    accessToken,
  );
  assertDeadlinePlanApiStatus(
    loweredWorkloadResult,
    200,
    'lowered preparation workload',
  );
  const loweredWorkload = assertPreparationWorkload(
    loweredWorkloadResult.json,
    { budget: 25, context: 'lowered preparation workload' },
  );
  if (!loweredWorkload.days.some((day) => day.over_budget_minutes > 0)) {
    throw new Error(
      `Lowering the budget hid existing over-budget reservations: ${loweredWorkloadResult.text}`,
    );
  }
  const overloadedDay = loweredWorkload.days.find(
    (day) => day.over_budget_minutes > 0,
  );
  const workloadDetailResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/workload/${overloadedDay.local_date}`,
    accessToken,
  );
  assertDeadlinePlanApiStatus(
    workloadDetailResult,
    200,
    'over-budget preparation workload detail',
  );
  const workloadDetail = assertPreparationWorkloadDetail(
    workloadDetailResult.json,
    {
      budget: 25,
      localDate: overloadedDay.local_date,
      context: 'over-budget preparation workload detail',
    },
  );
  if (
    workloadDetail.reserved_preparation_minutes !==
      overloadedDay.reserved_preparation_minutes ||
    workloadDetail.over_budget_minutes !== overloadedDay.over_budget_minutes ||
    workloadDetail.contributions.length !== overloadedDay.active_plan_count
  ) {
    throw new Error(
      `Preparation workload detail did not explain the seven-day total: ${workloadDetailResult.text}`,
    );
  }

  const confirmResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: crypto.randomUUID(), expected_revision: 1 },
    },
  );
  assertDeadlinePlanApiStatus(
    confirmResult,
    409,
    'budget-changed confirmation',
  );
  if (
    confirmResult.json?.detail !==
    'Daily preparation budget is exceeded. Create a fresh preview.'
  ) {
    throw new Error(
      `Budget confirmation returned unsafe guidance: ${confirmResult.text}`,
    );
  }
  await assertRows(
    `tasks?select=id&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) => rows.length === 0,
    'rejected account-capacity confirmation creates no task',
  );
  await assertRows(
    `deadline_plan_blocks?select=id,reservation_state&user_id=eq.${userId}&plan_id=eq.${planId}`,
    (rows) =>
      rows.length === proposed.pending_revision.blocks.length &&
      rows.every((row) => row.reservation_state === 'proposed'),
    'rejected account-capacity confirmation retains staged blocks',
  );

  const cancelled = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/cancel`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: crypto.randomUUID(), expected_revision: 1 },
    },
  );
  assertDeadlinePlanApiStatus(
    cancelled,
    200,
    'account-capacity draft cleanup',
  );
  const restored = await deadlinePlanApiRequest(
    '/v1/account/preparation-budget',
    accessToken,
    {
      method: 'PATCH',
      body: { daily_preparation_budget_minutes: 120 },
    },
  );
  assertDeadlinePlanApiStatus(restored, 200, 'restored preparation budget');
  if (restored.json?.daily_preparation_budget_minutes !== 120) {
    throw new Error(`Restored budget result is invalid: ${restored.text}`);
  }
  return planId;
}

async function assertDeadlinePlannerFlutterSurface({
  page,
  accessToken,
  planId,
  title,
  activeRevision,
}) {
  const lowered = await deadlinePlanApiRequest(
    '/v1/account/preparation-budget',
    accessToken,
    {
      method: 'PATCH',
      body: { daily_preparation_budget_minutes: 25 },
    },
  );
  assertDeadlinePlanApiStatus(
    lowered,
    200,
    'Flutter workload-detail budget setup',
  );
  const workloadResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/workload',
    accessToken,
  );
  assertDeadlinePlanApiStatus(
    workloadResult,
    200,
    'Flutter workload-detail baseline',
  );
  const workload = assertPreparationWorkload(workloadResult.json, {
    budget: 25,
    context: 'Flutter workload-detail baseline',
  });
  const overloadedDay = workload.days.find(
    (day) => day.over_budget_minutes > 0,
  );
  if (!overloadedDay) {
    throw new Error(
      `Flutter workload-detail setup has no review day: ${workloadResult.text}`,
    );
  }
  const planPageLoad = page.waitForResponse(
    (response) =>
      response.url() === `${aiServiceBaseUrl}/v1/deadline-plans` &&
      response.request().method() === 'GET',
    { timeout: 45000 },
  );
  await page.goto(
    appRoute(`/preparation-plans?plan_id=${encodeURIComponent(planId)}`),
    { waitUntil: 'domcontentloaded' },
  );
  const planPageResponse = await planPageLoad;
  if (!planPageResponse.ok()) {
    throw new Error(
      `Preparation-plan Flutter surface failed to load: ${planPageResponse.status()} ${await planPageResponse.text()}`,
    );
  }
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Preparation plans');
  await expectText(page, 'Your next 7 days');
  await expectText(
    page,
    '25 min total preparation per day across confirmed plans.',
  );
  const workloadDetailLoad = page.waitForResponse(
    (response) =>
      response.url() ===
        `${aiServiceBaseUrl}/v1/deadline-plans/workload/${overloadedDay.local_date}` &&
      response.request().method() === 'GET',
    { timeout: 45000 },
  );
  const dayLabel = new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${overloadedDay.local_date}T12:00:00Z`));
  const workloadDay = await scrollUntilTextInViewport(page, dayLabel, {
    maxSteps: 16,
    buttonFirst: true,
  });
  await workloadDay.click({ force: true });
  const workloadDetailResponse = await workloadDetailLoad;
  if (!workloadDetailResponse.ok()) {
    throw new Error(
      `Flutter workload detail failed to load: ${workloadDetailResponse.status()} ${await workloadDetailResponse.text()}`,
    );
  }
  assertPreparationWorkloadDetail(await workloadDetailResponse.json(), {
    budget: 25,
    localDate: overloadedDay.local_date,
    context: 'Flutter preparation workload detail',
  });
  await expectText(page, 'At least');
  await expectText(page, 'nothing changes automatically');
  await expectText(page, 'Review plan');
  await scrollUntilTextInViewport(page, 'Replan remaining time', {
    maxSteps: 8,
    buttonFirst: true,
  });
  await clickByText(page, 'Replan remaining time');
  await expectText(page, 'Replan remaining preparation');
  await expectText(page, 'Create preview with these values');
  await expectText(page, 'Nothing changes automatically');
  await clickByText(page, 'Change values');
  await expectText(page, 'Step 1 of 3');
  await expectText(page, 'Adjust preparation plan');
  const editorCancel = page.getByRole('button', {
    name: 'Cancel',
    exact: true,
  });
  if ((await editorCancel.count()) !== 1) {
    throw new Error(
      'Preparation replan editor did not expose one exact Cancel button.',
    );
  }
  await editorCancel.click();
  await page.waitForFunction(
    () => window.location.hash.startsWith('#/preparation-plans'),
    null,
    { timeout: 10000 },
  );
  await expectText(page, 'Preparation plans');

  const restored = await deadlinePlanApiRequest(
    '/v1/account/preparation-budget',
    accessToken,
    {
      method: 'PATCH',
      body: { daily_preparation_budget_minutes: 120 },
    },
  );
  assertDeadlinePlanApiStatus(
    restored,
    200,
    'Flutter workload-detail budget cleanup',
  );
  await scrollUntilTextInViewport(page, title, { maxSteps: 16 });
  await expectText(page, 'Active');
  await scrollUntilTextInViewport(page, 'Reserved in MyLifeGraph only', {
    maxSteps: 12,
  });

  const firstBlock = activeRevision.blocks[0];
  const firstBlockLabel =
    `${firstBlock.local_date} · ` +
    `${firstBlock.local_start_time.substring(0, 5)}–` +
    firstBlock.local_end_time.substring(0, 5);
  await scrollUntilTextInViewport(page, firstBlockLabel, { maxSteps: 12 });
  await scrollUntilTextInViewport(page, 'Adjust estimate or plan', {
    maxSteps: 12,
    buttonFirst: true,
  });

  const currentWeekBlockId = await page.evaluate((blocks) => {
    const now = new Date();
    const isoWeekday = now.getDay() || 7;
    const weekStart = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() - (isoWeekday - 1),
    );
    const weekEnd = new Date(
      weekStart.getFullYear(),
      weekStart.getMonth(),
      weekStart.getDate() + 7,
    );
    return (
      blocks.find((block) => {
        const startsAt = new Date(block.starts_at);
        return startsAt >= weekStart && startsAt < weekEnd;
      })?.id ?? null
    );
  }, activeRevision.blocks);
  const currentWeekBlock = activeRevision.blocks.find(
    (block) => block.id === currentWeekBlockId,
  );

  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  const dashboardPlanApiRequests = [];
  const captureDashboardRequest = (request) => {
    if (
      request.url().startsWith(`${aiServiceBaseUrl}/v1/deadline-plans`)
    ) {
      dashboardPlanApiRequests.push({
        method: request.method(),
        url: request.url(),
      });
    }
  };
  page.on('request', captureDashboardRequest);
  const dashboardBlockLoad = page.waitForResponse(
    (response) =>
      response.url().includes('/rest/v1/deadline_plan_blocks?') &&
      response.request().method() === 'GET',
    { timeout: 45000 },
  );
  const dashboardWorkloadLoad = page.waitForResponse(
    (response) =>
      response.url() === `${aiServiceBaseUrl}/v1/deadline-plans/workload` &&
      response.request().method() === 'GET',
    { timeout: 45000 },
  );
  // Hash navigation retains Riverpod's non-autoDispose Dashboard projection.
  // A real reload proves the current database reservations instead of reusing
  // the snapshot that Flutter loaded before the Node-side Planner mutations.
  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await scrollUntilTextInViewport(page, 'More', {
    maxSteps: 30,
    buttonFirst: true,
  });
  await clickByText(page, 'More');
  const [dashboardBlockResponse, dashboardWorkloadResponse] =
    await Promise.all([dashboardBlockLoad, dashboardWorkloadLoad]);
  if (!dashboardBlockResponse.ok()) {
    throw new Error(
      `Dashboard preparation block projection failed to load: ${dashboardBlockResponse.status()} ${await dashboardBlockResponse.text()}`,
    );
  }
  if (!dashboardWorkloadResponse.ok()) {
    throw new Error(
      `Dashboard preparation workload failed to load: ${dashboardWorkloadResponse.status()} ${await dashboardWorkloadResponse.text()}`,
    );
  }
  assertPreparationWorkload(await dashboardWorkloadResponse.json(), {
    budget: 120,
    context: 'Dashboard preparation workload',
  });
  await scrollUntilTextInViewport(page, '7-day preparation load', {
    maxSteps: 30,
  });
  await expectText(page, '7-day preparation load');
  await scrollUntilTextInViewport(page, 'Full week', { maxSteps: 40 });
  await expectText(page, 'Full week');
  await scrollUntilTextInViewport(page, `Preparation: ${title}`, {
    maxSteps: 20,
  });
  page.off('request', captureDashboardRequest);
  const unexpectedDashboardPlanRequests = dashboardPlanApiRequests.filter(
    (request) =>
      request.method !== 'GET' ||
      request.url !== `${aiServiceBaseUrl}/v1/deadline-plans/workload`,
  );
  if (
    !dashboardPlanApiRequests.some(
      (request) =>
        request.method === 'GET' &&
        request.url === `${aiServiceBaseUrl}/v1/deadline-plans/workload`,
    ) ||
    unexpectedDashboardPlanRequests.length !== 0
  ) {
    throw new Error(
      `Dashboard preparation requests exceeded the read-only workload plus bounded Supabase projections: ${JSON.stringify(dashboardPlanApiRequests)}`,
    );
  }
  if (currentWeekBlock) {
    await scrollUntilTextInViewport(page, `Preparation: ${title}`, {
      maxSteps: 12,
    });
    await scrollUntilTextInViewport(
      page,
      'Device time · MyLifeGraph reservation',
      { maxSteps: 8 },
    );
    await scrollUntilTextInViewport(page, 'Open preparation plan', {
      maxSteps: 4,
      buttonFirst: true,
    });
  }
}

async function assertDeadlinePlannerRls({
  ownerAccessToken,
  userId,
  planId,
  revision,
  blockId,
  claimedRequestId,
  proposalBody,
}) {
  const ownerPlanRead = await authenticatedRestRequest(
    `deadline_plans?select=id,user_id,status,current_revision,latest_revision&id=eq.${planId}`,
    ownerAccessToken,
  );
  const ownerRevisionRead = await authenticatedRestRequest(
    `deadline_plan_revisions?select=plan_id,user_id,revision,state&plan_id=eq.${planId}&revision=eq.${revision}`,
    ownerAccessToken,
  );
  const ownerBlockRead = await authenticatedRestRequest(
    `deadline_plan_blocks?select=id,plan_id,user_id,revision,reservation_state&id=eq.${blockId}`,
    ownerAccessToken,
  );
  if (
    !ownerPlanRead.response.ok ||
    ownerPlanRead.rows?.length !== 1 ||
    ownerPlanRead.rows[0].user_id !== userId ||
    !ownerRevisionRead.response.ok ||
    ownerRevisionRead.rows?.length !== 1 ||
    ownerRevisionRead.rows[0].user_id !== userId ||
    !ownerBlockRead.response.ok ||
    ownerBlockRead.rows?.length !== 1 ||
    ownerBlockRead.rows[0].user_id !== userId
  ) {
    throw new Error(
      `Deadline Planner owner RLS reads failed: ${stableJson({ ownerPlanRead: ownerPlanRead.text, ownerRevisionRead: ownerRevisionRead.text, ownerBlockRead: ownerBlockRead.text })}`,
    );
  }

  const ledgerRead = await authenticatedRestRequest(
    `deadline_plan_request_identities?select=request_id&request_id=eq.${claimedRequestId}`,
    ownerAccessToken,
  );
  if (ledgerRead.response.ok) {
    throw new Error(
      `Authenticated owner unexpectedly read the Deadline Planner ledger: ${ledgerRead.text}`,
    );
  }

  const directMutations = [
    await authenticatedRestRequest(
      `deadline_plans?id=eq.${planId}`,
      ownerAccessToken,
      { method: 'PATCH', body: { title: 'Direct plan rewrite' } },
    ),
    await authenticatedRestRequest(
      `deadline_plan_revisions?plan_id=eq.${planId}&revision=eq.${revision}`,
      ownerAccessToken,
      { method: 'PATCH', body: { title: 'Direct revision rewrite' } },
    ),
    await authenticatedRestRequest(
      `deadline_plan_blocks?id=eq.${blockId}`,
      ownerAccessToken,
      { method: 'DELETE' },
    ),
    await authenticatedRestRequest(
      'deadline_plans',
      ownerAccessToken,
      { method: 'POST', body: {} },
    ),
  ];
  if (directMutations.some((result) => result.response.ok)) {
    throw new Error(
      `Authenticated direct Deadline Planner mutation was accepted: ${stableJson(directMutations.map((result) => ({ status: result.response.status, body: result.text })))}`,
    );
  }
  await assertRows(
    `deadline_plans?select=id,status,title,current_revision,latest_revision&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'active' &&
      rows[0].title === proposalBody.title &&
      rows[0].current_revision === revision &&
      rows[0].latest_revision === revision,
    'backend-owned Deadline Planner state survives direct DML',
  );

  const secondaryEmail = `e2e-deadline-other-${runId}@example.test`;
  const secondaryPassword = `E2e-deadline-other-${runId}-password`;
  const secondaryUser = await createConfirmedUserWithCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    displayName: 'E2E Deadline Planner Other User',
  });
  const secondaryId = secondaryUser?.user?.id ?? secondaryUser?.id;
  if (!isCanonicalUuid(secondaryId)) {
    throw new Error(
      `Deadline Planner secondary Auth user is invalid: ${stableJson(secondaryUser)}`,
    );
  }
  const secondaryToken = await signInCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    context: 'Deadline Planner secondary principal',
  });
  const crossOwnerGet = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}`,
    secondaryToken,
  );
  assertDeadlinePlanApiStatus(
    crossOwnerGet,
    404,
    'cross-owner deadline plan detail',
  );
  const crossOwnerFeed = await deadlinePlanApiRequest(
    '/v1/deadline-plans',
    secondaryToken,
  );
  assertDeadlinePlanApiStatus(
    crossOwnerFeed,
    200,
    'cross-owner deadline plan collection',
  );
  const secondaryFeed = assertDeadlinePlanCollection(
    crossOwnerFeed.json,
    'cross-owner deadline plan collection',
  );
  if (secondaryFeed.plans.length !== 0) {
    throw new Error(
      `Deadline Planner collection exposed another owner's plan: ${crossOwnerFeed.text}`,
    );
  }
  const secondaryWorkloadResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/workload',
    secondaryToken,
  );
  assertDeadlinePlanApiStatus(
    secondaryWorkloadResult,
    200,
    'cross-owner preparation workload',
  );
  const secondaryWorkload = assertPreparationWorkload(
    secondaryWorkloadResult.json,
    { budget: null, context: 'cross-owner preparation workload' },
  );
  if (
    secondaryWorkload.days.some(
      (day) =>
        day.reserved_preparation_minutes !== 0 ||
        day.active_plan_count !== 0,
    )
  ) {
    throw new Error(
      `Preparation workload exposed another owner's reservations: ${secondaryWorkloadResult.text}`,
    );
  }
  const secondaryDetailResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/workload/${secondaryWorkload.days[0].local_date}`,
    secondaryToken,
  );
  assertDeadlinePlanApiStatus(
    secondaryDetailResult,
    200,
    'cross-owner preparation workload detail',
  );
  const secondaryDetail = assertPreparationWorkloadDetail(
    secondaryDetailResult.json,
    {
      budget: null,
      localDate: secondaryWorkload.days[0].local_date,
      context: 'cross-owner preparation workload detail',
    },
  );
  if (
    secondaryDetail.reserved_preparation_minutes !== 0 ||
    secondaryDetail.contributions.length !== 0
  ) {
    throw new Error(
      `Preparation workload detail exposed another owner's reservations: ${secondaryDetailResult.text}`,
    );
  }
  for (const [table, filter] of [
    ['deadline_plans', `id=eq.${planId}`],
    ['deadline_plan_revisions', `plan_id=eq.${planId}`],
    ['deadline_plan_blocks', `plan_id=eq.${planId}`],
  ]) {
    const crossOwnerRead = await authenticatedRestRequest(
      `${table}?select=*&${filter}`,
      secondaryToken,
    );
    if (!crossOwnerRead.response.ok || crossOwnerRead.rows?.length !== 0) {
      throw new Error(
        `Deadline Planner ${table} RLS exposed another owner: ${crossOwnerRead.response.status} ${crossOwnerRead.text}`,
      );
    }
  }
  const crossOwnerRequestReuse = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    secondaryToken,
    { method: 'POST', body: proposalBody },
  );
  assertDeadlinePlanApiStatus(
    crossOwnerRequestReuse,
    409,
    'global cross-owner deadline request identity',
  );
  await assertRows(
    `deadline_plans?select=id,user_id&id=eq.${planId}`,
    (rows) => rows.length === 1 && rows[0].user_id === userId,
    'cross-owner deadline request cannot reinterpret plan ownership',
  );
  await assertRows(
    `deadline_plans?select=id&user_id=eq.${secondaryId}`,
    (rows) => rows.length === 0,
    'cross-owner deadline conflict creates no secondary plan',
  );
}

async function assertDeadlinePlannerUnavailableAvailability({
  userId,
  accessToken,
  localToday,
}) {
  const currentPreferences = await plannerApiRequest(
    '/v1/planner/preferences',
    accessToken,
  );
  assertPlannerApiStatus(
    currentPreferences,
    200,
    'Planner calendar preference before Deadline availability',
  );
  const enabledPreferences = await plannerApiRequest(
    '/v1/planner/preferences',
    accessToken,
    {
      method: 'PATCH',
      body: {
        request_id: crypto.randomUUID(),
        expected_updated_at: currentPreferences.json?.updated_at ?? null,
        use_calendar_busy_time: true,
      },
    },
  );
  assertPlannerApiStatus(
    enabledPreferences,
    200,
    'central Planner calendar consent',
  );
  if (
    enabledPreferences.json?.use_calendar_busy_time !== true ||
    enabledPreferences.json?.calendar_available !== false ||
    enabledPreferences.json?.current_calendar_import_id !== null
  ) {
    throw new Error(
      `Central Planner calendar consent hid missing import truth: ${enabledPreferences.text}`,
    );
  }
  const planId = crypto.randomUUID();
  const unavailable = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: planId,
        base_revision: 0,
        kind: 'assignment',
        title: `E2E unavailable calendar capacity ${runId}`,
        deadline_at: `${addUtcDays(localToday, 7)}T12:00:00Z`,
        estimated_total_minutes: 90,
        credited_prior_minutes: 0,
        preferred_session_minutes: 45,
        max_daily_minutes: 90,
        planning_start_on: localToday,
        buffer_days: 1,
        source_kind: 'manual',
        use_calendar_availability: true,
      },
    },
  );
  assertDeadlinePlanApiStatus(
    unavailable,
    409,
    'Deadline Planner availability without a current import',
  );
  await assertRows(
    `deadline_plans?select=id&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) => rows.length === 0,
    'unavailable calendar capacity does not become an empty-calendar plan',
  );
}

async function assertDeadlinePlannerCalendarSource({
  userId,
  accessToken,
  scheduleBefore,
  fixture,
  firstVisibleEvents,
  replacementEvents,
  currentImportId,
}) {
  const localToday = isoDateInTimeZone(
    new Date().toISOString(),
    'Europe/Berlin',
  );
  const removedSource = firstVisibleEvents.find(
    (event) => event.title === fixture.recurrenceTitle,
  );
  const sourceEvent = replacementEvents.find(
    (event) => event.title === `Phase 9 page event 00 ${runId}`,
  );
  if (
    removedSource?.event_kind !== 'timed' ||
    sourceEvent?.event_kind !== 'timed' ||
    sourceEvent.busy_status !== 'busy' ||
    !isIsoTimestamp(sourceEvent.starts_at) ||
    !/^[0-9a-f]{64}$/.test(sourceEvent.source_fingerprint ?? '')
  ) {
    throw new Error(
      `Calendar fixture has no eligible explicit Deadline Planner source: ${stableJson({ removedSource, sourceEvent })}`,
    );
  }

  const stalePlanId = crypto.randomUUID();
  const staleSourceResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: stalePlanId,
        base_revision: 0,
        kind: 'assignment',
        title: `E2E removed calendar assignment ${runId}`,
        deadline_at: removedSource.starts_at,
        estimated_total_minutes: 90,
        credited_prior_minutes: 0,
        preferred_session_minutes: 45,
        max_daily_minutes: 90,
        planning_start_on: localToday,
        buffer_days: 0,
        source_kind: 'calendar_event',
        source_calendar_event_id: removedSource.id,
        source_calendar_event_fingerprint: removedSource.source_fingerprint,
        use_calendar_availability: false,
      },
    },
  );
  assertDeadlinePlanApiStatus(
    staleSourceResult,
    409,
    'removed imported event deadline source',
  );
  const changedFingerprintPlanId = crypto.randomUUID();
  const changedFingerprint =
    `${sourceEvent.source_fingerprint[0] === '0' ? '1' : '0'}` +
    sourceEvent.source_fingerprint.slice(1);
  const changedSourceResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: changedFingerprintPlanId,
        base_revision: 0,
        kind: 'assignment',
        title: `E2E stale fingerprint assignment ${runId}`,
        deadline_at: sourceEvent.starts_at,
        estimated_total_minutes: 90,
        credited_prior_minutes: 0,
        preferred_session_minutes: 45,
        max_daily_minutes: 90,
        planning_start_on: localToday,
        buffer_days: 0,
        source_kind: 'calendar_event',
        source_calendar_event_id: sourceEvent.id,
        source_calendar_event_fingerprint: changedFingerprint,
        use_calendar_availability: false,
      },
    },
  );
  assertDeadlinePlanApiStatus(
    changedSourceResult,
    409,
    'stale imported event fingerprint',
  );
  await assertRows(
    `deadline_plans?select=id&user_id=eq.${userId}&id=in.(${stalePlanId},${changedFingerprintPlanId})`,
    (rows) => rows.length === 0,
    'stale event sources create no Deadline Planner state',
  );

  const calendarBefore = await calendarPlannerSourceSnapshot(userId);
  const planId = crypto.randomUUID();
  const proposalRequestId = crypto.randomUUID();
  const title = `E2E user-chosen calendar assignment ${runId}`;
  if (title === sourceEvent.title) {
    throw new Error('Calendar Deadline Planner fixture accidentally inferred its title.');
  }
  const proposalBody = {
    request_id: proposalRequestId,
    plan_id: planId,
    base_revision: 0,
    kind: 'assignment',
    title,
    deadline_at: sourceEvent.starts_at,
    estimated_total_minutes: 150,
    credited_prior_minutes: 30,
    preferred_session_minutes: 40,
    max_daily_minutes: 80,
    planning_start_on: localToday,
    buffer_days: 1,
    source_kind: 'calendar_event',
    source_calendar_event_id: sourceEvent.id,
    source_calendar_event_fingerprint: sourceEvent.source_fingerprint,
    use_calendar_availability: true,
  };
  const proposalResult = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    { method: 'POST', body: proposalBody },
  );
  assertDeadlinePlanApiStatus(
    proposalResult,
    200,
    'explicit calendar-derived deadline proposal',
  );
  const proposed = assertDeadlinePlanEnvelope(
    proposalResult.json,
    'explicit calendar-derived deadline proposal',
  );
  const revision = proposed.pending_revision;
  if (
    proposed.plan.id !== planId ||
    proposed.plan.status !== 'draft' ||
    proposed.plan.title !== title ||
    proposed.plan.kind !== 'assignment' ||
    revision?.source_kind !== 'calendar_event' ||
    revision?.source_calendar_event_id !== sourceEvent.id ||
    revision?.source_calendar_event_fingerprint !==
      sourceEvent.source_fingerprint ||
    revision?.source_status !== 'current' ||
    revision?.use_calendar_availability !== true ||
    revision?.tracked_focus_minutes_at_proposal !== 0 ||
    revision?.remaining_minutes_at_proposal !== 120 ||
    revision?.planned_minutes + revision?.unscheduled_minutes !== 120 ||
    revision?.blocks.length < 1 ||
    !deadlineBlocksAvoidCurrentBusyEvents(revision.blocks, replacementEvents)
  ) {
    throw new Error(
      `Calendar-derived Deadline Planner proposal violated explicit source/capacity truth: ${proposalResult.text}`,
    );
  }
  await assertRows(
    `deadline_plan_revisions?select=plan_id,revision,source_kind,source_calendar_event_id,source_calendar_event_fingerprint,use_calendar_availability,availability_connection_id,availability_import_id,planning_fingerprint&user_id=eq.${userId}&plan_id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].revision === 1 &&
      rows[0].source_kind === 'calendar_event' &&
      rows[0].source_calendar_event_id === sourceEvent.id &&
      rows[0].source_calendar_event_fingerprint ===
        sourceEvent.source_fingerprint &&
      rows[0].use_calendar_availability === true &&
      isCanonicalUuid(rows[0].availability_connection_id) &&
      rows[0].availability_import_id === currentImportId &&
      /^[0-9a-f]{64}$/.test(rows[0].planning_fingerprint),
    'pinned current-import Deadline Planner provenance',
  );
  await assertCalendarPlannerSourceUnchanged(
    userId,
    calendarBefore,
    'calendar-derived Deadline Planner proposal',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar-derived Deadline Planner proposal',
  );

  const confirmRequestId = crypto.randomUUID();
  const confirmedResult = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: confirmRequestId, expected_revision: 1 },
    },
  );
  assertDeadlinePlanApiStatus(
    confirmedResult,
    200,
    'calendar-derived deadline confirmation',
  );
  const confirmed = assertDeadlinePlanEnvelope(
    confirmedResult.json,
    'calendar-derived deadline confirmation',
  );
  if (
    confirmed.plan.status !== 'active' ||
    confirmed.plan.managed_task_id !== planId ||
    confirmed.active_revision?.source_status !== 'current' ||
    confirmed.active_revision?.use_calendar_availability !== true ||
    Object.hasOwn(confirmed, 'pending_revision')
  ) {
    throw new Error(
      `Calendar-derived Deadline Planner confirmation is invalid: ${confirmedResult.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,title,status,deadline,source,metadata&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === title &&
      rows[0].status === 'todo' &&
      sameInstant(rows[0].deadline, sourceEvent.starts_at) &&
      rows[0].source === 'deadline-plan-v1' &&
      stableJson(rows[0].metadata) ===
        stableJson({
          contract_version: 'deadline-plan-v1',
          managed_by: 'deadline-planner',
          plan_id: planId,
        }),
    'calendar-derived plan creates only its managed task',
  );
  await assertCalendarPlannerSourceUnchanged(
    userId,
    calendarBefore,
    'calendar-derived Deadline Planner confirmation',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar-derived Deadline Planner confirmation',
  );
  return { planId, title, sourceEvent };
}

async function assertDeadlinePlannerCalendarSourceStatus({
  accessToken,
  planId,
  expectedSourceStatus,
  expectedPlanStatus,
  context,
}) {
  const result = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}`,
    accessToken,
  );
  assertDeadlinePlanApiStatus(result, 200, context);
  const detail = assertDeadlinePlanEnvelope(result.json, context);
  if (
    detail.plan.status !== expectedPlanStatus ||
    detail.active_revision?.source_status !== expectedSourceStatus ||
    detail.active_revision?.source_kind !== 'calendar_event'
  ) {
    throw new Error(`${context} lost retained source truth: ${result.text}`);
  }
  return detail;
}

async function cancelCalendarDeadlinePlan({
  userId,
  accessToken,
  planId,
  title,
  expectedRevision,
}) {
  const requestId = crypto.randomUUID();
  const body = {
    request_id: requestId,
    expected_revision: expectedRevision,
  };
  const result = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/cancel`,
    accessToken,
    { method: 'POST', body },
  );
  assertDeadlinePlanApiStatus(
    result,
    200,
    'explicit calendar-derived deadline cancellation',
  );
  const cancelled = assertDeadlinePlanEnvelope(
    result.json,
    'explicit calendar-derived deadline cancellation',
  );
  if (
    cancelled.plan.status !== 'cancelled' ||
    cancelled.plan.current_revision !== expectedRevision ||
    cancelled.active_revision?.source_status !== 'unavailable' ||
    !isIsoTimestamp(cancelled.plan.cancelled_at)
  ) {
    throw new Error(
      `Calendar-derived Deadline Planner cancellation is invalid: ${result.text}`,
    );
  }
  const replay = await deadlinePlanApiRequest(
    `/v1/deadline-plans/${planId}/cancel`,
    accessToken,
    { method: 'POST', body },
  );
  assertDeadlinePlanApiStatus(
    replay,
    200,
    'calendar-derived deadline cancellation replay',
  );
  if (stableJson(replay.json) !== stableJson(result.json)) {
    throw new Error(
      `Calendar-derived cancellation replay changed state: ${replay.text}`,
    );
  }
  await assertRows(
    `tasks?select=id,title,status,completed_at,cancelled_at&user_id=eq.${userId}&id=eq.${planId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].title === title &&
      rows[0].status === 'cancelled' &&
      rows[0].completed_at === null &&
      sameInstant(rows[0].cancelled_at, cancelled.plan.cancelled_at),
    'atomic matching calendar plan/task cancellation',
  );
  await assertRows(
    `deadline_plan_blocks?select=revision,reservation_state&user_id=eq.${userId}&plan_id=eq.${planId}`,
    (rows) =>
      rows.length > 0 &&
      rows.every(
        (row) =>
          row.revision === expectedRevision &&
          row.reservation_state === 'superseded',
      ),
    'calendar plan cancellation releases its local reservations',
  );
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'plan cancellation never recreates deleted imported events',
  );
}

function deadlineBlocksAvoidCurrentBusyEvents(blocks, events) {
  const busyTimed = events.filter(
    (event) => event.busy_status === 'busy' && event.event_kind === 'timed',
  );
  const busyAllDay = events.filter(
    (event) => event.busy_status === 'busy' && event.event_kind === 'all_day',
  );
  return blocks.every(
    (block) =>
      busyTimed.every(
        (event) =>
          Date.parse(block.ends_at) <= Date.parse(event.starts_at) ||
          Date.parse(block.starts_at) >= Date.parse(event.ends_at),
      ) &&
      busyAllDay.every(
        (event) =>
          block.local_date < event.starts_on ||
          block.local_date >= event.ends_on,
      ),
  );
}

async function calendarPlannerSourceSnapshot(userId) {
  const [connections, imports, events] = await Promise.all([
    fetchRows(
      `calendar_connections?select=*&user_id=eq.${userId}&order=id.asc`,
      'Deadline Planner calendar connection baseline',
    ),
    fetchRows(
      `calendar_imports?select=*&user_id=eq.${userId}&order=id.asc`,
      'Deadline Planner calendar import baseline',
    ),
    fetchRows(
      `calendar_events?select=*&user_id=eq.${userId}&order=id.asc`,
      'Deadline Planner calendar event baseline',
    ),
  ]);
  return { connections, imports, events };
}

async function assertCalendarPlannerSourceUnchanged(
  userId,
  expected,
  context,
) {
  const actual = await calendarPlannerSourceSnapshot(userId);
  if (stableJson(actual) !== stableJson(expected)) {
    throw new Error(
      `${context} mutated Calendar import/source state: ${stableJson(actual)}`,
    );
  }
}

async function assertBoundedCalendarImport(userId) {
  const accessToken = await signInAccessToken('Phase 9 calendar import');
  const scheduleBefore = await calendarScheduleSnapshot(userId);
  const deadlinePlansBeforeCalendarImport = await fetchRows(
    `deadline_plans?select=*&user_id=eq.${userId}&order=id.asc`,
    'Deadline Planner state before Calendar connect/import',
  );

  const initial = await calendarApiRequest(
    '/v1/calendar-integrations',
    accessToken,
  );
  assertCalendarApiStatus(initial, 200, 'initial calendar connection read');
  const initialConnection = assertCalendarConnectionEnvelope(
    initial.json,
    'initial calendar connection read',
  );
  if (initialConnection !== null) {
    throw new Error(
      `Phase 9 expected no initial calendar source: ${initial.text}`,
    );
  }
  await assertRows(
    `calendar_connections?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'read-only initial calendar GET',
  );

  const sourceLabel = `E2E calendar ${runId}`;
  const createRequestId = crypto.randomUUID();
  const createBody = {
    request_id: createRequestId,
    source_kind: 'ical_file',
    source_label: sourceLabel,
    consent: {
      consent_version: 'calendar-import-consent-v1',
      read_calendar_events: true,
      store_event_basics: true,
      provider_writes: false,
      llm_processing: false,
    },
  };
  const created = await calendarApiRequest(
    '/v1/calendar-integrations/connections',
    accessToken,
    { method: 'POST', body: createBody },
  );
  assertCalendarApiStatus(created, 200, 'calendar connection create');
  const connection = assertCalendarConnectionEnvelope(
    created.json,
    'calendar connection create',
  );
  if (
    connection === null ||
    connection.status !== 'connected' ||
    connection.source_label !== sourceLabel ||
    Object.hasOwn(connection, 'last_import') ||
    Object.hasOwn(connection, 'disconnected_at') ||
    Object.hasOwn(connection, 'imported_data_deleted_at')
  ) {
    throw new Error(
      `Calendar connection create returned invalid state: ${created.text}`,
    );
  }

  const createReplay = await calendarApiRequest(
    '/v1/calendar-integrations/connections',
    accessToken,
    { method: 'POST', body: createBody },
  );
  assertCalendarApiStatus(createReplay, 200, 'calendar connection replay');
  assertCalendarConnectionEnvelope(
    createReplay.json,
    'calendar connection replay',
  );
  if (stableJson(createReplay.json) !== stableJson(created.json)) {
    throw new Error(
      `Calendar connection replay changed its public result: ${createReplay.text}`,
    );
  }
  const createConflict = await calendarApiRequest(
    '/v1/calendar-integrations/connections',
    accessToken,
    {
      method: 'POST',
      body: { ...createBody, source_label: `${sourceLabel} changed` },
    },
  );
  assertCalendarApiStatus(
    createConflict,
    409,
    'calendar connection request-id conflict',
  );
  const secondCurrentSource = await calendarApiRequest(
    '/v1/calendar-integrations/connections',
    accessToken,
    {
      method: 'POST',
      body: { ...createBody, request_id: crypto.randomUUID() },
    },
  );
  assertCalendarApiStatus(
    secondCurrentSource,
    409,
    'second current calendar source',
  );

  await assertRows(
    `calendar_connections?select=id,user_id,create_request_id,source_label,status,last_import_id,provider_writes,llm_processing&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === connection.id &&
      rows[0].create_request_id === createRequestId &&
      rows[0].source_label === sourceLabel &&
      rows[0].status === 'connected' &&
      rows[0].last_import_id === null &&
      rows[0].provider_writes === false &&
      rows[0].llm_processing === false,
    'consented calendar connection without import',
  );
  await assertRows(
    `calendar_imports?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'calendar connection create without import history',
  );
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'calendar connection create without imported events',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar consent',
  );
  await assertDeadlinePlannerUnavailableAvailability({
    userId,
    accessToken,
    localToday: isoDateInTimeZone(
      new Date().toISOString(),
      'Europe/Berlin',
    ),
  });

  const fixture = buildCalendarImportFixture(
    isoDateInTimeZone(new Date().toISOString(), 'Europe/Berlin'),
  );
  const firstImportRequestId = crypto.randomUUID();
  const firstImportBody = {
    request_id: firstImportRequestId,
    calendar_text: fixture.firstCalendarText,
  };
  const firstImport = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    { method: 'POST', body: firstImportBody },
  );
  assertCalendarApiStatus(firstImport, 200, 'first calendar file import');
  const firstImported = assertCalendarImportEnvelope(
    firstImport.json,
    'first calendar file import',
  );
  assertCalendarCounts(
    firstImported.import.counts,
    fixture.firstCounts,
    'first calendar file import',
  );
  if (
    firstImported.connection.id !== connection.id ||
    firstImported.connection.status !== 'connected'
  ) {
    throw new Error(
      `First calendar import changed its connection identity: ${firstImport.text}`,
    );
  }

  const firstImportReplay = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    { method: 'POST', body: firstImportBody },
  );
  assertCalendarApiStatus(firstImportReplay, 200, 'calendar import replay');
  assertCalendarImportEnvelope(
    firstImportReplay.json,
    'calendar import replay',
  );
  if (stableJson(firstImportReplay.json) !== stableJson(firstImport.json)) {
    throw new Error(
      `Calendar import replay changed its persisted result: ${firstImportReplay.text}`,
    );
  }
  const firstImportConflict = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    {
      method: 'POST',
      body: {
        ...firstImportBody,
        calendar_text: `${fixture.firstCalendarText} `,
      },
    },
  );
  assertCalendarApiStatus(
    firstImportConflict,
    409,
    'calendar import request-id conflict',
  );

  await assertRows(
    `calendar_imports?select=id,request_id,connection_id,input_fingerprint,source_fingerprint,window_starts_on,window_ends_before,timezone,accepted_count,cancelled_count,out_of_window_count,unsupported_recurring_count,invalid_count&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === firstImported.import.id &&
      rows[0].request_id === firstImportRequestId &&
      rows[0].connection_id === connection.id &&
      /^[0-9a-f]{64}$/.test(rows[0].input_fingerprint) &&
      rows[0].source_fingerprint ===
        firstImported.import.source_fingerprint &&
      rows[0].window_starts_on === firstImported.import.window.starts_on &&
      rows[0].window_ends_before ===
        firstImported.import.window.ends_before &&
      rows[0].timezone === 'Europe/Berlin' &&
      rows[0].accepted_count === fixture.firstCounts.accepted &&
      rows[0].cancelled_count === fixture.firstCounts.cancelled &&
      rows[0].out_of_window_count === fixture.firstCounts.out_of_window &&
      rows[0].unsupported_recurring_count ===
        fixture.firstCounts.unsupported_recurring &&
      rows[0].invalid_count === fixture.firstCounts.invalid,
    'single replay-safe calendar import identity',
  );
  await assertRows(
    `calendar_events?select=id,connection_id,import_id,title,event_kind,source_event_key,source_fingerprint&user_id=eq.${userId}&order=id.asc`,
    (rows) =>
      rows.length === fixture.firstCounts.accepted &&
      rows.every(
        (row) =>
          row.connection_id === connection.id &&
          row.import_id === firstImported.import.id &&
          isCalendarIdentifier(row.id) &&
          /^[0-9a-f]{64}$/.test(row.source_event_key) &&
          /^[0-9a-f]{64}$/.test(row.source_fingerprint),
      ),
    'bounded deduplicated calendar event copy',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'first calendar import',
  );

  const firstEventPageResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events`,
    accessToken,
  );
  assertCalendarApiStatus(
    firstEventPageResult,
    200,
    'first calendar event page',
  );
  const firstEventPage = assertCalendarEventsEnvelope(
    firstEventPageResult.json,
    sourceLabel,
    'first calendar event page',
  );
  if (
    firstEventPage.connection_id !== connection.id ||
    firstEventPage.import_id !== firstImported.import.id ||
    firstEventPage.events.length !== 50 ||
    typeof firstEventPage.next_cursor !== 'string'
  ) {
    throw new Error(
      `First calendar event page is not bounded/paginated: ${firstEventPageResult.text}`,
    );
  }
  const staleCursor = firstEventPage.next_cursor;
  const secondEventPageResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events?cursor=${encodeURIComponent(staleCursor)}`,
    accessToken,
  );
  assertCalendarApiStatus(
    secondEventPageResult,
    200,
    'second calendar event page',
  );
  const secondEventPage = assertCalendarEventsEnvelope(
    secondEventPageResult.json,
    sourceLabel,
    'second calendar event page',
  );
  if (
    secondEventPage.import_id !== firstImported.import.id ||
    secondEventPage.events.length !== fixture.firstCounts.accepted - 50 ||
    Object.hasOwn(secondEventPage, 'next_cursor')
  ) {
    throw new Error(
      `Second calendar event page is invalid: ${secondEventPageResult.text}`,
    );
  }
  const firstVisibleEvents = [
    ...firstEventPage.events,
    ...secondEventPage.events,
  ];
  const firstVisibleIds = new Set(firstVisibleEvents.map((event) => event.id));
  if (
    firstVisibleIds.size !== fixture.firstCounts.accepted ||
    !firstVisibleEvents.some(
      (event) =>
        event.title === fixture.timezoneTitle &&
        event.event_kind === 'timed' &&
        event.event_timezone === 'Europe/Berlin' &&
        event.timezone_source === 'event' &&
        event.local_starts_at === `${fixture.timezoneDate}T09:00:00` &&
        event.location === 'Room Phase 9',
    ) ||
    !firstVisibleEvents.some(
      (event) =>
        event.title === fixture.allDayTitle &&
        event.event_kind === 'all_day' &&
        event.starts_on === fixture.allDayDate &&
        event.ends_on === addUtcDays(fixture.allDayDate, 1) &&
        event.timezone_source === 'profile',
    ) ||
    !firstVisibleEvents.some(
      (event) =>
        event.title === fixture.recurrenceTitle &&
        event.event_kind === 'timed',
    ) ||
    stableJson(firstVisibleEvents).includes(fixture.sensitiveMarker)
  ) {
    throw new Error(
      `Calendar event projection lost bounded TZ/all-day/recurrence/privacy semantics: ${JSON.stringify(firstVisibleEvents)}`,
    );
  }
  const firstEventIdsByTitle = Object.fromEntries(
    firstVisibleEvents.map((event) => [event.title, event.id]),
  );

  await assertCalendarIntegrationRls({
    ownerAccessToken: accessToken,
    userId,
    connectionId: connection.id,
    importId: firstImported.import.id,
    eventId: firstVisibleEvents[0].id,
    claimedRequestId: createRequestId,
  });

  const secondImportRequestId = crypto.randomUUID();
  const secondImport = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: secondImportRequestId,
        calendar_text: fixture.secondCalendarText,
      },
    },
  );
  assertCalendarApiStatus(secondImport, 200, 'replacement calendar import');
  const secondImported = assertCalendarImportEnvelope(
    secondImport.json,
    'replacement calendar import',
  );
  assertCalendarCounts(
    secondImported.import.counts,
    fixture.secondCounts,
    'replacement calendar import',
  );
  if (
    secondImported.import.id === firstImported.import.id ||
    secondImported.import.source_fingerprint ===
      firstImported.import.source_fingerprint
  ) {
    throw new Error(
      `Replacement calendar import did not advance provenance: ${secondImport.text}`,
    );
  }
  const supersededImportReplay = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    { method: 'POST', body: firstImportBody },
  );
  assertCalendarApiStatus(
    supersededImportReplay,
    409,
    'superseded calendar import replay',
  );

  const stalePage = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events?cursor=${encodeURIComponent(staleCursor)}`,
    accessToken,
  );
  assertCalendarApiStatus(stalePage, 409, 'stale calendar event cursor');

  const replacementPageResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events`,
    accessToken,
  );
  assertCalendarApiStatus(
    replacementPageResult,
    200,
    'replacement calendar event page',
  );
  const replacementPage = assertCalendarEventsEnvelope(
    replacementPageResult.json,
    sourceLabel,
    'replacement calendar event page',
  );
  const replacementTailResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events?cursor=${encodeURIComponent(replacementPage.next_cursor)}`,
    accessToken,
  );
  assertCalendarApiStatus(
    replacementTailResult,
    200,
    'replacement calendar event tail',
  );
  const replacementTail = assertCalendarEventsEnvelope(
    replacementTailResult.json,
    sourceLabel,
    'replacement calendar event tail',
  );
  const replacementEvents = [
    ...replacementPage.events,
    ...replacementTail.events,
  ];
  if (
    replacementPage.import_id !== secondImported.import.id ||
    replacementEvents.length !== fixture.secondCounts.accepted ||
    replacementEvents.some(
      (event) => event.title === fixture.recurrenceTitle,
    ) ||
    replacementEvents.some(
      (event) => event.title === fixture.omittedSnapshotTitle,
    ) ||
    replacementEvents.some(
      (event) =>
        firstEventIdsByTitle[event.title] !== undefined &&
        firstEventIdsByTitle[event.title] !== event.id,
    )
  ) {
    throw new Error(
      `Replacement calendar reconciliation is invalid: ${JSON.stringify(replacementEvents)}`,
    );
  }
  await assertRows(
    `calendar_imports?select=id,request_id&user_id=eq.${userId}&order=imported_at.asc`,
    (rows) =>
      rows.length === 2 &&
      rows[0].id === firstImported.import.id &&
      rows[1].id === secondImported.import.id,
    'immutable calendar import history before disconnect',
  );
  await assertRows(
    `calendar_events?select=id,import_id,title&user_id=eq.${userId}&order=id.asc`,
    (rows) =>
      rows.length === fixture.secondCounts.accepted &&
      rows.every(
        (row) =>
          row.import_id === secondImported.import.id &&
          row.title !== fixture.recurrenceTitle &&
          row.title !== fixture.omittedSnapshotTitle,
      ),
    'full-snapshot cancellation reconciliation',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'replacement calendar import',
  );
  await assertRows(
    `deadline_plans?select=*&user_id=eq.${userId}&order=id.asc`,
    (rows) =>
      stableJson(rows) === stableJson(deadlinePlansBeforeCalendarImport),
    'Calendar connect and imports create or mutate no preparation plan',
  );
  const calendarDeadlinePlan = await assertDeadlinePlannerCalendarSource({
    userId,
    accessToken,
    scheduleBefore,
    fixture,
    firstVisibleEvents,
    replacementEvents,
    currentImportId: secondImported.import.id,
  });

  const disconnectRequestId = crypto.randomUUID();
  const disconnectBody = { request_id: disconnectRequestId };
  const disconnected = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/disconnect`,
    accessToken,
    { method: 'POST', body: disconnectBody },
  );
  assertCalendarApiStatus(disconnected, 200, 'calendar disconnect');
  const disconnectedConnection = assertCalendarConnectionEnvelope(
    disconnected.json,
    'calendar disconnect',
  );
  if (
    disconnectedConnection?.id !== connection.id ||
    disconnectedConnection.status !== 'disconnected' ||
    !Object.hasOwn(disconnectedConnection, 'disconnected_at') ||
    disconnectedConnection.last_import?.id !== secondImported.import.id
  ) {
    throw new Error(
      `Calendar disconnect did not retain stale imported data: ${disconnected.text}`,
    );
  }
  const disconnectReplay = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/disconnect`,
    accessToken,
    { method: 'POST', body: disconnectBody },
  );
  assertCalendarApiStatus(disconnectReplay, 200, 'calendar disconnect replay');
  if (stableJson(disconnectReplay.json) !== stableJson(disconnected.json)) {
    throw new Error(
      `Calendar disconnect replay changed terminal state: ${disconnectReplay.text}`,
    );
  }
  const disconnectConflict = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/disconnect`,
    accessToken,
    { method: 'POST', body: { request_id: crypto.randomUUID() } },
  );
  assertCalendarApiStatus(
    disconnectConflict,
    409,
    'calendar disconnect request-id conflict',
  );
  const rejectedAfterDisconnect = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        calendar_text: fixture.firstCalendarText,
      },
    },
  );
  assertCalendarApiStatus(
    rejectedAfterDisconnect,
    409,
    'calendar import after disconnect',
  );
  const replayRejectedAfterDisconnect = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imports`,
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: secondImportRequestId,
        calendar_text: fixture.secondCalendarText,
      },
    },
  );
  assertCalendarApiStatus(
    replayRejectedAfterDisconnect,
    409,
    'calendar import replay after disconnect',
  );
  const retainedEventsResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events`,
    accessToken,
  );
  assertCalendarApiStatus(
    retainedEventsResult,
    200,
    'retained disconnected calendar events',
  );
  const retainedEvents = assertCalendarEventsEnvelope(
    retainedEventsResult.json,
    sourceLabel,
    'retained disconnected calendar events',
  );
  if (
    retainedEvents.import_id !== secondImported.import.id ||
    retainedEvents.events.length !== 50
  ) {
    throw new Error(
      `Disconnected calendar did not retain a stale local copy: ${retainedEventsResult.text}`,
    );
  }
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar disconnect',
  );
  await assertDeadlinePlannerCalendarSourceStatus({
    accessToken,
    planId: calendarDeadlinePlan.planId,
    expectedSourceStatus: 'stale',
    expectedPlanStatus: 'active',
    context: 'calendar-derived deadline plan after disconnect',
  });
  const disconnectedSourcePlanId = crypto.randomUUID();
  const disconnectedSourceProposal = await deadlinePlanApiRequest(
    '/v1/deadline-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: disconnectedSourcePlanId,
        base_revision: 0,
        kind: 'assignment',
        title: `E2E disconnected calendar source ${runId}`,
        deadline_at: calendarDeadlinePlan.sourceEvent.starts_at,
        estimated_total_minutes: 90,
        credited_prior_minutes: 0,
        preferred_session_minutes: 45,
        max_daily_minutes: 90,
        planning_start_on: isoDateInTimeZone(
          new Date().toISOString(),
          'Europe/Berlin',
        ),
        buffer_days: 0,
        source_kind: 'calendar_event',
        source_calendar_event_id: calendarDeadlinePlan.sourceEvent.id,
        source_calendar_event_fingerprint:
          calendarDeadlinePlan.sourceEvent.source_fingerprint,
        use_calendar_availability: false,
      },
    },
  );
  assertDeadlinePlanApiStatus(
    disconnectedSourceProposal,
    409,
    'disconnected imported event deadline source',
  );
  await assertRows(
    `deadline_plans?select=id&user_id=eq.${userId}&id=eq.${disconnectedSourcePlanId}`,
    (rows) => rows.length === 0,
    'disconnected event source creates no Deadline Planner state',
  );

  const deleteRequestId = crypto.randomUUID();
  const deletePath =
    `/v1/calendar-integrations/connections/${connection.id}/imported-data` +
    `?request_id=${encodeURIComponent(deleteRequestId)}`;
  const crossOperationDelete = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imported-data` +
      `?request_id=${encodeURIComponent(disconnectRequestId)}`,
    accessToken,
    { method: 'DELETE' },
  );
  assertCalendarApiStatus(
    crossOperationDelete,
    409,
    'calendar request id reused across disconnect and delete',
  );
  const deleteWithBody = await calendarApiRequest(deletePath, accessToken, {
    method: 'DELETE',
    body: { extra: true },
  });
  assertCalendarApiStatus(
    deleteWithBody,
    422,
    'calendar imported-data delete body rejection',
  );
  const deleted = await calendarApiRequest(deletePath, accessToken, {
    method: 'DELETE',
  });
  assertCalendarApiStatus(deleted, 200, 'calendar imported-data delete');
  const deletedConnection = assertCalendarConnectionEnvelope(
    deleted.json,
    'calendar imported-data delete',
  );
  if (
    deletedConnection?.id !== connection.id ||
    deletedConnection.status !== 'disconnected' ||
    !Object.hasOwn(deletedConnection, 'imported_data_deleted_at') ||
    Object.hasOwn(deletedConnection, 'last_import')
  ) {
    throw new Error(
      `Calendar imported-data delete returned invalid tombstone: ${deleted.text}`,
    );
  }
  const deleteReplay = await calendarApiRequest(deletePath, accessToken, {
    method: 'DELETE',
  });
  assertCalendarApiStatus(deleteReplay, 200, 'calendar delete replay');
  if (stableJson(deleteReplay.json) !== stableJson(deleted.json)) {
    throw new Error(
      `Calendar delete replay changed terminal state: ${deleteReplay.text}`,
    );
  }
  const deleteConflict = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/imported-data` +
      `?request_id=${encodeURIComponent(crypto.randomUUID())}`,
    accessToken,
    { method: 'DELETE' },
  );
  assertCalendarApiStatus(
    deleteConflict,
    409,
    'calendar delete request-id conflict',
  );

  await assertRows(
    `calendar_connections?select=id,status,disconnect_request_id,delete_request_id,last_import_id,imported_data_deleted_at&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === connection.id &&
      rows[0].status === 'disconnected' &&
      rows[0].disconnect_request_id === disconnectRequestId &&
      rows[0].delete_request_id === deleteRequestId &&
      rows[0].last_import_id === null &&
      rows[0].imported_data_deleted_at != null,
    'minimal deleted calendar connection tombstone',
  );
  await assertRows(
    `calendar_request_identities?select=request_id,user_id,connection_id,operation&user_id=eq.${userId}&order=created_at.asc,request_id.asc`,
    (rows) => {
      const identities = new Map(
        rows.map((row) => [row.request_id, row]),
      );
      return (
        rows.length === 5 &&
        identities.get(createRequestId)?.operation === 'create_connection' &&
        identities.get(firstImportRequestId)?.operation === 'import_file' &&
        identities.get(secondImportRequestId)?.operation === 'import_file' &&
        identities.get(disconnectRequestId)?.operation === 'disconnect' &&
        identities.get(deleteRequestId)?.operation === 'delete_imported_data' &&
        rows.every(
          (row) =>
            row.user_id === userId && row.connection_id === connection.id,
        )
      );
    },
    'global opaque calendar request identities',
  );
  await assertRows(
    `calendar_imports?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'deleted local calendar import history',
  );
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'deleted local calendar events',
  );
  const emptyEventsResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connection.id}/events`,
    accessToken,
  );
  assertCalendarApiStatus(
    emptyEventsResult,
    200,
    'deleted calendar event read',
  );
  const emptyEvents = assertCalendarEventsEnvelope(
    emptyEventsResult.json,
    sourceLabel,
    'deleted calendar event read',
  );
  if (
    emptyEvents.events.length !== 0 ||
    Object.hasOwn(emptyEvents, 'import_id') ||
    Object.hasOwn(emptyEvents, 'next_cursor')
  ) {
    throw new Error(
      `Deleted calendar event read fabricated retained data: ${emptyEventsResult.text}`,
    );
  }
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar imported-data deletion',
  );
  await assertDeadlinePlannerCalendarSourceStatus({
    accessToken,
    planId: calendarDeadlinePlan.planId,
    expectedSourceStatus: 'unavailable',
    expectedPlanStatus: 'active',
    context: 'calendar-derived deadline plan after local data deletion',
  });
  await cancelCalendarDeadlinePlan({
    userId,
    accessToken,
    planId: calendarDeadlinePlan.planId,
    title: calendarDeadlinePlan.title,
    expectedRevision: 1,
  });
}

async function assertCalendarImportUi(page, userId) {
  const accessToken = await signInAccessToken('Phase 9 calendar UI');
  const scheduleBefore = await calendarScheduleSnapshot(userId);
  await page.goto(appRoute('/settings'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Settings');
  const initialStatusPromise = page.waitForResponse(
    (response) =>
      response.url() === `${aiServiceBaseUrl}/v1/calendar-integrations` &&
      response.request().method() === 'GET' &&
      response.ok(),
  );
  await clickByText(page, 'Calendar import (optional)');
  await page.waitForURL('**/#/settings/integrations/calendar');
  await initialStatusPromise;
  await expectText(page, 'Calendar import');
  await expectText(page, 'Optional, explicit, and read-only');
  await expectText(page, 'Read-only import');
  await expectText(page, 'Imported data deleted');

  const sourceLabel = `E2E UI calendar ${runId}`;
  const consent = page.getByRole('checkbox', {
    name: /I consent to this read-only import/i,
  });
  const createButton = page.getByRole('button', {
    name: 'Create read-only source',
    exact: true,
  });
  if ((await consent.count()) !== 1 || (await consent.isChecked())) {
    throw new Error('Calendar import consent was not explicit and unchecked.');
  }
  if ((await createButton.count()) !== 1 || (await createButton.isEnabled())) {
    throw new Error('Calendar source creation was enabled before explicit consent.');
  }
  await fillByLabelOrPlaceholder(page, 'Source label', sourceLabel, 0);
  await checkSemanticCheckbox(
    page,
    consent,
    'I consent to this read-only import',
  );
  if (!(await createButton.isEnabled())) {
    throw new Error('Calendar source creation stayed disabled after valid consent.');
  }
  const createResponsePromise = waitForAiPost(
    page,
    '/v1/calendar-integrations/connections',
    'calendar source creation',
  );
  await clickByText(page, 'Create read-only source');
  const createResponse = await createResponsePromise;
  const createPayload = createResponse.request().postDataJSON();
  assertExactCalendarKeys(
    createPayload,
    ['request_id', 'source_kind', 'source_label', 'consent'],
    'calendar UI create request',
  );
  assertCalendarConsent(createPayload.consent, 'calendar UI create consent');
  if (
    !isUuid(createPayload.request_id) ||
    createPayload.source_kind !== 'ical_file' ||
    createPayload.source_label !== sourceLabel
  ) {
    throw new Error(
      `Calendar UI sent an invalid create request: ${JSON.stringify(createPayload)}`,
    );
  }
  const createdConnection = assertCalendarConnectionEnvelope(
    await createResponse.json(),
    'calendar UI create response',
  );
  if (
    createdConnection?.source_label !== sourceLabel ||
    createdConnection.status !== 'connected' ||
    Object.hasOwn(createdConnection, 'last_import')
  ) {
    throw new Error('Calendar UI did not show a connected import-only source.');
  }
  await expectText(page, sourceLabel);
  await expectText(page, 'Connected');
  await expectText(page, 'No file has been imported yet.');
  await assertRows(
    `calendar_imports?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'UI consent creates no calendar import',
  );
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'UI consent creates no calendar events',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar UI consent',
  );

  const fixture = buildCalendarImportFixture(
    isoDateInTimeZone(new Date().toISOString(), 'Europe/Berlin'),
  );
  const selectedName = `phase9-${runId}.ics`;
  const selectedBytes = Buffer.byteLength(fixture.firstCalendarText, 'utf8');
  const fileChooserPromise = page.waitForEvent('filechooser');
  await clickByText(page, 'Choose .ics file');
  const fileChooser = await fileChooserPromise;
  await fileChooser.setFiles({
    name: selectedName,
    mimeType: 'text/calendar',
    buffer: Buffer.from(fixture.firstCalendarText, 'utf8'),
  });
  await expectText(page, `${selectedName} · ${selectedBytes} bytes`);

  let lostImportPayload;
  const importUrl =
    `${aiServiceBaseUrl}/v1/calendar-integrations/connections/` +
    `${createdConnection.id}/imports`;
  const loseCommittedImportResponse = async (route) => {
    if (route.request().method() !== 'POST') {
      await route.continue();
      return;
    }
    lostImportPayload = route.request().postDataJSON();
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Calendar response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    await route.abort('failed');
  };
  await page.route(importUrl, loseCommittedImportResponse);
  await clickByText(page, 'Import selected file');
  await expectText(page, 'Could not confirm the calendar change');
  await expectText(page, 'Retry unchanged');
  await expectText(page, `${selectedName} · ${selectedBytes} bytes`);
  await page.unroute(importUrl, loseCommittedImportResponse);
  if (
    !isUuid(lostImportPayload?.request_id) ||
    lostImportPayload?.calendar_text !== fixture.firstCalendarText ||
    stableJson(Object.keys(lostImportPayload ?? {}).sort()) !==
      stableJson(['calendar_text', 'request_id'])
  ) {
    throw new Error(
      `Calendar UI did not retain the exact import request: ${JSON.stringify(lostImportPayload)}`,
    );
  }
  await assertRows(
    `calendar_imports?select=id,request_id,accepted_count,cancelled_count,out_of_window_count,unsupported_recurring_count,invalid_count&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].request_id === lostImportPayload.request_id &&
      rows[0].accepted_count === fixture.firstCounts.accepted &&
      rows[0].cancelled_count === fixture.firstCounts.cancelled &&
      rows[0].out_of_window_count === fixture.firstCounts.out_of_window &&
      rows[0].unsupported_recurring_count ===
        fixture.firstCounts.unsupported_recurring &&
      rows[0].invalid_count === fixture.firstCounts.invalid,
    'server-committed calendar import after lost UI response',
  );
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === fixture.firstCounts.accepted,
    'server-committed calendar events after lost UI response',
  );

  const retryResponsePromise = waitForAiPost(
    page,
    `/v1/calendar-integrations/connections/${createdConnection.id}/imports`,
    'exact calendar import retry',
  );
  await clickByText(page, 'Retry unchanged');
  const retryResponse = await retryResponsePromise;
  const retryPayload = retryResponse.request().postDataJSON();
  if (
    retryPayload.request_id !== lostImportPayload.request_id ||
    retryPayload.calendar_text !== lostImportPayload.calendar_text
  ) {
    throw new Error(
      `Calendar import retry changed identity or bytes. First ${JSON.stringify(lostImportPayload)}, retry ${JSON.stringify(retryPayload)}`,
    );
  }
  const retryImport = assertCalendarImportEnvelope(
    await retryResponse.json(),
    'calendar UI import retry response',
  );
  assertCalendarCounts(
    retryImport.import.counts,
    fixture.firstCounts,
    'calendar UI import retry',
  );
  await expectText(page, fixture.timezoneTitle);
  await expectText(page, 'Imported · read-only');
  await expectText(
    page,
    `${fixture.firstCounts.accepted} accepted · ${fixture.firstCounts.cancelled} cancelled`,
  );
  await assertRows(
    `calendar_imports?select=id,request_id&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === retryImport.import.id &&
      rows[0].request_id === retryPayload.request_id,
    'one import identity after exact UI retry',
  );

  const firstPageResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${createdConnection.id}/events`,
    accessToken,
  );
  assertCalendarApiStatus(firstPageResult, 200, 'UI calendar event baseline');
  const firstPage = assertCalendarEventsEnvelope(
    firstPageResult.json,
    sourceLabel,
    'UI calendar event baseline',
  );
  const tailResult = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${createdConnection.id}/events?cursor=${encodeURIComponent(firstPage.next_cursor)}`,
    accessToken,
  );
  assertCalendarApiStatus(tailResult, 200, 'UI calendar event tail');
  const tail = assertCalendarEventsEnvelope(
    tailResult.json,
    sourceLabel,
    'UI calendar event tail',
  );
  const tailTitle = tail.events.at(-1)?.title;
  if (!tailTitle) {
    throw new Error('Calendar pagination fixture did not produce a UI tail event.');
  }
  await scrollFlutterPage(page, 12000);
  await expectText(page, 'Load more imported events');
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === 'GET' &&
        response.url().startsWith(
          `${aiServiceBaseUrl}/v1/calendar-integrations/connections/${createdConnection.id}/events?cursor=`,
        ) &&
        response.ok(),
    ),
    clickByText(page, 'Load more imported events'),
  ]);
  await scrollFlutterPage(page, 3000);
  await expectText(page, tailTitle);
  const actionLabels = await page.getByRole('button').allTextContents();
  if (
    actionLabels.some((label) =>
      /edit imported event|add (?:to )?(?:schedule|calendar)|write to provider/i.test(
        label,
      ),
    )
  ) {
    throw new Error(
      `Imported calendar events exposed a write affordance: ${JSON.stringify(actionLabels)}`,
    );
  }
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar UI import and pagination',
  );

  await clickByText(page, 'Disconnect source');
  await expectText(page, 'Disconnect calendar source?');
  const [disconnectResponse] = await Promise.all([
    waitForAiPost(
      page,
      `/v1/calendar-integrations/connections/${createdConnection.id}/disconnect`,
      'calendar UI disconnect',
    ),
    clickByText(page, 'Disconnect'),
  ]);
  const disconnectPayload = disconnectResponse.request().postDataJSON();
  if (
    stableJson(Object.keys(disconnectPayload).sort()) !==
      stableJson(['request_id']) ||
    !isUuid(disconnectPayload.request_id)
  ) {
    throw new Error(
      `Calendar UI disconnect request is invalid: ${JSON.stringify(disconnectPayload)}`,
    );
  }
  const disconnected = assertCalendarConnectionEnvelope(
    await disconnectResponse.json(),
    'calendar UI disconnect response',
  );
  if (
    disconnected?.status !== 'disconnected' ||
    disconnected.last_import?.id !== retryImport.import.id
  ) {
    throw new Error('Calendar UI disconnect did not retain imported data.');
  }
  await scrollFlutterPage(page, -20000);
  await expectText(page, 'Disconnected · may be out of date');
  await scrollFlutterPage(page, 20000);
  await expectText(page, tailTitle);
  if ((await page.getByText('Choose .ics file', { exact: true }).count()) !== 0) {
    throw new Error('Calendar UI still allowed file import after disconnect.');
  }
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === fixture.firstCounts.accepted,
    'UI disconnect retains imported calendar events',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar UI disconnect',
  );

  await clickByText(page, 'Delete imported data');
  await expectText(page, 'Delete imported calendar data?');
  const [deleteResponse] = await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === 'DELETE' &&
        response.url().startsWith(
          `${aiServiceBaseUrl}/v1/calendar-integrations/connections/${createdConnection.id}/imported-data?`,
        ) &&
        response.ok(),
    ),
    clickByText(page, 'Delete local imported data'),
  ]);
  const deleteUrl = new URL(deleteResponse.url());
  const deleteQueryKeys = [...deleteUrl.searchParams.keys()].sort();
  if (
    stableJson(deleteQueryKeys) !== stableJson(['request_id']) ||
    !isUuid(deleteUrl.searchParams.get('request_id')) ||
    deleteResponse.request().postData() !== null
  ) {
    throw new Error(
      `Calendar UI delete transport is invalid: ${deleteResponse.url()}`,
    );
  }
  const deleted = assertCalendarConnectionEnvelope(
    await deleteResponse.json(),
    'calendar UI delete response',
  );
  if (
    deleted?.id !== createdConnection.id ||
    !Object.hasOwn(deleted, 'imported_data_deleted_at') ||
    Object.hasOwn(deleted, 'last_import')
  ) {
    throw new Error('Calendar UI delete did not return a minimal tombstone.');
  }
  await expectText(page, 'Imported data deleted');
  await assertRows(
    `calendar_imports?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'UI deletion removes calendar import history',
  );
  await assertRows(
    `calendar_events?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'UI deletion removes imported calendar events',
  );
  await assertCalendarScheduleUnchanged(
    userId,
    scheduleBefore,
    'calendar UI deletion',
  );

  await assertCalendarGuestBoundary();
  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Today at a glance');
}

async function assertCalendarGuestBoundary() {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
  });
  await context.addInitScript(() => {
    localStorage.setItem('flutter.auth_guest_active', 'true');
    localStorage.setItem('flutter.auth_guest_onboarding_done', 'true');
    localStorage.setItem(
      'flutter.auth_guest_name',
      JSON.stringify('Phase 9 Guest'),
    );
  });
  const guestPage = await context.newPage();
  const calendarRequests = [];
  const deadlinePlanRequests = [];
  guestPage.on('request', (request) => {
    if (request.url().includes('/v1/calendar-integrations')) {
      calendarRequests.push(`${request.method()} ${request.url()}`);
    }
    if (
      request.url().includes('/v1/deadline-plans') ||
      request.url().includes('/rest/v1/deadline_plan')
    ) {
      deadlinePlanRequests.push(`${request.method()} ${request.url()}`);
    }
  });
  try {
    await guestPage.goto(appRoute('/settings/integrations/calendar'), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterShell(guestPage);
    await enableFlutterSemantics(guestPage);
    await expectText(guestPage, 'Calendar import unavailable in local demo');
    await guestPage.waitForTimeout(500);
    if (calendarRequests.length !== 0) {
      throw new Error(
        `Guest calendar surface contacted the authenticated API: ${JSON.stringify(calendarRequests)}`,
      );
    }

    await guestPage.goto(appRoute('/preparation-plans'), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterShell(guestPage);
    await enableFlutterSemantics(guestPage);
    await expectText(guestPage, 'Preparation plans');
    await expectText(guestPage, 'Synced preparation plans unavailable');
    await guestPage.waitForTimeout(500);
    await guestPage.goto(appRoute('/dashboard'), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterShell(guestPage);
    await enableFlutterSemantics(guestPage);
    await guestPage.waitForTimeout(500);
    if (deadlinePlanRequests.length !== 0) {
      throw new Error(
        `Guest preparation surface contacted the authenticated API: ${JSON.stringify(deadlinePlanRequests)}`,
      );
    }
  } finally {
    await context.close();
  }
}

async function assertControlledCoach(page, userId) {
  const accessToken = await signInAccessToken('Phase 10 Controlled Coach');
  const persistenceBeforeReads = await coachPersistenceSnapshot(userId);
  if (
    persistenceBeforeReads.requests.length !== 0 ||
    persistenceBeforeReads.messages.length !== 0 ||
    persistenceBeforeReads.usage.length !== 0
  ) {
    throw new Error('Phase 10 requires an empty owner-scoped Coach history.');
  }

  const capabilityResult = await coachApiRequest(
    '/v1/coach/capabilities',
    accessToken,
  );
  assertCoachApiStatus(capabilityResult, 200, 'initial Coach capability');
  const initialCapability = assertCoachCapability(
    capabilityResult.json,
    'initial Coach capability',
  );

  const emptyHistoryResult = await coachApiRequest(
    '/v1/coach/history',
    accessToken,
  );
  assertCoachApiStatus(emptyHistoryResult, 200, 'read-only empty Coach history');
  assertCoachHistoryEnvelope(
    emptyHistoryResult.json,
    [],
    'read-only empty Coach history',
  );
  const persistenceAfterReads = await coachPersistenceSnapshot(userId);
  if (stableJson(persistenceAfterReads) !== stableJson(persistenceBeforeReads)) {
    throw new Error('Coach capability/history GET created persistence rows.');
  }

  const coachMemoryId = crypto.randomUUID();
  const coachMemoryContent =
    `Synthetic E2E memory ${runId}: prefer one bounded, reviewable next step.`;
  await insertRows('memory_entries', [
    {
      id: coachMemoryId,
      user_id: userId,
      type: 'pattern',
      title: coachMemoryTitle,
      content: coachMemoryContent,
      strength: 0.7,
      evidence: [],
      metadata: { source: 'phase-10-e2e' },
    },
  ]);

  const memoriesResult = await coachApiRequest(
    '/v1/coach/memories',
    accessToken,
  );
  assertCoachApiStatus(memoriesResult, 200, 'Coach memory read');
  const memories = assertCoachMemoryEnvelope(
    memoriesResult.json,
    'Coach memory read',
  );
  const eligibleMemory = memories.memories.find(
    (memory) => memory.id === coachMemoryId,
  );
  if (
    eligibleMemory?.type !== 'pattern' ||
    eligibleMemory.title !== coachMemoryTitle ||
    eligibleMemory.content !== coachMemoryContent ||
    eligibleMemory.ownership !== 'manual' ||
    eligibleMemory.selected !== false
  ) {
    throw new Error('Coach did not expose the exact eligible E2E memory.');
  }
  if (memories.memories.some((memory) => memory.type === 'preference')) {
    throw new Error('Coach exposed a preference memory as selectable context.');
  }

  const selectResult = await coachApiRequest(
    `/v1/coach/memories/${coachMemoryId}/selection`,
    accessToken,
    { method: 'POST', body: { selected: true } },
  );
  assertCoachApiStatus(selectResult, 200, 'Coach memory selection');
  const selectedMemories = assertCoachMemoryEnvelope(
    selectResult.json,
    'Coach memory selection',
  );
  if (
    selectedMemories.memories.find((memory) => memory.id === coachMemoryId)
      ?.selected !== true
  ) {
    throw new Error('Coach memory selection did not persist as selected.');
  }
  await assertRows(
    `coach_memory_selections?select=user_id,memory_id,selection_version&user_id=eq.${userId}&memory_id=eq.${coachMemoryId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].selection_version === 'coach-memory-selection-v1',
    'one exact Coach memory selection row',
  );

  const productBeforeResponses = await coachProductSnapshot(userId);
  const firstRequestId = crypto.randomUUID();
  const firstRequest = {
    contract_version: 'coach-request-v1',
    request_id: firstRequestId,
    message: coachApiMessage,
    context_scope: 'today',
  };
  const firstResult = await coachApiRequest(
    '/v1/coach/respond',
    accessToken,
    { method: 'POST', body: firstRequest },
  );
  assertCoachApiStatus(firstResult, 200, 'first Coach response');
  const firstResponse = assertCoachResponse(
    firstResult.json,
    {
      requestId: firstRequestId,
      source: 'model',
      providerCalled: true,
      safety: 'normal',
    },
    'first Coach response',
  );
  const memoryContext = firstResponse.used_context.find(
    (item) => item.source === 'memories',
  );
  if (
    memoryContext?.available_count !== 1 ||
    memoryContext.included_count !== 1 ||
    memoryContext.omitted_count !== 0
  ) {
    throw new Error('Selected Coach memory was not used exactly once.');
  }
  await assertCoachAtomicPersistence(userId, [
    {
      requestId: firstRequestId,
      message: coachApiMessage,
      response: firstResponse,
      outcome: 'completed',
      providerCalled: true,
    },
  ]);

  const persistenceBeforeReplay = await coachPersistenceSnapshot(userId);
  const replayResult = await coachApiRequest(
    '/v1/coach/respond',
    accessToken,
    { method: 'POST', body: firstRequest },
  );
  assertCoachApiStatus(replayResult, 200, 'same-id Coach replay');
  if (stableJson(replayResult.json) !== stableJson(firstResponse)) {
    throw new Error('Same-id same-body Coach replay changed the response.');
  }
  const persistenceAfterReplay = await coachPersistenceSnapshot(userId);
  if (stableJson(persistenceAfterReplay) !== stableJson(persistenceBeforeReplay)) {
    throw new Error('Same-id Coach replay created or changed persistence rows.');
  }

  const conflictResult = await coachApiRequest(
    '/v1/coach/respond',
    accessToken,
    {
      method: 'POST',
      body: { ...firstRequest, message: `${coachApiMessage} changed` },
    },
  );
  assertCoachApiStatus(conflictResult, 409, 'same-id Coach conflict');
  const expectedConflict = {
    detail: {
      code: 'request_conflict',
      message: 'The Coach request id conflicts with an earlier request.',
      retryable: false,
    },
  };
  if (stableJson(conflictResult.json) !== stableJson(expectedConflict)) {
    throw new Error('Same-id different-body Coach conflict was not exact.');
  }
  if (
    stableJson(await coachPersistenceSnapshot(userId)) !==
    stableJson(persistenceBeforeReplay)
  ) {
    throw new Error('Rejected Coach request-id conflict changed persistence.');
  }

  const safetyRequestId = crypto.randomUUID();
  const safetyResult = await coachApiRequest(
    '/v1/coach/respond',
    accessToken,
    {
      method: 'POST',
      body: {
        contract_version: 'coach-request-v1',
        request_id: safetyRequestId,
        message: coachSafetyMessage,
        context_scope: 'today',
      },
    },
  );
  assertCoachApiStatus(safetyResult, 200, 'deterministic Coach safety response');
  const safetyResponse = assertCoachResponse(
    safetyResult.json,
    {
      requestId: safetyRequestId,
      source: 'deterministic_safety',
      providerCalled: false,
      safety: 'safety_redirect',
    },
    'deterministic Coach safety response',
  );
  if (
    safetyResponse.used_context.length !== 0 ||
    safetyResponse.staged_suggestion !== null ||
    safetyResponse.uncertainty.level !== 'high'
  ) {
    throw new Error('Deterministic Coach safety bypass included model context.');
  }
  await assertCoachAtomicPersistence(userId, [
    {
      requestId: firstRequestId,
      message: coachApiMessage,
      response: firstResponse,
      outcome: 'completed',
      providerCalled: true,
    },
    {
      requestId: safetyRequestId,
      message: coachSafetyMessage,
      response: safetyResponse,
      outcome: 'safety_redirect',
      providerCalled: false,
    },
  ]);

  const persistedHistory = await coachApiRequest(
    '/v1/coach/history',
    accessToken,
  );
  assertCoachApiStatus(persistedHistory, 200, 'persisted Coach history');
  assertCoachHistoryEnvelope(
    persistedHistory.json,
    [firstRequestId, safetyRequestId],
    'persisted Coach history',
  );

  await page.goto(appRoute('/coach'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await page.waitForURL('**/#/coach');
  await expectText(page, 'Development Coach ready');
  await expectText(page, 'Uses fixed test responses. This is not a live assistant.');
  await fillByLabelOrPlaceholder(page, 'Ask Coach', coachUiMessage, -1);
  const uiResponsePromise = waitForAiPost(
    page,
    '/v1/coach/respond',
    'deliberate Coach UI response',
  );
  await clickByText(page, 'Send');
  const uiResponseResult = await uiResponsePromise;
  const uiPayload = uiResponseResult.request().postDataJSON();
  assertExactCoachKeys(
    uiPayload,
    ['contract_version', 'request_id', 'message', 'context_scope'],
    'Coach UI request',
  );
  if (
    uiPayload.contract_version !== 'coach-request-v1' ||
    !isUuid(uiPayload.request_id) ||
    uiPayload.message !== coachUiMessage ||
    uiPayload.context_scope !== 'today'
  ) {
    throw new Error('Coach UI did not send the exact bounded request contract.');
  }
  const uiResponse = assertCoachResponse(
    await uiResponseResult.json(),
    {
      requestId: uiPayload.request_id,
      source: 'model',
      providerCalled: true,
      safety: 'normal',
    },
    'Coach UI response',
  );
  // Anchor these assertions to the newly inserted Latest response card. The
  // deterministic provider intentionally returns the same wording for older
  // turns, so a global first/last text match can expand the wrong history card.
  await scrollFlutterPage(page, -20000);
  await scrollUntilTextInViewport(page, coachUiMessage);
  await scrollUntilTextInViewport(page, uiResponse.reply);
  await scrollUntilTextInViewport(page, 'Uncertainty');
  await scrollUntilTextInViewport(page, uiResponse.uncertainty.reason);
  await scrollUntilTextInViewport(page, 'Review-only suggestion');
  await scrollUntilTextInViewport(page, uiResponse.staged_suggestion.title);
  await scrollUntilTextInViewport(
    page,
    'This suggestion cannot apply changes.',
  );
  await scrollUntilTextInViewport(page, 'Data used', {
    buttonFirst: true,
  });
  await scrollUntilTextInViewport(
    page,
    'Provider and model',
    { buttonFirst: true },
  );
  // Exact expanded data-use and provenance text is exercised in Flutter's
  // widget test. The browser assertion stays anchored to this unique latest
  // card while the exact API envelope above verifies every underlying value.

  await assertCoachAtomicPersistence(userId, [
    {
      requestId: firstRequestId,
      message: coachApiMessage,
      response: firstResponse,
      outcome: 'completed',
      providerCalled: true,
    },
    {
      requestId: safetyRequestId,
      message: coachSafetyMessage,
      response: safetyResponse,
      outcome: 'safety_redirect',
      providerCalled: false,
    },
    {
      requestId: uiPayload.request_id,
      message: coachUiMessage,
      response: uiResponse,
      outcome: 'completed',
      providerCalled: true,
    },
  ]);
  const uiHistory = await coachApiRequest('/v1/coach/history', accessToken);
  assertCoachApiStatus(uiHistory, 200, 'Coach history after UI response');
  assertCoachHistoryEnvelope(
    uiHistory.json,
    [firstRequestId, safetyRequestId, uiPayload.request_id],
    'Coach history after UI response',
  );

  await assertCoachRls({
    ownerAccessToken: accessToken,
    userId,
    memoryId: coachMemoryId,
    memoryTitle: coachMemoryTitle,
    requestId: firstRequestId,
  });
  const productAfterResponses = await coachProductSnapshot(userId);
  if (stableJson(productAfterResponses) !== stableJson(productBeforeResponses)) {
    throw new Error('Controlled Coach mutated owner product records.');
  }

  const deselectResult = await coachApiRequest(
    `/v1/coach/memories/${coachMemoryId}/selection`,
    accessToken,
    { method: 'DELETE' },
  );
  assertCoachApiStatus(deselectResult, 200, 'Coach memory deselection');
  const deselectedMemories = assertCoachMemoryEnvelope(
    deselectResult.json,
    'Coach memory deselection',
  );
  if (
    deselectedMemories.memories.find((memory) => memory.id === coachMemoryId)
      ?.selected !== false
  ) {
    throw new Error('Coach memory deselection did not persist.');
  }
  await assertRows(
    `coach_memory_selections?select=memory_id&user_id=eq.${userId}&memory_id=eq.${coachMemoryId}`,
    (rows) => rows.length === 0,
    'removed Coach memory selection row',
  );

  const capabilityBeforeDeleteResult = await coachApiRequest(
    '/v1/coach/capabilities',
    accessToken,
  );
  assertCoachApiStatus(
    capabilityBeforeDeleteResult,
    200,
    'Coach capability before history deletion',
  );
  const capabilityBeforeDelete = assertCoachCapability(
    capabilityBeforeDeleteResult.json,
    'Coach capability before history deletion',
  );
  if (
    capabilityBeforeDelete.limits.remaining_requests !==
    initialCapability.limits.remaining_requests - 3
  ) {
    throw new Error('Coach attempts did not decrement the daily budget exactly.');
  }

  await scrollUntilTextInViewport(page, 'Conversation history');
  const firstDeleteConversation = await scrollUntilTextInViewport(
    page,
    'Delete conversation',
    { buttonFirst: true },
  );
  const historyDeletes = [];
  const historyDeleteObserver = (request) => {
    if (
      request.method() === 'DELETE' &&
      request.url() === `${aiServiceBaseUrl}/v1/coach/history`
    ) {
      historyDeletes.push(request);
    }
  };
  page.on('request', historyDeleteObserver);
  await firstDeleteConversation.click();
  await expectText(page, 'Delete conversation?');
  await page.waitForTimeout(250);
  if (historyDeletes.length !== 0) {
    throw new Error('Coach history was deleted before confirmation.');
  }
  await clickByText(page, 'Cancel', { match: 'last' });
  await page.waitForTimeout(250);
  if (historyDeletes.length !== 0) {
    throw new Error('Cancelling Coach history deletion still called the API.');
  }

  const secondDeleteConversation = await scrollUntilTextInViewport(
    page,
    'Delete conversation',
    { buttonFirst: true },
  );
  await secondDeleteConversation.click();
  await expectText(page, 'Delete conversation?');
  const deleteResponsePromise = page.waitForResponse(
    (response) =>
      response.request().method() === 'DELETE' &&
      response.url() === `${aiServiceBaseUrl}/v1/coach/history`,
  );
  await clickByText(page, 'Delete conversation', { match: 'last' });
  const deleteResponse = await deleteResponsePromise;
  page.off('request', historyDeleteObserver);
  if (!deleteResponse.ok()) {
    throw new Error(
      `Coach UI history deletion failed with ${deleteResponse.status()}.`,
    );
  }
  const historyDeleteBody = historyDeletes[0]?.postData();
  if (
    historyDeletes.length !== 1 ||
    (historyDeleteBody !== null && historyDeleteBody !== '')
  ) {
    throw new Error('Coach UI history DELETE was not exactly body-free.');
  }
  const deletePayload = await deleteResponse.json();
  if (
    stableJson(deletePayload) !==
    stableJson({ contract_version: 'coach-history-v1', deleted: true })
  ) {
    throw new Error('Coach UI history deletion returned an invalid envelope.');
  }
  await expectText(page, 'No saved Coach conversation yet.');

  const afterDelete = await coachPersistenceSnapshot(userId);
  if (
    afterDelete.messages.length !== 0 ||
    afterDelete.requests.length !== 3 ||
    afterDelete.usage.length !== 3 ||
    afterDelete.requests.some(
      (request) =>
        request.state !== 'deleted' ||
        request.message_fingerprint !== null ||
        request.response !== null ||
        stableJson(request.used_context) !== '[]' ||
        request.deleted_at === null,
    )
  ) {
    throw new Error('Coach history deletion did not retain exact tombstones/usage.');
  }
  const deletedHistory = await coachApiRequest('/v1/coach/history', accessToken);
  assertCoachApiStatus(deletedHistory, 200, 'deleted Coach history read');
  assertCoachHistoryEnvelope(
    deletedHistory.json,
    [],
    'deleted Coach history read',
  );
  const capabilityAfterDeleteResult = await coachApiRequest(
    '/v1/coach/capabilities',
    accessToken,
  );
  assertCoachApiStatus(
    capabilityAfterDeleteResult,
    200,
    'Coach capability after history deletion',
  );
  const capabilityAfterDelete = assertCoachCapability(
    capabilityAfterDeleteResult.json,
    'Coach capability after history deletion',
  );
  if (
    capabilityAfterDelete.limits.remaining_requests !==
    capabilityBeforeDelete.limits.remaining_requests
  ) {
    throw new Error('Deleting Coach history reset the retained daily budget.');
  }

  await assertCoachGuestBoundary();
}

async function coachApiRequest(path, accessToken, options = {}) {
  return calendarApiRequest(path, accessToken, options);
}

function assertCoachApiStatus(result, expectedStatus, context) {
  if (result.response.status !== expectedStatus) {
    throw new Error(
      `${context} returned ${result.response.status}, expected ${expectedStatus}: ${result.text}`,
    );
  }
}

function assertCoachCapability(payload, context) {
  assertExactCoachKeys(
    payload,
    [
      'contract_version',
      'state',
      'provider',
      'provider_mode',
      'model_requested',
      'model_source',
      'reason_code',
      'limits',
    ],
    context,
  );
  assertExactCoachKeys(
    payload.limits,
    [
      'message_codepoints',
      'context_bytes',
      'reply_codepoints',
      'timeout_seconds',
      'requests_per_local_day',
      'remaining_requests',
    ],
    `${context} limits`,
  );
  if (
    payload.contract_version !== 'coach-capabilities-v1' ||
    payload.state !== 'ready' ||
    payload.provider !== 'fake' ||
    payload.provider_mode !== 'deterministic_test_only' ||
    payload.model_requested !== null ||
    payload.model_source !== 'not_applicable' ||
    payload.reason_code !== 'ready' ||
    payload.limits.message_codepoints !== 2000 ||
    payload.limits.context_bytes !== 32768 ||
    payload.limits.reply_codepoints !== 4000 ||
    !Number.isInteger(payload.limits.timeout_seconds) ||
    payload.limits.timeout_seconds < 5 ||
    payload.limits.timeout_seconds > 120 ||
    !Number.isInteger(payload.limits.requests_per_local_day) ||
    payload.limits.requests_per_local_day < 1 ||
    payload.limits.requests_per_local_day > 100 ||
    !Number.isInteger(payload.limits.remaining_requests) ||
    payload.limits.remaining_requests < 0 ||
    payload.limits.remaining_requests > payload.limits.requests_per_local_day
  ) {
    throw new Error(`${context} is not the ready deterministic fake capability.`);
  }
  return payload;
}

function assertCoachMemoryEnvelope(payload, context) {
  assertExactCoachKeys(
    payload,
    ['contract_version', 'max_selected', 'available_count', 'memories'],
    context,
  );
  if (
    payload.contract_version !== 'coach-memory-selection-v1' ||
    payload.max_selected !== 8 ||
    !Number.isInteger(payload.available_count) ||
    payload.available_count < 0 ||
    !Array.isArray(payload.memories) ||
    payload.available_count < payload.memories.length
  ) {
    throw new Error(`${context} has an invalid memory-selection envelope.`);
  }
  for (const memory of payload.memories) {
    assertExactCoachKeys(
      memory,
      [
        'id',
        'type',
        'title',
        'content',
        'content_truncated',
        'ownership',
        'selected',
        'updated_at',
      ],
      `${context} memory`,
    );
    if (
      !isCanonicalUuid(memory.id) ||
      !['pattern', 'goal', 'habit', 'recurring_problem', 'recommendation'].includes(
        memory.type,
      ) ||
      typeof memory.title !== 'string' ||
      memory.title.length === 0 ||
      typeof memory.content !== 'string' ||
      memory.content.length === 0 ||
      typeof memory.content_truncated !== 'boolean' ||
      !['setup', 'manual'].includes(memory.ownership) ||
      typeof memory.selected !== 'boolean' ||
      Number.isNaN(Date.parse(memory.updated_at))
    ) {
      throw new Error(`${context} contains an invalid memory row.`);
    }
  }
  if (payload.memories.filter((memory) => memory.selected).length > 8) {
    throw new Error(`${context} exceeds the selected-memory limit.`);
  }
  return payload;
}

function assertCoachResponse(payload, expected, context) {
  assertExactCoachKeys(
    payload,
    [
      'contract_version',
      'request_id',
      'reply',
      'uncertainty',
      'staged_suggestion',
      'safety',
      'used_context',
      'provenance',
    ],
    context,
  );
  assertExactCoachKeys(
    payload.uncertainty,
    ['level', 'reason'],
    `${context} uncertainty`,
  );
  assertExactCoachKeys(
    payload.safety,
    ['classification'],
    `${context} safety`,
  );
  assertExactCoachKeys(
    payload.provenance,
    [
      'source',
      'provider',
      'provider_mode',
      'model_requested',
      'model_reported',
      'model_source',
      'prompt_version',
      'context_version',
      'generated_at',
      'provider_called',
    ],
    `${context} provenance`,
  );
  if (
    payload.contract_version !== 'coach-response-v1' ||
    payload.request_id !== expected.requestId ||
    typeof payload.reply !== 'string' ||
    payload.reply.length === 0 ||
    !['low', 'medium', 'high'].includes(payload.uncertainty.level) ||
    typeof payload.uncertainty.reason !== 'string' ||
    payload.uncertainty.reason.length === 0 ||
    payload.safety.classification !== expected.safety ||
    !Array.isArray(payload.used_context) ||
    payload.provenance.source !== expected.source ||
    payload.provenance.provider !== 'fake' ||
    payload.provenance.provider_mode !== 'deterministic_test_only' ||
    payload.provenance.model_requested !== null ||
    payload.provenance.model_reported !== null ||
    payload.provenance.model_source !== 'not_applicable' ||
    payload.provenance.prompt_version !== 'controlled-coach-prompt-v1' ||
    payload.provenance.context_version !== 'coach-context-v1' ||
    payload.provenance.provider_called !== expected.providerCalled ||
    Number.isNaN(Date.parse(payload.provenance.generated_at))
  ) {
    throw new Error(`${context} violates the exact Coach response contract.`);
  }
  if (payload.staged_suggestion !== null) {
    assertExactCoachKeys(
      payload.staged_suggestion,
      ['title', 'rationale'],
      `${context} staged suggestion`,
    );
    if (
      typeof payload.staged_suggestion.title !== 'string' ||
      payload.staged_suggestion.title.length === 0 ||
      typeof payload.staged_suggestion.rationale !== 'string' ||
      payload.staged_suggestion.rationale.length === 0
    ) {
      throw new Error(`${context} has an invalid staged suggestion.`);
    }
  }

  const sources = [];
  for (const item of payload.used_context) {
    assertExactCoachKeys(
      item,
      [
        'source',
        'available_count',
        'included_count',
        'omitted_count',
        'freshness',
      ],
      `${context} used context`,
    );
    if (
      !Number.isInteger(item.available_count) ||
      !Number.isInteger(item.included_count) ||
      !Number.isInteger(item.omitted_count) ||
      item.included_count + item.omitted_count !== item.available_count ||
      !['current', 'stale', 'missing', 'not_applicable'].includes(
        item.freshness,
      )
    ) {
      throw new Error(`${context} has non-reconciling context counts.`);
    }
    sources.push(item.source);
  }
  if (new Set(sources).size !== sources.length) {
    throw new Error(`${context} repeats a context source.`);
  }
  if (expected.source === 'model') {
    const expectedSources = [
      'profile',
      'daily_snapshot',
      'daily_briefing',
      'goals',
      'tasks',
      'habits',
      'focus_sessions',
      'weekly_review',
      'memories',
      'coach_history',
    ];
    if (stableJson(sources) !== stableJson(expectedSources)) {
      throw new Error(`${context} has an incomplete ordered context manifest.`);
    }
    const expectedReply =
      'Your current plan already contains a clear next step. Keep it small, then reassess your available capacity.';
    if (
      payload.reply !== expectedReply ||
      payload.staged_suggestion?.title !== 'Protect one small next step' ||
      payload.staged_suggestion?.rationale !==
        'Review whether one deliberately small action fits the capacity you have today.'
    ) {
      throw new Error(`${context} was not produced by the deterministic fake provider.`);
    }
  }
  return payload;
}

function assertCoachHistoryEnvelope(payload, expectedRequestIds, context) {
  assertExactCoachKeys(payload, ['contract_version', 'turns'], context);
  if (
    payload.contract_version !== 'coach-history-v1' ||
    !Array.isArray(payload.turns) ||
    payload.turns.length !== expectedRequestIds.length
  ) {
    throw new Error(`${context} has an invalid history envelope.`);
  }
  const actualIds = [];
  for (const turn of payload.turns) {
    assertExactCoachKeys(
      turn,
      ['request_id', 'message', 'response', 'created_at'],
      `${context} turn`,
    );
    if (
      !isUuid(turn.request_id) ||
      typeof turn.message !== 'string' ||
      turn.message.length === 0 ||
      Number.isNaN(Date.parse(turn.created_at)) ||
      turn.response?.request_id !== turn.request_id
    ) {
      throw new Error(`${context} contains an invalid history turn.`);
    }
    assertCoachResponse(
      turn.response,
      {
        requestId: turn.request_id,
        source: turn.response.provenance?.source,
        providerCalled: turn.response.provenance?.provider_called,
        safety: turn.response.safety?.classification,
      },
      `${context} persisted response`,
    );
    actualIds.push(turn.request_id);
  }
  if (
    stableJson([...actualIds].sort()) !==
    stableJson([...expectedRequestIds].sort())
  ) {
    throw new Error(`${context} returned the wrong request identities.`);
  }
  return payload;
}

function assertExactCoachKeys(value, keys, context) {
  if (
    value === null ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    stableJson(Object.keys(value).sort()) !== stableJson([...keys].sort())
  ) {
    throw new Error(`${context} has unknown, missing, or non-object fields.`);
  }
}

async function coachPersistenceSnapshot(userId) {
  const [requests, messages, usage] = await Promise.all([
    fetchRows(
      `coach_requests?select=request_id,user_id,contract_version,context_scope,local_date,message_fingerprint,state,lease_expires_at,provider,provider_mode,model_requested,model_reported,model_source,prompt_version,context_version,response,used_context,error,created_at,completed_at,failed_at,deleted_at,updated_at&user_id=eq.${userId}&order=request_id.asc`,
      'Phase 10 Coach requests',
    ),
    fetchRows(
      `coach_messages?select=id,user_id,request_id,contract_version,role,content,metadata,created_at&user_id=eq.${userId}&order=request_id.asc,role.asc,id.asc`,
      'Phase 10 Coach messages',
    ),
    fetchRows(
      `coach_usage_events?select=id,request_id,user_id,local_date,outcome,provider,provider_mode,model_requested,model_reported,model_source,error_code,counters,created_at&user_id=eq.${userId}&order=request_id.asc`,
      'Phase 10 Coach usage',
    ),
  ]);
  return { requests, messages, usage };
}

async function assertCoachAtomicPersistence(userId, expected) {
  const persisted = await coachPersistenceSnapshot(userId);
  if (
    persisted.requests.length !== expected.length ||
    persisted.messages.length !== expected.length * 2 ||
    persisted.usage.length !== expected.length
  ) {
    throw new Error('Coach did not persist one request, pair, and usage row per turn.');
  }
  for (const item of expected) {
    const request = persisted.requests.find(
      (row) => row.request_id === item.requestId,
    );
    const messages = persisted.messages.filter(
      (row) => row.request_id === item.requestId,
    );
    const usage = persisted.usage.find(
      (row) => row.request_id === item.requestId,
    );
    if (
      request?.state !== 'completed' ||
      request.contract_version !== 'coach-request-v1' ||
      request.context_scope !== 'today' ||
      request.provider !== 'fake' ||
      request.provider_mode !== 'deterministic_test_only' ||
      request.model_requested !== null ||
      request.model_source !== 'not_applicable' ||
      request.prompt_version !== 'controlled-coach-prompt-v1' ||
      request.context_version !== 'coach-context-v1' ||
      !/^[0-9a-f]{64}$/.test(request.message_fingerprint ?? '') ||
      stableJson(request.response) !== stableJson(item.response) ||
      stableJson(request.used_context) !== stableJson(item.response.used_context) ||
      request.error !== null ||
      request.completed_at === null ||
      stableJson(request).includes(item.message)
    ) {
      throw new Error(`Coach request ${item.requestId} is not an exact terminal row.`);
    }
    if (
      messages.length !== 2 ||
      !messages.every(
        (message) =>
          message.user_id === userId &&
          message.contract_version === 'coach-message-v1' &&
          stableJson(message.metadata) === '{}',
      ) ||
      messages.find((message) => message.role === 'user')?.content !==
        item.message ||
      messages.find((message) => message.role === 'assistant')?.content !==
        item.response.reply
    ) {
      throw new Error(`Coach request ${item.requestId} lacks its exact atomic pair.`);
    }
    assertExactCoachKeys(
      usage?.counters,
      ['provider_called', 'prompt_bytes', 'context_bytes', 'reply_codepoints'],
      `Coach request ${item.requestId} usage counters`,
    );
    if (
      usage?.outcome !== item.outcome ||
      usage.provider !== 'fake' ||
      usage.provider_mode !== 'deterministic_test_only' ||
      usage.model_requested !== null ||
      usage.model_reported !== null ||
      usage.model_source !== 'not_applicable' ||
      usage.error_code !== null ||
      usage.counters.provider_called !== item.providerCalled ||
      usage.counters.reply_codepoints !== Array.from(item.response.reply).length ||
      (item.providerCalled &&
        (usage.counters.prompt_bytes <= 0 || usage.counters.context_bytes <= 0)) ||
      (!item.providerCalled &&
        (usage.counters.prompt_bytes !== 0 || usage.counters.context_bytes !== 0))
    ) {
      throw new Error(`Coach request ${item.requestId} has invalid retained usage.`);
    }
  }
}

async function coachProductSnapshot(userId) {
  const tables = [
    'daily_logs',
    'behavioral_events',
    'goals',
    'tasks',
    'habits',
    'habit_logs',
    'focus_sessions',
    'schedule_items',
    'memory_entries',
    'recommendations',
    'user_state_snapshots',
    'daily_briefings',
    'weekly_reviews',
  ];
  const rows = await Promise.all(
    tables.map((table) =>
      fetchRows(
        `${table}?select=*&user_id=eq.${userId}&order=id.asc`,
        `Phase 10 ${table} mutation baseline`,
      ),
    ),
  );
  const [profile] = await fetchRows(
    `profiles?select=*&id=eq.${userId}`,
    'Phase 10 profile mutation baseline',
  );
  return {
    profile,
    ...Object.fromEntries(tables.map((table, index) => [table, rows[index]])),
  };
}

async function assertCoachRls({
  ownerAccessToken,
  userId,
  memoryId,
  memoryTitle,
  requestId,
}) {
  const ownerMessages = await authenticatedRestRequest(
    `coach_messages?select=id,user_id,request_id,role&request_id=eq.${requestId}`,
    ownerAccessToken,
  );
  const ownerMemory = await authenticatedRestRequest(
    `memory_entries?select=id,user_id,type,title&id=eq.${memoryId}`,
    ownerAccessToken,
  );
  const ownerSelection = await authenticatedRestRequest(
    `coach_memory_selections?select=user_id,memory_id,selection_version&memory_id=eq.${memoryId}`,
    ownerAccessToken,
  );
  if (
    !ownerMessages.response.ok ||
    ownerMessages.rows?.length !== 2 ||
    !ownerMemory.response.ok ||
    ownerMemory.rows?.length !== 1 ||
    !ownerSelection.response.ok ||
    ownerSelection.rows?.length !== 1
  ) {
    throw new Error('Coach owner SELECT policies did not expose exact owned rows.');
  }

  const secondaryEmail = `e2e-phase10-other-${coachAttemptId}@example.test`;
  const secondaryPassword = `E2e-phase10-other-${coachAttemptId}-password`;
  const secondary = await createConfirmedUserWithCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    displayName: 'E2E Coach Other User',
  });
  const secondaryToken = await signInCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    context: 'Phase 10 secondary principal',
  });
  const selfPromotion = await authenticatedRestRequest(
    `profiles?id=eq.${secondary.id}`,
    secondaryToken,
    {
      method: 'PATCH',
      body: { role: 'admin', auth_provider: 'email' },
    },
  );
  if (selfPromotion.response.ok) {
    throw new Error('Authenticated Coach principal self-promoted to admin.');
  }
  const selfOnboarding = await authenticatedRestRequest(
    `profiles?id=eq.${secondary.id}`,
    secondaryToken,
    {
      method: 'PATCH',
      body: { onboarding_completed_at: new Date().toISOString() },
    },
  );
  if (selfOnboarding.response.ok) {
    throw new Error(
      'Authenticated Coach principal bypassed the atomic Setup apply contract.',
    );
  }
  await assertRows(
    `profiles?select=id,role,auth_provider,onboarding_completed_at&id=eq.${secondary.id}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].role === 'user' &&
      rows[0].auth_provider === 'email' &&
      rows[0].onboarding_completed_at === null,
    'Coach secondary profile authority survives direct privilege attempts',
  );
  const crossOwnerReads = await Promise.all([
    authenticatedRestRequest(
      `coach_messages?select=id&request_id=eq.${requestId}`,
      secondaryToken,
    ),
    authenticatedRestRequest(
      `memory_entries?select=id&id=eq.${memoryId}`,
      secondaryToken,
    ),
    authenticatedRestRequest(
      `coach_memory_selections?select=memory_id&memory_id=eq.${memoryId}`,
      secondaryToken,
    ),
  ]);
  if (
    crossOwnerReads.some(
      (result) => !result.response.ok || result.rows?.length !== 0,
    )
  ) {
    throw new Error('Coach RLS exposed owner rows to a secondary principal.');
  }
  const secondaryHistory = await coachApiRequest(
    '/v1/coach/history',
    secondaryToken,
  );
  assertCoachApiStatus(secondaryHistory, 200, 'cross-owner Coach history');
  assertCoachHistoryEnvelope(
    secondaryHistory.json,
    [],
    'cross-owner Coach history',
  );

  const directMessageInsert = await authenticatedRestRequest(
    'coach_messages',
    ownerAccessToken,
    {
      method: 'POST',
      body: {
        user_id: userId,
        role: 'user',
        content: `E2E unauthorized Coach message ${runId}`,
        metadata: {},
      },
    },
  );
  const directMemoryPatch = await authenticatedRestRequest(
    `memory_entries?id=eq.${memoryId}`,
    ownerAccessToken,
    { method: 'PATCH', body: { title: 'E2E unauthorized memory rewrite' } },
  );
  const directSelectionDelete = await authenticatedRestRequest(
    `coach_memory_selections?user_id=eq.${userId}&memory_id=eq.${memoryId}`,
    ownerAccessToken,
    { method: 'DELETE' },
  );
  if (
    directMessageInsert.response.ok ||
    directMemoryPatch.response.ok ||
    directSelectionDelete.response.ok
  ) {
    throw new Error('Authenticated client wrote backend-owned Coach state directly.');
  }
  await assertRows(
    `coach_messages?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 6,
    'Coach messages survive direct authenticated insert',
  );
  await assertRows(
    `memory_entries?select=id,title&id=eq.${memoryId}`,
    (rows) => rows.length === 1 && rows[0].title === memoryTitle,
    'Coach memory survives direct authenticated update',
  );
  await assertRows(
    `coach_memory_selections?select=memory_id&user_id=eq.${userId}&memory_id=eq.${memoryId}`,
    (rows) => rows.length === 1,
    'Coach selection survives direct authenticated delete',
  );
}

async function assertCoachGuestBoundary() {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
  });
  await context.addInitScript(() => {
    localStorage.setItem('flutter.auth_guest_active', 'true');
    localStorage.setItem('flutter.auth_guest_onboarding_done', 'true');
    localStorage.setItem(
      'flutter.auth_guest_name',
      JSON.stringify('Phase 10 Guest'),
    );
  });
  const guestPage = await context.newPage();
  const coachRequests = [];
  guestPage.on('request', (request) => {
    if (request.url().includes('/v1/coach')) {
      coachRequests.push(`${request.method()} ${request.url()}`);
    }
  });
  try {
    await guestPage.goto(appRoute('/coach'), { waitUntil: 'domcontentloaded' });
    await waitForFlutterShell(guestPage);
    await enableFlutterSemantics(guestPage);
    await guestPage.waitForURL('**/#/coach');
    await expectText(guestPage, 'Coach unavailable');
    await expectText(
      guestPage,
      'No Coach provider is connected.',
    );
    await guestPage.waitForTimeout(500);
    if (coachRequests.length !== 0) {
      throw new Error(
        `Guest Coach surface contacted the authenticated API: ${JSON.stringify(coachRequests)}`,
      );
    }
  } finally {
    await context.close();
  }
}

async function assertDeterministicDailyBriefing(userId) {
  const accessToken = await signInAccessToken('Phase 4 briefing');
  let rowsBefore = await fetchRows(
    `daily_briefings?select=id&user_id=eq.${userId}`,
    'daily briefings before read-only GET',
  );
  // A separately running local notification scheduler may prepare this newly
  // onboarded isolated E2E account before the Phase 4 assertion gets here.
  // Remove only that test owner's rows, then retain the strict read-only check.
  if (rowsBefore.length > 0) {
    await deleteRows(
      `daily_briefings?user_id=eq.${userId}`,
      'concurrent scheduler briefings for the isolated E2E owner',
    );
    rowsBefore = await fetchRows(
      `daily_briefings?select=id&user_id=eq.${userId}`,
      'daily briefings after isolated scheduler cleanup',
    );
  }
  if (rowsBefore.length !== 0) {
    throw new Error(
      `Phase 4 precondition expected no briefing rows: ${JSON.stringify(rowsBefore)}`,
    );
  }

  const missing = await briefingRequest(
    '/v1/briefings/today',
    accessToken,
  );
  if (
    missing.contract_version !== 'daily-briefing-v1' ||
    missing.freshness !== 'missing' ||
    missing.needs_generation !== true ||
    missing.briefing !== null
  ) {
    throw new Error(
      `Read-only briefing GET did not report missing truth: ${JSON.stringify(missing)}`,
    );
  }
  await assertRows(
    `daily_briefings?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 0,
    'read-only briefing GET creates no row',
  );

  const profileRows = await fetchRows(
    `profiles?select=timezone&id=eq.${userId}`,
    'profile timezone for scheduled preparation',
  );
  if (
    profileRows.length !== 1 ||
    typeof profileRows[0].timezone !== 'string'
  ) {
    throw new Error(
      `Scheduled preparation profile timezone is unavailable: ${JSON.stringify(profileRows)}`,
    );
  }

  const snapshotPath =
    `user_state_snapshots?select=id,period_key,generated_at&user_id=eq.${userId}` +
    `&scope=eq.daily&period_key=eq.${missing.briefing_date}`;
  const snapshotsBeforePreparation = await fetchRows(
    snapshotPath,
    'daily snapshot before scheduled preparation',
  );
  if (snapshotsBeforePreparation.length > 1) {
    throw new Error(
      `Scheduled preparation found duplicate source snapshots: ${JSON.stringify(snapshotsBeforePreparation)}`,
    );
  }

  const scheduledPayload = {
    profile_ids: [userId],
    window_days: 7,
    limit: 1,
    include_recommendations: false,
  };
  const scheduled = await scheduledRefreshRequest(scheduledPayload);
  const scheduledResult = scheduled.results?.[0];
  const scheduledRunAtIsValid = isIsoTimestamp(scheduled.run_at);
  const expectedBriefingDate = scheduledRunAtIsValid
    ? isoDateInTimeZone(scheduled.run_at, profileRows[0].timezone)
    : null;
  if (
    !scheduledRunAtIsValid ||
    scheduled.target_date !== null ||
    scheduled.processed !== 1 ||
    scheduled.succeeded !== 1 ||
    scheduled.failed !== 0 ||
    scheduled.results?.length !== 1 ||
    scheduledResult?.user_id !== userId ||
    scheduledResult?.status !== 'succeeded' ||
    scheduledResult?.briefing_date !== expectedBriefingDate ||
    scheduledResult?.briefing_date !== missing.briefing_date ||
    scheduledResult?.period_key !== missing.briefing_date ||
    !['missing_snapshot', 'missing_briefing'].includes(
      scheduledResult?.selection_reason,
    ) ||
    !['generated', 'reused'].includes(scheduledResult?.snapshot_status) ||
    scheduledResult?.briefing_status !== 'generated' ||
    typeof scheduledResult?.snapshot_id !== 'string' ||
    typeof scheduledResult?.briefing_id !== 'string' ||
    scheduledResult?.recommendation_count !== null ||
    scheduledResult?.failed_stage !== null ||
    scheduledResult?.error !== null
  ) {
    throw new Error(
      `Scheduled daily preparation violated its bounded result contract: ${JSON.stringify(scheduled)}`,
    );
  }
  if (
    (snapshotsBeforePreparation.length === 0 &&
      (scheduledResult.selection_reason !== 'missing_snapshot' ||
        scheduledResult.snapshot_status !== 'generated')) ||
    (snapshotsBeforePreparation.length === 1 &&
      (scheduledResult.selection_reason !== 'missing_briefing' ||
        scheduledResult.snapshot_status !== 'reused' ||
        scheduledResult.snapshot_id !== snapshotsBeforePreparation[0].id))
  ) {
    throw new Error(
      `Scheduled preparation did not generate or reuse the exact snapshot prerequisite: ${JSON.stringify({ snapshotsBeforePreparation, scheduledResult })}`,
    );
  }

  const generated = await briefingRequest('/v1/briefings/today', accessToken);
  const briefing = generated.briefing;
  if (
    generated.contract_version !== 'daily-briefing-v1' ||
    generated.freshness !== 'current' ||
    generated.needs_generation !== false ||
    briefing?.mode !== 'recover' ||
    briefing?.provenance?.engine !== 'deterministic' ||
    briefing?.provenance?.llm_used !== false ||
    briefing?.provenance?.feedback_ranking?.contract_version !==
      'feedback-ranking-v1' ||
    briefing?.provenance?.feedback_ranking?.event_count !== 0 ||
    briefing?.capacity_minutes !== null ||
    !isExecutableBriefingAction(briefing?.primary_action) ||
    !Array.isArray(briefing?.support_actions) ||
    briefing.support_actions.length > 2 ||
    !briefing.support_actions.every(isExecutableBriefingAction)
  ) {
    throw new Error(
      `Generated Phase 4 briefing violates its contract: ${JSON.stringify(generated)}`,
    );
  }

  const snapshotsAfterPreparation = await fetchRows(
    snapshotPath,
    'daily snapshot after scheduled preparation',
  );
  if (
    snapshotsAfterPreparation.length !== 1 ||
    snapshotsAfterPreparation[0].id !== scheduledResult.snapshot_id ||
    (snapshotsBeforePreparation.length === 1 &&
      snapshotsAfterPreparation[0].generated_at !==
        snapshotsBeforePreparation[0].generated_at) ||
    scheduledResult.briefing_id !== briefing.id ||
    generated.briefing_date !== missing.briefing_date ||
    briefing.briefing_date !== missing.briefing_date
  ) {
    throw new Error(
      `Scheduled preparation did not preserve the exact local snapshot/briefing identity: ${JSON.stringify({ scheduledResult, snapshotsBeforePreparation, snapshotsAfterPreparation, generated })}`,
    );
  }

  const persisted = await fetchRows(
    `daily_briefings?select=id,briefing_date,mode,capacity_minutes,primary_action,support_actions,evidence_refs,provenance,data_quality,metadata,generated_at,updated_at&user_id=eq.${userId}`,
    'persisted deterministic daily briefing',
  );
  if (
    persisted.length !== 1 ||
    persisted[0].id !== briefing.id ||
    persisted[0].briefing_date !== generated.briefing_date ||
    persisted[0].mode !== briefing.mode ||
    persisted[0].capacity_minutes !== null ||
    persisted[0].metadata?.contract_version !== 'daily-briefing-v1' ||
    persisted[0].metadata?.ranking_version !==
      'deterministic-briefing-ranker-v2' ||
    persisted[0].provenance?.engine !== 'deterministic' ||
    persisted[0].provenance?.llm_used !== false ||
    persisted[0].provenance?.source_snapshot_id !==
      briefing.provenance.source_snapshot_id ||
    persisted[0].provenance?.source_snapshot_id !== scheduledResult.snapshot_id ||
    Date.parse(persisted[0].provenance?.source_snapshot_generated_at) !==
      Date.parse(snapshotsAfterPreparation[0].generated_at) ||
    stableJson(persisted[0].primary_action) !==
      stableJson(briefing.primary_action) ||
    stableJson(persisted[0].support_actions) !==
      stableJson(briefing.support_actions)
  ) {
    throw new Error(
      `Persisted Phase 4 briefing does not match its response: ${JSON.stringify(persisted)}`,
    );
  }

  const repeatedScheduled = await scheduledRefreshRequest(scheduledPayload);
  const repeated = await briefingRequest('/v1/briefings/today', accessToken);
  if (
    !isIsoTimestamp(repeatedScheduled.run_at) ||
    repeatedScheduled.target_date !== null ||
    repeatedScheduled.processed !== 0 ||
    repeatedScheduled.succeeded !== 0 ||
    repeatedScheduled.failed !== 0 ||
    repeatedScheduled.results?.length !== 0 ||
    repeated.briefing?.id !== briefing.id ||
    repeated.briefing?.generated_at !== briefing.generated_at ||
    repeated.briefing?.updated_at !== briefing.updated_at
  ) {
    throw new Error(
      `Idempotent Phase 4 generation changed the current row: ${JSON.stringify(repeated)}`,
    );
  }
  const snapshotsAfterRetry = await fetchRows(
    snapshotPath,
    'daily snapshot after scheduled retry',
  );
  await assertRows(
    `daily_briefings?select=id,generated_at,updated_at&user_id=eq.${userId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === briefing.id &&
      rows[0].generated_at === persisted[0].generated_at &&
      rows[0].updated_at === persisted[0].updated_at &&
      snapshotsAfterRetry.length === 1 &&
      snapshotsAfterRetry[0].id === snapshotsAfterPreparation[0].id &&
      snapshotsAfterRetry[0].generated_at ===
        snapshotsAfterPreparation[0].generated_at,
    'idempotent scheduled preparation preserves snapshot and briefing identity',
  );
  return generated;
}

async function assertCentralPlanner(page, userId) {
  const accessToken = await signInAccessToken('Planner V1');
  if ((await authenticatedUserId(accessToken)) !== userId) {
    throw new Error('Planner bearer resolved a different owner.');
  }
  const initial = await plannerApiRequest('/v1/planner/overview', accessToken);
  assertPlannerApiStatus(initial, 200, 'initial Planner overview');
  if (
    initial.json?.contract_version !== 'planner-v1' ||
    initial.json?.origin !== 'authenticated_backend' ||
    !isIsoTimestamp(initial.json?.generated_at) ||
    !Array.isArray(initial.json?.days) ||
    initial.json.days.length !== 7 ||
    initial.json?.preferences?.contract_version !== 'planner-preferences-v1'
  ) {
    throw new Error(`Initial Planner overview is invalid: ${initial.text}`);
  }
  const localDate = initial.json.local_date;
  const taskPlanId = crypto.randomUUID();
  const taskId = crypto.randomUUID();
  const taskProposal = await plannerApiRequest(
    '/v1/planner/action-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: taskPlanId,
        base_revision: 0,
        planning_start_on: localDate,
        target: {
          kind: 'task',
          operation: 'create',
          target_id: taskId,
          expected_updated_at: null,
          title: plannerTaskTitle,
          description: null,
          priority: 'high',
          estimated_minutes: 65,
          deadline_at: `${addUtcDays(localDate, 6)}T12:00:00Z`,
          preferred_session_minutes: 30,
        },
      },
    },
  );
  assertPlannerApiStatus(taskProposal, 200, 'split Task Planner proposal');
  const taskPreview = taskProposal.json?.plan?.pending_revision;
  if (
    taskPreview?.target?.title !== plannerTaskTitle ||
    taskPreview?.planned_minutes + taskPreview?.unscheduled_minutes !== 65 ||
    !Array.isArray(taskPreview?.task_blocks) ||
    taskPreview.task_blocks.length < 2 ||
    taskPreview.task_blocks.some(
      (block) =>
        block.state !== 'proposed' ||
        block.planned_minutes % 5 !== 0,
    )
  ) {
    throw new Error(`Split Task preview is invalid: ${taskProposal.text}`);
  }
  const taskConfirmed = await plannerApiRequest(
    `/v1/planner/action-plans/${taskPlanId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: crypto.randomUUID(), expected_revision: 1 },
    },
  );
  assertPlannerApiStatus(taskConfirmed, 200, 'split Task Planner confirm');
  if (
    taskConfirmed.json?.plan?.status !== 'active' ||
    taskConfirmed.json?.plan?.active_revision?.task_blocks?.some(
      (block) => block.state !== 'active',
    )
  ) {
    throw new Error(`Split Task confirmation is invalid: ${taskConfirmed.text}`);
  }

  const habitDate = addUtcDays(localDate, 1);
  const habitIsoWeekday = (() => {
    const day = new Date(`${habitDate}T00:00:00Z`).getUTCDay();
    return day === 0 ? 7 : day;
  })();
  const habitPlanId = crypto.randomUUID();
  const habitId = crypto.randomUUID();
  const habitProposal = await plannerApiRequest(
    '/v1/planner/action-plans/proposals',
    accessToken,
    {
      method: 'POST',
      body: {
        request_id: crypto.randomUUID(),
        plan_id: habitPlanId,
        base_revision: 0,
        planning_start_on: localDate,
        target: {
          kind: 'habit',
          operation: 'create',
          target_id: habitId,
          expected_updated_at: null,
          title: plannerHabitTitle,
          description: null,
          cadence: {
            kind: 'weekdays',
            scheduled_weekdays: [habitIsoWeekday],
            weekly_target: 1,
          },
          duration_minutes: 20,
        },
      },
    },
  );
  assertPlannerApiStatus(habitProposal, 200, 'Habit Planner proposal');
  const habitPreview = habitProposal.json?.plan?.pending_revision;
  if (
    habitPreview?.target?.title !== plannerHabitTitle ||
    !Array.isArray(habitPreview?.habit_slots) ||
    habitPreview.habit_slots.length !== 1 ||
    habitPreview.planned_minutes !== 20 ||
    habitPreview.unscheduled_minutes !== 0
  ) {
    throw new Error(`Habit preview is invalid: ${habitProposal.text}`);
  }
  const habitConfirmed = await plannerApiRequest(
    `/v1/planner/action-plans/${habitPlanId}/confirm`,
    accessToken,
    {
      method: 'POST',
      body: { request_id: crypto.randomUUID(), expected_revision: 1 },
    },
  );
  assertPlannerApiStatus(habitConfirmed, 200, 'Habit Planner confirm');
  if (habitConfirmed.json?.plan?.status !== 'active') {
    throw new Error(`Habit confirmation is invalid: ${habitConfirmed.text}`);
  }

  const oneOffId = crypto.randomUUID();
  const oneOff = await plannerApiRequest('/v1/planner/commitments', accessToken, {
    method: 'POST',
    body: {
      request_id: crypto.randomUUID(),
      commitment_id: oneOffId,
      title: plannerOneOffTitle,
      location: null,
      recurrence: 'one_off',
      starts_at: `${localDate}T12:00:00Z`,
      ends_at: `${localDate}T13:00:00Z`,
      weekday: null,
      local_starts_at: null,
      local_ends_at: null,
    },
  });
  assertPlannerApiStatus(oneOff, 200, 'one-time Planner commitment');

  const weeklyId = crypto.randomUUID();
  const weeklyDate = addUtcDays(localDate, 2);
  const weeklyJsDay = new Date(`${weeklyDate}T00:00:00Z`).getUTCDay();
  const weeklyWeekday = weeklyJsDay === 0 ? 7 : weeklyJsDay;
  const weekly = await plannerApiRequest('/v1/planner/commitments', accessToken, {
    method: 'POST',
    body: {
      request_id: crypto.randomUUID(),
      commitment_id: weeklyId,
      title: plannerWeeklyTitle,
      location: null,
      recurrence: 'weekly',
      starts_at: null,
      ends_at: null,
      weekday: weeklyWeekday,
      local_starts_at: '21:00:00',
      local_ends_at: '22:00:00',
    },
  });
  assertPlannerApiStatus(weekly, 200, 'weekly Planner commitment');

  const overview = await plannerApiRequest('/v1/planner/overview', accessToken);
  assertPlannerApiStatus(overview, 200, 'populated Planner overview');
  const activePlans = overview.json?.action_plans ?? [];
  const commitments = overview.json?.commitments ?? [];
  if (
    !activePlans.some(
      (plan) => plan.id === taskPlanId && plan.status === 'active',
    ) ||
    !activePlans.some(
      (plan) => plan.id === habitPlanId && plan.status === 'active',
    ) ||
    !commitments.some(
      (item) => item.id === oneOffId && item.recurrence === 'one_off',
    ) ||
    !commitments.some(
      (item) => item.id === weeklyId && item.recurrence === 'weekly',
    )
  ) {
    throw new Error(`Populated Planner overview lost state: ${overview.text}`);
  }

  await page.goto(appRoute('/planner'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Add new');
  await expectText(page, 'Needs attention');
  await assertFlutterTextAbsent(page, 'Inbox', 'Inbox main navigation target');
  for (const title of [
    plannerTaskTitle,
    plannerHabitTitle,
    plannerOneOffTitle,
    plannerWeeklyTitle,
  ]) {
    await scrollFlutterPage(page, -20000);
    await scrollUntilTextInViewport(page, title, {
      deltaY: 250,
      maxSteps: 50,
      precise: true,
    });
  }

  const today = await plannerApiRequest('/v1/today/overview-v2', accessToken);
  assertPlannerApiStatus(today, 200, 'Today V2 after Planner confirmation');
  if (
    today.json?.contract_version !== 'today-overview-v2' ||
    today.json?.source_states?.planner?.status !== 'current' ||
    !today.json?.timeline?.some(
      (item) =>
        item.kind === 'manual_commitment' && item.title === plannerOneOffTitle,
    )
  ) {
    throw new Error(`Today V2 lost Planner agenda truth: ${today.text}`);
  }
  const todayTaskBlocks = today.json.timeline.filter(
    (item) => item.kind === 'task_block' && item.task_id === taskId,
  );
  const todayTask = today.json.tasks?.all?.find((item) => item.id === taskId);
  if (todayTaskBlocks.length > 0 && todayTask?.scheduled_today !== true) {
    throw new Error('Today V2 did not select its scheduled Planner Task once.');
  }

  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await scrollFlutterPage(page, -20000);
  await scrollUntilTextInViewport(page, plannerOneOffTitle, {
    deltaY: 250,
    maxSteps: 40,
    precise: true,
  });
  await page.goto(appRoute('/settings'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Inbox');
  await clickByText(page, 'Inbox');
  await page.waitForURL('**/#/alerts');
  await expectText(page, 'Inbox');
}

async function assertTodayOverview(userId) {
  const accessToken = await signInAccessToken('Today overview');
  if ((await authenticatedUserId(accessToken)) !== userId) {
    throw new Error('Today overview bearer resolved a different owner.');
  }
  const overview = await briefingRequest('/v1/today/overview', accessToken);
  const sourceNames = [
    'check_ins',
    'tasks',
    'habits',
    'setup_commitments',
    'preparation',
    'calendar_events',
    'focus_sessions',
  ];
  if (
    overview.contract_version !== 'today-overview-v1' ||
    overview.origin !== 'authenticated_backend' ||
    !isIsoTimestamp(overview.generated_at) ||
    overview.local_date !==
      isoDateInTimeZone(overview.generated_at, overview.timezone) ||
    typeof overview.check_ins?.morning_saved !== 'boolean' ||
    typeof overview.check_ins?.evening_saved !== 'boolean' ||
    !Number.isInteger(overview.check_ins?.completed_days_streak) ||
    overview.check_ins.completed_days_streak < 0 ||
    !Array.isArray(overview.timeline) ||
    !Array.isArray(overview.tasks?.today) ||
    !Array.isArray(overview.tasks?.all) ||
    !Array.isArray(overview.habits) ||
    !Array.isArray(overview.progress_unavailable_sources) ||
    sourceNames.some(
      (name) =>
        !['current', 'unavailable'].includes(
          overview.source_states?.[name]?.status,
        ),
    )
  ) {
    throw new Error(
      `Today overview violates its source contract: ${JSON.stringify(overview)}`,
    );
  }
  const allTaskIds = new Set(overview.tasks.all.map((task) => task.id));
  if (overview.tasks.today.some((task) => !allTaskIds.has(task.id))) {
    throw new Error('Today tasks are missing from the all-task projection.');
  }
  const overviewV2 = await briefingRequest(
    '/v1/today/overview-v2',
    accessToken,
  );
  const v2SourceNames = [...sourceNames, 'planner'];
  if (
    overviewV2.contract_version !== 'today-overview-v2' ||
    overviewV2.origin !== 'authenticated_backend' ||
    overviewV2.local_date !== overview.local_date ||
    !Array.isArray(overviewV2.timeline) ||
    !Array.isArray(overviewV2.tasks?.today) ||
    !Array.isArray(overviewV2.tasks?.all) ||
    !Array.isArray(overviewV2.habits) ||
    v2SourceNames.some(
      (name) =>
        !['current', 'unavailable'].includes(
          overviewV2.source_states?.[name]?.status,
        ),
    )
  ) {
    throw new Error(
      `Today V2 overview violates its source contract: ${JSON.stringify(overviewV2)}`,
    );
  }
  const scheduledTaskIds = overviewV2.timeline
    .filter((item) => item.kind === 'task_block')
    .map((item) => item.task_id)
    .sort();
  const flaggedTaskIds = overviewV2.tasks.all
    .filter((task) => task.scheduled_today)
    .map((task) => task.id)
    .sort();
  const scheduledHabitIds = overviewV2.timeline
    .filter((item) => item.kind === 'habit_slot')
    .map((item) => item.habit_id)
    .sort();
  const flaggedHabitIds = overviewV2.habits
    .filter((habit) => habit.scheduled_today)
    .map((habit) => habit.id)
    .sort();
  if (
    stableJson([...new Set(scheduledTaskIds)]) !== stableJson(flaggedTaskIds) ||
    stableJson([...new Set(scheduledHabitIds)]) !== stableJson(flaggedHabitIds)
  ) {
    throw new Error('Today V2 scheduled target flags do not match its agenda.');
  }
  const unavailable = ['check_ins', 'tasks', 'habits', 'preparation'].filter(
    (name) => overview.source_states[name].status === 'unavailable',
  );
  if (stableJson(unavailable) !== stableJson(overview.progress_unavailable_sources)) {
    throw new Error('Today progress source availability is inconsistent.');
  }
  if (unavailable.length > 0) {
    if (overview.progress !== null) {
      throw new Error('Today progress must be unavailable with a failed source.');
    }
    return;
  }
  const preparation = overview.timeline.filter(
    (item) => item.kind === 'preparation',
  );
  const expectedTotal =
    2 + overview.tasks.today.length + overview.habits.length + preparation.length;
  const expectedCompleted =
    Number(overview.check_ins.morning_saved) +
    Number(overview.check_ins.evening_saved) +
    overview.tasks.today.filter((task) => task.status === 'done').length +
    overview.habits.filter((habit) => habit.outcome === 'completed').length +
    preparation.filter((block) => block.state === 'completed').length;
  if (
    overview.progress?.total !== expectedTotal ||
    overview.progress?.completed !== expectedCompleted
  ) {
    throw new Error(
      `Today progress arithmetic is inconsistent: ${JSON.stringify(overview.progress)}`,
    );
  }
}

async function signInAccessToken(context) {
  const response = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        apikey: supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    },
  );
  if (!response.ok) {
    throw new Error(
      `${context} sign-in failed: ${response.status} ${await response.text()}`,
    );
  }
  const accessToken = (await response.json()).access_token;
  if (typeof accessToken !== 'string' || accessToken.length === 0) {
    throw new Error(`${context} sign-in returned no access token.`);
  }
  return accessToken;
}

async function authenticatedUserId(accessToken) {
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${accessToken}`,
    },
  });
  if (!response.ok) {
    throw new Error(
      `Focused Phase 10 user lookup failed: ${response.status} ${await response.text()}`,
    );
  }
  const id = (await response.json()).id;
  if (!isCanonicalUuid(id)) {
    throw new Error('Focused Phase 10 user lookup returned no valid user id.');
  }
  return id;
}

async function resetCoachE2EState(userId) {
  await deleteRows(
    `coach_memory_selections?user_id=eq.${userId}`,
    'focused Phase 10 memory selections',
  );
  await deleteRows(
    `coach_requests?user_id=eq.${userId}`,
    'focused Phase 10 request history',
  );
  await deleteRows(
    `memory_entries?user_id=eq.${userId}&title=eq.${encodeURIComponent(coachMemoryTitle)}`,
    'focused Phase 10 synthetic memories',
  );
}

async function briefingRequest(path, accessToken, body) {
  const response = await fetch(`${aiServiceBaseUrl}${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (!response.ok) {
    throw new Error(
      `Briefing request ${path} failed: ${response.status} ${await response.text()}`,
    );
  }
  return response.json();
}

async function deadlinePlanApiRequest(
  path,
  accessToken,
  { method = 'GET', body } = {},
) {
  const response = await fetch(`${aiServiceBaseUrl}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text.length === 0 ? null : JSON.parse(text);
  } catch (_) {
    // The status assertion reports the raw response body.
  }
  return { response, text, json };
}

async function plannerApiRequest(
  path,
  accessToken,
  { method = 'GET', body } = {},
) {
  const response = await fetch(`${aiServiceBaseUrl}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text.length === 0 ? null : JSON.parse(text);
  } catch (_) {
    // The status assertion reports the raw response body.
  }
  return { response, text, json };
}

function assertPlannerApiStatus(result, expectedStatus, context) {
  if (result.response.status !== expectedStatus) {
    throw new Error(
      `${context} returned ${result.response.status}, expected ${expectedStatus}: ${result.text}`,
    );
  }
}

function assertDeadlinePlanApiStatus(result, expectedStatus, context) {
  if (result.response.status !== expectedStatus) {
    throw new Error(
      `${context} returned ${result.response.status}, expected ${expectedStatus}: ${result.text}`,
    );
  }
}

function assertPreparationWorkload(payload, { budget, context }) {
  assertExactDeadlineKeys(
    payload,
    [
      'contract_version',
      'origin',
      'generated_at',
      'timezone',
      'daily_preparation_budget_minutes',
      'days',
    ],
    context,
  );
  if (
    payload.contract_version !== 'preparation-workload-v1' ||
    payload.origin !== 'authenticated_backend' ||
    !isIsoTimestamp(payload.generated_at) ||
    typeof payload.timezone !== 'string' ||
    payload.daily_preparation_budget_minutes !== budget ||
    !Array.isArray(payload.days) ||
    payload.days.length !== 7
  ) {
    throw new Error(
      `${context} has invalid workload provenance or bounds: ${stableJson(payload)}`,
    );
  }
  for (const [index, day] of payload.days.entries()) {
    assertExactDeadlineKeys(
      day,
      [
        'local_date',
        'reserved_preparation_minutes',
        'remaining_budget_minutes',
        'over_budget_minutes',
        'active_plan_count',
        'fixed_commitment_minutes',
      ],
      `${context} day ${index + 1}`,
    );
    const previous = payload.days[index - 1];
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(day.local_date) ||
      (previous &&
        Date.parse(`${day.local_date}T00:00:00Z`) -
          Date.parse(`${previous.local_date}T00:00:00Z`) !==
          86_400_000) ||
      !Number.isInteger(day.reserved_preparation_minutes) ||
      day.reserved_preparation_minutes < 0 ||
      !Number.isInteger(day.over_budget_minutes) ||
      !Number.isInteger(day.active_plan_count) ||
      !Number.isInteger(day.fixed_commitment_minutes) ||
      (budget === null
        ? day.remaining_budget_minutes !== null ||
          day.over_budget_minutes !== 0
        : day.remaining_budget_minutes !==
            Math.max(0, budget - day.reserved_preparation_minutes) ||
          day.over_budget_minutes !==
            Math.max(0, day.reserved_preparation_minutes - budget))
    ) {
      throw new Error(
        `${context} day ${index + 1} is inconsistent: ${stableJson(day)}`,
      );
    }
  }
  return payload;
}

function assertPreparationWorkloadDetail(
  payload,
  { budget, localDate, context },
) {
  assertExactDeadlineKeys(
    payload,
    [
      'contract_version',
      'origin',
      'generated_at',
      'timezone',
      'local_date',
      'daily_preparation_budget_minutes',
      'reserved_preparation_minutes',
      'remaining_budget_minutes',
      'over_budget_minutes',
      'contributions',
    ],
    context,
  );
  if (
    payload.contract_version !== 'preparation-workload-detail-v1' ||
    payload.origin !== 'authenticated_backend' ||
    !isIsoTimestamp(payload.generated_at) ||
    typeof payload.timezone !== 'string' ||
    payload.local_date !== localDate ||
    payload.daily_preparation_budget_minutes !== budget ||
    !Number.isInteger(payload.reserved_preparation_minutes) ||
    payload.reserved_preparation_minutes < 0 ||
    !Number.isInteger(payload.over_budget_minutes) ||
    payload.over_budget_minutes < 0 ||
    !Array.isArray(payload.contributions) ||
    payload.contributions.length > 50 ||
    (budget === null
      ? payload.remaining_budget_minutes !== null ||
        payload.over_budget_minutes !== 0
      : payload.remaining_budget_minutes !==
          Math.max(0, budget - payload.reserved_preparation_minutes) ||
        payload.over_budget_minutes !==
          Math.max(0, payload.reserved_preparation_minutes - budget))
  ) {
    throw new Error(
      `${context} has invalid detail provenance or arithmetic: ${stableJson(payload)}`,
    );
  }
  const planIds = new Set();
  let contributionTotal = 0;
  for (const [index, contribution] of payload.contributions.entries()) {
    assertExactDeadlineKeys(
      contribution,
      [
        'plan_id',
        'title',
        'reserved_preparation_minutes',
        'block_count',
      ],
      `${context} contribution ${index + 1}`,
    );
    if (
      !isCanonicalUuid(contribution.plan_id) ||
      planIds.has(contribution.plan_id) ||
      typeof contribution.title !== 'string' ||
      contribution.title.trim() !== contribution.title ||
      [...contribution.title].length < 1 ||
      [...contribution.title].length > 160 ||
      !Number.isInteger(contribution.reserved_preparation_minutes) ||
      contribution.reserved_preparation_minutes < 5 ||
      contribution.reserved_preparation_minutes > 480 ||
      !Number.isInteger(contribution.block_count) ||
      contribution.block_count < 1 ||
      contribution.block_count > 120
    ) {
      throw new Error(
        `${context} contribution ${index + 1} is invalid: ${stableJson(contribution)}`,
      );
    }
    planIds.add(contribution.plan_id);
    contributionTotal += contribution.reserved_preparation_minutes;
  }
  if (contributionTotal !== payload.reserved_preparation_minutes) {
    throw new Error(
      `${context} contribution total is inconsistent: ${stableJson(payload)}`,
    );
  }
  return payload;
}

function assertDeadlinePlanCollection(payload, context) {
  assertExactDeadlineKeys(
    payload,
    ['contract_version', 'origin', 'plans'],
    context,
  );
  if (
    payload.contract_version !== 'deadline-plan-v1' ||
    payload.origin !== 'authenticated_backend' ||
    !Array.isArray(payload.plans) ||
    payload.plans.length > 50
  ) {
    throw new Error(
      `${context} has invalid Deadline Planner provenance or bounds: ${stableJson(payload)}`,
    );
  }
  const ids = new Set();
  for (const [index, detail] of payload.plans.entries()) {
    const parsed = assertDeadlinePlanDetail(
      detail,
      `${context} plan ${index + 1}`,
    );
    if (ids.has(parsed.plan.id)) {
      throw new Error(`${context} contains duplicate plan identities.`);
    }
    ids.add(parsed.plan.id);
  }
  return payload;
}

function assertDeadlinePlanEnvelope(payload, context) {
  if (
    payload === null ||
    typeof payload !== 'object' ||
    Array.isArray(payload)
  ) {
    throw new Error(`${context} did not return a Deadline Planner object.`);
  }
  const detail = { ...payload };
  delete detail.contract_version;
  delete detail.origin;
  if (
    payload.contract_version !== 'deadline-plan-v1' ||
    payload.origin !== 'authenticated_backend'
  ) {
    throw new Error(
      `${context} has invalid Deadline Planner provenance: ${stableJson(payload)}`,
    );
  }
  assertDeadlinePlanDetail(detail, context);
  assertExactDeadlineKeys(
    payload,
    ['contract_version', 'origin', ...Object.keys(detail)],
    context,
  );
  return payload;
}

function assertDeadlinePlanDetail(detail, context) {
  const keys = ['plan', 'progress'];
  for (const optional of ['active_revision', 'pending_revision']) {
    if (Object.hasOwn(detail ?? {}, optional)) keys.push(optional);
  }
  assertExactDeadlineKeys(detail, keys, context);
  if (
    ['active_revision', 'pending_revision'].some(
      (key) => Object.hasOwn(detail, key) && detail[key] === null,
    )
  ) {
    throw new Error(`${context} returned an explicit-null optional revision.`);
  }
  const plan = assertDeadlinePlanIdentity(detail.plan, `${context} identity`);
  const active = Object.hasOwn(detail, 'active_revision')
    ? assertDeadlinePlanRevision(
        detail.active_revision,
        `${context} active revision`,
      )
    : null;
  const pending = Object.hasOwn(detail, 'pending_revision')
    ? assertDeadlinePlanRevision(
        detail.pending_revision,
        `${context} pending revision`,
      )
    : null;
  const progress = assertDeadlinePlanProgress(
    detail.progress,
    `${context} progress`,
  );
  if (
    (plan.status === 'draft' && (active !== null || pending === null)) ||
    (['active', 'completed'].includes(plan.status) && active === null) ||
    (plan.status === 'cancelled' &&
      ((plan.current_revision === 0 &&
        (active !== null || pending !== null)) ||
        (plan.current_revision > 0 && active === null))) ||
    (active !== null &&
      (active.plan_id !== plan.id ||
        active.revision !== plan.current_revision ||
        active.state !== 'active')) ||
    (pending !== null &&
      (pending.plan_id !== plan.id ||
        pending.revision !== plan.latest_revision ||
        pending.state !== 'proposed')) ||
    (pending !== null && pending.revision <= plan.current_revision) ||
    (pending === null &&
      plan.latest_revision !== plan.current_revision &&
      !(plan.status === 'cancelled' && plan.current_revision === 0)) ||
    (plan.status === 'draft' && plan.current_revision !== 0)
  ) {
    throw new Error(`${context} has inconsistent revision projections.`);
  }
  return { plan, active_revision: active, pending_revision: pending, progress };
}

function assertDeadlinePlanIdentity(plan, context) {
  const keys = [
    'id',
    'status',
    'kind',
    'title',
    'original_estimated_total_minutes',
    'original_credited_prior_minutes',
    'current_revision',
    'latest_revision',
    'created_at',
    'updated_at',
  ];
  for (const optional of [
    'managed_task_id',
    'completed_at',
    'cancelled_at',
  ]) {
    if (Object.hasOwn(plan ?? {}, optional)) keys.push(optional);
  }
  assertExactDeadlineKeys(plan, keys, context);
  if (
    ['managed_task_id', 'completed_at', 'cancelled_at'].some(
      (key) => Object.hasOwn(plan, key) && plan[key] === null,
    ) ||
    !isCanonicalUuid(plan.id) ||
    !['draft', 'active', 'completed', 'cancelled'].includes(plan.status) ||
    !['exam', 'assignment'].includes(plan.kind) ||
    typeof plan.title !== 'string' ||
    plan.title.trim() !== plan.title ||
    [...plan.title].length < 1 ||
    [...plan.title].length > 160 ||
    !Number.isInteger(plan.original_estimated_total_minutes) ||
    plan.original_estimated_total_minutes < 30 ||
    plan.original_estimated_total_minutes > 30000 ||
    !Number.isInteger(plan.original_credited_prior_minutes) ||
    plan.original_credited_prior_minutes < 0 ||
    plan.original_credited_prior_minutes >=
      plan.original_estimated_total_minutes ||
    !Number.isInteger(plan.current_revision) ||
    plan.current_revision < 0 ||
    !Number.isInteger(plan.latest_revision) ||
    plan.latest_revision < 1 ||
    plan.latest_revision < Math.max(1, plan.current_revision) ||
    !isIsoTimestamp(plan.created_at) ||
    !isIsoTimestamp(plan.updated_at) ||
    Date.parse(plan.updated_at) < Date.parse(plan.created_at) ||
    (plan.current_revision === 0) !==
      !Object.hasOwn(plan, 'managed_task_id') ||
    (Object.hasOwn(plan, 'managed_task_id') &&
      plan.managed_task_id !== plan.id)
  ) {
    throw new Error(`${context} is invalid: ${stableJson(plan)}`);
  }
  if (
    (plan.status === 'completed' &&
      (!isIsoTimestamp(plan.completed_at) ||
        Object.hasOwn(plan, 'cancelled_at'))) ||
    (plan.status === 'cancelled' &&
      (!isIsoTimestamp(plan.cancelled_at) ||
        Object.hasOwn(plan, 'completed_at'))) ||
    (['draft', 'active'].includes(plan.status) &&
      (Object.hasOwn(plan, 'completed_at') ||
        Object.hasOwn(plan, 'cancelled_at')))
  ) {
    throw new Error(`${context} has an invalid terminal lifecycle.`);
  }
  return plan;
}

function assertDeadlinePlanRevision(revision, context) {
  const keys = [
    'plan_id',
    'revision',
    'base_revision',
    'state',
    'kind',
    'title',
    'deadline_at',
    'estimated_total_minutes',
    'credited_prior_minutes',
    'preferred_session_minutes',
    'max_daily_minutes',
    'planning_start_on',
    'buffer_days',
    'source_kind',
    'source_status',
    'use_calendar_availability',
    'timezone',
    'best_energy_window',
    'planning_fingerprint',
    'recovery_minutes',
    'tracked_focus_minutes_at_proposal',
    'remaining_minutes_at_proposal',
    'planned_minutes',
    'unscheduled_minutes',
    'created_at',
    'blocks',
  ];
  for (const optional of [
    'source_calendar_event_id',
    'source_calendar_event_fingerprint',
    'availability_connection_id',
    'availability_import_id',
    'study_setup_revision',
    'activated_at',
    'superseded_at',
  ]) {
    if (Object.hasOwn(revision ?? {}, optional)) keys.push(optional);
  }
  assertExactDeadlineKeys(revision, keys, context);
  if (
    [
      'source_calendar_event_id',
      'source_calendar_event_fingerprint',
      'availability_connection_id',
      'availability_import_id',
      'study_setup_revision',
      'activated_at',
      'superseded_at',
    ].some((key) => Object.hasOwn(revision, key) && revision[key] === null) ||
    !isCanonicalUuid(revision.plan_id) ||
    !Number.isInteger(revision.revision) ||
    revision.revision < 1 ||
    !Number.isInteger(revision.base_revision) ||
    revision.base_revision < 0 ||
    revision.base_revision >= revision.revision ||
    !['proposed', 'active', 'superseded'].includes(revision.state) ||
    !['exam', 'assignment'].includes(revision.kind) ||
    typeof revision.title !== 'string' ||
    revision.title.trim() !== revision.title ||
    [...revision.title].length < 1 ||
    [...revision.title].length > 160 ||
    !isIsoTimestamp(revision.deadline_at) ||
    !Number.isInteger(revision.estimated_total_minutes) ||
    revision.estimated_total_minutes < 30 ||
    revision.estimated_total_minutes > 30000 ||
    !Number.isInteger(revision.credited_prior_minutes) ||
    revision.credited_prior_minutes < 0 ||
    revision.credited_prior_minutes >= revision.estimated_total_minutes ||
    !Number.isInteger(revision.preferred_session_minutes) ||
    revision.preferred_session_minutes < 25 ||
    revision.preferred_session_minutes > 180 ||
    !Number.isInteger(revision.max_daily_minutes) ||
    revision.max_daily_minutes < revision.preferred_session_minutes ||
    revision.max_daily_minutes > 480 ||
    !isCalendarDate(revision.planning_start_on) ||
    !Number.isInteger(revision.buffer_days) ||
    revision.buffer_days < 0 ||
    revision.buffer_days > 7 ||
    !['manual', 'calendar_event'].includes(revision.source_kind) ||
    !['not_applicable', 'current', 'stale', 'unavailable'].includes(
      revision.source_status,
    ) ||
    typeof revision.use_calendar_availability !== 'boolean' ||
    typeof revision.timezone !== 'string' ||
    revision.timezone.trim() !== revision.timezone ||
    revision.timezone.length < 1 ||
    revision.timezone.length > 100 ||
    ![
      'early_morning',
      'morning',
      'afternoon',
      'evening',
      'variable',
    ].includes(revision.best_energy_window) ||
    !/^[0-9a-f]{64}$/.test(revision.planning_fingerprint ?? '') ||
    !Number.isInteger(revision.recovery_minutes) ||
    revision.recovery_minutes < 0 ||
    revision.recovery_minutes > 60 ||
    revision.recovery_minutes % 5 !== 0 ||
    (Object.hasOwn(revision, 'study_setup_revision') &&
      (!Number.isInteger(revision.study_setup_revision) ||
        revision.study_setup_revision < 1)) ||
    (!Object.hasOwn(revision, 'study_setup_revision') &&
      revision.recovery_minutes !== 0) ||
    !Number.isInteger(revision.tracked_focus_minutes_at_proposal) ||
    revision.tracked_focus_minutes_at_proposal < 0 ||
    !Number.isInteger(revision.remaining_minutes_at_proposal) ||
    revision.remaining_minutes_at_proposal < 0 ||
    !Number.isInteger(revision.planned_minutes) ||
    revision.planned_minutes < 0 ||
    !Number.isInteger(revision.unscheduled_minutes) ||
    revision.unscheduled_minutes < 0 ||
    !isIsoTimestamp(revision.created_at) ||
    !Array.isArray(revision.blocks) ||
    revision.blocks.length > 120
  ) {
    throw new Error(`${context} is invalid: ${stableJson(revision)}`);
  }
  const expectedRemaining = Math.max(
    0,
    revision.estimated_total_minutes -
      revision.credited_prior_minutes -
      revision.tracked_focus_minutes_at_proposal,
  );
  if (
    revision.remaining_minutes_at_proposal !== expectedRemaining ||
    revision.planned_minutes + revision.unscheduled_minutes !==
      expectedRemaining
  ) {
    throw new Error(`${context} has inconsistent proposal-time minutes.`);
  }
  if (
    (revision.source_kind === 'manual' &&
      (revision.source_status !== 'not_applicable' ||
        Object.hasOwn(revision, 'source_calendar_event_id') ||
        Object.hasOwn(revision, 'source_calendar_event_fingerprint'))) ||
    (revision.source_kind === 'calendar_event' &&
      (!isCanonicalUuid(revision.source_calendar_event_id) ||
        !/^[0-9a-f]{64}$/.test(
          revision.source_calendar_event_fingerprint ?? '',
        ) ||
        revision.source_status === 'not_applicable'))
  ) {
    throw new Error(`${context} has invalid source provenance.`);
  }
  const hasAvailabilityConnection = Object.hasOwn(
    revision,
    'availability_connection_id',
  );
  const hasAvailabilityImport = Object.hasOwn(
    revision,
    'availability_import_id',
  );
  if (
    hasAvailabilityConnection !== hasAvailabilityImport ||
    revision.use_calendar_availability !== hasAvailabilityConnection ||
    (hasAvailabilityConnection &&
      (!isCanonicalUuid(revision.availability_connection_id) ||
        !isCanonicalUuid(revision.availability_import_id)))
  ) {
    throw new Error(`${context} has invalid availability provenance.`);
  }
  if (
    (revision.state === 'proposed' &&
      (Object.hasOwn(revision, 'activated_at') ||
        Object.hasOwn(revision, 'superseded_at'))) ||
    (revision.state === 'active' &&
      (!isIsoTimestamp(revision.activated_at) ||
        Object.hasOwn(revision, 'superseded_at'))) ||
    (revision.state === 'superseded' &&
      (!isIsoTimestamp(revision.superseded_at) ||
        (Object.hasOwn(revision, 'activated_at') &&
          !isIsoTimestamp(revision.activated_at))))
  ) {
    throw new Error(`${context} has invalid revision timestamps.`);
  }
  let plannedTotal = 0;
  const blockIds = new Set();
  for (const [index, block] of revision.blocks.entries()) {
    assertDeadlinePlanBlock(block, revision, index + 1, `${context} block`);
    plannedTotal += block.planned_minutes;
    if (blockIds.has(block.id)) {
      throw new Error(`${context} contains duplicate block identities.`);
    }
    blockIds.add(block.id);
  }
  if (Object.hasOwn(revision, 'study_setup_revision')) {
    const shortBlocks = revision.blocks.filter(
      (block) => block.planned_minutes < revision.preferred_session_minutes,
    );
    if (
      revision.recovery_minutes < 5 ||
      revision.blocks.some(
        (block) =>
          block.recovery_minutes !== revision.recovery_minutes ||
          block.planned_minutes > revision.preferred_session_minutes,
      ) ||
      (shortBlocks.length > 0 &&
        (shortBlocks.length !== 1 ||
          shortBlocks[0] !== revision.blocks.at(-1)))
    ) {
      throw new Error(`${context} has an inconsistent Study rhythm.`);
    }
  } else if (
    revision.blocks.some((block) => block.recovery_minutes !== 0)
  ) {
    throw new Error(`${context} invented block recovery without Study setup.`);
  }
  if (plannedTotal !== revision.planned_minutes) {
    throw new Error(`${context} block total differs from planned_minutes.`);
  }
  return revision;
}

function assertDeadlinePlanBlock(block, revision, expectedSequence, context) {
  assertExactDeadlineKeys(
    block,
    [
      'id',
      'sequence',
      'starts_at',
      'ends_at',
      'local_date',
      'local_start_time',
      'local_end_time',
      'planned_minutes',
      'recovery_minutes',
      'reserved_ends_at',
      'credited_tracked_minutes',
      'state',
    ],
    context,
  );
  if (
    !isCanonicalUuid(block.id) ||
    block.sequence !== expectedSequence ||
    !isIsoTimestamp(block.starts_at) ||
    !isIsoTimestamp(block.ends_at) ||
    !isIsoTimestamp(block.reserved_ends_at) ||
    Date.parse(block.ends_at) <= Date.parse(block.starts_at) ||
    Date.parse(block.reserved_ends_at) < Date.parse(block.ends_at) ||
    !isCalendarDate(block.local_date) ||
    !isDeadlineLocalTime(block.local_start_time) ||
    !isDeadlineLocalTime(block.local_end_time) ||
    !Number.isInteger(block.planned_minutes) ||
    block.planned_minutes < 5 ||
    block.planned_minutes > 240 ||
    (Date.parse(block.ends_at) - Date.parse(block.starts_at)) / 60000 !==
      block.planned_minutes ||
    !Number.isInteger(block.recovery_minutes) ||
    block.recovery_minutes < 0 ||
    block.recovery_minutes > 60 ||
    block.recovery_minutes % 5 !== 0 ||
    (Date.parse(block.reserved_ends_at) - Date.parse(block.ends_at)) / 60000 !==
      block.recovery_minutes ||
    !Number.isInteger(block.credited_tracked_minutes) ||
    block.credited_tracked_minutes < 0 ||
    block.credited_tracked_minutes > block.planned_minutes ||
    !['proposed', 'upcoming', 'partial', 'completed', 'missed'].includes(
      block.state,
    ) ||
    (revision.state === 'proposed' &&
      (block.state !== 'proposed' || block.credited_tracked_minutes !== 0)) ||
    (revision.state === 'active' && block.state === 'proposed')
  ) {
    throw new Error(`${context} is invalid: ${stableJson(block)}`);
  }
}

function assertDeadlinePlanProgress(progress, context) {
  assertExactDeadlineKeys(
    progress,
    [
      'estimated_total_minutes',
      'credited_prior_minutes',
      'tracked_focus_minutes',
      'accounted_minutes',
      'remaining_minutes',
      'completion_suggested',
    ],
    context,
  );
  const values = [
    progress.estimated_total_minutes,
    progress.credited_prior_minutes,
    progress.tracked_focus_minutes,
    progress.accounted_minutes,
    progress.remaining_minutes,
  ];
  const expectedAccounted = Math.min(
    progress.estimated_total_minutes,
    progress.credited_prior_minutes + progress.tracked_focus_minutes,
  );
  if (
    values.some((value) => !Number.isInteger(value) || value < 0) ||
    progress.estimated_total_minutes < 30 ||
    progress.estimated_total_minutes > 30000 ||
    progress.credited_prior_minutes >= progress.estimated_total_minutes ||
    progress.accounted_minutes !== expectedAccounted ||
    progress.remaining_minutes !==
      progress.estimated_total_minutes - expectedAccounted ||
    progress.completion_suggested !== (progress.remaining_minutes === 0)
  ) {
    throw new Error(`${context} is invalid: ${stableJson(progress)}`);
  }
  return progress;
}

function assertExactDeadlineKeys(value, keys, context) {
  if (
    value === null ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    stableJson(Object.keys(value).sort()) !== stableJson([...keys].sort())
  ) {
    throw new Error(
      `${context} fields differ from deadline-plan-v1: ${stableJson(value)}`,
    );
  }
}

function isDeadlineLocalTime(value) {
  if (
    typeof value !== 'string' ||
    !/^\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$/.test(value)
  ) {
    return false;
  }
  const [hour, minute, second] = value.split(/[.:]/).map(Number);
  return hour <= 23 && minute <= 59 && second <= 59;
}

async function calendarApiRequest(
  path,
  accessToken,
  { method = 'GET', body } = {},
) {
  const response = await fetch(`${aiServiceBaseUrl}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text.length === 0 ? null : JSON.parse(text);
  } catch (_) {
    // The status assertion below reports the unparsed response body.
  }
  return { response, text, json };
}

function assertCalendarApiStatus(result, expectedStatus, context) {
  if (result.response.status !== expectedStatus) {
    throw new Error(
      `${context} returned ${result.response.status}, expected ${expectedStatus}: ${result.text}`,
    );
  }
}

function assertCalendarConnectionEnvelope(payload, context) {
  assertExactCalendarKeys(
    payload,
    ['contract_version', 'origin', 'connection'],
    context,
  );
  if (
    payload.contract_version !== 'calendar-import-v1' ||
    payload.origin !== 'authenticated_backend'
  ) {
    throw new Error(`${context} has invalid root provenance: ${stableJson(payload)}`);
  }
  if (payload.connection === null) return null;

  const connection = payload.connection;
  const required = [
    'id',
    'contract_version',
    'origin',
    'source_kind',
    'source_label',
    'status',
    'consent',
    'consented_at',
    'connected_at',
    'provider_writes',
    'llm_processed',
  ];
  const optional = [
    'disconnected_at',
    'imported_data_deleted_at',
    'last_import',
  ].filter((key) => Object.hasOwn(connection, key));
  assertExactCalendarKeys(connection, [...required, ...optional], `${context} connection`);
  if (optional.some((key) => connection[key] === null)) {
    throw new Error(`${context} returned an explicit-null optional connection field.`);
  }
  if (
    !isCalendarIdentifier(connection.id) ||
    connection.contract_version !== 'calendar-import-v1' ||
    connection.origin !== 'authenticated_backend' ||
    connection.source_kind !== 'ical_file' ||
    typeof connection.source_label !== 'string' ||
    connection.source_label.trim() !== connection.source_label ||
    [...connection.source_label].length < 1 ||
    [...connection.source_label].length > 80 ||
    !['connected', 'disconnected'].includes(connection.status) ||
    connection.provider_writes !== false ||
    connection.llm_processed !== false ||
    !isAwareCalendarTimestamp(connection.consented_at) ||
    !isAwareCalendarTimestamp(connection.connected_at)
  ) {
    throw new Error(`${context} returned an invalid connection: ${stableJson(connection)}`);
  }
  assertCalendarConsent(connection.consent, `${context} consent`);
  if (
    (connection.status === 'connected' &&
      Object.hasOwn(connection, 'disconnected_at')) ||
    (connection.status === 'disconnected' &&
      !isAwareCalendarTimestamp(connection.disconnected_at)) ||
    (Object.hasOwn(connection, 'imported_data_deleted_at') &&
      (connection.status !== 'disconnected' ||
        !isAwareCalendarTimestamp(connection.imported_data_deleted_at) ||
        Object.hasOwn(connection, 'last_import')))
  ) {
    throw new Error(`${context} returned an invalid connection lifecycle.`);
  }
  if (Object.hasOwn(connection, 'last_import')) {
    assertCalendarImportSummary(connection.last_import, `${context} last import`);
  }
  return connection;
}

function assertCalendarConsent(consent, context) {
  assertExactCalendarKeys(
    consent,
    [
      'consent_version',
      'read_calendar_events',
      'store_event_basics',
      'provider_writes',
      'llm_processing',
    ],
    context,
  );
  if (
    consent.consent_version !== 'calendar-import-consent-v1' ||
    consent.read_calendar_events !== true ||
    consent.store_event_basics !== true ||
    consent.provider_writes !== false ||
    consent.llm_processing !== false
  ) {
    throw new Error(`${context} is invalid: ${stableJson(consent)}`);
  }
}

function assertCalendarImportEnvelope(payload, context) {
  assertExactCalendarKeys(
    payload,
    ['contract_version', 'origin', 'connection', 'import'],
    context,
  );
  const connection = assertCalendarConnectionEnvelope(
    {
      contract_version: payload.contract_version,
      origin: payload.origin,
      connection: payload.connection,
    },
    context,
  );
  if (connection === null) {
    throw new Error(`${context} omitted its connection.`);
  }
  assertCalendarImportSummary(payload.import, `${context} import`);
  if (
    !Object.hasOwn(connection, 'last_import') ||
    stableJson(connection.last_import) !== stableJson(payload.import)
  ) {
    throw new Error(`${context} import does not match last_import projection.`);
  }
  return { connection, import: payload.import };
}

function assertCalendarImportSummary(summary, context) {
  assertExactCalendarKeys(
    summary,
    ['id', 'imported_at', 'window', 'counts', 'source_fingerprint'],
    context,
  );
  if (
    !isCalendarIdentifier(summary.id) ||
    !isAwareCalendarTimestamp(summary.imported_at) ||
    !/^[0-9a-f]{64}$/.test(summary.source_fingerprint ?? '')
  ) {
    throw new Error(`${context} has invalid identity/provenance.`);
  }
  assertExactCalendarKeys(
    summary.window,
    ['starts_on', 'ends_before', 'timezone'],
    `${context} window`,
  );
  if (
    !isCalendarDate(summary.window.starts_on) ||
    !isCalendarDate(summary.window.ends_before) ||
    addUtcDays(summary.window.starts_on, 105) !== summary.window.ends_before ||
    typeof summary.window.timezone !== 'string' ||
    summary.window.timezone.trim() !== summary.window.timezone ||
    summary.window.timezone.length < 1 ||
    summary.window.timezone.length > 100
  ) {
    throw new Error(`${context} has an invalid import window.`);
  }
  assertCalendarCounts(summary.counts, null, `${context} counts`);
  const localImportDate = isoDateInTimeZone(
    summary.imported_at,
    summary.window.timezone,
  );
  if (
    summary.window.starts_on !== addUtcDays(localImportDate, -14) ||
    summary.window.ends_before !== addUtcDays(localImportDate, 91)
  ) {
    throw new Error(`${context} window is not derived from the import instant.`);
  }
}

function assertCalendarCounts(actual, expected, context) {
  assertExactCalendarKeys(
    actual,
    [
      'accepted',
      'cancelled',
      'out_of_window',
      'unsupported_recurring',
      'invalid',
    ],
    context,
  );
  const values = Object.values(actual);
  if (
    values.some(
      (value) => !Number.isInteger(value) || value < 0 || value > 2000,
    ) ||
    actual.accepted > 500 ||
    values.reduce((sum, value) => sum + value, 0) > 2000
  ) {
    throw new Error(`${context} exceeds the bounded count contract.`);
  }
  if (expected !== null && stableJson(actual) !== stableJson(expected)) {
    throw new Error(
      `${context} counts differ: expected ${stableJson(expected)}, got ${stableJson(actual)}`,
    );
  }
}

function assertCalendarEventsEnvelope(payload, sourceLabel, context) {
  const required = [
    'contract_version',
    'origin',
    'connection_id',
    'events',
  ];
  const optional = ['import_id', 'next_cursor'].filter((key) =>
    Object.hasOwn(payload, key),
  );
  assertExactCalendarKeys(payload, [...required, ...optional], context);
  if (optional.some((key) => payload[key] === null)) {
    throw new Error(`${context} returned an explicit-null optional root field.`);
  }
  if (
    payload.contract_version !== 'calendar-import-v1' ||
    payload.origin !== 'authenticated_backend' ||
    !isCalendarIdentifier(payload.connection_id) ||
    !Array.isArray(payload.events) ||
    payload.events.length > 50 ||
    (Object.hasOwn(payload, 'import_id') &&
      !isCalendarIdentifier(payload.import_id)) ||
    (Object.hasOwn(payload, 'next_cursor') &&
      (typeof payload.next_cursor !== 'string' ||
        payload.next_cursor.length < 1 ||
        payload.next_cursor.length > 512)) ||
    (payload.events.length > 0 && !Object.hasOwn(payload, 'import_id')) ||
    (Object.hasOwn(payload, 'next_cursor') &&
      !Object.hasOwn(payload, 'import_id'))
  ) {
    throw new Error(`${context} has invalid root fields: ${stableJson(payload)}`);
  }
  const ids = new Set();
  for (const event of payload.events) {
    assertCalendarEvent(event, sourceLabel, `${context} event`);
    if (ids.has(event.id)) {
      throw new Error(`${context} contains a duplicate event id.`);
    }
    ids.add(event.id);
  }
  return payload;
}

function assertCalendarEvent(event, sourceLabel, context) {
  const base = [
    'id',
    'title',
    'event_kind',
    'busy_status',
    'event_status',
    'event_timezone',
    'timezone_source',
    'imported_at',
    'last_seen_at',
    'source_fingerprint',
    'provenance',
  ];
  const variant =
    event?.event_kind === 'timed'
      ? ['starts_at', 'ends_at', 'local_starts_at', 'local_ends_at']
      : ['starts_on', 'ends_on'];
  const optional = Object.hasOwn(event ?? {}, 'location') ? ['location'] : [];
  assertExactCalendarKeys(event, [...base, ...variant, ...optional], context);
  if (optional.some((key) => event[key] === null)) {
    throw new Error(`${context} returned explicit-null optional fields.`);
  }
  if (
    !isCalendarIdentifier(event.id) ||
    typeof event.title !== 'string' ||
    event.title.trim() !== event.title ||
    [...event.title].length < 1 ||
    [...event.title].length > 200 ||
    (Object.hasOwn(event, 'location') &&
      (typeof event.location !== 'string' ||
        event.location.trim() !== event.location ||
        [...event.location].length < 1 ||
        [...event.location].length > 300)) ||
    !['timed', 'all_day'].includes(event.event_kind) ||
    !['busy', 'free'].includes(event.busy_status) ||
    !['confirmed', 'tentative'].includes(event.event_status) ||
    typeof event.event_timezone !== 'string' ||
    event.event_timezone.trim() !== event.event_timezone ||
    event.event_timezone.length < 1 ||
    event.event_timezone.length > 100 ||
    !['utc', 'event', 'profile'].includes(event.timezone_source) ||
    !isAwareCalendarTimestamp(event.imported_at) ||
    !isAwareCalendarTimestamp(event.last_seen_at) ||
    Date.parse(event.last_seen_at) < Date.parse(event.imported_at) ||
    !/^[0-9a-f]{64}$/.test(event.source_fingerprint ?? '')
  ) {
    throw new Error(`${context} has invalid common fields: ${stableJson(event)}`);
  }
  if (event.event_kind === 'timed') {
    if (
      !isAwareCalendarTimestamp(event.starts_at) ||
      !isAwareCalendarTimestamp(event.ends_at) ||
      Date.parse(event.ends_at) <= Date.parse(event.starts_at) ||
      !isLocalCalendarTimestamp(event.local_starts_at) ||
      !isLocalCalendarTimestamp(event.local_ends_at)
    ) {
      throw new Error(`${context} has invalid timed fields.`);
    }
  } else if (
    !isCalendarDate(event.starts_on) ||
    !isCalendarDate(event.ends_on) ||
    event.timezone_source !== 'profile' ||
    new Date(`${event.ends_on}T00:00:00Z`) <=
      new Date(`${event.starts_on}T00:00:00Z`)
  ) {
    throw new Error(`${context} has invalid all-day fields.`);
  }
  assertExactCalendarKeys(
    event.provenance,
    [
      'kind',
      'contract_version',
      'source_kind',
      'source_label',
      'provider_writes',
      'llm_processed',
    ],
    `${context} provenance`,
  );
  if (
    event.provenance.kind !== 'integration' ||
    event.provenance.contract_version !== 'calendar-import-v1' ||
    event.provenance.source_kind !== 'ical_file' ||
    event.provenance.source_label !== sourceLabel ||
    event.provenance.provider_writes !== false ||
    event.provenance.llm_processed !== false
  ) {
    throw new Error(`${context} has invalid integration provenance.`);
  }
}

function assertExactCalendarKeys(value, keys, context) {
  if (
    value === null ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    stableJson(Object.keys(value).sort()) !== stableJson([...keys].sort())
  ) {
    throw new Error(
      `${context} fields differ from the exact contract: ${stableJson(value)}`,
    );
  }
}

function isCalendarIdentifier(value) {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      value,
    )
  );
}

function isCalendarDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function isAwareCalendarTimestamp(value) {
  return (
    typeof value === 'string' &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(
      value,
    ) &&
    Number.isFinite(Date.parse(value))
  );
}

function isLocalCalendarTimestamp(value) {
  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$/.test(value)
  ) {
    return false;
  }
  const [day, time] = value.split('T');
  if (!isCalendarDate(day)) return false;
  const [hour, minute, second] = time.split(/[.:]/).map(Number);
  return hour <= 23 && minute <= 59 && second <= 59;
}

function buildCalendarImportFixture(localToday) {
  const timezoneDate = addUtcDays(localToday, 1);
  const allDayDate = addUtcDays(localToday, 2);
  const recurrenceDate = addUtcDays(localToday, 3);
  const generatedDate = addUtcDays(localToday, 4);
  const unsupportedDate = addUtcDays(localToday, 5);
  const invalidDate = addUtcDays(localToday, 6);
  const outsideDate = addUtcDays(localToday, 120);
  const timezoneTitle = `Phase 9 timezone event ${runId}`;
  const allDayTitle = `Phase 9 all-day event ${runId}`;
  const recurrenceTitle = `Phase 9 moved occurrence ${runId}`;
  const sensitiveMarker = `private-phase9-${runId}`;
  const timed = calendarEventComponent([
    `UID:phase9-timezone-${runId}@example.test`,
    `DTSTART;TZID=Europe/Berlin:${compactCalendarDate(timezoneDate)}T090000`,
    `DTEND;TZID=Europe/Berlin:${compactCalendarDate(timezoneDate)}T100000`,
    `SUMMARY:${timezoneTitle}`,
    'LOCATION:Room Phase 9',
    `DESCRIPTION:${sensitiveMarker}`,
    `ATTENDEE:mailto:${sensitiveMarker}@example.test`,
    `ORGANIZER:mailto:${sensitiveMarker}-owner@example.test`,
    'TRANSP:OPAQUE',
    'BEGIN:VALARM',
    'TRIGGER:-PT15M',
    'ACTION:DISPLAY',
    `DESCRIPTION:${sensitiveMarker}-alarm`,
    'END:VALARM',
  ]);
  const allDay = calendarEventComponent([
    `UID:phase9-all-day-${runId}@example.test`,
    `DTSTART;VALUE=DATE:${compactCalendarDate(allDayDate)}`,
    `SUMMARY:${allDayTitle}`,
    'TRANSP:TRANSPARENT',
  ]);
  const recurrence = calendarEventComponent([
    `UID:phase9-series-${runId}@example.test`,
    `RECURRENCE-ID;TZID=Europe/Berlin:${compactCalendarDate(recurrenceDate)}T090000`,
    `DTSTART;TZID=Europe/Berlin:${compactCalendarDate(recurrenceDate)}T110000`,
    `DTEND;TZID=Europe/Berlin:${compactCalendarDate(recurrenceDate)}T120000`,
    `SUMMARY:${recurrenceTitle}`,
  ]);
  const cancellation = calendarEventComponent([
    `UID:phase9-series-${runId}@example.test`,
    `RECURRENCE-ID;TZID=Europe/Berlin:${compactCalendarDate(recurrenceDate)}T090000`,
    'STATUS:CANCELLED',
  ]);
  const generated = Array.from({ length: 52 }, (_, index) =>
    calendarEventComponent([
      `UID:phase9-page-${index}-${runId}@example.test`,
      `DTSTART:${compactCalendarDate(generatedDate)}T120000Z`,
      `DTEND:${compactCalendarDate(generatedDate)}T123000Z`,
      `SUMMARY:Phase 9 page event ${String(index).padStart(2, '0')} ${runId}`,
    ]),
  );
  const unsupported = calendarEventComponent([
    `UID:phase9-master-${runId}@example.test`,
    `DTSTART:${compactCalendarDate(unsupportedDate)}T090000Z`,
    `DTEND:${compactCalendarDate(unsupportedDate)}T100000Z`,
    'RRULE:FREQ=WEEKLY',
    `SUMMARY:Phase 9 unsupported master ${runId}`,
  ]);
  const outside = calendarEventComponent([
    `UID:phase9-outside-${runId}@example.test`,
    `DTSTART:${compactCalendarDate(outsideDate)}T090000Z`,
    `DTEND:${compactCalendarDate(outsideDate)}T100000Z`,
    `SUMMARY:Phase 9 outside event ${runId}`,
  ]);
  const invalid = calendarEventComponent([
    `UID:phase9-invalid-${runId}@example.test`,
    `DTSTART:${compactCalendarDate(invalidDate)}T090000Z`,
    `SUMMARY:Phase 9 invalid event ${runId}`,
  ]);

  return {
    firstCalendarText: calendarDocument([
      timed,
      timed,
      allDay,
      recurrence,
      ...generated,
      unsupported,
      outside,
      invalid,
    ]),
    secondCalendarText: calendarDocument([
      timed,
      timed,
      allDay,
      ...generated.slice(0, -1),
      unsupported,
      outside,
      invalid,
      cancellation,
    ]),
    firstCounts: {
      accepted: 55,
      cancelled: 0,
      out_of_window: 1,
      unsupported_recurring: 1,
      invalid: 1,
    },
    secondCounts: {
      accepted: 53,
      cancelled: 1,
      out_of_window: 1,
      unsupported_recurring: 1,
      invalid: 1,
    },
    timezoneDate,
    allDayDate,
    timezoneTitle,
    allDayTitle,
    recurrenceTitle,
    omittedSnapshotTitle: `Phase 9 page event 51 ${runId}`,
    sensitiveMarker,
  };
}

function calendarDocument(events) {
  return ['BEGIN:VCALENDAR', 'VERSION:2.0', ...events, 'END:VCALENDAR', ''].join(
    '\r\n',
  );
}

function calendarEventComponent(lines) {
  return ['BEGIN:VEVENT', ...lines, 'END:VEVENT'].join('\r\n');
}

function compactCalendarDate(value) {
  return value.replaceAll('-', '');
}

async function calendarScheduleSnapshot(userId) {
  return fetchRows(
    `schedule_items?select=id,title,location,weekday,starts_at,ends_at,source,metadata,updated_at&user_id=eq.${userId}&order=id.asc`,
    'Phase 9 schedule baseline',
  );
}

async function assertCalendarScheduleUnchanged(userId, expected, context) {
  const actual = await calendarScheduleSnapshot(userId);
  if (stableJson(actual) !== stableJson(expected)) {
    throw new Error(
      `${context} changed user-authored/setup schedule rows: ${JSON.stringify(actual)}`,
    );
  }
}

async function assertCalendarIntegrationRls({
  ownerAccessToken,
  userId,
  connectionId,
  importId,
  eventId,
  claimedRequestId,
}) {
  const ownerConnectionRead = await authenticatedRestRequest(
    `calendar_connections?select=id,contract_version,origin,source_kind,source_label,status,consent_version,read_calendar_events,store_event_basics,provider_writes,llm_processing,consented_at,connected_at,disconnected_at,imported_data_deleted_at,last_import_id&id=eq.${connectionId}`,
    ownerAccessToken,
  );
  if (
    !ownerConnectionRead.response.ok ||
    ownerConnectionRead.rows?.length !== 1 ||
    ownerConnectionRead.rows[0].id !== connectionId ||
    ownerConnectionRead.rows[0].provider_writes !== false ||
    ownerConnectionRead.rows[0].llm_processing !== false
  ) {
    throw new Error(
      `Calendar connection owner SELECT failed: ${ownerConnectionRead.response.status} ${ownerConnectionRead.text}`,
    );
  }
  const ownerEventRead = await authenticatedRestRequest(
    `calendar_events?select=id,connection_id,import_id,contract_version,origin,source_kind,source_fingerprint,title,location,event_kind,busy_status,event_status,event_timezone,timezone_source,starts_at,ends_at,local_starts_at,local_ends_at,starts_on,ends_on,imported_at,last_seen_at&id=eq.${eventId}`,
    ownerAccessToken,
  );
  if (
    !ownerEventRead.response.ok ||
    ownerEventRead.rows?.length !== 1 ||
    ownerEventRead.rows[0].id !== eventId ||
    ownerEventRead.rows[0].connection_id !== connectionId ||
    ownerEventRead.rows[0].import_id !== importId
  ) {
    throw new Error(
      `Calendar event owner SELECT failed: ${ownerEventRead.response.status} ${ownerEventRead.text}`,
    );
  }

  const restrictedReads = [
    await authenticatedRestRequest(
      `calendar_connections?select=create_request_id&id=eq.${connectionId}`,
      ownerAccessToken,
    ),
    await authenticatedRestRequest(
      `calendar_events?select=source_event_key&id=eq.${eventId}`,
      ownerAccessToken,
    ),
    await authenticatedRestRequest(
      `calendar_imports?select=id&id=eq.${importId}`,
      ownerAccessToken,
    ),
    await authenticatedRestRequest(
      `calendar_request_identities?select=request_id&connection_id=eq.${connectionId}`,
      ownerAccessToken,
    ),
  ];
  if (restrictedReads.some((result) => result.response.ok)) {
    throw new Error(
      `Calendar Data API exposed backend-only identity/import columns: ${JSON.stringify(restrictedReads.map((result) => result.text))}`,
    );
  }

  const secondaryEmail = `e2e-phase9-other-${runId}@example.test`;
  const secondaryPassword = `E2e-phase9-other-${runId}-password`;
  const secondary = await createConfirmedUserWithCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    displayName: 'E2E Calendar Other User',
  });
  const secondaryToken = await signInCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    context: 'Phase 9 secondary principal',
  });
  const [crossConnection, crossEvent] = await Promise.all([
    authenticatedRestRequest(
      `calendar_connections?select=id&id=eq.${connectionId}`,
      secondaryToken,
    ),
    authenticatedRestRequest(
      `calendar_events?select=id&id=eq.${eventId}`,
      secondaryToken,
    ),
  ]);
  if (
    !crossConnection.response.ok ||
    crossConnection.rows?.length !== 0 ||
    !crossEvent.response.ok ||
    crossEvent.rows?.length !== 0
  ) {
    throw new Error(
      `Calendar RLS exposed owner rows to ${secondary.id}: ${crossConnection.text} ${crossEvent.text}`,
    );
  }
  const crossOwnerApi = await calendarApiRequest(
    `/v1/calendar-integrations/connections/${connectionId}/events`,
    secondaryToken,
  );
  assertCalendarApiStatus(
    crossOwnerApi,
    404,
    'cross-owner calendar API read',
  );
  const crossOwnerRequestReuse = await calendarApiRequest(
    '/v1/calendar-integrations/connections',
    secondaryToken,
    {
      method: 'POST',
      body: {
        request_id: claimedRequestId,
        source_kind: 'ical_file',
        source_label: `Cross-owner ${runId}`,
        consent: {
          consent_version: 'calendar-import-consent-v1',
          read_calendar_events: true,
          store_event_basics: true,
          provider_writes: false,
          llm_processing: false,
        },
      },
    },
  );
  assertCalendarApiStatus(
    crossOwnerRequestReuse,
    409,
    'cross-owner calendar request-id reuse',
  );

  const directWrites = [
    await authenticatedRestRequest(
      `calendar_connections?id=eq.${connectionId}`,
      ownerAccessToken,
      { method: 'PATCH', body: { source_label: 'Client rewrite' } },
    ),
    await authenticatedRestRequest(
      `calendar_events?id=eq.${eventId}`,
      ownerAccessToken,
      { method: 'DELETE' },
    ),
    await authenticatedRestRequest(
      `calendar_imports?id=eq.${importId}`,
      ownerAccessToken,
      { method: 'DELETE' },
    ),
    await authenticatedRestRequest('calendar_events', ownerAccessToken, {
      method: 'POST',
      body: { id: crypto.randomUUID(), title: 'Client injected event' },
    }),
    await authenticatedRestRequest(
      'calendar_request_identities',
      ownerAccessToken,
      {
        method: 'POST',
        body: {
          request_id: crypto.randomUUID(),
          user_id: userId,
          connection_id: connectionId,
          operation: 'delete_imported_data',
          created_at: new Date().toISOString(),
        },
      },
    ),
  ];
  if (directWrites.some((result) => result.response.ok)) {
    throw new Error(
      `Authenticated client unexpectedly wrote backend-owned calendar state: ${JSON.stringify(directWrites.map((result) => result.text))}`,
    );
  }
  await assertRows(
    `calendar_connections?select=id,source_label&id=eq.${connectionId}`,
    (rows) => rows.length === 1 && rows[0].source_label !== 'Client rewrite',
    'calendar connection survives direct authenticated write attempts',
  );
  await assertRows(
    `calendar_imports?select=id&id=eq.${importId}`,
    (rows) => rows.length === 1,
    'calendar import survives direct authenticated write attempts',
  );
  await assertRows(
    `calendar_events?select=id&id=eq.${eventId}`,
    (rows) => rows.length === 1,
    'calendar event survives direct authenticated write attempts',
  );
  if (secondary?.id === userId) {
    throw new Error('Phase 9 RLS secondary principal unexpectedly matched owner.');
  }
}

async function scheduledRefreshRequest(body) {
  const response = await fetch(
    `${aiServiceBaseUrl}/v1/scheduled/daily-refresh`,
    {
      method: 'POST',
      headers: {
        'X-Scheduled-Refresh-Token': scheduledRefreshToken,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );
  if (!response.ok) {
    throw new Error(
      `Scheduled refresh failed: ${response.status} ${await response.text()}`,
    );
  }
  return response.json();
}

function isExecutableBriefingAction(action) {
  const target = action?.target;
  if (
    typeof action?.title !== 'string' ||
    action.title.length === 0 ||
    typeof action?.reason !== 'string' ||
    action.reason.length === 0 ||
    target?.contract_version !== 'executable-action-v1' ||
    typeof target?.id !== 'string' ||
    target.id.length === 0 ||
    target?.metadata?.source !== 'daily-briefing-v1'
  ) {
    return false;
  }
  if (target.command === 'open_task') {
    return target.kind === 'task' && typeof target.target_id === 'string';
  }
  if (target.command === 'log_habit') {
    return (
      target.kind === 'habit' &&
      typeof target.target_id === 'string' &&
      target.metadata?.habit_outcome === 'completed' &&
      /^\d{4}-\d{2}-\d{2}$/.test(target.metadata?.entry_date ?? '')
    );
  }
  if (target.command === 'open_capture') {
    return (
      target.kind === 'capture' &&
      target.target_id === undefined &&
      ['/morning-calibration', '/quick-mood-check-in'].includes(
        target.metadata?.route,
      )
    );
  }
  return false;
}

function stableJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

async function assertNoSetupOwnedRows(userId, context) {
  const [goals, habits, scheduleItems] = await Promise.all([
    fetchRows(
      `goals?select=id,metadata&user_id=eq.${userId}`,
      `${context} goals`,
    ),
    fetchRows(
      `habits?select=id,metadata&user_id=eq.${userId}`,
      `${context} habits`,
    ),
    fetchRows(
      `schedule_items?select=id,source,metadata&user_id=eq.${userId}`,
      `${context} schedule items`,
    ),
  ]);
  const setupOwned = [
    ...goals.filter(isSetupOwned),
    ...habits.filter(isSetupOwned),
    ...scheduleItems.filter(
      (row) => isSetupOwned(row) || row.source === 'onboarding',
    ),
  ];
  if (setupOwned.length !== 0) {
    throw new Error(
      `${context} unexpectedly materialized setup-owned rows: ${JSON.stringify(setupOwned)}`,
    );
  }
}

function isSetupOwned(row) {
  return (
    row.metadata?.managed_by === 'setup' ||
    row.metadata?.source === 'intake-v1'
  );
}

async function insertRows(table, rows) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${table}`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(rows),
  });
  if (!response.ok) {
    throw new Error(
      `Could not insert ${table} rows: ${response.status} ${await response.text()}`,
    );
  }
  return response.json();
}

async function upsertRows(table, rows, onConflict) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/${table}?on_conflict=${encodeURIComponent(onConflict)}`,
    {
      method: 'POST',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify(rows),
    },
  );
  if (!response.ok) {
    throw new Error(
      `Could not upsert ${table} rows: ${response.status} ${await response.text()}`,
    );
  }
  return response.json();
}

async function patchRows(path, values, description) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method: 'PATCH',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(values),
  });
  if (!response.ok) {
    throw new Error(
      `Could not patch ${description}: ${response.status} ${await response.text()}`,
    );
  }
  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1) {
    throw new Error(
      `Patch for ${description} returned an unexpected result: ${JSON.stringify(rows)}`,
    );
  }
  return rows[0];
}

async function assertWeeklyReviewRls({
  ownerAccessToken,
  userId,
  reviewId,
  periodKey,
  period,
  review,
  habitId,
  expectedHabitTarget,
}) {
  const ownerRead = await authenticatedRestRequest(
    `weekly_reviews?select=id,user_id,period_key&id=eq.${reviewId}`,
    ownerAccessToken,
  );
  if (
    !ownerRead.response.ok ||
    ownerRead.rows?.length !== 1 ||
    ownerRead.rows[0].user_id !== userId ||
    ownerRead.rows[0].period_key !== periodKey
  ) {
    throw new Error(
      `Weekly review owner SELECT failed: ${ownerRead.response.status} ${ownerRead.text}`,
    );
  }

  const secondaryEmail = `e2e-phase8-other-${runId}@example.test`;
  const secondaryPassword = `E2e-phase8-other-${runId}-password`;
  await createConfirmedUserWithCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    displayName: 'E2E Weekly Review Other User',
  });
  const secondaryToken = await signInCredentials({
    emailAddress: secondaryEmail,
    passwordValue: secondaryPassword,
    context: 'Phase 8 secondary principal',
  });
  const secondaryRead = await authenticatedRestRequest(
    `weekly_reviews?select=id&id=eq.${reviewId}`,
    secondaryToken,
  );
  if (!secondaryRead.response.ok || secondaryRead.rows?.length !== 0) {
    throw new Error(
      `Weekly review RLS exposed another owner's row: ${secondaryRead.response.status} ${secondaryRead.text}`,
    );
  }

  const ownerDelete = await authenticatedRestRequest(
    `weekly_reviews?id=eq.${reviewId}`,
    ownerAccessToken,
    { method: 'DELETE' },
  );
  if (ownerDelete.response.ok) {
    throw new Error('Authenticated owner unexpectedly deleted a weekly review.');
  }
  const ownerPatch = await authenticatedRestRequest(
    `weekly_reviews?id=eq.${reviewId}`,
    ownerAccessToken,
    { method: 'PATCH', body: { narrative: 'client rewrite' } },
  );
  if (ownerPatch.response.ok) {
    throw new Error('Authenticated owner unexpectedly updated a weekly review.');
  }
  const ownerInsert = weeklyReviewRowForPeriod({
    userId,
    startsOn: addUtcDays(period.startsOn, -14),
    review,
    narrative: 'E2E authenticated insert must be rejected',
  });
  const ownerInsertResponse = await authenticatedRestRequest(
    'weekly_reviews',
    ownerAccessToken,
    { method: 'POST', body: ownerInsert },
  );
  if (ownerInsertResponse.response.ok) {
    throw new Error('Authenticated owner unexpectedly inserted a weekly review.');
  }
  await assertRows(
    `weekly_reviews?select=id&id=eq.${ownerInsert.id}`,
    (rows) => rows.length === 0,
    'backend-owned weekly review rejects direct authenticated insert',
  );
  await assertRows(
    `weekly_reviews?select=id&id=eq.${reviewId}`,
    (rows) => rows.length === 1,
    'backend-owned weekly review survives direct authenticated delete',
  );

  const crossOwnerHabitPatch = await authenticatedRestRequest(
    `habits?id=eq.${habitId}`,
    secondaryToken,
    { method: 'PATCH', body: { target: expectedHabitTarget - 1 } },
  );
  if (
    !crossOwnerHabitPatch.response.ok ||
    crossOwnerHabitPatch.rows?.length !== 0
  ) {
    throw new Error(
      `Cross-owner habit PATCH did not resolve to an empty RLS result: ${crossOwnerHabitPatch.response.status} ${crossOwnerHabitPatch.text}`,
    );
  }
  await assertRows(
    `habits?select=id,target&id=eq.${habitId}`,
    (rows) =>
      rows.length === 1 && rows[0].target === expectedHabitTarget,
    'cross-owner weekly proposal target remains unchanged',
  );
}

async function assertWeeklyReviewDatabaseConstraints({
  userId,
  period,
  review,
  manualProposal,
}) {
  const startsOn = addUtcDays(period.startsOn, -7);
  const base = weeklyReviewRowForPeriod({
    userId,
    startsOn,
    review,
    narrative: 'E2E rejected weekly review constraint candidate',
  });
  await assertInsertRejected(
    'weekly_reviews',
    [
      {
        ...base,
        id: crypto.randomUUID(),
        source_fingerprint: 'A'.repeat(64),
        provenance: {
          ...base.provenance,
          source_fingerprint: 'A'.repeat(64),
        },
      },
    ],
    'uppercase weekly review source fingerprint',
    'weekly_reviews_source_fingerprint',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [
      {
        ...base,
        id: crypto.randomUUID(),
        proposals: [manualProposal, manualProposal, manualProposal],
      },
    ],
    'weekly review with more than two proposals',
    'weekly_reviews_proposals_array',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [
      {
        ...base,
        id: crypto.randomUUID(),
        evidence_refs: Array.from({ length: 41 }, (_, index) => ({
          table: 'habits',
          id: `bounded-evidence-${index}`,
          field: 'updated_at',
        })),
      },
    ],
    'weekly review with more than forty evidence references',
    'weekly_reviews_evidence_refs_array',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [{ ...base, id: crypto.randomUUID(), narrative: '   ' }],
    'blank weekly review narrative',
    'weekly_reviews_narrative_length',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [{ ...base, id: crypto.randomUUID(), data_quality: 'complete' }],
    'unknown weekly review data quality',
    'weekly_reviews_data_quality_check',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [{ ...base, id: crypto.randomUUID(), facts: [] }],
    'weekly review facts with a non-object shape',
    'weekly_reviews_facts_object',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [
      {
        ...base,
        id: crypto.randomUUID(),
        provenance: {
          ...base.provenance,
          source_fingerprint: 'b'.repeat(64),
        },
      },
    ],
    'weekly review with mismatched fingerprint provenance',
    'weekly_reviews_provenance_object',
  );
  const { contract_version: _contractVersion, ...missingContract } =
    base.provenance;
  await assertInsertRejected(
    'weekly_reviews',
    [
      {
        ...base,
        id: crypto.randomUUID(),
        provenance: missingContract,
      },
    ],
    'weekly review without provenance contract version',
    'weekly_reviews_provenance_object',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [
      {
        ...base,
        id: crypto.randomUUID(),
        provenance: {
          ...base.provenance,
          evidence_window: {
            ...base.provenance.evidence_window,
            starts_on: period.startsOn,
            ends_on: period.endsOn,
          },
        },
      },
    ],
    'weekly review with cross-period provenance window',
    'weekly_reviews_provenance_object',
  );
  await assertInsertRejected(
    'weekly_reviews',
    [{ ...base, id: crypto.randomUUID(), period_key: '2026-W54' }],
    'invalid ISO weekly review period',
    'weekly_reviews_period_key_format',
  );
}

function weeklyReviewRowForPeriod({ userId, startsOn, review, narrative }) {
  const endsOn = addUtcDays(startsOn, 6);
  return {
    id: crypto.randomUUID(),
    user_id: userId,
    period_key: isoPeriodKey(startsOn),
    week_start: startsOn,
    week_end: endsOn,
    timezone: 'Europe/Berlin',
    data_quality: review.data_quality,
    narrative,
    facts: review.facts,
    proposals: [],
    evidence_refs: [],
    provenance: {
      ...review.provenance,
      evidence_window: { starts_on: startsOn, ends_on: endsOn, days: 7 },
    },
    source_fingerprint: review.provenance.source_fingerprint,
    generated_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
}

async function authenticatedRestRequest(
  path,
  accessToken,
  { method = 'GET', body } = {},
) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let rows;
  try {
    rows = text.length === 0 ? [] : JSON.parse(text);
  } catch (_) {
    rows = null;
  }
  return { response, text, rows };
}

async function createConfirmedUserWithCredentials({
  emailAddress,
  passwordValue,
  displayName,
}) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: emailAddress,
      password: passwordValue,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    }),
  });
  if (!response.ok) {
    throw new Error(
      `Could not create additional local auth user: ${response.status} ${await response.text()}`,
    );
  }
  return response.json();
}

async function signInCredentials({
  emailAddress,
  passwordValue,
  context,
}) {
  const response = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        apikey: supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email: emailAddress, password: passwordValue }),
    },
  );
  if (!response.ok) {
    throw new Error(
      `${context} sign-in failed: ${response.status} ${await response.text()}`,
    );
  }
  const accessToken = (await response.json()).access_token;
  if (typeof accessToken !== 'string' || accessToken.length === 0) {
    throw new Error(`${context} sign-in returned no access token.`);
  }
  return accessToken;
}

async function assertInsertRejected(
  table,
  rows,
  description,
  expectedMarker,
) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${table}`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(rows),
  });
  const body = await response.text();
  if (response.ok) {
    const ids = rows.map((row) => row.id).filter(Boolean);
    if (ids.length > 0) {
      await deleteRows(
        `${table}?id=in.(${ids.join(',')})`,
        `unexpected accepted ${description}`,
      );
    }
    throw new Error(`Database unexpectedly accepted ${description}.`);
  }
  if (!body.includes(expectedMarker)) {
    throw new Error(
      `Database rejected ${description} for the wrong reason: ${response.status} ${body}`,
    );
  }
}

async function assertPatchRejected(
  path,
  values,
  description,
  expectedMarker,
) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method: 'PATCH',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify(values),
  });
  const body = await response.text();
  if (response.ok) {
    throw new Error(`Database unexpectedly accepted ${description}.`);
  }
  if (!body.includes(expectedMarker)) {
    throw new Error(
      `Database rejected ${description} for the wrong reason: ${response.status} ${body}`,
    );
  }
}

async function deleteRows(path, description) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method: 'DELETE',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      Prefer: 'return=minimal',
    },
  });
  if (!response.ok) {
    throw new Error(
      `Could not delete ${description}: ${response.status} ${await response.text()}`,
    );
  }
}

async function fetchRows(path, description) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
    },
  });

  if (!response.ok) {
    throw new Error(
      `Could not query ${description}: ${response.status} ${await response.text()}`,
    );
  }

  return response.json();
}
