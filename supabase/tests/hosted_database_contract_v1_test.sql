begin;
select no_plan();

select ok(
  has_function_privilege(
    'service_role',
    'public.get_hosted_database_contract_v1(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.get_hosted_database_contract_v1(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_hosted_database_contract_v1(text)',
    'EXECUTE'
  ),
  'only the backend can attest the hosted database boundary'
);

select ok(
  has_table_privilege(
    'service_role', 'public.daily_capture_request_identities', 'SELECT'
  )
  and has_table_privilege(
    'service_role', 'public.daily_capture_request_identities', 'INSERT'
  )
  and not has_table_privilege(
    'service_role', 'public.daily_capture_request_identities', 'UPDATE'
  )
  and not has_table_privilege(
    'service_role', 'public.daily_capture_request_identities', 'DELETE'
  )
  and has_table_privilege(
    'service_role', 'public.account_setting_request_identities', 'SELECT'
  )
  and has_table_privilege(
    'service_role', 'public.account_setting_request_identities', 'INSERT'
  )
  and not has_table_privilege(
    'service_role', 'public.account_setting_request_identities', 'UPDATE'
  )
  and not has_table_privilege(
    'service_role', 'public.account_setting_request_identities', 'DELETE'
  ),
  'hosted retry ledgers converge to their explicit service read/write grants'
);

select ok(
  has_table_privilege(
    'service_role', 'public.learning_request_identities', 'SELECT'
  )
  and has_table_privilege(
    'service_role', 'public.learning_request_identities', 'INSERT'
  )
  and has_table_privilege(
    'service_role', 'public.learning_request_identities', 'DELETE'
  )
  and not has_table_privilege(
    'service_role', 'public.learning_request_identities', 'UPDATE'
  )
  and has_table_privilege(
    'service_role', 'public.lifestyle_entries', 'SELECT'
  )
  and not has_table_privilege(
    'service_role', 'public.lifestyle_entries', 'INSERT'
  )
  and not has_table_privilege(
    'service_role', 'public.lifestyle_entries', 'UPDATE'
  )
  and not has_table_privilege(
    'service_role', 'public.lifestyle_entries', 'DELETE'
  ),
  'learning retry and legacy export tables keep only their owned service grants'
);

select ok(
  has_table_privilege('authenticated', 'public.intake_responses', 'SELECT')
  and not has_table_privilege(
    'authenticated', 'public.intake_responses', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.intake_responses', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.intake_responses', 'DELETE'
  )
  and has_table_privilege(
    'authenticated', 'public.user_state_snapshots', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.user_state_snapshots', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.user_state_snapshots', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.user_state_snapshots', 'DELETE'
  )
  and not has_table_privilege(
    'authenticated', 'public.lifestyle_entries', 'SELECT'
  ),
  'backend-owned Setup projections and lifestyle export are client read-only/hidden'
);

select is(
  (
    select count(*)::bigint
    from pg_catalog.pg_default_acl as defaults
    left join pg_catalog.pg_namespace as namespace
      on namespace.oid = defaults.defaclnamespace
    cross join lateral pg_catalog.aclexplode(defaults.defaclacl) as privilege
    left join pg_catalog.pg_roles as grantee
      on grantee.oid = privilege.grantee
    where defaults.defaclrole = 'postgres'::regrole
      and (defaults.defaclnamespace = 0 or namespace.nspname = 'public')
      and defaults.defaclobjtype in ('r', 'S', 'f')
      and coalesce(grantee.rolname, 'PUBLIC') in (
        'PUBLIC', 'anon', 'authenticated', 'service_role'
      )
  ),
  0::bigint,
  'future postgres public objects have no implicit application-role authority'
);

create table public.hosted_database_contract_default_acl_probe (
  id bigint primary key
);
create sequence public.hosted_database_contract_default_acl_probe_seq;
create function public.hosted_database_contract_default_acl_probe_fn()
returns integer
language sql
as $$
  select 1
$$;

select is(
  (
    select count(*)::bigint
    from (
      values ('anon'), ('authenticated'), ('service_role')
    ) as app_role(role_name)
    cross join (
      values
        ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
        ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
    ) as candidate(privilege_name)
    where has_table_privilege(
      app_role.role_name,
      'public.hosted_database_contract_default_acl_probe',
      candidate.privilege_name
    )
  ),
  0::bigint,
  'a new postgres public table grants no effective application-role privilege'
);

