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
  'a1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'retired-setup-migration@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-07-01T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Legacy Setup"}'::jsonb,
  '2026-07-01T08:00:00Z',
  '2026-07-01T08:00:00Z'
);

update public.profiles
set setup_revision = 1,
    onboarding_completed_at = '2026-07-01T09:00:00Z'
where id = 'a1000000-0000-4000-8000-000000000001';

update public.notification_preferences
set
  focus_prompts_enabled = false,
  recovery_prompts_enabled = true,
  weekly_summary_enabled = false,
  quiet_hours_start = '22:15',
  quiet_hours_end = '06:45',
  in_app_delivery_enabled = true,
  in_app_delivery_consent_version = 'in-app-notification-consent-v1',
  in_app_delivery_consented_at = '2026-07-01T08:30:00Z',
  in_app_delivery_disabled_at = null,
  daily_notification_limit = 1,
  delivery_settings_request_id =
    'a1000000-0000-4000-8000-000000000011',
  delivery_settings_request_fingerprint = repeat('1', 64),
  updated_at = '2026-07-01T09:30:00Z'
where user_id = 'a1000000-0000-4000-8000-000000000001';

create temporary table expected_notification_preferences on commit drop as
select to_jsonb(preference) as value
from public.notification_preferences as preference
where user_id = 'a1000000-0000-4000-8000-000000000001';

insert into public.intake_responses (
  id,
  user_id,
  version,
  responses,
  completed_at,
  metadata,
  request_id,
  base_revision,
  revision,
  state,
  updated_at
) values (
  'a1000000-0000-4000-8000-000000000101',
  'a1000000-0000-4000-8000-000000000001',
  'intake-v1',
  '{
    "display_name":"Legacy Setup",
    "weekday_shape":"Structured mornings",
    "best_energy_window":"morning",
    "primary_focus_areas":["focus"],
    "goals":[{"title":"Retired"}],
    "friction_points":["interruptions"],
    "coaching_style":"analytical",
    "reminder_preference":{"enabled":true},
    "context_note":"Retired private context",
    "routines":[],
    "fixed_commitments":[]
  }'::jsonb,
  '2026-07-01T09:00:00Z',
  '{"source":"onboarding"}'::jsonb,
  'a1000000-0000-4000-8000-000000000102',
  0,
  1,
  'applied',
  '2026-07-01T09:00:00Z'
);

insert into public.user_state_snapshots (
  id,
  user_id,
  scope,
  period_key,
  summary,
  signals,
  source,
  generated_at,
  metadata
) values
(
  'a1000000-0000-4000-8000-000000000201',
  'a1000000-0000-4000-8000-000000000001',
  'onboarding',
  'setup:intake-v1',
  '{
    "primary_focus_areas":["focus"],
    "goals":["Retired"],
    "friction_points":["interruptions"],
    "coaching_style":"analytical",
    "reminder_enabled":true,
    "best_energy_window":"morning",
    "fixed_commitment_count":1,
    "existing_habit_count":2,
    "routine_candidate_count":3,
    "active_habit_count":1
  }'::jsonb,
  '{"friction_points":["interruptions"],"routine_candidates":["old"]}'::jsonb,
  'backend',
  '2026-07-01T09:00:00Z',
  '{"source":"intake-v1","managed_by":"setup"}'::jsonb
),
(
  'a1000000-0000-4000-8000-000000000202',
  'a1000000-0000-4000-8000-000000000001',
  'daily',
  '2026-07-24',
  '{"daily_state":{"context":{"main_friction":"interruptions"}}}'::jsonb,
  '{"reason_evidence":{"plan_start_friction":[]}}'::jsonb,
  'backend',
  '2026-07-24T08:00:00Z',
  '{}'::jsonb
),
(
  'a1000000-0000-4000-8000-000000000203',
  'a1000000-0000-4000-8000-000000000001',
  'daily',
  '2026-07-25',
  '{"daily_state":{"contract_version":"explainable-daily-state-v2"}}'::jsonb,
  '{}'::jsonb,
  'backend',
  '2026-07-25T08:00:00Z',
  '{}'::jsonb
);

