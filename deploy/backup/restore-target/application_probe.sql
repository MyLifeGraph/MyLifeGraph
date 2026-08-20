\set ON_ERROR_STOP on
begin;

create temporary table restore_probe_users (
  owner_id uuid primary key,
  other_id uuid not null
) on commit drop;

insert into restore_probe_users (owner_id, other_id)
values (gen_random_uuid(), gen_random_uuid());

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  owner_id,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'authenticated',
  'authenticated',
  'restore-probe+' || owner_id::text || '@example.test',
  crypt('restore-probe-password', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
from restore_probe_users
union all
select
  other_id,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'authenticated',
  'authenticated',
  'restore-probe+' || other_id::text || '@example.test',
  crypt('restore-probe-password', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
from restore_probe_users;

select set_config(
  'mylifegraph.restore_owner_id',
  (select owner_id::text from restore_probe_users),
  true
);
select set_config(
  'mylifegraph.restore_other_id',
  (select other_id::text from restore_probe_users),
  true
);

select set_config(
  'mylifegraph.restore_gate_required',
  case
    when to_regclass('private.pilot_participation_gate_v1') is null then 'false'
    else coalesce(
      (
        select participation_required::text
        from private.pilot_participation_gate_v1
        where singleton
      ),
      'missing'
    )
  end,
  true
);

insert into public.daily_logs (user_id, entry_date, mood_score, source)
values (
  current_setting('mylifegraph.restore_owner_id')::uuid,
  date '1900-01-01',
  7,
  'restore-probe'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  current_setting('mylifegraph.restore_owner_id'),
  true
);

do $$
begin
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'restore probe cannot read exactly its own profile';
  end if;
  if current_setting('mylifegraph.restore_gate_required') = 'true'
     and (select count(*) from public.daily_logs) <> 0 then
    raise exception 'unaccepted restore probe bypassed participation RLS';
  end if;
  if current_setting('mylifegraph.restore_gate_required') = 'false'
     and (select count(*) from public.daily_logs) <> 1 then
    raise exception 'disabled restore gate unexpectedly hides owner data';
  end if;
end;
$$;

reset role;

do $$
begin
  if current_setting('mylifegraph.restore_gate_required') = 'true' then
    perform public.accept_pilot_participation_v1(
      current_setting('mylifegraph.restore_owner_id')::uuid,
      'pilot-participation-notice-v1'
    );
  elsif current_setting('mylifegraph.restore_gate_required') = 'missing' then
    raise exception 'restore participation gate singleton is missing';
  end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  current_setting('mylifegraph.restore_owner_id'),
  true
);

do $$
begin
  if not exists (
    select 1 from public.daily_logs where entry_date = date '1900-01-01'
  ) then
    raise exception 'accepted restore probe cannot read owner product data';
  end if;
  if exists (
    select 1
    from public.profiles
    where id = current_setting('mylifegraph.restore_other_id')::uuid
  ) then
    raise exception 'restore probe can read another owner profile';
  end if;
end;
$$;

reset role;
rollback;
