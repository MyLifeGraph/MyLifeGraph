-- Route current response V3 through the validator used by completion RPCs.
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
  if p_value ->> 'contract_version' = 'coach-response-v3' then
    return private.coach_response_is_valid_v3(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;
  if p_value ->> 'contract_version' = 'coach-response-v2' then
    return private.coach_response_is_valid_v2(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;
  if not private.coach_used_context_is_valid_v1(p_used_context) then
    return false;
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

revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  to service_role;
