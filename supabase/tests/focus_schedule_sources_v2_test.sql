begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  'f2000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'focus-v2-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f2000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'focus-v2-other@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.tasks (id, user_id, title, status, source)
values (
  'f2000000-0000-4000-8000-000000000010',
  'f2000000-0000-4000-8000-000000000001',
  'Review calculus', 'todo', 'manual'
);

insert into public.planner_action_plans (
  id, user_id, target_kind, target_id, status, current_revision,
  latest_revision, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000020',
  'f2000000-0000-4000-8000-000000000001',
  'task', 'f2000000-0000-4000-8000-000000000010',
  'active', 1, 1, '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);

insert into public.planner_action_plan_revisions (
  id, user_id, plan_id, revision, base_revision, state, target_payload,
  timezone, best_energy_window, planning_start_on, planning_fingerprint,
  planned_minutes, unscheduled_minutes, created_at, activated_at,
  study_setup_revision, recovery_minutes, timezone_revision
) values (
  'f2000000-0000-4000-8000-000000000021',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000020', 1, 0, 'active',
  '{"kind":"task","operation":"update"}',
  'UTC', 'morning', '2026-08-01', repeat('1', 64),
  30, 0, '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z',
  1, 10, 1
);

insert into public.planner_task_blocks (
  id, user_id, plan_id, revision, sequence, state, starts_at, ends_at,
  reserved_ends_at, local_date, planned_minutes, recovery_minutes,
  created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000030',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000020', 1, 1, 'active',
  '2026-08-01T06:00:00Z', '2026-08-01T06:30:00Z',
  '2026-08-01T06:40:00Z', '2026-08-01', 30, 10,
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);

select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class where oid = 'public.focus_session_schedule_sources'::regclass
  ),
  'schedule-source provenance has enabled and forced RLS'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.focus_session_schedule_sources', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.focus_session_schedule_sources', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.focus_session_schedule_sources', 'update'
  )
  and not has_table_privilege(
    'authenticated', 'public.focus_session_schedule_sources', 'delete'
  ),
  'authenticated clients can only read schedule-source provenance'
);
select is(
  (
    select count(*)::int from pg_indexes
    where schemaname = 'public'
      and tablename = 'focus_session_schedule_sources'
  ),
  5,
  'the primary/composite keys plus owner and both source indexes exist'
);
select is(
  private.focus_resolve_local_instant_v2(
    '2026-03-29 02:30:00', 'Europe/Berlin'
  ),
  null::timestamptz,
  'a DST gap fails closed instead of inventing a UTC instant'
);
select is(
  private.focus_resolve_local_instant_v2(
    '2026-10-25 02:30:00', 'Europe/Berlin'
  ),
  null::timestamptz,
  'a one-hour DST fold fails closed'
);
select is(
  private.focus_resolve_local_instant_v2(
    '2026-04-05 01:45:00', 'Australia/Lord_Howe'
  ),
  null::timestamptz,
  'a non-hour DST fold also fails closed'
);
select is(
  private.focus_resolve_local_instant_v2(
    '2026-04-05 03:00:00', 'Australia/Lord_Howe'
  ),
  '2026-04-04 16:30:00+00'::timestamptz,
  'an unambiguous local instant still resolves exactly'
);

set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T08:00:00Z'
  ) ->> 'source_state',
  'missed',
  'a past active Planner Task block is eligible as missed'
);
select is(
  (
    public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000001',
      'planner_task_block',
      'f2000000-0000-4000-8000-000000000030',
      '2026-08-02T08:00:00Z'
    ) ->> 'can_start'
  )::boolean,
  true,
  'the selected source excludes its own old reservation from collisions'
);
select throws_ok(
  $$
    select public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000002',
      'planner_task_block',
      'f2000000-0000-4000-8000-000000000030',
      '2026-08-02T08:00:00Z'
    )
  $$,
  'PT404',
  'Scheduled Focus source is unavailable.',
  'another owner cannot resolve the block context'
);

