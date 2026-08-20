#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

function requireText(source, value, label) {
  if (!source.includes(value)) {
    throw new Error(`${label} is missing ${value}.`);
  }
}

function requireImmutableActionPins(source, label) {
  const actionRefs = [...source.matchAll(/^\s*(?:-\s*)?uses:\s*([^\s#]+)/gm)].map(
    (match) => match[1],
  );
  if (actionRefs.length === 0) {
    throw new Error(`${label} has no third-party Actions.`);
  }
  for (const actionRef of actionRefs) {
    if (!/@[0-9a-f]{40}$/.test(actionRef)) {
      throw new Error(`${label} has a mutable Action ref: ${actionRef}.`);
    }
  }
}

export function checkAndroidReleaseConfig() {
  const ignore = read('.gitignore');
  const gradle = read('apps/mobile/android/app/build.gradle.kts');
  const mainManifest = read(
    'apps/mobile/android/app/src/main/AndroidManifest.xml',
  );
  const releaseManifest = read(
    'apps/mobile/android/app/src/release/AndroidManifest.xml',
  );
  const backupRules = read(
    'apps/mobile/android/app/src/main/res/xml/backup_rules.xml',
  );
  const extractionRules = read(
    'apps/mobile/android/app/src/main/res/xml/data_extraction_rules.xml',
  );
  const workflow = read('.github/workflows/pilot-release-apk.yml');
  const stagingWorkflow = read('.github/workflows/staging-debug-apk.yml');
  const captchaPlatform = read(
    'apps/mobile/lib/features/auth/presentation/captcha/auth_captcha_platform_native.dart',
  );
  const mobilePubspec = read('apps/mobile/pubspec.yaml');

  for (const value of [
    'apps/mobile/android/key.properties',
    'apps/mobile/android/*.jks',
    'apps/mobile/android/*.keystore',
  ]) {
    requireText(ignore, value, '.gitignore');
  }
  requireText(
    releaseManifest,
    'android:usesCleartextTraffic="false"',
    'manifest',
  );
  requireText(mainManifest, 'android:allowBackup="false"', 'main manifest');
  requireText(
    mainManifest,
    'android:fullBackupContent="@xml/backup_rules"',
    'main manifest',
  );
  requireText(
    mainManifest,
    'android:dataExtractionRules="@xml/data_extraction_rules"',
    'main manifest',
  );
  for (const domain of [
    'root',
    'file',
    'database',
    'sharedpref',
    'external',
    'device_root',
    'device_file',
    'device_database',
    'device_sharedpref',
  ]) {
    requireText(backupRules, `domain="${domain}" path="."`, 'backup rules');
    if (
      extractionRules.split(`domain="${domain}" path="."`).length - 1 !==
      2
    ) {
      throw new Error(
        `data extraction rules must exclude ${domain} from cloud and device transfer.`,
      );
    }
  }
  requireText(gradle, 'Release signing is not configured', 'Gradle guard');
  requireText(gradle, 'ANDROID_KEYSTORE_PATH', 'Gradle environment signing');
  requireText(workflow, 'tags:', 'release workflow');
  requireText(workflow, "'v*-pilot.*-rc.*'", 'release workflow');
  requireText(workflow, 'apksigner verify', 'release workflow');
  requireText(workflow, 'ANDROID_SIGNING_CERT_SHA256', 'release workflow');
  requireText(workflow, 'flutter pub get --enforce-lockfile', 'release workflow');
  requireText(workflow, 'git diff --exit-code -- pubspec.yaml pubspec.lock', 'release workflow');
  requireText(workflow, 'npm run verify:android-release', 'release workflow');
  requireText(workflow, 'flutter analyze', 'release workflow');
  requireText(workflow, 'test/app_config_environment_test.dart', 'release workflow');
  requireText(workflow, 'test/auth_recovery_test.dart', 'release workflow');
  requireText(workflow, 'test/coach_credentials_test.dart', 'release workflow');
  requireText(workflow, '"${#signer_digests[@]}" -eq 1', 'release workflow');
  requireText(workflow, 'v1.50.0/syft_1.50.0_linux_amd64.tar.gz', 'SBOM pin');
  requireText(
    workflow,
    'bf7b29ff57f06da30918266a0e1c2885a8f99784798d1bdb1628886aa015d788',
    'SBOM checksum',
  );
  requireText(workflow, 'cyclonedx-json=', 'CycloneDX SBOM');
  requireText(workflow, 'source_sbom_sha256', 'SBOM artifact identity');
  requireImmutableActionPins(workflow, 'release workflow');
  requireImmutableActionPins(stagingWorkflow, 'staging APK workflow');
  requireText(
    mobilePubspec,
    'webview_flutter_android: 4.14.0',
    'Turnstile Android dependency',
  );
  requireText(
    captchaPlatform,
    'setAcceptThirdPartyCookies(',
    'Turnstile Android WebView',
  );
  requireText(
    captchaPlatform,
    'AndroidWebViewController',
    'Turnstile Android WebView',
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    checkAndroidReleaseConfig();
    console.log('Android release configuration is fail-closed and secret-free.');
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
