-- Additive Android push. Existing foreground notification contracts are untouched.
alter table public.profiles add column push_settings jsonb not null default
  '{"enabled":false,"revision":0,"sleep":true,"deadlines":true,"patterns":true,"quiet_start":"22:00","quiet_end":"07:00"}'::jsonb;

create table private.push_devices (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  device_id uuid not null,
  registration_id uuid not null,
  session_id uuid not null,
  token text not null unique check (length(token) between 20 and 4096),
  updated_at timestamptz not null default now()
);
create table private.push_requests (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  request_id uuid not null,
  fingerprint text not null
);
create table private.push_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  dedupe_key text not null check (length(dedupe_key) <= 100),
  kind text not null check (kind in ('sleep','deadlines','pattern')),
  local_date date not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'reserved' check (status in ('reserved','accepted','failed')),
  unique(user_id, dedupe_key)
);
create index push_attempts_owner_time_idx on private.push_attempts(user_id,created_at desc);
alter table private.push_devices enable row level security;
alter table private.push_devices force row level security;
alter table private.push_requests enable row level security;
alter table private.push_requests force row level security;
alter table private.push_attempts enable row level security;
alter table private.push_attempts force row level security;
revoke all on private.push_devices,private.push_requests,private.push_attempts from public,anon,authenticated;
grant usage on schema private to service_role;
grant select,insert,update,delete on private.push_devices,private.push_requests,private.push_attempts to service_role;

create function private.guard_push_profile_v1() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if current_user in ('anon','authenticated') and new.push_settings is distinct from old.push_settings then
    raise exception 'Push settings are backend-owned.' using errcode='42501';
  end if;
  return new;
end $$;
create trigger guard_push_profile_v1 before update on public.profiles
for each row execute function private.guard_push_profile_v1();

-- This narrow definer reads Auth session metadata without granting the API role
-- general SELECT on auth.sessions. Only service_role may execute it.
create function private.push_session_active_v1(p_owner uuid,p_session uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from auth.sessions s where s.id=p_session and s.user_id=p_owner
    and (s.not_after is null or s.not_after > now()));
$$;
revoke all on function private.push_session_active_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function private.push_session_active_v1(uuid,uuid) to service_role;