select is(
  public.start_focus_session_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000040', repeat('2', 64),
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    20, 0, null, null, null, '2026-08-02T08:00:00Z'
  ) ->> 'started_at',
  '2026-08-02T08:00:00+00:00',
  'scheduled start records the actual server instant, not the old plan instant'
);
select is(
  (
    public.start_focus_session_v2(
      'f2000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000040', repeat('2', 64),
      'planner_task_block',
      'f2000000-0000-4000-8000-000000000030',
      20, 0, null, null, null, '2026-08-02T08:01:00Z'
    ) ->> 'replayed'
  )::boolean,
  true,
  'an exact request replay returns the existing session'
);
select throws_ok(
  $$
    select public.start_focus_session_v2(
      'f2000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000040', repeat('3', 64),
      'planner_task_block',
      'f2000000-0000-4000-8000-000000000030',
      20, 0, null, null, null, '2026-08-02T08:01:00Z'
    )
  $$,
  'PT409',
  'focus_request_conflict',
  'a request id cannot be rebound to different content'
);
select throws_ok(
  $$
    select public.start_focus_session_v2(
      'f2000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000041', repeat('9', 64),
      'manual', null, 25, 0, null, null, 'Independent focus block',
      '2026-08-02T08:02:00Z'
    )
  $$,
  'PT409',
  'active_focus_session',
  'a different manual request receives a stable active-session conflict'
);
select is(
  (
    select row(
      source_kind, planner_task_block_id, original_starts_at,
      original_ends_at, original_recovery_minutes
    )::text
    from public.focus_session_schedule_sources
    where focus_session_id = 'f2000000-0000-4000-8000-000000000040'
  ),
  '(planner_task_block,f2000000-0000-4000-8000-000000000030,"2026-08-01 06:00:00+00","2026-08-01 06:30:00+00",10)',
  'the immutable source row snapshots the original block and recovery'
);
select throws_ok(
  $$
    update public.focus_session_schedule_sources
    set original_recovery_minutes = 0
    where focus_session_id = 'f2000000-0000-4000-8000-000000000040'
  $$,
  '42501',
  null,
  'service role has no direct provenance update authority'
);
reset role;
select throws_ok(
  $$
    update public.focus_session_schedule_sources
    set original_recovery_minutes = 0
    where focus_session_id = 'f2000000-0000-4000-8000-000000000040'
  $$,
  '23514',
  'Focus schedule source provenance is immutable.',
  'the database rejects provenance mutation even for a table owner'
);
select throws_ok(
  $$
    delete from public.planner_task_blocks
    where id = 'f2000000-0000-4000-8000-000000000030'
  $$,
  '23503',
  null,
  'source block deletion is restricted while Focus provenance exists'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'f2000000-0000-4000-8000-000000000001';
select is(
  (select count(*)::int from public.focus_session_schedule_sources), 1,
  'RLS exposes the provenance row to its owner'
);
set local request.jwt.claim.sub =
  'f2000000-0000-4000-8000-000000000002';
select is(
  (select count(*)::int from public.focus_session_schedule_sources), 0,
  'RLS hides provenance from another owner'
);
reset role;

set local role service_role;
select is(
  public.finish_focus_session_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000040',
    'completed', '2026-08-02T08:17:59Z'
  ) ->> 'actual_minutes',
  '17',
  'terminal writes derive actual minutes from server timestamps'
);
select is(
  (
    public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000001',
      'planner_task_block',
      'f2000000-0000-4000-8000-000000000030',
      '2026-08-02T10:00:00Z'
    ) ->> 'remaining_minutes'
  )::int,
  13,
  'completed source-linked actual time leaves exact block capacity'
);
reset role;

set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  null::text,
  'the source is startable before additional collision fixtures exist'
);
reset role;

insert into public.schedule_items (
  id, user_id, title, weekday, starts_at, ends_at, source, metadata
) values (
  'f2000000-0000-4000-8000-000000000070',
  'f2000000-0000-4000-8000-000000000001',
  'Setup collision', 7, '10:10', '10:20', 'manual', '{}'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'recurring_commitment',
  'Focus plus recovery collides with a Setup timetable item'
);
reset role;
delete from public.schedule_items
where id = 'f2000000-0000-4000-8000-000000000070';

