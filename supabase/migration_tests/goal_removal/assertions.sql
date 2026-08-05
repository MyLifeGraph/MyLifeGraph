begin;
select no_plan();

select hasnt_table(
  'public',
  'goals',
  'the two-step migration leaves no Goals table'
);

select is_empty(
  $$
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'goals'
  $$,
  'the removed Goals table leaves no policy'
);

select is_empty(
  $$
    select grantee
    from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'goals'
  $$,
  'the removed Goals table leaves no grant'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc as p
    where p.pronamespace = 'private'::regnamespace
      and p.proname in (
        'goal_path_references_feature_v2',
        'is_goal_reference_object_v2',
        'references_goal_feature_v2',
        'sanitize_goal_feature_v2',
        'references_doomed_goal_record_v2',
        'remove_goal_derived_history_v2'
      )
  $$,
  'all follow-up migration helpers are absent'
);

select is_empty(
  $$
    select conname
    from pg_constraint
    where pg_get_constraintdef(oid) ~
      '(references_goal_feature_v2|sanitize_goal_feature_v2)'
  $$,
  'no permanent generic JSON Goal constraint was added'
);

select ok(
  (
    select not (responses ? 'legacy_ref')
      and responses ->> 'note' =
        'A goal mentioned in ordinary prose must remain.'
      and metadata -> 'sources' = '["tasks"]'::jsonb
      and metadata ->> 'ordinary' = 'goals can be prose'
    from public.intake_responses
    where id = 'e2000000-0000-4000-8000-000000000101'
  ),
  'Intake path and typed-array Goal references are sanitized without prose loss'
);

select ok(
  (
    select not (metadata ? 'legacy_ref')
      and metadata ->> 'note' = 'Keep this goal word as ordinary text.'
    from public.tasks
    where id = 'e2000000-0000-4000-8000-000000000201'
  ),
  'Task metadata is sanitized while ordinary Goal prose remains'
);

select ok(
  (
    select not (summary ? 'legacy_ref')
      and summary ->> 'note' = 'The word goal in prose remains.'
      and signals -> 'sources' = '["tasks"]'::jsonb
      and metadata = '{}'::jsonb
    from public.user_state_snapshots
    where id = 'e2000000-0000-4000-8000-000000000301'
  ),
  'the authoritative onboarding snapshot is structurally sanitized in place'
);

select is_empty(
  $$
    select id from public.recommendations
    where id = 'e2000000-0000-4000-8000-000000000401'
  $$,
  'a recommendation derived from the Setup onboarding snapshot is retired'
);

select is_empty(
  $$
    select id from public.daily_briefings
    where id = 'e2000000-0000-4000-8000-000000000411'
  $$,
  'a briefing carrying the retired recommendation id is retired'
);

select is_empty(
  $$
    select id from public.decision_feedback
    where id = 'e2000000-0000-4000-8000-000000000421'
  $$,
  'feedback linked through briefing and recommendation foreign keys is retired'
);

select is_empty(
  $$
    select id from public.weekly_reviews
    where id = 'e2000000-0000-4000-8000-000000000501'
  $$,
  'a review referencing indirectly retired feedback is retired'
);

select is_empty(
  $$
    select id from public.notifications
    where id = 'e2000000-0000-4000-8000-000000000601'
  $$,
  'the generated notification for an indirectly retired review is retired'
);

select is_empty(
  $$
    select request_id from public.notification_action_requests
    where request_id = 'e2000000-0000-4000-8000-000000000611'
  $$,
  'notification lifecycle retry history follows its established cascade'
);

select is_empty(
  $$
    select id from public.user_state_snapshots
    where id = 'e2000000-0000-4000-8000-000000000311'
  $$,
  'the field-path Goal snapshot is retired'
);

select is_empty(
  $$
    select id from public.weekly_reviews
    where id in (
      'e2000000-0000-4000-8000-000000000511',
      'e2000000-0000-4000-8000-000000000521'
    )
  $$,
  'reviews with a removed or already missing source snapshot are retired'
);

select is_empty(
  $$
    select id from public.memory_entries
    where id = 'e2000000-0000-4000-8000-000000000701'
  $$,
  'a structurally marked memory is retired'
);

select is_empty(
  $$
    select memory_id from public.coach_memory_selections
    where memory_id = 'e2000000-0000-4000-8000-000000000701'
  $$,
  'the memory selection follows its established cascade'
);

