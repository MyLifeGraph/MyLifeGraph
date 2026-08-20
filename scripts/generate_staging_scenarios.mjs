#!/usr/bin/env node

import { createHash, randomBytes } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  requireHttpsBaseUrl,
  requireProjectRef,
  resolveCompatibleKey,
  supabaseBackendHeaders,
} from './lib/supabase_deployment.mjs';
import {
  STAGING_SCENARIO_ALLOWED_PROJECT_REFS,
  STAGING_SCENARIO_MANIFEST_VERSION,
  selectStagingScenarios,
  stagingScenarioIdentity,
} from './staging_scenario_manifest.mjs';

export const STAGING_SCENARIO_EXPECTED_MIGRATION = '20260819185740';
export const STAGING_SCENARIO_PREVIEW_MAX_AGE_MS = 15 * 60 * 1000;

const RECEIPT_VERSION = 'staging-scenario-receipt-v1';
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const RUN_ID_PATTERN = /^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$/;
const DEFAULT_RECEIPT_DIR = fileURLToPath(
  new URL('../.tools/staging-scenarios/', import.meta.url),
);

export function stagingScenarioTarget(environment = process.env) {
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
  if (!STAGING_SCENARIO_ALLOWED_PROJECT_REFS.includes(projectRef)) {
    throw new Error(
      'The target is not in the immutable staging scenario allowlist.',
    );
  }
  const pilotProjectRef = requireProjectRef(
    'PILOT_SUPABASE_PROJECT_REF',
    environment.PILOT_SUPABASE_PROJECT_REF,
    { optional: true },
  );
  if (pilotProjectRef && pilotProjectRef === projectRef) {
    throw new Error('The staging scenario generator refuses the pilot project.');
  }
  const supabaseUrl = requireHttpsBaseUrl(
    'STAGING_SUPABASE_URL',
    environment.STAGING_SUPABASE_URL,
    { supabaseProjectRef: projectRef },
  );
  return Object.freeze({
    projectRef,
    pilotProjectRef,
    supabaseUrl,
    expectedMigration: STAGING_SCENARIO_EXPECTED_MIGRATION,
  });
}

export function parseStagingScenarioArguments(argv) {
  let operation = 'create';
  let runId = '';
  let confirmation = null;
  let requestedScenarioIds = [];
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--cleanup') {
      operation = 'cleanup';
    } else if (argument === '--run') {
      runId = argv[index + 1] ?? '';
      index += 1;
    } else if (argument === '--scenarios') {
      const value = argv[index + 1] ?? '';
      requestedScenarioIds = value ? value.split(',') : [];
      index += 1;
    } else if (argument === '--confirm') {
      confirmation = argv[index + 1] ?? '';
      index += 1;
    } else {
      throw new Error(`Unknown staging scenario argument: ${argument}.`);
    }
  }
  if (
    runId.length < 3 ||
    runId.length > 32 ||
    !RUN_ID_PATTERN.test(runId)
  ) {
    throw new Error(
      '--run must be a 3-32 character lowercase letter/digit/hyphen id.',
    );
  }
  if (operation === 'cleanup' && requestedScenarioIds.length > 0) {
    throw new Error('--scenarios cannot be combined with --cleanup.');
  }
  if (confirmation === '') {
    throw new Error('--confirm requires the exact preview fingerprint.');
  }
  return { operation, runId, requestedScenarioIds, confirmation };
}

export function buildStagingScenarioCreatePlan({
  target,
  runId,
  requestedScenarioIds = [],
}) {
  const scenarios = selectStagingScenarios(requestedScenarioIds);
  return {
    operation: 'create',
    manifest_version: STAGING_SCENARIO_MANIFEST_VERSION,
    expected_migration: target.expectedMigration,
    project_ref: target.projectRef,
    supabase_url: target.supabaseUrl,
    run_id: runId,
    scenarios: scenarios.map((scenario) => ({
      id: scenario.id,
      label: scenario.label,
      identity: stagingScenarioIdentity(runId, scenario),
    })),
  };
}

export function stagingScenarioConfirmationFingerprint(preview) {
  const digest = createHash('sha256')
    .update(canonicalJson(preview))
    .digest('hex');
  return `staging-scenarios-${digest.slice(0, 20)}`;
}

export function stagingScenarioReceiptPath(
  target,
  runId,
  receiptDir = DEFAULT_RECEIPT_DIR,
) {
  return join(receiptDir, `${target.projectRef}-${runId}.json`);
}

function previewPath(target, runId, operation, receiptDir) {
  return join(receiptDir, `${target.projectRef}-${runId}.${operation}.preview.json`);
}

