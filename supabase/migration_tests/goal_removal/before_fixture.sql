begin;

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
  'e2000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'goal-removal-harness@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')),
  '2026-08-04T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Goal removal harness"}'::jsonb,
  '2026-08-04T08:00:00Z',
  '2026-08-04T08:00:00Z'
);

insert into public.intake_responses (
  id, user_id, version, responses, completed_at, metadata, created_at,
  request_id, base_revision, revision, state, updated_at
) values (
  'e2000000-0000-4000-8000-000000000101',
  'e2000000-0000-4000-8000-000000000001',
  'intake-v1',
  '{
    "weekday_shape":"flexible",
    "legacy_ref":{"field":"metadata.goal_id","id":"legacy-goal"},
    "note":"A goal mentioned in ordinary prose must remain."
  }'::jsonb,
  '2026-08-04T08:10:00Z',
  '{"sources":["goals","tasks"],"ordinary":"goals can be prose"}'::jsonb,
  '2026-08-04T08:10:00Z',
  'e2000000-0000-4000-8000-000000000102',
  0,
  1,
  'applied',
  '2026-08-04T08:10:00Z'
);

insert into public.tasks (
  id, user_id, title, status, priority, source, metadata, created_at, updated_at
) values (
  'e2000000-0000-4000-8000-000000000201',
  'e2000000-0000-4000-8000-000000000001',
  'Writer-lock fixture',
  'todo',
  'medium',
  'manual',
  '{
    "legacy_ref":{"field":"metadata.goal_id","id":"legacy-goal"},
    "note":"Keep this goal word as ordinary text."
  }'::jsonb,
  '2026-08-04T08:20:00Z',
  '2026-08-04T08:20:00Z'
);

insert into public.user_state_snapshots (
  id, user_id, scope, period_key, summary, signals, source,
  source_observed_at, generated_at, metadata
) values
  (
    'e2000000-0000-4000-8000-000000000301',
    'e2000000-0000-4000-8000-000000000001',
    'onboarding',
    'setup:intake-v1',
    '{
      "legacy_ref":{"path":"summary.goals"},
      "note":"The word goal in prose remains."
    }'::jsonb,
    '{"sources":["goals","tasks"]}'::jsonb,
    'backend',
    '2026-08-04T08:30:00Z',
    '2026-08-04T08:30:00Z',
    '{"field_ref":{"field":"metadata.goal_id"}}'::jsonb
  ),
  (
    'e2000000-0000-4000-8000-000000000311',
    'e2000000-0000-4000-8000-000000000001',
    'weekly',
    '2026-W25',
    '{"daily_state":{"mode":"steady"}}'::jsonb,
    '{}'::jsonb,
    'backend',
    '2026-06-21T18:00:00Z',
    '2026-06-21T18:00:00Z',
    '{"legacy_ref":{"field":"metadata.goal_id"}}'::jsonb
  ),
  (
    'e2000000-0000-4000-8000-000000000312',
    'e2000000-0000-4000-8000-000000000001',
    'weekly',
    '2026-W26',
    '{"daily_state":{"mode":"steady"}}'::jsonb,
    '{}'::jsonb,
    'backend',
    '2026-06-28T18:00:00Z',
    '2026-06-28T18:00:00Z',
    '{}'::jsonb
  ),
  (
    'e2000000-0000-4000-8000-000000000313',
    'e2000000-0000-4000-8000-000000000001',
    'weekly',
    '2026-W27',
    '{"daily_state":{"mode":"steady"}}'::jsonb,
    '{}'::jsonb,
    'backend',
    '2026-07-05T18:00:00Z',
    '2026-07-05T18:00:00Z',
    '{}'::jsonb
  );

insert into public.recommendations (
  id, user_id, title, reason, action_label, category, confidence, status,
  priority, metadata, generated_at, updated_at
) values (
  'e2000000-0000-4000-8000-000000000401',
  'e2000000-0000-4000-8000-000000000001',
  'Legacy Setup recommendation',
  'Derived from the retired Setup personalization snapshot.',
  'Review',
  'planning',
  0.8,
  'new',
  'medium',
  '{
    "evidence_refs":[{
      "table":"user_state_snapshots",
      "id":"e2000000-0000-4000-8000-000000000301",
      "field":"summary"
    }],
    "ordinary":"No structural Goal reference here."
  }'::jsonb,
  '2026-06-23T08:00:00Z',
  '2026-06-23T08:00:00Z'
);