insert into public.planner_commitments (
  id, user_id, title, recurrence, status, weekday,
  local_starts_at, local_ends_at, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000071',
  'f2000000-0000-4000-8000-000000000001',
  'Weekly collision', 'weekly', 'active', 7, '10:10', '10:20',
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'recurring_commitment',
  'Focus plus recovery collides with a weekly Planner commitment'
);
reset role;
delete from public.planner_commitments
where id = 'f2000000-0000-4000-8000-000000000071';

insert into public.planner_habit_slots (
  id, user_id, plan_id, revision, weekday, starts_at, ends_at,
  duration_minutes, state, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000072',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000020', 1, 7,
  '10:10', '10:20', 10, 'active',
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'recurring_commitment',
  'Focus plus recovery collides with an active Habit reservation'
);
reset role;
delete from public.planner_habit_slots
where id = 'f2000000-0000-4000-8000-000000000072';

insert into public.planner_task_blocks (
  id, user_id, plan_id, revision, sequence, state, starts_at, ends_at,
  reserved_ends_at, local_date, planned_minutes, recovery_minutes,
  created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000073',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000020', 1, 2, 'active',
  '2026-08-02T10:10:00Z', '2026-08-02T10:20:00Z',
  '2026-08-02T10:20:00Z', '2026-08-02', 10, 0,
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'planner_task_block',
  'only the chosen Planner source is excluded from Task-block collisions'
);
reset role;
delete from public.planner_task_blocks
where id = 'f2000000-0000-4000-8000-000000000073';

insert into public.tasks (id, user_id, title, status, source)
values (
  'f2000000-0000-4000-8000-000000000060',
  'f2000000-0000-4000-8000-000000000001',
  'Prepare assignment', 'todo', 'manual'
);
insert into public.deadline_plans (
  id, user_id, status, kind, title, managed_task_id,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, first_activated_at, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000060',
  'f2000000-0000-4000-8000-000000000001',
  'active', 'assignment', 'Prepare assignment',
  'f2000000-0000-4000-8000-000000000060',
  30, 0, 1, 1, '2026-07-31T07:00:00Z',
  '2026-07-31T07:00:00Z', '2026-07-31T07:00:00Z'
);
insert into public.deadline_plan_revisions (
  id, user_id, plan_id, revision, base_revision, state, kind, title,
  deadline_at, estimated_total_minutes, credited_prior_minutes,
  preferred_session_minutes, max_daily_minutes, planning_start_on,
  buffer_days, source_kind, use_calendar_availability, timezone,
  best_energy_window, planning_fingerprint,
  tracked_focus_minutes_at_proposal, remaining_minutes_at_proposal,
  planned_minutes, unscheduled_minutes, created_at, activated_at
) values (
  'f2000000-0000-4000-8000-000000000061',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000060',
  1, 0, 'active', 'assignment', 'Prepare assignment',
  '2026-08-10T12:00:00Z', 30, 0, 30, 120, '2026-08-01',
  0, 'manual', false, 'UTC', 'morning', repeat('4', 64),
  0, 30, 30, 0, '2026-07-31T07:00:00Z', '2026-07-31T07:00:00Z'
);
insert into public.deadline_plan_blocks (
  id, user_id, plan_id, revision, sequence, reservation_state,
  starts_at, ends_at, local_date, local_start_time, local_end_time,
  planned_minutes, recovery_minutes, reserved_ends_at, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000062',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000060',
  1, 1, 'active', '2026-08-01T07:00:00Z', '2026-08-01T07:30:00Z',
  '2026-08-01', '07:00:00', '07:30:00', 30, 0,
  '2026-08-01T07:30:00Z', '2026-07-31T07:00:00Z',
  '2026-07-31T07:00:00Z'
);

