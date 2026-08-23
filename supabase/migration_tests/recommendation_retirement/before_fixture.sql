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
) values
  (
    'f7000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'recommendation-retirement-harness@example.test',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    '2026-08-13T08:00:00Z',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Recommendation retirement harness"}'::jsonb,
    '2026-08-13T08:00:00Z',
    '2026-08-13T08:00:00Z'
  ),
  (
    'f7000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'recommendation-retirement-second-owner@example.test',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    '2026-08-13T08:00:00Z',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Recommendation retirement second owner"}'::jsonb,
    '2026-08-13T08:00:00Z',
    '2026-08-13T08:00:00Z'
  );

update public.profiles
set timezone = 'Europe/Berlin',
    onboarding_completed_at = '2026-08-13T08:01:00Z'
where id = 'f7000000-0000-4000-8000-000000000001';

update public.profiles
set timezone = 'America/New_York',
    onboarding_completed_at = '2026-08-13T08:01:00Z'
where id = 'f7000000-0000-4000-8000-000000000002';

update public.notification_preferences
set focus_prompts_enabled = false,
    recovery_prompts_enabled = true,
    weekly_summary_enabled = false,
    quiet_hours_start = null,
    quiet_hours_end = null,
    in_app_delivery_enabled = true,
    in_app_delivery_consent_version = 'in-app-notification-consent-v1',
    in_app_delivery_consented_at = '2026-08-13T08:02:00Z',
    in_app_delivery_disabled_at = null,
    delivery_settings_request_id = null,
    daily_notification_limit = 2,
    updated_at = greatest(updated_at, '2026-08-13T08:02:00Z')
where user_id = 'f7000000-0000-4000-8000-000000000001';

insert into public.intake_responses (
  id, user_id, version, responses, completed_at, metadata, created_at,
  request_id, base_revision, revision, state, updated_at
) values (
  'f7000000-0000-4000-8000-000000000101',
  'f7000000-0000-4000-8000-000000000001',
  'intake-v1',
  '{
    "weekday_shape":"flexible",
    "recommendations":[{"id":"legacy"}],
    "note":"The word recommendation in prose must remain.",
    "user_feedback":{"rating":4}
  }'::jsonb,
  '2026-08-13T08:05:00Z',
  '{
    "sources":["recommendations","tasks"],
    "ordinary":"feedback in ordinary prose remains"
  }'::jsonb,
  '2026-08-13T08:05:00Z',
  'f7000000-0000-4000-8000-000000000102',
  0,
  1,
  'applied',
  '2026-08-13T08:05:00Z'
);

insert into public.tasks (
  id, user_id, title, status, priority, source, metadata, created_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000201',
  'f7000000-0000-4000-8000-000000000001',
  'Writer-lock fixture',
  'todo',
  'medium',
  'manual',
  '{
    "recommendation_id":"f7000000-0000-4000-8000-000000000401",
    "note":"Keep this recommendation sentence.",
    "user_feedback":{"rating":5}
  }'::jsonb,
  '2026-08-13T08:10:00Z',
  '2026-08-13T08:10:00Z'
);

insert into public.user_state_snapshots (
  id, user_id, scope, period_key, summary, signals, source,
  source_observed_at, generated_at, metadata
) values
  (
    'f7000000-0000-4000-8000-000000000301',
    'f7000000-0000-4000-8000-000000000001',
    'daily',
    '2026-08-13',
    '{
      "daily_state":{"mode":"steady"},
      "recommendation_ids":["legacy"],
      "note":"recommendation prose remains"
    }'::jsonb,
    '{"sources":["recommendations","tasks"]}'::jsonb,
    'backend',
    '2026-08-13T08:15:00Z',
    '2026-08-13T08:15:00Z',
    '{"feedback_ranking":{"score":1}}'::jsonb
  ),
  (
    'f7000000-0000-4000-8000-000000000302',
    'f7000000-0000-4000-8000-000000000001',
    'weekly',
    '2026-W32',
    '{"daily_state":{"mode":"steady"}}'::jsonb,
    '{}'::jsonb,
    'backend',
    '2026-08-09T18:00:00Z',
    '2026-08-09T18:00:00Z',
    '{}'::jsonb
  ),
  (
    'f7000000-0000-4000-8000-000000000303',
    'f7000000-0000-4000-8000-000000000002',
    'weekly',
    '2026-W32',
    '{"daily_state":{"mode":"steady"}}'::jsonb,
    '{}'::jsonb,
    'backend',
    '2026-08-09T18:00:00Z',
    '2026-08-09T18:00:00Z',
    '{}'::jsonb
  );

