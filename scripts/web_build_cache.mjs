#!/usr/bin/env node
// Only the credential-free verification bundle is reusable. Never used for releases.
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const buildArgs = ['build', 'web', '--debug', '--no-wasm-dry-run', '--no-pub'];
const schema = 'verification-web-cache-v1';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const digest = value => createHash('sha256').update(value).digest('hex');

export function cleanEnvironment(env) {
  // No .env, API keys, signing configuration, Dart defines or inherited compiler flags.
  const allowed = new Set(['PATH', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT',
    'HOME', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'TMP', 'TEMP', 'TMPDIR',
    'PUB_CACHE', 'FLUTTER_ROOT']);
  return { ...Object.fromEntries(Object.entries(env).filter(([k]) => allowed.has(k.toUpperCase()))),
    CI: 'true', LANG: 'C.UTF-8', TZ: 'UTC', FLUTTER_SUPPRESS_ANALYTICS: 'true' };
}

export function filesUnder(directory, prefix = '') {
  return readdirSync(directory).sort().flatMap(name => {
    const path = join(directory, name), rel = prefix + name, stat = lstatSync(path);
    if (stat.isSymbolicLink() || (!stat.isFile() && !stat.isDirectory())) {
      throw new Error('Cache/source links and special files are not supported.');
    }
    return stat.isDirectory() ? filesUnder(path, rel + '/') : [rel];
  });
}

export function manifest(directory) {
  if (lstatSync(directory).isSymbolicLink()) throw new Error('Cache root cannot be a link.');
  return Object.fromEntries(filesUnder(directory).map(name => [name, digest(readFileSync(join(directory, name)))]));
}

export function identity({ commit, sources, toolchain, platform, arch, image, args = buildArgs }) {
  return { schema, commit, sources, toolchain, platform, arch, image, args };
}
export const cacheKey = value => digest(JSON.stringify(value));

export function validEntry(entry, expected) {
  try {
    if (lstatSync(entry).isSymbolicLink()) return false;
    const metaPath = join(entry, 'manifest.json');
    if (lstatSync(metaPath).isSymbolicLink()) return false;
    const meta = JSON.parse(readFileSync(metaPath, 'utf8'));
    if (JSON.stringify(meta.identity) !== JSON.stringify(expected)) return false;
    const actual = manifest(join(entry, 'web'));
    return ['index.html', 'flutter_bootstrap.js', 'main.dart.js'].every(k => actual[k]) &&
      JSON.stringify(actual) === JSON.stringify(meta.files);
  } catch { return false; }
}