insert into public.daily_briefings (
  id, user_id, briefing_date, mode, summary, primary_action,
  support_actions, recommendation_ids, evidence_refs, provenance,
  data_quality, metadata, generated_at, created_at, updated_at
) values (
  'e2000000-0000-4000-8000-000000000411',
  'e2000000-0000-4000-8000-000000000001',
  '2026-06-23',
  'steady',
  'A briefing indirectly derived from retired Setup personalization.',
  '{
    "target":{"kind":"planning"},
    "title":"Plan the day",
    "reason":"Use the recommendation.",
    "recommendation_id":"e2000000-0000-4000-8000-000000000401",
    "evidence_refs":[]
  }'::jsonb,
  '[]'::jsonb,
  array['e2000000-0000-4000-8000-000000000401'::uuid],
  '[]'::jsonb,
  '{
    "engine":"deterministic",
    "contract_version":"daily-briefing-v1",
    "source_snapshot_id":"e2000000-0000-4000-8000-000000000312"
  }'::jsonb,
  'current',
  '{}'::jsonb,
  '2026-06-23T08:10:00Z',
  '2026-06-23T08:10:00Z',
  '2026-06-23T08:10:00Z'
);

insert into public.decision_feedback (
  id, user_id, request_id, briefing_id, recommendation_id, action_id,
  action_kind, feedback_type, context_mode, estimated_minutes, rule_key,
  metadata, created_at
) values (
  'e2000000-0000-4000-8000-000000000421',
  'e2000000-0000-4000-8000-000000000001',
  'e2000000-0000-4000-8000-000000000422',
  'e2000000-0000-4000-8000-000000000411',
  'e2000000-0000-4000-8000-000000000401',
  'primary',
  'planning',
  'done',
  'steady',
  20,
  'legacy_setup_recommendation',
  '{}'::jsonb,
  '2026-06-23T09:00:00Z'
);

