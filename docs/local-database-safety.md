# Local Database Safety and Recovery

Status: current operational contract for the repository-local Supabase database.

This document owns reset authority, local backup verification, destructive
confirmation, and disposable migration-test isolation. Read it before changing
any script that starts, verifies, backs up, resets, restores, or creates a test
target from the local Supabase Postgres instance.

## Quick Rules

1. `npm run verify:db`, `npm run start:local`, and every browser E2E command
   are non-reset workflows. Supplying `RESET_DB=true` makes them fail before a
   Supabase database command runs.
2. `APPLY_MIGRATIONS=true npm run verify:db` may apply reviewed pending SQL to
   the normal local database. It is not a reset and it may still change or
   delete local rows.
3. `npm run db:backup:local` is the supported full local backup command. A dump
   is published only after a successful restore into a physically separate,
   RAM-only Postgres container.
4. `npm run db:reset:local` is preview-only. It prints the exact validated
   target, row-count facts, migration boundary, and a content-bound
   confirmation token; it changes no database data.
5. A reset can execute only through the dedicated wrapper, with both
   `RESET_DB=true` and the fresh `RESET_DB_CONFIRMATION` token from the preview.
   The wrapper creates and restore-verifies another full backup before the sole
   allowed destructive invocation, `supabase db reset --local`.
6. Never use `supabase db reset --db-url`, `supabase db reset --linked`, or an
   unwrapped `supabase db reset` in repository automation. A loopback URL is not
   a sufficient isolation boundary.
7. Migration transition tests that write fixtures or acquire locks run in a
   separate Docker container with no normal Supabase volume. A second database
   in the normal Postgres cluster is not considered isolated.
8. A source backup and a tested recovery path are separate things. Do not
   replace the normal local database from an archive without a new, explicit
   user-approved recovery operation.

These rules apply only to the repository-local project from
`supabase/config.toml`. They grant no authority over a linked or remote project
and prove nothing about remote migration or backup state.

## Why This Boundary Exists

On 2026-08-04, while developing the Goal-removal transition test, Supabase CLI
`2.107.0` treated a loopback `db reset --db-url` target as the normal local
Supabase target. The normal local database was recreated even though the test
intended to reset a separately named database. Repository source, remote data,
and environment configuration were unaffected, and the four deterministic demo
accounts could be reseeded, but unseeded local rows would have required a
pre-existing backup.

The relevant lesson is structural: a database name, loopback URL, or shell
variable cannot make a destructive CLI operation safe if the CLI may
reclassify the target. The patch therefore removes reset authority from all
ordinary workflows, binds exceptional approval to exact current database
facts, requires a recovery archive, and gives transition tests a separate
Postgres process and storage boundary.

## Safety Layers

| Layer | Enforced behavior | Owning source |
| --- | --- | --- |
| Ordinary workflow guard | Rejects `RESET_DB=true`; default migration check is read-only. | `scripts/lib/local_supabase_migrations.sh` |
| Exact target validation | Requires project `mylifegraph`, the expected Supabase-labelled container, an exact `public.ecr.aws/supabase/postgres:<tag>` or `ghcr.io/supabase/postgres:<tag>` image, a running state, and database/user identity `postgres`. Other registries and GHCR namespaces remain rejected. | `scripts/lib/local_supabase_database_safety.sh` |
| Content-bound approval | Hashes project, container, database, Auth/profile counts, database size, latest migration, and a logical SHA-256 digest of the protected Auth, private product/ledger, public, Storage, and migration data into a short-lived reset token. PostgreSQL 17's per-dump `\\restrict` transport nonces are removed only as one exact, ordered, matching meta-command pair before hashing. | `scripts/lib/local_supabase_database_safety.sh` |
| Backup gate | Creates a complete custom-format `pg_dump`, checks required archive entries, restores it in a separate container, and compares Auth/profile counts and latest migration. | `scripts/backup_local_supabase.sh` and the shared safety library |
| Single reset choke point | Rechecks the fingerprint after backup, then and only then invokes `supabase db reset --local`. | `scripts/reset_local_supabase.sh` and the shared safety library |
| Physical test isolation | Uses a labelled, read-only-root, RAM-only Postgres container with no normal database volume. | `scripts/lib/goal_removal_migration_harness.sh` and the shared safety library |
| Source regression | Proves rejection paths, backup-before-reset order, target-drift refusal, exact `--local` invocation, and absence of unsafe reset targets. | `scripts/test_local_supabase_migrations.sh` |
| CI boundary | Fresh jobs start a fresh Supabase stack; they do not pass reset authority into verification or E2E. | `.github/workflows/ci.yml` |

