begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'e1000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'profile-owner@example.test',
    crypt('test-password', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    'e1000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'profile-other@example.test',
    crypt('test-password', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

set local role authenticated;
set local request.jwt.claim.sub =
  'e1000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.profiles),
  1,
  'an authenticated owner sees exactly their canonical profile'
);

select is(
  (select id::text from public.profiles limit 1),
  'e1000000-0000-4000-8000-000000000001',
  'profile RLS does not expose another owner'
);

select throws_ok(
  $$
    insert into public.profiles (id, role, auth_provider)
    values (
      'e1000000-0000-4000-8000-000000000001',
      'admin',
      'email'
    )
  $$,
  '42501',
  null,
  'an authenticated client cannot upsert or recreate its canonical profile'
);

select throws_ok(
  $$
    update public.profiles
    set role = 'admin'
    where id = 'e1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'an authenticated client cannot self-promote its profile role'
);

select throws_ok(
  $$
    update public.profiles
    set auth_provider = 'google'
    where id = 'e1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'an authenticated client cannot change backend auth-provider truth'
);

select throws_ok(
  $$
    delete from public.profiles
    where id = 'e1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'an authenticated client cannot delete its canonical profile directly'
);

set local request.jwt.claim.sub =
  'e1000000-0000-4000-8000-000000000002';

select is(
  (
    select count(*)::integer
    from public.profiles
    where id = 'e1000000-0000-4000-8000-000000000001'
  ),
  0,
  'a second authenticated owner cannot bind or read the first profile id'
);

select is(
  (
    select count(*)::integer
    from public.profiles
    where id = 'e1000000-0000-4000-8000-000000000002'
  ),
  1,
  'the second owner still sees their own canonical profile'
);

reset role;
select * from finish();
rollback;