insert into public.recommendations (
  id, user_id, title, reason, action_label, category, confidence, status,
  priority, metadata, generated_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000401',
  'f7000000-0000-4000-8000-000000000001',
  'Retired generic recommendation',
  'Legacy deterministic rule.',
  'Open',
  'planning',
  0.8,
  'new',
  'medium',
  '{}'::jsonb,
  '2026-08-13T08:20:00Z',
  '2026-08-13T08:20:00Z'
);

insert into public.recommendations (
  id, user_id, title, reason, action_label, category, confidence, status,
  priority, metadata, generated_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000402',
  'f7000000-0000-4000-8000-000000000002',
  'Second owner retired recommendation',
  'Legacy deterministic rule.',
  'Open',
  'planning',
  0.7,
  'new',
  'low',
  '{}'::jsonb,
  '2026-08-13T08:20:00Z',
  '2026-08-13T08:20:00Z'
);

insert into public.daily_briefings (
  id, user_id, briefing_date, mode, summary, primary_action,
  support_actions, recommendation_ids, evidence_refs, provenance,
  data_quality, metadata, generated_at, created_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000411',
  'f7000000-0000-4000-8000-000000000001',
  '2026-08-13',
  'steady',
  'Legacy briefing content.',
  '{
    "target":{"kind":"planning"},
    "title":"Review the old feed",
    "reason":"Legacy source.",
    "recommendation_id":"f7000000-0000-4000-8000-000000000401",
    "evidence_refs":[]
  }'::jsonb,
  '[]'::jsonb,
  array['f7000000-0000-4000-8000-000000000401'::uuid],
  '[]'::jsonb,
  '{"engine":"deterministic","contract_version":"daily-briefing-v1"}'::jsonb,
  'current',
  '{
    "contract_version":"daily-briefing-v1",
    "ranking_version":"deterministic-briefing-ranker-v2"
  }'::jsonb,
  '2026-08-13T08:25:00Z',
  '2026-08-13T08:25:00Z',
  '2026-08-13T08:25:00Z'
);

insert into public.daily_briefings (
  id, user_id, briefing_date, mode, summary, primary_action,
  support_actions, recommendation_ids, evidence_refs, provenance,
  data_quality, metadata, generated_at, created_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000412',
  'f7000000-0000-4000-8000-000000000002',
  '2026-08-13',
  'steady',
  'Second owner legacy briefing.',
  '{
    "target":{"kind":"planning"},
    "title":"Review the old feed",
    "reason":"Legacy source.",
    "recommendation_id":"f7000000-0000-4000-8000-000000000402",
    "evidence_refs":[]
  }'::jsonb,
  '[]'::jsonb,
  array['f7000000-0000-4000-8000-000000000402'::uuid],
  '[]'::jsonb,
  '{"engine":"deterministic","contract_version":"daily-briefing-v1"}'::jsonb,
  'current',
  '{
    "contract_version":"daily-briefing-v1",
    "ranking_version":"deterministic-briefing-ranker-v2"
  }'::jsonb,
  '2026-08-13T08:25:00Z',
  '2026-08-13T08:25:00Z',
  '2026-08-13T08:25:00Z'
);

insert into public.decision_feedback (
  id, user_id, request_id, briefing_id, recommendation_id, action_id,
  action_kind, feedback_type, context_mode, estimated_minutes, rule_key,
  metadata, created_at
) values (
  'f7000000-0000-4000-8000-000000000421',
  'f7000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000422',
  'f7000000-0000-4000-8000-000000000411',
  'f7000000-0000-4000-8000-000000000401',
  'primary',
  'planning',
  'done',
  'steady',
  20,
  'legacy_rule',
  '{}'::jsonb,
  '2026-08-13T08:30:00Z'
);

insert into public.decision_feedback (
  id, user_id, request_id, briefing_id, recommendation_id, action_id,
  action_kind, feedback_type, context_mode, estimated_minutes, rule_key,
  metadata, created_at
) values (
  'f7000000-0000-4000-8000-000000000423',
  'f7000000-0000-4000-8000-000000000002',
  'f7000000-0000-4000-8000-000000000424',
  'f7000000-0000-4000-8000-000000000412',
  'f7000000-0000-4000-8000-000000000402',
  'primary',
  'planning',
  'done',
  'steady',
  20,
  'legacy_rule',
  '{}'::jsonb,
  '2026-08-13T08:30:00Z'
);