No permanent generic JSON constraint is part of this safety layer. The Goal
retirement migrations own database cleanup, while current APIs reject retired
Goal inputs and continue to allow extensible metadata and ordinary free text.

## Normal Local Workflows

### Inspect and test the current database

```bash
npm run verify:db
```

This starts or reuses the local Supabase stack, compares repository migration
files with `supabase_migrations.schema_migrations`, runs the physically isolated
Goal transition harness, and finally runs the complete pgTAP suite against the
normal local database. It does not apply SQL or reset data by default.

The verifier and browser E2E runner capture raw `supabase start` output only in
a mode-`0600` temporary file. Success emits one stable marker instead of
replaying Docker pull progress into CI; failure emits at most the final 200
sanitized lines. The raw file is trap-cleaned in both cases. This bounded
logging prevents a successful image pull from failing solely because the CI log
channel applies backpressure, without hiding the CLI failure or exposing local
keys.

The same no-reset rule applies to:

```bash
npm run start:local
FLUTTER_BIN=/path/to/flutter npm run e2e:web:smoke
FLUTTER_BIN=/path/to/flutter npm run e2e:web:full
FLUTTER_BIN=/path/to/flutter npm run verify:full
```

Each command rejects `RESET_DB=true` before starting a database mutation. E2E
may create run-specific users and product rows, but its `finally` cleanup owns
only those exact user IDs; that scoped behavior is documented in
`docs/verification.md`.

### Apply reviewed pending migrations

```bash
APPLY_MIGRATIONS=true npm run verify:db
```

This remains an explicit local write path. Review the pending migration SQL and
counts of affected local rows first. The script runs `migration up --local`,
checks history again, then runs the transition and final-state tests. It does
not take an automatic backup and must not be described as non-destructive merely
because it does not reset the database. For a destructive or unusually broad
migration, create a verified backup first:

```bash
npm run db:backup:local
APPLY_MIGRATIONS=true npm run verify:db
```

## Full Restore-Verified Backup

Run:

```bash
npm run db:backup:local
```

The command performs these checks in order:

1. Starts or reuses only the project named by `supabase/config.toml`.
2. Validates the exact running database container, its Supabase project label,
   recognized image, current database, and current user.
3. Captures source Auth-user count, profile count, and latest migration.
4. Streams a full `pg_dump --format=custom` from the normal `postgres`
   database into a mode-`0600` partial file.
5. Uses `pg_restore --list` to require data entries for `auth.users`,
   `public.profiles`, and `supabase_migrations.schema_migrations`.
6. Starts a separate RAM-only Postgres container from the same Supabase image,
   bootstraps only the role names needed to parse restored policies and
   ownership-independent objects, and streams the archive into
   `pg_restore --no-owner --no-privileges --exit-on-error`.
7. Requires restored Auth-user count, profile count, and latest migration to
   match the source.
8. Removes the disposable container, atomically publishes the archive, and
   writes its SHA-256 and metadata sidecars.

A failed dump, incomplete archive, restore error, mismatch, or cleanup problem
does not publish the partial archive as a verified backup. Temporary partial,
list, and restore-log files are removed by the trap.

Successful artifacts are stored under:

```text
.tools/supabase-backups/
  mylifegraph-local-<UTC timestamp>-<pid>.dump
  mylifegraph-local-<UTC timestamp>-<pid>.dump.sha256
  mylifegraph-local-<UTC timestamp>-<pid>.dump.metadata
```

`.tools/` is ignored by Git. The dump contains local Auth and application data,
so treat it as sensitive: do not commit, attach, paste, or move it to an
untrusted location. The sidecars are evidence for the exact archive but are not
a remote backup, retention policy, encrypted vault, or proof that a later
archive remains readable.

## Guarded Local Reset

### Phase 1: preview only

```bash
npm run db:reset:local
```

The preview verifies the exact local target and prints:

- project and container identity;
- database name;
- current Auth-user and profile counts;
- database size;
- latest applied migration;
- a logical digest of the protected Auth, private product/ledger, public,
  Storage, and migration data;
- a confirmation token bound to those facts and that digest.

