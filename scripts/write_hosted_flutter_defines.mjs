#!/usr/bin/env node

import { chmodSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const REQUIRED_ENVIRONMENT = new Set(['staging', 'production']);

function requireHttpsUrl(name, value, { supabase = false } = {}) {
  if (!value) {
    throw new Error(`${name} is required for a hosted Flutter build.`);
  }

  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`${name} must be a valid HTTPS URL.`);
  }
  if (
    parsed.protocol !== 'https:' ||
    parsed.username ||
    parsed.password ||
    parsed.search ||
    parsed.hash
  ) {
    throw new Error(`${name} must be a credential-free HTTPS URL.`);
  }
  if (supabase && !parsed.hostname.endsWith('.supabase.co')) {
    throw new Error(`${name} must target a hosted Supabase project.`);
  }
  return value.replace(/\/$/, '');
}

export function hostedFlutterDefines(environment = process.env) {
  const appEnvironment = environment.APP_ENV;
  if (!REQUIRED_ENVIRONMENT.has(appEnvironment)) {
    throw new Error('APP_ENV must be exactly staging or production.');
  }
  if (environment.USE_MOCK_DATA !== 'false') {
    throw new Error('USE_MOCK_DATA must be exactly false for hosted builds.');
  }
  if (environment.COACH_SURFACE_ENABLED !== 'true') {
    throw new Error(
      'COACH_SURFACE_ENABLED must be exactly true for hosted Coach builds.',
    );
  }
  if (!environment.SUPABASE_ANON_KEY) {
    throw new Error('SUPABASE_ANON_KEY is required for a hosted Flutter build.');
  }

  return {
    APP_ENV: appEnvironment,
    USE_MOCK_DATA: 'false',
    COACH_SURFACE_ENABLED: 'true',
    SUPABASE_URL: requireHttpsUrl('SUPABASE_URL', environment.SUPABASE_URL, {
      supabase: true,
    }),
    SUPABASE_ANON_KEY: environment.SUPABASE_ANON_KEY,
    AI_SERVICE_BASE_URL: requireHttpsUrl(
      'AI_SERVICE_BASE_URL',
      environment.AI_SERVICE_BASE_URL,
    ),
  };
}

export function writeHostedFlutterDefines(outputPath, environment) {
  if (!outputPath) {
    throw new Error('An output path is required.');
  }
  writeFileSync(
    outputPath,
    `${JSON.stringify(hostedFlutterDefines(environment))}\n`,
    { encoding: 'utf8', mode: 0o600 },
  );
  chmodSync(outputPath, 0o600);
}

function main() {
  const [outputPath, ...unexpected] = process.argv.slice(2);
  if (!outputPath || unexpected.length > 0) {
    throw new Error(
      'Usage: node scripts/write_hosted_flutter_defines.mjs <output-path>',
    );
  }
  writeHostedFlutterDefines(outputPath, process.env);
  console.log('Prepared protected hosted Flutter defines.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
