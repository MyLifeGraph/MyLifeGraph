#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from 'node:fs';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const CURRENT_CONTRACTS_PATH = 'docs/current-contracts.json';
const CURRENT_CONTRACTS_SCHEMA_VERSION = 2;
const CURRENT_CONTRACTS_SCOPE =
  'named_cross_runtime_versions_and_explicit_exceptions';
const CONTRACT_SOURCE_SUFFIXES = [
  '.cjs',
  '.dart',
  '.js',
  '.json',
  '.mjs',
  '.py',
  '.sql',
  '.ts',
  '.tsx',
  '.yaml',
  '.yml',
];

const IGNORED_DIRECTORIES = new Set([
  '.dart_tool',
  '.git',
  '.idea',
  '.tools',
  '.vscode',
  'build',
  'node_modules',
]);

const REQUIRED_MIGRATION_DOCS = [
  'docs/supabase-current-state.md',
];

export const DOCS_IMPACT_RULES = [
  {
    name: 'Supabase migration',
    triggers: [/^supabase\/migrations\/.*\.sql$/],
    requiredAll: [
      'docs/supabase-current-state.md',
      'docs/verification.md',
    ],
  },
  {
    name: 'FastAPI route',
    triggers: [
      /^services\/ai_service\/app\/api\/routes\/.*\.py$/,
      /^services\/ai_service\/app\/main\.py$/,
      /^services\/ai_service\/app\/core\/config\.py$/,
    ],
    requiredAll: [
      'docs/architecture.md',
      'services/ai_service/README.md',
    ],
  },
  {
    name: 'Daily Capture',
    triggers: [
      /^apps\/mobile\/lib\/features\/quick_action\/(?:domain\/quick_check_in|data\/(?:guest_quick_check_in|quick_check_in_supabase_data_source)|presentation\/(?:pages\/(?:quick_mood_check_in|morning_calibration)_page|widgets\/daily_capture_controls))\.dart$/,
    ],
    requiredAll: [
      'apps/mobile/README.md',
      'docs/daily-briefing-implementation-plan.md',
    ],
  },
  {
    name: 'Daily State',
    triggers: [
      /^services\/ai_service\/app\/services\/snapshot_daily_state\.py$/,
    ],
    requiredAll: [
      'docs/daily-briefing-implementation-plan.md',
      'services/ai_service/README.md',
    ],
  },
  {
    name: 'Deadline Planner',
    triggers: [
      /^apps\/mobile\/lib\/features\/deadline_plans\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/deadline_plans|models\/deadline_plans|repositories\/deadline_plan_repository|services\/deadline_plan_service)\.py$/,
      /^services\/ai_service\/app\/services\/planning_availability\.py$/,
    ],
    requiredAll: [
      'docs/deadline-planner-v1-contract.md',
      'docs/exam-week-outlook-v1-contract.md',
    ],
  },
  {
    name: 'Planner',
    triggers: [
      /^apps\/mobile\/lib\/features\/planner\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/planner|models\/planner|repositories\/planner_repository|services\/planner_service)\.py$/,
    ],
    requiredAll: ['docs/planner-v1-contract.md'],
  },
  {
    name: 'Coach',
    triggers: [
      /^apps\/mobile\/lib\/features\/coach\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/deps\/coach|api\/routes\/coach|models\/coach|providers\/.*|repositories\/coach.*|services\/coach.*)\.(?:py|json)$/,
    ],
    requiredAll: ['docs/phase-10-controlled-coach-plan.md'],
  },
  {
    name: 'Setup or Intake',
    triggers: [
      /^apps\/mobile\/lib\/features\/(?:auth|onboarding)\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/intake|models\/intake|repositories\/intake_repository|services\/intake_service)\.py$/,
    ],
    requiredAny: [
      'docs/setup-personalization-retirement-contract.md',
      'docs/study-setup-v1-contract.md',
    ],
  },
  {
    name: 'Today Overview',
    triggers: [
      /^apps\/mobile\/lib\/features\/dashboard\/.*today.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/today|models\/today_overview|repositories\/today_overview_repository|services\/today_overview_service)\.py$/,
    ],
    requiredAll: ['docs/today-overview-v1-contract.md'],
  },
  {
    name: 'Calendar Import',
    triggers: [
      /^apps\/mobile\/lib\/features\/calendar_integration\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/calendar_integrations|models\/calendar_integrations|repositories\/calendar_integration_repository|services\/calendar_.*)\.py$/,
    ],
    requiredAll: ['docs/phase-9-calendar-import-contract.md'],
  },
  {
    name: 'Weekly Review',
    triggers: [
      /^apps\/mobile\/lib\/features\/weekly_review\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/weekly_reviews|models\/weekly_reviews|repositories\/weekly_review_repository|services\/weekly_review_service)\.py$/,
    ],
    requiredAll: ['docs/phase-8-weekly-review-contract.md'],
  },
  {
    name: 'Notification',
    triggers: [
      /^apps\/mobile\/lib\/features\/notifications\/.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/notifications|models\/notifications|repositories\/notification_repository|services\/notification_service)\.py$/,
    ],
    requiredAny: [
      'docs/notification-delivery-v1-contract.md',
      'docs/notification-lifecycle-v1-contract.md',
    ],
  },
  {
    name: 'Account controls',
    triggers: [
      /^apps\/mobile\/lib\/features\/settings\/.*account.*\.dart$/,
      /^services\/ai_service\/app\/(?:api\/routes\/account|models\/account|repositories\/account_repository|services\/account_service)\.py$/,
    ],
    requiredAll: ['docs/v1-account-controls-contract.md'],
  },
  {
    name: 'Verification automation',
    triggers: [
      /^e2e\/.*$/,
      /^scripts\/check_docs_consistency(?:\.test)?\.mjs$/,
      /^scripts\/e2e_web\.sh$/,
      /^scripts\/verify\.sh$/,
      /^scripts\/verify_supabase_local\.sh$/,
    ],
    requiredAll: ['docs/verification.md'],
  },
  {
    name: 'Local workflow',
    triggers: [
      /^scripts\/(?:start_frontend|start_local_stack|seed_demo_data|seed_student_feature_data)\.(?:sh|mjs|py)$/,
      /^\.env\.example$/,
    ],
    requiredAll: ['docs/local-dev.md'],
  },
];