It does not create a backup, invoke a reset, or change data. If any writer
changes protected logical data, the fingerprint and token change. Internal WAL
maintenance alone does not invalidate an otherwise unchanged preview.

### Phase 2: explicit execution

Copy the complete command printed by the immediately preceding preview:

```bash
RESET_DB=true \
RESET_DB_CONFIRMATION='<fresh token from preview>' \
npm run db:reset:local
```

The executing run refuses an empty, malformed, stale, or wrong token. With a
matching token it first creates the full restore-verified backup described
above. It then captures the target facts and protected logical digest again.
Any protected-data drift during backup changes the token, retains the verified
archive, and aborts before reset. Only an unchanged target reaches the
repository's sole destructive CLI line:

```text
supabase db reset --local
```

After the CLI succeeds, repository and local migration histories must match.
The recovery archive remains available under `.tools/supabase-backups/`.

The wrapper rejects `APPLY_MIGRATIONS=true`. Reset and incremental migration
application are separate operator decisions and cannot be combined in one
invocation.

## Physically Isolated Postgres Targets

The Exam Plan Health additive migration uses
`scripts/lib/exam_plan_health_migration_harness.sh` as a feature-specific
full-chain proof. It must preserve the same RAM-only/container-label target
checks as the general transition harness, run its pgTAP file only inside that
target, trap-clean the container, and prove the normal local migration history
is byte-identical before and after. Passing this harness is not authority to
apply `exam-plan-health-v1` or any pending migration to the normal local stack.

The Multi-Exam additive migration uses
`scripts/lib/multi_exam_plan_migration_harness.sh` under the same physical
isolation contract. It must validate the labeled RAM-only target, apply the
complete repository chain there, run only
`supabase/tests/multi_exam_plan_v1_test.sql`, trap-clean the target, and compare
the normal local migration history byte-for-byte before and after. Passing it
does not authorize applying `multi-exam-plan-v1` to the normal local stack.
The concurrency assertions are also safe in the normal non-superuser pgTAP
session: they create one expiring test login with a random SCRAM secret held
only in `pg_temp`, connect through the server interface where that password is
actually authenticated, and revoke/drop the login after both sessions close.
The login has exact Proposal/Confirm RPC and private fixture/helper rights only;
it is never a `service_role` member. The isolated superuser target uses its
permitted loopback path. Before fixture creation and after success, the test
removes only its fixed synthetic owner, private helper objects, and exact login
so an interrupted committed phase is retry-safe without touching another local
identity. When the test itself installs `dblink`, that transaction also writes
one marker bound to the extension OID, owner, schema, and version. Only a
matching marker permits a later non-`CASCADE` drop; markerless pre-existing
installations remain unchanged, while an interrupted marker-owned installation
is recovered on the next run.

The Recommendation/Decision Feedback retirement migration uses
`scripts/lib/recommendation_retirement_migration_harness.sh` under the same
physical-isolation contract. It applies the full immutable chain only inside a
labeled RAM-only container, loads filled two-owner transition fixtures, proves
a real concurrent writer produces SQLSTATE `55P03` with a complete rollback,
then applies the migration successfully and runs both its transition assertions
and the complete final-state pgTAP suite on pinned PostgreSQL 15 and 17,
independent of the normal local major. The PG17 lane uses a separate OID-10 bootstrap
superuser and a non-superuser `postgres` migration identity with `CREATEROLE`,
then round-trips the final database through another RAM-only PG17 container and
executes one restored deletion replay. The disposable bootstrap mirrors the
normal Supabase session boundary: `service_role` is `BYPASSRLS`, and
`anon`/`authenticated`/`service_role` have `USAGE` on the `extensions` schema
because the normal database search path is `"$user", public, extensions`.
Normal local migration history is serialized as ordered `version`, `name`, and
`statements` facts and SHA-256 hashed before and after every isolated stage.
Passing this harness does not authorize applying the erase migration to the
normal local database.

The shared isolation helper deliberately does not create a second database in
`supabase_db_mylifegraph`. It starts a separate Docker container with:

- the exact validated running Supabase Postgres image, except for the dedicated
  full-chain compatibility lanes' explicit, locally present pinned PG15 and
  PG17 images;
