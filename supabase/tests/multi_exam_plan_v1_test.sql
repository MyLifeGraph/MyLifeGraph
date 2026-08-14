begin;
create temporary table multi_exam_test_environment (
  dblink_host text,
  dblink_user text,
  dblink_password text
) on commit preserve rows;
insert into multi_exam_test_environment default values;

create or replace function pg_temp.multi_exam_drop_owned_dblink_v1()
returns boolean
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
declare
  marker_relation regclass :=
    to_regclass('private.multi_exam_dblink_extension_test_marker');
  marker_owner name;
  marker_rows bigint;
  marker_extension_oid oid;
  marker_extension_owner name;
  marker_extension_schema name;
  marker_extension_version text;
  current_extension_oid oid;
  current_extension_owner name;
  current_extension_schema name;
  current_extension_version text;
begin
  if marker_relation is null then
    return false;
  end if;

  select pg_get_userbyid(relowner)
  into marker_owner
  from pg_class
  where oid = marker_relation and relkind = 'r';
  if marker_owner is distinct from current_user then
    raise exception 'Multi-Exam dblink test marker ownership is invalid.';
  end if;

  execute 'select count(*) '
    'from private.multi_exam_dblink_extension_test_marker'
    into strict marker_rows;
  if marker_rows <> 1 then
    raise exception 'Multi-Exam dblink test marker cardinality is invalid.';
  end if;

  execute
    'select extension_oid, extension_owner, extension_schema, '
    'extension_version '
    'from private.multi_exam_dblink_extension_test_marker '
    'where marker = ''multi-exam-plan-v1-pgtap-dblink-v1'''
    into strict marker_extension_oid, marker_extension_owner,
      marker_extension_schema, marker_extension_version;

  select extension.oid, pg_get_userbyid(extension.extowner),
    namespace.nspname, extension.extversion
  into current_extension_oid, current_extension_owner,
    current_extension_schema, current_extension_version
  from pg_extension as extension
  join pg_namespace as namespace on namespace.oid = extension.extnamespace
  where extension.extname = 'dblink';

  if current_extension_oid is distinct from marker_extension_oid
     or current_extension_owner is distinct from marker_extension_owner
     or current_extension_schema is distinct from marker_extension_schema
     or current_extension_version is distinct from marker_extension_version then
    raise exception 'Multi-Exam dblink test marker does not own this extension.';
  end if;

  execute 'drop extension dblink';
  execute 'drop table private.multi_exam_dblink_extension_test_marker';
  return true;
end;
$$;

do $$
begin
  perform pg_temp.multi_exam_drop_owned_dblink_v1();
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_extension where extname = 'dblink'
  ) then
    execute 'create extension dblink with schema extensions';
    execute $marker$
      create table private.multi_exam_dblink_extension_test_marker (
        marker text primary key
          check (marker = 'multi-exam-plan-v1-pgtap-dblink-v1'),
        extension_oid oid not null,
        extension_owner name not null,
        extension_schema name not null,
        extension_version text not null
      )
    $marker$;
    insert into private.multi_exam_dblink_extension_test_marker (
      marker, extension_oid, extension_owner, extension_schema,
      extension_version
    )
    select 'multi-exam-plan-v1-pgtap-dblink-v1', extension.oid,
      pg_get_userbyid(extension.extowner), namespace.nspname,
      extension.extversion
    from pg_extension as extension
    join pg_namespace as namespace on namespace.oid = extension.extnamespace
    where extension.extname = 'dblink';
  end if;
end;
$$;

-- A failed concurrency phase commits its fixture before opening the second
-- session. Remove only that fixed test identity and its test-owned helpers so
-- the same file repairs an interrupted prior run before rebuilding the fixture.
drop function if exists private.multi_exam_test_confirm_and_hold_v1();
drop function if exists private.multi_exam_test_propose_and_hold_v1();
drop function if exists private.multi_exam_test_wait_for_advisory_lock_v1(int);
drop table if exists private.multi_exam_concurrency_fixture_test;
delete from auth.users
where id = 'e5000000-0000-4000-8000-000000000001';
do $$
begin
  if exists (
    select 1 from pg_roles
    where rolname = 'multi_exam_concurrency_test_login'
  ) then
    execute 'revoke execute on function '
      'public.propose_multi_exam_plan_v1('
      'uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,'
      'jsonb,timestamptz) from multi_exam_concurrency_test_login';
    execute 'revoke execute on function '
      'public.confirm_multi_exam_plan_v1('
      'uuid,uuid,uuid,text,integer,boolean,timestamptz) '
      'from multi_exam_concurrency_test_login';
    execute 'revoke usage on schema private '
      'from multi_exam_concurrency_test_login';
    execute 'drop role multi_exam_concurrency_test_login';
  end if;
end;
$$;
commit;
begin;
select plan(104);

select ok(to_regclass('private.multi_exam_plan_batches') is not null,
  'multi_exam_plan_batches exists privately');
select ok(to_regclass('private.multi_exam_plan_batch_revisions') is not null,
  'multi_exam_plan_batch_revisions exists privately');
select ok(to_regclass('private.multi_exam_plan_batch_items') is not null,
  'multi_exam_plan_batch_items exists privately');
select ok(to_regclass('private.multi_exam_plan_batch_links') is not null,
  'multi_exam_plan_batch_links exists privately');
select ok(to_regclass('private.multi_exam_plan_request_identities') is not null,
  'multi_exam_plan_request_identities exists privately');

select has_function('public', 'get_multi_exam_plan_snapshot_v1',
  array['uuid', 'timestamp with time zone']);
select has_function('public', 'get_multi_exam_plan_request_v1',
  array['uuid', 'uuid']);
select has_function('public', 'get_multi_exam_plan_projection_v1',
  array['uuid', 'uuid']);
select has_function('public', 'propose_multi_exam_plan_v1', array[
  'uuid', 'text', 'uuid', 'uuid', 'text', 'uuid', 'integer',
  'timestamp with time zone', 'text', 'text', 'boolean', 'jsonb',
  'timestamp with time zone'
]);
select has_function('public', 'confirm_multi_exam_plan_v1', array[
  'uuid', 'uuid', 'uuid', 'text', 'integer', 'boolean',
  'timestamp with time zone'
]);
select has_function('public', 'cancel_multi_exam_plan_v1', array[
  'uuid', 'uuid', 'uuid', 'text', 'integer', 'timestamp with time zone'
]);

select is((select relrowsecurity from pg_class
  where oid = 'private.multi_exam_plan_batches'::regclass), true,
  'batch metadata enables RLS');
select is((select relforcerowsecurity from pg_class
  where oid = 'private.multi_exam_plan_batches'::regclass), true,
  'batch metadata forces RLS');
select is((select relforcerowsecurity from pg_class
  where oid = 'private.multi_exam_plan_batch_revisions'::regclass), true,
  'batch revisions force RLS');
select is((select relforcerowsecurity from pg_class
  where oid = 'private.multi_exam_plan_batch_items'::regclass), true,
  'batch items force RLS');
select is((select relforcerowsecurity from pg_class
  where oid = 'private.multi_exam_plan_batch_links'::regclass), true,
  'batch links force RLS');
select is((select relforcerowsecurity from pg_class
  where oid = 'private.multi_exam_plan_request_identities'::regclass), true,
  'request ledger forces RLS');