const STALE_CURRENT_CLAIMS = [
  {
    pattern: /\bCurrent Capture V3\b/gi,
    message: 'Current Capture is V4.',
  },
  {
    pattern: /\bGuest V3 storage\b/gi,
    message: 'Current guest capture storage is V4.',
  },
  {
    pattern: /\bDaily Capture V2 metadata\b/gi,
    message: 'Current capture docs must describe V2/V3/V4 compatibility.',
  },
  {
    pattern: /\bDaily Capture V2 projection\b/gi,
    message: 'Current capture docs must describe V2/V3/V4 compatibility.',
  },
  {
    pattern: /\bprogressive optional goals\b/gi,
    message: 'Goals are retired from active Setup.',
  },
  {
    pattern: /\bcoach-context-v1 data\b/gi,
    message: 'Current Coach agent context uses personal-snapshot-v1.',
  },
  {
    pattern: /\breconciles notification preferences\b/gi,
    message: 'Setup must leave Notification preferences unchanged.',
  },
  {
    pattern: /\bInsights visibly consumes\b/gi,
    message: 'Do not claim an unimplemented visible Insights consumer.',
  },
];

const VERIFICATION_EVIDENCE_PATTERNS = [
  {
    pattern: /\be2e-\d+@example\.test\b/gi,
    label: 'an exact E2E identity',
  },
  {
    pattern: /\bE2E_RUN_ID=\d+\b/g,
    label: 'an exact E2E run id',
  },
  {
    pattern: /\b\d+\s+passed(?:,\s*\d+\s+skipped)?\b/gi,
    label: 'an exact test result',
  },
  {
    pattern: /\b(?:all\s+)?\d+\s+Flutter tests?\b/gi,
    label: 'an exact Flutter test count',
  },
  {
    pattern: /\b(?:commit|checkout)\s+`?[0-9a-f]{7,40}`?\b/gi,
    label: 'an exact commit id',
  },
];

function normalizePath(value) {
  return value.split(sep).join('/');
}

function lineNumberAt(text, index) {
  return text.slice(0, index).split('\n').length;
}

function readUtf8(path) {
  return readFileSync(path, 'utf8');
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, expected) {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return (
    actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index])
  );
}

function isSorted(values) {
  return values.every(
    (value, index) => index === 0 || values[index - 1] <= value,
  );
}

function isNormalizedRepositoryPath(path, suffixes) {
  return (
    typeof path === 'string' &&
    path.length > 0 &&
    !path.startsWith('/') &&
    !path.startsWith('./') &&
    !path.includes('\\') &&
    !path.includes('//') &&
    !path.split('/').includes('.') &&
    !path.split('/').includes('..') &&
    suffixes.some((suffix) => path.endsWith(suffix))
  );
}

