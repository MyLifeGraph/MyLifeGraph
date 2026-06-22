create extension if not exists "pgcrypto";

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  timezone text not null default 'Europe/Berlin',
  role text not null default 'user'
    check (role in ('user', 'vip', 'admin', 'guest')),
  auth_provider text not null default 'email',
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists email text,
  add column if not exists role text not null default 'user',
  add column if not exists auth_provider text not null default 'email',
  add column if not exists onboarding_completed_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_role_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_role_check
      check (role in ('user', 'vip', 'admin', 'guest'));
  end if;
end $$;

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  focus_prompts_enabled boolean not null default true,
  recovery_prompts_enabled boolean not null default true,
  weekly_summary_enabled boolean not null default true,
  quiet_hours_start time,
  quiet_hours_end time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.daily_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  entry_date date not null,
  sleep_hours numeric,
  steps int,
  activity_level int check (activity_level between 0 and 10),
  screen_time_hours numeric,
  focus_minutes int,
  mood_score int check (mood_score between 0 and 10),
  mood_label text check (
    mood_label is null
    or mood_label in ('very_low', 'low', 'neutral', 'good', 'great')
  ),
  energy_level int check (energy_level between 0 and 10),
  stress_level int check (stress_level between 0 and 10),
  nutrition_notes text,
  day_focus text,
  reflection text,
  source text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, entry_date)
);

create table if not exists public.behavioral_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  daily_log_id uuid references public.daily_logs (id) on delete set null,
  event_type text not null,
  value numeric,
  unit text,
  occurred_at timestamptz not null,
  source text not null default 'app',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.behavioral_events
  add column if not exists daily_log_id uuid references public.daily_logs (id) on delete set null,
  add column if not exists unit text,
  add column if not exists source text not null default 'app';

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text,
  status text not null default 'todo'
    check (status in ('todo', 'in_progress', 'done', 'cancelled', 'archived')),
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'critical')),
  deadline timestamptz,
  source text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.schedule_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  location text,
  weekday int not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  color text not null default '#1f9d8a',
  source text not null default 'manual',
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  message text not null,
  type text not null default 'coaching'
    check (type in ('reminder', 'warning', 'coaching', 'deadline', 'summary')),
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'critical')),
  is_read boolean not null default false,
  action_url text,
  due_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.memory_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null
    check (
      type in (
        'pattern',
        'preference',
        'goal',
        'habit',
        'recurring_problem',
        'recommendation'
      )
    ),
  title text not null,
  content text not null,
  strength numeric not null default 0.5 check (strength between 0 and 1),
  evidence jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.memory_entries
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.ai_insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text not null,
  category text not null,
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'critical')),
  recommendation text,
  confidence numeric check (confidence is null or confidence between 0 and 1),
  source text not null default 'ai-engine',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  reason text not null,
  action_label text not null,
  category text not null,
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  status text not null default 'new'
    check (status in ('new', 'accepted', 'dismissed', 'completed')),
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'critical')),
  metadata jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.recommendations
  add column if not exists priority text not null default 'medium',
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.skillset_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  overall_score int not null check (overall_score between 0 and 100),
  archetype text not null,
  scores jsonb not null default '[]'::jsonb,
  generated_at timestamptz not null default now()
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text,
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'archived')),
  progress int not null default 0 check (progress between 0 and 100),
  due_date date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text,
  frequency text not null default 'daily'
    check (frequency in ('daily', 'weekly')),
  target int not null default 1 check (target > 0),
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  habit_id uuid not null references public.habits (id) on delete cascade,
  entry_date date not null,
  value int not null default 1,
  notes text,
  created_at timestamptz not null default now(),
  unique (habit_id, entry_date)
);

create table if not exists public.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  planned_minutes int not null,
  actual_minutes int,
  label text,
  distractions int not null default 0,
  social_media_warning boolean not null default false,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

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

  if to_regclass('public.profiles') is not null then
    execute 'select role from public.profiles where id = $1 limit 1'
      into result
      using auth.uid();
  end if;

  if result is null and to_regclass('public."User"') is not null then
    execute 'select role from public."User" where id = $1 limit 1'
      into result
      using auth.uid()::text;
  end if;

  return coalesce(result, 'user');
end;
$$;

revoke all on function private.current_app_role() from public;
grant execute on function private.current_app_role() to anon, authenticated, service_role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  provider text;
  display_name text;
