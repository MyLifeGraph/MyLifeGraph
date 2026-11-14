-- Optional, additive reminders 10h/5h before the existing 48 elapsed-hour grace ends.
-- No historical migration, capture, receipt or streak credit is rewritten.
begin;
alter table private.push_attempts drop constraint push_attempts_kind_check;
alter table private.push_attempts add constraint push_attempts_kind_check
  check (kind in ('sleep','deadlines','pattern','morning','evening','streak_10h','streak_5h'));

-- Resolve the earliest valid instant at/after local midnight, matching Python's
-- two-fold boundary including repeated/skipped midnight and skipped calendar days.
create function private.streak_capture_deadline_v1(p_day date,p_timezone text)
returns timestamptz language sql stable strict security invoker set search_path='' as $$
  with wall as (select (p_day+1)::timestamp as midnight),
  offsets as (
    select distinct ((probe at time zone p_timezone)-(probe at time zone 'UTC')) as value
    from wall cross join lateral generate_series(
      (midnight at time zone p_timezone)-interval '48 hours',
      (midnight at time zone p_timezone)+interval '48 hours',interval '24 hours') probe
  ), candidates as (
    select (midnight-value) at time zone 'UTC' as instant,midnight from wall cross join offsets
  ) select min(instant)+interval '48 hours' from candidates
    where instant at time zone p_timezone >= midnight;
$$;

-- Conservative SQL gate. The worker ALSO reuses the complete strict Capture
-- parser (including projection integrity) before reservation and before sending.
create function private.streak_receipt_pair_v1(p_owner uuid,p_day date,p_zone text,p_now timestamptz)
returns boolean language sql stable security invoker set search_path='' as $$
  select count(distinct r.branch)=2 from public.daily_capture_request_identities r
  join public.daily_logs d on d.id=r.result_daily_log_id and d.user_id=r.user_id and d.entry_date=r.entry_date
  where r.user_id=p_owner and r.entry_date=p_day
    and r.created_at<=least(p_now,private.streak_capture_deadline_v1(p_day,p_zone))
    and jsonb_typeof(d.metadata #> array['captures',r.branch])='object';
$$;

create function private.streak_push_window_v1(p_owner uuid,p_kind text,p_now timestamptz)
returns table(entry_date date,dedupe_key text,expires_at timestamptz)
language sql stable security invoker set search_path='' as $$
  with profile as (select timezone from public.profiles where id=p_owner
    and push_settings->>'enabled'='true' and push_settings->>'streak'='true'
    and push_settings->>'consent_version'='android-push-consent-v1'),
  days as (select timezone,(p_now at time zone timezone)::date-i as day
    from profile cross join generate_series(0,4) i),
  windows as (select timezone,day,private.streak_capture_deadline_v1(day,timezone)-
    case p_kind when 'streak_10h' then interval '10 hours' when 'streak_5h' then interval '5 hours' end as starts
    from days)
  select day,'streak:'||day::text||case p_kind when 'streak_10h' then ':10h' else ':5h' end,
    starts+interval '15 minutes' from windows
  where p_kind in ('streak_10h','streak_5h') and p_now>=starts and p_now<starts+interval '15 minutes'
    and private.streak_receipt_pair_v1(p_owner,day-1,timezone,p_now)
    and not private.streak_receipt_pair_v1(p_owner,day,timezone,p_now)
  order by day limit 1;
$$;

create function public.get_streak_push_candidates_v1(p_user_id uuid,p_timezone text,p_revision bigint)
returns jsonb language sql stable security invoker set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind',k.kind,'dedupe_key',w.dedupe_key,
      'expires_at',w.expires_at)), '[]'::jsonb)
  from public.profiles p cross join (values('streak_10h'),('streak_5h')) k(kind)
  cross join lateral private.streak_push_window_v1(p.id,k.kind,now()) w
  where p.id=p_user_id and p.timezone=p_timezone and (p.push_settings->>'revision')::bigint=p_revision
    and p.onboarding_completed_at is not null and p.role<>'guest' and p.auth_provider not in ('guest','anonymous')
    and not (public.get_account_deletion_pending_v2(p.id)->>'pending')::boolean;
$$;


