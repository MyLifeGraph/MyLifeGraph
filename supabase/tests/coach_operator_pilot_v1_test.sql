begin;
select plan(15);

reset role;
select ok(
  has_function_privilege(
    'service_role',
    'public.record_coach_operator_dispatch_v1(uuid,uuid,uuid,uuid,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.record_coach_operator_dispatch_v1(uuid,uuid,uuid,uuid,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.record_coach_operator_dispatch_v1(uuid,uuid,uuid,uuid,timestamp with time zone,integer)',
    'EXECUTE'
  ),
  'operator dispatch recording is service-role-only'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.coach_operator_dispatches',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'public.coach_operator_dispatches',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.coach_operator_daily_budgets',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'public.coach_operator_daily_budgets',
    'SELECT'
  ),
  'operator dispatch and global-budget rows are not application-readable'
);

select ok(
  (
    select count(*) = 2 and bool_and(relrowsecurity and relforcerowsecurity)
    from pg_class
    where oid in (
      'public.coach_operator_dispatches'::regclass,
      'public.coach_operator_daily_budgets'::regclass
    )
  ),
  'operator dispatch and global-budget rows use forced RLS'
);

select ok(
  (
    select pg_get_constraintdef(oid) like '%operator_codex_pilot%'
    from pg_constraint
    where conrelid = 'public.coach_requests'::regclass
      and conname = 'coach_requests_provider'
  ),
  'Coach requests admit the exact operator provider identity'
);

select ok(
  private.coach_error_is_valid_v1(
    '{"code":"provider_limit","message":"Shared limit reached.","retryable":true}'::jsonb
  ),
  'the global provider-limit race is a persistable terminal Coach error'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ec000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'operator-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

create temporary table operator_claim on commit drop as
select public.claim_coach_request_v8(
  'ec000000-0000-4000-8000-000000000001',
  'coach-request-v4',
  'ec100000-0000-4000-8000-000000000001',
  repeat('a', 64),
  current_date,
  'operator_codex_pilot',
  'operator_subscription_pilot',
  'gpt-5.5',
  'explicit',
  now(),
  now() + interval '240 seconds',
  5,
  true
) as value;

select is(
  (select value ->> 'state' from operator_claim),
  'pending',
  'V4 operator claim creates one pending request'
);

select is(
  (
    select contract_version || ':' || provider || ':' || provider_mode
    from public.coach_requests
    where request_id = 'ec100000-0000-4000-8000-000000000001'
  ),
  'coach-request-v4:operator_codex_pilot:operator_subscription_pilot',
  'the pending request persists exact V4 operator provenance'
);

create temporary table first_dispatch on commit drop as
select public.record_coach_operator_dispatch_v1(
  'ec200000-0000-4000-8000-000000000001',
  'ec100000-0000-4000-8000-000000000001',
  'ec000000-0000-4000-8000-000000000001',
  'ec300000-0000-4000-8000-000000000001',
  now(),
  15
) as value;

select is(
  (select value ->> 'state' from first_dispatch),
  'dispatched',
  'the first durable dispatch consumes global budget'
);

select is(
  (
    select count(*)::int
    from public.coach_operator_dispatches
    where request_id = 'ec100000-0000-4000-8000-000000000001'
  ),
  1,
  'one request has exactly one durable dispatch identity'
);

select is(
  public.record_coach_operator_dispatch_v1(
    'ec200000-0000-4000-8000-000000000001',
    'ec100000-0000-4000-8000-000000000001',
    'ec000000-0000-4000-8000-000000000001',
    'ec300000-0000-4000-8000-000000000001',
    now(),
    15
  ) ->> 'state',
  'existing',
  'an exact dispatch retry is idempotent'
);

select is(
  (select dispatch_count from public.coach_operator_daily_budgets),
  1,
  'an exact dispatch retry increments the durable global budget only once'
);

select throws_ok(
  $$
    select public.record_coach_operator_dispatch_v1(
      'ec200000-0000-4000-8000-000000000001',
      'ec100000-0000-4000-8000-000000000001',
      'ec000000-0000-4000-8000-000000000001',
      'ec300000-0000-4000-8000-000000000002',
      now(),
      15
    )
  $$,
  'PT409',
  null,
  'a changed reservation cannot reuse the request dispatch'
);

select is(
  public.finish_coach_operator_dispatch_v1(
    'ec200000-0000-4000-8000-000000000001',
    'ec100000-0000-4000-8000-000000000001',
    'interrupted',
    'interrupted',
    now()
  ) ->> 'state',
  'interrupted',
  'a conservative interrupted terminal state is persisted'
);

select throws_ok(
  $$
    select public.claim_coach_request_v8(
      'ec000000-0000-4000-8000-000000000001',
      'coach-request-v4',
      'ec100000-0000-4000-8000-000000000001',
      repeat('a', 64),
      current_date,
      'openai',
      'user_supplied_key',
      'gpt-5.6-terra',
      'explicit',
      now(),
      now() + interval '240 seconds',
      20,
      true
    )
  $$,
  'PT409',
  null,
  'same-id replay cannot change the selected provider'
);

create temporary table operator_deletion on commit drop as
select public.prepare_account_deletion_v2(
  'ec000000-0000-4000-8000-000000000001',
  'ec400000-0000-4000-8000-000000000001',
  'DELETE'
) as value;

select public.mark_account_deletion_appending_v2(
  'ec000000-0000-4000-8000-000000000001',
  'ec400000-0000-4000-8000-000000000001'
);

select public.accept_account_deletion_journal_v2(
  'ec000000-0000-4000-8000-000000000001',
  'ec400000-0000-4000-8000-000000000001',
  (select (value ->> 'accepted_at')::timestamptz from operator_deletion),
  'deletions/v2/' ||
    to_char(
      (select (value ->> 'accepted_at')::timestamptz from operator_deletion)
        at time zone 'UTC',
      'YYYY/MM'
    ) ||
    '/ec400000-0000-4000-8000-000000000001/' || repeat('d', 64) || '.json',
  repeat('d', 64),
  (select (value ->> 'accepted_at')::timestamptz from operator_deletion)
);

select public.complete_account_deletion_v2(
  'ec000000-0000-4000-8000-000000000001',
  'ec400000-0000-4000-8000-000000000001',
  'DELETE',
  (select (value ->> 'accepted_at')::timestamptz from operator_deletion)
    + interval '1 second'
);

reset role;
select ok(
  not exists (
    select 1 from auth.users
    where id = 'ec000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1 from public.coach_operator_dispatches
    where request_id = 'ec100000-0000-4000-8000-000000000001'
  )
  and (select dispatch_count from public.coach_operator_daily_budgets) = 1,
  'account deletion removes owner-linked dispatch data without resetting the global budget'
);

select * from finish();
rollback;
