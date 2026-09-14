-- Optional account consent; measurements stay in the existing owner observation
-- stream, never in canonical manual daily_logs / quick_check_in projections.
alter table public.profiles
  add column health_connect_settings jsonb not null default '{"enabled":false,"revision":0}'::jsonb,
  add column health_connect_last_request jsonb;

create function private.guard_health_connect_profile_v1()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon', 'authenticated') and (
    new.health_connect_settings is distinct from old.health_connect_settings
    or new.health_connect_last_request is distinct from old.health_connect_last_request
  ) then
    raise exception 'Health Connect settings are backend-owned.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_health_connect_profile_v1() from public, anon, authenticated;
create trigger guard_health_connect_profile_v1 before update on public.profiles
for each row execute function private.guard_health_connect_profile_v1();

create unique index behavioral_events_health_connect_day_idx
on public.behavioral_events (user_id, event_type, (metadata ->> 'date'))
where source = 'health_connect';

create function public.apply_health_connect_v1(p_user_id uuid, p_request jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  profile public.profiles%rowtype;
  state jsonb;
  operation text := p_request ->> 'command';
  request_id uuid := (p_request ->> 'request_id')::uuid;
  expected_revision bigint := (p_request ->> 'expected_revision')::bigint;
  day_value jsonb;
  metric text;
  local_today date;
  observed_date date;
  observed_value numeric;
  observed_at timestamptz;
  captured_at timestamptz;
  day_start timestamptz;
  day_end timestamptz;
  metadata_value jsonb;
begin
  if p_user_id is null or request_id is null or expected_revision is null
     or expected_revision < 0 or p_request ->> 'contract_version' is distinct from 'health-connect-v1'
     or operation is null or operation not in ('connect', 'disconnect', 'delete_data', 'sync')
     or pg_catalog.octet_length(p_request::text) > 32000 then
    raise exception 'Invalid Health Connect command.' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  if (public.get_account_deletion_pending_v2(p_user_id) ->> 'pending')::boolean then
    raise exception 'Account deletion is pending.' using errcode = '42501';
  end if;
  select * into profile from public.profiles where id = p_user_id for update;
  if not found or profile.onboarding_completed_at is null
     or profile.auth_provider in ('guest', 'anonymous') or profile.role = 'guest' then
    raise exception 'A real configured account is required.' using errcode = '42501';
  end if;
  state := profile.health_connect_settings;
  -- Exact replay only. A delayed older request must reload, never re-enable consent.
  if profile.health_connect_last_request ->> 'request_id' = request_id::text then
    if profile.health_connect_last_request <> p_request then
      raise exception 'Request identity conflict.' using errcode = 'PT409';
    end if;
    return jsonb_build_object('timezone', profile.timezone, 'health_connect_settings', state);
  end if;
  if (state ->> 'revision')::bigint <> expected_revision then
    raise exception 'Health Connect revision changed.' using errcode = 'PT409';
  end if;

  if operation = 'connect' then
    if p_request ->> 'consent_version' is distinct from 'health-connect-cloud-consent-v1'
       or nullif(p_request ->> 'device_id', '') is null then
      raise exception 'Explicit cloud consent and device are required.' using errcode = '22023';
    end if;
    perform (p_request ->> 'device_id')::uuid;
    state := state || jsonb_build_object(
      'enabled', true, 'device_id', p_request ->> 'device_id',
      'consent_version', 'health-connect-cloud-consent-v1', 'consented_at', now()
    );
  elsif operation in ('disconnect', 'delete_data') then
    state := state || jsonb_build_object('enabled', false, 'device_id', null);
    if operation = 'delete_data' then
      delete from public.behavioral_events where user_id = p_user_id and source = 'health_connect';
      state := state || jsonb_build_object('last_synced_at', null);
    end if;
  else
    captured_at := (p_request ->> 'captured_at')::timestamptz;
    if state ->> 'enabled' is distinct from 'true'
       or state ->> 'consent_version' is distinct from 'health-connect-cloud-consent-v1'
       or p_request ->> 'device_id' is distinct from state ->> 'device_id'
       or p_request ->> 'timezone' is distinct from profile.timezone
       or captured_at is null or captured_at < now() - interval '5 minutes'
       or captured_at > now() + interval '30 seconds'
       or jsonb_typeof(p_request -> 'days') is distinct from 'array'
       or jsonb_array_length(p_request -> 'days') <> 7 then
      raise exception 'Health Connect consent or sync window is invalid.' using errcode = '22023';
    end if;
    local_today := (captured_at at time zone profile.timezone)::date;
    if (select count(distinct value ->> 'date') from jsonb_array_elements(p_request -> 'days')) <> 7 then
      raise exception 'Duplicate observation dates.' using errcode = '22023';
    end if;
    for day_value in select value from jsonb_array_elements(p_request -> 'days') loop
      observed_date := (day_value ->> 'date')::date;
      if observed_date is null or observed_date < local_today - 6 or observed_date > local_today then
        raise exception 'Observation date is outside the sync window.' using errcode = '22023';
      end if;
      day_start := observed_date::timestamp at time zone profile.timezone;
      day_end := least((observed_date + 1)::timestamp at time zone profile.timezone, captured_at);
      observed_at := day_end - interval '1 microsecond';
      foreach metric in array array['steps', 'sleep_minutes'] loop
        observed_value := (day_value ->> metric)::numeric;
        if observed_value is null then
          -- An authoritative missing result clears only this imported metric,
          -- never a manual observation, and is not fabricated as zero.
          delete from public.behavioral_events where user_id = p_user_id
            and source = 'health_connect' and event_type = 'health_connect_' || metric
            and metadata ->> 'date' = observed_date::text;
          continue;
        end if;
        if observed_value < 0 or observed_value::text in ('NaN', 'Infinity', '-Infinity')
           or (metric = 'steps' and (observed_value > 200000 or observed_value <> trunc(observed_value)))
           or (metric = 'sleep_minutes' and observed_value > extract(epoch from day_end - day_start) / 60) then
          raise exception 'Invalid observation value.' using errcode = '22023';
        end if;
        metadata_value := jsonb_build_object(
          'date', observed_date, 'timezone', profile.timezone,
          'window_start', day_start, 'window_end', day_end,
          'sources', day_value -> case when metric = 'steps' then 'steps_sources' else 'sleep_sources' end,
          'aggregation', 'health_connect_daily_total', 'synced_at', now(),
          'consent_version', 'health-connect-cloud-consent-v1'
        );
        insert into public.behavioral_events(user_id, event_type, value, unit, occurred_at, source, metadata)
        values (p_user_id, 'health_connect_' || metric, observed_value,
          case when metric = 'steps' then 'steps' else 'minutes' end,
          observed_at, 'health_connect', metadata_value)
        on conflict (user_id, event_type, (metadata ->> 'date')) where source = 'health_connect'
        do update set value = excluded.value, occurred_at = excluded.occurred_at, metadata = excluded.metadata;
      end loop;
    end loop;
    state := state || jsonb_build_object('last_synced_at', now());
  end if;
  state := state || jsonb_build_object('revision', expected_revision + 1);
  update public.profiles set health_connect_settings = state,
    health_connect_last_request = p_request where id = p_user_id;
  return jsonb_build_object('timezone', profile.timezone, 'health_connect_settings', state);
end;
$$;
revoke all on function public.apply_health_connect_v1(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.apply_health_connect_v1(uuid, jsonb) to service_role;
grant update(health_connect_settings, health_connect_last_request) on public.profiles to service_role;
