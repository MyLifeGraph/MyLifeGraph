-- Observation-ordered persistence for deterministic snapshots and weekly
-- reviews. Concurrent generators may become stale, but an older observation
-- can never replace a newer stored projection.

alter table public.user_state_snapshots
  add column if not exists source_observed_at timestamptz;
create or replace function private.default_projection_observation_v2()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.source_observed_at is null then
    new.source_observed_at := new.generated_at;
  end if;
  return new;
end;
$$;
create trigger user_state_snapshots_observation_default_v2
before insert or update of generated_at, source_observed_at
on public.user_state_snapshots
for each row execute function private.default_projection_observation_v2();

update public.user_state_snapshots
set source_observed_at = generated_at
where source_observed_at is null;
alter table public.user_state_snapshots
  alter column source_observed_at set not null;

alter table public.weekly_reviews
  add column if not exists source_observed_at timestamptz;
create trigger weekly_reviews_observation_default_v2
before insert or update of generated_at, source_observed_at
on public.weekly_reviews
for each row execute function private.default_projection_observation_v2();

update public.weekly_reviews
set source_observed_at = generated_at
where source_observed_at is null;
alter table public.weekly_reviews
  alter column source_observed_at set not null;

revoke all on function private.default_projection_observation_v2()
  from public, anon, authenticated, service_role;

alter table public.user_state_snapshots
  add constraint user_state_snapshots_observation_order_check
    check (source_observed_at <= generated_at);
alter table public.weekly_reviews
  add constraint weekly_reviews_observation_order_check
    check (source_observed_at <= generated_at);

create index user_state_snapshots_identity_observed_idx
  on public.user_state_snapshots
    (user_id, scope, period_key, source_observed_at desc, id desc);
create index weekly_reviews_identity_observed_idx
  on public.weekly_reviews
    (user_id, period_key, source_observed_at desc, id desc);

create or replace function public.persist_user_state_snapshot_v2(
  p_user_id uuid,
  p_scope text,
  p_period_key text,
  p_source_observed_at timestamptz,
  p_row jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  stored public.user_state_snapshots%rowtype;
  candidate_generated_at timestamptz;
begin
  candidate_generated_at := (p_row ->> 'generated_at')::timestamptz;
  if p_user_id is null
     or p_scope not in ('onboarding', 'daily', 'weekly')
     or trim(coalesce(p_period_key, '')) = ''
     or p_source_observed_at is null
     or jsonb_typeof(p_row) <> 'object'
     or p_row ->> 'user_id' is distinct from p_user_id::text
     or p_row ->> 'scope' is distinct from p_scope
     or p_row ->> 'period_key' is distinct from p_period_key
     or jsonb_typeof(p_row -> 'summary') <> 'object'
     or jsonb_typeof(p_row -> 'signals') <> 'object'
     or jsonb_typeof(p_row -> 'metadata') <> 'object'
     or candidate_generated_at < p_source_observed_at then
    raise exception 'Snapshot persistence payload is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  insert into public.user_state_snapshots (
    user_id,
    scope,
    period_key,
    summary,
    signals,
    source,
    source_observed_at,
    generated_at,
    metadata
  ) values (
    p_user_id,
    p_scope,
    p_period_key,
    p_row -> 'summary',
    p_row -> 'signals',
    coalesce(nullif(p_row ->> 'source', ''), 'backend'),
    p_source_observed_at,
    candidate_generated_at,
    p_row -> 'metadata'
  )
  on conflict (user_id, scope, period_key) do update
  set summary = excluded.summary,
      signals = excluded.signals,
      source = excluded.source,
      source_observed_at = excluded.source_observed_at,
      generated_at = excluded.generated_at,
      metadata = excluded.metadata
  where excluded.source_observed_at
          > public.user_state_snapshots.source_observed_at
  returning * into stored;

  if not found then
    select *
    into stored
    from public.user_state_snapshots
    where user_id = p_user_id
      and scope = p_scope
      and period_key = p_period_key;
  end if;
  if not found then
    raise exception 'Snapshot persistence returned no row.'
      using errcode = 'PT502';
  end if;
  return to_jsonb(stored);
end;
$$;

