begin;
select no_plan();

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
(
  'c4000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'coach-prompt-v1-replay@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-07-29T14:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Coach Prompt V1 Replay"}'::jsonb,
  '2026-07-29T14:00:00Z',
  '2026-07-29T14:00:00Z'
),
(
  'c4000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'coach-prompt-v2@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-07-29T14:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Coach Prompt V2"}'::jsonb,
  '2026-07-29T14:00:00Z',
  '2026-07-29T14:00:00Z'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v4('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_coach_request_v4('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.claim_coach_request_v4('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  ),
  'only service_role can call the English-prompt V4 claim'
);

create temporary table coach_prompt_v1_claim on commit drop as
select public.claim_coach_request_v3(
  'c4000000-0000-4000-8000-000000000001',
  'c4000000-0000-4000-8000-000000000101',
  encode(extensions.digest(convert_to('V1 replay', 'UTF8'), 'sha256'), 'hex'),
  '2026-07-29',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-07-29T15:00:00Z',
  '2026-07-29T15:02:00Z',
  20
) as value;

select is(
  (
    select prompt_version
    from public.coach_requests
    where request_id = 'c4000000-0000-4000-8000-000000000101'
  ),
  'free-coach-agent-prompt-v1',
  'the rolling-safe V3 server path still creates prompt V1 requests'
);

create temporary table coach_prompt_v1_replay on commit drop as
select public.claim_coach_request_v4(
  'c4000000-0000-4000-8000-000000000001',
  'c4000000-0000-4000-8000-000000000101',
  encode(extensions.digest(convert_to('V1 replay', 'UTF8'), 'sha256'), 'hex'),
  '2026-07-29',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-07-29T15:00:30Z',
  '2026-07-29T15:02:30Z',
  20
) as value;

select is(
  (select value ->> 'state' from coach_prompt_v1_replay),
  'in_progress',
  'V4 safely replays an existing in-progress V1 claim'
);

select is(
  (
    select prompt_version
    from public.coach_requests
    where request_id = 'c4000000-0000-4000-8000-000000000101'
  ),
  'free-coach-agent-prompt-v1',
  'V4 does not rewrite an existing V1 request'
);

create temporary table coach_prompt_v2_claim on commit drop as
select public.claim_coach_request_v4(
  'c4000000-0000-4000-8000-000000000002',
  'c4000000-0000-4000-8000-000000000102',
  encode(extensions.digest(convert_to('V2 claim', 'UTF8'), 'sha256'), 'hex'),
  '2026-07-29',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-07-29T15:00:00Z',
  '2026-07-29T15:02:00Z',
  20
) as value;

select ok(
  (select value ->> 'state' from coach_prompt_v2_claim) = 'pending'
  and (
    select prompt_version = 'free-coach-agent-prompt-v2'
      and context_version = 'personal-snapshot-v1'
    from public.coach_requests
    where request_id = 'c4000000-0000-4000-8000-000000000102'
  ),
  'a new V4 claim persists prompt V2 with the unchanged snapshot contract'
);

select * from finish();
rollback;
