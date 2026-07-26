begin;
select no_plan();

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'b2000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'recommendation-owner@example.test',
  crypt('test-password', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.recommendations (
  id, user_id, title, reason, action_label, category, confidence, status,
  priority, metadata, generated_at, updated_at
) values
(
  'b2000000-0000-4000-8000-000000000101',
  'b2000000-0000-4000-8000-000000000001',
  'Old new card', 'Old evidence', 'Review', 'planning', 0.6, 'new', 'medium',
  '{"fingerprint":"old-new"}',
  '2026-07-26T08:00:00Z', '2026-07-26T08:00:00Z'
),
(
  'b2000000-0000-4000-8000-000000000102',
  'b2000000-0000-4000-8000-000000000001',
  'Accepted card', 'Preserved evidence', 'Review', 'planning', 0.7,
  'accepted', 'medium', '{"fingerprint":"accepted"}',
  '2026-07-26T08:00:00Z', '2026-07-26T08:00:00Z'
);

set local role service_role;
select is(
  (
    public.replace_current_recommendations_v2(
      'b2000000-0000-4000-8000-000000000001',
      jsonb_build_array(
        jsonb_build_object(
          'title', 'Measured movement',
          'reason', 'Three measured days crossed the fixed threshold.',
          'action_label', 'Take a short walk',
          'category', 'movement',
          'priority', 'low',
          'confidence', 0.65,
          'metadata', jsonb_build_object(
            'rule_id', 'movement_nudge',
            'fingerprint',
              'deterministic-v1:movement_nudge:2026-W30:abcdef',
            'evidence_refs', jsonb_build_array(
              jsonb_build_object(
                'table', 'daily_logs', 'id', 'log-1', 'field', 'steps'
              )
            ),
            'period_key', '2026-W30',
            'source_engine_version', 'deterministic-v1',
            'invalidation_dependencies', jsonb_build_array('daily_logs.steps'),
            'deterministic_scores', jsonb_build_object('final', 0.65),
            'model', null
          )
        )
      ),
      '2026-07-26T09:00:00Z'
    ) ->> 'inserted_count'
  )::int,
  1,
  'one transaction installs the complete generated set'
);
reset role;

select is(
  (
    select status
    from public.recommendations
    where id = 'b2000000-0000-4000-8000-000000000101'
  ),
  'dismissed',
  'the previous new card remains as dismissed history'
);
select is(
  (
    select metadata ->> 'current_feed_retired_reason'
    from public.recommendations
    where id = 'b2000000-0000-4000-8000-000000000101'
  ),
  'replaced_by_deliberate_refresh',
  'retired history records why it left the current feed'
);
select is(
  (
    select status
    from public.recommendations
    where id = 'b2000000-0000-4000-8000-000000000102'
  ),
  'accepted',
  'accepted user history is not replaced'
);

set local role service_role;
select lives_ok(
  $$
    select public.replace_current_recommendations_v2(
      'b2000000-0000-4000-8000-000000000001',
      '[]'::jsonb,
      '2026-07-26T10:00:00Z'
    )
  $$,
  'an empty verified set atomically clears only the current new feed'
);
reset role;

select is(
  (
    select count(*)::int
    from public.recommendations
    where user_id = 'b2000000-0000-4000-8000-000000000001'
      and status = 'new'
  ),
  0,
  'no stale new card remains after an empty refresh'
);

select * from finish();
rollback;
