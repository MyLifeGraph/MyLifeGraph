-- Add the development-only free read-only Coach data-agent contract while
-- retaining readable V1/V2 requests, responses, messages, and usage rows.

alter table public.coach_requests
  add column evidence jsonb,
  add column agent_trace jsonb,
  add column tool_call_count int,
  add column service_tier text;

create or replace function private.coach_evidence_is_valid_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  item jsonb;
  count_value numeric;
begin
  if jsonb_typeof(p_value) is distinct from 'array'
     or jsonb_array_length(p_value) > 100
     or octet_length(p_value::text) > 65536 then
    return false;
  end if;
  for item in select value from jsonb_array_elements(p_value) loop
    if not private.coach_jsonb_has_exact_keys(
      item,
      array['source', 'record_count', 'period_start', 'period_end']
    )
       or jsonb_typeof(item -> 'source') is distinct from 'string'
       or char_length(item ->> 'source') not between 1 and 80
       or jsonb_typeof(item -> 'record_count') is distinct from 'number'
       or jsonb_typeof(item -> 'period_start') not in ('string', 'null')
       or jsonb_typeof(item -> 'period_end') not in ('string', 'null')
       or jsonb_typeof(item -> 'period_start') is distinct from
         jsonb_typeof(item -> 'period_end')
       or (
         jsonb_typeof(item -> 'period_start') = 'string'
         and char_length(item ->> 'period_start') not between 1 and 40
       )
       or (
         jsonb_typeof(item -> 'period_end') = 'string'
         and char_length(item ->> 'period_end') not between 1 and 40
       ) then
      return false;
    end if;
    count_value := (item ->> 'record_count')::numeric;
    if count_value is null
       or count_value not between 0 and 50000
       or trunc(count_value) <> count_value then
      return false;
    end if;
  end loop;
  return true;
exception
  when others then
    return false;
end;
$$;

create or replace function private.coach_agent_trace_is_valid_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  item jsonb;
  limitation jsonb;
  expected_sequence int := 1;
  count_value numeric;
  duration_value numeric;