function validatePathArray(value, { contractKey, field, suffixes }, errors) {
  if (!Array.isArray(value) || value.length === 0) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' must have a non-empty ${field} array.`,
    );
    return [];
  }
  const paths = value.filter((path) => typeof path === 'string');
  if (paths.length !== value.length || paths.some((path) => path.length === 0)) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' ${field} must contain non-empty strings only.`,
    );
  }
  if (paths.some((path) => !isNormalizedRepositoryPath(path, suffixes))) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' ${field} must contain normalized repository-relative ${suffixes.join(' or ')} paths.`,
    );
  }
  if (new Set(paths).size !== paths.length) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' ${field} contains duplicates.`,
    );
  }
  if (!isSorted(paths)) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' ${field} must be sorted.`,
    );
  }
  return paths.filter((path) => isNormalizedRepositoryPath(path, suffixes));
}

function sourceSortKey(source) {
  return `${source.path}\u0000${source.symbol ?? ''}\u0000${source.locator ?? ''}`;
}

function validateSourceArray(value, contractKey, errors) {
  if (!Array.isArray(value) || value.length === 0) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' must have a non-empty sources array.`,
    );
    return [];
  }

  const sources = [];
  for (const [index, source] of value.entries()) {
    if (!isPlainObject(source)) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources[${index}] must be an object.`,
      );
      continue;
    }
    const isSymbolSource = exactKeys(source, ['path', 'symbol']);
    const isLocatorSource = exactKeys(source, ['locator', 'path']);
    if (!isSymbolSource && !isLocatorSource) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources[${index}] must have exactly path and either symbol or locator.`,
      );
      continue;
    }

    if (!isNormalizedRepositoryPath(source.path, CONTRACT_SOURCE_SUFFIXES)) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources[${index}].path must be a normalized repository-relative source path.`,
      );
      continue;
    }
    if (
      isSymbolSource &&
      (typeof source.symbol !== 'string' ||
        !/^[A-Za-z_][A-Za-z0-9_]*$/.test(source.symbol))
    ) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources[${index}].symbol must be an identifier.`,
      );
      continue;
    }
    if (isLocatorSource) {
      const placeholderCount =
        typeof source.locator === 'string'
          ? source.locator.split('{version}').length - 1
          : 0;
      if (placeholderCount !== 1) {
        errors.push(
          `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources[${index}].locator must contain exactly one {version} placeholder.`,
        );
        continue;
      }
    }
    sources.push(
      isSymbolSource
        ? { path: source.path, symbol: source.symbol }
        : { locator: source.locator, path: source.path },
    );
  }

  const sourceKeys = sources.map(sourceSortKey);
  if (new Set(sourceKeys).size !== sourceKeys.length) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources contains duplicates.`,
    );
  }
  if (!isSorted(sourceKeys)) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: contract '${contractKey}' sources must be sorted by path and selector.`,
    );
  }
  return sources;
}

export function validateCurrentContractsMetadata(value) {
  const errors = [];
  if (!isPlainObject(value)) {
    return {
      contracts: [],
      errors: [`${CURRENT_CONTRACTS_PATH}: root must be an object.`],
    };
  }
  if (!exactKeys(value, ['schema_version', 'scope', 'contracts'])) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: root keys must be exactly 'schema_version', 'scope', and 'contracts'.`,
    );
  }
  if (value.schema_version !== CURRENT_CONTRACTS_SCHEMA_VERSION) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: schema_version must be ${CURRENT_CONTRACTS_SCHEMA_VERSION}.`,
    );
  }
  if (value.scope !== CURRENT_CONTRACTS_SCOPE) {
    errors.push(
      `${CURRENT_CONTRACTS_PATH}: scope must be '${CURRENT_CONTRACTS_SCOPE}'.`,
    );
  }
  if (!Array.isArray(value.contracts) || value.contracts.length === 0) {
    errors.push(`${CURRENT_CONTRACTS_PATH}: contracts must be a non-empty array.`);
    return { contracts: [], errors };
  }

  const contracts = [];
  for (const [index, entry] of value.contracts.entries()) {
    if (!isPlainObject(entry)) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contracts[${index}] must be an object.`,
      );
      continue;
    }
    if (
      !exactKeys(entry, [
        'coverage',
        'key',
        'version',
        'sources',
        'owners',
      ])
    ) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract at index ${index} must have exactly coverage, key, version, sources, and owners.`,
      );
    }
    const key = typeof entry.key === 'string' ? entry.key : '';
    const version = typeof entry.version === 'string' ? entry.version : '';
    const coverage =
      entry.coverage === 'shared_named' || entry.coverage === 'explicit'
        ? entry.coverage
        : '';
    if (!/^[a-z][A-Za-z0-9]*$/.test(key)) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract at index ${index} has an invalid key.`,
      );
    }
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(version)) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${key || index}' has an invalid version.`,
      );
    }
    if (!coverage) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${key || index}' coverage must be 'shared_named' or 'explicit'.`,
      );
    }
    const sources = validateSourceArray(
      entry.sources,
      key || String(index),
      errors,
    );
    const owners = validatePathArray(
      entry.owners,
      {
        contractKey: key || String(index),
        field: 'owners',
        suffixes: ['.md'],
      },
      errors,
    );
    contracts.push({ coverage, key, version, sources, owners });
  }

  const keys = contracts.map((contract) => contract.key);
  const versions = contracts.map((contract) => contract.version);
  if (new Set(keys).size !== keys.length) {
    errors.push(`${CURRENT_CONTRACTS_PATH}: contract keys must be unique.`);
  }
  if (new Set(versions).size !== versions.length) {
    errors.push(`${CURRENT_CONTRACTS_PATH}: contract versions must be unique.`);
  }
  if (!isSorted(keys)) {
    errors.push(`${CURRENT_CONTRACTS_PATH}: contracts must be sorted by key.`);
  }
  return { contracts, errors };
}

