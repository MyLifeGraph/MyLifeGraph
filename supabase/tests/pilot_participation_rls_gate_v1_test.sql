begin;
select no_plan();

select ok(
  has_function_privilege(
    'service_role',
    'public.configure_pilot_participation_gate_v1(text,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.configure_pilot_participation_gate_v1(text,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.configure_pilot_participation_gate_v1(text,boolean)',
    'EXECUTE'
  ),
  'only the backend can configure the database participation gate'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.get_pilot_participation_gate_v1()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.get_pilot_participation_gate_v1()',
    'EXECUTE'
  ),
  'only the backend can attest the database participation gate'
);

select is_empty(
  $$
    select class.relname
    from pg_catalog.pg_class as class
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relkind in ('r', 'p')
      and class.relrowsecurity
      and class.relname <> 'profiles'
      and not exists (
        select 1
        from pg_catalog.pg_policy as policy
        where policy.polrelid = class.oid
          and policy.polname = 'pilot_participation_required_v1'
          and not policy.polpermissive
      )
  $$,
  'every current public RLS product table has the restrictive gate policy'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_policy
    where polrelid = 'public.profiles'::regclass
      and polname in (
        'pilot_participation_profile_insert_v1',
        'pilot_participation_profile_update_v1',
        'pilot_participation_profile_delete_v1'
      )
      and not polpermissive
  ),
  3,
  'profile writes have three restrictive command policies while reads remain available'
);

select is_empty(
  $$
    select class.relname, policy.polname
    from pg_catalog.pg_policy as policy
    join pg_catalog.pg_class as class on class.oid = policy.polrelid
    where policy.polname like 'pilot_participation%'
      and (
        policy.polpermissive
        or concat(
          coalesce(pg_get_expr(policy.polqual, policy.polrelid), ''),
          ' ',
          coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
        ) not like '%current_request_has_pilot_participation_v1%'
      )
  $$,
  'every participation policy is restrictive and calls the exact gate authority'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ee000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'participation-rls@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.daily_logs (
  user_id,
  entry_date,
  mood_score,
  source
) values (
  'ee000000-0000-4000-8000-000000000001',
  date '2026-08-20',
  7,
  'test'
);

set local role service_role;

select is(
  public.configure_pilot_participation_gate_v1(
    'abcdefghijklmnopqrst',
    true
  ) ->> 'contract_version',
  'pilot-participation-gate-v1',
  'the backend enables an exact project-bound gate contract'
);

select is(
  public.get_pilot_participation_gate_v1() ->> 'project_ref',
  'abcdefghijklmnopqrst',
  'the readiness attestation returns the configured project ref'
);

select throws_ok(
  $$ select public.configure_pilot_participation_gate_v1(null, true) $$,
  '22023',
  null,
  'an enabled gate rejects a missing project ref'
);

select throws_ok(
  $$ select public.configure_pilot_participation_gate_v1('wrong', true) $$,
  '22023',
  null,
  'an enabled gate rejects a malformed project ref'
);

select throws_ok(
  $$
    select public.configure_pilot_participation_gate_v1(
      'abcdefghijklmnopqrst',
      false
    )
  $$,
  '22023',
  null,
  'a disabled gate rejects a retained project ref'
);

select throws_ok(
  $$ select public.configure_pilot_participation_gate_v1(null, null) $$,
  '22023',
  null,
  'the gate rejects an unknown required state'
);

select is(
  (
    select count(*)::integer
    from public.daily_logs
    where user_id = 'ee000000-0000-4000-8000-000000000001'
  ),
  1,
  'service-role access to the test owner is unchanged by backend enforcement'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'ee000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.profiles),
  1,
  'an unaccepted owner can read exactly their profile to discover gate state'
);

select is(
  (select count(*)::integer from public.daily_logs),
  0,
  'an unaccepted owner cannot read product rows through the public API key'
);

select throws_ok(
  $$
    insert into public.daily_logs (
      user_id, entry_date, mood_score, source
    ) values (
      'ee000000-0000-4000-8000-000000000001',
      date '2026-08-21',
      8,
      'test'
    )
  $$,
  '42501',
  null,
  'the public API key has no direct Daily Capture write grant before acceptance'
);

update public.profiles
set display_name = 'Blocked before acceptance'
where id = 'ee000000-0000-4000-8000-000000000001';

select isnt(
  (
    select display_name
    from public.profiles
    where id = 'ee000000-0000-4000-8000-000000000001'
  ),
  'Blocked before acceptance',
  'the restrictive gate reduces an unaccepted profile mutation to zero rows'
);

select throws_ok(
  $$
    select public.configure_pilot_participation_gate_v1(
      'abcdefghijklmnopqrst',
      true
    )
  $$,
  '42501',
  null,
  'an authenticated client cannot configure its own gate'
);

reset role;
delete from private.pilot_participation_gate_v1 where singleton;
set local role authenticated;
set local request.jwt.claim.sub =
  'ee000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.daily_logs),
  0,
  'a missing gate singleton fails closed for product reads'
);

reset role;
set local role service_role;
select throws_ok(
  $$
    select public.configure_pilot_participation_gate_v1(
      'abcdefghijklmnopqrst',
      true
    )
  $$,
  '55000',
  null,
  'configuration corruption cannot be silently recreated by the runtime RPC'
);

reset role;
insert into private.pilot_participation_gate_v1 (
  singleton,
  project_ref,
  participation_required,
  notice_version
) values (
  true,
  'abcdefghijklmnopqrst',
  true,
  'pilot-participation-notice-v1'
);

set local role service_role;

select public.accept_pilot_participation_v1(
  'ee000000-0000-4000-8000-000000000001',
  'pilot-participation-notice-v1'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'ee000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.daily_logs),
  1,
  'an accepted owner can read their product rows'
);

select throws_ok(
  $$
    insert into public.daily_logs (
      user_id, entry_date, mood_score, source
    ) values (
      'ee000000-0000-4000-8000-000000000001',
      date '2026-08-21',
      8,
      'test'
    )
  $$,
  '42501',
  null,
  'participation acceptance does not broaden the revoked Daily Capture write authority'
);

update public.profiles
set display_name = 'Accepted owner'
where id = 'ee000000-0000-4000-8000-000000000001';

select is(
  (
    select display_name
    from public.profiles
    where id = 'ee000000-0000-4000-8000-000000000001'
  ),
  'Accepted owner',
  'participation acceptance restores the existing constrained profile write seam'
);

reset role;
set local role service_role;

select is(
  public.configure_pilot_participation_gate_v1(null, false)
    ->> 'participation_required',
  'false',
  'the backend can explicitly restore local-development semantics'
);

update public.profiles
set
  pilot_participation_notice_version = null,
  pilot_participation_accepted_at = null
where id = 'ee000000-0000-4000-8000-000000000001';

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'ee000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.daily_logs),
  1,
  'the explicit disabled state preserves disposable local database behavior'
);

reset role;
select * from finish();
rollback;
