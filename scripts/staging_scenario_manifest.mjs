export const STAGING_SCENARIO_MANIFEST_VERSION = 'staging-scenarios-v1';

// This reviewed repository allowlist is the staging authority. Adding or
// replacing a ref is a code review decision; caller-provided environment alone
// can never make another project seedable.
export const STAGING_SCENARIO_ALLOWED_PROJECT_REFS = Object.freeze([
  'oscrunlndfrecjilojja',
]);

export const STAGING_SCENARIOS = deepFreeze([
  {
    id: 'fresh-account',
    label: 'Fresh accepted account',
    description: 'Adult participation accepted; Setup and product data empty.',
    seed: { kind: 'fresh_account' },
  },
  {
    id: 'exam-week',
    label: 'Exam week',
    description: 'An active exam plan with three upcoming preparation blocks.',
    seed: {
      kind: 'active_exam',
      title: 'Staging Algorithms exam',
      deadlineOffsetDays: 5,
      blockOffsetDays: [1, 2, 3],
      blockMinutes: 60,
    },
  },
  {
    id: 'overdue-tasks',
    label: 'Overdue tasks',
    description: 'Open work with distinct overdue and near-term deadlines.',
    seed: {
      kind: 'tasks',
      tasks: [
        {
          key: 'overdue-critical',
          title: 'Submit overdue staging report',
          description: 'Synthetic overdue work for Today and Planner testing.',
          priority: 'critical',
          deadlineOffsetDays: -2,
          estimatedMinutes: 90,
        },
        {
          key: 'overdue-high',
          title: 'Review missed staging lecture',
          description: 'Synthetic backlog item for prioritization testing.',
          priority: 'high',
          deadlineOffsetDays: -1,
          estimatedMinutes: 45,
        },
        {
          key: 'upcoming-medium',
          title: 'Prepare next staging tutorial',
          description: 'Synthetic near-term work beside overdue tasks.',
          priority: 'medium',
          deadlineOffsetDays: 2,
          estimatedMinutes: 60,
        },
      ],
    },
  },
  {
    id: 'sleep-deficit-high-stress',
    label: 'Sleep deficit and high stress',
    description: 'Seven V5 capture days with short sleep and elevated stress.',
    seed: { kind: 'daily_capture_series', days: 7 },
  },
  {
    id: 'existing-coach-history',
    label: 'Existing Coach history',
    description: 'A bounded legacy-compatible user/assistant history pair.',
    seed: { kind: 'coach_history' },
  },
  {
    id: 'deadline-conflicts',
    label: 'Deadline conflicts',
    description: 'Overlapping fixed commitments plus urgent synthetic work.',
    seed: {
      kind: 'deadline_conflicts',
      tasks: [
        {
          key: 'conflict-assignment',
          title: 'Finish conflicting staging assignment',
          description: 'Synthetic assignment competing with fixed time.',
          priority: 'high',
          deadlineOffsetDays: 2,
          estimatedMinutes: 180,
        },
        {
          key: 'conflict-reading',
          title: 'Complete staging reading',
          description: 'Synthetic reading due in the same constrained window.',
          priority: 'medium',
          deadlineOffsetDays: 2,
          estimatedMinutes: 90,
        },
      ],
      commitments: [
        {
          key: 'seminar',
          title: 'Staging seminar',
          location: 'Synthetic room A',
          startsAt: '09:00:00',
          endsAt: '11:00:00',
        },
        {
          key: 'lab',
          title: 'Staging lab',
          location: 'Synthetic room B',
          startsAt: '10:30:00',
          endsAt: '12:30:00',
        },
      ],
    },
  },
]);

const scenarioById = new Map(STAGING_SCENARIOS.map((scenario) => [scenario.id, scenario]));

export function selectStagingScenarios(requestedIds = []) {
  const ids = requestedIds.length === 0
    ? STAGING_SCENARIOS.map((scenario) => scenario.id)
    : requestedIds;
  if (new Set(ids).size !== ids.length) {
    throw new Error('Scenario ids must be unique.');
  }
  const requested = new Set(ids);
  for (const id of requested) {
    if (!scenarioById.has(id)) {
      throw new Error(`Unknown staging scenario id: ${id}.`);
    }
  }
  return STAGING_SCENARIOS.filter((scenario) => requested.has(scenario.id));
}

export function stagingScenarioIdentity(runId, scenario) {
  return Object.freeze({
    scenarioId: scenario.id,
    email: `mylifegraph-staging+${runId}-${scenario.id}@example.test`,
    displayName: `[STAGING] ${scenario.label} (${runId})`,
  });
}

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}
