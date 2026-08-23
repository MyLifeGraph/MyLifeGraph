-- Focus start V2: immutable planned-source provenance, owner-locked starts,
-- actual server timestamps, and source-aware Deadline progress projection.

alter table public.deadline_plan_blocks
  add constraint deadline_plan_blocks_id_user_id_key unique (id, user_id);
alter table public.planner_task_blocks
  add constraint planner_task_blocks_id_user_id_key unique (id, user_id);

create table public.focus_session_schedule_sources (
  focus_session_id uuid primary key,
  user_id uuid not null,
  source_kind text not null,
  deadline_plan_block_id uuid,
  planner_task_block_id uuid,
  original_starts_at timestamptz not null,
  original_ends_at timestamptz not null,
  original_recovery_minutes int not null,
  created_at timestamptz not null,
  unique (focus_session_id, user_id),
  foreign key (focus_session_id, user_id)
    references public.focus_sessions (id, user_id) on delete cascade,
  foreign key (deadline_plan_block_id, user_id)
    references public.deadline_plan_blocks (id, user_id) on delete restrict,
  foreign key (planner_task_block_id, user_id)
    references public.planner_task_blocks (id, user_id) on delete restrict,
  constraint focus_schedule_sources_shape_check check (
    source_kind in ('deadline_plan_block', 'planner_task_block')
    and (
      (
        source_kind = 'deadline_plan_block'
        and deadline_plan_block_id is not null
        and planner_task_block_id is null
      )
      or (
        source_kind = 'planner_task_block'
        and planner_task_block_id is not null
        and deadline_plan_block_id is null
      )
    )
    and original_ends_at > original_starts_at
    and original_ends_at - original_starts_at
      between interval '5 minutes' and interval '240 minutes'
    and original_recovery_minutes between 0 and 60
    and original_recovery_minutes % 5 = 0
  )
);

create index focus_schedule_sources_owner_created_idx
  on public.focus_session_schedule_sources
    (user_id, created_at desc, focus_session_id);
create index focus_schedule_sources_deadline_block_idx
  on public.focus_session_schedule_sources
    (deadline_plan_block_id, focus_session_id)
  where deadline_plan_block_id is not null;
create index focus_schedule_sources_planner_block_idx
  on public.focus_session_schedule_sources
    (planner_task_block_id, focus_session_id)
  where planner_task_block_id is not null;

alter table public.focus_session_schedule_sources enable row level security;
alter table public.focus_session_schedule_sources force row level security;
revoke all on table public.focus_session_schedule_sources
  from public, anon, authenticated, service_role;
grant select on table public.focus_session_schedule_sources to authenticated;
grant select, insert on table public.focus_session_schedule_sources
  to service_role;

create policy "focus_schedule_sources_owner_select"
  on public.focus_session_schedule_sources
  for select
  to authenticated
  using ((select auth.uid()) = user_id);
create policy "focus_schedule_sources_service_select"
  on public.focus_session_schedule_sources
  for select
  to service_role
  using (true);
create policy "focus_schedule_sources_service_insert"
  on public.focus_session_schedule_sources
  for insert
  to service_role
  with check (true);

create or replace function private.guard_focus_schedule_source_immutable_v2()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  raise exception 'Focus schedule source provenance is immutable.'
    using errcode = '23514';
end;
$$;

revoke all on function private.guard_focus_schedule_source_immutable_v2()
  from public, anon, authenticated, service_role;

create trigger focus_schedule_sources_immutable_v2
before update on public.focus_session_schedule_sources
for each row execute function private.guard_focus_schedule_source_immutable_v2();

create or replace function private.focus_resolve_local_instant_v2(
  p_local_timestamp timestamp,
  p_timezone text
)
returns timestamptz
language plpgsql
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  candidate timestamptz;
  resolved_candidate timestamptz;
  valid_candidate_count int;
