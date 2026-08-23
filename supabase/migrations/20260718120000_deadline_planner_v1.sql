-- Deadline Planner V1: staged deterministic preparation reservations.

create table public.deadline_plans (
  id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  contract_version text not null default 'deadline-plan-v1',
  origin text not null default 'authenticated_backend',
  status text not null default 'draft',
  kind text not null,
  title text not null,
  managed_task_id uuid,
  original_estimated_total_minutes int not null,
  original_credited_prior_minutes int not null,
  current_revision int not null default 0,
  latest_revision int not null default 1,
  first_activated_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (id, user_id),
  constraint deadline_plans_contract_check check (
    contract_version = 'deadline-plan-v1'
    and origin = 'authenticated_backend'
  ),
  constraint deadline_plans_identity_check check (
    kind in ('exam', 'assignment')
    and length(title) between 1 and 160
    and title = trim(title)
    and original_estimated_total_minutes between 30 and 30000
    and original_credited_prior_minutes >= 0
    and original_credited_prior_minutes < original_estimated_total_minutes
    and current_revision >= 0
    and latest_revision between greatest(current_revision, 1) and 200
    and updated_at >= created_at
  ),
  constraint deadline_plans_lifecycle_check check (
    (
      status = 'draft'
      and current_revision = 0
      and managed_task_id is null
      and first_activated_at is null
      and completed_at is null
      and cancelled_at is null
    )
    or (
      status = 'active'
      and current_revision > 0
      and managed_task_id = id
      and first_activated_at is not null
      and completed_at is null
      and cancelled_at is null
    )
    or (
      status = 'completed'
      and current_revision > 0
      and managed_task_id = id
      and first_activated_at is not null
      and completed_at is not null
      and cancelled_at is null
    )
    or (
      status = 'cancelled'
      and completed_at is null
      and cancelled_at is not null
      and (
        (
          current_revision = 0
          and managed_task_id is null
          and first_activated_at is null
        )
        or (
          current_revision > 0
          and managed_task_id = id
          and first_activated_at is not null
        )
      )
    )
  )
);

create table public.deadline_plan_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  plan_id uuid not null,
  revision int not null,
  base_revision int not null,
  state text not null default 'proposed',
  kind text not null,
  title text not null,
  deadline_at timestamptz not null,
  estimated_total_minutes int not null,
  credited_prior_minutes int not null,
  preferred_session_minutes int not null,
  max_daily_minutes int not null,
  planning_start_on date not null,
  buffer_days int not null,
  source_kind text not null,
  source_calendar_event_id uuid,
  source_calendar_event_fingerprint text,
  use_calendar_availability boolean not null,
  availability_connection_id uuid,
  availability_import_id uuid,
  timezone text not null,
  best_energy_window text not null,
  planning_fingerprint text not null,
  tracked_focus_minutes_at_proposal int not null,
  remaining_minutes_at_proposal int not null,
  planned_minutes int not null,
  unscheduled_minutes int not null,
  created_at timestamptz not null,
  activated_at timestamptz,
  superseded_at timestamptz,
  unique (plan_id, revision),
  unique (plan_id, user_id, revision),
  foreign key (plan_id, user_id)
    references public.deadline_plans (id, user_id) on delete cascade,
  constraint deadline_plan_revisions_sequence_check check (
    revision = base_revision + 1 and revision between 1 and 200
  ),
  constraint deadline_plan_revisions_input_check check (
    kind in ('exam', 'assignment')
    and length(title) between 1 and 160
    and title = trim(title)
    and estimated_total_minutes between 30 and 30000
    and credited_prior_minutes >= 0
    and credited_prior_minutes < estimated_total_minutes
    and preferred_session_minutes between 25 and 180
    and max_daily_minutes between 25 and 480
    and max_daily_minutes >= preferred_session_minutes
    and buffer_days between 0 and 7
    and length(timezone) between 1 and 100
    and best_energy_window in (
      'early_morning', 'morning', 'afternoon', 'evening', 'variable'
    )
    and planning_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint deadline_plan_revisions_source_check check (
    (
      source_kind = 'manual'
      and source_calendar_event_id is null
      and source_calendar_event_fingerprint is null
    )
    or (
      source_kind = 'calendar_event'
      and source_calendar_event_id is not null
      and source_calendar_event_fingerprint ~ '^[0-9a-f]{64}$'
    )
  ),
  constraint deadline_plan_revisions_availability_check check (
    (
      use_calendar_availability
      and availability_connection_id is not null
      and availability_import_id is not null
    )
    or (
      not use_calendar_availability
      and availability_connection_id is null
      and availability_import_id is null
    )
  ),
  constraint deadline_plan_revisions_summary_check check (
    tracked_focus_minutes_at_proposal >= 0
    and remaining_minutes_at_proposal = greatest(
      0,
      estimated_total_minutes
        - credited_prior_minutes
        - tracked_focus_minutes_at_proposal
    )
    and planned_minutes >= 0
    and unscheduled_minutes >= 0
    and planned_minutes + unscheduled_minutes = remaining_minutes_at_proposal
  ),
  constraint deadline_plan_revisions_lifecycle_check check (
    (
      state = 'proposed'
      and activated_at is null
      and superseded_at is null
    )
    or (
      state = 'active'
      and activated_at is not null
      and superseded_at is null
    )
    or (
      state = 'superseded'
      and superseded_at is not null
    )
  )
);

