-- Final-state security and atomic-series contract for finite weekly Assignments.
begin;
select no_plan();

select has_table(
  'public',
  'assignment_series',
  'assignment series identities are installed'
);
select has_table(
  'public',
  'assignment_series_revisions',
  'assignment series revisions are installed'
);
select has_table(
  'public',
  'assignment_series_revision_items',
  'assignment occurrence links are installed'
);
select has_table(
  'public',
  'assignment_series_request_identities',
  'assignment series anti-replay identities are installed'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    where c.oid = any(array[
      'public.assignment_series'::regclass,
      'public.assignment_series_revisions'::regclass,
      'public.assignment_series_revision_items'::regclass,
      'public.assignment_series_request_identities'::regclass
    ])
      and (not c.relrowsecurity or not c.relforcerowsecurity)
  $$,
  'all assignment series tables force RLS'
);

select ok(
  has_table_privilege('authenticated', 'public.assignment_series', 'SELECT')
    and has_table_privilege(
      'authenticated',
      'public.assignment_series_revisions',
      'SELECT'
    )
    and has_table_privilege(
      'authenticated',
      'public.assignment_series_revision_items',
      'SELECT'
    ),
  'authenticated owners can read the three product projections'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    where c.oid = any(array[
      'public.assignment_series'::regclass,
      'public.assignment_series_revisions'::regclass,
      'public.assignment_series_revision_items'::regclass,
      'public.assignment_series_request_identities'::regclass
    ])
      and (
        has_table_privilege('authenticated', c.oid, 'INSERT')
        or has_table_privilege('authenticated', c.oid, 'UPDATE')
        or has_table_privilege('authenticated', c.oid, 'DELETE')
      )
  $$,
  'authenticated clients cannot mutate assignment series tables directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.assignment_series_request_identities',
    'SELECT'
  ),
  'the assignment series anti-replay ledger remains backend-only'
);

select is_empty(
  $$
    select rpc::text
    from unnest(array[
      'public.propose_assignment_series_v1('
        'uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)'
        ::regprocedure,
      'public.confirm_assignment_series_v1('
        'uuid,uuid,uuid,text,integer,timestamp with time zone)'
        ::regprocedure,
      'public.cancel_assignment_series_future_v1('
        'uuid,uuid,uuid,text,integer,jsonb,timestamp with time zone)'
        ::regprocedure
    ]) as rpc
    where has_function_privilege('anon', rpc, 'EXECUTE')
      or has_function_privilege('authenticated', rpc, 'EXECUTE')
      or not has_function_privilege('service_role', rpc, 'EXECUTE')
  $$,
  'only service_role can execute assignment series mutations'
);

select is_empty(
  $$
    select indexname
    from (values
      ('assignment_series_user_updated_idx'),
      ('assignment_series_revisions_one_proposed_idx'),
      ('assignment_series_revisions_one_active_idx'),
      ('assignment_series_revisions_user_series_idx'),
      ('assignment_series_items_user_series_idx'),
      ('assignment_series_items_plan_idx'),
      ('assignment_series_requests_user_idx')
    ) as expected(indexname)
    where not exists (
      select 1
      from pg_indexes installed
      where installed.schemaname = 'public'
        and installed.indexname = expected.indexname
    )
  $$,
  'owner reads, lifecycle uniqueness, plan joins, and replay lookups are indexed'
);

select ok(
  pg_get_functiondef(
    'public.propose_assignment_series_v1('
      'uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)'
      ::regprocedure
  ) like '%exact weekly local cadence%'
    and pg_get_functiondef(
      'public.propose_assignment_series_v1('
        'uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)'
        ::regprocedure
    ) like '%Past or completed assignment occurrences must be preserved%'
    and pg_get_functiondef(
      'public.propose_assignment_series_v1('
        'uuid,uuid,text,uuid,integer,jsonb,jsonb,timestamp with time zone)'
        ::regprocedure
    ) like '%credited_prior_minutes%<> 0%'
    and pg_get_functiondef(
      'public.confirm_assignment_series_v1('
        'uuid,uuid,uuid,text,integer,timestamp with time zone)'
        ::regprocedure
    ) like '%confirm_deadline_plan_v1%'
    and pg_get_functiondef(
      'public.cancel_assignment_series_future_v1('
        'uuid,uuid,uuid,text,integer,jsonb,timestamp with time zone)'
        ::regprocedure
    ) like '%mutate_deadline_plan_lifecycle_v1%',
  'installed RPCs keep weekly cadence, legacy-credit, preservation, and atomic lifecycle calls'
);

select * from finish();
rollback;
