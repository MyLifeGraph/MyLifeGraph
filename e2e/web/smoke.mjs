import { chromium } from 'playwright';

const required = [
  'APP_URL',
  'AI_SERVICE_BASE_URL',
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
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
const headed = process.env.HEADED === 'true';
const runId = process.env.E2E_RUN_ID ?? `${Date.now()}`;
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
const eveningTomorrowPriority = `E2E protect a calm morning ${runId}`;
const editedEveningTomorrowPriority =
  `E2E finish the smallest useful draft ${runId}`;

const browser = await chromium.launch({
  headless: !headed,
  executablePath: process.env.CHROME_BIN || undefined,
});

let page;
try {
  await assertAiServiceHealthy();
  const user = await createConfirmedUser();
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
  await clickChoiceChip(page, 'No reminders');
  await clickByText(page, 'Save setup');

  await page.waitForURL('**/#/dashboard');
  await expectText(page, 'Latest check-in');
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
      !Object.hasOwn(rows[0].responses ?? {}, 'calendar_connection_intent'),
    'applied revision 1 with exact empty optional setup answers',
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
  await expectText(page, 'No reminders');

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
  await scrollFlutterPage(page, 700);
  await toggleSetupSection(page, 'Routines', 'Add routine candidate');
  await scrollFlutterPage(page, 700);
  await clickByText(page, 'Add routine candidate');
  await fillByLabelOrPlaceholder(page, 'Routine name', setupRoutineTitle, 3);
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
  await expectText(page, setupGoalTitle);
  await expectText(page, setupRoutineTitle);
  await expectText(page, setupCommitmentTitle);
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
  await clickByText(page, 'Retry exact setup save');
  const retryResponse = await retryResponsePromise;
  const retryPayload = retryResponse.request().postDataJSON();
  if (
    retryPayload.request_id !== lostSavePayload?.request_id ||
    retryPayload.base_revision !== 1
  ) {
    throw new Error(
      `Setup retry changed idempotency identity. First ${JSON.stringify(lostSavePayload)}, retry ${JSON.stringify(retryPayload)}`,
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
  await fillByLabelOrPlaceholder(page, 'Goal title', editedSetupGoalTitle, 1);
  await scrollFlutterPage(page, 700);
  await selectDropdownOption(
    page,
    'Cadence (required before activation)',
    'Weekly',
  );
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

  await page.goto(appRoute('/quick-action'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByText(page, 'Habit management');
  await expectText(page, 'Habit management');
  await clickByText(page, 'Add habit');
  await fillByLabelOrPlaceholder(page, 'Title', managedHabitTitle, 0);
  await fillByLabelOrPlaceholder(
    page,
    'Description',
    'Created through browser smoke',
    1,
  );
  await fillByLabelOrPlaceholder(page, 'Target', '1', 2);
  await clickByText(page, 'Save');
  await expectText(page, 'Habit added.');
  await waitForRows(
    `habits?select=id,title,frequency,active,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.title === managedHabitTitle &&
          row.frequency === 'daily' &&
          row.active === true &&
          row.metadata?.source === 'flutter-habit-management-v1',
      ),
    'habit row created from Habit management',
  );

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
  await clickByText(page, 'Next');
  await clickByRoleName(page, 'button', 'evening energy 9 of 10');
  await clickByText(page, 'Next');
  await clickByRoleName(page, 'button', 'evening stress 8 of 10');
  await clickByText(page, 'Next');
  await clickByRoleName(page, 'button', 'stress source private_emotional');
  await clickByText(page, 'Next');
  await clickByRoleName(
    page,
    'button',
    'stress controllability hardly_controllable',
  );
  await clickByText(page, 'Next');
  await clickByRoleName(page, 'button', 'focus band 30_to_60_minutes');
  await clickByText(page, 'Next');
  await clickByRoleName(page, 'button', 'main friction emotional_load');
  await clickByText(page, 'Next');
  await fillByLabelOrPlaceholder(
    page,
    'Tomorrow priority',
    `  ${eveningTomorrowPriority}  `,
    0,
  );
  await clickByText(page, 'Next');
  await clickByText(page, 'Save evening shutdown');
  await expectText(
    page,
    'Could not save. Your exact Evening Shutdown is still here. Try again.',
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
    'one committed required-only Evening Shutdown row after lost response',
  );

  const eveningRetrySnapshotPromise = waitForAiPost(
    page,
    '/v1/snapshots/generate',
    'Evening retry snapshot refresh',
  );
  await clickByText(page, 'Save evening shutdown');
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
  await expectText(page, 'Latest check-in');
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
    'one Evening Shutdown row after exact retry',
  );
  const eveningOnlyRows = await fetchRows(
    dailyCapturePath,
    'Evening Shutdown row after retry',
  );
  const dailyLogId = eveningOnlyRows[0].id;
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
  await clickByRoleName(page, 'button', 'morning energy 4 of 10');
  await clickByRoleName(page, 'button', 'day shape constrained');
  const morningSnapshotPromise = waitForAiPost(
    page,
    '/v1/snapshots/generate',
    'Morning Calibration snapshot refresh',
  );
  await clickByText(page, 'Save morning calibration');
  const morningSnapshotResponse = await morningSnapshotPromise;
  assertJsonPayload(
    morningSnapshotResponse.request(),
    {
      scope: 'daily',
      window_days: 7,
      target_date: captureEntryDate,
    },
    'Morning Calibration snapshot refresh payload',
  );
  await expectText(page, 'Latest check-in');

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
    'four exact merged current events after Morning Calibration',
  );

  await page.goto(appRoute('/quick-mood-check-in'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(
    page,
    "Today's Evening Shutdown is loaded. Saving replaces only its evening state.",
  );
  for (let index = 0; index < 3; index += 1) {
    await clickByText(page, 'Next');
  }
  await clickByRoleName(page, 'button', 'stress source workload');
  await clickByText(page, 'Next');
  await clickByRoleName(
    page,
    'button',
    'stress controllability mostly_controllable',
  );
  await clickByText(page, 'Next');
  await clickByText(page, 'Next');
  await clickByText(page, 'Next');
  await fillByLabelOrPlaceholder(
    page,
    'Tomorrow priority',
    editedEveningTomorrowPriority,
    0,
  );
  await clickByText(page, 'Next');
  await expectFieldValue(page, 'Reflection (optional)', '', 0);
  await expectFieldValue(page, 'Specific blocker (optional)', '', 1);
  const eveningEditSnapshotPromise = waitForAiPost(
    page,
    '/v1/snapshots/generate',
    'Evening edit snapshot refresh',
  );
  await clickByText(page, 'Save evening shutdown');
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
  await expectText(page, 'Latest check-in');
  await expectText(page, 'Morning energy');
  await expectText(page, '4/10');
  await expectText(page, '5.5 h');

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
      rows[0].signals?.input_counts?.daily_logs >= 1 &&
      rows[0].signals?.input_counts?.behavioral_events >= 4,
    'one daily snapshot refreshed from merged Phase 1 capture',
  );

  const dailySnapshotBeforeHabit = await latestDailySnapshotGeneratedAt(user.id);
  await page.goto(appRoute('/quick-action'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByText(page, 'Habit completion');
  await expectText(page, 'Habit completion');
  await clickByText(page, 'Log');
  await waitForRows(
    `habit_logs?select=id,habit_id,entry_date,value,habits(title)&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) => row.value === 1 && row.habits?.title === managedHabitTitle,
      ),
    'habit_logs row from Quick Action habit completion',
  );
  await waitForRows(
    `user_state_snapshots?select=id,scope,generated_at,signals,metadata&user_id=eq.${user.id}&scope=eq.daily`,
    (rows) =>
      rows.some(
        (row) =>
          row.metadata?.source === 'snapshot-aggregator-v1' &&
          row.signals?.input_counts?.habits >= 1 &&
          Date.parse(row.generated_at) > dailySnapshotBeforeHabit,
      ),
    'daily snapshot refreshed after habit completion',
  );

  const recommendationsBeforeManualRefresh =
    await activeDeterministicRecommendations(user.id);
  const dailySnapshotBeforeRecommendationRefresh =
    await latestDailySnapshotGeneratedAt(user.id);
  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Latest check-in');
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

  await page.goto(appRoute('/alerts'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await expectText(page, 'Notifications');

  await page.goto(appRoute('/coach'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await page.waitForURL('**/#/dashboard');
  await expectText(page, 'Latest check-in');

  await page.goto(appRoute('/deep-work'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await page.waitForURL('**/#/alerts');
  await expectText(page, 'Notifications');

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

async function clickChoiceChip(page, label) {
  const labelPattern = new RegExp(escapeRegExp(label), 'i');
  const candidates = [
    page.getByRole('button', { name: labelPattern }).first(),
    page.getByRole('checkbox', { name: labelPattern }).first(),
    page.getByLabel(labelPattern).first(),
    page.getByText(label, { exact: true }).first(),
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
      await page.getByText(expandedControl, { exact: true }).first().waitFor({
        state: 'visible',
        timeout: 1500,
      });
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
      const box = await labelNode.boundingBox();
      if (box) {
        await page.mouse.click(box.x + 24, box.y + box.height + 18);
        opened = true;
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
      await page.keyboard.press('Escape');
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
  await page.keyboard.press('Escape');
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

async function expectFieldValue(page, label, value, fallbackIndex) {
  const candidates = [
    page.getByLabel(label),
    page.getByPlaceholder(label),
    page.getByRole('textbox', { name: label }),
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
  if ((await textboxes.count()) > fallbackIndex) {
    const fallback = textboxes.nth(fallbackIndex);
    await fallback.click({ timeout: 2500 });
    if (await locatorHasValue(page, fallback, value)) {
      return;
    }
  }

  throw new Error(`Field ${label} did not retain exact value ${value}`);
}

async function fillLocatorWithValue(page, locator, value) {
  try {
    await fillFocusedLocator(page, locator);
    await page.keyboard.type(value, { delay: 2 });
    if (await activeElementHasValue(page, value)) {
      return;
    }
  } catch (_) {
    // Try a directly fillable input next.
  }

  await locator.fill(value, { timeout: 2500 });
  if (!(await locatorHasValue(page, locator, value))) {
    throw new Error('Focused element did not receive text input');
  }
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
      // Fall back to text matching for non-button controls and Flutter variants.
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
      return;
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
    evening?.focus_band === '30_to_60_minutes' &&
    evening?.main_friction === 'emotional_load' &&
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
        metadata?.focus_band !== '30_to_60_minutes' ||
        metadata?.main_friction !== 'emotional_load' ||
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
      metadata?.day_shape === 'constrained'
    );
  });
}

function isIsoTimestamp(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
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
