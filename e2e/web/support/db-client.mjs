import { JsonHttpClient } from './api-client.mjs';

export class SupabaseDbClient {
  constructor({ supabaseUrl, anonKey, accessToken }) {
    this.client = new JsonHttpClient({
      baseUrl: `${supabaseUrl.replace(/\/$/, '')}/rest/v1`,
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${accessToken}`,
      },
    });
  }

  async select(path) {
    return this.client.request(`/${path}`, {
      headers: { Accept: 'application/json' },
    });
  }

  async mutate(path, { method, body, returnRepresentation = true }) {
    return this.client.request(`/${path}`, {
      method,
      body,
      headers: {
        Prefer: returnRepresentation
          ? 'return=representation'
          : 'return=minimal',
      },
    });
  }
}
