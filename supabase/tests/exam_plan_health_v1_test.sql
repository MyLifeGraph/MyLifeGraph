begin;
select no_plan();

select ok(
  has_function_privilege(
    'service_role',
    'public.get_exam_plan_health_snapshot_v1(uuid,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.get_exam_plan_health_snapshot_v1(uuid,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_exam_plan_health_snapshot_v1(uuid,timestamp with time zone)',
    'execute'
  ),
  'only service_role can execute the Exam Plan Health snapshot'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e4000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'exam-health@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')),
  '2026-08-01T08:00:00Z',
  '{"provider":"email","providers":["email"]}', '{}',
  '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
);

update public.profiles
set timezone = 'UTC', timezone_revision = 2,
    daily_preparation_budget_minutes = 120
where id = 'e4000000-0000-4000-8000-000000000001';

select set_config('mylifegraph.deadline_plan_rpc', 'on', true);

insert into public.tasks (id, user_id, title, status, source)
values (
  'e4000000-0000-4000-8000-000000000010',
  'e4000000-0000-4000-8000-000000000001',
  'Prepare analysis', 'todo', 'deadline-plan-v1'
);

insert into public.deadline_plans (
  id, user_id, status, kind, title, managed_task_id,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, first_activated_at, created_at, updated_at
) values (
  'e4000000-0000-4000-8000-000000000010',
  'e4000000-0000-4000-8000-000000000001',
  'active', 'exam', 'Prepare analysis',
  'e4000000-0000-4000-8000-000000000010',
  300, 0, 1, 1, '2026-08-01T08:00:00Z',
  '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
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
  'e4000000-0000-4000-8000-000000000011',
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000010',
  1, 0, 'active', 'exam', 'Prepare analysis',
  '2026-09-10T18:00:00Z', 300, 0, 120, 120, '2026-08-13',
  2, 'manual', false, 'UTC', 'morning', repeat('4', 64),
  0, 300, 120, 180, '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
);

insert into public.deadline_plan_blocks (
  id, user_id, plan_id, revision, sequence, reservation_state,
  starts_at, ends_at, local_date, local_start_time, local_end_time,
  planned_minutes, recovery_minutes, reserved_ends_at, created_at, updated_at
) values (
  'e4000000-0000-4000-8000-000000000012',
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000010',
  1, 1, 'active', '2026-08-20T09:00:00Z', '2026-08-20T11:00:00Z',
  '2026-08-20', '09:00:00', '11:00:00', 120, 0,
  '2026-08-20T11:00:00Z', '2026-08-01T08:00:00Z',
  '2026-08-01T08:00:00Z'
);

insert into public.focus_sessions (
  id, user_id, started_at, ended_at, planned_minutes, actual_minutes,
  label, metadata, status, task_id, updated_at
) values (
  'e4000000-0000-4000-8000-000000000013',
  'e4000000-0000-4000-8000-000000000001',
  '2026-08-10T09:00:00Z', '2026-08-10T09:17:00Z', 25, 17,
  'Analysis', '{"entry_date":"2026-08-10"}', 'completed',
  'e4000000-0000-4000-8000-000000000010', '2026-08-10T09:17:00Z'
);

insert into public.focus_session_schedule_sources (
  focus_session_id, user_id, source_kind, deadline_plan_block_id,
  original_starts_at, original_ends_at, original_recovery_minutes, created_at
) values (
  'e4000000-0000-4000-8000-000000000013',
  'e4000000-0000-4000-8000-000000000001',
  'deadline_plan_block', 'e4000000-0000-4000-8000-000000000012',
  '2026-08-20T09:00:00Z', '2026-08-20T11:00:00Z', 0,
  '2026-08-10T09:00:00Z'
);

-- A second otherwise-active Exam lies just beyond the inclusive 366-day
-- local horizon and must not leak through the adjacent DST overlap anchor.
insert into public.tasks (id, user_id, title, status, source)
values (
  'e4000000-0000-4000-8000-000000000020',
  'e4000000-0000-4000-8000-000000000001',
  'Far future exam', 'todo', 'deadline-plan-v1'
);

insert into public.deadline_plans (
  id, user_id, status, kind, title, managed_task_id,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, first_activated_at, created_at, updated_at
) values (
  'e4000000-0000-4000-8000-000000000020',
  'e4000000-0000-4000-8000-000000000001',
  'active', 'exam', 'Far future exam',
  'e4000000-0000-4000-8000-000000000020',
  300, 0, 1, 1, '2026-08-01T08:00:00Z',
  '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
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
  'e4000000-0000-4000-8000-000000000021',
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000020',
  1, 0, 'active', 'exam', 'Far future exam',
  '2027-08-15T18:00:00Z', 300, 0, 120, 120, '2026-08-13',
  2, 'manual', false, 'UTC', 'morning', repeat('5', 64),
  0, 300, 0, 300, '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
);

set local role service_role;
select is(
  jsonb_array_length(
    public.get_exam_plan_health_snapshot_v1(
      'e4000000-0000-4000-8000-000000000001',
      '2026-08-13T08:00:00Z'
    ) -> 'exams'
  ),
  1,
  'the snapshot includes active Exams only through the inclusive 366-day horizon'
);
select is(
  (
    public.get_exam_plan_health_snapshot_v1(
      'e4000000-0000-4000-8000-000000000001',
      '2026-08-13T08:00:00Z'
    ) -> 'focus_totals' -> 0 ->> 'actual_minutes'
  )::int,
  17,
  'the snapshot credits completed Focus actual minutes exactly once'
);
select is(
  public.get_exam_plan_health_snapshot_v1(
    'e4000000-0000-4000-8000-000000000001',
    '2026-08-13T08:00:00Z'
  ) -> 'focus_facts' -> 0 ->> 'deadline_plan_block_id',
  'e4000000-0000-4000-8000-000000000012',
  'the snapshot preserves exact scheduled-block Focus provenance'
);
select is(
  jsonb_array_length(
    public.get_exam_plan_health_snapshot_v1(
      'e4000000-0000-4000-8000-000000000001',
      '2026-08-13T08:00:00Z'
    ) -> 'deadline_blocks'
  ),
  1,
  'the same statement contains the complete confirmed consumer block'
);
reset role;

set local role authenticated;
select throws_ok(
  $$
    select public.get_exam_plan_health_snapshot_v1(
      'e4000000-0000-4000-8000-000000000001',
      '2026-08-13T08:00:00Z'
    )
  $$,
  '42501',
  'permission denied for function get_exam_plan_health_snapshot_v1',
  'authenticated clients cannot call the backend snapshot directly'
);
reset role;

select * from finish();
rollback;
