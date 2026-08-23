#!/usr/bin/env node

import {
  hostedSupabaseTarget,
  resolveCompatibleKey,
  supabaseBackendHeaders,
} from './lib/supabase_deployment.mjs';

export const PILOT_PARTICIPATION_GATE_CONTRACT =
  'pilot-participation-gate-v1';
export const PILOT_PARTICIPATION_NOTICE =
  'pilot-participation-notice-v1';

export function parseParticipationGateArguments(argv) {
  let operation = 'check';
  let confirmation = '';
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--check') {
      operation = 'check';
    } else if (argument === '--enable') {
      operation = 'enable';
    } else if (argument === '--disable') {
      operation = 'disable';
    } else if (argument === '--confirm') {
      confirmation = argv[index + 1] ?? '';
      index += 1;
    } else {
      throw new Error(`Unknown participation-gate argument: ${argument}.`);
    }
  }
  if (operation === 'check' && confirmation) {
    throw new Error('--confirm is valid only for enable or disable.');
  }
  return { operation, confirmation };
}
export function participationGateConfirmation(operation, projectRef) {
  const verb = operation === 'enable' ? 'ENABLE' : 'DISABLE';
  return `${verb}:${projectRef}:${PILOT_PARTICIPATION_GATE_CONTRACT}`;
}

function backendKey(environment, appEnvironment) {
  return resolveCompatibleKey({
    environment,
    currentName: 'SUPABASE_SECRET_KEY',
    legacyName: 'SUPABASE_SERVICE_ROLE_KEY',
    currentPrefix: 'sb_secret_',
    requireCurrent: appEnvironment === 'pilot',
    context: `${appEnvironment} participation-gate administration`,
  });
}

function exactAttestation(value, { projectRef, required }) {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    Object.keys(value).sort().join(',') !==
      [
        'contract_version',
        'notice_version',
        'participation_required',
        'project_ref',
      ]
        .sort()
        .join(',') ||
    value.contract_version !== PILOT_PARTICIPATION_GATE_CONTRACT ||
    value.participation_required !== required ||
    value.project_ref !== (required ? projectRef : null) ||
    value.notice_version !== (required ? PILOT_PARTICIPATION_NOTICE : null)
  ) {
    throw new Error('Participation-gate attestation does not match the target.');
  }
  return value;
}

async function rpc({ target, key, functionName, body, fetchImpl }) {
  const response = await fetchImpl(
    `${target.supabaseUrl}/rest/v1/rpc/${functionName}`,
    {
      method: 'POST',
      headers: supabaseBackendHeaders(key, { json: true }),
      body: JSON.stringify(body),
      redirect: 'error',
    },
  );
  if (!response.ok) {
    throw new Error(`Participation-gate RPC failed with HTTP ${response.status}.`);
  }
  const value = await response.json();
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Participation-gate RPC returned an invalid body.');
  }
  return value;
}

export async function runParticipationGate({
  argv = process.argv.slice(2),
  environment = process.env,
  fetchImpl = globalThis.fetch,
} = {}) {
  const args = parseParticipationGateArguments(argv);
  const target = hostedSupabaseTarget(environment);
  const key = backendKey(environment, target.appEnvironment);
  if (args.operation !== 'check') {
    const expectedConfirmation = participationGateConfirmation(
      args.operation,
      target.projectRef,
    );
    if (args.confirmation !== expectedConfirmation) {
      throw new Error(
        `Remote mutation refused. Re-run with --confirm ${expectedConfirmation}`,
      );
    }
    const required = args.operation === 'enable';
    const configured = await rpc({
      target,
      key,
      functionName: 'configure_pilot_participation_gate_v1',
      body: {
        p_project_ref: required ? target.projectRef : null,
        p_required: required,
      },
      fetchImpl,
    });
    exactAttestation(configured, {
      projectRef: target.projectRef,
      required,
    });
  }
  const expectedRequired = args.operation !== 'disable';
  const attested = await rpc({
    target,
    key,
    functionName: 'get_pilot_participation_gate_v1',
    body: {},
    fetchImpl,
  });
  return exactAttestation(attested, {
    projectRef: target.projectRef,
    required: expectedRequired,
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runParticipationGate()
    .then((attestation) => {
      process.stdout.write(
        `${JSON.stringify({
          contract_version: attestation.contract_version,
          project_ref: attestation.project_ref,
          participation_required: attestation.participation_required,
          notice_version: attestation.notice_version,
        })}\n`,
      );
    })
    .catch((error) => {
      process.stderr.write(`Participation-gate error: ${error.message}\n`);
      process.exitCode = 1;
    });
}
