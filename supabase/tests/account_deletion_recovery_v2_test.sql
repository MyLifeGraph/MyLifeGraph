begin;
select no_plan();

select ok(
  has_function_privilege(
    'service_role',
    'public.prepare_account_deletion_v2(uuid,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)',
    'EXECUTE'
  )
  and has_function_privilege(
    'mylifegraph_deletion_replayer',
    'public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.prepare_account_deletion_v2(uuid,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.prepare_account_deletion_v2(uuid,uuid,text)',
    'EXECUTE'
  ),
  'runtime deletion and restore replay use separate database authorities'
);

select ok(
  private.account_deletion_replayer_role_safe_v2(),
  'the restore-only replayer has exact attributes and only the version-required creator edge'
);

alter role mylifegraph_deletion_replayer login;
select isnt(
  private.account_deletion_replayer_role_safe_v2(),
  true,
  'a login-capable replay role fails the role guard'
);
alter role mylifegraph_deletion_replayer nologin;

grant service_role to mylifegraph_deletion_replayer;
select isnt(
  private.account_deletion_replayer_role_safe_v2(),
  true,
  'membership in an application backend role fails the role guard'
);
revoke service_role from mylifegraph_deletion_replayer;

grant mylifegraph_deletion_replayer to service_role;
select isnt(
  private.account_deletion_replayer_role_safe_v2(),
  true,
  'delegating replay authority to an application role fails the role guard'
);
revoke mylifegraph_deletion_replayer from service_role;

select ok(
  not has_table_privilege(
    'service_role', 'public.account_deletion_intents', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.account_deletion_intents', 'SELECT'
  )
  and (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'public.account_deletion_intents'::regclass
  ),
  'the minimal recovery ledger is forced-RLS and RPC-only'
);

select is_empty(
  $$
    select class.relname
    from pg_catalog.pg_class as class
    where class.relnamespace = 'public'::regnamespace
      and class.relkind in ('r', 'p')
      and class.relrowsecurity
      and not exists (
        select 1 from pg_catalog.pg_policy as policy
        where policy.polrelid = class.oid
          and policy.polname = 'account_deletion_not_pending_v2'
          and not policy.polpermissive
      )
  $$,
  'every current public RLS table blocks a journal-accepted account'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  'ef000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'delete-v2@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'ef000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'restore-delete-v2@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

create temporary table prepared_deletion on commit drop as
select public.prepare_account_deletion_v2(
  'ef000000-0000-4000-8000-000000000001',
  'ef100000-0000-4000-8000-000000000001',
  'DELETE'
) as value;

select is(
  (select value ->> 'state' from prepared_deletion),
  'prepared',
  'the retry identity is prepared before any irreversible append'
);

select is(
  public.prepare_account_deletion_v2(
    'ef000000-0000-4000-8000-000000000001',
    'ef100000-0000-4000-8000-000000000001',
    'DELETE'
  ) ->> 'replayed',
  'true',
  'the exact prepare retry does not create a second intent'
);

select throws_ok(
  $$
    select public.prepare_account_deletion_v2(
      'ef000000-0000-4000-8000-000000000001',
      'ef100000-0000-4000-8000-000000000002',
      'DELETE'
    )
  $$,
  'PT409',
  null,
  'one account cannot bind a second deletion id'
);

select set_config(
  'mylifegraph.delete_v2_accepted_at',
  (select value ->> 'accepted_at' from prepared_deletion),
  true
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'ef000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.profiles),
  0,
  'a prepared intent blocks product use across a process crash boundary'
);

reset role;
set local role service_role;

select is(
  public.mark_account_deletion_appending_v2(
    'ef000000-0000-4000-8000-000000000001',
    'ef100000-0000-4000-8000-000000000001'
  ) ->> 'state',
  'appending',
  'starting the ambiguous off-host append establishes the pending boundary'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'ef000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.profiles),
  0,
  'an append-in-flight account is conservatively blocked from product access'
);

reset role;
set local role service_role;

create temporary table accepted_deletion on commit drop as
select public.accept_account_deletion_journal_v2(
  'ef000000-0000-4000-8000-000000000001',
  'ef100000-0000-4000-8000-000000000001',
  current_setting('mylifegraph.delete_v2_accepted_at')::timestamptz,
  'deletions/v2/' ||
    to_char(
      current_setting('mylifegraph.delete_v2_accepted_at')::timestamptz
        at time zone 'UTC',
      'YYYY/MM'
    ) ||
    '/ef100000-0000-4000-8000-000000000001/' || repeat('a', 64) || '.json',
  repeat('a', 64),
  current_setting('mylifegraph.delete_v2_accepted_at')::timestamptz
) as value;

select is(
  (select value ->> 'state' from accepted_deletion),
  'accepted',
  'the durable journal receipt establishes the irreversible pending state'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'ef000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.profiles),
  0,
  'journal acceptance immediately blocks direct Data API product access'
);

reset role;
set local role service_role;

select is(
  public.complete_account_deletion_v2(
    'ef000000-0000-4000-8000-000000000001',
    'ef100000-0000-4000-8000-000000000001',
    'DELETE',
    now() + interval '1 second'
  ) ->> 'state',
  'completed',
  'accepted deletion invokes the existing owner-locked deletion and completes'
);

reset role;

select ok(
  not exists (
    select 1 from auth.users
    where id = 'ef000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1 from public.profiles
    where id = 'ef000000-0000-4000-8000-000000000001'
  )
  and exists (
    select 1 from public.account_deletion_intents
    where deletion_id = 'ef100000-0000-4000-8000-000000000001'
      and state = 'completed'
  ),
  'account data is absent while the minimal recovery identity remains'
);

select (
  current_setting('server_version_num')::integer < 160000
) as legacy_replayer_membership \gset

-- PostgreSQL 15 has no automatic creator edge, so a transaction-local grant
-- lets this test exercise the exact role. PostgreSQL 16+ deliberately keeps
-- its unavoidable creator edge SET FALSE; the function owner invokes the
-- same SECURITY DEFINER replay path there without weakening that boundary.
\if :legacy_replayer_membership
  grant mylifegraph_deletion_replayer to postgres;
  set local role mylifegraph_deletion_replayer;
\endif

select (
  public.replay_account_deletion_v2(
    'ef000000-0000-4000-8000-000000000002',
    'ef100000-0000-4000-8000-000000000002',
    timestamptz '2026-08-20 12:00:00+00',
    'deletions/v2/2026/08/ef100000-0000-4000-8000-000000000002/' ||
      repeat('b', 64) || '.json',
    repeat('b', 64),
    timestamptz '2026-08-20 12:00:01+00'
  ) ->> 'state'
) as replayed_deletion_state \gset

\if :legacy_replayer_membership
  reset role;
  revoke mylifegraph_deletion_replayer from postgres;
\endif

select is(
  :'replayed_deletion_state'::text,
  'completed',
  'an external receipt missing from an older backup is recreated and replayed'
);

select ok(
  not exists (
    select 1 from auth.users
    where id = 'ef000000-0000-4000-8000-000000000002'
  ),
  'restore replay removes the resurrected Auth identity'
);

select * from finish();
rollback;
