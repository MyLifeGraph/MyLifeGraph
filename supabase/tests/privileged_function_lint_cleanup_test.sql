begin;
select no_plan();

select ok(
  not has_function_privilege(
    'anon', 'public.current_app_role()', 'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated', 'public.current_app_role()', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role', 'public.current_app_role()', 'EXECUTE'
  )
  and not (
    select prosecdef
    from pg_proc
    where oid = 'public.current_app_role()'::regprocedure
  ),
  'the retained public role helper is invoker-only and uncallable by application roles'
);

select ok(
  (
    select pg_get_functiondef('public.current_app_role()'::regprocedure)
      like '%select private.current_app_role()%'
  )
  and (
    select pg_get_functiondef('public.current_app_role()'::regprocedure)
      not like '%public."User"%'
  )
  and (
    select proconfig = array['search_path=""']
    from pg_proc
    where oid = 'public.current_app_role()'::regprocedure
  ),
  'the compatibility helper delegates to canonical role truth with an empty search path'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'c5000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'role-wrapper-user@example.test',
    crypt('test-password', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    'c5000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'role-wrapper-admin@example.test',
    crypt('test-password', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    'c5000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'cleanup-delete@example.test',
    crypt('test-password', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    'c5000000-0000-4000-8000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'cleanup-coach@example.test',
    crypt('test-password', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

update public.profiles
set role = 'admin'
where id = 'c5000000-0000-4000-8000-000000000002';

set local request.jwt.claim.sub =
  'c5000000-0000-4000-8000-000000000001';
select is(
  public.current_app_role(),
  'user',
  'the compatibility wrapper returns canonical user authority'
);

set local request.jwt.claim.sub =
  'c5000000-0000-4000-8000-000000000002';
select is(
  public.current_app_role(),
  'admin',
  'the compatibility wrapper preserves canonical admin authority'
);

reset request.jwt.claim.sub;

select ok(
  not has_function_privilege(
    'service_role', 'public.delete_account_v1(uuid,text)', 'EXECUTE'
  ) and not has_function_privilege(
    'authenticated', 'public.delete_account_v1(uuid,text)', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon', 'public.delete_account_v1(uuid,text)', 'EXECUTE'
  ),
  'Account Delete V1 is no longer directly executable after recovery V2'
);

select is(
  (
    public.delete_account_v1(
      'c5000000-0000-4000-8000-000000000003', 'DELETE'
    ) ->> 'deleted'
  )::boolean,
  true,
  'the lint-only Account Delete redefinition preserves full deletion behavior'
);

select ok(
  not exists (
    select 1 from auth.users
    where id = 'c5000000-0000-4000-8000-000000000003'
  )
  and not exists (
    select 1 from public.profiles
    where id = 'c5000000-0000-4000-8000-000000000003'
  ),
  'Account Delete still removes both Auth and canonical profile identity'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v8('
      'uuid,text,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_coach_request_v8('
      'uuid,text,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.claim_coach_request_v7('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and (
    select proconfig = array['search_path=pg_catalog, pg_temp']
    from pg_proc
    where oid = (
      'public.claim_coach_request_v8('
        'uuid,text,uuid,text,date,text,text,text,text,'
        'timestamp with time zone,timestamp with time zone,integer,boolean)'
    )::regprocedure
  ),
  'Coach V8 claim is backend-only with a hardened fixed search path and V7 is retired'
);

set local role service_role;
select is(
  (
    public.claim_coach_request_v8(
      'c5000000-0000-4000-8000-000000000004',
      'coach-request-v3',
      'c5000000-0000-4000-8000-000000000104',
      repeat('4', 64),
      '2026-08-02',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      '2026-08-02T10:00:00Z',
      '2026-08-02T10:01:00Z',
      20,
      true
    ) ->> 'state'
  ),
  'pending',
  'Coach V8 creates a pending compatibility-contract request'
);

select is(
  concat_ws(
    '|',
    public.claim_coach_request_v8(
      'c5000000-0000-4000-8000-000000000004',
      'coach-request-v3',
      'c5000000-0000-4000-8000-000000000104',
      repeat('4', 64),
      '2026-08-02',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      '2026-08-02T10:02:00Z',
      '2026-08-02T10:03:00Z',
      20,
      true
    ) ->> 'state',
    public.claim_coach_request_v8(
      'c5000000-0000-4000-8000-000000000004',
      'coach-request-v3',
      'c5000000-0000-4000-8000-000000000104',
      repeat('4', 64),
      '2026-08-02',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      '2026-08-02T10:02:00Z',
      '2026-08-02T10:03:00Z',
      20,
      true
    ) #>> '{error,code}'
  ),
  'failed|interrupted',
  'an expired Coach V8 replay still atomically records and returns interruption'
);
reset role;

select ok(
  (
    select state = 'failed'
      and error #>> '{code}' = 'interrupted'
    from public.coach_requests
    where request_id = 'c5000000-0000-4000-8000-000000000104'
  )
  and (
    select count(*) = 1
      and bool_and(outcome = 'failed')
      and bool_and(error_code = 'interrupted')
      and bool_and(
        counters = jsonb_build_object(
          'provider_called', false,
          'prompt_bytes', 0,
          'context_bytes', 0,
          'reply_codepoints', 0
        )
      )
    from public.coach_usage_events
    where request_id = 'c5000000-0000-4000-8000-000000000104'
  ),
  'discarding the fail RPC response preserves one durable failure and usage fact'
);

select * from finish();
rollback;
