-- Keep the database confirmation boundary aligned with the additive Setup
-- semester bounds stored in schedule_items.metadata. The existing RPC bodies
-- are intentionally retained byte-for-byte except for their three recurring
-- schedule predicates. Each guarded replacement fails closed if the expected
-- installed definition has drifted.

create or replace function private.setup_schedule_applies_on(
  p_metadata jsonb,
  p_local_date date
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  valid_from_text text;
  valid_until_text text;
  valid_from_date date;
  valid_until_date date;
begin
  if p_local_date is null then
    return false;
  end if;

  if (p_metadata ->> 'managed_by') is distinct from 'setup' then
    return true;
  end if;

  valid_from_text := p_metadata ->> 'valid_from';
  valid_until_text := p_metadata ->> 'valid_until';

  if valid_from_text is not null then
    if valid_from_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'Setup schedule valid_from is invalid.'
        using errcode = '22007';
    end if;
    valid_from_date := valid_from_text::date;
  end if;

  if valid_until_text is not null then
    if valid_until_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'Setup schedule valid_until is invalid.'
        using errcode = '22007';
    end if;
    valid_until_date := valid_until_text::date;
  end if;

  if valid_from_date is not null
     and valid_until_date is not null
     and valid_until_date < valid_from_date then
    raise exception 'Setup schedule validity range is invalid.'
      using errcode = '23514';
  end if;

  return (valid_from_date is null or p_local_date >= valid_from_date)
    and (valid_until_date is null or p_local_date <= valid_until_date);
end;
$$;

revoke all on function private.setup_schedule_applies_on(jsonb, date)
from public, anon, authenticated, service_role;

do $migration$
declare
  function_definition text;
  updated_definition text;
  old_task_schedule constant text := $old_task$
      join public.schedule_items as fixed
        on fixed.user_id = p_user_id
       and fixed.weekday = extract(isodow from proposed.local_date)::int
       and (proposed.starts_at at time zone revision_row.timezone)::time
           < fixed.ends_at
       and (proposed.ends_at at time zone revision_row.timezone)::time
           > fixed.starts_at
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
$old_task$;
  new_task_schedule constant text := $new_task$
      join public.schedule_items as fixed
        on fixed.user_id = p_user_id
       and fixed.weekday = extract(isodow from proposed.local_date)::int
       and private.setup_schedule_applies_on(
             fixed.metadata,
             proposed.local_date
           )
       and (proposed.starts_at at time zone revision_row.timezone)::time
           < fixed.ends_at
       and (proposed.ends_at at time zone revision_row.timezone)::time
           > fixed.starts_at
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
$new_task$;
  old_habit_schedule constant text := $old_habit$
    select 1
    from public.planner_habit_slots as proposed
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = proposed.weekday
     and proposed.starts_at < fixed.ends_at
     and proposed.ends_at > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
      and proposed.state = 'proposed'
$old_habit$;
  new_habit_schedule constant text := $new_habit$
    select 1
    from public.planner_habit_slots as proposed
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = proposed.weekday
     and proposed.starts_at < fixed.ends_at
     and proposed.ends_at > fixed.starts_at
     and exists (
       select 1
       from generate_series(0, 27) as occurrence(day_offset)
       where extract(
               isodow from revision_row.planning_start_on
                 + occurrence.day_offset
             )::int = proposed.weekday
         and private.setup_schedule_applies_on(
               fixed.metadata,
               revision_row.planning_start_on + occurrence.day_offset
             )
     )
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
      and proposed.state = 'proposed'
$new_habit$;
  old_deadline_schedule constant text := $old_deadline$
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and fixed.ends_at > fixed.starts_at
     and proposed.local_start_time < fixed.ends_at
     and proposed.local_end_time > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_expected_revision
      and proposed.reservation_state = 'proposed'
$old_deadline$;
  new_deadline_schedule constant text := $new_deadline$
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and private.setup_schedule_applies_on(
           fixed.metadata,
           proposed.local_date
         )
     and fixed.ends_at > fixed.starts_at
     and proposed.local_start_time < fixed.ends_at
     and proposed.local_end_time > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_expected_revision
      and proposed.reservation_state = 'proposed'
$new_deadline$;
begin
  select pg_get_functiondef(
    'private.planner_revision_conflicts(uuid,uuid,integer)'::regprocedure
  ) into function_definition;

  updated_definition := replace(
    function_definition,
    old_task_schedule,
    new_task_schedule
  );
  if updated_definition = function_definition then
    raise exception 'Planner Task schedule guard definition drifted.';
  end if;
  function_definition := updated_definition;

  updated_definition := replace(
    function_definition,
    old_habit_schedule,
    new_habit_schedule
  );
  if updated_definition = function_definition then
    raise exception 'Planner Habit schedule guard definition drifted.';
  end if;
  execute updated_definition;

  select pg_get_functiondef(
    'public.confirm_deadline_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'
      ::regprocedure
  ) into function_definition;
  updated_definition := replace(
    function_definition,
    old_deadline_schedule,
    new_deadline_schedule
  );
  if updated_definition = function_definition then
    raise exception 'Deadline schedule guard definition drifted.';
  end if;
  execute updated_definition;
end;
$migration$;
