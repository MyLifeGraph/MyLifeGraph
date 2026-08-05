import assert from 'node:assert/strict';
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import {
  extractCanonicalVersions,
  extractFastApiRoutesFromTexts,
  findCrossRuntimeContractCoverageErrors,
  findDocsImpactErrors,
  findDocumentedRouteErrorsFromTexts,
  findLatestMigrationErrors,
  findMarkdownLinkErrors,
  findRequiredVersionErrors,
  findStaleClaimErrors,
  findVerificationEvidenceErrors,
  isHistoricalDocument,
  loadCurrentContractsMetadata,
  validateCurrentContractsMetadata,
} from './check_docs_consistency.mjs';

function withFixture(files, callback) {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-docs-check-'));
  try {
    for (const [path, contents] of Object.entries(files)) {
      const absolutePath = join(root, path);
      mkdirSync(dirname(absolutePath), { recursive: true });
      writeFileSync(absolutePath, contents, 'utf8');
    }
    callback(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('Markdown links require an existing file and heading anchor', () => {
  withFixture(
    {
      'README.md':
        '[Baseline](docs/verification.md#current-verified-baseline)\n',
      'docs/verification.md': '# Verification\n\n## Current Verified Baseline\n',
    },
    (root) => {
      assert.deepEqual(
        findMarkdownLinkErrors(root, [
          'README.md',
          'docs/verification.md',
        ]),
        [],
      );

      writeFileSync(
        join(root, 'README.md'),
        '[Missing](docs/verification.md#unknown-heading)\n',
        'utf8',
      );
      assert.match(
        findMarkdownLinkErrors(root, [
          'README.md',
          'docs/verification.md',
        ])[0],
        /missing Markdown anchor/,
      );
    },
  );
});

test('documented route checks understand multiline FastAPI decorators and parameters', () => {
  const inventory = extractFastApiRoutesFromTexts(
    new Map([
      [
        'routes/things.py',
        `
router = APIRouter(prefix="/things", tags=["things"])

@router.get(
    "/{thing_id}",
    response_model=dict,
)
async def read_thing():
    pass
`,
      ],
    ]),
  );

  const errors = findDocumentedRouteErrorsFromTexts(
    inventory,
    new Map([
      [
        'README.md',
        [
          'Valid: GET /v1/things/123.',
          'Wrong method: POST /v1/things/456.',
          'Invalid: GET /v1/missing/123.',
        ].join('\n'),
      ],
    ]),
  );

  assert.equal(inventory.routes[0].path, '/v1/things/{thing_id}');
  assert.equal(errors.length, 2);
  assert.ok(errors.some((error) => /method POST/.test(error)));
  assert.ok(errors.some((error) => /\/v1\/missing\/123/.test(error)));
});

test('exact verification evidence is centralized unless a report is historical', () => {
  const historical =
    '# Old report\n\nStatus: historical checkout evidence.\n\n42 passed.\n';
  assert.equal(isHistoricalDocument(historical), true);

  const errors = findVerificationEvidenceErrors(
    new Map([
      ['README.md', 'The suite reported 42 passed.'],
      ['docs/old-report.md', historical],
      [
        'docs/verification.md',
        'Current baseline: 42 passed and e2e-123@example.test.',
      ],
    ]),
  );

  assert.equal(errors.length, 1);
  assert.match(errors[0], /README\.md/);
});

test('latest migration must be named by the Supabase current-state doc', () => {
  withFixture(
    {
      'supabase/migrations/20260101000000_first.sql': '-- first\n',
      'supabase/migrations/20260102000000_second.sql': '-- second\n',
    },
    (root) => {
      const staleDocuments = new Map([
        [
          'docs/supabase-current-state.md',
          [
            'Latest inventory: `20260102000000_second.sql`.',
            '`supabase db reset` must complete through:',
            '```text',
            '20260101000000_first.sql',
            '```',
          ].join('\n'),
        ],
      ]);
      assert.match(
        findLatestMigrationErrors(root, staleDocuments)[0],
        /current migration boundary/,
      );

      const currentDocuments = new Map([
        [
          'docs/supabase-current-state.md',
          '`supabase db reset` must complete through:\n\n```text\n20260102000000_second.sql\n```',
        ],
      ]);
      assert.deepEqual(
        findLatestMigrationErrors(root, currentDocuments),
        [],
      );
    },
  );
});

test('canonical versions must appear in every owning document', () => {
  const contracts = [
    {
      key: 'capture',
      version: 'daily-capture-v4',
      sources: [{ path: 'lib/capture.dart', symbol: 'captureVersion' }],
      owners: ['README.md', 'docs/capture.md'],
    },
  ];

  assert.deepEqual(
    findRequiredVersionErrors(
      contracts,
      new Map([
        ['README.md', 'daily-capture-v4'],
        ['docs/capture.md', 'daily-capture-v4'],
      ]),
    ),
    [],
  );
  assert.match(
    findRequiredVersionErrors(
      contracts,
      new Map([
        ['README.md', 'daily-capture-v3'],
        ['docs/capture.md', 'daily-capture-v4'],
      ]),
    )[0],
    /README\.md.*daily-capture-v4/,
  );
});

test('current-contract metadata has a strict deterministic schema', () => {
  const metadata = {
    schema_version: 2,
    scope: 'named_cross_runtime_versions_and_explicit_exceptions',
    contracts: [
      {
        coverage: 'shared_named',
        key: 'capture',
        version: 'daily-capture-v4',
        sources: [
          { path: 'lib/capture.dart', symbol: 'captureVersion' },
          {
            locator: 'CURRENT_CAPTURE = "{version}"',
            path: 'service/capture.py',
          },
        ],
        owners: ['README.md', 'docs/capture.md'],
      },
    ],
  };
  assert.deepEqual(validateCurrentContractsMetadata(metadata).errors, []);

  const invalid = structuredClone(metadata);
  invalid.contracts[0].owners = [
    'docs/capture.md',
    './README.md',
    './README.md',
  ];
  invalid.contracts[0].coverage = 'unknown';
  invalid.contracts[0].unexpected = true;
  const errors = validateCurrentContractsMetadata(invalid).errors;
  assert.ok(
    errors.some((error) =>
      /exactly coverage, key, version, sources, and owners/.test(error),
    ),
  );
  assert.ok(
    errors.some((error) => /normalized repository-relative/.test(error)),
  );
  assert.ok(errors.some((error) => /owners contains duplicates/.test(error)));
  assert.ok(errors.some((error) => /owners must be sorted/.test(error)));
  assert.ok(errors.some((error) => /coverage must be/.test(error)));
});

test('current-contract metadata references real sources and owners', () => {
  withFixture(
    {
      'docs/current-contracts.json': JSON.stringify({
        schema_version: 2,
        scope: 'named_cross_runtime_versions_and_explicit_exceptions',
        contracts: [
          {
            coverage: 'shared_named',
            key: 'capture',
            version: 'daily-capture-v4',
            sources: [
              { path: 'lib/capture.dart', symbol: 'captureVersion' },
            ],
            owners: ['README.md'],
          },
        ],
      }),
      'lib/capture.dart': "const captureVersion = 'daily-capture-v4';\n",
      'README.md': 'daily-capture-v4\n',
    },
    (root) => {
      assert.deepEqual(loadCurrentContractsMetadata(root).errors, []);
    },
  );
});

test('current-contract source selectors drive canonical version extraction', () => {
  withFixture(
    {
      'lib/capture.dart': "const captureVersion = 'daily-capture-v4';\n",
      'service/capture.py':
        'SUPPORTED = {"daily-capture-v2", "daily-capture-v3", "daily-capture-v4"}\n',
    },
    (root) => {
      const contracts = [
        {
          key: 'dailyCapture',
          version: 'daily-capture-v4',
          sources: [
            { path: 'lib/capture.dart', symbol: 'captureVersion' },
            {
              locator:
                '{"daily-capture-v2", "daily-capture-v3", "{version}"}',
              path: 'service/capture.py',
            },
          ],
          owners: [],
        },
      ];
      assert.deepEqual(extractCanonicalVersions(root, contracts), {
        errors: [],
        versions: { dailyCapture: 'daily-capture-v4' },
      });

      writeFileSync(
        join(root, 'lib/capture.dart'),
        "const captureVersion = 'daily-capture-v5';\n",
        'utf8',
      );
      assert.match(
        extractCanonicalVersions(root, contracts).errors[0],
        /declares 'daily-capture-v4'.*declares 'daily-capture-v5'/,
      );
    },
  );
});

test('every named version shared by Flutter and FastAPI is registered', () => {
  withFixture(
    {
      'apps/mobile/lib/shared.dart':
        "const String sharedContractVersion = 'shared-contract-v1';\n",
      'services/ai_service/app/shared.py':
        'SHARED_CONTRACT_VERSION = "shared-contract-v1"\n',
    },
    (root) => {
      assert.match(
        findCrossRuntimeContractCoverageErrors(root, [])[0],
        /shared named Flutter\/FastAPI contract 'shared-contract-v1' is not registered/,
      );

      const incomplete = [
        {
          coverage: 'shared_named',
          key: 'shared',
          version: 'shared-contract-v1',
          sources: [
            {
              path: 'apps/mobile/lib/shared.dart',
              symbol: 'sharedContractVersion',
            },
          ],
          owners: [],
        },
      ];
      assert.match(
        findCrossRuntimeContractCoverageErrors(root, incomplete)[0],
        /services\/ai_service\/app\/shared\.py:SHARED_CONTRACT_VERSION/,
      );

      incomplete[0].sources.push({
        path: 'services/ai_service/app/shared.py',
        symbol: 'SHARED_CONTRACT_VERSION',
      });
      incomplete[0].coverage = 'explicit';
      assert.match(
        findCrossRuntimeContractCoverageErrors(root, incomplete)[0],
        /must use coverage 'shared_named'/,
      );
      incomplete[0].coverage = 'shared_named';
      assert.deepEqual(
        findCrossRuntimeContractCoverageErrors(root, incomplete),
        [],
      );
    },
  );
});

test('changed product code requires its owning documentation in the same diff', () => {
  const captureCode =
    'apps/mobile/lib/features/quick_action/domain/quick_check_in.dart';
  const incomplete = findDocsImpactErrors([
    captureCode,
    'apps/mobile/README.md',
  ]);
  assert.equal(incomplete.length, 1);
  assert.match(incomplete[0], /docs\/daily-briefing-implementation-plan\.md/);

  assert.deepEqual(
    findDocsImpactErrors([
      captureCode,
      'apps/mobile/README.md',
      'docs/daily-briefing-implementation-plan.md',
    ]),
    [],
  );
});

test('a migration updates migration owners without churning AGENTS.md', () => {
  const migration = 'supabase/migrations/20260101000000_example.sql';
  assert.deepEqual(
    findDocsImpactErrors([
      migration,
      'docs/supabase-current-state.md',
      'docs/verification.md',
    ]),
    [],
  );

  const errors = findDocsImpactErrors([
    migration,
    'docs/supabase-current-state.md',
  ]);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /docs\/verification\.md/);
  assert.doesNotMatch(errors[0], /AGENTS\.md/);
});

test('local database safety changes require the complete operational owner set', () => {
  const source = 'scripts/lib/local_supabase_database_safety.sh';
  const owners = [
    'docs/architecture.md',
    'docs/local-database-safety.md',
    'docs/local-dev.md',
    'docs/supabase-current-state.md',
    'docs/verification.md',
  ];

  assert.deepEqual(findDocsImpactErrors([source, ...owners]), []);

  const errors = findDocsImpactErrors([
    source,
    ...owners.filter((path) => path !== 'docs/local-database-safety.md'),
  ]);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /docs\/local-database-safety\.md/);
});

test('known superseded current-state wording fails outside historical docs', () => {
  const errors = findStaleClaimErrors(
    new Map([
      ['README.md', 'Current Capture V3 is active.'],
      [
        'docs/old.md',
        '# Old\n\nStatus: historical checkout report.\n\nCurrent Capture V3.',
      ],
    ]),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Current Capture is V4/);
});

test('current docs cannot restore reset authority to verification or E2E', () => {
  const errors = findStaleClaimErrors(
    new Map([
      [
        'docs/current.md',
        [
          'RESET_DB=true npm run verify:db',
          'RESET_DB=true FLUTTER_BIN=/opt/flutter npm run e2e:web:full',
        ].join('\n'),
      ],
    ]),
  );

  assert.equal(errors.length, 2);
  assert.ok(
    errors.every((error) => /cannot delegate reset authority/.test(error)),
  );
});