insert into public.weekly_reviews (
  id, user_id, period_key, week_start, week_end, timezone, data_quality,
  narrative, facts, proposals, evidence_refs, provenance,
  source_fingerprint, source_observed_at, generated_at, created_at, updated_at
) values
  (
    'e2000000-0000-4000-8000-000000000501',
    'e2000000-0000-4000-8000-000000000001',
    '2026-W26',
    '2026-06-22',
    '2026-06-28',
    'Europe/Berlin',
    'sufficient',
    'Indirect feedback review.',
    '{"tasks":{"completed":1,"carried":0},"habits":{"completed":1,"skipped":0},"recovery":{"recovery_days":0}}'::jsonb,
    '[]'::jsonb,
    '[{
      "table":"decision_feedback",
      "id":"e2000000-0000-4000-8000-000000000421",
      "field":"feedback_type"
    }]'::jsonb,
    '{
      "engine":"deterministic",
      "contract_version":"weekly-review-v1",
      "source_snapshot_id":"e2000000-0000-4000-8000-000000000312",
      "source_snapshot_generated_at":"2026-06-28T18:00:00Z",
      "evidence_window":{"starts_on":"2026-06-22","ends_on":"2026-06-28","days":7},
      "source_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "baseline":"none",
      "limitations":[],
      "llm_used":false
    }'::jsonb,
    repeat('a', 64),
    '2026-06-28T18:00:00Z',
    '2026-06-28T18:00:00Z',
    '2026-06-28T18:01:00Z',
    '2026-06-28T18:02:00Z'
  ),
  (
    'e2000000-0000-4000-8000-000000000511',
    'e2000000-0000-4000-8000-000000000001',
    '2026-W25',
    '2026-06-15',
    '2026-06-21',
    'Europe/Berlin',
    'partial',
    'Review whose source snapshot is removed by the follow-up.',
    '{"tasks":{"completed":0,"carried":1},"habits":{"completed":0,"skipped":0},"recovery":{"recovery_days":0}}'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb,
    '{
      "engine":"deterministic",
      "contract_version":"weekly-review-v1",
      "source_snapshot_id":"e2000000-0000-4000-8000-000000000311",
      "source_snapshot_generated_at":"2026-06-21T18:00:00Z",
      "evidence_window":{"starts_on":"2026-06-15","ends_on":"2026-06-21","days":7},
      "source_fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "baseline":"none",
      "limitations":[],
      "llm_used":false
    }'::jsonb,
    repeat('b', 64),
    '2026-06-21T18:00:00Z',
    '2026-06-21T18:00:00Z',
    '2026-06-21T18:01:00Z',
    '2026-06-21T18:02:00Z'
  ),
  (
    'e2000000-0000-4000-8000-000000000521',
    'e2000000-0000-4000-8000-000000000001',
    '2026-W28',
    '2026-07-06',
    '2026-07-12',
    'Europe/Berlin',
    'partial',
    'Review with an already missing source snapshot.',
    '{"tasks":{"completed":0,"carried":1},"habits":{"completed":0,"skipped":0},"recovery":{"recovery_days":0}}'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb,
    '{
      "engine":"deterministic",
      "contract_version":"weekly-review-v1",
      "source_snapshot_id":"e2000000-0000-4000-8000-000000000399",
      "source_snapshot_generated_at":"2026-07-12T18:00:00Z",
      "evidence_window":{"starts_on":"2026-07-06","ends_on":"2026-07-12","days":7},
      "source_fingerprint":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "baseline":"none",
      "limitations":[],
      "llm_used":false
    }'::jsonb,
    repeat('c', 64),
    '2026-07-12T18:00:00Z',
    '2026-07-12T18:00:00Z',
    '2026-07-12T18:01:00Z',
    '2026-07-12T18:02:00Z'
  ),
  (
    'e2000000-0000-4000-8000-000000000531',
    'e2000000-0000-4000-8000-000000000001',
    '2026-W27',
    '2026-06-29',
    '2026-07-05',
    'Europe/Berlin',
    'sufficient',
    'Clean review with historical proposal transport.',
    '{"tasks":{"completed":2,"carried":0},"habits":{"completed":3,"skipped":1},"recovery":{"recovery_days":1}}'::jsonb,
    '[{
      "id":"weekly-review:2026-W27:habit:legacy:shrink",
      "operation":"shrink",
      "target_kind":"habit",
      "target_id":"e2000000-0000-4000-8000-000000000901",
      "target_title":"Historical habit",
      "ownership":"manual",
      "application_mode":"direct_habit",
      "reason":"Historical transport only.",
      "evidence_refs":[],
      "change":{"before":{"weekly_target":4},"after":{"weekly_target":3}}
    }]'::jsonb,
    '[]'::jsonb,
    '{
      "engine":"deterministic",
      "contract_version":"weekly-review-v1",
      "source_snapshot_id":"e2000000-0000-4000-8000-000000000313",
      "source_snapshot_generated_at":"2026-07-05T18:00:00Z",
      "evidence_window":{"starts_on":"2026-06-29","ends_on":"2026-07-05","days":7},
      "source_fingerprint":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "baseline":"none",
      "limitations":[],
      "llm_used":false
    }'::jsonb,
    repeat('d', 64),
    '2026-07-05T18:00:00Z',
    '2026-07-05T18:00:00Z',
    '2026-07-05T18:01:00Z',
    '2026-07-05T18:02:00Z'
  );

insert into public.notifications (
  id, user_id, title, message, type, priority, metadata, created_at, updated_at
) values
  (
    'e2000000-0000-4000-8000-000000000601',
    'e2000000-0000-4000-8000-000000000001',
    'Indirect weekly review',
    'This notification follows the review dependency.',
    'summary',
    'low',
    '{
      "source_kind":"weekly_review",
      "source_id":"e2000000-0000-4000-8000-000000000501"
    }'::jsonb,
    '2026-06-29T07:00:00Z',
    '2026-06-29T07:00:00Z'
  ),
  (
    'e2000000-0000-4000-8000-000000000602',
    'e2000000-0000-4000-8000-000000000001',
    'Transitive event notification',
    'This notification follows a transitive evidence chain.',
    'coaching',
    'medium',
    '{
      "source_kind":"behavioral_event",
      "source_id":"e2000000-0000-4000-8000-000000000721"
    }'::jsonb,
    '2026-06-29T07:05:00Z',
    '2026-06-29T07:05:00Z'
  );

