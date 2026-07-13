-- Preserve whether the provider was invoked when backend-owned safety copy
-- replaces its output. Both an early deterministic bypass and a post-provider
-- redirect are safety_redirect responses; provider_called distinguishes them.

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
declare
  uncertainty jsonb;
  suggestion jsonb;
  safety jsonb;
  provenance jsonb;
  generated_at_text text;
  generated_at_value timestamptz;
begin
  if not private.coach_jsonb_has_exact_keys(
    p_value,
    array[
      'contract_version',
      'request_id',
      'reply',
      'uncertainty',
      'staged_suggestion',
      'safety',
      'used_context',
      'provenance'
    ]
  )
     or jsonb_typeof(p_value -> 'contract_version') <> 'string'
     or p_value ->> 'contract_version' <> 'coach-response-v1'
     or jsonb_typeof(p_value -> 'request_id') <> 'string'
     or p_value ->> 'request_id' <> p_request_id::text
     or jsonb_typeof(p_value -> 'reply') <> 'string'
     or char_length(p_value ->> 'reply') not between 1 and 4000
     or p_value -> 'used_context' is distinct from p_used_context
     or not private.coach_used_context_is_valid_v1(p_used_context) then
    return false;
  end if;

  uncertainty := p_value -> 'uncertainty';
  if not private.coach_jsonb_has_exact_keys(
    uncertainty,
    array['level', 'reason']
  )
     or jsonb_typeof(uncertainty -> 'level') <> 'string'
     or uncertainty ->> 'level' not in ('low', 'medium', 'high')
     or jsonb_typeof(uncertainty -> 'reason') <> 'string'
     or char_length(uncertainty ->> 'reason') not between 1 and 300 then
    return false;
  end if;

  suggestion := p_value -> 'staged_suggestion';
  if jsonb_typeof(suggestion) <> 'null' then
    if not private.coach_jsonb_has_exact_keys(
      suggestion,
      array['title', 'rationale']
    )
       or jsonb_typeof(suggestion -> 'title') <> 'string'
       or char_length(suggestion ->> 'title') not between 1 and 120
       or jsonb_typeof(suggestion -> 'rationale') <> 'string'
       or char_length(suggestion ->> 'rationale') not between 1 and 500 then
      return false;
    end if;
  end if;

  safety := p_value -> 'safety';
  if not private.coach_jsonb_has_exact_keys(safety, array['classification'])
     or jsonb_typeof(safety -> 'classification') <> 'string'
     or safety ->> 'classification' not in (
       'normal', 'sensitive', 'safety_redirect'
     ) then
    return false;
  end if;

  provenance := p_value -> 'provenance';
  if not private.coach_jsonb_has_exact_keys(
    provenance,
    array[
      'source',
      'provider',
      'provider_mode',
      'model_requested',
      'model_reported',
      'model_source',
      'prompt_version',
      'context_version',
      'generated_at',
      'provider_called'
    ]
  )
     or jsonb_typeof(provenance -> 'source') <> 'string'
     or provenance ->> 'source' not in ('model', 'deterministic_safety')
     or jsonb_typeof(provenance -> 'provider') <> 'string'
     or provenance ->> 'provider' not in (
       'disabled', 'local_codex_oauth', 'fake'
     )
     or jsonb_typeof(provenance -> 'provider_mode') <> 'string'
     or provenance ->> 'provider_mode' not in (
       'disabled', 'local_development_only', 'deterministic_test_only'
     )
     or jsonb_typeof(provenance -> 'model_source') <> 'string'
     or provenance ->> 'model_source' not in (
       'explicit', 'cli_default', 'not_applicable'
     )
     or jsonb_typeof(provenance -> 'prompt_version') <> 'string'
     or provenance ->> 'prompt_version' <> 'controlled-coach-prompt-v1'
     or jsonb_typeof(provenance -> 'context_version') <> 'string'
     or provenance ->> 'context_version' <> 'coach-context-v1'
     or jsonb_typeof(provenance -> 'generated_at') <> 'string'
     or jsonb_typeof(provenance -> 'provider_called') <> 'boolean'
     or (
       provenance ->> 'source' = 'model'
       and (provenance ->> 'provider_called')::boolean is not true
     )
     or (
       provenance ->> 'source' = 'model'
       and safety ->> 'classification' = 'safety_redirect'
     )
     or (
       provenance ->> 'source' = 'deterministic_safety'
       and safety ->> 'classification' <> 'safety_redirect'
     )
     or (
       (provenance ->> 'provider_called')::boolean
       and provenance ->> 'provider' = 'disabled'
     ) then
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

  generated_at_text := provenance ->> 'generated_at';
  if generated_at_text !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then
    return false;
  end if;
  generated_at_value := generated_at_text::timestamptz;
  return generated_at_value is not null;
exception
  when others then
    return false;
end;
$$;

comment on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb) is
  'Validates strict coach-response-v1 output, including deterministic safety redirects before or after a provider call.';
