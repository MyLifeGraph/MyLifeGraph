-- Stabilization after the whole-product review: retry-safe Capture and account
-- writes, timezone-bound planning projections, and application write guards.

alter table public.profiles
  add column if not exists timezone_revision int not null default 1,
  add column if not exists preparation_budget_revision int not null default 1;

alter table public.profiles
  add constraint profiles_timezone_revision_positive_check
    check (timezone_revision between 1 and 2147483647),
  add constraint profiles_preparation_budget_revision_positive_check
    check (preparation_budget_revision between 1 and 2147483647);

create table public.daily_capture_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  entry_date date not null,
  branch text not null,
  request_fingerprint text not null,
  capture_id text not null,
  captured_at timestamptz not null,
  result_daily_log_id uuid not null references public.daily_logs (id)
    on delete cascade,
  result_updated_at timestamptz not null,
  created_at timestamptz not null,
  constraint daily_capture_request_branch_check
    check (branch in ('morning', 'evening')),
  constraint daily_capture_request_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint daily_capture_request_capture_id_check
    check (length(trim(capture_id)) between 1 and 160),
  constraint daily_capture_request_result_order_check
    check (captured_at <= result_updated_at)
);

create index daily_capture_requests_user_date_idx
  on public.daily_capture_request_identities
    (user_id, entry_date desc, created_at desc);

alter table public.daily_capture_request_identities enable row level security;
alter table public.daily_capture_request_identities force row level security;
revoke all on table public.daily_capture_request_identities
  from public, anon, authenticated;
grant select, insert on table public.daily_capture_request_identities
  to service_role;

create policy "daily_capture_requests_service_role_all"
  on public.daily_capture_request_identities
  for all
  to service_role
  using (true)
  with check (true);

create table public.account_setting_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  operation text not null,
  request_fingerprint text not null,
  expected_revision int not null,
  result_revision int not null,
  result_value jsonb not null,
  result_updated_at timestamptz not null,
  created_at timestamptz not null,
  constraint account_setting_requests_operation_check check (
    operation in ('timezone', 'preparation_budget')
  ),
  constraint account_setting_requests_fingerprint_check check (
    request_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint account_setting_requests_revision_check check (
    expected_revision >= 1 and result_revision = expected_revision + 1
  ),
  constraint account_setting_requests_result_check check (
    jsonb_typeof(result_value) = 'object'
  )
);

create index account_setting_requests_user_created_idx
  on public.account_setting_request_identities (user_id, created_at desc);

alter table public.account_setting_request_identities enable row level security;
alter table public.account_setting_request_identities force row level security;
revoke all on table public.account_setting_request_identities
  from public, anon, authenticated;
grant select, insert on table public.account_setting_request_identities
  to service_role;

create policy "account_setting_requests_service_role_all"
  on public.account_setting_request_identities
  for all
  to service_role
  using (true)
  with check (true);

-- Capture and its derived events are now one backend-owned transaction.
revoke insert, update, delete on table public.daily_logs
  from anon, authenticated;
revoke insert, update, delete on table public.behavioral_events
  from anon, authenticated;