create unique index deadline_plan_revisions_one_proposed_idx
  on public.deadline_plan_revisions (plan_id)
  where state = 'proposed';

create unique index deadline_plan_revisions_one_active_idx
  on public.deadline_plan_revisions (plan_id)
  where state = 'active';

create table public.deadline_plan_blocks (
  id uuid primary key,
  user_id uuid not null,
  plan_id uuid not null,
  revision int not null,
  sequence int not null,
  reservation_state text not null default 'proposed',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  local_date date not null,
  local_start_time time not null,
  local_end_time time not null,
  planned_minutes int not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (plan_id, revision, sequence),
  foreign key (plan_id, user_id, revision)
    references public.deadline_plan_revisions (plan_id, user_id, revision)
    on delete cascade,
  constraint deadline_plan_blocks_shape_check check (
    sequence between 1 and 120
    and reservation_state in ('proposed', 'active', 'superseded')
    and ends_at > starts_at
    and planned_minutes between 5 and 240
    and ends_at - starts_at = planned_minutes * interval '1 minute'
    and updated_at >= created_at
  )
);

create index deadline_plan_blocks_user_active_time_idx
  on public.deadline_plan_blocks (user_id, starts_at, ends_at, id)
  where reservation_state = 'active';

create table public.deadline_plan_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  operation text not null,
  request_fingerprint text not null,
  plan_id uuid not null,
  result_revision int not null,
  result_status text not null,
  created_at timestamptz not null,
  constraint deadline_plan_request_contract_check check (
    operation in ('proposal', 'confirm', 'complete', 'cancel')
    and request_fingerprint ~ '^[0-9a-f]{64}$'
    and result_revision between 1 and 200
    and (
      (operation = 'proposal' and result_status in ('draft', 'active'))
      or (operation = 'confirm' and result_status = 'active')
      or (operation = 'complete' and result_status = 'completed')
      or (operation = 'cancel' and result_status = 'cancelled')
    )
  )
);

alter table public.deadline_plans enable row level security;
alter table public.deadline_plans force row level security;
alter table public.deadline_plan_revisions enable row level security;
alter table public.deadline_plan_revisions force row level security;
alter table public.deadline_plan_blocks enable row level security;
alter table public.deadline_plan_blocks force row level security;
alter table public.deadline_plan_request_identities enable row level security;
alter table public.deadline_plan_request_identities force row level security;

revoke all on table public.deadline_plans,
  public.deadline_plan_revisions,
  public.deadline_plan_blocks,
  public.deadline_plan_request_identities
from public, anon, authenticated, service_role;

grant select on table public.deadline_plans,
  public.deadline_plan_revisions,
  public.deadline_plan_blocks
to authenticated;

grant select on table public.deadline_plans,
  public.deadline_plan_revisions,
  public.deadline_plan_blocks,
  public.deadline_plan_request_identities
to service_role;

create policy deadline_plans_owner_select
  on public.deadline_plans for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy deadline_plans_service_all
  on public.deadline_plans for all to service_role
  using (true) with check (true);
create policy deadline_plan_revisions_owner_select
  on public.deadline_plan_revisions for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy deadline_plan_revisions_service_all
  on public.deadline_plan_revisions for all to service_role
  using (true) with check (true);
create policy deadline_plan_blocks_owner_select
  on public.deadline_plan_blocks for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy deadline_plan_blocks_service_all
  on public.deadline_plan_blocks for all to service_role
  using (true) with check (true);
create policy deadline_plan_requests_service_all
  on public.deadline_plan_request_identities for all to service_role
  using (true) with check (true);