insert into public.goals (
  id, user_id, title, status, metadata, updated_at
) values
(
  'a1000000-0000-4000-8000-000000000301',
  'a1000000-0000-4000-8000-000000000001',
  'Setup goal',
  'active',
  '{"managed_by":"setup","source":"intake-v1","setup_state":"active"}',
  '2026-07-01T09:00:00Z'
),
(
  'a1000000-0000-4000-8000-000000000302',
  'a1000000-0000-4000-8000-000000000001',
  'Manual goal',
  'active',
  '{"source":"manual"}',
  '2026-07-01T09:00:00Z'
);

insert into public.memory_entries (
  id, user_id, type, title, content, strength, evidence, metadata,
  last_seen_at, updated_at
) values
(
  'a1000000-0000-4000-8000-000000000401',
  'a1000000-0000-4000-8000-000000000001',
  'pattern',
  'Best energy window',
  'morning',
  0.7,
  '[]',
  '{"managed_by":"setup","source":"intake-v1"}',
  '2026-07-01T09:00:00Z',
  '2026-07-01T09:00:00Z'
),
(
  'a1000000-0000-4000-8000-000000000402',
  'a1000000-0000-4000-8000-000000000001',
  'goal',
  'Goal: Retired',
  'Retired',
  0.7,
  '[]',
  '{"managed_by":"setup","source":"intake-v1"}',
  '2026-07-01T09:00:00Z',
  '2026-07-01T09:00:00Z'
),
(
  'a1000000-0000-4000-8000-000000000403',
  'a1000000-0000-4000-8000-000000000001',
  'preference',
  'Preferred coaching style',
  'analytical coaching',
  0.7,
  '[]',
  '{"managed_by":"setup","source":"intake-v1"}',
  '2026-07-01T09:00:00Z',
  '2026-07-01T09:00:00Z'
),
(
  'a1000000-0000-4000-8000-000000000404',
  'a1000000-0000-4000-8000-000000000001',
  'preference',
  'Intake context note',
  'Retired private context',
  0.7,
  '[]',
  '{"managed_by":"setup","source":"intake-v1"}',
  '2026-07-01T09:00:00Z',
  '2026-07-01T09:00:00Z'
),
(
  'a1000000-0000-4000-8000-000000000405',
  'a1000000-0000-4000-8000-000000000001',
  'preference',
  'Manual memory',
  'Keep',
  0.7,
  '[]',
  '{"source":"manual"}',
  '2026-07-01T09:00:00Z',
  '2026-07-01T09:00:00Z'
);

insert into public.daily_logs (
  id, user_id, entry_date, source, metadata
) values (
  'a1000000-0000-4000-8000-000000000501',
  'a1000000-0000-4000-8000-000000000001',
  '2026-07-24',
  'manual',
  '{
    "main_friction":"interruptions",
    "additional_frictions":["hard_to_start"],
    "capture_version":"daily-capture-v2",
    "captures":{"evening":{
      "main_friction":"interruptions",
      "additional_frictions":["hard_to_start"],
      "mood":7,
      "energy":6,
      "stress_intensity":4
    }}
  }'::jsonb
);

insert into public.behavioral_events (
  id, user_id, daily_log_id, event_type, occurred_at, source, metadata
) values (
  'a1000000-0000-4000-8000-000000000502',
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000501',
  'planning_friction',
  '2026-07-24T20:00:00Z',
  'app',
  '{
    "main_friction":"interruptions",
    "captures":{"evening":{"additional_frictions":["hard_to_start"]}}
  }'::jsonb
);

