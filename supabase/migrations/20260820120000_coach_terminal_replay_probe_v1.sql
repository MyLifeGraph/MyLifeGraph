begin;

create function public.probe_coach_terminal_replay_v1(
  p_user_id uuid,
  p_contract_version text,
  p_request_id uuid,
  p_message_fingerprint text,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_provider_dispatch_required boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing public.coach_requests%rowtype;
begin
  if p_user_id is null
     or p_contract_version not in ('coach-request-v3', 'coach-request-v4')
     or p_request_id is null
     or p_message_fingerprint is null
     or p_message_fingerprint !~ '^[0-9a-f]{64}$'
     or p_provider is null
     or p_provider_mode is null
     or p_model_source is null
     or p_provider_dispatch_required is null then
    raise exception 'Coach terminal replay probe is invalid'
      using errcode = '22023';
  end if;

  -- Match the claim/delete/completion order. The owner lock serializes whole-
  -- history deletion; the request lock serializes terminal completion.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into existing
  from public.coach_requests
  where request_id = p_request_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'state', 'missing',
      'response', null,
      'error', null
    );
  end if;

  if existing.contract_version <> p_contract_version
     or existing.provider <> p_provider
     or existing.provider_mode <> p_provider_mode
     or existing.model_requested is distinct from p_model_requested
     or existing.model_source <> p_model_source
     or existing.provider_dispatch_required
       is distinct from p_provider_dispatch_required
     or (
       existing.state <> 'deleted'
       and existing.message_fingerprint <> p_message_fingerprint
     ) then
    raise exception 'Coach request id was already used with different input'
      using errcode = 'PT409';
  end if;

  if existing.state not in ('completed', 'failed', 'deleted') then
    return jsonb_build_object(
      'state', 'active',
      'response', null,
      'error', null
    );
  end if;

  return jsonb_build_object(
    'state', existing.state,
    'response', existing.response,
    'error', existing.error
  );
end;
$$;

comment on function public.probe_coach_terminal_replay_v1(
  uuid, text, uuid, text, text, text, text, text, boolean
) is
  'Returns only exact owner terminal Coach truth before provider admission; missing and active requests still use the atomic claim RPC.';

revoke all on function public.probe_coach_terminal_replay_v1(
  uuid, text, uuid, text, text, text, text, text, boolean
) from public, anon, authenticated, service_role;

grant execute on function public.probe_coach_terminal_replay_v1(
  uuid, text, uuid, text, text, text, text, text, boolean
) to service_role;

commit;
