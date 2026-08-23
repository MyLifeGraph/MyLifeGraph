#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SHA = /^[0-9a-f]{40}$/;
const VERCEL_SOURCE_IDENTITY = /^(?:main|preview)-[0-9a-f]{40}$/;

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
  const releaseIdentity = required(
    environment,
    'APP_RELEASE_TAG',
    VERCEL_SOURCE_IDENTITY,
  );
  const ref = required(
    environment,
    'VERCEL_GIT_COMMIT_REF',
    /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/,
  );
  if (appEnvironment === 'pilot') {
    if (environment.VERCEL_ENV !== 'production' || ref !== 'main') {
      throw new Error('Pilot Vercel builds require production mode from main.');
    }
    if (releaseIdentity !== `main-${appSha}`) {
      throw new Error('APP_RELEASE_TAG does not match the Vercel main SHA.');
    }
  } else {
    if (environment.VERCEL_ENV !== 'preview' || ref === 'main') {
      throw new Error('Staging Vercel builds require a non-main preview ref.');
    }
    if (releaseIdentity !== `preview-${appSha}`) {
      throw new Error('APP_RELEASE_TAG does not match the Vercel preview SHA.');
    }
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
  return verifyVercelEnvironment(environment, {
    headSha: git('rev-parse', 'HEAD'),
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