export function loadCurrentContractsMetadata(root) {
  const path = resolve(root, CURRENT_CONTRACTS_PATH);
  if (!existsSync(path)) {
    return {
      contracts: [],
      errors: [`${CURRENT_CONTRACTS_PATH}: metadata file is missing.`],
    };
  }
  let value;
  try {
    value = JSON.parse(readUtf8(path));
  } catch (error) {
    return {
      contracts: [],
      errors: [
        `${CURRENT_CONTRACTS_PATH}: invalid JSON (${error instanceof Error ? error.message : String(error)}).`,
      ],
    };
  }
  const result = validateCurrentContractsMetadata(value);
  for (const contract of result.contracts) {
    for (const repositoryPath of [
      ...contract.sources.map((source) => source.path),
      ...contract.owners,
    ]) {
      const absolutePath = resolve(root, repositoryPath);
      if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
        result.errors.push(
          `${CURRENT_CONTRACTS_PATH}: contract '${contract.key}' references missing file '${repositoryPath}'.`,
        );
      }
    }
  }
  return result;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function resetRegExp(pattern) {
  return new RegExp(pattern.source, pattern.flags);
}

export function listMarkdownFiles(root) {
  const files = [];

  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.isDirectory() && IGNORED_DIRECTORIES.has(entry.name)) {
        continue;
      }
      const absolutePath = join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(absolutePath);
      } else if (entry.isFile() && extname(entry.name).toLowerCase() === '.md') {
        files.push(normalizePath(relative(root, absolutePath)));
      }
    }
  }

  visit(root);
  return files.sort();
}

export function isHistoricalDocument(text) {
  return /^Status:\s*historical\b/im.test(text.slice(0, 1200));
}