insert into public.notification_action_requests (
  request_id, user_id, notification_id, contract_version, command,
  expected_updated_at, result_is_read, result_read_at,
  result_dismissed_at, result_updated_at, created_at
) values (
  'e2000000-0000-4000-8000-000000000611',
  'e2000000-0000-4000-8000-000000000001',
  'e2000000-0000-4000-8000-000000000601',
  'notification-lifecycle-v1',
  'mark_read',
  '2026-06-29T07:00:00Z',
  true,
  '2026-06-29T07:01:00Z',
  null,
  '2026-06-29T07:01:00Z',
  '2026-06-29T07:01:00Z'
);

insert into public.memory_entries (
  id, user_id, type, title, content, strength, evidence, metadata,
  last_seen_at, created_at, updated_at
) values (
  'e2000000-0000-4000-8000-000000000701',
  'e2000000-0000-4000-8000-000000000001',
  'pattern',
  'Legacy structured memory',
  'Ordinary prose is not used to classify this memory.',
  0.7,
  '[{"field":"metadata.goal_id"}]'::jsonb,
  '{}'::jsonb,
  '2026-06-29T08:00:00Z',
  '2026-06-29T08:00:00Z',
  '2026-06-29T08:00:00Z'
);

insert into public.coach_memory_selections (
  user_id, memory_id, selection_version, selected_at
) values (
  'e2000000-0000-4000-8000-000000000001',
  'e2000000-0000-4000-8000-000000000701',
  'coach-memory-selection-v1',
  '2026-06-29T08:01:00Z'
);

insert into public.ai_insights (
  id, user_id, title, description, category, priority, source, metadata,
  created_at
) values (
  'e2000000-0000-4000-8000-000000000711',
  'e2000000-0000-4000-8000-000000000001',
  'Transitive memory insight',
  'Derived from a memory that will be retired.',
  'pattern',
  'medium',
  'ai-engine',
  '{
    "evidence_refs":[{
      "table":"memory_entries",
      "id":"e2000000-0000-4000-8000-000000000701",
      "field":"evidence"
    }]
  }'::jsonb,
  '2026-06-29T08:02:00Z'
);

insert into public.behavioral_events (
  id, user_id, event_type, occurred_at, source, metadata, created_at
) values (
  'e2000000-0000-4000-8000-000000000721',
  'e2000000-0000-4000-8000-000000000001',
  'insight_observed',
  '2026-06-29T08:03:00Z',
  'app',
  '{
    "evidence_refs":[{
      "table":"ai_insights",
      "id":"e2000000-0000-4000-8000-000000000711",
      "field":"metadata"
    }]
  }'::jsonb,
  '2026-06-29T08:03:00Z'
);

do $fixture$
declare
  request_value uuid;
  message_value text;
  reply_value text;
  evidence_value jsonb;
  trace_value jsonb := '{
    "tool_call_count":1,
    "steps":[{
      "sequence":1,
      "tool":"query_data",
      "status":"completed",
      "summary":"Read one structured source.",
      "row_count":1,
      "duration_ms":2
    }],
    "limitations":[]
  }'::jsonb;
  response_value jsonb;
  usage_value jsonb;
