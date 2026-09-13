import http from 'node:http';
import https from 'node:https';

export const cloudApiOrigin = 'https://mylifegraph.duckdns.org';
export const localWebOrigin = 'http://127.0.0.1:7357';
const localWebOrigins = new Set([localWebOrigin, 'http://localhost:7357']);
const methods = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
const requestHeaders = ['authorization', 'content-type', 'accept',
  'x-mylifegraph-coach-provider', 'x-mylifegraph-coach-api-key'];
const responseHeaders = ['content-type', 'content-length', 'content-encoding',
  'retry-after', 'x-request-id'];

// Private laptop transport, not an authentication service. The upstream still
// verifies every bearer and enforces ownership, participation and Coach limits.
export function createLocalCloudApiProxy({ request = https.request, diagnostic = () => {} } = {}) {
  return http.createServer((req, res) => {
    // Diagnostics contain only fixed labels/status, never URLs, headers or bodies.
    const reject = (status) => {
      diagnostic(`Local API rejected request: HTTP ${status}`);
      res.writeHead(status); res.end();
    };
    const allowedOrigin = localWebOrigins.has(req.headers.origin);
    const host = `127.0.0.1:${req.socket.localPort}`;
    if (req.headers.host !== host ||
        (req.headers.origin && !allowedOrigin)) {
      reject(403); return;
    }
    if (!req.url?.startsWith('/v1/') || req.url.includes('#')) {
      reject(404); return;
    }
    const url = new URL(req.url, cloudApiOrigin);
    if (url.origin !== cloudApiOrigin || !url.pathname.startsWith('/v1/')) {
      reject(404); return;
    }
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Vary', 'Origin');
    if (allowedOrigin) {
      res.setHeader('Access-Control-Allow-Origin', req.headers.origin);
      res.setHeader('Access-Control-Expose-Headers', 'Retry-After, X-Request-Id');
    }
    if (req.method === 'OPTIONS') {
      const requestedHeaders = String(req.headers['access-control-request-headers'] || '')
        .toLowerCase().split(',').map((v) => v.trim()).filter(Boolean);
      if (!allowedOrigin ||
          !methods.has(req.headers['access-control-request-method']) ||
          requestedHeaders.some((v) => !requestHeaders.includes(v))) {
        reject(403); return;
      }
      res.setHeader('Access-Control-Allow-Methods', [...methods].join(', '));
      res.setHeader('Access-Control-Allow-Headers', requestHeaders.join(', '));
      res.writeHead(204); res.end(); return;
    }
    if (!methods.has(req.method)) { reject(405); return; }
    if (!/^Bearer \S+$/.test(req.headers.authorization || '')) {
      reject(401); return;
    }
    const headers = {};
    for (const name of requestHeaders) {
      if (req.headers[name] !== undefined) headers[name] = req.headers[name];
    }
    // Never forward browser cookies, Origin, Host or forwarding headers.
    const upstream = request(url, { method: req.method, headers }, (reply) => {
      if (reply.statusCode >= 400) {
        diagnostic(`Local API upstream rejected request: HTTP ${reply.statusCode}`);
      }
      for (const name of responseHeaders) {
        if (reply.headers[name] !== undefined) res.setHeader(name, reply.headers[name]);
      }
      res.writeHead(reply.statusCode || 502);
      reply.on('error', () => res.destroy());
      reply.pipe(res);
    });
    upstream.on('error', () => {
      if (!res.headersSent) reject(502); else res.destroy();
    });
    upstream.setTimeout(600_000, () => upstream.destroy());
    req.on('aborted', () => upstream.destroy());
    res.on('close', () => upstream.destroy());
    req.pipe(upstream);
  });
}
