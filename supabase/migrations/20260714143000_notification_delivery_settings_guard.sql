-- Keep Notification Delivery settings monotone across the Setup-owned writer
-- and preserve the complete request identity needed for an honest replay.

alter table public.notification_preferences
  add column delivery_settings_request_fingerprint text;

-- The original migration retained only the request UUID, so its successful
-- pre-guard requests cannot be reconstructed with their expected revision.
-- Forget those incomplete identities instead of reinterpreting them.
update public.notification_preferences
set delivery_settings_request_id = null
where delivery_settings_request_id is not null;

alter table public.notification_preferences
  add constraint notification_preferences_delivery_request_identity_check check (
    (
      delivery_settings_request_id is null
      and delivery_settings_request_fingerprint is null
    )
    or (
      delivery_settings_request_id is not null
      and delivery_settings_request_fingerprint
        ~ '^[0-9a-f]{64}$'
    )
  );

create or replace function public.guard_notification_preferences_revision_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  -- A different owner-locked writer, currently Intake Setup, does not know
  -- the delivery request fingerprint. If it changes the projection while
  -- retaining the old identity columns, invalidate that identity so an old
  -- request cannot replay as though the row were unchanged.
  if old.delivery_settings_request_id is not null
     and new.delivery_settings_request_id
       is not distinct from old.delivery_settings_request_id
     and new.delivery_settings_request_fingerprint
       is not distinct from old.delivery_settings_request_fingerprint
     and (
       new.focus_prompts_enabled
         is distinct from old.focus_prompts_enabled
       or new.recovery_prompts_enabled
         is distinct from old.recovery_prompts_enabled
       or new.weekly_summary_enabled
         is distinct from old.weekly_summary_enabled
       or new.quiet_hours_start is distinct from old.quiet_hours_start
       or new.quiet_hours_end is distinct from old.quiet_hours_end
       or new.in_app_delivery_enabled
         is distinct from old.in_app_delivery_enabled
       or new.in_app_delivery_consent_version
         is distinct from old.in_app_delivery_consent_version
       or new.in_app_delivery_consented_at
         is distinct from old.in_app_delivery_consented_at
       or new.in_app_delivery_disabled_at
         is distinct from old.in_app_delivery_disabled_at
       or new.daily_notification_limit
         is distinct from old.daily_notification_limit
       or new.updated_at is distinct from old.updated_at
     ) then
    new.delivery_settings_request_id := null;
    new.delivery_settings_request_fingerprint := null;
  end if;

  -- Setup captures its completion instant before entering the database owner
  -- lock. Never allow that earlier instant to regress the shared revision or
  -- fall behind the consent timestamps preserved by Setup.
  new.updated_at := greatest(
    new.updated_at,
    old.updated_at + interval '1 microsecond',
    coalesce(new.in_app_delivery_consented_at, new.updated_at),
    coalesce(new.in_app_delivery_disabled_at, new.updated_at)
  );
  return new;
end;
$$;

revoke all on function public.guard_notification_preferences_revision_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists notification_preferences_revision_guard_v1
  on public.notification_preferences;
create trigger notification_preferences_revision_guard_v1
before update on public.notification_preferences
for each row execute function public.guard_notification_preferences_revision_v1();

-- Repair any row produced by the pre-guard race before enforcing the parser's
-- timestamp-order invariant at the database boundary.
update public.notification_preferences
set updated_at = greatest(
  updated_at,
  coalesce(in_app_delivery_consented_at, updated_at),
  coalesce(in_app_delivery_disabled_at, updated_at)
)
where (in_app_delivery_consented_at is not null
       and in_app_delivery_consented_at > updated_at)
   or (in_app_delivery_disabled_at is not null
       and in_app_delivery_disabled_at > updated_at);

alter table public.notification_preferences
  add constraint notification_preferences_delivery_timestamp_order_check check (
    (
      in_app_delivery_consented_at is null
      or in_app_delivery_consented_at <= updated_at
    )
    and (
      in_app_delivery_disabled_at is null
      or in_app_delivery_disabled_at <= updated_at
    )
  );

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
  request_fingerprint text;
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

  request_fingerprint := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'contract_version', 'notification-settings-v1',
          'user_id', p_user_id,
          'request_id', p_request_id,
          'expected_updated_at_epoch', extract(epoch from p_expected_updated_at),
          'in_app_delivery_enabled', p_in_app_delivery_enabled,
          'consent_version', p_consent_version,
          'focus_prompt', p_focus_prompt,
          'recovery_prompt', p_recovery_prompt,
          'weekly_summary', p_weekly_summary,
          'quiet_hours_start', case
            when p_quiet_hours_start is null then null
            else to_char(p_quiet_hours_start, 'HH24:MI:SS.US')
          end,
          'quiet_hours_end', case
            when p_quiet_hours_end is null then null
            else to_char(p_quiet_hours_end, 'HH24:MI:SS.US')
          end,
          'daily_limit', p_daily_limit
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

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
    if current_preferences.delivery_settings_request_fingerprint
         is distinct from request_fingerprint
       or current_preferences.in_app_delivery_enabled
         is distinct from p_in_app_delivery_enabled
       or current_preferences.focus_prompts_enabled is distinct from p_focus_prompt
       or current_preferences.recovery_prompts_enabled
         is distinct from p_recovery_prompt
       or current_preferences.weekly_summary_enabled
         is distinct from p_weekly_summary
       or current_preferences.quiet_hours_start
         is distinct from p_quiet_hours_start
       or current_preferences.quiet_hours_end is distinct from p_quiet_hours_end
       or current_preferences.daily_notification_limit
         is distinct from p_daily_limit then
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
      delivery_settings_request_fingerprint = request_fingerprint,
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
