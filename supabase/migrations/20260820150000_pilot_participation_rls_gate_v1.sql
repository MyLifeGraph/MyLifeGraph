-- Public-pilot participation is enforced at the database boundary as well as
-- in Flutter and FastAPI. The gate is disabled by default so disposable local
-- databases keep their existing development semantics. A hosted release is
-- not ready until the service-role-only configuration command binds the gate
-- to that exact Supabase project.

create table private.pilot_participation_gate_v1 (
  singleton boolean primary key default true check (singleton),
  project_ref text,
  participation_required boolean not null default false,
  notice_version text,
  updated_at timestamptz not null default now(),
  constraint pilot_participation_gate_v1_shape check (
    (
      not participation_required
      and project_ref is null
      and notice_version is null
    )
    or
    (
      participation_required
      and project_ref ~ '^[a-z]{20}$'
      and notice_version = 'pilot-participation-notice-v1'
    )
  )
);

revoke all on table private.pilot_participation_gate_v1
  from public, anon, authenticated, service_role;

insert into private.pilot_participation_gate_v1 (
  singleton,
  project_ref,
  participation_required,
  notice_version
) values (true, null, false, null);

create function private.current_request_has_pilot_participation_v1()
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, private, public, pg_temp
set row_security = off
as $$
declare
  gate_required boolean;
begin
  select gate.participation_required
  into gate_required
  from private.pilot_participation_gate_v1 as gate
  where gate.singleton;

  -- A missing singleton is configuration corruption and therefore fails
  -- closed. The explicit false state is the only development bypass.
  if gate_required is false then
    return true;
  end if;
  if gate_required is distinct from true or auth.uid() is null then
    return false;
  end if;

  return exists (
    select 1
    from public.profiles as profile
    where profile.id = auth.uid()
      and profile.pilot_participation_notice_version =
        'pilot-participation-notice-v1'
      and profile.pilot_participation_accepted_at is not null
  );
end;
$$;
revoke all on function private.current_request_has_pilot_participation_v1()
  from public, anon, service_role;
grant execute on function private.current_request_has_pilot_participation_v1()
  to authenticated;

create function public.configure_pilot_participation_gate_v1(
  p_project_ref text,
  p_required boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public, pg_temp
as $$
declare
  configured private.pilot_participation_gate_v1%rowtype;
begin
  if p_required is null then
    raise sqlstate '22023' using message = 'A required state is required.';
  end if;
  if p_required and (
    p_project_ref is null
    or p_project_ref !~ '^[a-z]{20}$'
  ) then
    raise sqlstate '22023' using message = 'An exact project ref is required.';
  end if;
  if not p_required and p_project_ref is not null then
    raise sqlstate '22023'
      using message = 'A disabled gate cannot retain a project ref.';
  end if;

  update private.pilot_participation_gate_v1
  set
    project_ref = p_project_ref,
    participation_required = p_required,
    notice_version = case
      when p_required then 'pilot-participation-notice-v1'
      else null
    end,
    updated_at = clock_timestamp()
  where singleton
  returning * into configured;

  if not found then
    raise sqlstate '55000'
      using message = 'Pilot participation gate configuration is unavailable.';
  end if;

  return jsonb_build_object(
    'contract_version', 'pilot-participation-gate-v1',
    'project_ref', configured.project_ref,
    'participation_required', configured.participation_required,
    'notice_version', configured.notice_version
  );
end;
$$;

revoke all on function public.configure_pilot_participation_gate_v1(text, boolean)
  from public, anon, authenticated;
grant execute on function public.configure_pilot_participation_gate_v1(text, boolean)
  to service_role;

create function public.get_pilot_participation_gate_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, private, public, pg_temp
as $$
  select jsonb_build_object(
    'contract_version', 'pilot-participation-gate-v1',
    'project_ref', gate.project_ref,
    'participation_required', gate.participation_required,
    'notice_version', gate.notice_version
  )
  from private.pilot_participation_gate_v1 as gate
  where gate.singleton
$$;

revoke all on function public.get_pilot_participation_gate_v1()
  from public, anon, authenticated;
grant execute on function public.get_pilot_participation_gate_v1()
  to service_role;

-- Restrictive policies compose with every existing owner policy. Tables that
-- are not granted to authenticated remain inaccessible as before. Profiles
-- keep only SELECT available before acceptance so the client can discover the
-- persisted participation state and render the notice; all profile mutations
-- are gated as product writes.
do $$
declare
  relation record;
begin
  for relation in
    select namespace.nspname as schema_name, class.relname as table_name
    from pg_catalog.pg_class as class
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relkind in ('r', 'p')
      and class.relrowsecurity
  loop
    if relation.table_name = 'profiles' then
      execute format(
        'create policy pilot_participation_profile_insert_v1 on %I.%I as restrictive for insert to authenticated with check ((select private.current_request_has_pilot_participation_v1()))',
        relation.schema_name,
        relation.table_name
      );
      execute format(
        'create policy pilot_participation_profile_update_v1 on %I.%I as restrictive for update to authenticated using ((select private.current_request_has_pilot_participation_v1())) with check ((select private.current_request_has_pilot_participation_v1()))',
        relation.schema_name,
        relation.table_name
      );
      execute format(
        'create policy pilot_participation_profile_delete_v1 on %I.%I as restrictive for delete to authenticated using ((select private.current_request_has_pilot_participation_v1()))',
        relation.schema_name,
        relation.table_name
      );
    else
      execute format(
        'create policy pilot_participation_required_v1 on %I.%I as restrictive for all to authenticated using ((select private.current_request_has_pilot_participation_v1())) with check ((select private.current_request_has_pilot_participation_v1()))',
        relation.schema_name,
        relation.table_name
      );
    end if;
  end loop;
end;
$$;
