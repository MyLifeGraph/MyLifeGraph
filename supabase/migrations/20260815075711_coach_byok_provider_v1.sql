-- Per-request BYOK Coach providers. Provider keys never cross this schema.

alter table public.coach_requests
  drop constraint coach_requests_provider,
  drop constraint coach_requests_provider_mode,
  drop constraint coach_requests_model_identity,
  drop constraint coach_requests_versions,
  drop constraint coach_requests_response;

alter table public.coach_usage_events
  drop constraint coach_usage_events_provider,
  drop constraint coach_usage_events_provider_mode,
  drop constraint coach_usage_events_model_identity;

create function private.coach_response_is_valid_v3(
  p_value jsonb,
  p_request_id uuid,
  p_evidence jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  normalized jsonb;
  provider text := p_value #>> '{provenance,provider}';
  expected_model text;
begin
  if p_value ->> 'contract_version' is distinct from 'coach-response-v3'
     or p_value #>> '{provenance,prompt_version}'
       is distinct from 'free-coach-agent-prompt-v5'
     or p_value #>> '{provenance,context_version}'
       is distinct from 'personal-snapshot-v3'
     or not private.coach_evidence_is_valid_v1(p_evidence) then
    return false;
  end if;

  normalized := jsonb_set(
    jsonb_set(
      p_value,
      '{contract_version}',
      '"coach-response-v2"'::jsonb,
      false
    ),
    '{provenance,prompt_version}',
    '"free-coach-agent-prompt-v4"'::jsonb,
    false
  );

  if provider in ('openai', 'gemini') then
    expected_model := case provider
      when 'openai' then 'gpt-5.6-terra'
      else 'gemini-3.6-flash'
    end;
    if p_value #>> '{provenance,provider_mode}'
         is distinct from 'user_supplied_key'
       or p_value #>> '{provenance,model_requested}'
         is distinct from expected_model
       or (
         p_value #>> '{provenance,model_reported}' is not null
         and p_value #>> '{provenance,model_reported}' <> expected_model
       )
       or p_value #>> '{provenance,model_source}' is distinct from 'explicit'
       or p_value #>> '{provenance,service_tier}'
         is distinct from 'not_applicable'
       or p_value #>> '{provenance,service_tier_status}'
         is distinct from 'not_applicable'
       or (p_value #>> '{provenance,fast_mode}')::boolean is not false then
      return false;
    end if;
    normalized := jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              normalized,
              '{provenance,provider}',
              '"fake"'::jsonb,
              false
            ),
            '{provenance,provider_mode}',
            '"deterministic_test_only"'::jsonb,
            false
          ),
          '{provenance,model_requested}',
          'null'::jsonb,
          false
        ),
        '{provenance,model_reported}',
        'null'::jsonb,
        false
      ),
      '{provenance,model_source}',
      '"not_applicable"'::jsonb,
      false
    );
  end if;

  return private.coach_response_is_valid_v2(
    normalized,
    p_request_id,
    p_evidence
  );
exception
  when others then
    return false;
end;
$$;

