-- Bind the operator-funded per-owner allowance to a server timestamp-derived
-- UTC day. A profile timezone remains presentation/planning data and can no
-- longer rotate the five-turn shared-provider bucket.

alter function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) rename to claim_coach_request_v8_local_date_legacy;

revoke all on function public.claim_coach_request_v8_local_date_legacy(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) from public, anon, authenticated, service_role;

create function public.claim_coach_request_v8(
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
  effective_budget_date date := case
    when p_contract_version = 'coach-request-v4'
      and p_provider = 'operator_codex_pilot'
      and p_claimed_at is not null
      then (p_claimed_at at time zone 'UTC')::date
    else p_local_date
  end;
begin
  return public.claim_coach_request_v8_local_date_legacy(
    p_user_id,
    p_contract_version,
    p_request_id,
    p_message_fingerprint,
    effective_budget_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit,
    p_provider_dispatch_required
  );
end;
$$;

revoke all on function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) to service_role;

comment on function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) is
  'Current Coach V8 claim; operator-funded daily budgets use claimed-at UTC while other providers retain profile-local dates.';