select ok(
  not exists (
    select 1 from public.ai_insights
    where id = 'e2000000-0000-4000-8000-000000000711'
  )
  and not exists (
    select 1 from public.behavioral_events
    where id = 'e2000000-0000-4000-8000-000000000721'
  )
  and not exists (
    select 1 from public.notifications
    where id = 'e2000000-0000-4000-8000-000000000602'
  ),
  'memory, insight, event, and notification dependencies close transitively'
);

select ok(
  (
    select id = 'e2000000-0000-4000-8000-000000000531'
      and period_key = '2026-W27'
      and week_start = '2026-06-29'::date
      and week_end = '2026-07-05'::date
      and source_fingerprint = repeat('d', 64)
      and source_observed_at = '2026-07-05T18:00:00Z'::timestamptz
      and generated_at = '2026-07-05T18:00:00Z'::timestamptz
      and created_at = '2026-07-05T18:01:00Z'::timestamptz
      and updated_at = '2026-07-05T18:02:00Z'::timestamptz
      and proposals = '[{
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
      }]'::jsonb
    from public.weekly_reviews
    where id = 'e2000000-0000-4000-8000-000000000531'
  ),
  'a clean review retains identity, period, fingerprint, timestamps, and historical proposals'
);

select ok(
  (
    select state = 'deleted'
      and context_parameters = '{}'::jsonb
      and response is null
      and used_context = '[]'::jsonb
      and evidence is null
      and agent_trace is null
      and tool_call_count is null
      and service_tier is null
      and deleted_at is not null
    from public.coach_requests
    where request_id = 'e2000000-0000-4000-8000-000000000801'
  ),
  'the V1 personal full-snapshot Coach turn is tombstoned and cleared'
);

select is_empty(
  $$
    select id from public.coach_messages
    where request_id = 'e2000000-0000-4000-8000-000000000801'
  $$,
  'messages belonging to the full-snapshot Coach turn are removed'
);

select ok(
  (
    select state = 'completed'
      and context_version = 'personal-snapshot-v1'
      and evidence @> '[{"source":"tasks"}]'::jsonb
      and response is not null
      and agent_trace is not null
    from public.coach_requests
    where request_id = 'e2000000-0000-4000-8000-000000000802'
  )
  and (
    select count(*) = 2
    from public.coach_messages
    where request_id = 'e2000000-0000-4000-8000-000000000802'
  ),
  'the clean table-specific V1 Coach turn and its messages remain'
);

select ok(
  (
    select state = 'pending'
      and prompt_version = 'free-coach-agent-prompt-v3'
      and context_version = 'personal-snapshot-v2'
      and response is null
      and evidence is null
    from public.coach_requests
    where request_id = 'e2000000-0000-4000-8000-000000000803'
  ),
  'the current Goal-free V2 Coach turn remains'
);

select is(
  (
    select count(*)::int
    from public.coach_usage_events
    where request_id in (
      'e2000000-0000-4000-8000-000000000801',
      'e2000000-0000-4000-8000-000000000802'
    )
  ),
  2,
  'append-only usage survives for tombstoned and retained Coach turns'
);

select ok(
  not exists (
    select 1 from public.coach_messages
    where id = 'e2000000-0000-4000-8000-000000000811'
  )
  and exists (
    select 1 from public.coach_messages
    where id = 'e2000000-0000-4000-8000-000000000812'
      and content =
        'This ordinary goal sentence must remain in legacy history.'
  ),
  'requestless structured Goal metadata is removed while ordinary prose remains'
);

select is_empty(
  $$
    select review.id
    from public.weekly_reviews as review
    where not exists (
      select 1
      from public.user_state_snapshots as snapshot
      where snapshot.id::text = review.provenance ->> 'source_snapshot_id'
        and snapshot.user_id = review.user_id
        and snapshot.scope = 'weekly'
        and snapshot.period_key = review.period_key
    )
       or exists (
        select 1
        from jsonb_array_elements(review.evidence_refs) as evidence(value)
        where evidence.value ->> 'table' = 'decision_feedback'
          and not exists (
            select 1
            from public.decision_feedback as feedback
            where feedback.id::text = evidence.value ->> 'id'
              and feedback.user_id = review.user_id
          )
      )
  $$,
  'no Weekly Review retains a dangling snapshot or feedback reference'
);

select * from finish();
rollback;
