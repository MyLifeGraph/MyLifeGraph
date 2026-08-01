#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(
  fileURLToPath(new URL('..', import.meta.url)),
);

const scannedRoots = [
  'apps/mobile/lib/core/widgets',
  'apps/mobile/lib/features',
];

const colorAllowlist = new Map([
  [
    'apps/mobile/lib/features/auth/presentation/pages/auth_page.dart',
    'Google sign-in logo brand colors',
  ],
  [
    'apps/mobile/lib/features/insights/presentation/pages/insights_page.dart',
    'bounded data-visualization series palette',
  ],
]);

const textStyleAllowlist = new Map([
  [
    'apps/mobile/lib/features/insights/presentation/pages/insights_page.dart',
    'canvas chart labels, derived from themed colors and font sizes',
  ],
]);

function filesBelow(root, relativeRoot) {
  const absolute = join(root, relativeRoot);
  if (!existsSync(absolute)) return [];
  const files = [];
  for (const entry of readdirSync(absolute)) {
    const candidate = join(absolute, entry);
    const info = statSync(candidate);
    if (info.isDirectory()) {
      files.push(...filesBelow(root, relative(root, candidate)));
    } else if (extname(candidate) === '.dart') {
      files.push(relative(root, candidate));
    }
  }
  return files;
}

