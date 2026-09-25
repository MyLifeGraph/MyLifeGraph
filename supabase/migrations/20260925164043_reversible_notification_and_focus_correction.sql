alter table public.notification_action_requests drop constraint notification_action_requests_command_check;
alter table public.notification_action_requests add constraint notification_action_requests_command_check
  check (command in ('mark_read', 'mark_unread', 'dismiss', 'restore'));

create or replace function public.apply_notification_action_v1(
  p_user_id uuid,
  p_notification_id uuid,
  p_request_id uuid,
  p_command text,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.notification_action_requests%rowtype;
  current_notification public.notifications%rowtype;
  changed_at timestamptz;
begin
  if p_user_id is null
     or p_notification_id is null
     or p_request_id is null
     or p_expected_updated_at is null
     or p_command is null
     or p_command not in ('mark_read', 'mark_unread', 'dismiss', 'restore') then
    raise exception 'Invalid notification lifecycle request'
      using errcode = '22023';
  end if;

  -- Match full-account deletion's owner-first lock before taking request or
  -- notification row locks. This prevents a lifecycle replay from retaining a
  -- ledger row while account deletion waits on the notification cascade.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 14));

  select * into existing_request
  from public.notification_action_requests
  where request_id = p_request_id
  for update;

  if found then
    if existing_request.user_id is distinct from p_user_id
       or existing_request.notification_id is distinct from p_notification_id
       or existing_request.command is distinct from p_command
       or existing_request.expected_updated_at is distinct from p_expected_updated_at then
      raise exception 'Notification action request id was already used'
        using errcode = 'PT409';
    end if;

    return jsonb_build_object(
      'contract_version', 'notification-lifecycle-v1',
      'notification_id', existing_request.notification_id,
      'command', existing_request.command,
      'is_read', existing_request.result_is_read,
      'read_at', existing_request.result_read_at,
      'dismissed_at', existing_request.result_dismissed_at,
      'updated_at', existing_request.result_updated_at,
      'replayed', true
    );
  end if;

  select * into current_notification
  from public.notifications
  where id = p_notification_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Notification is unavailable'
      using errcode = 'PT404';
  end if;

  if current_notification.updated_at is distinct from p_expected_updated_at then
    raise exception 'Notification changed since it was loaded'
      using errcode = 'PT409';
  end if;

  if current_notification.dismissed_at is not null and p_command <> 'restore' then
    raise exception 'Notification is already dismissed'
      using errcode = 'PT409';
  end if;

  changed_at := greatest(
    clock_timestamp(),
    current_notification.updated_at + interval '1 microsecond'
  );

  if p_command = 'mark_read' and not current_notification.is_read then
    update public.notifications
    set
      is_read = true,
      read_at = changed_at,
      updated_at = changed_at
    where id = p_notification_id and user_id = p_user_id
    returning * into current_notification;
  elsif p_command = 'mark_unread' and current_notification.is_read then
    update public.notifications
    set
      is_read = false,
      read_at = null,
      updated_at = changed_at
    where id = p_notification_id and user_id = p_user_id
    returning * into current_notification;
  elsif p_command = 'restore' and current_notification.dismissed_at is not null then
    update public.notifications set dismissed_at = null, updated_at = changed_at
    where id = p_notification_id and user_id = p_user_id
    returning * into current_notification;
  elsif p_command = 'dismiss' then
    update public.notifications
    set
      is_read = true,
      read_at = coalesce(read_at, changed_at),
      dismissed_at = changed_at,
      updated_at = changed_at
    where id = p_notification_id and user_id = p_user_id
    returning * into current_notification;
  end if;

  insert into public.notification_action_requests (
    request_id,
    user_id,
    notification_id,
    command,
    expected_updated_at,
    result_is_read,
    result_read_at,
    result_dismissed_at,
    result_updated_at,
    created_at
  ) values (
    p_request_id,
    p_user_id,
    p_notification_id,
    p_command,
    p_expected_updated_at,
    current_notification.is_read,
    current_notification.read_at,
    current_notification.dismissed_at,
    current_notification.updated_at,
    changed_at
  );

  return jsonb_build_object(
    'contract_version', 'notification-lifecycle-v1',
    'notification_id', current_notification.id,
    'command', p_command,
    'is_read', current_notification.is_read,
    'read_at', current_notification.read_at,
    'dismissed_at', current_notification.dismissed_at,
    'updated_at', current_notification.updated_at,
    'replayed', false
  );
end;
$$;

