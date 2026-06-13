create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.current_app_role()
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

revoke all on function private.current_app_role() from public;
grant execute on function private.current_app_role() to anon, authenticated, service_role;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
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
      execute format('alter table public.%I force row level security', table_name);
    end if;
  end loop;
end $$;

do $$
begin
  if to_regclass('public."User"') is not null then
    drop policy if exists "User_own_or_admin_select" on public."User";
    drop policy if exists "User_own_insert" on public."User";
    drop policy if exists "User_own_or_admin_update" on public."User";
    drop policy if exists "User_own_or_admin_all" on public."User";

    create policy "User_own_or_admin_select"
      on public."User" for select
      using (id = auth.uid()::text or private.current_app_role() = 'admin');

    create policy "User_own_insert"
      on public."User" for insert
      with check (id = auth.uid()::text);

    create policy "User_own_or_admin_update"
      on public."User" for update
      using (id = auth.uid()::text or private.current_app_role() = 'admin')
      with check (id = auth.uid()::text or private.current_app_role() = 'admin');
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
      execute format('drop policy if exists %I on public.%I', policy_name, table_name);
      execute format(
        'create policy %I on public.%I for all using ("userId" = auth.uid()::text or private.current_app_role() = ''admin'') with check ("userId" = auth.uid()::text or private.current_app_role() = ''admin'')',
        policy_name,
        table_name
      );
    end if;
  end loop;
end $$;

revoke execute on function public.handle_new_auth_user() from public;
revoke execute on function public.handle_new_auth_user() from anon;
revoke execute on function public.handle_new_auth_user() from authenticated;

revoke execute on function public.current_app_role() from public;
revoke execute on function public.current_app_role() from anon;
revoke execute on function public.current_app_role() from authenticated;