create or replace function public.get_deadline_plan_projection_v1(
  p_user_id uuid,
  p_plan_id uuid default null
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  with open_plans as materialized (
    select plan.*
    from public.deadline_plans as plan
    where p_plan_id is null
      and plan.user_id = p_user_id
      and plan.status in ('draft', 'active')
    order by plan.updated_at desc, plan.id asc
    limit 51
  ),
  terminal_plans as materialized (
    select plan.*
    from public.deadline_plans as plan
    where p_plan_id is null
      and plan.user_id = p_user_id
      and plan.status in ('completed', 'cancelled')
    order by plan.updated_at desc, plan.id asc
    limit (
      greatest(0, 50 - (select count(*)::int from open_plans))
    )
  ),
  selected_plans as materialized (
    select plan.*
    from public.deadline_plans as plan
    where p_plan_id is not null
      and plan.user_id = p_user_id
      and plan.id = p_plan_id
    union all
    select plan.* from open_plans as plan
    union all
    select plan.* from terminal_plans as plan
  ),
  selected_revisions as materialized (
    select revision.*
    from selected_plans as plan
    join public.deadline_plan_revisions as revision
      on revision.user_id = plan.user_id
     and revision.plan_id = plan.id
     and (
       (
         revision.state = 'active'
         and revision.revision = plan.current_revision
       )
       or (
         plan.status in ('draft', 'active')
         and revision.state = 'proposed'
         and revision.revision = plan.latest_revision
       )
     )
  ),
  selected_blocks as materialized (
    select block.*
    from selected_revisions as revision
    join public.deadline_plan_blocks as block
      on block.user_id = revision.user_id
     and block.plan_id = revision.plan_id
     and block.revision = revision.revision
  ),
  focus_totals as materialized (
    select plan.id as plan_id,
      count(focus.id)::bigint as focus_count,
      coalesce(sum(focus.actual_minutes), 0)::bigint
        as tracked_focus_minutes
    from selected_plans as plan
    left join public.focus_sessions as focus
      on focus.user_id = plan.user_id
     and focus.task_id = plan.managed_task_id
     and focus.status = 'completed'
     and focus.started_at >= plan.first_activated_at
    group by plan.id
  ),
  source_events as materialized (
    select event.id,
      event.user_id,
      event.connection_id,
      event.import_id,
      event.source_fingerprint,
      connection.status as _connection_status,
      connection.last_import_id as _connection_last_import_id,
      connection.imported_data_deleted_at
        as _connection_imported_data_deleted_at
    from public.calendar_events as event
    join (
      select distinct revision.source_calendar_event_id as event_id
      from selected_revisions as revision
      where revision.source_calendar_event_id is not null
    ) as selected_source on selected_source.event_id = event.id
    left join public.calendar_connections as connection
      on connection.id = event.connection_id
     and connection.user_id = event.user_id
    where event.user_id = p_user_id
  )
  select jsonb_build_object(
    'plan_count', (select count(*)::int from selected_plans),
    'plans', coalesce(
      (
        select jsonb_agg(
          to_jsonb(plan) order by plan.updated_at desc, plan.id asc
        )
        from selected_plans as plan
      ),
      '[]'::jsonb
    ),
    'revision_count', (select count(*)::int from selected_revisions),
    'revisions', coalesce(
      (
        select jsonb_agg(
          to_jsonb(revision_row)
          order by revision_row.plan_id, revision_row.revision
        )
        from selected_revisions as revision_row
      ),
      '[]'::jsonb
    ),
    'block_count', (select count(*)::int from selected_blocks),
    'blocks', coalesce(
      (
        select jsonb_agg(
          to_jsonb(block)
          order by block.plan_id, block.revision, block.sequence
        )
        from selected_blocks as block
      ),
      '[]'::jsonb
    ),
    'focus_total_count', (select count(*)::int from focus_totals),
    'focus_totals', coalesce(
      (
        select jsonb_agg(
          to_jsonb(focus) order by focus.plan_id
        )
        from focus_totals as focus
      ),
      '[]'::jsonb
    ),
    'calendar_event_count', (select count(*)::int from source_events),
    'calendar_events', coalesce(
      (
        select jsonb_agg(
          to_jsonb(event) order by event.id
        )
        from source_events as event
      ),
      '[]'::jsonb
    )
  );
$$;

revoke all on function public.get_deadline_plan_projection_v1(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_deadline_plan_projection_v1(uuid, uuid)
to service_role;

create or replace function private.guard_deadline_plan_managed_task()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  gate_open boolean := coalesce(
    current_setting('mylifegraph.deadline_plan_rpc', true),
    ''
  ) = 'on';
  old_managed boolean := false;
  new_managed boolean := false;
begin
  if tg_op <> 'INSERT' then
    old_managed := old.source = 'deadline-plan-v1'
      or old.metadata ->> 'contract_version' = 'deadline-plan-v1'
      or exists (select 1 from public.deadline_plans where id = old.id);
  end if;
  if tg_op <> 'DELETE' then
    new_managed := new.source = 'deadline-plan-v1'
      or new.metadata ->> 'contract_version' = 'deadline-plan-v1'
      or exists (select 1 from public.deadline_plans where id = new.id);
  end if;

  -- Cascaded task deletion during permanent account deletion is nested under
  -- the profile/Auth cascade and must remain possible after focus rows are gone.
  if (old_managed or new_managed)
     and not gate_open
     and not (tg_op = 'DELETE' and pg_trigger_depth() > 1) then
    raise exception 'Deadline-plan managed tasks are backend-workflow owned.'
      using errcode = 'PT409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.guard_deadline_plan_managed_task()
from public, anon, authenticated, service_role;

create trigger tasks_guard_deadline_plan_managed
before insert or update or delete on public.tasks
for each row execute function private.guard_deadline_plan_managed_task();

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
  existing_request public.deadline_plan_request_identities%rowtype;
  plan_row public.deadline_plans%rowtype;
  next_revision int;
  block_count int;
  block_minutes int;
  use_calendar boolean;
  availability_connection uuid;
  availability_import uuid;
  proposal_status text;
  tracked_focus_minutes bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));

  select * into existing_request
  from public.deadline_plan_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'proposal'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.plan_id <> p_plan_id then
      raise exception 'request_id is already bound to another deadline operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'plan_id', existing_request.plan_id,
      'revision', existing_request.result_revision,
      'status', existing_request.result_status
    );
  end if;

  if jsonb_typeof(p_proposal) <> 'object'
     or jsonb_typeof(p_blocks) <> 'array'
     or not (p_proposal ?& array[
       'plan_id', 'base_revision', 'kind', 'title', 'deadline_at',
       'estimated_total_minutes', 'credited_prior_minutes',
       'preferred_session_minutes', 'max_daily_minutes', 'planning_start_on',
       'buffer_days', 'source_kind', 'source_calendar_event_id',
       'source_calendar_event_fingerprint', 'use_calendar_availability',
       'availability_connection_id', 'availability_import_id', 'timezone',
       'best_energy_window', 'planning_fingerprint',
       'tracked_focus_minutes_at_proposal', 'remaining_minutes_at_proposal',
       'planned_minutes', 'unscheduled_minutes'
     ])
     or p_proposal - array[
       'plan_id', 'base_revision', 'kind', 'title', 'deadline_at',
       'estimated_total_minutes', 'credited_prior_minutes',
       'preferred_session_minutes', 'max_daily_minutes', 'planning_start_on',
       'buffer_days', 'source_kind', 'source_calendar_event_id',
       'source_calendar_event_fingerprint', 'use_calendar_availability',
       'availability_connection_id', 'availability_import_id', 'timezone',
       'best_energy_window', 'planning_fingerprint',
       'tracked_focus_minutes_at_proposal', 'remaining_minutes_at_proposal',
       'planned_minutes', 'unscheduled_minutes'
     ] <> '{}'::jsonb
     or exists (
       select 1 from jsonb_array_elements(p_blocks) as block
       where jsonb_typeof(block) <> 'object'
          or not (block ?& array[
            'id', 'sequence', 'starts_at', 'ends_at', 'local_date',
            'local_start_time', 'local_end_time', 'planned_minutes'
          ])
          or block - array[
            'id', 'sequence', 'starts_at', 'ends_at', 'local_date',
            'local_start_time', 'local_end_time', 'planned_minutes'
          ] <> '{}'::jsonb
     )
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or (p_proposal ->> 'plan_id')::uuid <> p_plan_id
     or (p_proposal ->> 'base_revision')::int <> p_base_revision then
    raise exception 'Deadline proposal payload is invalid.' using errcode = '22023';
  end if;

  block_count := jsonb_array_length(p_blocks);
  if block_count > 120 then
    raise exception 'Deadline proposal exceeds the 120-block bound.'
      using errcode = '22023';
  end if;

  select * into plan_row
  from public.deadline_plans
  where id = p_plan_id and user_id = p_user_id
  for update;

  if not found then
    if p_base_revision <> 0 then
      raise exception 'Deadline plan base revision is stale.' using errcode = 'PT409';
    end if;
    next_revision := 1;
    proposal_status := 'draft';
    if (
      select count(*) from public.deadline_plans
      where user_id = p_user_id and status in ('draft', 'active')
    ) >= 50 then
      raise exception 'You already have 50 open deadline plans.'
        using errcode = 'PT409';
    end if;
    insert into public.deadline_plans (
      id, user_id, kind, title,
      original_estimated_total_minutes, original_credited_prior_minutes,
      current_revision, latest_revision, created_at, updated_at
    ) values (
      p_plan_id, p_user_id, p_proposal ->> 'kind', p_proposal ->> 'title',
      (p_proposal ->> 'estimated_total_minutes')::int,
      (p_proposal ->> 'credited_prior_minutes')::int,
      0, 1, p_now, p_now
    );
  else
    if plan_row.status not in ('draft', 'active')
       or plan_row.latest_revision <> p_base_revision then
      raise exception 'Deadline plan changed. Reload before replanning.'
        using errcode = 'PT409';
    end if;
    if plan_row.latest_revision >= 200 then
      raise exception 'Deadline revision history exceeds the V1 bound.'
        using errcode = 'PT409';
    end if;
    if plan_row.current_revision > 0 then
      perform 1
      from public.tasks as task
      where task.id = p_plan_id
        and task.user_id = p_user_id
        and task.status in ('todo', 'in_progress')
        and task.source = 'deadline-plan-v1'
        and task.metadata ->> 'contract_version' = 'deadline-plan-v1'
      for update;
      if not found then
        raise exception 'Managed task is unavailable for replanning.'
          using errcode = 'PT409';
      end if;
      perform 1
      from public.focus_sessions as focus
      where focus.user_id = p_user_id
        and focus.task_id = p_plan_id
        and (
          focus.status = 'active'
          or (
            focus.status = 'completed'
            and focus.started_at >= plan_row.first_activated_at
          )
        )
      for update;
      if exists (
        select 1 from public.focus_sessions as focus
        where focus.user_id = p_user_id
          and focus.task_id = p_plan_id
          and focus.status = 'active'
      ) then
        raise exception 'Finish or abandon active focus before replanning.'
          using errcode = 'PT409';
      end if;
      select coalesce(sum(focus.actual_minutes), 0)::bigint
      into tracked_focus_minutes
      from public.focus_sessions as focus
      where focus.user_id = p_user_id
        and focus.task_id = p_plan_id
        and focus.status = 'completed'
        and focus.started_at >= plan_row.first_activated_at;
      if tracked_focus_minutes <>
         (p_proposal ->> 'tracked_focus_minutes_at_proposal')::bigint then
        raise exception 'Focus progress changed; replan.' using errcode = 'PT409';
      end if;
    end if;
    next_revision := plan_row.latest_revision + 1;
    proposal_status := plan_row.status;
    update public.deadline_plan_revisions
    set state = 'superseded', superseded_at = p_now
    where plan_id = p_plan_id and state = 'proposed';
    update public.deadline_plan_blocks
    set reservation_state = 'superseded', updated_at = p_now
    where plan_id = p_plan_id and reservation_state = 'proposed';
    update public.deadline_plans
    set latest_revision = next_revision,
        kind = case when current_revision = 0 then p_proposal ->> 'kind' else kind end,
        title = case when current_revision = 0 then p_proposal ->> 'title' else title end,
        updated_at = p_now
    where id = p_plan_id;
  end if;

  use_calendar := (p_proposal ->> 'use_calendar_availability')::boolean;
  availability_connection := nullif(p_proposal ->> 'availability_connection_id', '')::uuid;
  availability_import := nullif(p_proposal ->> 'availability_import_id', '')::uuid;
  if use_calendar and not exists (
    select 1 from public.calendar_connections as connection
    where connection.id = availability_connection
      and connection.user_id = p_user_id
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
      and connection.last_import_id = availability_import
  ) then
    raise exception 'Calendar availability is no longer current.' using errcode = 'PT409';
  end if;

  if p_proposal ->> 'source_kind' = 'calendar_event'
     and not exists (
       select 1
       from public.calendar_events as event
       join public.calendar_connections as connection
         on connection.id = event.connection_id
        and connection.user_id = event.user_id
       where event.id = (p_proposal ->> 'source_calendar_event_id')::uuid
         and event.user_id = p_user_id
         and event.source_fingerprint =
           p_proposal ->> 'source_calendar_event_fingerprint'
         and connection.status = 'connected'
         and connection.imported_data_deleted_at is null
         and connection.last_import_id = event.import_id
     ) then
    raise exception 'Selected calendar source is no longer current.'
      using errcode = 'PT409';
  end if;

  with blocks as (
    select * from jsonb_to_recordset(p_blocks) as block(
      id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
      local_date date, local_start_time time, local_end_time time,
      planned_minutes int
    )
  )
  select count(*), coalesce(sum(planned_minutes), 0)
  into block_count, block_minutes from blocks;

  if block_minutes <> (p_proposal ->> 'planned_minutes')::int
     or exists (
       select 1
       from jsonb_to_recordset(p_blocks) as block(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, local_start_time time, local_end_time time,
         planned_minutes int
       )
       having count(*) > 0 and (
         min(block.sequence) <> 1
         or max(block.sequence) <> count(*)
         or count(distinct block.sequence) <> count(*)
       )
     )
     or exists (
       select 1 from jsonb_to_recordset(p_blocks) as block(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, local_start_time time, local_end_time time,
         planned_minutes int
       )
       where block.sequence not between 1 and 120
          or block.ends_at <= block.starts_at
          or block.planned_minutes not between 5 and 240
          or block.ends_at - block.starts_at <>
             block.planned_minutes * interval '1 minute'
          or block.local_date < (p_proposal ->> 'planning_start_on')::date
          or block.local_date <> (
            block.starts_at at time zone (p_proposal ->> 'timezone')
          )::date
          or block.local_start_time <> (
            block.starts_at at time zone (p_proposal ->> 'timezone')
          )::time
          or block.local_end_time <> (
            block.ends_at at time zone (p_proposal ->> 'timezone')
          )::time
          or block.local_date <> (
            block.ends_at at time zone (p_proposal ->> 'timezone')
          )::date
          or block.ends_at > (p_proposal ->> 'deadline_at')::timestamptz
          or (
            (p_proposal ->> 'buffer_days')::int = 0
            and block.local_date > (
              (p_proposal ->> 'deadline_at')::timestamptz
                at time zone (p_proposal ->> 'timezone')
            )::date
          )
          or (
            (p_proposal ->> 'buffer_days')::int > 0
            and block.local_date > (
              (
                (p_proposal ->> 'deadline_at')::timestamptz
                  at time zone (p_proposal ->> 'timezone')
              )::date - (p_proposal ->> 'buffer_days')::int - 1
            )
          )
     )
     or exists (
       select 1
       from jsonb_to_recordset(p_blocks) as block(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, local_start_time time, local_end_time time,
         planned_minutes int
       )
       group by block.local_date
       having sum(block.planned_minutes) >
         (p_proposal ->> 'max_daily_minutes')::int
     )
     or exists (
       select 1
       from jsonb_to_recordset(p_blocks) as left_block(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, local_start_time time, local_end_time time,
         planned_minutes int
       )
       join jsonb_to_recordset(p_blocks) as right_block(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, local_start_time time, local_end_time time,
         planned_minutes int
       ) on left_block.sequence < right_block.sequence
          and tstzrange(left_block.starts_at, left_block.ends_at, '[)') &&
              tstzrange(right_block.starts_at, right_block.ends_at, '[)')
     ) then
    raise exception 'Deadline proposal block shape is invalid.' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_blocks) as proposed(
      id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
      local_date date, local_start_time time, local_end_time time,
      planned_minutes int
    )
    join public.deadline_plan_blocks as active
      on active.user_id = p_user_id
     and active.plan_id <> p_plan_id
     and active.reservation_state = 'active'
     and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
         tstzrange(active.starts_at, active.ends_at, '[)')
  ) then
    raise exception 'Deadline proposal conflicts with a current reservation.'
      using errcode = 'PT409';
  end if;

  insert into public.deadline_plan_revisions (
    user_id, plan_id, revision, base_revision, state, kind, title, deadline_at,
    estimated_total_minutes, credited_prior_minutes, preferred_session_minutes,
    max_daily_minutes, planning_start_on, buffer_days, source_kind,
    source_calendar_event_id, source_calendar_event_fingerprint,
    use_calendar_availability, availability_connection_id,
    availability_import_id, timezone, best_energy_window, planning_fingerprint,
    tracked_focus_minutes_at_proposal, remaining_minutes_at_proposal,
    planned_minutes, unscheduled_minutes, created_at
  ) values (
    p_user_id, p_plan_id, next_revision, p_base_revision, 'proposed',
    p_proposal ->> 'kind', p_proposal ->> 'title',
    (p_proposal ->> 'deadline_at')::timestamptz,
    (p_proposal ->> 'estimated_total_minutes')::int,
    (p_proposal ->> 'credited_prior_minutes')::int,
    (p_proposal ->> 'preferred_session_minutes')::int,
    (p_proposal ->> 'max_daily_minutes')::int,
    (p_proposal ->> 'planning_start_on')::date,
    (p_proposal ->> 'buffer_days')::int,
    p_proposal ->> 'source_kind',
    nullif(p_proposal ->> 'source_calendar_event_id', '')::uuid,
    nullif(p_proposal ->> 'source_calendar_event_fingerprint', ''),
    use_calendar, availability_connection, availability_import,
    p_proposal ->> 'timezone', p_proposal ->> 'best_energy_window',
    p_proposal ->> 'planning_fingerprint',
    (p_proposal ->> 'tracked_focus_minutes_at_proposal')::int,
    (p_proposal ->> 'remaining_minutes_at_proposal')::int,
    (p_proposal ->> 'planned_minutes')::int,
    (p_proposal ->> 'unscheduled_minutes')::int,
    p_now
  );

  insert into public.deadline_plan_blocks (
    id, user_id, plan_id, revision, sequence, reservation_state,
    starts_at, ends_at, local_date, local_start_time, local_end_time,
    planned_minutes, created_at, updated_at
  )
  select block.id, p_user_id, p_plan_id, next_revision, block.sequence,
    'proposed', block.starts_at, block.ends_at, block.local_date,
    block.local_start_time, block.local_end_time, block.planned_minutes,
    p_now, p_now
  from jsonb_to_recordset(p_blocks) as block(
    id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
    local_date date, local_start_time time, local_end_time time,
    planned_minutes int
  );

  insert into public.deadline_plan_request_identities (
    request_id, user_id, operation, request_fingerprint, plan_id,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'proposal', p_request_fingerprint, p_plan_id,
    next_revision, proposal_status, p_now
  );
  return jsonb_build_object(
    'plan_id', p_plan_id, 'revision', next_revision, 'status', proposal_status
  );