function git(...args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }).trimEnd();
}
function flutter(args, cwd, env, capture = false) {
  const binary = process.env.FLUTTER_BIN || 'flutter';
  // Windows batch launcher requires cmd; arguments here are fixed, never secret/user values.
  if (/["\r\n&|<>^%!]/.test(binary)) throw new Error('Unsafe Flutter executable path.');
  const result = process.platform === 'win32'
    ? spawnSync(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', `""${binary}" --no-version-check ${args.join(' ')}"`],
      { cwd, env, windowsVerbatimArguments: true, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit', maxBuffer: 16 * 1024 * 1024 })
    : spawnSync(binary, ['--no-version-check', ...args],
      { cwd, env, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit', maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`Flutter ${args[0]} failed; no cached success recorded.`);
  return result.stdout;
}

function sourceSnapshot() {
  // All tracked/non-ignored app and build-tool inputs. Deletions are hashed too.
  const paths = [...new Set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard',
    '--', 'apps/mobile', 'scripts', '.github', 'package.json', 'package-lock.json', '.gitattributes')
    .split('\0').filter(Boolean))].sort();
  const records = paths.map(name => {
    if (name.split('/').some(part => part === '..') || /(?:^|\/)(?:\.env(?:\..*)?|key\.properties|google-services\.json)$|\.(?:jks|keystore|p12|pfx)$/i.test(name)) {
      throw new Error('Private configuration must not be a tracked build input.');
    }
    const path = join(root, name);
    if (!existsSync(path)) return [name, null];
    if (!lstatSync(path).isFile() || lstatSync(path).isSymbolicLink()) throw new Error('Only ordinary build inputs are supported.');
    return [name, digest(readFileSync(path))];
  });
  return { records, hash: digest(JSON.stringify(records)) };
}

export function run(argv = process.argv.slice(2)) {
  if (argv.some(a => !['--key', '--no-cache'].includes(a))) throw new Error('Use --key or --no-cache only.');
  const started = performance.now();
  const disabled = argv.includes('--no-cache') || process.env.CI_NO_CACHE === 'true';
  const env = cleanEnvironment(process.env);
  const runtime = JSON.parse(flutter(['--version', '--machine'], root, env, true));
  for (const field of ['frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion']) {
    if (!runtime[field]) throw new Error(`Missing toolchain identity: ${field}`);
  }
  const snapshot = sourceSnapshot();
  const current = identity({ commit: git('rev-parse', 'HEAD'), sources: snapshot.hash,
    toolchain: { flutter: runtime.frameworkVersion, framework: runtime.frameworkRevision,
      engine: runtime.engineRevision, dart: runtime.dartSdkVersion, node: process.version },
    platform: process.platform, arch: process.arch,
    image: [process.env.ImageOS || '', process.env.ImageVersion || ''] });
  if (process.env.GITHUB_ACTIONS === 'true' && current.commit !== process.env.GITHUB_SHA) {
    throw new Error('Checkout differs from the workflow commit.');
  }
  const key = cacheKey(current);
  if (argv.includes('--key')) { console.log(`key=${key}`); return; }
  const cacheRoot = join(root, '.tools', 'ci-cache', 'web-debug');
  const entry = join(cacheRoot, key);
  const output = join(root, 'apps', 'mobile', 'build', 'web');
  // Refuse redirected output/cache roots before any recursive removal/copy.
  for (const target of [cacheRoot, output]) {
    let cursor = root;
    for (const part of relative(root, target).split(sep)) {
      cursor = join(cursor, part);
      if (existsSync(cursor) && lstatSync(cursor).isSymbolicLink()) throw new Error('Redirected build/cache path.');
    }
  }
  const hit = !disabled && validEntry(entry, current);
  let buildRoot;
  try {
    let payload = join(entry, 'web');
    if (!hit) {
      // Fresh generated build state on every miss; never consumes local signing files.
      buildRoot = mkdtempSync(join(tmpdir(), 'mlg-web-check-'));
      for (const [name, hash] of snapshot.records) {
        if (hash === null || !name.startsWith('apps/mobile/')) continue;
        const dest = join(buildRoot, name);
        mkdirSync(dirname(dest), { recursive: true });
        cpSync(join(root, name), dest);
      }
      const mobile = join(buildRoot, 'apps', 'mobile');
      const buildEnv = disabled ? { ...env, PUB_CACHE: join(buildRoot, 'pub-cache') } : env;
      flutter(['pub', 'get', '--enforce-lockfile'], mobile, buildEnv);
      flutter(buildArgs, mobile, buildEnv);
      payload = join(mobile, 'build', 'web');
      const files = manifest(payload);
      if (!['index.html', 'flutter_bootstrap.js', 'main.dart.js'].every(k => files[k])) {
        throw new Error('Incomplete web build.');
      }
      if (sourceSnapshot().hash !== snapshot.hash) throw new Error('Sources changed while building; retry.');
      if (!disabled) {
        mkdirSync(cacheRoot, { recursive: true });
        const pending = mkdtempSync(join(cacheRoot, '.pending-'));
        try {
          cpSync(payload, join(pending, 'web'), { recursive: true });
          writeFileSync(join(pending, 'manifest.json'), JSON.stringify({ identity: current, files }));
          if (!validEntry(pending, current)) throw new Error('Build cache failed integrity validation.');
          // Exact content-addressed entry only; never another project directory.
          rmSync(entry, { recursive: true, force: true });
          renameSync(pending, entry);
        } finally { rmSync(pending, { recursive: true, force: true }); }
      }
    }
    rmSync(output, { recursive: true, force: true });
    cpSync(payload, output, { recursive: true });
    const result = { cache: disabled ? 'disabled' : hit ? 'hit' : 'miss', key,
      seconds: Number(((performance.now() - started) / 1000).toFixed(2)), commit: current.commit };
    console.log(JSON.stringify(result));
    return result;
  } finally {
    if (buildRoot) rmSync(buildRoot, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { run(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