export function markdownHeadingAnchors(text) {
  const anchors = new Set();
  const occurrences = new Map();

  for (const line of text.split('\n')) {
    const match = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
    if (!match) {
      continue;
    }
    const heading = match[2]
      .replace(/<[^>]*>/g, '')
      .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      .replace(/[`*_~]/g, '')
      .toLowerCase();
    const baseSlug = heading
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .trim()
      .replace(/\s+/g, '-');
    if (!baseSlug) {
      continue;
    }
    const duplicateIndex = occurrences.get(baseSlug) ?? 0;
    occurrences.set(baseSlug, duplicateIndex + 1);
    anchors.add(duplicateIndex === 0 ? baseSlug : `${baseSlug}-${duplicateIndex}`);
  }

  for (const match of text.matchAll(/\b(?:id|name)=["']([^"']+)["']/gi)) {
    anchors.add(match[1]);
  }
  return anchors;
}

function extractMarkdownTargets(text) {
  const targets = [];
  const inlinePattern =
    /!?\[[^\]]*]\(\s*(<[^>]+>|[^)\s]+)(?:\s+["'][^"']*["'])?\s*\)/g;
  const referencePattern = /^\s*\[[^\]]+]:\s*(<[^>]+>|\S+)/gm;

  for (const pattern of [inlinePattern, referencePattern]) {
    for (const match of text.matchAll(pattern)) {
      targets.push({ target: match[1], index: match.index ?? 0 });
    }
  }
  return targets;
}

function decodeLinkPart(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

export function findMarkdownLinkErrors(root, markdownFiles = listMarkdownFiles(root)) {
  const errors = [];

  for (const relativePath of markdownFiles) {
    const absolutePath = resolve(root, relativePath);
    const text = readUtf8(absolutePath);
    for (const { target: rawTarget, index } of extractMarkdownTargets(text)) {
      const target = rawTarget.replace(/^<|>$/g, '');
      if (
        /^(?:https?:|mailto:|tel:|data:|app:|javascript:)/i.test(target) ||
        target === ''
      ) {
        continue;
      }

      const hashIndex = target.indexOf('#');
      const pathAndQuery = hashIndex === -1 ? target : target.slice(0, hashIndex);
      const fragment =
        hashIndex === -1 ? '' : decodeLinkPart(target.slice(hashIndex + 1));
      const pathPart = decodeLinkPart(pathAndQuery.split('?')[0]);

      if (pathPart.startsWith('/')) {
        continue;
      }

      const targetPath = pathPart
        ? resolve(dirname(absolutePath), pathPart)
        : absolutePath;
      if (!existsSync(targetPath)) {
        errors.push(
          `${relativePath}:${lineNumberAt(text, index)}: broken Markdown link '${target}'`,
        );
        continue;
      }

      if (
        fragment &&
        statSync(targetPath).isFile() &&
        extname(targetPath).toLowerCase() === '.md'
      ) {
        const anchors = markdownHeadingAnchors(readUtf8(targetPath));
        if (!anchors.has(fragment)) {
          errors.push(
            `${relativePath}:${lineNumberAt(text, index)}: missing Markdown anchor '#${fragment}' in ${normalizePath(relative(root, targetPath))}`,
          );
        }
      }
    }
  }

  return errors;
}

const CONTRACT_VERSION_PATTERN =
  '[a-z0-9]+(?:-[a-z0-9]+)*-v[0-9]+';

function canonicalSourceMatches(text, source) {
  let pattern;
  if (source.symbol) {
    pattern = new RegExp(
      `\\b${escapeRegExp(source.symbol)}\\b\\s*(?::[^=\\n]+)?=\\s*['"](${CONTRACT_VERSION_PATTERN})['"]`,
      'g',
    );
  } else {
    const [before, after] = source.locator.split('{version}');
    pattern = new RegExp(
      `${escapeRegExp(before)}(${CONTRACT_VERSION_PATTERN})${escapeRegExp(after)}`,
      'g',
    );
  }
  return [...text.matchAll(pattern)].map((match) => match[1]);
}

export function extractCanonicalVersions(root, contracts) {
  const errors = [];
  const versions = {};

  for (const contract of contracts) {
    const sourceVersions = [];
    for (const source of contract.sources) {
      const absolutePath = resolve(root, source.path);
      if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
        continue;
      }
      const matches = canonicalSourceMatches(readUtf8(absolutePath), source);
      const selector = source.symbol
        ? `symbol '${source.symbol}'`
        : `locator '${source.locator}'`;
      if (matches.length === 0) {
        errors.push(
          `${source.path}: could not extract contract '${contract.key}' through ${selector}.`,
        );
        continue;
      }
      if (matches.length > 1) {
        errors.push(
          `${source.path}: ${selector} is ambiguous for contract '${contract.key}' (${matches.length} matches).`,
        );
        continue;
      }
      const sourceVersion = matches[0];
      sourceVersions.push(sourceVersion);
      if (sourceVersion !== contract.version) {
        errors.push(
          `${CURRENT_CONTRACTS_PATH}: contract '${contract.key}' declares '${contract.version}', but ${source.path} ${selector} declares '${sourceVersion}'.`,
        );
      }
    }
    versions[contract.key] = sourceVersions[0] ?? null;
  }

  return { errors, versions };
}

function listFilesBySuffix(root, suffix) {
  if (!existsSync(root)) {
    return [];
  }
  const files = [];
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.isDirectory() && IGNORED_DIRECTORIES.has(entry.name)) {
        continue;
      }
      const absolutePath = join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(absolutePath);
      } else if (entry.isFile() && entry.name.endsWith(suffix)) {
        files.push(absolutePath);
      }
    }
  }
  visit(root);
  return files.sort();
}

function namedContractDeclarations(root, runtime) {
  const configuration =
    runtime === 'flutter'
      ? {
          directory: 'apps/mobile/lib',
          pattern: new RegExp(
            `^[ \\t]*(?:static[ \\t]+)?const[ \\t]+(?:String[ \\t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \\t]*=[ \\t\\r\\n]*['"](${CONTRACT_VERSION_PATTERN})['"]`,
            'gm',
          ),
          suffix: '.dart',
        }
      : {
          directory: 'services/ai_service/app',
          pattern: new RegExp(
            `^[ \\t]*([A-Z][A-Z0-9_]*)[ \\t]*(?::[^=\\n]+)?=[ \\t]*['"](${CONTRACT_VERSION_PATTERN})['"]`,
            'gm',
          ),
          suffix: '.py',
        };
  const declarations = [];
  const directory = resolve(root, configuration.directory);
  for (const absolutePath of listFilesBySuffix(directory, configuration.suffix)) {
    const text = readUtf8(absolutePath);
    for (const match of text.matchAll(configuration.pattern)) {
      const symbol = match[1];
      if (/(?:legacy|previous|prior)/i.test(symbol)) {
        continue;
      }
      declarations.push({
        path: normalizePath(relative(root, absolutePath)),
        runtime,
        symbol,
        version: match[2],
      });
    }
  }
  return declarations;
}

