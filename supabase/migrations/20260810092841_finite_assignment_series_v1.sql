-- Finite weekly Assignment Series with one atomic preview/confirmation boundary.

create table public.assignment_series (
  id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  contract_version text not null default 'assignment-series-v1',
  origin text not null default 'authenticated_backend',
  status text not null default 'draft',
  title text not null,
  current_revision int not null default 0,
  latest_revision int not null default 1,
  first_activated_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (id, user_id),
  constraint assignment_series_contract_check check (
    contract_version = 'assignment-series-v1'
    and origin = 'authenticated_backend'
  ),
  constraint assignment_series_shape_check check (
    length(title) between 1 and 160
    and title = trim(title)
    and current_revision between 0 and 200
    and latest_revision between greatest(current_revision, 1) and 200
    and updated_at >= created_at
  ),
  constraint assignment_series_lifecycle_check check (
    (
      status = 'draft'
      and current_revision = 0
      and first_activated_at is null
      and cancelled_at is null
    )
    or (
      status = 'active'
      and current_revision > 0
      and first_activated_at is not null
      and cancelled_at is null
    )
    or (
      status = 'cancelled'
      and cancelled_at is not null
      and (
        (current_revision = 0 and first_activated_at is null)
        or (current_revision > 0 and first_activated_at is not null)
      )
    )
  )
);

create index assignment_series_user_updated_idx
  on public.assignment_series (user_id, updated_at desc, id);

create table public.assignment_series_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  series_id uuid not null,
  revision int not null,
  base_revision int not null,
  state text not null default 'proposed',
  title text not null,
  next_deadline_at timestamptz not null,
  remaining_occurrences int not null,
  estimated_total_minutes int not null,
  preferred_session_minutes int not null,
  max_daily_minutes int not null,
  buffer_days int not null,
  use_calendar_availability boolean not null,
  timezone text not null,
  planned_minutes int not null,
  unscheduled_minutes int not null,
  created_at timestamptz not null,
  activated_at timestamptz,
  superseded_at timestamptz,
  unique (series_id, revision),
  unique (series_id, user_id, revision),
  foreign key (series_id, user_id)
    references public.assignment_series (id, user_id) on delete cascade,
  constraint assignment_series_revisions_sequence_check check (
    revision = base_revision + 1 and revision between 1 and 200
  ),
  constraint assignment_series_revisions_input_check check (
    length(title) between 1 and 160
    and title = trim(title)
    and remaining_occurrences between 1 and 20
    and estimated_total_minutes between 30 and 30000
    and preferred_session_minutes between 25 and 180
    and max_daily_minutes between preferred_session_minutes and 480
    and buffer_days between 0 and 7
    and length(timezone) between 1 and 100
    and planned_minutes between 0 and 600000
    and unscheduled_minutes between 0 and 600000
  ),
  constraint assignment_series_revisions_lifecycle_check check (
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
    or (state = 'superseded' and superseded_at is not null)
  )
);

create unique index assignment_series_revisions_one_proposed_idx
  on public.assignment_series_revisions (series_id)
  where state = 'proposed';

create unique index assignment_series_revisions_one_active_idx
  on public.assignment_series_revisions (series_id)
  where state = 'active';

create index assignment_series_revisions_user_series_idx
  on public.assignment_series_revisions (user_id, series_id, revision);

create table public.assignment_series_revision_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  series_id uuid not null,
  series_revision int not null,
  position int not null,
  action text not null,
  plan_id uuid not null,
  plan_revision int not null,
  deadline_at timestamptz not null,
  proposal_request_id uuid,
  proposal_request_fingerprint text,
  mutation_request_id uuid,
  mutation_request_fingerprint text,
  created_at timestamptz not null,
  unique (series_id, series_revision, position),
  unique (series_id, series_revision, plan_id),
  foreign key (series_id, user_id, series_revision)
    references public.assignment_series_revisions (
      series_id, user_id, revision
    ) on delete cascade,
  foreign key (plan_id, user_id)
    references public.deadline_plans (id, user_id) on delete cascade,
  constraint assignment_series_items_shape_check check (
    position between 1 and 200
    and plan_revision between 1 and 200
    and action in ('retain', 'upsert', 'cancel')
    and (
      (
        action = 'retain'
        and proposal_request_id is null
        and proposal_request_fingerprint is null
        and mutation_request_id is null
        and mutation_request_fingerprint is null
      )
      or (
        action = 'upsert'
        and proposal_request_id is not null
        and proposal_request_fingerprint ~ '^[0-9a-f]{64}$'
        and mutation_request_id is not null
        and mutation_request_fingerprint ~ '^[0-9a-f]{64}$'
      )
      or (
        action = 'cancel'
        and proposal_request_id is null
        and proposal_request_fingerprint is null
        and mutation_request_id is not null
        and mutation_request_fingerprint ~ '^[0-9a-f]{64}$'
      )
    )
  )
);