insert into public.daily_briefings (
  id,
  user_id,
  briefing_date,
  mode,
  summary,
  primary_action,
  support_actions,
  evidence_refs,
  provenance,
  data_quality,
  metadata
) values
(
  'a1000000-0000-4000-8000-000000000601',
  'a1000000-0000-4000-8000-000000000001',
  '2026-07-24',
  'plan',
  'Old derived briefing',
  '{"kind":"capture","target_type":"daily_log"}',
  '[]',
  '[{"table":"daily_logs","id":"a1000000-0000-4000-8000-000000000501",
    "field":"metadata.captures.evening.main_friction"}]',
  '{"contract_version":"daily-briefing-v1"}',
  'current',
  '{}'
),
(
  'a1000000-0000-4000-8000-000000000602',
  'a1000000-0000-4000-8000-000000000001',
  '2026-07-25',
  'steady',
  'Current clean briefing',
  '{"kind":"task","target_type":"task"}',
  '[]',
  '[{"table":"tasks","id":"a1000000-0000-4000-8000-000000000999",
    "field":"status"}]',
  '{"contract_version":"daily-briefing-v1"}',
  'current',
  '{}'
);

insert into public.weekly_reviews (
  id,
  user_id,
  period_key,
  week_start,
  week_end,
  timezone,
  data_quality,
  narrative,
  facts,
  proposals,
  evidence_refs,
  provenance,
  source_fingerprint
) values (
  'a1000000-0000-4000-8000-000000000701',
  'a1000000-0000-4000-8000-000000000001',
  '2026-W30',
  '2026-07-20',
  '2026-07-26',
  'Europe/Berlin',
  'sufficient',
  'Old goal-derived review',
  '{"tasks":{"goal_linked_completed":1}}',
  '[]',
  '[]',
  '{
    "engine":"deterministic",
    "contract_version":"weekly-review-v1",
    "baseline":"none",
    "llm_used":false,
    "source_snapshot_id":"a1000000-0000-4000-8000-000000000202",
    "source_snapshot_generated_at":"2026-07-24T08:00:00Z",
    "evidence_window":{
      "starts_on":"2026-07-20",
      "ends_on":"2026-07-26",
      "days":7
    },
    "source_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "limitations":[]
  }',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
);

insert into public.recommendations (
  id,
  user_id,
  title,
  reason,
  action_label,
  category,
  confidence,
  status,
  metadata
) values
(
  'a1000000-0000-4000-8000-000000000801',
  'a1000000-0000-4000-8000-000000000001',
  'Old onboarding recommendation',
  'Old Setup evidence',
  'Review',
  'planning',
  0.8,
  'new',
  '{
    "rule_id":"planning_reset",
    "evidence_refs":[{
      "table":"user_state_snapshots",
      "id":"a1000000-0000-4000-8000-000000000201",
      "field":"summary.goals"
    }]
  }'
),
(
  'a1000000-0000-4000-8000-000000000802',
  'a1000000-0000-4000-8000-000000000001',
  'Old planning-friction recommendation',
  'Old runtime evidence',
  'Review',
  'planning',
  0.8,
  'new',
  '{
    "rule_id":"planning_reset",
    "evidence_refs":[{
      "table":"behavioral_events",
      "id":"a1000000-0000-4000-8000-000000000502",
      "field":"event_type"
    }]
  }'
),
(
  'a1000000-0000-4000-8000-000000000803',
  'a1000000-0000-4000-8000-000000000001',
  'Clean task recommendation',
  'Current task evidence',
  'Review',
  'planning',
  0.8,
  'new',
  '{
    "rule_id":"planning_reset",
    "evidence_refs":[{
      "table":"tasks",
      "id":"a1000000-0000-4000-8000-000000000999",
      "field":"status"
    }]
  }'
),
(
  'a1000000-0000-4000-8000-000000000804',
  'a1000000-0000-4000-8000-000000000001',
  'Clean runtime snapshot recommendation',
  'Current Daily State evidence',
  'Review',
  'planning',
  0.8,
  'new',
  '{
    "rule_id":"planning_reset",
    "evidence_refs":[{
      "table":"user_state_snapshots",
      "id":"a1000000-0000-4000-8000-000000000203",
      "field":"summary.daily_state.mode"
    }]
  }'
);

select private.retire_setup_goals_and_friction_v1();

select ok(
  not (
    select responses ?| array[
      'primary_focus_areas',
      'goals',
      'friction_points',
      'coaching_style',
      'reminder_preference',
      'context_note'
    ]
    from public.intake_responses
    where id = 'a1000000-0000-4000-8000-000000000101'
  ),
  'retired Intake keys are removed'
);