function writeProtectedJson(path, value) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  chmodSync(path, 0o600);
}

function readJson(path, context) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    throw new Error(`${context} is missing or invalid.`);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(`${context} has an invalid shape.`);
  }
  return parsed;
}

function createFreshPreview({ plan, target, runId, operation, receiptDir, now }) {
  const preview = {
    preview_version: 'staging-scenario-preview-v1',
    nonce: randomBytes(16).toString('hex'),
    previewed_at: now.toISOString(),
    expires_at: new Date(
      now.getTime() + STAGING_SCENARIO_PREVIEW_MAX_AGE_MS,
    ).toISOString(),
    plan,
  };
  writeProtectedJson(previewPath(target, runId, operation, receiptDir), preview);
  return preview;
}

function consumeFreshPreview({
  expectedPlan,
  target,
  runId,
  operation,
  receiptDir,
  confirmation,
  now,
}) {
  const path = previewPath(target, runId, operation, receiptDir);
  const preview = readJson(path, 'Staging scenario preview');
  if (
    preview.preview_version !== 'staging-scenario-preview-v1' ||
    typeof preview.nonce !== 'string' ||
    !/^[0-9a-f]{32}$/.test(preview.nonce) ||
    typeof preview.previewed_at !== 'string' ||
    typeof preview.expires_at !== 'string' ||
    preview.consumed_at !== undefined ||
    canonicalJson(preview.plan) !== canonicalJson(expectedPlan)
  ) {
    throw new Error('Staging scenario preview does not match the current plan.');
  }
  const previewedAt = Date.parse(preview.previewed_at);
  const expiresAt = Date.parse(preview.expires_at);
  if (
    !Number.isFinite(previewedAt) ||
    !Number.isFinite(expiresAt) ||
    expiresAt - previewedAt !== STAGING_SCENARIO_PREVIEW_MAX_AGE_MS ||
    now.getTime() < previewedAt ||
    now.getTime() > expiresAt
  ) {
    throw new Error('Staging scenario confirmation has expired; preview again.');
  }
  const expected = stagingScenarioConfirmationFingerprint(preview);
  if (confirmation !== expected) {
    throw new Error('Confirmation does not match the fresh staging scenario preview.');
  }
  writeProtectedJson(path, { ...preview, consumed_at: now.toISOString() });
  return preview;
}

function requiredScenarioPassword(environment) {
  const password = environment.STAGING_SCENARIO_PASSWORD;
  if (
    typeof password !== 'string' ||
    password.length < 12 ||
    password.length > 128 ||
    password.trim() !== password
  ) {
    throw new Error(
      'STAGING_SCENARIO_PASSWORD must be a 12-128 character caller secret.',
    );
  }
  return password;
}

function scenarioBackendKey(environment) {
  return resolveCompatibleKey({
    environment,
    currentName: 'STAGING_SUPABASE_SECRET_KEY',
    legacyName: 'STAGING_SUPABASE_SERVICE_ROLE_KEY',
    currentPrefix: 'sb_secret_',
    context: 'confirmed staging scenario generation',
  });
}

class StagingScenarioRemote {
  constructor({ target, backendKey, fetchImpl = globalThis.fetch }) {
    this.target = target;
    this.backendKey = backendKey;
    this.fetchImpl = fetchImpl;
  }

  headers({ json = true, prefer = '' } = {}) {
    return supabaseBackendHeaders(this.backendKey, { json, prefer });
  }

  async request(path, { method = 'GET', body, prefer = '' } = {}, context) {
    const response = await this.fetchImpl(`${this.target.supabaseUrl}${path}`, {
      method,
      headers: this.headers({ json: body !== undefined, prefer }),
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(30_000),
    });
    const text = await response.text();
    let json = null;
    if (text) {
      try {
        json = JSON.parse(text);
      } catch {
        // Remote response bodies are intentionally never echoed.
      }
    }
    return { status: response.status, ok: response.ok, json, context };
  }

  requireStatus(result, expected) {
    const statuses = Array.isArray(expected) ? expected : [expected];
    if (!statuses.includes(result.status)) {
      throw new Error(`${result.context} returned unexpected HTTP ${result.status}.`);
    }
    return result.json;
  }

  async verifySchema() {
    const result = await this.request(
      '/rest/v1/profiles?select=id,pilot_participation_notice_version,pilot_participation_accepted_at&limit=0',
      {},
      'Staging participation schema check',
    );
    this.requireStatus(result, 200);
  }

