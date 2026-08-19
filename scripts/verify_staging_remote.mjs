#!/usr/bin/env node

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

import {
  requireHttpsBaseUrl,
  requireProjectRef,
  resolveCompatibleKey,
} from './lib/supabase_deployment.mjs';

export const STAGING_HARNESS_VERSION = 'staging-remote-v1';
export const EXPECTED_MIGRATION = '20260819185740';

export function stagingTarget(environment = process.env) {
  const currentRef = environment.STAGING_SUPABASE_PROJECT_REF ?? '';
  const legacyRef = environment.STAGING_PROJECT_REF ?? '';
  if (currentRef && legacyRef && currentRef !== legacyRef) {
    throw new Error(
      'STAGING_SUPABASE_PROJECT_REF and STAGING_PROJECT_REF conflict.',
    );
  }
  const projectRef = requireProjectRef(
    'STAGING_SUPABASE_PROJECT_REF',
    currentRef || legacyRef,
  );
  const pilotProjectRef = requireProjectRef(
    'PILOT_SUPABASE_PROJECT_REF',
    environment.PILOT_SUPABASE_PROJECT_REF,
    { optional: true },
  );
  if (pilotProjectRef && pilotProjectRef === projectRef) {
    throw new Error('The staging harness refuses the pilot Supabase project.');
  }
  const supabaseUrl = requireHttpsBaseUrl(
    'STAGING_SUPABASE_URL',
    environment.STAGING_SUPABASE_URL,
    { supabaseProjectRef: projectRef },
  );
  const aiServiceBaseUrl = requireHttpsBaseUrl(
    'STAGING_AI_SERVICE_BASE_URL',
    environment.STAGING_AI_SERVICE_BASE_URL,
  );
  return {
    projectRef,
    pilotProjectRef,
    supabaseUrl,
    aiServiceBaseUrl,
    expectedMigration: EXPECTED_MIGRATION,
  };
}

export function stagingTargetFingerprint(target) {
  const digest = createHash('sha256')
    .update(
      [
        STAGING_HARNESS_VERSION,
        target.projectRef,
        target.pilotProjectRef,
        target.supabaseUrl,
        target.aiServiceBaseUrl,
        target.expectedMigration,
      ].join('|'),
    )
    .digest('hex');
  return `staging-target-${digest.slice(0, 16)}`;
}

function parseArguments(argv) {
  if (argv.length === 0) return { confirmation: null };
  if (argv.length === 2 && argv[0] === '--confirm') {
    return { confirmation: argv[1] };
  }
  throw new Error(
    'Usage: npm run verify:staging:remote -- [--confirm <fingerprint>]',
  );
}

function requiredSecret(environment, name) {
  const value = environment[name];
  if (!value) throw new Error(`${name} is required for a confirmed run.`);
  return value;
}

async function request(
  url,
  { method = 'GET', headers = {}, body, fetchImpl = globalThis.fetch } = {},
) {
  const response = await fetchImpl(url, {
    method,
    headers: {
      ...headers,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(30_000),
  });
  let json = null;
  const text = await response.text();
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      // Status-only assertions deliberately avoid echoing remote bodies.
    }
  }
  return { status: response.status, ok: response.ok, json };
}

function requireStatus(result, expected, context) {
  const accepted = Array.isArray(expected) ? expected : [expected];
  if (!accepted.includes(result.status)) {
    throw new Error(`${context} returned unexpected HTTP ${result.status}.`);
  }
  return result;
}

function requireArray(result, context) {
  if (!Array.isArray(result.json)) {
    throw new Error(`${context} returned an invalid JSON shape.`);
  }
  return result.json;
}

function assertNotPresent(payload, marker, context) {
  if (JSON.stringify(payload).includes(marker)) {
    throw new Error(`${context} exposed another user's staging marker.`);
  }
}

export class ExactRemoteAuthUsers {
  constructor({ supabaseUrl, serviceRoleKey, fetchImpl = globalThis.fetch }) {
    this.supabaseUrl = supabaseUrl;
    this.serviceRoleKey = serviceRoleKey;
    this.fetchImpl = fetchImpl;
    this.userIds = [];
  }

