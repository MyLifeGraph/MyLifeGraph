-- Exam Plan Health V1 is a read-only, point-in-time feasibility snapshot.
-- It deliberately stores no health state. One stable statement gathers every
-- owner-filtered source so the backend never combines torn or truncated reads.

create or replace function public.get_exam_plan_health_snapshot_v1(
  p_user_id uuid,
  p_generated_at timestamptz
)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  local_today date;
  horizon_ends_before date;
  range_starts_at timestamptz;
  range_ends_at timestamptz;
  result jsonb;
begin
  if p_user_id is null or p_generated_at is null then
    raise exception 'Exam health snapshot arguments are required.'
      using errcode = '22023';
  end if;

  select profile.*
  into profile_row
  from public.profiles as profile
  where profile.id = p_user_id;

  if not found then
    raise exception 'Account profile is unavailable.' using errcode = 'PT404';
  end if;

  local_today := (p_generated_at at time zone profile_row.timezone)::date;
  horizon_ends_before := local_today + 367;
  -- One adjacent local-day anchor on each side makes recurring/DST overlap
  -- checks complete without turning this bounded read into an unbounded scan.
  range_starts_at := ((local_today - 1)::timestamp at time zone profile_row.timezone);
  range_ends_at := ((horizon_ends_before + 1)::timestamp at time zone profile_row.timezone);

  with active_exams as (
    select
      plan.id,
      plan.title,
      plan.first_activated_at,
      plan.current_revision,
      plan.latest_revision,
      revision.revision,
      revision.deadline_at,
      revision.estimated_total_minutes,
      revision.credited_prior_minutes,
      revision.preferred_session_minutes,
      revision.max_daily_minutes,
      revision.planning_start_on,
      revision.buffer_days,
      revision.use_calendar_availability,
      revision.recovery_minutes,
      revision.study_setup_revision,
      revision.timezone,
      revision.best_energy_window,
      revision.tracked_focus_minutes_at_proposal,
      (
        select count(*)::int
        from public.deadline_plan_blocks as counted_block
        where counted_block.user_id = plan.user_id
          and counted_block.plan_id = plan.id
          and counted_block.revision = revision.revision
      ) as active_block_count
    from public.deadline_plans as plan
    join public.deadline_plan_revisions as revision
      on revision.plan_id = plan.id
     and revision.user_id = plan.user_id
     and revision.revision = plan.current_revision
     and revision.state = 'active'
    where plan.user_id = p_user_id
      and plan.status = 'active'
      and plan.kind = 'exam'
      and revision.deadline_at <
        (horizon_ends_before::timestamp at time zone profile_row.timezone)
  ), focus_facts as (
    select
      focus.id,
      exam.id as plan_id,
      focus.started_at,
      focus.actual_minutes,
      source.deadline_plan_block_id
    from active_exams as exam
    join public.focus_sessions as focus
      on focus.user_id = p_user_id
     and focus.task_id = exam.id
     and focus.status = 'completed'
     and focus.started_at >= exam.first_activated_at
    left join public.focus_session_schedule_sources as source
      on source.focus_session_id = focus.id
     and source.user_id = focus.user_id
  ), focus_totals as (
    select
      exam.id as plan_id,
      coalesce(sum(focus.actual_minutes), 0)::int as actual_minutes,
      count(focus.id)::int as focus_count
    from active_exams as exam
    left join public.focus_sessions as focus
      on focus.user_id = p_user_id
     and focus.task_id = exam.id
     and focus.status = 'completed'
     and focus.started_at >= exam.first_activated_at
    group by exam.id
  ), current_connection as (
    select connection.*
    from public.calendar_connections as connection
    where connection.user_id = p_user_id
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
    order by connection.updated_at desc, connection.id desc
    limit 1
  ), current_import as (
    select import.*
    from current_connection as connection
    join public.calendar_imports as import
      on import.id = connection.last_import_id
     and import.user_id = connection.user_id
     and import.connection_id = connection.id
    limit 1
  )
  select jsonb_build_object(
    'contract_version', 'exam-plan-health-snapshot-v1',
    'generated_at', p_generated_at,
    'local_today', local_today,
    'horizon_ends_before', horizon_ends_before,
    'profile', jsonb_build_object(
      'timezone', profile_row.timezone,
      'timezone_revision', profile_row.timezone_revision,
      'daily_preparation_budget_minutes',
        profile_row.daily_preparation_budget_minutes
    ),
    'best_energy_window', coalesce((
      select response.responses ->> 'best_energy_window'
      from public.intake_responses as response
      where response.user_id = p_user_id
        and response.version = 'intake-v1'
        and response.state = 'applied'
      order by response.revision desc, response.updated_at desc, response.id desc
      limit 1
    ), 'variable'),
    'study_setup', (
      select to_jsonb(setup)
        - 'user_id' - 'created_at' - 'updated_at'
      from public.study_setup_profiles as setup
      where setup.user_id = p_user_id
    ),
    'planner_preference', coalesce((
      select jsonb_build_object(
        'use_calendar_busy_time', preference.use_calendar_busy_time
      )
      from public.planner_preferences as preference
      where preference.user_id = p_user_id
    ), jsonb_build_object('use_calendar_busy_time', false)),
    'exams', coalesce((
      select jsonb_agg(to_jsonb(exam) order by
        exam.deadline_at, exam.estimated_total_minutes desc, exam.id)
      from active_exams as exam
    ), '[]'::jsonb),
    'focus_totals', coalesce((
      select jsonb_agg(to_jsonb(total) order by total.plan_id)
      from focus_totals as total
    ), '[]'::jsonb),
    'focus_facts', coalesce((
      select jsonb_agg(to_jsonb(fact) order by fact.started_at, fact.id)
      from focus_facts as fact
    ), '[]'::jsonb),
    'deadline_blocks', coalesce((
      select jsonb_agg(to_jsonb(block) order by block.starts_at, block.id)
      from (
        select
          source.id,
          source.plan_id,
          source.revision,
          source.sequence,
          source.starts_at,
          source.ends_at,
          source.reserved_ends_at,
          source.local_date,
          source.planned_minutes,
          source.recovery_minutes
        from public.deadline_plan_blocks as source
        where source.user_id = p_user_id
          and source.reservation_state = 'active'
          and (
            (
              source.reserved_ends_at > range_starts_at
              and source.starts_at < range_ends_at
            )
            or exists (
              select 1
              from active_exams as exam
              where exam.id = source.plan_id
                and exam.revision = source.revision
            )
          )
      ) as block
    ), '[]'::jsonb),
    'schedule_items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.weekday, item.starts_at, item.id)
      from (
        select schedule.id, schedule.weekday, schedule.starts_at,
               schedule.ends_at, schedule.metadata
        from public.schedule_items as schedule
        where schedule.user_id = p_user_id
      ) as item
    ), '[]'::jsonb),
    'planner_task_blocks', coalesce((
      select jsonb_agg(to_jsonb(block) order by block.starts_at, block.id)
      from (
        select task.id, task.plan_id, task.starts_at, task.ends_at,
               task.reserved_ends_at, task.local_date, task.planned_minutes,
               task.recovery_minutes
        from public.planner_task_blocks as task
        where task.user_id = p_user_id
          and task.state = 'active'
          and task.reserved_ends_at > range_starts_at
          and task.starts_at < range_ends_at
      ) as block
    ), '[]'::jsonb),
    'planner_habit_slots', coalesce((
      select jsonb_agg(to_jsonb(slot) order by slot.weekday, slot.starts_at, slot.id)
      from (
        select habit.id, habit.plan_id, habit.weekday, habit.starts_at,
               habit.ends_at, habit.duration_minutes
        from public.planner_habit_slots as habit
        where habit.user_id = p_user_id and habit.state = 'active'
      ) as slot
    ), '[]'::jsonb),
    'planner_commitments', coalesce((
      select jsonb_agg(to_jsonb(commitment) order by commitment.created_at,
                       commitment.id)
      from (
        select fixed.id, fixed.recurrence, fixed.starts_at, fixed.ends_at,
               fixed.weekday, fixed.local_starts_at, fixed.local_ends_at,
               fixed.created_at
        from public.planner_commitments as fixed
        where fixed.user_id = p_user_id and fixed.status = 'active'
      ) as commitment
    ), '[]'::jsonb),
    'calendar_import', (
      select jsonb_build_object(
        'connection_id', connection.id,
        'import_id', import.id,
        'planning_status', import.planning_status,
        'timezone', import.timezone,
        'profile_timezone_revision', import.profile_timezone_revision,
        'window_starts_on', import.window_starts_on,
        'window_ends_before', import.window_ends_before
      )
      from current_connection as connection
      join current_import as import on true
    ),
    'calendar_timed_events', coalesce((
      select jsonb_agg(to_jsonb(event) order by event.starts_at, event.id)
      from (
        select item.id, item.starts_at, item.ends_at
        from public.calendar_events as item
        join current_import as import
          on import.id = item.import_id
         and import.user_id = item.user_id
         and import.connection_id = item.connection_id
        where item.user_id = p_user_id
          and import.planning_status = 'current'
          and item.event_kind = 'timed'
          and item.busy_status = 'busy'
          and item.ends_at > range_starts_at
          and item.starts_at < range_ends_at
      ) as event
    ), '[]'::jsonb),
    'calendar_all_day_events', coalesce((
      select jsonb_agg(to_jsonb(event) order by event.starts_on, event.id)
      from (
        select item.id, item.starts_on, item.ends_on
        from public.calendar_events as item
        join current_import as import
          on import.id = item.import_id
         and import.user_id = item.user_id
         and import.connection_id = item.connection_id
        where item.user_id = p_user_id
          and import.planning_status = 'current'
          and item.event_kind = 'all_day'
          and item.busy_status = 'busy'
          and item.ends_on > local_today - 1
          and item.starts_on < horizon_ends_before + 1
      ) as event
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke all on function public.get_exam_plan_health_snapshot_v1(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.get_exam_plan_health_snapshot_v1(uuid, timestamptz)
  to service_role;