  async listUsers() {
    const users = [];
    for (let page = 1; page <= 20; page += 1) {
      const result = await this.request(
        `/auth/v1/admin/users?page=${page}&per_page=100`,
        {},
        'Bounded staging Auth user list',
      );
      const json = this.requireStatus(result, 200);
      const pageUsers = Array.isArray(json) ? json : json?.users;
      if (!Array.isArray(pageUsers)) {
        throw new Error('Bounded staging Auth user list returned invalid JSON.');
      }
      users.push(...pageUsers);
      if (pageUsers.length < 100) return users;
    }
    throw new Error('Staging Auth user list exceeded the 2,000-user safety bound.');
  }

  async ensureUser({ identity, runId, password, existingUsers }) {
    const matches = existingUsers.filter(
      (user) => user?.email?.toLowerCase() === identity.email.toLowerCase(),
    );
    if (matches.length > 1) {
      throw new Error(`Synthetic identity is not unique: ${identity.email}.`);
    }
    const metadata = {
      display_name: identity.displayName,
      staging_scenario_version: STAGING_SCENARIO_MANIFEST_VERSION,
      staging_scenario_run: runId,
      staging_scenario_id: identity.scenarioId,
    };
    let user = matches[0] ?? null;
    if (user !== null) {
      assertOwnedSyntheticUser(user, identity, runId);
      const updated = await this.request(
        `/auth/v1/admin/users/${user.id}`,
        {
          method: 'PUT',
          body: { password, email_confirm: true, user_metadata: metadata },
        },
        `Refresh exact synthetic Auth identity ${identity.scenarioId}`,
      );
      user = this.requireStatus(updated, 200);
    } else {
      const created = await this.request(
        '/auth/v1/admin/users',
        {
          method: 'POST',
          body: {
            email: identity.email,
            password,
            email_confirm: true,
            user_metadata: metadata,
          },
        },
        `Create exact synthetic Auth identity ${identity.scenarioId}`,
      );
      user = this.requireStatus(created, 200);
    }
    if (!user || typeof user.id !== 'string' || !UUID_PATTERN.test(user.id)) {
      throw new Error('Synthetic Auth identity returned no valid UUID.');
    }
    assertOwnedSyntheticUser(user, identity, runId);
    return user.id;
  }

  async upsert(table, rows, conflict = 'id') {
    if (rows.length === 0) return;
    const result = await this.request(
      `/rest/v1/${table}?on_conflict=${encodeURIComponent(conflict)}`,
      {
        method: 'POST',
        body: rows,
        prefer: 'resolution=merge-duplicates,return=minimal',
      },
      `Upsert exact synthetic ${table}`,
    );
    this.requireStatus(result, [200, 201, 204]);
  }

  async rpc(name, body) {
    const result = await this.request(
      `/rest/v1/rpc/${name}`,
      { method: 'POST', body },
      `Run exact synthetic ${name}`,
    );
    return this.requireStatus(result, 200);
  }

  async select(path, context) {
    const result = await this.request(`/rest/v1/${path}`, {}, context);
    const rows = this.requireStatus(result, 200);
    if (!Array.isArray(rows)) throw new Error(`${context} returned invalid JSON.`);
    return rows;
  }

  async getUser(userId) {
    const result = await this.request(
      `/auth/v1/admin/users/${userId}`,
      {},
      'Read exact synthetic Auth identity',
    );
    if (result.status === 404) return null;
    return this.requireStatus(result, 200);
  }

  async deleteUser(userId) {
    const result = await this.request(
      `/auth/v1/admin/users/${userId}`,
      { method: 'DELETE' },
      'Delete exact synthetic Auth identity',
    );
    this.requireStatus(result, [200, 204, 404]);
  }
}

function assertOwnedSyntheticUser(user, identity, runId) {
  const metadata = user.user_metadata;
  if (
    user.email?.toLowerCase() !== identity.email.toLowerCase() ||
    !metadata ||
    metadata.staging_scenario_version !== STAGING_SCENARIO_MANIFEST_VERSION ||
    metadata.staging_scenario_run !== runId ||
    metadata.staging_scenario_id !== identity.scenarioId
  ) {
    throw new Error(
      `Refusing to reuse or delete non-owned synthetic identity ${identity.email}.`,
    );
  }
}

