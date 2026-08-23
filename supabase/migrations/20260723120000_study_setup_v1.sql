-- Optional Study Setup V1: revisioned focus rhythm, local start ritual,
-- semester facts, recovery reservations, and stale-plan guards.

create or replace function private.study_setup_profile_is_valid(
  p_focus_minutes int,
  p_recovery_minutes int,
  p_preparation_items jsonb,
  p_current_semester jsonb,
  p_next_semester jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  item jsonb;
  course jsonb;
  current_starts date;
  current_ends date;
  next_starts date;
  next_ends date;
  selection_starts date;
  selection_ends date;
begin
  if (p_focus_minutes is null) <> (p_recovery_minutes is null) then
    return false;
  end if;
  if p_focus_minutes is null then
    if p_preparation_items <> '[]'::jsonb then
      return false;
    end if;
  elsif p_focus_minutes not between 25 and 180
     or p_focus_minutes % 5 <> 0
     or p_recovery_minutes not between 5 and 60
     or p_recovery_minutes % 5 <> 0
     or jsonb_typeof(p_preparation_items) <> 'array'
     or jsonb_array_length(p_preparation_items) > 12 then
    return false;
  end if;

  for item in select value from jsonb_array_elements(p_preparation_items)
  loop
    if jsonb_typeof(item) <> 'object'
       or not (item ?& array['key', 'label', 'active'])
       or item - array['key', 'label', 'active'] <> '{}'::jsonb
       or jsonb_typeof(item -> 'key') <> 'string'
       or (item ->> 'key') !~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(item -> 'label') <> 'string'
       or length(item ->> 'label') not between 1 and 120
       or item ->> 'label' <> btrim(item ->> 'label')
       or jsonb_typeof(item -> 'active') <> 'boolean' then
      return false;
    end if;
  end loop;
  if (
    select count(*) <> count(distinct lower(value ->> 'key'))
      or count(*) <> count(distinct lower(value ->> 'label'))
    from jsonb_array_elements(p_preparation_items) as values(value)
  ) then
    return false;
  end if;

  if (p_current_semester is null) <> (p_next_semester is null) then
    return false;
  end if;
  if p_current_semester is null then
    return true;
  end if;
  if jsonb_typeof(p_current_semester) <> 'object'
     or not (p_current_semester ?& array['name', 'starts_on', 'ends_on'])
     or p_current_semester - array['name', 'starts_on', 'ends_on'] <> '{}'::jsonb
     or jsonb_typeof(p_current_semester -> 'name') <> 'string'
     or length(p_current_semester ->> 'name') not between 1 and 120
     or p_current_semester ->> 'name' <> btrim(p_current_semester ->> 'name')
     or (p_current_semester ->> 'starts_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or (p_current_semester ->> 'ends_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or jsonb_typeof(p_next_semester) <> 'object'
     or not (
       p_next_semester ?& array[
         'name', 'starts_on', 'ends_on', 'course_selection_starts_on',
         'course_selection_ends_on', 'course_names',
         'course_selection_completed'
       ]
     )
     or p_next_semester - array[
       'name', 'starts_on', 'ends_on', 'course_selection_starts_on',
       'course_selection_ends_on', 'course_names',
       'course_selection_completed'
     ] <> '{}'::jsonb
     or jsonb_typeof(p_next_semester -> 'name') <> 'string'
     or length(p_next_semester ->> 'name') not between 1 and 120
     or p_next_semester ->> 'name' <> btrim(p_next_semester ->> 'name')
     or (p_next_semester ->> 'starts_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or (p_next_semester ->> 'ends_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or (p_next_semester ->> 'course_selection_starts_on')
        !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or (p_next_semester ->> 'course_selection_ends_on')
        !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or jsonb_typeof(p_next_semester -> 'course_names') <> 'array'
     or jsonb_array_length(p_next_semester -> 'course_names') > 12
     or jsonb_typeof(p_next_semester -> 'course_selection_completed')
        <> 'boolean' then
    return false;
  end if;

  for course in
    select value from jsonb_array_elements(p_next_semester -> 'course_names')
  loop
    if jsonb_typeof(course) <> 'string'
       or length(course #>> '{}') not between 1 and 120
       or course #>> '{}' <> btrim(course #>> '{}') then
      return false;
    end if;
  end loop;
  if (
    select count(*) <> count(distinct lower(value #>> '{}'))
    from jsonb_array_elements(p_next_semester -> 'course_names') as values(value)
  ) then
    return false;
  end if;

  current_starts := (p_current_semester ->> 'starts_on')::date;
  current_ends := (p_current_semester ->> 'ends_on')::date;
  next_starts := (p_next_semester ->> 'starts_on')::date;
  next_ends := (p_next_semester ->> 'ends_on')::date;
  selection_starts :=
    (p_next_semester ->> 'course_selection_starts_on')::date;
  selection_ends :=
    (p_next_semester ->> 'course_selection_ends_on')::date;
  return current_starts <= current_ends
    and current_ends < next_starts
    and next_starts <= next_ends
    and selection_starts <= selection_ends;
exception
  when others then
    return false;
end;
$$;

revoke all on function private.study_setup_profile_is_valid(
  int, int, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

create table public.study_setup_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  contract_version text not null default 'study-setup-v1',
  focus_minutes int,
  recovery_minutes int,
  preparation_items jsonb not null default '[]'::jsonb,
  current_semester jsonb,
  next_semester jsonb,
  setup_revision int not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  constraint study_setup_profiles_contract_check check (
    contract_version = 'study-setup-v1'
    and setup_revision >= 1
    and updated_at >= created_at
    and private.study_setup_profile_is_valid(
      focus_minutes,
      recovery_minutes,
      preparation_items,
      current_semester,
      next_semester
    )
  )
);

alter table public.study_setup_profiles enable row level security;
alter table public.study_setup_profiles force row level security;
revoke all on table public.study_setup_profiles from public, anon, authenticated;
grant select on table public.study_setup_profiles to authenticated;
grant select, insert, update, delete
on table public.study_setup_profiles to service_role;

create policy study_setup_profiles_owner_select
on public.study_setup_profiles
for select
to authenticated
using (
  (select auth.uid()) = user_id
  or (select private.current_app_role()) = 'admin'
);

create policy study_setup_profiles_service_all
on public.study_setup_profiles
for all
to service_role
using (true)
with check (true);

alter table public.deadline_plan_revisions
  add column study_setup_revision int,
  add column recovery_minutes int not null default 0,
  add constraint deadline_plan_revisions_study_setup_check check (
    (
      study_setup_revision is null
      and recovery_minutes = 0
    )
    or (
      study_setup_revision >= 1
      and recovery_minutes between 5 and 60
      and recovery_minutes % 5 = 0
    )
  );

alter table public.deadline_plan_blocks
  add column recovery_minutes int not null default 0,
  add column reserved_ends_at timestamptz;
update public.deadline_plan_blocks set reserved_ends_at = ends_at;
alter table public.deadline_plan_blocks
  alter column reserved_ends_at set not null,
  alter column reserved_ends_at set default now(),
  add constraint deadline_plan_blocks_recovery_check check (
    recovery_minutes between 0 and 60
    and recovery_minutes % 5 = 0
    and reserved_ends_at = ends_at + recovery_minutes * interval '1 minute'
  );
alter table public.deadline_plan_blocks
  alter column reserved_ends_at drop default;

create or replace function private.default_recovery_reservation_end()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  if new.reserved_ends_at is null then
    new.reserved_ends_at := new.ends_at;
  end if;
  return new;
end;
$$;

revoke all on function private.default_recovery_reservation_end()
from public, anon, authenticated, service_role;

create trigger deadline_plan_blocks_default_recovery_end
before insert on public.deadline_plan_blocks
for each row execute function private.default_recovery_reservation_end();

drop index public.deadline_plan_blocks_user_active_time_idx;
create index deadline_plan_blocks_user_active_time_idx
on public.deadline_plan_blocks (user_id, starts_at, reserved_ends_at, id)
where reservation_state = 'active';

alter table public.planner_action_plan_revisions
  add column study_setup_revision int,
  add column recovery_minutes int not null default 0,
  add constraint planner_action_revisions_study_setup_check check (
    (
      study_setup_revision is null
      and recovery_minutes = 0
    )
    or (
      study_setup_revision >= 1
      and recovery_minutes between 5 and 60
      and recovery_minutes % 5 = 0
    )
  );

alter table public.planner_task_blocks
  add column recovery_minutes int not null default 0,
  add column reserved_ends_at timestamptz;
update public.planner_task_blocks set reserved_ends_at = ends_at;
alter table public.planner_task_blocks
  alter column reserved_ends_at set not null,
  alter column reserved_ends_at set default now(),
  add constraint planner_task_blocks_recovery_check check (
    recovery_minutes between 0 and 60
    and recovery_minutes % 5 = 0
    and reserved_ends_at = ends_at + recovery_minutes * interval '1 minute'
  );
alter table public.planner_task_blocks
  alter column reserved_ends_at drop default;

create trigger planner_task_blocks_default_recovery_end
before insert on public.planner_task_blocks
for each row execute function private.default_recovery_reservation_end();

drop index public.planner_task_blocks_owner_active_time_idx;
create index planner_task_blocks_owner_active_time_idx
on public.planner_task_blocks (user_id, starts_at, reserved_ends_at, id)
where state = 'active';

-- Keep the large, already-verified RPC bodies as uncallable inner functions.
-- The wrappers below add only Study Setup projection and reservation guards.
alter function public.apply_intake_v1_setup_revision(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) rename to apply_intake_v1_setup_revision_without_study_setup;
revoke all on function public.apply_intake_v1_setup_revision_without_study_setup(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.apply_intake_v1_setup_revision(
  p_user_id uuid,
  p_intake_response_id uuid,
  p_request_id uuid,
  p_base_revision int,
  p_revision int,
  p_completed_at timestamptz,
  p_notification_preferences jsonb,
  p_goals jsonb,
  p_habits jsonb,
  p_schedule_items jsonb,
  p_memory_entries jsonb,
  p_snapshot jsonb,
  p_intake_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  canonical_row public.intake_responses%rowtype;
  study jsonb;
  focus jsonb;
  semesters jsonb;
  current_study_revision int;
begin
  result := public.apply_intake_v1_setup_revision_without_study_setup(
    p_user_id,
    p_intake_response_id,
    p_request_id,
    p_base_revision,
    p_revision,
    p_completed_at,
    p_notification_preferences,
    p_goals,
    p_habits,
    p_schedule_items,
    p_memory_entries,
    p_snapshot,
    p_intake_metadata
  );

  select value.*
  into canonical_row
  from public.intake_responses as value
  where value.id = p_intake_response_id
    and value.user_id = p_user_id
    and value.request_id = p_request_id
    and value.revision = p_revision
    and value.state = 'applied'
    and not exists (
      select 1
      from public.intake_responses as newer
      where newer.user_id = value.user_id
        and newer.version = 'intake-v1'
        and newer.state = 'applied'
        and newer.revision > value.revision
    );
  if not found then
    return result;
  end if;

  study := canonical_row.responses -> 'study_setup';
  if study is null then
    delete from public.study_setup_profiles
    where user_id = p_user_id and setup_revision <= p_revision;
  else
    if jsonb_typeof(study) <> 'object'
       or study - array['focus_rhythm', 'semester_planning'] <> '{}'::jsonb
       or not (study ? 'focus_rhythm' or study ? 'semester_planning') then
      raise exception 'Canonical Study Setup shape is invalid.'
        using errcode = '22023';
    end if;
    focus := study -> 'focus_rhythm';
    semesters := study -> 'semester_planning';
    if focus is not null and (
      jsonb_typeof(focus) <> 'object'
      or not (
        focus ?& array[
          'focus_minutes', 'recovery_minutes', 'preparation_items'
        ]
      )
      or focus - array[
        'focus_minutes', 'recovery_minutes', 'preparation_items'
      ] <> '{}'::jsonb
    ) then
      raise exception 'Canonical Study Focus shape is invalid.'
        using errcode = '22023';
    end if;
    if semesters is not null and (
      jsonb_typeof(semesters) <> 'object'
      or not (
        semesters ?& array['current_semester', 'next_semester']
      )
      or semesters - array['current_semester', 'next_semester'] <> '{}'::jsonb
    ) then
      raise exception 'Canonical Study Semester shape is invalid.'
        using errcode = '22023';
    end if;

    insert into public.study_setup_profiles (
      user_id,
      focus_minutes,
      recovery_minutes,
      preparation_items,
      current_semester,
      next_semester,
      setup_revision,
      created_at,
      updated_at
    ) values (
      p_user_id,
      nullif(focus ->> 'focus_minutes', '')::int,
      nullif(focus ->> 'recovery_minutes', '')::int,
      coalesce(focus -> 'preparation_items', '[]'::jsonb),
      semesters -> 'current_semester',
      semesters -> 'next_semester',
      p_revision,
      canonical_row.completed_at,
      canonical_row.completed_at
    )
    on conflict (user_id) do update
    set focus_minutes = excluded.focus_minutes,
        recovery_minutes = excluded.recovery_minutes,
        preparation_items = excluded.preparation_items,
        current_semester = excluded.current_semester,
        next_semester = excluded.next_semester,
        setup_revision = excluded.setup_revision,
        updated_at = greatest(
          public.study_setup_profiles.updated_at,
          excluded.updated_at
        )
    where public.study_setup_profiles.setup_revision <= excluded.setup_revision;
  end if;

  select setup_revision into current_study_revision
  from public.study_setup_profiles
  where user_id = p_user_id;

  update public.planner_action_plans as plan
  set attention_reasons = (
        select array_agg(distinct reason order by reason)
        from unnest(
          plan.attention_reasons || array['study_rhythm_changed']::text[]
        ) as reasons(reason)
      ),
      updated_at = greatest(plan.updated_at, canonical_row.completed_at)
  from public.planner_action_plan_revisions as revision
  where plan.user_id = p_user_id
    and plan.id = revision.plan_id
    and revision.revision = plan.current_revision
    and revision.state = 'active'
    and revision.target_payload ->> 'kind' = 'task'
    and revision.target_payload ->> 'use_study_rhythm' = 'true'
    and revision.study_setup_revision
        is distinct from current_study_revision;
  return result;
end;
$$;

revoke all on function public.apply_intake_v1_setup_revision(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_intake_v1_setup_revision(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) to service_role;

create or replace function private.deadline_study_reservations_conflict(
  p_user_id uuid,
  p_plan_id uuid,
  p_revision int
)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  revision_row public.deadline_plan_revisions%rowtype;
begin
  select * into revision_row
  from public.deadline_plan_revisions
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = p_revision;
  if not found then
    return true;
  end if;
  return exists (
    select 1
    from public.deadline_plan_blocks as left_block
    join public.deadline_plan_blocks as right_block
      on left_block.sequence < right_block.sequence
     and tstzrange(
       left_block.starts_at, left_block.reserved_ends_at, '[)'
     ) && tstzrange(
       right_block.starts_at, right_block.reserved_ends_at, '[)'
     )
    where left_block.plan_id = p_plan_id
      and left_block.revision = p_revision
      and right_block.plan_id = p_plan_id
      and right_block.revision = p_revision
  ) or exists (
    select 1
    from public.deadline_plan_blocks as proposed
    join public.deadline_plan_blocks as active
      on active.user_id = p_user_id
     and active.plan_id <> p_plan_id
     and active.reservation_state = 'active'
     and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
         tstzrange(active.starts_at, active.reserved_ends_at, '[)')
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.deadline_plan_blocks as proposed
    join public.planner_task_blocks as active
      on active.user_id = p_user_id
     and active.state = 'active'
     and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
         tstzrange(active.starts_at, active.reserved_ends_at, '[)')
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.deadline_plan_blocks as proposed
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and private.setup_schedule_applies_on(fixed.metadata, proposed.local_date)
     and proposed.local_start_time < fixed.ends_at
     and (proposed.reserved_ends_at at time zone revision_row.timezone)::time
         > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.deadline_plan_blocks as proposed
    join public.planner_habit_slots as fixed
      on fixed.user_id = p_user_id
     and fixed.state = 'active'
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and proposed.local_start_time < fixed.ends_at
     and (proposed.reserved_ends_at at time zone revision_row.timezone)::time
         > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.deadline_plan_blocks as proposed
    join public.planner_commitments as fixed
      on fixed.user_id = p_user_id
     and fixed.status = 'active'
     and (
       (
         fixed.recurrence = 'one_off'
         and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
             tstzrange(fixed.starts_at, fixed.ends_at, '[)')
       )
       or (
         fixed.recurrence = 'weekly'
         and fixed.weekday = extract(isodow from proposed.local_date)::int
         and proposed.local_start_time < fixed.local_ends_at
         and (proposed.reserved_ends_at at time zone revision_row.timezone)::time
             > fixed.local_starts_at
       )
     )
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or (
    revision_row.use_calendar_availability and (
      exists (
        select 1
        from public.deadline_plan_blocks as proposed
        join public.calendar_events as event
          on event.user_id = p_user_id
         and event.connection_id = revision_row.availability_connection_id
         and event.import_id = revision_row.availability_import_id
         and event.event_kind = 'timed'
         and event.busy_status = 'busy'
         and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
             tstzrange(event.starts_at, event.ends_at, '[)')
        where proposed.plan_id = p_plan_id
          and proposed.revision = p_revision
      ) or exists (
        select 1
        from public.deadline_plan_blocks as proposed
        join public.calendar_events as event
          on event.user_id = p_user_id
         and event.connection_id = revision_row.availability_connection_id
         and event.import_id = revision_row.availability_import_id
         and event.event_kind = 'all_day'
         and event.busy_status = 'busy'
         and proposed.local_date >= event.starts_on
         and proposed.local_date < event.ends_on
        where proposed.plan_id = p_plan_id
          and proposed.revision = p_revision
      )
    )
  );
end;
$$;

revoke all on function private.deadline_study_reservations_conflict(
  uuid, uuid, int
) from public, anon, authenticated, service_role;

create or replace function private.planner_study_reservations_conflict(
  p_user_id uuid,
  p_plan_id uuid,
  p_revision int
)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  revision_row public.planner_action_plan_revisions%rowtype;
begin
  select * into revision_row
  from public.planner_action_plan_revisions
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = p_revision;
  if not found then
    return true;
  end if;
  if revision_row.target_payload ->> 'kind' <> 'task' then
    return false;
  end if;
  return exists (
    select 1
    from public.planner_task_blocks as left_block
    join public.planner_task_blocks as right_block
      on left_block.sequence < right_block.sequence
     and tstzrange(
       left_block.starts_at, left_block.reserved_ends_at, '[)'
     ) && tstzrange(
       right_block.starts_at, right_block.reserved_ends_at, '[)'
     )
    where left_block.plan_id = p_plan_id
      and left_block.revision = p_revision
      and right_block.plan_id = p_plan_id
      and right_block.revision = p_revision
  ) or exists (
    select 1
    from public.planner_task_blocks as proposed
    join public.planner_task_blocks as active
      on active.user_id = p_user_id
     and active.plan_id <> p_plan_id
     and active.state = 'active'
     and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
         tstzrange(active.starts_at, active.reserved_ends_at, '[)')
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.planner_task_blocks as proposed
    join public.deadline_plan_blocks as active
      on active.user_id = p_user_id
     and active.reservation_state = 'active'
     and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
         tstzrange(active.starts_at, active.reserved_ends_at, '[)')
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.planner_task_blocks as proposed
    join public.planner_habit_slots as fixed
      on fixed.user_id = p_user_id
     and fixed.plan_id <> p_plan_id
     and fixed.state = 'active'
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and (proposed.starts_at at time zone revision_row.timezone)::time
         < fixed.ends_at
     and (proposed.reserved_ends_at at time zone revision_row.timezone)::time
         > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.planner_task_blocks as proposed
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and private.setup_schedule_applies_on(fixed.metadata, proposed.local_date)
     and (proposed.starts_at at time zone revision_row.timezone)::time
         < fixed.ends_at
     and (proposed.reserved_ends_at at time zone revision_row.timezone)::time
         > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or exists (
    select 1
    from public.planner_task_blocks as proposed
    join public.planner_commitments as fixed
      on fixed.user_id = p_user_id
     and fixed.status = 'active'
     and (
       (
         fixed.recurrence = 'one_off'
         and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
             tstzrange(fixed.starts_at, fixed.ends_at, '[)')
       )
       or (
         fixed.recurrence = 'weekly'
         and fixed.weekday = extract(isodow from proposed.local_date)::int
         and (proposed.starts_at at time zone revision_row.timezone)::time
             < fixed.local_ends_at
         and (proposed.reserved_ends_at at time zone revision_row.timezone)::time
             > fixed.local_starts_at
       )
     )
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
  ) or (
    revision_row.calendar_import_id is not null and (
      exists (
        select 1
        from public.planner_task_blocks as proposed
        join public.calendar_events as event
          on event.user_id = p_user_id
         and event.import_id = revision_row.calendar_import_id
         and event.event_kind = 'timed'
         and event.event_status = 'confirmed'
         and event.busy_status = 'busy'
         and tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)') &&
             tstzrange(event.starts_at, event.ends_at, '[)')
        where proposed.plan_id = p_plan_id
          and proposed.revision = p_revision
      ) or exists (
        select 1
        from public.planner_task_blocks as proposed
        join public.calendar_events as event
          on event.user_id = p_user_id
         and event.import_id = revision_row.calendar_import_id
         and event.event_kind = 'all_day'
         and event.event_status = 'confirmed'
         and event.busy_status = 'busy'
         and proposed.local_date >= event.starts_on
         and proposed.local_date < event.ends_on
        where proposed.plan_id = p_plan_id
          and proposed.revision = p_revision
      )
    )
  );
end;
$$;

revoke all on function private.planner_study_reservations_conflict(
  uuid, uuid, int
) from public, anon, authenticated, service_role;

alter function public.propose_deadline_plan_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) rename to propose_deadline_plan_v1_without_study_setup;
revoke all on function public.propose_deadline_plan_v1_without_study_setup(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.propose_deadline_plan_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_plan_id uuid,
  p_base_revision int,
  p_proposal jsonb,
  p_blocks jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  result_revision int;
  replay boolean;
  current_study public.study_setup_profiles%rowtype;
  proposal_study_revision int;
  proposal_recovery int;
  block_count int;
begin
  replay := exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  );
  result := public.propose_deadline_plan_v1_without_study_setup(
    p_user_id,
    p_request_id,
    p_request_fingerprint,
    p_plan_id,
    p_base_revision,
    p_proposal - array['study_setup_revision', 'recovery_minutes'],
    coalesce(
      (
        select jsonb_agg(
          value - array['recovery_minutes', 'reserved_ends_at']
          order by (value ->> 'sequence')::int
        )
        from jsonb_array_elements(p_blocks) as blocks(value)
      ),
      '[]'::jsonb
    ),
    p_now
  );
  if replay then
    return result;
  end if;

  if jsonb_typeof(p_proposal) <> 'object'
     or not (
       p_proposal ?& array['study_setup_revision', 'recovery_minutes']
     )
     or (
       p_proposal -> 'study_setup_revision' <> 'null'::jsonb
       and jsonb_typeof(p_proposal -> 'study_setup_revision') <> 'number'
     )
     or jsonb_typeof(p_proposal -> 'recovery_minutes') <> 'number'
     or jsonb_typeof(p_blocks) <> 'array' then
    raise exception 'Deadline Study Setup proposal shape is invalid.'
      using errcode = '22023';
  end if;
  proposal_study_revision :=
    nullif(p_proposal ->> 'study_setup_revision', '')::int;
  proposal_recovery := (p_proposal ->> 'recovery_minutes')::int;
  select * into current_study
  from public.study_setup_profiles
  where user_id = p_user_id;
  if found and current_study.focus_minutes is not null then
    if proposal_study_revision is distinct from current_study.setup_revision
       or (p_proposal ->> 'preferred_session_minutes')::int
          <> current_study.focus_minutes
       or proposal_recovery <> current_study.recovery_minutes then
      raise exception 'Study rhythm changed. Create a new deadline preview.'
        using errcode = 'PT409';
    end if;
  elsif proposal_study_revision is not null or proposal_recovery <> 0 then
    raise exception 'Deadline proposal cannot invent a Study rhythm.'
      using errcode = 'PT409';
  end if;

  block_count := jsonb_array_length(p_blocks);
  if exists (
    select 1
    from jsonb_to_recordset(p_blocks) as block(
      id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
      local_date date, local_start_time time, local_end_time time,
      planned_minutes int, recovery_minutes int, reserved_ends_at timestamptz
    )
    where block.recovery_minutes <> proposal_recovery
       or block.reserved_ends_at <>
          block.ends_at + proposal_recovery * interval '1 minute'
       or (
         proposal_study_revision is not null
         and block.planned_minutes >
             (p_proposal ->> 'preferred_session_minutes')::int
       )
       or (
         proposal_study_revision is not null
         and block.planned_minutes <
             (p_proposal ->> 'preferred_session_minutes')::int
         and block.sequence <> block_count
       )
       or (
         block.reserved_ends_at at time zone (p_proposal ->> 'timezone')
       )::date
          <> block.local_date
  ) then
    raise exception 'Deadline recovery reservation shape is invalid.'
      using errcode = '22023';
  end if;

  result_revision := (result ->> 'revision')::int;
  update public.deadline_plan_revisions
  set study_setup_revision = proposal_study_revision,
      recovery_minutes = proposal_recovery
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = result_revision;
  update public.deadline_plan_blocks as persisted
  set recovery_minutes = proposed.recovery_minutes,
      reserved_ends_at = proposed.reserved_ends_at
  from jsonb_to_recordset(p_blocks) as proposed(
    id uuid, recovery_minutes int, reserved_ends_at timestamptz
  )
  where persisted.id = proposed.id
    and persisted.user_id = p_user_id
    and persisted.plan_id = p_plan_id
    and persisted.revision = result_revision;
  if private.deadline_study_reservations_conflict(
    p_user_id, p_plan_id, result_revision
  ) then
    raise exception 'Deadline recovery conflicts with current availability.'
      using errcode = 'PT409';
  end if;
  return result;
end;
$$;

revoke all on function public.propose_deadline_plan_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.propose_deadline_plan_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) to service_role;

alter function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) rename to confirm_deadline_plan_v1_without_study_setup;
revoke all on function public.confirm_deadline_plan_v1_without_study_setup(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.confirm_deadline_plan_v1(
  p_user_id uuid,
  p_plan_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_revision int,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  revision_row public.deadline_plan_revisions%rowtype;
  current_study public.study_setup_profiles%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    return public.confirm_deadline_plan_v1_without_study_setup(
      p_user_id, p_plan_id, p_request_id, p_request_fingerprint,
      p_expected_revision, p_now
    );
  end if;
  select * into revision_row
  from public.deadline_plan_revisions
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = p_expected_revision
    and state = 'proposed';
  if not found then
    raise exception 'Deadline proposal changed. Reload before confirmation.'
      using errcode = 'PT409';
  end if;
  select * into current_study
  from public.study_setup_profiles where user_id = p_user_id;
  if found and current_study.focus_minutes is not null then
    if revision_row.study_setup_revision is distinct from current_study.setup_revision
       or revision_row.preferred_session_minutes <> current_study.focus_minutes
       or revision_row.recovery_minutes <> current_study.recovery_minutes then
      raise exception 'Study rhythm changed. Create a new deadline preview.'
        using errcode = 'PT409';
    end if;
  elsif revision_row.study_setup_revision is not null
     or revision_row.recovery_minutes <> 0 then
    raise exception 'Study rhythm changed. Create a new deadline preview.'
      using errcode = 'PT409';
  end if;
  if private.deadline_study_reservations_conflict(
    p_user_id, p_plan_id, p_expected_revision
  ) then
    raise exception 'Recovery availability changed. Replan before confirmation.'
      using errcode = 'PT409';
  end if;
  return public.confirm_deadline_plan_v1_without_study_setup(
    p_user_id, p_plan_id, p_request_id, p_request_fingerprint,
    p_expected_revision, p_now
  );
end;
$$;

revoke all on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated;
grant execute on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) to service_role;

alter function public.propose_planner_action_plan_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) rename to propose_planner_action_plan_v1_without_study_setup;
revoke all on function public.propose_planner_action_plan_v1_without_study_setup(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.propose_planner_action_plan_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_plan_id uuid,
  p_base_revision int,
  p_target_kind text,
  p_target_id uuid,
  p_target_payload jsonb,
  p_revision_payload jsonb,
  p_task_blocks jsonb,
  p_habit_slots jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  result_revision int;
  replay boolean;
  use_study boolean;
  current_study public.study_setup_profiles%rowtype;
  proposal_study_revision int;
  proposal_recovery int;
  block_count int;
begin
  replay := exists (
    select 1 from public.planner_request_identities
    where request_id = p_request_id
  );
  result := public.propose_planner_action_plan_v1_without_study_setup(
    p_user_id,
    p_request_id,
    p_request_fingerprint,
    p_plan_id,
    p_base_revision,
    p_target_kind,
    p_target_id,
    p_target_payload - 'use_study_rhythm',
    jsonb_set(
      p_revision_payload - array['study_setup_revision', 'recovery_minutes'],
      '{target}',
      p_target_payload - 'use_study_rhythm'
    ),
    coalesce(
      (
        select jsonb_agg(
          value - array['recovery_minutes', 'reserved_ends_at']
          order by (value ->> 'sequence')::int
        )
        from jsonb_array_elements(p_task_blocks) as blocks(value)
      ),
      '[]'::jsonb
    ),
    p_habit_slots,
    p_now
  );
  if replay then
    return result;
  end if;

  use_study := p_target_kind = 'task'
    and p_target_payload ->> 'use_study_rhythm' = 'true';
  if p_target_kind = 'task' and jsonb_typeof(
       p_target_payload -> 'use_study_rhythm'
     ) <> 'boolean' then
    raise exception 'Task use_study_rhythm must be explicit.'
      using errcode = '22023';
  elsif p_target_kind = 'habit' and p_target_payload ? 'use_study_rhythm' then
    raise exception 'Habits cannot use the Study rhythm.'
      using errcode = '22023';
  end if;
  if not (
    p_revision_payload ?& array['study_setup_revision', 'recovery_minutes']
  ) or (
    p_revision_payload -> 'study_setup_revision' <> 'null'::jsonb
    and jsonb_typeof(p_revision_payload -> 'study_setup_revision') <> 'number'
  ) or jsonb_typeof(p_revision_payload -> 'recovery_minutes') <> 'number' then
    raise exception 'Planner Study Setup revision shape is invalid.'
      using errcode = '22023';
  end if;
  proposal_study_revision :=
    nullif(p_revision_payload ->> 'study_setup_revision', '')::int;
  proposal_recovery := (p_revision_payload ->> 'recovery_minutes')::int;
  select * into current_study
  from public.study_setup_profiles where user_id = p_user_id;
  if use_study then
    if not found or current_study.focus_minutes is null
       or proposal_study_revision is distinct from current_study.setup_revision
       or nullif(p_target_payload ->> 'preferred_session_minutes', '')::int
          is distinct from current_study.focus_minutes
       or proposal_recovery <> current_study.recovery_minutes then
      raise exception 'Current Study rhythm is required for this Task.'
        using errcode = 'PT409';
    end if;
  elsif proposal_study_revision is not null or proposal_recovery <> 0 then
    raise exception 'An ordinary Task cannot reserve Study recovery.'
      using errcode = '22023';
  end if;

  block_count := jsonb_array_length(p_task_blocks);
  if exists (
    select 1
    from jsonb_to_recordset(p_task_blocks) as block(
      id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
      local_date date, planned_minutes int, recovery_minutes int,
      reserved_ends_at timestamptz
    )
    where block.recovery_minutes <> proposal_recovery
       or block.reserved_ends_at <>
          block.ends_at + proposal_recovery * interval '1 minute'
       or (
         use_study
         and block.planned_minutes >
             (p_target_payload ->> 'preferred_session_minutes')::int
       )
       or (
         use_study
         and block.planned_minutes <
             (p_target_payload ->> 'preferred_session_minutes')::int
         and block.sequence <> block_count
       )
       or (
         block.reserved_ends_at
           at time zone (p_revision_payload ->> 'timezone')
       )::date
          <> block.local_date
  ) then
    raise exception 'Planner recovery reservation shape is invalid.'
      using errcode = '22023';
  end if;

  result_revision := (result ->> 'revision')::int;
  update public.planner_action_plan_revisions
  set target_payload = p_target_payload,
      study_setup_revision = proposal_study_revision,
      recovery_minutes = proposal_recovery
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = result_revision;
  update public.planner_task_blocks as persisted
  set recovery_minutes = proposed.recovery_minutes,
      reserved_ends_at = proposed.reserved_ends_at
  from jsonb_to_recordset(p_task_blocks) as proposed(
    id uuid, recovery_minutes int, reserved_ends_at timestamptz
  )
  where persisted.id = proposed.id
    and persisted.user_id = p_user_id
    and persisted.plan_id = p_plan_id
    and persisted.revision = result_revision;
  if private.planner_study_reservations_conflict(
    p_user_id, p_plan_id, result_revision
  ) then
    raise exception 'Planner recovery conflicts with current availability.'
      using errcode = 'PT409';
  end if;
  return result;
end;
$$;

revoke all on function public.propose_planner_action_plan_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) from public, anon, authenticated;
grant execute on function public.propose_planner_action_plan_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) to service_role;

alter function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) rename to confirm_planner_action_plan_v1_without_study_setup;
revoke all on function public.confirm_planner_action_plan_v1_without_study_setup(
  uuid, uuid, uuid, int, text, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.confirm_planner_action_plan_v1(
  p_user_id uuid,
  p_plan_id uuid,
  p_request_id uuid,
  p_expected_revision int,
  p_request_fingerprint text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  revision_row public.planner_action_plan_revisions%rowtype;
  current_study public.study_setup_profiles%rowtype;
  use_study boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  if exists (
    select 1 from public.planner_request_identities
    where request_id = p_request_id
  ) then
    return public.confirm_planner_action_plan_v1_without_study_setup(
      p_user_id, p_plan_id, p_request_id, p_expected_revision,
      p_request_fingerprint, p_now
    );
  end if;
  select * into revision_row
  from public.planner_action_plan_revisions
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = p_expected_revision
    and state = 'proposed';
  if not found then
    raise exception 'Planner preview changed. Reload before confirmation.'
      using errcode = 'PT409';
  end if;
  use_study := revision_row.target_payload ->> 'kind' = 'task'
    and revision_row.target_payload ->> 'use_study_rhythm' = 'true';
  select * into current_study
  from public.study_setup_profiles where user_id = p_user_id;
  if use_study and (
    not found
    or current_study.focus_minutes is null
    or revision_row.study_setup_revision
       is distinct from current_study.setup_revision
    or nullif(
      revision_row.target_payload ->> 'preferred_session_minutes', ''
    )::int is distinct from current_study.focus_minutes
    or revision_row.recovery_minutes <> current_study.recovery_minutes
  ) then
    raise exception 'Study rhythm changed. Create a new Planner preview.'
      using errcode = 'PT409';
  end if;
  if private.planner_study_reservations_conflict(
    p_user_id, p_plan_id, p_expected_revision
  ) then
    raise exception 'Recovery availability changed. Replan before confirmation.'
      using errcode = 'PT409';
  end if;

  result := public.confirm_planner_action_plan_v1_without_study_setup(
    p_user_id, p_plan_id, p_request_id, p_expected_revision,
    p_request_fingerprint, p_now
  );
  if revision_row.target_payload ->> 'kind' = 'task' then
    update public.tasks
    set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'use_study_rhythm', use_study,
          'study_setup_revision', revision_row.study_setup_revision,
          'recovery_minutes', revision_row.recovery_minutes
        )
    where id = (revision_row.target_payload ->> 'target_id')::uuid
      and user_id = p_user_id;
  end if;
  return result;
end;
$$;

revoke all on function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) to service_role;

comment on table public.study_setup_profiles is
  'Backend-owned projection of optional revisioned Study Setup.';
comment on column public.deadline_plan_blocks.reserved_ends_at is
  'End of the non-bookable focus plus recovery reservation.';
comment on column public.planner_task_blocks.reserved_ends_at is
  'End of the non-bookable Task focus plus recovery reservation.';
