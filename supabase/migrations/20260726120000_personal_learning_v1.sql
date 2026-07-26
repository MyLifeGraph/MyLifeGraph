-- Personal Learning V1: editable terminal Focus reflections, revisioned
-- preferences, and retry-safe preference/history commands.

do $focus_session_owner_key$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_id_user_id_key'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_id_user_id_key unique (id, user_id);
  end if;
end;
$focus_session_owner_key$;

create table public.focus_session_reflections (
  focus_session_id uuid primary key,
  user_id uuid not null,
  contract_version text not null default 'focus-reflection-v1'
    check (contract_version = 'focus-reflection-v1'),
  focus_quality smallint not null check (focus_quality between 1 and 5),
  useful_progress smallint not null check (useful_progress between 1 and 5),
  obstacles text[] not null default array[]::text[],
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint focus_session_reflections_owner_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade,
  constraint focus_session_reflections_session_owner_fkey
    foreign key (focus_session_id, user_id)
    references public.focus_sessions (id, user_id) on delete cascade,
  constraint focus_session_reflections_obstacles_check check (
    cardinality(obstacles) between 0 and 2
    and array_position(obstacles, null) is null
    and obstacles <@ array[
      'tired',
      'distracted',
      'interrupted',
      'unclear_goal',
      'material_too_difficult',
      'session_too_long',
      'environment',
      'other'
    ]::text[]
    and (
      cardinality(obstacles) <> 2
      or obstacles[1] is distinct from obstacles[2]
    )
  ),
  constraint focus_session_reflections_timestamp_order_check
    check (created_at <= updated_at)
);

create index focus_session_reflections_user_updated_idx
  on public.focus_session_reflections (user_id, updated_at desc);

create or replace function private.guard_focus_session_reflection_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  changed_at timestamptz;
begin
  perform 1
  from public.focus_sessions as focus
  where focus.id = new.focus_session_id
    and focus.user_id = new.user_id
    and focus.status in ('completed', 'abandoned')
  for key share;

  if not found then
    raise exception
      'A Focus reflection requires an owned terminal session'
      using errcode = '23514';
  end if;

  changed_at := clock_timestamp();
  if tg_op = 'INSERT' then
    new.contract_version := 'focus-reflection-v1';
    new.created_at := changed_at;
    new.updated_at := changed_at;
  else
    if new.focus_session_id is distinct from old.focus_session_id
       or new.user_id is distinct from old.user_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Focus reflection identity is immutable'
        using errcode = '23514';
    end if;
    new.contract_version := 'focus-reflection-v1';
    new.created_at := old.created_at;
    new.updated_at := greatest(
      changed_at,
      old.updated_at + interval '1 microsecond'
    );
  end if;
  return new;
end;
$$;

revoke all on function private.guard_focus_session_reflection_v1()
  from public, anon, authenticated, service_role;

create trigger focus_session_reflections_guard_v1
before insert or update on public.focus_session_reflections
for each row execute function private.guard_focus_session_reflection_v1();

create table public.learning_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  contract_version text not null default 'learning-preferences-v1'
    check (contract_version = 'learning-preferences-v1'),
  revision int not null default 0 check (revision >= 0),
  focus_reflection_prompt_enabled boolean not null default true,
  personal_pattern_analysis_enabled boolean not null default true,
  learned_focus_planning_enabled boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint learning_preferences_analysis_dependency_check check (
    not learned_focus_planning_enabled
    or personal_pattern_analysis_enabled
  ),
  constraint learning_preferences_timestamp_order_check
    check (created_at <= updated_at)
);

create table public.learning_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  contract_version text not null default 'learning-request-v1'
    check (contract_version = 'learning-request-v1'),
  action text not null check (
    action in ('update_preferences', 'clear_focus_reflections')
  ),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  expected_revision int not null check (expected_revision >= 0),
  result jsonb not null check (
    jsonb_typeof(result) = 'object'
    and result ->> 'contract_version'
      in ('learning-preferences-v1', 'focus-reflection-v1')
  ),
  created_at timestamptz not null default clock_timestamp()
);

create index learning_request_identities_user_created_idx
  on public.learning_request_identities (user_id, created_at desc);