revoke all on function public.apply_notification_action_v1(
  uuid, uuid, uuid, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_notification_action_v1(
  uuid, uuid, uuid, text, timestamptz
) to service_role;
-- Only the audited service command below may correct a completed interval.
-- Original timestamps are retained; all existing readers use the corrected row.
create table private.focus_time_corrections (
  request_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null references public.focus_sessions(id) on delete cascade,
  expected_updated_at timestamptz not null,
  old_ended_at timestamptz not null,
  new_ended_at timestamptz not null,
  minutes integer not null check (minutes >= 0),
  transaction_id bigint not null,
  result jsonb,
  created_at timestamptz not null default clock_timestamp()
);
alter table private.focus_time_corrections enable row level security;
alter table private.focus_time_corrections force row level security;
revoke all on private.focus_time_corrections from public, anon, authenticated, service_role;
create index focus_time_corrections_session_idx on private.focus_time_corrections(session_id, created_at);

create or replace function private.enforce_focus_session_transition()
returns trigger language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin
  if new.started_at is distinct from old.started_at then
    raise exception 'A focus session start timestamp is immutable.' using errcode = '23514';
  end if;
  if old.status in ('completed', 'abandoned') then
    if old.status = 'completed'
      and (to_jsonb(new) - array['ended_at', 'actual_minutes', 'updated_at', 'metadata']) =
          (to_jsonb(old) - array['ended_at', 'actual_minutes', 'updated_at', 'metadata'])
      and (new.metadata - 'time_correction') = (old.metadata - 'time_correction')
      and exists (select 1 from private.focus_time_corrections c
        where c.session_id = old.id and c.user_id = old.user_id
          and c.expected_updated_at = old.updated_at and c.old_ended_at = old.ended_at
          and c.new_ended_at = new.ended_at and c.minutes = new.actual_minutes
          and c.transaction_id = txid_current() and c.result is null)
    then return new; end if;
    raise exception 'A terminal focus session is immutable.' using errcode = '23514';
  end if;
  if old.status = 'active' and new.status not in ('active', 'completed', 'abandoned') then
    raise exception 'Focus session transition is invalid.' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_focus_session_transition() from public, anon, authenticated, service_role;

create function public.correct_focus_time_v1(
  p_user_id uuid, p_session_id uuid, p_request_id uuid,
  p_expected_updated_at timestamptz, p_minutes integer
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare
  previous private.focus_time_corrections%rowtype;
  target public.focus_sessions%rowtype;
  original_end timestamptz;
  corrected_end timestamptz;
  response jsonb;
begin
  if p_user_id is null or p_session_id is null or p_request_id is null
     or p_expected_updated_at is null or p_minutes is null or p_minutes < 0 then
    raise exception 'Invalid correction.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 53));
  select * into previous from private.focus_time_corrections where request_id = p_request_id;
  if found then
    if previous.user_id <> p_user_id or previous.session_id <> p_session_id
       or previous.expected_updated_at <> p_expected_updated_at or previous.minutes <> p_minutes then
      raise exception 'Correction request changed.' using errcode = 'PT409';
    end if;
    return previous.result || jsonb_build_object('replayed', true);
  end if;
  select * into target from public.focus_sessions where id = p_session_id and user_id = p_user_id for update;
  if not found then raise exception 'Focus session unavailable.' using errcode = 'PT404'; end if;
  if target.status <> 'completed' or target.updated_at <> p_expected_updated_at then
    raise exception 'Focus session changed. Reload.' using errcode = 'PT409';
  end if;
  select old_ended_at into original_end from private.focus_time_corrections
    where session_id = p_session_id order by created_at, request_id limit 1;
  original_end := coalesce(original_end, target.ended_at);
  corrected_end := target.started_at + make_interval(mins => p_minutes);
  if corrected_end > original_end then
    raise exception 'Correction exceeds the recorded session.' using errcode = 'PT409';
  end if;
  insert into private.focus_time_corrections(request_id,user_id,session_id,expected_updated_at,
    old_ended_at,new_ended_at,minutes,transaction_id)
    values(p_request_id,p_user_id,p_session_id,p_expected_updated_at,target.ended_at,corrected_end,p_minutes,txid_current());
  update public.focus_sessions set ended_at = corrected_end, actual_minutes = p_minutes,
    updated_at = greatest(clock_timestamp(), target.updated_at + interval '1 microsecond'),
    metadata = jsonb_set(metadata, '{time_correction}', jsonb_build_object(
      'original_ended_at', original_end, 'corrected_at', clock_timestamp()))
    where id = p_session_id and user_id = p_user_id;
  response := private.focus_session_response_v2(p_user_id, p_session_id, false);
  update private.focus_time_corrections set result = response where request_id = p_request_id;
  return response;
end;
$$;
revoke all on function public.correct_focus_time_v1(uuid,uuid,uuid,timestamptz,integer) from public, anon, authenticated;
grant execute on function public.correct_focus_time_v1(uuid,uuid,uuid,timestamptz,integer) to service_role;
