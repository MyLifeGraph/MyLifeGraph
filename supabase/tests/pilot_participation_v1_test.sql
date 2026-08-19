begin;
select no_plan();

select columns_are(
  'public',
  'profiles',
  array[
    'id',
    'email',
    'display_name',
    'timezone',
    'role',
    'auth_provider',
    'onboarding_completed_at',
    'created_at',
    'updated_at',
    'setup_revision',
    'daily_preparation_budget_minutes',
    'timezone_revision',
    'preparation_budget_revision',
    'pilot_participation_notice_version',
    'pilot_participation_accepted_at'
  ],
  'profiles contains only the current version/time participation fields'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.accept_pilot_participation_v1(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.accept_pilot_participation_v1(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.accept_pilot_participation_v1(uuid,text)',
    'EXECUTE'
  ),
  'the acceptance command is service-role-only'
);

select is_empty(
  $$
    select column_name
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name in ('birth_date', 'date_of_birth', 'age')
  $$,
  'the profile contains no birth date or age field'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'eb000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'pilot-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}',
  '{"pilot_participation_notice_version":"pilot-participation-notice-v1"}',
  now(), now()
);

select is(
  (
    select pilot_participation_notice_version
    from public.profiles
    where id = 'eb000000-0000-4000-8000-000000000001'
  ),
  null,
  'editable Auth user metadata does not grant participation eligibility'
);

set local role service_role;

create temporary table first_acceptance_result on commit drop as
select public.accept_pilot_participation_v1(
  'eb000000-0000-4000-8000-000000000001',
  'pilot-participation-notice-v1'
) as value;

select is(
  (select value ->> 'contract_version' from first_acceptance_result),
  'pilot-participation-v1',
  'the command returns the exact participation contract'
);

select is(
  (select value ->> 'notice_version' from first_acceptance_result),
  'pilot-participation-notice-v1',
  'the command persists the exact notice version'
);

select is(
  (select (value ->> 'replayed')::boolean from first_acceptance_result),
  false,
  'the first command reports a new acceptance'
);

create temporary table replay_acceptance_result on commit drop as
select public.accept_pilot_participation_v1(
  'eb000000-0000-4000-8000-000000000001',
  'pilot-participation-notice-v1'
) as value;

select is(
  (select (value ->> 'replayed')::boolean from replay_acceptance_result),
  true,
  'the exact retry reports replay'
);

select is(
  (select value ->> 'accepted_at' from replay_acceptance_result),
  (select value ->> 'accepted_at' from first_acceptance_result),
  'an exact retry preserves the original backend acceptance time'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'eb000000-0000-4000-8000-000000000001';

select throws_ok(
  $$
    update public.profiles
    set pilot_participation_accepted_at = now()
    where id = 'eb000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'an authenticated owner cannot self-write eligibility'
);

select is(
  (
    select pilot_participation_notice_version
    from public.profiles
    where id = 'eb000000-0000-4000-8000-000000000001'
  ),
  'pilot-participation-notice-v1',
  'the owner can read the accepted current notice on their profile'
);

reset role;
select * from finish();
rollback;
