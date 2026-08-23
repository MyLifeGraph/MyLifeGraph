-- Multi Exam Plan V1: derived orchestration metadata around canonical
-- Deadline Plan V1 revisions. User plan content remains in the existing
-- public deadline tables; these private rows only make a multi-plan preview
-- reviewable, retry-safe, and atomically confirmable.

create table private.multi_exam_plan_batches (
  id uuid not null,
  user_id uuid not null,
  contract_version text not null default 'multi-exam-plan-v1',
  status text not null default 'proposed',
  target_plan_id uuid not null,
  current_revision int not null default 1,
  latest_revision int not null default 1,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  primary key (id),
  unique (id, user_id),
  foreign key (user_id) references public.profiles (id) on delete cascade,
  foreign key (target_plan_id, user_id)
    references public.deadline_plans (id, user_id) on delete cascade,
  constraint multi_exam_plan_batches_contract_check check (
    contract_version = 'multi-exam-plan-v1'
    and status in ('proposed', 'confirmed', 'cancelled')
    and current_revision = 1
    and latest_revision = 1
    and updated_at >= created_at
    and (
      (status = 'proposed' and confirmed_at is null and cancelled_at is null)
      or (status = 'confirmed' and confirmed_at is not null and cancelled_at is null)
      or (status = 'cancelled' and confirmed_at is null and cancelled_at is not null)
    )
  )
);

create table private.multi_exam_plan_batch_revisions (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  balance_id uuid not null,
  revision int not null,
  state text not null default 'proposed',
  context_generated_at timestamptz not null,
  context_fingerprint text not null,
  confirmation_fingerprint text not null,
  learned_timing_marker text not null,
  timezone text not null,
  created_at timestamptz not null,
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  primary key (id),
  unique (balance_id, revision),
  unique (balance_id, user_id, revision),
  foreign key (balance_id, user_id)
    references private.multi_exam_plan_batches (id, user_id) on delete cascade,
  constraint multi_exam_plan_batch_revisions_shape_check check (
    revision = 1
    and state in ('proposed', 'confirmed', 'cancelled')
    and context_fingerprint ~ '^[0-9a-f]{64}$'
    and confirmation_fingerprint ~ '^[0-9a-f]{64}$'
    and learned_timing_marker ~ '^[0-9a-f]{64}$'
    and length(timezone) between 1 and 100
    and (
      (state = 'proposed' and confirmed_at is null and cancelled_at is null)
      or (state = 'confirmed' and confirmed_at is not null and cancelled_at is null)
      or (state = 'cancelled' and confirmed_at is null and cancelled_at is not null)
    )
  )
);

create unique index multi_exam_plan_batch_revisions_one_proposed_idx
  on private.multi_exam_plan_batch_revisions (balance_id)
  where state = 'proposed';

create table private.multi_exam_plan_batch_items (
  user_id uuid not null,
  balance_id uuid not null,
  balance_revision int not null,
  position int not null,
  plan_id uuid not null,
  active_revision int not null,
  base_revision int not null,
  proposed_revision int not null,
  retained_minutes int not null,
  added_minutes int not null,
  shifted_minutes int not null,
  removed_minutes int not null,
  review jsonb not null,
  primary key (balance_id, balance_revision, position),
  unique (balance_id, balance_revision, plan_id),
  unique (balance_id, user_id, balance_revision, plan_id),
  foreign key (balance_id, user_id, balance_revision)
    references private.multi_exam_plan_batch_revisions
      (balance_id, user_id, revision) on delete cascade,
  foreign key (plan_id, user_id)
    references public.deadline_plans (id, user_id) on delete cascade,
  foreign key (plan_id, user_id, proposed_revision)
    references public.deadline_plan_revisions (plan_id, user_id, revision)
      on delete cascade,
  constraint multi_exam_plan_batch_items_shape_check check (
    position between 1 and 8
    and active_revision between 1 and 200
    and base_revision between active_revision and 199
    and proposed_revision = base_revision + 1
    and retained_minutes between 0 and 30000
    and added_minutes between 0 and 30000
    and shifted_minutes between 0 and 30000
    and removed_minutes between 0 and 30000
    and jsonb_typeof(review) = 'object'
    and (review ->> 'position')::int = position
    and (review ->> 'plan_id')::uuid = plan_id
    and (review ->> 'active_revision')::int = active_revision
    and (review ->> 'base_revision')::int = base_revision
    and (review ->> 'proposed_revision')::int = proposed_revision
    and (review ->> 'retained_minutes')::int = retained_minutes
    and (review ->> 'added_minutes')::int = added_minutes
    and (review ->> 'shifted_minutes')::int = shifted_minutes
    and (review ->> 'removed_minutes')::int = removed_minutes
    and jsonb_typeof(review -> 'current_blocks') = 'array'
    and jsonb_typeof(review -> 'proposed_blocks') = 'array'
    and review -> 'current_blocks' <> review -> 'proposed_blocks'
  )
);

create index multi_exam_plan_batch_items_plan_idx
  on private.multi_exam_plan_batch_items
    (user_id, plan_id, proposed_revision, balance_id);

create index multi_exam_plan_batches_target_fk_idx
  on private.multi_exam_plan_batches (target_plan_id, user_id);

create table private.multi_exam_plan_batch_links (
  user_id uuid not null,
  plan_id uuid not null,
  proposed_revision int not null,
  balance_id uuid not null,
  balance_revision int not null,
  status text not null default 'proposed',
  confirm_request_id uuid not null,
  confirm_request_fingerprint text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  primary key (plan_id, proposed_revision),
  unique (balance_id, balance_revision, plan_id),
  foreign key (balance_id, user_id, balance_revision, plan_id)
    references private.multi_exam_plan_batch_items
      (balance_id, user_id, balance_revision, plan_id) on delete cascade,
  foreign key (plan_id, user_id, proposed_revision)
    references public.deadline_plan_revisions (plan_id, user_id, revision)
      on delete cascade,
  constraint multi_exam_plan_batch_links_shape_check check (
    proposed_revision between 2 and 200
    and balance_revision = 1
    and status in ('proposed', 'confirmed', 'cancelled')
    and confirm_request_fingerprint ~ '^[0-9a-f]{64}$'
    and updated_at >= created_at
  )
);

create unique index multi_exam_plan_batch_links_one_proposed_plan_idx
  on private.multi_exam_plan_batch_links (plan_id)
  where status = 'proposed';

create index multi_exam_plan_batch_links_revision_fk_idx
  on private.multi_exam_plan_batch_links
    (plan_id, user_id, proposed_revision);

create index multi_exam_plan_batch_links_item_fk_idx
  on private.multi_exam_plan_batch_links
    (balance_id, user_id, balance_revision, plan_id);

create table private.multi_exam_plan_request_identities (
  request_id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  operation text not null,
  request_fingerprint text not null,
  target_plan_id uuid,
  expected_plan_revision int,
  balance_id uuid,
  expected_balance_revision int,
  outcome text not null,
  result_plan_id uuid,
  result_revision int,
  result_status text not null,
  created_at timestamptz not null,
  foreign key (target_plan_id, user_id)
    references public.deadline_plans (id, user_id) on delete cascade,
  foreign key (result_plan_id, user_id)
    references public.deadline_plans (id, user_id) on delete cascade,
  foreign key (balance_id, user_id)
    references private.multi_exam_plan_batches (id, user_id) on delete cascade,
  constraint multi_exam_plan_requests_shape_check check (
    operation in ('proposal', 'confirm', 'cancel')
    and request_fingerprint ~ '^[0-9a-f]{64}$'
    and outcome in ('no_change', 'single_plan', 'multi_exam_batch')
    and result_status in ('unchanged', 'proposed', 'confirmed', 'cancelled')
    and (
      operation = 'proposal'
      and target_plan_id is not null
      and expected_plan_revision between 1 and 199
      and expected_balance_revision is null
      and (
        (outcome = 'no_change' and balance_id is null and result_plan_id is null
          and result_revision is null and result_status = 'unchanged')
        or (outcome = 'single_plan' and balance_id is null
          and result_plan_id is not null and result_revision between 2 and 200
          and result_status = 'proposed')
        or (outcome = 'multi_exam_batch' and balance_id is not null
          and result_plan_id is null and result_revision = 1
          and result_status = 'proposed')
      )
      or operation in ('confirm', 'cancel')
      and target_plan_id is null
      and expected_plan_revision is null
      and balance_id is not null
      and expected_balance_revision = 1
      and outcome = 'multi_exam_batch'
      and result_plan_id is null
      and result_revision = 1
      and result_status = case operation
        when 'confirm' then 'confirmed' else 'cancelled' end
    )
  )
);

create index multi_exam_plan_requests_owner_created_idx
  on private.multi_exam_plan_request_identities
    (user_id, created_at desc, request_id desc);

create index multi_exam_plan_requests_target_fk_idx
  on private.multi_exam_plan_request_identities (target_plan_id, user_id)
  where target_plan_id is not null;

