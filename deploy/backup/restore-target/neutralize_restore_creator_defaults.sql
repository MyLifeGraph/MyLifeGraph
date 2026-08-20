\set ON_ERROR_STOP on

-- pg_dump creates objects as the connected restore role before assigning
-- their recorded owner.  Remove the disposable image's Supabase-admin
-- defaults so those transient creator privileges cannot leak onto restored or
-- reference application objects.
alter default privileges for role supabase_admin in schema public
  revoke all on tables from public, postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public
  revoke all on sequences from public, postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public
  revoke all on functions from public, postgres, anon, authenticated, service_role;
