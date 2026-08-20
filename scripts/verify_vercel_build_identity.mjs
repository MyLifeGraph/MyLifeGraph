#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SHA = /^[0-9a-f]{40}$/;
const RC_TAG = /^v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+-rc\.[0-9]+$/;

function required(environment, name, pattern) {
  const value = environment[name];
  if (typeof value !== 'string' || value.trim() !== value || !pattern.test(value)) {
    throw new Error(`${name} is missing or invalid.`);
  }
  return value;
}

export function verifyVercelEnvironment(environment, gitIdentity) {
  if (environment.VERCEL !== '1') {
    throw new Error('The Vercel build must have VERCEL=1.');
  }
  if (
    environment.VERCEL_GIT_REPO_OWNER !== 'MyLifeGraph' ||
    environment.VERCEL_GIT_REPO_SLUG !== 'MyLifeGraph'
  ) {
    throw new Error('The Vercel Git repository identity is invalid.');
  }
  const appEnvironment = required(
    environment,
    'APP_ENV',
    /^(?:staging|pilot)$/,
  );
  const appSha = required(environment, 'APP_BUILD_SHA', SHA);
  const vercelSha = required(environment, 'VERCEL_GIT_COMMIT_SHA', SHA);
  if (appSha !== vercelSha || gitIdentity.headSha !== vercelSha) {
    throw new Error('APP_BUILD_SHA does not match Vercel and checkout identity.');
  }
  const ref = required(
    environment,
    'VERCEL_GIT_COMMIT_REF',
    /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/,
  );
  if (appEnvironment === 'pilot') {
    if (environment.VERCEL_ENV !== 'production' || ref !== 'main') {
      throw new Error('Pilot Vercel builds require production mode from main.');
    }
    const tag = required(environment, 'APP_RELEASE_TAG', RC_TAG);
    if (gitIdentity.tagType !== 'tag' || gitIdentity.tagSha !== appSha) {
      throw new Error(
        `APP_RELEASE_TAG ${tag} is not an annotated tag for APP_BUILD_SHA.`,
      );
    }
  } else if (environment.VERCEL_ENV !== 'preview' || ref === 'main') {
    throw new Error('Staging Vercel builds require a non-main preview ref.');
  }
  return { appEnvironment, appSha, ref };
}

function git(...args) {
  return execFileSync('git', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

export function verifyCurrentVercelCheckout(environment = process.env) {
  const tag = environment.APP_RELEASE_TAG ?? '';
  const appEnvironment = environment.APP_ENV;
  let tagType = null;
  let tagSha = null;
  if (appEnvironment === 'pilot' && RC_TAG.test(tag)) {
    try {
      tagType = git('cat-file', '-t', `refs/tags/${tag}`);
      tagSha = git('rev-list', '-n', '1', `refs/tags/${tag}`);
    } catch {
      tagType = null;
      tagSha = null;
    }
  }
  return verifyVercelEnvironment(environment, {
    headSha: git('rev-parse', 'HEAD'),
    tagType,
    tagSha,
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    verifyCurrentVercelCheckout(process.env);
    console.log('Vercel checkout identity verified.');
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
