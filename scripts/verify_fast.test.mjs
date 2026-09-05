import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

function runFixture(args, failGroup = '') {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-verify-groups-'));
  try {
    for (const directory of ['scripts', 'apps/mobile', 'services/ai_service']) {
      mkdirSync(join(root, directory), { recursive: true });
    }
    copyFileSync(new URL('./verify_fast.sh', import.meta.url), join(root, 'scripts/verify_fast.sh'));
    const paths = { source: 'scripts/verify_source.sh', flutter: 'flutter', backend: 'python' };
    for (const [group, path] of Object.entries(paths)) {
      writeFileSync(join(root, path), `#!/usr/bin/env bash
printf '%s\\n' '${group}' >> "$TEST_CALL_LOG"
[[ "$TEST_FAIL_GROUP" != '${group}' ]]
`, { mode: 0o700 });
    }
    const log = join(root, 'calls');
    const result = spawnSync('bash', [join(root, 'scripts/verify_fast.sh'), ...args], {
      encoding: 'utf8',
      env: {
        PATH: '/usr/bin:/bin',
        FLUTTER_BIN: join(root, 'flutter'),
        AI_SERVICE_PYTHON: join(root, 'python'),
        TEST_CALL_LOG: log,
        TEST_FAIL_GROUP: failGroup,
      },
    });
    assert.ifError(result.error);
    return {
      ...result,
      calls: existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').sort() : [],
    };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('default fast verification still executes every group', () => {
  const result = runFixture([]);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(result.calls, ['backend', 'backend', 'backend', 'flutter', 'flutter', 'flutter', 'source']);
});

test('an explicit group executes only that group', () => {
  for (const group of ['source', 'flutter', 'backend']) {
    const result = runFixture(['--group', group]);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.deepEqual(result.calls, Array(group === 'source' ? 1 : 3).fill(group));
  }
});

test('invalid group arguments fail before invoking tools', () => {
  for (const args of [['--group'], ['--group', 'unknown'], ['flutter'], ['--group', 'flutter', 'extra']]) {
    const result = runFixture(args);
    assert.equal(result.status, 64);
    assert.deepEqual(result.calls, []);
  }
});

test('a failing group fails the selected run and the complete run', () => {
  for (const group of ['source', 'flutter', 'backend']) {
    const selected = runFixture(['--group', group], group);
    assert.equal(selected.status, 1);
    assert.deepEqual(selected.calls, [group]);
    const full = runFixture([], group);
    assert.equal(full.status, 1);
    assert.deepEqual([...new Set(full.calls)].sort(), ['backend', 'flutter', 'source']);
  }
});
