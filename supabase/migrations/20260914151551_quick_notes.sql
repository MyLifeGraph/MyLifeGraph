-- Optional confirmed text context. No daily_logs, numeric values, or capture writes.
create table private.quick_note_identities (
  note_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  fingerprint text not null check (length(fingerprint) = 64),
  deleted boolean not null default false
);
alter table private.quick_note_identities enable row level security;
alter table private.quick_note_identities force row level security;
revoke all on private.quick_note_identities from public, anon, authenticated;
grant select, insert, update, delete on private.quick_note_identities to service_role;
create index quick_note_identities_owner_idx on private.quick_note_identities(user_id);
create index behavioral_events_quick_notes_page_idx
  on public.behavioral_events(user_id, created_at desc, id desc)
  where source = 'quick_note' and event_type = 'quick_note';

create function private.quick_notes_timezone_v1(p_user_id uuid)
returns text language plpgsql security invoker set search_path = '' as $$
declare profile public.profiles%rowtype;
begin
  if p_user_id is null or (public.get_account_deletion_pending_v2(p_user_id) ->> 'pending')::boolean then
    raise exception 'Account unavailable.' using errcode = '42501';
  end if;
  select * into profile from public.profiles where id = p_user_id;
  if not found or profile.onboarding_completed_at is null
     or profile.auth_provider in ('guest', 'anonymous') or profile.role = 'guest'
     or profile.timezone is null or not exists (
       select 1 from pg_catalog.pg_timezone_names where name = profile.timezone
     ) then
    raise exception 'Configured account required.' using errcode = '42501';
  end if;
  return profile.timezone;
end;
$$;
revoke all on function private.quick_notes_timezone_v1(uuid) from public, anon, authenticated;
grant execute on function private.quick_notes_timezone_v1(uuid) to service_role;

create function public.save_quick_note_v1(p_user_id uuid, p_request jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  target_note_id uuid;
  note_text text;
  zone text;
  request_hash text;
  identity private.quick_note_identities%rowtype;
  note public.behavioral_events%rowtype;
  replayed boolean := false;
begin
  if jsonb_typeof(p_request) is distinct from 'object'
     or p_request ->> 'contract_version' is distinct from 'quick-notes-v1'
     or (select count(*) from jsonb_object_keys(p_request)) <> 4
     or not p_request ?& array['contract_version', 'note_id', 'timezone', 'text']
     or jsonb_typeof(p_request -> 'note_id') is distinct from 'string'
     or jsonb_typeof(p_request -> 'timezone') is distinct from 'string'
     or jsonb_typeof(p_request -> 'text') is distinct from 'string'
     or length(p_request ->> 'text') not between 1 and 2000
     or length(btrim(p_request ->> 'text', E' \n\r\t')) = 0
     or octet_length(p_request::text) > 16000 then
    raise exception 'Invalid note.' using errcode = '22023';
  end if;
  target_note_id := (p_request ->> 'note_id')::uuid;
  note_text := p_request ->> 'text';
  if p_user_id is null or target_note_id is null then
    raise exception 'Invalid note identity.' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  zone := private.quick_notes_timezone_v1(p_user_id);
  request_hash := encode(sha256(convert_to(p_request::text, 'UTF8')), 'hex');
  select * into identity from private.quick_note_identities where note_id = target_note_id;
  if found then
    if identity.user_id <> p_user_id or identity.fingerprint <> request_hash or identity.deleted then
      raise exception 'Note identity conflict.' using errcode = 'PT409';
    end if;
    replayed := true;
  else
    if p_request ->> 'timezone' is distinct from zone then
      raise exception 'Account timezone changed.' using errcode = 'PT409';
    end if;
    insert into private.quick_note_identities(note_id, user_id, fingerprint)
      values (target_note_id, p_user_id, request_hash);
    insert into public.behavioral_events(id, user_id, event_type, value, unit, occurred_at, source, metadata)
      values (target_note_id, p_user_id, 'quick_note', null, null, now(), 'quick_note', jsonb_build_object(
        'contract_version', 'quick-notes-v1', 'text', note_text,
        'entry_date', (now() at time zone zone)::date, 'timezone', zone
      ));
  end if;
  select * into note from public.behavioral_events where id = target_note_id
    and user_id = p_user_id and source = 'quick_note' and event_type = 'quick_note';
  if not found then
    raise exception 'Note identity conflict.' using errcode = 'PT409';
  end if;
  return jsonb_build_object('contract_version', 'quick-notes-v1', 'replayed', replayed,
    'note', jsonb_build_object('id', note.id, 'text', note.metadata ->> 'text',
      'entry_date', note.metadata ->> 'entry_date', 'timezone', note.metadata ->> 'timezone',
      'created_at', note.created_at));
exception when unique_violation then
  raise exception 'Note identity conflict.' using errcode = 'PT409';
end;
$$;
revoke all on function public.save_quick_note_v1(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.save_quick_note_v1(uuid,jsonb) to service_role;

create function public.read_quick_notes_v1(p_user_id uuid, p_before uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  zone text := private.quick_notes_timezone_v1(p_user_id);
  cursor_time timestamptz;
  notes jsonb;
  next_cursor uuid;
begin
  if p_before is not null then
    select created_at into cursor_time from public.behavioral_events
      where id = p_before and user_id = p_user_id and source = 'quick_note' and event_type = 'quick_note';
    if not found then
      raise exception 'Note cursor unavailable.' using errcode = '22023';
    end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'text', n.metadata ->> 'text',
    'entry_date', n.metadata ->> 'entry_date', 'timezone', n.metadata ->> 'timezone',
    'created_at', n.created_at) order by n.created_at desc, n.id desc), '[]'::jsonb)
  into notes from (
    select id, metadata, created_at from public.behavioral_events
    where user_id = p_user_id and source = 'quick_note' and event_type = 'quick_note'
      and (p_before is null or (created_at, id) < (cursor_time, p_before))
    order by created_at desc, id desc limit 51
  ) n;
  if jsonb_array_length(notes) > 50 then
    next_cursor := (notes -> 49 ->> 'id')::uuid;
    notes := notes - 50;
  end if;
  return jsonb_build_object('contract_version', 'quick-notes-v1', 'timezone', zone,
    'notes', notes, 'next_cursor', next_cursor);
end;
$$;
revoke all on function public.read_quick_notes_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function public.read_quick_notes_v1(uuid,uuid) to service_role;

create function public.delete_quick_note_v1(p_user_id uuid, p_note_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  if p_user_id is null or p_note_id is null then
    raise exception 'Invalid note identity.' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  perform private.quick_notes_timezone_v1(p_user_id);
  update private.quick_note_identities set deleted = true
    where user_id = p_user_id and note_id = p_note_id;
  if not found then
    raise exception 'Note not found.' using errcode = 'PT404';
  end if;
  delete from public.behavioral_events where id = p_note_id and user_id = p_user_id
    and source = 'quick_note' and event_type = 'quick_note';
  return jsonb_build_object('contract_version', 'quick-notes-v1', 'note_id', p_note_id, 'deleted', true);
end;
$$;
revoke all on function public.delete_quick_note_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function public.delete_quick_note_v1(uuid,uuid) to service_role;