function initialReceipt({ target, plan, existingReceipt, now }) {
  if (existingReceipt) {
    validateReceipt(existingReceipt, target, plan.run_id);
    if (
      canonicalJson(existingReceipt.scenario_ids) !==
      canonicalJson(plan.scenarios.map((item) => item.id))
    ) {
      throw new Error(
        'This run id already belongs to another scenario selection; clean it first.',
      );
    }
  }
  const expectedIdentities = new Map(
    plan.scenarios.map((item) => [item.id, item.identity.email]),
  );
  const users = Array.isArray(existingReceipt?.users)
    ? existingReceipt.users.filter(
        (user) => expectedIdentities.get(user.scenario_id) === user.email,
      )
    : [];
  return {
    receipt_version: RECEIPT_VERSION,
    manifest_version: STAGING_SCENARIO_MANIFEST_VERSION,
    project_ref: target.projectRef,
    supabase_url: target.supabaseUrl,
    run_id: plan.run_id,
    scenario_ids: plan.scenarios.map((item) => item.id),
    status: 'incomplete',
    created_at: existingReceipt?.created_at ?? now.toISOString(),
    updated_at: now.toISOString(),
    users,
  };
}

function validateReceipt(receipt, target, runId) {
  if (
    receipt.receipt_version !== RECEIPT_VERSION ||
    receipt.manifest_version !== STAGING_SCENARIO_MANIFEST_VERSION ||
    receipt.project_ref !== target.projectRef ||
    receipt.supabase_url !== target.supabaseUrl ||
    receipt.run_id !== runId ||
    !['incomplete', 'ready', 'cleaned'].includes(receipt.status) ||
    !Array.isArray(receipt.scenario_ids) ||
    !Array.isArray(receipt.users)
  ) {
    throw new Error('Staging scenario receipt does not match the current target.');
  }
  selectStagingScenarios(receipt.scenario_ids);
  if (new Set(receipt.scenario_ids).size !== receipt.scenario_ids.length) {
    throw new Error('Staging scenario receipt contains duplicate scenario ids.');
  }
  for (const user of receipt.users) {
    if (
      !user ||
      typeof user.scenario_id !== 'string' ||
      typeof user.email !== 'string' ||
      typeof user.user_id !== 'string' ||
      !UUID_PATTERN.test(user.user_id)
    ) {
      throw new Error('Staging scenario receipt contains an invalid user record.');
    }
    const scenario = selectStagingScenarios([user.scenario_id])[0];
    const identity = stagingScenarioIdentity(runId, scenario);
    if (
      !receipt.scenario_ids.includes(user.scenario_id) ||
      user.email !== identity.email
    ) {
      throw new Error('Staging scenario receipt contains an unexpected identity.');
    }
  }
  if (new Set(receipt.users.map((user) => user.user_id)).size !== receipt.users.length) {
    throw new Error('Staging scenario receipt contains duplicate user ids.');
  }
  return receipt;
}

function readReceipt(target, runId, receiptDir) {
  const path = stagingScenarioReceiptPath(target, runId, receiptDir);
  if (!existsSync(path)) return null;
  return validateReceipt(readJson(path, 'Staging scenario receipt'), target, runId);
}

function recordReceiptUser(receipt, identity, userId, now) {
  const next = receipt.users.filter(
    (user) => user.scenario_id !== identity.scenarioId,
  );
  next.push({
    scenario_id: identity.scenarioId,
    email: identity.email,
    user_id: userId,
  });
  next.sort((left, right) => left.scenario_id.localeCompare(right.scenario_id));
  return { ...receipt, users: next, updated_at: now.toISOString() };
}

async function prepareProfile({ remote, userId, identity, scenario, now }) {
  const onboardingComplete = scenario.seed.kind !== 'fresh_account';
  await remote.upsert('profiles', [
    {
      id: userId,
      email: identity.email,
      display_name: identity.displayName,
      timezone: 'Europe/Berlin',
      role: 'user',
      auth_provider: 'email',
      onboarding_completed_at: onboardingComplete ? now.toISOString() : null,
      setup_revision: onboardingComplete ? 1 : 0,
      daily_preparation_budget_minutes: null,
      updated_at: now.toISOString(),
    },
  ]);
  const accepted = await remote.rpc('accept_pilot_participation_v1', {
    p_user_id: userId,
    p_notice_version: 'pilot-participation-notice-v1',
  });
  if (
    !accepted ||
    accepted.contract_version !== 'pilot-participation-v1' ||
    accepted.notice_version !== 'pilot-participation-notice-v1' ||
    typeof accepted.accepted_at !== 'string' ||
    typeof accepted.replayed !== 'boolean'
  ) {
    throw new Error('Staging participation RPC returned an invalid contract.');
  }
}

