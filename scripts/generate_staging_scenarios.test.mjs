import assert from 'node:assert/strict';
import {
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  buildStagingScenarioCreatePlan,
  parseStagingScenarioArguments,
  runConfirmedStagingScenarioCleanup,
  stagingScenarioConfirmationFingerprint,
  stagingScenarioReceiptPath,
  stagingScenarioTarget,
} from './generate_staging_scenarios.mjs';
import {
  STAGING_SCENARIOS,
  STAGING_SCENARIO_MANIFEST_VERSION,
} from './staging_scenario_manifest.mjs';

const projectRef = 'oscrunlndfrecjilojja';
const environment = {
  STAGING_SUPABASE_PROJECT_REF: projectRef,
  STAGING_SUPABASE_URL: `https://${projectRef}.supabase.co`,
};
const target = stagingScenarioTarget(environment);

test('manifest contains the six immutable reviewable pilot scenarios', () => {
  assert.equal(STAGING_SCENARIO_MANIFEST_VERSION, 'staging-scenarios-v1');
  assert.deepEqual(
    STAGING_SCENARIOS.map((scenario) => scenario.id),
    [
      'fresh-account',
      'exam-week',
      'overdue-tasks',
      'sleep-deficit-high-stress',
      'existing-coach-history',
      'deadline-conflicts',
    ],
  );
  assert.ok(Object.isFrozen(STAGING_SCENARIOS));
  assert.ok(STAGING_SCENARIOS.every((scenario) => Object.isFrozen(scenario)));
});

test('target is hard allowlisted, HTTPS-bound, and rejects pilot crossover', () => {
  assert.deepEqual(target, {
    projectRef,
    pilotProjectRef: '',
    supabaseUrl: `https://${projectRef}.supabase.co`,
    expectedMigration: '20260819185740',
  });
  assert.throws(
    () =>
      stagingScenarioTarget({
        STAGING_SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
        STAGING_SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
      }),
    /immutable staging scenario allowlist/,
  );
  assert.throws(
    () =>
      stagingScenarioTarget({
        ...environment,
        PILOT_SUPABASE_PROJECT_REF: projectRef,
      }),
    /refuses the pilot project/,
  );
  assert.throws(
    () =>
      stagingScenarioTarget({
        ...environment,
        STAGING_SUPABASE_URL: `http://${projectRef}.supabase.co`,
      }),
    /HTTPS/,
  );
});

test('create preview binds exact scenario identities without secrets', () => {
  const plan = buildStagingScenarioCreatePlan({
    target,
    runId: 'professor-demo',
    requestedScenarioIds: ['overdue-tasks', 'fresh-account'],
  });
  assert.deepEqual(
    plan.scenarios.map((scenario) => scenario.id),
    ['fresh-account', 'overdue-tasks'],
  );
  assert.deepEqual(
    plan.scenarios.map((scenario) => scenario.identity.email),
    [
      'mylifegraph-staging+professor-demo-fresh-account@example.test',
      'mylifegraph-staging+professor-demo-overdue-tasks@example.test',
    ],
  );
  assert.equal(JSON.stringify(plan).includes('password'), false);
  assert.equal(JSON.stringify(plan).includes('secret'), false);

  const preview = {
    preview_version: 'staging-scenario-preview-v1',
    nonce: 'a'.repeat(32),
    previewed_at: '2026-08-19T12:00:00.000Z',
    expires_at: '2026-08-19T12:15:00.000Z',
    plan,
  };
  assert.match(
    stagingScenarioConfirmationFingerprint(preview),
    /^staging-scenarios-[0-9a-f]{20}$/,
  );
  assert.notEqual(
    stagingScenarioConfirmationFingerprint(preview),
    stagingScenarioConfirmationFingerprint({
      ...preview,
      nonce: 'b'.repeat(32),
    }),
  );
});

test('arguments are strict and cleanup cannot select new scenarios', () => {
  assert.deepEqual(
    parseStagingScenarioArguments([
      '--run',
      'professor-demo',
      '--scenarios',
      'fresh-account,exam-week',
    ]),
    {
      operation: 'create',
      runId: 'professor-demo',
      requestedScenarioIds: ['fresh-account', 'exam-week'],
      confirmation: null,
    },
  );
  assert.throws(
    () => parseStagingScenarioArguments(['--run', 'x']),
    /3-32 character/,
  );
  assert.throws(
    () =>
      parseStagingScenarioArguments([
        '--cleanup',
        '--run',
        'professor-demo',
        '--scenarios',
        'fresh-account',
      ]),
    /cannot be combined/,
  );
});