export function findCrossRuntimeContractCoverageErrors(root, contracts) {
  const errors = [];
  const declarations = [
    ...namedContractDeclarations(root, 'flutter'),
    ...namedContractDeclarations(root, 'fastapi'),
  ];
  const runtimesByVersion = new Map();
  for (const declaration of declarations) {
    if (!runtimesByVersion.has(declaration.version)) {
      runtimesByVersion.set(declaration.version, new Set());
    }
    runtimesByVersion.get(declaration.version).add(declaration.runtime);
  }
  const sharedVersions = new Set(
    [...runtimesByVersion]
      .filter(([, runtimes]) => runtimes.size === 2)
      .map(([version]) => version),
  );
  const metadataByVersion = new Map(
    contracts.map((contract) => [contract.version, contract]),
  );

  for (const version of [...sharedVersions].sort()) {
    const contract = metadataByVersion.get(version);
    if (!contract) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: shared named Flutter/FastAPI contract '${version}' is not registered.`,
      );
      continue;
    }
    if (contract.coverage !== 'shared_named') {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: shared named contract '${contract.key}' must use coverage 'shared_named'.`,
      );
    }
    for (const declaration of declarations.filter(
      (candidate) => candidate.version === version,
    )) {
      const registered = contract.sources.some(
        (source) =>
          source.path === declaration.path &&
          source.symbol === declaration.symbol,
      );
      if (!registered) {
        errors.push(
          `${CURRENT_CONTRACTS_PATH}: contract '${contract.key}' must register shared named source ${declaration.path}:${declaration.symbol}.`,
        );
      }
    }
  }
  for (const contract of contracts) {
    if (
      contract.coverage === 'shared_named' &&
      !sharedVersions.has(contract.version)
    ) {
      errors.push(
        `${CURRENT_CONTRACTS_PATH}: contract '${contract.key}' uses coverage 'shared_named', but no named Flutter/FastAPI declaration pair was found.`,
      );
    }
  }
  return errors;
}

export function findRequiredVersionErrors(
  contracts,
  documents,
) {
  const errors = [];
  for (const contract of contracts) {
    for (const path of contract.owners) {
      const text = documents.get(path);
      if (text === undefined) {
        errors.push(`${path}: required version document is missing.`);
      } else if (
        !new RegExp(
          `(?:^|[^a-z0-9-])${escapeRegExp(contract.version)}(?![a-z0-9-])`,
          'i',
        ).test(text)
      ) {
        errors.push(
          `${path}: missing canonical ${contract.key} contract '${contract.version}'.`,
        );
      }
    }
  }
  return errors;
}

export function latestMigrationName(root) {
  const migrationDirectory = resolve(root, 'supabase/migrations');
  const migrations = readdirSync(migrationDirectory)
    .filter((name) => /^\d+_.*\.sql$/.test(name))
    .sort();
  if (migrations.length === 0) {
    throw new Error('No Supabase migrations were found.');
  }
  return migrations.at(-1);
}