begin
  provider := coalesce(new.raw_app_meta_data->>'provider', 'email');
  display_name := coalesce(
    new.raw_user_meta_data->>'display_name',
    new.raw_user_meta_data->>'full_name',
    split_part(coalesce(new.email, 'New User'), '@', 1),
    'New User'
  );

  insert into public.profiles (
    id,
    email,
    display_name,
    timezone,
    role,
    auth_provider,
    updated_at
  )
  values (
    new.id,
    new.email,
    display_name,
    'Europe/Berlin',
    case when provider = 'anonymous' then 'guest' else 'user' end,
    provider,
    now()
  )
  on conflict (id) do update
  set
    email = excluded.email,
    display_name = coalesce(public.profiles.display_name, excluded.display_name),
    auth_provider = excluded.auth_provider,
    role = coalesce(public.profiles.role, excluded.role),
    updated_at = now();

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
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
  if to_regclass('auth.users') is not null
     and not exists (
       select 1
       from pg_trigger
       where tgname = 'on_auth_user_created'
         and tgrelid = 'auth.users'::regclass
     ) then
    create trigger on_auth_user_created
      after insert on auth.users
      for each row execute function public.handle_new_user();
  end if;
end $$;

do $$
begin
  if to_regclass('public."User"') is not null then
    insert into public.profiles (
      id,
      email,
      display_name,
      timezone,
      role,
      auth_provider,
      onboarding_completed_at,
      created_at,
      updated_at
    )
    select
      id::uuid,
      email,
      name,
      coalesce(timezone, 'Europe/Berlin'),
      coalesce(role, 'user'),
      coalesce("authProvider", 'email'),
      case when "onboardingDone" then coalesce("updatedAt", now()) else null end,
      coalesce("createdAt", now()),
      coalesce("updatedAt", now())
    from public."User"
    where id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    on conflict (id) do update
    set
      email = excluded.email,
      display_name = excluded.display_name,
      timezone = excluded.timezone,
      role = excluded.role,
      auth_provider = excluded.auth_provider,
      onboarding_completed_at = excluded.onboarding_completed_at,
      updated_at = excluded.updated_at;
  end if;
end $$;

insert into public.notification_preferences (user_id)
select id
from public.profiles
on conflict (user_id) do nothing;

do $$
begin
  if to_regclass('public."DailyLog"') is not null then
    insert into public.daily_logs (
      user_id,
      entry_date,
      sleep_hours,
      steps,
      activity_level,
      screen_time_hours,
      focus_minutes,
      mood_label,
      energy_level,
      nutrition_notes,
      day_focus,
      reflection,
      source,
      metadata,
      created_at,
      updated_at
    )
    select
      "userId"::uuid,
      "date"::date,
      "sleepHours",
      steps,
      "activityLevel",
      "screenTimeHours",
      "focusMinutes",
      lower("mood"::text),
      "energyLevel",
      nutrition,
      "dayFocus",
      reflection,
      'legacy_camel_case',
      jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now()),
      coalesce("updatedAt", now())
    from public."DailyLog"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    on conflict (user_id, entry_date) do update
    set
      sleep_hours = excluded.sleep_hours,
      steps = excluded.steps,
      activity_level = excluded.activity_level,
      screen_time_hours = excluded.screen_time_hours,
      focus_minutes = excluded.focus_minutes,
      mood_label = excluded.mood_label,
      energy_level = excluded.energy_level,
      nutrition_notes = excluded.nutrition_notes,
      day_focus = excluded.day_focus,
      reflection = excluded.reflection,
      metadata = public.daily_logs.metadata || excluded.metadata,
      updated_at = excluded.updated_at;
  end if;
end $$;

do $$
begin
  if to_regclass('public."Task"') is not null then
    insert into public.tasks (
      user_id,
      title,
      description,
      status,
      priority,
      deadline,
      source,
      metadata,
      created_at,
      updated_at
    )
    select
      "userId"::uuid,
      title,
      description,
      case
        when status::text = 'DONE' then 'done'
        when status::text = 'IN_PROGRESS' then 'in_progress'
        when status::text = 'ARCHIVED' then 'archived'
        else 'todo'
      end,
      lower(priority::text),
      deadline,
      'legacy_camel_case',
      jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now()),
      coalesce("updatedAt", now())
    from public."Task"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