create index assignment_series_items_user_series_idx
  on public.assignment_series_revision_items (
    user_id, series_id, series_revision, position
  );

create index assignment_series_items_plan_idx
  on public.assignment_series_revision_items (plan_id, series_id);

create table public.assignment_series_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  operation text not null,
  request_fingerprint text not null,
  series_id uuid not null,
  result_revision int not null,
  result_status text not null,
  created_at timestamptz not null,
  foreign key (series_id, user_id)
    references public.assignment_series (id, user_id) on delete cascade,
  constraint assignment_series_requests_shape_check check (
    operation in ('proposal', 'confirm', 'cancel_future')
    and request_fingerprint ~ '^[0-9a-f]{64}$'
    and result_revision between 1 and 200
    and (
      (operation = 'proposal' and result_status in ('draft', 'active'))
      or (operation = 'confirm' and result_status = 'active')
      or (operation = 'cancel_future' and result_status = 'cancelled')
    )
  )
);

create index assignment_series_requests_user_idx
  on public.assignment_series_request_identities (user_id, created_at, request_id);

alter table public.assignment_series enable row level security;
alter table public.assignment_series force row level security;
alter table public.assignment_series_revisions enable row level security;
alter table public.assignment_series_revisions force row level security;
alter table public.assignment_series_revision_items enable row level security;
alter table public.assignment_series_revision_items force row level security;
alter table public.assignment_series_request_identities enable row level security;
alter table public.assignment_series_request_identities force row level security;

revoke all on table public.assignment_series,
  public.assignment_series_revisions,
  public.assignment_series_revision_items,
  public.assignment_series_request_identities
from public, anon, authenticated, service_role;

grant select on table public.assignment_series,
  public.assignment_series_revisions,
  public.assignment_series_revision_items
to authenticated;

grant select on table public.assignment_series,
  public.assignment_series_revisions,
  public.assignment_series_revision_items,
  public.assignment_series_request_identities
to service_role;

create policy assignment_series_owner_select
  on public.assignment_series for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy assignment_series_service_all
  on public.assignment_series for all to service_role
  using (true) with check (true);
create policy assignment_series_revisions_owner_select
  on public.assignment_series_revisions for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy assignment_series_revisions_service_all
  on public.assignment_series_revisions for all to service_role
  using (true) with check (true);
create policy assignment_series_items_owner_select
  on public.assignment_series_revision_items for select to authenticated
  using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');
create policy assignment_series_items_service_all
  on public.assignment_series_revision_items for all to service_role
  using (true) with check (true);
create policy assignment_series_requests_service_all
  on public.assignment_series_request_identities for all to service_role
  using (true) with check (true);