- a unique process-scoped name and ownership labels;
- no bind mount and no normal Supabase volume;
- a read-only root filesystem;
- Postgres data, runtime, and temporary directories on bounded RAM `tmpfs`;
- all Linux capabilities dropped and `no-new-privileges` enabled;
- CPU, memory, process, and swap limits;
- a random port published only on `127.0.0.1`;
- a one-day self-signed certificate generated inside the disposable data
  directory because pinned Supabase CLI versions may attempt TLS even when a
  loopback URL asks to disable it;
- host authentication limited to the single validated Docker bridge gateway
  address (`/32`); the PG17 Multi-Exam dblink proof additionally permits only
  the validated container self-address (`/32`) with SCRAM; and
- an ownership-label check before forced cleanup.

The disposable server receives no Supabase key, application credential, normal
database URL, host data volume, or remote-project reference. `pg_net` is
preloaded only when the isolated bootstrap identity is the image's ordinary
`postgres` role; PG16+ lanes with a separate bootstrap superuser start without
that background worker. The
container is removed on success, test failure, interrupt, and backup failure.

### Goal-removal transition harness

`npm run verify:db` uses this boundary to test
`20260804150153_remove_goals_and_make_weekly_review_observational.sql` followed
by `20260804192406_harden_goal_removal_dependencies.sql`:

1. It records the normal database's complete migration-history string.
2. It starts a separate database named exactly
   `mylifegraph_goal_removal_migration_test` in the disposable container.
3. It bootstraps minimal role names, Auth functions/table, `pgcrypto`, and
   pgTAP; product objects still come only from repository migrations.
4. `supabase migration up --db-url` applies the chain through the version
   immediately before the original Goal migration.
5. Filled before-fixtures are inserted, the original Goal migration is applied,
   and a between-migration `free-coach-agent-prompt-v3` /
   `personal-snapshot-v2` fixture is inserted to prove that current Goal-free
   Coach history survives the dependency-hardening follow-up.
6. A second PostgreSQL session holds a real writer lock on `public.tasks`.
7. The first follow-up attempt must hit its five-second `lock_timeout`.
   Assertions require no follow-up history row, no partial fixture change, and
   no leaked temporary migration helper.
8. After lock release, the same follow-up migration must succeed.
9. Twenty-seven pgTAP transition assertions verify sanitization, dependency
   deletion, Coach tombstoning, historical review preservation, no dangling
   reference, no Goal trace, and helper cleanup.
10. The normal database's migration-history string is compared after every
    isolated stage.

The normal database is never a fixture target. Do not replace this container
with `db reset --db-url`, a temporary database in the normal cluster, or a test
that relies only on cleanup after a destructive command.

## Recovery From a Local Data Incident

An archive existing is not permission to overwrite the normal database. Use
this order:

1. Stop application, seed, E2E, scheduler, and migration writers.
2. Preserve the current damaged or questionable database with a new verified
   backup when it is still readable; never overwrite the earlier archive.
3. Record the exact candidate archive, its checksum sidecar, metadata, CLI
   version, and repository migration boundary.
4. Verify `sha256sum --check` from the archive directory.
5. Rehearse the archive in a physically separate target and inspect more than
   counts for the incident-specific tables. The standard backup command already
   proves a clean full restore at creation time; recovery analysis may need
   additional read-only queries.
6. Decide whether recovery requires the whole database, selected rows, or
   reseeding only the four deterministic demo identities. Do not restore a
   whole archive merely to recover one seedable account.
7. Obtain explicit user approval for the resolved normal local target and the
   chosen replacement/import operation.
8. Perform the recovery as a separately reviewed operation, then run migration
   history, pgTAP, demo-contract, and user-specific checks.

The repository intentionally provides no one-command in-place restore. A
generic restore would need destructive cleanup, role/global handling, and an
incident-specific choice between complete replacement and selective recovery;
putting that authority into ordinary verification would recreate the risk this
contract removes.

The deterministic local demo accounts remain owned by `npm run seed:demo`.
That command replaces only its four exact named demo identities. It is not a
backup and cannot reconstruct arbitrary local accounts or unseeded edits.

## External Tool Approval Hygiene

Repository guards cannot revoke approvals stored by an agent shell, IDE, or
automation host. After any incident, remove persistent approval rules that
allow broad `supabase db reset` execution. If command approvals are needed,
scope them to the non-destructive wrappers (`npm run verify:db`,
`npm run db:backup:local`, or preview-only `npm run db:reset:local`) rather than
the Supabase binary or a raw reset prefix.