do $$
begin
  if to_regclass('public."SleepLog"') is not null then
    insert into public.behavioral_events (
      user_id,
      daily_log_id,
      event_type,
      value,
      unit,
      occurred_at,
      source,
      metadata,
      created_at
    )
    select
      legacy."userId"::uuid,
      daily.id,
      'sleep',
      legacy.hours,
      'hours',
      legacy.date,
      'legacy_camel_case',
      jsonb_build_object(
        'legacy_id', legacy.id,
        'quality', legacy.quality,
        'notes', legacy.notes
      ),
      coalesce(legacy."createdAt", now())
    from public."SleepLog" legacy
    left join public.daily_logs daily
      on daily.user_id = legacy."userId"::uuid
      and daily.entry_date = legacy.date::date
    where legacy."userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

do $$
begin
  if to_regclass('public."MoodLog"') is not null then
    insert into public.behavioral_events (
      user_id,
      daily_log_id,
      event_type,
      value,
      unit,
      occurred_at,
      source,
      metadata,
      created_at
    )
    select
      legacy."userId"::uuid,
      daily.id,
      event.event_type,
      event.value,
      event.unit,
      legacy.date,
      'legacy_camel_case',
      jsonb_build_object(
        'legacy_id', legacy.id,
        'mood_label', lower(legacy.mood::text),
        'notes', legacy.notes
      ),
      coalesce(legacy."createdAt", now())
    from public."MoodLog" legacy
    left join public.daily_logs daily
      on daily.user_id = legacy."userId"::uuid
      and daily.entry_date = legacy.date::date
    cross join lateral (
      values
        (
          'mood',
          case legacy.mood::text
            when 'GREAT' then 9
            when 'GOOD' then 7
            when 'NEUTRAL' then 5
            when 'LOW' then 3
            when 'VERY_LOW' then 1
            else null
          end::numeric,
          'score_0_10'
        ),
        ('energy', legacy."energyLevel"::numeric, 'score_0_10'),
        ('stress', legacy."stressLevel"::numeric, 'score_0_10')
    ) as event(event_type, value, unit)
    where legacy."userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and event.value is not null;
  end if;
end $$;

do $$
begin
  if to_regclass('public."ActivityLog"') is not null then
    insert into public.behavioral_events (
      user_id,
      daily_log_id,
      event_type,
      value,
      unit,
      occurred_at,
      source,
      metadata,
      created_at
    )
    select
      legacy."userId"::uuid,
      daily.id,
      event.event_type,
      event.value,
      event.unit,
      legacy.date,
      'legacy_camel_case',
      jsonb_build_object('legacy_id', legacy.id, 'notes', legacy.notes),
      coalesce(legacy."createdAt", now())
    from public."ActivityLog" legacy
    left join public.daily_logs daily
      on daily.user_id = legacy."userId"::uuid
      and daily.entry_date = legacy.date::date
    cross join lateral (
      values
        ('activity_steps', legacy.steps::numeric, 'steps'),
        ('activity_level', legacy."activityLevel"::numeric, 'score_0_10'),
        ('workout', legacy."workoutMinutes"::numeric, 'minutes')
    ) as event(event_type, value, unit)
    where legacy."userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and event.value is not null;
  end if;
end $$;

do $$
begin
  if to_regclass('public."ScheduleItem"') is not null then
    insert into public.schedule_items (
      user_id,
      title,
      location,
      weekday,
      starts_at,
      ends_at,
      color,
      source,
      notes,
      metadata,
      created_at,
      updated_at
    )
    select
      "userId"::uuid,
      title,
      location,
      weekday,
      "startsAt"::time,
      "endsAt"::time,
      coalesce(color, '#1f9d8a'),
      coalesce(source, 'legacy_camel_case'),
      notes,
      jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now()),
      coalesce("updatedAt", now())
    from public."ScheduleItem"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

do $$
begin
  if to_regclass('public."Notification"') is not null then
    insert into public.notifications (
      user_id,
      title,
      message,
      type,
      priority,
      is_read,
      action_url,
      due_at,
      metadata,
      created_at
    )
    select
      "userId"::uuid,
      title,
      message,
      lower(type::text),
      lower(priority::text),
      read,
      "actionUrl",
      "dueAt",
      jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now())
    from public."Notification"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

do $$
begin
  if to_regclass('public."CoachMessage"') is not null then
    insert into public.coach_messages (
      user_id,
      role,
      content,
      metadata,
      created_at
    )
    select
      "userId"::uuid,
      lower(role::text),
      content,
      coalesce(metadata, '{}'::jsonb) || jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now())
    from public."CoachMessage"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

