begin;

-- Goal retirement is deliberately structural. These helpers inspect JSON keys
-- and typed references only; prose containing words such as "goal" survives.
create or replace function private.remove_goal_keys_v1(payload jsonb)
returns jsonb
language plpgsql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
declare
  key text;
  value jsonb;
  result jsonb;
begin
  if payload is null then
    return null;
  end if;
  if jsonb_typeof(payload) = 'object' then
    result := '{}'::jsonb;
    for key, value in select * from jsonb_each(payload) loop
      if key = any(array[
        'goal', 'goals', 'goal_id', 'goal_ids', 'goal_key', 'goal_keys',
        'goal_linked', 'goal_linked_completed'
      ]) then
        continue;
      end if;
      result := result || jsonb_build_object(
        key,
        private.remove_goal_keys_v1(value)
      );
    end loop;
    return result;
  end if;
  if jsonb_typeof(payload) = 'array' then
    select coalesce(
      jsonb_agg(private.remove_goal_keys_v1(value) order by ordinal),
      '[]'::jsonb
    )
    into result
    from jsonb_array_elements(payload) with ordinality as item(value, ordinal);
    return result;
  end if;
  return payload;
end;
$$;

create or replace function private.references_goal_feature_v1(payload jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
declare
  key text;
  value jsonb;
begin
  if payload is null then
    return false;
  end if;
  if jsonb_typeof(payload) = 'object' then
    for key, value in select * from jsonb_each(payload) loop
      if key = any(array[
        'goal', 'goals', 'goal_id', 'goal_ids', 'goal_key', 'goal_keys',
        'goal_linked', 'goal_linked_completed'
      ]) then
        return true;
      end if;
      if key in ('table', 'source', 'source_kind')
         and jsonb_typeof(value) = 'string'
         and value #>> '{}' in ('goal', 'goals') then
        return true;
      end if;
      if key in ('type', 'target_type', 'target_kind', 'memory_type')
         and jsonb_typeof(value) = 'string'
         and value #>> '{}' = 'goal' then
        return true;
      end if;
      if private.references_goal_feature_v1(value) then
        return true;
      end if;
    end loop;
    return false;
  end if;
  if jsonb_typeof(payload) = 'array' then
    return exists (
      select 1
      from jsonb_array_elements(payload) as item(value)
      where private.references_goal_feature_v1(item.value)
    );
  end if;
  return false;
end;
$$;

revoke all on function private.remove_goal_keys_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.references_goal_feature_v1(jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.remove_goal_derived_history_v1()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $cleanup$
declare
  tombstone_at timestamptz := statement_timestamp();
begin
  create temporary table if not exists _goal_recommendations (
    id uuid primary key
  ) on commit drop;
  create temporary table if not exists _goal_snapshots (
    id uuid primary key
  ) on commit drop;
  create temporary table if not exists _goal_reviews (
    id uuid primary key
  ) on commit drop;
  create temporary table if not exists _goal_briefings (
    id uuid primary key
  ) on commit drop;
  create temporary table if not exists _goal_coach_requests (
    request_id uuid primary key
  ) on commit drop;

  truncate pg_temp._goal_recommendations;
  truncate pg_temp._goal_snapshots;
  truncate pg_temp._goal_reviews;
  truncate pg_temp._goal_briefings;
  truncate pg_temp._goal_coach_requests;

  -- Authoritative Setup and Task rows survive with only exact Goal keys gone.
  update public.intake_responses
  set responses = private.remove_goal_keys_v1(responses),
      metadata = private.remove_goal_keys_v1(metadata)
  where private.references_goal_feature_v1(responses)
     or private.references_goal_feature_v1(metadata);

  update public.tasks
  set metadata = private.remove_goal_keys_v1(metadata)
  where private.references_goal_feature_v1(metadata);

  -- Onboarding snapshots remain the authoritative Setup projection. Other
  -- projections are derived and are invalidated when they depend on Goals.
  update public.user_state_snapshots
  set summary = private.remove_goal_keys_v1(summary),
      signals = private.remove_goal_keys_v1(signals),
      metadata = private.remove_goal_keys_v1(metadata)
  where scope = 'onboarding'
    and (
      private.references_goal_feature_v1(summary)
      or private.references_goal_feature_v1(signals)
      or private.references_goal_feature_v1(metadata)
    );

  insert into pg_temp._goal_recommendations(id)
  select id
  from public.recommendations
  where private.references_goal_feature_v1(metadata)
  on conflict do nothing;

  insert into pg_temp._goal_snapshots(id)
  select id
  from public.user_state_snapshots
  where scope <> 'onboarding'
    and (
      private.references_goal_feature_v1(summary)
      or private.references_goal_feature_v1(signals)
      or private.references_goal_feature_v1(metadata)
    )
  on conflict do nothing;

  insert into pg_temp._goal_reviews(id)
  select id
  from public.weekly_reviews
  where private.references_goal_feature_v1(
          facts #- '{tasks,goal_linked_completed}'
        )
     or private.references_goal_feature_v1(proposals)
     or private.references_goal_feature_v1(evidence_refs)
     or private.references_goal_feature_v1(provenance)
     or coalesce(facts #>> '{tasks,goal_linked_completed}', '0') <> '0'
  on conflict do nothing;

  insert into pg_temp._goal_briefings(id)
  select briefing.id
  from public.daily_briefings as briefing
  where private.references_goal_feature_v1(briefing.primary_action)
     or private.references_goal_feature_v1(briefing.support_actions)
     or private.references_goal_feature_v1(briefing.evidence_refs)
     or private.references_goal_feature_v1(briefing.provenance)
     or private.references_goal_feature_v1(briefing.metadata)
     or exists (
       select 1
       from pg_temp._goal_recommendations as doomed
       where doomed.id = any(briefing.recommendation_ids)
     )
     or exists (
       select 1
       from jsonb_array_elements(
         case
           when jsonb_typeof(briefing.evidence_refs) = 'array'
             then briefing.evidence_refs
           else '[]'::jsonb
         end
       ) as evidence(value)
       join pg_temp._goal_snapshots as doomed
         on evidence.value ->> 'table' = 'user_state_snapshots'
        and evidence.value ->> 'id' = doomed.id::text
     )
  on conflict do nothing;

  -- Feedback tied to a doomed briefing or recommendation is derived history.
  delete from public.decision_feedback as feedback
  where private.references_goal_feature_v1(feedback.metadata)
     or exists (
       select 1 from pg_temp._goal_briefings as doomed
       where doomed.id = feedback.briefing_id
     )
     or exists (
       select 1 from pg_temp._goal_recommendations as doomed
       where doomed.id = feedback.recommendation_id
     );

  -- Generated notifications carry typed source_kind/source_id metadata. Their
  -- retry rows disappear through the established notification FK cascade.
  delete from public.notifications as notification
  where private.references_goal_feature_v1(notification.metadata)
     or exists (
       select 1 from pg_temp._goal_briefings as doomed
       where notification.metadata ->> 'source_kind' = 'daily_briefing'
         and notification.metadata ->> 'source_id' = doomed.id::text
     )
     or exists (
       select 1 from pg_temp._goal_snapshots as doomed
       where notification.metadata ->> 'source_kind' = 'daily_state'
         and notification.metadata ->> 'source_id' = doomed.id::text
     )
     or exists (
       select 1 from pg_temp._goal_reviews as doomed
       where notification.metadata ->> 'source_kind' = 'weekly_review'
         and notification.metadata ->> 'source_id' = doomed.id::text
     );

  delete from public.daily_briefings as briefing
  where exists (
    select 1 from pg_temp._goal_briefings as doomed
    where doomed.id = briefing.id
  );
  delete from public.weekly_reviews as review
  where exists (
    select 1 from pg_temp._goal_reviews as doomed
    where doomed.id = review.id
  );
  delete from public.recommendations as recommendation
  where exists (
    select 1 from pg_temp._goal_recommendations as doomed
    where doomed.id = recommendation.id
  );
  delete from public.user_state_snapshots as snapshot
  where exists (
    select 1 from pg_temp._goal_snapshots as doomed
    where doomed.id = snapshot.id
  );

  delete from public.ai_insights
  where private.references_goal_feature_v1(metadata);
  delete from public.behavioral_events
  where private.references_goal_feature_v1(metadata)
     or event_type in (
       'goal_created', 'goal_updated', 'goal_completed', 'goal_archived'
     );

  insert into pg_temp._goal_coach_requests(request_id)
  select request_id
  from public.coach_requests
  where private.references_goal_feature_v1(response)
     or private.references_goal_feature_v1(used_context)
     or private.references_goal_feature_v1(evidence)
     or private.references_goal_feature_v1(agent_trace)
  union
  select request_id
  from public.coach_messages
  where request_id is not null
    and private.references_goal_feature_v1(metadata)
  on conflict do nothing;

  delete from public.coach_messages as message
  where exists (
    select 1 from pg_temp._goal_coach_requests as doomed
    where doomed.request_id = message.request_id
  );

  update public.coach_requests as request
  set state = 'deleted',
      message_fingerprint = null,
      lease_expires_at = null,
      response = null,
      used_context = '[]'::jsonb,
      error = null,
      evidence = null,
      agent_trace = null,
      tool_call_count = null,
      service_tier = null,
      completed_at = null,
      failed_at = null,
      deleted_at = greatest(request.created_at, tombstone_at),
      updated_at = greatest(request.created_at, tombstone_at)
  where exists (
    select 1 from pg_temp._goal_coach_requests as doomed
    where doomed.request_id = request.request_id
  );

  -- Goal memories are deleted by their typed discriminator. The owner-only
  -- selection projection follows via its existing ON DELETE CASCADE FK.
  delete from public.memory_entries where type = 'goal';
end;
$cleanup$;

revoke all on function private.remove_goal_derived_history_v1()
  from public, anon, authenticated, service_role;

select private.remove_goal_derived_history_v1();

-- Surviving reviews keep identity, timestamps, period, fingerprint, and any
-- historical proposal array. Their visible narrative and provenance become V2.
alter table public.weekly_reviews
  drop constraint weekly_reviews_provenance_object,
  drop constraint weekly_reviews_facts_object;

update public.weekly_reviews
set facts = jsonb_set(
      facts,
      '{tasks}',
      coalesce(facts -> 'tasks', '{}'::jsonb) - 'goal_linked_completed',
      true
    ),
    narrative = format(
      'This week records %s completed and %s still-open tasks, %s completed and %s intentionally skipped habit outcomes, and %s observed recovery days.',
      coalesce(facts #>> '{tasks,completed}', '0'),
      coalesce(facts #>> '{tasks,carried}', '0'),
      coalesce(facts #>> '{habits,completed}', '0'),
      coalesce(facts #>> '{habits,skipped}', '0'),
      coalesce(facts #>> '{recovery,recovery_days}', '0')
    ),
    provenance = jsonb_set(
      provenance,
      '{contract_version}',
      '"weekly-review-v2"'::jsonb,
      true
    );

alter table public.weekly_reviews
  add constraint weekly_reviews_facts_object check (
    jsonb_typeof(facts) = 'object'
    and octet_length(facts::text) <= 65536
    and not coalesce(
      (facts #> '{tasks}') ? 'goal_linked_completed',
      false
    )
  ),
  add constraint weekly_reviews_provenance_object check (
    jsonb_typeof(provenance) = 'object'
    and octet_length(provenance::text) <= 32768
    and provenance @> '{
      "engine": "deterministic",
      "contract_version": "weekly-review-v2",
      "baseline": "none",
      "llm_used": false
    }'::jsonb
    and provenance ?& array[
      'source_snapshot_id',
      'source_snapshot_generated_at',
      'evidence_window',
      'source_fingerprint',
      'limitations'
    ]
    and jsonb_typeof(provenance -> 'evidence_window') = 'object'
    and provenance #>> '{evidence_window,starts_on}' = week_start::text
    and provenance #>> '{evidence_window,ends_on}' = week_end::text
    and provenance #>> '{evidence_window,days}' = '7'
    and jsonb_typeof(provenance -> 'limitations') = 'array'
    and provenance ->> 'source_fingerprint' = source_fingerprint
  );

alter table public.memory_entries
  drop constraint if exists memory_entries_type_check,
  add constraint memory_entries_type_check check (
    type in (
      'pattern',
      'preference',
      'habit',
      'recurring_problem',
      'recommendation'
    )
  );

-- The existing persistence identity remains V2, but every successful insert or
-- refresh now stores an empty proposal array.
create or replace function public.persist_weekly_review_v2(
  p_user_id uuid,
  p_period_key text,
  p_source_observed_at timestamptz,
  p_row jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  stored public.weekly_reviews%rowtype;
  source_snapshot public.user_state_snapshots%rowtype;
  source_snapshot_id uuid;
  candidate_generated_at timestamptz;
  candidate_fingerprint text;
begin
  source_snapshot_id :=
    nullif(p_row #>> '{provenance,source_snapshot_id}', '')::uuid;
  candidate_generated_at := (p_row ->> 'generated_at')::timestamptz;
  candidate_fingerprint := p_row ->> 'source_fingerprint';
  if p_user_id is null
     or p_period_key !~ '^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$'
     or p_source_observed_at is null
     or jsonb_typeof(p_row) <> 'object'
     or p_row ->> 'user_id' is distinct from p_user_id::text
     or p_row ->> 'period_key' is distinct from p_period_key
     or jsonb_typeof(p_row -> 'facts') <> 'object'
     or coalesce(
          (p_row #> '{facts,tasks}') ? 'goal_linked_completed',
          false
        )
     or jsonb_typeof(p_row -> 'proposals') <> 'array'
     or p_row -> 'proposals' <> '[]'::jsonb
     or jsonb_typeof(p_row -> 'evidence_refs') <> 'array'
     or jsonb_typeof(p_row -> 'provenance') <> 'object'
     or p_row #>> '{provenance,contract_version}'
          is distinct from 'weekly-review-v2'
     or candidate_fingerprint !~ '^[0-9a-f]{64}$'
     or p_row #>> '{provenance,source_fingerprint}'
          is distinct from candidate_fingerprint
     or candidate_generated_at < p_source_observed_at then
    raise exception 'Weekly review persistence payload is invalid.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select *
  into source_snapshot
  from public.user_state_snapshots
  where id = source_snapshot_id
    and user_id = p_user_id
    and scope = 'weekly'
    and period_key = p_period_key
  for update;
  if not found
     or source_snapshot.source_observed_at > p_source_observed_at
     or source_snapshot.generated_at is distinct from
       (p_row #>> '{provenance,source_snapshot_generated_at}')::timestamptz then
    raise exception 'Weekly snapshot changed. Generate the review again.'
      using errcode = 'PT409';
  end if;

  insert into public.weekly_reviews (
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
    p_user_id,
    p_period_key,
    (p_row ->> 'week_start')::date,
    (p_row ->> 'week_end')::date,
    p_row ->> 'timezone',
    p_row ->> 'data_quality',
    p_row ->> 'narrative',
    p_row -> 'facts',
    '[]'::jsonb,
    p_row -> 'evidence_refs',
    p_row -> 'provenance',
    candidate_fingerprint,
    p_source_observed_at,
    candidate_generated_at,
    coalesce(
      nullif(p_row ->> 'created_at', '')::timestamptz,
      candidate_generated_at
    ),
    (p_row ->> 'updated_at')::timestamptz
  )
  on conflict (user_id, period_key) do update
  set week_start = excluded.week_start,
      week_end = excluded.week_end,
      timezone = excluded.timezone,
      data_quality = excluded.data_quality,
      narrative = excluded.narrative,
      facts = excluded.facts,
      proposals = '[]'::jsonb,
      evidence_refs = excluded.evidence_refs,
      provenance = excluded.provenance,
      source_fingerprint = excluded.source_fingerprint,
      source_observed_at = excluded.source_observed_at,
      generated_at = excluded.generated_at,
      updated_at = excluded.updated_at
  where excluded.source_observed_at >= public.weekly_reviews.source_observed_at
  returning * into stored;

  if not found then
    select *
    into stored
    from public.weekly_reviews
    where user_id = p_user_id and period_key = p_period_key;
  end if;
  if not found then
    raise exception 'Weekly review persistence returned no row.'
      using errcode = 'PT502';
  end if;
  return to_jsonb(stored);
end;
$$;

revoke all on function public.persist_weekly_review_v2(
  uuid, text, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.persist_weekly_review_v2(
  uuid, text, timestamptz, jsonb
) to service_role;

-- Existing terminal Coach rows remain readable. New turns use the paired V3
-- prompt and V2 snapshot, and legacy Goal-bearing turns were tombstoned above.
alter table public.coach_requests
  drop constraint coach_requests_versions,
  add constraint coach_requests_versions check (
    (
      contract_version = 'coach-request-v1'
      and (
        (
          prompt_version = 'controlled-coach-prompt-v1'
          and context_version = 'coach-context-v1'
        )
        or (
          prompt_version = 'controlled-coach-prompt-v2'
          and context_version = 'coach-context-v2'
        )
      )
    )
    or (
      contract_version = 'coach-request-v2'
      and prompt_version = 'controlled-coach-prompt-v3'
      and context_version = 'coach-context-v3'
    )
    or (
      contract_version = 'coach-request-v3'
      and (
        (
          prompt_version in (
            'free-coach-agent-prompt-v1',
            'free-coach-agent-prompt-v2'
          )
          and context_version = 'personal-snapshot-v1'
        )
        or (
          prompt_version = 'free-coach-agent-prompt-v3'
          and context_version = 'personal-snapshot-v2'
        )
      )
    )
  );

alter function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  rename to coach_response_is_valid_before_goal_retirement_v2;

create or replace function private.coach_response_is_valid_v2(
  p_value jsonb,
  p_request_id uuid,
  p_evidence jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  prompt_version text;
  context_version text;
  normalized jsonb;
begin
  prompt_version := p_value #>> '{provenance,prompt_version}';
  context_version := p_value #>> '{provenance,context_version}';
  if (
    prompt_version in (
      'free-coach-agent-prompt-v1',
      'free-coach-agent-prompt-v2'
    )
    and context_version = 'personal-snapshot-v1'
  ) then
    return private.coach_response_is_valid_before_goal_retirement_v2(
      p_value,
      p_request_id,
      p_evidence
    );
  end if;
  if prompt_version <> 'free-coach-agent-prompt-v3'
     or context_version <> 'personal-snapshot-v2' then
    return false;
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) as item(value)
    where item.value ->> 'source' in ('goal', 'goals')
  ) then
    return false;
  end if;
  normalized := jsonb_set(
    jsonb_set(
      p_value,
      '{provenance,prompt_version}',
      '"free-coach-agent-prompt-v2"'::jsonb,
      false
    ),
    '{provenance,context_version}',
    '"personal-snapshot-v1"'::jsonb,
    false
  );
  return private.coach_response_is_valid_before_goal_retirement_v2(
    normalized,
    p_request_id,
    p_evidence
  );
exception
  when others then
    return false;
end;
$$;

create or replace function private.coach_response_is_valid_v1(
  p_value jsonb,
  p_request_id uuid,
  p_used_context jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
begin
  if p_value ->> 'contract_version' = 'coach-response-v2' then
    return private.coach_response_is_valid_v2(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;
  return private.coach_response_is_valid_before_free_agent(
    p_value,
    p_request_id,
    p_used_context
  );
exception
  when others then
    return false;
end;
$$;

create or replace function private.coach_used_context_is_valid_v1(
  p_value jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  item jsonb;
  available_count numeric;
  included_count numeric;
  omitted_count numeric;
begin
  if jsonb_typeof(p_value) <> 'array'
     or jsonb_array_length(p_value) > 10
     or octet_length(p_value::text) > 32768 then
    return false;
  end if;
  for item in select value from jsonb_array_elements(p_value) loop
    if not private.coach_jsonb_has_exact_keys(
      item,
      array[
        'source',
        'available_count',
        'included_count',
        'omitted_count',
        'freshness'
      ]
    )
       or jsonb_typeof(item -> 'source') <> 'string'
       or item ->> 'source' not in (
         'profile',
         'daily_snapshot',
         'daily_briefing',
         'tasks',
         'habits',
         'focus_sessions',
         'weekly_review',
         'memories',
         'coach_history',
         'daily_capture',
         'focus_reflections',
         'habit_outcomes',
         'decision_feedback',
         'weekly_reviews',
         'task_lifecycle'
       )
       or jsonb_typeof(item -> 'available_count') <> 'number'
       or jsonb_typeof(item -> 'included_count') <> 'number'
       or jsonb_typeof(item -> 'omitted_count') <> 'number'
       or jsonb_typeof(item -> 'freshness') <> 'string'
       or item ->> 'freshness' not in (
         'current', 'stale', 'missing', 'not_applicable'
       ) then
      return false;
    end if;
    available_count := (item ->> 'available_count')::numeric;
    included_count := (item ->> 'included_count')::numeric;
    omitted_count := (item ->> 'omitted_count')::numeric;
    if available_count < 0
       or included_count < 0
       or omitted_count < 0
       or trunc(available_count) <> available_count
       or trunc(included_count) <> included_count
       or trunc(omitted_count) <> omitted_count
       or included_count + omitted_count <> available_count then
      return false;
    end if;
  end loop;
  return true;
exception
  when others then
    return false;
end;
$$;

create or replace function public.claim_coach_request_v5(
  p_user_id uuid,
  p_request_id uuid,
  p_message_fingerprint text,
  p_local_date date,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_claimed_at timestamptz,
  p_lease_expires_at timestamptz,
  p_daily_limit int
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
begin
  -- Start from the original idempotent claim body so a retried V3 request may
  -- already carry any earlier free-agent prompt pair. Normalize every pending
  -- pair to the current Goal-free pair in the same transaction.
  result := public.claim_coach_request_v3(
    p_user_id,
    p_request_id,
    p_message_fingerprint,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit
  );
  if result ->> 'state' = 'pending' then
    update public.coach_requests
    set prompt_version = 'free-coach-agent-prompt-v3',
        context_version = 'personal-snapshot-v2'
    where request_id = p_request_id
      and user_id = p_user_id
      and contract_version = 'coach-request-v3'
      and (
        (
          prompt_version in (
            'free-coach-agent-prompt-v1',
            'free-coach-agent-prompt-v2'
          )
          and context_version = 'personal-snapshot-v1'
        )
        or (
          prompt_version = 'free-coach-agent-prompt-v3'
          and context_version = 'personal-snapshot-v2'
        )
      )
      and state = 'pending';
    if not found then
      raise exception 'Coach V5 contract transition failed'
        using errcode = 'PT409';
    end if;
  end if;
  return result;
end;
$$;

revoke all on function private.coach_response_is_valid_before_goal_retirement_v2(
  jsonb, uuid, jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_used_context_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_coach_request_v5(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
revoke all on function public.claim_coach_request_v4(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
revoke all on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;

grant execute on function private.coach_response_is_valid_before_goal_retirement_v2(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_v2(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_used_context_is_valid_v1(jsonb)
  to service_role;
grant execute on function public.claim_coach_request_v5(
  uuid, uuid, text, date, text, text, text, text, timestamptz, timestamptz, int
) to service_role;

-- Replace the layered Setup adapters with one Goal-free, service-role-only RPC.
drop function public.apply_intake_v1_setup_revision(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
);
drop function public.apply_intake_v1_setup_revision_without_study_setup(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
);
drop function public.apply_intake_v1_setup_revision_with_retired_fields(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
);

drop trigger if exists notification_preferences_intake_retired_write_guard_v1
  on public.notification_preferences;
drop function if exists public.suppress_retired_intake_notification_write_v1();
drop function if exists private.retire_setup_goals_and_friction_v1();
drop function if exists private.references_retired_personalization_v1(jsonb);

create or replace function public.apply_intake_v1_setup_revision(
  p_user_id uuid,
  p_intake_response_id uuid,
  p_request_id uuid,
  p_base_revision int,
  p_revision int,
  p_completed_at timestamptz,
  p_notification_preferences jsonb,
  p_habits jsonb,
  p_schedule_items jsonb,
  p_memory_entries jsonb,
  p_snapshot jsonb,
  p_intake_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $apply$
declare
  target_intake public.intake_responses%rowtype;
  canonical_row public.intake_responses%rowtype;
  latest_intake_id uuid;
  latest_applied_id uuid;
  snapshot_id uuid;
  current_profile_revision int;
  affected_count int;
  desired_count int;
  profile_repaired boolean := false;
  result jsonb;
  study jsonb;
  focus jsonb;
  semesters jsonb;
  current_study_revision int;
begin
  <<core_apply>>
  begin
    -- The established owner lock, revision identity, and replay semantics stay
    -- unchanged even though one materialization family is gone.
    perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

    select *
    into target_intake
    from public.intake_responses
    where id = p_intake_response_id
      and user_id = p_user_id
      and version = 'intake-v1'
      and request_id = p_request_id
    for update;

    if not found then
      raise exception 'Intake V1 setup revision not found'
        using errcode = '22023';
    end if;
    if target_intake.responses ? 'goals' then
      raise exception 'Intake V1 goals are no longer supported'
        using errcode = '22023';
    end if;
    if target_intake.base_revision <> p_base_revision
       or target_intake.revision <> p_revision then
      raise exception 'Intake V1 setup revision identity mismatch'
        using errcode = '22023';
    end if;

    if target_intake.state = 'applied' then
      select id
      into latest_applied_id
      from public.intake_responses
      where user_id = p_user_id
        and version = 'intake-v1'
        and state = 'applied'
      order by revision desc, updated_at desc, id desc
      limit 1;

      if latest_applied_id = target_intake.id then
        update public.profiles
        set display_name = case
              when target_intake.responses ? 'display_name'
                then target_intake.responses ->> 'display_name'
              else display_name
            end,
            onboarding_completed_at = target_intake.completed_at,
            updated_at = greatest(updated_at, target_intake.completed_at),
            setup_revision = target_intake.revision
        where id = p_user_id
          and setup_revision < target_intake.revision;
        get diagnostics affected_count = row_count;
        profile_repaired := affected_count = 1;
      end if;

      begin
        snapshot_id := nullif(target_intake.metadata ->> 'snapshot_id', '')::uuid;
      exception
        when invalid_text_representation then
          snapshot_id := null;
      end;
      if snapshot_id is null then
        select id
        into snapshot_id
        from public.user_state_snapshots
        where user_id = p_user_id
          and scope = 'onboarding'
          and period_key = 'setup:intake-v1'
        limit 1;
      end if;
      result := jsonb_build_object(
        'intake_response_id', target_intake.id,
        'request_id', target_intake.request_id,
        'base_revision', target_intake.base_revision,
        'revision', target_intake.revision,
        'state', target_intake.state,
        'completed_at', target_intake.completed_at,
        'snapshot_id', snapshot_id,
        'profile_repaired', profile_repaired
      );
      exit core_apply;
    end if;

    select id
    into latest_intake_id
    from public.intake_responses
    where user_id = p_user_id
      and version = 'intake-v1'
    order by revision desc, updated_at desc, id desc
    limit 1
    for update;

    if latest_intake_id is distinct from target_intake.id then
      raise exception 'Intake V1 setup revision is no longer current'
        using errcode = '40001';
    end if;
    if target_intake.state <> 'pending' then
      raise exception 'Intake V1 setup revision has invalid state'
        using errcode = '22023';
    end if;
    if p_completed_at is null then
      raise exception 'Setup completion time is required'
        using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(p_notification_preferences, '{}'::jsonb))
         <> 'object'
       or jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(p_intake_metadata, '{}'::jsonb)) <> 'object' then
      raise exception 'Setup objects must be JSON objects'
        using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(p_habits, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_schedule_items, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_memory_entries, '[]'::jsonb)) <> 'array' then
      raise exception 'Setup materializations must be JSON arrays'
        using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(p_snapshot -> 'summary', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(p_snapshot -> 'signals', '{}'::jsonb)) <> 'object'
       or jsonb_typeof(coalesce(p_snapshot -> 'metadata', '{}'::jsonb)) <> 'object'
    then
      raise exception 'Setup snapshot payload is invalid'
        using errcode = '22023';
    end if;

    -- Notification settings remain independently owned. The parameter stays in
    -- the internal ABI for this focused contract change but is never written.
    perform p_notification_preferences;

    if exists (
      select 1
      from (
        select value as item
        from jsonb_array_elements(coalesce(p_habits, '[]'::jsonb))
        union all
        select value
        from jsonb_array_elements(coalesce(p_schedule_items, '[]'::jsonb))
        union all
        select value
        from jsonb_array_elements(coalesce(p_memory_entries, '[]'::jsonb))
      ) as desired
      where jsonb_typeof(desired.item) <> 'object'
         or coalesce(desired.item -> 'metadata' ->> 'managed_by', '') <> 'setup'
         or coalesce(desired.item -> 'metadata' ->> 'source', '') <> 'intake-v1'
         or coalesce(desired.item -> 'metadata' ->> 'revision', '')
              <> p_revision::text
         or coalesce(desired.item -> 'metadata' ->> 'setup_item_id', '') = ''
    ) then
      raise exception 'Setup materialization ownership metadata is invalid'
        using errcode = '22023';
    end if;

    select setup_revision
    into current_profile_revision
    from public.profiles
    where id = p_user_id
    for update;
    if not found then
      raise exception 'Authenticated profile does not exist'
        using errcode = '23503';
    end if;
    if current_profile_revision >= p_revision then
      raise exception 'Profile already projects this or a newer Setup revision'
        using errcode = '40001';
    end if;

    if exists (
      select 1
      from public.habits as existing
      join jsonb_array_elements(coalesce(p_habits, '[]'::jsonb)) as desired
        on existing.id = (desired ->> 'id')::uuid
      where existing.user_id <> p_user_id
         or not (
           existing.metadata ->> 'managed_by' = 'setup'
           or existing.metadata ->> 'source' = 'intake-v1'
         )
    ) then
      raise exception 'Setup habit id collides with a non-Setup row'
        using errcode = '23505';
    end if;
    if exists (
      select 1
      from public.schedule_items as existing
      join jsonb_array_elements(coalesce(p_schedule_items, '[]'::jsonb)) as desired
        on existing.id = (desired ->> 'id')::uuid
      where existing.user_id <> p_user_id
         or not (
           existing.metadata ->> 'managed_by' = 'setup'
           or existing.metadata ->> 'source' = 'intake-v1'
         )
    ) then
      raise exception 'Setup schedule id collides with a non-Setup row'
        using errcode = '23505';
    end if;
    if exists (
      select 1
      from public.memory_entries as existing
      join jsonb_array_elements(coalesce(p_memory_entries, '[]'::jsonb)) as desired
        on existing.id = (desired ->> 'id')::uuid
      where existing.user_id <> p_user_id
         or not (
           existing.metadata ->> 'managed_by' = 'setup'
           or existing.metadata ->> 'source' = 'intake-v1'
         )
    ) then
      raise exception 'Setup memory id collides with a non-Setup row'
        using errcode = '23505';
    end if;

    insert into public.habits as target (
      id, user_id, title, frequency, target, active, metadata, updated_at
    )
    select
      desired.id,
      p_user_id,
      desired.title,
      desired.frequency,
      desired.target,
      desired.active,
      desired.metadata,
      p_completed_at
    from jsonb_to_recordset(coalesce(p_habits, '[]'::jsonb)) as desired(
      id uuid,
      title text,
      frequency text,
      target int,
      active boolean,
      metadata jsonb
    )
    on conflict (id) do update set
      title = excluded.title,
      frequency = excluded.frequency,
      target = excluded.target,
      active = excluded.active,
      metadata = excluded.metadata,
      updated_at = excluded.updated_at
    where target.user_id = p_user_id
      and (
        target.metadata ->> 'managed_by' = 'setup'
        or target.metadata ->> 'source' = 'intake-v1'
      );
    get diagnostics affected_count = row_count;
    desired_count := jsonb_array_length(coalesce(p_habits, '[]'::jsonb));
    if affected_count <> desired_count then
      raise exception 'Setup habit id collides with a non-Setup row'
        using errcode = '23505';
    end if;

    update public.habits as existing
    set active = false,
        metadata = existing.metadata || jsonb_build_object(
          'source', 'intake-v1',
          'managed_by', 'setup',
          'setup_item_id', coalesce(
            existing.metadata ->> 'setup_item_id',
            existing.id::text
          ),
          'revision', p_revision,
          'setup_state', 'archived'
        ),
        updated_at = p_completed_at
    where existing.user_id = p_user_id
      and (
        existing.metadata ->> 'managed_by' = 'setup'
        or existing.metadata ->> 'source' = 'intake-v1'
      )
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(p_habits, '[]'::jsonb)) as desired
        where (desired ->> 'id')::uuid = existing.id
      );

    insert into public.schedule_items as target (
      id, user_id, title, location, weekday, starts_at, ends_at,
      source, metadata, updated_at
    )
    select
      desired.id,
      p_user_id,
      desired.title,
      desired.location,
      desired.weekday,
      desired.starts_at,
      desired.ends_at,
      'onboarding',
      desired.metadata,
      p_completed_at
    from jsonb_to_recordset(coalesce(p_schedule_items, '[]'::jsonb)) as desired(
      id uuid,
      title text,
      location text,
      weekday int,
      starts_at time,
      ends_at time,
      metadata jsonb
    )
    on conflict (id) do update set
      title = excluded.title,
      location = excluded.location,
      weekday = excluded.weekday,
      starts_at = excluded.starts_at,
      ends_at = excluded.ends_at,
      source = excluded.source,
      metadata = excluded.metadata,
      updated_at = excluded.updated_at
    where target.user_id = p_user_id
      and (
        target.metadata ->> 'managed_by' = 'setup'
        or target.metadata ->> 'source' = 'intake-v1'
      );
    get diagnostics affected_count = row_count;
    desired_count := jsonb_array_length(coalesce(p_schedule_items, '[]'::jsonb));
    if affected_count <> desired_count then
      raise exception 'Setup schedule id collides with a non-Setup row'
        using errcode = '23505';
    end if;

    delete from public.schedule_items as existing
    where existing.user_id = p_user_id
      and (
        existing.metadata ->> 'managed_by' = 'setup'
        or existing.metadata ->> 'source' = 'intake-v1'
        or (
          existing.source = 'onboarding'
          and existing.metadata = '{}'::jsonb
          and existing.title = 'Math'
          and existing.location = 'Room 204'
          and existing.weekday = 1
          and existing.starts_at = '08:15'::time
          and existing.ends_at = '09:45'::time
          and existing.notes is null
        )
      )
      and not exists (
        select 1
        from jsonb_array_elements(
          coalesce(p_schedule_items, '[]'::jsonb)
        ) as desired
        where (desired ->> 'id')::uuid = existing.id
      );

    insert into public.memory_entries as target (
      id, user_id, type, title, content, strength, evidence, metadata,
      last_seen_at, updated_at
    )
    select
      desired.id,
      p_user_id,
      desired.type,
      desired.title,
      desired.content,
      desired.strength,
      desired.evidence,
      desired.metadata,
      p_completed_at,
      p_completed_at
    from jsonb_to_recordset(
      coalesce(p_memory_entries, '[]'::jsonb)
    ) as desired(
      id uuid,
      type text,
      title text,
      content text,
      strength numeric,
      evidence jsonb,
      metadata jsonb
    )
    on conflict (id) do update set
      type = excluded.type,
      title = excluded.title,
      content = excluded.content,
      strength = excluded.strength,
      evidence = excluded.evidence,
      metadata = excluded.metadata,
      last_seen_at = excluded.last_seen_at,
      updated_at = excluded.updated_at
    where target.user_id = p_user_id
      and (
        target.metadata ->> 'managed_by' = 'setup'
        or target.metadata ->> 'source' = 'intake-v1'
      );
    get diagnostics affected_count = row_count;
    desired_count := jsonb_array_length(coalesce(p_memory_entries, '[]'::jsonb));
    if affected_count <> desired_count then
      raise exception 'Setup memory id collides with a non-Setup row'
        using errcode = '23505';
    end if;

    delete from public.memory_entries as existing
    where existing.user_id = p_user_id
      and (
        existing.metadata ->> 'managed_by' = 'setup'
        or existing.metadata ->> 'source' = 'intake-v1'
      )
      and not exists (
        select 1
        from jsonb_array_elements(
          coalesce(p_memory_entries, '[]'::jsonb)
        ) as desired
        where (desired ->> 'id')::uuid = existing.id
      );

    insert into public.user_state_snapshots (
      user_id, scope, period_key, summary, signals, source, generated_at, metadata
    ) values (
      p_user_id,
      'onboarding',
      'setup:intake-v1',
      coalesce(p_snapshot -> 'summary', '{}'::jsonb),
      coalesce(p_snapshot -> 'signals', '{}'::jsonb),
      'backend',
      p_completed_at,
      coalesce(p_snapshot -> 'metadata', '{}'::jsonb)
    )
    on conflict (user_id, scope, period_key) do update set
      summary = excluded.summary,
      signals = excluded.signals,
      source = excluded.source,
      generated_at = excluded.generated_at,
      metadata = excluded.metadata
    returning id into snapshot_id;

    update public.intake_responses
    set state = 'applied',
        completed_at = p_completed_at,
        updated_at = p_completed_at,
        metadata = coalesce(p_intake_metadata, '{}'::jsonb)
          || jsonb_build_object('snapshot_id', snapshot_id::text)
    where id = target_intake.id
      and user_id = p_user_id
      and version = 'intake-v1'
      and state = 'pending';
    get diagnostics affected_count = row_count;
    if affected_count <> 1 then
      raise exception 'Intake V1 setup revision changed during apply'
        using errcode = '40001';
    end if;

    update public.profiles
    set display_name = case
          when target_intake.responses ? 'display_name'
            then target_intake.responses ->> 'display_name'
          else display_name
        end,
        onboarding_completed_at = p_completed_at,
        updated_at = p_completed_at,
        setup_revision = p_revision
    where id = p_user_id
      and setup_revision < p_revision;
    get diagnostics affected_count = row_count;
    if affected_count <> 1 then
      raise exception 'Profile Setup projection did not advance'
        using errcode = '40001';
    end if;

    result := jsonb_build_object(
      'intake_response_id', target_intake.id,
      'request_id', target_intake.request_id,
      'base_revision', target_intake.base_revision,
      'revision', target_intake.revision,
      'state', 'applied',
      'completed_at', p_completed_at,
      'snapshot_id', snapshot_id,
      'profile_repaired', false
    );
  end core_apply;

  -- Study Setup remains an atomic projection of the canonical applied Intake.
  select value.*
  into canonical_row
  from public.intake_responses as value
  where value.id = p_intake_response_id
    and value.user_id = p_user_id
    and value.request_id = p_request_id
    and value.revision = p_revision
    and value.state = 'applied'
    and not exists (
      select 1
      from public.intake_responses as newer
      where newer.user_id = value.user_id
        and newer.version = 'intake-v1'
        and newer.state = 'applied'
        and newer.revision > value.revision
    );
  if not found then
    return result;
  end if;

  study := canonical_row.responses -> 'study_setup';
  if study is null then
    delete from public.study_setup_profiles
    where user_id = p_user_id and setup_revision <= p_revision;
  else
    if jsonb_typeof(study) <> 'object'
       or study - array['focus_rhythm', 'semester_planning'] <> '{}'::jsonb
       or not (study ? 'focus_rhythm' or study ? 'semester_planning') then
      raise exception 'Canonical Study Setup shape is invalid.'
        using errcode = '22023';
    end if;
    focus := study -> 'focus_rhythm';
    semesters := study -> 'semester_planning';
    if focus is not null and (
      jsonb_typeof(focus) <> 'object'
      or not (
        focus ?& array[
          'focus_minutes', 'recovery_minutes', 'preparation_items'
        ]
      )
      or focus - array[
        'focus_minutes', 'recovery_minutes', 'preparation_items'
      ] <> '{}'::jsonb
    ) then
      raise exception 'Canonical Study Focus shape is invalid.'
        using errcode = '22023';
    end if;
    if semesters is not null and (
      jsonb_typeof(semesters) <> 'object'
      or not (semesters ?& array['current_semester', 'next_semester'])
      or semesters - array[
        'current_semester', 'next_semester'
      ] <> '{}'::jsonb
    ) then
      raise exception 'Canonical Study Semester shape is invalid.'
        using errcode = '22023';
    end if;

    insert into public.study_setup_profiles (
      user_id,
      focus_minutes,
      recovery_minutes,
      preparation_items,
      current_semester,
      next_semester,
      setup_revision,
      created_at,
      updated_at
    ) values (
      p_user_id,
      nullif(focus ->> 'focus_minutes', '')::int,
      nullif(focus ->> 'recovery_minutes', '')::int,
      coalesce(focus -> 'preparation_items', '[]'::jsonb),
      semesters -> 'current_semester',
      semesters -> 'next_semester',
      p_revision,
      canonical_row.completed_at,
      canonical_row.completed_at
    )
    on conflict (user_id) do update
    set focus_minutes = excluded.focus_minutes,
        recovery_minutes = excluded.recovery_minutes,
        preparation_items = excluded.preparation_items,
        current_semester = excluded.current_semester,
        next_semester = excluded.next_semester,
        setup_revision = excluded.setup_revision,
        updated_at = greatest(
          public.study_setup_profiles.updated_at,
          excluded.updated_at
        )
    where public.study_setup_profiles.setup_revision <= excluded.setup_revision;
  end if;

  select setup_revision
  into current_study_revision
  from public.study_setup_profiles
  where user_id = p_user_id;

  update public.planner_action_plans as plan
  set attention_reasons = (
        select array_agg(distinct reason order by reason)
        from unnest(
          plan.attention_reasons || array['study_rhythm_changed']::text[]
        ) as reasons(reason)
      ),
      updated_at = greatest(plan.updated_at, canonical_row.completed_at)
  from public.planner_action_plan_revisions as revision
  where plan.user_id = p_user_id
    and plan.id = revision.plan_id
    and revision.revision = plan.current_revision
    and revision.state = 'active'
    and revision.target_payload ->> 'kind' = 'task'
    and revision.target_payload ->> 'use_study_rhythm' = 'true'
    and revision.study_setup_revision is distinct from current_study_revision;

  return result;
end;
$apply$;

revoke all on function public.apply_intake_v1_setup_revision(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_intake_v1_setup_revision(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) to service_role;

-- No database object may retain a dependency on the compatibility table.
drop function private.remove_goal_derived_history_v1();
drop function private.references_goal_feature_v1(jsonb);
drop function private.remove_goal_keys_v1(jsonb);

delete from public.goals;
drop table public.goals;

commit;
