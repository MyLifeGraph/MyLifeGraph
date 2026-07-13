-- Phase 9 follow-up: one immutable request identity across every calendar
-- mutation plus reliable PostgREST conflict semantics.

create table public.calendar_request_identities (
  request_id uuid primary key,
  user_id uuid not null,
  connection_id uuid not null,
  operation text not null,
  created_at timestamptz not null,
  constraint calendar_request_identities_connection_owner_fk
    foreign key (connection_id, user_id)
    references public.calendar_connections (id, user_id)
    on delete cascade,
  constraint calendar_request_identities_operation check (
    operation in (
      'create_connection',
      'import_file',
      'disconnect',
      'delete_imported_data'
    )
  )
);

create index calendar_request_identities_owner_recent_idx
  on public.calendar_request_identities (user_id, created_at desc, request_id);

-- Do not silently reinterpret or rewrite a request id that was already used by
-- another owner, connection, or operation before this guard existed. A
-- conflicting pre-existing database needs explicit operator reconciliation.
do $$
begin
  if exists (
    select existing.request_id
    from (
      select create_request_id as request_id
      from public.calendar_connections
      union all
      select request_id
      from public.calendar_imports
      union all
      select disconnect_request_id
      from public.calendar_connections
      where disconnect_request_id is not null
      union all
      select delete_request_id
      from public.calendar_connections
      where delete_request_id is not null
    ) existing
    group by existing.request_id
    having count(*) > 1
  ) then
    raise exception
      'Existing calendar request identities conflict across owner, connection, or operation';
  end if;
end;
$$;

insert into public.calendar_request_identities (
  request_id,
  user_id,
  connection_id,
  operation,
  created_at
)
select
  create_request_id,
  user_id,
  id,
  'create_connection',
  created_at
from public.calendar_connections;

insert into public.calendar_request_identities (
  request_id,
  user_id,
  connection_id,
  operation,
  created_at
)
select
  request_id,
  user_id,
  connection_id,
  'import_file',
  imported_at
from public.calendar_imports;

insert into public.calendar_request_identities (
  request_id,
  user_id,
  connection_id,
  operation,
  created_at
)
select
  disconnect_request_id,
  user_id,
  id,
  'disconnect',
  disconnected_at
from public.calendar_connections
where disconnect_request_id is not null;

insert into public.calendar_request_identities (
  request_id,
  user_id,
  connection_id,
  operation,
  created_at
)
select
  delete_request_id,
  user_id,
  id,
  'delete_imported_data',
  imported_data_deleted_at
from public.calendar_connections
where delete_request_id is not null;

alter table public.calendar_request_identities enable row level security;
alter table public.calendar_request_identities force row level security;

revoke all on table public.calendar_request_identities
from public, anon, authenticated, service_role;
grant select, insert
on table public.calendar_request_identities to service_role;

create policy "calendar_request_identities_service_role_select"
  on public.calendar_request_identities
  for select
  to service_role
  using (true);

create policy "calendar_request_identities_service_role_insert"
  on public.calendar_request_identities
  for insert
  to service_role
  with check (true);

create or replace function public.create_calendar_connection_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_source_label text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  request_identity public.calendar_request_identities%rowtype;
  existing public.calendar_connections%rowtype;
  created public.calendar_connections%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 9));

  select * into request_identity
  from public.calendar_request_identities
  where request_id = p_request_id
  for update;
  if found then
    if request_identity.user_id <> p_user_id
       or request_identity.operation <> 'create_connection' then
      raise exception 'Calendar request id was already used'
        using errcode = 'PT409';
    end if;
    select * into existing
    from public.calendar_connections
    where id = request_identity.connection_id and user_id = p_user_id
    limit 1;
    if not found
       or existing.create_request_fingerprint <> p_request_fingerprint then
      raise exception 'Calendar connection request id was already used'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'connection_id', request_identity.connection_id,
      'replayed', true
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  if exists (
    select 1 from public.calendar_connections
    where user_id = p_user_id and imported_data_deleted_at is null
  ) then
    raise exception 'A current calendar source already exists'
      using errcode = 'PT409';
  end if;

  insert into public.calendar_connections (
    user_id,
    create_request_id,
    create_request_fingerprint,
    source_label,
    consent_version,
    read_calendar_events,
    store_event_basics,
    provider_writes,
    llm_processing,
    consented_at,
    connected_at,
    created_at,
    updated_at
  ) values (
    p_user_id,
    p_request_id,
    p_request_fingerprint,
    p_source_label,
    'calendar-import-consent-v1',
    true,
    true,
    false,
    false,
    p_now,
    p_now,
    p_now,
    p_now
  ) returning * into created;

  insert into public.calendar_request_identities (
    request_id,
    user_id,
    connection_id,
    operation,
    created_at
  ) values (
    p_request_id,
    p_user_id,
    created.id,
    'create_connection',
    p_now
  );

  return jsonb_build_object(
    'connection_id', created.id,
    'replayed', false
  );
end;
$$;

