-- Remove superseded permissive policies left by the initial schema and make
-- the canonical owner/admin policies evaluate stable identity helpers once per
-- statement. This changes neither table privileges nor the owner/admin rule.

drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "behavioral_events_own_all" on public.behavioral_events;
drop policy if exists "lifestyle_entries_own_all" on public.lifestyle_entries;
drop policy if exists "notification_preferences_own_all"
  on public.notification_preferences;

drop policy if exists "profiles_own_or_admin_all" on public.profiles;
create policy "profiles_own_or_admin_all"
  on public.profiles for all
  using (
    id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  )
  with check (
    id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

do $optimize_owner_admin_policies$
declare
  table_name text;
  policy_name text;
begin
  foreach table_name in array array[
    'behavioral_events',
    'daily_logs',
    'focus_sessions',
    'goals',
    'habit_logs',
    'habits',
    'lifestyle_entries',
    'notification_preferences',
    'schedule_items',
    'tasks'
  ]
  loop
    policy_name := table_name || '_own_or_admin_all';
    execute format(
      'drop policy if exists %I on public.%I',
      policy_name,
      table_name
    );
    execute format(
      'create policy %I on public.%I for all '
      'using (user_id = (select auth.uid()) '
      'or (select private.current_app_role()) = ''admin'') '
      'with check (user_id = (select auth.uid()) '
      'or (select private.current_app_role()) = ''admin'')',
      policy_name,
      table_name
    );
  end loop;
end;
$optimize_owner_admin_policies$;
