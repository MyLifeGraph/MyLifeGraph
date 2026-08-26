# Supabase pilot backup runner

This is the contract for an off-host, encrypted logical backup. The
default execution host is a protected GitHub Actions environment, not the VPS.
The workflow is inert until the repository variable `PILOT_BACKUP_ENABLED` is
set to exact `true` and all protected secrets/variables are configured.

The runner uses Supabase CLI `2.107.0` and Restic `0.19.1`. It creates roles,
application schema, data, migration-history schema/data, a complete
`auth,storage` managed-schema part, and the official custom-schema diff part.
The custom diff remains the portable hosted-destination artifact. The complete
managed part lets the physically isolated rehearsal reproduce the exact source
Auth/Storage generation when the pinned local CLI base image lags the hosted
project. It validates that Auth tables are present, retains the schema-dump
comments needed to attest the PostgreSQL server version, records aggregate
per-table counts, and fails closed if any Storage object exists. Supabase CLI
excludes the platform-managed
`storage.buckets_vectors` and `storage.vector_indexes` rows from the logical
data part; the runner therefore queries both relations separately with read-only
`psql`, records exact existence/count facts in the signed inventory, and also
fails closed when either excluded relation is non-empty. Before encryption it
compares every applied `supabase_migrations.schema_migrations` identity with
every repository migration; missing, ahead, renamed, duplicate, or divergent
history aborts the run. Because a data-only dump has no row-order guarantee,
unique history identities are canonically sorted before that exact comparison;
physical COPY order is not treated as migration order. The current application
has no Storage feature; remote Staging was observed empty on 2026-08-19, but the
pilot target must be checked again on every run. Supporting non-empty Storage
requires a separately reviewed object-byte export and restore implementation.

The GitHub setup action is pinned to an immutable full commit SHA and supplies
its version-pinned CLI through `PATH`; the workflow does not assume a stable
`/usr/local/bin` installation path. The database URL
must match either the exact pilot direct host or an official Supabase session-
pooler host with the exact pilot username and must carry no password.

Plaintext exists only in the ephemeral runner's mode-0700 temporary directory.
Restic encrypts it into a separately owned off-host repository. The job restores
the exact new snapshot into another private temporary directory and rechecks
every part hash before it counts as successful. It then verifies the repository
and keeps seven daily plus four weekly snapshots. No SQL file is uploaded as a
GitHub artifact.

The same run calls Supabase's read-only Management API Auth-config endpoint and
writes two strict files. `auth-config-inventory.json` is secret-free and keeps
only presence/count/hash/compliance facts suitable for an attestation.
`auth-config-recovery.json` contains exact credential-free rebuild material
(including templates, public site/client identifiers, and sender/admin
addresses); it stays only inside the mode-0700 plaintext workspace and the
encrypted Restic snapshot and must be treated as sensitive recovery data.
Compliance requires the Site URL
to equal `PILOT_PUBLIC_APP_ORIGIN`, the redirect allowlist to contain exactly
that origin plus `/` and `com.mylifegraph.app://login-callback/`, public email
signup with confirmation, a complete custom-SMTP shape (host, port, sender name,
and admin address), and exact Turnstile configuration matching the protected
public site key. The recovery file also records Google client IDs, email
templates, Auth rate limits, and Realtime settings required for rebuild.
Provider secrets, SMTP credentials, Supabase access tokens, and database
passwords are never written to either file.
Security drift is recorded as noncompliant (or unavailable), the encrypted
backup and retention still complete, the heartbeat carries that status, and
the job exits non-zero afterwards so a configuration incident cannot destroy
the 24-hour RPO.

Supabase CLI may report a successful empty `auth,storage` diff without creating
the requested output file. After—and only after—the diff command succeeds, the
runner normalizes that case to a mode-0600 comment-only SQL part. A real diff is
preserved byte-for-byte, while CLI failure, a symlink, or another non-regular
output still fails closed.

The daily run performs a Restic byte restore and checksum verification. The
separate first-of-month schedule and every manual pre-release run additionally
start the committed `mylifegraph-restore-rehearsal` Supabase Postgres target on
ports `56320`–`56329`, with migrations and seed disabled. Only inside that
fresh disposable target, the runner replaces the empty base `auth`/`storage`
schemas with the captured managed foundation, restores the application schema
and trigger-suppressed data, and then installs the deferred managed triggers,
policies, and ACLs. It first neutralizes image-provided creator defaults so
they cannot leak additional privileges onto restored objects; the application
dump then recreates the source's `postgres` defaults and object ACLs. The
historical source boundary is checked before recovery migrations run.

The rehearsal checks every dumped table count, exact migration identities,
Auth/profile orphan counts, forced RLS, current and future client table
privileges, privileged function grants, PostgreSQL-major compatibility, and
the project-bound participation gate. It then advances both the restored
database and an independent migration-built reference to the recovery head.
Raw DDL and ACL statements must match after two explicit normalizations: known optional CamelCase
legacy objects are removed from both disposable targets, and PostgreSQL's
associative-parenthesis formatting is canonicalized only for a reviewed list
of legacy `CHECK` constraints. Catalog postconditions additionally attest
ACL/RLS/RPC semantics and fail closed, including current table authority and
future creator defaults. Any other DDL, ACL, or `CHECK` expression change still
changes the schema digest. The
runner refuses a pre-existing target and deletes only its exact disposable
projects on exit. A failed rehearsal is reported only after the encrypted
backup, repository check, retention, and heartbeat complete, so recovery drift
cannot destroy the backup RPO.