create index multi_exam_plan_requests_result_fk_idx
  on private.multi_exam_plan_request_identities (result_plan_id, user_id)
  where result_plan_id is not null;

create index multi_exam_plan_requests_balance_fk_idx
  on private.multi_exam_plan_request_identities (balance_id, user_id)
  where balance_id is not null;

create index multi_exam_plan_batches_owner_updated_idx
  on private.multi_exam_plan_batches (user_id, updated_at desc, id desc);

alter table private.multi_exam_plan_batches enable row level security;
alter table private.multi_exam_plan_batches force row level security;
alter table private.multi_exam_plan_batch_revisions enable row level security;
alter table private.multi_exam_plan_batch_revisions force row level security;
alter table private.multi_exam_plan_batch_items enable row level security;
alter table private.multi_exam_plan_batch_items force row level security;
alter table private.multi_exam_plan_batch_links enable row level security;
alter table private.multi_exam_plan_batch_links force row level security;
alter table private.multi_exam_plan_request_identities enable row level security;
alter table private.multi_exam_plan_request_identities force row level security;

revoke all on table private.multi_exam_plan_batches,
  private.multi_exam_plan_batch_revisions,
  private.multi_exam_plan_batch_items,
  private.multi_exam_plan_batch_links,
  private.multi_exam_plan_request_identities
from public, anon, authenticated, service_role;

create policy multi_exam_plan_batches_service_v1
on private.multi_exam_plan_batches for all to service_role
using ((select auth.role()) = 'service_role')
with check ((select auth.role()) = 'service_role');
create policy multi_exam_plan_batch_revisions_service_v1
on private.multi_exam_plan_batch_revisions for all to service_role
using ((select auth.role()) = 'service_role')
with check ((select auth.role()) = 'service_role');
create policy multi_exam_plan_batch_items_service_v1
on private.multi_exam_plan_batch_items for all to service_role
using ((select auth.role()) = 'service_role')
with check ((select auth.role()) = 'service_role');
create policy multi_exam_plan_batch_links_service_v1
on private.multi_exam_plan_batch_links for all to service_role
using ((select auth.role()) = 'service_role')
with check ((select auth.role()) = 'service_role');
create policy multi_exam_plan_requests_service_v1
on private.multi_exam_plan_request_identities for all to service_role
using ((select auth.role()) = 'service_role')
with check ((select auth.role()) = 'service_role');

-- These legacy owner-writable authorities participate in the balance context
-- or can release reservations included in it, but predate the shared owner-
-- lock convention. Acquire that lock before their row guards or writes, so a
-- balance fingerprint cannot be read between an authoritative mutation and
-- its commit. The Task/Habit BEFORE triggers also run before their existing
-- AFTER release_planner_target_reservations triggers.
create or replace function private.lock_multi_exam_context_owner_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  prior_owner uuid;
  next_owner uuid;
  owner_id uuid;
begin
  if tg_table_schema <> 'public'
     or tg_table_name not in (
       'profiles', 'tasks', 'habits', 'schedule_items', 'focus_sessions',
       'learning_preferences'
     ) then
    raise exception 'Multi-Exam context owner lock target is invalid.'
      using errcode = '22023';
  end if;
  if tg_table_name = 'profiles' then
    if tg_op <> 'INSERT' then
      prior_owner := old.id;
    end if;
    if tg_op <> 'DELETE' then
      next_owner := new.id;
    end if;
  else
    if tg_op <> 'INSERT' then
      prior_owner := old.user_id;
    end if;
    if tg_op <> 'DELETE' then
      next_owner := new.user_id;
    end if;
  end if;
  if prior_owner is not null and next_owner is not null
     and prior_owner <> next_owner then
    raise exception 'Planning context ownership cannot be changed.'
      using errcode = 'PT409';
  end if;
  owner_id := coalesce(next_owner, prior_owner);
  if owner_id is null then
    raise exception 'Planning context owner is required.'
      using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.lock_multi_exam_context_owner_v1()
from public, anon, authenticated, service_role;

create trigger a_multi_exam_context_owner_lock_profiles_v1
before insert or update or delete on public.profiles
for each row execute function private.lock_multi_exam_context_owner_v1();

create trigger a_multi_exam_context_owner_lock_tasks_v1
before insert or update or delete on public.tasks
for each row execute function private.lock_multi_exam_context_owner_v1();

create trigger a_multi_exam_context_owner_lock_habits_v1
before insert or update or delete on public.habits
for each row execute function private.lock_multi_exam_context_owner_v1();

create trigger a_multi_exam_context_owner_lock_schedule_v1
before insert or update or delete on public.schedule_items
for each row execute function private.lock_multi_exam_context_owner_v1();

create trigger a_multi_exam_context_owner_lock_focus_v1
before insert or update or delete on public.focus_sessions
for each row execute function private.lock_multi_exam_context_owner_v1();

create trigger a_multi_exam_context_owner_lock_learning_v1
before insert or update or delete on public.learning_preferences
for each row execute function private.lock_multi_exam_context_owner_v1();

create or replace function private.multi_exam_plan_context_payload_v1(
  p_user_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'profile', (
      select jsonb_build_object(
        'timezone', profile.timezone,
        'timezone_revision', profile.timezone_revision,
        'daily_preparation_budget_minutes',
          profile.daily_preparation_budget_minutes,
        'preparation_budget_revision', profile.preparation_budget_revision
      )
      from public.profiles as profile
      where profile.id = p_user_id
    ),
    'best_energy_window', coalesce((
      select response.responses -> 'best_energy_window'
      from public.intake_responses as response
      where response.user_id = p_user_id
        and response.version = 'intake-v1'
        and response.state = 'applied'
      order by response.revision desc, response.updated_at desc, response.id desc
      limit 1
    ), '"variable"'::jsonb),
    'study_setup', (
      select to_jsonb(setup) - array['user_id', 'created_at', 'updated_at']
      from public.study_setup_profiles as setup
      where setup.user_id = p_user_id
    ),
    'planner_preference', (
      select to_jsonb(preference) - array['user_id', 'created_at']
      from public.planner_preferences as preference
      where preference.user_id = p_user_id
    ),
    'learning_preference', (
      select jsonb_build_object(
        'revision', preference.revision,
        'personal_pattern_analysis_enabled',
          preference.personal_pattern_analysis_enabled,
        'learned_focus_planning_enabled',
          preference.learned_focus_planning_enabled,
        'updated_at', preference.updated_at
      )
      from public.learning_preferences as preference
      where preference.user_id = p_user_id
    ),
    'deadline_plans', coalesce((
      select jsonb_agg(to_jsonb(plan) order by plan.id)
      from public.deadline_plans as plan
      where plan.user_id = p_user_id and plan.status = 'active'
    ), '[]'::jsonb),
    'deadline_revisions', coalesce((
      select jsonb_agg(to_jsonb(revision) order by revision.plan_id,
                       revision.revision)
      from public.deadline_plan_revisions as revision
      join public.deadline_plans as plan
        on plan.id = revision.plan_id and plan.user_id = revision.user_id
      where revision.user_id = p_user_id
        and plan.status = 'active'
        and revision.revision in (plan.current_revision, plan.latest_revision)
    ), '[]'::jsonb),
    'deadline_blocks', coalesce((
      select jsonb_agg(to_jsonb(block) order by block.plan_id, block.revision,
                       block.sequence, block.id)
      from public.deadline_plan_blocks as block
      join public.deadline_plans as plan
        on plan.id = block.plan_id and plan.user_id = block.user_id
      where block.user_id = p_user_id
        and plan.status = 'active'
        and block.revision in (plan.current_revision, plan.latest_revision)
    ), '[]'::jsonb),
    'focus_facts', coalesce((
      select jsonb_agg(
        to_jsonb(focus) || jsonb_build_object(
          'deadline_plan_block_id', source.deadline_plan_block_id
        ) order by focus.started_at, focus.id
      )
      from public.focus_sessions as focus
      join public.deadline_plans as plan
        on plan.id = focus.task_id and plan.user_id = focus.user_id
      left join public.focus_session_schedule_sources as source
        on source.focus_session_id = focus.id and source.user_id = focus.user_id
      where focus.user_id = p_user_id
        and plan.status = 'active'
        and focus.status = 'completed'
        and focus.started_at >= plan.first_activated_at
    ), '[]'::jsonb),
    'schedule_items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.weekday, item.starts_at,
                       item.id)
      from public.schedule_items as item where item.user_id = p_user_id
    ), '[]'::jsonb),
    'planner_plans', coalesce((
      select jsonb_agg(to_jsonb(plan) order by plan.id)
      from public.planner_action_plans as plan
      where plan.user_id = p_user_id
        and plan.status in ('active', 'unscheduled')
    ), '[]'::jsonb),
    'planner_revisions', coalesce((
      select jsonb_agg(to_jsonb(revision) order by revision.plan_id,
                       revision.revision)
      from public.planner_action_plan_revisions as revision
      join public.planner_action_plans as plan
        on plan.id = revision.plan_id and plan.user_id = revision.user_id
      where revision.user_id = p_user_id
        and plan.status in ('active', 'unscheduled')
        and revision.revision in (plan.current_revision, plan.latest_revision)
    ), '[]'::jsonb),
    'planner_task_blocks', coalesce((
      select jsonb_agg(to_jsonb(block) order by block.plan_id, block.revision,
                       block.starts_at, block.id)
      from public.planner_task_blocks as block
      where block.user_id = p_user_id and block.state = 'active'
    ), '[]'::jsonb),
    'planner_habit_slots', coalesce((
      select jsonb_agg(to_jsonb(slot) order by slot.plan_id, slot.weekday,
                       slot.starts_at, slot.id)
      from public.planner_habit_slots as slot
      where slot.user_id = p_user_id and slot.state = 'active'
    ), '[]'::jsonb),
    'planner_commitments', coalesce((
      select jsonb_agg(to_jsonb(commitment) order by commitment.id)
      from public.planner_commitments as commitment
      where commitment.user_id = p_user_id and commitment.status = 'active'
    ), '[]'::jsonb),
    'calendar_connection', (
      select to_jsonb(connection)
      from public.calendar_connections as connection
      where connection.user_id = p_user_id
        and connection.status = 'connected'
        and connection.imported_data_deleted_at is null
      order by connection.updated_at desc, connection.id desc
      limit 1
    ),
    'calendar_import', (
      select to_jsonb(import)
      from public.calendar_connections as connection
      join public.calendar_imports as import
        on import.id = connection.last_import_id
       and import.user_id = connection.user_id
       and import.connection_id = connection.id
      where connection.user_id = p_user_id
        and connection.status = 'connected'
        and connection.imported_data_deleted_at is null
      order by connection.updated_at desc, connection.id desc
      limit 1
    ),
    'calendar_events', coalesce((
      select jsonb_agg(to_jsonb(event) order by event.sort_date,
                       event.sort_time, event.id)
      from public.calendar_connections as connection
      join public.calendar_imports as import
        on import.id = connection.last_import_id
       and import.user_id = connection.user_id
       and import.connection_id = connection.id
      join public.calendar_events as event
        on event.import_id = import.id
       and event.user_id = import.user_id
       and event.connection_id = import.connection_id
      where connection.user_id = p_user_id
        and connection.status = 'connected'
        and connection.imported_data_deleted_at is null
    ), '[]'::jsonb)
  );
