\set ON_ERROR_STOP on

-- A disposable Supabase base image can carry creator defaults that differ
-- from the hosted source.  Clear only the postgres/public defaults before
-- restoring application objects; the schema dump later recreates the exact
-- source defaults and every object-level ACL.
alter default privileges for role postgres in schema public
  revoke all on tables from public, postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from public, postgres, anon, authenticated, service_role;
