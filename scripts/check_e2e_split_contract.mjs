#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(
  fileURLToPath(new URL('..', import.meta.url)),
);

const expectedJourneys = new Set([
  'account-controls',
  'auth-capture-today',
  'coach',
  'personal-learning',
  'planner-confirm',
  'setup-onboarding',
]);

export function findE2eSplitContractErrors(root = repositoryRoot) {
  const errors = [];
  const journeysRoot = join(root, 'e2e/web/journeys');
  const legacyPath = join(root, 'e2e/web/legacy-full.mjs');
  if (existsSync(legacyPath)) {
    errors.push('e2e/web/legacy-full.mjs: retired monolithic oracle exists');
  }

  const specs = existsSync(journeysRoot)
    ? readdirSync(journeysRoot)
        .filter((name) => name.endsWith('.spec.mjs'))
        .sort()
    : [];
  const actualJourneys = new Set(
    specs.map((name) => name.replace(/\.spec\.mjs$/, '')),
  );
  for (const name of expectedJourneys) {
    if (!actualJourneys.has(name)) {
      errors.push(`e2e/web/journeys/${name}.spec.mjs: journey is missing`);
    }
  }
  for (const name of actualJourneys) {
    if (!expectedJourneys.has(name)) {
      errors.push(`e2e/web/journeys/${name}.spec.mjs: unregistered journey`);
    }
  }

  const tags = new Set();
  for (const spec of specs) {
    const relativePath = `e2e/web/journeys/${spec}`;
    const source = readFileSync(join(journeysRoot, spec), 'utf8');
    const expectedTag = spec.replace(/\.spec\.mjs$/, '');
    const match = source.match(/\btest\(\s*['"]@([a-z0-9-]+)\b/);
    if (match?.[1] !== expectedTag) {
      errors.push(`${relativePath}: primary tag must be @${expectedTag}`);
    } else if (tags.has(match[1])) {
      errors.push(`${relativePath}: duplicate journey tag @${match[1]}`);
    } else {
      tags.add(match[1]);
    }
    if (!/\{\s*[\s\S]*\bpage\b[\s\S]*\}\s*\)\s*=>/.test(source)) {
      errors.push(`${relativePath}: journey does not request a browser page`);
    }
    if (!source.includes('e2e.signInUi')) {
      errors.push(`${relativePath}: journey does not authenticate through Flutter`);
    }
    if (!source.includes('expectFlutterText')) {
      errors.push(`${relativePath}: journey has no user-visible Flutter assertion`);
    }
  }

  const requiredFiles = [
    'e2e/web/playwright.config.mjs',
    'scripts/e2e_web.sh',
    'scripts/verify_fast.sh',
    'package.json',
  ];
  for (const relativePath of requiredFiles) {
    const absolutePath = join(root, relativePath);
    if (!existsSync(absolutePath)) {
      errors.push(`${relativePath}: required E2E integration file is missing`);
      continue;
    }
    const source = readFileSync(absolutePath, 'utf8');
    for (const retired of [
      'legacy-full.mjs',
      'e2e:web:legacy',
      'e2e:web:new-full',
      'E2E_PHASE10_ONLY',
      'E2E_PERSONAL_LEARNING_ONLY',
    ]) {
      if (source.includes(retired)) {
        errors.push(`${relativePath}: references retired ${retired}`);
      }
    }
  }

  const configPath = join(root, 'e2e/web/playwright.config.mjs');
  if (existsSync(configPath)) {
    const config = readFileSync(configPath, 'utf8');
    for (const tag of [
      'setup-onboarding',
      'auth-capture-today',
      'planner-confirm',
      'coach',
    ]) {
      if (!config.includes(tag)) {
        errors.push(
          `e2e/web/playwright.config.mjs: smoke suite is missing @${tag}`,
        );
      }
    }
    if (!config.includes("full: undefined")) {
      errors.push(
        'e2e/web/playwright.config.mjs: full suite must remain unfiltered',
      );
    }
  }

  return errors;
}

function main() {
  const errors = findE2eSplitContractErrors();
  if (errors.length > 0) {
    console.error('E2E split contract failed:');
    for (const error of errors) console.error(`- ${error}`);
    process.exitCode = 1;
    return;
  }
  console.log(
    `E2E split contract passed (${expectedJourneys.size} independent UI journeys).`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
