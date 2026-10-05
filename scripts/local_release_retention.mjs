#!/usr/bin/env node
// Local artifact retention only. Never traverse build trees or deployed releases.
import * as fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { androidReleaseIdentity } from './android_release_identity.mjs';

export const REPOSITORY = 'MyLifeGraph/MyLifeGraph';
const SCHEMA = 'mylifegraph-local-release-retention-v1';
const CERT = '9c06793b9a5841527fd43289c338d6f23cfcc60eb471cc7fcb189a12c24de691';
const GROUP = { platform: 'android', variant: 'signed-pilot' };
const SHA = /^[a-f0-9]{40}$/;
const HASH = /^[a-f0-9]{64}$/;
const hash = value => createHash('sha256').update(value).digest('hex');
const json = value => JSON.stringify(value, null, 2) + '\n';
const fail = message => { throw new Error(message); };

function namesFor(tag) {
  androidReleaseIdentity(tag); // Same bounded tag convention as the signer.
  return [`MyLifeGraph-${tag}.apk`, `MyLifeGraph-${tag}.cdx.json`,
    'SHA256SUMS', 'release-metadata.json'];
}

function noLinks(target, directory = false) {
  const stat = fs.lstatSync(target);
  if (stat.isSymbolicLink() || (directory ? !stat.isDirectory() : !stat.isFile()) ||
      (!directory && stat.nlink !== 1)) fail('Non-regular or linked path: ' + target);
  if (path.resolve(fs.realpathSync(target)) !== path.resolve(target)) {
    fail('Redirected path: ' + target);
  }
  return stat;
}

function ancestors(target) {
  let current = path.resolve(target);
  for (;;) {
    noLinks(current, true);
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}

function mkdir(target) {
  ancestors(path.dirname(target));
  if (!fs.existsSync(target)) fs.mkdirSync(target, { mode: 0o700 });
  noLinks(target, true);
}

function readJson(target) {
  const stat = noLinks(target);
  if (stat.size > 64 * 1024) fail('Oversized control file: ' + target);
  try { return JSON.parse(fs.readFileSync(target, 'utf8')); }
  catch { fail('Invalid JSON control file: ' + target); }
}

function atomicJson(target, value) {
  ancestors(path.dirname(target));
  if (fs.existsSync(target)) noLinks(target);
  const temporary = target + '.writing';
  fs.writeFileSync(temporary, json(value), { flag: 'wx', mode: 0o600 });
  try { fs.renameSync(temporary, target); }
  finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
}

async function fileIdentity(target) {
  ancestors(path.dirname(target));
  const before = noLinks(target);
  const digest = createHash('sha256');
  // O_NOFOLLOW is supported on Linux; Windows is covered by path/file checks.
  const fd = fs.openSync(target, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0));
  try {
    const opened = fs.fstatSync(fd);
    if (!opened.isFile() || opened.nlink !== 1 || opened.ino !== before.ino ||
        opened.dev !== before.dev) fail('File changed while opening: ' + target);
    const stream = fs.createReadStream(target, { fd, autoClose: false });
    for await (const chunk of stream) digest.update(chunk);
    const after = noLinks(target);
    if (before.ino !== after.ino || before.dev !== after.dev ||
        before.size !== after.size || before.mtimeMs !== after.mtimeMs) {
      fail('File changed while hashing: ' + target);
    }
    return { size: before.size, sha256: digest.digest('hex') };
  } finally { fs.closeSync(fd); }
}