select ok(
  to_regclass('private.multi_exam_plan_batches_owner_updated_idx') is not null,
  'batch history has its bounded owner/update list index'
);
select ok(
  to_regclass('private.multi_exam_plan_batches_target_fk_idx') is not null,
  'batch target foreign key has a matching lookup index'
);
select ok(
  to_regclass('private.multi_exam_plan_batch_links_revision_fk_idx') is not null,
  'batch child revision foreign key has a matching lookup index'
);
select ok(
  to_regclass('private.multi_exam_plan_batch_links_item_fk_idx') is not null,
  'batch item foreign key has a matching lookup index'
);
select ok(
  to_regclass('private.multi_exam_plan_requests_target_fk_idx') is not null,
  'request target foreign key has a matching lookup index'
);
select ok(
  to_regclass('private.multi_exam_plan_requests_result_fk_idx') is not null,
  'request result foreign key has a matching lookup index'
);
select ok(
  to_regclass('private.multi_exam_plan_requests_balance_fk_idx') is not null,
  'request balance foreign key has a matching lookup index'
);
select has_trigger(
  'public', 'profiles', 'a_multi_exam_context_owner_lock_profiles_v1',
  'profile context writes take the shared owner lock first'
);
select has_trigger(
  'public', 'tasks', 'a_multi_exam_context_owner_lock_tasks_v1',
  'direct Task writes take the shared owner lock before release triggers'
);
select has_trigger(
  'public', 'habits', 'a_multi_exam_context_owner_lock_habits_v1',
  'direct Habit writes take the shared owner lock before release triggers'
);
select has_trigger(
  'public', 'schedule_items', 'a_multi_exam_context_owner_lock_schedule_v1',
  'fixed-schedule context writes take the shared owner lock first'
);
select has_trigger(
  'public', 'focus_sessions', 'a_multi_exam_context_owner_lock_focus_v1',
  'Focus context writes take the shared owner lock first'
);
select has_trigger(
  'public', 'learning_preferences',
  'a_multi_exam_context_owner_lock_learning_v1',
  'learned-timing permission writes take the shared owner lock first'
);

select function_privs_are('public', 'get_multi_exam_plan_snapshot_v1',
  array['uuid', 'timestamp with time zone'], 'service_role', array['EXECUTE']);
select function_privs_are('public', 'get_multi_exam_plan_projection_v1',
  array['uuid', 'uuid'], 'service_role', array['EXECUTE']);
select function_privs_are('public', 'confirm_multi_exam_plan_v1', array[
  'uuid', 'uuid', 'uuid', 'text', 'integer', 'boolean',
  'timestamp with time zone'
], 'service_role', array['EXECUTE']);
select function_privs_are('public', 'cancel_multi_exam_plan_v1', array[
  'uuid', 'uuid', 'uuid', 'text', 'integer', 'timestamp with time zone'
], 'service_role', array['EXECUTE']);

select function_privs_are('public', 'get_multi_exam_plan_snapshot_v1',
  array['uuid', 'timestamp with time zone'], 'authenticated', array[]::text[]);
select function_privs_are('public', 'propose_multi_exam_plan_v1', array[
  'uuid', 'text', 'uuid', 'uuid', 'text', 'uuid', 'integer',
  'timestamp with time zone', 'text', 'text', 'boolean', 'jsonb',
  'timestamp with time zone'
], 'authenticated', array[]::text[]);
select function_privs_are('public',
  'confirm_deadline_plan_v1_without_exam_balance_guard', array[
    'uuid', 'uuid', 'uuid', 'text', 'integer', 'timestamp with time zone'
  ], 'service_role', array[]::text[]);
select function_privs_are('private', 'multi_exam_plan_context_payload_v1',
  array['uuid'], 'service_role', array[]::text[]);
select function_privs_are('private', 'lock_multi_exam_context_owner_v1',
  array[]::text[], 'service_role', array[]::text[]);
select function_privs_are('private', 'multi_exam_plan_learned_timing_marker_v1',
  array['uuid', 'boolean'], 'service_role', array[]::text[]);
select function_privs_are('public',
  'propose_deadline_plan_with_timing_v1_without_balance_guard', array[
    'uuid', 'uuid', 'text', 'uuid', 'integer', 'jsonb', 'jsonb',
    'timestamp with time zone'
  ], 'service_role', array[]::text[]);
select function_privs_are('public',
  'mutate_deadline_plan_lifecycle_v1_without_balance_guard', array[
    'uuid', 'uuid', 'uuid', 'text', 'integer', 'text',
    'timestamp with time zone'
  ], 'service_role', array[]::text[]);

select is((select prosecdef from pg_proc where oid =
  'public.propose_multi_exam_plan_v1(uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,jsonb,timestamptz)'::regprocedure),
  true, 'proposal RPC is SECURITY DEFINER');
select is((select proconfig from pg_proc where oid =
  'public.propose_multi_exam_plan_v1(uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,jsonb,timestamptz)'::regprocedure),
  array['search_path=pg_catalog, pg_temp']::text[],
  'proposal RPC pins search_path');
select is((select proconfig from pg_proc where oid =
  'public.confirm_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,boolean,timestamptz)'::regprocedure),
  array['search_path=pg_catalog, pg_temp']::text[],
  'confirm RPC pins search_path');
select is((select proconfig from pg_proc where oid =
  'public.cancel_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'::regprocedure),
  array['search_path=pg_catalog, pg_temp']::text[],
  'cancel RPC pins search_path');
select is((select prosecdef from pg_proc where oid =
  'private.lock_multi_exam_context_owner_v1()'::regprocedure),
  true, 'legacy context writer lock trigger is SECURITY DEFINER');
select is((select proconfig from pg_proc where oid =
  'private.lock_multi_exam_context_owner_v1()'::regprocedure),
  array['search_path=pg_catalog, pg_temp']::text[],
  'legacy context writer lock trigger pins search_path');
