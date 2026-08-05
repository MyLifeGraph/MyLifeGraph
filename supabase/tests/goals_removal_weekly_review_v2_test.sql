begin;
select no_plan();

select hasnt_table(
  'public',
  'goals',
  'Goals are absent after the additive retirement migration'
);

select is_empty(
  $$
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'goals'
  $$,
  'Goals leave no RLS policy behind'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc as p
    where p.pronamespace = 'private'::regnamespace
      and p.proname in (
        'retire_setup_goals_and_friction_v1',
        'references_retired_personalization_v1',
        'remove_goal_derived_history_v1',
        'references_goal_feature_v1',
        'remove_goal_keys_v1'
      )
  $$,
  'migration-only and retired Goal helpers are absent from final state'
);

select ok(
  to_regprocedure(
    'public.apply_intake_v1_setup_revision('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)'
  ) is not null
  and to_regprocedure(
    'public.apply_intake_v1_setup_revision('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)'
  ) is null,
  'Setup exposes only the Goal-free twelve-argument RPC signature'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.apply_intake_v1_setup_revision('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.apply_intake_v1_setup_revision('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_intake_v1_setup_revision('
      'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
      'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)',
    'EXECUTE'
  ),
  'the Goal-free Setup RPC remains service-role-only'
);

select ok(
  position(
    '''goal''' in (
    select pg_get_constraintdef(oid)
    from pg_constraint
    where conrelid = 'public.memory_entries'::regclass
      and conname = 'memory_entries_type_check'
    )
  ) = 0,
  'Goal is no longer an allowed memory discriminator'
);

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
  'd1000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'goal-free-contract@example.test',
  crypt('test-password', gen_salt('bf')),
  '2026-08-03T08:00:00Z',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Goal-free contract"}'::jsonb,
  '2026-08-03T08:00:00Z',
  '2026-08-03T08:00:00Z'
);

insert into public.user_state_snapshots (
  id,
  user_id,
  scope,
  period_key,
  summary,
  signals,
  source,
  source_observed_at,
  generated_at,
  metadata
) values (
  'd1000000-0000-4000-8000-000000000101',
  'd1000000-0000-4000-8000-000000000001',
  'weekly',
  '2026-W31',
  '{}'::jsonb,
  '{}'::jsonb,
  'backend',
  '2026-08-03T09:00:00Z',
  '2026-08-03T09:00:00Z',
  '{}'::jsonb
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
  source_fingerprint,
  source_observed_at,
  generated_at,
  created_at,
  updated_at
) values (
  'd1000000-0000-4000-8000-000000000201',
  'd1000000-0000-4000-8000-000000000001',
  '2026-W31',
  '2026-07-27',
  '2026-08-02',
  'Europe/Berlin',
  'sufficient',
  'Historical proposal transport fixture.',
  '{"tasks":{"completed":1,"carried":0,"overdue_carried":0,"cancelled":0}}',
  '[{
    "id":"weekly-review:2026-W31:habit:legacy:shrink",
    "operation":"shrink",
    "target_kind":"habit",
    "target_id":"d1000000-0000-4000-8000-000000000301",
    "target_title":"Historical habit",
    "ownership":"manual",
    "application_mode":"direct_habit",
    "expected_updated_at":"2026-08-02T18:00:00Z",
    "reason_code":"legacy_adjustment",
    "reason":"Historical transport only.",
    "evidence_refs":[],
    "change":{
      "before":{"lifecycle":"active","cadence":{"kind":"weekly_target","weekly_target":4,"scheduled_weekdays":[]}},
      "after":{"lifecycle":"active","cadence":{"kind":"weekly_target","weekly_target":3,"scheduled_weekdays":[]}}
    }
  }]'::jsonb,
  '[]'::jsonb,
  '{
    "engine":"deterministic",
    "contract_version":"weekly-review-v2",
    "source_snapshot_id":"d1000000-0000-4000-8000-000000000101",
    "source_snapshot_generated_at":"2026-08-03T09:00:00Z",
    "evidence_window":{"starts_on":"2026-07-27","ends_on":"2026-08-02","days":7},
    "source_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "baseline":"none",
    "limitations":[],
    "llm_used":false
  }'::jsonb,
  repeat('a', 64),
  '2026-08-03T09:00:00Z',
  '2026-08-03T09:00:00Z',
  '2026-08-03T09:00:00Z',
  '2026-08-03T09:00:00Z'
);

select is(
  jsonb_array_length(
    (
      select proposals
      from public.weekly_reviews
      where id = 'd1000000-0000-4000-8000-000000000201'
    )
  ),
  1,
  'a historical proposal array remains stored and transport-readable'
);

