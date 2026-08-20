-- Restore-safe account deletion. The database records only a UUID identity,
-- journal object identity/hash, and timestamps; it never stores email or
-- product content in this recovery ledger. The off-host append happens between
-- prepare and accept. Once accepted, restrictive RLS blocks the account until
-- the owner-locked V1 deletion converges.

create table public.account_deletion_intents (
  deletion_id uuid primary key,
  user_id uuid not null unique,
  contract_version text not null default 'account-deletion-v2'
    check (contract_version = 'account-deletion-v2'),
  state text not null default 'prepared'
    check (state in ('prepared', 'appending', 'accepted', 'completed')),
  accepted_at timestamptz not null,
  journal_object_key text,
  journal_payload_sha256 text,
  journaled_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null,
  constraint account_deletion_intents_state_shape check (
    (
      state in ('prepared', 'appending')
      and journal_object_key is null
      and journal_payload_sha256 is null
      and journaled_at is null
      and completed_at is null
    )
    or
    (
      state = 'accepted'
      and journal_object_key is not null
      and journal_payload_sha256 ~ '^[0-9a-f]{64}$'
      and journaled_at is not null
      and completed_at is null
    )
    or
    (
      state = 'completed'
      and journal_object_key is not null
      and journal_payload_sha256 ~ '^[0-9a-f]{64}$'
      and journaled_at is not null
      and completed_at is not null
    )
  ),
  constraint account_deletion_intents_time_order check (
    updated_at >= accepted_at
    and (journaled_at is null or journaled_at >= accepted_at)
    and (completed_at is null or completed_at >= journaled_at)
  )
);

comment on table public.account_deletion_intents is
  'Service-only minimal restore ledger; external encrypted append authority remains off-host.';

create index account_deletion_intents_pending_idx
  on public.account_deletion_intents (state, accepted_at, deletion_id)
  where state in ('prepared', 'appending', 'accepted');

alter table public.account_deletion_intents enable row level security;
alter table public.account_deletion_intents force row level security;
revoke all on table public.account_deletion_intents
  from public, anon, authenticated, service_role;

create policy pilot_participation_required_v1
  on public.account_deletion_intents
  as restrictive
  for all
  to authenticated
  using ((select private.current_request_has_pilot_participation_v1()))
  with check ((select private.current_request_has_pilot_participation_v1()));

create function private.current_request_not_deletion_pending_v2()
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

revoke all on function private.current_request_not_deletion_pending_v2()
  from public, anon, service_role;
grant execute on function private.current_request_not_deletion_pending_v2()
  to authenticated;

create function private.account_deletion_intent_json_v2(
  p_intent public.account_deletion_intents,
  p_replayed boolean
)
returns jsonb
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'contract_version', p_intent.contract_version,
    'deletion_id', p_intent.deletion_id,
    'user_id', p_intent.user_id,
    'state', p_intent.state,
    'accepted_at', p_intent.accepted_at,
    'journal_object_key', p_intent.journal_object_key,
    'journal_payload_sha256', p_intent.journal_payload_sha256,
    'completed_at', p_intent.completed_at,
    'replayed', p_replayed
  )
$$;

revoke all on function private.account_deletion_intent_json_v2(
  public.account_deletion_intents,
  boolean
) from public, anon, authenticated, service_role;

-- A rolled-back V1 application must fail closed after this migration instead
-- of deleting an account without the off-host journal sequence. V2 definer
-- functions retain owner authority to call the implementation internally.
revoke all on function public.delete_account_v1(uuid, text)
  from public, anon, authenticated, service_role;