Do not infer safety merely because an external approval UI accepted a command.
Repository target validation, backup, fresh confirmation, and the exact
`--local` choke point still apply.

## Changing or Upgrading This Patch

Treat changes to the following as one safety boundary:

- `scripts/lib/local_supabase_migrations.sh`;
- `scripts/lib/local_supabase_database_safety.sh`;
- `scripts/backup_local_supabase.sh`;
- `scripts/reset_local_supabase.sh`;
- `scripts/lib/goal_removal_migration_harness.sh`;
- `scripts/lib/recommendation_retirement_migration_harness.sh`;
- `scripts/verify_supabase_local.sh`;
- `scripts/e2e_web.sh` and `scripts/start_local_stack.sh`;
- `scripts/test_local_supabase_migrations.sh`;
- `.github/workflows/ci.yml`; and
- this document plus `docs/local-dev.md` and `docs/verification.md`.

Before adopting another Supabase CLI release:

1. Inspect installed help for `db dump`, `db reset`, `migration up`, and
   `test db`; do not guess flags.
2. Keep the CLI version change separate from unrelated product work.
3. Run the hermetic source safety tests.
4. Create a new full restore-verified backup.
5. Run reset preview only; do not use a CLI upgrade as permission to reset.
6. Run the isolated Goal harness and final-state pgTAP suite.
7. Confirm the exact normal migration history and a known local user before and
   after the checks.
8. Update `docs/verification.md#current-verified-baseline` only with results
   from the actual checkout.

If a future CLI correctly honors non-TLS loopback URLs, ephemeral TLS may be
removed only after the pinned old and proposed new versions both pass the
physical harness or after the repository deliberately drops old-version
support. Physical process/storage isolation and reset prohibition remain.

## Reverting the Safety Patch

The safety patch changes repository scripts, tests, CI, and documentation. It
does not add a database migration or mutate the schema, so reverting the patch
does not require a database rollback. Once delivered as one commit, the safest
source rollback is a normal Git revert of that exact commit; review the revert
before applying it because later changes may depend on the wrapper names.

For a manual source rollback, remove or reverse the boundary as one coherent
change:

1. Remove the `db:backup:local` and `db:reset:local` package scripts only when
   their wrapper files and documentation are removed in the same change.
2. Remove the two wrappers and shared safety library only after replacing every
   caller and the Goal harness with an equivalently isolated design.
3. Revert ordinary workflows and CI together; never leave one path with reset
   authority merely because another still rejects it.
4. Revert hermetic safety tests and docs-impact ownership only together with the
   behavior they assert.
5. Update this document, `AGENTS.md`, `docs/local-dev.md`,
   `docs/verification.md`, `docs/architecture.md`, and
   `docs/supabase-current-state.md` so they describe the resulting truth.
6. Run documentation, fast, database, web, and full verification plus
   `git diff --check` before handoff.

Do not roll back one guard in isolation. In particular, reintroducing
`RESET_DB=true npm run verify:db`, raw reset in E2E, `db reset --db-url`, or a
temporary database inside the normal cluster is not an acceptable mechanical
revert. A deliberate policy rollback must state the replacement isolation,
confirmation, and recovery controls and receive explicit user authorization.

The Goal-retirement migrations are a different boundary. Removing their SQL
files does not restore deleted data and violates migration immutability.
Reintroducing Goals would require a new forward migration, corresponding API
and product-contract changes, and recovery of deleted records from an actual
pre-migration backup. The setup-retirement contract documents that product
rollback separately.

## Handoff Checklist

Before claiming local database safety work complete:

- [ ] Normal target identity and migration history were inspected read-only.
- [ ] A full custom archive was restored successfully in a separate container.
- [ ] The backup path, checksum sidecar, and metadata sidecar exist outside Git.
- [ ] Reset preview passed and the executing reset mode was not run unless the
      user explicitly authorized that exact destructive operation.
- [ ] The isolated migration transition/locking harness passed.
- [ ] The complete final-state pgTAP suite passed.
- [ ] A known local identity or equivalent aggregate remained unchanged.
- [ ] No disposable safety container remains.
- [ ] `npm run verify:docs`, relevant product gates, and `git diff --check`
      passed.
- [ ] Both staged and unstaged diffs were inspected.
- [ ] No remote migration, deployment, push, reset, or recovery was claimed
      without direct evidence and authority.