select ok(
  position('pg_advisory_xact_lock' in pg_get_functiondef(
    'private.lock_multi_exam_context_owner_v1()'::regprocedure
  )) > 0,
  'legacy context writers acquire the canonical owner advisory lock'
);
select ok(
  position('link.status = ''proposed''' in pg_get_functiondef(
    'public.confirm_deadline_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'::regprocedure
  )) > 0
  and position('confirm_deadline_plan_v1_without_exam_balance_guard' in
    pg_get_functiondef(
      'public.confirm_deadline_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'::regprocedure
    )
  ) > 0,
  'single confirmation guards a proposed batch child before its inner chain'
);
select ok(
  position('link.status = ''proposed''' in pg_get_functiondef(
    'public.propose_deadline_plan_with_timing_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamptz)'::regprocedure
  )) > 0
  and position('without_balance_guard' in pg_get_functiondef(
    'public.propose_deadline_plan_with_timing_v1(uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamptz)'::regprocedure
  )) > 0,
  'normal single-plan proposal rejects a pending batch child'
);
select ok(
  position('link.status = ''proposed''' in pg_get_functiondef(
    'public.mutate_deadline_plan_lifecycle_v1(uuid,uuid,uuid,text,integer,text,timestamptz)'::regprocedure
  )) > 0
  and position('without_balance_guard' in pg_get_functiondef(
    'public.mutate_deadline_plan_lifecycle_v1(uuid,uuid,uuid,text,integer,text,timestamptz)'::regprocedure
  )) > 0,
  'normal lifecycle mutation rejects a pending batch child'
);
select ok(
  position('confirmation_fingerprint' in pg_get_functiondef(
    'public.confirm_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,boolean,timestamptz)'::regprocedure
  )) > 0
  and position('multi_exam_plan_learned_timing_marker_v1' in
    pg_get_functiondef(
      'public.confirm_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,boolean,timestamptz)'::regprocedure
    )
  ) > 0
  and position('confirm_deadline_plan_v1_without_exam_balance_guard' in
    pg_get_functiondef(
      'public.confirm_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,boolean,timestamptz)'::regprocedure
    )
  ) > 0,
  'batch confirmation checks post-proposal CAS and uses the ungranted inner chain'
);
select ok(
  position('propose_deadline_plan_with_timing_v1_without_balance_guard' in
    pg_get_functiondef(
      'public.propose_multi_exam_plan_v1(uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,jsonb,timestamptz)'::regprocedure
    )
  ) > 0,
  'batch proposal uses the validated ungranted Deadline proposal chain'
);
select ok(
  position('update public.deadline_plan_revisions as proposed' in
    pg_get_functiondef(
      'public.cancel_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'::regprocedure
    )
  ) > 0
  and position('set state = ''superseded''' in pg_get_functiondef(
    'public.cancel_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'::regprocedure
  )) > 0
  and position('update public.deadline_plans' in pg_get_functiondef(
    'public.cancel_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)'::regprocedure
  )) = 0,
  'batch cancellation supersedes staged revisions without cancelling active plans'
);
select ok(
  position('public.deadline_plan_revisions' in pg_get_functiondef(
    'private.multi_exam_plan_context_payload_v1(uuid)'::regprocedure
  )) > 0
  and position('public.focus_sessions' in pg_get_functiondef(
    'private.multi_exam_plan_context_payload_v1(uuid)'::regprocedure
  )) > 0
  and position('public.calendar_events' in pg_get_functiondef(
    'private.multi_exam_plan_context_payload_v1(uuid)'::regprocedure
  )) > 0
  and position('public.planner_commitments' in pg_get_functiondef(
    'private.multi_exam_plan_context_payload_v1(uuid)'::regprocedure
  )) > 0
  and position('public.learning_preferences' in pg_get_functiondef(
    'private.multi_exam_plan_context_payload_v1(uuid)'::regprocedure
  )) > 0,
  'context CAS includes plan, Focus, Calendar, Planner, and learning authorities'
);

select throws_ok(
  $$select public.get_multi_exam_plan_snapshot_v1(null, now())$$,
  '22023', 'Exam balance snapshot arguments are required.',
  'snapshot rejects missing owner'
);
select throws_ok(
  $$select public.propose_multi_exam_plan_v1(
    null, 'no_change', null, gen_random_uuid(), repeat('a', 64),
    gen_random_uuid(), 1, now(), repeat('b', 64), 'UTC', true, '[]', now()
  )$$,
  '22023', 'Exam balance proposal arguments are invalid.',
  'proposal rejects missing owner'
);
select throws_ok(
  $$select public.propose_multi_exam_plan_v1(
    gen_random_uuid(), 'no_change', null, gen_random_uuid(), repeat('a', 64),
    gen_random_uuid(), 1, now() + interval '1 minute', repeat('b', 64),
    'UTC', true, '[]', now()
  )$$,
  '22023', 'Exam balance proposal arguments are invalid.',
  'proposal rejects a snapshot from after the mutation instant'
);
select throws_ok(
  $$select public.confirm_multi_exam_plan_v1(
    gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), repeat('a', 64),
    2, true, now()
  )$$,
  '22023', 'Exam balance confirmation arguments are invalid.',
  'confirm rejects another revision'
);
select throws_ok(
  $$select public.cancel_multi_exam_plan_v1(
    gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), repeat('a', 64),
    2, now()
  )$$,
  '22023', 'Exam balance cancellation arguments are invalid.',
  'cancel rejects another revision'
);

select is(private.multi_exam_plan_review_is_valid_v1(
  jsonb_build_object(
    'current_blocks', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'starts_at', '2026-08-20T09:00:00Z',
      'ends_at', '2026-08-20T10:00:00Z',
      'reserved_ends_at', '2026-08-20T10:00:00Z',
      'planned_minutes', 60, 'recovery_minutes', 0, 'credited_minutes', 0
    )),
    'proposed_blocks', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'starts_at', '2026-08-21T09:00:00Z',
      'ends_at', '2026-08-21T09:25:00Z',
      'reserved_ends_at', '2026-08-21T09:25:00Z',
      'planned_minutes', 25, 'recovery_minutes', 0, 'credited_minutes', 0
    )),
    'retained_minutes', 0, 'shifted_minutes', 25,
    'removed_minutes', 35, 'added_minutes', 0,
    'retained_block_count', 0, 'shifted_block_count', 1,
    'removed_block_count', 0, 'added_block_count', 0
  )
), true, 'SQL review validates old-unmatched greater than new-unmatched');

select is(private.multi_exam_plan_review_is_valid_v1(
  jsonb_build_object(
    'current_blocks', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'starts_at', '2026-08-20T09:00:00Z',
      'ends_at', '2026-08-20T09:25:00Z',
      'reserved_ends_at', '2026-08-20T09:25:00Z',
      'planned_minutes', 25, 'recovery_minutes', 0, 'credited_minutes', 0
    )),
    'proposed_blocks', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'starts_at', '2026-08-21T09:00:00Z',
      'ends_at', '2026-08-21T10:00:00Z',
      'reserved_ends_at', '2026-08-21T10:00:00Z',
      'planned_minutes', 60, 'recovery_minutes', 0, 'credited_minutes', 0
    )),
    'retained_minutes', 0, 'shifted_minutes', 25,
    'removed_minutes', 0, 'added_minutes', 35,
    'retained_block_count', 0, 'shifted_block_count', 1,
    'removed_block_count', 0, 'added_block_count', 0
  )
), true, 'SQL review validates new-unmatched greater than old-unmatched');

select is(private.multi_exam_plan_review_is_valid_v1(
  jsonb_build_object(
    'current_blocks', jsonb_build_array(
      jsonb_build_object(
        'sequence', 1, 'starts_at', '2026-08-20T09:00:00Z',
        'ends_at', '2026-08-20T09:30:00Z',
        'reserved_ends_at', '2026-08-20T09:30:00Z',
        'planned_minutes', 30, 'recovery_minutes', 0, 'credited_minutes', 10
      ),
      jsonb_build_object(
        'sequence', 2, 'starts_at', '2026-08-20T09:00:00Z',
        'ends_at', '2026-08-20T09:30:00Z',
        'reserved_ends_at', '2026-08-20T09:30:00Z',
        'planned_minutes', 30, 'recovery_minutes', 0, 'credited_minutes', 0
      )
    ),
    'proposed_blocks', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'starts_at', '2026-08-20T09:00:00Z',
      'ends_at', '2026-08-20T09:30:00Z',
      'reserved_ends_at', '2026-08-20T09:30:00Z',
      'planned_minutes', 30, 'recovery_minutes', 0, 'credited_minutes', 0
    )),
    'retained_minutes', 30, 'shifted_minutes', 0,
    'removed_minutes', 20, 'added_minutes', 0,
    'retained_block_count', 1, 'shifted_block_count', 0,
    'removed_block_count', 1, 'added_block_count', 0
  )
), true, 'SQL review handles duplicate signatures and partial credit exactly');

