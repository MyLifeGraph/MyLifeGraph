begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  'b1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'learning-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'b1000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'learning-other@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

select is(
  (
    select row(
      focus_reflection_prompt_enabled,
      personal_pattern_analysis_enabled,
      learned_focus_planning_enabled,
      revision
    )::text
    from public.learning_preferences
    where user_id = 'b1000000-0000-4000-8000-000000000001'
  ),
  '(t,t,f,0)',
  'new profiles receive the exact privacy-safe learning defaults'
);

insert into public.focus_sessions (
  id, user_id, started_at, ended_at, planned_minutes, actual_minutes,
  status, metadata, updated_at
) values
(
  'b1000000-0000-4000-8000-000000000101',
  'b1000000-0000-4000-8000-000000000001',
  '2026-07-20T08:00:00Z', '2026-07-20T08:45:00Z', 45, 45,
  'completed', '{"entry_date":"2026-07-20"}', '2026-07-20T08:45:00Z'
),
(
  'b1000000-0000-4000-8000-000000000102',
  'b1000000-0000-4000-8000-000000000001',
  '2026-07-21T08:00:00Z', '2026-07-21T08:20:00Z', 30, 20,
  'abandoned', '{"entry_date":"2026-07-21"}', '2026-07-21T08:20:00Z'
),
(
  'b1000000-0000-4000-8000-000000000103',
  'b1000000-0000-4000-8000-000000000001',
  '2026-07-22T08:00:00Z', null, 45, null,
  'active', '{"entry_date":"2026-07-22"}', '2026-07-22T08:00:00Z'
),
(
  'b1000000-0000-4000-8000-000000000104',
  'b1000000-0000-4000-8000-000000000002',
  '2026-07-20T09:00:00Z', '2026-07-20T09:30:00Z', 30, 30,
  'completed', '{"entry_date":"2026-07-20"}', '2026-07-20T09:30:00Z'
);

select lives_ok(
  $$
    insert into public.focus_session_reflections (
      focus_session_id, user_id, focus_quality, useful_progress, obstacles
    ) values (
      'b1000000-0000-4000-8000-000000000101',
      'b1000000-0000-4000-8000-000000000001',
      4, 5, array['distracted', 'interrupted']
    )
  $$,
  'a terminal owner reflection with two controlled obstacles is accepted'
);

select throws_ok(
  $$
    insert into public.focus_session_reflections (
      focus_session_id, user_id, focus_quality, useful_progress, obstacles
    ) values (
      'b1000000-0000-4000-8000-000000000102',
      'b1000000-0000-4000-8000-000000000001',
      0, 5, '{}'
    )
  $$,
  '23514',
  null,
  'rating values outside 1 through 5 are rejected'
);

select throws_ok(
  $$
    insert into public.focus_session_reflections (
      focus_session_id, user_id, focus_quality, useful_progress, obstacles
    ) values (
      'b1000000-0000-4000-8000-000000000102',
      'b1000000-0000-4000-8000-000000000001',
      3, 3, array['tired', 'distracted', 'other']
    )
  $$,
  '23514',
  null,
  'more than two obstacles are rejected'
);

select throws_ok(
  $$
    insert into public.focus_session_reflections (
      focus_session_id, user_id, focus_quality, useful_progress, obstacles
    ) values (
      'b1000000-0000-4000-8000-000000000103',
      'b1000000-0000-4000-8000-000000000001',
      3, 3, '{}'
    )
  $$,
  '23514',
  'A Focus reflection requires an owned terminal session',
  'active sessions cannot be rated'
);

select throws_ok(
  $$
    insert into public.focus_session_reflections (
      focus_session_id, user_id, focus_quality, useful_progress, obstacles
    ) values (
      'b1000000-0000-4000-8000-000000000104',
      'b1000000-0000-4000-8000-000000000001',
      3, 3, '{}'
    )
  $$,
  '23514',
  'A Focus reflection requires an owned terminal session',
  'the composite owner foreign key rejects cross-owner reflections'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'b1000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::int from public.focus_session_reflections),
  1,
  'RLS exposes the owner reflection'
);
select lives_ok(
  $$
    update public.focus_session_reflections
    set focus_quality = 5
    where focus_session_id = 'b1000000-0000-4000-8000-000000000101'
  $$,
  'the owner can correct a reflection'
);

set local request.jwt.claim.sub =
  'b1000000-0000-4000-8000-000000000002';
select is(
  (select count(*)::int from public.focus_session_reflections),
  0,
  'RLS hides another owners reflection'
);
reset role;

set local role service_role;
select is(
  (
    public.update_learning_preferences_v1(
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000201',
      0, true, true, true
    ) ->> 'revision'
  )::int,
  1,
  'the complete preference state advances the exact revision'
);
select is(
  (
    public.update_learning_preferences_v1(
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000201',
      0, true, true, true
    ) ->> 'replayed'
  )::boolean,
  true,
  'an exact preference retry returns the recorded result'
);
select throws_ok(
  $$
    select public.update_learning_preferences_v1(
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000202',
      1, true, false, true
    )
  $$,
  '22023',
  'Invalid Personal learning preference request',
  'Planner use cannot remain enabled when analysis is disabled'
);
reset role;

insert into public.focus_session_reflections (
  focus_session_id, user_id, focus_quality, useful_progress, obstacles
) values (
  'b1000000-0000-4000-8000-000000000102',
  'b1000000-0000-4000-8000-000000000001',
  3, 2, array['tired']
);

set local role service_role;
select is(
  (
    public.clear_focus_reflection_history_v1(
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000203',
      1, 'CLEAR'
    ) ->> 'deleted_count'
  )::int,
  2,
  'confirmed bulk clear removes only the owners reflection history'
);
select is(
  (
    public.clear_focus_reflection_history_v1(
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000203',
      1, 'CLEAR'
    ) ->> 'deleted_count'
  )::int,
  2,
  'bulk clear replay retains its original deletion count'
);
reset role;

delete from auth.users
where id = 'b1000000-0000-4000-8000-000000000002';
select is(
  (
    select count(*)::int
    from public.learning_preferences
    where user_id = 'b1000000-0000-4000-8000-000000000002'
  ),
  0,
  'account deletion cascades learning preferences'
);

select * from finish();
rollback;
