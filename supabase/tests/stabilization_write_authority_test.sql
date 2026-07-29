begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'd1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'stabilization-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

select is(
  public.apply_daily_capture_branch_v1(
    'd1000000-0000-4000-8000-000000000001',
    '2026-07-29',
    'morning',
    'd1000000-0000-4000-8000-000000000101',
    repeat('1', 64),
    null,
    '{
      "branch_version":"daily-capture-v4",
      "capture_kind":"morning",
      "entry_date":"2026-07-29",
      "capture_id":"morning-1",
      "captured_at":"2026-07-29T06:30:00Z",
      "sleep_hours":8,
      "sleep_quality":8,
      "current_energy":7,
      "day_shape":"normal",
      "estimated_sleep_started_at":"2026-07-28T22:30:00Z",
      "woke_at":"2026-07-29T06:30:00Z",
      "estimated_sleep_minutes":480,
      "sleep_target_minutes":480
    }'::jsonb,
    '2026-07-29T06:31:00Z'
  ) ->> 'capture_id',
  'morning-1',
  'the first branch creates the canonical daily row'
);

reset role;
insert into public.behavioral_events (
  user_id, daily_log_id, event_type, value, unit, occurred_at, source
)
select
  user_id, id, 'manual_marker', 1, 'count',
  '2026-07-29T06:32:00Z', 'manual_import'
from public.daily_logs
where user_id = 'd1000000-0000-4000-8000-000000000001'
  and entry_date = '2026-07-29';

set local role service_role;
select is(
  public.apply_daily_capture_branch_v1(
    'd1000000-0000-4000-8000-000000000001',
    '2026-07-29',
    'evening',
    'd1000000-0000-4000-8000-000000000102',
    repeat('2', 64),
    null,
    '{
      "branch_version":"daily-capture-v4",
      "capture_kind":"evening",
      "entry_date":"2026-07-29",
      "capture_id":"evening-1",
      "captured_at":"2026-07-29T20:30:00Z",
      "mood":6,
      "energy":4,
      "stress_intensity":7,
      "stress_intensity_label":"high",
      "planned_sleep_time":"23:00",
      "sleep_target_minutes":480
    }'::jsonb,
    '2026-07-29T20:31:00Z'
  ) ->> 'capture_id',
  'evening-1',
  'a serialized Evening write merges after Morning without a row-wide CAS'
);

select is(
  (
    select metadata #>> '{captures,morning,capture_id}'
    from public.daily_logs
    where user_id = 'd1000000-0000-4000-8000-000000000001'
      and entry_date = '2026-07-29'
  ),
  'morning-1',
  'the other branch survives the merge'
);

select is(
  (
    select count(*)::int
    from public.behavioral_events
    where user_id = 'd1000000-0000-4000-8000-000000000001'
      and source = 'manual_import'
  ),
  1,
  'capture recomputation preserves unrelated behavioral events'
);

select ok(
  (
    public.apply_daily_capture_branch_v1(
      'd1000000-0000-4000-8000-000000000001',
      '2026-07-29',
      'evening',
      'd1000000-0000-4000-8000-000000000102',
      repeat('2', 64),
      null,
      '{
        "branch_version":"daily-capture-v4",
        "capture_kind":"evening",
        "entry_date":"2026-07-29",
        "capture_id":"evening-1",
        "captured_at":"2026-07-29T20:30:00Z"
      }'::jsonb,
      '2026-07-29T20:31:00Z'
    ) ->> 'replayed'
  )::boolean,
  'an exact request replay returns the durable result'
);

select throws_ok(
  $$
    select public.apply_daily_capture_branch_v1(
      'd1000000-0000-4000-8000-000000000001',
      '2026-07-29',
      'evening',
      'd1000000-0000-4000-8000-000000000103',
      repeat('3', 64),
      '{"capture_id":"wrong","captured_at":"2026-07-29T20:30:00Z"}',
      '{
        "branch_version":"daily-capture-v4",
        "capture_kind":"evening",
        "entry_date":"2026-07-29",
        "capture_id":"evening-2",
        "captured_at":"2026-07-29T20:40:00Z"
      }',
      '2026-07-29T20:41:00Z'
    )
  $$,
  'PT409',
  null,
  'same-branch compare-and-swap rejects a stale expected identity'
);

select throws_ok(
  $$
    select public.apply_daily_capture_branch_v1(
      'd1000000-0000-4000-8000-000000000001',
      '2026-07-29',
      'evening',
      'd1000000-0000-4000-8000-000000000102',
      repeat('4', 64),
      null,
      '{
        "branch_version":"daily-capture-v4",
        "capture_kind":"evening",
        "entry_date":"2026-07-29",
        "capture_id":"evening-1",
        "captured_at":"2026-07-29T20:30:00Z"
      }',
      '2026-07-29T20:31:00Z'
    )
  $$,
  'PT409',
  null,
  'a request id cannot replay with a different fingerprint'
);

