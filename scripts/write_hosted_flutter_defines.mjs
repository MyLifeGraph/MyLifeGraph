#!/usr/bin/env node

import { chmodSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  hostedSupabaseTarget,
  requireHttpsBaseUrl,
  resolveCompatibleKey,
} from './lib/supabase_deployment.mjs';

export function hostedFlutterDefines(environment = process.env) {
  const target = hostedSupabaseTarget(environment);
  if (environment.USE_MOCK_DATA !== 'false') {
    throw new Error('USE_MOCK_DATA must be exactly false for hosted builds.');
  }
  if (environment.COACH_SURFACE_ENABLED !== 'true') {
    throw new Error(
      'COACH_SURFACE_ENABLED must be exactly true for hosted Coach builds.',
    );
  }
  const publishableKey = resolveCompatibleKey({
    environment,
    currentName: 'SUPABASE_PUBLISHABLE_KEY',
    legacyName: 'SUPABASE_ANON_KEY',
    currentPrefix: 'sb_publishable_',
    requireCurrent: target.appEnvironment === 'pilot',
    context: `${target.appEnvironment} Flutter build`,
  });

  return {
    APP_ENV: target.appEnvironment,
    USE_MOCK_DATA: 'false',
    COACH_SURFACE_ENABLED: 'true',
    STAGING_SUPABASE_PROJECT_REF: target.stagingProjectRef,
    PILOT_SUPABASE_PROJECT_REF: target.pilotProjectRef,
    SUPABASE_URL: target.supabaseUrl,
    SUPABASE_PUBLISHABLE_KEY:
      publishableKey.source === 'current' ? publishableKey.value : '',
    SUPABASE_ANON_KEY:
      publishableKey.source === 'legacy' ? publishableKey.value : '',
    AI_SERVICE_BASE_URL: requireHttpsBaseUrl(
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
