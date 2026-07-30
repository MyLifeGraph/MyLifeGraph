import { requireLoopbackSupabaseUrl } from './local-auth-users.mjs';

export class JsonHttpClient {
  constructor({ baseUrl, headers = {} }) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.headers = { ...headers };
  }

  withBearer(accessToken) {
    return new JsonHttpClient({
      baseUrl: this.baseUrl,
      headers: {
        ...this.headers,
        Authorization: `Bearer ${accessToken}`,
      },
    });
  }

  async request(path, { method = 'GET', body, headers = {} } = {}) {
    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        ...this.headers,
        ...headers,
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await response.text();
    let json = null;
    if (text.length > 0) {
      try {
        json = JSON.parse(text);
      } catch {
        // Binary or plain-text responses remain available through text.
      }
    }
    return {
      status: response.status,
      ok: response.ok,
      headers: response.headers,
      text,
      json,
    };
  }
}

export class LocalAuthAdminClient {
  constructor({
    supabaseUrl,
    anonKey,
    serviceRoleKey,
    fetchImpl = globalThis.fetch,
  }) {
    this.supabaseUrl = requireLoopbackSupabaseUrl(supabaseUrl);
    this.anonKey = anonKey;
    this.serviceRoleKey = serviceRoleKey;
    this.fetchImpl = fetchImpl;
  }

  async createConfirmedUser({ email, password, displayName }) {
    const response = await this.fetchImpl(
      `${this.supabaseUrl}/auth/v1/admin/users`,
      {
        method: 'POST',
        headers: this.#adminHeaders({ json: true }),
        body: JSON.stringify({
          email,
          password,
          email_confirm: true,
          user_metadata: { display_name: displayName },
        }),
      },
    );
    if (!response.ok) {
      throw new Error(
        `Could not create exact local E2E user: HTTP ${response.status} ${await response.text()}`,
      );
    }
    return response.json();
  }

  async signIn({ email, password }) {
    const response = await this.fetchImpl(
      `${this.supabaseUrl}/auth/v1/token?grant_type=password`,
      {
        method: 'POST',
        headers: {
          apikey: this.anonKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, password }),
      },
    );
    if (!response.ok) {
      throw new Error(
        `Could not sign in exact local E2E user: HTTP ${response.status} ${await response.text()}`,
      );
    }
    const payload = await response.json();
    if (
      typeof payload?.access_token !== 'string' ||
      payload.access_token.length === 0
    ) {
      throw new Error('Local E2E sign-in returned no access token.');
    }
    return payload.access_token;
  }

  async getUser(userId) {
    return this.fetchImpl(
      `${this.supabaseUrl}/auth/v1/admin/users/${userId}`,
      { headers: this.#adminHeaders() },
    );
  }

  #adminHeaders({ json = false } = {}) {
    return {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
      ...(json ? { 'Content-Type': 'application/json' } : {}),
    };
  }
}

export function assertHttpStatus(result, expected, context) {
  if (result.status !== expected) {
    throw new Error(
      `${context} returned HTTP ${result.status}: ${result.text}`,
    );
  }
  return result;
}
