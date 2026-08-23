-- Keep confirmation timestamps monotone when the API host and database clock
-- differ slightly. The existing confirmation functions retain all authority,
-- availability, revision, and replay checks behind these owner-locked wrappers.

alter function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) rename to confirm_planner_action_plan_v1_without_timestamp_guard;

revoke all on function
  public.confirm_planner_action_plan_v1_without_timestamp_guard(
    uuid, uuid, uuid, int, text, timestamptz
  )
from public, anon, authenticated, service_role;

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
  effective_now timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select greatest(p_now, coalesce(max(stamp), p_now))
  into effective_now
  from (
    select plan.updated_at as stamp
    from public.planner_action_plans as plan
    where plan.user_id = p_user_id and plan.id = p_plan_id
    union all
    select revision.created_at
    from public.planner_action_plan_revisions as revision
    where revision.user_id = p_user_id
      and revision.plan_id = p_plan_id
      and revision.revision = p_expected_revision
    union all
    select block.updated_at
    from public.planner_task_blocks as block
    where block.user_id = p_user_id
      and block.plan_id = p_plan_id
      and block.revision = p_expected_revision
    union all
    select slot.updated_at
    from public.planner_habit_slots as slot
    where slot.user_id = p_user_id
      and slot.plan_id = p_plan_id
      and slot.revision = p_expected_revision
    union all
    select task.updated_at
    from public.tasks as task
    join public.planner_action_plans as plan
      on plan.target_id = task.id
     and plan.user_id = task.user_id
     and plan.target_kind = 'task'
    where plan.user_id = p_user_id and plan.id = p_plan_id
    union all
    select habit.updated_at
    from public.habits as habit
    join public.planner_action_plans as plan
      on plan.target_id = habit.id
     and plan.user_id = habit.user_id
     and plan.target_kind = 'habit'
    where plan.user_id = p_user_id and plan.id = p_plan_id
  ) as persisted_timestamps;

  return public.confirm_planner_action_plan_v1_without_timestamp_guard(
    p_user_id,
    p_plan_id,
    p_request_id,
    p_expected_revision,
    p_request_fingerprint,
    effective_now
  );
end;
$$;

alter function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) rename to confirm_deadline_plan_v1_without_timestamp_guard;

revoke all on function public.confirm_deadline_plan_v1_without_timestamp_guard(
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
  effective_now timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select greatest(p_now, coalesce(max(stamp), p_now))
  into effective_now
  from (
    select plan.updated_at as stamp
    from public.deadline_plans as plan
    where plan.user_id = p_user_id and plan.id = p_plan_id
    union all
    select revision.created_at
    from public.deadline_plan_revisions as revision
    where revision.user_id = p_user_id
      and revision.plan_id = p_plan_id
      and revision.revision = p_expected_revision
    union all
    select block.updated_at
    from public.deadline_plan_blocks as block
    where block.user_id = p_user_id
      and block.plan_id = p_plan_id
      and block.revision = p_expected_revision
  ) as persisted_timestamps;

  return public.confirm_deadline_plan_v1_without_timestamp_guard(
    p_user_id,
    p_plan_id,
    p_request_id,
    p_request_fingerprint,
    p_expected_revision,
    effective_now
  );
end;
$$;

revoke all on function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) to service_role;

revoke all on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated;
grant execute on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) to service_role;
