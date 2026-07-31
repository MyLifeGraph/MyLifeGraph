import { fileURLToPath } from 'node:url';

export const ALL_JOURNEYS = Object.freeze([
  'account-controls',
  'auth-capture-today',
  'coach',
  'exam-week-outlook',
  'notification-lifecycle',
  'personal-learning',
  'planner-confirm',
  'setup-onboarding',
]);

export const SMOKE_JOURNEYS = Object.freeze([
  'setup-onboarding',
  'auth-capture-today',
  'planner-confirm',
  'coach',
]);

const knownJourneys = new Set(ALL_JOURNEYS);

export function isKnownJourney(value) {
  return knownJourneys.has(value);
}

export function journeyTagPattern(journeys) {
  const tags = journeys.map(escapeRegExp).join('|');
  return new RegExp(`@(${tags})\\b`);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function main() {
  const journey = process.argv[2] ?? '';
  if (journey === '' || !isKnownJourney(journey)) {
    process.exitCode = 64;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