revoke all on function private.coach_response_is_valid_v3(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v3(jsonb, uuid, jsonb)
  to service_role;

alter table public.coach_requests
  add constraint coach_requests_provider check (
    provider in ('disabled', 'local_codex_oauth', 'fake', 'openai', 'gemini')
  ),
  add constraint coach_requests_provider_mode check (
    provider_mode in (
      'disabled', 'local_development_only', 'deterministic_test_only',
      'user_supplied_key'
    )
  ),
  add constraint coach_requests_model_identity check (
    (model_source = 'explicit' and model_requested is not null)
    or (model_source in ('cli_default', 'not_applicable') and model_requested is null)
  ),
  add constraint coach_requests_versions check (
    (
      contract_version = 'coach-request-v1'
      and (
        (prompt_version = 'controlled-coach-prompt-v1' and context_version = 'coach-context-v1')
        or (prompt_version = 'controlled-coach-prompt-v2' and context_version = 'coach-context-v2')
      )
    )
    or (
      contract_version = 'coach-request-v2'
      and prompt_version = 'controlled-coach-prompt-v3'
      and context_version = 'coach-context-v3'
    )
    or (
      contract_version = 'coach-request-v3'
      and prompt_version in ('free-coach-agent-prompt-v4', 'free-coach-agent-prompt-v5')
      and context_version = 'personal-snapshot-v3'
    )
  ),
  add constraint coach_requests_response check (
    response is null
    or (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and response ->> 'contract_version' = 'coach-response-v1'
      and private.coach_response_is_valid_v1(response, request_id, used_context)
    )
    or (
      contract_version = 'coach-request-v3'
      and response ->> 'contract_version' = 'coach-response-v2'
      and private.coach_response_is_valid_v2(response, request_id, used_context)
    )
    or (
      contract_version = 'coach-request-v3'
      and response ->> 'contract_version' = 'coach-response-v3'
      and private.coach_response_is_valid_v3(response, request_id, used_context)
    )
  );

alter table public.coach_usage_events
  add constraint coach_usage_events_provider check (
    provider in ('disabled', 'local_codex_oauth', 'fake', 'openai', 'gemini')
  ),
  add constraint coach_usage_events_provider_mode check (
    provider_mode in (
      'disabled', 'local_development_only', 'deterministic_test_only',
      'user_supplied_key'
    )
  ),
  add constraint coach_usage_events_model_identity check (
    (model_source = 'explicit' and model_requested is not null)
    or (model_source in ('cli_default', 'not_applicable') and model_requested is null)
  );

create function public.claim_coach_request_v7(
  p_user_id uuid,
  p_request_id uuid,
  p_message_fingerprint text,
  p_local_date date,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_claimed_at timestamptz,
  p_lease_expires_at timestamptz,
  p_daily_limit int
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  compatibility_provider text := p_provider;
  compatibility_mode text := p_provider_mode;
  compatibility_model text := p_model_requested;
  compatibility_source text := p_model_source;
begin
  if p_provider = 'openai' then
    if p_provider_mode <> 'user_supplied_key'
       or p_model_requested is distinct from 'gpt-5.6-terra'
       or p_model_source <> 'explicit' then
      raise exception 'OpenAI Coach V7 identity is invalid' using errcode = '22023';
    end if;
  elsif p_provider = 'gemini' then
    if p_provider_mode <> 'user_supplied_key'
       or p_model_requested is distinct from 'gemini-3.6-flash'
       or p_model_source <> 'explicit' then
      raise exception 'Gemini Coach V7 identity is invalid' using errcode = '22023';
    end if;
  elsif p_provider not in ('disabled', 'local_codex_oauth', 'fake') then
    raise exception 'Coach V7 provider is invalid' using errcode = '22023';
  end if;

  if p_provider in ('openai', 'gemini') then
    compatibility_provider := 'fake';
    compatibility_mode := 'deterministic_test_only';
    compatibility_model := null;
    compatibility_source := 'not_applicable';
  end if;

  result := public.claim_coach_request_v6(
    p_user_id, p_request_id, p_message_fingerprint, p_local_date,
    compatibility_provider, compatibility_mode, compatibility_model,
    compatibility_source, p_claimed_at, p_lease_expires_at, p_daily_limit
  );

  if result ->> 'state' = 'pending' then
    update public.coach_requests
    set provider = p_provider,
        provider_mode = p_provider_mode,
        model_requested = p_model_requested,
        model_source = p_model_source,
        prompt_version = 'free-coach-agent-prompt-v5'
    where request_id = p_request_id
      and user_id = p_user_id
      and state = 'pending'
      and created_at = p_claimed_at;
    if not found then
      raise exception 'Coach V7 claim transition failed' using errcode = 'PT409';
    end if;
  end if;
  return result;
end;
$$;

revoke all on function public.claim_coach_request_v7(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v7(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;
revoke all on function public.claim_coach_request_v6(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
