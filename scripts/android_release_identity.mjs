#!/usr/bin/env node

const pattern =
  /^v(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)-pilot\.(?<pilot>0|[1-9]\d*)-rc\.(?<rc>0|[1-9]\d*)$/;

export function androidReleaseIdentity(tag) {
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
    build_number: String(buildNumber),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    if (process.argv.length !== 3) {
      throw new Error('usage: android_release_identity.mjs <pilot-rc-tag>');
    }
    const identity = androidReleaseIdentity(process.argv[2]);
    process.stdout.write(
      `build_name=${identity.build_name}\nbuild_number=${identity.build_number}\n`,
    );
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