insert into public.weekly_reviews (
  id, user_id, period_key, week_start, week_end, timezone, data_quality,
  narrative, facts, proposals, evidence_refs, provenance,
  source_fingerprint, source_observed_at, generated_at, created_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000501',
  'f7000000-0000-4000-8000-000000000001',
  '2026-W32',
  '2026-08-03',
  '2026-08-09',
  'Europe/Berlin',
  'sufficient',
  'Legacy feedback-based review.',
  '{
    "tasks":{"completed":1,"carried":0},
    "habits":{"completed":1,"skipped":0},
    "focus":{"actual_minutes":30},
    "recovery":{"recovery_days":0},
    "feedback":{"done":1}
  }'::jsonb,
  '[]'::jsonb,
  '[{
    "table":"decision_feedback",
    "id":"f7000000-0000-4000-8000-000000000421",
    "field":"feedback_type"
  }]'::jsonb,
  '{
    "engine":"deterministic",
    "contract_version":"weekly-review-v2",
    "source_snapshot_id":"f7000000-0000-4000-8000-000000000303",
    "source_snapshot_generated_at":"2026-08-09T18:00:00Z",
    "evidence_window":{"starts_on":"2026-08-03","ends_on":"2026-08-09","days":7},
    "source_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "baseline":"none",
    "limitations":[],
    "llm_used":false
  }'::jsonb,
  repeat('a', 64),
  '2026-08-09T18:00:00Z',
  '2026-08-09T18:00:00Z',
  '2026-08-09T18:01:00Z',
  '2026-08-09T18:02:00Z'
);

insert into public.weekly_reviews (
  id, user_id, period_key, week_start, week_end, timezone, data_quality,
  narrative, facts, proposals, evidence_refs, provenance,
  source_fingerprint, source_observed_at, generated_at, created_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000502',
  'f7000000-0000-4000-8000-000000000002',
  '2026-W32',
  '2026-08-03',
  '2026-08-09',
  'America/New_York',
  'sufficient',
  'Second owner feedback-based review.',
  '{
    "tasks":{"completed":1,"carried":0},
    "habits":{"completed":1,"skipped":0},
    "focus":{"actual_minutes":30},
    "recovery":{"recovery_days":0},
    "feedback":{"done":1}
  }'::jsonb,
  '[]'::jsonb,
  '[{
    "table":"decision_feedback",
    "id":"f7000000-0000-4000-8000-000000000423",
    "field":"feedback_type"
  }]'::jsonb,
  '{
    "engine":"deterministic",
    "contract_version":"weekly-review-v2",
    "source_snapshot_id":"f7000000-0000-4000-8000-000000000302",
    "source_snapshot_generated_at":"2026-08-09T18:00:00Z",
    "evidence_window":{"starts_on":"2026-08-03","ends_on":"2026-08-09","days":7},
    "source_fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "baseline":"none",
    "limitations":[],
    "llm_used":false
  }'::jsonb,
  repeat('b', 64),
  '2026-08-09T18:00:00Z',
  '2026-08-09T18:00:00Z',
  '2026-08-09T18:01:00Z',
  '2026-08-09T18:02:00Z'
);

