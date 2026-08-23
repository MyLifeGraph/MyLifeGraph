-- Phase 8 bounded, backend-owned weekly reviews.

create table public.weekly_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  period_key text not null,
  week_start date not null,
  week_end date not null,
  timezone text not null,
  data_quality text not null check (
    data_quality in ('insufficient', 'partial', 'sufficient')
  ),
  narrative text not null,
  facts jsonb not null,
  proposals jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  provenance jsonb not null,
  source_fingerprint text not null,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint weekly_reviews_user_period_key unique (user_id, period_key),
  constraint weekly_reviews_period_key_format check (
    period_key ~ '^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$'
    and period_key = to_char(week_start, 'IYYY-"W"IW')
  ),
  constraint weekly_reviews_week_start_monday check (
    extract(isodow from week_start) = 1
  ),
  constraint weekly_reviews_week_bounds check (
    week_end = week_start + 6
  ),
  constraint weekly_reviews_timezone_length check (
    length(trim(timezone)) between 1 and 100
  ),
  constraint weekly_reviews_narrative_length check (
    length(trim(narrative)) between 1 and 500
  ),
  constraint weekly_reviews_facts_object check (
    jsonb_typeof(facts) = 'object'
    and octet_length(facts::text) <= 65536
  ),
  constraint weekly_reviews_proposals_array check (
    jsonb_typeof(proposals) = 'array'
    and jsonb_array_length(proposals) <= 2
    and octet_length(proposals::text) <= 32768
  ),
  constraint weekly_reviews_evidence_refs_array check (
    jsonb_typeof(evidence_refs) = 'array'
    and jsonb_array_length(evidence_refs) <= 40
    and octet_length(evidence_refs::text) <= 32768
  ),
  constraint weekly_reviews_provenance_object check (
    jsonb_typeof(provenance) = 'object'
    and octet_length(provenance::text) <= 32768
    and provenance ? 'contract_version'
    and provenance ->> 'contract_version' = 'weekly-review-v1'
    and provenance ? 'source_fingerprint'
    and provenance ->> 'source_fingerprint' = source_fingerprint
  ),
  constraint weekly_reviews_source_fingerprint check (
    source_fingerprint ~ '^[0-9a-f]{64}$'
  )
);

create index weekly_reviews_user_generated_idx
  on public.weekly_reviews (user_id, generated_at desc, id desc);

alter table public.weekly_reviews enable row level security;
alter table public.weekly_reviews force row level security;

grant usage on schema public to authenticated, service_role;
revoke all on table public.weekly_reviews
  from anon, authenticated, service_role;
grant select on table public.weekly_reviews to authenticated;
grant select, insert, update, delete on table public.weekly_reviews
  to service_role;

create policy "weekly_reviews_own_or_admin_select"
  on public.weekly_reviews
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "weekly_reviews_service_role_all"
  on public.weekly_reviews
  for all
  to service_role
  using (true)
  with check (true);