$$;

revoke all on function private.multi_exam_plan_context_payload_v1(uuid)
from public, anon, authenticated, service_role;

create or replace function private.multi_exam_plan_context_fingerprint_v1(
  p_user_id uuid
)
returns text
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select encode(
    extensions.digest(
      convert_to(private.multi_exam_plan_context_payload_v1(p_user_id)::text,
                 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function private.multi_exam_plan_context_fingerprint_v1(uuid)
from public, anon, authenticated, service_role;

create or replace function private.multi_exam_plan_learned_timing_marker_v1(
  p_user_id uuid,
  p_pilot_enabled boolean
)
returns text
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select encode(
    extensions.digest(
      convert_to(jsonb_build_object(
        'pilot_enabled', p_pilot_enabled,
        'preference', (
          select jsonb_build_object(
            'revision', preference.revision,
            'personal_pattern_analysis_enabled',
              preference.personal_pattern_analysis_enabled,
            'learned_focus_planning_enabled',
              preference.learned_focus_planning_enabled,
            'updated_at', preference.updated_at
          )
          from public.learning_preferences as preference
          where preference.user_id = p_user_id
        ),
        'active_exam_timing', coalesce((
          select jsonb_agg(jsonb_build_object(
            'plan_id', plan.id,
            'revision', revision.revision,
            'source', revision.timing_preference_source,
            'window', revision.timing_preference_window,
            'evidence_count', revision.timing_evidence_count,
            'evidence_starts_on', revision.timing_evidence_starts_on,
            'evidence_ends_on', revision.timing_evidence_ends_on,
            'evidence_fingerprint', revision.timing_evidence_fingerprint,
            'fell_back_to_setup', revision.timing_fell_back_to_setup,
            'warning', revision.timing_warning
          ) order by plan.id)
          from public.deadline_plans as plan
          join public.deadline_plan_revisions as revision
            on revision.user_id = plan.user_id
           and revision.plan_id = plan.id
           and revision.revision = plan.current_revision
          where plan.user_id = p_user_id
            and plan.status = 'active'
            and plan.kind = 'exam'
        ), '[]'::jsonb)
      )::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function private.multi_exam_plan_learned_timing_marker_v1(
  uuid, boolean
) from public, anon, authenticated, service_role;

create or replace function private.multi_exam_plan_active_plans_v1(
  p_user_id uuid,
  p_generated_at timestamptz
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(jsonb_agg(plan_row.payload order by
    (plan_row.payload ->> 'deadline_at')::timestamptz,
    plan_row.payload ->> 'id'), '[]'::jsonb)
  from (
    select
      to_jsonb(revision)
      || jsonb_build_object(
        'id', plan.id,
        'status', plan.status,
        'kind', plan.kind,
        'title', revision.title,
        'managed_task_id', plan.managed_task_id,
        'first_activated_at', plan.first_activated_at,
        'current_revision', plan.current_revision,
        'latest_revision', plan.latest_revision,
        'active_revision', plan.current_revision,
        'pending_revision', (
          select proposed.revision
          from public.deadline_plan_revisions as proposed
          where proposed.user_id = plan.user_id
            and proposed.plan_id = plan.id
            and proposed.state = 'proposed'
          limit 1
        ),
        'source_calendar_event', (
          select to_jsonb(event) || jsonb_build_object(
            '_connection_status', connection.status,
            '_connection_last_import_id', connection.last_import_id,
            '_connection_imported_data_deleted_at',
              connection.imported_data_deleted_at,
            '_import_planning_status', import.planning_status
          )
          from public.calendar_events as event
          join public.calendar_connections as connection
            on connection.id = event.connection_id
           and connection.user_id = event.user_id
          join public.calendar_imports as import
            on import.id = event.import_id
           and import.user_id = event.user_id
           and import.connection_id = event.connection_id
          where event.user_id = plan.user_id
            and event.id = revision.source_calendar_event_id
          limit 1
        )
      ) as payload
    from public.deadline_plans as plan
    join public.deadline_plan_revisions as revision
      on revision.user_id = plan.user_id
     and revision.plan_id = plan.id
     and revision.revision = plan.current_revision
     and revision.state = 'active'
    join public.profiles as profile on profile.id = plan.user_id
    where plan.user_id = p_user_id
      and plan.status = 'active'
      and (
        plan.kind = 'assignment'
        or revision.deadline_at < (
          ((p_generated_at at time zone profile.timezone)::date + 367)::timestamp
          at time zone profile.timezone
        )
      )
  ) as plan_row;
$$;

revoke all on function private.multi_exam_plan_active_plans_v1(
  uuid, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.get_multi_exam_plan_snapshot_v1(
  p_user_id uuid,
  p_generated_at timestamptz
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  health jsonb;
  fingerprint text;
  active_plans jsonb;
begin
  if p_user_id is null or p_generated_at is null then
    raise exception 'Exam balance snapshot arguments are required.'
      using errcode = '22023';
  end if;
  select public.get_exam_plan_health_snapshot_v1(p_user_id, p_generated_at),
         private.multi_exam_plan_context_fingerprint_v1(p_user_id),
         private.multi_exam_plan_active_plans_v1(p_user_id, p_generated_at)
  into health, fingerprint, active_plans;
  if health is null or fingerprint is null or active_plans is null then
    raise exception 'Exam balance source authorities are unavailable.'
      using errcode = 'PT404';
  end if;
  return jsonb_build_object(
    'contract_version', 'multi-exam-plan-snapshot-v1',
    'context_fingerprint', fingerprint,
    'active_plans', active_plans,
    'health_snapshot', health
  );
end;
$$;

revoke all on function public.get_multi_exam_plan_snapshot_v1(uuid, timestamptz)
from public, anon, authenticated, service_role;
grant execute on function public.get_multi_exam_plan_snapshot_v1(uuid, timestamptz)
to service_role;

create or replace function public.get_multi_exam_plan_request_v1(
  p_user_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  request_row private.multi_exam_plan_request_identities%rowtype;
begin
  if p_user_id is null or p_request_id is null then
    raise exception 'Exam balance request lookup arguments are required.'
      using errcode = '22023';
  end if;
  select * into request_row
  from private.multi_exam_plan_request_identities
  where request_id = p_request_id;
  if not found then
    return jsonb_build_object('found', false);
  end if;
  if request_row.user_id <> p_user_id then
    raise exception 'request_id is already bound to another owner.'
      using errcode = 'PT409';
  end if;
  return jsonb_build_object(
    'found', true,
    'user_id', request_row.user_id,
    'operation', request_row.operation,
    'request_fingerprint', request_row.request_fingerprint,
    'target_plan_id', request_row.target_plan_id,
    'expected_plan_revision', request_row.expected_plan_revision,
    'balance_id', request_row.balance_id,
    'expected_balance_revision', request_row.expected_balance_revision,
    'outcome', request_row.outcome,
    'result_plan_id', request_row.result_plan_id,
    'result_revision', request_row.result_revision,
    'result_status', request_row.result_status
  );
end;
$$;

revoke all on function public.get_multi_exam_plan_request_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_multi_exam_plan_request_v1(uuid, uuid)
to service_role;

create or replace function private.multi_exam_plan_batch_projection_v1(
  p_user_id uuid,
  p_balance_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'id', batch.id,
    'status', batch.status,
    'revision', batch.current_revision,
    'target_plan_id', batch.target_plan_id,
    'context_fingerprint', revision.context_fingerprint,
    'confirmation_fingerprint', revision.confirmation_fingerprint,
    'timezone', revision.timezone,
    'created_at', batch.created_at,
    'updated_at', batch.updated_at,
    'confirmed_at', batch.confirmed_at,
    'cancelled_at', batch.cancelled_at,
    'retained_minutes', coalesce((
      select sum(item.retained_minutes)::int
      from private.multi_exam_plan_batch_items as item
      where item.user_id = batch.user_id
        and item.balance_id = batch.id
        and item.balance_revision = revision.revision
    ), 0),
    'added_minutes', coalesce((
      select sum(item.added_minutes)::int
      from private.multi_exam_plan_batch_items as item
      where item.user_id = batch.user_id
        and item.balance_id = batch.id
        and item.balance_revision = revision.revision
    ), 0),
    'shifted_minutes', coalesce((
      select sum(item.shifted_minutes)::int
      from private.multi_exam_plan_batch_items as item
      where item.user_id = batch.user_id
        and item.balance_id = batch.id
        and item.balance_revision = revision.revision
    ), 0),
    'removed_minutes', coalesce((
      select sum(item.removed_minutes)::int
      from private.multi_exam_plan_batch_items as item
      where item.user_id = batch.user_id
        and item.balance_id = batch.id
        and item.balance_revision = revision.revision
    ), 0),
    'items', coalesce((
      select jsonb_agg(item.review order by item.position)
      from private.multi_exam_plan_batch_items as item
      where item.user_id = batch.user_id
        and item.balance_id = batch.id
        and item.balance_revision = revision.revision
    ), '[]'::jsonb),
    'child_links', coalesce((
      select jsonb_agg(jsonb_build_object(
        'plan_id', link.plan_id,
        'proposed_revision', link.proposed_revision,
        'balance_id', link.balance_id,
        'balance_revision', link.balance_revision,
        'status', link.status
      ) order by item.position)
      from private.multi_exam_plan_batch_links as link
      join private.multi_exam_plan_batch_items as item
        on item.balance_id = link.balance_id
       and item.balance_revision = link.balance_revision
       and item.plan_id = link.plan_id
       and item.user_id = link.user_id
      where link.user_id = batch.user_id
        and link.balance_id = batch.id
        and link.balance_revision = revision.revision
    ), '[]'::jsonb)
  )
  from private.multi_exam_plan_batches as batch
  join private.multi_exam_plan_batch_revisions as revision
    on revision.balance_id = batch.id
   and revision.user_id = batch.user_id
   and revision.revision = batch.current_revision
  where batch.user_id = p_user_id and batch.id = p_balance_id;
$$;

revoke all on function private.multi_exam_plan_batch_projection_v1(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function public.get_multi_exam_plan_projection_v1(
  p_user_id uuid,
  p_balance_id uuid default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
declare
  balance jsonb;
  balances jsonb;
begin
  if p_user_id is null then
    raise exception 'Exam balance projection owner is required.'
      using errcode = '22023';
  end if;
  if p_balance_id is not null then
    balance := private.multi_exam_plan_batch_projection_v1(
      p_user_id, p_balance_id
    );
    if balance is null then
      raise exception 'Exam balance was not found.' using errcode = 'PT404';
    end if;
    return jsonb_build_object(
      'contract_version', 'multi-exam-plan-v1',
      'origin', 'authenticated_backend',
      'balance', balance
    );
  end if;
  select coalesce(jsonb_agg(summary.payload order by
    (summary.payload ->> 'updated_at')::timestamptz desc,
    summary.payload ->> 'id' desc), '[]'::jsonb)
  into balances
  from (
    select jsonb_build_object(
      'id', batch.id,
      'status', batch.status,
      'revision', batch.current_revision,
      'target_plan_id', batch.target_plan_id,
      'affected_plan_count', (
        select count(*)::int
        from private.multi_exam_plan_batch_items as item
        where item.user_id = batch.user_id
          and item.balance_id = batch.id
          and item.balance_revision = batch.current_revision
      ),
      'shifted_minutes', (
        select coalesce(sum(item.shifted_minutes), 0)::int
        from private.multi_exam_plan_batch_items as item
        where item.user_id = batch.user_id
          and item.balance_id = batch.id
          and item.balance_revision = batch.current_revision
      ),
      'created_at', batch.created_at,
      'updated_at', batch.updated_at
    ) as payload
    from private.multi_exam_plan_batches as batch
    where batch.user_id = p_user_id
    order by batch.updated_at desc, batch.id desc
    limit 200
  ) as summary;
  return jsonb_build_object(
    'contract_version', 'multi-exam-plan-v1',
    'origin', 'authenticated_backend',
    'balances', balances
  );
end;
$$;

revoke all on function public.get_multi_exam_plan_projection_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_multi_exam_plan_projection_v1(uuid, uuid)
to service_role;

-- Keep every normal single-plan proposal outside a pending batch. The batch
-- writer calls the ungranted inner chain before it creates links, while
-- Assignment Series continues to use this public wrapper and therefore keeps
-- its existing atomic delegation path.
alter function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) rename to propose_deadline_plan_with_timing_v1_without_balance_guard;

revoke all on function
  public.propose_deadline_plan_with_timing_v1_without_balance_guard(
    uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
  )
from public, anon, authenticated, service_role;

create or replace function public.propose_deadline_plan_with_timing_v1(
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
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));

  -- The inner function owns exact replay validation. Preserve that precedence
  -- so a successful response-loss retry never becomes a later batch conflict.
  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    return public.propose_deadline_plan_with_timing_v1_without_balance_guard(
      p_user_id, p_request_id, p_request_fingerprint, p_plan_id,
      p_base_revision, p_proposal, p_blocks, p_now
    );
  end if;

  if exists (
    select 1
    from private.multi_exam_plan_batch_links as link
    where link.user_id = p_user_id
      and link.plan_id = p_plan_id
      and link.status = 'proposed'
  ) then
    raise exception
      'This Exam is part of a pending Exam balance. Review Exam balance.'
      using errcode = 'PT409';
  end if;

  return public.propose_deadline_plan_with_timing_v1_without_balance_guard(
    p_user_id, p_request_id, p_request_fingerprint, p_plan_id,
    p_base_revision, p_proposal, p_blocks, p_now
  );
end;
$$;

revoke all on function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) to service_role;

-- Completing or cancelling the active root while a replacement belongs to a
-- batch would strand the batch. Preserve exact lifecycle replay first, then
-- reject every new single lifecycle mutation for a linked plan.
alter function public.mutate_deadline_plan_lifecycle_v1(
  uuid, uuid, uuid, text, int, text, timestamptz
) rename to mutate_deadline_plan_lifecycle_v1_without_balance_guard;

revoke all on function
  public.mutate_deadline_plan_lifecycle_v1_without_balance_guard(
    uuid, uuid, uuid, text, int, text, timestamptz
  )
from public, anon, authenticated, service_role;

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
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));

  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    return public.mutate_deadline_plan_lifecycle_v1_without_balance_guard(
      p_user_id, p_plan_id, p_request_id, p_request_fingerprint,
      p_expected_revision, p_action, p_now
    );
  end if;

  if exists (
    select 1
    from private.multi_exam_plan_batch_links as link
    where link.user_id = p_user_id
      and link.plan_id = p_plan_id
      and link.status = 'proposed'
  ) then
    raise exception
      'This Exam is part of a pending Exam balance. Review Exam balance.'
      using errcode = 'PT409';
  end if;

  return public.mutate_deadline_plan_lifecycle_v1_without_balance_guard(
    p_user_id, p_plan_id, p_request_id, p_request_fingerprint,
    p_expected_revision, p_action, p_now
  );
end;
$$;

revoke all on function public.mutate_deadline_plan_lifecycle_v1(
  uuid, uuid, uuid, text, int, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.mutate_deadline_plan_lifecycle_v1(
  uuid, uuid, uuid, text, int, text, timestamptz
) to service_role;

alter function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) rename to confirm_deadline_plan_v1_without_exam_balance_guard;

revoke all on function
  public.confirm_deadline_plan_v1_without_exam_balance_guard(
    uuid, uuid, uuid, text, int, timestamptz
  )
from public, anon, authenticated, service_role;

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
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));
  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    return public.confirm_deadline_plan_v1_without_exam_balance_guard(
      p_user_id, p_plan_id, p_request_id, p_request_fingerprint,
      p_expected_revision, p_now
    );
  end if;
  if exists (
    select 1
    from private.multi_exam_plan_batch_links as link
    where link.user_id = p_user_id
      and link.plan_id = p_plan_id
      and link.proposed_revision = p_expected_revision
      and link.status = 'proposed'
  ) then
    raise exception
      'This preview belongs to an Exam balance. Review Exam balance.'
      using errcode = 'PT409';
  end if;
  return public.confirm_deadline_plan_v1_without_exam_balance_guard(
    p_user_id,
    p_plan_id,
    p_request_id,
    p_request_fingerprint,
    p_expected_revision,
    p_now
  );
end;
$$;

revoke all on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.confirm_deadline_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) to service_role;

create or replace function private.multi_exam_plan_current_blocks_v1(
  p_user_id uuid,
  p_plan_id uuid,
  p_revision int,
  p_generated_at timestamptz
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  with credits as (
    select private.deadline_block_credits_v2(
      p_user_id, p_plan_id, p_revision
    ) as value
  ), eligible as (
    select
      block.*,
      coalesce((credits.value ->> block.id::text)::int, 0) as credited_minutes
    from public.deadline_plan_blocks as block
    cross join credits
    where block.user_id = p_user_id
      and block.plan_id = p_plan_id
      and block.revision = p_revision
      and block.reservation_state = 'active'
      and block.starts_at >= p_generated_at
      and coalesce((credits.value ->> block.id::text)::int, 0)
          < block.planned_minutes
  ), ordered as (
    select eligible.*,
      row_number() over (order by starts_at, id)::int as review_sequence
    from eligible
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'sequence', review_sequence,
    'starts_at', to_char(starts_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'ends_at', to_char(ends_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'reserved_ends_at', to_char(reserved_ends_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'local_date', local_date,
    'planned_minutes', planned_minutes,
    'recovery_minutes', recovery_minutes,
    'credited_minutes', credited_minutes
  ) order by review_sequence), '[]'::jsonb)
  from ordered;
$$;

revoke all on function private.multi_exam_plan_current_blocks_v1(
  uuid, uuid, int, timestamptz
) from public, anon, authenticated, service_role;

create or replace function private.multi_exam_plan_proposed_blocks_v1(
  p_blocks jsonb
)
returns jsonb
language sql
security definer
immutable
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', value -> 'id',
    'sequence', value -> 'sequence',
    'starts_at', value -> 'starts_at',
    'ends_at', value -> 'ends_at',
    'reserved_ends_at', value -> 'reserved_ends_at',
    'local_date', value -> 'local_date',
    'planned_minutes', value -> 'planned_minutes',
    'recovery_minutes', value -> 'recovery_minutes',
    'credited_minutes', 0
  ) order by (value ->> 'sequence')::int), '[]'::jsonb)
  from jsonb_array_elements(p_blocks) as blocks(value);
$$;

revoke all on function private.multi_exam_plan_proposed_blocks_v1(jsonb)
from public, anon, authenticated, service_role;

create or replace function private.multi_exam_plan_review_is_valid_v1(
  p_review jsonb
)
returns boolean
language sql
security definer
immutable
set search_path = pg_catalog, pg_temp
as $$
  with current_rows as (
    select value,
      jsonb_build_array(
        value -> 'starts_at', value -> 'ends_at',
        value -> 'reserved_ends_at', value -> 'planned_minutes',
        value -> 'recovery_minutes'
      ) as signature,
      count(*) filter (
        where (value ->> 'credited_minutes')::int = 0
      ) over (
        partition by jsonb_build_array(
          value -> 'starts_at', value -> 'ends_at',
          value -> 'reserved_ends_at', value -> 'planned_minutes',
          value -> 'recovery_minutes'
        ) order by ordinal rows unbounded preceding
      ) as duplicate_number
    from jsonb_array_elements(p_review -> 'current_blocks')
      with ordinality as blocks(value, ordinal)
  ), proposed_rows as (
    select value,
      jsonb_build_array(
        value -> 'starts_at', value -> 'ends_at',
        value -> 'reserved_ends_at', value -> 'planned_minutes',
        value -> 'recovery_minutes'
      ) as signature,
      row_number() over (
        partition by jsonb_build_array(
          value -> 'starts_at', value -> 'ends_at',
          value -> 'reserved_ends_at', value -> 'planned_minutes',
          value -> 'recovery_minutes'
        ) order by ordinal
      ) as duplicate_number
    from jsonb_array_elements(p_review -> 'proposed_blocks')
      with ordinality as blocks(value, ordinal)
  ), totals as (
    select
      coalesce((select sum(
        (value ->> 'planned_minutes')::int
          - (value ->> 'credited_minutes')::int
      ) from current_rows), 0)::int as old_total,
      coalesce((select sum((value ->> 'planned_minutes')::int)
        from proposed_rows), 0)::int as new_total,
      coalesce((select sum((current_rows.value ->> 'planned_minutes')::int)
        from current_rows
        join proposed_rows using (signature, duplicate_number)
        where (current_rows.value ->> 'credited_minutes')::int = 0
      ), 0)::int as retained_total,
      coalesce((select count(*) from current_rows), 0)::int as old_count,
      coalesce((select count(*) from proposed_rows), 0)::int as new_count,
      coalesce((select count(*)
        from current_rows
        join proposed_rows using (signature, duplicate_number)
        where (current_rows.value ->> 'credited_minutes')::int = 0
      ), 0)::int as retained_count
  ), axes as (
    select *,
      least(old_total - retained_total, new_total - retained_total)::int
        as shifted_total,
      least(old_count - retained_count, new_count - retained_count)::int
        as shifted_count
    from totals
  )
  select
    jsonb_typeof(p_review) = 'object'
    and jsonb_typeof(p_review -> 'current_blocks') = 'array'
    and jsonb_typeof(p_review -> 'proposed_blocks') = 'array'
    and jsonb_array_length(p_review -> 'current_blocks') <= 120
    and jsonb_array_length(p_review -> 'proposed_blocks') <= 120
    and not exists (
      select 1
      from jsonb_array_elements(p_review -> 'current_blocks')
        with ordinality as block(value, ordinal)
      where (value ->> 'sequence')::int <> ordinal
        or (value ->> 'credited_minutes')::int < 0
        or (value ->> 'credited_minutes')::int
             > (value ->> 'planned_minutes')::int
    )
    and not exists (
      select 1
      from jsonb_array_elements(p_review -> 'proposed_blocks')
        with ordinality as block(value, ordinal)
      where (value ->> 'sequence')::int <> ordinal
        or (value ->> 'credited_minutes')::int <> 0
    )
    and (p_review ->> 'retained_minutes')::int = retained_total
    and (p_review ->> 'shifted_minutes')::int = shifted_total
    and (p_review ->> 'removed_minutes')::int =
      old_total - retained_total - shifted_total
    and (p_review ->> 'added_minutes')::int =
      new_total - retained_total - shifted_total
    and (p_review ->> 'retained_block_count')::int = retained_count
    and (p_review ->> 'shifted_block_count')::int = shifted_count
    and (p_review ->> 'removed_block_count')::int =
      old_count - retained_count - shifted_count
    and (p_review ->> 'added_block_count')::int =
      new_count - retained_count - shifted_count
    and (
      old_total <> retained_total
      or new_total <> retained_total
      or old_count <> retained_count
      or new_count <> retained_count
    )
  from axes;
$$;

revoke all on function private.multi_exam_plan_review_is_valid_v1(jsonb)
from public, anon, authenticated, service_role;

create or replace function public.propose_multi_exam_plan_v1(
  p_user_id uuid,
  p_outcome text,
  p_balance_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_target_plan_id uuid,
  p_expected_plan_revision int,
  p_context_generated_at timestamptz,
  p_context_fingerprint text,
  p_timezone text,
  p_learned_timing_pilot_enabled boolean,
  p_children jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request private.multi_exam_plan_request_identities%rowtype;
  target_plan public.deadline_plans%rowtype;
  child jsonb;
  review jsonb;
  proposal jsonb;
  blocks jsonb;
  child_plan public.deadline_plans%rowtype;
  child_result jsonb;
  child_count int;
  child_base int;
  child_proposed int;
  hidden_block_ids uuid[];
  confirmation_fingerprint text;
  learned_timing_marker text;
  result_plan_id uuid;
  result_revision int;
  changed int;
begin
  perform set_config('lock_timeout', '2s', true);
  if p_user_id is null or p_request_id is null or p_target_plan_id is null
     or p_expected_plan_revision not between 1 and 199
     or p_context_generated_at is null or p_now is null
     or p_context_generated_at > p_now
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_context_fingerprint !~ '^[0-9a-f]{64}$'
     or length(p_timezone) not between 1 and 100
     or p_learned_timing_pilot_enabled is null
     or p_outcome not in ('no_change', 'single_plan', 'multi_exam_batch')
     or jsonb_typeof(p_children) <> 'array' then
    raise exception 'Exam balance proposal arguments are invalid.'
      using errcode = '22023';
  end if;
  child_count := jsonb_array_length(p_children);
  if (p_outcome = 'no_change' and (child_count <> 0 or p_balance_id is not null))
     or (p_outcome = 'single_plan'
       and (child_count <> 1 or p_balance_id is not null))
     or (p_outcome = 'multi_exam_batch'
       and (child_count not between 2 and 8 or p_balance_id is null)) then
    raise exception 'Exam balance outcome and child count disagree.'
      using errcode = '22023';
  end if;

  -- Fixed lock order: owner, outer request, then sorted plan rows.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing_request
  from private.multi_exam_plan_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'proposal'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.target_plan_id <> p_target_plan_id
       or existing_request.expected_plan_revision <> p_expected_plan_revision
       or existing_request.outcome <> p_outcome
       or existing_request.balance_id is distinct from p_balance_id then
      raise exception
        'request_id is already bound to another Exam balance operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'outcome', existing_request.outcome,
      'balance_id', existing_request.balance_id,
      'result_plan_id', existing_request.result_plan_id,
      'result_revision', existing_request.result_revision,
      'result_status', existing_request.result_status
    );
  end if;
  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    raise exception
      'request_id is already bound to another deadline operation.'
      using errcode = 'PT409';
  end if;

  perform 1
  from public.deadline_plans as plan
  where plan.user_id = p_user_id
    and (
      plan.id = p_target_plan_id
      or plan.id in (
        select (value ->> 'plan_id')::uuid
        from jsonb_array_elements(p_children) as children(value)
      )
    )
  order by plan.id
  for update;

  select * into target_plan
  from public.deadline_plans
  where user_id = p_user_id and id = p_target_plan_id;
  if not found or target_plan.status <> 'active' or target_plan.kind <> 'exam' then
    raise exception 'Selected Exam is unavailable.' using errcode = 'PT404';
  end if;
  if target_plan.latest_revision <> p_expected_plan_revision then
    raise exception 'Selected Exam changed. Reload before balancing.'
      using errcode = 'PT409';
  end if;
  if not exists (
    select 1
    from public.profiles as profile
    where profile.id = p_user_id and profile.timezone = p_timezone
  ) then
    raise exception 'Exam balance timezone changed. Reload before balancing.'
      using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.deadline_plan_revisions as pending
    join public.deadline_plans as plan
      on plan.id = pending.plan_id and plan.user_id = pending.user_id
    where pending.user_id = p_user_id
      and plan.status = 'active'
      and pending.state = 'proposed'
  ) then
    raise exception
      'Confirm or discard existing preparation previews before balancing Exams.'
      using errcode = 'PT409';
  end if;
  if private.multi_exam_plan_context_fingerprint_v1(p_user_id)
       <> p_context_fingerprint then
    raise exception 'Exam balance sources changed. Reload before balancing.'
      using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_children) as children(value)
    where value -> 'proposal' -> 'timing_preference' ->> 'source'
            = 'learned_personal_pattern'
      and (
        not p_learned_timing_pilot_enabled
        or not exists (
          select 1
          from public.learning_preferences as preference
          where preference.user_id = p_user_id
            and preference.personal_pattern_analysis_enabled
            and preference.learned_focus_planning_enabled
        )
      )
  ) then
    raise exception
      'Learned Focus timing changed. Reload before balancing.'
      using errcode = 'PT409';
  end if;

  if child_count > 0 and not exists (
    select 1
    from jsonb_array_elements(p_children) as children(value)
    where (value ->> 'plan_id')::uuid = p_target_plan_id
  ) then
    raise exception 'Exam balance must include the selected Exam.'
      using errcode = '22023';
  end if;
  if (
    select count(distinct value ->> 'plan_id')
    from jsonb_array_elements(p_children) as children(value)
  ) <> child_count then
    raise exception 'Exam balance child plans must be unique.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_children) with ordinality
      as children(value, ordinal)
    where jsonb_typeof(value) <> 'object'
      or not (value ?& array[
        'plan_id', 'request_id', 'request_fingerprint',
        'confirm_request_id', 'confirm_request_fingerprint', 'base_revision',
        'proposal', 'blocks', 'review'
      ])
      or (value -> 'review' ->> 'position')::int <> ordinal
      or (value -> 'review' ->> 'plan_id')::uuid
           <> (value ->> 'plan_id')::uuid
      or (value -> 'review' ->> 'base_revision')::int
           <> (value ->> 'base_revision')::int
      or (value -> 'review' ->> 'proposed_revision')::int
           <> (value ->> 'base_revision')::int + 1
      or jsonb_typeof(value -> 'proposal') <> 'object'
      or jsonb_typeof(value -> 'blocks') <> 'array'
      or jsonb_array_length(value -> 'blocks') > 120
      or jsonb_typeof(value -> 'review' -> 'current_blocks') <> 'array'
      or jsonb_typeof(value -> 'review' -> 'proposed_blocks') <> 'array'
      or value -> 'review' -> 'current_blocks'
           = value -> 'review' -> 'proposed_blocks'
      or value -> 'review' -> 'proposed_blocks'
           <> private.multi_exam_plan_proposed_blocks_v1(value -> 'blocks')
      or not private.multi_exam_plan_review_is_valid_v1(value -> 'review')
      or value ->> 'request_fingerprint' !~ '^[0-9a-f]{64}$'
      or value ->> 'confirm_request_fingerprint' !~ '^[0-9a-f]{64}$'
  ) then
    raise exception 'Exam balance child payload is invalid.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_children) with ordinality
      as child_left(value, child_ordinal)
    cross join lateral jsonb_array_elements(value -> 'blocks') with ordinality
      as block_left(value, block_ordinal)
    join lateral jsonb_array_elements(p_children) with ordinality
      as child_right(value, child_ordinal) on true
    cross join lateral jsonb_array_elements(child_right.value -> 'blocks')
      with ordinality as block_right(value, block_ordinal)
    where (child_left.child_ordinal, block_left.block_ordinal)
        < (child_right.child_ordinal, block_right.block_ordinal)
      and tstzrange(
        (block_left.value ->> 'starts_at')::timestamptz,
        (block_left.value ->> 'reserved_ends_at')::timestamptz,
        '[)'
      ) && tstzrange(
        (block_right.value ->> 'starts_at')::timestamptz,
        (block_right.value ->> 'reserved_ends_at')::timestamptz,
        '[)'
      )
  ) then
    raise exception 'Exam balance child reservations overlap.'
      using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_children) as children(value)
    cross join lateral jsonb_array_elements(value -> 'blocks') as block(value)
    where (block.value ->> 'starts_at')::timestamptz <= p_now
      or (block.value ->> 'reserved_ends_at')::timestamptz
           <= (block.value ->> 'starts_at')::timestamptz
  ) then
    raise exception 'Exam balance reservations must still be in the future.'
      using errcode = 'PT409';
  end if;

  for child in
    select value
    from jsonb_array_elements(p_children) with ordinality
      as children(value, ordinal)
    order by ordinal
  loop
    child_base := (child ->> 'base_revision')::int;
    review := child -> 'review';
    proposal := child -> 'proposal';
    blocks := child -> 'blocks';
    select * into child_plan
    from public.deadline_plans
    where user_id = p_user_id and id = (child ->> 'plan_id')::uuid;
    if not found or child_plan.status <> 'active' or child_plan.kind <> 'exam'
       or child_plan.latest_revision <> child_base
       or (proposal ->> 'plan_id')::uuid <> child_plan.id
       or (proposal ->> 'base_revision')::int <> child_base
       or proposal ->> 'kind' <> 'exam'
       or (proposal ->> 'unscheduled_minutes')::int <> 0
       or (review ->> 'active_revision')::int
            <> child_plan.current_revision
       or (review ->> 'base_revision')::int <> child_base
       or (review ->> 'proposed_revision')::int <> child_base + 1 then
      raise exception 'Exam balance child changed. Reload before balancing.'
        using errcode = 'PT409';
    end if;
    if review -> 'current_blocks' <>
      private.multi_exam_plan_current_blocks_v1(
        p_user_id,
        child_plan.id,
        child_plan.current_revision,
        p_context_generated_at
      ) then
      raise exception 'Exam balance current review changed. Reload before balancing.'
        using errcode = 'PT409';
    end if;
  end loop;

  with hidden as (
    update public.deadline_plan_blocks as block
    set reservation_state = 'superseded'
    from public.deadline_plans as plan
    where block.user_id = p_user_id
      and plan.user_id = block.user_id
      and plan.id = block.plan_id
      and block.revision = plan.current_revision
      and block.reservation_state = 'active'
      and block.plan_id in (
        select (value ->> 'plan_id')::uuid
        from jsonb_array_elements(p_children) as children(value)
      )
    returning block.id
  )
  select array_agg(id order by id) into hidden_block_ids from hidden;

  for child in
    select value
    from jsonb_array_elements(p_children) with ordinality
      as children(value, ordinal)
    order by ordinal
  loop
    child_result :=
      public.propose_deadline_plan_with_timing_v1_without_balance_guard(
      p_user_id,
      (child ->> 'request_id')::uuid,
      child ->> 'request_fingerprint',
      (child ->> 'plan_id')::uuid,
      (child ->> 'base_revision')::int,
      child -> 'proposal',
      child -> 'blocks',
      p_now
    );
    if (child_result ->> 'revision')::int
         <> (child ->> 'base_revision')::int + 1 then
      raise exception 'Exam balance child proposal revision is inconsistent.'
        using errcode = 'PT409';
    end if;
    result_plan_id := (child ->> 'plan_id')::uuid;
    result_revision := (child_result ->> 'revision')::int;
  end loop;

  update public.deadline_plan_blocks
  set reservation_state = 'active'
  where id = any(coalesce(hidden_block_ids, array[]::uuid[]));

  if p_outcome = 'multi_exam_batch' then
    confirmation_fingerprint :=
      private.multi_exam_plan_context_fingerprint_v1(p_user_id);
    learned_timing_marker := private.multi_exam_plan_learned_timing_marker_v1(
      p_user_id, p_learned_timing_pilot_enabled
    );
    insert into private.multi_exam_plan_batches (
      id, user_id, status, target_plan_id, created_at, updated_at
    ) values (
      p_balance_id, p_user_id, 'proposed', p_target_plan_id, p_now, p_now
    );
    insert into private.multi_exam_plan_batch_revisions (
      user_id, balance_id, revision, state, context_generated_at,
      context_fingerprint, confirmation_fingerprint, learned_timing_marker,
      timezone, created_at
    ) values (
      p_user_id, p_balance_id, 1, 'proposed', p_context_generated_at,
      p_context_fingerprint, confirmation_fingerprint, learned_timing_marker,
      p_timezone, p_now
    );
    for child in
      select value
      from jsonb_array_elements(p_children) with ordinality
        as children(value, ordinal)
      order by ordinal
    loop
      review := child -> 'review';
      child_proposed := (review ->> 'proposed_revision')::int;
      insert into private.multi_exam_plan_batch_items (
        user_id, balance_id, balance_revision, position, plan_id,
        active_revision, base_revision, proposed_revision,
        retained_minutes, added_minutes, shifted_minutes, removed_minutes,
        review
      ) values (
        p_user_id, p_balance_id, 1, (review ->> 'position')::int,
        (review ->> 'plan_id')::uuid,
        (review ->> 'active_revision')::int,
        (review ->> 'base_revision')::int,
        child_proposed,
        (review ->> 'retained_minutes')::int,
        (review ->> 'added_minutes')::int,
        (review ->> 'shifted_minutes')::int,
        (review ->> 'removed_minutes')::int,
        review
      );
      insert into private.multi_exam_plan_batch_links (
        user_id, plan_id, proposed_revision, balance_id, balance_revision,
        status, confirm_request_id, confirm_request_fingerprint,
        created_at, updated_at
      ) values (
        p_user_id, (review ->> 'plan_id')::uuid, child_proposed,
        p_balance_id, 1, 'proposed',
        (child ->> 'confirm_request_id')::uuid,
        child ->> 'confirm_request_fingerprint', p_now, p_now
      );
    end loop;
    select count(*) into changed
    from private.multi_exam_plan_batch_items
    where user_id = p_user_id and balance_id = p_balance_id
      and balance_revision = 1;
    if changed <> child_count then
      raise exception 'Exam balance did not persist every changed child.'
        using errcode = 'PT409';
    end if;
    result_plan_id := null;
    result_revision := 1;
  elsif p_outcome = 'no_change' then
    result_plan_id := null;
    result_revision := null;
  end if;

  insert into private.multi_exam_plan_request_identities (
    request_id, user_id, operation, request_fingerprint, target_plan_id,
    expected_plan_revision, balance_id, expected_balance_revision, outcome,
    result_plan_id, result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'proposal', p_request_fingerprint,
    p_target_plan_id, p_expected_plan_revision, p_balance_id, null, p_outcome,
    result_plan_id, result_revision,
    case p_outcome when 'no_change' then 'unchanged' else 'proposed' end,
    p_now
  );
  return jsonb_build_object(
    'outcome', p_outcome,
    'balance_id', p_balance_id,
    'result_plan_id', result_plan_id,
    'result_revision', result_revision,
    'result_status',
      case p_outcome when 'no_change' then 'unchanged' else 'proposed' end
  );
