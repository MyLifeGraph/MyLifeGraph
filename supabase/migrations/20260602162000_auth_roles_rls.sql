create extension if not exists "pgcrypto";

alter table if exists public."User"
  add column if not exists role text not null default 'user';

do $$
declare
  user_table regclass;
begin
  user_table := to_regclass('public."User"');

  if user_table is not null
     and not exists (
       select 1
       from pg_constraint
       where conname = 'User_role_check'
         and conrelid = user_table
     ) then
    alter table public."User"
      add constraint "User_role_check"
      check (role in ('user', 'vip', 'admin', 'guest'));
  end if;
end $$;

do $$
begin
  if to_regclass('public."User"') is not null then
    update public."User"
    set role = case
      when lower(coalesce("authProvider", '')) = 'guest' then 'guest'
      when role is null then 'user'
      else role
    end
    where role is null or lower(coalesce("authProvider", '')) = 'guest';
  end if;
end $$;

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

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  provider text;
  display_name text;
  default_role text;
begin
  provider := coalesce(new.raw_app_meta_data->>'provider', 'email');
  display_name := coalesce(
    new.raw_user_meta_data->>'display_name',
    new.raw_user_meta_data->>'full_name',
    split_part(coalesce(new.email, 'New User'), '@', 1),
    'New User'
  );
  default_role := case when provider = 'anonymous' then 'guest' else 'user' end;

  if to_regclass('public."User"') is not null then
    execute '
      insert into public."User" (
        id,
        email,
        name,
        timezone,
        "authProvider",
        "onboardingDone",
        role,
        "updatedAt"
      )
      values ($1, $2, $3, ''Europe/Berlin'', $4, false, $5, now())
      on conflict (id) do update
      set
        email = excluded.email,
        name = coalesce(public."User".name, excluded.name),
        "authProvider" = excluded."authProvider",
        role = coalesce(public."User".role, excluded.role),
        "updatedAt" = now()
    '
    using new.id::text, coalesce(new.email, ''), display_name, provider, default_role;
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'on_auth_user_created_app_user'
      and tgrelid = 'auth.users'::regclass
  ) then
    create trigger on_auth_user_created_app_user
      after insert on auth.users
      for each row execute function public.handle_new_auth_user();
  end if;
end $$;

alter table if exists public."User" enable row level security;
alter table if exists public."AIInsight" enable row level security;
alter table if exists public."ActivityLog" enable row level security;
alter table if exists public."CoachMessage" enable row level security;
alter table if exists public."DailyLog" enable row level security;
alter table if exists public."FocusSession" enable row level security;
alter table if exists public."Goal" enable row level security;
alter table if exists public."Habit" enable row level security;
alter table if exists public."MemoryEntry" enable row level security;
alter table if exists public."MoodLog" enable row level security;
alter table if exists public."Notification" enable row level security;
alter table if exists public."ScheduleItem" enable row level security;
alter table if exists public."SleepLog" enable row level security;
alter table if exists public."Task" enable row level security;

do $$
declare
  table_name text;
  policy_name text;
begin
  if to_regclass('public."User"') is not null then
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'User'
        and policyname = 'User_own_or_admin_select'
    ) then
      create policy "User_own_or_admin_select"
        on public."User" for select
        using (id = auth.uid()::text or public.current_app_role() = 'admin');
    end if;

    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'User'
        and policyname = 'User_own_insert'
    ) then
      create policy "User_own_insert"
        on public."User" for insert
        with check (id = auth.uid()::text);
    end if;

    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'User'
        and policyname = 'User_own_or_admin_update'
    ) then
      create policy "User_own_or_admin_update"
        on public."User" for update
        using (id = auth.uid()::text or public.current_app_role() = 'admin')
        with check (id = auth.uid()::text or public.current_app_role() = 'admin');
    end if;
  end if;

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
