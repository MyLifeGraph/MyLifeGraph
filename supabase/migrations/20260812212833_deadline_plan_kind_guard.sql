-- Keep the persisted Deadline Plan root kind authoritative at the final
-- proposal RPC boundary. The FastAPI precheck remains useful feedback, while
-- this wrapper also protects callers that reach the service-role RPC directly.

alter function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) rename to propose_deadline_plan_with_timing_v1_without_kind_guard;

revoke all on function
  public.propose_deadline_plan_with_timing_v1_without_kind_guard(
    uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
  )
from public, anon, authenticated, service_role;

-- The strict V1 body has no timing provenance or persisted-root kind guard.
-- Keep it available only to the postgres-owned SECURITY DEFINER call chain.
revoke all on function public.propose_deadline_plan_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.propose_deadline_plan_with_timing_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_plan_id uuid,
  p_base_revision int,
  p_proposal jsonb,
  p_blocks jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing_request public.deadline_plan_request_identities%rowtype;
  persisted_kind text;
begin
  -- Retain the established proposal lock order. Both locks are transaction
  -- scoped and may be reacquired by the wrapped implementation.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13));

  -- Existing request identities still own replay and collision semantics. The
  -- wrapped implementation performs the complete exact-identity validation.
  select * into existing_request
  from public.deadline_plan_request_identities
  where request_id = p_request_id;
  if found then
    return public.propose_deadline_plan_with_timing_v1_without_kind_guard(
      p_user_id,
      p_request_id,
      p_request_fingerprint,
      p_plan_id,
      p_base_revision,
      p_proposal,
      p_blocks,
      p_now
    );
  end if;

  select plan.kind into persisted_kind
  from public.deadline_plans as plan
  where plan.id = p_plan_id
    and plan.user_id = p_user_id
    and plan.status in ('draft', 'active')
  for update;

  if found
     and p_proposal ->> 'kind' is not null
     and p_proposal ->> 'kind' <> persisted_kind then
    raise exception 'Deadline plan kind cannot be changed.'
      using errcode = 'PT409';
  end if;

  return public.propose_deadline_plan_with_timing_v1_without_kind_guard(
    p_user_id,
    p_request_id,
    p_request_fingerprint,
    p_plan_id,
    p_base_revision,
    p_proposal,
    p_blocks,
    p_now
  );
end;
$$;

revoke all on function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

grant execute on function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) to service_role;