function equal(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

function validateMetadata(metadata, tag, sha) {
  const keys = ['schema_version', 'release_tag', 'release_sha', 'build_name',
    'build_number', 'signing_certificate_sha256', 'source_sbom_sha256'];
  if (!equal(Object.keys(metadata).sort(), keys.sort()) ||
      metadata.schema_version !== 'mylifegraph-android-artifact-v1' ||
      metadata.release_tag !== tag || metadata.release_sha !== sha ||
      metadata.build_name !== tag.slice(1) ||
      !/^[1-9]\d*$/.test(metadata.build_number) ||
      Number(metadata.build_number) > 2_100_000_000 ||
      metadata.signing_certificate_sha256 !== CERT ||
      !HASH.test(metadata.source_sbom_sha256)) fail('Artifact identity/signing metadata mismatch');
}

export async function readBundle(directory, tag, sha) {
  if (!SHA.test(sha)) fail('Expected full source SHA');
  ancestors(directory);
  const names = namesFor(tag);
  validateMetadata(readJson(path.join(directory, names[3])), tag, sha);
  const files = {};
  for (const name of names) files[name] = await fileIdentity(path.join(directory, name));
  const sums = fs.readFileSync(path.join(directory, 'SHA256SUMS'), 'utf8');
  const expected = names.slice(0, 2).map(name => `${files[name].sha256}  ${name}`).join('\n') + '\n';
  if (sums.replaceAll('\r\n', '\n') !== expected) fail('APK/SBOM checksum manifest mismatch');
  const metadata = readJson(path.join(directory, names[3]));
  if (metadata.source_sbom_sha256 !== files[names[1]].sha256) fail('SBOM metadata mismatch');
  return files;
}

export class GitHubPublicationProof {
  constructor({ fetchImpl = fetch, token = process.env.GITHUB_TOKEN } = {}) {
    this.fetchImpl = fetchImpl;
    this.token = token;
  }

  async api(suffix) {
    const response = await this.fetchImpl(`https://api.github.com/repos/${REPOSITORY}${suffix}`, {
      headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}) },
      signal: AbortSignal.timeout(30_000), redirect: 'error',
    });
    if (response.status === 404) return null;
    if (!response.ok) fail('GitHub publication verification unavailable: HTTP ' + response.status);
    return response.json();
  }

  async snapshot(record) {
    const release = await this.api('/releases/tags/' + encodeURIComponent(record.tag));
    if (!release || release.draft === true || !release.published_at) return null;
    if (release.draft !== false || release.tag_name !== record.tag ||
        !Number.isSafeInteger(release.id) || !Number.isFinite(Date.parse(release.published_at))) {
      fail('Invalid published release identity');
    }
    const commit = await this.api('/commits/' + encodeURIComponent(record.tag));
    if (commit?.sha !== record.sha) fail('Published tag/source mismatch');
    const assets = [];
    for (const name of namesFor(record.tag)) {
      const matches = (release.assets ?? []).filter(asset => asset.name === name);
      if (matches.length !== 1) fail('Missing or duplicate published asset: ' + name);
      const asset = matches[0];
      const file = record.files[name];
      const expectedUrl = `https://github.com/${REPOSITORY}/releases/download/${record.tag}/${name}`;
      if (!Number.isSafeInteger(asset.id) || asset.state !== 'uploaded' ||
          asset.size !== file.size || asset.digest !== 'sha256:' + file.sha256 ||
          asset.browser_download_url !== expectedUrl) fail('Uploaded asset identity/digest mismatch: ' + name);
      assets.push({ id: asset.id, name, size: asset.size, digest: asset.digest, url: expectedUrl });
    }
    return { id: release.id, tag: record.tag, sha: record.sha,
      publishedAt: release.published_at, assets };
  }

  async downloadIdentity(url, expectedSize) {
    const allowed = new Set(['github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com']);
    for (let redirect = 0; redirect < 5; redirect++) {
      const parsed = new URL(url);
      if (parsed.protocol !== 'https:' || !allowed.has(parsed.hostname) || parsed.username ||
          parsed.password || parsed.port) fail('Unexpected asset download origin');
      // Never forward API credentials to an asset download or redirect.
      const response = await this.fetchImpl(url, { redirect: 'manual', signal: AbortSignal.timeout(120_000) });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get('location');
        if (!location) fail('Invalid asset redirect');
        await response.body?.cancel();
        url = new URL(location, url).href;
        continue;
      }
      if (!response.ok || !response.body) fail('Asset download verification failed: HTTP ' + response.status);
      const digest = createHash('sha256');
      let size = 0;
      for await (const chunk of response.body) {
        size += chunk.length;
        if (size > expectedSize) fail('Downloaded asset exceeds its published size');
        digest.update(chunk);
      }
      return { size, sha256: digest.digest('hex') };
    }
    fail('Too many asset redirects');
  }

  async verify(record) {
    const snapshot = await this.snapshot(record);
    if (!snapshot) return null;
    for (const asset of snapshot.assets) {
      const downloaded = await this.downloadIdentity(asset.url, asset.size);
      if (!equal(downloaded, record.files[asset.name])) fail('Downloaded SHA-256/size mismatch: ' + asset.name);
    }
    if (!equal(snapshot, await this.snapshot(record))) fail('Publication changed during verification');
    return snapshot;
  }
}

