begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'd1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'deadline-kind-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

update public.profiles
set timezone = 'Europe/Berlin'
where id = 'd1000000-0000-4000-8000-000000000001';

select ok(
  has_function_privilege(
    'service_role',
    'public.propose_deadline_plan_with_timing_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.propose_deadline_plan_with_timing_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.propose_deadline_plan_with_timing_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  ),
  'only service_role can execute the public guarded proposal RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.propose_deadline_plan_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.propose_deadline_plan_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.propose_deadline_plan_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  ),
  'no application role can execute the unguarded base proposal RPC'
);
set local role service_role;
select throws_ok(
  $$
    select public.propose_deadline_plan_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000009', repeat('0', 64),
      'd1000000-0000-4000-8000-000000000010', 1,
      '{}'::jsonb, '[]'::jsonb, '2026-08-12T09:00:00Z'
    )
  $$,
  '42501',
  'permission denied for function propose_deadline_plan_v1',
  'service_role cannot bypass the guarded timing proposal RPC'
);
reset role;
select ok(
  to_regprocedure(
    'public.propose_deadline_plan_with_timing_v1_without_kind_guard(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)'
  ) is not null,
  'the prior proposal implementation remains available to the wrapper'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.propose_deadline_plan_with_timing_v1_without_kind_guard(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.propose_deadline_plan_with_timing_v1_without_kind_guard(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.propose_deadline_plan_with_timing_v1_without_kind_guard(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)',
    'execute'
  ),
  'the renamed inner proposal implementation is not an application RPC'
);

insert into public.deadline_plans (
  id, user_id, status, kind, title,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, created_at, updated_at
) values (
  'd1000000-0000-4000-8000-000000000010',
  'd1000000-0000-4000-8000-000000000001',
  'draft', 'exam', 'Draft exam', 60, 0, 0, 1,
  '2026-08-12T08:00:00Z', '2026-08-12T08:00:00Z'
);

insert into public.deadline_plans (
  id, user_id, status, kind, title, managed_task_id,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, first_activated_at, created_at, updated_at
) values (
  'd1000000-0000-4000-8000-000000000020',
  'd1000000-0000-4000-8000-000000000001',
  'active', 'assignment', 'Active assignment',
  'd1000000-0000-4000-8000-000000000020',
  60, 0, 1, 1, '2026-08-12T08:00:00Z',
  '2026-08-12T08:00:00Z', '2026-08-12T08:00:00Z'
);

set local role service_role;
select throws_ok(
  $$
    select public.propose_deadline_plan_with_timing_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000011', repeat('1', 64),
      'd1000000-0000-4000-8000-000000000010', 1,
      '{"kind":"assignment","timing_preference":{"source":"setup"}}',
      '[]', '2026-08-12T09:00:00Z'
    )
  $$,
  'PT409',
  'Deadline plan kind cannot be changed.',
  'a draft Exam rejects an Assignment proposal at the final RPC boundary'
);
select throws_ok(
  $$
    select public.propose_deadline_plan_with_timing_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000021', repeat('2', 64),
      'd1000000-0000-4000-8000-000000000020', 1,
      '{"kind":"exam","timing_preference":{"source":"setup"}}',
      '[]', '2026-08-12T09:00:00Z'
    )
  $$,
  'PT409',
  'Deadline plan kind cannot be changed.',
  'an active Assignment rejects an Exam proposal at the final RPC boundary'
);
reset role;

select is(
  (
    select row(status, kind, current_revision, latest_revision, updated_at)::text
    from public.deadline_plans
    where id = 'd1000000-0000-4000-8000-000000000010'
  ),
  '(draft,exam,0,1,"2026-08-12 08:00:00+00")',
  'the rejected draft proposal leaves the root projection unchanged'
);
select is(
  (
    select row(status, kind, current_revision, latest_revision, updated_at)::text
    from public.deadline_plans
    where id = 'd1000000-0000-4000-8000-000000000020'
  ),
  '(active,assignment,1,1,"2026-08-12 08:00:00+00")',
  'the rejected active proposal leaves the root projection unchanged'
);
select is(
  (
    select count(*)::int
    from public.deadline_plan_request_identities
    where request_id in (
      'd1000000-0000-4000-8000-000000000009',
      'd1000000-0000-4000-8000-000000000011',
      'd1000000-0000-4000-8000-000000000021'
    )
  ),
  0,
  'kind conflicts create no request-ledger entry'
);

