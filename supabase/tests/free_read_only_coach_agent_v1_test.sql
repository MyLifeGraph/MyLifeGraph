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
) values (
  'b3000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'free-coach-agent-v3@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-07-29T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Free Coach V3"}'::jsonb,
  '2026-07-29T08:00:00Z',
  '2026-07-29T08:00:00Z'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v8('
      'uuid,text,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.claim_coach_request_v8('
      'uuid,text,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.claim_coach_request_v8('
      'uuid,text,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.claim_coach_request_v7('
      'uuid,uuid,text,date,text,text,text,text,'
      'timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.complete_coach_request_v2('
      'uuid,uuid,text,jsonb,jsonb,jsonb,integer,text,jsonb,'
      'timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.complete_coach_request_v2('
      'uuid,uuid,text,jsonb,jsonb,jsonb,integer,text,jsonb,'
      'timestamp with time zone)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.delete_coach_history_v1(uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.delete_coach_history_v1(uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'only the backend role can execute the current V8 Coach claim, completion, and deletion RPCs'
);

select ok(
  has_function_privilege(
    'service_role',
    'private.coach_response_is_valid_v2(jsonb,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.coach_response_is_valid_v2(jsonb,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.coach_delete_history_v1_before_free_agent('
      'uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'the response validator is backend-only and the superseded delete body is not callable'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.coach_requests',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.coach_requests',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.coach_requests',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.coach_requests',
    'DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.coach_usage_events',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.coach_usage_events',
    'INSERT'
  ),
  'application users have no direct Coach request or usage-ledger authority'
);

select ok(
  private.coach_error_is_valid_v1(
    jsonb_build_object(
      'code', 'fast_mode_unavailable',
      'message', 'The configured Fast service tier is unavailable.',
      'retryable', false
    )
  )
  and not private.coach_error_is_valid_v1(
    jsonb_build_object(
      'code', 'silent_standard_fallback',
      'message', 'The provider silently used the standard tier.',
      'retryable', false
    )
  ),
  'Fast-mode unavailability is explicit while an uncontracted fallback code is rejected'
);

create temporary table coach_v3_claim on commit drop as
select public.claim_coach_request_v8(
  'b3000000-0000-4000-8000-000000000001',
  'coach-request-v3',
  'b3000000-0000-4000-8000-000000000201',
  encode(
    extensions.digest(
      convert_to('How did focus change?', 'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  '2026-07-29',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-07-29T10:00:00Z',
  '2026-07-29T10:02:00Z',
  20,
  true
) as value;

select is(
  (select value ->> 'state' from coach_v3_claim),
  'pending',
  'a message-only V3 request is claimed'
);

select is(
  (select (value ->> 'remaining_requests')::int from coach_v3_claim),
  19,
  'the first V3 claim consumes exactly one daily question'
);

select is(
  (
    select concat_ws(
      '|',
      contract_version,
      context_scope,
      context_parameters::text,
      local_date::text,
      provider,
      provider_mode,
      coalesce(model_requested, 'null'),
      model_source,
      prompt_version,
      context_version,
      state
    )
    from public.coach_requests
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'coach-request-v3|today|{}|2026-07-29|fake|deterministic_test_only|null|not_applicable|free-coach-agent-prompt-v5|personal-snapshot-v3|pending',
  'the claim persists the exact V3 contract and fixed context projection'
);

select is(
  (
    select public.claim_coach_request_v8(
      'b3000000-0000-4000-8000-000000000001',
      'coach-request-v3',
      'b3000000-0000-4000-8000-000000000201',
      encode(
        extensions.digest(
          convert_to('How did focus change?', 'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      '2026-07-30',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      '2026-07-29T10:00:30Z',
      '2026-07-29T10:02:30Z',
      20,
      true
    ) ->> 'state'
  ),
  'in_progress',
  'an exact message replay ignores a changed backend date while preserving provider identity'
);

select is(
  (
    select concat_ws('|', local_date::text, provider, provider_mode)
    from public.coach_requests
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  '2026-07-29|fake|deterministic_test_only',
  'replay keeps the original backend configuration frozen'
);

select throws_ok(
  $$
    select public.claim_coach_request_v8(
      'b3000000-0000-4000-8000-000000000001',
      'coach-request-v3',
      'b3000000-0000-4000-8000-000000000201',
      repeat('f', 64),
      '2026-07-29',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      '2026-07-29T10:00:40Z',
      '2026-07-29T10:02:40Z',
      20,
      true
    )
  $$,
  'PT409',
  'Coach request id was already used with different input',
  'a V3 request id cannot be replayed with another message'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'b3000000-0000-4000-8000-000000000001';

select throws_ok(
  $$
    update public.coach_requests
    set state = 'failed'
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  $$,
  '42501',
  null,
  'an authenticated owner cannot mutate the backend request ledger directly'
);

select throws_ok(
  $$
    select public.claim_coach_request_v8(
      'b3000000-0000-4000-8000-000000000001',
      'coach-request-v3',
      'b3000000-0000-4000-8000-000000000299',
      repeat('a', 64),
      '2026-07-29',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      '2026-07-29T10:00:45Z',
      '2026-07-29T10:02:45Z',
      20,
      true
    )
  $$,
  '42501',
  null,
  'an authenticated owner cannot invoke the backend claim RPC'
);

reset role;

create temporary table coach_v3_evidence on commit drop as
select jsonb_build_array(
  jsonb_build_object(
    'source', 'focus_sessions',
    'record_count', 7,
    'period_start', '2026-07-01T08:00:00+00:00',
    'period_end', '2026-07-28T09:00:00+00:00'
  )
) as value;

select is(
  private.coach_evidence_is_valid_v1(null::jsonb),
  false,
  'SQL NULL is not accepted as an empty evidence array'
);

select ok(
  private.coach_evidence_is_valid_v1(
    jsonb_build_array(
      jsonb_build_object(
        'source', 'focus_sessions',
        'record_count', 0,
        'period_start', null,
        'period_end', null
      )
    )
  )
  and not private.coach_evidence_is_valid_v1(
    jsonb_build_array(
      jsonb_build_object(
        'source', 'focus_sessions',
        'record_count', 1,
        'period_start', '2026-07-01T08:00:00+00:00',
        'period_end', null
      )
    )
  )
  and not private.coach_evidence_is_valid_v1(
    jsonb_build_array(
      jsonb_build_object(
        'source', 'focus_sessions',
        'record_count', 1,
        'period_start', null,
        'period_end', '2026-07-28T09:00:00+00:00'
      )
    )
  ),
  'evidence periods must be both strings or both JSON null'
);

create temporary table coach_v3_trace on commit drop as
select jsonb_build_object(
  'tool_call_count', 2,
  'steps', jsonb_build_array(
    jsonb_build_object(
      'sequence', 1,
      'tool', 'inspect_data',
      'status', 'completed',
      'summary', 'Inspected the personal data catalog.',
      'row_count', null,
      'duration_ms', 3
    ),
    jsonb_build_object(
      'sequence', 2,
      'tool', 'query_data',
      'status', 'completed',
      'summary', 'Ran read-only SQL and returned 7 rows.',
      'row_count', 7,
      'duration_ms', 8
    )
  ),
  'limitations', jsonb_build_array(
    'The records are observational and do not establish causality.'
  )
) as value;

select is(
  private.coach_agent_trace_is_valid_v1(null::jsonb),
  false,
  'SQL NULL is not accepted as an agent trace'
);

create temporary table coach_v3_response on commit drop as
select jsonb_build_object(
  'contract_version', 'coach-response-v2',
  'request_id', 'b3000000-0000-4000-8000-000000000201',
  'reply',
    'Across seven recorded sessions, completed focus time became steadier.',
  'uncertainty', jsonb_build_object(
    'level', 'medium',
    'reason', 'Only seven sessions are available in the recorded period.'
  ),
  'safety', jsonb_build_object('classification', 'normal'),
  'evidence', (select value from coach_v3_evidence),
  'agent_trace', (select value from coach_v3_trace),
  'provenance', jsonb_build_object(
    'source', 'model',
    'provider', 'fake',
    'provider_mode', 'deterministic_test_only',
    'model_requested', null,
    'model_reported', null,
    'model_source', 'not_applicable',
    'prompt_version', 'free-coach-agent-prompt-v4',
    'context_version', 'personal-snapshot-v3',
    'generated_at', '2026-07-29T10:01:00Z',
    'provider_called', true,
    'service_tier', 'not_applicable',
    'service_tier_status', 'not_applicable',
    'fast_mode', false,
    'snapshot_row_count', 7,
    'snapshot_bytes', 4096
  )
) as value;

create temporary table coach_v3_usage on commit drop as
select jsonb_build_object(
  'provider_called', true,
  'prompt_bytes', 512,
  'context_bytes', 4096,
  'reply_codepoints',
    char_length(
      'Across seven recorded sessions, completed focus time became steadier.'
    )
) as value;

create temporary table coach_v3_current_response on commit drop as
select jsonb_set(
  jsonb_set(
    (select value from coach_v3_response),
    '{contract_version}',
    '"coach-response-v3"'::jsonb
  ),
  '{provenance,prompt_version}',
  '"free-coach-agent-prompt-v5"'::jsonb
) as value;

select ok(
  private.coach_response_is_valid_v2(
    (select value from coach_v3_response),
    'b3000000-0000-4000-8000-000000000201',
    (select value from coach_v3_evidence)
  ),
  'the exact fake-provider response-v2 fixture is valid'
);

select is(
  private.coach_response_is_valid_v2(
    null::jsonb,
    'b3000000-0000-4000-8000-000000000201',
    (select value from coach_v3_evidence)
  ),
  false,
  'SQL NULL is not accepted as a response-v2 envelope'
);

select is(
  (
    select count(*)::int
    from (
      values
        (array['contract_version']::text[]),
        (array['request_id']::text[]),
        (array['reply']::text[]),
        (array['uncertainty', 'level']::text[]),
        (array['uncertainty', 'reason']::text[]),
        (array['safety', 'classification']::text[]),
        (array['provenance', 'source']::text[]),
        (array['provenance', 'provider']::text[]),
        (array['provenance', 'provider_mode']::text[]),
        (array['provenance', 'model_source']::text[]),
        (array['provenance', 'prompt_version']::text[]),
        (array['provenance', 'context_version']::text[]),
        (array['provenance', 'generated_at']::text[]),
        (array['provenance', 'provider_called']::text[]),
        (array['provenance', 'service_tier']::text[]),
        (array['provenance', 'service_tier_status']::text[]),
        (array['provenance', 'fast_mode']::text[]),
        (array['provenance', 'snapshot_row_count']::text[]),
        (array['provenance', 'snapshot_bytes']::text[])
    ) as null_case(json_path)
    cross join coach_v3_response response_fixture
    cross join coach_v3_evidence evidence_fixture
    where private.coach_response_is_valid_v2(
      jsonb_set(
        response_fixture.value,
        null_case.json_path,
        'null'::jsonb,
        false
      ),
      'b3000000-0000-4000-8000-000000000201',
      evidence_fixture.value
    )
  ),
  0,
  'JSON null fails closed for every required scalar response field'
);

select throws_ok(
  $$
    select public.complete_coach_request_v2(
      'b3000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000201',
      'How did focus change?',
      jsonb_set(
        (select value from coach_v3_response),
        '{provenance,service_tier}',
        'null'::jsonb
      ),
      (select value from coach_v3_evidence),
      (select value from coach_v3_trace),
      2,
      'not_applicable',
      (select value from coach_v3_usage),
      '2026-07-29T10:01:00Z'
    )
  $$,
  '22023',
  'Coach V2 completion is invalid',
  'completion rejects a JSON-null service tier before persistence'
);

select ok(
  (
    select state = 'pending'
      and evidence is null
      and agent_trace is null
      and tool_call_count is null
      and service_tier is null
    from public.coach_requests
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'a rejected completion leaves no partial backend-owned fields'
);

create temporary table coach_v3_completion on commit drop as
select public.complete_coach_request_v2(
  'b3000000-0000-4000-8000-000000000001',
  'b3000000-0000-4000-8000-000000000201',
  'How did focus change?',
  (select value from coach_v3_current_response),
  (select value from coach_v3_evidence),
  (select value from coach_v3_trace),
  2,
  'not_applicable',
  (select value from coach_v3_usage),
  '2026-07-29T10:01:00Z'
) as value;

select is(
  (select value ->> 'state' from coach_v3_completion),
  'completed',
  'a valid response-v2 atomically completes the V3 request'
);

select ok(
  (
    select state = 'completed'
      and response is not distinct from
        (select value from coach_v3_current_response)
      and used_context is not distinct from
        (select value from coach_v3_evidence)
      and evidence is not distinct from
        (select value from coach_v3_evidence)
      and agent_trace is not distinct from
        (select value from coach_v3_trace)
      and tool_call_count = 2
      and service_tier = 'not_applicable'
      and completed_at = '2026-07-29T10:01:00Z'::timestamptz
      and lease_expires_at is null
    from public.coach_requests
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'completion persists the exact response, evidence, trace, count, and service tier'
);

select ok(
  (
    select count(*) = 1
      and bool_and(outcome = 'completed')
      and bool_and(provider = 'fake')
      and bool_and(provider_mode = 'deterministic_test_only')
      and bool_and(error_code is null)
      and bool_and(
        counters is not distinct from (select value from coach_v3_usage)
      )
    from public.coach_usage_events
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'completion appends one exact usage-ledger row'
);

select is(
  (
    select string_agg(role || ':' || content, '|' order by created_at, role)
    from public.coach_messages
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'user:How did focus change?|assistant:Across seven recorded sessions, completed focus time became steadier.',
  'completion persists the exact user and assistant message pair'
);

select is(
  (
    select public.complete_coach_request_v2(
      'b3000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000201',
      'How did focus change?',
      (select value from coach_v3_current_response),
      (select value from coach_v3_evidence),
      (select value from coach_v3_trace),
      2,
      'not_applicable',
      (select value from coach_v3_usage),
      '2026-07-29T10:01:00Z'
    ) ->> 'state'
  ),
  'completed',
  'an exact completion replay returns the stored terminal result'
);

select is(
  (
    select concat_ws(
      '|',
      (
        select count(*)::text
        from public.coach_messages
        where request_id = 'b3000000-0000-4000-8000-000000000201'
      ),
      (
        select count(*)::text
        from public.coach_usage_events
        where request_id = 'b3000000-0000-4000-8000-000000000201'
      )
    )
  ),
  '2|1',
  'completion replay does not duplicate messages or usage'
);

select throws_ok(
  $$
    select public.complete_coach_request_v2(
      'b3000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000201',
      'How did focus change?',
      jsonb_set(
        (select value from coach_v3_current_response),
        '{evidence,0,record_count}',
        '6'::jsonb
      ),
      jsonb_set(
        (select value from coach_v3_evidence),
        '{0,record_count}',
        '6'::jsonb
      ),
      (select value from coach_v3_trace),
      2,
      'not_applicable',
      (select value from coach_v3_usage),
      '2026-07-29T10:01:00Z'
    )
  $$,
  'PT409',
  'Coach V2 completion replay differs',
  'completion replay cannot replace persisted evidence'
);

select throws_ok(
  $$
    select public.complete_coach_request_v2(
      'b3000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000201',
      'How did focus change again?',
      (select value from coach_v3_current_response),
      (select value from coach_v3_evidence),
      (select value from coach_v3_trace),
      2,
      'not_applicable',
      (select value from coach_v3_usage),
      '2026-07-29T10:01:00Z'
    )
  $$,
  'PT409',
  'Coach completion does not match its claim',
  'completion replay remains bound to the original user message'
);

select is(
  (
    select public.delete_coach_history_v1(
      'b3000000-0000-4000-8000-000000000001',
      '2026-07-29T10:02:00Z'
    ) ->> 'state'
  ),
  'deleted',
  'history deletion tombstones the completed V3 turn'
);

select ok(
  (
    select state = 'deleted'
      and message_fingerprint is null
      and response is null
      and used_context = '[]'::jsonb
      and evidence is null
      and agent_trace is null
      and tool_call_count is null
      and service_tier is null
      and deleted_at = '2026-07-29T10:02:00Z'::timestamptz
    from public.coach_requests
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'history deletion clears content and agent detail while retaining the request tombstone'
);

select is(
  (
    select count(*)::int
    from public.coach_messages
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  0,
  'history deletion removes the stored conversation pair'
);

select ok(
  (
    select count(*) = 1
      and bool_and(outcome = 'completed')
      and bool_and(
        counters is not distinct from (select value from coach_v3_usage)
      )
    from public.coach_usage_events
    where request_id = 'b3000000-0000-4000-8000-000000000201'
  ),
  'history deletion retains immutable usage and daily-budget truth'
);

select is(
  (
    select concat_ws(
      '|',
      result ->> 'state',
      result #>> '{error,code}',
      result ->> 'remaining_requests'
    )
    from (
      select public.claim_coach_request_v8(
        'b3000000-0000-4000-8000-000000000001',
        'coach-request-v3',
        'b3000000-0000-4000-8000-000000000201',
        repeat('0', 64),
        '2026-07-30',
        'fake',
        'deterministic_test_only',
        null,
        'not_applicable',
        '2026-07-29T10:03:00Z',
        '2026-07-29T10:05:00Z',
        20,
        true
      ) as result
    ) replay
  ),
  'deleted|history_deleted|19',
  'a deleted request id remains terminal and still consumes its original local-day budget'
);

create temporary table coach_v3_failure_cases (
  request_id uuid primary key,
  error_code text not null,
  claimed_at timestamptz not null,
  failed_at timestamptz not null,
  provider_called boolean not null,
  retryable boolean not null
) on commit drop;

insert into coach_v3_failure_cases (
  request_id,
  error_code,
  claimed_at,
  failed_at,
  provider_called,
  retryable
) values
  (
    'b3000000-0000-4000-8000-000000000301',
    'provider_timeout',
    '2026-07-29T10:04:00Z',
    '2026-07-29T10:05:00Z',
    true,
    true
  ),
  (
    'b3000000-0000-4000-8000-000000000302',
    'snapshot_too_large',
    '2026-07-29T10:07:00Z',
    '2026-07-29T10:08:00Z',
    false,
    false
  ),
  (
    'b3000000-0000-4000-8000-000000000303',
    'tool_limit',
    '2026-07-29T10:10:00Z',
    '2026-07-29T10:11:00Z',
    true,
    false
  ),
  (
    'b3000000-0000-4000-8000-000000000304',
    'fast_mode_unavailable',
    '2026-07-29T10:13:00Z',
    '2026-07-29T10:14:00Z',
    true,
    false
  );

select lives_ok(
  $test$
    do $body$
    declare
      failure_case record;
      result jsonb;
    begin
      for failure_case in
        select *
        from coach_v3_failure_cases
        order by claimed_at
      loop
        select public.claim_coach_request_v8(
          'b3000000-0000-4000-8000-000000000001',
          'coach-request-v3',
          failure_case.request_id,
          encode(
            extensions.digest(
              convert_to(failure_case.error_code, 'UTF8'),
              'sha256'
            ),
            'hex'
          ),
          '2026-07-29',
          'local_codex_oauth',
          'local_development_only',
          'gpt-5.5',
          'explicit',
          failure_case.claimed_at,
          failure_case.claimed_at + interval '2 minutes',
          20,
          true
        ) into result;

        if result ->> 'state' is distinct from 'pending' then
          raise exception 'Expected a pending claim for %', failure_case.error_code;
        end if;

        select public.fail_coach_request_v1(
          'b3000000-0000-4000-8000-000000000001',
          failure_case.request_id,
          jsonb_build_object(
            'code', failure_case.error_code,
            'message', 'Persisted ' || failure_case.error_code || ' failure.',
            'retryable', failure_case.retryable
          ),
          jsonb_build_object(
            'provider_called', failure_case.provider_called,
            'prompt_bytes', 0,
            'context_bytes', 0,
            'reply_codepoints', 0
          ),
          failure_case.failed_at
        ) into result;

        if result ->> 'state' is distinct from 'failed' then
          raise exception 'Expected a failed result for %', failure_case.error_code;
        end if;
      end loop;
    end;
    $body$
  $test$,
  'every new V3 failure code persists through the real claim and failure RPC path'
);

select is(
  (
    select count(*)::int
    from public.coach_requests requests
    join coach_v3_failure_cases cases using (request_id)
    where requests.state = 'failed'
      and requests.error ->> 'code' = cases.error_code
  ),
  4,
  'all four new V3 failure codes are stored on terminal requests'
);

select ok(
  (
    select count(*) = 4
      and bool_and(usage.outcome = 'failed')
      and bool_and(usage.error_code = cases.error_code)
      and bool_and(
        usage.counters = jsonb_build_object(
          'provider_called', cases.provider_called,
          'prompt_bytes', 0,
          'context_bytes', 0,
          'reply_codepoints', 0
        )
      )
    from public.coach_usage_events usage
    join coach_v3_failure_cases cases using (request_id)
  ),
  'all four new V3 failure codes retain exact immutable usage-ledger truth'
);

select lives_ok(
  $test$
    do $body$
    declare
      failure_case record;
      result jsonb;
    begin
      for failure_case in
        select *
        from coach_v3_failure_cases
        order by failed_at
      loop
        select public.fail_coach_request_v1(
          'b3000000-0000-4000-8000-000000000001',
          failure_case.request_id,
          jsonb_build_object(
            'code', failure_case.error_code,
            'message', 'Persisted ' || failure_case.error_code || ' failure.',
            'retryable', failure_case.retryable
          ),
          jsonb_build_object(
            'provider_called', failure_case.provider_called,
            'prompt_bytes', 0,
            'context_bytes', 0,
            'reply_codepoints', 0
          ),
          failure_case.failed_at + interval '1 minute'
        ) into result;

        if result ->> 'state' is distinct from 'failed' then
          raise exception 'Expected a failed replay for %', failure_case.error_code;
        end if;
      end loop;
    end;
    $body$
  $test$,
  'every new V3 failure code supports exact terminal replay without duplicate usage'
);

select throws_ok(
  $$
    update public.coach_usage_events
    set error_code = null
    where request_id = 'b3000000-0000-4000-8000-000000000301'
  $$,
  '23514',
  null,
  'a failed usage event cannot bypass its error-code constraint with SQL NULL'
);

select ok(
  (
    select count(*) = 4
      and bool_and(usage.error_code is not null)
    from public.coach_usage_events usage
    join coach_v3_failure_cases cases using (request_id)
  ),
  'the rejected NULL update leaves every V3 failure code intact'
);

select * from finish();
rollback;
