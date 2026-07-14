-- Explicit consent, deterministic generation, and acknowledged foreground
-- in-app delivery. Existing reminder preferences are not delivery permission.

alter table public.notification_preferences
  add column in_app_delivery_enabled boolean not null default false,
  add column in_app_delivery_consent_version text,
  add column in_app_delivery_consented_at timestamptz,
  add column in_app_delivery_disabled_at timestamptz,
  add column delivery_settings_request_id uuid,
  add column daily_notification_limit smallint not null default 2;

-- Older rows had no pair constraint. An incomplete legacy pair is not a safe
-- delivery window, so normalize only that invalid shape to no quiet window.
update public.notification_preferences
set quiet_hours_start = null,
    quiet_hours_end = null
where (quiet_hours_start is null) <> (quiet_hours_end is null);

alter table public.notification_preferences
  add constraint notification_preferences_delivery_consent_check check (
    (
      in_app_delivery_enabled
      and in_app_delivery_consent_version = 'in-app-notification-consent-v1'
      and in_app_delivery_consented_at is not null
      and in_app_delivery_disabled_at is null
    )
    or (
      not in_app_delivery_enabled
      and (
        (
          in_app_delivery_consent_version is null
          and in_app_delivery_consented_at is null
          and in_app_delivery_disabled_at is null
        )
        or (
          in_app_delivery_consent_version = 'in-app-notification-consent-v1'
          and in_app_delivery_consented_at is not null
          and in_app_delivery_disabled_at is not null
          and in_app_delivery_disabled_at >= in_app_delivery_consented_at
        )
      )
    )
  ),
  add constraint notification_preferences_quiet_hours_pair_check check (
    (quiet_hours_start is null and quiet_hours_end is null)
    or (
      quiet_hours_start is not null
      and quiet_hours_end is not null
    )
  ),
  add constraint notification_preferences_daily_limit_check check (
    daily_notification_limit between 1 and 5
  );

alter table public.notifications
  add column generation_key text,
  add column generation_category text,
  add column delivery_date date,
  add column in_app_delivered_at timestamptz;

alter table public.notifications
  add constraint notifications_generation_shape_check check (
    (
      generation_key is null
      and generation_category is null
      and delivery_date is null
      and in_app_delivered_at is null
    )
    or (
      generation_key is not null
      and length(generation_key) between 1 and 200
      and generation_category in (
        'focus_prompt',
        'recovery_prompt',
        'weekly_summary'
      )
      and delivery_date is not null
      and metadata ->> 'contract_version' = 'notification-generation-v1'
      and metadata ->> 'origin' = 'deterministic_backend'
      and metadata ->> 'category' = generation_category
      and metadata ->> 'delivery_date' = delivery_date::text
      and metadata ->> 'llm_used' = 'false'
      and metadata ->> 'sensitive_copy_excluded' = 'true'
    )
  ),
  add constraint notifications_in_app_delivery_time_check check (
    in_app_delivered_at is null or in_app_delivered_at >= created_at
  );

create unique index notifications_owner_generation_key_idx
  on public.notifications (user_id, generation_key)
  where generation_key is not null;

create index notifications_owner_delivery_pending_idx
  on public.notifications (
    user_id,
    in_app_delivered_at,
    due_at,
    created_at,
    id
  )
  where generation_key is not null and dismissed_at is null;

-- Delivery settings are now a backend-owned projection. Authenticated users
-- can read their row, while Flutter changes it only through the bearer-derived
-- FastAPI boundary and the service-role RPC below.
revoke insert, update, delete, truncate on table public.notification_preferences
  from public, anon, authenticated;
grant select on table public.notification_preferences to authenticated;

create or replace function public.update_notification_settings_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_expected_updated_at timestamptz,
  p_in_app_delivery_enabled boolean,
  p_consent_version text,
  p_focus_prompt boolean,
  p_recovery_prompt boolean,
  p_weekly_summary boolean,
  p_quiet_hours_start time,
  p_quiet_hours_end time,
  p_daily_limit smallint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_preferences public.notification_preferences%rowtype;
  changed_at timestamptz;
  replayed boolean := false;