create function public.get_push_state_v1(p_user_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('contract_version','android-push-v1','settings',p.push_settings,
    'timezone',p.timezone,'device_id',d.device_id,'registration_id',d.registration_id)
  from public.profiles p left join private.push_devices d on d.user_id=p.id
  where p.id=p_user_id;
$$;

create function public.apply_push_command_v1(p_user_id uuid,p_session_id uuid,p_request jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
  profile public.profiles%rowtype;
  previous private.push_requests%rowtype;
  settings jsonb;
  command text := p_request->>'command';
  request_id uuid := (p_request->>'request_id')::uuid;
  fingerprint text := encode(extensions.digest(p_request::text || p_session_id::text,'sha256'),'hex');
  clock_value text;
begin
  if request_id is null or p_user_id is null or p_session_id is null
    or p_request->>'contract_version' is distinct from 'android-push-v1'
    or command is null or command not in ('settings','register','unregister')
    or octet_length(p_request::text)>8192 then
    raise exception 'Invalid push command.' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  if not private.push_session_active_v1(p_user_id,p_session_id)
    or (public.get_account_deletion_pending_v2(p_user_id)->>'pending')::boolean then
    raise exception 'Account session unavailable.' using errcode='42501';
  end if;
  select * into profile from public.profiles where id=p_user_id for update;
  if not found or profile.onboarding_completed_at is null or profile.role='guest'
    or profile.auth_provider in ('guest','anonymous') then
    raise exception 'Real configured account required.' using errcode='42501';
  end if;
  select * into previous from private.push_requests where user_id=p_user_id;
  if previous.request_id=request_id then
    if previous.fingerprint is distinct from fingerprint then
      raise exception 'Push request identity conflict.' using errcode='PT409';
    end if;
    return public.get_push_state_v1(p_user_id);
  end if;
  settings := profile.push_settings;
  if p_request->>'expected_revision' is null or
    (p_request->>'expected_revision')::bigint <> (settings->>'revision')::bigint then
    raise exception 'Push settings changed. Reload.' using errcode='PT409';
  end if;
  if command='settings' then
    if p_request->>'consent_version' is distinct from 'android-push-consent-v1'
      or jsonb_typeof(p_request->'enabled') is distinct from 'boolean'
      or jsonb_typeof(p_request->'sleep') is distinct from 'boolean'
      or jsonb_typeof(p_request->'deadlines') is distinct from 'boolean'
      or jsonb_typeof(p_request->'patterns') is distinct from 'boolean' then
      raise exception 'Explicit push settings required.' using errcode='22023';
    end if;
    foreach clock_value in array array[p_request->>'quiet_start',p_request->>'quiet_end'] loop
      if clock_value is null or clock_value !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Invalid quiet hours.' using errcode='22023';
      end if;
    end loop;
    settings := settings || jsonb_build_object('enabled',p_request->'enabled',
      'sleep',p_request->'sleep','deadlines',p_request->'deadlines','patterns',p_request->'patterns',
      'quiet_start',p_request->>'quiet_start','quiet_end',p_request->>'quiet_end',
      'consent_version','android-push-consent-v1','consented_at',now());
    if settings->>'enabled'='false' then delete from private.push_devices where user_id=p_user_id; end if;
  elsif command='register' then
    if settings->>'enabled' is distinct from 'true'
      or settings->>'consent_version' is distinct from 'android-push-consent-v1'
      or p_request->>'device_id' is null or p_request->>'registration_id' is null
      or p_request->>'token' is null or length(p_request->>'token') not between 20 and 4096 then
      raise exception 'Push consent and device required.' using errcode='22023';
    end if;
    insert into private.push_devices(user_id,device_id,registration_id,session_id,token)
    values(p_user_id,(p_request->>'device_id')::uuid,(p_request->>'registration_id')::uuid,p_session_id,p_request->>'token')
    on conflict(user_id) do update set device_id=excluded.device_id,registration_id=excluded.registration_id,
      session_id=excluded.session_id,token=excluded.token,updated_at=now();
  else
    delete from private.push_devices where user_id=p_user_id
      and device_id=(p_request->>'device_id')::uuid and session_id=p_session_id;
  end if;
  settings := settings || jsonb_build_object('revision',(settings->>'revision')::bigint+1);
  update public.profiles set push_settings=settings where id=p_user_id;
  insert into private.push_requests values(p_user_id,request_id,fingerprint)
  on conflict(user_id) do update set request_id=excluded.request_id,fingerprint=excluded.fingerprint;
  return public.get_push_state_v1(p_user_id);
end $$;

-- The server scans a bounded, keyset-paged list. This function never generates data.
create function public.list_push_owners_v1(p_after uuid default null) returns jsonb
language sql stable security invoker set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(candidate)), '[]'::jsonb) from (
    select p.id,p.timezone,p.push_settings from public.profiles p
    join private.push_devices d on d.user_id=p.id
    where p.push_settings->>'enabled'='true'
      and (p_after is null or p.id>p_after)
      and private.push_session_active_v1(p.id,d.session_id)
      and not (public.get_account_deletion_pending_v2(p.id)->>'pending')::boolean
    order by p.id limit 25
  ) candidate;
$$;