export class LocalReleaseStore {
  constructor(repositoryRoot, proof = new GitHubPublicationProof()) {
    this.repositoryRoot = path.resolve(repositoryRoot);
    this.root = path.join(this.repositoryRoot, '.tools', 'release-artifacts');
    this.proof = proof;
  }

  initialize() {
    ancestors(this.repositoryRoot);
    mkdir(path.join(this.repositoryRoot, '.tools'));
    mkdir(this.root);
    const marker = path.join(this.root, 'store.json');
    const expected = { schema: SCHEMA, repository: REPOSITORY, root: this.root };
    if (!fs.existsSync(marker)) {
      if (fs.readdirSync(this.root).length) fail('Refusing to adopt a non-empty unmarked store');
      fs.writeFileSync(marker, json(expected), { flag: 'wx', mode: 0o600 });
    }
    if (!equal(readJson(marker), expected)) fail('Store marker/path mismatch');
    mkdir(path.join(this.root, GROUP.platform));
    mkdir(path.join(this.root, GROUP.platform, GROUP.variant));
  }

  async locked(operation) {
    this.initialize();
    const lock = path.join(this.root, 'operation.lock');
    const content = json({ pid: process.pid, started: new Date().toISOString() });
    fs.writeFileSync(lock, content, { flag: 'wx', mode: 0o600 });
    try { return await operation(); }
    finally {
      ancestors(this.root);
      noLinks(lock);
      if (fs.readFileSync(lock, 'utf8') !== content) fail('Store lock changed; manual review required');
      fs.unlinkSync(lock);
    }
  }

  directory(tag) { namesFor(tag); return path.join(this.root, GROUP.platform, GROUP.variant, tag); }

  async stage(source, tag, sha) {
    const files = await readBundle(path.resolve(source), tag, sha);
    const directory = this.directory(tag);
    mkdir(directory);
    const receipt = path.join(directory, 'receipt.json');
    const record = { schema: SCHEMA, repository: REPOSITORY, ...GROUP, tag, sha, files, pinned: false };
    if (fs.existsSync(receipt)) {
      const saved = this.validateRecord(readJson(receipt), tag);
      if (saved.sha !== sha || !equal(saved.files, files)) fail('Refusing to overwrite another candidate');
      await readBundle(directory, tag, sha);
      return saved;
    }
    if (fs.readdirSync(directory).length) fail('Refusing to adopt unregistered files');
    for (const name of namesFor(tag)) {
      const destination = path.join(directory, name);
      fs.copyFileSync(path.join(source, name), destination, fs.constants.COPYFILE_EXCL);
      if (!equal(await fileIdentity(destination), files[name])) fail('Source changed during staging');
    }
    await readBundle(directory, tag, sha);
    fs.writeFileSync(receipt, json(record), { flag: 'wx', mode: 0o600 });
    return record;
  }

