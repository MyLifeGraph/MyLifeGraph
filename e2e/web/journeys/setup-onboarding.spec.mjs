import {
  clickFlutterText,
  expectFlutterText,
  scrollFlutterTextIntoView,
  selectFlutterDropdownOption,
} from '../support/flutter-ui.mjs';
import { expect, test } from '../fixtures/e2e.fixture.mjs';

test('@setup-onboarding completes required Setup through Flutter', async ({
  page,
  e2e,
}) => {
  await e2e.signInUi({ expectedPath: '/onboarding' });
  await expectFlutterText(page, 'Required setup');
  await selectFlutterDropdownOption(
    page,
    'Typical weekday required',
    'School or work blocks',
  );
  await selectFlutterDropdownOption(
    page,
    'Best energy window required',
    'Morning',
  );
  await scrollFlutterTextIntoView(page, 'Save setup');
  await clickFlutterText(page, 'Save setup');

  await page.waitForURL('**/#/dashboard', { timeout: 45000 });
  await expectFlutterText(page, 'Today at a glance');
  const stored = await e2e.db.select(
    `intake_responses?select=version,base_revision,revision,state,responses,metadata&user_id=eq.${e2e.identity.user.id}`,
  );
  expect(stored.status).toBe(200);
  expect(stored.json).toHaveLength(1);
  expect(stored.json[0]).toMatchObject({
    version: 'intake-v1',
    base_revision: 0,
    revision: 1,
    state: 'applied',
    metadata: { source: 'onboarding' },
    responses: {
      weekday_shape: 'school_or_work',
      best_energy_window: 'morning',
      routines: [],
      fixed_commitments: [],
    },
  });
});
