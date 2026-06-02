create extension if not exists "pgcrypto";

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'Optimizer'));

  insert into public.notification_preferences (user_id)
  values (new.id);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create table public.behavioral_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  event_type text not null,
  value numeric,
  occurred_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.lifestyle_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  entry_date date not null,
  sleep_hours numeric,
  energy_score int check (energy_score between 0 and 100),
  stress_score int check (stress_score between 0 and 100),
  mood_score int check (mood_score between 0 and 100),
  notes text,
  created_at timestamptz not null default now(),
  unique (user_id, entry_date)
);

create table public.skillset_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  overall_score int not null check (overall_score between 0 and 100),
  archetype text not null,
  scores jsonb not null default '[]'::jsonb,
  generated_at timestamptz not null default now()
);

create table public.recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  reason text not null,
  action_label text not null,
  category text not null,
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  status text not null default 'new'
    check (status in ('new', 'accepted', 'dismissed', 'completed')),
  generated_at timestamptz not null default now()
);

create table public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  focus_prompts_enabled boolean not null default true,
  recovery_prompts_enabled boolean not null default true,
  weekly_summary_enabled boolean not null default true,
  quiet_hours_start time,
  quiet_hours_end time,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.behavioral_events enable row level security;
alter table public.lifestyle_entries enable row level security;
alter table public.skillset_profiles enable row level security;
alter table public.recommendations enable row level security;
alter table public.notification_preferences enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "behavioral_events_own_all"
  on public.behavioral_events for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "lifestyle_entries_own_all"
  on public.lifestyle_entries for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "skillset_profiles_select_own"
  on public.skillset_profiles for select
  using (auth.uid() = user_id);

create policy "recommendations_select_own"
  on public.recommendations for select
  using (auth.uid() = user_id);

create policy "recommendations_update_own"
  on public.recommendations for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "notification_preferences_own_all"
  on public.notification_preferences for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index behavioral_events_user_time_idx
  on public.behavioral_events (user_id, occurred_at desc);

create index lifestyle_entries_user_date_idx
  on public.lifestyle_entries (user_id, entry_date desc);

create index skillset_profiles_user_generated_idx
  on public.skillset_profiles (user_id, generated_at desc);

create index recommendations_user_generated_idx
  on public.recommendations (user_id, generated_at desc);