create temporary table deadline_kind_guard_test_proposals (
  request_name text primary key,
  proposal jsonb not null
) on commit drop;

insert into deadline_kind_guard_test_proposals (request_name, proposal)
values
(
  'initial',
  jsonb_build_object(
    'plan_id', 'd1000000-0000-4000-8000-000000000030',
    'base_revision', 0,
    'kind', 'exam',
    'title', 'Same-kind exam',
    'deadline_at', '2026-08-20T12:00:00Z',
    'estimated_total_minutes', 30,
    'credited_prior_minutes', 0,
    'preferred_session_minutes', 25,
    'max_daily_minutes', 25,
    'planning_start_on', '2026-08-12',
    'buffer_days', 0,
    'source_kind', 'manual',
    'source_calendar_event_id', null,
    'source_calendar_event_fingerprint', null,
    'use_calendar_availability', false,
    'availability_connection_id', null,
    'availability_import_id', null,
    'timezone', 'Europe/Berlin',
    'best_energy_window', 'morning',
    'planning_fingerprint', repeat('3', 64),
    'tracked_focus_minutes_at_proposal', 0,
    'remaining_minutes_at_proposal', 30,
    'planned_minutes', 0,
    'unscheduled_minutes', 30,
    'study_setup_revision', null,
    'recovery_minutes', 0,
    'timing_preference', jsonb_build_object('source', 'setup')
  )
),
(
  'replan',
  jsonb_build_object(
    'plan_id', 'd1000000-0000-4000-8000-000000000030',
    'base_revision', 1,
    'kind', 'exam',
    'title', 'Same-kind exam',
    'deadline_at', '2026-08-20T12:00:00Z',
    'estimated_total_minutes', 30,
    'credited_prior_minutes', 0,
    'preferred_session_minutes', 25,
    'max_daily_minutes', 25,
    'planning_start_on', '2026-08-12',
    'buffer_days', 0,
    'source_kind', 'manual',
    'source_calendar_event_id', null,
    'source_calendar_event_fingerprint', null,
    'use_calendar_availability', false,
    'availability_connection_id', null,
    'availability_import_id', null,
    'timezone', 'Europe/Berlin',
    'best_energy_window', 'morning',
    'planning_fingerprint', repeat('4', 64),
    'tracked_focus_minutes_at_proposal', 0,
    'remaining_minutes_at_proposal', 30,
    'planned_minutes', 0,
    'unscheduled_minutes', 30,
    'study_setup_revision', null,
    'recovery_minutes', 0,
    'timing_preference', jsonb_build_object('source', 'setup')
  )
);

grant select on deadline_kind_guard_test_proposals to service_role;

set local role service_role;
select is(
  (
    public.propose_deadline_plan_with_timing_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000031', repeat('5', 64),
      'd1000000-0000-4000-8000-000000000030', 0,
      (select proposal from deadline_kind_guard_test_proposals
       where request_name = 'initial'),
      '[]', '2026-08-12T09:00:00Z'
    ) ->> 'revision'
  )::int,
  1,
  'the public wrapper delegates a valid new Exam proposal'
);
select is(
  (
    public.propose_deadline_plan_with_timing_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000031', repeat('5', 64),
      'd1000000-0000-4000-8000-000000000030', 0,
      (select proposal from deadline_kind_guard_test_proposals
       where request_name = 'initial'),
      '[]', '2026-08-12T09:05:00Z'
    ) ->> 'revision'
  )::int,
  1,
  'an exact proposal replay still returns its persisted revision'
);
select is(
  (
    public.propose_deadline_plan_with_timing_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000032', repeat('6', 64),
      'd1000000-0000-4000-8000-000000000030', 1,
      (select proposal from deadline_kind_guard_test_proposals
       where request_name = 'replan'),
      '[]', '2026-08-12T09:10:00Z'
    ) ->> 'revision'
  )::int,
  2,
  'an existing Exam accepts a same-kind replan through the guarded RPC'
);
reset role;

select is(
  (
    select row(kind, current_revision, latest_revision)::text
    from public.deadline_plans
    where id = 'd1000000-0000-4000-8000-000000000030'
  ),
  '(exam,0,2)',
  'same-kind proposal and replay preserve the root kind and advance once per request'
);
select is(
  (
    select count(*)::int
    from public.deadline_plan_request_identities
    where plan_id = 'd1000000-0000-4000-8000-000000000030'
  ),
  2,
  'exact replay retains one request-ledger row while a new replan adds one'
);

select * from finish();
rollback;