begin
  if not exists (
    select 1 from pg_catalog.pg_timezone_names where name = p_timezone
  ) then
    return null;
  end if;
  candidate := p_local_timestamp at time zone p_timezone;
  if candidate at time zone p_timezone <> p_local_timestamp then
    return null;
  end if;

  -- PostgreSQL deliberately chooses one side of an ambiguous local clock
  -- value. Derive the offsets in force immediately before, at, and after the
  -- transition window, then accept the local value only when exactly one UTC
  -- candidate round-trips. The 36-hour probes cover non-hour IANA transitions
  -- such as Australia/Lord_Howe without assuming the size of the offset jump.
  with offsets as (
    select distinct
      (probe at time zone p_timezone) - (probe at time zone 'UTC') as value
    from unnest(array[
      candidate - interval '36 hours',
      candidate,
      candidate + interval '36 hours'
    ]) as probes(probe)
  ), candidates as (
    select distinct
      (p_local_timestamp - value) at time zone 'UTC' as instant
    from offsets
  ), valid_candidates as (
    select instant
    from candidates
    where instant at time zone p_timezone = p_local_timestamp
  )
  select count(*)::int, min(instant)
  into valid_candidate_count, resolved_candidate
  from valid_candidates;

  if valid_candidate_count <> 1 then
    return null;
  end if;
  return resolved_candidate;
end;
$$;

revoke all on function private.focus_resolve_local_instant_v2(timestamp, text)
  from public, anon, authenticated, service_role;