  headers(json = false) {
    return {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
      ...(json ? { 'Content-Type': 'application/json' } : {}),
    };
  }

  async create({ email, password, displayName }) {
    const result = await request(`${this.supabaseUrl}/auth/v1/admin/users`, {
      method: 'POST',
      headers: this.headers(),
      body: {
        email,
        password,
        email_confirm: true,
        user_metadata: { display_name: displayName },
      },
      fetchImpl: this.fetchImpl,
    });
    requireStatus(result, 200, 'Exact staging Auth user creation');
    if (typeof result.json?.id !== 'string') {
      throw new Error('Exact staging Auth user creation returned no UUID.');
    }
    this.userIds.push(result.json.id);
    return result.json.id;
  }

  async cleanup() {
    let failures = 0;
    for (const userId of [...this.userIds].reverse()) {
      const deleted = await request(
        `${this.supabaseUrl}/auth/v1/admin/users/${userId}`,
        {
          method: 'DELETE',
          headers: this.headers(),
          fetchImpl: this.fetchImpl,
        },
      );
      if (![200, 204, 404].includes(deleted.status)) {
        failures += 1;
        continue;
      }
      const remaining = await request(
        `${this.supabaseUrl}/auth/v1/admin/users/${userId}`,
        { headers: this.headers(), fetchImpl: this.fetchImpl },
      );
      if (remaining.status !== 404) failures += 1;
    }
    if (failures > 0) {
      throw new Error(
        `Cleanup failed for ${failures} exact staging Auth user(s).`,
      );
    }
    return this.userIds.length;
  }
}