create or replace function public.get_push_state_v1(p_user_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('contract_version','android-push-v1','settings',jsonb_build_object('streak',false)||p.push_settings,
    'timezone',p.timezone,'device_id',d.device_id,'registration_id',d.registration_id)
  from public.profiles p left join private.push_devices d on d.user_id=p.id
  where p.id=p_user_id;
$$;

create or replace function public.apply_push_command_v1(p_user_id uuid,p_session_id uuid,p_request jsonb) returns jsonb
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
    if p_request ? 'streak' then
      if jsonb_typeof(p_request->'streak') is distinct from 'boolean' then
        raise exception 'Explicit streak preference required.' using errcode='22023';
      end if;
      settings := settings || jsonb_build_object('streak',p_request->'streak');
    end if;
    -- Older clients omit all four keys: preserve this extension.
    if (p_request->>'morning') is not null or (p_request->>'evening') is not null
      or (p_request->>'morning_time') is not null or (p_request->>'evening_time') is not null then
      if jsonb_typeof(p_request->'morning') is distinct from 'boolean'
        or jsonb_typeof(p_request->'evening') is distinct from 'boolean'
        or coalesce(p_request->>'morning_time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(p_request->>'evening_time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Complete check-in settings required.' using errcode='22023';
      end if;
      settings := settings || jsonb_build_object('morning',p_request->'morning',
        'evening',p_request->'evening','morning_time',p_request->>'morning_time',
        'evening_time',p_request->>'evening_time');
    end if;
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

create function private.reserve_streak_push_at_v1(p_user_id uuid,p_kind text,p_key text,p_timezone text,
  p_revision bigint,p_expires_at timestamptz,p_now timestamptz) returns jsonb
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
  if p_kind is null or p_kind not in ('streak_10h','streak_5h') or p_key is null
    or length(p_key)>100 or p_expires_at is null or p_expires_at<=p_now
    or p_expires_at>p_now+interval '15 minutes' then return null; end if;
  if settings->>('streak') is distinct from 'true' then return null; end if;
  select * into device from private.push_devices where user_id=p_user_id;
  if not found or not private.push_session_active_v1(p_user_id,device.session_id) then return null; end if;
  local_now := p_now at time zone profile.timezone;
  quiet_start := (settings->>'quiet_start')::time;
  quiet_end := (settings->>'quiet_end')::time;
  if quiet_start=quiet_end or (quiet_start<quiet_end and local_now::time>=quiet_start and local_now::time<quiet_end)
    or (quiet_start>quiet_end and (local_now::time>=quiet_start or local_now::time<quiet_end)) then return null; end if;
  if not exists(select 1 from private.streak_push_window_v1(p_user_id,p_kind,p_now) w
      where w.dedupe_key=p_key and w.expires_at=p_expires_at) then return null; end if;
  if (select count(*) from private.push_attempts where user_id=p_user_id
      and kind in ('streak_10h','streak_5h') and created_at>=p_now-interval '24 hours')>=2 then return null; end if;
  insert into private.push_attempts(user_id,dedupe_key,kind,local_date,expires_at,created_at)
  values(p_user_id,p_key,p_kind,local_now::date,p_expires_at,p_now)
  on conflict(user_id,dedupe_key) do nothing returning id into attempt_id;
  if attempt_id is null then return null; end if;
  return jsonb_build_object('attempt_id',attempt_id,'token',device.token,'device_id',device.device_id,
    'registration_id',device.registration_id,'session_id',device.session_id);
end $$;

create or replace function public.reserve_push_v1(p_user_id uuid,p_kind text,p_key text,p_timezone text,
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
  if p_kind in ('streak_10h','streak_5h') then
    return private.reserve_streak_push_at_v1(p_user_id,p_kind,p_key,p_timezone,p_revision,p_expires_at,clock_timestamp());
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  select * into profile from public.profiles where id=p_user_id for update;
  if not found then return null; end if;
  settings := profile.push_settings;
  if settings->>'enabled' is distinct from 'true'
    or settings->>'consent_version' is distinct from 'android-push-consent-v1'
    or (settings->>'revision')::bigint <> p_revision or profile.timezone<>p_timezone
    or (public.get_account_deletion_pending_v2(p_user_id)->>'pending')::boolean then return null; end if;
  if p_kind is null or p_kind not in ('sleep','deadlines','pattern','morning','evening') or p_key is null
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
  if p_kind in ('morning','evening') and (
    p_key <> p_kind || ':' || local_now::date::text
    or not private.checkin_push_due_v1(p_user_id,p_kind,local_now)) then return null; end if;
  -- Independent rolling caps: two optional check-ins and two existing reminders.
  -- Neither timezone changes nor preference toggles replenish either budget.
  if (select count(*) from private.push_attempts where user_id=p_user_id and
       created_at>=clock_timestamp()-interval '24 hours'
       and kind not in ('streak_10h','streak_5h')
       and (kind in ('morning','evening')) = (p_kind in ('morning','evening'))) >=2 then return null; end if;
  if p_kind='pattern' and exists(select 1 from private.push_attempts where user_id=p_user_id
    and kind='pattern' and created_at>clock_timestamp()-interval '30 days') then return null; end if;
  insert into private.push_attempts(user_id,dedupe_key,kind,local_date,expires_at)
  values(p_user_id,p_key,p_kind,local_now::date,p_expires_at)
  on conflict(user_id,dedupe_key) do nothing returning id into attempt_id;
  if attempt_id is null then return null; end if;
  return jsonb_build_object('attempt_id',attempt_id,'token',device.token,'device_id',device.device_id,
    'registration_id',device.registration_id,'session_id',device.session_id);
end $$;

create function private.check_push_reservation_at_v1(p_user_id uuid,p_attempt_id uuid,
  p_registration_id uuid,p_revision bigint,p_timezone text,p_now timestamptz) returns boolean
language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from private.push_attempts a
    join public.profiles p on p.id=a.user_id
    join private.push_devices d on d.user_id=p.id
    where a.user_id=p_user_id and a.id=p_attempt_id and a.status='reserved'
      and (a.kind not in ('morning','evening') or (
        a.local_date=(p_now at time zone p.timezone)::date
        and private.checkin_push_due_v1(p.id,a.kind,p_now at time zone p.timezone)))
      and (a.kind not in ('streak_10h','streak_5h') or exists(
        select 1 from private.streak_push_window_v1(p_user_id,a.kind,p_now) w
        where w.dedupe_key=a.dedupe_key and w.expires_at=a.expires_at))
      and a.expires_at>p_now and d.registration_id=p_registration_id
      and p.timezone=p_timezone and (p.push_settings->>'revision')::bigint=p_revision
      and p.push_settings->>'enabled'='true'
      and p.push_settings->>'consent_version'='android-push-consent-v1'
      and p.push_settings->>(case when a.kind in ('streak_10h','streak_5h') then 'streak' when a.kind='pattern' then 'patterns' else a.kind end)='true'
      and private.push_session_active_v1(p.id,d.session_id)
      and not (public.get_account_deletion_pending_v2(p.id)->>'pending')::boolean
      and case when (p.push_settings->>'quiet_start')::time < (p.push_settings->>'quiet_end')::time
        then not ((p_now at time zone p.timezone)::time >= (p.push_settings->>'quiet_start')::time
          and (p_now at time zone p.timezone)::time < (p.push_settings->>'quiet_end')::time)
        else (p_now at time zone p.timezone)::time < (p.push_settings->>'quiet_start')::time
          and (p_now at time zone p.timezone)::time >= (p.push_settings->>'quiet_end')::time end
  );
$$;

create or replace function public.check_push_reservation_v1(p_user_id uuid,p_attempt_id uuid,
  p_registration_id uuid,p_revision bigint,p_timezone text) returns boolean
language sql stable security invoker set search_path='' as $$
  select private.check_push_reservation_at_v1(p_user_id,p_attempt_id,p_registration_id,p_revision,p_timezone,now());
$$;



-- Private helpers are not Data API endpoints. Preserve old public function OIDs/ACLs.
revoke all on function private.streak_capture_deadline_v1(date,text) from public,anon,authenticated;
grant execute on function private.streak_capture_deadline_v1(date,text) to service_role;
revoke all on function private.streak_receipt_pair_v1(uuid,date,text,timestamptz) from public,anon,authenticated;
grant execute on function private.streak_receipt_pair_v1(uuid,date,text,timestamptz) to service_role;
revoke all on function private.streak_push_window_v1(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function private.streak_push_window_v1(uuid,text,timestamptz) to service_role;
revoke all on function private.reserve_streak_push_at_v1(uuid,text,text,text,bigint,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function private.reserve_streak_push_at_v1(uuid,text,text,text,bigint,timestamptz,timestamptz) to service_role;
revoke all on function private.check_push_reservation_at_v1(uuid,uuid,uuid,bigint,text,timestamptz) from public,anon,authenticated;
grant execute on function private.check_push_reservation_at_v1(uuid,uuid,uuid,bigint,text,timestamptz) to service_role;
revoke all on function public.get_streak_push_candidates_v1(uuid,text,bigint) from public,anon,authenticated;
grant execute on function public.get_streak_push_candidates_v1(uuid,text,bigint) to service_role;


commit;
