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
const setupExecutionHabitTitle = `E2E setup execution habit ${runId}`;
const phase3TaskTitle = `E2E executable task ${runId}`;
const phase3EditedTaskTitle = `E2E executable task edited ${runId}`;
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
    'morning energy 4 of 10',
    '4 / 10',
  );
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
      sleepHours: 5.5,
      currentEnergy: 4,
      dayShape: 'constrained',
      expectedRisks: [
        'private_emotional_stress',
        'low_controllability',
        'low_sleep',
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
      sleepHours: 5.5,
      currentEnergy: 4,
      dayShape: 'constrained',
      expectedRisks: [
        'workload_pressure',
        'high_stress',
        'low_sleep',
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
      rows[0].metadata?.daily_state_contract_version ===
        'explainable-daily-state-v1' &&
      rows[0].summary?.daily_state?.mode === 'recover' &&
      rows[0].summary?.daily_state?.data_quality === 'current' &&
      rows[0].summary?.daily_state?.context?.stress?.source === 'workload' &&
      rows[0].summary?.daily_state?.context?.stress?.controllability ===
        'mostly_controllable' &&
      rows[0].summary?.daily_state?.context?.sleep_hours === 5.5 &&
      rows[0].summary?.daily_state?.context?.current_energy === 4 &&
      rows[0].summary?.daily_state?.context?.day_shape === 'constrained' &&
      rows[0].summary?.daily_state?.risk_flags?.includes('low_sleep') &&
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

  await page.goto(appRoute('/dashboard'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByText(page, 'Add task');
  await fillByLabelOrPlaceholder(page, 'Task title', phase3TaskTitle, 0);
  await fillByLabelOrPlaceholder(
    page,
    'Task description optional',
    'Distinctive Phase 3 browser task',
    1,
  );
  await selectDropdownOption(page, 'Task priority', 'High');
  await fillByLabelOrPlaceholder(
    page,
    'Estimate minutes optional (5–480)',
    '35',
    2,
  );
  let lostTaskCreateResponseCount = 0;
  const loseCommittedTaskCreateResponse = async (route) => {
    const request = route.request();
    if (request.method() !== 'POST' || lostTaskCreateResponseCount > 0) {
      await route.continue();
      return;
    }
    const committedResponse = await route.fetch();
    if (!committedResponse.ok()) {
      throw new Error(
        `Task response-loss precondition failed: ${committedResponse.status()} ${await committedResponse.text()}`,
      );
    }
    lostTaskCreateResponseCount += 1;
    await route.abort('failed');
  };
  await page.route('**/rest/v1/tasks**', loseCommittedTaskCreateResponse);
  await clickByText(page, 'Save task');
  await expectText(page, 'Task could not be added. Your draft is retained.');
  await clickByText(page, 'Retry');
  await clickByText(page, 'Save task');
  await expectText(page, 'Task added.');
  await page.unroute('**/rest/v1/tasks**', loseCommittedTaskCreateResponse);
  if (lostTaskCreateResponseCount !== 1) {
    throw new Error('Task response-loss path was not exercised exactly once.');
  }
  const phase3TaskRows = await waitForRows(
    `tasks?select=id,title,description,status,priority,deadline,estimated_minutes,completed_at,cancelled_at,source,metadata&user_id=eq.${user.id}&title=eq.${encodeURIComponent(phase3TaskTitle)}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].description === 'Distinctive Phase 3 browser task' &&
      rows[0].status === 'todo' &&
      rows[0].priority === 'high' &&
      rows[0].deadline === null &&
      rows[0].estimated_minutes === 35 &&
      rows[0].completed_at === null &&
      rows[0].cancelled_at === null &&
      rows[0].source === 'flutter-task-v1' &&
      rows[0].metadata?.contract_version === 'executable-task-v1',
    'typed task created from Dashboard',
  );
  const phase3TaskId = phase3TaskRows[0].id;
  if (!isUuid(phase3TaskId)) {
    throw new Error(`Task did not use a client-stable UUID: ${phase3TaskId}`);
  }

  await clickByRoleName(
    page,
    'button',
    `Task actions for ${phase3TaskTitle}`,
  );
  await clickByRoleName(page, 'menuitem', 'Edit task');
  await fillByLabelOrPlaceholder(page, 'Task title', phase3EditedTaskTitle, 0);
  await fillByLabelOrPlaceholder(
    page,
    'Task description optional',
    'Edited without replacing identity',
    1,
  );
  await selectDropdownOption(page, 'Task priority', 'Critical');
  await fillByLabelOrPlaceholder(
    page,
    'Estimate minutes optional (5–480)',
    '50',
    2,
  );
  await clickByText(page, 'Save task');
  await expectText(page, 'Task updated.');
  await waitForRows(
    `tasks?select=id,title,description,status,priority,deadline,estimated_minutes&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].id === phase3TaskId &&
      rows[0].title === phase3EditedTaskTitle &&
      rows[0].description === 'Edited without replacing identity' &&
      rows[0].status === 'todo' &&
      rows[0].priority === 'critical' &&
      rows[0].estimated_minutes === 50,
    'task edit preserves identity and replaces typed fields',
  );

  await clickByRoleName(
    page,
    'button',
    `Task actions for ${phase3EditedTaskTitle}`,
  );
  await clickByRoleName(page, 'menuitem', 'Postpone task');
  await clickByText(page, 'OK');
  const postponedRows = await waitForRows(
    `tasks?select=id,status,deadline&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'todo' &&
      isIsoTimestamp(rows[0].deadline),
    'task postpone updates the existing deadline',
  );
  const postponedDeadline = postponedRows[0].deadline;
  await clickByText(page, 'Undo', { match: 'last' });
  await waitForRows(
    `tasks?select=id,status,deadline&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'todo' &&
      rows[0].deadline === null,
    `task postpone undo restores null deadline from ${postponedDeadline}`,
  );

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
  await clickByRoleName(
    page,
    'button',
    `Complete task ${phase3EditedTaskTitle}`,
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

  await clickByRoleName(
    page,
    'button',
    `Task actions for ${phase3EditedTaskTitle}`,
  );
  await clickByRoleName(page, 'menuitem', 'Cancel task');
  await clickByText(page, 'Cancel task', { match: 'last' });
  await waitForRows(
    `tasks?select=id,status,completed_at,cancelled_at&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'cancelled' &&
      rows[0].completed_at === null &&
      isIsoTimestamp(rows[0].cancelled_at),
    'task cancellation preserves row and writes terminal timestamp',
  );

  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickByText(page, 'Cancelled (1)');
  await clickByRoleName(
    page,
    'button',
    `Restore task ${phase3EditedTaskTitle}`,
  );
  await waitForRows(
    `tasks?select=id,status,completed_at,cancelled_at&user_id=eq.${user.id}&id=eq.${phase3TaskId}`,
    (rows) =>
      rows.length === 1 &&
      rows[0].status === 'todo' &&
      rows[0].completed_at === null &&
      rows[0].cancelled_at === null,
    'durable cancelled-task restore returns the task to todo',
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

  await clickByRoleName(
    page,
    'button',
    `Focus on ${phase3EditedTaskTitle}`,
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
      rows[0].planned_minutes === 25 &&
      rows[0].task_id === phase3TaskId &&
      rows[0].habit_id === null &&
      rows[0].ended_at === null &&
      rows[0].actual_minutes === null &&
      rows[0].metadata?.contract_version === 'focus-session-v1' &&
      rows[0].metadata?.action_target?.contract_version ===
        'executable-action-v1' &&
      rows[0].metadata?.action_target?.kind === 'focus' &&
      rows[0].metadata?.action_target?.command === 'start_focus' &&
      rows[0].metadata?.action_target?.target_id === phase3TaskId &&
      rows[0].metadata?.action_target?.metadata?.target_kind === 'task' &&
      rows[0].metadata?.action_target?.metadata?.focus_minutes === 25,
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
    'Focus session finished. Linked tasks and habits were not completed automatically.',
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

  await expectText(page, 'Independent focus block');
  await clickByText(page, 'Start focus session');
  const secondFocusRows = await waitForRows(
    `focus_sessions?select=id,status,task_id,habit_id&user_id=eq.${user.id}&status=eq.active`,
    (rows) =>
      rows.length === 1 &&
      rows[0].task_id === null &&
      rows[0].habit_id === null,
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
    sleepHours: state.context?.sleep_hours,
    currentEnergy: state.context?.current_energy,
    dayShape: state.context?.day_shape,
  };
  for (const [key, expectedValue] of Object.entries(expected)) {
    if (
      key in exactValues &&
      expectedValue !== undefined &&
      exactValues[key] !== expectedValue
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

function isUuid(value) {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
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

async function assertDeterministicDailyBriefing(userId) {
  const accessToken = await signInAccessToken('Phase 4 briefing');
  const rowsBefore = await fetchRows(
    `daily_briefings?select=id&user_id=eq.${userId}`,
    'daily briefings before read-only GET',
  );
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

  const generated = await briefingRequest(
    '/v1/briefings/generate',
    accessToken,
    { force: false },
  );
  const briefing = generated.briefing;
  if (
    generated.contract_version !== 'daily-briefing-v1' ||
    generated.freshness !== 'current' ||
    generated.needs_generation !== false ||
    briefing?.mode !== 'recover' ||
    briefing?.provenance?.engine !== 'deterministic' ||
    briefing?.provenance?.llm_used !== false ||
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
      'deterministic-briefing-ranker-v1' ||
    persisted[0].provenance?.source_snapshot_id !==
      briefing.provenance.source_snapshot_id ||
    stableJson(persisted[0].primary_action) !==
      stableJson(briefing.primary_action) ||
    stableJson(persisted[0].support_actions) !==
      stableJson(briefing.support_actions)
  ) {
    throw new Error(
      `Persisted Phase 4 briefing does not match its response: ${JSON.stringify(persisted)}`,
    );
  }

  const repeated = await briefingRequest(
    '/v1/briefings/generate',
    accessToken,
    { force: false },
  );
  if (
    repeated.briefing?.id !== briefing.id ||
    repeated.briefing?.generated_at !== briefing.generated_at ||
    repeated.briefing?.updated_at !== briefing.updated_at
  ) {
    throw new Error(
      `Idempotent Phase 4 generation changed the current row: ${JSON.stringify(repeated)}`,
    );
  }
  await assertRows(
    `daily_briefings?select=id&user_id=eq.${userId}`,
    (rows) => rows.length === 1 && rows[0].id === briefing.id,
    'idempotent briefing generation preserves one daily identity',
  );
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
