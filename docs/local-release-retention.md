# Safe Local Release Retention

## Scope and protection

The portable Node.js tool (Node 20 or newer, Git available) operates only in the
marked `<exact MyLifeGraph Git root>/.tools/release-artifacts` store. The CLI
requires the exact `MyLifeGraph/MyLifeGraph` origin. It never scans arbitrary
build directories, user folders or deployed releases. The same tool works on
the Windows laptop and Linux development VM; no background sweeper is installed.

The current reviewed output format is **Android / signed-pilot**. Other
platforms/variants remain untouched until their real publication format has a
reviewed allowlist and tests. Production web/server deployments, SDK caches,
automatic Main testing APKs and unregistered legacy outputs are not this format.

Within that group, retain the oldest and newest **locally registered, verified
published** bundle, ordered by GitHub publication time and release id, not by
filenames or filesystem timestamps. Zero, one or two published bundles remove
nothing. Pinned, unpublished, draft, unknown or unregistered outputs remain in
addition to these two. Protection always wins over a count target.

The four exact files are `MyLifeGraph-<RC-tag>.apk`,
`MyLifeGraph-<RC-tag>.cdx.json`, `SHA256SUMS` and `release-metadata.json`.
Registration verifies the existing bounded RC convention, full source SHA,
artifact metadata, configured signing-certificate identity and APK/SBOM hashes.
It copies only these files into the managed store and leaves originals intact.
Never place secrets in this store. Extra files protect the entire bundle.

Existing unregistered downloads are **not automatically** adopted or deleted.
A separate explicit instruction to clean that historical inventory may authorize
a one-time, reviewed migration/deduplication: list exact folders and filenames,
bind local hashes to real published/downloaded asset proof, preview the plan,
retain the true oldest/newest in the managed store, and recheck every target
before individual removal. Record deleted and newly copied bytes separately so
the reported space saving is net, not inflated by temporary copies. Unknown,
unpublished, signing, backup, user and runtime paths remain protected. This is
not permission for broad directory scanning/deletion or a background sweeper.
The read-only `readBundle` inspector supports explicit inventory validation;
the normal cleanup CLI still operates only in its marked store.

Repositories, worktrees, local databases, uploads, user data, backups, secrets,
keystores, signing configuration, build/source folders, Docker images and all
active/previous/rollback server versions are outside deletion scope. Needed
offline or rollback **copies inside the store** must also be explicitly pinned.
Local copies removed under this policy remain recoverable from the verified
GitHub Release; this is not a backup strategy.

## Mandatory publication workflow

1. Complete the normal source, test, security, signing and deployment gates.
   Build and verify the exact candidate commit. Nothing here weakens those gates.
2. Optionally register that known output using `release:stage-local`. It remains
   protected until a real non-draft GitHub Release is published. An Actions
   upload alone is a held candidate and does not count as publication.
3. After authorized GitHub publication, the publishing host and each laptop/VM
   with registered release copies **must** run `release:finalize-local` for the
   published output. It registers the bundle, verifies publication, prints the
   dry-run and applies that exact plan with fresh checks. A nonzero exit means
   the release's local-retention step is incomplete; report and retry it.
4. Proof requires the release tag resolving to the recorded full commit, all
   four uniquely named assets in `uploaded` state, exact sizes, GitHub-computed
   SHA-256 digests, expected public download paths and streamed download bytes
   matching local SHA-256. Release/asset identities are reread afterward.
5. A dry-run does not delete files. Apply recomputes the plan, checks its
   content-bound confirmation and rechecks all deletion targets before removing
   the first file. Pinning, local edits or publication drift invalidate it.

The source gate and both signed-APK workflows run `verify:release-cleanup`.
They deliberately do not clean held uploads or SSH into private hosts. Their
upload steps name this mandatory post-publication procedure; the actual
publisher must run the finalizer after publication, not before it.

```bash
# One-time initialization (also performed by other commands):
node scripts/local_release_retention.mjs init

# Before publication, only register known files; originals are preserved:
npm run release:stage-local -- --source <absolute-output-folder> --tag <RC-tag> --sha <full-commit-sha>

# REQUIRED after successful GitHub publication:
npm run release:finalize-local -- --source <absolute-output-folder> --tag <RC-tag> --sha <full-commit-sha>

# Independent maintenance: preview first, inspect, then use that exact hash:
npm run release:cleanup
npm run release:cleanup:apply -- --confirm <confirmation-from-dry-run>

# Protect an additional offline/rollback artifact copy:
node scripts/local_release_retention.mjs pin --tag <RC-tag>
# Only after its protection is no longer needed:
node scripts/local_release_retention.mjs unpin --tag <RC-tag>
```

Do not invent a tag, SHA or source path. The output folder must hold the exact
four verified files, not a signing directory or a mixed archive. Retention never
publishes, moves tags, replaces assets or deploys anything. Public reads need no
new login; an optional `GITHUB_TOKEN` is read only from the process environment,
never printed, saved or forwarded to asset-download redirects.

## VM installation and failures

For the older development VM checkout, install a checksum-verified standalone
copy of `local_release_retention.mjs` and `android_release_identity.mjs` together
outside the repository, without replacing its source or restarting the retired
development stack. Invoke the installed tool with
`--repo-root /home/codex/code/MyLifeGraph`; it validates that exact Git root and
origin before initializing the same bounded store. The dated installation,
tool fingerprint and checks belong in
[Current Verified Baseline](verification.md#current-verified-baseline).
The VM topology/protected data remain owned by
[VM rebuild](personal-dev-vm-rebuild.md).

An exclusive store lock prevents concurrent commands. A stale or edited lock
fails closed; inspect the owning process before manually recovering it. Do not
expire locks by time. Symbolic links/junctions, hardlinked files, redirected
ancestors, conflicting candidates, malformed receipts and partial bundles stop
cleanup. Network/API errors, draft releases, hash or source mismatch never
authorize deletion. Unknown files/bundles are preserved without adoption.

Deletion uses only individually validated allowlisted files, never recursive
removal. Receipts and directories remain as audit evidence. If a filesystem
failure interrupts deletion, the remaining files and receipt are retained;
later runs reject that partial bundle. Restore the missing exact verified
published files from GitHub before retrying. Do not remove the receipt to hide
the failure. A fully pruned bundle is recognized on repetition and removes
nothing again. Invalid cache/build results are unrelated to this policy.

## Verification

`npm run verify:release-cleanup` uses disposable isolated fixtures. It covers
dry-run, oldest/newest selection, repeated no-op apply, unpublished/protected
outputs, unknown paths, secrets/backups/runtime isolation, hardlinks/junctions,
hash/size/source/upload/redirect failures, local/publication drift, locks and
CLI root constraints. Real GitHub proof and host installation are separately
recorded evidence, not inferred from mocked tests.
