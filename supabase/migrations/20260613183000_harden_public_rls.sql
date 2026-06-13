create extension if not exists "pgcrypto";

create or replace function public.current_app_role()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result text;
begin
  if auth.uid() is null then
    return 'guest';
  end if;

  if to_regclass('public."User"') is not null then
    execute 'select role from public."User" where id = $1 limit 1'
      into result
      using auth.uid()::text;
  end if;

  return coalesce(result, 'user');
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles',
    'behavioral_events',
    'lifestyle_entries',
    'skillset_profiles',
    'recommendations',
    'notification_preferences',
    'User',
    'AIInsight',
    'ActivityLog',
    'CoachMessage',
    'DailyLog',
    'FocusSession',
    'Goal',
    'Habit',
    'MemoryEntry',
    'MoodLog',
    'Notification',
    'ScheduleItem',
    'SleepLog',
    'Task'
  ] loop
    if to_regclass(format('public.%I', table_name)) is not null then
      execute format('alter table public.%I enable row level security', table_name);
      execute format('alter table public.%I force row level security', table_name);
    end if;
  end loop;
end $$;

do $$
begin
  if to_regclass('public.profiles') is not null then
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'profiles'
        and policyname = 'profiles_own_or_admin_all'
    ) then
      create policy "profiles_own_or_admin_all"
        on public.profiles for all
        using (id = auth.uid() or public.current_app_role() = 'admin')
        with check (id = auth.uid() or public.current_app_role() = 'admin');
    end if;
  end if;

  if to_regclass('public.notification_preferences') is not null then
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'notification_preferences'
        and policyname = 'notification_preferences_own_or_admin_all'
    ) then
      create policy "notification_preferences_own_or_admin_all"
        on public.notification_preferences for all
        using (user_id = auth.uid() or public.current_app_role() = 'admin')
        with check (user_id = auth.uid() or public.current_app_role() = 'admin');
    end if;
  end if;
end $$;

do $$
declare
  table_name text;
  policy_name text;
begin
  foreach table_name in array array[
    'behavioral_events',
    'lifestyle_entries',
    'skillset_profiles',
    'recommendations'
  ] loop
    if to_regclass(format('public.%I', table_name)) is not null then
      policy_name := table_name || '_own_or_admin_all';
      if not exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = table_name
          and policyname = policy_name
      ) then
        execute format(
          'create policy %I on public.%I for all using (user_id = auth.uid() or public.current_app_role() = ''admin'') with check (user_id = auth.uid() or public.current_app_role() = ''admin'')',
          policy_name,
          table_name
        );
      end if;
    end if;
  end loop;
end $$;

do $$
begin
  if to_regclass('public."User"') is not null then
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'User'
        and policyname = 'User_own_or_admin_all'
    ) then
      create policy "User_own_or_admin_all"
        on public."User" for all
        using (id = auth.uid()::text or public.current_app_role() = 'admin')
        with check (id = auth.uid()::text or public.current_app_role() = 'admin');
    end if;
  end if;
end $$;

do $$
declare
  table_name text;
  policy_name text;
begin
  foreach table_name in array array[
    'AIInsight',
    'ActivityLog',
    'CoachMessage',
    'DailyLog',
    'FocusSession',
    'Goal',
    'Habit',
    'MemoryEntry',
    'MoodLog',
    'Notification',
    'ScheduleItem',
    'SleepLog',
    'Task'
  ] loop
    if to_regclass(format('public.%I', table_name)) is not null then
      policy_name := table_name || '_own_or_admin_all';
      if not exists (
        select 1 from pg_policies
        where schemaname = 'public'
          and tablename = table_name
          and policyname = policy_name
      ) then
        execute format(
          'create policy %I on public.%I for all using ("userId" = auth.uid()::text or public.current_app_role() = ''admin'') with check ("userId" = auth.uid()::text or public.current_app_role() = ''admin'')',
          policy_name,
          table_name
        );
      end if;
    end if;
  end loop;
end $$;