insert into public.deadline_plan_blocks (
  id, user_id, plan_id, revision, sequence, reservation_state,
  starts_at, ends_at, local_date, local_start_time, local_end_time,
  planned_minutes, recovery_minutes, reserved_ends_at, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000064',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000060',
  1, 2, 'active', '2026-08-02T10:10:00Z', '2026-08-02T10:20:00Z',
  '2026-08-02', '10:10:00', '10:20:00', 10, 0,
  '2026-08-02T10:20:00Z', '2026-07-31T07:00:00Z',
  '2026-07-31T07:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'deadline_plan_block',
  'Focus plus recovery collides with another active Preparation block'
);
reset role;
delete from public.deadline_plan_blocks
where id = 'f2000000-0000-4000-8000-000000000064';

set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'deadline_plan_block',
    'f2000000-0000-4000-8000-000000000062',
    '2026-08-02T11:00:00Z'
  ) ->> 'source_state',
  'missed',
  'a past active Preparation block is eligible as missed'
);
select is(
  (
    public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000001',
      'deadline_plan_block',
      'f2000000-0000-4000-8000-000000000062',
      '2026-08-02T11:00:00Z'
    ) ->> 'can_start'
  )::boolean,
  true,
  'the missed Preparation source excludes its own old reservation'
);
select is(
  public.start_focus_session_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000063', repeat('5', 64),
    'deadline_plan_block',
    'f2000000-0000-4000-8000-000000000062',
    10, 0, null, null, null, '2026-08-02T11:00:00Z'
  ) ->> 'started_at',
  '2026-08-02T11:00:00+00:00',
  'a missed Preparation start persists its actual server instant'
);
select is(
  public.finish_focus_session_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000063',
    'completed', '2026-08-02T11:06:00Z'
  ) ->> 'actual_minutes',
  '6',
  'the completed make-up session records actual elapsed minutes'
);
select is(
  (
    public.finish_focus_session_v2(
      'f2000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000063',
      'completed', '2026-08-02T11:07:00Z'
    ) ->> 'replayed'
  )::boolean,
  true,
  'an exact terminal replay reuses the completed make-up session'
);
select is(
  (
    public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000001',
      'deadline_plan_block',
      'f2000000-0000-4000-8000-000000000062',
      '2026-08-02T12:00:00Z'
    ) ->> 'remaining_minutes'
  )::int,
  24,
  'source-linked make-up minutes credit the selected Preparation block exactly once'
);
select is(
  public.get_deadline_plan_projection_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000060'
  ) -> 'focus_facts' -> 0 ->> 'deadline_plan_block_id',
  'f2000000-0000-4000-8000-000000000062',
  'the internal Deadline projection exposes the exact source-linked Focus fact'
);
reset role;

insert into public.tasks (id, user_id, title, status, source)
values (
  'f2000000-0000-4000-8000-000000000090',
  'f2000000-0000-4000-8000-000000000001',
  'Prepare future exam', 'todo', 'manual'
);
insert into public.deadline_plans (
  id, user_id, status, kind, title, managed_task_id,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, first_activated_at, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000090',
  'f2000000-0000-4000-8000-000000000001',
  'active', 'exam', 'Prepare future exam',
  'f2000000-0000-4000-8000-000000000090',
  30, 0, 1, 1, '2026-07-31T07:00:00Z',
  '2026-07-31T07:00:00Z', '2026-07-31T07:00:00Z'
);
insert into public.deadline_plan_revisions (
  id, user_id, plan_id, revision, base_revision, state, kind, title,
  deadline_at, estimated_total_minutes, credited_prior_minutes,
  preferred_session_minutes, max_daily_minutes, planning_start_on,
  buffer_days, source_kind, use_calendar_availability, timezone,
  best_energy_window, planning_fingerprint,
  tracked_focus_minutes_at_proposal, remaining_minutes_at_proposal,
  planned_minutes, unscheduled_minutes, created_at, activated_at
) values (
  'f2000000-0000-4000-8000-000000000091',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000090',
  1, 0, 'active', 'exam', 'Prepare future exam',
  '2026-08-10T12:00:00Z', 30, 0, 25, 120, '2026-08-01',
  0, 'manual', false, 'UTC', 'morning', repeat('6', 64),
  0, 30, 20, 10, '2026-07-31T07:00:00Z', '2026-07-31T07:00:00Z'
);
insert into public.deadline_plan_blocks (
  id, user_id, plan_id, revision, sequence, reservation_state,
  starts_at, ends_at, local_date, local_start_time, local_end_time,
  planned_minutes, recovery_minutes, reserved_ends_at, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000092',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000090',
  1, 1, 'active', '2026-08-05T07:00:00Z', '2026-08-05T07:20:00Z',
  '2026-08-05', '07:00:00', '07:20:00', 20, 0,
  '2026-08-05T07:20:00Z', '2026-07-31T07:00:00Z',
  '2026-07-31T07:00:00Z'
);

