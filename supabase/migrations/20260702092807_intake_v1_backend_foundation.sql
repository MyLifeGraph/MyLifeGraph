create table if not exists public.intake_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  version text not null default 'intake-v1',
  responses jsonb not null,
  completed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint intake_responses_version_not_empty check (length(trim(version)) > 0),
  constraint intake_responses_responses_object check (jsonb_typeof(responses) = 'object'),
  constraint intake_responses_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create table if not exists public.user_state_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  scope text not null check (scope in ('onboarding', 'daily', 'weekly')),
  period_key text not null,
  summary jsonb not null,
  signals jsonb not null default '{}'::jsonb,
  source text not null default 'backend',
  generated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint user_state_snapshots_period_key_not_empty check (length(trim(period_key)) > 0),
  constraint user_state_snapshots_source_not_empty check (length(trim(source)) > 0),
  constraint user_state_snapshots_summary_object check (jsonb_typeof(summary) = 'object'),
  constraint user_state_snapshots_signals_object check (jsonb_typeof(signals) = 'object'),
  constraint user_state_snapshots_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create index if not exists intake_responses_user_completed_idx
  on public.intake_responses (user_id, completed_at desc);

create index if not exists user_state_snapshots_user_scope_generated_idx
  on public.user_state_snapshots (user_id, scope, generated_at desc);

create index if not exists user_state_snapshots_user_period_idx
  on public.user_state_snapshots (user_id, period_key);

alter table public.intake_responses enable row level security;
alter table public.intake_responses force row level security;

alter table public.user_state_snapshots enable row level security;
alter table public.user_state_snapshots force row level security;

grant usage on schema public to authenticated, service_role;

grant select on table
  public.intake_responses,
  public.user_state_snapshots
to authenticated;

grant select, insert, update, delete on table
  public.intake_responses,
  public.user_state_snapshots
to service_role;

do $$
begin
  drop policy if exists "intake_responses_own_or_admin_select" on public.intake_responses;
  create policy "intake_responses_own_or_admin_select"
    on public.intake_responses
    for select
    to authenticated
    using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');

  drop policy if exists "intake_responses_service_role_all" on public.intake_responses;
  create policy "intake_responses_service_role_all"
    on public.intake_responses
    for all
    to service_role
    using (true)
    with check (true);
end $$;

do $$
begin
  drop policy if exists "user_state_snapshots_own_or_admin_select" on public.user_state_snapshots;
  create policy "user_state_snapshots_own_or_admin_select"
    on public.user_state_snapshots
    for select
    to authenticated
    using (user_id = (select auth.uid()) or private.current_app_role() = 'admin');

  drop policy if exists "user_state_snapshots_service_role_all" on public.user_state_snapshots;
  create policy "user_state_snapshots_service_role_all"
    on public.user_state_snapshots
    for all
    to service_role
    using (true)
    with check (true);
end $$;
