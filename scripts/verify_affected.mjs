import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const escalationCategories = new Set([
  'auth',
  'config',
  'core',
  'routing',
  'schema',
  'unknown',
]);

export function classifyPath(path) {
  if (
    /^(?:README\.md|AGENTS\.md|docs\/|.*\.md$)/.test(path) ||
    /^scripts\/check_(?:docs_consistency|frontend_visual_contract)(?:\.test)?\.mjs$/.test(
      path,
    )
  ) {
    return { category: 'docs', stack: null };
  }

  if (/^supabase\/(?:migrations|tests|config\.toml)/.test(path)) {
    return { category: 'schema', stack: 'schema' };
  }

  if (
    /^apps\/mobile\/lib\/features\/auth\//.test(path) ||
    /^apps\/mobile\/test\/.*auth/i.test(path) ||
    /^services\/ai_service\/(?:app|tests)\/.*auth/i.test(path)
  ) {
    return { category: 'auth', stack: inferStack(path) };
  }

  if (
    /^apps\/mobile\/lib\/core\//.test(path) ||
    /^apps\/mobile\/test\/.*(?:bootstrap|core|supabase)/i.test(path)
  ) {
    return { category: 'core', stack: 'flutter' };
  }

  if (
    /(?:^|\/)(?:app_)?router(?:_test)?\.(?:dart|py|mjs)$/.test(path) ||
    /(?:^|\/)routes?(?:\/|_)/.test(path)
  ) {
    return { category: 'routing', stack: inferStack(path) };
  }

  if (
    /^(?:package(?:-lock)?\.json|\.github\/|\.env|deploy\/(?:vps|backup)\/|scripts\/(?:e2e|verify|start_|lib\/local_supabase)|apps\/mobile\/(?:pubspec(?:\.lock)?|web\/|android\/)|services\/ai_service\/(?:requirements|pyproject|Dockerfile))/.test(
      path,
    ) ||
    /^e2e\//.test(path)
  ) {
    return { category: 'config', stack: inferStack(path) };
  }

  if (/^apps\/mobile\//.test(path)) {
    return { category: 'flutter', stack: 'flutter' };
  }

  if (/^services\/ai_service\//.test(path)) {
    return { category: 'backend', stack: 'backend' };
  }

  if (/^scripts\/(?:seed_|generate_brand_assets)/.test(path)) {
    return { category: 'config', stack: null };
  }

  return { category: 'unknown', stack: null };
}

export function classifyAffectedPaths(paths) {
  const normalizedPaths = [...new Set(paths.filter(Boolean))].sort();
  const entries = normalizedPaths.map((path) => ({
    path,
    ...classifyPath(path),
  }));
  const categories = new Set(entries.map((entry) => entry.category));
  const stacks = new Set(
    entries.map((entry) => entry.stack).filter((stack) => stack !== null),
  );

  let classification;
  if (entries.length === 0) {
    classification = 'none';
  } else if (stacks.size > 1) {
    classification = 'mixed';
  } else if (
    [...categories].some((category) =>
      escalationCategories.has(category),
    )
  ) {
    classification = [...categories].sort().join('+');
  } else if (categories.has('flutter')) {
    classification = 'flutter';
  } else if (categories.has('backend')) {
    classification = 'backend';
  } else {
    classification = 'docs';
  }

  return {
    classification,
    commands: selectLocalCommands(entries, stacks),
    categories: [...categories].sort(),
    stacks: [...stacks].sort(),
    paths: entries,
  };
}

// These two presentation-only constants keep their conservative CI category.
const localPresentationPaths = new Set([
  'apps/mobile/lib/core/constants/app_spacing.dart',
  'apps/mobile/lib/core/constants/app_radii.dart',
]);

function selectLocalCommands(entries, stacks) {
  if (entries.length === 0) return [];
  if (
    stacks.size > 1 ||
    entries.some(({ path, category }) =>
      escalationCategories.has(category) && !localPresentationPaths.has(path),
    )
  ) {
    return ['verify:full'];
  }
  if (stacks.has('flutter')) {
    return ['verify:source', 'verify:flutter', 'verify:web'];
  }
  if (stacks.has('backend')) {
    return ['verify:source', 'verify:backend'];
  }
  return ['verify:docs', 'verify:visual'];
}

export function selectCiGates(result) {
  const categories = new Set(result.categories);
  const stacks = new Set(result.stacks);
  return {
    web: stacks.has('flutter'),
    db: stacks.has('schema'),
    fullE2e:
      result.classification === 'mixed' ||
      ['auth', 'config', 'core', 'routing', 'schema', 'unknown'].some(
        (category) => categories.has(category),
      ),
  };
}

function inferStack(path) {
  if (path.startsWith('apps/mobile/')) {
    return 'flutter';
  }
  if (path.startsWith('services/ai_service/')) {
    return 'backend';
  }
  if (path.startsWith('supabase/')) {
    return 'schema';
  }
  return null;
}

function parseArguments(argv) {
  const formats = new Set(['--json', '--human', '--commands', '--ci']);
  if (argv.length !== 1 || !formats.has(argv[0])) {
    throw new Error(
      'Expected exactly one of --json, --human, --commands, or --ci.',
    );
  }
  return argv[0];
}

function main() {
  const format = parseArguments(process.argv.slice(2));
  const result = classifyAffectedPaths(
    readFileSync(0, 'utf8').split(/\r?\n/).filter(Boolean),
  );
  if (format === '--json') {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else if (format === '--human') {
    console.log(
      `Affected verification: ${result.classification}; commands: ${
        result.commands.join(', ') || 'none'
      }`,
    );
    for (const entry of result.paths) {
      console.log(`  ${entry.category}: ${entry.path}`);
    }
  } else if (format === '--commands') {
    for (const command of result.commands) {
      console.log(command);
    }
  } else {
    const gates = selectCiGates(result);
    console.log(`web=${gates.web}`);
    console.log(`db=${gates.db}`);
    console.log(`full_e2e=${gates.fullE2e}`);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