create or replace function private.deadline_block_credits_v2(
  p_user_id uuid,
  p_plan_id uuid,
  p_revision int
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  revision_row public.deadline_plan_revisions%rowtype;
  plan_row public.deadline_plans%rowtype;
  focus_row record;
  block_row record;
  credits jsonb := '{}'::jsonb;
  capacities jsonb := '{}'::jsonb;
  proposal_credit_left int;
  generic_credit int := 0;
  available int;
  applied int;
begin
  select * into plan_row
  from public.deadline_plans
  where id = p_plan_id and user_id = p_user_id;
  select * into revision_row
  from public.deadline_plan_revisions
  where plan_id = p_plan_id
    and user_id = p_user_id
    and revision = p_revision;
  if not found or plan_row.id is null then
    return credits;
  end if;

  for block_row in
    select id, planned_minutes
    from public.deadline_plan_blocks
    where plan_id = p_plan_id
      and user_id = p_user_id
      and revision = p_revision
    order by sequence, id
  loop
    credits := credits || jsonb_build_object(block_row.id::text, 0);
    capacities := capacities ||
      jsonb_build_object(block_row.id::text, block_row.planned_minutes);
  end loop;

  proposal_credit_left := revision_row.tracked_focus_minutes_at_proposal;
  for focus_row in
    select
      focus.id,
      focus.actual_minutes,
      source.deadline_plan_block_id
    from public.focus_sessions as focus
    left join public.focus_session_schedule_sources as source
      on source.focus_session_id = focus.id
     and source.user_id = focus.user_id
    where focus.user_id = p_user_id
      and focus.task_id = plan_row.managed_task_id
      and focus.status = 'completed'
      and focus.started_at >= plan_row.first_activated_at
    order by focus.started_at, focus.id
  loop
    applied := least(focus_row.actual_minutes, proposal_credit_left);
    proposal_credit_left := proposal_credit_left - applied;
    focus_row.actual_minutes := focus_row.actual_minutes - applied;
    if focus_row.actual_minutes <= 0 then
      continue;
    end if;

    if focus_row.deadline_plan_block_id is not null
       and credits ? focus_row.deadline_plan_block_id::text then
      available := (capacities ->> focus_row.deadline_plan_block_id::text)::int
        - (credits ->> focus_row.deadline_plan_block_id::text)::int;
      applied := least(focus_row.actual_minutes, greatest(available, 0));
      credits := jsonb_set(
        credits,
        array[focus_row.deadline_plan_block_id::text],
        to_jsonb(
          (credits ->> focus_row.deadline_plan_block_id::text)::int + applied
        )
      );
      focus_row.actual_minutes := focus_row.actual_minutes - applied;
    end if;
    generic_credit := generic_credit + focus_row.actual_minutes;
  end loop;

  for block_row in
    select id, planned_minutes
    from public.deadline_plan_blocks
    where plan_id = p_plan_id
      and user_id = p_user_id
      and revision = p_revision
    order by sequence, id
  loop
    exit when generic_credit <= 0;
    available := block_row.planned_minutes
      - (credits ->> block_row.id::text)::int;
    applied := least(generic_credit, greatest(available, 0));
    credits := jsonb_set(
      credits,
      array[block_row.id::text],
      to_jsonb((credits ->> block_row.id::text)::int + applied)
    );
    generic_credit := generic_credit - applied;
  end loop;
  return credits;
end;
$$;

revoke all on function private.deadline_block_credits_v2(uuid, uuid, int)
  from public, anon, authenticated, service_role;

create or replace function private.focus_schedule_conflict_v2(
  p_user_id uuid,
  p_source_kind text,
  p_block_id uuid,
  p_starts_at timestamptz,
  p_planned_minutes int,
  p_recovery_minutes int
)
returns text
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  profile_row public.profiles%rowtype;
  candidate_ends_at timestamptz;
  local_starts_on date;
  local_ends_on date;
  current_import_id uuid;
  calendar_enabled boolean;
begin
  select * into profile_row from public.profiles where id = p_user_id;
  if not found or not exists (
    select 1 from pg_catalog.pg_timezone_names
    where name = profile_row.timezone
  ) then
    return 'availability_unavailable';
  end if;
  candidate_ends_at := p_starts_at
    + (p_planned_minutes + p_recovery_minutes) * interval '1 minute';
  local_starts_on := (p_starts_at at time zone profile_row.timezone)::date;
  local_ends_on := (
    (candidate_ends_at - interval '1 microsecond')
      at time zone profile_row.timezone
  )::date;

  if exists (
    select 1 from public.focus_sessions
    where user_id = p_user_id and status = 'active'
  ) then
    return 'active_focus_session';
  end if;

  if exists (
    select 1 from public.deadline_plan_blocks as block
    where block.user_id = p_user_id
      and block.reservation_state = 'active'
      and not (
        p_source_kind = 'deadline_plan_block' and block.id = p_block_id
      )
      and tstzrange(p_starts_at, candidate_ends_at, '[)') &&
          tstzrange(block.starts_at, block.reserved_ends_at, '[)')
  ) then
    return 'deadline_plan_block';
  end if;
  if exists (
    select 1 from public.planner_task_blocks as block
    where block.user_id = p_user_id
      and block.state = 'active'
      and not (
        p_source_kind = 'planner_task_block' and block.id = p_block_id
      )
      and tstzrange(p_starts_at, candidate_ends_at, '[)') &&
          tstzrange(block.starts_at, block.reserved_ends_at, '[)')
  ) then
    return 'planner_task_block';
  end if;
  if exists (
    select 1 from public.planner_commitments as commitment
    where commitment.user_id = p_user_id
      and commitment.status = 'active'
      and commitment.recurrence = 'one_off'
      and tstzrange(p_starts_at, candidate_ends_at, '[)') &&
          tstzrange(commitment.starts_at, commitment.ends_at, '[)')
  ) then
    return 'fixed_commitment';
  end if;

  -- Resolve recurring wall times for the candidate dates plus the previous
  -- date so cross-midnight Setup rows remain visible. Invalid or ambiguous
  -- local instants block honestly instead of guessing an offset.
  if exists (
    with dates as (
      select value::date as local_date
      from generate_series(
        local_starts_on - 1,
        local_ends_on,
        interval '1 day'
      ) as value
    ), recurring as (
      select
        private.focus_resolve_local_instant_v2(
          date.local_date + schedule.starts_at,
          profile_row.timezone
        ) as starts_at,
        private.focus_resolve_local_instant_v2(
          date.local_date
            + case when schedule.ends_at <= schedule.starts_at
                then 1 else 0 end
            + schedule.ends_at,
          profile_row.timezone
        ) as ends_at
      from dates as date
      join public.schedule_items as schedule
        on schedule.user_id = p_user_id
       and schedule.weekday = extract(isodow from date.local_date)::int
       and private.setup_schedule_applies_on(
         schedule.metadata, date.local_date
       )
      union all
      select
        private.focus_resolve_local_instant_v2(
          date.local_date + commitment.local_starts_at,
          profile_row.timezone
        ),
        private.focus_resolve_local_instant_v2(
          date.local_date + commitment.local_ends_at,
          profile_row.timezone
        )
      from dates as date
      join public.planner_commitments as commitment
        on commitment.user_id = p_user_id
       and commitment.status = 'active'
       and commitment.recurrence = 'weekly'
       and commitment.weekday = extract(isodow from date.local_date)::int
      union all
      select
        private.focus_resolve_local_instant_v2(
          date.local_date + slot.starts_at,
          profile_row.timezone
        ),
        private.focus_resolve_local_instant_v2(
          date.local_date + slot.ends_at,
          profile_row.timezone
        )
      from dates as date
      join public.planner_habit_slots as slot
        on slot.user_id = p_user_id
       and slot.state = 'active'
       and slot.weekday = extract(isodow from date.local_date)::int
    )
    select 1 from recurring
    where starts_at is null or ends_at is null
  ) then
    return 'availability_unavailable';
  end if;
  if exists (
    with dates as (
      select value::date as local_date
      from generate_series(
        local_starts_on - 1,
        local_ends_on,
        interval '1 day'
      ) as value
    ), recurring as (
      select
        private.focus_resolve_local_instant_v2(
          date.local_date + schedule.starts_at,
          profile_row.timezone
        ) as starts_at,
        private.focus_resolve_local_instant_v2(
          date.local_date
            + case when schedule.ends_at <= schedule.starts_at
                then 1 else 0 end
            + schedule.ends_at,
          profile_row.timezone
        ) as ends_at
      from dates as date
      join public.schedule_items as schedule
        on schedule.user_id = p_user_id
       and schedule.weekday = extract(isodow from date.local_date)::int
       and private.setup_schedule_applies_on(
         schedule.metadata, date.local_date
       )
      union all
      select
        private.focus_resolve_local_instant_v2(
          date.local_date + commitment.local_starts_at,
          profile_row.timezone
        ),
        private.focus_resolve_local_instant_v2(
          date.local_date + commitment.local_ends_at,
          profile_row.timezone
        )
      from dates as date
      join public.planner_commitments as commitment
        on commitment.user_id = p_user_id
       and commitment.status = 'active'
       and commitment.recurrence = 'weekly'
       and commitment.weekday = extract(isodow from date.local_date)::int
      union all
      select
        private.focus_resolve_local_instant_v2(
          date.local_date + slot.starts_at,
          profile_row.timezone
        ),
        private.focus_resolve_local_instant_v2(
          date.local_date + slot.ends_at,
          profile_row.timezone
        )
      from dates as date
      join public.planner_habit_slots as slot
        on slot.user_id = p_user_id
       and slot.state = 'active'
       and slot.weekday = extract(isodow from date.local_date)::int
    )
    select 1 from recurring
    where tstzrange(p_starts_at, candidate_ends_at, '[)') &&
          tstzrange(starts_at, ends_at, '[)')
  ) then
    return 'recurring_commitment';
  end if;

  select coalesce(preference.use_calendar_busy_time, false)
  into calendar_enabled
  from public.planner_preferences as preference
  where preference.user_id = p_user_id;
  calendar_enabled := coalesce(calendar_enabled, false);
  if calendar_enabled then
    select import.id into current_import_id
    from public.calendar_connections as connection
    join public.calendar_imports as import
      on import.id = connection.last_import_id
     and import.user_id = connection.user_id
     and import.connection_id = connection.id
    where connection.user_id = p_user_id
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
      and import.planning_status = 'current'
      and import.profile_timezone_revision = profile_row.timezone_revision
    order by connection.connected_at desc, connection.id
    limit 1;
    if current_import_id is null then
      return 'calendar_availability_unavailable';
    end if;
    if exists (
      select 1 from public.calendar_events as event
      where event.user_id = p_user_id
        and event.import_id = current_import_id
        and event.event_status = 'confirmed'
        and event.busy_status = 'busy'
        and (
          (
            event.event_kind = 'timed'
            and tstzrange(p_starts_at, candidate_ends_at, '[)') &&
                tstzrange(event.starts_at, event.ends_at, '[)')
          )
          or (
            event.event_kind = 'all_day'
            and local_starts_on < event.ends_on
            and local_ends_on >= event.starts_on
          )
        )
    ) then
      return 'calendar_busy';
    end if;
  end if;
  return null;
end;
$$;

revoke all on function private.focus_schedule_conflict_v2(
  uuid, text, uuid, timestamptz, int, int
) from public, anon, authenticated, service_role;

create or replace function public.get_focus_start_context_v2(
  p_user_id uuid,
  p_source_kind text,
  p_block_id uuid,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  block_starts_at timestamptz;
  block_ends_at timestamptz;
  block_recovery int;
  block_minutes int;
  credited_minutes int;
  remaining_minutes int;
  target_id uuid;
  target_title text;
  source_state text;
  blocking_reason text;
  plan_id uuid;
  revision_number int;
  credits jsonb;
begin
  if p_source_kind = 'deadline_plan_block' then
    select
      block.starts_at,
      block.ends_at,
      block.recovery_minutes,
      block.planned_minutes,
      plan.managed_task_id,
      revision.title,
      plan.id,
      revision.revision
    into
      block_starts_at,
      block_ends_at,
      block_recovery,
      block_minutes,
      target_id,
      target_title,
      plan_id,
      revision_number
    from public.deadline_plan_blocks as block
    join public.deadline_plans as plan
      on plan.id = block.plan_id and plan.user_id = block.user_id
    join public.deadline_plan_revisions as revision
      on revision.plan_id = block.plan_id
     and revision.user_id = block.user_id
     and revision.revision = block.revision
    join public.tasks as task
      on task.id = plan.managed_task_id and task.user_id = plan.user_id
    where block.id = p_block_id
      and block.user_id = p_user_id
      and block.reservation_state = 'active'
      and plan.status = 'active'
      and plan.current_revision = block.revision
      and revision.state = 'active'
      and task.status in ('todo', 'in_progress');
    if not found then
      raise exception 'Scheduled Focus source is unavailable.'
        using errcode = 'PT404';
    end if;
    credits := private.deadline_block_credits_v2(
      p_user_id, plan_id, revision_number
    );
    credited_minutes := coalesce((credits ->> p_block_id::text)::int, 0);
  elsif p_source_kind = 'planner_task_block' then
    select
      block.starts_at,
      block.ends_at,
      block.recovery_minutes,
      block.planned_minutes,
      plan.target_id,
      task.title
    into
      block_starts_at,
      block_ends_at,
      block_recovery,
      block_minutes,
      target_id,
      target_title
    from public.planner_task_blocks as block
    join public.planner_action_plans as plan
      on plan.id = block.plan_id and plan.user_id = block.user_id
    join public.planner_action_plan_revisions as revision
      on revision.plan_id = block.plan_id
     and revision.user_id = block.user_id
     and revision.revision = block.revision
    join public.tasks as task
      on task.id = plan.target_id and task.user_id = plan.user_id
    where block.id = p_block_id
      and block.user_id = p_user_id
      and block.state = 'active'
      and plan.status = 'active'
      and plan.target_kind = 'task'
      and plan.current_revision = block.revision
      and revision.state = 'active'
      and task.status in ('todo', 'in_progress');
    if not found then
      raise exception 'Scheduled Focus source is unavailable.'
        using errcode = 'PT404';
    end if;
    select coalesce(sum(focus.actual_minutes), 0)::int
    into credited_minutes
    from public.focus_session_schedule_sources as source
    join public.focus_sessions as focus
      on focus.id = source.focus_session_id
     and focus.user_id = source.user_id
    where source.user_id = p_user_id
      and source.planner_task_block_id = p_block_id
      and focus.status = 'completed';
  else
    raise exception 'Scheduled Focus source kind is invalid.'
      using errcode = '22023';
  end if;

  remaining_minutes := greatest(0, block_minutes - credited_minutes);
  source_state := case
    when remaining_minutes = 0 then 'completed'
    when credited_minutes > 0 then 'partial'
    when p_now >= block_ends_at then 'missed'
    else 'upcoming'
  end;
  if remaining_minutes = 0 then
    blocking_reason := 'source_fully_credited';
  elsif remaining_minutes < 5 then
    blocking_reason := 'source_remaining_too_short';
  else
    blocking_reason := private.focus_schedule_conflict_v2(
      p_user_id,
      p_source_kind,
      p_block_id,
      p_now,
      5,
      block_recovery
    );
  end if;
  return jsonb_build_object(
    'contract_version', 'focus-start-context-v2',
    'origin', 'authenticated_backend',
    'source_kind', p_source_kind,
    'block_id', p_block_id,
    'target', jsonb_build_object(
      'kind', 'task', 'id', target_id, 'title', target_title
    ),
    'original_starts_at', block_starts_at,
    'original_ends_at', block_ends_at,
    'recovery_minutes', block_recovery,
    'remaining_minutes', remaining_minutes,
    'source_state', source_state,
    'can_start', blocking_reason is null,
    'blocking_reason', blocking_reason
  );
end;
$$;

revoke all on function public.get_focus_start_context_v2(
  uuid, text, uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.get_focus_start_context_v2(
  uuid, text, uuid, timestamptz
) to service_role;

create or replace function private.focus_session_response_v2(
  p_user_id uuid,
  p_session_id uuid,
  p_replayed boolean
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'contract_version', 'focus-session-v2',
    'origin', 'authenticated_backend',
    'replayed', p_replayed,
    'id', focus.id,
    'status', focus.status,
    'started_at', focus.started_at,
    'ended_at', focus.ended_at,
    'planned_minutes', focus.planned_minutes,
    'actual_minutes', focus.actual_minutes,
    'label', focus.label,
    'task_id', focus.task_id,
    'habit_id', focus.habit_id,
    'entry_date', focus.metadata ->> 'entry_date',
    'recovery_minutes', coalesce(
      (focus.metadata ->> 'recovery_minutes')::int, 0
    ),
    'updated_at', focus.updated_at,
    'schedule_source', case when source.focus_session_id is null then null
      else jsonb_build_object(
        'source_kind', source.source_kind,
        'block_id', coalesce(
          source.deadline_plan_block_id,
          source.planner_task_block_id
        ),
        'original_starts_at', source.original_starts_at,
        'original_ends_at', source.original_ends_at,
        'original_recovery_minutes', source.original_recovery_minutes
      ) end
  )
  from public.focus_sessions as focus
  left join public.focus_session_schedule_sources as source
    on source.focus_session_id = focus.id and source.user_id = focus.user_id
  where focus.id = p_session_id and focus.user_id = p_user_id;
$$;

revoke all on function private.focus_session_response_v2(uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

create or replace function public.start_focus_session_v2(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_source_kind text,
  p_source_block_id uuid,
  p_planned_minutes int,
  p_recovery_minutes int,
  p_target_kind text,
  p_target_id uuid,
  p_label text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing public.focus_sessions%rowtype;
  profile_row public.profiles%rowtype;
  context jsonb;
  resolved_target_id uuid;
  resolved_label text;
  resolved_recovery int;
  blocking_reason text;
  metadata jsonb;
  violated_constraint text;
begin
  if p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_planned_minutes not between 5 and 240
     or p_source_kind not in (
       'manual', 'deadline_plan_block', 'planner_task_block'
     ) then
    raise exception 'Focus start request is invalid.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing
  from public.focus_sessions
  where id = p_request_id
  for update;
  if found then
    if existing.user_id <> p_user_id
       or existing.metadata ->> 'focus_request_fingerprint'
            is distinct from p_request_fingerprint
       or existing.metadata ->> 'contract_version'
            is distinct from 'focus-session-v2' then
      raise exception 'focus_request_conflict' using errcode = 'PT409';
    end if;
    return private.focus_session_response_v2(
      p_user_id, p_request_id, true
    );
  end if;

  select * into profile_row from public.profiles
  where id = p_user_id for update;
  if not found or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = profile_row.timezone
  ) then
    raise exception 'Account timezone is unavailable.' using errcode = 'PT409';
  end if;

  perform 1
  from public.focus_sessions as focus
  where focus.user_id = p_user_id and focus.status = 'active'
  for update;
  if found then
    raise exception 'active_focus_session' using errcode = 'PT409';
  end if;

  if p_source_kind = 'manual' then
    if p_source_block_id is not null
       or (p_target_kind is null) <> (p_target_id is null)
       or p_target_kind is not null and p_target_kind not in ('task', 'habit')
       or p_recovery_minutes <> 0 and (
         p_recovery_minutes not between 5 and 60
         or p_recovery_minutes % 5 <> 0
       )
       or p_label is not null and (
         length(p_label) not between 1 and 160 or p_label <> btrim(p_label)
       ) then
      raise exception 'Manual Focus start request is invalid.'
        using errcode = '22023';
    end if;
    resolved_target_id := p_target_id;
    resolved_label := p_label;
    resolved_recovery := p_recovery_minutes;
  else
    if p_source_block_id is null
       or p_recovery_minutes <> 0
       or p_target_kind is not null
       or p_target_id is not null
       or p_label is not null then
      raise exception 'Scheduled Focus start request is invalid.'
        using errcode = '22023';
    end if;
    context := public.get_focus_start_context_v2(
      p_user_id, p_source_kind, p_source_block_id, p_now
    );
    if not (context ->> 'can_start')::boolean then
      raise exception '%', context ->> 'blocking_reason'
        using errcode = 'PT409';
    end if;
    if p_planned_minutes > (context ->> 'remaining_minutes')::int then
      raise exception 'Scheduled Focus duration exceeds remaining minutes.'
        using errcode = 'PT409';
    end if;
    blocking_reason := private.focus_schedule_conflict_v2(
      p_user_id,
      p_source_kind,
      p_source_block_id,
      p_now,
      p_planned_minutes,
      (context ->> 'recovery_minutes')::int
    );
    if blocking_reason is not null then
      raise exception '%', blocking_reason using errcode = 'PT409';
    end if;
    resolved_target_id := (context #>> '{target,id}')::uuid;
    resolved_label := context #>> '{target,title}';
    resolved_recovery := (context ->> 'recovery_minutes')::int;
  end if;

  metadata := jsonb_build_object(
    'source', 'flutter-focus-v2',
    'contract_version', 'focus-session-v2',
    'entry_date', to_char(p_now at time zone profile_row.timezone, 'YYYY-MM-DD'),
    'focus_request_fingerprint', p_request_fingerprint,
    'action_target', jsonb_build_object(
      'contract_version', 'executable-action-v1',
      'id', 'start_focus:' || p_request_id::text,
      'kind', 'focus',
      'command', 'start_focus',
      'target_id', resolved_target_id,
      'estimated_minutes', p_planned_minutes,
      'metadata', jsonb_strip_nulls(jsonb_build_object(
        'focus_minutes', p_planned_minutes,
        'source', 'focus_session',
        'target_kind', case
          when resolved_target_id is null then null
          when p_source_kind <> 'manual' then 'task'
          else p_target_kind end
      ))
    )
  );
  if resolved_recovery > 0 then
    metadata := metadata ||
      jsonb_build_object('recovery_minutes', resolved_recovery);
  end if;

  begin
    insert into public.focus_sessions (
      id, user_id, status, started_at, planned_minutes, label,
      task_id, habit_id, metadata, updated_at
    ) values (
      p_request_id,
      p_user_id,
      'active',
      p_now,
      p_planned_minutes,
      resolved_label,
      case when p_source_kind <> 'manual' or p_target_kind = 'task'
        then resolved_target_id else null end,
      case when p_source_kind = 'manual' and p_target_kind = 'habit'
        then resolved_target_id else null end,
      metadata,
      p_now
    );
  exception when unique_violation then
    get stacked diagnostics violated_constraint = constraint_name;
    if violated_constraint = 'focus_sessions_one_active_per_user_idx' then
      raise exception 'active_focus_session' using errcode = 'PT409';
    end if;
    raise;
  end;

  if p_source_kind <> 'manual' then
    insert into public.focus_session_schedule_sources (
      focus_session_id,
      user_id,
      source_kind,
      deadline_plan_block_id,
      planner_task_block_id,
      original_starts_at,
      original_ends_at,
      original_recovery_minutes,
      created_at
    ) values (
      p_request_id,
      p_user_id,
      p_source_kind,
      case when p_source_kind = 'deadline_plan_block'
        then p_source_block_id else null end,
      case when p_source_kind = 'planner_task_block'
        then p_source_block_id else null end,
      (context ->> 'original_starts_at')::timestamptz,
      (context ->> 'original_ends_at')::timestamptz,
      resolved_recovery,
      p_now
    );
  end if;
  return private.focus_session_response_v2(p_user_id, p_request_id, false);
end;
$$;

revoke all on function public.start_focus_session_v2(
  uuid, uuid, text, text, uuid, int, int, text, uuid, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.start_focus_session_v2(
  uuid, uuid, text, text, uuid, int, int, text, uuid, text, timestamptz
) to service_role;

create or replace function public.finish_focus_session_v2(
  p_user_id uuid,
  p_session_id uuid,
  p_terminal_status text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  session_row public.focus_sessions%rowtype;
  replayed boolean := false;
begin
  if p_terminal_status not in ('completed', 'abandoned') then
    raise exception 'Focus terminal status is invalid.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 17));
  select * into session_row
  from public.focus_sessions
  where id = p_session_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Focus session is unavailable.' using errcode = 'PT404';
  end if;
  if session_row.status = p_terminal_status then
    replayed := true;
  elsif session_row.status <> 'active' then
    raise exception 'Focus session already ended differently.'
      using errcode = 'PT409';
  elsif p_now < session_row.started_at then
    raise exception 'Focus server time is invalid.' using errcode = 'PT409';
  else
    update public.focus_sessions
    set status = p_terminal_status,
        ended_at = p_now,
        actual_minutes = floor(
          extract(epoch from (p_now - session_row.started_at)) / 60
        )::int,
        updated_at = p_now
    where id = p_session_id and user_id = p_user_id;
  end if;
  return private.focus_session_response_v2(
    p_user_id, p_session_id, replayed
  );
end;
$$;

revoke all on function public.finish_focus_session_v2(
  uuid, uuid, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.finish_focus_session_v2(
  uuid, uuid, text, timestamptz
) to service_role;

create or replace function public.get_deadline_plan_projection_v2(
  p_user_id uuid,
  p_plan_id uuid default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  projection jsonb;
  facts jsonb;
begin
  projection := public.get_deadline_plan_projection_v1(p_user_id, p_plan_id);
  select coalesce(jsonb_agg(to_jsonb(fact) order by fact.started_at, fact.id),
                  '[]'::jsonb)
  into facts
  from (
    select
      focus.id,
      plan.id as plan_id,
      focus.started_at,
      focus.actual_minutes,
      source.deadline_plan_block_id
    from public.deadline_plans as plan
    join public.focus_sessions as focus
      on focus.user_id = plan.user_id
     and focus.task_id = plan.managed_task_id
     and focus.status = 'completed'
     and focus.started_at >= plan.first_activated_at
    left join public.focus_session_schedule_sources as source
      on source.focus_session_id = focus.id
     and source.user_id = focus.user_id
    where plan.user_id = p_user_id
      and (
        p_plan_id is not null and plan.id = p_plan_id
        or p_plan_id is null and exists (
          select 1
          from jsonb_array_elements(projection -> 'plans') as selected(value)
          where selected.value ->> 'id' = plan.id::text
        )
      )
  ) as fact;
  return projection
    || jsonb_build_object('focus_fact_count', jsonb_array_length(facts))
    || jsonb_build_object('focus_facts', facts);
end;
$$;

revoke all on function public.get_deadline_plan_projection_v2(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.get_deadline_plan_projection_v2(uuid, uuid)
  to service_role;