export function findLatestMigrationErrors(
  root,
  documents,
  requiredPaths = REQUIRED_MIGRATION_DOCS,
) {
  const errors = [];
  const latest = latestMigrationName(root);
  for (const path of requiredPaths) {
    const text = documents.get(path);
    if (text === undefined) {
      errors.push(`${path}: required migration document is missing.`);
    } else if (!text.includes(latest)) {
      errors.push(`${path}: latest migration '${latest}' is not documented.`);
    }
  }

  const boundaryPattern =
    /(migration chain currently ends at|reset`?\s+(?:should|must) complete through|expected successful reset output applies migrations through|fresh migration-chain verification should end at)[\s\S]{0,180}?(\d+_[A-Za-z0-9_]+\.sql)/gi;
  for (const [path, text] of documents) {
    if (path === 'docs/verification.md' || isHistoricalDocument(text)) {
      continue;
    }
    for (const match of text.matchAll(boundaryPattern)) {
      const namedMigration = match[2].split('/').at(-1);
      if (namedMigration !== latest) {
        errors.push(
          `${path}:${lineNumberAt(text, match.index ?? 0)}: current migration boundary names '${namedMigration}', expected '${latest}'.`,
        );
      }
    }
  }

  return errors;
}

export function extractFastApiRoutesFromTexts(
  routeSources,
  apiPrefix = '/v1',
) {
  const routes = [];
  const prefixes = new Set();

  for (const [path, text] of routeSources) {
    const routerCall = /router\s*=\s*APIRouter\(([\s\S]*?)\)\s*/.exec(text);
    const prefixMatch = routerCall
      ? /\bprefix\s*=\s*['"]([^'"]*)['"]/.exec(routerCall[1])
      : null;
    const routerPrefix = prefixMatch?.[1] ?? '';
    prefixes.add(`${apiPrefix}${routerPrefix}` || '/');

    const decoratorPattern =
      /@router\.(get|post|put|patch|delete)\(\s*['"]([^'"]*)['"]/g;
    for (const match of text.matchAll(decoratorPattern)) {
      const routePath = `${apiPrefix}${routerPrefix}${match[2]}` || '/';
      routes.push({
        method: match[1].toUpperCase(),
        path: routePath.replace(/\/{2,}/g, '/'),
        source: path,
      });
    }
  }

  return { prefixes, routes };
}

export function extractFastApiRoutes(root) {
  const configText = readUtf8(
    resolve(root, 'services/ai_service/app/core/config.py'),
  );
  const apiPrefix =
    /\bapi_prefix\s*:\s*str\s*=\s*Field\(\s*default\s*=\s*['"]([^'"]+)['"]/.exec(
      configText,
    )?.[1] ?? '/v1';
  const routeDirectory = resolve(root, 'services/ai_service/app/api/routes');
  const routeSources = new Map(
    readdirSync(routeDirectory)
      .filter((name) => name.endsWith('.py') && name !== '__init__.py')
      .sort()
      .map((name) => [
        normalizePath(relative(root, join(routeDirectory, name))),
        readUtf8(join(routeDirectory, name)),
      ]),
  );
  return extractFastApiRoutesFromTexts(routeSources, apiPrefix);
}

function routePattern(routePath) {
  const segments = routePath.split('/');
  const pattern = segments
    .map((segment) =>
      /^\{[^}]+\}$/.test(segment) ? '[^/]+' : escapeRegExp(segment),
    )
    .join('/');
  return new RegExp(`^${pattern}$`);
}

function normalizeDocumentedRoute(routePath) {
  const withoutQuery = routePath.split('?')[0];
  return withoutQuery
    .replace(/<[^/>]+>/g, '{parameter}')
    .replace(/\/+$/g, '');
}

function documentedMethodsBefore(text, index) {
  const lineStart = text.lastIndexOf('\n', index - 1) + 1;
  const prefix = text
    .slice(lineStart, index)
    .replace(/[`*_]/g, '')
    .trimEnd();
  const match =
    /((?:GET|POST|PUT|PATCH|DELETE)(?:\s*[|/]\s*(?:GET|POST|PUT|PATCH|DELETE))*)\s*\|?\s*$/i.exec(
      prefix,
    );
  return match
    ? match[1]
        .toUpperCase()
        .split(/\s*[|/]\s*/)
        .filter(Boolean)
    : [];
}

export function findDocumentedRouteErrorsFromTexts(routeInventory, documents) {
  const errors = [];
  const actualPatterns = routeInventory.routes.map((route) => ({
    ...route,
    pattern: routePattern(route.path),
  }));
  const routeReferencePattern =
    /\/v1(?:\/[A-Za-z0-9._~:{}<>-]+)+(?:\?[A-Za-z0-9._~:{}<>=&%-]+)?/g;

  for (const [path, text] of documents) {
    if (isHistoricalDocument(text)) {
      continue;
    }
    for (const match of text.matchAll(routeReferencePattern)) {
      const documentedRoute = normalizeDocumentedRoute(match[0]);
      const matchingRoutes = actualPatterns.filter(({ pattern }) =>
        pattern.test(documentedRoute),
      );
      const matchesPrefix = routeInventory.prefixes.has(documentedRoute);
      if (matchingRoutes.length === 0 && !matchesPrefix) {
        errors.push(
          `${path}:${lineNumberAt(text, match.index ?? 0)}: documented FastAPI route '${match[0]}' does not exist in source.`,
        );
        continue;
      }
      if (matchesPrefix) {
        continue;
      }
      for (const method of documentedMethodsBefore(text, match.index ?? 0)) {
        if (!matchingRoutes.some((route) => route.method === method)) {
          errors.push(
            `${path}:${lineNumberAt(text, match.index ?? 0)}: documented method ${method} is not defined for FastAPI route '${match[0]}'.`,
          );
        }
      }
    }
  }

  return errors;
}

export function findVerificationEvidenceErrors(documents) {
  const errors = [];
  for (const [path, text] of documents) {
    if (path === 'docs/verification.md' || isHistoricalDocument(text)) {
      continue;
    }
    for (const evidence of VERIFICATION_EVIDENCE_PATTERNS) {
      const pattern = resetRegExp(evidence.pattern);
      for (const match of text.matchAll(pattern)) {
        errors.push(
          `${path}:${lineNumberAt(text, match.index ?? 0)}: ${evidence.label} belongs only in docs/verification.md or an explicitly historical report.`,
        );
      }
    }
  }
  return errors;
}

