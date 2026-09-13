import assert from 'node:assert/strict';
import test from 'node:test';

import { androidCiBuildNumber, androidMainIdentity, androidReleaseIdentity } from './android_release_identity.mjs';

test('automatic and tagged builds share a stable increasing CI versionCode', () => {
  const sha = 'a'.repeat(40);
  assert.deepEqual(androidMainIdentity(sha, '150'), {
    build_name: 'main-aaaaaaaaaaaa', build_number: '10000150',
  });
  assert.equal(androidReleaseIdentity('v0.1.0-pilot.1-rc.1', '150').build_number,
    androidMainIdentity(sha, '150').build_number);
  assert.ok(Number(androidCiBuildNumber('151')) > Number(androidCiBuildNumber('150')));
  for (const count of ['0', '-1', '01', '1.2', 'Infinity', '2090000001', 'x']) {
    assert.throws(() => androidCiBuildNumber(count));
  }
  assert.throws(() => androidMainIdentity('short', '150'));
});

test('derives a stable monotonic Android identity from an RC tag', () => {
  assert.deepEqual(androidReleaseIdentity('v0.1.0-pilot.1-rc.1'), {
    build_name: '0.1.0-pilot.1-rc.1',
    build_number: '1000101',
  });
  assert.equal(
    Number(androidReleaseIdentity('v0.1.0-pilot.2-rc.1').build_number) >
      Number(androidReleaseIdentity('v0.1.0-pilot.1-rc.99').build_number),
    true,
  );
  assert.equal(
    Number(androidReleaseIdentity('v0.1.1-pilot.1-rc.1').build_number) >
      Number(androidReleaseIdentity('v0.1.0-pilot.99-rc.99').build_number),
    true,
  );
});

test('rejects final, malformed, negative, and overflowing tag identities', () => {
  for (const tag of [
    'v0.1.0-pilot.1',
    '0.1.0-pilot.1-rc.1',
    'v0.1.0-pilot.-1-rc.1',
    'v21.0.0-pilot.1-rc.1',
    'v0.100.0-pilot.1-rc.1',
    'v0.1.0-pilot.100-rc.1',
    'v0.01.0-pilot.1-rc.1',
    'v00.1.0-pilot.1-rc.1',
    'v0.1.0-pilot.01-rc.1',
    'v0.1.0-pilot.1-rc.01',
  ]) {
    assert.throws(() => androidReleaseIdentity(tag));
  }
});