set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'deadline_plan_block',
    'f2000000-0000-4000-8000-000000000092',
    '2026-08-02T13:00:00Z'
  ) ->> 'source_state',
  'upcoming',
  'a future active Preparation block remains startable as upcoming'
);
select is(
  public.start_focus_session_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000093', repeat('7', 64),
    'deadline_plan_block',
    'f2000000-0000-4000-8000-000000000092',
    20, 0, null, null, null, '2026-08-02T13:00:00Z'
  ) ->> 'started_at',
  '2026-08-02T13:00:00+00:00',
  'a future Preparation start persists the actual server instant'
);
select is(
  (
    public.start_focus_session_v2(
      'f2000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000093', repeat('7', 64),
      'deadline_plan_block',
      'f2000000-0000-4000-8000-000000000092',
      20, 0, null, null, null, '2026-08-02T13:01:00Z'
    ) ->> 'replayed'
  )::boolean,
  true,
  'an exact future-source start replay reuses the same Focus session'
);
select is(
  (
    select row(
      original_starts_at, original_ends_at, original_recovery_minutes
    )::text
    from public.focus_session_schedule_sources
    where focus_session_id = 'f2000000-0000-4000-8000-000000000093'
  ),
  '("2026-08-05 07:00:00+00","2026-08-05 07:20:00+00",0)',
  'the future source origin remains its immutable planned interval'
);
select is(
  public.finish_focus_session_v2(
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000093',
    'completed', '2026-08-02T13:08:00Z'
  ) ->> 'actual_minutes',
  '8',
  'future-source completion records actual elapsed minutes'
);
select is(
  (
    public.finish_focus_session_v2(
      'f2000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000093',
      'completed', '2026-08-02T13:09:00Z'
    ) ->> 'replayed'
  )::boolean,
  true,
  'an exact future-source terminal replay is idempotent'
);
select is(
  (
    public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000001',
      'deadline_plan_block',
      'f2000000-0000-4000-8000-000000000092',
      '2026-08-02T14:00:00Z'
    ) ->> 'remaining_minutes'
  )::int,
  12,
  'future-source actual minutes reduce the selected block exactly once'
);
select is(
  (
    select count(*)::int
    from public.focus_session_schedule_sources
    where deadline_plan_block_id = 'f2000000-0000-4000-8000-000000000092'
  ),
  1,
  'start and finish replays leave one immutable future-source association'
);
reset role;

insert into public.planner_preferences (
  user_id, use_calendar_busy_time, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000001', true,
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'calendar_availability_unavailable',
  'enabled Calendar busy time fails closed without a current projection'
);
reset role;