async function seedScenario({ remote, target, runId, scenario, userId, now }) {
  const identity = stagingScenarioIdentity(runId, scenario);
  await prepareProfile({ remote, userId, identity, scenario, now });
  const metadata = {
    source: STAGING_SCENARIO_MANIFEST_VERSION,
    staging_scenario_run: runId,
    staging_scenario_id: scenario.id,
  };
  const exactIds = [];
  if (scenario.seed.kind === 'tasks' || scenario.seed.kind === 'deadline_conflicts') {
    const taskRows = scenario.seed.tasks.map((task) => {
      const id = deterministicUuid(
        `${target.projectRef}|${runId}|${scenario.id}|task|${task.key}`,
      );
      exactIds.push(['tasks', id]);
      return {
        id,
        user_id: userId,
        title: task.title,
        description: task.description,
        status: 'todo',
        priority: task.priority,
        deadline: atUtcDayOffset(now, task.deadlineOffsetDays, 16),
        estimated_minutes: task.estimatedMinutes,
        source: 'staging_scenario',
        metadata,
        created_at: atUtcDayOffset(now, -7, 12),
        updated_at: now.toISOString(),
      };
    });
    await remote.upsert('tasks', taskRows);
  }
  if (scenario.seed.kind === 'deadline_conflicts') {
    const targetDay = addUtcDays(now, 1);
    const weekday = isoWeekday(targetDay);
    const rows = scenario.seed.commitments.map((commitment) => {
      const id = deterministicUuid(
        `${target.projectRef}|${runId}|${scenario.id}|commitment|${commitment.key}`,
      );
      exactIds.push(['schedule_items', id]);
      return {
        id,
        user_id: userId,
        title: commitment.title,
        location: commitment.location,
        weekday,
        starts_at: commitment.startsAt,
        ends_at: commitment.endsAt,
        color: '#B86B00',
        source: 'staging_scenario',
        notes: 'Synthetic overlapping availability fixture.',
        metadata,
      };
    });
    await remote.upsert('schedule_items', rows);
  }
  if (scenario.seed.kind === 'daily_capture_series') {
    const rows = buildDailyCaptureRows({
      target,
      runId,
      scenario,
      userId,
      now,
      metadata,
    });
    rows.forEach((row) => exactIds.push(['daily_logs', row.id]));
    await remote.upsert('daily_logs', rows);
  }
  if (scenario.seed.kind === 'coach_history') {
    const createdAt = atUtcDayOffset(now, -1, 18);
    const rows = [
      {
        id: deterministicUuid(
          `${target.projectRef}|${runId}|${scenario.id}|coach|user`,
        ),
        user_id: userId,
        role: 'user',
        content: 'Which synthetic deadline should I inspect first?',
        metadata,
        created_at: createdAt,
      },
      {
        id: deterministicUuid(
          `${target.projectRef}|${runId}|${scenario.id}|coach|assistant`,
        ),
        user_id: userId,
        role: 'assistant',
        content:
          'Start with the nearest synthetic deadline and verify the available evidence before acting.',
        metadata,
        created_at: new Date(Date.parse(createdAt) + 60_000).toISOString(),
      },
    ];
    rows.forEach((row) => exactIds.push(['coach_messages', row.id]));
    await remote.upsert('coach_messages', rows);
  }
  if (scenario.seed.kind === 'active_exam') {
    const planId = await seedActiveExam({
      remote,
      target,
      runId,
      scenario,
      userId,
      now,
    });
    exactIds.push(['deadline_plans', planId]);
  }
  await verifyScenario({ remote, userId, scenario, exactIds });
}

