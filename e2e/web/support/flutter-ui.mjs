export function flutterRoute(appUrl, path) {
  return `${appUrl.replace(/\/$/, '')}/#${path}`;
}

export async function waitForFlutterShell(page) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      await page.locator('flt-glass-pane, flutter-view').first().waitFor({
        state: 'attached',
        timeout: 30000,
      });
      return;
    } catch (error) {
      lastError = error;
      if (attempt < 2) {
        await page.reload({
          waitUntil: 'domcontentloaded',
          timeout: 30000,
        });
      }
    }
  }
  throw lastError ?? new Error('Flutter shell did not attach.');
}

export async function enableFlutterSemantics(page) {
  const preEnabled = process.env.E2E_SEMANTICS_PRE_ENABLED === 'true';
  const startedAt = performance.now();
  const semantics = page.locator('flt-semantics').first();
  let mode = preEnabled ? 'pre_enabled' : 'click_fallback';
  if (preEnabled) {
    await semantics.waitFor({ state: 'attached', timeout: 1000 }).catch(() => {});
  }
  if ((await semantics.count()) === 0) {
    mode = 'click_fallback';
    const accessibilityButton = page.getByRole('button', {
      name: /enable accessibility/i,
    });
    try {
      await accessibilityButton.waitFor({ state: 'attached', timeout: 10000 });
      await accessibilityButton.evaluate((element) => element.click());
    } catch {
      await page.locator('flt-semantics-placeholder').evaluate(
        (element) => element.click(),
      );
    }
    await semantics.waitFor({
      state: 'attached',
      timeout: 10000,
    });
  }
  console.log(
    `[e2e:timing] ${JSON.stringify({
      phase: 'semantics_spec',
      duration_ms: Math.round(performance.now() - startedAt),
      mode,
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
  expectedPath = '/dashboard',
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
  await page.waitForURL(`**/#${expectedPath}**`, { timeout: 45000 });
}

export async function openFlutterRoute(page, appUrl, path) {
  await page.goto(flutterRoute(appUrl, path), {
    waitUntil: 'domcontentloaded',
  });
  await waitForFlutterShell(page);
  await enableFlutterSemantics(page);
}

export async function fillFlutterField(
  page,
  label,
  value,
  fallbackIndex = 0,
) {
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

export async function clickFlutterText(
  page,
  text,
  { match = 'first', timeout = 7500 } = {},
) {
  const exactButton = page.getByRole('button', {
    name: text,
    exact: true,
  });
  const partialButton = page.getByRole('button', {
    name: new RegExp(escapeRegExp(text), 'i'),
  });
  const exactText = page.getByText(text, { exact: true });
  const partialText = page.getByText(text);
  const candidates = [
    exactButton,
    partialButton,
    exactText,
    partialText,
  ].map((locator) => (match === 'last' ? locator.last() : locator.first()));
  let lastError;
  for (const candidate of candidates) {
    try {
      await candidate.click({ timeout });
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? new Error(`No Flutter control matched ${text}.`);
}

export async function scrollFlutterPage(page, deltaY) {
  const root = page.locator('flt-glass-pane, flutter-view').first();
  const box = await root.boundingBox();
  await page.mouse.move(
    box ? box.x + box.width / 2 : 640,
    box ? box.y + box.height / 2 : 480,
  );
  const direction = deltaY >= 0 ? 1 : -1;
  for (let remaining = Math.abs(deltaY); remaining > 0; remaining -= 700) {
    await page.mouse.wheel(0, direction * Math.min(700, remaining));
    await page.waitForTimeout(100);
  }
}

export async function scrollFlutterTextIntoView(
  page,
  text,
  { deltaY = 700, maxSteps = 20 } = {},
) {
  const viewport = page.viewportSize();
  for (let step = 0; step <= maxSteps; step += 1) {
    const candidates = [
      page.getByRole('button', {
        name: new RegExp(escapeRegExp(text), 'i'),
      }),
      page.getByText(text, { exact: true }),
      page.getByText(text),
      page.getByLabel(text, { exact: false }),
    ];
    for (const candidate of candidates) {
      const count = await candidate.count();
      for (let index = 0; index < count; index += 1) {
        const item = candidate.nth(index);
        const box = await item.boundingBox().catch(() => null);
        if (
          box &&
          box.width > 0 &&
          box.height > 0 &&
          (!viewport || (box.y < viewport.height && box.y + box.height > 0))
        ) {
          return item;
        }
      }
    }
    if (step < maxSteps) await scrollFlutterPage(page, deltaY);
  }
  throw new Error(`Could not bring ${text} into the Flutter viewport.`);
}

export async function selectFlutterDropdownOption(page, label, option) {
  const labelNode = page.getByText(label, { exact: true }).first();
  await labelNode.waitFor({ state: 'visible', timeout: 5000 });
  const labelBox = await labelNode.boundingBox();
  if (!labelBox) throw new Error(`No rendered Flutter label matched ${label}.`);

  const buttons = page.getByRole('button');
  let field = null;
  let distance = Number.POSITIVE_INFINITY;
  for (let index = 0; index < (await buttons.count()); index += 1) {
    const candidate = buttons.nth(index);
    const box = await candidate.boundingBox().catch(() => null);
    if (
      !box ||
      box.y < labelBox.y - 8 ||
      box.y > labelBox.y + 100 ||
      box.x < labelBox.x - 40
    ) {
      continue;
    }
    const candidateDistance = Math.abs(box.y - labelBox.y);
    if (candidateDistance < distance) {
      field = candidate;
      distance = candidateDistance;
    }
  }
  if (field === null) {
    throw new Error(`No Flutter dropdown field was adjacent to ${label}.`);
  }
  await field.evaluate((element) => element.click());

  const optionPattern = new RegExp(`^${escapeRegExp(option)}$`, 'i');
  const choices = [
    page.getByRole('menuitem', { name: optionPattern }).last(),
    page.getByRole('option', { name: optionPattern }).last(),
    page.getByRole('button', { name: optionPattern }).last(),
    page.getByText(option, { exact: true }).last(),
  ];
  for (let attempt = 0; attempt < 20; attempt += 1) {
    for (const choice of choices) {
      if ((await choice.count()) === 0) continue;
      await choice.evaluate((element) => element.click());
      await page.waitForTimeout(250);
      return;
    }
    await page.waitForTimeout(100);
  }
  throw new Error(`No open Flutter option matched ${option}.`);
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