select is(
  (
    public.apply_account_timezone_v2(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000201',
      repeat('5', 64),
      1,
      'Europe/Berlin',
      '2026-07-29T21:00:00Z'
    ) ->> 'revision'
  )::int,
  2,
  'timezone CAS advances its independent revision'
);

select throws_ok(
  $$
    select public.apply_account_timezone_v2(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000202',
      repeat('6', 64),
      1,
      'Europe/London',
      '2026-07-29T21:01:00Z'
    )
  $$,
  'PT409',
  null,
  'two timezone writes cannot both win from one revision'
);

select is(
  (
    public.apply_account_preparation_budget_v2(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000203',
      repeat('7', 64),
      1,
      120,
      '2026-07-29T21:02:00Z'
    ) ->> 'revision'
  )::int,
  2,
  'preparation budget has an independent compare-and-swap revision'
);

select ok(
  (
    public.create_calendar_connection_v1(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000401',
      repeat('8', 64),
      'Stabilization calendar',
      '2026-07-29T21:03:00Z'
    ) ->> 'connection_id'
  )::uuid is not null,
  'a consented calendar source is available for timezone-race checks'
);

select ok(
  not (
    public.apply_calendar_import_v2(
      'd1000000-0000-4000-8000-000000000001',
      (
        select id from public.calendar_connections
        where create_request_id =
          'd1000000-0000-4000-8000-000000000401'
      ),
      'd1000000-0000-4000-8000-000000000402',
      repeat('9', 64),
      repeat('a', 64),
      repeat('b', 64),
      '2026-07-01',
      '2026-10-14',
      'Europe/Berlin',
      'Europe/Berlin',
      2,
      '{
        "accepted":0,
        "cancelled":0,
        "out_of_window":0,
        "unsupported_recurring":0,
        "invalid":0
      }',
      '[]',
      '[]',
      '2026-07-29T21:04:00Z'
    ) ->> 'replayed'
  )::boolean,
  'a new calendar import is bound to the current profile timezone revision'
);

select ok(
  not (
    public.apply_calendar_import_v2(
      'd1000000-0000-4000-8000-000000000001',
      (
        select id from public.calendar_connections
        where create_request_id =
          'd1000000-0000-4000-8000-000000000401'
      ),
      'd1000000-0000-4000-8000-000000000403',
      repeat('c', 64),
      repeat('d', 64),
      repeat('e', 64),
      '2026-07-01',
      '2026-10-14',
      'Europe/Berlin',
      'Europe/Berlin',
      2,
      '{
        "accepted":0,
        "cancelled":0,
        "out_of_window":0,
        "unsupported_recurring":0,
        "invalid":0
      }',
      '[]',
      '[]',
      '2026-07-29T21:05:00Z'
    ) ->> 'replayed'
  )::boolean,
  'a replacement calendar import advances the current projection'
);

select results_eq(
  $$
    select planning_status
    from public.calendar_imports
    where user_id = 'd1000000-0000-4000-8000-000000000001'
    order by imported_at
  $$,
  $$ values ('not_imported'::text), ('current'::text) $$,
  'only the newest connected calendar import remains current'
);

select is(
  (
    public.apply_account_timezone_v2(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000404',
      repeat('f', 64),
      2,
      'Europe/London',
      '2026-07-29T21:06:00Z'
    ) ->> 'revision'
  )::int,
  3,
  'a timezone change advances the profile identity under the owner lock'
);

select is(
  (
    select planning_status
    from public.calendar_imports
    where request_id = 'd1000000-0000-4000-8000-000000000403'
  ),
  'profile_timezone_changed',
  'the prior current import becomes unavailable for planning'
);

select ok(
  (
    public.apply_calendar_import_v2(
      'd1000000-0000-4000-8000-000000000001',
      (
        select id from public.calendar_connections
        where create_request_id =
          'd1000000-0000-4000-8000-000000000401'
      ),
      'd1000000-0000-4000-8000-000000000403',
      repeat('c', 64),
      repeat('d', 64),
      repeat('e', 64),
      '2026-07-01',
      '2026-10-14',
      'Europe/Berlin',
      'Europe/Berlin',
      2,
      '{
        "accepted":0,
        "cancelled":0,
        "out_of_window":0,
        "unsupported_recurring":0,
        "invalid":0
      }',
      '[]',
      '[]',
      '2026-07-29T21:05:00Z'
    ) ->> 'replayed'
  )::boolean,
  'an exact completed Calendar replay remains valid after timezone change'
);

