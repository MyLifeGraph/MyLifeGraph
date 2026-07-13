-- Phase 10 follow-up: serialize every request lifecycle RPC by owner before
-- its existing request/row locks are acquired. History deletion already takes
-- this owner lock first. Wrapping the tested RPC bodies preserves their exact
-- transaction contract while preventing a completion from holding a row lock
-- and waiting on an owner lock held by a concurrent claim or deletion.

alter function public.claim_coach_request_v1(
  uuid,
  uuid,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  int
) rename to coach_claim_request_v1_locked_body;

alter function public.complete_coach_request_v1(
  uuid,
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb,
  timestamptz
) rename to coach_complete_request_v1_locked_body;

alter function public.fail_coach_request_v1(
  uuid,
  uuid,
  jsonb,
  jsonb,
  timestamptz
) rename to coach_fail_request_v1_locked_body;

revoke all on function public.coach_claim_request_v1_locked_body(
  uuid,
  uuid,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  int
) from public, anon, authenticated, service_role;

revoke all on function public.coach_complete_request_v1_locked_body(
  uuid,
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;

revoke all on function public.coach_fail_request_v1_locked_body(
  uuid,
  uuid,
  jsonb,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;

create function public.claim_coach_request_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_message_fingerprint text,
  p_context_scope text,
  p_local_date date,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_prompt_version text,
  p_context_version text,
  p_claimed_at timestamptz,
  p_lease_expires_at timestamptz,
  p_daily_limit int
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_user_id is null then
    raise exception 'Coach claim owner is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  return public.coach_claim_request_v1_locked_body(
    p_user_id,
    p_request_id,
    p_message_fingerprint,
    p_context_scope,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    p_prompt_version,
    p_context_version,
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit
  );
end;
$$;

create function public.complete_coach_request_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_user_message text,
  p_response jsonb,
  p_used_context jsonb,
  p_usage jsonb,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_user_id is null then
    raise exception 'Coach completion owner is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  return public.coach_complete_request_v1_locked_body(
    p_user_id,
    p_request_id,
    p_user_message,
    p_response,
    p_used_context,
    p_usage,
    p_completed_at
  );
end;
$$;

create function public.fail_coach_request_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_error jsonb,
  p_usage jsonb,
  p_failed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_user_id is null then
    raise exception 'Coach failure owner is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  return public.coach_fail_request_v1_locked_body(
    p_user_id,
    p_request_id,
    p_error,
    p_usage,
    p_failed_at
  );
end;
$$;

revoke all on function public.claim_coach_request_v1(
  uuid,
  uuid,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  int
) from public, anon, authenticated, service_role;

revoke all on function public.complete_coach_request_v1(
  uuid,
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;

revoke all on function public.fail_coach_request_v1(
  uuid,
  uuid,
  jsonb,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;

grant execute on function public.claim_coach_request_v1(
  uuid,
  uuid,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  int
) to service_role;

grant execute on function public.complete_coach_request_v1(
  uuid,
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb,
  timestamptz
) to service_role;

grant execute on function public.fail_coach_request_v1(
  uuid,
  uuid,
  jsonb,
  jsonb,
  timestamptz
) to service_role;