export function findStaleClaimErrors(documents) {
  const errors = [];
  for (const [path, text] of documents) {
    if (path === 'docs/verification.md' || isHistoricalDocument(text)) {
      continue;
    }
    for (const staleClaim of STALE_CURRENT_CLAIMS) {
      const pattern = resetRegExp(staleClaim.pattern);
      for (const match of text.matchAll(pattern)) {
        errors.push(
          `${path}:${lineNumberAt(text, match.index ?? 0)}: ${staleClaim.message}`,
        );
      }
    }
  }
  return errors;
}

export function findDocsImpactErrors(
  changedFiles,
  rules = DOCS_IMPACT_RULES,
) {
  const normalizedFiles = changedFiles.map(normalizePath);
  const changedSet = new Set(normalizedFiles);
  const errors = [];

  for (const rule of rules) {
    const triggeringFiles = normalizedFiles.filter((path) =>
      rule.triggers.some((pattern) => pattern.test(path)),
    );
    if (triggeringFiles.length === 0) {
      continue;
    }
    const missingAll = (rule.requiredAll ?? []).filter(
      (path) => !changedSet.has(path),
    );
    if (missingAll.length > 0) {
      errors.push(
        `${rule.name}: ${triggeringFiles.join(', ')} changed without required docs ${missingAll.join(', ')}.`,
      );
    }
    const requiredAny = rule.requiredAny ?? [];
    if (
      requiredAny.length > 0 &&
      !requiredAny.some((path) => changedSet.has(path))
    ) {
      errors.push(
        `${rule.name}: ${triggeringFiles.join(', ')} changed without one owning doc (${requiredAny.join(' or ')}).`,
      );
    }
  }
  return errors;
}

function gitOutput(root, args) {
  return execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

export function changedFilesForDocsImpact(
  root,
  baseRef = process.env.DOCS_BASE_REF,
) {
  const changed = new Set();
  if (baseRef) {
    for (const path of gitOutput(root, ['diff', '--name-only', `${baseRef}...HEAD`])) {
      changed.add(normalizePath(path));
    }
  }
  for (const path of gitOutput(root, ['diff', '--name-only', 'HEAD'])) {
    changed.add(normalizePath(path));
  }
  for (const path of gitOutput(root, [
    'ls-files',
    '--others',
    '--exclude-standard',
  ])) {
    changed.add(normalizePath(path));
  }
  return [...changed].sort();
}

export function runDocumentationChecks(
  root = DEFAULT_ROOT,
  { changedFiles } = {},
) {
  const markdownFiles = listMarkdownFiles(root);
  const documents = new Map(
    markdownFiles.map((path) => [path, readUtf8(resolve(root, path))]),
  );
  const errors = [];

  errors.push(...findMarkdownLinkErrors(root, markdownFiles));

  const metadata = loadCurrentContractsMetadata(root);
  errors.push(...metadata.errors);

  const canonical = extractCanonicalVersions(root, metadata.contracts);
  errors.push(...canonical.errors);
  errors.push(
    ...findCrossRuntimeContractCoverageErrors(root, metadata.contracts),
  );
  errors.push(...findRequiredVersionErrors(metadata.contracts, documents));

  errors.push(...findLatestMigrationErrors(root, documents));

  const routeInventory = extractFastApiRoutes(root);
  errors.push(...findDocumentedRouteErrorsFromTexts(routeInventory, documents));

  errors.push(...findVerificationEvidenceErrors(documents));
  errors.push(...findStaleClaimErrors(documents));

  const impactFiles =
    changedFiles ?? changedFilesForDocsImpact(root, process.env.DOCS_BASE_REF);
  errors.push(...findDocsImpactErrors(impactFiles));

  return {
    changedFiles: impactFiles,
    errors: [...new Set(errors)].sort(),
    markdownFileCount: markdownFiles.length,
    routeCount: routeInventory.routes.length,
  };
}

function main() {
  try {
    const result = runDocumentationChecks();
    if (result.errors.length > 0) {
      console.error(
        `Documentation consistency check failed with ${result.errors.length} issue(s):`,
      );
      for (const [index, error] of result.errors.entries()) {
        console.error(`${index + 1}. ${error}`);
      }
      process.exitCode = 1;
      return;
    }
    console.log(
      `Documentation consistency checks passed (${result.markdownFileCount} Markdown files, ${result.routeCount} FastAPI routes).`,
    );
  } catch (error) {
    console.error(
      `Documentation consistency check could not run: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exitCode = 1;
  }
}

if (resolve(process.argv[1] ?? '') === SCRIPT_PATH) {
  main();
}
