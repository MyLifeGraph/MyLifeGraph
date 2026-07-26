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
  extractFastApiRoutesFromTexts,
  findDocsImpactErrors,
  findDocumentedRouteErrorsFromTexts,
  findLatestMigrationErrors,
  findMarkdownLinkErrors,
  findRequiredVersionErrors,
  findStaleClaimErrors,
  findVerificationEvidenceErrors,
  isHistoricalDocument,
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

test('latest migration must be named by required current docs', () => {
  withFixture(
    {
      'supabase/migrations/20260101000000_first.sql': '-- first\n',
      'supabase/migrations/20260102000000_second.sql': '-- second\n',
    },
    (root) => {
      const staleDocuments = new Map([
        [
          'AGENTS.md',
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
        findLatestMigrationErrors(root, staleDocuments, ['AGENTS.md'])[0],
        /current migration boundary/,
      );

      const currentDocuments = new Map([
        [
          'AGENTS.md',
          '`supabase db reset` must complete through:\n\n```text\n20260102000000_second.sql\n```',
        ],
      ]);
      assert.deepEqual(
        findLatestMigrationErrors(root, currentDocuments, ['AGENTS.md']),
        [],
      );
    },
  );
});

test('canonical versions must appear in every owning document', () => {
  const requirements = { capture: ['README.md', 'docs/capture.md'] };
  const versions = { capture: 'daily-capture-v4' };

  assert.deepEqual(
    findRequiredVersionErrors(
      versions,
      new Map([
        ['README.md', 'daily-capture-v4'],
        ['docs/capture.md', 'daily-capture-v4'],
      ]),
      requirements,
    ),
    [],
  );
  assert.match(
    findRequiredVersionErrors(
      versions,
      new Map([
        ['README.md', 'daily-capture-v3'],
        ['docs/capture.md', 'daily-capture-v4'],
      ]),
      requirements,
    )[0],
    /README\.md.*daily-capture-v4/,
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