insert into public.learning_preferences (user_id)
select profile.id
from public.profiles as profile
on conflict (user_id) do nothing;

create or replace function private.ensure_learning_preferences_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  insert into public.learning_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function private.ensure_learning_preferences_v1()
  from public, anon, authenticated, service_role;

create trigger profiles_ensure_learning_preferences_v1
after insert on public.profiles
for each row execute function private.ensure_learning_preferences_v1();

alter table public.focus_session_reflections enable row level security;
alter table public.focus_session_reflections force row level security;
alter table public.learning_preferences enable row level security;
alter table public.learning_preferences force row level security;
alter table public.learning_request_identities enable row level security;
alter table public.learning_request_identities force row level security;

create policy focus_session_reflections_owner_select_v1
on public.focus_session_reflections
for select to authenticated
using ((select auth.uid()) = user_id);

create policy focus_session_reflections_owner_insert_v1
on public.focus_session_reflections
for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy focus_session_reflections_owner_update_v1
on public.focus_session_reflections
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy focus_session_reflections_owner_delete_v1
on public.focus_session_reflections
for delete to authenticated
using ((select auth.uid()) = user_id);

create policy learning_preferences_owner_select_v1
on public.learning_preferences
for select to authenticated
using ((select auth.uid()) = user_id);

revoke all privileges on table public.focus_session_reflections
  from public, anon;
revoke all privileges on table public.learning_preferences
  from public, anon, authenticated;
revoke all privileges on table public.learning_request_identities
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.focus_session_reflections to authenticated;
revoke truncate, references, trigger
  on table public.focus_session_reflections from authenticated;
grant select on table public.learning_preferences to authenticated;

grant select, insert, update, delete
  on table public.focus_session_reflections to service_role;
grant select, insert, update, delete
  on table public.learning_preferences to service_role;
grant select, insert, delete
  on table public.learning_request_identities to service_role;

create or replace function public.update_learning_preferences_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_expected_revision int,
  p_focus_reflection_prompt_enabled boolean,
  p_personal_pattern_analysis_enabled boolean,
  p_learned_focus_planning_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_preferences public.learning_preferences%rowtype;
  existing_request public.learning_request_identities%rowtype;
  request_fingerprint text;
  response jsonb;
  changed_at timestamptz;