select is(private.multi_exam_plan_review_is_valid_v1(
  jsonb_build_object(
    'current_blocks', '[]'::jsonb,
    'proposed_blocks', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'starts_at', '2026-08-21T09:00:00Z',
      'ends_at', '2026-08-21T09:30:00Z',
      'reserved_ends_at', '2026-08-21T09:30:00Z',
      'planned_minutes', 30, 'recovery_minutes', 0, 'credited_minutes', 0
    )),
    'retained_minutes', 0, 'shifted_minutes', 30,
    'removed_minutes', 0, 'added_minutes', 0,
    'retained_block_count', 0, 'shifted_block_count', 1,
    'removed_block_count', 0, 'added_block_count', 0
  )
), false, 'SQL review rejects a forged change summary');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e5000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'multi-exam@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')),
  '2026-08-01T08:00:00Z',
  '{"provider":"email","providers":["email"]}', '{}',
  '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
);

update public.profiles
set timezone = 'UTC', timezone_revision = 2,
    daily_preparation_budget_minutes = 240
where id = 'e5000000-0000-4000-8000-000000000001';

insert into public.planner_preferences (
  user_id, use_calendar_busy_time, created_at, updated_at
) values (
  'e5000000-0000-4000-8000-000000000001', false,
  '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
);

select set_config('mylifegraph.deadline_plan_rpc', 'on', true);