Both the restore target and its independently generated schema-reference target
pin PostgreSQL major 17, matching the hosted pilot generation. The verifier also
requires the source dump and restored database to have the same major; changing
the hosted major therefore requires an explicit compatibility update and a new
restore rehearsal rather than an implicit fallback.

Required protected configuration:

- `PILOT_SUPABASE_PROJECT_REF` (variable);
- `PILOT_PUBLIC_APP_ORIGIN` (protected variable), the exact canonical HTTPS
  origin used by the promoted web app and Supabase Site URL;
- `PILOT_EXPECTED_MIGRATION_HEAD` (variable), set to the exact migration file
  of the currently deployed/attested database boundary. A pre-migration backup
  deliberately keeps the prior value while the checkout may already contain
  the next migration; the actual database must equal that exact repository
  prefix. Update it only after the migration is applied and verified;
- `SUPABASE_ACCESS_TOKEN` (secret) with access to read the pilot project's
  Management API configuration;
- `SUPABASE_DB_URL` (secret or protected variable) without an embedded
  password, using the direct/session-pooler port suitable for logical dumps;
- `SUPABASE_DB_PASSWORD` (secret);
- PostgreSQL `psql` on the protected runner, used only for the read-only exact
  inventory of excluded Vector Storage relations;
- `RESTIC_REPOSITORY`, repository backend credentials, and
  `RESTIC_PASSWORD` (secrets);
- `BACKUP_HEARTBEAT_CURL_CONFIG` (secret) containing a complete curl
  config for the named off-host heartbeat monitor.

The Restic credentials must reach only the `pilot-backup` environment. The
VPS users, application, executor, deployment account, Flutter/Vercel builds,
and professor never receive them. Protect the environment with named backup
owners, no pull-request access from forks, and an exact protected-`main`
deployment-branch rule. No second reviewer account is mandatory; independent
review remains optional evidence. The workflow also checks repository/ref/SHA/
origin-main/clean-tree identity before any secret-bearing step; retain the
GitHub environment/ruleset export as external evidence.
The repository must use an explicitly off-host Restic backend (`s3`, `sftp`,
`rest`, `azure`, `gs`, `b2`, or `rclone`); local paths are rejected. Generated
password and heartbeat-config files must be regular, non-symlink, owner-only
files.

Before enabling the schedule:

1. Select and document the encrypted object-store account, region, retention/
   deletion policy, recovery owner, current price, and billing cap.
2. Initialize the Restic repository once from the protected environment.
3. Run the workflow manually and require `database_restore_status=passed` in
   the snapshot heartbeat and the secret-free restore attestation. The runner
   uses a physically separate disposable Supabase/Postgres target and never the
   normal local stack or a linked project.
4. Apply the deletion-journal replay tool to the isolated restore and prove the
   watermark/postconditions before any restored service is reachable.
   The heartbeat must retain the strict `mylifegraph-restore-evidence-v1`
   summary: whole-attestation hash, schema-reference hash, backup/recovery
   migration heads, and (when applicable) journal-export, source-inventory, and
   replay-set hashes plus entry count. It contains no user/deletion identifiers
   or SQL; configure the off-host monitor to retain this body for release
   evidence.
5. Record RPO 24 hours, target RTO 4 hours, tool versions, snapshot/checksum
   identity, restore duration, and owner in release evidence.

For a Deletion V2 boundary, the restore workflow exports the complete retained
`account-deletion-journal-v2` history through a separate recovery-read identity.
It uses paginated S3 object-version listing and exact versioned GETs, rejects
delete markers/multiple-current versions, wrong KMS identity, non-Compliance
Object Lock, or retention shorter than the recovery cutoff plus four-hour RTO,
and repeats the inventory pass before accepting it. Selection covers every
version written from the backup start through the recovery cutoff plus any
older object whose `prepared`/`appending`/`accepted` deletion identity is
present in the restored `data.sql`; this closes the Put-before-dump,
DB-complete-after-dump crash window without extending unrelated old objects.
The API write credential
is never reused for this step. Replay then runs only as the dedicated
`mylifegraph_deletion_replayer` database role and must produce the bound,
identifier-free watermark after Auth/profile/all-owner-table/Storage absence
checks. Restore verification applies the version-aware role invariant:
PostgreSQL 15 permits no incident membership, while PostgreSQL 16+ permits only
the automatic target-to-migration-creator edge from bootstrap OID 10 with
`ADMIN TRUE`, `SET FALSE`, and `INHERIT FALSE`. It reads version-specific
membership options without making the verifier unparsable on PostgreSQL 15.

Journal objects are retained for 45 days. This exceeds the 35-day protected
pre-migration Restic window by the required seven days and adds the four-hour
RTO margin. Until a real encrypted snapshot, versioned journal export, isolated
database restore, and replay all pass, these backups must not reopen a
participant-facing environment. Byte restoration or repository unit tests
alone are not a recovery rehearsal.