insert into public.notifications (
  id, user_id, title, message, type, priority, is_read, read_at, action_url,
  due_at, metadata, generation_key, generation_category, delivery_date,
  created_at, updated_at
) values
  (
    'f7000000-0000-4000-8000-000000000601',
    'f7000000-0000-4000-8000-000000000001',
    'Legacy briefing ready',
    'Open Today.',
    'reminder',
    'medium',
    false,
    null,
    '/dashboard',
    '2026-08-13T09:00:00Z',
    '{
      "contract_version":"notification-generation-v1",
      "origin":"deterministic_backend",
      "category":"focus_prompt",
      "reason_code":"current_daily_briefing",
      "delivery_date":"2026-08-13",
      "timezone":"Europe/Berlin",
      "source_kind":"daily_briefing",
      "source_id":"f7000000-0000-4000-8000-000000000411",
      "source_generated_at":"2026-08-13T08:25:00Z",
      "sensitive_copy_excluded":true,
      "llm_used":false
    }'::jsonb,
    'notification-generation-v1:focus_prompt:2026-08-13',
    'focus_prompt',
    '2026-08-13',
    '2026-08-13T09:00:00Z',
    '2026-08-13T09:00:00Z'
  ),
  (
    'f7000000-0000-4000-8000-000000000602',
    'f7000000-0000-4000-8000-000000000001',
    'Imported note',
    'This is not generated by the Briefing contract.',
    'coaching',
    'low',
    false,
    null,
    null,
    null,
    '{"source_kind":"daily_briefing","ordinary":"keep exactly"}'::jsonb,
    null,
    null,
    null,
    '2026-08-13T09:05:00Z',
    '2026-08-13T09:05:00Z'
  ),
  (
    'f7000000-0000-4000-8000-000000000603',
    'f7000000-0000-4000-8000-000000000001',
    'Daily state check-in',
    'Open Today when you are ready.',
    'coaching',
    'low',
    false,
    null,
    '/dashboard',
    '2026-08-13T10:00:00Z',
    '{
      "contract_version":"notification-generation-v1",
      "origin":"deterministic_backend",
      "category":"recovery_prompt",
      "reason_code":"current_daily_state",
      "delivery_date":"2026-08-13",
      "timezone":"Europe/Berlin",
      "source_kind":"daily_state",
      "source_id":"f7000000-0000-4000-8000-000000000301",
      "source_generated_at":"2026-08-13T08:15:00Z",
      "sensitive_copy_excluded":true,
      "llm_used":false
    }'::jsonb,
    'notification-generation-v1:recovery_prompt:2026-08-13',
    'recovery_prompt',
    '2026-08-13',
    '2026-08-13T10:00:00Z',
    '2026-08-13T10:00:00Z'
  );

insert into public.notification_action_requests (
  request_id, user_id, notification_id, contract_version, command,
  expected_updated_at, result_is_read, result_read_at,
  result_dismissed_at, result_updated_at, created_at
) values
  (
    'f7000000-0000-4000-8000-000000000611',
    'f7000000-0000-4000-8000-000000000001',
    'f7000000-0000-4000-8000-000000000601',
    'notification-lifecycle-v1',
    'mark_read',
    '2026-08-13T09:00:00Z',
    true,
    '2026-08-13T09:01:00Z',
    null,
    '2026-08-13T09:01:00Z',
    '2026-08-13T09:01:00Z'
  ),
  (
    'f7000000-0000-4000-8000-000000000612',
    'f7000000-0000-4000-8000-000000000001',
    'f7000000-0000-4000-8000-000000000603',
    'notification-lifecycle-v1',
    'mark_read',
    '2026-08-13T10:00:00Z',
    true,
    '2026-08-13T10:01:00Z',
    null,
    '2026-08-13T10:01:00Z',
    '2026-08-13T10:01:00Z'
  );

insert into public.memory_entries (
  id, user_id, type, title, content, strength, evidence, metadata,
  last_seen_at, created_at, updated_at
) values (
  'f7000000-0000-4000-8000-000000000701',
  'f7000000-0000-4000-8000-000000000001',
  'recommendation',
  'Retained memory advice',
  'This normal memory content remains byte-for-byte.',
  0.7,
  '[{"source":"tasks","id":"task-1"}]'::jsonb,
  '{"ordinary":"recommendation prose","user_feedback":{"rating":5}}'::jsonb,
  '2026-08-13T09:10:00Z',
  '2026-08-13T09:10:00Z',
  '2026-08-13T09:10:00Z'
);

insert into public.coach_memory_selections (
  user_id, memory_id, selection_version, selected_at
) values (
  'f7000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000701',
  'coach-memory-selection-v1',
  '2026-08-13T09:11:00Z'
);

insert into public.ai_insights (
  id, user_id, title, description, category, priority, recommendation,
  confidence, source, metadata, created_at
) values
  (
    'f7000000-0000-4000-8000-000000000711',
    'f7000000-0000-4000-8000-000000000001',
    'Retained insight',
    'A normal observation.',
    'sleep',
    'medium',
    'Keep a stable wind-down window.',
    0.8,
    'ai-engine',
    '{"ordinary":"feedback prose","user_feedback":{"rating":4}}'::jsonb,
    '2026-08-13T09:12:00Z'
  ),
  (
    'f7000000-0000-4000-8000-000000000712',
    'f7000000-0000-4000-8000-000000000001',
    'Retired insight source',
    'Derived from the retired feed.',
    'recommendation',
    'medium',
    'This row is derived history.',
    0.7,
    'recommendations',
    '{}'::jsonb,
    '2026-08-13T09:13:00Z'
  );

