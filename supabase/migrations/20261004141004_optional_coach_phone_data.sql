-- Optional Coach-only context; never enters behavioral events or correlations.
alter table public.profiles
  add column coach_phone_data jsonb not null default '{"enabled":false,"revision":0}'::jsonb,
  add column coach_phone_last_request jsonb;

create function private.guard_coach_phone_data_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon', 'authenticated') then
    if (tg_op = 'INSERT' and (new.coach_phone_data <> '{"enabled":false,"revision":0}'::jsonb or new.coach_phone_last_request is not null))
       or (tg_op = 'UPDATE' and (new.coach_phone_data is distinct from old.coach_phone_data or new.coach_phone_last_request is distinct from old.coach_phone_last_request)) then
      raise exception 'Phone sharing is backend-owned.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_coach_phone_data_v1() from public, anon, authenticated;
create trigger guard_coach_phone_data_v1 before insert or update on public.profiles
for each row execute function private.guard_coach_phone_data_v1();

create function public.apply_coach_phone_data_v1(p_user_id uuid, p_request jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  profile public.profiles%rowtype;
  state jsonb;
  operation text := p_request ->> 'command';
  revision bigint := (p_request ->> 'expected_revision')::bigint;
  identity uuid := (p_request ->> 'request_id')::uuid;
  sample jsonb := p_request -> 'data';
  captured timestamptz;
begin
  if p_user_id is null or identity is null or revision is null or revision < 0
     or p_request ->> 'contract_version' is distinct from 'coach-phone-data-v1'
     or operation is null or operation not in ('enable','disable','delete','sync')
     or pg_catalog.octet_length(p_request::text) > 16000 then
    raise exception 'Invalid phone command' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  if (public.get_account_deletion_pending_v2(p_user_id) ->> 'pending')::boolean then
    raise exception 'Account deletion pending' using errcode = '42501';
  end if;
  select * into profile from public.profiles where id = p_user_id for update;
  if not found or profile.onboarding_completed_at is null or profile.auth_provider in ('guest','anonymous') or profile.role = 'guest' then
    raise exception 'Real configured account required' using errcode = '42501';
  end if;
  state := profile.coach_phone_data;
  if profile.coach_phone_last_request ->> 'request_id' = identity::text then
    if profile.coach_phone_last_request <> p_request then
      raise exception 'Request conflict' using errcode = 'PT409';
    end if;
    return jsonb_build_object('timezone',profile.timezone,'coach_phone_data',state);
  end if;
  if (state ->> 'revision')::bigint <> revision then
    raise exception 'Sharing changed' using errcode = 'PT409';
  end if;
  if operation = 'enable' then
    if p_request ->> 'consent_version' is distinct from 'coach-phone-consent-v1' or nullif(p_request ->> 'device_id','') is null then
      raise exception 'Explicit consent required' using errcode = '22023';
    end if;
    perform (p_request ->> 'device_id')::uuid;
    state := jsonb_build_object('enabled',true,'device_id',p_request ->> 'device_id',
      'consent_version','coach-phone-consent-v1','data',null);
  elsif operation in ('disable','delete') then
    state := jsonb_build_object('enabled',false,'device_id',null,'consent_version',null,'data',null);
  else
    captured := (sample ->> 'captured_at')::timestamptz;
    if state ->> 'enabled' is distinct from 'true' or state ->> 'consent_version' is distinct from 'coach-phone-consent-v1'
       or p_request ->> 'device_id' is distinct from state ->> 'device_id'
       or sample ->> 'timezone' is distinct from profile.timezone
       or captured is null or captured < now() - interval '5 minutes' or captured > now() + interval '30 seconds'
       or jsonb_typeof(sample -> 'days') is distinct from 'array' or jsonb_array_length(sample -> 'days') <> 7
       or jsonb_typeof(sample -> 'apps') is distinct from 'array' or jsonb_array_length(sample -> 'apps') > 10 then
      raise exception 'Invalid or revoked phone sample' using errcode = '22023';
    end if;
    state := state || jsonb_build_object('data',sample);
  end if;
  state := state || jsonb_build_object('revision',revision + 1);
  update public.profiles set coach_phone_data=state, coach_phone_last_request=p_request where id=p_user_id;
  return jsonb_build_object('timezone',profile.timezone,'coach_phone_data',state);
end;
$$;
revoke all on function public.apply_coach_phone_data_v1(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.apply_coach_phone_data_v1(uuid,jsonb) to service_role;
grant update(coach_phone_data,coach_phone_last_request) on public.profiles to service_role;
