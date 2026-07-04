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
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const headed = process.env.HEADED === 'true';
const runId = process.env.E2E_RUN_ID ?? `${Date.now()}`;
const artifactDir = process.env.E2E_ARTIFACT_DIR ?? '.tools/e2e';
const email = `e2e-${runId}@example.test`;
const password = `E2e-${runId}-password`;
const coachPrompt = 'Plan my day based on my current energy and deadlines';
const habitTitle = `E2E hydration habit ${runId}`;
const managedHabitTitle = `E2E managed habit ${runId}`;

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

  await expectText(page, 'Your profile');
  await expectText(page, 'Your timetable');
  await scrollFlutterPage(page, 2600);
  await fillByLabelOrPlaceholder(page, 'Existing habits', habitTitle, 4);
  await clickByText(page, 'Skip timetable for now');

  await expectText(page, "Today's wellness score");
  await waitForRows(
    `intake_responses?select=id,version,responses,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.version === 'intake-v1' &&
          row.metadata?.source === 'onboarding' &&
          Array.isArray(row.responses?.primary_focus_areas) &&
          row.responses.primary_focus_areas.includes('focus') &&
          Array.isArray(row.responses?.goals) &&
          row.responses.goals.length > 0,
      ),
    'FastAPI intake_responses row from onboarding',
  );
  await waitForRows(
    `user_state_snapshots?select=id,scope,period_key,summary,signals,metadata&user_id=eq.${user.id}&scope=eq.onboarding`,
    (rows) =>
      rows.some(
        (row) =>
          row.summary?.coaching_style === 'direct' &&
          Array.isArray(row.summary?.primary_focus_areas) &&
          row.summary.primary_focus_areas.includes('planning') &&
          row.metadata?.source === 'intake-v1',
      ),
    'onboarding user_state_snapshots row',
  );
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
  await waitForRows(
    `goals?select=id,title,status,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.status === 'active' && row.metadata?.source === 'intake-v1',
      ),
    'goal row generated from intake',
  );
  await waitForRows(
    `habits?select=id,title,frequency,active,metadata&user_id=eq.${user.id}`,
    (rows) =>
      rows.some(
        (row) =>
          row.title === habitTitle &&
          row.frequency === 'daily' &&
          row.active === true &&
          row.metadata?.source === 'intake-v1',
    ),
    'habit row generated from intake',
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

  await page.goto(appRoute('/daily-check-in'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await scrollFlutterPage(page, 4200);
  await clickByText(page, 'Save check-in');
  await waitForRows(
    `daily_logs?select=id,source&user_id=eq.${user.id}&source=eq.daily_check_in`,
    (rows) => rows.length > 0,
    'daily_check_in daily_logs row',
  );
  await waitForRows(
    `user_state_snapshots?select=id,scope,period_key,summary,signals,metadata&user_id=eq.${user.id}&scope=eq.daily`,
    (rows) =>
      rows.some(
        (row) =>
          row.metadata?.source === 'snapshot-aggregator-v1' &&
          row.signals?.input_counts?.daily_logs >= 1 &&
          row.signals?.input_counts?.behavioral_events >= 7,
      ),
    'daily snapshot refreshed after daily check-in',
  );

  await page.goto(appRoute('/quick-mood-check-in'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  for (let index = 0; index < 4; index += 1) {
    await clickByText(page, 'Next');
  }
  await fillLastTextbox(page, `E2E quick mood note ${runId}`);
  await clickByText(page, 'Save');
  await expectText(page, "Today's wellness score");
  await waitForRows(
    `user_state_snapshots?select=id,scope,period_key,summary,signals,metadata&user_id=eq.${user.id}&scope=eq.daily`,
    (rows) =>
      rows.some(
        (row) =>
          row.metadata?.source === 'snapshot-aggregator-v1' &&
          row.signals?.input_counts?.daily_logs >= 1 &&
          row.signals?.input_counts?.behavioral_events >= 11 &&
          row.signals?.input_counts?.memory_entries >= 4,
      ),
    'daily snapshot refreshed after quick mood check-in',
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
  await expectText(page, "Today's wellness score");
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
  await expectText(page, 'Recommendations refreshed.');
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
  await expectText(page, 'Alerts');

  await page.goto(appRoute('/coach'), { waitUntil: 'domcontentloaded' });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await clickSendButton(page);
  await waitForRows(
    `coach_messages?select=id,content&user_id=eq.${user.id}`,
    (rows) => rows.some((row) => row.content === coachPrompt),
    'coach_messages row for browser prompt',
  );

  await assertRows(
    `daily_logs?select=id,source&user_id=eq.${user.id}`,
    (rows) => rows.some((row) => row.source === 'quick_check_in'),
    'daily_logs row updated by quick check-in',
  );

  await assertRows(
    `behavioral_events?select=id,source&user_id=eq.${user.id}`,
    (rows) =>
      rows.some((row) => row.source === 'daily_check_in') &&
      rows.some((row) => row.source === 'quick_check_in'),
    'behavioral_events rows for daily and quick check-ins',
  );

  await assertRows(
    `coach_messages?select=id,content&user_id=eq.${user.id}`,
    (rows) => rows.some((row) => row.content === coachPrompt),
    'coach_messages row for browser prompt',
  );

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

async function fillByLabelOrPlaceholder(page, label, value, fallbackIndex) {
  const candidates = [
    page.getByLabel(label),
    page.getByPlaceholder(label),
    page.getByRole('textbox', { name: label }),
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
  if ((await textboxes.count()) > fallbackIndex) {
    await fillLocatorWithValue(page, textboxes.nth(fallbackIndex), value);
    return;
  }

  throw new Error(`Could not fill field: ${label}`);
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

async function fillLastTextbox(page, value) {
  const textboxes = page.getByRole('textbox');
  const count = await textboxes.count();
  if (count === 0) {
    throw new Error('No textbox found');
  }
  await fillLocatorWithValue(page, textboxes.nth(count - 1), value);
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

async function clickSendButton(page) {
  const candidates = [
    page.getByRole('button', { name: /send coach message/i }),
    page.getByRole('button', { name: /send/i }),
    page.locator('[aria-label*="send" i]').first(),
  ];

  for (const locator of candidates) {
    try {
      await locator.click({ timeout: 2500 });
      return;
    } catch (_) {
      try {
        await locator.click({ timeout: 2500, force: true });
        return;
      } catch (_) {
        // Try next candidate.
      }
    }
  }

  await page.keyboard.press('Tab');
  await page.keyboard.press('Enter');
}

async function expectText(page, text) {
  await page.getByText(text).first().waitFor({
    state: 'visible',
    timeout: 15000,
  });
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
