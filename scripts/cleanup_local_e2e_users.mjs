import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

import {
  createLocalAuthUserRegistry,
  requireLoopbackSupabaseUrl,
} from '../e2e/web/support/local-auth-users.mjs';

const E2E_EMAIL =
  /^e2e-[A-Za-z0-9][A-Za-z0-9._-]{0,57}@example\.test$/;

export function selectLegacyE2eUsers(users) {
  return users
    .filter(
      (user) =>
        typeof user?.id === 'string' &&
        typeof user?.email === 'string' &&
        E2E_EMAIL.test(user.email),
    )
    .map(({ id, email }) => ({ id, email }))
    .sort(
      (left, right) =>
        left.email.localeCompare(right.email) || left.id.localeCompare(right.id),
    );
}

export function e2eUserSelectionFingerprint(users) {
  const digest = createHash('sha256')
    .update(users.map(({ id, email }) => `${id}:${email}`).join('\n'))
    .digest('hex');
  return `e2e-users-${users.length}-${digest.slice(0, 16)}`;
}

export async function listLocalAuthUsers({
  supabaseUrl,
  serviceRoleKey,
  fetchImpl = globalThis.fetch,
}) {
  const localSupabaseUrl = requireLoopbackSupabaseUrl(supabaseUrl);
  const users = [];
  const perPage = 1000;

  for (let page = 1; page <= 100; page += 1) {
    const response = await fetchImpl(
      `${localSupabaseUrl}/auth/v1/admin/users?page=${page}&per_page=${perPage}`,
      {
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      },
    );
    if (!response.ok) {
      throw new Error(
        `Local Auth user listing returned HTTP ${response.status}.`,
      );
    }
    const payload = await response.json();
    if (!Array.isArray(payload?.users)) {
      throw new Error('Local Auth user listing returned an invalid payload.');
    }
    users.push(...payload.users);
    if (payload.users.length < perPage) {
      return users;
    }
  }

  throw new Error('Local Auth user listing exceeded the 100-page safety cap.');
}

function parseArguments(argv) {
  if (argv.length === 0) {
    return { confirmation: null };
  }
  if (argv.length === 2 && argv[0] === '--confirm') {
    return { confirmation: argv[1] };
  }
  throw new Error('Usage: npm run e2e:cleanup:local -- [--confirm <fingerprint>]');
}

async function main() {
  const { confirmation } = parseArguments(process.argv.slice(2));
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.',
    );
  }

  const selected = selectLegacyE2eUsers(
    await listLocalAuthUsers({ supabaseUrl, serviceRoleKey }),
  );
  const fingerprint = e2eUserSelectionFingerprint(selected);

  console.log(`Found ${selected.length} exact local E2E Auth user(s):`);
  for (const user of selected) {
    console.log(`  ${user.email} (${user.id})`);
  }
  console.log(`Selection fingerprint: ${fingerprint}`);

  if (confirmation === null) {
    if (selected.length > 0) {
      console.log(
        `Preview only. To delete exactly this still-current selection, rerun with --confirm ${fingerprint}`,
      );
    }
    return;
  }
  if (confirmation !== fingerprint) {
    throw new Error(
      'Confirmation fingerprint does not match the current exact user selection; rerun the preview.',
    );
  }
  if (selected.length === 0) {
    console.log('No matching local E2E users require cleanup.');
    return;
  }

  const registry = createLocalAuthUserRegistry({
    supabaseUrl,
    serviceRoleKey,
  });
  for (const user of selected) {
    registry.register(user.id);
  }
  const result = await registry.cleanup();
  console.log(
    `Deleted ${result.deleted} exact local E2E Auth user(s); ${result.alreadyAbsent} were already absent.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
