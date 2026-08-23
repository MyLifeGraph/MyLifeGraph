-- Account-wide preparation capacity for Deadline Planner proposals.
-- The nullable value is explicit user input; null preserves the existing
-- per-plan-only behavior. Backend writes and plan confirmation share the
-- existing owner advisory lock so concurrent confirmations cannot bypass it.

alter table public.profiles
  add column if not exists daily_preparation_budget_minutes int;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_daily_preparation_budget_minutes_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_daily_preparation_budget_minutes_check
      check (
        daily_preparation_budget_minutes is null
        or (
          daily_preparation_budget_minutes between 25 and 480
          and daily_preparation_budget_minutes % 5 = 0
        )
      );
  end if;
end;
$$;

-- This setting affects backend scheduling authority. Authenticated clients may
-- read their profile through existing RLS but must use the verified FastAPI
-- path rather than direct Data API mutation.
revoke update (daily_preparation_budget_minutes)
  on table public.profiles from anon, authenticated;

create or replace function public.set_daily_preparation_budget_v1(
  p_user_id uuid,
  p_daily_preparation_budget_minutes int
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  stored_minutes int;
begin
  if p_user_id is null
     or (
       p_daily_preparation_budget_minutes is not null
       and (
         p_daily_preparation_budget_minutes not between 25 and 480
         or p_daily_preparation_budget_minutes % 5 <> 0
       )
     ) then
    raise exception 'Daily preparation budget is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  update public.profiles
  set daily_preparation_budget_minutes = p_daily_preparation_budget_minutes,
      updated_at = case
        when daily_preparation_budget_minutes
          is distinct from p_daily_preparation_budget_minutes
        then clock_timestamp()
        else updated_at
      end
  where id = p_user_id
  returning daily_preparation_budget_minutes into stored_minutes;

  if not found then
    raise exception 'Account profile is unavailable.' using errcode = 'PT404';
  end if;

  return jsonb_build_object(
    'daily_preparation_budget_minutes', stored_minutes
  );
end;
$$;

revoke all on function public.set_daily_preparation_budget_v1(uuid, int)
  from public, anon, authenticated;
grant execute on function public.set_daily_preparation_budget_v1(uuid, int)
  to service_role;

create or replace function private.enforce_deadline_plan_account_budget()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
declare
  account_budget int;
begin
  if old.reservation_state = 'proposed'
     and new.reservation_state = 'active' then
    select profile.daily_preparation_budget_minutes
    into account_budget
    from public.profiles as profile
    where profile.id = new.user_id;

    if account_budget is not null and exists (
      select 1
      from (
        select active.local_date, active.planned_minutes
        from public.deadline_plan_blocks as active
        where active.user_id = new.user_id
          and active.reservation_state = 'active'
          and not (
            active.plan_id = new.plan_id
            and active.revision = new.revision
          )
          and active.local_date in (
            select scoped.local_date
            from public.deadline_plan_blocks as scoped
            where scoped.user_id = new.user_id
              and scoped.plan_id = new.plan_id
              and scoped.revision = new.revision
              and scoped.reservation_state in ('proposed', 'active')
          )
        union all
        select candidate.local_date, candidate.planned_minutes
        from public.deadline_plan_blocks as candidate
        where candidate.user_id = new.user_id
          and candidate.plan_id = new.plan_id
          and candidate.revision = new.revision
          and candidate.reservation_state in ('proposed', 'active')
      ) as combined
      group by combined.local_date
      having sum(combined.planned_minutes) > account_budget
    ) then
      raise exception
        'Daily preparation budget is exceeded. Create a fresh preview.'
        using errcode = 'PT409';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_deadline_plan_account_budget()
  from public, anon, authenticated, service_role;

drop trigger if exists deadline_plan_blocks_enforce_account_budget
  on public.deadline_plan_blocks;
create trigger deadline_plan_blocks_enforce_account_budget
before update of reservation_state on public.deadline_plan_blocks
for each row execute function private.enforce_deadline_plan_account_budget();
