-- Preserve profile-local request dates while enforcing the operator-funded
-- allowance against a separate server-derived UTC budget period.

alter table public.coach_requests
  add column operator_budget_utc_date date;

update public.coach_requests
set operator_budget_utc_date = (created_at at time zone 'UTC')::date
where provider = 'operator_codex_pilot'
  and provider_dispatch_required;

create function private.set_coach_operator_budget_period_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  new.operator_budget_utc_date := case
    when new.provider = 'operator_codex_pilot'
      and new.provider_dispatch_required
      then (new.created_at at time zone 'UTC')::date
    else null
  end;
  return new;
end;
$$;

revoke all on function private.set_coach_operator_budget_period_v1()
  from public, anon, authenticated, service_role;

create trigger set_coach_operator_budget_period_v1
before insert or update of provider, provider_dispatch_required, created_at
on public.coach_requests
for each row execute function private.set_coach_operator_budget_period_v1();

alter table public.coach_requests
  add constraint coach_requests_operator_budget_period
  check (
    (provider = 'operator_codex_pilot' and provider_dispatch_required)
      = (operator_budget_utc_date is not null)
  );

create index coach_requests_operator_owner_utc_budget_idx
  on public.coach_requests (user_id, operator_budget_utc_date)
  where provider = 'operator_codex_pilot' and provider_dispatch_required;

create or replace function public.claim_coach_request_v8(
  p_user_id uuid,
  p_contract_version text,
  p_request_id uuid,
  p_message_fingerprint text,
  p_local_date date,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_claimed_at timestamptz,
  p_lease_expires_at timestamptz,
  p_daily_limit int,
  p_provider_dispatch_required boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.coach_requests%rowtype;
  request_exists boolean := false;
  budget_date date;
  used_count int := 0;
  result jsonb;
begin
  if p_contract_version = 'coach-request-v4'
     and p_provider = 'operator_codex_pilot'
     and p_claimed_at is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
    select * into existing_request
    from public.coach_requests
    where request_id = p_request_id;
    request_exists := found;
    budget_date := case
      when request_exists and existing_request.operator_budget_utc_date is not null
        then existing_request.operator_budget_utc_date
      when request_exists
        then (existing_request.created_at at time zone 'UTC')::date
      else (p_claimed_at at time zone 'UTC')::date
    end;
    select count(*)::int into used_count
    from public.coach_requests
    where user_id = p_user_id
      and provider = 'operator_codex_pilot'
      and provider_dispatch_required
      and operator_budget_utc_date = budget_date;
    if not request_exists
       and p_provider_dispatch_required
       and used_count >= 5 then
      raise exception 'Coach daily request limit reached' using errcode = 'PT429';
    end if;
  end if;

  result := public.claim_coach_request_v8_local_date_legacy(
    p_user_id,
    p_contract_version,
    p_request_id,
    p_message_fingerprint,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit,
    case
      -- The legacy implementation still owns the shared 20-turn profile-day
      -- limit and request lifecycle, but its former five-turn local-date
      -- operator check is no longer authoritative. Insert a new operator
      -- request without that flag, then set the flag atomically below so the
      -- dedicated UTC-period check above is the only five-turn gate.
      when p_contract_version = 'coach-request-v4'
        and p_provider = 'operator_codex_pilot'
        and p_provider_dispatch_required
        and not request_exists
        then false
      else p_provider_dispatch_required
    end
  );

  if p_contract_version = 'coach-request-v4'
     and p_provider = 'operator_codex_pilot'
     and budget_date is not null then
    if not request_exists
       and p_provider_dispatch_required
       and result ->> 'state' = 'pending' then
      update public.coach_requests
      set provider_dispatch_required = true
      where request_id = p_request_id
        and user_id = p_user_id;
      if not found then
        raise exception 'Coach operator request was not persisted'
          using errcode = 'PT503';
      end if;
    end if;
    select count(*)::int into used_count
    from public.coach_requests
    where user_id = p_user_id
      and provider = 'operator_codex_pilot'
      and provider_dispatch_required
      and operator_budget_utc_date = budget_date;
    result := jsonb_set(
      result,
      '{remaining_requests}',
      to_jsonb(greatest(5 - used_count, 0)),
      false
    );
  end if;
  return result;
end;
$$;

comment on function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) is
  'Current Coach V8 claim; local_date stays profile-local while operator-funded allowance uses operator_budget_utc_date.';
