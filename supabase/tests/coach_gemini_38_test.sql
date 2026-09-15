begin;
select plan(10);

with cases(requested, reported, valid) as (
  values
    ('gemini-3.6-flash', 'gemini-3.6-flash', true),
    ('gemini-3.7-flash', 'gemini-3.7-flash', true),
    ('gemini-3.7-flash', 'gemini-3.8-flash', false),
    ('gemini-3.8-flash', 'gemini-3.8-flash', true),
    ('gemini-unknown', 'gemini-unknown', false),
    ('gemini-3.8-flash', 'gemini-3.6-flash', false)
)
select is(
  private.coach_response_is_valid_v3(
    jsonb_build_object(
      'contract_version', 'coach-response-v3',
      'request_id', 'd7000000-0000-4000-8000-000000000001',
      'reply', 'One bounded result is available.',
      'uncertainty', jsonb_build_object('level', 'medium', 'reason', 'Only the bounded snapshot was available.'),
      'safety', jsonb_build_object('classification', 'normal'),
      'evidence', '[]'::jsonb,
      'agent_trace', jsonb_build_object('tool_call_count', 0, 'steps', '[]'::jsonb,
        'limitations', jsonb_build_array('No personal-data tool was needed.')),
      'provenance', jsonb_build_object(
        'source', 'model', 'provider', 'gemini', 'provider_mode', 'user_supplied_key',
        'model_requested', requested, 'model_reported', reported, 'model_source', 'explicit',
        'prompt_version', 'free-coach-agent-prompt-v5', 'context_version', 'personal-snapshot-v3',
        'generated_at', '2026-09-15T10:00:00Z', 'provider_called', true,
        'service_tier', 'not_applicable', 'service_tier_status', 'not_applicable',
        'fast_mode', false, 'snapshot_row_count', 0, 'snapshot_bytes', 0
      )
    ), 'd7000000-0000-4000-8000-000000000001', '[]'::jsonb
  ), valid, 'Gemini provenance: ' || requested || ' / ' || reported
) from cases;

select ok(position('gemini-3.8-flash' in pg_get_functiondef(
  'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer)'::regprocedure
)) > 0, 'internal V7 claim admits 3.8');
select ok(position('gemini-3.8-flash' in pg_get_functiondef(
  'public.claim_coach_request_v8_local_date_legacy(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer,boolean)'::regprocedure
)) > 0, 'V8 legacy delegate admits 3.8 without changing budget wrapper');

select ok(position('gemini-3.7-flash' in pg_get_functiondef(
  'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer)'::regprocedure
)) > 0, 'internal V7 claim admits exactly 3.7 as an additional choice');
select ok(position('gemini-3.7-flash' in pg_get_functiondef(
  'public.claim_coach_request_v8_local_date_legacy(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer,boolean)'::regprocedure
)) > 0, 'V8 delegate admits 3.7 with existing identity checks');
select * from finish();
rollback;
