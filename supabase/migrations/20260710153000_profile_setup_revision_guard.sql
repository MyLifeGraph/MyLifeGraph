alter table public.profiles
  add column if not exists setup_revision int not null default 0;

-- Keep the profile projection monotonic for users who already completed one or
-- more versioned Intake V1 revisions before this guard existed.
with latest_applied_setup as (
  select
    user_id,
    max(revision)::int as revision
  from public.intake_responses
  where version = 'intake-v1'
    and state = 'applied'
  group by user_id
)
update public.profiles as profile
set setup_revision = greatest(
  profile.setup_revision,
  latest_applied_setup.revision
)
from latest_applied_setup
where profile.id = latest_applied_setup.user_id;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_setup_revision_nonnegative'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_setup_revision_nonnegative
      check (setup_revision >= 0);
  end if;
end $$;