end;
$$;

revoke all on function public.propose_multi_exam_plan_v1(
  uuid, text, uuid, uuid, text, uuid, int, timestamptz, text, text, boolean,
  jsonb, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.propose_multi_exam_plan_v1(
  uuid, text, uuid, uuid, text, uuid, int, timestamptz, text, text, boolean,
  jsonb, timestamptz
) to service_role;

create or replace function public.confirm_multi_exam_plan_v1(
  p_user_id uuid,
  p_balance_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_expected_revision int,
  p_learned_timing_pilot_enabled boolean,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request private.multi_exam_plan_request_identities%rowtype;
  batch private.multi_exam_plan_batches%rowtype;
  revision_row private.multi_exam_plan_batch_revisions%rowtype;
  linked record;
  effective_now timestamptz;
  hidden_block_ids uuid[];
  child_result jsonb;
  changed int;
begin
  perform set_config('lock_timeout', '2s', true);
  if p_user_id is null or p_balance_id is null or p_request_id is null
     or p_expected_revision <> 1 or p_now is null
     or p_learned_timing_pilot_enabled is null
     or p_request_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Exam balance confirmation arguments are invalid.'
      using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing_request
  from private.multi_exam_plan_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'confirm'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.balance_id <> p_balance_id
       or existing_request.expected_balance_revision <> p_expected_revision
       or existing_request.result_status <> 'confirmed' then
      raise exception
        'request_id is already bound to another Exam balance operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'outcome', 'multi_exam_batch',
      'balance_id', p_balance_id,
      'result_revision', 1,
      'result_status', 'confirmed'
    );
  end if;
  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    raise exception
      'request_id is already bound to another deadline operation.'
      using errcode = 'PT409';
  end if;

  select * into batch
  from private.multi_exam_plan_batches
  where user_id = p_user_id and id = p_balance_id
  for update;
  if not found then
    raise exception 'Exam balance was not found.' using errcode = 'PT404';
  end if;
  select batch_revision.* into revision_row
  from private.multi_exam_plan_batch_revisions as batch_revision
  where batch_revision.user_id = p_user_id
    and batch_revision.balance_id = p_balance_id
    and batch_revision.revision = p_expected_revision
  for update;
  if batch.status <> 'proposed' or revision_row.state <> 'proposed'
     or batch.current_revision <> p_expected_revision then
    raise exception 'Exam balance is no longer pending.' using errcode = 'PT409';
  end if;
  perform 1
  from public.deadline_plans as plan
  join private.multi_exam_plan_batch_items as item
    on item.plan_id = plan.id and item.user_id = plan.user_id
  where item.user_id = p_user_id
    and item.balance_id = p_balance_id
    and item.balance_revision = p_expected_revision
  order by plan.id
  for update of plan;

  if private.multi_exam_plan_learned_timing_marker_v1(
       p_user_id, p_learned_timing_pilot_enabled
     ) <> revision_row.learned_timing_marker then
    raise exception
      'Learned Focus timing changed. Reload and create a fresh preview.'
      using errcode = 'PT409';
  end if;

  if private.multi_exam_plan_context_fingerprint_v1(p_user_id)
       <> revision_row.confirmation_fingerprint then
    raise exception
      'Exam balance sources changed. Reload and create a fresh preview.'
      using errcode = 'PT409';
  end if;
  effective_now := greatest(p_now, batch.updated_at, revision_row.created_at);
  if exists (
    select 1
    from private.multi_exam_plan_batch_items as item
    join public.deadline_plan_revisions as proposed
      on proposed.user_id = item.user_id
     and proposed.plan_id = item.plan_id
     and proposed.revision = item.proposed_revision
    join public.deadline_plans as plan
      on plan.user_id = item.user_id and plan.id = item.plan_id
    where item.user_id = p_user_id
      and item.balance_id = p_balance_id
      and item.balance_revision = p_expected_revision
      and (
        item.active_revision <> plan.current_revision
        or item.base_revision <> proposed.base_revision
        or item.proposed_revision <> plan.latest_revision
        or proposed.state <> 'proposed'
      )
  ) then
    raise exception
      'An Exam balance child changed. Reload and create a fresh preview.'
      using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from private.multi_exam_plan_batch_items as item
    join public.deadline_plan_blocks as block
      on block.user_id = item.user_id
     and block.plan_id = item.plan_id
     and block.revision = item.proposed_revision
    where item.user_id = p_user_id
      and item.balance_id = p_balance_id
      and item.balance_revision = p_expected_revision
      and (
        block.reservation_state <> 'proposed'
        or block.starts_at <= effective_now
      )
  ) then
    raise exception
      'Exam balance reservations no longer start in the future.'
      using errcode = 'PT409';
  end if;

  with hidden as (
    update public.deadline_plan_blocks as block
    set reservation_state = 'superseded', updated_at = effective_now
    from private.multi_exam_plan_batch_items as item
    where item.user_id = p_user_id
      and item.balance_id = p_balance_id
      and item.balance_revision = p_expected_revision
      and block.user_id = item.user_id
      and block.plan_id = item.plan_id
      and block.revision = item.active_revision
      and block.reservation_state = 'active'
    returning block.id
  )
  select array_agg(id order by id) into hidden_block_ids from hidden;

  for linked in
    select item.position, link.*
    from private.multi_exam_plan_batch_links as link
    join private.multi_exam_plan_batch_items as item
      on item.user_id = link.user_id
     and item.balance_id = link.balance_id
     and item.balance_revision = link.balance_revision
     and item.plan_id = link.plan_id
    where link.user_id = p_user_id
      and link.balance_id = p_balance_id
      and link.balance_revision = p_expected_revision
      and link.status = 'proposed'
    order by item.position
  loop
    child_result :=
      public.confirm_deadline_plan_v1_without_exam_balance_guard(
        p_user_id,
        linked.plan_id,
        linked.confirm_request_id,
        linked.confirm_request_fingerprint,
        linked.proposed_revision,
        effective_now
      );
    if child_result ->> 'status' <> 'active'
       or (child_result ->> 'revision')::int <> linked.proposed_revision then
      raise exception 'Exam balance child confirmation was inconsistent.'
        using errcode = 'PT409';
    end if;
  end loop;

  update private.multi_exam_plan_batch_links
  set status = 'confirmed', updated_at = effective_now
  where user_id = p_user_id and balance_id = p_balance_id
    and balance_revision = p_expected_revision and status = 'proposed';
  get diagnostics changed = row_count;
  if changed not between 2 and 8 then
    raise exception 'Exam balance did not confirm every child.'
      using errcode = 'PT409';
  end if;
  update private.multi_exam_plan_batch_revisions
  set state = 'confirmed', confirmed_at = effective_now
  where user_id = p_user_id and balance_id = p_balance_id
    and revision = p_expected_revision and state = 'proposed';
  update private.multi_exam_plan_batches
  set status = 'confirmed', updated_at = effective_now,
      confirmed_at = effective_now
  where user_id = p_user_id and id = p_balance_id and status = 'proposed';

  insert into private.multi_exam_plan_request_identities (
    request_id, user_id, operation, request_fingerprint, target_plan_id,
    expected_plan_revision, balance_id, expected_balance_revision, outcome,
    result_plan_id, result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'confirm', p_request_fingerprint, null, null,
    p_balance_id, p_expected_revision, 'multi_exam_batch', null, 1,
    'confirmed', effective_now
  );
  return jsonb_build_object(
    'outcome', 'multi_exam_batch',
    'balance_id', p_balance_id,
    'result_revision', 1,
    'result_status', 'confirmed'
  );