test('cleanup deletes only receipt-bound users and verifies absence', async () => {
  const receiptDir = mkdtempSync(join(tmpdir(), 'mylifegraph-scenarios-'));
  try {
    const runId = 'professor-demo';
    const userId = '11111111-1111-4111-8111-111111111111';
    const email =
      'mylifegraph-staging+professor-demo-fresh-account@example.test';
    const receiptPath = stagingScenarioReceiptPath(target, runId, receiptDir);
    writeFileSync(
      receiptPath,
      JSON.stringify({
        receipt_version: 'staging-scenario-receipt-v1',
        manifest_version: STAGING_SCENARIO_MANIFEST_VERSION,
        project_ref: projectRef,
        supabase_url: target.supabaseUrl,
        run_id: runId,
        scenario_ids: ['fresh-account'],
        status: 'ready',
        created_at: '2026-08-19T12:00:00.000Z',
        updated_at: '2026-08-19T12:00:00.000Z',
        users: [
          { scenario_id: 'fresh-account', email, user_id: userId },
        ],
      }),
      { mode: 0o600 },
    );
    const plan = {
      operation: 'cleanup',
      manifest_version: STAGING_SCENARIO_MANIFEST_VERSION,
      project_ref: projectRef,
      supabase_url: target.supabaseUrl,
      run_id: runId,
      users: [{ scenario_id: 'fresh-account', email, user_id: userId }],
    };
    let deleted = false;
    const calls = [];
    const fetchImpl = async (url, options = {}) => {
      const method = options.method ?? 'GET';
      calls.push({
        request: `${method} ${new URL(url).pathname}`,
        headers: options.headers,
      });
      if (method === 'DELETE') {
        deleted = true;
        return new Response(null, { status: 204 });
      }
      if (deleted) return new Response(null, { status: 404 });
      return Response.json({
        id: userId,
        email,
        user_metadata: {
          staging_scenario_version: STAGING_SCENARIO_MANIFEST_VERSION,
          staging_scenario_run: runId,
          staging_scenario_id: 'fresh-account',
        },
      });
    };

    const result = await runConfirmedStagingScenarioCleanup({
      target,
      plan,
      environment: { STAGING_SUPABASE_SECRET_KEY: 'sb_secret_test-value' },
      fetchImpl,
      receiptDir,
      now: new Date('2026-08-19T12:05:00.000Z'),
    });

    assert.deepEqual(result, { usersDeleted: 1 });
    assert.deepEqual(calls.map(({ request }) => request), [
      `GET /auth/v1/admin/users/${userId}`,
      `DELETE /auth/v1/admin/users/${userId}`,
      `GET /auth/v1/admin/users/${userId}`,
    ]);
    for (const call of calls) {
      assert.equal(call.headers.apikey, 'sb_secret_test-value');
      assert.equal('Authorization' in call.headers, false);
    }
    assert.equal(JSON.parse(readFileSync(receiptPath, 'utf8')).status, 'cleaned');
    assert.equal(statSync(receiptPath).mode & 0o777, 0o600);
  } finally {
    rmSync(receiptDir, { recursive: true, force: true });
  }
});

test('cleanup refuses a current Auth identity whose ownership marker drifted', async () => {
  const receiptDir = mkdtempSync(join(tmpdir(), 'mylifegraph-scenarios-'));
  try {
    const runId = 'professor-demo';
    const userId = '22222222-2222-4222-8222-222222222222';
    const email =
      'mylifegraph-staging+professor-demo-fresh-account@example.test';
    const receiptPath = stagingScenarioReceiptPath(target, runId, receiptDir);
    writeFileSync(
      receiptPath,
      JSON.stringify({
        receipt_version: 'staging-scenario-receipt-v1',
        manifest_version: STAGING_SCENARIO_MANIFEST_VERSION,
        project_ref: projectRef,
        supabase_url: target.supabaseUrl,
        run_id: runId,
        scenario_ids: ['fresh-account'],
        status: 'ready',
        created_at: '2026-08-19T12:00:00.000Z',
        updated_at: '2026-08-19T12:00:00.000Z',
        users: [
          { scenario_id: 'fresh-account', email, user_id: userId },
        ],
      }),
      { mode: 0o600 },
    );
    const plan = {
      operation: 'cleanup',
      manifest_version: STAGING_SCENARIO_MANIFEST_VERSION,
      project_ref: projectRef,
      supabase_url: target.supabaseUrl,
      run_id: runId,
      users: [{ scenario_id: 'fresh-account', email, user_id: userId }],
    };
    let deleteCalls = 0;
    const fetchImpl = async (_url, options = {}) => {
      if (options.method === 'DELETE') deleteCalls += 1;
      return Response.json({
        id: userId,
        email,
        user_metadata: {
          staging_scenario_version: STAGING_SCENARIO_MANIFEST_VERSION,
          staging_scenario_run: 'another-run',
          staging_scenario_id: 'fresh-account',
        },
      });
    };

    await assert.rejects(
      runConfirmedStagingScenarioCleanup({
        target,
        plan,
        environment: { STAGING_SUPABASE_SECRET_KEY: 'sb_secret_test-value' },
        fetchImpl,
        receiptDir,
      }),
      /Refusing to reuse or delete non-owned synthetic identity/,
    );
    assert.equal(deleteCalls, 0);
  } finally {
    rmSync(receiptDir, { recursive: true, force: true });
  }
});