create function public.prepare_account_deletion_v2(
  p_user_id uuid,
  p_deletion_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  intent public.account_deletion_intents%rowtype;
  accepted_at_value timestamptz;
begin
  if p_user_id is null
     or p_deletion_id is null
     or p_confirmation is distinct from 'DELETE' then
    raise sqlstate '22023'
      using message = 'Exact account deletion identity and confirmation are required.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select * into intent
  from public.account_deletion_intents
  where user_id = p_user_id
  for update;

  if found then
    if intent.deletion_id is distinct from p_deletion_id then
      raise sqlstate 'PT409'
        using message = 'A different account deletion is already recorded.';
    end if;
    return private.account_deletion_intent_json_v2(intent, true);
  end if;

  perform 1 from auth.users where id = p_user_id for update;
  if not found then
    raise sqlstate 'PT404' using message = 'Account is unavailable.';
  end if;
  accepted_at_value := date_trunc('second', clock_timestamp());
  insert into public.account_deletion_intents (
    deletion_id,
    user_id,
    state,
    accepted_at,
    updated_at
  ) values (
    p_deletion_id,
    p_user_id,
    'prepared',
    accepted_at_value,
    accepted_at_value
  ) returning * into intent;

  return private.account_deletion_intent_json_v2(intent, false);
end;
$$;

create function public.mark_account_deletion_appending_v2(
  p_user_id uuid,
  p_deletion_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  intent public.account_deletion_intents%rowtype;
begin
  if p_user_id is null or p_deletion_id is null then
    raise sqlstate '22023' using message = 'Deletion append identity is invalid.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select * into intent
  from public.account_deletion_intents
  where deletion_id = p_deletion_id and user_id = p_user_id
  for update;
  if not found then
    raise sqlstate 'PT404' using message = 'Deletion intent is unavailable.';
  end if;
  if intent.state <> 'prepared' then
    return private.account_deletion_intent_json_v2(intent, true);
  end if;
  update public.account_deletion_intents
  set state = 'appending', updated_at = greatest(updated_at, clock_timestamp())
  where deletion_id = p_deletion_id
  returning * into intent;
  return private.account_deletion_intent_json_v2(intent, false);
end;
$$;

create function public.accept_account_deletion_journal_v2(
  p_user_id uuid,
  p_deletion_id uuid,
  p_accepted_at timestamptz,
  p_journal_object_key text,
  p_journal_payload_sha256 text,
  p_journaled_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  intent public.account_deletion_intents%rowtype;
  expected_object_key text;
begin
  if p_user_id is null
     or p_deletion_id is null
     or p_accepted_at is null
     or p_journaled_at is null
     or p_journaled_at < p_accepted_at
     or p_journal_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise sqlstate '22023' using message = 'Deletion journal receipt is invalid.';
  end if;
  expected_object_key := format(
    'deletions/v2/%s/%s/%s.json',
    to_char(p_accepted_at at time zone 'UTC', 'YYYY/MM'),
    p_deletion_id,
    p_journal_payload_sha256
  );
  if p_journal_object_key is distinct from expected_object_key then
    raise sqlstate '22023' using message = 'Deletion journal object key is invalid.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select * into intent
  from public.account_deletion_intents
  where deletion_id = p_deletion_id and user_id = p_user_id
  for update;
  if not found then
    raise sqlstate 'PT404' using message = 'Deletion intent is unavailable.';
  end if;
  if intent.accepted_at is distinct from p_accepted_at then
    raise sqlstate 'PT409' using message = 'Deletion acceptance identity changed.';
  end if;
  if intent.state in ('accepted', 'completed') then
    if intent.journal_object_key is distinct from p_journal_object_key
       or intent.journal_payload_sha256 is distinct from p_journal_payload_sha256 then
      raise sqlstate 'PT409' using message = 'Deletion journal receipt changed.';
    end if;
    return private.account_deletion_intent_json_v2(intent, true);
  end if;
  if intent.state <> 'appending' then
    raise sqlstate '55000' using message = 'Deletion append was not started.';
  end if;

  update public.account_deletion_intents
  set
    state = 'accepted',
    journal_object_key = p_journal_object_key,
    journal_payload_sha256 = p_journal_payload_sha256,
    journaled_at = p_journaled_at,
    updated_at = greatest(updated_at, p_journaled_at)
  where deletion_id = p_deletion_id
  returning * into intent;
  return private.account_deletion_intent_json_v2(intent, false);
end;
$$;

create function public.complete_account_deletion_v2(
  p_user_id uuid,
  p_deletion_id uuid,
  p_confirmation text,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  intent public.account_deletion_intents%rowtype;
  deletion_result jsonb;
begin
  if p_user_id is null
     or p_deletion_id is null
     or p_confirmation is distinct from 'DELETE'
     or p_completed_at is null then
    raise sqlstate '22023' using message = 'Account deletion completion is invalid.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select * into intent
  from public.account_deletion_intents
  where deletion_id = p_deletion_id and user_id = p_user_id
  for update;
  if not found then
    raise sqlstate 'PT404' using message = 'Deletion intent is unavailable.';
  end if;
  if intent.state = 'completed' then
    return private.account_deletion_intent_json_v2(intent, true);
  end if;
  if intent.state <> 'accepted' or p_completed_at < intent.journaled_at then
    raise sqlstate '55000' using message = 'Deletion journal is not accepted.';
  end if;

  deletion_result := public.delete_account_v1(p_user_id, p_confirmation);
  if not (
    (deletion_result ->> 'deleted')::boolean
    or (deletion_result ->> 'not_found')::boolean
  ) then
    raise sqlstate 'P0001' using message = 'Account deletion did not converge.';
  end if;
  update public.account_deletion_intents
  set
    state = 'completed',
    completed_at = p_completed_at,
    updated_at = greatest(updated_at, p_completed_at)
  where deletion_id = p_deletion_id
  returning * into intent;
  return private.account_deletion_intent_json_v2(intent, false);
end;
$$;

create function public.replay_account_deletion_v2(
  p_user_id uuid,
  p_deletion_id uuid,
  p_accepted_at timestamptz,
  p_journal_object_key text,
  p_journal_payload_sha256 text,
  p_replayed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  intent public.account_deletion_intents%rowtype;
  expected_object_key text;
begin
  if p_user_id is null
     or p_deletion_id is null
     or p_accepted_at is null
     or p_replayed_at is null
     or p_replayed_at < p_accepted_at
     or p_journal_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise sqlstate '22023' using message = 'Deletion replay envelope is invalid.';
  end if;
  expected_object_key := format(
    'deletions/v2/%s/%s/%s.json',
    to_char(p_accepted_at at time zone 'UTC', 'YYYY/MM'),
    p_deletion_id,
    p_journal_payload_sha256
  );
  if p_journal_object_key is distinct from expected_object_key then
    raise sqlstate '22023' using message = 'Deletion replay object key is invalid.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select * into intent
  from public.account_deletion_intents
  where user_id = p_user_id
  for update;
  if found and intent.deletion_id is distinct from p_deletion_id then
    raise sqlstate 'PT409' using message = 'Deletion replay identity conflicts.';
  end if;
  if not found then
    insert into public.account_deletion_intents (
      deletion_id,
      user_id,
      state,
      accepted_at,
      journal_object_key,
      journal_payload_sha256,
      journaled_at,
      updated_at
    ) values (
      p_deletion_id,
      p_user_id,
      'accepted',
      p_accepted_at,
      p_journal_object_key,
      p_journal_payload_sha256,
      p_accepted_at,
      p_accepted_at
    ) returning * into intent;
  elsif intent.state in ('prepared', 'appending') then
    if intent.accepted_at is distinct from p_accepted_at then
      raise sqlstate 'PT409' using message = 'Deletion replay time conflicts.';
    end if;
    update public.account_deletion_intents
    set
      state = 'accepted',
      journal_object_key = p_journal_object_key,
      journal_payload_sha256 = p_journal_payload_sha256,
      journaled_at = p_accepted_at,
      updated_at = greatest(updated_at, p_accepted_at)
    where deletion_id = p_deletion_id
    returning * into intent;
  elsif intent.journal_object_key is distinct from p_journal_object_key
     or intent.journal_payload_sha256 is distinct from p_journal_payload_sha256
     or intent.accepted_at is distinct from p_accepted_at then
    raise sqlstate 'PT409' using message = 'Deletion replay receipt conflicts.';
  end if;

  if intent.state = 'completed' then
    return private.account_deletion_intent_json_v2(intent, true);
  end if;
  return public.complete_account_deletion_v2(
    p_user_id,
    p_deletion_id,
    'DELETE',
    p_replayed_at
  );
end;
$$;

do $$
declare
  target_role_oid oid;
  incident_membership_count bigint;
  allowed_membership_count bigint;
  server_version_number integer :=
    current_setting('server_version_num')::integer;
begin
  -- PostgreSQL 16+ always grants a role created by a non-superuser
  -- CREATEROLE principal back to that creator with ADMIN TRUE. Keep the
  -- optional SET/INHERIT self-grants disabled in this transaction; the
  -- unavoidable ADMIN-only edge is attested below.
  if server_version_number >= 160000 then
    perform pg_catalog.set_config('createrole_self_grant', '', true);
  end if;

  if not exists (
    select 1 from pg_catalog.pg_roles
    where rolname = 'mylifegraph_deletion_replayer'
  ) then
    create role mylifegraph_deletion_replayer with
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls
      connection limit 0;
  end if;

  -- Supabase's postgres migration role is intentionally not a true
  -- superuser. It can create an unprivileged role, but it cannot safely strip
  -- SUPERUSER from a hostile pre-existing role. Refuse drift before the first
  -- replay grant instead of attempting a privileged repair.
  if not exists (
    select 1
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
  ) then
    raise insufficient_privilege using message =
      'Account deletion replayer role has unsafe attributes.';
  end if;

  select role.oid into strict target_role_oid
  from pg_catalog.pg_roles as role
  where role.rolname = 'mylifegraph_deletion_replayer';

  select
    count(*),
    count(*) filter (
      where membership.roleid = target_role_oid
        and membership.member = current_user::regrole
        and membership.grantor = 10
        and membership.admin_option
        -- PostgreSQL 15 does not expose these PG16+ catalog columns. Reading
        -- the catalog row through JSON keeps the migration parseable there.
        and (to_jsonb(membership) ->> 'inherit_option')::boolean is false
        and (to_jsonb(membership) ->> 'set_option')::boolean is false
    )
  into incident_membership_count, allowed_membership_count
  from pg_catalog.pg_auth_members as membership
  where membership.roleid = target_role_oid
     or membership.member = target_role_oid;

  if (
    server_version_number < 160000
    and incident_membership_count <> 0
  ) or (
    server_version_number >= 160000
    and (
      incident_membership_count <> 1
      or allowed_membership_count <> 1
    )
  ) then
    raise insufficient_privilege using message =
      'Account deletion replayer role has unsafe memberships.';
  end if;
end;
$$;

revoke all on function public.replay_account_deletion_v2(
  uuid, uuid, timestamptz, text, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.replay_account_deletion_v2(
  uuid, uuid, timestamptz, text, text, timestamptz
) to mylifegraph_deletion_replayer;

create function public.list_pending_account_deletions_v2(p_limit int)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  intents jsonb;
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise sqlstate '22023' using message = 'Pending deletion limit is invalid.';
  end if;
  select coalesce(
    jsonb_agg(
      private.account_deletion_intent_json_v2(intent, true)
      order by intent.accepted_at, intent.deletion_id
    ),
    '[]'::jsonb
  ) into intents
  from (
    select *
    from public.account_deletion_intents
    where state in ('prepared', 'appending', 'accepted')
    order by accepted_at, deletion_id
    limit p_limit
  ) as intent;
  return jsonb_build_object(
    'contract_version', 'account-deletion-reconcile-v2',
    'intents', intents
  );
end;
$$;

create function public.get_account_deletion_pending_v2(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
  select jsonb_build_object(
    'contract_version', 'account-deletion-pending-v2',
    'pending', exists (
      select 1 from public.account_deletion_intents
      where user_id = p_user_id and state in ('appending', 'accepted')
    )
  )
$$;

create function public.get_account_deletion_intent_v2(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
declare
  intent public.account_deletion_intents%rowtype;
begin
  if p_user_id is null then
    raise sqlstate '22023' using message = 'Deletion status owner is invalid.';
  end if;
  select * into intent
  from public.account_deletion_intents
  where user_id = p_user_id;
  return jsonb_build_object(
    'contract_version', 'account-deletion-status-v2',
    'intent', case
      when found then private.account_deletion_intent_json_v2(intent, true)
      else null
    end
  );
end;
$$;

create function public.get_account_deletion_recovery_status_v2()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
  select jsonb_build_object(
    'contract_version', 'account-deletion-recovery-v2',
    'legacy_direct_delete_revoked', not has_function_privilege(
      'service_role',
      'public.delete_account_v1(uuid,text)',
      'EXECUTE'
    ),
    'pending_count', count(*)::bigint,
    'oldest_pending_at', min(accepted_at)
  )
  from public.account_deletion_intents
  where state in ('appending', 'accepted')
$$;

do $$
declare
  signature regprocedure;
begin
  foreach signature in array array[
    'public.prepare_account_deletion_v2(uuid,uuid,text)'::regprocedure,
    'public.mark_account_deletion_appending_v2(uuid,uuid)'::regprocedure,
    'public.accept_account_deletion_journal_v2(uuid,uuid,timestamptz,text,text,timestamptz)'::regprocedure,
    'public.complete_account_deletion_v2(uuid,uuid,text,timestamptz)'::regprocedure,
    'public.list_pending_account_deletions_v2(int)'::regprocedure,
    'public.get_account_deletion_pending_v2(uuid)'::regprocedure,
    'public.get_account_deletion_intent_v2(uuid)'::regprocedure,
    'public.get_account_deletion_recovery_status_v2()'::regprocedure
  ] loop
    execute format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      signature
    );
    execute format('grant execute on function %s to service_role', signature);
  end loop;
end;
$$;

-- Once the backend begins the possibly ambiguous off-host append, the account
-- is blocked at the Data API until append and deletion converge. A merely
-- prepared identity remains readable during the synchronous handoff. Existing
-- permissive owner policies remain necessary; this restrictive policy only
-- removes access.
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
    execute format(
      'create policy account_deletion_not_pending_v2 on %I.%I as restrictive for all to authenticated using ((select private.current_request_not_deletion_pending_v2())) with check ((select private.current_request_not_deletion_pending_v2()))',
      relation.schema_name,
      relation.table_name
    );
  end loop;
end;
$$;