begin
  request_value := 'e2000000-0000-4000-8000-000000000801';
  message_value := 'Summarize my recorded context.';
  reply_value := 'The recorded context contains one full snapshot observation.';
  evidence_value := '[{
    "source":"personal_snapshot",
    "record_count":1,
    "period_start":null,
    "period_end":null
  }]'::jsonb;
  perform public.claim_coach_request_v4(
    'e2000000-0000-4000-8000-000000000001',
    request_value,
    encode(extensions.digest(convert_to(message_value, 'UTF8'), 'sha256'), 'hex'),
    '2026-08-04',
    'fake',
    'deterministic_test_only',
    null,
    'not_applicable',
    '2026-08-04T10:00:00Z',
    '2026-08-04T10:02:00Z',
    20
  );
  response_value := jsonb_build_object(
    'contract_version', 'coach-response-v2',
    'request_id', request_value::text,
    'reply', reply_value,
    'uncertainty', jsonb_build_object(
      'level', 'medium',
      'reason', 'Only one recorded observation is available.'
    ),
    'safety', jsonb_build_object('classification', 'normal'),
    'evidence', evidence_value,
    'agent_trace', trace_value,
    'provenance', jsonb_build_object(
      'source', 'model',
      'provider', 'fake',
      'provider_mode', 'deterministic_test_only',
      'model_requested', null,
      'model_reported', null,
      'model_source', 'not_applicable',
      'prompt_version', 'free-coach-agent-prompt-v2',
      'context_version', 'personal-snapshot-v1',
      'generated_at', '2026-08-04T10:01:00Z',
      'provider_called', true,
      'service_tier', 'not_applicable',
      'service_tier_status', 'not_applicable',
      'fast_mode', false,
      'snapshot_row_count', 1,
      'snapshot_bytes', 1024
    )
  );
  usage_value := jsonb_build_object(
    'provider_called', true,
    'prompt_bytes', 256,
    'context_bytes', 1024,
    'reply_codepoints', char_length(reply_value)
  );
  perform public.complete_coach_request_v2(
    'e2000000-0000-4000-8000-000000000001',
    request_value,
    message_value,
    response_value,
    evidence_value,
    trace_value,
    1,
    'not_applicable',
    usage_value,
    '2026-08-04T10:01:00Z'
  );

  request_value := 'e2000000-0000-4000-8000-000000000802';
  message_value := 'Summarize my recorded tasks.';
  reply_value := 'The task source contains one clean observation.';
  evidence_value := '[{
    "source":"tasks",
    "record_count":1,
    "period_start":null,
    "period_end":null
  }]'::jsonb;
  perform public.claim_coach_request_v4(
    'e2000000-0000-4000-8000-000000000001',
    request_value,
    encode(extensions.digest(convert_to(message_value, 'UTF8'), 'sha256'), 'hex'),
    '2026-08-04',
    'fake',
    'deterministic_test_only',
    null,
    'not_applicable',
    '2026-08-04T10:03:00Z',
    '2026-08-04T10:05:00Z',
    20
  );
  response_value := jsonb_build_object(
    'contract_version', 'coach-response-v2',
    'request_id', request_value::text,
    'reply', reply_value,
    'uncertainty', jsonb_build_object(
      'level', 'low',
      'reason', 'The task source is directly recorded.'
    ),
    'safety', jsonb_build_object('classification', 'normal'),
    'evidence', evidence_value,
    'agent_trace', trace_value,
    'provenance', jsonb_build_object(
      'source', 'model',
      'provider', 'fake',
      'provider_mode', 'deterministic_test_only',
      'model_requested', null,
      'model_reported', null,
      'model_source', 'not_applicable',
      'prompt_version', 'free-coach-agent-prompt-v2',
      'context_version', 'personal-snapshot-v1',
      'generated_at', '2026-08-04T10:04:00Z',
      'provider_called', true,
      'service_tier', 'not_applicable',
      'service_tier_status', 'not_applicable',
      'fast_mode', false,
      'snapshot_row_count', 1,
      'snapshot_bytes', 1024
    )
  );
  usage_value := jsonb_build_object(
    'provider_called', true,
    'prompt_bytes', 256,
    'context_bytes', 1024,
    'reply_codepoints', char_length(reply_value)
  );
  perform public.complete_coach_request_v2(
    'e2000000-0000-4000-8000-000000000001',
    request_value,
    message_value,
    response_value,
    evidence_value,
    trace_value,
    1,
    'not_applicable',
    usage_value,
    '2026-08-04T10:04:00Z'
  );
end;
$fixture$;

insert into public.coach_messages (
  id, user_id, role, content, metadata, created_at
) values
  (
    'e2000000-0000-4000-8000-000000000811',
    'e2000000-0000-4000-8000-000000000001',
    'system',
    'Legacy structured metadata.',
    '{"field":"metadata.goal_id"}'::jsonb,
    '2026-08-04T10:05:00Z'
  ),
  (
    'e2000000-0000-4000-8000-000000000812',
    'e2000000-0000-4000-8000-000000000001',
    'user',
    'This ordinary goal sentence must remain in legacy history.',
    '{}'::jsonb,
    '2026-08-04T10:06:00Z'
  );

commit;
