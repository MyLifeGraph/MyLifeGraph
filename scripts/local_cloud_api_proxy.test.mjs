import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { createLocalCloudApiProxy, cloudApiOrigin, localWebOrigin } from './local_cloud_api_proxy.mjs';

test('private proxy enforces host, origin, route and bearer without replacing upstream auth', async (t) => {
  const received = [];
  const upstream = http.createServer((req, res) => {
    received.push({ url: req.url, headers: req.headers });
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Retry-After', '7');
    res.setHeader('Set-Cookie', 'not-forwarded=yes');
    res.writeHead(401);
    res.end('{"detail":"Invalid bearer"}');
  });
  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  const proxy = createLocalCloudApiProxy({
    request(url, options, callback) {
      assert.equal(url.origin, cloudApiOrigin);
      return http.request(`http://127.0.0.1:${upstream.address().port}${url.pathname}${url.search}`,
        options, callback);
    },
  });
  await new Promise((resolve) => proxy.listen(0, '127.0.0.1', resolve));
  t.after(() => { proxy.closeAllConnections(); proxy.close(); upstream.closeAllConnections(); upstream.close(); });
  const origin = `http://127.0.0.1:${proxy.address().port}`;
  const fetchLocal = (path, options) => fetch(`${origin}${path}`, options);

  for (const [path, headers, expected] of [
    ['/v1/coach/history', { Origin: 'https://untrusted.example' }, 403],
    ['/v1/coach/history', { Origin: 'http://localhost:7358' }, 403],
    ['/v1/coach/history', { Origin: 'http://localhost.attacker.example:7357' }, 403],
    ['//untrusted.example/v1/coach/history', {}, 404],
    ['/v1/../admin', {}, 404],
    ['/auth/v1/token', {}, 404],
    ['/v1/coach/history', { Origin: localWebOrigin }, 401],
  ]) {
    assert.equal((await fetchLocal(path, { headers })).status, expected);
  }
  assert.equal(received.length, 0);
  const invalidHostStatus = await new Promise((resolve, reject) => {
    const request = http.get(`${origin}/v1/coach/history`, {
      headers: { Host: 'untrusted.example' },
    }, (reply) => { reply.resume(); resolve(reply.statusCode); });
    request.on('error', reject);
  });
  assert.equal(invalidHostStatus, 403);
  const preflight = await fetchLocal('/v1/coach/capabilities', { method: 'OPTIONS', headers: {
    Origin: localWebOrigin, 'Access-Control-Request-Method': 'GET',
    'Access-Control-Request-Headers': 'authorization,x-mylifegraph-coach-provider',
  } });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), localWebOrigin);
  assert.equal(received.length, 0);
  const forbiddenPreflight = await fetchLocal('/v1/coach/capabilities', { method: 'OPTIONS', headers: {
    Origin: localWebOrigin, 'Access-Control-Request-Method': 'GET',
    'Access-Control-Request-Headers': 'x-unapproved-header',
  } });
  assert.equal(forbiddenPreflight.status, 403);

  const reply = await fetchLocal('/v1/coach/capabilities', { headers: {
    Origin: localWebOrigin, Authorization: 'Bearer deliberately-invalid-test-token',
    Cookie: 'must-not-forward=yes', 'X-Forwarded-For': 'untrusted',
    'X-MyLifeGraph-Coach-Provider': 'gemini',
    'X-MyLifeGraph-Coach-Model': 'gemini-3.6-flash',
  } });
  assert.equal(reply.status, 401);
  assert.equal(reply.headers.get('Retry-After'), '7');
  assert.equal(reply.headers.get('Set-Cookie'), null);
  assert.equal(reply.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(await reply.json(), { detail: 'Invalid bearer' });
  assert.equal(received.length, 1);
  assert.equal(received[0].headers.authorization, 'Bearer deliberately-invalid-test-token');
  assert.equal(received[0].headers['x-mylifegraph-coach-provider'], 'gemini');
  assert.equal(received[0].headers['x-mylifegraph-coach-model'], 'gemini-3.6-flash');
  assert.equal(received[0].headers.origin, undefined);
  assert.equal(received[0].headers.cookie, undefined);
  assert.equal(received[0].headers['x-forwarded-for'], undefined);
  const localhostPreflight = await fetchLocal('/v1/account/deletion', {
    method: 'OPTIONS', headers: {
      Origin: 'http://localhost:7357',
      'Access-Control-Request-Method': 'GET',
      'Access-Control-Request-Headers': 'authorization',
    },
  });
  assert.equal(localhostPreflight.status, 204);
  assert.equal(localhostPreflight.headers.get('Access-Control-Allow-Origin'), 'http://localhost:7357');
  const localhostReply = await fetchLocal('/v1/account/deletion', { headers: {
    Origin: 'http://localhost:7357', Authorization: 'Bearer deliberately-invalid-test-token',
  } });
  assert.equal(localhostReply.status, 401); // Upstream auth remains authoritative.
  assert.equal(localhostReply.headers.get('Access-Control-Allow-Origin'), 'http://localhost:7357');
  assert.equal(received.length, 2);
});
