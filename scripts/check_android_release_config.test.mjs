import assert from 'node:assert/strict';
import test from 'node:test';

import {
  checkAndroidReleaseConfig,
  requireExactProperties,
} from './check_android_release_config.mjs';

test('Android release configuration check passes for the repository', () => {
  assert.doesNotThrow(() => checkAndroidReleaseConfig());
});

const expectedWrapperProperties = {
  distributionSha256Sum: 'official-sha',
  distributionUrl: 'https\\://services.gradle.org/distributions/gradle.zip',
};

test('wrapper properties require unique active exact values', () => {
  assert.doesNotThrow(() =>
    requireExactProperties(
      [
        'distributionSha256Sum=official-sha',
        'distributionUrl=https\\://services.gradle.org/distributions/gradle.zip',
      ].join('\n'),
      expectedWrapperProperties,
      'test wrapper',
    ),
  );
  assert.throws(
    () =>
      requireExactProperties(
        [
          '# distributionSha256Sum=official-sha',
          'distributionSha256Sum=wrong-sha',
          'distributionUrl=https\\://services.gradle.org/distributions/gradle.zip',
        ].join('\n'),
        expectedWrapperProperties,
        'test wrapper',
      ),
    /requires exact distributionSha256Sum=official-sha/,
  );
  assert.throws(
    () =>
      requireExactProperties(
        [
          'distributionSha256Sum=official-sha',
          'distributionSha256Sum=wrong-sha',
          'distributionUrl=https\\://services.gradle.org/distributions/gradle.zip',
        ].join('\n'),
        expectedWrapperProperties,
        'test wrapper',
      ),
    /duplicate property distributionSha256Sum/,
  );
  assert.throws(
    () =>
      requireExactProperties(
        [
          'distributionSha256Sum=official-sha',
          'distributionUrl=https\\://services.gradle.org/distributions/gradle.zip',
          'validateDistributionUrl=false',
        ].join('\n'),
        expectedWrapperProperties,
        'test wrapper',
      ),
    /unexpected property validateDistributionUrl/,
  );
});
