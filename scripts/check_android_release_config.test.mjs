import assert from 'node:assert/strict';
import test from 'node:test';

import { checkAndroidReleaseConfig } from './check_android_release_config.mjs';

test('Android release configuration check passes for the repository', () => {
  assert.doesNotThrow(() => checkAndroidReleaseConfig());
});
