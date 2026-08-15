-- Final-state authority belongs here, after the complete migration chain.
-- Historical Python source guards protect rollout identity; they do not prove
-- the effective catalog, role privileges, RLS mode, or installed triggers.
begin;
select no_plan();

select hasnt_table(
  'public',
  'goals',
  'the retired Goals table is absent from the final schema'
);

select is_empty(
  $$
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'goals'
  $$,
  'the retired Goals table leaves no policy behind'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and (not c.relrowsecurity or not c.relforcerowsecurity)
  $$,
  'every current public product table has RLS enabled and forced'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and (
        has_table_privilege('anon', c.oid, 'SELECT')
        or has_table_privilege('anon', c.oid, 'INSERT')
        or has_table_privilege('anon', c.oid, 'UPDATE')
        or has_table_privilege('anon', c.oid, 'DELETE')
        or has_table_privilege('anon', c.oid, 'TRUNCATE')
        or has_table_privilege('anon', c.oid, 'REFERENCES')
        or has_table_privilege('anon', c.oid, 'TRIGGER')
      )
  $$,
  'anon has no effective privilege on current public product tables'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and (
        has_table_privilege('authenticated', c.oid, 'TRUNCATE')
        or has_table_privilege('authenticated', c.oid, 'REFERENCES')
        or has_table_privilege('authenticated', c.oid, 'TRIGGER')
      )
  $$,
  'authenticated has no dangerous effective table privileges'
);

select is_empty(
  $$
    select c.relname
    from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relname in (
        'notifications',
        'ai_insights',
        'daily_briefings',
        'skillset_profiles'
      )
      and (
        not has_table_privilege('authenticated', c.oid, 'SELECT')
        or has_table_privilege('authenticated', c.oid, 'INSERT')
        or has_table_privilege('authenticated', c.oid, 'UPDATE')
        or has_table_privilege('authenticated', c.oid, 'DELETE')
      )
  $$,
  'backend-owned generated projections remain authenticated read-only'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosecdef
      and (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
      )
  $$,
  'public security-definer functions are not executable by application roles'
);

select is_empty(
  $$
    select rpc::text
    from unnest(array[
      'public.delete_account_v1(uuid,text)'::regprocedure,
      'public.apply_notification_action_v1('
        'uuid,uuid,uuid,text,timestamp with time zone)'::regprocedure,
      'public.claim_coach_request_v7('
        'uuid,uuid,text,date,text,text,text,text,timestamp with time zone,'
        'timestamp with time zone,integer)'::regprocedure,
      'public.persist_weekly_review_v3('
        'uuid,text,timestamp with time zone,jsonb)'::regprocedure,
      'public.start_focus_session_v2('
        'uuid,uuid,text,text,uuid,integer,integer,text,uuid,text,'
        'timestamp with time zone)'::regprocedure
    ]) as rpc
    where not has_function_privilege('service_role', rpc, 'EXECUTE')
  $$,
  'critical owner-mutating RPCs retain service-role execution authority'
);

select set_eq(
  $$
    select policyname::text
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'profiles',
        'behavioral_events',
        'daily_logs',
        'focus_sessions',
        'habit_logs',
        'habits',
        'lifestyle_entries',
        'notification_preferences',
        'schedule_items',
        'tasks'
      )
  $$,
  array[
    'profiles_own_or_admin_all',
    'behavioral_events_own_or_admin_all',
    'daily_logs_own_or_admin_all',
    'focus_sessions_own_or_admin_all',
    'habit_logs_own_or_admin_all',
    'habits_own_or_admin_all',
    'lifestyle_entries_own_or_admin_all',
    'notification_preferences_own_or_admin_all',
    'schedule_items_own_or_admin_all',
    'tasks_own_or_admin_all'
  ]::text[],
  'the optimized canonical owner/admin policy set is installed'
);

select is_empty(
  $$
    select policyname
    from pg_policies
    where schemaname = 'public'
      and policyname = any(array[
        'profiles_own_or_admin_all',
        'behavioral_events_own_or_admin_all',
        'daily_logs_own_or_admin_all',
        'focus_sessions_own_or_admin_all',
        'habit_logs_own_or_admin_all',
        'habits_own_or_admin_all',
        'lifestyle_entries_own_or_admin_all',
        'notification_preferences_own_or_admin_all',
        'schedule_items_own_or_admin_all',
        'tasks_own_or_admin_all'
      ])
      and (
        (coalesce(qual, '') like '%auth.uid()%'
          and coalesce(qual, '') not like '%SELECT auth.uid()%')
        or (coalesce(with_check, '') like '%auth.uid()%'
          and coalesce(with_check, '') not like '%SELECT auth.uid()%')
        or (coalesce(qual, '') like '%private.current_app_role()%'
          and coalesce(qual, '') not like '%SELECT private.current_app_role()%')
        or (coalesce(with_check, '') like '%private.current_app_role()%'
          and coalesce(with_check, '')
            not like '%SELECT private.current_app_role()%')
      )
  $$,
  'canonical owner/admin policies keep identity and role calls initplan-safe'
);

select set_eq(
  $$
    select conname::text
    from pg_constraint
    where conname in (
      'notifications_created_updated_order_check',
      'notifications_read_updated_order_check',
      'notifications_dismissed_updated_order_check',
      'notification_action_requests_expected_result_order_check',
      'notification_action_requests_read_result_order_check',
      'notification_action_requests_dismissed_result_order_check'
    )
      and contype = 'c'
      and not convalidated
  $$,
  array[
    'notifications_created_updated_order_check',
    'notifications_read_updated_order_check',
    'notifications_dismissed_updated_order_check',
    'notification_action_requests_expected_result_order_check',
    'notification_action_requests_read_result_order_check',
    'notification_action_requests_dismissed_result_order_check'
  ]::text[],
  'new-write notification timestamp guards remain installed as NOT VALID checks'
);

select set_eq(
  $$
    select t.tgname::text
    from pg_trigger t
    where t.tgrelid = 'auth.users'::regclass
      and not t.tgisinternal
      and t.tgname in (
        'on_auth_user_created',
        'on_auth_user_created_app_user'
      )
  $$,
  array[
    'on_auth_user_created',
    'on_auth_user_created_app_user'
  ]::text[],
  'both preexisting Auth profile triggers remain installed'
);

select * from finish();
rollback;
