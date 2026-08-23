import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { webContentSecurityPolicy, writeWebCsp } from './write_web_csp.mjs';

const environment = {
  APP_ENV: 'pilot',
  USE_MOCK_DATA: 'false',
  COACH_SURFACE_ENABLED: 'true',
  APP_BUILD_SHA: 'a'.repeat(40),
  APP_RELEASE_TAG: 'v0.1.0-pilot.1-rc.1',
  STAGING_SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
  PILOT_SUPABASE_PROJECT_REF: 'bcdefghijklmnopqrstu',
  SUPABASE_URL: 'https://bcdefghijklmnopqrstu.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test-value',
  PILOT_CONTACT_EMAIL: 'pilot@example.test',
  APP_PUBLIC_ORIGIN: 'https://app.example.test',
  TURNSTILE_SITE_KEY: '1x00000000000000000000AA',
  AI_SERVICE_BASE_URL: 'https://api.example.test',
};

test('CSP narrows bearer and BYOK-capable connections to exact origins', () => {
  const policy = webContentSecurityPolicy(environment);
  assert.match(policy, /connect-src 'self'/);
  assert.match(policy, /https:\/\/bcdefghijklmnopqrstu\.supabase\.co/);
  assert.match(policy, /wss:\/\/bcdefghijklmnopqrstu\.supabase\.co/);
  assert.match(policy, /https:\/\/api\.example\.test/);
  assert.ok(!policy.includes("connect-src 'self' https: wss:"));
  assert.doesNotMatch(policy, /(?:^| )'unsafe-eval'(?: |;)/);
  assert.match(policy, /wasm-unsafe-eval/);
  assert.doesNotMatch(policy, /hcaptcha/i);
});

test('CSP writer injects one policy and rejects replacement', () => {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-csp-'));
  try {
    const index = join(root, 'index.html');
    writeFileSync(index, '<html>\n<head>\n  <meta charset="UTF-8">\n</head>\n</html>\n');
    writeWebCsp(index, environment);
    const result = readFileSync(index, 'utf8');
    assert.equal(result.match(/Content-Security-Policy/g)?.length, 1);
    assert.match(result, /https:\/\/api\.example\.test/);
    assert.throws(() => writeWebCsp(index, environment), /already contains/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
