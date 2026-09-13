#!/usr/bin/env node

import { fileURLToPath } from 'node:url';

const pattern =
  /^v(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)-pilot\.(?<pilot>0|[1-9]\d*)-rc\.(?<rc>0|[1-9]\d*)$/;

// Both automatic main builds and tagged candidates share this sequence.
// Full first-parent history makes reruns stable and future main builds increase.
export function androidCiBuildNumber(count) {
  if (!/^[1-9]\d*$/.test(String(count))) {
    throw new Error('Expected a positive first-parent commit count.');
  }
  const result = 10_000_000 + Number(count);
  if (!Number.isSafeInteger(result) || result > 2_100_000_000) {
    throw new Error('Android CI versionCode is outside the supported range.');
  }
  return String(result);
}

export function androidMainIdentity(sha, count) {
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error('Expected a full commit SHA.');
  return {
    build_name: `main-${sha.slice(0, 12)}`,
    build_number: androidCiBuildNumber(count),
  };
}

export function androidReleaseIdentity(tag, count) {
  const match = pattern.exec(tag);
  if (!match?.groups) {
    throw new Error('Expected an exact pilot RC tag.');
  }
  const values = Object.fromEntries(
    Object.entries(match.groups).map(([key, value]) => [key, Number(value)]),
  );
  if (
    !Number.isSafeInteger(values.major) ||
    values.major > 20 ||
    [values.minor, values.patch, values.pilot, values.rc].some(
      (value) => !Number.isSafeInteger(value) || value > 99,
    )
  ) {
    throw new Error('Pilot RC tag components exceed Android version bounds.');
  }
  const buildNumber =
    values.major * 100_000_000 +
    values.minor * 1_000_000 +
    values.patch * 10_000 +
    values.pilot * 100 +
    values.rc;
  if (buildNumber < 1 || buildNumber > 2_100_000_000) {
    throw new Error('Derived Android versionCode is outside the supported range.');
  }
  return {
    build_name: tag.slice(1),
    build_number: count === undefined ? String(buildNumber) : androidCiBuildNumber(count),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (!(args.length === 1 || args.length === 2 ||
        (args.length === 3 && args[0] === '--main'))) {
      throw new Error('usage: android_release_identity.mjs <pilot-rc-tag> [commit-count] | --main <sha> <commit-count>');
    }
    const identity = args[0] === '--main'
      ? androidMainIdentity(args[1], args[2])
      : androidReleaseIdentity(args[0], args[1]);
    process.stdout.write(
      `build_name=${identity.build_name}\nbuild_number=${identity.build_number}\n`,
    );
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
