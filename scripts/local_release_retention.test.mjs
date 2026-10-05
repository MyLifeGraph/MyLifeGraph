import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import fsMutable from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { GitHubPublicationProof, LocalReleaseStore, REPOSITORY, cli } from './local_release_retention.mjs';

const SHA = 'a'.repeat(40);
const CERT = '9c06793b9a5841527fd43289c338d6f23cfcc60eb471cc7fcb189a12c24de691';
const digest = value => createHash('sha256').update(value).digest('hex');
const encoded = value => JSON.stringify(value, null, 2) + '\n';
const tagFor = n => `v0.1.0-pilot.1-rc.${n}`;
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

function environment(t) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'mylifegraph-retention-test-'));
  t.after(() => {
    const resolved = path.resolve(temporary);
    assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
    assert(path.basename(resolved).startsWith('mylifegraph-retention-test-'));
    assert(!fs.lstatSync(resolved).isSymbolicLink());
    fs.rmSync(resolved, { recursive: true, force: true });
  });
  const repo = path.join(temporary, 'repository');
  fs.mkdirSync(repo);
  const releases = new Map(), bodies = new Map();
  const faults = {};
  const requests = [];
  const fetchImpl = async (url, options) => {
    requests.push({ url, options });
    if (faults.network) throw Error('simulated connection failure');
    if (url.startsWith('https://api.github.com/')) {
      if (faults.http) return new Response('not exposed provider body', { status: faults.http });
      if (url.includes('/commits/')) return Response.json({ sha: faults.commit ?? SHA });
      const tag = decodeURIComponent(url.split('/tags/')[1]);
      const release = releases.get(tag);
      return release ? Response.json(release) : new Response('', { status: 404 });
    }
    if (faults.redirect) return new Response('', { status: 302, headers: { location: faults.redirect } });
    const body = bodies.get(url);
    faults.onDownload?.();
    return body ? new Response(faults.bytes ? Buffer.from('corrupted uploaded data') : body) : new Response('', { status: 404 });
  };
  const proof = new GitHubPublicationProof({ fetchImpl, token: 'test-only-token' });
  const store = new LocalReleaseStore(repo, proof);
  store.initialize();

  async function stage(n, { published = true, time = n } = {}) {
    const tag = tagFor(n), source = path.join(temporary, 'source-' + n);
    fs.mkdirSync(source);
    const apk = `MyLifeGraph-${tag}.apk`, sbom = `MyLifeGraph-${tag}.cdx.json`;
    const data = { [apk]: Buffer.from('PK deterministic test APK ' + tag),
      [sbom]: Buffer.from(encoded({ bomFormat: 'CycloneDX', tag })) };
    data.SHA256SUMS = Buffer.from(`${digest(data[apk])}  ${apk}\n${digest(data[sbom])}  ${sbom}\n`);
    data['release-metadata.json'] = Buffer.from(encoded({ schema_version: 'mylifegraph-android-artifact-v1',
      release_tag: tag, release_sha: SHA, build_name: tag.slice(1), build_number: String(10_000_000 + n),
      signing_certificate_sha256: CERT, source_sbom_sha256: digest(data[sbom]) }));
    for (const [name, value] of Object.entries(data)) fs.writeFileSync(path.join(source, name), value);
    const record = await store.stage(source, tag, SHA);
    const assets = Object.entries(data).map(([name, body], index) => {
      const url = `https://github.com/${REPOSITORY}/releases/download/${tag}/${name}`;
      bodies.set(url, body);
      return { id: n * 10 + index, name, size: body.length, digest: 'sha256:' + digest(body),
        state: 'uploaded', browser_download_url: url };
    });
    if (published) releases.set(tag, { id: n, tag_name: tag, draft: false,
      published_at: new Date(Date.UTC(2026, 9, time)).toISOString(), assets });
    return { record, source, directory: store.directory(tag), apk: path.join(store.directory(tag), apk) };
  }
  return { store, stage, releases, bodies, faults, requests, repo, temporary };
}

