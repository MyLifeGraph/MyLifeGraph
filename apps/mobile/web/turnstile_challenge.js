(() => {
  'use strict';

  const params = new URLSearchParams(window.location.search);
  const sitekey = params.get('sitekey') ?? '';
  const action = params.get('action') ?? '';
  const nonce = params.get('nonce') ?? '';
  const client = params.get('client') ?? '';
  const validActions = new Set([
    'signin',
    'signup',
    'password_reset',
    'signup_resend',
  ]);
  const status = document.getElementById('status');
  const cancel = document.getElementById('cancel');
  let completed = false;

  function validInput() {
    return /^[A-Za-z0-9_-]{20,128}$/.test(sitekey) &&
      validActions.has(action) &&
      /^[A-Za-z0-9_-]{32}$/.test(nonce) &&
      (client === 'web' || client === 'native');
  }

  function deliver(message) {
    if (completed) return;
    completed = true;
    const payload = JSON.stringify({
      kind: 'mylifegraph_turnstile',
      action,
      nonce,
      ...message,
    });
    if (client === 'native' && window.TurnstileToken?.postMessage) {
      window.TurnstileToken.postMessage(payload);
      return;
    }
    if (client === 'web' && window.opener && !window.opener.closed) {
      window.opener.postMessage(payload, window.location.origin);
      window.close();
    }
  }

  window.mylifegraphTurnstileReady = () => {
    if (!validInput() || !window.turnstile) {
      status.textContent = 'The security check is not configured correctly.';
      deliver({ error: 'invalid_configuration' });
      return;
    }
    status.textContent = 'Complete the check below.';
    window.turnstile.render('#turnstile-widget', {
      sitekey,
      action,
      callback(token) {
        status.textContent = 'Verification complete.';
        deliver({ token });
      },
      'expired-callback'() {
        status.textContent = 'The check expired. Complete it again.';
      },
      'timeout-callback'() {
        status.textContent = 'The check timed out. Complete it again.';
      },
      'error-callback'() {
        status.textContent = 'The security check failed. Try again.';
        return true;
      },
    });
  };

  cancel.addEventListener('click', () => deliver({ error: 'cancelled' }));
  if (!validInput()) {
    status.textContent = 'The security check is not configured correctly.';
  }
})();