end;
$$;

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
  existing_request public.deadline_plan_request_identities%rowtype;
  plan_row public.deadline_plans%rowtype;
  revision_row public.deadline_plan_revisions%rowtype;
  tracked_focus_minutes bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request from public.deadline_plan_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'confirm'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.plan_id <> p_plan_id
       or existing_request.result_revision <> p_expected_revision then
      raise exception 'request_id is already bound to another deadline operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'plan_id', p_plan_id, 'revision', p_expected_revision, 'status', 'active'
    );
  end if;

  select * into plan_row from public.deadline_plans
  where id = p_plan_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Deadline plan is unavailable.' using errcode = 'PT404';
  end if;
  select * into revision_row from public.deadline_plan_revisions
  where plan_id = p_plan_id and user_id = p_user_id
    and revision = p_expected_revision and state = 'proposed'
  for update;
  if not found
     or plan_row.status not in ('draft', 'active')
     or plan_row.latest_revision <> p_expected_revision then
    raise exception 'Deadline proposal changed. Reload before confirmation.'
      using errcode = 'PT409';
  end if;

  if plan_row.current_revision > 0 then
    perform 1
    from public.tasks as task
    where task.id = p_plan_id
      and task.user_id = p_user_id
      and task.status in ('todo', 'in_progress')
      and task.source = 'deadline-plan-v1'
      and task.metadata ->> 'contract_version' = 'deadline-plan-v1'
    for update;
    if not found then
      raise exception 'Managed task is unavailable for replanning.'
        using errcode = 'PT409';
    end if;
    perform 1
    from public.focus_sessions as focus
    where focus.user_id = p_user_id
      and focus.task_id = p_plan_id
      and (
        focus.status = 'active'
        or (
          focus.status = 'completed'
          and focus.started_at >= plan_row.first_activated_at
        )
      )
    for update;
    if exists (
      select 1 from public.focus_sessions as focus
      where focus.user_id = p_user_id
        and focus.task_id = p_plan_id
        and focus.status = 'active'
    ) then
      raise exception 'Finish or abandon active focus before confirmation.'
        using errcode = 'PT409';
    end if;
    select coalesce(sum(focus.actual_minutes), 0)::bigint
    into tracked_focus_minutes
    from public.focus_sessions as focus
    where focus.user_id = p_user_id
      and focus.task_id = p_plan_id
      and focus.status = 'completed'
      and focus.started_at >= plan_row.first_activated_at;
    if tracked_focus_minutes <> revision_row.tracked_focus_minutes_at_proposal then
      raise exception 'Focus progress changed; replan before confirmation.'
        using errcode = 'PT409';
    end if;
  end if;

  if revision_row.use_calendar_availability and not exists (
    select 1 from public.calendar_connections as connection
    where connection.id = revision_row.availability_connection_id
      and connection.user_id = p_user_id
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
      and connection.last_import_id = revision_row.availability_import_id
  ) then
    raise exception 'Calendar availability changed. Replan before confirmation.'
      using errcode = 'PT409';
  end if;
  if revision_row.source_kind = 'calendar_event' and not exists (
    select 1 from public.calendar_events as event
    join public.calendar_connections as connection
      on connection.id = event.connection_id and connection.user_id = event.user_id
    where event.id = revision_row.source_calendar_event_id
      and event.user_id = p_user_id
      and event.source_fingerprint = revision_row.source_calendar_event_fingerprint
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
      and connection.last_import_id = event.import_id
  ) then
    raise exception 'Calendar source changed. Replan before confirmation.'
      using errcode = 'PT409';
  end if;

  if revision_row.deadline_at <= p_now or exists (
    select 1 from public.deadline_plan_blocks as proposed
    join public.deadline_plan_blocks as active
      on active.user_id = p_user_id
     and active.plan_id <> p_plan_id
     and active.reservation_state = 'active'
     and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
         tstzrange(active.starts_at, active.ends_at, '[)')
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_expected_revision
      and proposed.reservation_state = 'proposed'
  ) or exists (
    select 1 from public.deadline_plan_blocks
    where plan_id = p_plan_id and revision = p_expected_revision
      and reservation_state = 'proposed' and starts_at <= p_now
  ) then
    raise exception 'Deadline proposal is stale or conflicts with a reservation.'
      using errcode = 'PT409';
  end if;

  if exists (
    select 1
    from public.deadline_plan_blocks as proposed
    join public.schedule_items as fixed
      on fixed.user_id = p_user_id
     and fixed.weekday = extract(isodow from proposed.local_date)::int
     and fixed.ends_at > fixed.starts_at
     and proposed.local_start_time < fixed.ends_at
     and proposed.local_end_time > fixed.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_expected_revision
      and proposed.reservation_state = 'proposed'
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
         and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
             tstzrange(event.starts_at, event.ends_at, '[)')
        where proposed.plan_id = p_plan_id
          and proposed.revision = p_expected_revision
          and proposed.reservation_state = 'proposed'
      )
      or exists (
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
          and proposed.revision = p_expected_revision
          and proposed.reservation_state = 'proposed'
      )
    )
  ) then
    raise exception 'Availability changed. Replan before confirmation.'
      using errcode = 'PT409';
  end if;

  perform set_config('mylifegraph.deadline_plan_rpc', 'on', true);
  if plan_row.current_revision = 0 then
    if exists (select 1 from public.tasks where id = p_plan_id) then
      raise exception 'Managed task identity is unavailable.' using errcode = 'PT409';
    end if;
    insert into public.tasks (
      id, user_id, title, description, status, priority, deadline,
      estimated_minutes, source, metadata, created_at, updated_at
    ) values (
      p_plan_id, p_user_id, revision_row.title, null,
      'todo', 'high', revision_row.deadline_at, null, 'deadline-plan-v1',
      jsonb_build_object(
        'contract_version', 'deadline-plan-v1',
        'managed_by', 'deadline-planner',
        'plan_id', p_plan_id
      ),
      p_now, p_now
    );
  else
    update public.tasks
    set title = revision_row.title,
        deadline = revision_row.deadline_at,
        estimated_minutes = null,
        source = 'deadline-plan-v1',
        metadata = jsonb_build_object(
          'contract_version', 'deadline-plan-v1',
          'managed_by', 'deadline-planner',
          'plan_id', p_plan_id
        ),
        updated_at = p_now
    where id = p_plan_id and user_id = p_user_id
      and status in ('todo', 'in_progress')
      and source = 'deadline-plan-v1'
      and metadata ->> 'contract_version' = 'deadline-plan-v1';
    if not found then
      raise exception 'Managed task is unavailable for replanning.'
        using errcode = 'PT409';
    end if;
  end if;

  update public.deadline_plan_revisions
  set state = 'superseded', superseded_at = p_now
  where plan_id = p_plan_id and state = 'active';
  update public.deadline_plan_blocks
  set reservation_state = 'superseded', updated_at = p_now
  where plan_id = p_plan_id and reservation_state = 'active';
  update public.deadline_plan_revisions
  set state = 'active', activated_at = p_now
  where plan_id = p_plan_id and revision = p_expected_revision;
  update public.deadline_plan_blocks
  set reservation_state = 'active', updated_at = p_now
  where plan_id = p_plan_id and revision = p_expected_revision;
  update public.deadline_plans
  set status = 'active', kind = revision_row.kind, title = revision_row.title,
      managed_task_id = p_plan_id, current_revision = p_expected_revision,
      first_activated_at = coalesce(first_activated_at, p_now),
      completed_at = null, cancelled_at = null, updated_at = p_now
  where id = p_plan_id;

  insert into public.deadline_plan_request_identities (
    request_id, user_id, operation, request_fingerprint, plan_id,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'confirm', p_request_fingerprint, p_plan_id,
    p_expected_revision, 'active', p_now
  );
  return jsonb_build_object(
    'plan_id', p_plan_id, 'revision', p_expected_revision, 'status', 'active'
  );