test('dry-run preserves all files; apply keeps oldest/newest; repeat is a no-op', async t => {
  const e = environment(t), a = await e.stage(1), b = await e.stage(2), c = await e.stage(3);
  const plan = await e.store.locked(() => e.store.plan());
  assert.deepEqual(plan.keep.map(x => x.tag), [tagFor(1), tagFor(3)]);
  assert.deepEqual(plan.remove.map(x => x.record.tag), [tagFor(2)]);
  assert(fs.existsSync(b.apk));
  const result = await e.store.locked(() => e.store.apply(plan.confirmation));
  assert(result.removedBytes > 0);
  assert(fs.existsSync(a.apk) && fs.existsSync(c.apk));
  assert(!fs.existsSync(b.apk));
  assert(fs.existsSync(path.join(b.directory, 'receipt.json')));
  const again = await e.store.locked(() => e.store.plan());
  assert.equal(again.remove.length, 0);
  assert.equal((await e.store.locked(() => e.store.apply(again.confirmation))).removedBytes, 0);
  assert(fs.existsSync(path.join(b.source, path.basename(b.apk))), 'source output remains protected');
});

test('publication time, not tag or filesystem time, determines the two edges', async t => {
  const e = environment(t);
  await e.stage(9, { time: 1 }); await e.stage(1, { time: 3 }); await e.stage(3, { time: 2 });
  const plan = await e.store.plan();
  assert.deepEqual(plan.keep.map(x => x.tag), [tagFor(9), tagFor(1)]);
  assert.equal(plan.remove[0].record.tag, tagFor(3));
});

test('zero, one and two published releases are never removed', async t => {
  const e = environment(t);
  assert.equal((await e.store.plan()).remove.length, 0);
  await e.stage(1); assert.equal((await e.store.plan()).remove.length, 0);
  await e.stage(2); assert.equal((await e.store.plan()).remove.length, 0);
});

test('unpublished, draft, pinned and unknown outputs survive beside the two edges', async t => {
  const e = environment(t);
  await e.stage(1); const pinned = await e.stage(2); await e.stage(3);
  const candidate = await e.stage(4, { published: false });
  const draft = await e.stage(5); e.releases.get(tagFor(5)).draft = true;
  const unknown = await e.stage(6);
  fs.writeFileSync(path.join(unknown.directory, 'private-backup.txt'), 'do not touch');
  e.store.pin(tagFor(2), true);
  const plan = await e.store.plan();
  assert.equal(plan.remove.length, 0);
  assert.equal(plan.protected.length, 3);
  assert(fs.existsSync(pinned.apk) && fs.existsSync(candidate.apk) && fs.existsSync(draft.apk));
});

test('other platforms/variants and runtime, backup, signing, repo and user paths are not traversed', async t => {
  const e = environment(t);
  await e.stage(1); await e.stage(2); await e.stage(3);
  const protectedFiles = ['.tools/release-artifacts/ios/signed/device.ipa',
    '.tools/release-artifacts/android/debug/app.apk', '.tools/android-signing/keystore.jks',
    '.tools/supabase-backups/database.dump', '.git/objects/example', '.env',
    'build/user-note.txt', 'runtime/current/server.bin', 'runtime/previous/server.bin'];
  for (const name of protectedFiles) {
    const target = path.join(e.repo, name);
    fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, 'protected');
  }
  const plan = await e.store.plan(); await e.store.apply(plan.confirmation);
  for (const name of protectedFiles) assert.equal(fs.readFileSync(path.join(e.repo, name), 'utf8'), 'protected');
});

for (const fault of ['network', 'http', 'commit', 'bytes', 'redirect']) {
  test('publication failure ' + fault + ' refuses cleanup without removing files', async t => {
    const e = environment(t); await e.stage(1); const middle = await e.stage(2); await e.stage(3);
    const plan = await e.store.plan();
    e.faults[fault] = { network: true, http: 403, commit: 'b'.repeat(40), bytes: true,
      redirect: 'https://untrusted.example/secret' }[fault];
    await assert.rejects(e.store.apply(plan.confirmation));
    assert(fs.existsSync(middle.apk));
  });
}

for (const field of ['digest', 'state', 'size', 'browser_download_url']) {
  test('uploaded asset mismatch ' + field + ' fails closed', async t => {
    const e = environment(t), bundle = await e.stage(1);
    e.releases.get(tagFor(1)).assets[0][field] = 'invalid';
    await assert.rejects(e.store.plan()); assert(fs.existsSync(bundle.apk));
  });
}