function buildDailyCaptureRows({ target, runId, scenario, userId, now, metadata }) {
  return Array.from({ length: scenario.seed.days }, (_, index) => {
    const offset = index - (scenario.seed.days - 1);
    const day = addUtcDays(now, offset);
    const entryDate = dateOnly(day);
    const previousDate = dateOnly(addUtcDays(day, -1));
    const stress = index % 2 === 0 ? 9 : 8;
    const energy = index % 2 === 0 ? 3 : 4;
    const mood = index % 2 === 0 ? 4 : 5;
    const morningCapturedAt = atUtcDate(day, 7, 10);
    const wokeAt = atUtcDate(day, 7, 0);
    const estimatedSleepStartedAt = new Date(
      Date.parse(wokeAt) - 300 * 60_000,
    ).toISOString();
    const eveningCapturedAt = atUtcDate(day, 20, 30);
    return {
      id: deterministicUuid(
        `${target.projectRef}|${runId}|${scenario.id}|daily-log|${entryDate}`,
      ),
      user_id: userId,
      entry_date: entryDate,
      sleep_hours: 5,
      steps: null,
      activity_level: null,
      screen_time_hours: null,
      focus_minutes: null,
      mood_score: mood,
      mood_label: mood >= 5 ? 'neutral' : 'low',
      energy_level: energy,
      stress_level: stress,
      nutrition_notes: null,
      day_focus: null,
      reflection: null,
      source: 'quick_check_in',
      metadata: {
        ...metadata,
        capture_version: 'daily-capture-v5',
        captures: {
          evening: {
            branch_version: 'daily-capture-v5',
            capture_kind: 'evening',
            entry_date: entryDate,
            capture_id: deterministicUuid(
              `${target.projectRef}|${runId}|${scenario.id}|evening|${entryDate}`,
            ),
            captured_at: eveningCapturedAt,
            mood,
            energy,
            stress_intensity: stress,
            stress_intensity_label: 'high',
            stress_source: 'workload',
            stress_controllability: 'partly_controllable',
            planned_sleep_time: '23:30',
            sleep_target_minutes: 480,
          },
          morning: {
            branch_version: 'daily-capture-v5',
            capture_kind: 'morning',
            entry_date: entryDate,
            capture_id: deterministicUuid(
              `${target.projectRef}|${runId}|${scenario.id}|morning|${entryDate}`,
            ),
            captured_at: morningCapturedAt,
            estimated_sleep_started_at: estimatedSleepStartedAt,
            woke_at: wokeAt,
            estimated_sleep_minutes: 300,
            sleep_target_minutes: 480,
            source_evening_capture_id: deterministicUuid(
              `${target.projectRef}|${runId}|${scenario.id}|evening|${previousDate}`,
            ),
            sleep_hours: 5,
            sleep_quality: 4,
            current_energy: energy,
          },
        },
      },
      created_at: morningCapturedAt,
      updated_at: eveningCapturedAt,
    };
  });
}

async function seedActiveExam({ remote, target, runId, scenario, userId, now }) {
  const planId = deterministicUuid(
    `${target.projectRef}|${runId}|${scenario.id}|plan`,
  );
  const proposalRequestId = deterministicUuid(
    `${target.projectRef}|${runId}|${scenario.id}|proposal-request`,
  );
  const confirmRequestId = deterministicUuid(
    `${target.projectRef}|${runId}|${scenario.id}|confirm-request`,
  );
  const deadlineAt = atUtcDayOffset(now, scenario.seed.deadlineOffsetDays, 16);
  const blocks = scenario.seed.blockOffsetDays.map((offset, index) => {
    const startsAt = atUtcDayOffset(now, offset, 9);
    const endsAt = new Date(
      Date.parse(startsAt) + scenario.seed.blockMinutes * 60_000,
    ).toISOString();
    const localStart = berlinParts(new Date(startsAt));
    const localEnd = berlinParts(new Date(endsAt));
    return {
      id: deterministicUuid(
        `${target.projectRef}|${runId}|${scenario.id}|block|${index + 1}`,
      ),
      sequence: index + 1,
      starts_at: startsAt,
      ends_at: endsAt,
      recovery_minutes: 0,
      reserved_ends_at: endsAt,
      local_date: localStart.date,
      local_start_time: localStart.time,
      local_end_time: localEnd.time,
      planned_minutes: scenario.seed.blockMinutes,
    };
  });
  const plannedMinutes = blocks.reduce(
    (total, block) => total + block.planned_minutes,
    0,
  );
  const proposalFingerprint = hashHex(
    `${target.projectRef}|${runId}|${scenario.id}|proposal-payload`,
  );
  await remote.rpc('propose_deadline_plan_with_timing_v1', {
    p_user_id: userId,
    p_request_id: proposalRequestId,
    p_request_fingerprint: hashHex(
      `${target.projectRef}|${runId}|${scenario.id}|proposal-identity`,
    ),
    p_plan_id: planId,
    p_base_revision: 0,
    p_proposal: {
      plan_id: planId,
      base_revision: 0,
      kind: 'exam',
      title: scenario.seed.title,
      deadline_at: deadlineAt,
      estimated_total_minutes: plannedMinutes,
      credited_prior_minutes: 0,
      preferred_session_minutes: scenario.seed.blockMinutes,
      max_daily_minutes: scenario.seed.blockMinutes * 2,
      planning_start_on: berlinParts(now).date,
      buffer_days: 1,
      source_kind: 'manual',
      source_calendar_event_id: null,
      source_calendar_event_fingerprint: null,
      use_calendar_availability: false,
      availability_connection_id: null,
      availability_import_id: null,
      timezone: 'Europe/Berlin',
      best_energy_window: 'morning',
      planning_fingerprint: proposalFingerprint,
      timing_preference: {
        source: 'setup',
        window: null,
        evidence_count: 0,
        evidence_starts_on: null,
        evidence_ends_on: null,
        evidence_fingerprint: null,
        fell_back_to_setup: false,
        warning: null,
      },
      study_setup_revision: null,
      recovery_minutes: 0,
      tracked_focus_minutes_at_proposal: 0,
      remaining_minutes_at_proposal: plannedMinutes,
      planned_minutes: plannedMinutes,
      unscheduled_minutes: 0,
    },
    p_blocks: blocks,
    p_now: now.toISOString(),
  });
  await remote.rpc('confirm_deadline_plan_v1', {
    p_user_id: userId,
    p_plan_id: planId,
    p_request_id: confirmRequestId,
    p_request_fingerprint: hashHex(
      `${target.projectRef}|${runId}|${scenario.id}|confirm-identity`,
    ),
    p_expected_revision: 1,
    p_now: now.toISOString(),
  });
  return planId;
}

