import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(
  new URL('../apps/mobile/web/turnstile_challenge.js', import.meta.url),
  'utf8',
);

function challenge(search) {
  const messages = [];
  const elements = new Map(
    ['status', 'turnstile-widget', 'cancel'].map((id) => [
      id,
      {
        id,
        textContent: '',
        listeners: {},
        addEventListener(name, handler) {
          this.listeners[name] = handler;
        },
      },
    ]),
  );
  const rendered = [];
  const window = {
    location: { search, origin: 'https://app.example.test' },
    TurnstileToken: { postMessage: (message) => messages.push(message) },
    turnstile: {
      render(selector, options) {
        rendered.push({ selector, options });
      },
    },
  };
  vm.runInNewContext(source, {
    window,
    document: { getElementById: (id) => elements.get(id) },
    URLSearchParams,
    JSON,
    Set,
  });
  return { elements, messages, rendered, window };
}

test('native Turnstile bridge binds action and nonce to one token', () => {
  const nonce = 'a'.repeat(32);
  const result = challenge(
    `?sitekey=1x00000000000000000000AA&action=signin&nonce=${nonce}&client=native`,
  );
  result.window.mylifegraphTurnstileReady();
  assert.equal(result.rendered.length, 1);
  assert.equal(result.rendered[0].selector, '#turnstile-widget');
  assert.equal(result.rendered[0].options.action, 'signin');
  result.rendered[0].options.callback('fresh-token');
  assert.deepEqual(JSON.parse(result.messages[0]), {
    kind: 'mylifegraph_turnstile',
    action: 'signin',
    nonce,
    token: 'fresh-token',
  });
  result.rendered[0].options.callback('second-token');
  assert.equal(result.messages.length, 1);
});

test('unknown actions fail closed before rendering', () => {
  const result = challenge(
    `?sitekey=1x00000000000000000000AA&action=admin&nonce=${'b'.repeat(32)}&client=native`,
  );
  result.window.mylifegraphTurnstileReady();
  assert.equal(result.rendered.length, 0);
  assert.equal(JSON.parse(result.messages[0]).error, 'invalid_configuration');
});
