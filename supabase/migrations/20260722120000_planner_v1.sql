-- Planner V1: staged Task/Habit reservations and authoritative commitments.

create table public.planner_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  contract_version text not null default 'planner-preferences-v1',
  use_calendar_busy_time boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  constraint planner_preferences_contract_check check (
    contract_version = 'planner-preferences-v1'
    and updated_at >= created_at
  )
);

create table public.planner_action_plans (
  id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  contract_version text not null default 'planner-v1',
  target_kind text not null,
  target_id uuid not null,
  status text not null default 'draft',
  current_revision int not null default 0,
  latest_revision int not null default 1,
  attention_reasons text[] not null default '{}'::text[],
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (id, user_id),
  unique (user_id, target_kind, target_id),
  constraint planner_action_plans_contract_check check (
    contract_version = 'planner-v1'
    and target_kind in ('task', 'habit')
    and status in ('draft', 'active', 'unscheduled', 'cancelled')
    and current_revision >= 0
    and latest_revision between greatest(current_revision, 1) and 500
    and cardinality(attention_reasons) <= 12
    and array_position(attention_reasons, null) is null
    and updated_at >= created_at
  )
);

create table public.planner_action_plan_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  plan_id uuid not null,
  revision int not null,
  base_revision int not null,
  state text not null default 'proposed',
  target_payload jsonb not null,
  timezone text not null,
  best_energy_window text not null,
  planning_start_on date not null,
  planning_fingerprint text not null,
  calendar_import_id uuid,
  planned_minutes int not null,
  unscheduled_minutes int not null,
  created_at timestamptz not null,
  activated_at timestamptz,
  superseded_at timestamptz,
  unique (plan_id, revision),
  unique (plan_id, user_id, revision),
  foreign key (plan_id, user_id)
    references public.planner_action_plans (id, user_id) on delete cascade,
  constraint planner_action_revisions_sequence_check check (
    revision = base_revision + 1 and revision between 1 and 500
  ),
  constraint planner_action_revisions_shape_check check (
    jsonb_typeof(target_payload) = 'object'
    and target_payload ->> 'kind' in ('task', 'habit')
    and target_payload ->> 'operation' in ('create', 'update')
    and length(timezone) between 1 and 100
    and best_energy_window in (
      'early_morning', 'morning', 'afternoon', 'evening', 'variable'
    )
    and planning_fingerprint ~ '^[0-9a-f]{64}$'
    and planned_minutes >= 0
    and unscheduled_minutes >= 0
  ),
  constraint planner_action_revisions_lifecycle_check check (
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

create unique index planner_action_revisions_one_proposed_idx
  on public.planner_action_plan_revisions (plan_id)
  where state = 'proposed';
create unique index planner_action_revisions_one_active_idx
  on public.planner_action_plan_revisions (plan_id)
  where state = 'active';

create table public.planner_task_blocks (
  id uuid primary key,
  user_id uuid not null,
  plan_id uuid not null,
  revision int not null,
  sequence int not null,
  state text not null default 'proposed',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  local_date date not null,
  planned_minutes int not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (plan_id, revision, sequence),
  foreign key (plan_id, user_id, revision)
    references public.planner_action_plan_revisions (plan_id, user_id, revision)
    on delete cascade,
  constraint planner_task_blocks_shape_check check (
    sequence between 1 and 1500
    and state in ('proposed', 'active', 'released', 'superseded')
    and ends_at > starts_at
    and planned_minutes between 5 and 240
    and planned_minutes % 5 = 0
    and ends_at - starts_at = planned_minutes * interval '1 minute'
    and updated_at >= created_at
  )
);

create index planner_task_blocks_owner_active_time_idx
  on public.planner_task_blocks (user_id, starts_at, ends_at, id)
  where state = 'active';

create table public.planner_habit_slots (
  id uuid primary key,
  user_id uuid not null,
  plan_id uuid not null,
  revision int not null,
  weekday int not null,
  starts_at time not null,
  ends_at time not null,
  duration_minutes int not null,
  state text not null default 'proposed',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (plan_id, revision, weekday),
  foreign key (plan_id, user_id, revision)
    references public.planner_action_plan_revisions (plan_id, user_id, revision)
    on delete cascade,
  constraint planner_habit_slots_shape_check check (
    weekday between 1 and 7
    and ends_at > starts_at
    and duration_minutes between 5 and 240
    and duration_minutes % 5 = 0
    and extract(epoch from (ends_at - starts_at)) / 60 = duration_minutes
    and state in ('proposed', 'active', 'released', 'superseded')
    and updated_at >= created_at
  )
);

create index planner_habit_slots_owner_active_time_idx
  on public.planner_habit_slots (user_id, weekday, starts_at, ends_at, id)
  where state = 'active';

create table public.planner_commitments (
  id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  contract_version text not null default 'planner-v1',
  title text not null,
  location text,
  recurrence text not null,
  status text not null default 'active',
  starts_at timestamptz,
  ends_at timestamptz,
  weekday int,
  local_starts_at time,
  local_ends_at time,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  constraint planner_commitments_contract_check check (
    contract_version = 'planner-v1'
    and length(title) between 1 and 160
    and title = trim(title)
    and (location is null or length(location) <= 300)
    and recurrence in ('one_off', 'weekly')
    and status in ('active', 'archived')
    and updated_at >= created_at
    and ((status = 'active') = (archived_at is null))
    and (
      (
        recurrence = 'one_off'
        and starts_at is not null
        and ends_at > starts_at
        and weekday is null
        and local_starts_at is null
        and local_ends_at is null
      )
      or (
        recurrence = 'weekly'
        and starts_at is null
        and ends_at is null
        and weekday between 1 and 7
        and local_starts_at is not null
        and local_ends_at > local_starts_at
      )
    )
  )
);

create index planner_commitments_owner_active_idx
  on public.planner_commitments (user_id, recurrence, starts_at, weekday, id)
  where status = 'active';

create table public.planner_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  operation text not null,
  resource_id uuid not null,
  request_fingerprint text not null,
  result_revision int,
  result_status text not null,
  created_at timestamptz not null,
  constraint planner_requests_contract_check check (
    operation in (
      'preferences', 'proposal', 'confirm', 'cancel',
      'commitment_create', 'commitment_update', 'commitment_archive'
    )
    and request_fingerprint ~ '^[0-9a-f]{64}$'
    and (result_revision is null or result_revision between 1 and 500)
    and length(result_status) between 1 and 40
  )
);

alter table public.planner_preferences enable row level security;
alter table public.planner_preferences force row level security;
alter table public.planner_action_plans enable row level security;
alter table public.planner_action_plans force row level security;
alter table public.planner_action_plan_revisions enable row level security;
alter table public.planner_action_plan_revisions force row level security;
alter table public.planner_task_blocks enable row level security;
alter table public.planner_task_blocks force row level security;
alter table public.planner_habit_slots enable row level security;
alter table public.planner_habit_slots force row level security;
alter table public.planner_commitments enable row level security;
alter table public.planner_commitments force row level security;
alter table public.planner_request_identities enable row level security;
alter table public.planner_request_identities force row level security;

revoke all on table public.planner_preferences,
  public.planner_action_plans,
  public.planner_action_plan_revisions,
  public.planner_task_blocks,
  public.planner_habit_slots,
  public.planner_commitments,
  public.planner_request_identities