revoke all on function public.persist_user_state_snapshot_v2(
  uuid, text, text, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.persist_user_state_snapshot_v2(
  uuid, text, text, timestamptz, jsonb
) to service_role;

create or replace function public.persist_weekly_review_v2(
  p_user_id uuid,
  p_period_key text,
  p_source_observed_at timestamptz,
  p_row jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  stored public.weekly_reviews%rowtype;
  source_snapshot public.user_state_snapshots%rowtype;
  source_snapshot_id uuid;
  candidate_generated_at timestamptz;
  candidate_fingerprint text;
begin
  source_snapshot_id :=
    nullif(p_row #>> '{provenance,source_snapshot_id}', '')::uuid;
  candidate_generated_at := (p_row ->> 'generated_at')::timestamptz;
  candidate_fingerprint := p_row ->> 'source_fingerprint';
  if p_user_id is null
     or p_period_key !~ '^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$'
     or p_source_observed_at is null
     or jsonb_typeof(p_row) <> 'object'
     or p_row ->> 'user_id' is distinct from p_user_id::text
     or p_row ->> 'period_key' is distinct from p_period_key
     or jsonb_typeof(p_row -> 'facts') <> 'object'
     or jsonb_typeof(p_row -> 'proposals') <> 'array'
     or jsonb_typeof(p_row -> 'evidence_refs') <> 'array'
     or jsonb_typeof(p_row -> 'provenance') <> 'object'
     or candidate_fingerprint !~ '^[0-9a-f]{64}$'
     or p_row #>> '{provenance,source_fingerprint}'
          is distinct from candidate_fingerprint
     or candidate_generated_at < p_source_observed_at then
    raise exception 'Weekly review persistence payload is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select *
  into source_snapshot
  from public.user_state_snapshots
  where id = source_snapshot_id
    and user_id = p_user_id
    and scope = 'weekly'
    and period_key = p_period_key
  for update;
  if not found
     or source_snapshot.source_observed_at > p_source_observed_at
     or source_snapshot.generated_at is distinct from
       (p_row #>> '{provenance,source_snapshot_generated_at}')::timestamptz then
    raise exception 'Weekly snapshot changed. Generate the review again.'
      using errcode = 'PT409';
  end if;

  insert into public.weekly_reviews (
    user_id,
    period_key,
    week_start,
    week_end,
    timezone,
    data_quality,
    narrative,
    facts,
    proposals,
    evidence_refs,
    provenance,
    source_fingerprint,
    source_observed_at,
    generated_at,
    created_at,
    updated_at
  ) values (
    p_user_id,
    p_period_key,
    (p_row ->> 'week_start')::date,
    (p_row ->> 'week_end')::date,
    p_row ->> 'timezone',
    p_row ->> 'data_quality',
    p_row ->> 'narrative',
    p_row -> 'facts',
    p_row -> 'proposals',
    p_row -> 'evidence_refs',
    p_row -> 'provenance',
    candidate_fingerprint,
    p_source_observed_at,
    candidate_generated_at,
    coalesce(
      nullif(p_row ->> 'created_at', '')::timestamptz,
      candidate_generated_at
    ),
    (p_row ->> 'updated_at')::timestamptz
  )
  on conflict (user_id, period_key) do update
  set week_start = excluded.week_start,
      week_end = excluded.week_end,
      timezone = excluded.timezone,
      data_quality = excluded.data_quality,
      narrative = excluded.narrative,
      facts = excluded.facts,
      proposals = excluded.proposals,
      evidence_refs = excluded.evidence_refs,
      provenance = excluded.provenance,
      source_fingerprint = excluded.source_fingerprint,
      source_observed_at = excluded.source_observed_at,
      generated_at = excluded.generated_at,
      updated_at = excluded.updated_at
  where excluded.source_observed_at >= public.weekly_reviews.source_observed_at
  returning * into stored;

  if not found then
    select *
    into stored
    from public.weekly_reviews
    where user_id = p_user_id and period_key = p_period_key;
  end if;
  if not found then
    raise exception 'Weekly review persistence returned no row.'
      using errcode = 'PT502';
  end if;
  return to_jsonb(stored);
end;
$$;

revoke all on function public.persist_weekly_review_v2(
  uuid, text, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.persist_weekly_review_v2(
  uuid, text, timestamptz, jsonb
) to service_role;
