-- Minimal role substrate for restore-verifying a local backup in a physically
-- separate Postgres container. No login, password, or application authority is
-- created; pg_restore uses --no-owner and --no-privileges.

do $$
declare
  role_name text;
begin
  foreach role_name in array array[
    'anon',
    'authenticated',
    'authenticator',
    'dashboard_user',
    'pgbouncer',
    'service_role',
    'supabase_admin',
    'supabase_auth_admin',
    'supabase_read_only_user',
    'supabase_replication_admin',
    'supabase_storage_admin'
  ]
  loop
    if not exists (
      select 1 from pg_roles where rolname = role_name
    ) then
      execute format('create role %I nologin', role_name);
    end if;
  end loop;
end
$$;
