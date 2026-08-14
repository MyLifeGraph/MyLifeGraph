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
) values (
  'c4000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'coach-prompt-v4@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-08-04T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Coach Prompt V4"}'::jsonb,
  '2026-08-04T08:00:00Z',
  '2026-08-04T08:00:00Z'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v6('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_coach_request_v6('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.claim_coach_request_v6('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  ),
  'only service_role can call the current V6 Coach claim'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.claim_coach_request_v4('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.claim_coach_request_v3('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  ),
  'older free-Coach claim entrypoints cannot create new legacy contexts'
);

set local role service_role;
create temporary table coach_prompt_v4_claim on commit drop as
select public.claim_coach_request_v6(
  'c4000000-0000-4000-8000-000000000001',
  'c4000000-0000-4000-8000-000000000101',
  encode(
    extensions.digest(convert_to('V4 Goal-free claim', 'UTF8'), 'sha256'),
    'hex'
  ),
  '2026-08-04',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-08-04T09:00:00Z',
  '2026-08-04T09:02:00Z',
  20
) as value;
reset role;

select ok(
  (select value ->> 'state' from coach_prompt_v4_claim) = 'pending'
  and (
    select prompt_version = 'free-coach-agent-prompt-v4'
      and context_version = 'personal-snapshot-v3'
    from public.coach_requests
    where request_id = 'c4000000-0000-4000-8000-000000000101'
  ),
  'a new V6 claim atomically stores the current prompt and snapshot pair'
);

set local role service_role;
create temporary table coach_prompt_v4_replay on commit drop as
select public.claim_coach_request_v6(
  'c4000000-0000-4000-8000-000000000001',
  'c4000000-0000-4000-8000-000000000101',
  encode(
    extensions.digest(convert_to('V4 Goal-free claim', 'UTF8'), 'sha256'),
    'hex'
  ),
  '2026-08-04',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-08-04T09:00:30Z',
  '2026-08-04T09:02:30Z',
  20
) as value;
reset role;

select ok(
  (select value ->> 'state' from coach_prompt_v4_replay) = 'in_progress'
  and (
    select prompt_version = 'free-coach-agent-prompt-v4'
      and context_version = 'personal-snapshot-v3'
    from public.coach_requests
    where request_id = 'c4000000-0000-4000-8000-000000000101'
  ),
  'a retry preserves the current in-progress identity and contract pair'
);

select ok(
  not private.coach_used_context_is_valid_v1(
    '[{
      "source":"goals",
      "available_count":1,
      "included_count":1,
      "omitted_count":0,
      "freshness":"current"
    }]'::jsonb
  ),
  'legacy Goals cannot appear in a newly validated Coach context manifest'
);

select * from finish();
rollback;