from public, anon, authenticated, service_role;

grant select on table public.planner_preferences,
  public.planner_action_plans,
  public.planner_action_plan_revisions,
  public.planner_task_blocks,
  public.planner_habit_slots,
  public.planner_commitments
to authenticated;

grant select, insert, update, delete on table public.planner_preferences,
  public.planner_action_plans,
  public.planner_action_plan_revisions,
  public.planner_task_blocks,
  public.planner_habit_slots,
  public.planner_commitments,
  public.planner_request_identities
to service_role;

create policy planner_preferences_owner_select
  on public.planner_preferences for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy planner_preferences_service_all
  on public.planner_preferences for all to service_role
  using (true) with check (true);
create policy planner_action_plans_owner_select
  on public.planner_action_plans for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy planner_action_plans_service_all
  on public.planner_action_plans for all to service_role
  using (true) with check (true);
create policy planner_action_revisions_owner_select
  on public.planner_action_plan_revisions for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy planner_action_revisions_service_all
  on public.planner_action_plan_revisions for all to service_role
  using (true) with check (true);
create policy planner_task_blocks_owner_select
  on public.planner_task_blocks for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy planner_task_blocks_service_all
  on public.planner_task_blocks for all to service_role
  using (true) with check (true);
create policy planner_habit_slots_owner_select
  on public.planner_habit_slots for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy planner_habit_slots_service_all
  on public.planner_habit_slots for all to service_role
  using (true) with check (true);
create policy planner_commitments_owner_select
  on public.planner_commitments for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy planner_commitments_service_all
  on public.planner_commitments for all to service_role
  using (true) with check (true);
create policy planner_requests_service_all
  on public.planner_request_identities for all to service_role
  using (true) with check (true);

create or replace function public.set_planner_preferences_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_expected_updated_at timestamptz,
  p_use_calendar_busy_time boolean,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.planner_request_identities%rowtype;
  current_row public.planner_preferences%rowtype;
  request_fingerprint text;
begin
  request_fingerprint := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'operation', 'preferences',
          'user_id', p_user_id,
          'expected_updated_at', p_expected_updated_at,
          'use_calendar_busy_time', p_use_calendar_busy_time
        )::text,
        'utf8'
      ),
      'sha256'
    ),
    'hex'
  );
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request
  from public.planner_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'preferences'
       or existing_request.resource_id <> p_user_id
       or existing_request.request_fingerprint <> request_fingerprint then
      raise exception 'request_id is already bound to another Planner operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object('updated_at', existing_request.created_at);
  end if;

  perform 1 from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Planner profile is unavailable.' using errcode = 'P0002';
  end if;
  select * into current_row
  from public.planner_preferences
  where user_id = p_user_id
  for update;
  if found then
    if p_expected_updated_at is null
       or current_row.updated_at <> p_expected_updated_at then
      raise exception 'Planner preferences changed. Reload before saving.'
        using errcode = 'PT409';
    end if;
    update public.planner_preferences
    set use_calendar_busy_time = p_use_calendar_busy_time,
        updated_at = greatest(p_now, current_row.updated_at)
    where user_id = p_user_id;
  else
    if p_expected_updated_at is not null then
      raise exception 'Planner preferences changed. Reload before saving.'
        using errcode = 'PT409';
    end if;
    insert into public.planner_preferences (
      user_id, use_calendar_busy_time, created_at, updated_at
    ) values (
      p_user_id, p_use_calendar_busy_time, p_now, p_now
    );
  end if;
  insert into public.planner_request_identities (
    request_id, user_id, operation, resource_id, request_fingerprint,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'preferences', p_user_id, request_fingerprint,
    null, 'saved', p_now
  );
  return jsonb_build_object('updated_at', p_now);