test('missing or duplicate uploaded assets refuse verification', async t => {
  const e = environment(t); await e.stage(1);
  const assets = e.releases.get(tagFor(1)).assets;
  assets.push(assets[0]); await assert.rejects(e.store.plan(), /duplicate/);
  assets.pop(); assets.pop(); await assert.rejects(e.store.plan(), /Missing/);
});

test('pin/publication changes invalidate a dry-run token', async t => {
  const e = environment(t); await e.stage(1); const middle = await e.stage(2); await e.stage(3);
  const plan = await e.store.plan(); e.store.pin(tagFor(2), true);
  await assert.rejects(e.store.apply(plan.confirmation), /drift/); assert(fs.existsSync(middle.apk));
  e.store.pin(tagFor(2), false);
  e.releases.get(tagFor(2)).published_at = new Date(Date.UTC(2026, 9, 10)).toISOString();
  await assert.rejects(e.store.apply(plan.confirmation), /drift/); assert(fs.existsSync(middle.apk));
});

test('changed/incomplete local bytes cannot be removed; missing confirmation is rejected', async t => {
  const e = environment(t); await e.stage(1); const b = await e.stage(2); await e.stage(3);
  const plan = await e.store.plan();
  await assert.rejects(e.store.apply(), /confirmation/);
  fs.appendFileSync(b.apk, 'edited'); await assert.rejects(e.store.apply(plan.confirmation));
  assert(fs.existsSync(b.apk));
  fs.unlinkSync(b.apk); await assert.rejects(e.store.plan(), /Incomplete/);
  assert(fs.existsSync(path.join(b.directory, 'SHA256SUMS')));
});

test('hardlinks and directory links are rejected, never followed', async t => {
  const e = environment(t), bundle = await e.stage(1);
  fs.linkSync(bundle.apk, path.join(e.temporary, 'outside.apk'));
  await assert.rejects(e.store.plan(), /linked/);
  assert(fs.existsSync(bundle.apk));
  const second = environment(t);
  const linked = second.store.directory(tagFor(2));
  fs.symlinkSync(e.temporary, linked, process.platform === 'win32' ? 'junction' : 'dir');
  await assert.rejects(second.store.plan(), /linked/);
});

test('non-empty unmarked store and moved/edited marker are never adopted', async t => {
  const e = environment(t);
  fs.unlinkSync(path.join(e.store.root, 'store.json'));
  assert.throws(() => e.store.initialize(), /unmarked/);
  assert(fs.existsSync(path.join(e.store.root, 'android')));
});

test('exclusive store lock refuses concurrent operations and stale locks', async t => {
  const e = environment(t);
  await e.store.locked(async () => {
    await assert.rejects(e.store.locked(async () => {}), /EEXIST/);
  });
  fs.writeFileSync(path.join(e.store.root, 'operation.lock'), 'stale lock');
  await assert.rejects(e.store.locked(async () => {}), /EEXIST/);
  assert.equal(fs.readFileSync(path.join(e.store.root, 'operation.lock'), 'utf8'), 'stale lock');
});

test('no API credentials are forwarded to streamed asset downloads', async t => {
  const e = environment(t); await e.stage(1); await e.store.plan();
  for (const request of e.requests.filter(x => !x.url.startsWith('https://api.github.com/'))) {
    assert.equal(request.options.headers?.Authorization, undefined);
  }
});

test('publication changed while bytes are downloading fails closed', async t => {
  const e = environment(t), bundle = await e.stage(1);
  e.faults.onDownload = () => { e.releases.get(tagFor(1)).id += 1; };
  await assert.rejects(e.store.plan(), /changed during/);
  assert(fs.existsSync(bundle.apk));
});

test('truncated and missing GitHub digests fail closed', async t => {
  const e = environment(t), bundle = await e.stage(1);
  const asset = e.releases.get(tagFor(1)).assets[0];
  const original = e.bodies.get(asset.browser_download_url);
  e.bodies.set(asset.browser_download_url, original.subarray(0, 2));
  await assert.rejects(e.store.plan(), /SHA-256/);
  asset.digest = null;
  await assert.rejects(e.store.plan(), /digest/);
  assert(fs.existsSync(bundle.apk));
});