do $$
begin
  if to_regclass('public."MemoryEntry"') is not null then
    insert into public.memory_entries (
      user_id,
      type,
      title,
      content,
      strength,
      evidence,
      last_seen_at,
      metadata,
      created_at,
      updated_at
    )
    select
      "userId"::uuid,
      lower(type::text),
      title,
      content,
      strength,
      coalesce(evidence, '[]'::jsonb),
      coalesce("lastSeenAt", now()),
      jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now()),
      coalesce("updatedAt", now())
    from public."MemoryEntry"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

do $$
begin
  if to_regclass('public."AIInsight"') is not null then
    insert into public.ai_insights (
      user_id,
      title,
      description,
      category,
      priority,
      recommendation,
      confidence,
      source,
      metadata,
      created_at
    )
    select
      "userId"::uuid,
      title,
      description,
      lower(category::text),
      lower(priority::text),
      recommendation,
      confidence,
      source,
      coalesce(metadata, '{}'::jsonb) || jsonb_build_object('legacy_id', id),
      coalesce("createdAt", now())
    from public."AIInsight"
    where "userId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  end if;
end $$;

create index if not exists profiles_role_idx
  on public.profiles (role);

create index if not exists daily_logs_user_date_idx
  on public.daily_logs (user_id, entry_date desc);

create index if not exists behavioral_events_user_time_idx
  on public.behavioral_events (user_id, occurred_at desc);

create index if not exists tasks_user_status_deadline_idx
  on public.tasks (user_id, status, deadline);

create index if not exists schedule_items_user_weekday_idx
  on public.schedule_items (user_id, weekday, starts_at);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists coach_messages_user_created_idx
  on public.coach_messages (user_id, created_at);

create index if not exists memory_entries_user_seen_idx
  on public.memory_entries (user_id, last_seen_at desc);

create index if not exists ai_insights_user_created_idx
  on public.ai_insights (user_id, created_at desc);

create index if not exists recommendations_user_generated_idx
  on public.recommendations (user_id, generated_at desc);

create index if not exists skillset_profiles_user_generated_idx
  on public.skillset_profiles (user_id, generated_at desc);

create index if not exists goals_user_status_idx
  on public.goals (user_id, status);

create index if not exists habits_user_active_idx
  on public.habits (user_id, active);

create index if not exists habit_logs_user_date_idx
  on public.habit_logs (user_id, entry_date desc);

create index if not exists focus_sessions_user_started_idx
  on public.focus_sessions (user_id, started_at desc);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles',
    'notification_preferences',
    'daily_logs',
    'behavioral_events',
    'tasks',
    'schedule_items',
    'notifications',
    'coach_messages',
    'memory_entries',
    'ai_insights',
    'recommendations',
    'skillset_profiles',
    'goals',
    'habits',
    'habit_logs',
    'focus_sessions'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
  end loop;
end $$;

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on table
  public.profiles,
  public.notification_preferences,
  public.daily_logs,
  public.behavioral_events,
  public.tasks,
  public.schedule_items,
  public.notifications,
  public.coach_messages,
  public.memory_entries,
  public.ai_insights,
  public.recommendations,
  public.skillset_profiles,
  public.goals,
  public.habits,
  public.habit_logs,
  public.focus_sessions
to authenticated, service_role;

do $$
begin
  drop policy if exists "profiles_own_or_admin_all" on public.profiles;
  create policy "profiles_own_or_admin_all"
    on public.profiles for all
    using (id = auth.uid() or private.current_app_role() = 'admin')
    with check (id = auth.uid() or private.current_app_role() = 'admin');
end $$;

do $$
declare
  table_name text;
  policy_name text;
begin
  foreach table_name in array array[
    'notification_preferences',
    'daily_logs',
    'behavioral_events',
    'tasks',
    'schedule_items',
    'notifications',
    'coach_messages',
    'memory_entries',
    'ai_insights',
    'recommendations',
    'skillset_profiles',
    'goals',
    'habits',
    'habit_logs',
    'focus_sessions'
  ] loop
    policy_name := table_name || '_own_or_admin_all';
    execute format('drop policy if exists %I on public.%I', policy_name, table_name);
    execute format(
      'create policy %I on public.%I for all using (user_id = auth.uid() or private.current_app_role() = ''admin'') with check (user_id = auth.uid() or private.current_app_role() = ''admin'')',
      policy_name,
      table_name
    );
  end loop;
end $$;