begin
  if p_user_id is null
     or p_request_id is null
     or p_expected_updated_at is null
     or p_in_app_delivery_enabled is null
     or p_consent_version is distinct from 'in-app-notification-consent-v1'
     or p_focus_prompt is null
     or p_recovery_prompt is null
     or p_weekly_summary is null
     or p_daily_limit is null
     or p_daily_limit not between 1 and 5
     or ((p_quiet_hours_start is null) <> (p_quiet_hours_end is null)) then
    raise exception 'Invalid notification settings request'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select * into current_preferences
  from public.notification_preferences
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'Notification settings are unavailable'
      using errcode = 'PT404';
  end if;

  if current_preferences.delivery_settings_request_id = p_request_id then
    if current_preferences.in_app_delivery_enabled is distinct from p_in_app_delivery_enabled
       or current_preferences.focus_prompts_enabled is distinct from p_focus_prompt
       or current_preferences.recovery_prompts_enabled is distinct from p_recovery_prompt
       or current_preferences.weekly_summary_enabled is distinct from p_weekly_summary
       or current_preferences.quiet_hours_start is distinct from p_quiet_hours_start
       or current_preferences.quiet_hours_end is distinct from p_quiet_hours_end
       or current_preferences.daily_notification_limit is distinct from p_daily_limit then
      raise exception 'Notification settings request id was already used'
        using errcode = 'PT409';
    end if;
    replayed := true;
  elsif current_preferences.updated_at is distinct from p_expected_updated_at then
    raise exception 'Notification settings changed since they were loaded'
      using errcode = 'PT409';
  else
    changed_at := greatest(
      clock_timestamp(),
      current_preferences.updated_at + interval '1 microsecond'
    );

    update public.notification_preferences
    set
      focus_prompts_enabled = p_focus_prompt,
      recovery_prompts_enabled = p_recovery_prompt,
      weekly_summary_enabled = p_weekly_summary,
      quiet_hours_start = p_quiet_hours_start,
      quiet_hours_end = p_quiet_hours_end,
      in_app_delivery_enabled = p_in_app_delivery_enabled,
      in_app_delivery_consent_version = case
        when p_in_app_delivery_enabled then p_consent_version
        else in_app_delivery_consent_version
      end,
      in_app_delivery_consented_at = case
        when p_in_app_delivery_enabled and not in_app_delivery_enabled
          then changed_at
        else in_app_delivery_consented_at
      end,
      in_app_delivery_disabled_at = case
        when p_in_app_delivery_enabled then null
        when in_app_delivery_enabled then changed_at
        else in_app_delivery_disabled_at
      end,
      delivery_settings_request_id = p_request_id,
      daily_notification_limit = p_daily_limit,
      updated_at = changed_at
    where user_id = p_user_id
    returning * into current_preferences;
  end if;

  return jsonb_build_object(
    'contract_version', 'notification-settings-v1',
    'in_app_delivery_enabled', current_preferences.in_app_delivery_enabled,
    'consent_version', current_preferences.in_app_delivery_consent_version,
    'consented_at', current_preferences.in_app_delivery_consented_at,
    'disabled_at', current_preferences.in_app_delivery_disabled_at,
    'categories', jsonb_build_object(
      'focus_prompt', current_preferences.focus_prompts_enabled,
      'recovery_prompt', current_preferences.recovery_prompts_enabled,
      'weekly_summary', current_preferences.weekly_summary_enabled
    ),
    'quiet_hours', case
      when current_preferences.quiet_hours_start is null then null
      else jsonb_build_object(
        'starts_at', to_char(current_preferences.quiet_hours_start, 'HH24:MI'),
        'ends_at', to_char(current_preferences.quiet_hours_end, 'HH24:MI')
      )
    end,
    'daily_limit', current_preferences.daily_notification_limit,
    'updated_at', current_preferences.updated_at,
    'replayed', replayed
  );
end;
$$;

revoke all on function public.update_notification_settings_v1(
  uuid, uuid, timestamptz, boolean, text, boolean, boolean, boolean,
  time, time, smallint
) from public, anon, authenticated;
grant execute on function public.update_notification_settings_v1(
  uuid, uuid, timestamptz, boolean, text, boolean, boolean, boolean,
  time, time, smallint
) to service_role;