  validateRecord(record, tag) {
    if (!equal(Object.keys(record).sort(), ['schema', 'repository', 'platform', 'variant', 'tag', 'sha', 'files', 'pinned'].sort()) ||
        record.schema !== SCHEMA || record.repository !== REPOSITORY || record.tag !== tag ||
        record.platform !== GROUP.platform || record.variant !== GROUP.variant ||
        !SHA.test(record.sha) || typeof record.pinned !== 'boolean' ||
        !equal(Object.keys(record.files ?? {}).sort(), namesFor(tag).sort())) fail('Invalid artifact receipt');
    for (const file of Object.values(record.files)) {
      if (!equal(Object.keys(file).sort(), ['size', 'sha256'].sort()) ||
          !HASH.test(file.sha256) || !Number.isSafeInteger(file.size) || file.size <= 0) fail('Invalid artifact fingerprint');
    }
    return record;
  }

  async plan() {
    const protectedEntries = [], published = [], pruned = [];
    const group = path.join(this.root, GROUP.platform, GROUP.variant);
    ancestors(group);
    for (const tag of fs.readdirSync(group).sort()) {
      try { namesFor(tag); }
      catch { protectedEntries.push({ tag, reason: 'unknown-output' }); continue; }
      const directory = this.directory(tag);
      noLinks(directory, true);
      const receiptPath = path.join(directory, 'receipt.json');
      if (!fs.existsSync(receiptPath)) { protectedEntries.push({ tag, reason: 'unregistered-output' }); continue; }
      const record = this.validateRecord(readJson(receiptPath), tag);
      const names = namesFor(tag);
      const unknown = fs.readdirSync(directory).filter(name => !names.includes(name) && name !== 'receipt.json');
      if (unknown.length) { protectedEntries.push({ tag, reason: 'unknown-files' }); continue; }
      const present = names.filter(name => fs.existsSync(path.join(directory, name)));
      if (!present.length) { pruned.push(tag); continue; }
      if (present.length !== names.length) fail('Incomplete registered bundle; no cleanup: ' + tag);
      if (!equal(await readBundle(directory, tag, record.sha), record.files)) fail('Local artifact changed: ' + tag);
      const proof = await this.proof.verify(record);
      if (!proof) { protectedEntries.push({ tag, reason: 'unpublished' }); continue; }
      published.push({ record, proof });
    }
    published.sort((a, b) => Date.parse(a.proof.publishedAt) - Date.parse(b.proof.publishedAt) || a.proof.id - b.proof.id);
    const retained = new Set([published[0]?.record.tag, published.at(-1)?.record.tag]);
    const remove = [], keep = [];
    for (const { record, proof } of published) {
      if (retained.has(record.tag) || record.pinned) {
        keep.push({ tag: record.tag, reason: record.pinned ? 'pinned' : 'oldest-or-newest' });
      } else { remove.push({ record, proof }); }
    }
    const plan = { schema: SCHEMA, root: this.root, ...GROUP, keep,
      protected: protectedEntries, alreadyPruned: pruned, remove };
    return { ...plan, confirmation: hash(JSON.stringify(plan)),
      bytesToRemove: remove.reduce((sum, entry) => sum + Object.values(entry.record.files).reduce((n, file) => n + file.size, 0), 0) };
  }

