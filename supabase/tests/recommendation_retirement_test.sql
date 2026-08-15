begin;
select no_plan();

select hasnt_table(
  'public',
  'recommendations',
  'the generic Recommendation table is absent from final state'
);
select hasnt_table(
  'public',
  'decision_feedback',
  'the Decision Feedback table is absent from final state'
);
select hasnt_column(
  'public',
  'daily_briefings',
  'recommendation_ids',
  'Daily Briefing V2 has no Recommendation id transport'
);

select ok(
  to_regprocedure(
    'public.replace_current_recommendations_v2(uuid,jsonb,timestamp with time zone)'
  ) is null
    and to_regprocedure(
      'public.persist_weekly_review_v2(uuid,text,timestamp with time zone,jsonb)'
    ) is null,
  'retired Recommendation and Weekly V2 writer RPCs are absent'
);
select ok(
  to_regprocedure(
    'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)'
  ) is not null
    and to_regprocedure(
      'public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)'
    ) is not null,
  'Coach V7 and Weekly V3 are the installed writer contracts'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
    and not has_function_privilege(
      'authenticated',
      'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'EXECUTE'
    ),
  'Coach V7 is service-role-only'
);
select is_empty(
  $$
    select signature
    from unnest(array[
      'public.claim_coach_request_v3(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'public.claim_coach_request_v4(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'public.claim_coach_request_v5(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)'
    ]) as signature
    where has_function_privilege('service_role', signature, 'EXECUTE')
  $$,
  'obsolete free-agent Coach claim entrypoints are not executable'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.claim_coach_request_v1(uuid,uuid,text,text,date,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
    'EXECUTE'
  )
    and has_function_privilege(
      'service_role',
      'public.claim_coach_request_v2(uuid,uuid,text,text,jsonb,date,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'public.claim_coach_request_v1(uuid,uuid,text,text,date,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'public.claim_coach_request_v2(uuid,uuid,text,text,jsonb,date,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
      'EXECUTE'
    ),
  'controlled Coach V1 and longitudinal V2 remain backend-only writers'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)',
    'EXECUTE'
  )
    and not has_function_privilege(
      'authenticated',
      'public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)',
      'EXECUTE'
    ),
  'Weekly V3 is service-role-only'
);
select ok(
  has_function_privilege(
    'service_role',
    'private.references_retired_recommendation_v1(jsonb)',
    'EXECUTE'
  )
    and not has_function_privilege(
      'authenticated',
      'private.references_retired_recommendation_v1(jsonb)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'private.references_retired_recommendation_v1(jsonb)',
      'EXECUTE'
    )
    and to_regprocedure(
      'private.sanitize_retired_recommendation_v1(jsonb)'
    ) is null,
  'only the durable service-role validation guard survives transition'
);

select is(
  (
    select proconfig
    from pg_proc
    where oid =
      'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)'::regprocedure
  ),
  array['search_path=pg_catalog, pg_temp']::text[],
  'Coach V7 fixes its SECURITY DEFINER search path'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid =
      'public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)'::regprocedure
  ),
  array['search_path=pg_catalog, pg_temp']::text[],
  'Weekly V3 fixes its SECURITY DEFINER search path'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid =
      'public.create_generated_notification_v1(uuid,uuid,text,text,date,timestamp with time zone,text,text,text,text,text,text,text,text,text,timestamp with time zone)'::regprocedure
  ),
  array['search_path=pg_catalog, pg_temp']::text[],
  'the retained notification writer fixes its SECURITY DEFINER search path'
);
select ok(
  strpos(
    pg_get_functiondef(
      'public.create_generated_notification_v1(uuid,uuid,text,text,date,timestamp with time zone,text,text,text,text,text,text,text,text,text,timestamp with time zone)'::regprocedure
    ),
    '''daily_briefing'''
  ) = 0,
  'the current notification writer cannot generate from Daily Briefing'
);

select set_eq(
  $$
    select conname::text
    from pg_constraint
    where conrelid = 'public.daily_briefings'::regclass
      and conname in (
        'daily_briefings_metadata_object',
        'daily_briefings_v2_sources'
      )
  $$,
  array[
    'daily_briefings_metadata_object',
    'daily_briefings_v2_sources'
  ]::text[],
  'Daily Briefing V2 final-state guards are installed'
);
select set_eq(
  $$
    select conname::text
    from pg_constraint
    where conrelid = 'public.weekly_reviews'::regclass
      and conname in (
        'weekly_reviews_facts_object',
        'weekly_reviews_provenance_object',
        'weekly_reviews_retired_sources'
      )
  $$,
  array[
    'weekly_reviews_facts_object',
    'weekly_reviews_provenance_object',
    'weekly_reviews_retired_sources'
  ]::text[],
  'Weekly Review V3 final-state guards are installed'
);
select ok(
  (
    select pg_get_constraintdef(oid) like '%daily-briefing-v2%'
      and pg_get_constraintdef(oid) like '%deterministic-briefing-ranker-v3%'
    from pg_constraint
    where conrelid = 'public.daily_briefings'::regclass
      and conname = 'daily_briefings_metadata_object'
  ),
  'Daily Briefing metadata admits only the V2/ranker-V3 pair'
);
select ok(
  (
    select pg_get_constraintdef(oid) like '%weekly-review-v3%'
      and pg_get_constraintdef(oid) not like '%weekly-review-v2%'
    from pg_constraint
    where conrelid = 'public.weekly_reviews'::regclass
      and conname = 'weekly_reviews_provenance_object'
  ),
  'Weekly Review provenance admits only V3'
);
select ok(
  (
    select pg_get_constraintdef(oid) like '%controlled-coach-prompt-v2%'
      and pg_get_constraintdef(oid) like '%controlled-coach-prompt-v3%'
      and pg_get_constraintdef(oid) like '%free-coach-agent-prompt-v4%'
      and pg_get_constraintdef(oid) like '%personal-snapshot-v3%'
    from pg_constraint
    where conrelid = 'public.coach_requests'::regclass
      and conname = 'coach_requests_versions'
  ),
  'controlled Coach stays writable while free-agent turns use V4/V3'
);

select is(
  (
    select count(*)::bigint
    from pg_class
    where oid in (
      'public.coach_requests'::regclass,
      'public.daily_briefings'::regclass,
      'public.notifications'::regclass,
      'public.weekly_reviews'::regclass
    )
      and relrowsecurity
      and relforcerowsecurity
  ),
  4::bigint,
  'retirement preserves RLS and forced RLS on changed content tables'
);

select has_column(
  'public',
  'ai_insights',
  'recommendation',
  'the independent Insight recommendation field remains'
);
select has_table(
  'public',
  'skillset_profiles',
  'Skillset remains a separate product concept'
);
select ok(
  (
    select pg_get_constraintdef(oid) like '%''recommendation''%'
    from pg_constraint
    where conrelid = 'public.memory_entries'::regclass
      and conname = 'memory_entries_type_check'
  ),
  'the Recommendation memory discriminator remains supported'
);

select * from finish();
rollback;