async function verifyScenario({ remote, userId, scenario, exactIds }) {
  const profileRows = await remote.select(
    `profiles?select=id,pilot_participation_notice_version,pilot_participation_accepted_at,onboarding_completed_at&id=eq.${userId}`,
    `Verify exact synthetic profile ${scenario.id}`,
  );
  if (
    profileRows.length !== 1 ||
    profileRows[0].pilot_participation_notice_version !==
      'pilot-participation-notice-v1' ||
    typeof profileRows[0].pilot_participation_accepted_at !== 'string' ||
    (scenario.seed.kind === 'fresh_account'
      ? profileRows[0].onboarding_completed_at !== null
      : typeof profileRows[0].onboarding_completed_at !== 'string')
  ) {
    throw new Error(`Synthetic profile verification failed for ${scenario.id}.`);
  }
  for (const [table, id] of exactIds) {
    const rows = await remote.select(
      `${table}?select=id&id=eq.${id}`,
      `Verify exact synthetic ${table} ${scenario.id}`,
    );
    if (rows.length !== 1 || rows[0]?.id !== id) {
      throw new Error(`Synthetic ${table} verification failed for ${scenario.id}.`);
    }
  }
}

export async function runConfirmedStagingScenarioCreate({
  target,
  plan,
  environment = process.env,
  fetchImpl = globalThis.fetch,
  receiptDir = DEFAULT_RECEIPT_DIR,
  now = new Date(),
}) {
  const password = requiredScenarioPassword(environment);
  const backendKey = scenarioBackendKey(environment);
  const remote = new StagingScenarioRemote({ target, backendKey, fetchImpl });
  await remote.verifySchema();
  const existingUsers = await remote.listUsers();
  const receiptPath = stagingScenarioReceiptPath(target, plan.run_id, receiptDir);
  const existingReceipt = readReceipt(target, plan.run_id, receiptDir);
  let receipt = initialReceipt({ target, plan, existingReceipt, now });
  writeProtectedJson(receiptPath, receipt);

  for (const item of plan.scenarios) {
    const scenario = selectStagingScenarios([item.id])[0];
    const identity = stagingScenarioIdentity(plan.run_id, scenario);
    const userId = await remote.ensureUser({
      identity,
      runId: plan.run_id,
      password,
      existingUsers,
    });
    receipt = recordReceiptUser(receipt, identity, userId, now);
    writeProtectedJson(receiptPath, receipt);
    await seedScenario({
      remote,
      target,
      runId: plan.run_id,
      scenario,
      userId,
      now,
    });
  }
  receipt = {
    ...receipt,
    status: 'ready',
    updated_at: new Date().toISOString(),
  };
  writeProtectedJson(receiptPath, receipt);
  return { usersReady: receipt.users.length, receiptPath };
}

function buildCleanupPlan(target, runId, receiptDir) {
  const receipt = readReceipt(target, runId, receiptDir);
  if (receipt === null || receipt.status === 'cleaned') {
    throw new Error('No active staging scenario receipt exists for this run.');
  }
  return {
    operation: 'cleanup',
    manifest_version: receipt.manifest_version,
    project_ref: receipt.project_ref,
    supabase_url: receipt.supabase_url,
    run_id: receipt.run_id,
    users: receipt.users.map((user) => ({ ...user })),
  };
}