create or replace function public.apply_calendar_import_v1(
  p_user_id uuid,
  p_connection_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_input_fingerprint text,
  p_source_fingerprint text,
  p_window_starts_on date,
  p_window_ends_before date,
  p_timezone text,
  p_counts jsonb,
  p_events jsonb,
  p_cancelled_source_keys jsonb,
  p_imported_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  request_identity public.calendar_request_identities%rowtype;
  target_connection public.calendar_connections%rowtype;
  existing_import public.calendar_imports%rowtype;
  created_import public.calendar_imports%rowtype;
  event_row jsonb;
  accepted_count int;
  cancelled_count int;
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
       or request_identity.operation <> 'import_file' then
      raise exception 'Calendar request id was already used'
        using errcode = 'PT409';
    end if;
    request_replay := true;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_connection_id::text, 0));

  select * into target_connection
  from public.calendar_connections
  where id = p_connection_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Calendar connection is unavailable' using errcode = '22023';
  end if;

  if request_replay then
    select * into existing_import
    from public.calendar_imports
    where user_id = p_user_id
      and connection_id = p_connection_id
      and request_id = p_request_id
    limit 1;
    if not found
       or existing_import.input_fingerprint <> p_input_fingerprint
       or target_connection.status <> 'connected'
       or target_connection.imported_data_deleted_at is not null
       or target_connection.last_import_id is distinct from existing_import.id then
      raise exception 'Calendar import request is no longer current'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'connection_id', existing_import.connection_id,
      'import_id', existing_import.id,
      'replayed', true
    );
  end if;

  if target_connection.status <> 'connected'
     or target_connection.imported_data_deleted_at is not null then
    raise exception 'Calendar connection is not connected'
      using errcode = 'PT409';
  end if;

  if jsonb_typeof(p_events) <> 'array'
     or jsonb_array_length(p_events) > 500
     or jsonb_typeof(p_cancelled_source_keys) <> 'array'
     or jsonb_array_length(p_cancelled_source_keys) > 2000
     or jsonb_typeof(p_counts) <> 'object' then
    raise exception 'Calendar import payload is invalid' using errcode = '22023';
  end if;
  accepted_count := (p_counts ->> 'accepted')::int;
  cancelled_count := (p_counts ->> 'cancelled')::int;
  if accepted_count <> jsonb_array_length(p_events)
     or cancelled_count <> jsonb_array_length(p_cancelled_source_keys)
     or accepted_count + cancelled_count
       + (p_counts ->> 'out_of_window')::int
       + (p_counts ->> 'unsupported_recurring')::int
       + (p_counts ->> 'invalid')::int > 2000
     or (
       select count(distinct item ->> 'source_event_key')
       from jsonb_array_elements(p_events) item
     ) <> jsonb_array_length(p_events)
     or (
       select count(distinct value)
       from jsonb_array_elements_text(p_cancelled_source_keys)
     ) <> jsonb_array_length(p_cancelled_source_keys)
     or exists (
       select 1
       from jsonb_array_elements_text(p_cancelled_source_keys) value
       where value !~ '^[0-9a-f]{64}$'
     ) then
    raise exception 'Calendar import counts or identities are invalid'
      using errcode = '22023';
  end if;

  insert into public.calendar_request_identities (
    request_id,
    user_id,
    connection_id,
    operation,
    created_at
  ) values (
    p_request_id,
    p_user_id,
    p_connection_id,
    'import_file',
    p_imported_at
  );

  insert into public.calendar_imports (
    user_id,
    connection_id,
    request_id,
    request_fingerprint,
    input_fingerprint,
    source_fingerprint,
    window_starts_on,
    window_ends_before,
    timezone,
    accepted_count,
    cancelled_count,
    out_of_window_count,
    unsupported_recurring_count,
    invalid_count,
    imported_at,
    created_at
  ) values (
    p_user_id,
    p_connection_id,
    p_request_id,
    p_request_fingerprint,
    p_input_fingerprint,
    p_source_fingerprint,
    p_window_starts_on,
    p_window_ends_before,
    p_timezone,
    accepted_count,
    cancelled_count,
    (p_counts ->> 'out_of_window')::int,
    (p_counts ->> 'unsupported_recurring')::int,
    (p_counts ->> 'invalid')::int,
    p_imported_at,
    p_imported_at
  ) returning * into created_import;

  for event_row in select value from jsonb_array_elements(p_events)
  loop
    insert into public.calendar_events (
      id,
      user_id,
      connection_id,
      import_id,
      source_event_key,
      source_fingerprint,
      title,
      location,
      event_kind,
      busy_status,
      event_status,
      event_timezone,
      timezone_source,
      starts_at,
      ends_at,
      local_starts_at,
      local_ends_at,
      starts_on,
      ends_on,
      last_modified_at,
      sort_date,
      sort_time,
      imported_at,
      last_seen_at,
      created_at,
      updated_at
    ) values (
      (event_row ->> 'id')::uuid,
      p_user_id,
      p_connection_id,
      created_import.id,
      event_row ->> 'source_event_key',
      event_row ->> 'source_fingerprint',
      event_row ->> 'title',
      event_row ->> 'location',
      event_row ->> 'event_kind',
      event_row ->> 'busy_status',
      event_row ->> 'event_status',
      event_row ->> 'event_timezone',
      event_row ->> 'timezone_source',
      (event_row ->> 'starts_at')::timestamptz,
      (event_row ->> 'ends_at')::timestamptz,
      (event_row ->> 'local_starts_at')::timestamp,
      (event_row ->> 'local_ends_at')::timestamp,
      (event_row ->> 'starts_on')::date,
      (event_row ->> 'ends_on')::date,
      (event_row ->> 'last_modified_at')::timestamptz,
      (event_row ->> 'sort_date')::date,
      (event_row ->> 'sort_time')::time,
      p_imported_at,
      p_imported_at,
      p_imported_at,
      p_imported_at
    )
    on conflict (connection_id, source_event_key) do update set
      import_id = excluded.import_id,
      source_fingerprint = excluded.source_fingerprint,
      title = excluded.title,
      location = excluded.location,
      event_kind = excluded.event_kind,
      busy_status = excluded.busy_status,
      event_status = excluded.event_status,
      event_timezone = excluded.event_timezone,
      timezone_source = excluded.timezone_source,
      starts_at = excluded.starts_at,
      ends_at = excluded.ends_at,
      local_starts_at = excluded.local_starts_at,
      local_ends_at = excluded.local_ends_at,
      starts_on = excluded.starts_on,
      ends_on = excluded.ends_on,
      last_modified_at = excluded.last_modified_at,
      sort_date = excluded.sort_date,
      sort_time = excluded.sort_time,
      last_seen_at = excluded.last_seen_at,
      updated_at = excluded.updated_at;
  end loop;

  delete from public.calendar_events target
  where target.user_id = p_user_id
    and target.connection_id = p_connection_id
    and not exists (
      select 1
      from jsonb_array_elements(p_events) item
      where item ->> 'source_event_key' = target.source_event_key
    );

  update public.calendar_connections
  set last_import_id = created_import.id,
      updated_at = p_imported_at
  where id = p_connection_id and user_id = p_user_id;

  return jsonb_build_object(
    'connection_id', p_connection_id,
    'import_id', created_import.id,
    'replayed', false
  );