export function findVisualContractErrors(root = repositoryRoot) {
  const errors = [];
  const productionFiles = filesBelow(root, 'apps/mobile/lib');
  const files = scannedRoots.flatMap((path) => filesBelow(root, path));
  const backdropFilterUses = [];
  const imageBlurUses = [];
  const bannedPatterns = [
    [/\bIcons\./, 'Material Icons; use AppIcons/Phosphor'],
    [
      /\b(?:Linear|Radial|Sweep)Gradient\b|\b(?:FragmentShader|ShaderMask)\b|\bShimmer\b/,
      'gradients, shimmer, or shader decoration',
    ],
    [/\bsaveLayer\s*\(/, 'canvas saveLayer'],
    [
      /BorderRadius\.circular\(\s*\d/,
      'raw radius; use AppRadii tokens',
    ],
    [
      /Colors\.(?:red|blue|green|orange|yellow|purple|teal|cyan|indigo|amber|deepOrange)\b/,
      'uncontrolled named color; use AppVisualTokens',
    ],
    [/\bfontFamily\s*:/, 'route-local font family'],
  ];

  for (const file of files) {
    const text = readFileSync(join(root, file), 'utf8');
    for (const [pattern, label] of bannedPatterns) {
      if (pattern.test(text)) {
        errors.push(`${file}: contains ${label}`);
      }
    }
    if (/Color\(0x[0-9A-Fa-f]+\)/.test(text) && !colorAllowlist.has(file)) {
      errors.push(`${file}: contains a hard color outside the visual allowlist`);
    }
    if (/\bTextStyle\(/.test(text) && !textStyleAllowlist.has(file)) {
      errors.push(`${file}: contains a route-local TextStyle`);
    }
  }

  for (const file of productionFiles) {
    const text = readFileSync(join(root, file), 'utf8');
    for (const _match of text.matchAll(/\bBackdropFilter\s*\(/g)) {
      backdropFilterUses.push(file);
    }
    for (const _match of text.matchAll(/\bImageFilter\.blur\s*\(/g)) {
      imageBlurUses.push(file);
    }
  }

  const navigationBlurOwner =
    'apps/mobile/lib/features/shell/presentation/main_shell.dart';
  if (
    backdropFilterUses.length !== 1 ||
    backdropFilterUses[0] !== navigationBlurOwner
  ) {
    errors.push(
      `${navigationBlurOwner}: must own the only production BackdropFilter; found ${backdropFilterUses.length} across ${[...new Set(backdropFilterUses)].join(', ') || 'no files'}`,
    );
  }
  if (imageBlurUses.length !== 1 || imageBlurUses[0] !== navigationBlurOwner) {
    errors.push(
      `${navigationBlurOwner}: must own the only production ImageFilter.blur; found ${imageBlurUses.length} across ${[...new Set(imageBlurUses)].join(', ') || 'no files'}`,
    );
  }

  const appSurfacePath = 'apps/mobile/lib/core/widgets/app_surface.dart';
  if (!existsSync(join(root, appSurfacePath))) {
    errors.push(`${appSurfacePath}: shared surface source is missing`);
  } else {
    const appSurface = readFileSync(join(root, appSurfacePath), 'utf8');
    if (!appSurface.includes('_AppSurfaceHudPainter')) {
      errors.push(`${appSurfacePath}: missing the token-owned Space HUD frame`);
    }
  }

  const appThemePath = 'apps/mobile/lib/core/theme/app_theme.dart';
  if (!existsSync(join(root, appThemePath))) {
    errors.push(`${appThemePath}: theme source is missing`);
  } else {
    const appTheme = readFileSync(join(root, appThemePath), 'utf8');
    if (!/navigationBlurSigma:\s*8\b/.test(appTheme)) {
      errors.push(`${appThemePath}: Space navigation blur must remain sigma 8`);
    }
    if (
      !appTheme.includes(
        'surfaceMaterialOverride: AppSurfaceMaterial.disabled',
      )
    ) {
      errors.push(
        `${appThemePath}: high contrast must disable clear Space materials`,
      );
    }
  }

  const pubspecPath = join(root, 'apps/mobile/pubspec.yaml');
  const pubspec = readFileSync(pubspecPath, 'utf8');
  for (const dependency of [
    'flutter_svg: 2.1.0',
    'phosphor_flutter: 2.1.0',
  ]) {
    if (!pubspec.includes(dependency)) {
      errors.push(`apps/mobile/pubspec.yaml: missing exact ${dependency}`);
    }
  }
  for (const weight of [400, 500, 600, 700]) {
    if (!pubspec.includes(`weight: ${weight}`)) {
      errors.push(`apps/mobile/pubspec.yaml: missing Instrument Sans ${weight}`);
    }
  }
  if (!pubspec.includes('- assets/theme/')) {
    errors.push('apps/mobile/pubspec.yaml: missing local theme assets');
  }

  const spaceBackdropAssets = [
    'apps/mobile/assets/theme/space-deep-field-landscape.webp',
    'apps/mobile/assets/theme/space-deep-field-portrait.webp',
  ];
  const requiredAssets = [
    'apps/mobile/assets/brand/app_brand_mark.svg',
    ...spaceBackdropAssets,
    'apps/mobile/assets/fonts/InstrumentSans-Regular.ttf',
    'apps/mobile/assets/fonts/InstrumentSans-Medium.ttf',
    'apps/mobile/assets/fonts/InstrumentSans-SemiBold.ttf',
    'apps/mobile/assets/fonts/InstrumentSans-Bold.ttf',
    'apps/mobile/assets/fonts/OFL.txt',
    'apps/mobile/web/favicon.png',
    'apps/mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  ];
  for (const asset of requiredAssets) {
    if (!existsSync(join(root, asset))) {
      errors.push(`${asset}: required visual-system asset is missing`);
    }
  }
  if (spaceBackdropAssets.every((asset) => existsSync(join(root, asset)))) {
    const totalBackdropBytes = spaceBackdropAssets.reduce(
      (total, asset) => total + statSync(join(root, asset)).size,
      0,
    );
    if (totalBackdropBytes > 2 * 1024 * 1024) {
      errors.push(
        'Space backdrop assets: combined size exceeds the two-megabyte budget',
      );
    }
  }

  const manifest = readFileSync(
    join(root, 'apps/mobile/web/manifest.json'),
    'utf8',
  );
  if (manifest.includes('#0175C2') || !manifest.includes('#08110F')) {
    errors.push('apps/mobile/web/manifest.json: brand colors are not current');
  }

  return errors;
}

function main() {
  const errors = findVisualContractErrors();
  if (errors.length > 0) {
    console.error('Frontend visual contract failed:');
    for (const error of errors) console.error(`- ${error}`);
    process.exitCode = 1;
    return;
  }

  console.log(
    `Frontend visual contract passed (${colorAllowlist.size} color allowlist entries, ${textStyleAllowlist.size} TextStyle allowlist entry).`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
