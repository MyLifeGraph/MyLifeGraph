-- Daily Capture V5 removes day_shape from new Morning branches while keeping
-- complete V4 branch writes available during the client rollout. The existing
-- retry ledger, owner lock order, conflict checks, projections, and grants stay
-- unchanged.

create or replace function public.apply_daily_capture_branch_v1(
  p_user_id uuid,
  p_entry_date date,
  p_branch text,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_capture jsonb,
  p_capture jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  existing_request public.daily_capture_request_identities%rowtype;
  target_log public.daily_logs%rowtype;
  current_capture jsonb;
  next_metadata jsonb;
  next_captures jsonb;
  stored_capture jsonb;
  next_capture_version text;
  next_evening jsonb;
  next_morning jsonb;
  next_mood int;
  next_energy int;
  next_stress int;
  next_sleep numeric;
  next_reflection text;
  next_updated_at timestamptz;
  event_kind text;
  event_value numeric;
  event_unit text;
  event_capture jsonb;
  event_id uuid;
  log_hex text;
begin
  if p_user_id is null
     or p_entry_date is null
     or p_branch not in ('morning', 'evening')
     or p_request_id is null
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_now is null
     or p_capture is null
     or jsonb_typeof(p_capture) <> 'object'
     or p_capture ->> 'capture_kind' is distinct from p_branch
     or p_capture ->> 'entry_date' is distinct from p_entry_date::text
     or coalesce(p_capture ->> 'branch_version', '')
          not in ('daily-capture-v4', 'daily-capture-v5')
     or (
       p_branch = 'morning'
       and p_capture ->> 'branch_version' = 'daily-capture-v5'
       and p_capture ? 'day_shape'
     )
     or length(trim(coalesce(p_capture ->> 'capture_id', ''))) not between 1 and 160
     or nullif(p_capture ->> 'captured_at', '') is null
     or (
       p_expected_capture is not null
       and (
         jsonb_typeof(p_expected_capture) <> 'object'
         or length(trim(coalesce(p_expected_capture ->> 'capture_id', '')))
              not between 1 and 160
         or nullif(p_expected_capture ->> 'captured_at', '') is null
       )
     ) then
    raise exception 'Daily Capture request is invalid.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select *
  into existing_request
  from public.daily_capture_request_identities
  where request_id = p_request_id
  for update;

  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.entry_date <> p_entry_date
       or existing_request.branch <> p_branch
       or existing_request.request_fingerprint <> p_request_fingerprint then
      raise exception 'Daily Capture request id was already used.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'contract_version', 'daily-capture-write-v1',
      'entry_date', existing_request.entry_date,
      'branch', existing_request.branch,
      'capture_id', existing_request.capture_id,
      'captured_at', existing_request.captured_at,
      'updated_at', existing_request.result_updated_at,
      'replayed', true
    );
  end if;

  select *
  into target_log
  from public.daily_logs
  where user_id = p_user_id and entry_date = p_entry_date
  for update;

  if found then
    current_capture := target_log.metadata -> 'captures' -> p_branch;
  else
    current_capture := null;
  end if;

  if (
       p_expected_capture is null
       and current_capture is not null
     )
     or (
       p_expected_capture is not null
       and (
         current_capture is null
         or current_capture ->> 'capture_id'
              is distinct from p_expected_capture ->> 'capture_id'
         or (current_capture ->> 'captured_at')::timestamptz
              is distinct from
                (p_expected_capture ->> 'captured_at')::timestamptz
       )
     ) then
    raise exception 'Daily Capture branch changed. Reload before saving.'
      using errcode = 'PT409';
  end if;

  if not found then
    insert into public.daily_logs (
      user_id,
      entry_date,
      source,
      metadata,
      created_at,
      updated_at
    ) values (
      p_user_id,
      p_entry_date,
      'quick_check_in',
      '{}'::jsonb,
      p_now,
      p_now
    )
    returning * into target_log;
  end if;

  next_capture_version := case
    when target_log.metadata ->> 'capture_version' = 'daily-capture-v5'
      or p_capture ->> 'branch_version' = 'daily-capture-v5'
      then 'daily-capture-v5'
    else 'daily-capture-v4'
  end;
  next_captures := case
    when jsonb_typeof(target_log.metadata -> 'captures') = 'object'
      then target_log.metadata -> 'captures'
    else '{}'::jsonb
  end;
  stored_capture := p_capture;
  if next_capture_version = 'daily-capture-v5'
     and p_capture ->> 'branch_version' <> 'daily-capture-v5' then
    stored_capture := p_capture || jsonb_build_object('compatibility', true);
  else
    stored_capture := stored_capture - 'compatibility';
  end if;
  next_captures := jsonb_set(
    next_captures,
    array[p_branch],
    stored_capture,
    true
  );
  if next_captures -> 'evening' is not null
     and next_captures -> 'evening' ->> 'branch_version'
          is distinct from next_capture_version then
    next_captures := jsonb_set(
      next_captures,
      '{evening,compatibility}',
      'true'::jsonb,
      true
    );
  end if;
  if next_captures -> 'morning' is not null
     and next_captures -> 'morning' ->> 'branch_version'
          is distinct from next_capture_version then
    next_captures := jsonb_set(
      next_captures,
      '{morning,compatibility}',
      'true'::jsonb,
      true
    );
  end if;
  next_metadata := jsonb_set(
    coalesce(target_log.metadata, '{}'::jsonb)
      || jsonb_build_object('capture_version', next_capture_version),
    '{captures}',
    next_captures,
    true
  );
  next_evening := next_metadata -> 'captures' -> 'evening';
  next_morning := next_metadata -> 'captures' -> 'morning';
  next_mood := nullif(next_evening ->> 'mood', '')::int;
  next_energy := coalesce(
    nullif(next_morning ->> 'current_energy', '')::int,
    nullif(next_evening ->> 'energy', '')::int
  );
  next_stress := nullif(next_evening ->> 'stress_intensity', '')::int;
  next_sleep := nullif(next_morning ->> 'sleep_hours', '')::numeric;
  next_reflection := nullif(trim(coalesce(
    next_evening ->> 'reflection_note',
    ''
  )), '');
  next_updated_at := greatest(
    target_log.updated_at,
    p_now,
    (p_capture ->> 'captured_at')::timestamptz
  );

  update public.daily_logs
  set sleep_hours = next_sleep,
      energy_level = next_energy,
      stress_level = next_stress,
      mood_score = next_mood,
      mood_label = case
        when next_mood is null then null
        when next_mood >= 9 then 'great'
        when next_mood >= 7 then 'good'
        when next_mood >= 5 then 'neutral'
        when next_mood >= 3 then 'low'
        else 'very_low'
      end,
      reflection = next_reflection,
      source = 'quick_check_in',
      metadata = next_metadata,
      updated_at = next_updated_at
  where id = target_log.id;

  delete from public.behavioral_events
  where daily_log_id = target_log.id
    and source = 'quick_check_in';

  log_hex := replace(target_log.id::text, '-', '');
  foreach event_kind in array array['mood', 'energy', 'stress', 'sleep']
  loop
    event_value := case event_kind
      when 'mood' then next_mood
      when 'energy' then next_energy
      when 'stress' then next_stress
      else next_sleep
    end;
    continue when event_value is null;
    event_unit := case event_kind
      when 'sleep' then 'hours'
      else 'score_0_10'
    end;
    event_capture := case
      when event_kind in ('mood', 'stress') then next_evening
      when event_kind in ('energy', 'sleep') and next_morning is not null
        then next_morning
      else next_evening
    end;
    event_id := (
      substr(log_hex, 1, 8) || '-' ||
      substr(log_hex, 9, 4) || '-' ||
      substr(log_hex, 13, 4) || '-' ||
      substr(log_hex, 17, 4) || '-' ||
      substr(log_hex, 21, 4) ||
      case event_kind
        when 'mood' then '6d6f6f64'
        when 'energy' then '656e6572'
        when 'stress' then '73747273'
        else '736c6570'
      end
    )::uuid;

    insert into public.behavioral_events (
      id,
      user_id,
      daily_log_id,
      event_type,
      value,
      unit,
      occurred_at,
      source,
      metadata,
      created_at
    ) values (
      event_id,
      p_user_id,
      target_log.id,
      event_kind,
      event_value,
      event_unit,
      (event_capture ->> 'captured_at')::timestamptz,
      'quick_check_in',
      jsonb_build_object(
        'capture_version', next_capture_version,
        'entry_date', p_entry_date,
        'capture_kind', event_capture ->> 'capture_kind',
        'capture_id', event_capture ->> 'capture_id',
        'captured_at', event_capture ->> 'captured_at'
      ),
      next_updated_at
    );
  end loop;

  insert into public.daily_capture_request_identities (
    request_id,
    user_id,
    entry_date,
    branch,
    request_fingerprint,
    capture_id,
    captured_at,
    result_daily_log_id,
    result_updated_at,
    created_at
  ) values (
    p_request_id,
    p_user_id,
    p_entry_date,
    p_branch,
    p_request_fingerprint,
    p_capture ->> 'capture_id',
    (p_capture ->> 'captured_at')::timestamptz,
    target_log.id,
    next_updated_at,
    p_now
  );

  return jsonb_build_object(
    'contract_version', 'daily-capture-write-v1',
    'entry_date', p_entry_date,
    'branch', p_branch,
    'capture_id', p_capture ->> 'capture_id',
    'captured_at', p_capture ->> 'captured_at',
    'updated_at', next_updated_at,
    'replayed', false
  );
end;
$$;

revoke all on function public.apply_daily_capture_branch_v1(
  uuid, date, text, uuid, text, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_daily_capture_branch_v1(
  uuid, date, text, uuid, text, jsonb, jsonb, timestamptz
) to service_role;