test('failed operations release their own lock; malformed receipts are not adopted', async t => {
  const e = environment(t), bundle = await e.stage(1);
  await assert.rejects(e.store.locked(async () => { throw Error('test failure'); }));
  assert(!fs.existsSync(path.join(e.store.root, 'operation.lock')));
  fs.writeFileSync(path.join(bundle.directory, 'receipt.json'), '{broken');
  await assert.rejects(e.store.locked(() => e.store.plan()), /Invalid JSON/);
  assert(fs.existsSync(bundle.apk));
  assert(!fs.existsSync(path.join(e.store.root, 'operation.lock')));
});

test('candidate retry is stable and mismatched overwrite is refused', async t => {
  const e = environment(t), bundle = await e.stage(1, { published: false });
  assert.deepEqual(await e.store.stage(bundle.source, tagFor(1), SHA), bundle.record);
  await assert.rejects(e.store.stage(bundle.source, tagFor(1), 'b'.repeat(40)), /metadata/);
  assert(fs.existsSync(bundle.apk));
});

test('filesystem failure preserves receipt and remaining files; partial retry fails closed', async t => {
  const e = environment(t); await e.stage(1); const b = await e.stage(2); await e.stage(3);
  const plan = await e.store.plan();
  const original = fsMutable.unlinkSync;
  const interrupted = path.join(b.directory, `MyLifeGraph-${tagFor(2)}.cdx.json`);
  t.mock.method(fsMutable, 'unlinkSync', target => {
    if (target === interrupted) throw Error('simulated busy file');
    return original(target);
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  await assert.rejects(e.store.locked(() => e.store.apply(plan.confirmation)), /busy/);
  assert(!fs.existsSync(b.apk));
  assert(fs.existsSync(interrupted));
  assert(fs.existsSync(path.join(b.directory, 'receipt.json')));
  await assert.rejects(e.store.plan(), /Incomplete/);
  t.mock.restoreAll(); syncBuiltinESMExports();
});

test('marker drift and symlinked store roots are rejected', async t => {
  const e = environment(t);
  fs.writeFileSync(path.join(e.store.root, 'store.json'), encoded({ schema: 'wrong' }));
  assert.throws(() => e.store.initialize(), /marker/);
  const other = environment(t);
  const linkedRepo = path.join(e.temporary, 'linked-repo');
  fs.symlinkSync(other.repo, linkedRepo, process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => new LocalReleaseStore(linkedRepo).initialize(), /linked/);
});

test('bad tag/path and changed signing metadata are rejected before adoption', async t => {
  const e = environment(t), bundle = await e.stage(1);
  assert.throws(() => e.store.directory('../secrets'));
  const metadataPath = path.join(bundle.source, 'release-metadata.json');
  const metadata = JSON.parse(fs.readFileSync(metadataPath));
  metadata.signing_certificate_sha256 = 'b'.repeat(64);
  fs.writeFileSync(metadataPath, encoded(metadata));
  await assert.rejects(e.store.stage(bundle.source, tagFor(1), SHA), /signing/);
});

test('CLI rejects apply without a preview token and foreign repository roots', async t => {
  await assert.rejects(cli(['apply']), /usage/);
  await assert.rejects(cli(['dry-run', '--store', '/']), /Unknown/);
  const e = environment(t);
  const init = spawnSync('git', ['init', e.repo], { windowsHide: true });
  assert.equal(init.status, 0);
  assert.equal(spawnSync('git', ['-C', e.repo, 'remote', 'add', 'origin', 'https://github.com/other/repository.git'], { windowsHide: true }).status, 0);
  await assert.rejects(cli(['init', '--repo-root', e.repo]), /Unexpected repository/);
});

test('workflow/source gates require retention tests without treating held uploads as publication', () => {
  const source = fs.readFileSync(path.join(root, 'scripts/verify_source.sh'), 'utf8');
  assert.match(source, /node --test scripts\/local_release_retention\.test\.mjs/);
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/pilot-release-apk.yml'), 'utf8');
  assert.match(workflow, /npm run verify:release-cleanup/);
  assert.doesNotMatch(workflow, /local_release_retention\.mjs (?:apply|finalize)/);
  const automatic = fs.readFileSync(path.join(root, '.github/workflows/staging-debug-apk.yml'), 'utf8');
  assert.match(automatic, /npm run verify:release-cleanup/);
  for (const name of ['AGENTS.md', 'docs/local-release-retention.md']) {
    assert.match(fs.readFileSync(path.join(root, name), 'utf8'), /release:finalize-local/);
  }
});
