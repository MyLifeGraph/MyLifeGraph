import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  checkAndroidReleaseConfig,
  requireExactJavaVersion,
  requireExactProperties,
} from './check_android_release_config.mjs';

test('Android release configuration check passes for the repository', () => {
  assert.doesNotThrow(() => checkAndroidReleaseConfig());
});

test('blocking notification artwork decodes a PNG, not adaptive launcher XML', () => {
  const source = readFileSync(new URL(
    '../apps/mobile/android/app/src/main/kotlin/com/mylifegraph/app/BlockingTimerNotifications.kt',
    import.meta.url,
  ), 'utf8');
  assert.match(source,
    /BitmapFactory\.decodeResource\(\s*context\.resources,\s*R\.drawable\.app_launcher_art\s*\)/);
  const artwork = readFileSync(new URL(
    '../apps/mobile/android/app/src/main/res/drawable-nodpi/app_launcher_art.png',
    import.meta.url,
  ));
  assert.deepEqual(artwork.subarray(0, 8),
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
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

test('Android workflows require one exact Java 21 toolchain', () => {
  assert.doesNotThrow(() =>
    requireExactJavaVersion("java-version: '21'", '21', 'test workflow'),
  );
  assert.throws(
    () => requireExactJavaVersion("java-version: '17'", '21', 'test workflow'),
    /requires exact java-version 21/,
  );
  assert.throws(
    () =>
      requireExactJavaVersion(
        "java-version: '21'\njava-version: '21'",
        '21',
        'test workflow',
      ),
    /requires exactly one active java-version/,
  );
  assert.throws(
    () => requireExactJavaVersion('java-version: ${JAVA}', '21', 'test workflow'),
    /malformed java-version/,
  );
});