create or replace function public.create_generated_notification_v1(
  p_user_id uuid,
  p_notification_id uuid,
  p_generation_key text,
  p_category text,
  p_delivery_date date,
  p_run_at timestamptz,
  p_timezone text,
  p_title text,
  p_message text,
  p_type text,
  p_priority text,
  p_action_url text,
  p_reason_code text,
  p_source_kind text,
  p_source_id text,
  p_source_generated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_preferences public.notification_preferences%rowtype;
  profile_timezone text;
  local_run_at timestamp;
  existing_notification_id uuid;
  generated_count integer;
  category_enabled boolean;
  in_quiet_hours boolean := false;
  notification_metadata jsonb;
begin
  if p_user_id is null
     or p_notification_id is null
     or p_generation_key is null
     or length(p_generation_key) not between 1 and 200
     or p_category not in ('focus_prompt', 'recovery_prompt', 'weekly_summary')
     or p_delivery_date is null
     or p_run_at is null
     or p_timezone is null
     or length(p_timezone) not between 1 and 100
     or p_title is null
     or length(btrim(p_title)) not between 1 and 120
     or p_message is null
     or length(btrim(p_message)) not between 1 and 300
     or p_type not in ('reminder', 'warning', 'coaching', 'deadline', 'summary')
     or p_priority not in ('low', 'medium', 'high', 'critical')
     or p_action_url not in ('/dashboard', '/weekly-review')
     or p_reason_code is null
     or length(p_reason_code) not between 1 and 80
     or p_source_kind not in ('daily_briefing', 'daily_state', 'weekly_review')
     or p_source_id is null
     or length(p_source_id) not between 1 and 100
     or p_source_generated_at is null then
    raise exception 'Invalid generated notification request'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select timezone into profile_timezone
  from public.profiles
  where id = p_user_id and onboarding_completed_at is not null and role <> 'guest'
  for share;

  if not found then
    return jsonb_build_object('status', 'not_consented');
  end if;
  if profile_timezone is distinct from p_timezone then
    raise exception 'Notification timezone changed'
      using errcode = 'PT409';
  end if;

  select * into current_preferences
  from public.notification_preferences
  where user_id = p_user_id
  for update;

  if not found
     or not current_preferences.in_app_delivery_enabled
     or current_preferences.in_app_delivery_consent_version
       is distinct from 'in-app-notification-consent-v1' then
    return jsonb_build_object('status', 'not_consented');
  end if;

  select id into existing_notification_id
  from public.notifications
  where user_id = p_user_id and generation_key = p_generation_key;

  if found then
    return jsonb_build_object(
      'status', 'duplicate',
      'notification_id', existing_notification_id
    );
  end if;

  category_enabled := case p_category
    when 'focus_prompt' then current_preferences.focus_prompts_enabled
    when 'recovery_prompt' then current_preferences.recovery_prompts_enabled
    when 'weekly_summary' then current_preferences.weekly_summary_enabled
  end;
  if not category_enabled then
    return jsonb_build_object('status', 'category_disabled');
  end if;

  begin
    local_run_at := p_run_at at time zone p_timezone;
  exception when invalid_parameter_value then
    raise exception 'Notification timezone is invalid'
      using errcode = '22023';
  end;
  if local_run_at::date is distinct from p_delivery_date then
    raise exception 'Notification delivery date is invalid'
      using errcode = '22023';
  end if;

  if current_preferences.quiet_hours_start is not null then
    in_quiet_hours := case
      when current_preferences.quiet_hours_start
        < current_preferences.quiet_hours_end
        then local_run_at::time >= current_preferences.quiet_hours_start
          and local_run_at::time < current_preferences.quiet_hours_end
      else local_run_at::time >= current_preferences.quiet_hours_start
        or local_run_at::time < current_preferences.quiet_hours_end
    end;
  end if;
  if in_quiet_hours then
    return jsonb_build_object('status', 'quiet_hours');
  end if;

  select count(*) into generated_count
  from public.notifications
  where user_id = p_user_id
    and delivery_date = p_delivery_date
    and generation_key is not null;
  if generated_count >= current_preferences.daily_notification_limit then
    return jsonb_build_object('status', 'daily_limit');
  end if;

  notification_metadata := jsonb_strip_nulls(jsonb_build_object(
    'contract_version', 'notification-generation-v1',
    'origin', 'deterministic_backend',
    'category', p_category,
    'reason_code', p_reason_code,
    'delivery_date', p_delivery_date,
    'timezone', p_timezone,
    'source_kind', p_source_kind,
    'source_id', p_source_id,
    'source_generated_at', p_source_generated_at,
    'sensitive_copy_excluded', true,
    'llm_used', false
  ));

  insert into public.notifications (
    id,
    user_id,
    title,
    message,
    type,
    priority,
    is_read,
    read_at,
    action_url,
    due_at,
    metadata,
    generation_key,
    generation_category,
    delivery_date,
    created_at,
    updated_at
  ) values (
    p_notification_id,
    p_user_id,
    btrim(p_title),
    btrim(p_message),
    p_type,
    p_priority,
    false,
    null,
    p_action_url,
    p_run_at,
    notification_metadata,
    p_generation_key,
    p_category,
    p_delivery_date,
    p_run_at,
    p_run_at
  );

  return jsonb_build_object(
    'status', 'created',
    'notification_id', p_notification_id
  );
end;
$$;

revoke all on function public.create_generated_notification_v1(
  uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
  text, text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.create_generated_notification_v1(
  uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
  text, text, text, text, timestamptz
) to service_role;

create or replace function public.acknowledge_in_app_notification_v1(
  p_user_id uuid,
  p_notification_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_notification public.notifications%rowtype;
  current_preferences public.notification_preferences%rowtype;
  profile_timezone text;
  local_delivery_at timestamp;
  category_enabled boolean;
  in_quiet_hours boolean := false;
  delivered_at timestamptz;
begin
  if p_user_id is null or p_notification_id is null then
    raise exception 'Invalid in-app delivery request'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select * into current_notification
  from public.notifications
  where id = p_notification_id and user_id = p_user_id
  for update;

  if not found
     or current_notification.generation_key is null
     or current_notification.dismissed_at is not null then
    raise exception 'Notification is unavailable'
      using errcode = 'PT404';
  end if;

  if current_notification.in_app_delivered_at is not null then
    return jsonb_build_object(
      'contract_version', 'in-app-notification-delivery-v1',
      'notification_id', current_notification.id,
      'channel', 'in_app',
      'delivered_at', current_notification.in_app_delivered_at,
      'replayed', true
    );
  end if;

  select timezone into profile_timezone
  from public.profiles
  where id = p_user_id and onboarding_completed_at is not null and role <> 'guest'
  for share;

  if not found then
    raise exception 'Notification is unavailable'
      using errcode = 'PT404';
  end if;

  select * into current_preferences
  from public.notification_preferences
  where user_id = p_user_id
  for update;

  if not found
     or not current_preferences.in_app_delivery_enabled
     or current_preferences.in_app_delivery_consent_version
       is distinct from 'in-app-notification-consent-v1' then
    raise exception 'In-app delivery is currently unavailable'
      using errcode = 'PT409';
  end if;

  category_enabled := case current_notification.generation_category
    when 'focus_prompt' then current_preferences.focus_prompts_enabled
    when 'recovery_prompt' then current_preferences.recovery_prompts_enabled
    when 'weekly_summary' then current_preferences.weekly_summary_enabled
    else false
  end;
  if not category_enabled or current_notification.due_at > clock_timestamp() then
    raise exception 'In-app delivery is currently unavailable'
      using errcode = 'PT409';
  end if;

  begin
    local_delivery_at := clock_timestamp() at time zone profile_timezone;
  exception when invalid_parameter_value then
    raise exception 'In-app delivery is currently unavailable'
      using errcode = 'PT409';
  end;
  if current_preferences.quiet_hours_start is not null then
    in_quiet_hours := case
      when current_preferences.quiet_hours_start
        < current_preferences.quiet_hours_end
        then local_delivery_at::time >= current_preferences.quiet_hours_start
          and local_delivery_at::time < current_preferences.quiet_hours_end
      else local_delivery_at::time >= current_preferences.quiet_hours_start
        or local_delivery_at::time < current_preferences.quiet_hours_end
    end;
  end if;
  if in_quiet_hours then
    raise exception 'In-app delivery is currently unavailable'
      using errcode = 'PT409';
  end if;

  delivered_at := greatest(clock_timestamp(), current_notification.created_at);
  update public.notifications
  set in_app_delivered_at = delivered_at
  where id = p_notification_id and user_id = p_user_id
  returning * into current_notification;

  return jsonb_build_object(
    'contract_version', 'in-app-notification-delivery-v1',
    'notification_id', current_notification.id,
    'channel', 'in_app',
    'delivered_at', current_notification.in_app_delivered_at,
    'replayed', false
  );
end;
$$;

revoke all on function public.acknowledge_in_app_notification_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.acknowledge_in_app_notification_v1(uuid, uuid)
  to service_role;