select is(
  (
    select count(*)::bigint
    from (
      values ('anon'), ('authenticated'), ('service_role')
    ) as app_role(role_name)
    cross join (
      values ('USAGE'), ('SELECT'), ('UPDATE')
    ) as candidate(privilege_name)
    where has_sequence_privilege(
      app_role.role_name,
      'public.hosted_database_contract_default_acl_probe_seq',
      candidate.privilege_name
    )
  ),
  0::bigint,
  'a new postgres public sequence grants no effective application-role privilege'
);

select is(
  (
    select count(*)::bigint
    from (
      values ('anon'), ('authenticated'), ('service_role')
    ) as app_role(role_name)
    where has_function_privilege(
      app_role.role_name,
      'public.hosted_database_contract_default_acl_probe_fn()',
      'EXECUTE'
    )
  ),
  0::bigint,
  'a new postgres public function does not inherit PUBLIC or client execute'
);

drop function public.hosted_database_contract_default_acl_probe_fn();
drop sequence public.hosted_database_contract_default_acl_probe_seq;
drop table public.hosted_database_contract_default_acl_probe;

set local role service_role;

select is(
  public.get_hosted_database_contract_v1(
    '20260820200000_account_deletion_replayer_role_guard_v2.sql'
  ),
  jsonb_build_object(
    'contract_version', 'hosted-database-contract-v1',
    'migration_head', '20260820200000_account_deletion_replayer_role_guard_v2.sql',
    'migration_count', 69,
    'migration_identity_sha256',
      'e1c5fe56d8a359f4aa08248e5363a2cdbafd518c09e4046d48ccf1ae7f4f8ff9',
    'prefix_head', '20260820200000_account_deletion_replayer_role_guard_v2.sql',
    'prefix_count', 69,
    'prefix_identity_sha256',
      'e1c5fe56d8a359f4aa08248e5363a2cdbafd518c09e4046d48ccf1ae7f4f8ff9',
    'prepared_deletion_pending_guard', true
  ),
  'the readiness seam derives the complete migration identity and recovery guard'
);

reset role;

delete from supabase_migrations.schema_migrations
where version = '20260820183000';

set local role service_role;

select is(
  public.get_hosted_database_contract_v1(
    '20260820200000_account_deletion_replayer_role_guard_v2.sql'
  ) ->> 'migration_head',
  '20260820200000_account_deletion_replayer_role_guard_v2.sql',
  'removing an intermediate migration does not disguise itself as a new head'
);

select is(
  (public.get_hosted_database_contract_v1(
    '20260820200000_account_deletion_replayer_role_guard_v2.sql'
  ) ->> 'migration_count')::int,
  68,
  'the exact migration count detects a missing intermediate migration'
);

select isnt(
  public.get_hosted_database_contract_v1(
    '20260820200000_account_deletion_replayer_role_guard_v2.sql'
  ) ->> 'migration_identity_sha256',
  'e1c5fe56d8a359f4aa08248e5363a2cdbafd518c09e4046d48ccf1ae7f4f8ff9',
  'the migration identity digest detects a missing intermediate migration'
);

reset role;

create or replace function private.current_request_not_deletion_pending_v2()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
  select auth.uid() is not null
    and not exists (
      select 1
      from public.account_deletion_intents as intent
      where intent.user_id = auth.uid()
        and intent.state in ('appending', 'accepted')
    )
$$;

set local role service_role;

select is(
  (public.get_hosted_database_contract_v1(
    '20260820200000_account_deletion_replayer_role_guard_v2.sql'
  )
    ->> 'prepared_deletion_pending_guard')::boolean,
  false,
  'the recovery guard attestation reflects the installed function semantics'
);

reset role;

select is(
  (
    select proconfig
    from pg_catalog.pg_proc
    where oid = 'public.get_hosted_database_contract_v1(text)'::regprocedure
  ),
  array['search_path=pg_catalog, pg_temp']::text[],
  'the database attestation fixes its security-definer search path'
);

select * from finish();
rollback;
