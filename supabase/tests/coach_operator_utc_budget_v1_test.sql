begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ed000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'operator-utc-budget@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v8(uuid,text,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.claim_coach_request_v8_local_date_legacy(uuid,text,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  ),
  'only the UTC-normalizing V8 entrypoint is runtime executable'
);

set local role service_role;

do $$
declare
  request_number int;
  request_id uuid;
  claim_result jsonb;
begin
  for request_number in 1..5 loop
    request_id := (
      'ed100000-0000-4000-8000-' || lpad(request_number::text, 12, '0')
    )::uuid;
    claim_result := public.claim_coach_request_v8(
      'ed000000-0000-4000-8000-000000000001',
      'coach-request-v4',
      request_id,
      encode(
        extensions.digest(
          convert_to('operator utc ' || request_number, 'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      date '2026-08-19',
      'operator_codex_pilot',
      'operator_subscription_pilot',
      'gpt-5.5',
      'explicit',
      timestamptz '2026-08-20 12:00:00+00'
        + make_interval(secs => request_number),
      timestamptz '2026-08-20 12:04:00+00'
        + make_interval(secs => request_number),
      5,
      true
    );
    if claim_result ->> 'state' is distinct from 'pending' then
      raise exception 'Expected UTC-budget claim % to be pending.', request_number;
    end if;
    perform public.fail_coach_request_v1(
      'ed000000-0000-4000-8000-000000000001',
      request_id,
      jsonb_build_object(
        'code', 'provider_unavailable',
        'message', 'Deterministic quota fixture.',
        'retryable', true
      ),
      jsonb_build_object(
        'provider_called', false,
        'prompt_bytes', 0,
        'context_bytes', 0,
        'reply_codepoints', 0
      ),
      timestamptz '2026-08-20 12:05:00+00'
        + make_interval(secs => request_number)
    );
  end loop;
end;
$$;

select is(
  (
    select count(*)::integer
    from public.coach_requests
    where user_id = 'ed000000-0000-4000-8000-000000000001'
      and operator_budget_utc_date = date '2026-08-20'
      and provider = 'operator_codex_pilot'
  ),
  5,
  'timezone-shaped local dates collapse into one server-derived UTC bucket'
);

select is(
  (
    select count(*)::integer
    from public.coach_requests
    where user_id = 'ed000000-0000-4000-8000-000000000001'
      and local_date = date '2026-08-19'
  ),
  5,
  'the separate budget period does not overwrite profile-local request dates'
);

select throws_ok(
  $$
    select public.claim_coach_request_v8(
      'ed000000-0000-4000-8000-000000000001',
      'coach-request-v4',
      'ed100000-0000-4000-8000-000000000006',
      repeat('f', 64),
      date '2026-08-22',
      'operator_codex_pilot',
      'operator_subscription_pilot',
      'gpt-5.5',
      'explicit',
      timestamptz '2026-08-20 13:00:00+00',
      timestamptz '2026-08-20 13:04:00+00',
      5,
      true
    )
  $$,
  'PT429',
  'Coach daily request limit reached',
  'a timezone change cannot open a sixth operator-funded turn in one UTC day'
);

select is(
  (
    public.claim_coach_request_v8(
      'ed000000-0000-4000-8000-000000000001',
      'coach-request-v4',
      'ed100000-0000-4000-8000-000000000007',
      repeat('e', 64),
      date '2026-08-19',
      'operator_codex_pilot',
      'operator_subscription_pilot',
      'gpt-5.5',
      'explicit',
      timestamptz '2026-08-21 00:00:01+00',
      timestamptz '2026-08-21 00:04:01+00',
      5,
      true
    ) ->> 'state'
  ),
  'pending',
  'a new UTC day opens the operator allowance even when local_date is unchanged'
);

select is(
  (
    select count(*)::integer
    from public.coach_requests
    where user_id = 'ed000000-0000-4000-8000-000000000001'
      and operator_budget_utc_date = date '2026-08-21'
      and local_date = date '2026-08-19'
  ),
  1,
  'the new UTC bucket remains independent of the unchanged profile-local day'
);

reset role;
select * from finish();
rollback;