end;
$$;

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
  existing_request public.planner_request_identities%rowtype;
  plan_row public.planner_action_plans%rowtype;
  target_operation text;
  next_revision int;
  block_count int;
  block_minutes int;
  slot_count int;
  slot_minutes int;
  calendar_import uuid;
  preference_enabled boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request
  from public.planner_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'proposal'
       or existing_request.resource_id <> p_plan_id
       or existing_request.request_fingerprint <> p_request_fingerprint then
      raise exception 'request_id is already bound to another Planner operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'plan_id', p_plan_id,
      'revision', existing_request.result_revision,
      'status', existing_request.result_status
    );
  end if;

  if p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_target_kind not in ('task', 'habit')
     or jsonb_typeof(p_target_payload) <> 'object'
     or jsonb_typeof(p_revision_payload) <> 'object'
     or jsonb_typeof(p_task_blocks) <> 'array'
     or jsonb_typeof(p_habit_slots) <> 'array'
     or p_revision_payload - array[
       'revision', 'base_revision', 'target', 'timezone',
       'best_energy_window', 'planning_start_on', 'planning_fingerprint',
       'calendar_import_id', 'planned_minutes', 'unscheduled_minutes'
     ] <> '{}'::jsonb
     or not (p_revision_payload ?& array[
       'revision', 'base_revision', 'target', 'timezone',
       'best_energy_window', 'planning_start_on', 'planning_fingerprint',
       'calendar_import_id', 'planned_minutes', 'unscheduled_minutes'
     ])
     or p_revision_payload -> 'target' <> p_target_payload
     or p_target_payload ->> 'kind' <> p_target_kind
     or (p_target_payload ->> 'target_id')::uuid <> p_target_id
     or (p_revision_payload ->> 'base_revision')::int <> p_base_revision
     or (p_revision_payload ->> 'revision')::int <> p_base_revision + 1 then
    raise exception 'Planner proposal payload is invalid.' using errcode = '22023';
  end if;

  if p_target_kind = 'task' then
    if p_target_payload - array[
      'kind', 'operation', 'target_id', 'expected_updated_at', 'title',
      'description', 'priority', 'estimated_minutes', 'deadline_at',
      'preferred_session_minutes'
    ] <> '{}'::jsonb
       or not (p_target_payload ?& array[
         'kind', 'operation', 'target_id', 'expected_updated_at', 'title',
         'description', 'priority', 'estimated_minutes', 'deadline_at',
         'preferred_session_minutes'
       ])
       or jsonb_array_length(p_habit_slots) <> 0 then
      raise exception 'Planner Task proposal payload is invalid.'
        using errcode = '22023';
    end if;
  else
    if p_target_payload - array[
      'kind', 'operation', 'target_id', 'expected_updated_at', 'title',
      'description', 'cadence', 'duration_minutes'
    ] <> '{}'::jsonb
       or not (p_target_payload ?& array[
         'kind', 'operation', 'target_id', 'expected_updated_at', 'title',
         'description', 'cadence', 'duration_minutes'
       ])
       or jsonb_array_length(p_task_blocks) <> 0
       or jsonb_typeof(p_target_payload -> 'cadence') <> 'object' then
      raise exception 'Planner Habit proposal payload is invalid.'
        using errcode = '22023';
    end if;
  end if;
  target_operation := p_target_payload ->> 'operation';
  if target_operation not in ('create', 'update')
     or length(p_target_payload ->> 'title') not between 1 and 160
     or p_target_payload ->> 'title' <> trim(p_target_payload ->> 'title') then
    raise exception 'Planner target is invalid.' using errcode = '22023';
  end if;

  if target_operation = 'create' then
    if p_target_payload -> 'expected_updated_at' <> 'null'::jsonb then
      raise exception 'A new Planner target cannot carry a version.'
        using errcode = '22023';
    end if;
    if (p_target_kind = 'task' and exists (
      select 1 from public.tasks where id = p_target_id
    )) or (p_target_kind = 'habit' and exists (
      select 1 from public.habits where id = p_target_id
    )) then
      raise exception 'The Planner target id is already in use.'
        using errcode = 'PT409';
    end if;
  elsif p_target_payload -> 'expected_updated_at' = 'null'::jsonb then
    raise exception 'An updated Planner target requires its exact version.'
      using errcode = '22023';
  elsif p_target_kind = 'task' then
    perform 1 from public.tasks
    where id = p_target_id
      and user_id = p_user_id
      and updated_at = (p_target_payload ->> 'expected_updated_at')::timestamptz
      and status in ('todo', 'in_progress')
    for update;
    if not found then
      raise exception 'The Task changed or is unavailable.' using errcode = 'PT409';
    end if;
  else
    perform 1 from public.habits
    where id = p_target_id
      and user_id = p_user_id
      and updated_at = (p_target_payload ->> 'expected_updated_at')::timestamptz
      and active = true
      and coalesce(metadata ->> 'lifecycle', 'active') = 'active'
    for update;
    if not found then
      raise exception 'The Habit changed or is unavailable.' using errcode = 'PT409';
    end if;
  end if;

  select * into plan_row
  from public.planner_action_plans
  where id = p_plan_id and user_id = p_user_id
  for update;
  if not found then
    if p_base_revision <> 0 then
      raise exception 'Planner base revision is stale.' using errcode = 'PT409';
    end if;
    if exists (
      select 1 from public.planner_action_plans
      where user_id = p_user_id
        and target_kind = p_target_kind
        and target_id = p_target_id
    ) then
      raise exception 'The target already has an action plan.' using errcode = 'PT409';
    end if;
    if (
      select count(*) from public.planner_action_plans
      where user_id = p_user_id and status <> 'cancelled'
    ) >= 1000 then
      raise exception 'Planner action plan count exceeds its bound.'
        using errcode = 'PT409';
    end if;
    next_revision := 1;
    insert into public.planner_action_plans (
      id, user_id, target_kind, target_id, status,
      current_revision, latest_revision, created_at, updated_at
    ) values (
      p_plan_id, p_user_id, p_target_kind, p_target_id, 'draft',
      0, 1, p_now, p_now
    );
  else
    if plan_row.status = 'cancelled'
       or plan_row.target_kind <> p_target_kind
       or plan_row.target_id <> p_target_id
       or plan_row.latest_revision <> p_base_revision
       or plan_row.latest_revision >= 500 then
      raise exception 'Planner action plan changed. Reload before replanning.'
        using errcode = 'PT409';
    end if;
    next_revision := plan_row.latest_revision + 1;
    update public.planner_action_plan_revisions
    set state = 'superseded', superseded_at = p_now
    where plan_id = p_plan_id and state = 'proposed';
    update public.planner_task_blocks
    set state = 'superseded', updated_at = p_now
    where plan_id = p_plan_id and state = 'proposed';
    update public.planner_habit_slots
    set state = 'superseded', updated_at = p_now
    where plan_id = p_plan_id and state = 'proposed';
    update public.planner_action_plans
    set latest_revision = next_revision,
        status = case when current_revision = 0 then 'draft' else status end,
        updated_at = p_now
    where id = p_plan_id;
  end if;

  calendar_import := nullif(p_revision_payload ->> 'calendar_import_id', '')::uuid;
  select coalesce(preference.use_calendar_busy_time, false)
  into preference_enabled
  from (select p_user_id as user_id) as owner
  left join public.planner_preferences as preference
    on preference.user_id = owner.user_id;
  if preference_enabled <> (calendar_import is not null) then
    raise exception 'Planner calendar preference changed. Create a new preview.'
      using errcode = 'PT409';
  end if;
  if calendar_import is not null and not exists (
    select 1 from public.calendar_connections as connection
    where connection.user_id = p_user_id
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
      and connection.last_import_id = calendar_import
  ) then
    raise exception 'Planner calendar import is no longer current.'
      using errcode = 'PT409';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_task_blocks) as value
    where jsonb_typeof(value) <> 'object'
       or value - array[
         'id', 'sequence', 'starts_at', 'ends_at', 'local_date', 'planned_minutes'
       ] <> '{}'::jsonb
       or not (value ?& array[
         'id', 'sequence', 'starts_at', 'ends_at', 'local_date', 'planned_minutes'
       ])
  ) or exists (
    select 1 from jsonb_array_elements(p_habit_slots) as value
    where jsonb_typeof(value) <> 'object'
       or value - array[
         'id', 'weekday', 'starts_at', 'ends_at', 'duration_minutes'
       ] <> '{}'::jsonb
       or not (value ?& array[
         'id', 'weekday', 'starts_at', 'ends_at', 'duration_minutes'
       ])
  ) then
    raise exception 'Planner reservation payload is invalid.' using errcode = '22023';
  end if;

  with blocks as (
    select * from jsonb_to_recordset(p_task_blocks) as value(
      id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
      local_date date, planned_minutes int
    )
  )
  select count(*), coalesce(sum(planned_minutes), 0)
  into block_count, block_minutes from blocks;
  with slots as (
    select * from jsonb_to_recordset(p_habit_slots) as value(
      id uuid, weekday int, starts_at time, ends_at time, duration_minutes int
    )
  )
  select count(*), coalesce(sum(duration_minutes), 0)
  into slot_count, slot_minutes from slots;
  if block_count > 1500
     or slot_count > 7
     or block_minutes + slot_minutes < 0
     or block_minutes + slot_minutes <> (p_revision_payload ->> 'planned_minutes')::int
     or exists (
       select 1 from jsonb_to_recordset(p_task_blocks) as value(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, planned_minutes int
       )
       where sequence not between 1 and 1500
          or planned_minutes not between 5 and 240
          or planned_minutes % 5 <> 0
          or ends_at - starts_at <> planned_minutes * interval '1 minute'
     )
     or exists (
       select 1 from jsonb_to_recordset(p_task_blocks) as left_value(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, planned_minutes int
       )
       join jsonb_to_recordset(p_task_blocks) as right_value(
         id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
         local_date date, planned_minutes int
       ) on left_value.sequence < right_value.sequence
        and tstzrange(left_value.starts_at, left_value.ends_at, '[)') &&
            tstzrange(right_value.starts_at, right_value.ends_at, '[)')
     )
     or exists (
       select 1 from jsonb_to_recordset(p_habit_slots) as value(
         id uuid, weekday int, starts_at time, ends_at time, duration_minutes int
       )
       where weekday not between 1 and 7
          or ends_at <= starts_at
          or duration_minutes not between 5 and 240
          or duration_minutes % 5 <> 0
          or extract(epoch from (ends_at - starts_at)) / 60 <> duration_minutes
     ) then
    raise exception 'Planner reservation shape is invalid.' using errcode = '22023';
  end if;
  if block_count > 0 and (
    select count(distinct sequence) <> block_count
        or min(sequence) <> 1
        or max(sequence) <> block_count
    from jsonb_to_recordset(p_task_blocks) as value(
      id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
      local_date date, planned_minutes int
    )
  ) then
    raise exception 'Planner Task block sequence is invalid.' using errcode = '22023';
  end if;
  if slot_count > 0 and (
    select count(distinct weekday) <> slot_count
    from jsonb_to_recordset(p_habit_slots) as value(
      id uuid, weekday int, starts_at time, ends_at time, duration_minutes int
    )
  ) then
    raise exception 'Planner Habit weekdays must be unique.' using errcode = '22023';
  end if;

  insert into public.planner_action_plan_revisions (
    user_id, plan_id, revision, base_revision, state, target_payload,
    timezone, best_energy_window, planning_start_on, planning_fingerprint,
    calendar_import_id, planned_minutes, unscheduled_minutes, created_at
  ) values (
    p_user_id, p_plan_id, next_revision, p_base_revision, 'proposed',
    p_target_payload, p_revision_payload ->> 'timezone',
    p_revision_payload ->> 'best_energy_window',
    (p_revision_payload ->> 'planning_start_on')::date,
    p_revision_payload ->> 'planning_fingerprint', calendar_import,
    (p_revision_payload ->> 'planned_minutes')::int,
    (p_revision_payload ->> 'unscheduled_minutes')::int, p_now
  );
  insert into public.planner_task_blocks (
    id, user_id, plan_id, revision, sequence, state, starts_at, ends_at,
    local_date, planned_minutes, created_at, updated_at
  )
  select value.id, p_user_id, p_plan_id, next_revision, value.sequence,
    'proposed', value.starts_at, value.ends_at, value.local_date,
    value.planned_minutes, p_now, p_now
  from jsonb_to_recordset(p_task_blocks) as value(
    id uuid, sequence int, starts_at timestamptz, ends_at timestamptz,
    local_date date, planned_minutes int
  );
  insert into public.planner_habit_slots (
    id, user_id, plan_id, revision, weekday, starts_at, ends_at,
    duration_minutes, state, created_at, updated_at
  )
  select value.id, p_user_id, p_plan_id, next_revision, value.weekday,
    value.starts_at, value.ends_at, value.duration_minutes,
    'proposed', p_now, p_now
  from jsonb_to_recordset(p_habit_slots) as value(
    id uuid, weekday int, starts_at time, ends_at time, duration_minutes int
  );
  insert into public.planner_request_identities (
    request_id, user_id, operation, resource_id, request_fingerprint,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'proposal', p_plan_id, p_request_fingerprint,
    next_revision, 'draft', p_now
  );
  return jsonb_build_object(
    'plan_id', p_plan_id, 'revision', next_revision, 'status', 'draft'
  );