create or replace function public.propose_assignment_series_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_series_id uuid,
  p_base_revision int,
  p_series jsonb,
  p_items jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.assignment_series_request_identities%rowtype;
  series_row public.assignment_series%rowtype;
  next_revision int;
  result_status text;
  effective_now timestamptz;
  item jsonb;
  result jsonb;
  hidden_block_ids uuid[] := '{}'::uuid[];
  upsert_count int;
  planned_total bigint;
  unscheduled_total bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));

  select * into existing_request
  from public.assignment_series_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'proposal'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.series_id <> p_series_id
       or existing_request.result_revision <> p_base_revision + 1 then
      raise exception 'request_id is already bound to another assignment series operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'series_id', p_series_id,
      'revision', existing_request.result_revision,
      'status', existing_request.result_status
    );
  end if;

  if p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_series) <> 'object'
     or not (p_series ?& array[
       'title', 'next_deadline_at', 'remaining_occurrences',
       'estimated_total_minutes', 'preferred_session_minutes',
       'max_daily_minutes', 'buffer_days', 'use_calendar_availability',
       'timezone', 'planned_minutes', 'unscheduled_minutes'
     ])
     or p_series - array[
       'title', 'next_deadline_at', 'remaining_occurrences',
       'estimated_total_minutes', 'preferred_session_minutes',
       'max_daily_minutes', 'buffer_days', 'use_calendar_availability',
       'timezone', 'planned_minutes', 'unscheduled_minutes'
     ] <> '{}'::jsonb
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 40 then
    raise exception 'Assignment series proposal payload is invalid.'
      using errcode = '22023';
  end if;

  select * into series_row
  from public.assignment_series
  where id = p_series_id and user_id = p_user_id
  for update;
  if not found then
    if p_base_revision <> 0 then
      raise exception 'Assignment series base revision is stale.'
        using errcode = 'PT409';
    end if;
    if (p_series ->> 'remaining_occurrences')::int < 2 then
      raise exception 'A new assignment series needs at least two occurrences.'
        using errcode = '22023';
    end if;
    if (
      select count(*) from public.assignment_series
      where user_id = p_user_id and status in ('draft', 'active')
    ) >= 20 then
      raise exception 'You already have 20 open assignment series.'
        using errcode = 'PT409';
    end if;
    next_revision := 1;
    result_status := 'draft';
    effective_now := p_now;
  else
    if series_row.status not in ('draft', 'active')
       or series_row.latest_revision <> p_base_revision then
      raise exception 'Assignment series changed. Reload before editing it.'
        using errcode = 'PT409';
    end if;
    if series_row.latest_revision >= 200 then
      raise exception 'Assignment series revision history exceeds its V1 bound.'
        using errcode = 'PT409';
    end if;
    next_revision := series_row.latest_revision + 1;
    result_status := series_row.status;
    effective_now := greatest(p_now, series_row.updated_at);
  end if;

  if length(p_series ->> 'title') not between 1 and 160
     or p_series ->> 'title' <> trim(p_series ->> 'title')
     or (p_series ->> 'next_deadline_at')::timestamptz <= effective_now
     or (p_series ->> 'remaining_occurrences')::int not between 1 and 20
     or (p_series ->> 'estimated_total_minutes')::int not between 30 and 30000
     or (p_series ->> 'preferred_session_minutes')::int not between 25 and 180
     or (p_series ->> 'max_daily_minutes')::int not between
          (p_series ->> 'preferred_session_minutes')::int and 480
     or (p_series ->> 'buffer_days')::int not between 0 and 7
     or length(p_series ->> 'timezone') not between 1 and 100
     or (p_series ->> 'planned_minutes')::int not between 0 and 600000
     or (p_series ->> 'unscheduled_minutes')::int not between 0 and 600000 then
    raise exception 'Assignment series values are invalid.' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as entries(value)
    where jsonb_typeof(value) <> 'object'
       or not (value ?& array[
         'position', 'action', 'plan_id', 'plan_revision', 'deadline_at'
       ])
       or value ->> 'action' not in ('retain', 'upsert', 'cancel')
       or (value ->> 'position')::int not between 1 and 200
       or (value ->> 'plan_revision')::int not between 1 and 200
       or (
         value ->> 'action' = 'retain'
         and (
           not (value ?& array[
             'position', 'action', 'plan_id', 'plan_revision', 'deadline_at'
           ])
           or value - array[
             'position', 'action', 'plan_id', 'plan_revision', 'deadline_at'
           ] <> '{}'::jsonb
         )
       )
       or (
         value ->> 'action' = 'upsert'
         and (
           not (value ?& array[
             'position', 'action', 'plan_id', 'plan_revision', 'deadline_at',
             'proposal_request_id', 'proposal_request_fingerprint',
             'proposal', 'blocks', 'mutation_request_id',
             'mutation_request_fingerprint'
           ])
           or value - array[
             'position', 'action', 'plan_id', 'plan_revision', 'deadline_at',
             'proposal_request_id', 'proposal_request_fingerprint',
             'proposal', 'blocks', 'mutation_request_id',
             'mutation_request_fingerprint'
           ] <> '{}'::jsonb
           or value ->> 'proposal_request_fingerprint' !~ '^[0-9a-f]{64}$'
           or value ->> 'mutation_request_fingerprint' !~ '^[0-9a-f]{64}$'
           or jsonb_typeof(value -> 'proposal') <> 'object'
           or jsonb_typeof(value -> 'blocks') <> 'array'
         )
       )
       or (
         value ->> 'action' = 'cancel'
         and (
           not (value ?& array[
             'position', 'action', 'plan_id', 'plan_revision', 'deadline_at',
             'mutation_request_id', 'mutation_request_fingerprint'
           ])
           or value - array[
             'position', 'action', 'plan_id', 'plan_revision', 'deadline_at',
             'mutation_request_id', 'mutation_request_fingerprint'
           ] <> '{}'::jsonb
           or value ->> 'mutation_request_fingerprint' !~ '^[0-9a-f]{64}$'
         )
       )
  ) then
    raise exception 'Assignment series occurrence payload is invalid.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as entries(value)
    group by (value ->> 'position')::int
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(p_items) as entries(value)
    group by (value ->> 'plan_id')::uuid
    having count(*) > 1
  ) then
    raise exception 'Assignment series occurrences must be unique.'
      using errcode = '22023';
  end if;

  select count(*) into upsert_count
  from jsonb_array_elements(p_items) as entries(value)
  where value ->> 'action' = 'upsert';
  if upsert_count <> (p_series ->> 'remaining_occurrences')::int
     or (p_base_revision = 0 and exists (
       select 1 from jsonb_array_elements(p_items) as entries(value)
       where value ->> 'action' <> 'upsert'
     )) then
    raise exception 'Assignment series occurrence count is invalid.'
      using errcode = '22023';
  end if;

  if p_base_revision > 0 and (
    exists (
      select 1
      from jsonb_array_elements(p_items) as entries(value)
      where value ->> 'action' in ('retain', 'cancel')
        and not exists (
          select 1
          from public.assignment_series_revision_items as previous
          where previous.user_id = p_user_id
            and previous.series_id = p_series_id
            and previous.series_revision = p_base_revision
            and previous.plan_id = (value ->> 'plan_id')::uuid
            and previous.position = (value ->> 'position')::int
        )
    )
    or exists (
      select 1
      from jsonb_array_elements(p_items) as entries(value)
      join public.deadline_plans as plan
        on plan.id = (value ->> 'plan_id')::uuid
       and plan.user_id = p_user_id
      where value ->> 'action' = 'upsert'
        and not exists (
          select 1
          from public.assignment_series_revision_items as previous
          where previous.user_id = p_user_id
            and previous.series_id = p_series_id
            and previous.series_revision = p_base_revision
            and previous.plan_id = plan.id
            and previous.position = (value ->> 'position')::int
        )
    )
    or exists (
      select 1
      from public.assignment_series_revision_items as previous
      join public.deadline_plans as plan
        on plan.id = previous.plan_id and plan.user_id = previous.user_id
      where previous.user_id = p_user_id
        and previous.series_id = p_series_id
        and previous.series_revision = p_base_revision
        and previous.action <> 'cancel'
        and (
          plan.status in ('completed', 'cancelled')
          or (
            plan.status = 'active'
            and previous.deadline_at <= effective_now
          )
        )
        and not exists (
          select 1 from jsonb_array_elements(p_items) as entries(value)
          where (value ->> 'plan_id')::uuid = previous.plan_id
            and value ->> 'action' = 'retain'
        )
    )
  ) then
    raise exception 'Past or completed assignment occurrences must be preserved.'
      using errcode = 'PT409';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as entries(value)
    left join public.deadline_plans as plan
      on plan.id = (value ->> 'plan_id')::uuid
     and plan.user_id = p_user_id
    where (
      value ->> 'action' = 'retain'
      and (
        plan.id is null
        or not (
          plan.status in ('completed', 'cancelled')
          or (plan.status = 'active' and (value ->> 'deadline_at')::timestamptz <= effective_now)
        )
      )
    ) or (
      value ->> 'action' = 'cancel'
      and (
        plan.id is null
        or plan.status not in ('draft', 'active')
        or (value ->> 'deadline_at')::timestamptz <= effective_now
      )
    ) or (
      value ->> 'action' = 'upsert'
      and plan.id is not null
      and (
        plan.status not in ('draft', 'active')
        or (value ->> 'deadline_at')::timestamptz <= effective_now
      )
    )
  ) then
    raise exception 'Assignment occurrence lifecycle changed. Reload the series.'
      using errcode = 'PT409';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as entries(value)
    where value ->> 'action' = 'upsert'
      and (
        (value -> 'proposal' ->> 'plan_id')::uuid <>
          (value ->> 'plan_id')::uuid
        or (value -> 'proposal' ->> 'base_revision')::int + 1 <>
          (value ->> 'plan_revision')::int
        or value -> 'proposal' ->> 'kind' <> 'assignment'
        or value -> 'proposal' ->> 'title' <> p_series ->> 'title'
        or (value -> 'proposal' ->> 'deadline_at')::timestamptz <>
          (value ->> 'deadline_at')::timestamptz
        or (value -> 'proposal' ->> 'estimated_total_minutes')::int <>
          (p_series ->> 'estimated_total_minutes')::int
        or (value -> 'proposal' ->> 'credited_prior_minutes')::int <> 0
        or (value -> 'proposal' ->> 'preferred_session_minutes')::int <>
          (p_series ->> 'preferred_session_minutes')::int
        or (value -> 'proposal' ->> 'max_daily_minutes')::int <>
          (p_series ->> 'max_daily_minutes')::int
        or (value -> 'proposal' ->> 'buffer_days')::int <>
          (p_series ->> 'buffer_days')::int
        or value -> 'proposal' ->> 'source_kind' <> 'manual'
        or (value -> 'proposal' ->> 'use_calendar_availability')::boolean <>
          (p_series ->> 'use_calendar_availability')::boolean
        or value -> 'proposal' ->> 'timezone' <> p_series ->> 'timezone'
      )
  ) then
    raise exception 'Assignment occurrence does not match the shared template.'
      using errcode = '22023';
  end if;

  if exists (
    with ordered as (
      select
        (value ->> 'deadline_at')::timestamptz as deadline_at,
        row_number() over (
          order by (value ->> 'deadline_at')::timestamptz,
            (value ->> 'position')::int
        ) as sequence
      from jsonb_array_elements(p_items) as entries(value)
      where value ->> 'action' = 'upsert'
    )
    select 1 from ordered
    where deadline_at at time zone (p_series ->> 'timezone') <>
      (
        (p_series ->> 'next_deadline_at')::timestamptz
          at time zone (p_series ->> 'timezone')
      ) + ((sequence - 1) * interval '7 days')
  ) then
    raise exception 'Assignment occurrences must use an exact weekly local cadence.'
      using errcode = '22023';
  end if;

  if exists (
    with proposed_blocks as (
      select
        (entry.value ->> 'plan_id')::uuid as plan_id,
        (block.value ->> 'starts_at')::timestamptz as starts_at,
        (block.value ->> 'reserved_ends_at')::timestamptz as reserved_ends_at
      from jsonb_array_elements(p_items) as entry(value)
      cross join lateral jsonb_array_elements(entry.value -> 'blocks') as block(value)
      where entry.value ->> 'action' = 'upsert'
    )
    select 1
    from proposed_blocks as left_block
    join proposed_blocks as right_block
      on left_block.plan_id < right_block.plan_id
     and tstzrange(left_block.starts_at, left_block.reserved_ends_at, '[)') &&
         tstzrange(right_block.starts_at, right_block.reserved_ends_at, '[)')
  ) then
    raise exception 'Assignment occurrence previews conflict with one another.'
      using errcode = 'PT409';
  end if;

  select
    coalesce(sum((value -> 'proposal' ->> 'planned_minutes')::int), 0),
    coalesce(sum((value -> 'proposal' ->> 'unscheduled_minutes')::int), 0)
  into planned_total, unscheduled_total
  from jsonb_array_elements(p_items) as entries(value)
  where value ->> 'action' = 'upsert';
  if planned_total <> (p_series ->> 'planned_minutes')::bigint
     or unscheduled_total <> (p_series ->> 'unscheduled_minutes')::bigint then
    raise exception 'Assignment series minute totals are invalid.'
      using errcode = '22023';
  end if;

  perform 1
  from public.deadline_plans as plan
  join jsonb_array_elements(p_items) as entries(value)
    on plan.id = (value ->> 'plan_id')::uuid
  where plan.user_id = p_user_id
    and value ->> 'action' in ('upsert', 'cancel')
  order by plan.id
  for update of plan;

  select coalesce(array_agg(block.id order by block.id), '{}'::uuid[])
  into hidden_block_ids
  from public.deadline_plan_blocks as block
  where block.user_id = p_user_id
    and block.reservation_state = 'active'
    and block.plan_id in (
      select (value ->> 'plan_id')::uuid
      from jsonb_array_elements(p_items) as entries(value)
      where value ->> 'action' in ('upsert', 'cancel')
    );
  update public.deadline_plan_blocks
  set reservation_state = 'superseded'
  where id = any(hidden_block_ids);

  for item in
    select value
    from jsonb_array_elements(p_items) as entries(value)
    where value ->> 'action' = 'upsert'
    order by value ->> 'plan_id'
  loop
    result := public.propose_deadline_plan_with_timing_v1(
      p_user_id,
      (item ->> 'proposal_request_id')::uuid,
      item ->> 'proposal_request_fingerprint',
      (item ->> 'plan_id')::uuid,
      (item -> 'proposal' ->> 'base_revision')::int,
      item -> 'proposal',
      item -> 'blocks',
      effective_now
    );
    if (result ->> 'revision')::int <> (item ->> 'plan_revision')::int then
      raise exception 'Assignment occurrence revision changed during proposal.'
        using errcode = 'PT409';
    end if;
  end loop;

  update public.deadline_plan_blocks
  set reservation_state = 'active'
  where id = any(hidden_block_ids);

  if series_row.id is null then
    insert into public.assignment_series (
      id, user_id, title, current_revision, latest_revision,
      created_at, updated_at
    ) values (
      p_series_id, p_user_id, p_series ->> 'title', 0, 1,
      effective_now, effective_now
    );
  else
    update public.assignment_series_revisions
    set state = 'superseded', superseded_at = effective_now
    where user_id = p_user_id
      and series_id = p_series_id
      and state = 'proposed';
    update public.assignment_series
    set latest_revision = next_revision,
        title = case
          when current_revision = 0 then p_series ->> 'title'
          else title
        end,
        updated_at = effective_now
    where id = p_series_id and user_id = p_user_id;
  end if;

  insert into public.assignment_series_revisions (
    user_id, series_id, revision, base_revision, state, title,
    next_deadline_at, remaining_occurrences, estimated_total_minutes,
    preferred_session_minutes, max_daily_minutes, buffer_days,
    use_calendar_availability, timezone, planned_minutes,
    unscheduled_minutes, created_at
  ) values (
    p_user_id, p_series_id, next_revision, p_base_revision, 'proposed',
    p_series ->> 'title',
    (p_series ->> 'next_deadline_at')::timestamptz,
    (p_series ->> 'remaining_occurrences')::int,
    (p_series ->> 'estimated_total_minutes')::int,
    (p_series ->> 'preferred_session_minutes')::int,
    (p_series ->> 'max_daily_minutes')::int,
    (p_series ->> 'buffer_days')::int,
    (p_series ->> 'use_calendar_availability')::boolean,
    p_series ->> 'timezone',
    (p_series ->> 'planned_minutes')::int,
    (p_series ->> 'unscheduled_minutes')::int,
    effective_now
  );

  insert into public.assignment_series_revision_items (
    user_id, series_id, series_revision, position, action,
    plan_id, plan_revision, deadline_at,
    proposal_request_id, proposal_request_fingerprint,
    mutation_request_id, mutation_request_fingerprint, created_at
  )
  select
    p_user_id, p_series_id, next_revision,
    (value ->> 'position')::int,
    value ->> 'action',
    (value ->> 'plan_id')::uuid,
    (value ->> 'plan_revision')::int,
    (value ->> 'deadline_at')::timestamptz,
    nullif(value ->> 'proposal_request_id', '')::uuid,
    nullif(value ->> 'proposal_request_fingerprint', ''),
    nullif(value ->> 'mutation_request_id', '')::uuid,
    nullif(value ->> 'mutation_request_fingerprint', ''),
    effective_now
  from jsonb_array_elements(p_items) as entries(value);

  insert into public.assignment_series_request_identities (
    request_id, user_id, operation, request_fingerprint, series_id,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'proposal', p_request_fingerprint, p_series_id,
    next_revision, result_status, effective_now
  );
  return jsonb_build_object(
    'series_id', p_series_id,
    'revision', next_revision,
    'status', result_status
  );