select is(
  (
    select summary
    from public.user_state_snapshots
    where id = 'a1000000-0000-4000-8000-000000000201'
  ),
  '{
    "best_energy_window":"morning",
    "fixed_commitment_count":1,
    "existing_habit_count":2,
    "routine_candidate_count":3,
    "active_habit_count":1
  }'::jsonb,
  'the onboarding summary keeps only energy and relevant counters'
);

select is(
  (
    select signals
    from public.user_state_snapshots
    where id = 'a1000000-0000-4000-8000-000000000201'
  ),
  '{}'::jsonb,
  'retired onboarding signals are cleared'
);

select is(
  (
    select status
    from public.goals
    where id = 'a1000000-0000-4000-8000-000000000301'
  ),
  'archived',
  'Setup-owned Goals are archived'
);

select is(
  (
    select status
    from public.goals
    where id = 'a1000000-0000-4000-8000-000000000302'
  ),
  'active',
  'manual Goals remain unchanged'
);

select is(
  (
    select array_agg(title order by title)
    from public.memory_entries
    where user_id = 'a1000000-0000-4000-8000-000000000001'
  ),
  array['Best energy window', 'Manual memory']::text[],
  'only retired Setup memories are deleted'
);

select ok(
  not (
    select metadata::text ~ 'main_friction|additional_frictions'
    from public.daily_logs
    where id = 'a1000000-0000-4000-8000-000000000501'
  ),
  'Daily Log friction keys are removed'
);

select ok(
  not (
    select metadata::text ~ 'main_friction|additional_frictions'
    from public.behavioral_events
    where id = 'a1000000-0000-4000-8000-000000000502'
  ),
  'Behavioral Event friction keys are removed'
);

select is(
  (
    select count(*)
    from public.user_state_snapshots
    where id = 'a1000000-0000-4000-8000-000000000202'
  ),
  0::bigint,
  'affected Daily State snapshots are invalidated'
);

select is(
  (
    select count(*)
    from public.user_state_snapshots
    where id = 'a1000000-0000-4000-8000-000000000203'
  ),
  1::bigint,
  'clean Daily State snapshots remain'
);

select is(
  (
    select count(*)
    from public.daily_briefings
    where id = 'a1000000-0000-4000-8000-000000000601'
  ),
  0::bigint,
  'affected briefings are invalidated'
);

select is(
  (
    select count(*)
    from public.daily_briefings
    where id = 'a1000000-0000-4000-8000-000000000602'
  ),
  1::bigint,
  'clean briefings remain'
);

select is(
  (
    select count(*)
    from public.weekly_reviews
    where id = 'a1000000-0000-4000-8000-000000000701'
  ),
  0::bigint,
  'goal-derived weekly reviews are invalidated'
);

select is(
  (
    select array_agg(id order by id)
    from public.recommendations
    where user_id = 'a1000000-0000-4000-8000-000000000001'
  ),
  array[
    'a1000000-0000-4000-8000-000000000803'::uuid,
    'a1000000-0000-4000-8000-000000000804'::uuid
  ],
  'clean task and runtime-snapshot recommendations remain'
);

select is(
  (
    select to_jsonb(preference)
    from public.notification_preferences as preference
    where user_id = 'a1000000-0000-4000-8000-000000000001'
  ),
  (select value from expected_notification_preferences),
  'the cleanup does not touch personalized Reminder settings'
);

create temporary table state_after_first_cleanup on commit drop as
select
  (
    select updated_at
    from public.goals
    where id = 'a1000000-0000-4000-8000-000000000301'
  ) as setup_goal_updated_at,
  (
    select jsonb_agg(to_jsonb(intake) order by intake.id)
    from public.intake_responses as intake
    where user_id = 'a1000000-0000-4000-8000-000000000001'
  ) as intake_rows;

select private.retire_setup_goals_and_friction_v1();

select is(
  (
    select updated_at
    from public.goals
    where id = 'a1000000-0000-4000-8000-000000000301'
  ),
  (select setup_goal_updated_at from state_after_first_cleanup),
  'a second cleanup execution does not retimestamp archived Goals'
);

