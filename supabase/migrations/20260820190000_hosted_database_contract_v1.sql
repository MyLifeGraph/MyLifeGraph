-- Expose the exact applied migration boundary through one service-role-only
-- readiness seam. The value is derived from Supabase migration history rather
-- than trusted from the application release that asks for it.

-- Hosted projects and fresh local images can have different creator-default
-- ACLs. Converge the few historical tables whose migrations previously
-- granted an intended subset without first revoking service/authenticated
-- defaults. This makes the effective hosted authority identical to a fresh
-- migration chain before the readiness seam can report success.
revoke all privileges on table
  public.daily_capture_request_identities,
  public.account_setting_request_identities
from public, anon, authenticated, service_role;
grant select, insert on table
  public.daily_capture_request_identities,
  public.account_setting_request_identities
to service_role;

revoke all privileges on table public.learning_request_identities
  from public, anon, authenticated, service_role;
grant select, insert, delete on table public.learning_request_identities
  to service_role;

revoke all privileges on table public.lifestyle_entries
  from public, anon, authenticated, service_role;
grant select on table public.lifestyle_entries to service_role;

revoke all privileges on table
  public.intake_responses,
  public.user_state_snapshots
from public, anon, authenticated, service_role;
grant select on table
  public.intake_responses,
  public.user_state_snapshots
to authenticated;
grant select, insert, update, delete on table
  public.intake_responses,
  public.user_state_snapshots
to service_role;

-- Future repository objects require explicit grants in their owning
-- migration. In particular, no base-image default may expose a new table or
-- function to a client role before its RLS/function contract is installed.
-- PostgreSQL combines global and per-schema defaults. Revoke both layers: a
-- per-schema revoke alone cannot override the built-in global PUBLIC EXECUTE
-- default for functions.
alter default privileges for role postgres
  revoke all privileges on tables
  from public, anon, authenticated, service_role;
alter default privileges for role postgres
  revoke all privileges on sequences
  from public, anon, authenticated, service_role;
alter default privileges for role postgres
  revoke all privileges on functions
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all privileges on tables
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all privileges on functions
  from public, anon, authenticated, service_role;

create function public.get_hosted_database_contract_v1(p_through_head text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  applied_version text;
  applied_name text;
  applied_head text;
  migration_count int;
  migration_identity text;
  migration_identity_sha256 text;
  prefix_count int;
  prefix_identity text;
  prefix_identity_sha256 text;
  history_is_valid boolean;
  prepared_guard boolean;
begin
  if p_through_head !~ '^[0-9]{14}_[a-z0-9_]+\.sql$' then
    raise sqlstate '22023'
      using message = 'Hosted database migration prefix is invalid.';
  end if;
  select
    count(*)::int,
    max(migration.version::text),
    (array_agg(migration.name::text order by migration.version desc))[1],
    string_agg(
      migration.version::text || '_' || migration.name::text || '.sql' || chr(10),
      '' order by migration.version, migration.name
    ),
    bool_and(
      migration.version::text ~ '^[0-9]{14}$'
      and migration.name::text ~ '^[a-z0-9_]+$'
    )
  into
    migration_count,
    applied_version,
    applied_name,
    migration_identity,
    history_is_valid
  from supabase_migrations.schema_migrations as migration;

  if migration_count < 1
     or history_is_valid is not true
     or applied_version !~ '^[0-9]{14}$'
     or applied_name !~ '^[a-z0-9_]+$'
     or migration_identity is null then
    raise sqlstate '55000'
      using message = 'Hosted database migration history is unavailable.';
  end if;

  applied_head := applied_version || '_' || applied_name || '.sql';
  migration_identity_sha256 := encode(
    extensions.digest(convert_to(migration_identity, 'UTF8'), 'sha256'),
    'hex'
  );
  if not exists (
    select 1
    from supabase_migrations.schema_migrations as migration
    where migration.version::text || '_' || migration.name::text || '.sql'
      = p_through_head
  ) then
    raise sqlstate '55000'
      using message = 'Hosted database migration prefix is unavailable.';
  end if;
  select
    count(*)::int,
    string_agg(
      migration.version::text || '_' || migration.name::text || '.sql' || chr(10),
      '' order by migration.version, migration.name
    )
  into prefix_count, prefix_identity
  from supabase_migrations.schema_migrations as migration
  where migration.version::text || '_' || migration.name::text || '.sql'
    <= p_through_head;
  prefix_identity_sha256 := encode(
    extensions.digest(convert_to(prefix_identity, 'UTF8'), 'sha256'),
    'hex'
  );
  prepared_guard :=
    position(
      'intent.state in (''prepared'', ''appending'', ''accepted'')'
      in regexp_replace(
        lower(pg_get_functiondef(
          'private.current_request_not_deletion_pending_v2()'::regprocedure
        )),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ) > 0
    and position(
      'state in (''prepared'', ''appending'', ''accepted'')'
      in regexp_replace(
        lower(pg_get_functiondef(
          'public.get_account_deletion_pending_v2(uuid)'::regprocedure
        )),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ) > 0
    and position(
      'state in (''prepared'', ''appending'', ''accepted'')'
      in regexp_replace(
        lower(pg_get_functiondef(
          'public.get_account_deletion_recovery_status_v2()'::regprocedure
        )),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ) > 0;
  return jsonb_build_object(
    'contract_version', 'hosted-database-contract-v1',
    'migration_head', applied_head,
    'migration_count', migration_count,
    'migration_identity_sha256', migration_identity_sha256,
    'prefix_head', p_through_head,
    'prefix_count', prefix_count,
    'prefix_identity_sha256', prefix_identity_sha256,
    'prepared_deletion_pending_guard', prepared_guard
  );
end;
$$;

revoke all on function public.get_hosted_database_contract_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_hosted_database_contract_v1(text)
  to service_role;

comment on function public.get_hosted_database_contract_v1(text) is
  'Service-role-only exact hosted schema boundary and recovery guard attestation.';