insert into public.calendar_connections (
  id, user_id, create_request_id, create_request_fingerprint, source_label,
  consent_version, read_calendar_events, store_event_basics,
  provider_writes, llm_processing, consented_at, connected_at
) values (
  'f2000000-0000-4000-8000-000000000080',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000081', repeat('a', 64),
  'Focus test calendar', 'calendar-import-consent-v1', true, true,
  false, false, '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
insert into public.calendar_imports (
  id, user_id, connection_id, request_id, request_fingerprint,
  input_fingerprint, source_fingerprint, window_starts_on,
  window_ends_before, timezone, accepted_count, cancelled_count,
  out_of_window_count, unsupported_recurring_count, invalid_count,
  imported_at, profile_timezone_revision, planning_status
) select
  'f2000000-0000-4000-8000-000000000082',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000080',
  'f2000000-0000-4000-8000-000000000083', repeat('b', 64),
  repeat('c', 64), repeat('d', 64), '2026-07-01', '2026-10-14',
  'UTC', 1, 0, 0, 0, 0, '2026-08-01T06:00:00Z',
  timezone_revision, 'current'
from public.profiles
where id = 'f2000000-0000-4000-8000-000000000001';
update public.calendar_connections
set last_import_id = 'f2000000-0000-4000-8000-000000000082'
where id = 'f2000000-0000-4000-8000-000000000080';

insert into public.calendar_events (
  id, user_id, connection_id, import_id, source_event_key,
  source_fingerprint, title, event_kind, busy_status, event_status,
  event_timezone, timezone_source, starts_at, ends_at,
  local_starts_at, local_ends_at, sort_date, sort_time,
  imported_at, last_seen_at
) values (
  'f2000000-0000-4000-8000-000000000084',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000080',
  'f2000000-0000-4000-8000-000000000082', repeat('e', 64), repeat('f', 64),
  'Busy timed event', 'timed', 'busy', 'confirmed', 'UTC', 'utc',
  '2026-08-02T10:10:00Z', '2026-08-02T10:20:00Z',
  '2026-08-02 10:10:00', '2026-08-02 10:20:00',
  '2026-08-02', '10:10', '2026-08-01T06:00:00Z',
  '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'calendar_busy',
  'Focus plus recovery collides with current timed Calendar busy time'
);
reset role;
delete from public.calendar_events
where id = 'f2000000-0000-4000-8000-000000000084';

insert into public.calendar_events (
  id, user_id, connection_id, import_id, source_event_key,
  source_fingerprint, title, event_kind, busy_status, event_status,
  event_timezone, timezone_source, starts_on, ends_on, sort_date, sort_time,
  imported_at, last_seen_at
) values (
  'f2000000-0000-4000-8000-000000000085',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000080',
  'f2000000-0000-4000-8000-000000000082', repeat('1', 64), repeat('2', 64),
  'Busy all-day event', 'all_day', 'busy', 'confirmed', 'UTC', 'profile',
  '2026-08-02', '2026-08-03', '2026-08-02', '00:00',
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'calendar_busy',
  'an all-day Calendar busy event blocks the local profile date'
);
reset role;
update public.calendar_imports
set planning_status = 'profile_timezone_changed'
where id = 'f2000000-0000-4000-8000-000000000082';
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'calendar_availability_unavailable',
  'a stale Calendar projection fails closed even when stored events remain'
);
reset role;
update public.planner_preferences
set use_calendar_busy_time = false
where user_id = 'f2000000-0000-4000-8000-000000000001';

insert into public.planner_commitments (
  id, user_id, title, recurrence, status, starts_at, ends_at,
  created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000050',
  'f2000000-0000-4000-8000-000000000001',
  'Fixed appointment', 'one_off', 'active',
  '2026-08-02T10:05:00Z', '2026-08-02T10:20:00Z',
  '2026-08-01T06:00:00Z', '2026-08-01T06:00:00Z'
);
set local role service_role;
select is(
  public.get_focus_start_context_v2(
    'f2000000-0000-4000-8000-000000000001',
    'planner_task_block',
    'f2000000-0000-4000-8000-000000000030',
    '2026-08-02T10:00:00Z'
  ) ->> 'blocking_reason',
  'fixed_commitment',
  'recovery overlap with a fixed commitment blocks the scheduled start'
);
select is(
  (
    public.get_focus_start_context_v2(
      'f2000000-0000-4000-8000-000000000001',
      'planner_task_block',
      'f2000000-0000-4000-8000-000000000030',
      '2026-08-02T10:20:00Z'
    ) ->> 'can_start'
  )::boolean,
  true,
  'a directly adjacent half-open interval remains startable'
);
select is(
  (
    public.delete_account_v1(
      'f2000000-0000-4000-8000-000000000001', 'DELETE'
    ) ->> 'deleted'
  )::boolean,
  true,
  'account deletion removes Focus history before restricted source blocks'
);
reset role;
select is(
  (
    select count(*)::int from public.focus_session_schedule_sources
    where user_id = 'f2000000-0000-4000-8000-000000000001'
  ),
  0,
  'account deletion leaves no schedule-source provenance'
);

select * from finish();
rollback;
