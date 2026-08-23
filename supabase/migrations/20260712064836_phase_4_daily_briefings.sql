-- Phase 4 deterministic daily briefing persistence.

create table public.daily_briefings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  briefing_date date not null,
  mode text not null check (mode in ('push', 'steady', 'recover', 'plan')),
  capacity_minutes int check (
    capacity_minutes is null or capacity_minutes between 1 and 480
  ),
  summary text not null check (length(trim(summary)) between 1 and 400),
  primary_action jsonb not null,
  support_actions jsonb not null default '[]'::jsonb,
  recommendation_ids uuid[] not null default '{}'::uuid[],
  evidence_refs jsonb not null default '[]'::jsonb,
  provenance jsonb not null,
  data_quality text not null check (
    data_quality in ('missing', 'partial', 'current', 'stale')
  ),
  metadata jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_briefings_user_date_key unique (user_id, briefing_date),
  constraint daily_briefings_primary_action_object check (
    jsonb_typeof(primary_action) = 'object'
  ),
  constraint daily_briefings_support_actions_array check (
    jsonb_typeof(support_actions) = 'array'
    and jsonb_array_length(support_actions) <= 2
  ),
  constraint daily_briefings_evidence_refs_array check (
    jsonb_typeof(evidence_refs) = 'array'
    and jsonb_array_length(evidence_refs) <= 20
  ),
  constraint daily_briefings_provenance_object check (
    jsonb_typeof(provenance) = 'object'
  ),
  constraint daily_briefings_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create index daily_briefings_user_generated_idx
  on public.daily_briefings (user_id, generated_at desc);

alter table public.daily_briefings enable row level security;
alter table public.daily_briefings force row level security;

grant usage on schema public to authenticated, service_role;
revoke all on table public.daily_briefings
  from anon, authenticated, service_role;
grant select on table public.daily_briefings to authenticated;
grant select, insert, update, delete on table public.daily_briefings to service_role;

create policy "daily_briefings_own_or_admin_select"
  on public.daily_briefings
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "daily_briefings_service_role_all"
  on public.daily_briefings
  for all
  to service_role
  using (true)
  with check (true);
