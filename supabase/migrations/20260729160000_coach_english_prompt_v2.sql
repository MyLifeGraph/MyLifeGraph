begin;

alter table public.coach_requests
  drop constraint coach_requests_versions,
  add constraint coach_requests_versions check (
    (
      contract_version = 'coach-request-v1'
      and (
        (
          prompt_version = 'controlled-coach-prompt-v1'
          and context_version = 'coach-context-v1'
        )
        or (
          prompt_version = 'controlled-coach-prompt-v2'
          and context_version = 'coach-context-v2'
        )
      )
    )
    or (
      contract_version = 'coach-request-v2'
      and prompt_version = 'controlled-coach-prompt-v3'
      and context_version = 'coach-context-v3'
    )
    or (
      contract_version = 'coach-request-v3'
      and prompt_version in (
        'free-coach-agent-prompt-v1',
        'free-coach-agent-prompt-v2'
      )
      and context_version = 'personal-snapshot-v1'
    )
  );

alter function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  rename to coach_response_is_valid_before_prompt_v2;

create or replace function private.coach_response_is_valid_v2(
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
  prompt_version text;
  normalized jsonb;
begin
  prompt_version := p_value #>> '{provenance,prompt_version}';
  if prompt_version not in (
    'free-coach-agent-prompt-v1',
    'free-coach-agent-prompt-v2'
  ) then
    return false;
  end if;

  normalized := case
    when prompt_version = 'free-coach-agent-prompt-v2' then
      jsonb_set(
        p_value,
        '{provenance,prompt_version}',
        '"free-coach-agent-prompt-v1"'::jsonb,
        false
      )
    else p_value
  end;
  return private.coach_response_is_valid_before_prompt_v2(
    normalized,
    p_request_id,
    p_evidence
  );
exception
  when others then
    return false;
end;
$$;

create or replace function private.coach_response_is_valid_v1(
  p_value jsonb,
  p_request_id uuid,
  p_used_context jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
begin
  if p_value ->> 'contract_version' = 'coach-response-v2' then
    return private.coach_response_is_valid_v2(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;
  return private.coach_response_is_valid_before_free_agent(
    p_value,
    p_request_id,
    p_used_context
  );
exception
  when others then
    return false;
end;
$$;

create or replace function public.claim_coach_request_v4(
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
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  result := public.claim_coach_request_v3(
    p_user_id,
    p_request_id,
    p_message_fingerprint,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit
  );

  if result ->> 'state' = 'pending' then
    update public.coach_requests
    set prompt_version = 'free-coach-agent-prompt-v2'
    where request_id = p_request_id
      and user_id = p_user_id
      and contract_version = 'coach-request-v3'
      and prompt_version = 'free-coach-agent-prompt-v1'
      and context_version = 'personal-snapshot-v1'
      and state = 'pending';
    if not found then
      raise exception 'Coach V4 prompt transition failed'
        using errcode = 'PT409';
    end if;
  end if;
  return result;
end;
$$;

comment on function public.claim_coach_request_v4(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) is
  'Claims a free-question Coach request using English-only prompt V2 while preserving V1 terminal and in-progress replay.';

revoke all on function private.coach_response_is_valid_before_prompt_v2(
  jsonb, uuid, jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_coach_request_v4(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;

grant execute on function private.coach_response_is_valid_before_prompt_v2(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_v2(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function public.claim_coach_request_v4(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) to service_role;

commit;