end;
$$;

create or replace function public.confirm_assignment_series_v1(
  p_user_id uuid,
  p_series_id uuid,
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
  existing_request public.assignment_series_request_identities%rowtype;
  series_row public.assignment_series%rowtype;
  revision_row public.assignment_series_revisions%rowtype;
  item public.assignment_series_revision_items%rowtype;
  hidden_block_ids uuid[] := '{}'::uuid[];
  effective_now timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing_request
  from public.assignment_series_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'confirm'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.series_id <> p_series_id
       or existing_request.result_revision <> p_expected_revision then
      raise exception 'request_id is already bound to another assignment series operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'series_id', p_series_id,
      'revision', p_expected_revision,
      'status', 'active'
    );
  end if;

  select * into series_row
  from public.assignment_series
  where id = p_series_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Assignment series is unavailable.' using errcode = 'PT404';
  end if;
  select * into revision_row
  from public.assignment_series_revisions
  where user_id = p_user_id
    and series_id = p_series_id
    and revision = p_expected_revision
    and state = 'proposed'
  for update;
  if not found
     or series_row.status not in ('draft', 'active')
     or series_row.latest_revision <> p_expected_revision then
    raise exception 'Assignment series preview changed. Reload before confirmation.'
      using errcode = 'PT409';
  end if;
  effective_now := greatest(p_now, series_row.updated_at, revision_row.created_at);

  perform 1
  from public.deadline_plans as plan
  join public.assignment_series_revision_items as series_item
    on series_item.plan_id = plan.id
   and series_item.user_id = plan.user_id
  where series_item.user_id = p_user_id
    and series_item.series_id = p_series_id
    and series_item.series_revision = p_expected_revision
    and series_item.action in ('upsert', 'cancel')
  order by plan.id
  for update of plan;

  if exists (
    select 1
    from public.assignment_series_revision_items as series_item
    left join public.deadline_plans as plan
      on plan.id = series_item.plan_id and plan.user_id = series_item.user_id
    where series_item.user_id = p_user_id
      and series_item.series_id = p_series_id
      and series_item.series_revision = p_expected_revision
      and (
        (
          series_item.action = 'upsert'
          and (
            plan.id is null
            or plan.status not in ('draft', 'active')
            or plan.latest_revision <> series_item.plan_revision
            or not exists (
              select 1 from public.deadline_plan_revisions as proposed
              where proposed.user_id = p_user_id
                and proposed.plan_id = series_item.plan_id
                and proposed.revision = series_item.plan_revision
                and proposed.state = 'proposed'
            )
          )
        )
        or (
          series_item.action = 'cancel'
          and (
            plan.id is null
            or plan.status not in ('draft', 'active')
            or series_item.plan_revision <> case
              when plan.status = 'active' then plan.current_revision
              else plan.latest_revision
            end
          )
        )
      )
  ) then
    raise exception 'An assignment occurrence changed. Reload before confirmation.'
      using errcode = 'PT409';
  end if;

  select coalesce(array_agg(block.id order by block.id), '{}'::uuid[])
  into hidden_block_ids
  from public.deadline_plan_blocks as block
  where block.user_id = p_user_id
    and block.reservation_state = 'active'
    and block.plan_id in (
      select series_item.plan_id
      from public.assignment_series_revision_items as series_item
      where series_item.user_id = p_user_id
        and series_item.series_id = p_series_id
        and series_item.series_revision = p_expected_revision
        and series_item.action in ('upsert', 'cancel')
    );
  update public.deadline_plan_blocks
  set reservation_state = 'superseded'
  where id = any(hidden_block_ids);

  for item in
    select *
    from public.assignment_series_revision_items
    where user_id = p_user_id
      and series_id = p_series_id
      and series_revision = p_expected_revision
      and action = 'cancel'
    order by plan_id
  loop
    perform public.mutate_deadline_plan_lifecycle_v1(
      p_user_id,
      item.plan_id,
      item.mutation_request_id,
      item.mutation_request_fingerprint,
      item.plan_revision,
      'cancel',
      effective_now
    );
  end loop;

  for item in
    select *
    from public.assignment_series_revision_items
    where user_id = p_user_id
      and series_id = p_series_id
      and series_revision = p_expected_revision
      and action = 'upsert'
    order by plan_id
  loop
    perform public.confirm_deadline_plan_v1(
      p_user_id,
      item.plan_id,
      item.mutation_request_id,
      item.mutation_request_fingerprint,
      item.plan_revision,
      effective_now
    );
  end loop;

  update public.assignment_series_revisions
  set state = 'superseded', superseded_at = effective_now
  where user_id = p_user_id
    and series_id = p_series_id
    and state = 'active';
  update public.assignment_series_revisions
  set state = 'active', activated_at = effective_now
  where user_id = p_user_id
    and series_id = p_series_id
    and revision = p_expected_revision;
  update public.assignment_series
  set status = 'active',
      title = revision_row.title,
      current_revision = p_expected_revision,
      first_activated_at = coalesce(first_activated_at, effective_now),
      cancelled_at = null,
      updated_at = effective_now
  where id = p_series_id and user_id = p_user_id;

  insert into public.assignment_series_request_identities (
    request_id, user_id, operation, request_fingerprint, series_id,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'confirm', p_request_fingerprint, p_series_id,
    p_expected_revision, 'active', effective_now
  );
  return jsonb_build_object(
    'series_id', p_series_id,
    'revision', p_expected_revision,
    'status', 'active'
  );
