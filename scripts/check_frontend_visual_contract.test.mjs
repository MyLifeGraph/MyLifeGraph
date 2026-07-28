import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import { findVisualContractErrors } from './check_frontend_visual_contract.mjs';

function writeFixture(root, path, contents = 'fixture') {
  const target = join(root, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
}

test('visual guard rejects uncontrolled route styling', () => {
  const root = mkdtempSync(join(tmpdir(), 'mylifegraph-visual-'));
  try {
    writeFixture(
      root,
      'apps/mobile/lib/features/example/presentation/example.dart',
      'final x = Icons.star; final c = Color(0xFF123456);',
    );
    writeFixture(
      root,
      'apps/mobile/pubspec.yaml',
      [
        'flutter_svg: 2.1.0',
        'phosphor_flutter: 2.1.0',
        ...[400, 500, 600, 700].map((weight) => `weight: ${weight}`),
      ].join('\n'),
    );
    for (const asset of [
      'apps/mobile/assets/brand/app_brand_mark.svg',
      'apps/mobile/assets/fonts/InstrumentSans-Regular.ttf',
      'apps/mobile/assets/fonts/InstrumentSans-Medium.ttf',
      'apps/mobile/assets/fonts/InstrumentSans-SemiBold.ttf',
      'apps/mobile/assets/fonts/InstrumentSans-Bold.ttf',
      'apps/mobile/assets/fonts/OFL.txt',
      'apps/mobile/web/favicon.png',
      'apps/mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ]) {
      writeFixture(root, asset);
    }
    writeFixture(
      root,
      'apps/mobile/web/manifest.json',
      '{"background_color":"#08110F"}',
    );

    const errors = findVisualContractErrors(root);
    assert.ok(errors.some((error) => error.includes('Material Icons')));
    assert.ok(errors.some((error) => error.includes('hard color')));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
