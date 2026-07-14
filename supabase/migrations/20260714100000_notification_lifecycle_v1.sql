-- Durable, retry-safe lifecycle commands for stored Inbox notifications.

alter table public.notifications
  add column if not exists read_at timestamptz,
  add column if not exists dismissed_at timestamptz;

-- Preserve the canonical is_read projection while giving already-read rows an
-- honest lifecycle timestamp derived from their last persisted representation.
update public.notifications
set read_at = coalesce(read_at, updated_at, created_at)
where is_read and read_at is null;

alter table public.notifications
  drop constraint if exists notifications_read_state_check,
  add constraint notifications_read_state_check check (
    (is_read and read_at is not null)
    or (not is_read and read_at is null)
  ),
  drop constraint if exists notifications_dismissed_state_check,
  add constraint notifications_dismissed_state_check check (
    dismissed_at is null
    or (is_read and read_at is not null)
  );

create unique index if not exists notifications_id_user_key
  on public.notifications (id, user_id);

create index if not exists notifications_user_visible_created_idx
  on public.notifications (user_id, dismissed_at, created_at desc, id desc);

create table public.notification_action_requests (
  request_id uuid primary key,
  user_id uuid not null,
  notification_id uuid not null,
  contract_version text not null default 'notification-lifecycle-v1'
    check (contract_version = 'notification-lifecycle-v1'),
  command text not null
    check (command in ('mark_read', 'mark_unread', 'dismiss')),
  expected_updated_at timestamptz not null,
  result_is_read boolean not null,
  result_read_at timestamptz,
  result_dismissed_at timestamptz,
  result_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint notification_action_requests_notification_owner_fk
    foreign key (notification_id, user_id)
    references public.notifications (id, user_id)
    on delete cascade,
  constraint notification_action_requests_read_state_check check (
    (result_is_read and result_read_at is not null)
    or (not result_is_read and result_read_at is null)
  ),
  constraint notification_action_requests_dismissed_state_check check (
    result_dismissed_at is null
    or (result_is_read and result_read_at is not null)
  )
);

create index notification_action_requests_owner_created_idx
  on public.notification_action_requests (user_id, created_at desc, request_id);

alter table public.notifications enable row level security;
alter table public.notifications force row level security;
alter table public.notification_action_requests enable row level security;
alter table public.notification_action_requests force row level security;

-- The Inbox remains directly read-only for application roles. Lifecycle
-- mutation is possible only through the bearer-derived FastAPI call and the
-- service-role-only RPC below.
revoke insert, update, delete, truncate on table public.notifications
  from public, anon, authenticated;
grant select on table public.notifications to authenticated;

revoke all on table public.notification_action_requests
  from public, anon, authenticated, service_role;
grant select on table public.notification_action_requests to service_role;

create policy "notification_action_requests_service_role_select"
  on public.notification_action_requests
  for select
  to service_role
  using (true);

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
     or p_command not in ('mark_read', 'mark_unread', 'dismiss') then
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

  if current_notification.dismissed_at is not null then
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
