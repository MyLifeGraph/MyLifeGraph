import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  hostedFlutterDefines,
  writeHostedFlutterDefines,
} from './write_hosted_flutter_defines.mjs';

const validEnvironment = {
  APP_ENV: 'staging',
  USE_MOCK_DATA: 'false',
  COACH_SURFACE_ENABLED: 'true',
  APP_BUILD_SHA: 'a'.repeat(40),
  APP_RELEASE_TAG: 'v0.1.0-pilot.1-rc.1',
  STAGING_SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
  SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co/',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test-value',
  PILOT_CONTACT_EMAIL: 'staging-contact@example.test',
  APP_PUBLIC_ORIGIN: 'https://app-staging.example.test/',
  TURNSTILE_SITE_KEY: '1x00000000000000000000AA',
  AI_SERVICE_BASE_URL: 'https://coach-staging.example.test/',
};

test('hosted defines require complete fail-closed staging configuration', () => {
  assert.deepEqual(hostedFlutterDefines(validEnvironment), {
    APP_ENV: 'staging',
    USE_MOCK_DATA: 'false',
    COACH_SURFACE_ENABLED: 'true',
    APP_BUILD_SHA: 'a'.repeat(40),
    APP_RELEASE_TAG: 'v0.1.0-pilot.1-rc.1',
    STAGING_SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
    PILOT_SUPABASE_PROJECT_REF: '',
    SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
    SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test-value',
    SUPABASE_ANON_KEY: '',
    PILOT_CONTACT_EMAIL: 'staging-contact@example.test',
    APP_PUBLIC_ORIGIN: 'https://app-staging.example.test',
    TURNSTILE_SITE_KEY: '1x00000000000000000000AA',
    AI_SERVICE_BASE_URL: 'https://coach-staging.example.test',
  });

  for (const name of [
    'APP_ENV',
    'STAGING_SUPABASE_PROJECT_REF',
    'SUPABASE_URL',
    'SUPABASE_PUBLISHABLE_KEY',
    'PILOT_CONTACT_EMAIL',
    'APP_PUBLIC_ORIGIN',
    'TURNSTILE_SITE_KEY',
    'AI_SERVICE_BASE_URL',
    'APP_BUILD_SHA',
    'APP_RELEASE_TAG',
  ]) {
    assert.throws(
      () => hostedFlutterDefines({ ...validEnvironment, [name]: '' }),
      new RegExp(name),
    );
  }
  assert.throws(
    () =>
      hostedFlutterDefines({ ...validEnvironment, USE_MOCK_DATA: 'true' }),
    /USE_MOCK_DATA/,
  );
  assert.throws(
    () =>
      hostedFlutterDefines({
        ...validEnvironment,
        COACH_SURFACE_ENABLED: 'false',
      }),
    /COACH_SURFACE_ENABLED/,
  );
});

test('hosted defines keep a bounded staging legacy-key transition', () => {
  const definitions = hostedFlutterDefines({
    ...validEnvironment,
    SUPABASE_PUBLISHABLE_KEY: '',
    SUPABASE_ANON_KEY: 'legacy-anon-test-value',
  });
  assert.equal(definitions.SUPABASE_PUBLISHABLE_KEY, '');
  assert.equal(definitions.SUPABASE_ANON_KEY, 'legacy-anon-test-value');

  const duringRotation = hostedFlutterDefines({
    ...validEnvironment,
    SUPABASE_ANON_KEY: 'different-legacy-value',
  });
  assert.equal(
    duringRotation.SUPABASE_PUBLISHABLE_KEY,
    validEnvironment.SUPABASE_PUBLISHABLE_KEY,
  );
  assert.equal(duringRotation.SUPABASE_ANON_KEY, '');
});

test('hosted defines reject framework-specific aliases', () => {
  const aliasesOnly = {
    ...validEnvironment,
    SUPABASE_URL: '',
    SUPABASE_PUBLISHABLE_KEY: '',
    VITE_SUPABASE_URL: validEnvironment.SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      validEnvironment.SUPABASE_PUBLISHABLE_KEY,
  };

  assert.throws(() => hostedFlutterDefines(aliasesOnly), /SUPABASE_URL/);
});

test('pilot builds require current keys and reject staging crossover', () => {
  const pilotEnvironment = {
    ...validEnvironment,
    APP_ENV: 'pilot',
    PILOT_SUPABASE_PROJECT_REF: 'bcdefghijklmnopqrstu',
    SUPABASE_URL: 'https://bcdefghijklmnopqrstu.supabase.co',
  };
  assert.equal(hostedFlutterDefines(pilotEnvironment).APP_ENV, 'pilot');
  assert.throws(
    () =>
      hostedFlutterDefines({
        ...pilotEnvironment,
        SUPABASE_PUBLISHABLE_KEY: '',
        SUPABASE_ANON_KEY: 'legacy-anon-test-value',
      }),
    /SUPABASE_PUBLISHABLE_KEY/,
  );
  assert.throws(
    () =>
      hostedFlutterDefines({
        ...pilotEnvironment,
        SUPABASE_URL: validEnvironment.SUPABASE_URL,
      }),
    /does not match/,
  );
  assert.throws(
    () =>
      hostedFlutterDefines({
        ...pilotEnvironment,
        PILOT_SUPABASE_PROJECT_REF:
          pilotEnvironment.STAGING_SUPABASE_PROJECT_REF,
      }),
    /must be distinct/,
  );
});

test('hosted defines reject insecure and credential-bearing endpoints', () => {
  for (const [name, value] of [
    ['SUPABASE_URL', 'http://abcdefghijklmnopqrst.supabase.co'],
    ['SUPABASE_URL', 'https://abcdefghijklmnopqrst.supabase.co:443'],
    ['SUPABASE_URL', 'https://example.test'],
    ['SUPABASE_URL', 'https://abcdefghijklmnopqrst.supabase.co/rest/v1'],
    ['AI_SERVICE_BASE_URL', 'http://coach.example.test'],
    ['AI_SERVICE_BASE_URL', 'https://user:secret@coach.example.test'],
    ['AI_SERVICE_BASE_URL', 'https://coach.example.test?token=secret'],
  ]) {
    assert.throws(
      () => hostedFlutterDefines({ ...validEnvironment, [name]: value }),
      new RegExp(name),
    );
  }
});

test('hosted defines are written with owner-only permissions', () => {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-hosted-defines-'));
  try {
    const outputPath = join(root, 'defines.json');
    writeHostedFlutterDefines(outputPath, validEnvironment);
    assert.equal(statSync(outputPath).mode & 0o777, 0o600);
    assert.deepEqual(JSON.parse(readFileSync(outputPath, 'utf8')), {
      APP_ENV: 'staging',
      USE_MOCK_DATA: 'false',
      COACH_SURFACE_ENABLED: 'true',
      APP_BUILD_SHA: 'a'.repeat(40),
      APP_RELEASE_TAG: 'v0.1.0-pilot.1-rc.1',
      STAGING_SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
      PILOT_SUPABASE_PROJECT_REF: '',
      SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test-value',
      SUPABASE_ANON_KEY: '',
      PILOT_CONTACT_EMAIL: 'staging-contact@example.test',
      APP_PUBLIC_ORIGIN: 'https://app-staging.example.test',
      TURNSTILE_SITE_KEY: '1x00000000000000000000AA',
      AI_SERVICE_BASE_URL: 'https://coach-staging.example.test',
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
