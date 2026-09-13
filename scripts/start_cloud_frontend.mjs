import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createLocalCloudApiProxy } from './local_cloud_api_proxy.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const releaseOrigin = 'https://my-life-graph-my-life-graph-s-projects.vercel.app';
const supabaseOrigin = 'https://oscrunlndfrecjilojja.supabase.co';
const environment = Object.fromEntries([
  'PATH', 'PATHEXT', 'SystemRoot', 'WINDIR', 'COMSPEC', 'TEMP', 'TMP',
  'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'HOMEDRIVE', 'HOMEPATH',
  'PROGRAMFILES', 'PROGRAMFILES(X86)', 'PROGRAMDATA',
].filter((name) => process.env[name] !== undefined).map((name) => [name, process.env[name]]));

// Only the already-public client key is read from the released app. Never read
// a credential store, copy a backend key, print the key or save it to disk.
const response = await fetch(`${releaseOrigin}/main.dart.js`, {
  signal: AbortSignal.timeout(30_000), redirect: 'error',
});
if (!response.ok) throw new Error('Could not read the public release configuration.');
const bundle = await response.text();
const keys = [...new Set(bundle.match(/sb_publishable_[A-Za-z0-9_-]+/g) || [])];
const projects = [...new Set(bundle.match(/https:\/\/[a-z0-9]+\.supabase\.co/g) || [])];
if (keys.length !== 1 || projects.length !== 1 || projects[0] !== supabaseOrigin) {
  throw new Error('Public release target changed; review before using real accounts.');
}
const proxy = createLocalCloudApiProxy({ diagnostic: (message) => console.warn(message) });
await new Promise((resolve, reject) => {
  proxy.once('error', reject);
  proxy.listen(8003, '127.0.0.1', resolve);
});
console.log('Cloud-account mode: REAL Pilot data. Local API transport: 127.0.0.1:8003 only.');
console.log('Use your existing Google account; the old development demo login does not apply.');
const child = spawn('C:/Program Files/Git/bin/bash.exe', [
  './scripts/start_frontend.sh',
], {
  // Keep Flutter's input open without a separate long-lived sleep process.
  cwd: root, stdio: ['pipe', 'inherit', 'inherit'],
  env: {
    ...environment,
    FLUTTER_BIN: '/c/flutter/bin/flutter',
    APP_ENV: 'development', USE_MOCK_DATA: 'false', COACH_SURFACE_ENABLED: 'true',
    HOST: '127.0.0.1', PORT: '7357',
    SUPABASE_URL: supabaseOrigin, SUPABASE_PUBLISHABLE_KEY: keys[0], SUPABASE_ANON_KEY: '',
    AI_SERVICE_BASE_URL: 'http://127.0.0.1:8003',
    SPEECH_SERVICE_BASE_URL: 'http://127.0.0.1:8003',
  },
});
child.on('error', () => { proxy.close(); process.exitCode = 1; });
child.on('exit', (code) => {
  proxy.closeAllConnections(); proxy.close(); process.exitCode = code ?? 1;
});