begin
  if p_user_id is null
     or p_request_id is null
     or p_expected_revision is null
     or p_expected_revision < 0
     or p_focus_reflection_prompt_enabled is null
     or p_personal_pattern_analysis_enabled is null
     or p_learned_focus_planning_enabled is null
     or (
       p_learned_focus_planning_enabled
       and not p_personal_pattern_analysis_enabled
     ) then
    raise exception 'Invalid Personal learning preference request'
      using errcode = '22023';
  end if;

  request_fingerprint := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'contract_version', 'learning-preferences-v1',
          'user_id', p_user_id,
          'request_id', p_request_id,
          'expected_revision', p_expected_revision,
          'focus_reflection_prompt_enabled',
            p_focus_reflection_prompt_enabled,
          'personal_pattern_analysis_enabled',
            p_personal_pattern_analysis_enabled,
          'learned_focus_planning_enabled',
            p_learned_focus_planning_enabled
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 1));

  select * into existing_request
  from public.learning_request_identities
  where request_id = p_request_id
  for update;

  if found then
    if existing_request.user_id is distinct from p_user_id
       or existing_request.action <> 'update_preferences'
       or existing_request.request_fingerprint
         is distinct from request_fingerprint
       or existing_request.expected_revision <> p_expected_revision then
      raise exception 'Personal learning request id was already used'
        using errcode = 'PT409';
    end if;
    return existing_request.result || jsonb_build_object('replayed', true);
  end if;

  insert into public.learning_preferences (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into current_preferences
  from public.learning_preferences
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'Personal learning preferences are unavailable'
      using errcode = 'PT404';
  end if;
  if current_preferences.revision <> p_expected_revision then
    raise exception 'Personal learning preferences changed since they were loaded'
      using errcode = 'PT409';
  end if;

  changed_at := greatest(
    clock_timestamp(),
    current_preferences.updated_at + interval '1 microsecond'
  );
  update public.learning_preferences
  set
    revision = current_preferences.revision + 1,
    focus_reflection_prompt_enabled =
      p_focus_reflection_prompt_enabled,
    personal_pattern_analysis_enabled =
      p_personal_pattern_analysis_enabled,
    learned_focus_planning_enabled =
      p_learned_focus_planning_enabled,
    updated_at = changed_at
  where user_id = p_user_id
  returning * into current_preferences;

  response := jsonb_build_object(
    'contract_version', 'learning-preferences-v1',
    'revision', current_preferences.revision,
    'focus_reflection_prompt_enabled',
      current_preferences.focus_reflection_prompt_enabled,
    'personal_pattern_analysis_enabled',
      current_preferences.personal_pattern_analysis_enabled,
    'learned_focus_planning_enabled',
      current_preferences.learned_focus_planning_enabled,
    'updated_at', current_preferences.updated_at,
    'replayed', false
  );

  insert into public.learning_request_identities (
    request_id,
    user_id,
    action,
    request_fingerprint,
    expected_revision,
    result
  ) values (
    p_request_id,
    p_user_id,
    'update_preferences',
    request_fingerprint,
    p_expected_revision,
    response
  );
  return response;
end;
$$;

create or replace function public.clear_focus_reflection_history_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_expected_revision int,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_preferences public.learning_preferences%rowtype;
  existing_request public.learning_request_identities%rowtype;
  request_fingerprint text;
  response jsonb;
  deleted_count int;
  cleared_at timestamptz;
begin
  if p_user_id is null
     or p_request_id is null
     or p_expected_revision is null
     or p_expected_revision < 0
     or p_confirmation is distinct from 'CLEAR' then
    raise exception 'Invalid Focus reflection clear request'
      using errcode = '22023';
  end if;

  request_fingerprint := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'contract_version', 'focus-reflection-v1',
          'user_id', p_user_id,
          'request_id', p_request_id,
          'expected_revision', p_expected_revision,
          'confirmation', p_confirmation
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 1));

  select * into existing_request
  from public.learning_request_identities
  where request_id = p_request_id
  for update;

  if found then
    if existing_request.user_id is distinct from p_user_id
       or existing_request.action <> 'clear_focus_reflections'
       or existing_request.request_fingerprint
         is distinct from request_fingerprint
       or existing_request.expected_revision <> p_expected_revision then
      raise exception 'Personal learning request id was already used'
        using errcode = 'PT409';
    end if;
    return existing_request.result || jsonb_build_object('replayed', true);
  end if;

  insert into public.learning_preferences (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into current_preferences
  from public.learning_preferences
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'Personal learning preferences are unavailable'
      using errcode = 'PT404';
  end if;
  if current_preferences.revision <> p_expected_revision then
    raise exception 'Personal learning preferences changed since they were loaded'
      using errcode = 'PT409';
  end if;

  delete from public.focus_session_reflections
  where user_id = p_user_id;
  get diagnostics deleted_count = row_count;
  cleared_at := clock_timestamp();

  response := jsonb_build_object(
    'contract_version', 'focus-reflection-v1',
    'revision', current_preferences.revision,
    'deleted_count', deleted_count,
    'cleared_at', cleared_at,
    'replayed', false
  );

  insert into public.learning_request_identities (
    request_id,
    user_id,
    action,
    request_fingerprint,
    expected_revision,
    result
  ) values (
    p_request_id,
    p_user_id,
    'clear_focus_reflections',
    request_fingerprint,
    p_expected_revision,
    response
  );
  return response;
end;
$$;

revoke all on function public.update_learning_preferences_v1(
  uuid, uuid, int, boolean, boolean, boolean
) from public, anon, authenticated;
grant execute on function public.update_learning_preferences_v1(
  uuid, uuid, int, boolean, boolean, boolean
) to service_role;

revoke all on function public.clear_focus_reflection_history_v1(
  uuid, uuid, int, text
) from public, anon, authenticated;
grant execute on function public.clear_focus_reflection_history_v1(
  uuid, uuid, int, text
) to service_role;
