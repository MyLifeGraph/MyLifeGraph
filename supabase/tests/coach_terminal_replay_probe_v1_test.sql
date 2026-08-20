begin;
select plan(9);

select ok(
  has_function_privilege(
    'service_role',
    'public.probe_coach_terminal_replay_v1(uuid,text,uuid,text,text,text,text,text,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.probe_coach_terminal_replay_v1(uuid,text,uuid,text,text,text,text,text,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.probe_coach_terminal_replay_v1(uuid,text,uuid,text,text,text,text,text,boolean)',
    'EXECUTE'
  ),
  'terminal replay probe is service-role-only'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  'ed000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'replay-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'ed000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'other-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

select is(
  public.probe_coach_terminal_replay_v1(
    'ed000000-0000-4000-8000-000000000001', 'coach-request-v4',
    'ed100000-0000-4000-8000-000000000001', repeat('a', 64),
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
  ) ->> 'state',
  'missing',
  'an unused owner request id is missing'
);

select is(
  public.claim_coach_request_v8(
    'ed000000-0000-4000-8000-000000000001', 'coach-request-v4',
    'ed100000-0000-4000-8000-000000000001', repeat('a', 64), current_date,
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit',
    now(), now() + interval '240 seconds', 20, true
  ) ->> 'state',
  'pending',
  'the fixture request is atomically claimed'
);

select is(
  public.probe_coach_terminal_replay_v1(
    'ed000000-0000-4000-8000-000000000001', 'coach-request-v4',
    'ed100000-0000-4000-8000-000000000001', repeat('a', 64),
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
  ) ->> 'state',
  'active',
  'an active request still proceeds through claim lease handling'
);

select throws_ok(
  $$
    select public.probe_coach_terminal_replay_v1(
      'ed000000-0000-4000-8000-000000000001', 'coach-request-v4',
      'ed100000-0000-4000-8000-000000000001', repeat('b', 64),
      'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
    )
  $$,
  'PT409',
  null,
  'changed exact input conflicts before provider admission'
);

select public.fail_coach_request_v1(
  'ed000000-0000-4000-8000-000000000001',
  'ed100000-0000-4000-8000-000000000001',
  '{"code":"provider_timeout","message":"Original turn timed out.","retryable":true}'::jsonb,
  '{"provider_called":true,"prompt_bytes":10,"context_bytes":20,"reply_codepoints":0}'::jsonb,
  now()
);

select is(
  public.probe_coach_terminal_replay_v1(
    'ed000000-0000-4000-8000-000000000001', 'coach-request-v4',
    'ed100000-0000-4000-8000-000000000001', repeat('a', 64),
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
  ) #>> '{error,code}',
  'provider_timeout',
  'persisted terminal failure is returned without a new claim'
);

select is(
  public.probe_coach_terminal_replay_v1(
    'ed000000-0000-4000-8000-000000000002', 'coach-request-v4',
    'ed100000-0000-4000-8000-000000000001', repeat('a', 64),
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
  ) ->> 'state',
  'missing',
  'another owner cannot observe terminal request existence'
);

select is(
  public.delete_coach_history_v1(
    'ed000000-0000-4000-8000-000000000001',
    now() + interval '1 second'
  ) ->> 'state',
  'deleted',
  'history deletion creates the retained tombstone used by replay'
);

select is(
  public.probe_coach_terminal_replay_v1(
    'ed000000-0000-4000-8000-000000000001', 'coach-request-v4',
    'ed100000-0000-4000-8000-000000000001', repeat('b', 64),
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
  ) ->> 'state',
  'deleted',
  'deleted tombstone replay remains body-free while retaining provider identity'
);

select * from finish();
rollback;