end;
$$;

create or replace function public.mutate_deadline_plan_lifecycle_v1(
  p_user_id uuid,
  p_plan_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_revision int,
  p_action text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.deadline_plan_request_identities%rowtype;
  plan_row public.deadline_plans%rowtype;
  target_status text;
begin
  if p_action not in ('complete', 'cancel') then
    raise exception 'Deadline lifecycle action is unsupported.' using errcode = '22023';
  end if;
  target_status := case when p_action = 'complete' then 'completed' else 'cancelled' end;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request from public.deadline_plan_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> p_action
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.plan_id <> p_plan_id
       or existing_request.result_revision <> p_expected_revision then
      raise exception 'request_id is already bound to another deadline operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'plan_id', p_plan_id, 'revision', p_expected_revision,
      'status', existing_request.result_status
    );
  end if;

  select * into plan_row from public.deadline_plans
  where id = p_plan_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Deadline plan is unavailable.' using errcode = 'PT404';
  end if;

  if plan_row.status = 'draft' then
    if p_action <> 'cancel' or plan_row.latest_revision <> p_expected_revision then
      raise exception 'Draft deadline plan cannot perform this lifecycle action.'
        using errcode = 'PT409';
    end if;
  elsif plan_row.status <> 'active'
        or plan_row.current_revision <> p_expected_revision then
    raise exception 'Deadline plan changed. Reload before updating it.'
      using errcode = 'PT409';
  end if;

  if plan_row.status = 'active' then
    perform 1
    from public.tasks
    where id = p_plan_id and user_id = p_user_id
      and status in ('todo', 'in_progress')
      and source = 'deadline-plan-v1'
      and metadata ->> 'contract_version' = 'deadline-plan-v1'
    for update;
    if not found then
      raise exception 'Managed task is unavailable for lifecycle update.'
        using errcode = 'PT409';
    end if;
    if exists (
      select 1 from public.focus_sessions
      where user_id = p_user_id and task_id = p_plan_id and status = 'active'
    ) then
      raise exception 'Finish or abandon the active focus session first.'
        using errcode = 'PT409';
    end if;
    perform set_config('mylifegraph.deadline_plan_rpc', 'on', true);
    update public.tasks
    set status = case when p_action = 'complete' then 'done' else 'cancelled' end,
        completed_at = case when p_action = 'complete' then p_now else null end,
        cancelled_at = case when p_action = 'cancel' then p_now else null end,
        updated_at = p_now
    where id = p_plan_id and user_id = p_user_id
      and status in ('todo', 'in_progress')
      and source = 'deadline-plan-v1'
      and metadata ->> 'contract_version' = 'deadline-plan-v1';
  end if;

  update public.deadline_plan_revisions
  set state = 'superseded', superseded_at = p_now
  where plan_id = p_plan_id and state = 'proposed';
  update public.deadline_plan_blocks
  set reservation_state = 'superseded', updated_at = p_now
  where plan_id = p_plan_id and reservation_state in ('proposed', 'active');
  update public.deadline_plans
  set status = target_status,
      completed_at = case when p_action = 'complete' then p_now else null end,
      cancelled_at = case when p_action = 'cancel' then p_now else null end,
      updated_at = p_now
  where id = p_plan_id;

  insert into public.deadline_plan_request_identities (
    request_id, user_id, operation, request_fingerprint, plan_id,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, p_action, p_request_fingerprint, p_plan_id,
    p_expected_revision, target_status, p_now
  );
  return jsonb_build_object(
    'plan_id', p_plan_id, 'revision', p_expected_revision, 'status', target_status
  );
end;
$$;

revoke all on function public.propose_deadline_plan_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
revoke all on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated;
revoke all on function public.mutate_deadline_plan_lifecycle_v1(
  uuid, uuid, uuid, text, int, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.propose_deadline_plan_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) to service_role;
grant execute on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) to service_role;
grant execute on function public.mutate_deadline_plan_lifecycle_v1(
  uuid, uuid, uuid, text, int, text, timestamptz
) to service_role;
