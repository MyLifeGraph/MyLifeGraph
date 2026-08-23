begin;

-- Recovery replay is intentionally unavailable to every application login.
-- The preceding migration creates this role with exact safe attributes and
-- refuses any unsafe pre-existing role before granting replay. This additive
-- guard deliberately only attests that boundary: Supabase's ordinary postgres
-- migration role is not a true superuser and must never attempt to repair a
-- privileged role by altering its SUPERUSER status.

create function private.account_deletion_replayer_role_safe_v2()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  with target_role as (
    select role.oid
    from pg_catalog.pg_roles as role
    where role.rolname = 'mylifegraph_deletion_replayer'
      and not role.rolcanlogin
      and not role.rolsuper
      and not role.rolcreatedb
      and not role.rolcreaterole
      and not role.rolinherit
      and not role.rolreplication
      and not role.rolbypassrls
      and role.rolconnlimit = 0
      and role.rolconfig is null
  ), incident_memberships as (
    select membership.*, to_jsonb(membership) as membership_facts
    from pg_catalog.pg_auth_members as membership
    join target_role
      on membership.roleid = target_role.oid
      or membership.member = target_role.oid
  )
  select exists (select 1 from target_role)
    and (
      (
        current_setting('server_version_num')::integer < 160000
        and not exists (select 1 from incident_memberships)
      )
      or (
        current_setting('server_version_num')::integer >= 160000
        and 1 = (select count(*) from incident_memberships)
        and exists (
          select 1
          from incident_memberships as membership
          where membership.roleid = (select oid from target_role)
            and membership.member = current_user::regrole
            and membership.grantor = 10
            and membership.admin_option
            and (
              membership.membership_facts ->> 'inherit_option'
            )::boolean is false
            and (
              membership.membership_facts ->> 'set_option'
            )::boolean is false
        )
      )
    )
$$;

revoke all on function private.account_deletion_replayer_role_safe_v2()
  from public, anon, authenticated, service_role,
    mylifegraph_deletion_replayer;

do $$
begin
  if not private.account_deletion_replayer_role_safe_v2() then
    raise exception 'Account deletion replayer role boundary is unsafe.';
  end if;
end;
$$;

comment on function private.account_deletion_replayer_role_safe_v2() is
  'Fail-closed attribute and version-aware membership guard for the restore-only deletion replay role.';

commit;