grant select on table public.daily_logs, public.behavioral_events
  to authenticated;

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
     or p_capture ->> 'branch_version' is distinct from 'daily-capture-v4'
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

  -- Match the owner-before-row lock order used by other owner workflows.
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

  next_metadata :=
    jsonb_set(
      jsonb_set(
        coalesce(target_log.metadata, '{}'::jsonb)
          || jsonb_build_object('capture_version', 'daily-capture-v4'),
        '{captures}',
        case
          when jsonb_typeof(target_log.metadata -> 'captures') = 'object'
            then target_log.metadata -> 'captures'
          else '{}'::jsonb
        end,
        true
      ),
      array['captures', p_branch],
      p_capture,
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
        'capture_version', 'daily-capture-v4',
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

create or replace function public.apply_account_timezone_v2(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_revision int,
  p_timezone text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  existing_request public.account_setting_request_identities%rowtype;
  target_profile public.profiles%rowtype;
  next_revision int;
  normalized_timezone text := trim(coalesce(p_timezone, ''));
  result_value jsonb;
begin
  if p_user_id is null
     or p_request_id is null
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_expected_revision < 1
     or length(normalized_timezone) not between 1 and 100
     or p_now is null
     or not exists (
       select 1 from pg_timezone_names where name = normalized_timezone
     ) then
    raise exception 'Account timezone request is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select * into existing_request
  from public.account_setting_request_identities
  where request_id = p_request_id
  for update;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'timezone'
       or existing_request.request_fingerprint <> p_request_fingerprint then
      raise exception 'Account setting request id was already used.'
        using errcode = 'PT409';
    end if;
    return existing_request.result_value || jsonb_build_object(
      'contract_version', 'account-profile-v2',
      'revision', existing_request.result_revision,
      'updated_at', existing_request.result_updated_at,
      'replayed', true
    );
  end if;

  select * into target_profile
  from public.profiles
  where id = p_user_id
  for update;
  if not found then
    raise exception 'Account profile is unavailable.' using errcode = 'PT404';
  end if;
  if target_profile.timezone_revision <> p_expected_revision then
    raise exception 'Account timezone changed. Reload before saving.'
      using errcode = 'PT409';
  end if;

  next_revision := p_expected_revision + 1;
  update public.profiles
  set timezone = normalized_timezone,
      timezone_revision = next_revision,
      updated_at = greatest(updated_at, p_now)
  where id = p_user_id;

  update public.planner_action_plans
  set attention_reasons = case
        when 'timezone_changed' = any(attention_reasons)
          then attention_reasons
        else array_append(attention_reasons, 'timezone_changed')
      end,
      updated_at = greatest(updated_at, p_now)
  where user_id = p_user_id and status = 'active';

  update public.deadline_plans
  set attention_reasons = case
        when 'timezone_changed' = any(attention_reasons)
          then attention_reasons
        else array_append(attention_reasons, 'timezone_changed')
      end,
      updated_at = greatest(updated_at, p_now)
  where user_id = p_user_id and status = 'active';

  update public.calendar_imports
  set planning_status = 'profile_timezone_changed'
  where user_id = p_user_id
    and planning_status = 'current'
    and (
      timezone <> normalized_timezone
      or profile_timezone_revision <> next_revision
    );

  result_value := jsonb_build_object('timezone', normalized_timezone);
  insert into public.account_setting_request_identities (
    request_id, user_id, operation, request_fingerprint, expected_revision,
    result_revision, result_value, result_updated_at, created_at
  ) values (
    p_request_id, p_user_id, 'timezone', p_request_fingerprint,
    p_expected_revision, next_revision, result_value,
    greatest(target_profile.updated_at, p_now), p_now
  );

  return result_value || jsonb_build_object(
    'contract_version', 'account-profile-v2',
    'revision', next_revision,
    'updated_at', greatest(target_profile.updated_at, p_now),
    'replayed', false
  );
end;
$$;

create or replace function public.apply_account_preparation_budget_v2(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_revision int,
  p_daily_preparation_budget_minutes int,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  existing_request public.account_setting_request_identities%rowtype;
  target_profile public.profiles%rowtype;
  next_revision int;
  result_value jsonb;
begin
  if p_user_id is null
     or p_request_id is null
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_expected_revision < 1
     or p_now is null
     or (
       p_daily_preparation_budget_minutes is not null
       and (
         p_daily_preparation_budget_minutes not between 25 and 480
         or p_daily_preparation_budget_minutes % 5 <> 0
       )
     ) then
    raise exception 'Preparation budget request is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select * into existing_request
  from public.account_setting_request_identities
  where request_id = p_request_id
  for update;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'preparation_budget'
       or existing_request.request_fingerprint <> p_request_fingerprint then
      raise exception 'Account setting request id was already used.'
        using errcode = 'PT409';
    end if;
    return existing_request.result_value || jsonb_build_object(
      'contract_version', 'account-preparation-budget-v2',
      'revision', existing_request.result_revision,
      'updated_at', existing_request.result_updated_at,
      'replayed', true
    );
  end if;

  select * into target_profile
  from public.profiles
  where id = p_user_id
  for update;
  if not found then
    raise exception 'Account profile is unavailable.' using errcode = 'PT404';
  end if;
  if target_profile.preparation_budget_revision <> p_expected_revision then
    raise exception 'Preparation budget changed. Reload before saving.'
      using errcode = 'PT409';
  end if;

  next_revision := p_expected_revision + 1;
  update public.profiles
  set daily_preparation_budget_minutes = p_daily_preparation_budget_minutes,
      preparation_budget_revision = next_revision,
      updated_at = greatest(updated_at, p_now)
  where id = p_user_id;

  result_value := jsonb_build_object(
    'daily_preparation_budget_minutes',
    p_daily_preparation_budget_minutes
  );
  insert into public.account_setting_request_identities (
    request_id, user_id, operation, request_fingerprint, expected_revision,
    result_revision, result_value, result_updated_at, created_at
  ) values (
    p_request_id, p_user_id, 'preparation_budget', p_request_fingerprint,
    p_expected_revision, next_revision, result_value,
    greatest(target_profile.updated_at, p_now), p_now
  );

  return result_value || jsonb_build_object(
    'contract_version', 'account-preparation-budget-v2',
    'revision', next_revision,
    'updated_at', greatest(target_profile.updated_at, p_now),
    'replayed', false
  );
end;
$$;

revoke all on function public.apply_account_timezone_v2(
  uuid, uuid, text, int, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_account_timezone_v2(
  uuid, uuid, text, int, text, timestamptz
) to service_role;
revoke all on function public.apply_account_preparation_budget_v2(
  uuid, uuid, text, int, int, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_account_preparation_budget_v2(
  uuid, uuid, text, int, int, timestamptz
) to service_role;

-- The V1 budget setter is no longer an executable write contract.
revoke all on function public.set_daily_preparation_budget_v1(uuid, int)
  from public, anon, authenticated, service_role;

-- Bind every immutable planning preview to the profile timezone revision that
-- existed under the owner lock. Existing revisions are conservative: a row
-- whose stored timezone differs from the profile cannot be confirmed.
alter table public.planner_action_plan_revisions
  add column if not exists timezone_revision int;
alter table public.deadline_plan_revisions
  add column if not exists timezone_revision int;
alter table public.deadline_plans
  add column if not exists attention_reasons text[] not null default '{}';

update public.planner_action_plan_revisions revision
set timezone_revision = case
  when revision.timezone = profile.timezone then profile.timezone_revision
  else 0
end
from public.profiles profile
where profile.id = revision.user_id
  and revision.timezone_revision is null;

update public.deadline_plan_revisions revision
set timezone_revision = case
  when revision.timezone = profile.timezone then profile.timezone_revision
  else 0
end
from public.profiles profile
where profile.id = revision.user_id
  and revision.timezone_revision is null;

alter table public.planner_action_plan_revisions
  alter column timezone_revision set not null,
  alter column timezone_revision set default 0,
  add constraint planner_action_revision_timezone_revision_check
    check (timezone_revision >= 0);
alter table public.deadline_plan_revisions
  alter column timezone_revision set not null,
  alter column timezone_revision set default 0,
  add constraint deadline_plan_revision_timezone_revision_check
    check (timezone_revision >= 0);
alter table public.deadline_plans
  add constraint deadline_plans_attention_reasons_check check (
    cardinality(attention_reasons) <= 12
    and array_position(attention_reasons, null) is null
  );

create or replace function private.bind_planning_timezone_revision_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  current_timezone text;
  current_revision int;
begin
  select timezone, timezone_revision
  into current_timezone, current_revision
  from public.profiles
  where id = new.user_id;
  if not found then
    raise exception 'Planner profile is unavailable.' using errcode = 'PT404';
  end if;

  if tg_op = 'INSERT' then
    if new.timezone <> current_timezone then
      raise exception 'Planner timezone changed. Create a fresh preview.'
        using errcode = 'PT409';
    end if;
    new.timezone_revision := current_revision;
  elsif old.state = 'proposed' and new.state = 'active' then
    if old.timezone <> current_timezone
       or old.timezone_revision <> current_revision then
      raise exception 'Planner timezone changed. Create a fresh preview.'
        using errcode = 'PT409';
    end if;
  end if;
  return new;
end;
$$;

create trigger planner_action_revision_timezone_guard_v1
before insert or update of state
on public.planner_action_plan_revisions
for each row execute function private.bind_planning_timezone_revision_v1();

create trigger deadline_plan_revision_timezone_guard_v1
before insert or update of state
on public.deadline_plan_revisions
for each row execute function private.bind_planning_timezone_revision_v1();

revoke all on function private.bind_planning_timezone_revision_v1()
  from public, anon, authenticated, service_role;

-- Calendar projections remain readable after a profile timezone change but
-- only a current, revision-bound import may be used as Planner busy time.
alter table public.calendar_imports
  add column if not exists profile_timezone_revision int,
  add column if not exists planning_status text;

update public.calendar_imports import
set profile_timezone_revision = case
      when import.timezone = profile.timezone
        then profile.timezone_revision
      else 0
    end,
    planning_status = case
      when connection.imported_data_deleted_at is not null then 'deleted'
      when connection.status = 'disconnected' then 'disconnected'
      when connection.last_import_id is distinct from import.id
        then 'not_imported'
      when import.timezone = profile.timezone
        then 'current'
      else 'profile_timezone_changed'
    end
from public.profiles profile,
     public.calendar_connections connection
where profile.id = import.user_id
  and connection.id = import.connection_id
  and import.profile_timezone_revision is null;

alter table public.calendar_imports
  alter column profile_timezone_revision set not null,
  alter column profile_timezone_revision set default 0,
  alter column planning_status set not null,
  alter column planning_status set default 'not_imported',
  add constraint calendar_imports_profile_timezone_revision_check
    check (profile_timezone_revision >= 0),
  add constraint calendar_imports_planning_status_check check (
    planning_status in (
      'not_imported',
      'current',
      'profile_timezone_changed',
      'disconnected',
      'deleted'
    )
  );

alter table public.calendar_imports
  drop constraint calendar_imports_contract;
alter table public.calendar_imports
  add constraint calendar_imports_contract check (
    contract_version in ('calendar-import-v1', 'calendar-import-v2')
    and origin = 'authenticated_backend'
    and source_kind = 'ical_file'
  );

alter table public.calendar_events
  drop constraint calendar_events_contract;
alter table public.calendar_events
  add constraint calendar_events_contract check (
    contract_version in ('calendar-import-v1', 'calendar-import-v2')
    and origin = 'authenticated_backend'
    and source_kind = 'ical_file'
  );

create or replace function public.apply_calendar_import_v2(
  p_user_id uuid,
  p_connection_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_input_fingerprint text,
  p_source_fingerprint text,
  p_window_starts_on date,
  p_window_ends_before date,
  p_timezone text,
  p_expected_profile_timezone text,
  p_expected_timezone_revision int,
  p_counts jsonb,
  p_events jsonb,
  p_cancelled_source_keys jsonb,
  p_imported_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  existing_identity public.calendar_request_identities%rowtype;
  existing_import public.calendar_imports%rowtype;
  target_profile public.profiles%rowtype;
  applied jsonb;
begin
  if p_expected_timezone_revision < 1
     or trim(coalesce(p_expected_profile_timezone, '')) = '' then
    raise exception 'Calendar profile timezone identity is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select *
  into existing_identity
  from public.calendar_request_identities
  where request_id = p_request_id
  for update;
  if found then
    if existing_identity.user_id <> p_user_id
       or existing_identity.connection_id <> p_connection_id
       or existing_identity.operation <> 'import_file' then
      raise exception 'Calendar request id was already used.'
        using errcode = 'PT409';
    end if;
    select *
    into existing_import
    from public.calendar_imports
    where request_id = p_request_id
      and user_id = p_user_id
      and connection_id = p_connection_id;
    if not found
       or existing_import.request_fingerprint <> p_request_fingerprint
       or existing_import.input_fingerprint <> p_input_fingerprint
       or existing_import.source_fingerprint <> p_source_fingerprint
       or existing_import.timezone <> p_timezone
       or existing_import.profile_timezone_revision
            <> p_expected_timezone_revision then
      raise exception 'Calendar import replay payload differs.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'contract_version', 'calendar-import-v2',
      'connection_id', existing_import.connection_id,
      'import_id', existing_import.id,
      'planning_status', existing_import.planning_status,
      'profile_timezone_revision',
        existing_import.profile_timezone_revision,
      'replayed', true
    );
  end if;

  select *
  into target_profile
  from public.profiles
  where id = p_user_id
  for update;
  if not found then
    raise exception 'Account profile is unavailable.' using errcode = 'PT404';
  end if;
  if target_profile.timezone <> p_expected_profile_timezone
     or target_profile.timezone <> p_timezone
     or target_profile.timezone_revision <> p_expected_timezone_revision then
    raise exception 'Profile timezone changed. Start a new calendar import.'
      using errcode = 'PT409';
  end if;

  applied := public.apply_calendar_import_v1(
    p_user_id,
    p_connection_id,
    p_request_id,
    p_request_fingerprint,
    p_input_fingerprint,
    p_source_fingerprint,
    p_window_starts_on,
    p_window_ends_before,
    p_timezone,
    p_counts,
    p_events,
    p_cancelled_source_keys,
    p_imported_at
  );

  update public.calendar_imports
  set planning_status = 'not_imported'
  where user_id = p_user_id
    and connection_id = p_connection_id
    and id <> (applied ->> 'import_id')::uuid
    and planning_status = 'current';

  update public.calendar_imports
  set contract_version = 'calendar-import-v2',
      profile_timezone_revision = p_expected_timezone_revision,
      planning_status = 'current'
  where id = (applied ->> 'import_id')::uuid
    and user_id = p_user_id
  returning * into existing_import;
  if not found then
    raise exception 'Calendar import persistence returned no row.'
      using errcode = 'PT502';
  end if;

  update public.calendar_events
  set contract_version = 'calendar-import-v2'
  where import_id = existing_import.id
    and user_id = p_user_id
    and connection_id = p_connection_id;

  return jsonb_build_object(
    'contract_version', 'calendar-import-v2',
    'connection_id', existing_import.connection_id,
    'import_id', existing_import.id,
    'planning_status', existing_import.planning_status,
    'profile_timezone_revision', existing_import.profile_timezone_revision,
    'replayed', false
  );
end;
$$;

revoke all on function public.apply_calendar_import_v1(
  uuid, uuid, uuid, text, text, text, date, date, text, jsonb, jsonb, jsonb,
  timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.apply_calendar_import_v2(
  uuid, uuid, uuid, text, text, text, date, date, text, text, int, jsonb,
  jsonb, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_calendar_import_v2(
  uuid, uuid, uuid, text, text, text, date, date, text, text, int, jsonb,
  jsonb, jsonb, timestamptz
) to service_role;

create or replace function private.project_calendar_import_planning_status_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.imported_data_deleted_at is not null then
    update public.calendar_imports
    set planning_status = 'deleted'
    where connection_id = new.id and user_id = new.user_id;
  elsif new.status = 'disconnected' then
    update public.calendar_imports
    set planning_status = 'disconnected'
    where connection_id = new.id
      and user_id = new.user_id
      and planning_status <> 'deleted';
  end if;
  return new;
end;
$$;

create trigger calendar_connection_planning_status_v1
after update of status, imported_data_deleted_at
on public.calendar_connections
for each row
execute function private.project_calendar_import_planning_status_v1();

revoke all on function private.project_calendar_import_planning_status_v1()
  from public, anon, authenticated, service_role;

-- Local deletion removes event content but retains the bounded import audit
-- row. The retained row is explicitly unusable for planning and lets V2
-- readers explain the terminal state without retaining source event data.
create or replace function public.delete_calendar_imported_data_v1(
  p_user_id uuid,
  p_connection_id uuid,
  p_request_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  request_identity public.calendar_request_identities%rowtype;
  target public.calendar_connections%rowtype;
  request_replay boolean := false;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 9));

  select * into request_identity
  from public.calendar_request_identities
  where request_id = p_request_id
  for update;
  if found then
    if request_identity.user_id <> p_user_id
       or request_identity.connection_id <> p_connection_id
       or request_identity.operation <> 'delete_imported_data' then
      raise exception 'Calendar request id was already used'
        using errcode = 'PT409';
    end if;
    request_replay := true;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_connection_id::text, 0));
  select * into target
  from public.calendar_connections
  where id = p_connection_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Calendar connection is unavailable' using errcode = '22023';
  end if;

  if request_replay then
    if target.imported_data_deleted_at is null
       or target.delete_request_id is distinct from p_request_id then
      raise exception 'Calendar delete request does not match durable state'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object('connection_id', target.id, 'replayed', true);
  end if;

  if target.imported_data_deleted_at is not null then
    raise exception 'Calendar delete request id does not match terminal state'
      using errcode = 'PT409';
  end if;
  if target.status <> 'disconnected' then
    raise exception 'Disconnect calendar source before deleting imported data'
      using errcode = 'PT409';
  end if;

  insert into public.calendar_request_identities (
    request_id, user_id, connection_id, operation, created_at
  ) values (
    p_request_id, p_user_id, p_connection_id, 'delete_imported_data', p_now
  );

  update public.calendar_connections
  set last_import_id = null,
      imported_data_deleted_at = p_now,
      delete_request_id = p_request_id,
      updated_at = greatest(updated_at, p_now)
  where id = p_connection_id and user_id = p_user_id;

  delete from public.calendar_events
  where connection_id = p_connection_id and user_id = p_user_id;

  update public.calendar_imports
  set planning_status = 'deleted'
  where connection_id = p_connection_id and user_id = p_user_id;

  return jsonb_build_object('connection_id', p_connection_id, 'replayed', false);
end;
$$;

-- Setup markers are backend authority. A Data API or direct service-role DML
-- call cannot forge, alter, unmark, or delete these rows; the security-definer
-- Setup apply path executes as the migration owner and remains authoritative.
create or replace function private.guard_setup_owned_row_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  old_owned boolean := false;
  new_owned boolean := false;
begin
  if tg_op <> 'INSERT' then
    old_owned :=
      old.metadata ->> 'managed_by' = 'setup'
      or old.metadata ->> 'source' = 'intake-v1';
  end if;
  if tg_op <> 'DELETE' then
    new_owned :=
      new.metadata ->> 'managed_by' = 'setup'
      or new.metadata ->> 'source' = 'intake-v1';
  end if;

  if current_user in ('anon', 'authenticated', 'service_role')
     and (old_owned or new_owned) then
    raise exception 'Setup-owned rows may only be changed through Setup.'
      using errcode = 'PT403';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger habits_setup_owned_guard_v1
before insert or update or delete on public.habits
for each row execute function private.guard_setup_owned_row_v1();
create trigger schedule_items_setup_owned_guard_v1
before insert or update or delete on public.schedule_items
for each row execute function private.guard_setup_owned_row_v1();

revoke all on function private.guard_setup_owned_row_v1()
  from public, anon, authenticated, service_role;

-- Manual Task/Habit creation has a durable identity. The database computes the
-- immutable payload fingerprint from the creation payload, so a late retry can
-- recognize the row without overwriting later edits or reactivating a Habit.
alter table public.tasks
  add column if not exists creation_request_id uuid,
  add column if not exists creation_fingerprint text;
alter table public.habits
  add column if not exists creation_request_id uuid,
  add column if not exists creation_fingerprint text;

create unique index tasks_user_creation_request_unique_idx
  on public.tasks (user_id, creation_request_id)
  where creation_request_id is not null;
create unique index habits_user_creation_request_unique_idx
  on public.habits (user_id, creation_request_id)
  where creation_request_id is not null;

alter table public.tasks
  add constraint tasks_creation_identity_pair_check check (
    (creation_request_id is null and creation_fingerprint is null)
    or (
      creation_request_id is not null
      and creation_fingerprint ~ '^[0-9a-f]{64}$'
    )
  );
alter table public.habits
  add constraint habits_creation_identity_pair_check check (
    (creation_request_id is null and creation_fingerprint is null)
    or (
      creation_request_id is not null
      and creation_fingerprint ~ '^[0-9a-f]{64}$'
    )
  );

create or replace function private.guard_manual_creation_identity_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  creation_payload jsonb;
begin
  if tg_op = 'INSERT' then
    if tg_table_name = 'tasks'
       and current_user in ('anon', 'authenticated', 'service_role') then
      if new.creation_request_id is null then
        raise exception 'Task creation identity is required.'
          using errcode = '22023';
      end if;
      creation_payload := jsonb_build_object(
        'title', new.title,
        'description', new.description,
        'priority', new.priority,
        'deadline', new.deadline,
        'estimated_minutes', new.estimated_minutes,
        'source', new.source
      );
      new.creation_fingerprint :=
        encode(extensions.digest(creation_payload::text, 'sha256'), 'hex');
    elsif tg_table_name = 'habits'
          and current_user in ('anon', 'authenticated', 'service_role') then
      if new.creation_request_id is null then
        raise exception 'Habit creation identity is required.'
          using errcode = '22023';
      end if;
      creation_payload := jsonb_build_object(
        'title', new.title,
        'description', new.description,
        'frequency', new.frequency,
        'target', new.target,
        'metadata', new.metadata
      );
      new.creation_fingerprint :=
        encode(extensions.digest(creation_payload::text, 'sha256'), 'hex');
    end if;
  elsif new.creation_request_id is distinct from old.creation_request_id
        or new.creation_fingerprint is distinct from old.creation_fingerprint then
    raise exception 'Creation identity is immutable.' using errcode = 'PT409';
  end if;
  return new;
end;
$$;

create trigger tasks_manual_creation_identity_guard_v1
before insert or update on public.tasks
for each row execute function private.guard_manual_creation_identity_v1();
create trigger habits_manual_creation_identity_guard_v1
before insert or update on public.habits
for each row execute function private.guard_manual_creation_identity_v1();

revoke all on function private.guard_manual_creation_identity_v1()
  from public, anon, authenticated, service_role;
