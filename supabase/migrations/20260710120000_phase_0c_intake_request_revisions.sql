alter table public.intake_responses
  add column if not exists request_id uuid,
  add column if not exists base_revision int,
  add column if not exists revision int,
  add column if not exists state text,
  add column if not exists updated_at timestamptz;

-- Rows created before Phase 0C have no request identity or revision. Rank the
-- complete legacy history deterministically, then mark only those unversioned
-- rows as applied. Using state is null as the legacy marker keeps this backfill
-- safe to re-run without rewriting later pending or applied requests.
with ranked_legacy_rows as (
  select
    id,
    row_number() over (
      partition by user_id, version
      order by completed_at, created_at, id
    )::int as revision
  from public.intake_responses
)
update public.intake_responses as intake_response
set
  request_id = intake_response.id,
  base_revision = ranked_legacy_rows.revision - 1,
  revision = ranked_legacy_rows.revision,
  state = 'applied',
  updated_at = intake_response.completed_at
from ranked_legacy_rows
where intake_response.id = ranked_legacy_rows.id
  and intake_response.state is null;

alter table public.intake_responses
  alter column request_id set not null,
  alter column base_revision set not null,
  alter column revision set not null,
  alter column state set default 'pending',
  alter column state set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'intake_responses_revision_positive'
      and conrelid = 'public.intake_responses'::regclass
  ) then
    alter table public.intake_responses
      add constraint intake_responses_revision_positive
      check (revision > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'intake_responses_base_revision_nonnegative'
      and conrelid = 'public.intake_responses'::regclass
  ) then
    alter table public.intake_responses
      add constraint intake_responses_base_revision_nonnegative
      check (base_revision >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'intake_responses_revision_follows_base'
      and conrelid = 'public.intake_responses'::regclass
  ) then
    alter table public.intake_responses
      add constraint intake_responses_revision_follows_base
      check (revision = base_revision + 1);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'intake_responses_state_valid'
      and conrelid = 'public.intake_responses'::regclass
  ) then
    alter table public.intake_responses
      add constraint intake_responses_state_valid
      check (state in ('pending', 'applied'));
  end if;
end $$;

create unique index if not exists intake_responses_user_version_request_unique_idx
  on public.intake_responses (user_id, version, request_id);

create unique index if not exists intake_responses_user_version_revision_unique_idx
  on public.intake_responses (user_id, version, revision);