  async apply(confirmation) {
    if (!HASH.test(confirmation ?? '')) fail('Apply requires the exact dry-run confirmation');
    const plan = await this.plan(); // Fresh remote bytes + local hashes, not a cached receipt.
    if (confirmation !== plan.confirmation) fail('Dry-run drift; nothing removed');
    // Recheck every deletion target before the first unlink; never use recursive deletion.
    for (const { record, proof } of plan.remove) {
      if (!equal(await this.proof.snapshot(record), proof)) fail('Publication changed before cleanup');
      if (!equal(await readBundle(this.directory(record.tag), record.tag, record.sha), record.files)) fail('Local file drift');
      const saved = this.validateRecord(readJson(path.join(this.directory(record.tag), 'receipt.json')), record.tag);
      if (!equal(saved, record)) fail('Protection/receipt changed before cleanup');
      const allowed = [...namesFor(record.tag), 'receipt.json'];
      if (fs.readdirSync(this.directory(record.tag)).some(name => !allowed.includes(name))) {
        fail('Unknown file appeared before cleanup');
      }
    }
    let removedBytes = 0;
    for (const { record } of plan.remove) {
      for (const name of namesFor(record.tag)) {
        const target = path.join(this.directory(record.tag), name);
        if (!equal(await fileIdentity(target), record.files[name])) fail('File changed immediately before unlink');
        fs.unlinkSync(target);
        removedBytes += record.files[name].size;
      }
    }
    return { ...plan, applied: true, removedBytes };
  }

  pin(tag, enabled) {
    const receipt = path.join(this.directory(tag), 'receipt.json');
    const record = this.validateRecord(readJson(receipt), tag);
    atomicJson(receipt, { ...record, pinned: enabled });
  }
}

function repositoryForCli(explicit) {
  const root = path.resolve(explicit ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '..'));
  const git = args => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8', windowsHide: true }).trim();
  if (path.resolve(git(['rev-parse', '--show-toplevel'])) !== root) fail('Expected exact repository root');
  const origin = git(['remote', 'get-url', 'origin']);
  if (!['https://github.com/MyLifeGraph/MyLifeGraph.git', 'https://github.com/MyLifeGraph/MyLifeGraph',
    'git@github.com:MyLifeGraph/MyLifeGraph.git'].includes(origin)) fail('Unexpected repository');
  return root;
}

export async function cli(args) {
  const [mode, ...rest] = args;
  const options = {};
  for (let i = 0; i < rest.length; i += 2) {
    const key = rest[i], value = rest[i + 1];
    if (!['--repo-root', '--source', '--tag', '--sha', '--confirm'].includes(key) ||
        !value || key in options) fail('Unknown, missing or duplicate option');
    options[key] = value;
  }
  const allowed = { init: [], stage: ['--source', '--tag', '--sha'],
    finalize: ['--source', '--tag', '--sha'], 'dry-run': [], apply: ['--confirm'],
    pin: ['--tag'], unpin: ['--tag'] };
  if (!(mode in allowed) || Object.keys(options).some(key => key !== '--repo-root' && !allowed[mode].includes(key)) ||
      allowed[mode].some(key => !(key in options))) fail('usage: local_release_retention.mjs init|stage|finalize|dry-run|apply|pin|unpin [--repo-root path] [--source path --tag tag --sha sha] [--confirm dry-run-hash]');
  const store = new LocalReleaseStore(repositoryForCli(options['--repo-root']));
  return store.locked(async () => {
    if (mode === 'init') return { initialized: true, root: store.root };
    if (mode === 'stage' || mode === 'finalize') {
      const record = await store.stage(path.resolve(options['--source']), options['--tag'], options['--sha']);
      if (mode === 'stage') return { staged: true, tag: record.tag, publicationVerified: false };
      const preview = await store.plan();
      if (!preview.keep.some(entry => entry.tag === record.tag) &&
          !preview.remove.some(entry => entry.record.tag === record.tag)) {
        fail('Release is not verified published; candidate protected');
      }
      console.log(json({ dryRun: true, ...preview }));
      return store.apply(preview.confirmation);
    }
    if (mode === 'dry-run') return { dryRun: true, ...await store.plan() };
    if (mode === 'apply') return store.apply(options['--confirm']);
    store.pin(options['--tag'], mode === 'pin');
    return { tag: options['--tag'], pinned: mode === 'pin' };
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  cli(process.argv.slice(2)).then(result => console.log(json(result))).catch(error => {
    // Do not print HTTP bodies, environment, credentials or download redirect URLs.
    console.error('Release cleanup stopped: ' + error.message);
    process.exitCode = 1;
  });
}