select throws_ok(
  $$
    select public.apply_calendar_import_v2(
      'd1000000-0000-4000-8000-000000000001',
      (
        select id from public.calendar_connections
        where create_request_id =
          'd1000000-0000-4000-8000-000000000401'
      ),
      'd1000000-0000-4000-8000-000000000405',
      repeat('0', 64),
      repeat('1', 64),
      repeat('2', 64),
      '2026-07-01',
      '2026-10-14',
      'Europe/Berlin',
      'Europe/Berlin',
      2,
      '{
        "accepted":0,
        "cancelled":0,
        "out_of_window":0,
        "unsupported_recurring":0,
        "invalid":0
      }',
      '[]',
      '[]',
      '2026-07-29T21:07:00Z'
    )
  $$,
  'PT409',
  null,
  'a newly claimed Calendar import fails closed against a stale timezone identity'
);
reset role;

select ok(
  not has_table_privilege(
    'authenticated',
    'public.daily_capture_request_identities',
    'select'
  ),
  'authenticated cannot read the Capture anti-replay ledger'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.account_setting_request_identities',
    'select'
  ),
  'authenticated cannot read the Settings anti-replay ledger'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.daily_capture_request_identities',
    'select'
  )
  and has_table_privilege(
    'service_role',
    'public.account_setting_request_identities',
    'select'
  ),
  'service role retains only the backend ledger visibility it needs'
);
select ok(
  not has_table_privilege('authenticated', 'public.daily_logs', 'insert'),
  'authenticated direct Daily Log writes are revoked'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.behavioral_events',
    'delete'
  ),
  'authenticated direct Behavioral Event mutation is revoked'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.set_daily_preparation_budget_v1(uuid,integer)',
    'execute'
  ),
  'the V1 preparation setter has no remaining service write authority'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.apply_calendar_import_v1(uuid,uuid,uuid,text,text,text,date,date,text,jsonb,jsonb,jsonb,timestamp with time zone)',
    'execute'
  ),
  'the V1 calendar import writer has no remaining service authority'
);
select has_trigger(
  'public',
  'planner_action_plan_revisions',
  'planner_action_revision_timezone_guard_v1',
  'Planner revisions have the timezone confirmation guard'
);
select has_trigger(
  'public',
  'deadline_plan_revisions',
  'deadline_plan_revision_timezone_guard_v1',
  'Deadline revisions have the timezone confirmation guard'
);

insert into public.habits (
  id, user_id, title, frequency, target, active, metadata
) values (
  'd1000000-0000-4000-8000-000000000301',
  'd1000000-0000-4000-8000-000000000001',
  'Setup routine', 'daily', 1, true,
  '{"managed_by":"setup","source":"intake-v1"}'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'd1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$
    update public.habits
    set metadata = '{}'
    where id = 'd1000000-0000-4000-8000-000000000301'
  $$,
  'PT403',
  null,
  'an application role cannot unmark a Setup-owned Habit'
);
select throws_ok(
  $$
    delete from public.habits
    where id = 'd1000000-0000-4000-8000-000000000301'
  $$,
  'PT403',
  null,
  'an application role cannot delete a Setup-owned Habit'
);
select throws_ok(
  $$
    insert into public.habits (
      id, user_id, title, frequency, target, active, metadata,
      creation_request_id
    ) values (
      'd1000000-0000-4000-8000-000000000302',
      'd1000000-0000-4000-8000-000000000001',
      'Forged Setup routine', 'daily', 1, true,
      '{"managed_by":"setup","source":"intake-v1"}',
      'd1000000-0000-4000-8000-000000000302'
    )
  $$,
  'PT403',
  null,
  'an application role cannot forge Setup ownership markers'
);
select throws_ok(
  $$
    insert into public.tasks (
      id, user_id, title, source
    ) values (
      'd1000000-0000-4000-8000-000000000303',
      'd1000000-0000-4000-8000-000000000001',
      'Missing creation identity', 'manual'
    )
  $$,
  '22023',
  null,
  'new manual Task rows require a creation identity'
);
select lives_ok(
  $$
    insert into public.tasks (
      id, user_id, title, source, creation_request_id
    ) values (
      'd1000000-0000-4000-8000-000000000304',
      'd1000000-0000-4000-8000-000000000001',
      'Stable creation identity', 'manual',
      'd1000000-0000-4000-8000-000000000304'
    )
  $$,
  'a manual Task with a creation identity is accepted'
);
select ok(
  (
    select creation_fingerprint ~ '^[0-9a-f]{64}$'
    from public.tasks
    where id = 'd1000000-0000-4000-8000-000000000304'
  ),
  'the database derives the immutable creation payload fingerprint'
);

reset role;
select * from finish();
rollback;