begin
  if not private.coach_jsonb_has_exact_keys(
    p_value,
    array['tool_call_count', 'steps', 'limitations']
  )
     or jsonb_typeof(p_value -> 'tool_call_count') is distinct from 'number'
     or jsonb_typeof(p_value -> 'steps') is distinct from 'array'
     or jsonb_array_length(p_value -> 'steps') > 12
     or jsonb_typeof(p_value -> 'limitations') is distinct from 'array'
     or jsonb_array_length(p_value -> 'limitations') > 20
     or octet_length(p_value::text) > 65536 then
    return false;
  end if;
  count_value := (p_value ->> 'tool_call_count')::numeric;
  if count_value is null
     or count_value is distinct from jsonb_array_length(p_value -> 'steps')
     or count_value not between 0 and 12
     or trunc(count_value) <> count_value then
    return false;
  end if;
  for item in select value from jsonb_array_elements(p_value -> 'steps') loop
    if not private.coach_jsonb_has_exact_keys(
      item,
      array[
        'sequence', 'tool', 'status', 'summary', 'row_count', 'duration_ms'
      ]
    )
       or jsonb_typeof(item -> 'sequence') is distinct from 'number'
       or (item ->> 'sequence')::numeric <> expected_sequence
       or jsonb_typeof(item -> 'tool') is distinct from 'string'
       or item ->> 'tool' not in (
         'inspect_data', 'query_data', 'run_python'
       )
       or jsonb_typeof(item -> 'status') is distinct from 'string'
       or item ->> 'status' not in ('completed', 'failed')
       or jsonb_typeof(item -> 'summary') is distinct from 'string'
       or char_length(item ->> 'summary') not between 1 and 500
       or jsonb_typeof(item -> 'row_count') not in ('number', 'null')
       or jsonb_typeof(item -> 'duration_ms') is distinct from 'number' then
      return false;
    end if;
    if jsonb_typeof(item -> 'row_count') = 'number' then
      count_value := (item ->> 'row_count')::numeric;
      if count_value is null
         or count_value not between 0 and 50000
         or trunc(count_value) <> count_value then
        return false;
      end if;
    end if;
    duration_value := (item ->> 'duration_ms')::numeric;
    if duration_value is null
       or duration_value not between 0 and 180000
       or trunc(duration_value) <> duration_value then
      return false;
    end if;
    expected_sequence := expected_sequence + 1;
  end loop;
  for limitation in
    select value from jsonb_array_elements(p_value -> 'limitations')
  loop
    if jsonb_typeof(limitation) is distinct from 'string'
       or char_length(limitation #>> '{}') not between 1 and 500 then
      return false;
    end if;
  end loop;
  return true;
exception
  when others then
    return false;
end;
$$;

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
  uncertainty jsonb;
  safety jsonb;
  provenance jsonb;
  trace jsonb;
  generated_at_text text;
  count_value numeric;
begin
  if not private.coach_jsonb_has_exact_keys(
    p_value,
    array[
      'contract_version', 'request_id', 'reply', 'uncertainty', 'safety',
      'evidence', 'agent_trace', 'provenance'
    ]
  )
     or jsonb_typeof(p_value -> 'contract_version') is distinct from 'string'
     or p_value ->> 'contract_version' is distinct from 'coach-response-v2'
     or jsonb_typeof(p_value -> 'request_id') is distinct from 'string'
     or p_value ->> 'request_id' is distinct from p_request_id::text
     or jsonb_typeof(p_value -> 'reply') is distinct from 'string'
     or char_length(p_value ->> 'reply') not between 1 and 4000
     or octet_length(p_value::text) > 196608
     or p_value -> 'evidence' is distinct from p_evidence
     or not private.coach_evidence_is_valid_v1(p_evidence) then
    return false;
  end if;

  uncertainty := p_value -> 'uncertainty';
  if not private.coach_jsonb_has_exact_keys(
    uncertainty,
    array['level', 'reason']
  )
     or jsonb_typeof(uncertainty -> 'level') is distinct from 'string'
     or uncertainty ->> 'level' is null
     or uncertainty ->> 'level' not in ('low', 'medium', 'high')
     or jsonb_typeof(uncertainty -> 'reason') is distinct from 'string'
     or char_length(uncertainty ->> 'reason') not between 1 and 300 then
    return false;
  end if;

  safety := p_value -> 'safety';
  if not private.coach_jsonb_has_exact_keys(safety, array['classification'])
     or jsonb_typeof(safety -> 'classification') is distinct from 'string'
     or safety ->> 'classification' is null
     or safety ->> 'classification' not in (
       'normal', 'sensitive', 'safety_redirect'
     ) then
    return false;
  end if;

  trace := p_value -> 'agent_trace';
  if not private.coach_agent_trace_is_valid_v1(trace) then
    return false;
  end if;

  provenance := p_value -> 'provenance';
  if not private.coach_jsonb_has_exact_keys(
    provenance,
    array[
      'source', 'provider', 'provider_mode', 'model_requested',
      'model_reported', 'model_source', 'prompt_version', 'context_version',
      'generated_at', 'provider_called', 'service_tier',
      'service_tier_status', 'fast_mode', 'snapshot_row_count', 'snapshot_bytes'
    ]
  )
     or jsonb_typeof(provenance -> 'source') is distinct from 'string'
     or provenance ->> 'source' is null
     or provenance ->> 'source' not in ('model', 'deterministic_safety')
     or jsonb_typeof(provenance -> 'provider') is distinct from 'string'
     or provenance ->> 'provider' is null
     or provenance ->> 'provider' not in (
       'disabled', 'local_codex_oauth', 'fake'
     )
     or jsonb_typeof(provenance -> 'provider_mode') is distinct from 'string'
     or provenance ->> 'provider_mode' is null
     or provenance ->> 'provider_mode' not in (
       'disabled', 'local_development_only', 'deterministic_test_only'
     )
     or jsonb_typeof(provenance -> 'model_source') is distinct from 'string'
     or provenance ->> 'model_source' is null
     or provenance ->> 'model_source' not in (
       'explicit', 'cli_default', 'not_applicable'
     )
     or jsonb_typeof(provenance -> 'prompt_version') is distinct from 'string'
     or provenance ->> 'prompt_version'
       is distinct from 'free-coach-agent-prompt-v1'
     or jsonb_typeof(provenance -> 'context_version') is distinct from 'string'
     or provenance ->> 'context_version'
       is distinct from 'personal-snapshot-v1'
     or jsonb_typeof(provenance -> 'generated_at') is distinct from 'string'
     or jsonb_typeof(provenance -> 'provider_called') is distinct from 'boolean'
     or jsonb_typeof(provenance -> 'service_tier') is distinct from 'string'
     or provenance ->> 'service_tier' is null
     or jsonb_typeof(provenance -> 'service_tier_status')
       is distinct from 'string'
     or provenance ->> 'service_tier_status' is null
     or jsonb_typeof(provenance -> 'fast_mode') is distinct from 'boolean'
     or jsonb_typeof(provenance -> 'snapshot_row_count')
       is distinct from 'number'
     or jsonb_typeof(provenance -> 'snapshot_bytes')
       is distinct from 'number'
     or (
       provenance ->> 'source' = 'model'
       and (provenance ->> 'provider_called')::boolean is not true
     )
     or (
       (safety ->> 'classification' = 'safety_redirect')
       is distinct from
       (provenance ->> 'source' = 'deterministic_safety')
     ) then
    return false;
  end if;

  count_value := (provenance ->> 'snapshot_row_count')::numeric;
  if count_value is null
     or count_value not between 0 and 50000
     or trunc(count_value) <> count_value then
    return false;
  end if;
  count_value := (provenance ->> 'snapshot_bytes')::numeric;
  if count_value is null
     or count_value not between 0 and 8388608
     or trunc(count_value) <> count_value then
    return false;
  end if;

  if jsonb_typeof(provenance -> 'model_requested') not in ('string', 'null')
     or jsonb_typeof(provenance -> 'model_reported') not in ('string', 'null')
     or (
       jsonb_typeof(provenance -> 'model_requested') = 'string'
       and char_length(provenance ->> 'model_requested') not between 1 and 100
     )
     or (
       jsonb_typeof(provenance -> 'model_reported') = 'string'
       and char_length(provenance ->> 'model_reported') not between 1 and 100
     ) then
    return false;
  end if;

  if provenance ->> 'provider' = 'local_codex_oauth' then
    if provenance ->> 'provider_mode'
         is distinct from 'local_development_only'
       or provenance ->> 'model_requested' is distinct from 'gpt-5.5'
       or (
         provenance ->> 'model_reported' is not null
         and provenance ->> 'model_reported' <> 'gpt-5.5'
       )
       or provenance ->> 'model_source' is distinct from 'explicit'
       or provenance ->> 'service_tier' is distinct from 'fast'
       or provenance ->> 'service_tier_status' is distinct from 'configured'
       or (provenance ->> 'fast_mode')::boolean is not true then
      return false;
    end if;
  elsif provenance ->> 'provider' = 'fake' then
    if provenance ->> 'provider_mode'
         is distinct from 'deterministic_test_only'
       or provenance -> 'model_requested' is distinct from 'null'::jsonb
       or provenance -> 'model_reported' is distinct from 'null'::jsonb
       or provenance ->> 'model_source' is distinct from 'not_applicable'
       or provenance ->> 'service_tier' is distinct from 'not_applicable'
       or provenance ->> 'service_tier_status'
         is distinct from 'not_applicable'
       or (provenance ->> 'fast_mode')::boolean is not false then
      return false;
    end if;
  else
    if provenance ->> 'provider_mode' is distinct from 'disabled'
       or provenance -> 'model_requested' is distinct from 'null'::jsonb
       or provenance -> 'model_reported' is distinct from 'null'::jsonb
       or provenance ->> 'model_source' is distinct from 'not_applicable'
       or provenance ->> 'service_tier' is distinct from 'not_applicable'
       or provenance ->> 'service_tier_status'
         is distinct from 'not_applicable'
       or (provenance ->> 'fast_mode')::boolean is not false
       or (provenance ->> 'provider_called')::boolean is not false
       or provenance ->> 'source' is distinct from 'deterministic_safety' then
      return false;
    end if;
  end if;

  generated_at_text := provenance ->> 'generated_at';
  return generated_at_text ~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
    and generated_at_text::timestamptz is not null;
exception
  when others then
    return false;
end;
$$;

alter function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  rename to coach_response_is_valid_before_free_agent;

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

create or replace function private.coach_error_is_valid_v1(p_value jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select private.coach_jsonb_has_exact_keys(
      p_value,
      array['code', 'message', 'retryable']
    )
    and jsonb_typeof(p_value -> 'code') is not distinct from 'string'
    and p_value ->> 'code' in (
      'provider_disabled', 'provider_unavailable', 'missing_cli',
      'not_logged_in', 'unavailable_model', 'account_limit',
      'provider_failure', 'timeout', 'provider_timeout', 'invalid_output',
      'tool_free_unavailable', 'unsafe_provider_event', 'context_failure',
      'interrupted', 'snapshot_too_large', 'tool_limit',
      'fast_mode_unavailable'
    )
    and jsonb_typeof(p_value -> 'message') is not distinct from 'string'
    and char_length(p_value ->> 'message') between 1 and 300
    and jsonb_typeof(p_value -> 'retryable') is not distinct from 'boolean';
$$;

create or replace function private.coach_usage_is_valid_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  prompt_bytes numeric;
  context_bytes numeric;
  reply_codepoints numeric;
begin
  if not private.coach_jsonb_has_exact_keys(
    p_value,
    array[
      'provider_called', 'prompt_bytes', 'context_bytes', 'reply_codepoints'
    ]
  )
     or jsonb_typeof(p_value -> 'provider_called') is distinct from 'boolean'
     or jsonb_typeof(p_value -> 'prompt_bytes') is distinct from 'number'
     or jsonb_typeof(p_value -> 'context_bytes') is distinct from 'number'
     or jsonb_typeof(p_value -> 'reply_codepoints') is distinct from 'number'
       then
    return false;
  end if;
  prompt_bytes := (p_value ->> 'prompt_bytes')::numeric;
  context_bytes := (p_value ->> 'context_bytes')::numeric;
  reply_codepoints := (p_value ->> 'reply_codepoints')::numeric;
  return prompt_bytes is not null
    and context_bytes is not null
    and reply_codepoints is not null
    and prompt_bytes between 0 and 131072
    and trunc(prompt_bytes) = prompt_bytes
    and context_bytes between 0 and 8388608
    and trunc(context_bytes) = context_bytes
    and reply_codepoints between 0 and 4000
    and trunc(reply_codepoints) = reply_codepoints;
exception
  when others then
    return false;
end;
$$;

alter table public.coach_usage_events
  drop constraint coach_usage_events_error_code,
  add constraint coach_usage_events_error_code check (
    (
      outcome = 'failed'
      and error_code is not null
      and error_code in (
        'provider_disabled', 'provider_unavailable', 'missing_cli',
        'not_logged_in', 'unavailable_model', 'account_limit',
        'provider_failure', 'timeout', 'provider_timeout', 'invalid_output',
        'tool_free_unavailable', 'unsafe_provider_event', 'context_failure',
        'interrupted', 'snapshot_too_large', 'tool_limit',
        'fast_mode_unavailable'
      )
    )
    or (outcome <> 'failed' and error_code is null)
  );

alter table public.coach_requests
  drop constraint coach_requests_contract,
  add constraint coach_requests_contract check (
    contract_version in (
      'coach-request-v1', 'coach-request-v2', 'coach-request-v3'
    )
  ),
  drop constraint coach_requests_context_scope,
  add constraint coach_requests_context_scope check (
    (
      contract_version = 'coach-request-v1'
      and context_scope = 'today'
      and context_parameters = '{}'::jsonb
    )
    or (
      contract_version = 'coach-request-v2'
      and private.coach_context_parameters_is_valid_v2(
        context_scope,
        context_parameters
      )
    )
    or (
      contract_version = 'coach-request-v3'
      and context_scope = 'today'
      and context_parameters = '{}'::jsonb
    )
  ),
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
      and prompt_version = 'free-coach-agent-prompt-v1'
      and context_version = 'personal-snapshot-v1'
    )
  ),
  drop constraint coach_requests_used_context,
  add constraint coach_requests_used_context check (
    (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and private.coach_used_context_is_valid_v1(used_context)
    )
    or (
      contract_version = 'coach-request-v3'
      and private.coach_evidence_is_valid_v1(used_context)
    )
  ),
  drop constraint coach_requests_response,
  add constraint coach_requests_response check (
    response is null
    or private.coach_response_is_valid_v1(response, request_id, used_context)
  ),
  add constraint coach_requests_agent_fields check (
    (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and evidence is null
      and agent_trace is null
      and tool_call_count is null
      and service_tier is null
    )
    or (
      contract_version = 'coach-request-v3'
      and (
        (
          state = 'completed'
          and evidence is not null
          and agent_trace is not null
          and tool_call_count is not null
          and service_tier is not null
          and private.coach_evidence_is_valid_v1(evidence)
          and private.coach_agent_trace_is_valid_v1(agent_trace)
          and tool_call_count between 0 and 12
          and tool_call_count = (agent_trace ->> 'tool_call_count')::int
          and service_tier in ('fast', 'not_applicable')
          and evidence is not distinct from used_context
          and evidence is not distinct from response -> 'evidence'
          and agent_trace is not distinct from response -> 'agent_trace'
          and service_tier is not distinct from
            response #>> '{provenance,service_tier}'
        )
        or (
          state = 'failed'
          and evidence is null
          and agent_trace is null
          and tool_call_count is null
          and service_tier is null
        )
        or (
          -- The established deletion body clears the response and changes
          -- state first; the outer wrapper clears these fields in the same
          -- transaction immediately afterward.
          state = 'deleted'
          and (
            (
              evidence is null
              and agent_trace is null
              and tool_call_count is null
              and service_tier is null
            )
            or (
              evidence is not null
              and agent_trace is not null
              and tool_call_count is not null
              and service_tier is not null
              and private.coach_evidence_is_valid_v1(evidence)
              and private.coach_agent_trace_is_valid_v1(agent_trace)
              and tool_call_count between 0 and 12
              and tool_call_count =
                (agent_trace ->> 'tool_call_count')::int
              and service_tier in ('fast', 'not_applicable')
            )
          )
        )
        or (
          -- Completion writes these backend-owned fields immediately before
          -- the established atomic V1 body advances the row to completed.
          state = 'pending'
          and (
            (
              evidence is null
              and agent_trace is null
              and tool_call_count is null
              and service_tier is null
            )
            or (
              evidence is not null
              and agent_trace is not null
              and tool_call_count is not null
              and service_tier is not null
              and private.coach_evidence_is_valid_v1(evidence)
              and private.coach_agent_trace_is_valid_v1(agent_trace)
              and tool_call_count between 0 and 12
              and tool_call_count =
                (agent_trace ->> 'tool_call_count')::int
              and service_tier in ('fast', 'not_applicable')
            )
          )
        )
      )
    )
  );

