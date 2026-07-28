begin;
select no_plan();

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
(
  'b2000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'coach-longitudinal-v2@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-07-28T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Longitudinal V2"}'::jsonb,
  '2026-07-28T08:00:00Z',
  '2026-07-28T08:00:00Z'
),
(
  'b2000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'coach-longitudinal-v1@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-07-28T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Compatible V1"}'::jsonb,
  '2026-07-28T08:00:00Z',
  '2026-07-28T08:00:00Z'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v2('
      'uuid,uuid,text,text,jsonb,date,text,text,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_coach_request_v2('
      'uuid,uuid,text,text,jsonb,date,text,text,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  ),
  'the V2 claim RPC is callable only through the backend role'
);

select ok(
  private.coach_context_parameters_is_valid_v2(
    'today',
    '{}'::jsonb
  )
  and private.coach_context_parameters_is_valid_v2(
    'review',
    '{}'::jsonb
  )
  and private.coach_context_parameters_is_valid_v2(
    'patterns',
    '{"horizon":"all_available"}'::jsonb
  )
  and private.coach_context_parameters_is_valid_v2(
    'focus',
    '{"focus_session_id":"b2000000-0000-4000-8000-000000000101"}'::jsonb
  ),
  'every exact V2 context parameter shape is accepted'
);

select ok(
  not private.coach_context_parameters_is_valid_v2(
    'today',
    '{"horizon":"90_days"}'::jsonb
  )
  and not private.coach_context_parameters_is_valid_v2(
    'patterns',
    '{"horizon":"90_days","extra":true}'::jsonb
  )
  and not private.coach_context_parameters_is_valid_v2(
    'patterns',
    '{"horizon":"forever"}'::jsonb
  )
  and not private.coach_context_parameters_is_valid_v2(
    'focus',
    '{"focus_session_id":"not-a-uuid"}'::jsonb
  ),
  'unknown, mixed, and invalid V2 context parameters fail closed'
);

create temporary table coach_v2_claim on commit drop as
select public.claim_coach_request_v2(
  'b2000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000201',
  encode(
    extensions.digest(convert_to('Longitudinal request', 'UTF8'), 'sha256'),
    'hex'
  ),
  'patterns',
  '{"horizon":"all_available"}'::jsonb,
  '2026-07-28',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  'controlled-coach-prompt-v3',
  'coach-context-v3',
  '2026-07-28T10:00:00Z',
  '2026-07-28T10:02:00Z',
  20
) as value;

select is(
  (select value ->> 'state' from coach_v2_claim),
  'pending',
  'a valid longitudinal Coach request is claimed'
);

select is(
  (
    select concat_ws(
      '|',
      contract_version,
      context_scope,
      context_parameters ->> 'horizon',
      prompt_version,
      context_version
    )
    from public.coach_requests
    where request_id = 'b2000000-0000-4000-8000-000000000201'
  ),
  'coach-request-v2|patterns|all_available|controlled-coach-prompt-v3|coach-context-v3',
  'the V2 request stores its exact scope, parameters, and paired provenance'
);

select is(
  (
    select public.claim_coach_request_v2(
      'b2000000-0000-4000-8000-000000000001',
      'b2000000-0000-4000-8000-000000000201',
      encode(
        extensions.digest(convert_to('Longitudinal request', 'UTF8'), 'sha256'),
        'hex'
      ),
      'patterns',
      '{"horizon":"all_available"}'::jsonb,
      '2026-07-29',
      'disabled',
      'disabled',
      null,
      'not_applicable',
      'controlled-coach-prompt-v3',
      'coach-context-v3',
      '2026-07-28T10:00:30Z',
      '2026-07-28T10:02:30Z',
      20
    ) ->> 'state'
  ),
  'in_progress',
  'an exact replay keeps original backend configuration frozen'
);

select throws_ok(
  $$
    select public.claim_coach_request_v2(
      'b2000000-0000-4000-8000-000000000001',
      'b2000000-0000-4000-8000-000000000201',
      encode(
        extensions.digest(convert_to('Longitudinal request', 'UTF8'), 'sha256'),
        'hex'
      ),
      'patterns',
      '{"horizon":"1_year"}'::jsonb,
      '2026-07-28',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v3',
      'coach-context-v3',
      '2026-07-28T10:00:30Z',
      '2026-07-28T10:02:30Z',
      20
    )
  $$,
  'PT409',
  'Coach request id was already used with different input',
  'a request id cannot be replayed with another horizon'
);

select throws_ok(
  $$
    select public.claim_coach_request_v2(
      'b2000000-0000-4000-8000-000000000001',
      'b2000000-0000-4000-8000-000000000202',
      repeat('a', 64),
      'focus',
      '{"focus_session_id":"invalid"}'::jsonb,
      '2026-07-28',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v3',
      'coach-context-v3',
      '2026-07-28T10:03:00Z',
      '2026-07-28T10:04:00Z',
      20
    )
  $$,
  '22023',
  'Coach V2 claim is invalid',
  'an invalid focus parameter is rejected before persistence'
);

create temporary table longitudinal_manifest on commit drop as
select jsonb_build_array(
  jsonb_build_object(
    'source', 'daily_capture',
    'available_count', 3,
    'included_count', 3,
    'omitted_count', 0,
    'freshness', 'current'
  ),
  jsonb_build_object(
    'source', 'focus_reflections',
    'available_count', 2,
    'included_count', 2,
    'omitted_count', 0,
    'freshness', 'current'
  )
) as value;

select public.complete_coach_request_v1(
  'b2000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000201',
  'Longitudinal request',
  jsonb_build_object(
    'contract_version', 'coach-response-v1',
    'request_id', 'b2000000-0000-4000-8000-000000000201',
    'reply', 'Bounded longitudinal response.',
    'uncertainty', jsonb_build_object(
      'level', 'medium',
      'reason', 'The retained history has incomplete coverage.'
    ),
    'staged_suggestion', null,
    'safety', jsonb_build_object('classification', 'normal'),
    'used_context', (select value from longitudinal_manifest),
    'provenance', jsonb_build_object(
      'source', 'model',
      'provider', 'fake',
      'provider_mode', 'deterministic_test_only',
      'model_requested', null,
      'model_reported', null,
      'model_source', 'not_applicable',
      'prompt_version', 'controlled-coach-prompt-v3',
      'context_version', 'coach-context-v3',
      'generated_at', '2026-07-28T10:01:00Z',
      'provider_called', true
    )
  ),
  (select value from longitudinal_manifest),
  jsonb_build_object(
    'provider_called', true,
    'prompt_bytes', 100,
    'context_bytes', 200,
    'reply_codepoints', char_length('Bounded longitudinal response.')
  ),
  '2026-07-28T10:01:00Z'
);

select is(
  (
    select response #>> '{provenance,context_version}'
    from public.coach_requests
    where request_id = 'b2000000-0000-4000-8000-000000000201'
      and state = 'completed'
  ),
  'coach-context-v3',
  'the established completion RPC accepts a strict V3 response unchanged'
);

select is(
  (
    select public.claim_coach_request_v2(
      'b2000000-0000-4000-8000-000000000001',
      'b2000000-0000-4000-8000-000000000203',
      repeat('c', 64),
      'focus',
      '{"focus_session_id":"b2000000-0000-4000-8000-000000000101"}'::jsonb,
      '2026-07-28',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v3',
      'coach-context-v3',
      '2026-07-28T10:02:00Z',
      '2026-07-28T10:03:00Z',
      20
    ) ->> 'state'
  ),
  'pending',
  'a Focus-scoped request is persisted before history deletion'
);

select is(
  (
    select public.delete_coach_history_v1(
      'b2000000-0000-4000-8000-000000000001',
      '2026-07-28T10:04:00Z'
    ) ->> 'state'
  ),
  'deleted',
  'the established history delete path still completes for V2 rows'
);

select is(
  (
    select concat_ws(
      '|',
      state,
      context_scope,
      context_parameters::text,
      (message_fingerprint is null)::text,
      (response is null)::text,
      (used_context = '[]'::jsonb)::text
    )
    from public.coach_requests
    where request_id = 'b2000000-0000-4000-8000-000000000203'
  ),
  'deleted|today|{}|true|true|true',
  'a deleted Focus request retains no Focus UUID or conversation content'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.delete_coach_history_v1(uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.delete_coach_history_v1(uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.coach_delete_history_v1_before_longitudinal_context('
      'uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'only the hardened public history-delete wrapper remains backend-callable'
);

select is(
  (
    select public.claim_coach_request_v1(
      'b2000000-0000-4000-8000-000000000002',
      'b2000000-0000-4000-8000-000000000301',
      encode(
        extensions.digest(convert_to('Compatible V1 request', 'UTF8'), 'sha256'),
        'hex'
      ),
      'today',
      '2026-07-28',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v2',
      'coach-context-v2',
      '2026-07-28T11:00:00Z',
      '2026-07-28T11:01:00Z',
      20
    ) ->> 'state'
  ),
  'pending',
  'the established V1 request and V2 provenance path remains compatible'
);

select is(
  (
    select contract_version || '|' || context_scope || '|'
      || context_parameters::text
    from public.coach_requests
    where request_id = 'b2000000-0000-4000-8000-000000000301'
  ),
  'coach-request-v1|today|{}',
  'legacy request rows retain the exact V1 today empty-parameter shape'
);

select * from finish();
rollback;
