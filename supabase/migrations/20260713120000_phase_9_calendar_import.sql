-- Phase 9 bounded, consented, manual read-only iCalendar file import.

create table public.calendar_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  create_request_id uuid not null,
  create_request_fingerprint text not null,
  contract_version text not null default 'calendar-import-v1',
  origin text not null default 'authenticated_backend',
  source_kind text not null default 'ical_file',
  source_label text not null,
  status text not null default 'connected',
  consent_version text not null,
  read_calendar_events boolean not null,
  store_event_basics boolean not null,
  provider_writes boolean not null,
  llm_processing boolean not null,
  consented_at timestamptz not null,
  connected_at timestamptz not null,
  disconnected_at timestamptz,
  disconnect_request_id uuid,
  imported_data_deleted_at timestamptz,
  delete_request_id uuid,
  last_import_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint calendar_connections_id_user_key unique (id, user_id),
  constraint calendar_connections_user_create_request_key
    unique (user_id, create_request_id),
  constraint calendar_connections_contract check (
    contract_version = 'calendar-import-v1'
    and origin = 'authenticated_backend'
    and source_kind = 'ical_file'
  ),
  constraint calendar_connections_label_length check (
    length(source_label) between 1 and 80
    and source_label = trim(source_label)
  ),
  constraint calendar_connections_consent check (
    consent_version = 'calendar-import-consent-v1'
    and read_calendar_events
    and store_event_basics
    and not provider_writes
    and not llm_processing
  ),
  constraint calendar_connections_status check (
    (status = 'connected' and disconnected_at is null)
    or (status = 'disconnected' and disconnected_at is not null)
  ),
  constraint calendar_connections_fingerprint check (
    create_request_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint calendar_connections_disconnect_request check (
    (disconnected_at is null and disconnect_request_id is null)
    or (disconnected_at is not null and disconnect_request_id is not null)
  ),
  constraint calendar_connections_delete_request check (
    (imported_data_deleted_at is null and delete_request_id is null)
    or (imported_data_deleted_at is not null and delete_request_id is not null)
  ),
  constraint calendar_connections_deleted_lifecycle check (
    imported_data_deleted_at is null
    or (status = 'disconnected' and last_import_id is null)
  )
);

-- One current source is visible. Deleted minimal tombstones remain available
-- for exact replay/audit while permitting a newly consented source.
create unique index calendar_connections_one_current_per_user_idx
  on public.calendar_connections (user_id)
  where imported_data_deleted_at is null;
create index calendar_connections_user_recent_idx
  on public.calendar_connections (user_id, created_at desc, id desc);
create unique index calendar_connections_user_disconnect_request_idx
  on public.calendar_connections (user_id, disconnect_request_id)
  where disconnect_request_id is not null;
create unique index calendar_connections_user_delete_request_idx
  on public.calendar_connections (user_id, delete_request_id)
  where delete_request_id is not null;

create table public.calendar_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  connection_id uuid not null,
  request_id uuid not null,
  request_fingerprint text not null,
  input_fingerprint text not null,
  source_fingerprint text not null,
  contract_version text not null default 'calendar-import-v1',
  origin text not null default 'authenticated_backend',
  source_kind text not null default 'ical_file',
  window_starts_on date not null,
  window_ends_before date not null,
  timezone text not null,
  accepted_count int not null,
  cancelled_count int not null,
  out_of_window_count int not null,
  unsupported_recurring_count int not null,
  invalid_count int not null,
  imported_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint calendar_imports_id_owner_connection_key
    unique (id, user_id, connection_id),
  constraint calendar_imports_user_request_key unique (user_id, request_id),
  constraint calendar_imports_connection_owner_fk
    foreign key (connection_id, user_id)
    references public.calendar_connections (id, user_id)
    on delete cascade,
  constraint calendar_imports_contract check (
    contract_version = 'calendar-import-v1'
    and origin = 'authenticated_backend'
    and source_kind = 'ical_file'
  ),
  constraint calendar_imports_fingerprints check (
    request_fingerprint ~ '^[0-9a-f]{64}$'
    and input_fingerprint ~ '^[0-9a-f]{64}$'
    and source_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint calendar_imports_window check (
    window_ends_before = window_starts_on + 105
    and length(trim(timezone)) between 1 and 100
  ),
  constraint calendar_imports_counts check (
    accepted_count between 0 and 500
    and cancelled_count between 0 and 2000
    and out_of_window_count between 0 and 2000
    and unsupported_recurring_count between 0 and 2000
    and invalid_count between 0 and 2000
    and accepted_count + cancelled_count + out_of_window_count
      + unsupported_recurring_count + invalid_count <= 2000
  )
);

