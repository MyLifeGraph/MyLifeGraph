import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { cacheKey, cleanEnvironment, identity, manifest, validEntry } from './web_build_cache.mjs';

const inputs = {
  commit: 'current-commit', sources: 'source-content-hash',
  toolchain: { flutter: '3.44.0', framework: 'revision', engine: 'engine', dart: 'version', node: '20' },
  platform: 'linux', arch: 'x64', image: ['ubuntu24', 'image-version'],
};

test('exact build identity includes source, commit, toolchains, flags and runner', () => {
  const baseline = cacheKey(identity(inputs));
  assert.equal(cacheKey(identity(structuredClone(inputs))), baseline);
  for (const field of ['commit', 'sources', 'platform', 'arch', 'image', 'args']) {
    assert.notEqual(cacheKey(identity({ ...inputs, [field]: ['changed'] })), baseline, field);
  }
  for (const field of Object.keys(inputs.toolchain)) {
    assert.notEqual(cacheKey(identity({
      ...inputs, toolchain: { ...inputs.toolchain, [field]: 'changed' },
    })), baseline, field);
  }
});

test('credentials, signing, inherited defines and compiler flags never reach build', () => {
  const env = cleanEnvironment({
    Path: 'bin', TEMP: 'temp', PUB_CACHE: 'packages',
    SUPABASE_SERVICE_ROLE_KEY: 'secret', ANDROID_KEY_PASSWORD: 'secret',
    GOOGLE_APPLICATION_CREDENTIALS: 'secret-file', DART_DEFINES: 'secret',
    NODE_OPTIONS: '--require=injected.js', JAVA_TOOL_OPTIONS: 'injected',
    FLUTTER_BUILD_ARGS: '--release', FIREBASE_ANDROID_CONFIG_BASE64: 'secret',
  });
  assert.equal(env.Path, 'bin');
  assert.equal(env.PUB_CACHE, 'packages');
  assert.equal(Object.keys(env).length, 7);
  assert.equal(env.CI, 'true');
});

test('invalid, missing, altered or extra cache output fails closed', () => {
  const entry = mkdtempSync(join(tmpdir(), 'mlg-cache-test-'));
  try {
    const web = join(entry, 'web');
    mkdirSync(web);
    for (const file of ['index.html', 'flutter_bootstrap.js', 'main.dart.js']) {
      writeFileSync(join(web, file), 'verified build ' + file);
    }
    const expected = identity(inputs);
    const original = JSON.stringify({ identity: expected, files: manifest(web) });
    writeFileSync(join(entry, 'manifest.json'), original);
    assert.equal(validEntry(entry, expected), true);
    assert.equal(validEntry(entry, identity({ ...inputs, sources: 'changed' })), false);
    writeFileSync(join(web, 'extra.js'), 'unexpected');
    assert.equal(validEntry(entry, expected), false);
    rmSync(join(web, 'extra.js'));
    writeFileSync(join(web, 'main.dart.js'), 'corrupt');
    assert.equal(validEntry(entry, expected), false);
    writeFileSync(join(web, 'main.dart.js'), 'verified build main.dart.js');
    assert.equal(validEntry(entry, expected), true);
    rmSync(join(web, 'main.dart.js'));
    assert.equal(validEntry(entry, expected), false);
    writeFileSync(join(entry, 'manifest.json'), '{}');
    assert.equal(validEntry(entry, expected), false);
  } finally { rmSync(entry, { recursive: true, force: true }); }
});

test('dependency caches exclude build products and secrets; signing stays fresh', () => {
  for (const file of ['ci.yml', 'pilot-release-apk.yml', 'staging-debug-apk.yml']) {
    const workflow = readFileSync(new URL('../.github/workflows/' + file, import.meta.url), 'utf8');
    assert.doesNotMatch(workflow, /cache: gradle/);
    assert.match(workflow, /~\/.gradle\/caches\/modules-2/);
    assert.match(workflow, /pub-cache: false/);
    assert.match(workflow, /CI_NO_CACHE/);
    assert.match(workflow, /pub get --enforce-lockfile/);
    if (file !== 'ci.yml') {
      assert.match(workflow, /flutter build apk --release --no-pub/);
      assert.match(workflow, /apksigner verify --print-certs/);
      assert.doesNotMatch(workflow, /web_build_cache|restore-keys|cache-hit/);
    } else {
      assert.match(workflow, /flutter test --no-pub/);
      assert.match(workflow, /python -m pytest/);
      assert.match(workflow, /npm run e2e:web:full/);
    }
  }
});
