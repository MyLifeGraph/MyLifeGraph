begin;
select plan(7);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v8(uuid,text,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_coach_request_v8(uuid,text,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.claim_coach_request_v8(uuid,text,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  ),
  'Coach V8 is service-role-only'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  ),
  'superseded Coach V7 has no execution grant'
);

select ok(
  has_function_privilege(
    'service_role',
    'private.coach_response_is_valid_v3(jsonb,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.coach_response_is_valid_v3(jsonb,uuid,jsonb)',
    'EXECUTE'
  ),
  'response V3 validation is backend-only'
);

select ok(
  (
    select pg_get_constraintdef(oid) like '%openai%'
      and pg_get_constraintdef(oid) like '%gemini%'
    from pg_constraint
    where conrelid = 'public.coach_requests'::regclass
      and conname = 'coach_requests_provider'
  ),
  'request provenance admits only the named BYOK providers'
);

select ok(
  (
    select pg_get_constraintdef(oid) like '%coach-response-v1%'
      and pg_get_constraintdef(oid) like '%coach-response-v2%'
      and pg_get_constraintdef(oid) like '%coach-response-v3%'
    from pg_constraint
    where conrelid = 'public.coach_requests'::regclass
      and conname = 'coach_requests_response'
  ),
  'response V3 retains V1 and V2 compatibility'
);

select is(
  private.coach_response_is_valid_v3(
    jsonb_build_object(
      'contract_version', 'coach-response-v3',
      'request_id', 'd7000000-0000-4000-8000-000000000001',
      'reply', 'One bounded result is available.',
      'uncertainty', jsonb_build_object(
        'level', 'medium',
        'reason', 'Only the bounded snapshot was available.'
      ),
      'safety', jsonb_build_object('classification', 'normal'),
      'evidence', '[]'::jsonb,
      'agent_trace', jsonb_build_object(
        'tool_call_count', 0,
        'steps', '[]'::jsonb,
        'limitations', jsonb_build_array('No personal-data tool was needed.')
      ),
      'provenance', jsonb_build_object(
        'source', 'model',
        'provider', 'openai',
        'provider_mode', 'user_supplied_key',
        'model_requested', 'gpt-5.6-terra',
        'model_reported', 'gpt-5.6-terra',
        'model_source', 'explicit',
        'prompt_version', 'free-coach-agent-prompt-v5',
        'context_version', 'personal-snapshot-v3',
        'generated_at', '2026-08-15T10:00:00Z',
        'provider_called', true,
        'service_tier', 'not_applicable',
        'service_tier_status', 'not_applicable',
        'fast_mode', false,
        'snapshot_row_count', 0,
        'snapshot_bytes', 0
      )
    ),
    'd7000000-0000-4000-8000-000000000001',
    '[]'::jsonb
  ),
  true,
  'exact OpenAI response V3 is valid'
);

select is(
  private.coach_response_is_valid_v3(
    jsonb_build_object('contract_version', 'coach-response-v3'),
    'd7000000-0000-4000-8000-000000000001',
    '[]'::jsonb
  ),
  false,
  'partial response V3 is rejected'
);

select * from finish();
rollback;
