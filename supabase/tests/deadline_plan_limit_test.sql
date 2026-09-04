begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'f2000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'deadline-limit-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
update public.profiles set timezone = 'Europe/Berlin'
where id = 'f2000000-0000-4000-8000-000000000001';

-- Only the already-existing roots are fixture inserts; all operations under
-- test go through the current service-role RPC wrappers.
insert into public.deadline_plans (
  id, user_id, status, kind, title,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, created_at, updated_at
)
select
  ('f2010000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'f2000000-0000-4000-8000-000000000001', 'draft', 'exam', 'Existing plan',
  30, 0, 0, 1, '2026-08-12T08:00:00Z', '2026-08-12T08:00:00Z'
from generate_series(1, 49) as n;

create temporary table deadline_limit_test_proposals as
select n as position,
  ('f2020000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as plan_id,
  ('f2030000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as request_id,
  jsonb_build_object(
    'plan_id', 'f2020000-0000-4000-8000-' || lpad(n::text, 12, '0'),
    'base_revision', 0, 'kind', 'assignment', 'title', 'Weekly assignment',
    'deadline_at', '2026-08-20T12:00:00Z'::timestamptz + (n - 1) * interval '7 days',
    'estimated_total_minutes', 30, 'credited_prior_minutes', 0,
    'preferred_session_minutes', 25, 'max_daily_minutes', 25,
    'planning_start_on', '2026-08-12', 'buffer_days', 0,
    'source_kind', 'manual', 'source_calendar_event_id', null,
    'source_calendar_event_fingerprint', null, 'use_calendar_availability', false,
    'availability_connection_id', null, 'availability_import_id', null,
    'timezone', 'Europe/Berlin', 'best_energy_window', 'morning',
    'planning_fingerprint', repeat('3', 64),
    'tracked_focus_minutes_at_proposal', 0, 'remaining_minutes_at_proposal', 30,
    'planned_minutes', 0, 'unscheduled_minutes', 30,
    'study_setup_revision', null, 'recovery_minutes', 0,
    'timing_preference', jsonb_build_object('source', 'setup')
  ) as proposal
from generate_series(1, 2) as n;

create temporary table deadline_limit_test_series as
select jsonb_build_object(
    'title', 'Weekly assignment', 'next_deadline_at', '2026-08-20T12:00:00Z',
    'remaining_occurrences', 2, 'estimated_total_minutes', 30,
    'preferred_session_minutes', 25, 'max_daily_minutes', 25, 'buffer_days', 0,
    'use_calendar_availability', false, 'timezone', 'Europe/Berlin',
    'planned_minutes', 0, 'unscheduled_minutes', 60
  ) as series,
  jsonb_agg(jsonb_build_object(
    'position', position, 'action', 'upsert', 'plan_id', plan_id,
    'plan_revision', 1, 'deadline_at', proposal -> 'deadline_at',
    'proposal_request_id', request_id, 'proposal_request_fingerprint', repeat('a', 64),
    'proposal', proposal, 'blocks', '[]'::jsonb,
    'mutation_request_id', 'f2040000-0000-4000-8000-' || lpad(position::text, 12, '0'),
    'mutation_request_fingerprint', repeat('b', 64)
  ) order by position) as items
from deadline_limit_test_proposals;
grant select on deadline_limit_test_proposals, deadline_limit_test_series to service_role;

set local role service_role;
select throws_ok(
  $$select public.propose_assignment_series_v1(
    'f2000000-0000-4000-8000-000000000001',
    'f2050000-0000-4000-8000-000000000001', repeat('c', 64),
    'f2060000-0000-4000-8000-000000000001', 0,
    (select series from deadline_limit_test_series),
    (select items from deadline_limit_test_series), '2026-08-12T09:00:00Z'
  )$$,
  'PT409', 'You already have 50 open deadline plans.',
  'a two-occurrence series at 49 open plans fails at the shared cap'
);
reset role;
select is(
  (select count(*)::int from public.deadline_plans
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  49, 'the first occurrence was rolled back with the rejected series'
);
select is(
  (select count(*)::int from public.deadline_plan_revisions
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  0, 'the rejected series leaves no occurrence revisions'
);
select is(
  (select count(*)::int from public.deadline_plan_request_identities
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  0, 'the rejected series leaves no occurrence replay identities'
);
select is(
  (select count(*)::int from public.assignment_series
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  0, 'the rejected series leaves no series root'
);
select is(
  (select count(*)::int from public.assignment_series_request_identities
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  0, 'the rejected series leaves no series replay identity'
);

set local role service_role;
select is(
  (select (public.propose_deadline_plan_with_timing_v1(
    'f2000000-0000-4000-8000-000000000001', request_id, repeat('a', 64),
    plan_id, 0, proposal, '[]', '2026-08-12T09:00:00Z'
  ) ->> 'revision')::int from deadline_limit_test_proposals where position = 1),
  1, 'the fiftieth open plan is accepted'
);
select is(
  (select (public.propose_deadline_plan_with_timing_v1(
    'f2000000-0000-4000-8000-000000000001', request_id, repeat('a', 64),
    plan_id, 0, proposal, '[]', '2026-08-12T09:05:00Z'
  ) ->> 'revision')::int from deadline_limit_test_proposals where position = 1),
  1, 'an exact replay at 50 open plans remains successful'
);
select throws_ok(
  $$select public.propose_deadline_plan_with_timing_v1(
    'f2000000-0000-4000-8000-000000000001', request_id, repeat('a', 64),
    plan_id, 0, proposal, '[]', '2026-08-12T09:10:00Z'
  ) from deadline_limit_test_proposals where position = 2$$,
  'PT409', 'You already have 50 open deadline plans.',
  'a new fifty-first plan is rejected'
);
reset role;
select is(
  (select count(*)::int from public.deadline_plans
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  50, 'replay and cap rejection keep exactly 50 open plans'
);
select is(
  (select count(*)::int from public.deadline_plan_request_identities
   where user_id = 'f2000000-0000-4000-8000-000000000001'),
  1, 'only the successful new plan owns a replay identity'
);
select * from finish();
rollback;