end;
$$;

create or replace function private.planner_revision_conflicts(
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
  target_kind text;
begin
  select * into revision_row
  from public.planner_action_plan_revisions
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = p_revision;
  if not found then
    return true;
  end if;
  target_kind := revision_row.target_payload ->> 'kind';

  if target_kind = 'task' then
    return exists (
      select 1
      from public.planner_task_blocks as proposed
      join public.planner_task_blocks as active
        on active.user_id = p_user_id
       and active.plan_id <> p_plan_id
       and active.state = 'active'
       and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
           tstzrange(active.starts_at, active.ends_at, '[)')
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
    ) or exists (
      select 1
      from public.planner_task_blocks as proposed
      join public.deadline_plan_blocks as active
        on active.user_id = p_user_id
       and active.reservation_state = 'active'
       and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
           tstzrange(active.starts_at, active.ends_at, '[)')
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
    ) or exists (
      select 1
      from public.planner_task_blocks as proposed
      join public.planner_habit_slots as active
        on active.user_id = p_user_id
       and active.plan_id <> p_plan_id
       and active.state = 'active'
       and active.weekday = extract(isodow from proposed.local_date)::int
       and (proposed.starts_at at time zone revision_row.timezone)::time
           < active.ends_at
       and (proposed.ends_at at time zone revision_row.timezone)::time
           > active.starts_at
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
    ) or exists (
      select 1
      from public.planner_task_blocks as proposed
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
    ) or exists (
      select 1
      from public.planner_task_blocks as proposed
      join public.planner_commitments as fixed
        on fixed.user_id = p_user_id
       and fixed.status = 'active'
       and (
         (
           fixed.recurrence = 'one_off'
           and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
               tstzrange(fixed.starts_at, fixed.ends_at, '[)')
         )
         or (
           fixed.recurrence = 'weekly'
           and fixed.weekday = extract(isodow from proposed.local_date)::int
           and (proposed.starts_at at time zone revision_row.timezone)::time
               < fixed.local_ends_at
           and (proposed.ends_at at time zone revision_row.timezone)::time
               > fixed.local_starts_at
         )
       )
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
    ) or (
      revision_row.calendar_import_id is not null and (
        exists (
          select 1
          from public.planner_task_blocks as proposed
          join public.calendar_events as event
            on event.user_id = p_user_id
           and event.import_id = revision_row.calendar_import_id
           and event.event_status = 'confirmed'
           and event.event_kind = 'timed'
           and event.busy_status = 'busy'
           and tstzrange(proposed.starts_at, proposed.ends_at, '[)') &&
               tstzrange(event.starts_at, event.ends_at, '[)')
          where proposed.plan_id = p_plan_id
            and proposed.revision = p_revision
            and proposed.state = 'proposed'
        ) or exists (
          select 1
          from public.planner_task_blocks as proposed
          join public.calendar_events as event
            on event.user_id = p_user_id
           and event.import_id = revision_row.calendar_import_id
           and event.event_status = 'confirmed'
           and event.event_kind = 'all_day'
           and event.busy_status = 'busy'
           and proposed.local_date >= event.starts_on
           and proposed.local_date < event.ends_on
          where proposed.plan_id = p_plan_id
            and proposed.revision = p_revision
            and proposed.state = 'proposed'
        )
      )
    );
  end if;

  return exists (
    select 1
    from public.planner_habit_slots as proposed
    join public.planner_habit_slots as active
      on active.user_id = p_user_id
     and active.plan_id <> p_plan_id
     and active.state = 'active'
     and active.weekday = proposed.weekday
     and proposed.starts_at < active.ends_at
     and proposed.ends_at > active.starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
      and proposed.state = 'proposed'
  ) or exists (
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
  ) or exists (
    select 1
    from public.planner_habit_slots as proposed
    join public.planner_commitments as fixed
      on fixed.user_id = p_user_id
     and fixed.status = 'active'
     and fixed.recurrence = 'weekly'
     and fixed.weekday = proposed.weekday
     and proposed.starts_at < fixed.local_ends_at
     and proposed.ends_at > fixed.local_starts_at
    where proposed.plan_id = p_plan_id
      and proposed.revision = p_revision
      and proposed.state = 'proposed'
  ) or exists (
    with occurrences as materialized (
      select proposed.id,
        day.local_date,
        make_timestamptz(
          extract(year from day.local_date)::int,
          extract(month from day.local_date)::int,
          extract(day from day.local_date)::int,
          extract(hour from proposed.starts_at)::int,
          extract(minute from proposed.starts_at)::int,
          0,
          revision_row.timezone
        ) as starts_at,
        make_timestamptz(
          extract(year from day.local_date)::int,
          extract(month from day.local_date)::int,
          extract(day from day.local_date)::int,
          extract(hour from proposed.ends_at)::int,
          extract(minute from proposed.ends_at)::int,
          0,
          revision_row.timezone
        ) as ends_at
      from public.planner_habit_slots as proposed
      cross join lateral (
        select value::date as local_date
        from generate_series(
          revision_row.planning_start_on,
          revision_row.planning_start_on + 27,
          interval '1 day'
        ) as value
        where extract(isodow from value)::int = proposed.weekday
      ) as day
      where proposed.plan_id = p_plan_id
        and proposed.revision = p_revision
        and proposed.state = 'proposed'
    )
    select 1 from occurrences as occurrence
    where exists (
      select 1 from public.planner_task_blocks as active
      where active.user_id = p_user_id
        and active.plan_id <> p_plan_id
        and active.state = 'active'
        and tstzrange(occurrence.starts_at, occurrence.ends_at, '[)') &&
            tstzrange(active.starts_at, active.ends_at, '[)')
    ) or exists (
      select 1 from public.deadline_plan_blocks as active
      where active.user_id = p_user_id
        and active.reservation_state = 'active'
        and tstzrange(occurrence.starts_at, occurrence.ends_at, '[)') &&
            tstzrange(active.starts_at, active.ends_at, '[)')
    ) or exists (
      select 1 from public.planner_commitments as fixed
      where fixed.user_id = p_user_id
        and fixed.status = 'active'
        and fixed.recurrence = 'one_off'
        and tstzrange(occurrence.starts_at, occurrence.ends_at, '[)') &&
            tstzrange(fixed.starts_at, fixed.ends_at, '[)')
    ) or (
      revision_row.calendar_import_id is not null and (
        exists (
          select 1 from public.calendar_events as event
          where event.user_id = p_user_id
            and event.import_id = revision_row.calendar_import_id
            and event.event_status = 'confirmed'
            and event.event_kind = 'timed'
            and event.busy_status = 'busy'
            and tstzrange(occurrence.starts_at, occurrence.ends_at, '[)') &&
                tstzrange(event.starts_at, event.ends_at, '[)')
        ) or exists (
          select 1 from public.calendar_events as event
          where event.user_id = p_user_id
            and event.import_id = revision_row.calendar_import_id
            and event.event_status = 'confirmed'
            and event.event_kind = 'all_day'
            and event.busy_status = 'busy'
            and occurrence.local_date >= event.starts_on
            and occurrence.local_date < event.ends_on
        )
      )
    )
  );
end;
$$;

revoke all on function private.planner_revision_conflicts(uuid, uuid, int)
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
  existing_request public.planner_request_identities%rowtype;
  plan_row public.planner_action_plans%rowtype;
  revision_row public.planner_action_plan_revisions%rowtype;
  payload jsonb;
  target_kind text;
  target_operation text;
  preference_enabled boolean;
  result_status text;
  cadence_kind text;
  cadence_target int;
  cadence_weekdays jsonb;
  existing_habit public.habits%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request
  from public.planner_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'confirm'
       or existing_request.resource_id <> p_plan_id
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.result_revision <> p_expected_revision then
      raise exception 'request_id is already bound to another Planner operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'plan_id', p_plan_id,
      'revision', p_expected_revision,
      'status', existing_request.result_status
    );
  end if;

  select * into plan_row from public.planner_action_plans
  where id = p_plan_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Planner action plan is unavailable.' using errcode = 'P0002';
  end if;
  select * into revision_row from public.planner_action_plan_revisions
  where plan_id = p_plan_id
    and user_id = p_user_id
    and revision = p_expected_revision
    and state = 'proposed'
  for update;
  if not found
     or plan_row.status not in ('draft', 'active', 'unscheduled')
     or plan_row.latest_revision <> p_expected_revision then
    raise exception 'Planner preview changed. Reload before confirmation.'
      using errcode = 'PT409';
  end if;
  payload := revision_row.target_payload;
  target_kind := payload ->> 'kind';
  target_operation := payload ->> 'operation';

  if target_operation = 'create' then
    if (target_kind = 'task' and exists (
      select 1 from public.tasks where id = plan_row.target_id
    )) or (target_kind = 'habit' and exists (
      select 1 from public.habits where id = plan_row.target_id
    )) then
      raise exception 'The new Planner target id is no longer available.'
        using errcode = 'PT409';
    end if;
  elsif target_kind = 'task' then
    perform 1 from public.tasks
    where id = plan_row.target_id
      and user_id = p_user_id
      and updated_at = (payload ->> 'expected_updated_at')::timestamptz
      and status in ('todo', 'in_progress')
    for update;
    if not found then
      raise exception 'The Task changed. Create a new preview.'
        using errcode = 'PT409';
    end if;
  else
    select * into existing_habit from public.habits
    where id = plan_row.target_id
      and user_id = p_user_id
      and updated_at = (payload ->> 'expected_updated_at')::timestamptz
      and active = true
      and coalesce(metadata ->> 'lifecycle', 'active') = 'active'
    for update;
    if not found then
      raise exception 'The Habit changed. Create a new preview.'
        using errcode = 'PT409';
    end if;
  end if;

  select coalesce(preference.use_calendar_busy_time, false)
  into preference_enabled
  from (select p_user_id as user_id) as owner
  left join public.planner_preferences as preference
    on preference.user_id = owner.user_id;
  if preference_enabled <> (revision_row.calendar_import_id is not null) then
    raise exception 'Planner calendar preference changed. Create a new preview.'
      using errcode = 'PT409';
  end if;
  if revision_row.calendar_import_id is not null and not exists (
    select 1 from public.calendar_connections as connection
    where connection.user_id = p_user_id
      and connection.status = 'connected'
      and connection.imported_data_deleted_at is null
      and connection.last_import_id = revision_row.calendar_import_id
  ) then
    raise exception 'Calendar busy time changed. Create a new preview.'
      using errcode = 'PT409';
  end if;
  if exists (
    select 1 from public.planner_task_blocks
    where plan_id = p_plan_id
      and revision = p_expected_revision
      and state = 'proposed'
      and starts_at <= p_now
  ) or private.planner_revision_conflicts(
    p_user_id, p_plan_id, p_expected_revision
  ) then
    raise exception 'Planner preview is stale or conflicts with a reservation.'
      using errcode = 'PT409';
  end if;

  perform set_config('mylifegraph.planner_rpc', 'on', true);
  if target_kind = 'task' then
    if target_operation = 'create' then
      insert into public.tasks (
        id, user_id, title, description, status, priority, deadline,
        estimated_minutes, source, metadata, created_at, updated_at
      ) values (
        plan_row.target_id, p_user_id, payload ->> 'title',
        nullif(payload ->> 'description', ''), 'todo', payload ->> 'priority',
        nullif(payload ->> 'deadline_at', '')::timestamptz,
        nullif(payload ->> 'estimated_minutes', '')::int,
        'planner-v1',
        jsonb_build_object(
          'source', 'planner-v1',
          'contract_version', 'executable-task-v1',
          'planner_plan_id', p_plan_id,
          'preferred_session_minutes',
            nullif(payload ->> 'preferred_session_minutes', '')::int
        ),
        p_now, p_now
      );
    else
      update public.tasks
      set title = payload ->> 'title',
          description = nullif(payload ->> 'description', ''),
          priority = payload ->> 'priority',
          deadline = nullif(payload ->> 'deadline_at', '')::timestamptz,
          estimated_minutes = nullif(payload ->> 'estimated_minutes', '')::int,
          metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
            'planner_plan_id', p_plan_id,
            'preferred_session_minutes',
              nullif(payload ->> 'preferred_session_minutes', '')::int
          ),
          updated_at = p_now
      where id = plan_row.target_id and user_id = p_user_id
        and updated_at = (payload ->> 'expected_updated_at')::timestamptz
        and status in ('todo', 'in_progress');
      if not found then
        raise exception 'The Task changed. Create a new preview.'
          using errcode = 'PT409';
      end if;
    end if;
  else
    cadence_kind := payload #>> '{cadence,kind}';
    cadence_target := (payload #>> '{cadence,weekly_target}')::int;
    cadence_weekdays := payload #> '{cadence,scheduled_weekdays}';
    if target_operation = 'create' then
      insert into public.habits (
        id, user_id, title, description, frequency, target, active,
        metadata, created_at, updated_at
      ) values (
        plan_row.target_id, p_user_id, payload ->> 'title',
        nullif(payload ->> 'description', ''),
        case when cadence_kind = 'weekly_target' then 'weekly' else 'daily' end,
        case when cadence_kind = 'weekly_target' then cadence_target else 1 end,
        true,
        jsonb_strip_nulls(jsonb_build_object(
          'contract_version', 'habit-v1',
          'cadence', cadence_kind,
          'scheduled_weekdays',
            case when cadence_kind = 'weekdays' then cadence_weekdays else null end,
          'lifecycle', 'active',
          'managed_by', 'planner',
          'planner_plan_id', p_plan_id,
          'planner_duration_minutes', (payload ->> 'duration_minutes')::int
        )),
        p_now, p_now
      );
    else
      if existing_habit.metadata ->> 'managed_by' = 'setup' and (
        existing_habit.title <> payload ->> 'title'
        or existing_habit.description is distinct from nullif(payload ->> 'description', '')
        or (
          cadence_kind = 'daily'
          and not (
            existing_habit.frequency = 'daily'
            and coalesce(existing_habit.metadata ->> 'cadence', 'daily') = 'daily'
          )
        )
        or (
          cadence_kind = 'weekdays'
          and not (
            existing_habit.frequency = 'daily'
            and existing_habit.metadata ->> 'cadence' = 'weekdays'
            and existing_habit.metadata -> 'scheduled_weekdays' = cadence_weekdays
          )
        )
        or (
          cadence_kind = 'weekly_target'
          and not (
            existing_habit.frequency = 'weekly'
            and existing_habit.target = cadence_target
            and coalesce(existing_habit.metadata ->> 'cadence', 'weekly_target')
                = 'weekly_target'
          )
        )
      ) then
        raise exception 'Setup-owned Habit definitions belong in Settings.'
          using errcode = 'PT409';
      end if;
      update public.habits
      set title = case
            when metadata ->> 'managed_by' = 'setup' then title
            else payload ->> 'title'
          end,
          description = case
            when metadata ->> 'managed_by' = 'setup' then description
            else nullif(payload ->> 'description', '')
          end,
          frequency = case
            when metadata ->> 'managed_by' = 'setup' then frequency
            when cadence_kind = 'weekly_target' then 'weekly'
            else 'daily'
          end,
          target = case
            when metadata ->> 'managed_by' = 'setup' then target
            when cadence_kind = 'weekly_target' then cadence_target
            else 1
          end,
          metadata = case
            when metadata ->> 'managed_by' = 'setup' then
              metadata || jsonb_build_object(
                'planner_plan_id', p_plan_id,
                'planner_duration_minutes', (payload ->> 'duration_minutes')::int
              )
            else
              (
                metadata || jsonb_strip_nulls(jsonb_build_object(
                'contract_version', 'habit-v1',
                'cadence', cadence_kind,
                'scheduled_weekdays',
                  case when cadence_kind = 'weekdays' then cadence_weekdays else null end,
                'lifecycle', 'active',
                'planner_plan_id', p_plan_id,
                'planner_duration_minutes', (payload ->> 'duration_minutes')::int
                ))
              ) - case
                when cadence_kind = 'weekdays' then ''
                else 'scheduled_weekdays'
              end
          end,
          updated_at = p_now
      where id = plan_row.target_id and user_id = p_user_id
        and updated_at = (payload ->> 'expected_updated_at')::timestamptz
        and active = true;
      if not found then
        raise exception 'The Habit changed. Create a new preview.'
          using errcode = 'PT409';
      end if;
    end if;
  end if;

  update public.planner_action_plan_revisions
  set state = 'superseded', superseded_at = p_now
  where plan_id = p_plan_id and state = 'active';
  update public.planner_task_blocks
  set state = 'superseded', updated_at = p_now
  where plan_id = p_plan_id and state = 'active';
  update public.planner_habit_slots
  set state = 'superseded', updated_at = p_now
  where plan_id = p_plan_id and state = 'active';
  update public.planner_action_plan_revisions
  set state = 'active', activated_at = p_now
  where plan_id = p_plan_id and revision = p_expected_revision;
  update public.planner_task_blocks
  set state = 'active', updated_at = p_now
  where plan_id = p_plan_id and revision = p_expected_revision;
  update public.planner_habit_slots
  set state = 'active', updated_at = p_now
  where plan_id = p_plan_id and revision = p_expected_revision;
  result_status := case
    when revision_row.planned_minutes = 0 then 'unscheduled'
    else 'active'
  end;
  update public.planner_action_plans
  set status = result_status,
      current_revision = p_expected_revision,
      attention_reasons = case
        when revision_row.unscheduled_minutes > 0
          then array['unplaced_minutes']::text[]
        else '{}'::text[]
      end,
      updated_at = p_now
  where id = p_plan_id;
  insert into public.planner_request_identities (
    request_id, user_id, operation, resource_id, request_fingerprint,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'confirm', p_plan_id, p_request_fingerprint,
    p_expected_revision, result_status, p_now
  );
  return jsonb_build_object(
    'plan_id', p_plan_id, 'revision', p_expected_revision, 'status', result_status
  );
end;
$$;

create or replace function public.cancel_planner_action_plan_v1(
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
  existing_request public.planner_request_identities%rowtype;
  plan_row public.planner_action_plans%rowtype;
  result_status text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request
  from public.planner_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'cancel'
       or existing_request.resource_id <> p_plan_id
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.result_revision <> p_expected_revision then
      raise exception 'request_id is already bound to another Planner operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'plan_id', p_plan_id,
      'revision', p_expected_revision,
      'status', existing_request.result_status
    );
  end if;
  select * into plan_row from public.planner_action_plans
  where id = p_plan_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Planner action plan is unavailable.' using errcode = 'P0002';
  end if;
  if plan_row.status = 'cancelled'
     or plan_row.latest_revision <> p_expected_revision then
    raise exception 'Planner action plan changed. Reload before cancelling.'
      using errcode = 'PT409';
  end if;
  result_status := case
    when plan_row.current_revision = 0 then 'cancelled'
    else 'unscheduled'
  end;
  update public.planner_action_plan_revisions
  set state = 'superseded', superseded_at = p_now
  where plan_id = p_plan_id and state in ('proposed', 'active');
  update public.planner_task_blocks
  set state = case when state = 'active' then 'released' else 'superseded' end,
      updated_at = p_now
  where plan_id = p_plan_id and state in ('proposed', 'active');
  update public.planner_habit_slots
  set state = case when state = 'active' then 'released' else 'superseded' end,
      updated_at = p_now
  where plan_id = p_plan_id and state in ('proposed', 'active');
  update public.planner_action_plans
  set status = result_status,
      current_revision = 0,
      attention_reasons = case
        when result_status = 'unscheduled' then array['target_released']::text[]
        else '{}'::text[]
      end,
      updated_at = p_now
  where id = p_plan_id;
  insert into public.planner_request_identities (
    request_id, user_id, operation, resource_id, request_fingerprint,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'cancel', p_plan_id, p_request_fingerprint,
    p_expected_revision, result_status, p_now
  );
  return jsonb_build_object(
    'plan_id', p_plan_id, 'revision', p_expected_revision, 'status', result_status
  );
end;
$$;

create or replace function private.refresh_planner_commitment_attention(
  p_user_id uuid,
  p_now timestamptz
)
returns uuid[]
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  profile_timezone text;
  affected uuid[];
begin
  select timezone into profile_timezone
  from public.profiles where id = p_user_id;
  if not found then
    raise exception 'Planner profile is unavailable.' using errcode = 'P0002';
  end if;
  update public.planner_action_plans
  set attention_reasons = array_remove(attention_reasons, 'commitment_conflict'),
      updated_at = greatest(updated_at, p_now)
  where user_id = p_user_id
    and 'commitment_conflict' = any(attention_reasons);

  with conflicted as materialized (
    select distinct plan.id
    from public.planner_action_plans as plan
    join public.planner_task_blocks as block
      on block.user_id = plan.user_id
     and block.plan_id = plan.id
     and block.state = 'active'
    join public.planner_commitments as fixed
      on fixed.user_id = plan.user_id
     and fixed.status = 'active'
     and (
       (
         fixed.recurrence = 'one_off'
         and tstzrange(block.starts_at, block.ends_at, '[)') &&
             tstzrange(fixed.starts_at, fixed.ends_at, '[)')
       )
       or (
         fixed.recurrence = 'weekly'
         and fixed.weekday = extract(isodow from block.local_date)::int
         and (block.starts_at at time zone profile_timezone)::time
             < fixed.local_ends_at
         and (block.ends_at at time zone profile_timezone)::time
             > fixed.local_starts_at
       )
     )
    where plan.user_id = p_user_id and plan.status in ('active', 'unscheduled')
    union
    select distinct plan.id
    from public.planner_action_plans as plan
    join public.planner_habit_slots as slot
      on slot.user_id = plan.user_id
     and slot.plan_id = plan.id
     and slot.state = 'active'
    join public.planner_commitments as fixed
      on fixed.user_id = plan.user_id
     and fixed.status = 'active'
     and (
       (
         fixed.recurrence = 'weekly'
         and fixed.weekday = slot.weekday
         and slot.starts_at < fixed.local_ends_at
         and slot.ends_at > fixed.local_starts_at
       )
       or (
         fixed.recurrence = 'one_off'
         and extract(isodow from fixed.starts_at at time zone profile_timezone)::int
             = slot.weekday
         and (fixed.starts_at at time zone profile_timezone)::time < slot.ends_at
         and (fixed.ends_at at time zone profile_timezone)::time > slot.starts_at
       )
     )
    where plan.user_id = p_user_id and plan.status in ('active', 'unscheduled')
  ), updated as (
    update public.planner_action_plans as plan
    set attention_reasons = array_append(
          plan.attention_reasons,
          'commitment_conflict'
        ),
        updated_at = greatest(plan.updated_at, p_now)
    from conflicted
    where plan.id = conflicted.id
      and not ('commitment_conflict' = any(plan.attention_reasons))
    returning plan.id
  )
  select coalesce(array_agg(id order by id), '{}'::uuid[])
  into affected from conflicted;
  return affected;
end;
$$;

revoke all on function private.refresh_planner_commitment_attention(uuid, timestamptz)
from public, anon, authenticated, service_role;

create or replace function public.mutate_planner_commitment_v1(
  p_user_id uuid,
  p_commitment_id uuid,
  p_request_id uuid,
  p_operation text,
  p_request_fingerprint text,
  p_expected_updated_at timestamptz,
  p_payload jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.planner_request_identities%rowtype;
  commitment_row public.planner_commitments%rowtype;
  affected uuid[];
begin
  if p_operation not in ('create', 'update', 'archive')
     or p_request_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Planner commitment operation is invalid.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  select * into existing_request from public.planner_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'commitment_' || p_operation
       or existing_request.resource_id <> p_commitment_id
       or existing_request.request_fingerprint <> p_request_fingerprint then
      raise exception 'request_id is already bound to another Planner operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'commitment_id', p_commitment_id,
      'status', existing_request.result_status,
      'affected_plan_ids', '[]'::jsonb
    );
  end if;
  if p_operation in ('create', 'update') and (
    jsonb_typeof(p_payload) <> 'object'
    or p_payload - array[
      'title', 'location', 'recurrence', 'starts_at', 'ends_at',
      'weekday', 'local_starts_at', 'local_ends_at'
    ] <> '{}'::jsonb
    or not (p_payload ?& array[
      'title', 'location', 'recurrence', 'starts_at', 'ends_at',
      'weekday', 'local_starts_at', 'local_ends_at'
    ])
    or length(p_payload ->> 'title') not between 1 and 160
    or p_payload ->> 'title' <> trim(p_payload ->> 'title')
  ) then
    raise exception 'Planner commitment payload is invalid.' using errcode = '22023';
  end if;
  if p_operation = 'archive' and p_payload is not null then
    raise exception 'Archive does not accept a commitment payload.'
      using errcode = '22023';
  end if;
  select * into commitment_row from public.planner_commitments
  where id = p_commitment_id and user_id = p_user_id for update;
  if p_operation = 'create' then
    if found or p_expected_updated_at is not null then
      raise exception 'Planner commitment identity is already in use.'
        using errcode = 'PT409';
    end if;
    if (
      select count(*) from public.planner_commitments
      where user_id = p_user_id and status = 'active'
    ) >= 1000 then
      raise exception 'Planner commitment count exceeds its bound.'
        using errcode = 'PT409';
    end if;
    insert into public.planner_commitments (
      id, user_id, title, location, recurrence, status,
      starts_at, ends_at, weekday, local_starts_at, local_ends_at,
      created_at, updated_at
    ) values (
      p_commitment_id, p_user_id, p_payload ->> 'title',
      nullif(p_payload ->> 'location', ''), p_payload ->> 'recurrence', 'active',
      nullif(p_payload ->> 'starts_at', '')::timestamptz,
      nullif(p_payload ->> 'ends_at', '')::timestamptz,
      nullif(p_payload ->> 'weekday', '')::int,
      nullif(p_payload ->> 'local_starts_at', '')::time,
      nullif(p_payload ->> 'local_ends_at', '')::time,
      p_now, p_now
    );
  else
    if not found then
      raise exception 'Planner commitment is unavailable.' using errcode = 'P0002';
    end if;
    if commitment_row.updated_at <> p_expected_updated_at
       or commitment_row.status <> 'active' then
      raise exception 'Planner commitment changed. Reload before saving.'
        using errcode = 'PT409';
    end if;
    if p_operation = 'update' then
      update public.planner_commitments
      set title = p_payload ->> 'title',
          location = nullif(p_payload ->> 'location', ''),
          recurrence = p_payload ->> 'recurrence',
          starts_at = nullif(p_payload ->> 'starts_at', '')::timestamptz,
          ends_at = nullif(p_payload ->> 'ends_at', '')::timestamptz,
          weekday = nullif(p_payload ->> 'weekday', '')::int,
          local_starts_at = nullif(p_payload ->> 'local_starts_at', '')::time,
          local_ends_at = nullif(p_payload ->> 'local_ends_at', '')::time,
          updated_at = p_now
      where id = p_commitment_id;
    else
      update public.planner_commitments
      set status = 'archived', archived_at = p_now, updated_at = p_now
      where id = p_commitment_id;
    end if;
  end if;
  affected := private.refresh_planner_commitment_attention(p_user_id, p_now);
  insert into public.planner_request_identities (
    request_id, user_id, operation, resource_id, request_fingerprint,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'commitment_' || p_operation,
    p_commitment_id, p_request_fingerprint, null,
    case when p_operation = 'archive' then 'archived' else 'active' end,
    p_now
  );
  return jsonb_build_object(
    'commitment_id', p_commitment_id,
    'status', case when p_operation = 'archive' then 'archived' else 'active' end,
    'affected_plan_ids', to_jsonb(affected[1:100])
  );
end;
$$;

create or replace function private.release_planner_target_reservations()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_target_user_id uuid;
  v_target_id uuid;
  v_target_kind text;
  terminal boolean;
  changed boolean;
  mutation_at timestamptz;
begin
  if coalesce(current_setting('mylifegraph.planner_rpc', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  v_target_user_id := case
    when tg_op = 'DELETE' then old.user_id else new.user_id
  end;
  v_target_id := case when tg_op = 'DELETE' then old.id else new.id end;
  v_target_kind := case when tg_table_name = 'tasks' then 'task' else 'habit' end;
  mutation_at := case
    when tg_op = 'DELETE' then clock_timestamp()
    else new.updated_at
  end;
  if v_target_kind = 'task' then
    terminal := tg_op = 'DELETE' or new.status in ('done', 'cancelled', 'archived');
    changed := tg_op = 'DELETE' or new.updated_at is distinct from old.updated_at;
  else
    terminal := tg_op = 'DELETE'
      or new.active is not true
      or coalesce(new.metadata ->> 'lifecycle', 'active') <> 'active';
    changed := tg_op = 'DELETE' or new.updated_at is distinct from old.updated_at;
  end if;
  if terminal then
    update public.planner_task_blocks as block
    set state = case when block.ends_at > mutation_at then 'released' else 'superseded' end,
        updated_at = mutation_at
    from public.planner_action_plans as plan
    where plan.user_id = v_target_user_id
      and plan.target_kind = v_target_kind
      and plan.target_id = v_target_id
      and block.plan_id = plan.id
      and block.state = 'active';
    update public.planner_habit_slots as slot
    set state = 'released', updated_at = mutation_at
    from public.planner_action_plans as plan
    where plan.user_id = v_target_user_id
      and plan.target_kind = v_target_kind
      and plan.target_id = v_target_id
      and slot.plan_id = plan.id
      and slot.state = 'active';
    update public.planner_action_plan_revisions as revision
    set state = 'superseded', superseded_at = mutation_at
    from public.planner_action_plans as plan
    where plan.user_id = v_target_user_id
      and plan.target_kind = v_target_kind
      and plan.target_id = v_target_id
      and revision.plan_id = plan.id
      and revision.state in ('active', 'proposed');
    update public.planner_action_plans
    set status = 'unscheduled', current_revision = 0,
        attention_reasons = array['target_released']::text[],
        updated_at = mutation_at
    where user_id = v_target_user_id
      and planner_action_plans.target_kind = v_target_kind
      and planner_action_plans.target_id = v_target_id
      and status <> 'cancelled';
  elsif changed then
    update public.planner_action_plans
    set attention_reasons = case
          when 'target_changed' = any(attention_reasons) then attention_reasons
          else array_append(attention_reasons, 'target_changed')
        end,
        updated_at = mutation_at
    where user_id = v_target_user_id
      and planner_action_plans.target_kind = v_target_kind
      and planner_action_plans.target_id = v_target_id
      and status = 'active';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.release_planner_target_reservations()
from public, anon, authenticated, service_role;

create trigger tasks_release_planner_reservations
after update or delete on public.tasks
for each row execute function private.release_planner_target_reservations();
create trigger habits_release_planner_reservations
after update or delete on public.habits
for each row execute function private.release_planner_target_reservations();

create or replace function private.guard_deadline_against_planner_reservations()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  profile_timezone text;
begin
  if new.reservation_state <> 'active'
     or (tg_op = 'UPDATE' and old.reservation_state = 'active') then
    return new;
  end if;
  select timezone into profile_timezone
  from public.profiles where id = new.user_id;
  if exists (
    select 1 from public.planner_task_blocks as block
    where block.user_id = new.user_id
      and block.state = 'active'
      and tstzrange(new.starts_at, new.ends_at, '[)') &&
          tstzrange(block.starts_at, block.ends_at, '[)')
  ) or exists (
    select 1 from public.planner_habit_slots as slot
    where slot.user_id = new.user_id
      and slot.state = 'active'
      and slot.weekday = extract(isodow from new.local_date)::int
      and new.local_start_time < slot.ends_at
      and new.local_end_time > slot.starts_at
  ) or exists (
    select 1 from public.planner_commitments as fixed
    where fixed.user_id = new.user_id
      and fixed.status = 'active'
      and (
        (
          fixed.recurrence = 'one_off'
          and tstzrange(new.starts_at, new.ends_at, '[)') &&
              tstzrange(fixed.starts_at, fixed.ends_at, '[)')
        )
        or (
          fixed.recurrence = 'weekly'
          and fixed.weekday = extract(isodow from new.local_date)::int
          and new.local_start_time < fixed.local_ends_at
          and new.local_end_time > fixed.local_starts_at
        )
      )
  ) then
    raise exception 'Preparation block conflicts with a Planner reservation.'
      using errcode = 'PT409';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_deadline_against_planner_reservations()
from public, anon, authenticated, service_role;

create trigger deadline_blocks_guard_planner_reservations
before insert or update of reservation_state on public.deadline_plan_blocks
for each row execute function private.guard_deadline_against_planner_reservations();

revoke all on function public.set_planner_preferences_v1(
  uuid, uuid, timestamptz, boolean, timestamptz
) from public, anon, authenticated;
revoke all on function public.propose_planner_action_plan_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) from public, anon, authenticated;
revoke all on function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) from public, anon, authenticated;
revoke all on function public.cancel_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) from public, anon, authenticated;
revoke all on function public.mutate_planner_commitment_v1(
  uuid, uuid, uuid, text, text, timestamptz, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.set_planner_preferences_v1(
  uuid, uuid, timestamptz, boolean, timestamptz
) to service_role;
grant execute on function public.propose_planner_action_plan_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) to service_role;
grant execute on function public.confirm_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) to service_role;
grant execute on function public.cancel_planner_action_plan_v1(
  uuid, uuid, uuid, int, text, timestamptz
) to service_role;
grant execute on function public.mutate_planner_commitment_v1(
  uuid, uuid, uuid, text, text, timestamptz, jsonb, timestamptz
) to service_role;