select is(
  (
    select jsonb_agg(to_jsonb(intake) order by intake.id)
    from public.intake_responses as intake
    where user_id = 'a1000000-0000-4000-8000-000000000001'
  ),
  (select intake_rows from state_after_first_cleanup),
  'a second cleanup execution leaves canonical Intake rows unchanged'
);

insert into public.intake_responses (
  id,
  user_id,
  version,
  responses,
  completed_at,
  metadata,
  request_id,
  base_revision,
  revision,
  state,
  updated_at
) values (
  'a1000000-0000-4000-8000-000000000103',
  'a1000000-0000-4000-8000-000000000001',
  'intake-v1',
  '{
    "display_name":"Canonical Setup",
    "weekday_shape":"Flexible afternoons",
    "best_energy_window":"afternoon",
    "routines":[],
    "fixed_commitments":[]
  }'::jsonb,
  '2026-07-25T10:00:00Z',
  '{"source":"onboarding"}'::jsonb,
  'a1000000-0000-4000-8000-000000000104',
  1,
  2,
  'pending',
  '2026-07-25T10:00:00Z'
);

update public.goals
set status = 'active',
    metadata = metadata || '{"setup_state":"active"}'::jsonb
where id = 'a1000000-0000-4000-8000-000000000301';

select public.apply_intake_v1_setup_revision(
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000103',
  'a1000000-0000-4000-8000-000000000104',
  1,
  2,
  '2026-07-25T10:05:00Z',
  '["this retired argument is intentionally not an object"]'::jsonb,
  '{"this retired argument":"is intentionally not an array"}'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', 'a1000000-0000-4000-8000-000000000401',
    'type', 'pattern',
    'title', 'Best energy window',
    'content', 'afternoon',
    'strength', 0.7,
    'evidence', '[]'::jsonb,
    'metadata', jsonb_build_object(
      'managed_by', 'setup',
      'source', 'intake-v1',
      'revision', 2,
      'setup_item_id', 'a1000000-0000-4000-8000-000000000901'
    )
  )),
  '{
    "summary":{
      "best_energy_window":"afternoon",
      "fixed_commitment_count":0,
      "existing_habit_count":0,
      "routine_candidate_count":0,
      "active_habit_count":0
    },
    "signals":{},
    "metadata":{"source":"intake-v1","managed_by":"setup"}
  }'::jsonb,
  '{"source":"onboarding"}'::jsonb
);

select is(
  (
    select to_jsonb(preference)
    from public.notification_preferences as preference
    where user_id = 'a1000000-0000-4000-8000-000000000001'
  ),
  (select value from expected_notification_preferences),
  'Setup Apply leaves the entire personalized Reminder row byte-for-byte equal'
);

select is(
  (
    select status
    from public.goals
    where id = 'a1000000-0000-4000-8000-000000000301'
  ),
  'archived',
  'Setup Apply always archives a Setup-owned Goal'
);

select is(
  (
    select status
    from public.goals
    where id = 'a1000000-0000-4000-8000-000000000302'
  ),
  'active',
  'Setup Apply does not alter a manual Goal'
);

select is(
  (
    select content
    from public.memory_entries
    where id = 'a1000000-0000-4000-8000-000000000401'
  ),
  'afternoon',
  'Setup Apply retains and refreshes only the energy memory'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_intake_v1_setup_revision_without_study_setup('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.apply_intake_v1_setup_revision_without_study_setup('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)',
    'EXECUTE'
  ),
  'the compatibility inner function remains uncallable'
);

create temporary table coach_v2_claim on commit drop as
select public.claim_coach_request_v1(
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000a01',
  encode(
    extensions.digest(convert_to('V2 Coach request', 'UTF8'), 'sha256'),
    'hex'
  ),
  'today',
  '2026-07-25',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  'controlled-coach-prompt-v2',
  'coach-context-v2',
  '2026-07-25T11:00:00Z',
  '2026-07-25T11:01:00Z',
  10
) as value;