insert into public.behavioral_events (
  id, user_id, event_type, occurred_at, source, metadata, created_at
) values
  (
    'f7000000-0000-4000-8000-000000000721',
    'f7000000-0000-4000-8000-000000000001',
    'task_observed',
    '2026-08-13T09:14:00Z',
    'app',
    '{
      "recommendation_id":"f7000000-0000-4000-8000-000000000401",
      "ordinary":"recommendation prose remains"
    }'::jsonb,
    '2026-08-13T09:14:00Z'
  ),
  (
    'f7000000-0000-4000-8000-000000000722',
    'f7000000-0000-4000-8000-000000000001',
    'recommendation',
    '2026-08-13T09:15:00Z',
    'recommendations',
    '{}'::jsonb,
    '2026-08-13T09:15:00Z'
  );

insert into public.skillset_profiles (
  id, user_id, overall_score, archetype, scores, generated_at
) values (
  'f7000000-0000-4000-8000-000000000731',
  'f7000000-0000-4000-8000-000000000001',
  72,
  'Steady learner',
  '[{"skill":"planning","score":72}]'::jsonb,
  '2026-08-13T09:16:00Z'
);

select public.claim_coach_request_v5(
  'f7000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000801',
  encode(
    extensions.digest(convert_to('Retire this generated turn.', 'UTF8'), 'sha256'),
    'hex'
  ),
  '2026-08-13',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-08-13T09:20:00Z',
  '2026-08-13T09:22:00Z',
  20
);

select public.fail_coach_request_v1(
  'f7000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000801',
  '{
    "code":"interrupted",
    "message":"The Coach request expired before completion.",
    "retryable":true
  }'::jsonb,
  '{
    "provider_called":false,
    "prompt_bytes":0,
    "context_bytes":0,
    "reply_codepoints":0
  }'::jsonb,
  '2026-08-13T09:21:00Z'
);

select public.claim_coach_request_v1(
  'f7000000-0000-4000-8000-000000000002',
  'f7000000-0000-4000-8000-000000000802',
  encode(
    extensions.digest(convert_to('Historical Coach V1.', 'UTF8'), 'sha256'),
    'hex'
  ),
  'today',
  '2026-08-13',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  'controlled-coach-prompt-v1',
  'coach-context-v1',
  '2026-08-13T09:22:00Z',
  '2026-08-13T09:24:00Z',
  20
);

select public.fail_coach_request_v1(
  'f7000000-0000-4000-8000-000000000002',
  'f7000000-0000-4000-8000-000000000802',
  '{
    "code":"interrupted",
    "message":"The Coach request expired before completion.",
    "retryable":true
  }'::jsonb,
  '{
    "provider_called":false,
    "prompt_bytes":0,
    "context_bytes":0,
    "reply_codepoints":0
  }'::jsonb,
  '2026-08-13T09:23:00Z'
);

select public.claim_coach_request_v2(
  'f7000000-0000-4000-8000-000000000002',
  'f7000000-0000-4000-8000-000000000803',
  encode(
    extensions.digest(convert_to('Historical Coach V2.', 'UTF8'), 'sha256'),
    'hex'
  ),
  'today',
  '{}'::jsonb,
  '2026-08-13',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  'controlled-coach-prompt-v3',
  'coach-context-v3',
  '2026-08-13T09:24:00Z',
  '2026-08-13T09:26:00Z',
  20
);

select public.fail_coach_request_v1(
  'f7000000-0000-4000-8000-000000000002',
  'f7000000-0000-4000-8000-000000000803',
  '{
    "code":"interrupted",
    "message":"The Coach request expired before completion.",
    "retryable":true
  }'::jsonb,
  '{
    "provider_called":false,
    "prompt_bytes":0,
    "context_bytes":0,
    "reply_codepoints":0
  }'::jsonb,
  '2026-08-13T09:25:00Z'
);

insert into public.coach_messages (
  id, request_id, user_id, role, content, metadata, created_at,
  contract_version
) values (
  'f7000000-0000-4000-8000-000000000811',
  'f7000000-0000-4000-8000-000000000801',
  'f7000000-0000-4000-8000-000000000001',
  'user',
  'Retire this generated turn.',
  '{}'::jsonb,
  '2026-08-13T09:21:00Z',
  'coach-message-v1'
);

commit;