create function public.reserve_push_v1(p_user_id uuid,p_kind text,p_key text,p_timezone text,
  p_revision bigint,p_expires_at timestamptz) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
  profile public.profiles%rowtype;
  device private.push_devices%rowtype;
  settings jsonb;
  local_now timestamp;
  quiet_start time;
  quiet_end time;
  attempt_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  select * into profile from public.profiles where id=p_user_id for update;
  if not found then return null; end if;
  settings := profile.push_settings;
  if settings->>'enabled' is distinct from 'true'
    or settings->>'consent_version' is distinct from 'android-push-consent-v1'
    or (settings->>'revision')::bigint <> p_revision or profile.timezone<>p_timezone
    or (public.get_account_deletion_pending_v2(p_user_id)->>'pending')::boolean then return null; end if;
  if p_kind is null or p_kind not in ('sleep','deadlines','pattern') or p_key is null
    or length(p_key)>100 or p_expires_at is null or p_expires_at<=clock_timestamp()
    or p_expires_at>clock_timestamp()+interval '15 minutes' then return null; end if;
  if settings->>(case when p_kind='pattern' then 'patterns' else p_kind end) is distinct from 'true' then return null; end if;
  select * into device from private.push_devices where user_id=p_user_id;
  if not found or not private.push_session_active_v1(p_user_id,device.session_id) then return null; end if;
  local_now := clock_timestamp() at time zone profile.timezone;
  quiet_start := (settings->>'quiet_start')::time;
  quiet_end := (settings->>'quiet_end')::time;
  if quiet_start=quiet_end or (quiet_start<quiet_end and local_now::time>=quiet_start and local_now::time<quiet_end)
    or (quiet_start>quiet_end and (local_now::time>=quiet_start or local_now::time<quiet_end)) then return null; end if;
  -- A rolling cap cannot be replenished by a timezone change.
  if (select count(*) from private.push_attempts where user_id=p_user_id and
       created_at>=clock_timestamp()-interval '24 hours') >=2 then return null; end if;
  if p_kind='pattern' and exists(select 1 from private.push_attempts where user_id=p_user_id
    and kind='pattern' and created_at>clock_timestamp()-interval '30 days') then return null; end if;
  insert into private.push_attempts(user_id,dedupe_key,kind,local_date,expires_at)
  values(p_user_id,p_key,p_kind,local_now::date,p_expires_at)
  on conflict(user_id,dedupe_key) do nothing returning id into attempt_id;
  if attempt_id is null then return null; end if;
  return jsonb_build_object('attempt_id',attempt_id,'token',device.token,'device_id',device.device_id,
    'registration_id',device.registration_id,'session_id',device.session_id);
end $$;

-- Read-only last-moment recheck. A message already handed to FCM cannot be
-- recalled; Android independently rejects expired and mismatched-session data.
create function public.check_push_reservation_v1(p_user_id uuid,p_attempt_id uuid,
  p_registration_id uuid,p_revision bigint,p_timezone text) returns boolean
language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from private.push_attempts a
    join public.profiles p on p.id=a.user_id
    join private.push_devices d on d.user_id=p.id
    where a.user_id=p_user_id and a.id=p_attempt_id and a.status='reserved'
      and a.expires_at>now() and d.registration_id=p_registration_id
      and p.timezone=p_timezone and (p.push_settings->>'revision')::bigint=p_revision
      and p.push_settings->>'enabled'='true'
      and p.push_settings->>'consent_version'='android-push-consent-v1'
      and p.push_settings->>(case when a.kind='pattern' then 'patterns' else a.kind end)='true'
      and private.push_session_active_v1(p.id,d.session_id)
      and not (public.get_account_deletion_pending_v2(p.id)->>'pending')::boolean
      and case when (p.push_settings->>'quiet_start')::time < (p.push_settings->>'quiet_end')::time
        then not ((now() at time zone p.timezone)::time >= (p.push_settings->>'quiet_start')::time
          and (now() at time zone p.timezone)::time < (p.push_settings->>'quiet_end')::time)
        else (now() at time zone p.timezone)::time < (p.push_settings->>'quiet_start')::time
          and (now() at time zone p.timezone)::time >= (p.push_settings->>'quiet_end')::time end
  );
$$;

create function public.finish_push_v1(p_user_id uuid,p_attempt_id uuid,p_accepted boolean,
  p_invalid_token text default null) returns void language plpgsql security invoker set search_path='' as $$
begin
  update private.push_attempts set status=case when p_accepted then 'accepted' else 'failed' end
  where id=p_attempt_id and user_id=p_user_id and status='reserved';
  if p_invalid_token is not null then
    delete from private.push_devices where user_id=p_user_id and token=p_invalid_token;
  end if;
end $$;

revoke all on function public.get_push_state_v1(uuid),public.apply_push_command_v1(uuid,uuid,jsonb),
  public.list_push_owners_v1(uuid),public.reserve_push_v1(uuid,text,text,text,bigint,timestamptz),
  public.check_push_reservation_v1(uuid,uuid,uuid,bigint,text),
  public.finish_push_v1(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.get_push_state_v1(uuid),public.apply_push_command_v1(uuid,uuid,jsonb),
  public.list_push_owners_v1(uuid),public.reserve_push_v1(uuid,text,text,text,bigint,timestamptz),
  public.check_push_reservation_v1(uuid,uuid,uuid,bigint,text),
  public.finish_push_v1(uuid,uuid,boolean,text) to service_role;