select is(
  (select value ->> 'state' from coach_v2_claim),
  'pending',
  'a new Coach V2 request is claimed'
);

select is(
  (
    select prompt_version || '/' || context_version
    from public.coach_requests
    where request_id = 'a1000000-0000-4000-8000-000000000a01'
  ),
  'controlled-coach-prompt-v2/coach-context-v2',
  'the new Coach request persists paired V2 provenance'
);

select is(
  (
    select public.claim_coach_request_v1(
      'a1000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000a01',
      encode(
        extensions.digest(convert_to('V2 Coach request', 'UTF8'), 'sha256'),
        'hex'
      ),
      'today',
      '2026-07-25',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v2',
      'coach-context-v2',
      '2026-07-25T11:00:00Z',
      '2026-07-25T11:01:00Z',
      10
    ) ->> 'state'
  ),
  'in_progress',
  'an exact pending Coach V2 claim replay preserves the existing in-progress semantics'
);

select public.complete_coach_request_v1(
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000a01',
  'V2 Coach request',
  jsonb_build_object(
    'contract_version', 'coach-response-v1',
    'request_id', 'a1000000-0000-4000-8000-000000000a01',
    'reply', 'V2 response',
    'uncertainty', jsonb_build_object(
      'level', 'low',
      'reason', 'Deterministic test response.'
    ),
    'staged_suggestion', null,
    'safety', jsonb_build_object('classification', 'normal'),
    'used_context', '[]'::jsonb,
    'provenance', jsonb_build_object(
      'source', 'model',
      'provider', 'fake',
      'provider_mode', 'deterministic_test_only',
      'model_requested', null,
      'model_reported', null,
      'model_source', 'not_applicable',
      'prompt_version', 'controlled-coach-prompt-v2',
      'context_version', 'coach-context-v2',
      'generated_at', '2026-07-25T11:00:30Z',
      'provider_called', true
    )
  ),
  '[]'::jsonb,
  jsonb_build_object(
    'provider_called', true,
    'prompt_bytes', 10,
    'context_bytes', 20,
    'reply_codepoints', char_length('V2 response')
  ),
  '2026-07-25T11:00:30Z'
);

select is(
  (
    select response #>> '{provenance,context_version}'
    from public.coach_requests
    where request_id = 'a1000000-0000-4000-8000-000000000a01'
      and state = 'completed'
  ),
  'coach-context-v2',
  'a strict Coach V2 response completes without rewriting its provenance'
);

select is(
  (
    select public.claim_coach_request_v1(
      'a1000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000a02',
      encode(
        extensions.digest(convert_to('V1 Coach replay', 'UTF8'), 'sha256'),
        'hex'
      ),
      'today',
      '2026-07-25',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v1',
      'coach-context-v1',
      '2026-07-25T11:02:00Z',
      '2026-07-25T11:03:00Z',
      10
    ) ->> 'state'
  ),
  'pending',
  'the persisted V1 Coach boundary remains readable and replay-compatible'
);

select throws_ok(
  $$
    select public.claim_coach_request_v1(
      'a1000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000a02',
      encode(
        extensions.digest(convert_to('V1 Coach replay', 'UTF8'), 'sha256'),
        'hex'
      ),
      'today',
      '2026-07-25',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v2',
      'coach-context-v2',
      '2026-07-25T11:02:00Z',
      '2026-07-25T11:03:00Z',
      10
    )
  $$,
  'PT409',
  'Coach request id already uses different versions',
  'a pending V1 request cannot be reinterpreted as V2'
);

select throws_ok(
  $$
    select public.claim_coach_request_v1(
      'a1000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000a03',
      repeat('a', 64),
      'today',
      '2026-07-25',
      'fake',
      'deterministic_test_only',
      null,
      'not_applicable',
      'controlled-coach-prompt-v2',
      'coach-context-v1',
      '2026-07-25T11:04:00Z',
      '2026-07-25T11:05:00Z',
      10
    )
  $$,
  '22023',
  'Coach claim versions are invalid',
  'mixed Coach prompt/context versions are rejected'
);

select * from finish();
rollback;