create or replace function public.claim_coach_request_v3(
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
  existing public.coach_requests%rowtype;
  result jsonb;
  used_count int;
  ignored jsonb;
  interrupted_error constant jsonb := jsonb_build_object(
    'code', 'interrupted',
    'message', 'The Coach request expired before completion.',
    'retryable', true
  );
  interrupted_usage constant jsonb := jsonb_build_object(
    'provider_called', false,
    'prompt_bytes', 0,
    'context_bytes', 0,
    'reply_codepoints', 0
  );
begin
  if p_user_id is null
     or p_request_id is null
     or p_local_date is null
     or p_claimed_at is null
     or p_lease_expires_at is null
     or p_provider is null
     or p_provider_mode is null
     or p_model_source is null
     or p_daily_limit is null
     or p_message_fingerprint is null
     or p_message_fingerprint !~ '^[0-9a-f]{64}$'
     or p_provider not in ('disabled', 'local_codex_oauth', 'fake')
     or p_provider_mode not in (
       'disabled', 'local_development_only', 'deterministic_test_only'
     )
     or p_model_source not in ('explicit', 'cli_default', 'not_applicable')
     or (
       p_model_requested is not null
       and char_length(p_model_requested) not between 1 and 100
     )
     or (
       p_provider = 'local_codex_oauth'
       and (
         p_provider_mode <> 'local_development_only'
         or p_model_requested is distinct from 'gpt-5.5'
         or p_model_source <> 'explicit'
       )
     )
     or (
       p_provider <> 'local_codex_oauth'
       and (
         p_model_requested is not null
         or p_model_source <> 'not_applicable'
       )
     )
     or p_lease_expires_at <= p_claimed_at
     or p_lease_expires_at > p_claimed_at + interval '5 minutes'
     or p_daily_limit <> 20 then
    raise exception 'Coach V3 claim is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into existing
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if found then
    if existing.user_id <> p_user_id
       or existing.contract_version <> 'coach-request-v3'
       or (
         existing.state <> 'deleted'
         and existing.message_fingerprint <> p_message_fingerprint
       ) then
      raise exception 'Coach request id was already used with different input'
        using errcode = 'PT409';
    end if;

    select count(*)::int into used_count
    from public.coach_requests
    where user_id = p_user_id and local_date = existing.local_date;

    if existing.state = 'deleted' then
      return jsonb_build_object(
        'state', 'deleted',
        'remaining_requests', greatest(p_daily_limit - used_count, 0),
        'response', null,
        'error', jsonb_build_object(
          'code', 'history_deleted',
          'message', 'This Coach request history was deleted.',
          'retryable', false
        )
      );
    end if;

    if existing.state = 'pending'
       and existing.lease_expires_at <= p_claimed_at then
      ignored := public.fail_coach_request_v1(
        p_user_id,
        p_request_id,
        interrupted_error,
        interrupted_usage,
        p_claimed_at
      );
      existing.state := 'failed';
      existing.error := interrupted_error;
    end if;

    if existing.state = 'completed' then
      return jsonb_build_object(
        'state', 'completed',
        'remaining_requests', greatest(p_daily_limit - used_count, 0),
        'response', existing.response,
        'error', null
      );
    elsif existing.state = 'failed' then
      return jsonb_build_object(
        'state', 'failed',
        'remaining_requests', greatest(p_daily_limit - used_count, 0),
        'response', null,
        'error', existing.error
      );
    end if;
    return jsonb_build_object(
      'state', 'in_progress',
      'remaining_requests', greatest(p_daily_limit - used_count, 0),
      'response', null,
      'error', null
    );
  end if;

  result := public.claim_coach_request_v2(
    p_user_id,
    p_request_id,
    p_message_fingerprint,
    'today',
    '{}'::jsonb,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    'controlled-coach-prompt-v3',
    'coach-context-v3',
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit
  );

  if result ->> 'state' = 'pending' then
    update public.coach_requests
    set contract_version = 'coach-request-v3',
        prompt_version = 'free-coach-agent-prompt-v1',
        context_version = 'personal-snapshot-v1'
    where request_id = p_request_id
      and user_id = p_user_id
      and contract_version = 'coach-request-v2';
    if not found then
      raise exception 'Coach V3 claim transition failed'
        using errcode = 'PT409';
    end if;
  end if;
  return result;
end;
$$;

create or replace function public.complete_coach_request_v2(
  p_user_id uuid,
  p_request_id uuid,
  p_user_message text,
  p_response jsonb,
  p_evidence jsonb,
  p_agent_trace jsonb,
  p_tool_call_count int,
  p_service_tier text,
  p_usage jsonb,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.coach_requests%rowtype;
  result jsonb;
begin
  if p_user_id is null
     or p_request_id is null
     or p_response is null
     or p_evidence is null
     or p_agent_trace is null
     or p_tool_call_count is null
     or p_service_tier is null
     or p_usage is null
     or p_completed_at is null
     or not private.coach_evidence_is_valid_v1(p_evidence)
     or not private.coach_agent_trace_is_valid_v1(p_agent_trace)
     or p_response -> 'evidence' is distinct from p_evidence
     or p_response -> 'agent_trace' is distinct from p_agent_trace
     or p_tool_call_count <> (p_agent_trace ->> 'tool_call_count')::int
     or p_tool_call_count not between 0 and 12
     or p_service_tier is distinct from
       p_response #>> '{provenance,service_tier}'
     or p_service_tier not in ('fast', 'not_applicable') then
    raise exception 'Coach V2 completion is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));
  select * into target
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if not found
     or target.user_id <> p_user_id
     or target.contract_version <> 'coach-request-v3' then
    raise exception 'Coach V3 request identity does not match'
      using errcode = 'PT409';
  end if;

  if target.state = 'completed' then
    if target.evidence is distinct from p_evidence
       or target.agent_trace is distinct from p_agent_trace
       or target.tool_call_count is distinct from p_tool_call_count
       or target.service_tier is distinct from p_service_tier then
      raise exception 'Coach V2 completion replay differs'
        using errcode = 'PT409';
    end if;
  elsif target.state = 'pending' then
    update public.coach_requests
    set evidence = p_evidence,
        agent_trace = p_agent_trace,
        tool_call_count = p_tool_call_count,
        service_tier = p_service_tier
    where request_id = p_request_id;
  else
    raise exception 'Coach V3 request is already terminal'
      using errcode = 'PT409';
  end if;

  result := public.complete_coach_request_v1(
    p_user_id,
    p_request_id,
    p_user_message,
    p_response,
    p_evidence,
    p_usage,
    p_completed_at
  );
  return result;
end;
$$;

alter function public.delete_coach_history_v1(uuid, timestamptz)
  rename to coach_delete_history_v1_before_free_agent;

revoke all on function public.coach_delete_history_v1_before_free_agent(
  uuid, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.delete_coach_history_v1(
  p_user_id uuid,
  p_deleted_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  result := public.coach_delete_history_v1_before_free_agent(
    p_user_id,
    p_deleted_at
  );
  update public.coach_requests
  set evidence = null,
      agent_trace = null,
      tool_call_count = null,
      service_tier = null
  where user_id = p_user_id and state = 'deleted';
  return result;
end;
$$;

comment on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) is
  'Claims one free-question Coach request with message-only replay identity, one owner turn, and the established local-day budget.';
comment on function public.complete_coach_request_v2(
  uuid, uuid, text, jsonb, jsonb, jsonb, int, text, jsonb, timestamptz
) is
  'Atomically completes a V3 Coach request with backend-generated evidence, tool trace, and service-tier provenance.';

revoke all on function private.coach_evidence_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_agent_trace_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_before_free_agent(
  jsonb, uuid, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
revoke all on function public.complete_coach_request_v2(
  uuid, uuid, text, jsonb, jsonb, jsonb, int, text, jsonb, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.delete_coach_history_v1(uuid, timestamptz)
  from public, anon, authenticated, service_role;

grant execute on function private.coach_evidence_is_valid_v1(jsonb)
  to service_role;
grant execute on function private.coach_agent_trace_is_valid_v1(jsonb)
  to service_role;
grant execute on function private.coach_response_is_valid_v2(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_before_free_agent(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) to service_role;
grant execute on function public.complete_coach_request_v2(
  uuid, uuid, text, jsonb, jsonb, jsonb, int, text, jsonb, timestamptz
) to service_role;
grant execute on function public.delete_coach_history_v1(uuid, timestamptz)
  to service_role;