export async function runConfirmedStagingScenarioCleanup({
  target,
  plan,
  environment = process.env,
  fetchImpl = globalThis.fetch,
  receiptDir = DEFAULT_RECEIPT_DIR,
  now = new Date(),
}) {
  const backendKey = scenarioBackendKey(environment);
  const remote = new StagingScenarioRemote({ target, backendKey, fetchImpl });
  const receipt = readReceipt(target, plan.run_id, receiptDir);
  if (receipt === null || receipt.status === 'cleaned') {
    throw new Error('No active staging scenario receipt exists for cleanup.');
  }
  if (canonicalJson(buildCleanupPlan(target, plan.run_id, receiptDir)) !== canonicalJson(plan)) {
    throw new Error('Cleanup plan no longer matches the exact receipt.');
  }
  for (const userRecord of [...receipt.users].reverse()) {
    const scenario = selectStagingScenarios([userRecord.scenario_id])[0];
    const identity = stagingScenarioIdentity(plan.run_id, scenario);
    const user = await remote.getUser(userRecord.user_id);
    if (user !== null) {
      assertOwnedSyntheticUser(user, identity, plan.run_id);
      await remote.deleteUser(userRecord.user_id);
    }
    if ((await remote.getUser(userRecord.user_id)) !== null) {
      throw new Error(
        `Cleanup could not verify deletion for ${userRecord.scenario_id}.`,
      );
    }
  }
  writeProtectedJson(stagingScenarioReceiptPath(target, plan.run_id, receiptDir), {
    ...receipt,
    status: 'cleaned',
    cleaned_at: now.toISOString(),
    updated_at: now.toISOString(),
  });
  return { usersDeleted: receipt.users.length };
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function hashHex(value) {
  return createHash('sha256').update(value).digest('hex');
}

function deterministicUuid(seed) {
  const bytes = createHash('sha256').update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join('-');
}

function addUtcDays(date, offset) {
  const value = new Date(date);
  value.setUTCDate(value.getUTCDate() + offset);
  return value;
}

function atUtcDate(date, hour, minute = 0) {
  const value = new Date(date);
  value.setUTCHours(hour, minute, 0, 0);
  return value.toISOString();
}

function atUtcDayOffset(date, offset, hour) {
  return atUtcDate(addUtcDays(date, offset), hour);
}

function dateOnly(date) {
  return date.toISOString().slice(0, 10);
}

function isoWeekday(date) {
  return date.getUTCDay() || 7;
}

function berlinParts(date) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Europe/Berlin',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(date)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${parts.hour}:${parts.minute}:${parts.second}`,
  };
}

function printPlan(plan, fingerprint) {
  console.log(`Operation: ${plan.operation}`);
  console.log(`Staging project ref: ${plan.project_ref}`);
  console.log(`Staging Supabase host: ${new URL(plan.supabase_url).hostname}`);
  console.log(`Run id: ${plan.run_id}`);
  if (plan.operation === 'create') {
    console.log(`Manifest: ${plan.manifest_version}`);
    console.log(`Expected migration: ${plan.expected_migration}`);
    for (const item of plan.scenarios) {
      console.log(`Scenario: ${item.id} -> ${item.identity.email}`);
    }
  } else {
    for (const user of plan.users) {
      console.log(
        `Cleanup identity: ${user.scenario_id} -> ${user.email} (${user.user_id})`,
      );
    }
  }
  console.log(`Required confirmation: ${fingerprint}`);
}

async function main() {
  const args = parseStagingScenarioArguments(process.argv.slice(2));
  const target = stagingScenarioTarget(process.env);
  const receiptDir = DEFAULT_RECEIPT_DIR;
  const plan =
    args.operation === 'create'
      ? buildStagingScenarioCreatePlan({
          target,
          runId: args.runId,
          requestedScenarioIds: args.requestedScenarioIds,
        })
      : buildCleanupPlan(target, args.runId, receiptDir);

  if (args.confirmation === null) {
    const preview = createFreshPreview({
      plan,
      target,
      runId: args.runId,
      operation: args.operation,
      receiptDir,
      now: new Date(),
    });
    const fingerprint = stagingScenarioConfirmationFingerprint(preview);
    printPlan(plan, fingerprint);
    console.log(
      `Preview only. Rerun unchanged within 15 minutes with --confirm ${fingerprint}.`,
    );
    return;
  }

  consumeFreshPreview({
    expectedPlan: plan,
    target,
    runId: args.runId,
    operation: args.operation,
    receiptDir,
    confirmation: args.confirmation,
    now: new Date(),
  });
  if (args.operation === 'create') {
    const result = await runConfirmedStagingScenarioCreate({ target, plan });
    console.log(
      `Staging scenarios ready for ${result.usersReady} exact synthetic identities.`,
    );
    console.log('The caller-owned password was not printed or persisted.');
  } else {
    const result = await runConfirmedStagingScenarioCleanup({ target, plan });
    console.log(
      `Staging scenario cleanup verified ${result.usersDeleted} exact identities absent.`,
    );
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