end;
$$;

create or replace function public.cancel_assignment_series_future_v1(
  p_user_id uuid,
  p_series_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_revision int,
  p_items jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.assignment_series_request_identities%rowtype;
  series_row public.assignment_series%rowtype;
  revision_row public.assignment_series_revisions%rowtype;
  item jsonb;
  effective_now timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing_request
  from public.assignment_series_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'cancel_future'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.series_id <> p_series_id
       or existing_request.result_revision <> p_expected_revision then
      raise exception 'request_id is already bound to another assignment series operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'series_id', p_series_id,
      'revision', p_expected_revision,
      'status', 'cancelled'
    );
  end if;

  select * into series_row
  from public.assignment_series
  where id = p_series_id and user_id = p_user_id
  for update;
  if not found then
    raise exception 'Assignment series is unavailable.' using errcode = 'PT404';
  end if;
  select * into revision_row
  from public.assignment_series_revisions
  where user_id = p_user_id
    and series_id = p_series_id
    and revision = p_expected_revision
    and state in ('proposed', 'active')
  for update;
  if not found
     or series_row.status not in ('draft', 'active')
     or (
       revision_row.state = 'proposed'
       and series_row.latest_revision <> p_expected_revision
     )
     or (
       revision_row.state = 'active'
       and series_row.current_revision <> p_expected_revision
     ) then
    raise exception 'Assignment series changed. Reload before cancellation.'
      using errcode = 'PT409';
  end if;
  effective_now := greatest(p_now, series_row.updated_at, revision_row.created_at);

  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 40
     or exists (
       select 1 from jsonb_array_elements(p_items) as entries(value)
       where jsonb_typeof(value) <> 'object'
          or not (value ?& array[
            'plan_id', 'expected_revision', 'request_id', 'request_fingerprint'
          ])
          or value - array[
            'plan_id', 'expected_revision', 'request_id', 'request_fingerprint'
          ] <> '{}'::jsonb
          or value ->> 'request_fingerprint' !~ '^[0-9a-f]{64}$'
          or (value ->> 'expected_revision')::int not between 1 and 200
     )
     or exists (
       select 1 from jsonb_array_elements(p_items) as entries(value)
       group by (value ->> 'plan_id')::uuid
       having count(*) > 1
     ) then
    raise exception 'Assignment series cancellation payload is invalid.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.assignment_series_revision_items as series_item
    join public.deadline_plans as plan
      on plan.id = series_item.plan_id and plan.user_id = series_item.user_id
    where series_item.user_id = p_user_id
      and series_item.series_id = p_series_id
      and series_item.series_revision = p_expected_revision
      and series_item.deadline_at > effective_now
      and plan.status in ('draft', 'active')
      and not exists (
        select 1 from jsonb_array_elements(p_items) as entries(value)
        where (value ->> 'plan_id')::uuid = plan.id
          and (value ->> 'expected_revision')::int = case
            when plan.status = 'active' then plan.current_revision
            else plan.latest_revision
          end
      )
  ) or exists (
    select 1
    from jsonb_array_elements(p_items) as entries(value)
    left join public.assignment_series_revision_items as series_item
      on series_item.user_id = p_user_id
     and series_item.series_id = p_series_id
     and series_item.series_revision = p_expected_revision
     and series_item.plan_id = (value ->> 'plan_id')::uuid
    left join public.deadline_plans as plan
      on plan.id = series_item.plan_id and plan.user_id = series_item.user_id
    where series_item.id is null
       or series_item.deadline_at <= effective_now
       or plan.status not in ('draft', 'active')
       or (value ->> 'expected_revision')::int <> case
         when plan.status = 'active' then plan.current_revision
         else plan.latest_revision
       end
  ) then
    raise exception 'Open future assignment occurrences changed. Reload the series.'
      using errcode = 'PT409';
  end if;

  perform 1
  from public.deadline_plans as plan
  join jsonb_array_elements(p_items) as entries(value)
    on plan.id = (value ->> 'plan_id')::uuid
  where plan.user_id = p_user_id
  order by plan.id
  for update of plan;

  for item in
    select value
    from jsonb_array_elements(p_items) as entries(value)
    order by value ->> 'plan_id'
  loop
    perform public.mutate_deadline_plan_lifecycle_v1(
      p_user_id,
      (item ->> 'plan_id')::uuid,
      (item ->> 'request_id')::uuid,
      item ->> 'request_fingerprint',
      (item ->> 'expected_revision')::int,
      'cancel',
      effective_now
    );
  end loop;

  if revision_row.state = 'proposed' then
    update public.assignment_series_revisions
    set state = 'superseded', superseded_at = effective_now
    where user_id = p_user_id
      and series_id = p_series_id
      and revision = p_expected_revision;
  end if;
  update public.assignment_series
  set status = 'cancelled',
      cancelled_at = effective_now,
      updated_at = effective_now
  where id = p_series_id and user_id = p_user_id;

  insert into public.assignment_series_request_identities (
    request_id, user_id, operation, request_fingerprint, series_id,
    result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'cancel_future', p_request_fingerprint, p_series_id,
    p_expected_revision, 'cancelled', effective_now
  );
  return jsonb_build_object(
    'series_id', p_series_id,
    'revision', p_expected_revision,
    'status', 'cancelled'
  );
end;
$$;

revoke all on function public.propose_assignment_series_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
revoke all on function public.confirm_assignment_series_v1(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated;
revoke all on function public.cancel_assignment_series_future_v1(
  uuid, uuid, uuid, text, int, jsonb, timestamptz
) from public, anon, authenticated;

grant execute on function public.propose_assignment_series_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) to service_role;
grant execute on function public.confirm_assignment_series_v1(
  uuid, uuid, uuid, text, int, timestamptz
) to service_role;
grant execute on function public.cancel_assignment_series_future_v1(
  uuid, uuid, uuid, text, int, jsonb, timestamptz
) to service_role;