create temporary table current_weekly_payload on commit drop as
select '{
  "user_id":"d1000000-0000-4000-8000-000000000001",
  "period_key":"2026-W31",
  "week_start":"2026-07-27",
  "week_end":"2026-08-02",
  "timezone":"Europe/Berlin",
  "data_quality":"sufficient",
  "narrative":"This week records 2 completed and 0 still-open tasks, 4 completed and 0 intentionally skipped habit outcomes, and 1 observed recovery days.",
  "facts":{
    "tasks":{"completed":2,"carried":0,"overdue_carried":0,"cancelled":0},
    "habits":{"active":1,"paused":0,"archived":0,"stable_definitions":1,"changed_definitions":0,"scheduled_opportunities":4,"completed":4,"skipped":0,"missed":0,"recovery_open":0,"unknown":0},
    "focus":{"completed_sessions":1,"abandoned_sessions":0,"active_sessions":0,"actual_minutes":45},
    "recovery":{"observed_days":7,"recovery_days":1},
    "feedback":{"total":1,"done":0,"later":0,"not_helpful":0,"too_much":1,"does_not_fit":0}
  },
  "proposals":[],
  "evidence_refs":[],
  "provenance":{
    "engine":"deterministic",
    "contract_version":"weekly-review-v2",
    "source_snapshot_id":"d1000000-0000-4000-8000-000000000101",
    "source_snapshot_generated_at":"2026-08-03T09:00:00Z",
    "evidence_window":{"starts_on":"2026-07-27","ends_on":"2026-08-02","days":7},
    "source_fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "baseline":"none",
    "limitations":[],
    "llm_used":false
  },
  "source_fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "source_observed_at":"2026-08-03T09:00:00Z",
  "generated_at":"2026-08-03T09:05:00Z",
  "updated_at":"2026-08-03T09:05:00Z"
}'::jsonb as value;

select lives_ok(
  $$
    select public.persist_weekly_review_v2(
      'd1000000-0000-4000-8000-000000000001',
      '2026-W31',
      '2026-08-03T09:00:00Z',
      (select value from current_weekly_payload)
    )
  $$,
  'a current V2 refresh persists only observational facts'
);

select ok(
  (
    select id = 'd1000000-0000-4000-8000-000000000201'
      and proposals = '[]'::jsonb
      and not ((facts #> '{tasks}') ? 'goal_linked_completed')
      and provenance ->> 'contract_version' = 'weekly-review-v2'
    from public.weekly_reviews
    where user_id = 'd1000000-0000-4000-8000-000000000001'
      and period_key = '2026-W31'
  ),
  'refresh preserves identity while replacing legacy proposals with an empty array'
);

select throws_ok(
  $$
    select public.persist_weekly_review_v2(
      'd1000000-0000-4000-8000-000000000001',
      '2026-W31',
      '2026-08-03T09:00:00Z',
      jsonb_set(
        (select value from current_weekly_payload),
        '{proposals}',
        '[{}]'::jsonb
      )
    )
  $$,
  '22023',
  'Weekly review persistence payload is invalid.',
  'the V2 persistence RPC rejects every new non-empty proposal array'
);

select throws_ok(
  $$
    insert into public.weekly_reviews (
      user_id, period_key, week_start, week_end, timezone, data_quality,
      narrative, facts, proposals, evidence_refs, provenance,
      source_fingerprint, source_observed_at, generated_at, updated_at
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      '2026-W30',
      '2026-07-20',
      '2026-07-26',
      'Europe/Berlin',
      'sufficient',
      'Invalid retired fact.',
      '{"tasks":{"goal_linked_completed":0}}',
      '[]',
      '[]',
      '{
        "engine":"deterministic",
        "contract_version":"weekly-review-v2",
        "source_snapshot_id":"d1000000-0000-4000-8000-000000000101",
        "source_snapshot_generated_at":"2026-08-03T09:00:00Z",
        "evidence_window":{"starts_on":"2026-07-20","ends_on":"2026-07-26","days":7},
        "source_fingerprint":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "baseline":"none",
        "limitations":[],
        "llm_used":false
      }',
      repeat('c', 64),
      '2026-08-03T09:00:00Z',
      '2026-08-03T09:00:00Z',
      '2026-08-03T09:00:00Z'
    )
  $$,
  '23514',
  null,
  'the final table rejects the retired Goal-linked task counter'
);

insert into public.intake_responses (
  id,
  user_id,
  version,
  responses,
  metadata,
  request_id,
  base_revision,
  revision,
  state,
  updated_at
) values (
  'd1000000-0000-4000-8000-000000000401',
  'd1000000-0000-4000-8000-000000000001',
  'intake-v1',
  '{
    "weekday_shape":"flexible",
    "best_energy_window":"morning",
    "goals":[],
    "routines":[],
    "fixed_commitments":[]
  }'::jsonb,
  '{}'::jsonb,
  'd1000000-0000-4000-8000-000000000402',
  0,
  1,
  'pending',
  '2026-08-03T10:00:00Z'
);

select throws_ok(
  $$
    select public.apply_intake_v1_setup_revision(
      'd1000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000401',
      'd1000000-0000-4000-8000-000000000402',
      0,
      1,
      '2026-08-03T10:05:00Z',
      '{}'::jsonb,
      '[]'::jsonb,
      '[]'::jsonb,
      '[]'::jsonb,
      '{"summary":{},"signals":{},"metadata":{}}'::jsonb,
      '{}'::jsonb
    )
  $$,
  '22023',
  'Intake V1 goals are no longer supported',
  'the internal Setup RPC rejects responses.goals without writing projections'
);

select * from finish();
rollback;
