import assert from 'node:assert/strict';
import test from 'node:test';

import {
  participationGateConfirmation,
  runParticipationGate,
} from './configure_pilot_participation_gate.mjs';

const projectRef = 'abcdefghijklmnopqrst';
const environment = {
  APP_ENV: 'pilot',
  STAGING_SUPABASE_PROJECT_REF: 'zyxwvutsrqponmlkjihg',
  PILOT_SUPABASE_PROJECT_REF: projectRef,
  PILOT_CONTACT_EMAIL: 'pilot@example.test',
  SUPABASE_URL: `https://${projectRef}.supabase.co`,
  SUPABASE_SECRET_KEY: 'sb_secret_sentinel-never-print',
};

function attestation(required) {
  return {
    contract_version: 'pilot-participation-gate-v1',
    project_ref: required ? projectRef : null,
    participation_required: required,
    notice_version: required ? 'pilot-participation-notice-v1' : null,
  };
}

test('check is read-only, current-key compatible, and exact', async () => {
  const calls = [];
  const result = await runParticipationGate({
    argv: ['--check'],
    environment,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return Response.json(attestation(true));
    },
  });

  assert.deepEqual(result, attestation(true));
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /get_pilot_participation_gate_v1$/);
  assert.equal(calls[0].options.headers.apikey, environment.SUPABASE_SECRET_KEY);
  assert.equal('Authorization' in calls[0].options.headers, false);
  assert.equal(calls[0].options.body, '{}');
});
test('enable requires exact content-bound confirmation and re-attests', async () => {
  await assert.rejects(
    runParticipationGate({
      argv: ['--enable'],
      environment,
      fetchImpl: async () => {
        throw new Error('must not call remote');
      },
    }),
    /Remote mutation refused/,
  );

  const calls = [];
  await runParticipationGate({
    argv: [
      '--enable',
      '--confirm',
      participationGateConfirmation('enable', projectRef),
    ],
    environment,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return Response.json(attestation(true));
    },
  });
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /configure_pilot_participation_gate_v1$/);
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    p_project_ref: projectRef,
    p_required: true,
  });
  assert.match(calls[1].url, /get_pilot_participation_gate_v1$/);
});

test('disable is separately confirmed and proves the null disabled shape', async () => {
  const calls = [];
  const result = await runParticipationGate({
    argv: [
      '--disable',
      '--confirm',
      participationGateConfirmation('disable', projectRef),
    ],
    environment,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return Response.json(attestation(false));
    },
  });
  assert.deepEqual(result, attestation(false));
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    p_project_ref: null,
    p_required: false,
  });
});

test('wrong project attestation and legacy pilot keys fail closed', async () => {
  await assert.rejects(
    runParticipationGate({
      argv: ['--check'],
      environment,
      fetchImpl: async () =>
        Response.json({ ...attestation(true), project_ref: 'z'.repeat(20) }),
    }),
    /does not match/,
  );
  await assert.rejects(
    runParticipationGate({
      argv: ['--check'],
      environment: {
        ...environment,
        SUPABASE_SECRET_KEY: '',
        SUPABASE_SERVICE_ROLE_KEY: 'legacy-jwt',
      },
    }),
    /SUPABASE_SECRET_KEY is required/,
  );
});
