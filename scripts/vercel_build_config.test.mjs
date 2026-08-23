import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const build = readFileSync(new URL('./vercel_build.sh', import.meta.url), 'utf8');
const vercel = JSON.parse(
  readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'),
);

test('Vercel build uses an immutable official Flutter archive', () => {
  assert.match(build, /readonly FLUTTER_VERSION='3\.44\.0'/);
  assert.match(build, /559ffa3f75e7402d65a8def9c28389a9b2e6fe42/);
  assert.match(build, /e1ec95e6c550458a34de93580cb85dac24da0e9bedb9bb42811f050ac5a0c7d5/);
  assert.match(build, /SHA256SUM_BIN[^\n]*--check --strict/);
  assert.doesNotMatch(build, /command -v flutter/);
  assert.doesNotMatch(build, /git clone/);
  assert.match(build, /\/tmp\/\*\|\/var\/tmp\/\*\|\/home\/\*/);
  assert.match(build, /readonly VERCEL_BUILD_UID="\$\{EUID\}"/);
  assert.match(
    build,
    /tool[^\n]*'node'[^\n]*resolved[^\n]*'\/node24\/bin\/node'/,
  );
  assert.match(
    build,
    /\/node24\|\/node24\/bin\) parent_owner_trusted='true'/,
  );
  assert.match(build, /tool_uid[^\n]*== '0'/);
  assert.doesNotMatch(
    build,
    /(?:git|curl|sha256sum|tar)[^\n]*VERCEL_BUILD_UID/,
  );
  assert.match(build, /node_version[^\n]*--version/);
  assert.match(build, /\^v24\\\./);
  assert.match(build, /PATH='\/usr\/local\/bin:\/usr\/bin:\/bin'/);
  assert.match(build, /verify_vercel_build_identity\.mjs/);
  assert.match(build, /APP_BUILD_SHA="\$\{VERCEL_GIT_COMMIT_SHA-\}"/);
  assert.match(build, /APP_RELEASE_TAG="main-\$\{APP_BUILD_SHA\}"/);
  assert.match(build, /APP_RELEASE_TAG="preview-\$\{APP_BUILD_SHA\}"/);
  assert.match(build, /APP_ENV='pilot'/);
  assert.match(build, /APP_ENV='staging'/);
  assert.doesNotMatch(build, /VITE_|NEXT_PUBLIC_|RESOLVED_SUPABASE/);
  assert.match(build, /pub get --enforce-lockfile/);
  assert.match(build, /--no-web-resources-cdn --csp/);
  assert.match(build, /write_web_csp\.mjs/);
});

test('Vercel response headers enforce browser security boundaries', () => {
  const headers = vercel.headers.flatMap((rule) => rule.headers);
  const values = Object.fromEntries(headers.map(({ key, value }) => [key, value]));
  assert.match(values['Content-Security-Policy'], /frame-ancestors 'none'/);
  assert.match(values['Content-Security-Policy'], /object-src 'none'/);
  assert.equal(values['X-Frame-Options'], 'DENY');
  assert.equal(values['X-Content-Type-Options'], 'nosniff');
  assert.equal(values['Referrer-Policy'], 'no-referrer');
  assert.match(values['Permissions-Policy'], /camera=\(\)/);
  assert.equal(values['Cross-Origin-Opener-Policy'], 'same-origin-allow-popups');
  assert.equal(vercel.outputDirectory, 'apps/mobile/build/web');
});

test('Vercel child environment drops inherited sentinel secrets', () => {
  const result = spawnSync(
    '/bin/bash',
    [
      '-c',
      [
        'set -Eeuo pipefail',
        'source scripts/lib/vercel_build_environment.sh',
        'VERCEL_BUILD_HOME=/tmp',
        'VERCEL_BUILD_PATH=/usr/local/bin:/usr/bin:/bin',
        'VERCEL_PUB_CACHE=/tmp/mylifegraph-test-pub-cache',
        'APP_ENV=staging',
        'APP_BUILD_SHA=' + 'a'.repeat(40),
        'vercel_run_public /usr/bin/env',
      ].join('\n'),
    ],
    {
      cwd: new URL('..', import.meta.url),
      encoding: 'utf8',
      env: {
        PATH: process.env.PATH,
        SENTINEL_SECRET: 'must-not-reach-child',
        SUPABASE_ACCESS_TOKEN: 'must-not-reach-child-either',
        VITE_SUPABASE_URL: 'must-not-reach-child-vite',
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'must-not-reach-child-next',
        OPENAI_API_KEY: 'must-not-reach-child-openai',
        AWS_SECRET_ACCESS_KEY: 'must-not-reach-child-aws',
      },
    },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^APP_ENV=staging$/m);
  assert.doesNotMatch(result.stdout, /must-not-reach-child/);
  assert.doesNotMatch(
    result.stdout,
    /SUPABASE_ACCESS_TOKEN|VITE_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY|OPENAI_API_KEY|AWS_SECRET_ACCESS_KEY|SENTINEL_SECRET/,
  );
});
