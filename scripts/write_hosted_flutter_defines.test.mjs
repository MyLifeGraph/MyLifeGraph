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
  SUPABASE_URL: 'https://project-ref.supabase.co/',
  SUPABASE_ANON_KEY: 'publishable-test-value',
  AI_SERVICE_BASE_URL: 'https://coach-staging.example.test/',
};

test('hosted defines require complete fail-closed staging configuration', () => {
  assert.deepEqual(hostedFlutterDefines(validEnvironment), {
    APP_ENV: 'staging',
    USE_MOCK_DATA: 'false',
    COACH_SURFACE_ENABLED: 'true',
    SUPABASE_URL: 'https://project-ref.supabase.co',
    SUPABASE_ANON_KEY: 'publishable-test-value',
    AI_SERVICE_BASE_URL: 'https://coach-staging.example.test',
  });

  for (const name of [
    'APP_ENV',
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'AI_SERVICE_BASE_URL',
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

test('hosted defines reject insecure and credential-bearing endpoints', () => {
  for (const [name, value] of [
    ['SUPABASE_URL', 'http://project-ref.supabase.co'],
    ['SUPABASE_URL', 'https://example.test'],
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
      SUPABASE_URL: 'https://project-ref.supabase.co',
      SUPABASE_ANON_KEY: 'publishable-test-value',
      AI_SERVICE_BASE_URL: 'https://coach-staging.example.test',
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