insert into public.tasks (
  id, user_id, title, status, source, metadata, created_at, updated_at
) values
  (
    'e5000000-0000-4000-8000-000000000010',
    'e5000000-0000-4000-8000-000000000001',
    'Algorithms', 'todo', 'deadline-plan-v1',
    '{"contract_version":"deadline-plan-v1"}',
    '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  ),
  (
    'e5000000-0000-4000-8000-000000000020',
    'e5000000-0000-4000-8000-000000000001',
    'Physics', 'todo', 'deadline-plan-v1',
    '{"contract_version":"deadline-plan-v1"}',
    '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  ),
  (
    'e5000000-0000-4000-8000-000000000030',
    'e5000000-0000-4000-8000-000000000001',
    'Direct Task writer probe', 'todo', 'manual', '{}',
    '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  );

insert into public.habits (
  id, user_id, title, frequency, target, active, metadata,
  created_at, updated_at
) values (
  'e5000000-0000-4000-8000-000000000040',
  'e5000000-0000-4000-8000-000000000001',
  'Direct Habit writer probe', 'daily', 1, true, '{}',
  '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
);

insert into public.deadline_plans (
  id, user_id, status, kind, title, managed_task_id,
  original_estimated_total_minutes, original_credited_prior_minutes,
  current_revision, latest_revision, first_activated_at, created_at, updated_at
) values
  (
    'e5000000-0000-4000-8000-000000000010',
    'e5000000-0000-4000-8000-000000000001',
    'active', 'exam', 'Algorithms',
    'e5000000-0000-4000-8000-000000000010',
    30, 0, 1, 1, '2026-08-01T08:00:00Z',
    '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  ),
  (
    'e5000000-0000-4000-8000-000000000020',
    'e5000000-0000-4000-8000-000000000001',
    'active', 'exam', 'Physics',
    'e5000000-0000-4000-8000-000000000020',
    30, 0, 1, 1, '2026-08-01T08:00:00Z',
    '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  );

insert into public.deadline_plan_revisions (
  id, user_id, plan_id, revision, base_revision, state, kind, title,
  deadline_at, estimated_total_minutes, credited_prior_minutes,
  preferred_session_minutes, max_daily_minutes, planning_start_on,
  buffer_days, source_kind, use_calendar_availability, timezone,
  best_energy_window, planning_fingerprint,
  tracked_focus_minutes_at_proposal, remaining_minutes_at_proposal,
  planned_minutes, unscheduled_minutes, created_at, activated_at
) values
  (
    'e5000000-0000-4000-8000-000000000011',
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000010',
    1, 0, 'active', 'exam', 'Algorithms',
    '2026-09-10T18:00:00Z', 30, 0, 30, 60, '2026-08-13',
    0, 'manual', false, 'UTC', 'morning', repeat('1', 64),
    0, 30, 30, 0, '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  ),
  (
    'e5000000-0000-4000-8000-000000000021',
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000020',
    1, 0, 'active', 'exam', 'Physics',
    '2026-09-11T18:00:00Z', 30, 0, 30, 60, '2026-08-13',
    0, 'manual', false, 'UTC', 'morning', repeat('2', 64),
    0, 30, 30, 0, '2026-08-01T08:00:00Z', '2026-08-01T08:00:00Z'
  );

insert into public.deadline_plan_blocks (
  id, user_id, plan_id, revision, sequence, reservation_state,
  starts_at, ends_at, local_date, local_start_time, local_end_time,
  planned_minutes, recovery_minutes, reserved_ends_at, created_at, updated_at
) values
  (
    'e5000000-0000-4000-8000-000000000012',
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000010',
    1, 1, 'active', '2026-08-20T09:00:00Z', '2026-08-20T09:30:00Z',
    '2026-08-20', '09:00:00', '09:30:00', 30, 0,
    '2026-08-20T09:30:00Z', '2026-08-01T08:00:00Z',
    '2026-08-01T08:00:00Z'
  ),
  (
    'e5000000-0000-4000-8000-000000000022',
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000020',
    1, 1, 'active', '2026-08-20T10:00:00Z', '2026-08-20T10:30:00Z',
    '2026-08-20', '10:00:00', '10:30:00', 30, 0,
    '2026-08-20T10:30:00Z', '2026-08-01T08:00:00Z',
    '2026-08-01T08:00:00Z'
  );

create temporary table multi_exam_lifecycle_fixture (
  name text primary key,
  value jsonb not null
) on commit preserve rows;

insert into multi_exam_lifecycle_fixture (name, value)
select 'snapshot', public.get_multi_exam_plan_snapshot_v1(
  'e5000000-0000-4000-8000-000000000001',
  '2026-08-13T09:00:00Z'
);

insert into multi_exam_lifecycle_fixture (name, value)
select name, jsonb_build_object(
  'plan_id', plan_id,
  'base_revision', 1,
  'kind', 'exam',
  'title', title,
  'deadline_at', deadline_at,
  'estimated_total_minutes', 30,
  'credited_prior_minutes', 0,
  'preferred_session_minutes', 30,
  'max_daily_minutes', 60,
  'planning_start_on', '2026-08-13',
  'buffer_days', 0,
  'source_kind', 'manual',
  'source_calendar_event_id', null,
  'source_calendar_event_fingerprint', null,
  'use_calendar_availability', false,
  'availability_connection_id', null,
  'availability_import_id', null,
  'timezone', 'UTC',
  'best_energy_window', 'morning',
  'planning_fingerprint', repeat(fingerprint_digit, 64),
  'tracked_focus_minutes_at_proposal', 0,
  'remaining_minutes_at_proposal', 30,
  'planned_minutes', 30,
  'unscheduled_minutes', 0,
  'study_setup_revision', null,
  'recovery_minutes', 0,
  'timing_preference', jsonb_build_object(
    'source', 'setup', 'window', null, 'evidence_count', 0,
    'evidence_starts_on', null, 'evidence_ends_on', null,
    'evidence_fingerprint', null, 'fell_back_to_setup', false,
    'warning', null
  )
)
from (values
  ('proposal-a', 'e5000000-0000-4000-8000-000000000010',
    'Algorithms', '2026-09-10T18:00:00Z', '3'),
  ('proposal-b', 'e5000000-0000-4000-8000-000000000020',
    'Physics', '2026-09-11T18:00:00Z', '4')
) as rows(name, plan_id, title, deadline_at, fingerprint_digit);

insert into multi_exam_lifecycle_fixture (name, value) values
  ('blocks-a', jsonb_build_array(jsonb_build_object(
    'id', 'e5000000-0000-4000-8000-000000000013', 'sequence', 1,
    'starts_at', '2026-08-21T09:00:00Z',
    'ends_at', '2026-08-21T09:30:00Z',
    'reserved_ends_at', '2026-08-21T09:30:00Z',
    'local_date', '2026-08-21', 'local_start_time', '09:00:00',
    'local_end_time', '09:30:00', 'planned_minutes', 30,
    'recovery_minutes', 0
  ))),
  ('blocks-b', jsonb_build_array(jsonb_build_object(
    'id', 'e5000000-0000-4000-8000-000000000023', 'sequence', 1,
    'starts_at', '2026-08-21T10:00:00Z',
    'ends_at', '2026-08-21T10:30:00Z',
    'reserved_ends_at', '2026-08-21T10:30:00Z',
    'local_date', '2026-08-21', 'local_start_time', '10:00:00',
    'local_end_time', '10:30:00', 'planned_minutes', 30,
    'recovery_minutes', 0
  )));

insert into multi_exam_lifecycle_fixture (name, value)
select 'children', jsonb_agg(jsonb_build_object(
  'plan_id', plan_id,
  'request_id', request_id,
  'request_fingerprint', repeat(request_digit, 64),
  'confirm_request_id', confirm_request_id,
  'confirm_request_fingerprint', repeat(confirm_digit, 64),
  'base_revision', 1,
  'proposal', proposal,
  'blocks', blocks,
  'review', jsonb_build_object(
    'position', position,
    'plan_id', plan_id,
    'title', title,
    'deadline_at', deadline_at,
    'remaining_minutes', 30,
    'active_revision', 1,
    'base_revision', 1,
    'proposed_revision', 2,
    'current_blocks', current_blocks,
    'proposed_blocks', private.multi_exam_plan_proposed_blocks_v1(blocks),
    'retained_minutes', 0,
    'added_minutes', 0,
    'shifted_minutes', 30,
    'removed_minutes', 0,
    'retained_block_count', 0,
    'added_block_count', 0,
    'shifted_block_count', 1,
    'removed_block_count', 0
  )
) order by position)
from (
  select 1 as position,
    'e5000000-0000-4000-8000-000000000010' as plan_id,
    'e5000000-0000-4000-8000-000000000031' as request_id,
    '5' as request_digit,
    'e5000000-0000-4000-8000-000000000032' as confirm_request_id,
    '6' as confirm_digit,
    'Algorithms' as title, '2026-09-10T18:00:00Z' as deadline_at,
    (select value from multi_exam_lifecycle_fixture where name = 'proposal-a')
      as proposal,
    (select value from multi_exam_lifecycle_fixture where name = 'blocks-a')
      as blocks,
    private.multi_exam_plan_current_blocks_v1(
      'e5000000-0000-4000-8000-000000000001',
      'e5000000-0000-4000-8000-000000000010', 1,
      '2026-08-13T09:00:00Z'
    ) as current_blocks
  union all
  select 2,
    'e5000000-0000-4000-8000-000000000020',
    'e5000000-0000-4000-8000-000000000041', '7',
    'e5000000-0000-4000-8000-000000000042', '8',
    'Physics', '2026-09-11T18:00:00Z',
    (select value from multi_exam_lifecycle_fixture where name = 'proposal-b'),
    (select value from multi_exam_lifecycle_fixture where name = 'blocks-b'),
    private.multi_exam_plan_current_blocks_v1(
      'e5000000-0000-4000-8000-000000000001',
      'e5000000-0000-4000-8000-000000000020', 1,
      '2026-08-13T09:00:00Z'
    )
) as children;

grant select, insert, update on multi_exam_lifecycle_fixture to service_role;

set local role service_role;
select throws_ok(
  $$select public.propose_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001', 'multi_exam_batch',
    'e5000000-0000-4000-8000-000000000055',
    'e5000000-0000-4000-8000-000000000056', repeat('8', 64),
    'e5000000-0000-4000-8000-000000000010', 1,
    '2026-08-13T09:00:00Z',
    (select value ->> 'context_fingerprint'
     from multi_exam_lifecycle_fixture where name = 'snapshot'),
    'UTC', false,
    (select jsonb_set(
       value,
       '{0,proposal,timing_preference,source}',
       to_jsonb('learned_personal_pattern'::text)
     ) from multi_exam_lifecycle_fixture where name = 'children'),
    '2026-08-13T09:00:00Z'
  )$$,
  'PT409',
  'Learned Focus timing changed. Reload before balancing.',
  'batch proposal rejects learned timing when its deployment authority is off'
);

reset role;

create table private.multi_exam_concurrency_fixture_test as
select name, value from multi_exam_lifecycle_fixture;
alter table private.multi_exam_concurrency_fixture_test
  add primary key (name);

create or replace function private.multi_exam_test_wait_for_advisory_lock_v1(
  p_pid int
)
returns boolean
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  for attempt in 1..100 loop
    if (
      select count(*) >= 2
      from pg_locks
      where pid = p_pid and locktype = 'advisory' and granted
    ) then
      return true;
    end if;
    perform pg_sleep(0.02);
  end loop;
  return false;
end;
$$;

create or replace function private.multi_exam_test_propose_and_hold_v1()
returns jsonb
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
begin
  result := public.propose_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001', 'multi_exam_batch',
    'e5000000-0000-4000-8000-000000000050',
    'e5000000-0000-4000-8000-000000000051', repeat('9', 64),
    'e5000000-0000-4000-8000-000000000010', 1,
    '2026-08-13T09:00:00Z',
    (select value ->> 'context_fingerprint'
     from private.multi_exam_concurrency_fixture_test
     where name = 'snapshot'),
    'UTC', true,
    (select value from private.multi_exam_concurrency_fixture_test
     where name = 'children'),
    '2026-08-13T09:00:00Z'
  );
  perform pg_sleep(1.5);
  return result;
end;
$$;

create or replace function private.multi_exam_test_confirm_and_hold_v1()
returns jsonb
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
begin
  result := public.confirm_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000090',
    'e5000000-0000-4000-8000-000000000092', repeat('4', 64), 1,
    true, '2026-08-13T10:05:00Z'
  );
  perform pg_sleep(1.5);
  return result;
end;
$$;

revoke all on function private.multi_exam_test_wait_for_advisory_lock_v1(int),
  private.multi_exam_test_propose_and_hold_v1(),
  private.multi_exam_test_confirm_and_hold_v1()
from public, anon, authenticated, service_role;

do $$
declare
  test_host text := case
    when (select rolsuper from pg_roles where rolname = current_user)
      then '127.0.0.1'
    else host(inet_server_addr())
  end;
  test_password text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if test_host is null then
    raise exception 'Multi-Exam concurrency tests require a TCP database session.';
  end if;

  perform set_config('password_encryption', 'scram-sha-256', true);
  execute format(
    'create role multi_exam_concurrency_test_login login inherit '
    'connection limit 2 valid until %L password %L',
    clock_timestamp() + interval '1 hour',
    test_password
  );
  execute 'grant execute on function '
    'public.propose_multi_exam_plan_v1('
    'uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,'
    'jsonb,timestamptz) to multi_exam_concurrency_test_login';
  execute 'grant execute on function '
    'public.confirm_multi_exam_plan_v1('
    'uuid,uuid,uuid,text,integer,boolean,timestamptz) '
    'to multi_exam_concurrency_test_login';
  execute 'grant usage on schema private '
    'to multi_exam_concurrency_test_login';
  execute 'grant select on private.multi_exam_concurrency_fixture_test '
    'to multi_exam_concurrency_test_login';
  execute 'grant execute on function '
    'private.multi_exam_test_propose_and_hold_v1(), '
    'private.multi_exam_test_confirm_and_hold_v1() '
    'to multi_exam_concurrency_test_login';

  update multi_exam_test_environment
  set dblink_host = test_host,
      dblink_user = 'multi_exam_concurrency_test_login',
      dblink_password = test_password;
end;
$$;

select ok(
  not pg_has_role(
    'multi_exam_concurrency_test_login', 'service_role', 'MEMBER'
  )
  and (
    select count(*) = 0
    from pg_auth_members
    where member = (
      select oid from pg_roles
      where rolname = 'multi_exam_concurrency_test_login'
    )
  )
  and has_function_privilege(
    'multi_exam_concurrency_test_login',
    'public.propose_multi_exam_plan_v1(uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,jsonb,timestamptz)',
    'EXECUTE'
  )
  and has_function_privilege(
    'multi_exam_concurrency_test_login',
    'public.confirm_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,boolean,timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'multi_exam_concurrency_test_login',
    'public.cancel_multi_exam_plan_v1(uuid,uuid,uuid,text,integer,timestamptz)',
    'EXECUTE'
  )
  and has_table_privilege(
    'multi_exam_concurrency_test_login',
    'private.multi_exam_concurrency_fixture_test', 'SELECT'
  )
  and not has_table_privilege(
    'multi_exam_concurrency_test_login',
    'private.multi_exam_plan_batches', 'SELECT'
  ),
  'the concurrency login has only its exact RPC and fixture authority'
);

commit;
begin;

create temporary table multi_exam_concurrency_sessions (
  name text primary key,
  pid int not null
) on commit preserve rows;

do $$
declare
  test_conninfo text;
begin
  select format(
    'hostaddr=%L port=%L dbname=%L user=%L password=%L '
    'connect_timeout=5 sslmode=disable',
    dblink_host, current_setting('port'), current_database(), dblink_user,
    dblink_password
  ) into strict test_conninfo
  from multi_exam_test_environment;

  if extensions.dblink_connect(
    'proposal_owner_lock',
    test_conninfo
  ) <> 'OK' then
    raise exception 'Proposal concurrency connection failed.';
  end if;
end;
$$;

insert into multi_exam_concurrency_sessions (name, pid)
select 'proposal', remote.pid
from extensions.dblink(
  'proposal_owner_lock', 'select pg_backend_pid()'
) as remote(pid int);

do $$
begin
  if extensions.dblink_send_query(
    'proposal_owner_lock',
    'select private.multi_exam_test_propose_and_hold_v1()'
  ) <> 1 then
    raise exception 'Proposal concurrency query did not start.';
  end if;
end;
$$;

select ok(
  private.multi_exam_test_wait_for_advisory_lock_v1((
    select pid from multi_exam_concurrency_sessions where name = 'proposal'
  )),
  'a real batch proposal holds owner and request advisory locks before commit'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'e5000000-0000-4000-8000-000000000001';
set local lock_timeout = '250ms';
select throws_ok(
  $$update public.tasks
    set updated_at = '2026-08-13T09:04:00Z'
    where id = 'e5000000-0000-4000-8000-000000000030'$$,
  '55P03', null,
  'a direct owner Task write cannot cross an in-flight batch proposal digest'
);
reset role;
set local lock_timeout = '0';

select is(
  (
    select response.result ->> 'result_status'
    from extensions.dblink_get_result('proposal_owner_lock')
      as response(result jsonb)
  ),
  'proposed',
  'two changed Exams persist one batch proposal atomically'
);

do $$
begin
  if extensions.dblink_disconnect('proposal_owner_lock') <> 'OK' then
    raise exception 'Proposal concurrency disconnect failed.';
  end if;
end;
$$;

select is((
  select updated_at
  from public.tasks
  where id = 'e5000000-0000-4000-8000-000000000030'
), '2026-08-01T08:00:00Z'::timestamptz,
  'the timed-out direct Task write leaves its row unchanged');

set local role service_role;

select is(
  public.propose_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001', 'multi_exam_batch',
    'e5000000-0000-4000-8000-000000000050',
    'e5000000-0000-4000-8000-000000000051', repeat('9', 64),
    'e5000000-0000-4000-8000-000000000010', 1,
    '2026-08-13T09:00:00Z',
    (select value ->> 'context_fingerprint'
     from multi_exam_lifecycle_fixture where name = 'snapshot'),
    'UTC', true,
    (select value from multi_exam_lifecycle_fixture where name = 'children'),
    '2026-08-13T09:05:00Z'
  ) ->> 'result_status',
  'proposed',
  'exact batch proposal retry replays without another child revision'
);

select throws_ok(
  $$select public.propose_deadline_plan_with_timing_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000057', repeat('7', 64),
    'e5000000-0000-4000-8000-000000000010', 2,
    (select value from multi_exam_lifecycle_fixture where name = 'proposal-a'),
    (select value from multi_exam_lifecycle_fixture where name = 'blocks-a'),
    '2026-08-13T09:06:00Z'
  )$$,
  'PT409',
  'This Exam is part of a pending Exam balance. Review Exam balance.',
  'normal single-plan proposal cannot bypass a pending batch child'
);

select throws_ok(
  $$select public.mutate_deadline_plan_lifecycle_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000010',
    'e5000000-0000-4000-8000-000000000058', repeat('6', 64), 1,
    'complete', '2026-08-13T09:07:00Z'
  )$$,
  'PT409',
  'This Exam is part of a pending Exam balance. Review Exam balance.',
  'normal completion cannot strand a pending batch child'
);

select throws_ok(
  $$select public.mutate_deadline_plan_lifecycle_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000010',
    'e5000000-0000-4000-8000-000000000059', repeat('5', 64), 1,
    'cancel', '2026-08-13T09:08:00Z'
  )$$,
  'PT409',
  'This Exam is part of a pending Exam balance. Review Exam balance.',
  'normal cancellation cannot strand a pending batch child'
);