async function signIn({ target, publishableKey, email, password, fetchImpl }) {
  const result = await request(
    `${target.supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: { apikey: publishableKey },
      body: { email, password },
      fetchImpl,
    },
  );
  requireStatus(result, 200, 'Exact staging Auth sign-in');
  if (typeof result.json?.access_token !== 'string') {
    throw new Error('Exact staging Auth sign-in returned no access token.');
  }
  return result.json.access_token;
}

function dataHeaders(publishableKey, accessToken, { returnRows = false } = {}) {
  return {
    apikey: publishableKey,
    Authorization: `Bearer ${accessToken}`,
    ...(returnRows ? { Prefer: 'return=representation' } : {}),
  };
}

async function insertOwnedRow({
  target,
  table,
  row,
  publishableKey,
  accessToken,
  fetchImpl,
}) {
  const result = await request(`${target.supabaseUrl}/rest/v1/${table}`, {
    method: 'POST',
    headers: dataHeaders(publishableKey, accessToken, { returnRows: true }),
    body: row,
    fetchImpl,
  });
  requireStatus(result, 201, `${table} owner insert`);
  const rows = requireArray(result, `${table} owner insert`);
  if (rows.length !== 1 || typeof rows[0]?.id !== 'string') {
    throw new Error(`${table} owner insert returned an invalid row.`);
  }
  return rows[0];
}

async function selectRows({
  target,
  table,
  query,
  publishableKey,
  accessToken,
  fetchImpl,
}) {
  const result = await request(
    `${target.supabaseUrl}/rest/v1/${table}?select=*&${query}`,
    { headers: dataHeaders(publishableKey, accessToken), fetchImpl },
  );
  requireStatus(result, 200, `${table} scoped select`);
  return requireArray(result, `${table} scoped select`);
}

async function backendRequest({
  target,
  path,
  accessToken,
  method,
  body,
  fetchImpl,
}) {
  const result = await request(`${target.aiServiceBaseUrl}${path}`, {
    method,
    headers: { Authorization: `Bearer ${accessToken}` },
    body,
    fetchImpl,
  });
  requireStatus(result, 200, `${method ?? 'GET'} ${path}`);
  return result.json;
}

async function completeMinimalIntake({
  target,
  accessToken,
  marker,
  fetchImpl,
}) {
  return backendRequest({
    target,
    path: '/v1/intake/complete',
    accessToken,
    method: 'POST',
    body: {
      request_id: randomUUID(),
      base_revision: 0,
      version: 'intake-v1',
      responses: {
        display_name: marker,
        weekday_shape: 'Remote staging isolation check',
        best_energy_window: 'morning',
        routines: [],
        fixed_commitments: [],
        calendar_connection_intent: 'not_now',
      },
      metadata: { source: STAGING_HARNESS_VERSION },
    },
    fetchImpl,
  });
}

async function acceptPilotParticipation({
  target,
  accessToken,
  fetchImpl,
}) {
  const result = await backendRequest({
    target,
    path: '/v1/account/pilot-participation',
    accessToken,
    method: 'POST',
    body: {
      contract_version: 'pilot-participation-v1',
      notice_version: 'pilot-participation-notice-v1',
      confirmed_18_or_older: true,
    },
    fetchImpl,
  });
  if (
    result?.contract_version !== 'pilot-participation-v1' ||
    result?.notice_version !== 'pilot-participation-notice-v1' ||
    typeof result?.accepted_at !== 'string' ||
    typeof result?.replayed !== 'boolean'
  ) {
    throw new Error('Staging participation returned an invalid contract.');
  }
}

export async function runConfirmedStagingHarness({
  target,
  environment = process.env,
  fetchImpl = globalThis.fetch,
}) {
  const publishableKey = requiredSecret(
    environment,
    'STAGING_SUPABASE_PUBLISHABLE_KEY',
  );
  const backendKey = resolveCompatibleKey({
    environment,
    currentName: 'STAGING_SUPABASE_SECRET_KEY',
    legacyName: 'STAGING_SUPABASE_SERVICE_ROLE_KEY',
    currentPrefix: 'sb_secret_',
    context: 'confirmed staging harness',
  }).value;
  const authUsers = new ExactRemoteAuthUsers({
    supabaseUrl: target.supabaseUrl,
    serviceRoleKey: backendKey,
    fetchImpl,
  });
  const runId = `${Date.now()}-${randomBytes(4).toString('hex')}`;
  const markerA = `staging-a-${runId}`;
  const markerB = `staging-b-${runId}`;
  const passwordA = `${randomBytes(24).toString('base64url')}!Aa1`;
  const passwordB = `${randomBytes(24).toString('base64url')}!Bb2`;
  let primaryError = null;

  try {
    const health = await request(`${target.aiServiceBaseUrl}/v1/health`, {
      fetchImpl,
    });
    requireStatus(health, 200, 'Staging FastAPI health');

    const userA = await authUsers.create({
      email: `mylifegraph-${markerA}@example.test`,
      password: passwordA,
      displayName: markerA,
    });
    const userB = await authUsers.create({
      email: `mylifegraph-${markerB}@example.test`,
      password: passwordB,
      displayName: markerB,
    });
    const tokenA = await signIn({
      target,
      publishableKey,
      email: `mylifegraph-${markerA}@example.test`,
      password: passwordA,
      fetchImpl,
    });
    const tokenB = await signIn({
      target,
      publishableKey,
      email: `mylifegraph-${markerB}@example.test`,
      password: passwordB,
      fetchImpl,
    });

    await acceptPilotParticipation({
      target,
      accessToken: tokenA,
      fetchImpl,
    });
    await acceptPilotParticipation({
      target,
      accessToken: tokenB,
      fetchImpl,
    });

    await completeMinimalIntake({
      target,
      accessToken: tokenA,
      marker: markerA,
      fetchImpl,
    });
    await completeMinimalIntake({
      target,
      accessToken: tokenB,
      marker: markerB,
      fetchImpl,
    });

    const task = await insertOwnedRow({
      target,
      table: 'tasks',
      row: {
        user_id: userA,
        title: markerA,
        priority: 'medium',
        estimated_minutes: 25,
        metadata: { source: STAGING_HARNESS_VERSION },
      },
      publishableKey,
      accessToken: tokenA,
      fetchImpl,
    });
    const habit = await insertOwnedRow({
      target,
      table: 'habits',
      row: {
        user_id: userA,
        title: markerA,
        frequency: 'daily',
        target: 1,
        metadata: { source: STAGING_HARNESS_VERSION },
      },
      publishableKey,
      accessToken: tokenA,
      fetchImpl,
    });
    await insertOwnedRow({
      target,
      table: 'schedule_items',
      row: {
        user_id: userA,
        title: markerA,
        weekday: 1,
        starts_at: '09:00:00',
        ends_at: '10:00:00',
        metadata: { source: STAGING_HARNESS_VERSION },
      },
      publishableKey,
      accessToken: tokenA,
      fetchImpl,
    });
    const startedAt = new Date(Date.now() - 30 * 60 * 1000).toISOString();
    const endedAt = new Date(
      new Date(startedAt).getTime() + 25 * 60 * 1000,
    ).toISOString();
    const focus = await insertOwnedRow({
      target,
      table: 'focus_sessions',
      row: {
        user_id: userA,
        started_at: startedAt,
        planned_minutes: 25,
        status: 'active',
        task_id: task.id,
        label: markerA,
        metadata: { source: STAGING_HARNESS_VERSION },
      },
      publishableKey,
      accessToken: tokenA,
      fetchImpl,
    });
    const focusFinish = await request(
      `${target.supabaseUrl}/rest/v1/focus_sessions?id=eq.${focus.id}`,
      {
        method: 'PATCH',
        headers: dataHeaders(publishableKey, tokenA, { returnRows: true }),
        body: {
          status: 'completed',
          ended_at: endedAt,
          actual_minutes: 25,
        },
        fetchImpl,
      },
    );
    requireStatus(focusFinish, 200, 'focus_sessions owner finish');
    if (requireArray(focusFinish, 'focus_sessions owner finish').length !== 1) {
      throw new Error('focus_sessions owner finish changed no exact row.');
    }

    for (const [table, id] of [
      ['tasks', task.id],
      ['habits', habit.id],
      ['focus_sessions', focus.id],
    ]) {
      const ownerRows = await selectRows({
        target,
        table,
        query: `id=eq.${id}`,
        publishableKey,
        accessToken: tokenA,
        fetchImpl,
      });
      if (ownerRows.length !== 1) {
        throw new Error(`${table} owner could not read the exact staging row.`);
      }
      const foreignRows = await selectRows({
        target,
        table,
        query: `id=eq.${id}`,
        publishableKey,
        accessToken: tokenB,
        fetchImpl,
      });
      if (foreignRows.length !== 0) {
        throw new Error(`${table} exposed an exact foreign staging row.`);
      }
    }

    const foreignUpdate = await request(
      `${target.supabaseUrl}/rest/v1/tasks?id=eq.${task.id}`,
      {
        method: 'PATCH',
        headers: dataHeaders(publishableKey, tokenB, { returnRows: true }),
        body: { title: markerB },
        fetchImpl,
      },
    );
    requireStatus(foreignUpdate, 200, 'Foreign task update');
    if (requireArray(foreignUpdate, 'Foreign task update').length !== 0) {
      throw new Error('Foreign task update changed an exact staging row.');
    }
    const foreignDelete = await request(
      `${target.supabaseUrl}/rest/v1/tasks?id=eq.${task.id}`,
      {
        method: 'DELETE',
        headers: dataHeaders(publishableKey, tokenB, { returnRows: true }),
        fetchImpl,
      },
    );
    requireStatus(foreignDelete, 200, 'Foreign task delete');
    if (requireArray(foreignDelete, 'Foreign task delete').length !== 0) {
      throw new Error('Foreign task delete removed an exact staging row.');
    }
    const taskAfterForeignDelete = await selectRows({
      target,
      table: 'tasks',
      query: `id=eq.${task.id}`,
      publishableKey,
      accessToken: tokenA,
      fetchImpl,
    });
    if (taskAfterForeignDelete.length !== 1) {
      throw new Error('Owner task disappeared after a foreign delete attempt.');
    }
    const forgedInsert = await request(`${target.supabaseUrl}/rest/v1/tasks`, {
      method: 'POST',
      headers: dataHeaders(publishableKey, tokenB, { returnRows: true }),
      body: { user_id: userA, title: markerB, priority: 'medium' },
      fetchImpl,
    });
    if (forgedInsert.ok) {
      throw new Error('Forged foreign task insert unexpectedly succeeded.');
    }

    const foreignFocusFinish = await request(
      `${target.aiServiceBaseUrl}/v1/focus/sessions/${focus.id}/finish`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${tokenB}` },
        fetchImpl,
      },
    );
    requireStatus(foreignFocusFinish, 404, 'Foreign FastAPI focus update');

    const planner = await backendRequest({
      target,
      path: '/v1/planner/overview',
      accessToken: tokenA,
      fetchImpl,
    });
    if (typeof planner?.local_date !== 'string') {
      throw new Error('Planner overview returned no local date.');
    }
    const captureId = `${markerA}-${randomUUID()}`;
    await backendRequest({
      target,
      path: `/v1/daily-capture/${planner.local_date}/evening`,
      accessToken: tokenA,
      method: 'PUT',
      body: {
        contract_version: 'daily-capture-write-v1',
        request_id: randomUUID(),
        expected_capture: null,
        capture: {
          branch_version: 'daily-capture-v5',
          capture_kind: 'evening',
          entry_date: planner.local_date,
          capture_id: captureId,
          captured_at: new Date().toISOString(),
          mood: 7,
          energy: 6,
          stress_intensity: 3,
          stress_intensity_label: 'low',
          planned_sleep_time: '23:00',
          sleep_target_minutes: 480,
        },
      },
      fetchImpl,
    });
    await backendRequest({
      target,
      path: '/v1/snapshots/generate',
      accessToken: tokenA,
      method: 'POST',
      body: { scope: 'daily' },
      fetchImpl,
    });
    await backendRequest({
      target,
      path: '/v1/briefings/generate',
      accessToken: tokenA,
      method: 'POST',
      body: { force: true },
      fetchImpl,
    });

    for (const path of [
      '/v1/today/overview-v2',
      '/v1/planner/overview',
      '/v1/briefings/today',
      '/v1/coach/history',
    ]) {
      const ownerPayload = await backendRequest({
        target,
        path,
        accessToken: tokenA,
        fetchImpl,
      });
      const foreignPayload = await backendRequest({
        target,
        path,
        accessToken: tokenB,
        fetchImpl,
      });
      assertNotPresent(foreignPayload, markerA, path);
      if (path === '/v1/today/overview-v2') {
        if (!JSON.stringify(ownerPayload).includes(markerA)) {
          throw new Error('Today overview omitted the owner staging marker.');
        }
      }
    }
    await backendRequest({
      target,
      path: '/v1/coach/history',
      accessToken: tokenA,
      method: 'DELETE',
      fetchImpl,
    });

    return { usersCreated: 2, isolationTables: 3, backendReads: 4 };
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    try {
      const deleted = await authUsers.cleanup();
      if (!primaryError && deleted !== 2) {
        throw new Error('Cleanup did not remove both exact staging Auth users.');
      }
    } catch (cleanupError) {
      if (!primaryError) throw cleanupError;
      throw new AggregateError(
        [primaryError, cleanupError],
        'Staging verification and exact Auth cleanup both failed.',
      );
    }
  }
}

async function main() {
  const { confirmation } = parseArguments(process.argv.slice(2));
  const target = stagingTarget(process.env);
  const fingerprint = stagingTargetFingerprint(target);
  console.log(`Staging project ref: ${target.projectRef}`);
  console.log(
    `Pilot crossover guard: ${target.pilotProjectRef ? 'configured' : 'not configured'}`,
  );
  console.log(`Staging Supabase host: ${new URL(target.supabaseUrl).hostname}`);
  console.log(`Staging FastAPI host: ${new URL(target.aiServiceBaseUrl).hostname}`);
  console.log(`Expected migration: ${target.expectedMigration}`);
  console.log(`Required confirmation: ${fingerprint}`);

  if (confirmation === null) {
    console.log(
      `Preview only. Rerun with --confirm ${fingerprint} to create and clean up exactly two temporary staging users.`,
    );
    return;
  }
  if (confirmation !== fingerprint) {
    throw new Error('Confirmation does not match the current staging target.');
  }
  const result = await runConfirmedStagingHarness({ target });
  console.log(
    `Staging isolation passed: ${result.usersCreated} exact users, ${result.isolationTables} RLS tables, ${result.backendReads} backend reads; exact Auth cleanup passed.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