end;
$$;

revoke all on function public.confirm_multi_exam_plan_v1(
  uuid, uuid, uuid, text, int, boolean, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.confirm_multi_exam_plan_v1(
  uuid, uuid, uuid, text, int, boolean, timestamptz
) to service_role;

create or replace function public.cancel_multi_exam_plan_v1(
  p_user_id uuid,
  p_balance_id uuid,
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
  existing_request private.multi_exam_plan_request_identities%rowtype;
  batch private.multi_exam_plan_batches%rowtype;
  revision_row private.multi_exam_plan_batch_revisions%rowtype;
  effective_now timestamptz;
  changed int;
begin
  perform set_config('lock_timeout', '2s', true);
  if p_user_id is null or p_balance_id is null or p_request_id is null
     or p_expected_revision <> 1 or p_now is null
     or p_request_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Exam balance cancellation arguments are invalid.'
      using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing_request
  from private.multi_exam_plan_request_identities
  where request_id = p_request_id;
  if found then
    if existing_request.user_id <> p_user_id
       or existing_request.operation <> 'cancel'
       or existing_request.request_fingerprint <> p_request_fingerprint
       or existing_request.balance_id <> p_balance_id
       or existing_request.expected_balance_revision <> p_expected_revision
       or existing_request.result_status <> 'cancelled' then
      raise exception
        'request_id is already bound to another Exam balance operation.'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'outcome', 'multi_exam_batch',
      'balance_id', p_balance_id,
      'result_revision', 1,
      'result_status', 'cancelled'
    );
  end if;
  if exists (
    select 1 from public.deadline_plan_request_identities
    where request_id = p_request_id
  ) then
    raise exception
      'request_id is already bound to another deadline operation.'
      using errcode = 'PT409';
  end if;

  select * into batch
  from private.multi_exam_plan_batches
  where user_id = p_user_id and id = p_balance_id
  for update;
  if not found then
    raise exception 'Exam balance was not found.' using errcode = 'PT404';
  end if;
  select batch_revision.* into revision_row
  from private.multi_exam_plan_batch_revisions as batch_revision
  where batch_revision.user_id = p_user_id
    and batch_revision.balance_id = p_balance_id
    and batch_revision.revision = p_expected_revision
  for update;
  if batch.status <> 'proposed' or revision_row.state <> 'proposed'
     or batch.current_revision <> p_expected_revision then
    raise exception 'Exam balance is no longer pending.' using errcode = 'PT409';
  end if;
  perform 1
  from public.deadline_plans as plan
  join private.multi_exam_plan_batch_items as item
    on item.plan_id = plan.id and item.user_id = plan.user_id
  where item.user_id = p_user_id
    and item.balance_id = p_balance_id
    and item.balance_revision = p_expected_revision
  order by plan.id
  for update of plan;
  effective_now := greatest(p_now, batch.updated_at, revision_row.created_at);

  if exists (
    select 1
    from private.multi_exam_plan_batch_items as item
    join public.deadline_plan_revisions as proposed
      on proposed.user_id = item.user_id
     and proposed.plan_id = item.plan_id
     and proposed.revision = item.proposed_revision
    where item.user_id = p_user_id
      and item.balance_id = p_balance_id
      and item.balance_revision = p_expected_revision
      and proposed.state <> 'proposed'
  ) then
    raise exception 'An Exam balance child is no longer pending.'
      using errcode = 'PT409';
  end if;
  update public.deadline_plan_blocks as block
  set reservation_state = 'superseded', updated_at = effective_now
  from private.multi_exam_plan_batch_items as item
  where item.user_id = p_user_id
    and item.balance_id = p_balance_id
    and item.balance_revision = p_expected_revision
    and block.user_id = item.user_id
    and block.plan_id = item.plan_id
    and block.revision = item.proposed_revision
    and block.reservation_state = 'proposed';
  update public.deadline_plan_revisions as proposed
  set state = 'superseded', superseded_at = effective_now
  from private.multi_exam_plan_batch_items as item
  where item.user_id = p_user_id
    and item.balance_id = p_balance_id
    and item.balance_revision = p_expected_revision
    and proposed.user_id = item.user_id
    and proposed.plan_id = item.plan_id
    and proposed.revision = item.proposed_revision
    and proposed.state = 'proposed';
  get diagnostics changed = row_count;
  if changed not between 2 and 8 then
    raise exception 'Exam balance did not discard every child.'
      using errcode = 'PT409';
  end if;
  update private.multi_exam_plan_batch_links
  set status = 'cancelled', updated_at = effective_now
  where user_id = p_user_id and balance_id = p_balance_id
    and balance_revision = p_expected_revision and status = 'proposed';
  update private.multi_exam_plan_batch_revisions
  set state = 'cancelled', cancelled_at = effective_now
  where user_id = p_user_id and balance_id = p_balance_id
    and revision = p_expected_revision and state = 'proposed';
  update private.multi_exam_plan_batches
  set status = 'cancelled', updated_at = effective_now,
      cancelled_at = effective_now
  where user_id = p_user_id and id = p_balance_id and status = 'proposed';

  insert into private.multi_exam_plan_request_identities (
    request_id, user_id, operation, request_fingerprint, target_plan_id,
    expected_plan_revision, balance_id, expected_balance_revision, outcome,
    result_plan_id, result_revision, result_status, created_at
  ) values (
    p_request_id, p_user_id, 'cancel', p_request_fingerprint, null, null,
    p_balance_id, p_expected_revision, 'multi_exam_batch', null, 1,
    'cancelled', effective_now
  );
  return jsonb_build_object(
    'outcome', 'multi_exam_batch',
    'balance_id', p_balance_id,
    'result_revision', 1,
    'result_status', 'cancelled'
  );
end;
$$;

revoke all on function public.cancel_multi_exam_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.cancel_multi_exam_plan_v1(
  uuid, uuid, uuid, text, int, timestamptz
) to service_role;