select throws_ok(
  $$select public.confirm_deadline_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000010',
    'e5000000-0000-4000-8000-000000000061', repeat('a', 64), 2,
    '2026-08-13T09:10:00Z'
  )$$,
  'PT409',
  'This preview belongs to an Exam balance. Review Exam balance.',
  'a linked child cannot be confirmed through the single-plan RPC'
);

select is((
  select row(current_revision, latest_revision)::text
  from public.deadline_plans
  where id = 'e5000000-0000-4000-8000-000000000010'
), '(1,2)', 'batch proposal stages without changing the active revision');

select is((
  select count(*)::int
  from public.deadline_plan_revisions
  where user_id = 'e5000000-0000-4000-8000-000000000001'
    and plan_id in (
      'e5000000-0000-4000-8000-000000000010',
      'e5000000-0000-4000-8000-000000000020'
    )
    and revision = 2 and state = 'proposed'
), 2, 'batch proposal persists exactly two proposed child revisions');

reset role;

update public.profiles
set daily_preparation_budget_minutes = 180,
    preparation_budget_revision = preparation_budget_revision + 1
where id = 'e5000000-0000-4000-8000-000000000001';

select is((
  select daily_preparation_budget_minutes
  from public.profiles
  where id = 'e5000000-0000-4000-8000-000000000001'
), 180, 'test context advances the authoritative preparation budget');