alter table public.calendar_connections
  add constraint calendar_connections_last_import_fk
  foreign key (last_import_id, user_id, id)
  references public.calendar_imports (id, user_id, connection_id)
  on delete set null (last_import_id);

create index calendar_imports_connection_recent_idx
  on public.calendar_imports (connection_id, imported_at desc, id desc);

create table public.calendar_events (
  id uuid primary key,
  user_id uuid not null,
  connection_id uuid not null,
  import_id uuid not null,
  contract_version text not null default 'calendar-import-v1',
  origin text not null default 'authenticated_backend',
  source_kind text not null default 'ical_file',
  source_event_key text not null,
  source_fingerprint text not null,
  title text not null,
  location text,
  event_kind text not null,
  busy_status text not null,
  event_status text not null,
  event_timezone text not null,
  timezone_source text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  local_starts_at timestamp,
  local_ends_at timestamp,
  starts_on date,
  ends_on date,
  last_modified_at timestamptz,
  sort_date date not null,
  sort_time time not null,
  imported_at timestamptz not null,
  last_seen_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint calendar_events_connection_source_key
    unique (connection_id, source_event_key),
  constraint calendar_events_connection_owner_fk
    foreign key (connection_id, user_id)
    references public.calendar_connections (id, user_id)
    on delete cascade,
  constraint calendar_events_import_owner_connection_fk
    foreign key (import_id, user_id, connection_id)
    references public.calendar_imports (id, user_id, connection_id)
    on delete cascade,
  constraint calendar_events_contract check (
    contract_version = 'calendar-import-v1'
    and origin = 'authenticated_backend'
    and source_kind = 'ical_file'
  ),
  constraint calendar_events_fingerprints check (
    source_event_key ~ '^[0-9a-f]{64}$'
    and source_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint calendar_events_text_bounds check (
    length(title) between 1 and 200
    and (location is null or length(location) between 1 and 300)
    and length(trim(event_timezone)) between 1 and 100
  ),
  constraint calendar_events_enums check (
    event_kind in ('timed', 'all_day')
    and busy_status in ('busy', 'free')
    and event_status in ('confirmed', 'tentative')
    and timezone_source in ('utc', 'event', 'profile')
  ),
  constraint calendar_events_temporal_shape check (
    (
      event_kind = 'timed'
      and starts_at is not null
      and ends_at is not null
      and ends_at > starts_at
      and local_starts_at is not null
      and local_ends_at is not null
      and starts_on is null
      and ends_on is null
    )
    or
    (
      event_kind = 'all_day'
      and starts_at is null
      and ends_at is null
      and local_starts_at is null
      and local_ends_at is null
      and starts_on is not null
      and ends_on is not null
      and ends_on > starts_on
      and timezone_source = 'profile'
    )
  ),
  constraint calendar_events_seen_after_import check (
    last_seen_at >= imported_at
  )
);

create index calendar_events_connection_order_idx
  on public.calendar_events (
    connection_id,
    import_id,
    sort_date,
    sort_time,
    id
  );

alter table public.calendar_connections enable row level security;
alter table public.calendar_connections force row level security;
alter table public.calendar_imports enable row level security;
alter table public.calendar_imports force row level security;
alter table public.calendar_events enable row level security;
alter table public.calendar_events force row level security;

grant usage on schema public to authenticated, service_role;
revoke all on table public.calendar_connections,
  public.calendar_imports,
  public.calendar_events
from anon, authenticated, service_role;
grant select (
  id,
  contract_version,
  origin,
  source_kind,
  source_label,
  status,
  consent_version,
  read_calendar_events,
  store_event_basics,
  provider_writes,
  llm_processing,
  consented_at,
  connected_at,
  disconnected_at,
  imported_data_deleted_at,
  last_import_id
) on public.calendar_connections to authenticated;
grant select (
  id,
  connection_id,
  import_id,
  contract_version,
  origin,
  source_kind,
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
  imported_at,
  last_seen_at
) on public.calendar_events to authenticated;
grant select, insert, update, delete on table public.calendar_connections,
  public.calendar_imports,
  public.calendar_events
to service_role;

create policy "calendar_connections_own_or_admin_select"
  on public.calendar_connections
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "calendar_connections_service_role_all"
  on public.calendar_connections
  for all
  to service_role
  using (true)
  with check (true);

create policy "calendar_imports_service_role_all"
  on public.calendar_imports
  for all
  to service_role
  using (true)
  with check (true);

create policy "calendar_events_own_or_admin_select"
  on public.calendar_events
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "calendar_events_service_role_all"
  on public.calendar_events
  for all
  to service_role
  using (true)
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
  existing public.calendar_connections%rowtype;
  created public.calendar_connections%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select * into existing
  from public.calendar_connections
  where user_id = p_user_id and create_request_id = p_request_id
  limit 1;

  if found then
    if existing.create_request_fingerprint <> p_request_fingerprint then
      raise exception 'Calendar connection request id was already used'
        using errcode = '40001';
    end if;
    return jsonb_build_object('connection_id', existing.id, 'replayed', true);
  end if;

  if exists (
    select 1 from public.calendar_connections
    where user_id = p_user_id and imported_data_deleted_at is null
  ) then
    raise exception 'A current calendar source already exists'
      using errcode = '40001';
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

  return jsonb_build_object('connection_id', created.id, 'replayed', false);
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
  target_connection public.calendar_connections%rowtype;
  existing_import public.calendar_imports%rowtype;
  created_import public.calendar_imports%rowtype;
  event_row jsonb;
  accepted_count int;
  cancelled_count int;
begin
  -- A request replay is resolved before current connection state or scope is
  -- considered, so an unchanged retry after local midnight returns its pinned
  -- import identity.
  select * into existing_import
  from public.calendar_imports
  where user_id = p_user_id and request_id = p_request_id
  limit 1;

  if found then
    if existing_import.connection_id <> p_connection_id
       or existing_import.input_fingerprint <> p_input_fingerprint then
      raise exception 'Calendar import request id was already used'
        using errcode = '40001';
    end if;
    return jsonb_build_object(
      'connection_id', existing_import.connection_id,
      'import_id', existing_import.id,
      'replayed', true
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_connection_id::text, 0));

  -- Re-check after the lock for a concurrent same-request worker.
  select * into existing_import
  from public.calendar_imports
  where user_id = p_user_id and request_id = p_request_id
  limit 1;
  if found then
    if existing_import.connection_id <> p_connection_id
       or existing_import.input_fingerprint <> p_input_fingerprint then
      raise exception 'Calendar import request id was already used'
        using errcode = '40001';
    end if;
    return jsonb_build_object(
      'connection_id', existing_import.connection_id,
      'import_id', existing_import.id,
      'replayed', true
    );
  end if;

  select * into target_connection
  from public.calendar_connections
  where id = p_connection_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Calendar connection is unavailable' using errcode = '22023';
  end if;
  if target_connection.status <> 'connected'
     or target_connection.imported_data_deleted_at is not null then
    raise exception 'Calendar connection is not connected' using errcode = '40001';
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

  -- The parsed file is the complete bounded current-copy snapshot. Anything
  -- absent (including a cancellation tombstone) leaves no current event row.
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
  target public.calendar_connections%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_connection_id::text, 0));
  select * into target
  from public.calendar_connections
  where id = p_connection_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Calendar connection is unavailable' using errcode = '22023';
  end if;
  if target.status = 'disconnected' then
    if target.disconnect_request_id <> p_request_id then
      raise exception 'Calendar disconnect request id does not match terminal state'
        using errcode = '40001';
    end if;
    return jsonb_build_object('connection_id', target.id, 'replayed', true);
  end if;
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
  target public.calendar_connections%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_connection_id::text, 0));
  select * into target
  from public.calendar_connections
  where id = p_connection_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Calendar connection is unavailable' using errcode = '22023';
  end if;
  if target.imported_data_deleted_at is not null then
    if target.delete_request_id <> p_request_id then
      raise exception 'Calendar delete request id does not match terminal state'
        using errcode = '40001';
    end if;
    return jsonb_build_object('connection_id', target.id, 'replayed', true);
  end if;
  if target.status <> 'disconnected' then
    raise exception 'Disconnect calendar source before deleting imported data'
      using errcode = '40001';
  end if;

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
