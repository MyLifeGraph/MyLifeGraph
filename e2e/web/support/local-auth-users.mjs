const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1']);

export function requireLoopbackSupabaseUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error('E2E Supabase URL must be a valid loopback URL.');
  }

  if (
    url.protocol !== 'http:' ||
    !LOOPBACK_HOSTS.has(url.hostname) ||
    url.username !== '' ||
    url.password !== ''
  ) {
    throw new Error(
      'E2E Auth user management is allowed only for an unauthenticated HTTP loopback Supabase URL.',
    );
  }

  return url.toString().replace(/\/$/, '');
}

export function createLocalAuthUserRegistry({
  supabaseUrl,
  serviceRoleKey,
  fetchImpl = globalThis.fetch,
}) {
  const localSupabaseUrl = requireLoopbackSupabaseUrl(supabaseUrl);
  const userIds = new Set();

  function register(userId) {
    if (
      typeof userId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        userId,
      )
    ) {
      throw new Error('E2E Auth registry received an invalid user UUID.');
    }
    userIds.add(userId);
    return userId;
  }

  async function cleanup() {
    const failures = [];
    let deleted = 0;
    let alreadyAbsent = 0;

    for (const userId of userIds) {
      try {
        const focusCleanup = await fetchImpl(
          `${localSupabaseUrl}/rest/v1/focus_sessions?user_id=eq.${userId}`,
          {
            method: 'DELETE',
            headers: {
              apikey: serviceRoleKey,
              Authorization: `Bearer ${serviceRoleKey}`,
              Prefer: 'return=minimal',
            },
          },
        );
        if (!focusCleanup.ok) {
          failures.push(
            `${userId}: exact focus-history cleanup returned HTTP ${focusCleanup.status}`,
          );
          continue;
        }

        const response = await fetchImpl(
          `${localSupabaseUrl}/auth/v1/admin/users/${userId}`,
          {
            method: 'DELETE',
            headers: {
              apikey: serviceRoleKey,
              Authorization: `Bearer ${serviceRoleKey}`,
            },
          },
        );
        if (response.ok) {
          deleted += 1;
        } else if (response.status === 404) {
          alreadyAbsent += 1;
        } else {
          failures.push(
            `${userId}: admin delete returned HTTP ${response.status}`,
          );
          continue;
        }

        const readBack = await fetchImpl(
          `${localSupabaseUrl}/auth/v1/admin/users/${userId}`,
          {
            headers: {
              apikey: serviceRoleKey,
              Authorization: `Bearer ${serviceRoleKey}`,
            },
          },
        );
        if (readBack.status !== 404) {
          failures.push(
            `${userId}: user remained readable after cleanup (HTTP ${readBack.status})`,
          );
        }
      } catch (error) {
        failures.push(
          `${userId}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    if (failures.length > 0) {
      throw new Error(
        `E2E Auth cleanup failed for ${failures.length} registered user(s): ${failures.join('; ')}`,
      );
    }

    return {
      registered: userIds.size,
      deleted,
      alreadyAbsent,
    };
  }

  return {
    register,
    cleanup,
    get size() {
      return userIds.size;
    },
  };
}
