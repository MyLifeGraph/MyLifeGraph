export function flutterRoute(appUrl, path) {
  return `${appUrl.replace(/\/$/, '')}/#${path}`;
}

export async function waitForFlutterShell(page) {
  await page.locator('flt-glass-pane, flutter-view').first().waitFor({
    state: 'attached',
    timeout: 90000,
  });
}

export async function enableFlutterSemantics(page) {
  const preEnabled = process.env.E2E_SEMANTICS_PRE_ENABLED === 'true';
  const startedAt = performance.now();
  if (preEnabled) {
    await page.locator('flt-semantics').first().waitFor({
      state: 'attached',
      timeout: 1000,
    });
  } else {
    const placeholder = page.locator('flt-semantics-placeholder');
    try {
      await placeholder.click({ force: true, timeout: 10000 });
    } catch {
      await page
        .getByRole('button', { name: /enable accessibility/i })
        .click({ timeout: 2000 })
        .catch(() => {});
    }
    await page.locator('flt-semantics').first().waitFor({
      state: 'attached',
      timeout: 10000,
    });
  }
  console.log(
    `[e2e:timing] ${JSON.stringify({
      phase: 'semantics_spec',
      duration_ms: Math.round(performance.now() - startedAt),
      mode: preEnabled ? 'pre_enabled' : 'click_fallback',
    })}`,
  );
}

export async function expectFlutterText(page, text, timeout = 15000) {
  try {
    await page.getByText(text).first().waitFor({
      state: 'visible',
      timeout,
    });
  } catch {
    await page.getByLabel(text, { exact: false }).first().waitFor({
      state: 'visible',
      timeout,
    });
  }
}

export async function signInThroughFlutter({
  page,
  appUrl,
  email,
  password,
}) {
  await page.goto(flutterRoute(appUrl, '/auth'), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
  await fillFlutterField(page, 'Email', email, 0);
  await fillFlutterField(page, 'Password', password, 1);
  const login = page.getByRole('button', { name: 'Login', exact: true }).last();
  await login.click({ timeout: 7500 });
  await page.waitForURL('**/#/dashboard', { timeout: 45000 });
}

export async function openFlutterRoute(page, appUrl, path) {
  await page.goto(flutterRoute(appUrl, path), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
}

async function fillFlutterField(page, label, value, fallbackIndex) {
  const labelPattern = new RegExp(
    `^${escapeRegExp(label)}(?:$|\\s)`,
    'i',
  );
  const locators = [
    page.getByLabel(labelPattern),
    page.getByPlaceholder(label, { exact: true }),
    page.getByRole('textbox', { name: labelPattern }),
  ];
  let lastError;
  for (const locator of locators) {
    try {
      await fillStable(page, locator.first(), value);
      return;
    } catch (error) {
      lastError = error;
    }
  }

  const textboxes = page.getByRole('textbox');
  if ((await textboxes.count()) > fallbackIndex) {
    await fillStable(page, textboxes.nth(fallbackIndex), value);
    return;
  }
  throw lastError ?? new Error('No Flutter input was available.');
}

async function fillStable(page, locator, value) {
  for (const delay of [15, 30]) {
    await locator.click({ timeout: 2500 });
    await page.keyboard.press(
      process.platform === 'darwin' ? 'Meta+A' : 'Control+A',
    );
    await page.keyboard.press('Backspace');
    await page.keyboard.type(value, { delay });
    await page.keyboard.press('Tab');
    await page.waitForTimeout(250);
    await locator.click({ timeout: 2500 });
    if ((await locator.inputValue().catch(() => null)) === value) {
      return;
    }
  }
  await locator.fill(value, { timeout: 2500 });
  await page.keyboard.press('Tab');
  await page.waitForTimeout(250);
  await locator.click({ timeout: 2500 });
  if ((await locator.inputValue().catch(() => null)) !== value) {
    throw new Error('Flutter field did not retain its exact value.');
  }
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