select isnt(
  private.multi_exam_plan_context_fingerprint_v1(
    'e5000000-0000-4000-8000-000000000001'
  ),
  (
    select confirmation_fingerprint
    from private.multi_exam_plan_batch_revisions
    where balance_id = 'e5000000-0000-4000-8000-000000000050'
      and revision = 1
  ),
  'the post-proposal fingerprint observes preparation-budget drift'
);

set local role service_role;
select throws_ok(
  $$select public.confirm_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000050',
    'e5000000-0000-4000-8000-000000000062', repeat('b', 64), 1,
    true, '2026-08-13T09:15:00Z'
  )$$,
  'PT409',
  'Exam balance sources changed. Reload and create a fresh preview.',
  'post-proposal context drift makes atomic confirmation stale'
);

select is((
  select count(*)::int from public.deadline_plan_revisions
  where user_id = 'e5000000-0000-4000-8000-000000000001'
    and plan_id in (
      'e5000000-0000-4000-8000-000000000010',
      'e5000000-0000-4000-8000-000000000020'
    )
    and revision = 2 and state = 'active'
), 0, 'stale batch confirmation activates no child');

reset role;
update public.learning_preferences
set revision = revision + 1,
    learned_focus_planning_enabled = true,
    updated_at = updated_at + interval '1 microsecond'
where user_id = 'e5000000-0000-4000-8000-000000000001';

set local role service_role;
select throws_ok(
  $$select public.confirm_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000050',
    'e5000000-0000-4000-8000-000000000064', repeat('d', 64), 1,
    true, '2026-08-13T09:17:00Z'
  )$$,
  'PT409',
  'Learned Focus timing changed. Reload and create a fresh preview.',
  'learned-timing permission revision makes an existing batch stale'
);

select is(
  public.cancel_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000050',
    'e5000000-0000-4000-8000-000000000063', repeat('c', 64), 1,
    '2026-08-13T09:20:00Z'
  ) ->> 'result_status',
  'cancelled',
  'cancel remains available when the confirmation context is stale'
);

select is(
  public.cancel_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000050',
    'e5000000-0000-4000-8000-000000000063', repeat('c', 64), 1,
    '2026-08-13T09:25:00Z'
  ) ->> 'result_status',
  'cancelled',
  'exact stale-context cancellation retry replays safely'
);

select is((
  select row(current_revision, latest_revision)::text
  from public.deadline_plans
  where id = 'e5000000-0000-4000-8000-000000000010'
), '(1,2)', 'batch cancellation leaves the active plan untouched');

select is((
  select count(*)::int from public.deadline_plan_revisions
  where user_id = 'e5000000-0000-4000-8000-000000000001'
    and revision = 2 and state = 'superseded'
    and plan_id in (
      'e5000000-0000-4000-8000-000000000010',
      'e5000000-0000-4000-8000-000000000020'
    )
), 2, 'batch cancellation supersedes every staged child');

reset role;

update multi_exam_lifecycle_fixture
set value = jsonb_set(
  jsonb_set(value, '{base_revision}', '2'),
  '{planning_fingerprint}', to_jsonb(repeat('d', 64))
)
where name in ('proposal-a', 'proposal-b');

update multi_exam_lifecycle_fixture
set value = jsonb_set(
  value,
  '{0,id}',
  to_jsonb(case name
    when 'blocks-a' then 'e5000000-0000-4000-8000-000000000014'
    else 'e5000000-0000-4000-8000-000000000024' end)
)
where name in ('blocks-a', 'blocks-b');

update multi_exam_lifecycle_fixture as fixture
set value = (
  select jsonb_agg(
    jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
                jsonb_set(child, '{base_revision}', '2'),
                '{proposal}', proposal.value
              ),
              '{blocks}', blocks.value
            ),
            '{review,proposed_blocks}',
            private.multi_exam_plan_proposed_blocks_v1(blocks.value)
          ),
          '{review,base_revision}', '2'
      ),
      '{review,proposed_revision}', '3'
    )
    || jsonb_build_object(
      'request_id', case child ->> 'plan_id'
        when 'e5000000-0000-4000-8000-000000000010'
          then 'e5000000-0000-4000-8000-000000000071'
        else 'e5000000-0000-4000-8000-000000000081' end,
      'request_fingerprint', repeat(case child ->> 'plan_id'
        when 'e5000000-0000-4000-8000-000000000010' then 'e' else 'f' end, 64),
      'confirm_request_id', case child ->> 'plan_id'
        when 'e5000000-0000-4000-8000-000000000010'
          then 'e5000000-0000-4000-8000-000000000072'
        else 'e5000000-0000-4000-8000-000000000082' end,
      'confirm_request_fingerprint', repeat(case child ->> 'plan_id'
        when 'e5000000-0000-4000-8000-000000000010' then '1' else '2' end, 64)
    ) order by ordinal)
  from jsonb_array_elements(fixture.value)
    with ordinality as children(child, ordinal)
  join multi_exam_lifecycle_fixture as proposal
    on proposal.name = case child ->> 'plan_id'
      when 'e5000000-0000-4000-8000-000000000010' then 'proposal-a'
      else 'proposal-b' end
  join multi_exam_lifecycle_fixture as blocks
    on blocks.name = case child ->> 'plan_id'
      when 'e5000000-0000-4000-8000-000000000010' then 'blocks-a'
      else 'blocks-b' end
)
where fixture.name = 'children';

update multi_exam_lifecycle_fixture
set value = public.get_multi_exam_plan_snapshot_v1(
  'e5000000-0000-4000-8000-000000000001',
  '2026-08-13T10:00:00Z'
)
where name = 'snapshot';

set local role service_role;
select is(
  public.propose_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001', 'multi_exam_batch',
    'e5000000-0000-4000-8000-000000000090',
    'e5000000-0000-4000-8000-000000000091', repeat('3', 64),
    'e5000000-0000-4000-8000-000000000010', 2,
    '2026-08-13T10:00:00Z',
    (select value ->> 'context_fingerprint'
     from multi_exam_lifecycle_fixture where name = 'snapshot'),
    'UTC', true,
    (select value from multi_exam_lifecycle_fixture where name = 'children'),
    '2026-08-13T10:00:00Z'
  ) ->> 'result_revision',
  '1',
  'cancel then new balance advances from latest base instead of active revision'
);

