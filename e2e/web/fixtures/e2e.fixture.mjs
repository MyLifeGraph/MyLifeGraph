import { createHash } from 'node:crypto';

import { test as base, expect } from 'playwright/test';

import {
  JsonHttpClient,
  LocalAuthAdminClient,
  assertHttpStatus,
} from '../support/api-client.mjs';
import { SupabaseDbClient } from '../support/db-client.mjs';
import { signInThroughFlutter } from '../support/flutter-ui.mjs';
import { createLocalAuthUserRegistry } from '../support/local-auth-users.mjs';

const requiredEnvironment = [
  'APP_URL',
  'AI_SERVICE_BASE_URL',
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'E2E_RUN_ID',
];
for (const name of requiredEnvironment) {
  if (!process.env[name]) {
    throw new Error(`${name} is required for Playwright E2E fixtures.`);
  }
}

const appUrl = process.env.APP_URL.replace(/\/$/, '');
const aiServiceBaseUrl = process.env.AI_SERVICE_BASE_URL.replace(/\/$/, '');
const supabaseUrl = process.env.SUPABASE_URL.replace(/\/$/, '');
const anonKey = process.env.SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const runId = process.env.E2E_RUN_ID;

export const test = base.extend({
  e2e: async ({ page }, use, testInfo) => {
    const registry = createLocalAuthUserRegistry({
      supabaseUrl,
      serviceRoleKey,
    });
    const admin = new LocalAuthAdminClient({
      supabaseUrl,
      anonKey,
      serviceRoleKey,
    });

    async function createIdentity(label) {
      const digest = createHash('sha256')
        .update(`${runId}:${testInfo.testId}:${label}`)
        .digest('hex');
      const identity = {
        email: `e2e-${digest.slice(0, 24)}@example.test`,
        password: `E2e-${digest.slice(0, 20)}-Pass!`,
      };
      const user = await admin.createConfirmedUser({
        ...identity,
        displayName: `E2E ${label}`,
      });
      registry.register(user.id);
      let accessToken;
      try {
        accessToken = await admin.signIn(identity);
      } catch (error) {
        await registry.cleanup();
        throw error;
      }
      const result = { ...identity, user, accessToken };
      return result;
    }

    const identity = await createIdentity('primary');
    const api = new JsonHttpClient({
      baseUrl: aiServiceBaseUrl,
    }).withBearer(identity.accessToken);
    const db = new SupabaseDbClient({
      supabaseUrl,
      anonKey,
      accessToken: identity.accessToken,
    });
    const serviceDb = new SupabaseDbClient({
      supabaseUrl,
      anonKey: serviceRoleKey,
      accessToken: serviceRoleKey,
    });
    let setupComplete = false;

    page.on('pageerror', (error) => {
      console.error(`[browser page error] ${error.message}`);
    });
    page.on('console', (message) => {
      if (['error', 'warning'].includes(message.type())) {
        console.error(`[browser ${message.type()}] ${message.text()}`);
      }
    });

    const fixture = {
      appUrl,
      aiServiceBaseUrl,
      supabaseUrl,
      anonKey,
      admin,
      identity,
      api,
      db,
      serviceDb,
      async createAdditionalIdentity(label) {
        const additional = await createIdentity(label);
        return {
          ...additional,
          api: new JsonHttpClient({
            baseUrl: aiServiceBaseUrl,
          }).withBearer(additional.accessToken),
          db: new SupabaseDbClient({
            supabaseUrl,
            anonKey,
            accessToken: additional.accessToken,
          }),
        };
      },
      async completeSetup() {
        if (setupComplete) return;
        const result = await api.request('/v1/intake/complete', {
          method: 'POST',
          body: {
            version: 'intake-v1',
            request_id: crypto.randomUUID(),
            base_revision: 0,
            responses: {
              display_name: 'Independent E2E',
              weekday_shape: 'School or work blocks',
              best_energy_window: 'morning',
              routines: [],
              fixed_commitments: [],
            },
            metadata: {
              client: 'playwright-independent-spec',
              source: 'onboarding',
            },
          },
        });
        assertHttpStatus(result, 200, 'independent Setup');
        if (
          result.json?.exists !== true ||
          result.json?.status !== 'applied' ||
          result.json?.revision !== 1
        ) {
          throw new Error(`Independent Setup was invalid: ${result.text}`);
        }
        setupComplete = true;
      },
      async signInUi({ expectedPath = '/dashboard' } = {}) {
        await signInThroughFlutter({
          page,
          appUrl,
          email: identity.email,
          password: identity.password,
          expectedPath,
        });
      },
    };

    let cleanupError = null;
    try {
      await use(fixture);
    } finally {
      const cleanupStartedAt = performance.now();
      try {
        const cleanup = await registry.cleanup();
        console.log(
          `[e2e:timing] ${JSON.stringify({
            phase: 'spec_auth_cleanup',
            test: testInfo.title,
            duration_ms: Math.round(performance.now() - cleanupStartedAt),
            registered_users: cleanup.registered,
            deleted_users: cleanup.deleted,
            already_absent_users: cleanup.alreadyAbsent,
            status: 'passed',
          })}`,
        );
      } catch (error) {
        cleanupError = error;
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[e2e cleanup error] ${message}`);
        await testInfo.attach('cleanup-error.txt', {
          body: Buffer.from(message),
          contentType: 'text/plain',
        });
      }
    }

    if (cleanupError !== null && testInfo.status === testInfo.expectedStatus) {
      throw cleanupError;
    }
  },
});

export { expect };