end;
$$;

create or replace function public.disconnect_calendar_connection_v1(
  p_user_id uuid,
  p_connection_id uuid,
  p_request_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
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
       or request_identity.operation <> 'disconnect' then
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
    if target.status <> 'disconnected'
       or target.disconnect_request_id is distinct from p_request_id then
      raise exception 'Calendar disconnect request does not match durable state'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object('connection_id', target.id, 'replayed', true);
  end if;

  if target.status = 'disconnected' then
    raise exception 'Calendar disconnect request id does not match terminal state'
      using errcode = 'PT409';
  end if;

  insert into public.calendar_request_identities (
    request_id,
    user_id,
    connection_id,
    operation,
    created_at
  ) values (
    p_request_id,
    p_user_id,
    p_connection_id,
    'disconnect',
    p_now
  );

  update public.calendar_connections
  set status = 'disconnected',
      disconnected_at = p_now,
      disconnect_request_id = p_request_id,
      updated_at = p_now
  where id = p_connection_id and user_id = p_user_id;
  return jsonb_build_object('connection_id', p_connection_id, 'replayed', false);
end;
$$;

create or replace function public.delete_calendar_imported_data_v1(
  p_user_id uuid,
  p_connection_id uuid,
  p_request_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
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
    request_id,
    user_id,
    connection_id,
    operation,
    created_at
  ) values (
    p_request_id,
    p_user_id,
    p_connection_id,
    'delete_imported_data',
    p_now
  );

  update public.calendar_connections
  set last_import_id = null,
      imported_data_deleted_at = p_now,
      delete_request_id = p_request_id,
      updated_at = p_now
  where id = p_connection_id and user_id = p_user_id;
  delete from public.calendar_events
  where connection_id = p_connection_id and user_id = p_user_id;
  delete from public.calendar_imports
  where connection_id = p_connection_id and user_id = p_user_id;

  return jsonb_build_object('connection_id', p_connection_id, 'replayed', false);
end;
$$;

revoke all on function public.create_calendar_connection_v1(
  uuid, uuid, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.create_calendar_connection_v1(
  uuid, uuid, text, text, timestamptz
) to service_role;

revoke all on function public.apply_calendar_import_v1(
  uuid, uuid, uuid, text, text, text, date, date, text, jsonb, jsonb, jsonb,
  timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_calendar_import_v1(
  uuid, uuid, uuid, text, text, text, date, date, text, jsonb, jsonb, jsonb,
  timestamptz
) to service_role;

revoke all on function public.disconnect_calendar_connection_v1(
  uuid, uuid, uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.disconnect_calendar_connection_v1(
  uuid, uuid, uuid, timestamptz
) to service_role;

revoke all on function public.delete_calendar_imported_data_v1(
  uuid, uuid, uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.delete_calendar_imported_data_v1(
  uuid, uuid, uuid, timestamptz
) to service_role;