select throws_ok(
  $$select public.confirm_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000090',
    'e5000000-0000-4000-8000-000000000093', repeat('5', 64), 1,
    false, '2026-08-13T10:04:00Z'
  )$$,
  'PT409',
  'Learned Focus timing changed. Reload and create a fresh preview.',
  'deployment pilot authority is part of the confirmation marker'
);

reset role;
select is((
  select row(active_revision, base_revision, proposed_revision)::text
  from private.multi_exam_plan_batch_items
  where balance_id = 'e5000000-0000-4000-8000-000000000090'
    and position = 1
), '(1,2,3)', 'new batch preserves distinct active, base, and proposed revisions');

commit;
begin;

do $$
declare
  test_conninfo text;
begin
  select format(
    'hostaddr=%L port=%L dbname=%L user=%L password=%L '
    'connect_timeout=5 sslmode=disable',
    dblink_host, current_setting('port'), current_database(), dblink_user,
    dblink_password
  ) into strict test_conninfo
  from multi_exam_test_environment;

  if extensions.dblink_connect(
    'confirm_owner_lock',
    test_conninfo
  ) <> 'OK' then
    raise exception 'Confirmation concurrency connection failed.';
  end if;
end;
$$;

insert into multi_exam_concurrency_sessions (name, pid)
select 'confirm', remote.pid
from extensions.dblink(
  'confirm_owner_lock', 'select pg_backend_pid()'
) as remote(pid int);

do $$
begin
  if extensions.dblink_send_query(
    'confirm_owner_lock',
    'select private.multi_exam_test_confirm_and_hold_v1()'
  ) <> 1 then
    raise exception 'Confirmation concurrency query did not start.';
  end if;
end;
$$;

select ok(
  private.multi_exam_test_wait_for_advisory_lock_v1((
    select pid from multi_exam_concurrency_sessions where name = 'confirm'
  )),
  'a real batch confirmation holds owner and request locks through commit'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'e5000000-0000-4000-8000-000000000001';
set local lock_timeout = '250ms';
select throws_ok(
  $$update public.habits
    set updated_at = '2026-08-13T10:06:00Z'
    where id = 'e5000000-0000-4000-8000-000000000040'$$,
  '55P03', null,
  'a direct owner Habit write cannot cross an in-flight batch confirmation'
);
reset role;
set local lock_timeout = '0';

select is(
  (
    select response.result ->> 'result_status'
    from extensions.dblink_get_result('confirm_owner_lock')
      as response(result jsonb)
  ),
  'confirmed',
  'batch confirmation atomically activates the complete child set'
);

do $$
begin
  if extensions.dblink_disconnect('confirm_owner_lock') <> 'OK' then
    raise exception 'Confirmation concurrency disconnect failed.';
  end if;
end;
$$;

update multi_exam_test_environment
set dblink_password = null;

select is((
  select updated_at
  from public.habits
  where id = 'e5000000-0000-4000-8000-000000000040'
), '2026-08-01T08:00:00Z'::timestamptz,
  'the timed-out direct Habit write leaves its row unchanged');

set local role service_role;

select is(
  public.confirm_multi_exam_plan_v1(
    'e5000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000090',
    'e5000000-0000-4000-8000-000000000092', repeat('4', 64), 1,
    true, '2026-08-13T10:10:00Z'
  ) ->> 'result_status',
  'confirmed',
  'exact batch confirmation retry replays after commit'
);

reset role;
select is((
  select count(*)::int from public.deadline_plans
  where user_id = 'e5000000-0000-4000-8000-000000000001'
    and id in (
      'e5000000-0000-4000-8000-000000000010',
      'e5000000-0000-4000-8000-000000000020'
    )
    and current_revision = 3 and latest_revision = 3
), 2, 'atomic confirmation advances both roots and no partial root');

select is((
  select count(*)::int from public.deadline_plan_revisions
  where user_id = 'e5000000-0000-4000-8000-000000000001'
    and plan_id in (
      'e5000000-0000-4000-8000-000000000010',
      'e5000000-0000-4000-8000-000000000020'
    )
    and revision = 3 and state = 'active'
), 2, 'atomic confirmation activates every proposed revision');

select is((
  select count(*)::int from public.deadline_plan_blocks
  where user_id = 'e5000000-0000-4000-8000-000000000001'
    and plan_id in (
      'e5000000-0000-4000-8000-000000000010',
      'e5000000-0000-4000-8000-000000000020'
    )
    and revision = 3 and reservation_state = 'active'
), 2, 'atomic confirmation activates every proposed reservation');

select is((
  select count(*)::int
  from private.multi_exam_plan_request_identities
  where user_id = 'e5000000-0000-4000-8000-000000000001'
), 4, 'append-only outer ledger records one proposal/cancel/proposal/confirm row');

select is((
  select count(*)::int
  from public.deadline_plan_request_identities
  where user_id = 'e5000000-0000-4000-8000-000000000001'
), 6, 'inner child ledger records each proposal and confirmation exactly once');

reset role;
delete from auth.users
where id = 'e5000000-0000-4000-8000-000000000001';

drop function private.multi_exam_test_confirm_and_hold_v1();
drop function private.multi_exam_test_propose_and_hold_v1();
drop function private.multi_exam_test_wait_for_advisory_lock_v1(int);
drop table private.multi_exam_concurrency_fixture_test;
do $$
begin
  execute 'revoke execute on function '
    'public.propose_multi_exam_plan_v1('
    'uuid,text,uuid,uuid,text,uuid,integer,timestamptz,text,text,boolean,'
    'jsonb,timestamptz) from multi_exam_concurrency_test_login';
  execute 'revoke execute on function '
    'public.confirm_multi_exam_plan_v1('
    'uuid,uuid,uuid,text,integer,boolean,timestamptz) '
    'from multi_exam_concurrency_test_login';
  execute 'revoke usage on schema private '
    'from multi_exam_concurrency_test_login';
  execute 'drop role multi_exam_concurrency_test_login';
end;
$$;

do $$
begin
  perform pg_temp.multi_exam_drop_owned_dblink_v1();
end;
$$;

select is((
  select count(*)::int from auth.users
  where id = 'e5000000-0000-4000-8000-000000000001'
), 0, 'the committed concurrency fixture removes its Auth identity');

select is((
  select count(*)::int
  from public.deadline_plans
  where user_id = 'e5000000-0000-4000-8000-000000000001'
), 0, 'the committed concurrency fixture removes its owner content');

select is((
  (select count(*) from private.multi_exam_plan_batches
   where user_id = 'e5000000-0000-4000-8000-000000000001')
  + (select count(*) from private.multi_exam_plan_request_identities
     where user_id = 'e5000000-0000-4000-8000-000000000001')
)::int, 0, 'the committed concurrency fixture removes private orchestration rows');

select ok(
  to_regclass('private.multi_exam_concurrency_fixture_test') is null
  and to_regprocedure(
    'private.multi_exam_test_wait_for_advisory_lock_v1(integer)'
  ) is null
  and to_regprocedure(
    'private.multi_exam_test_propose_and_hold_v1()'
  ) is null
  and to_regprocedure(
    'private.multi_exam_test_confirm_and_hold_v1()'
  ) is null
  and not exists (
    select 1 from pg_roles
    where rolname = 'multi_exam_concurrency_test_login'
  )
  and to_regclass(
    'private.multi_exam_dblink_extension_test_marker'
  ) is null,
  'the committed fixture removes every test-only helper, login, and marker'
);

select * from finish();

commit;
