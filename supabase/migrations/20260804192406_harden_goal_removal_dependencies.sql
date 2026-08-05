begin;

set local lock_timeout = '5s';

-- The cleanup observes and changes a connected history graph. Acquire every
-- relevant table lock before reading the first row so a concurrent writer
-- either finishes first or makes this whole transaction fail without a
-- partial cleanup. The order is deliberately alphabetical.
lock table public.ai_insights in share row exclusive mode;
lock table public.behavioral_events in share row exclusive mode;
lock table public.coach_memory_selections in share row exclusive mode;
lock table public.coach_messages in share row exclusive mode;
lock table public.coach_requests in share row exclusive mode;
lock table public.coach_usage_events in share row exclusive mode;
lock table public.daily_briefings in share row exclusive mode;
lock table public.decision_feedback in share row exclusive mode;
lock table public.intake_responses in share row exclusive mode;
lock table public.memory_entries in share row exclusive mode;
lock table public.notification_action_requests in share row exclusive mode;
lock table public.notifications in share row exclusive mode;
lock table public.recommendations in share row exclusive mode;
lock table public.tasks in share row exclusive mode;
lock table public.user_state_snapshots in share row exclusive mode;
lock table public.weekly_reviews in share row exclusive mode;

-- Only values stored under an explicit field/path key are interpreted as
-- paths. Ordinary prose is never inspected for Goal words.
create or replace function private.goal_path_references_feature_v2(
  path_value text
)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
declare
  normalized text;
  segment text;
begin
  if path_value is null then
    return false;
  end if;
  normalized := translate(
    lower(path_value),
    '.[]/{}''"->#:',
    '............'
  );
  foreach segment in array regexp_split_to_array(normalized, '[.]+') loop
    if btrim(segment) = any(array[
      'goal', 'goals', 'goal_id', 'goal_ids', 'goal_key', 'goal_keys',
      'goal_linked', 'goal_linked_completed'
    ]) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

-- A typed reference object is removed as a unit by the sanitizer. Exact Goal
-- keys are handled separately so sibling non-Goal metadata survives.
create or replace function private.is_goal_reference_object_v2(payload jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
declare
  key text;
begin
  if jsonb_typeof(payload) <> 'object' then
    return false;
  end if;
  foreach key in array array['table', 'source', 'source_kind'] loop
    if jsonb_typeof(payload -> key) = 'string'
       and lower(payload ->> key) in ('goal', 'goals') then
      return true;
    end if;
  end loop;
  foreach key in array array[
    'type', 'target_type', 'target_kind', 'memory_type'
  ] loop
    if jsonb_typeof(payload -> key) = 'string'
       and lower(payload ->> key) in ('goal', 'goals') then
      return true;
    end if;
  end loop;
  foreach key in array array[
    'field', 'path', 'field_path', 'json_path', 'source_path', 'target_path'
  ] loop
    if jsonb_typeof(payload -> key) = 'string'
       and private.goal_path_references_feature_v2(payload ->> key) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

create or replace function private.references_goal_feature_v2(payload jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
declare
  key text;
  value jsonb;
  item jsonb;
begin
  if payload is null then
    return false;
  end if;
  if jsonb_typeof(payload) = 'object' then
    if private.is_goal_reference_object_v2(payload) then
      return true;
    end if;
    for key, value in select * from jsonb_each(payload) loop
      if key = any(array[
        'goal', 'goals', 'goal_id', 'goal_ids', 'goal_key', 'goal_keys',
        'goal_linked', 'goal_linked_completed'
      ]) then
        return true;
      end if;
      if key in ('tables', 'sources')
         and jsonb_typeof(value) = 'array' then
        for item in select item_value from jsonb_array_elements(value) item(item_value)
        loop
          if jsonb_typeof(item) = 'string'
             and lower(item #>> '{}') in ('goal', 'goals') then
            return true;
          end if;
        end loop;
      end if;
      if private.references_goal_feature_v2(value) then
        return true;
      end if;
    end loop;
    return false;
  end if;
  if jsonb_typeof(payload) = 'array' then
    return exists (
      select 1
      from jsonb_array_elements(payload) as item(item_value)
      where private.references_goal_feature_v2(item.item_value)
    );
  end if;
  return false;
end;
$$;

create or replace function private.sanitize_goal_feature_v2(payload jsonb)
returns jsonb
language plpgsql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
declare
  key text;
  value jsonb;
  item jsonb;
  cleaned jsonb;
  result jsonb;
begin
  if payload is null then
    return null;
  end if;
  if jsonb_typeof(payload) = 'object' then
    if private.is_goal_reference_object_v2(payload) then
      return null;
    end if;
    result := '{}'::jsonb;
    for key, value in select * from jsonb_each(payload) loop
      if key = any(array[
        'goal', 'goals', 'goal_id', 'goal_ids', 'goal_key', 'goal_keys',
        'goal_linked', 'goal_linked_completed'
      ]) then
        continue;
      end if;
      if key in ('tables', 'sources')
         and jsonb_typeof(value) = 'array' then
        cleaned := '[]'::jsonb;
        for item in select item_value from jsonb_array_elements(value) item(item_value)
        loop
          if jsonb_typeof(item) = 'string'
             and lower(item #>> '{}') in ('goal', 'goals') then
            continue;
          end if;
          item := private.sanitize_goal_feature_v2(item);
          if item is not null then
            cleaned := cleaned || jsonb_build_array(item);
          end if;
        end loop;
      else
        cleaned := private.sanitize_goal_feature_v2(value);
      end if;
      if cleaned is not null then
        result := result || jsonb_build_object(key, cleaned);
      end if;
    end loop;
    return result;
  end if;
  if jsonb_typeof(payload) = 'array' then
    result := '[]'::jsonb;
    for item in select item_value from jsonb_array_elements(payload) item(item_value)
    loop
      cleaned := private.sanitize_goal_feature_v2(item);
      if cleaned is not null then
        result := result || jsonb_build_array(cleaned);
      end if;
    end loop;
    return result;
  end if;
  return payload;
end;
$$;

revoke all on function private.goal_path_references_feature_v2(text)
  from public, anon, authenticated, service_role;
revoke all on function private.is_goal_reference_object_v2(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.references_goal_feature_v2(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.sanitize_goal_feature_v2(jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.remove_goal_derived_history_v2()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $cleanup$
declare
  tombstone_at timestamptz := statement_timestamp();
  added int;
  total_added int;
begin
  create temporary table _goal_recommendations (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_snapshots (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_briefings (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_feedback (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_reviews (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_memories (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_insights (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_events (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_notifications (
    id uuid primary key,
    user_id uuid not null
  ) on commit drop;
  create temporary table _goal_coach_requests (
    request_id uuid primary key,
    user_id uuid not null
  ) on commit drop;

  -- Authoritative input, Task, and onboarding projection rows are retained and
  -- cleaned structurally. A top-level typed Goal reference becomes an empty
  -- object so the existing JSON shape constraints remain valid.
  update public.intake_responses
  set responses = coalesce(
        private.sanitize_goal_feature_v2(responses),
        '{}'::jsonb
      ),
      metadata = coalesce(
        private.sanitize_goal_feature_v2(metadata),
        '{}'::jsonb
      )
  where private.references_goal_feature_v2(responses)
     or private.references_goal_feature_v2(metadata);

  update public.tasks
  set metadata = coalesce(
        private.sanitize_goal_feature_v2(metadata),
        '{}'::jsonb
      )
  where private.references_goal_feature_v2(metadata);

  update public.user_state_snapshots
  set summary = coalesce(
        private.sanitize_goal_feature_v2(summary),
        '{}'::jsonb
      ),
      signals = coalesce(
        private.sanitize_goal_feature_v2(signals),
        '{}'::jsonb
      ),
      metadata = coalesce(
        private.sanitize_goal_feature_v2(metadata),
        '{}'::jsonb
      )
  where scope = 'onboarding'
    and (
      private.references_goal_feature_v2(summary)
      or private.references_goal_feature_v2(signals)
      or private.references_goal_feature_v2(metadata)
    );

  if exists (
    select 1
    from public.intake_responses
    where private.references_goal_feature_v2(responses)
       or private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1
    from public.tasks
    where private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1
    from public.user_state_snapshots
    where scope = 'onboarding'
      and (
        private.references_goal_feature_v2(summary)
        or private.references_goal_feature_v2(signals)
        or private.references_goal_feature_v2(metadata)
      )
  ) then
    raise exception 'Goal cleanup left an authoritative structured reference.';
  end if;

  insert into pg_temp._goal_recommendations(id, user_id)
  select recommendation.id, recommendation.user_id
  from public.recommendations as recommendation
  where private.references_goal_feature_v2(recommendation.metadata)
     or exists (
       select 1
       from jsonb_array_elements(
         case
           when jsonb_typeof(recommendation.metadata -> 'evidence_refs') = 'array'
             then recommendation.metadata -> 'evidence_refs'
           else '[]'::jsonb
         end
       ) as evidence(value)
       join public.user_state_snapshots as snapshot
         on snapshot.id::text = coalesce(
           evidence.value ->> 'id',
           evidence.value ->> 'source_id'
         )
        and snapshot.user_id = recommendation.user_id
       where lower(coalesce(
               evidence.value ->> 'table',
               evidence.value ->> 'source',
               evidence.value ->> 'source_kind'
             )) in (
               'user_state_snapshot', 'user_state_snapshots',
               'personal_snapshot'
             )
         and snapshot.scope = 'onboarding'
         and snapshot.period_key = 'setup:intake-v1'
     )
  on conflict do nothing;

  insert into pg_temp._goal_snapshots(id, user_id)
  select id, user_id
  from public.user_state_snapshots
  where scope <> 'onboarding'
    and (
      private.references_goal_feature_v2(summary)
      or private.references_goal_feature_v2(signals)
      or private.references_goal_feature_v2(metadata)
      or lower(source) in ('goal', 'goals')
    )
  on conflict do nothing;

  insert into pg_temp._goal_briefings(id, user_id)
  select id, user_id
  from public.daily_briefings
  where private.references_goal_feature_v2(primary_action)
     or private.references_goal_feature_v2(support_actions)
     or private.references_goal_feature_v2(evidence_refs)
     or private.references_goal_feature_v2(provenance)
     or private.references_goal_feature_v2(metadata)
  on conflict do nothing;

  insert into pg_temp._goal_feedback(id, user_id)
  select id, user_id
  from public.decision_feedback
  where private.references_goal_feature_v2(metadata)
  on conflict do nothing;

  insert into pg_temp._goal_reviews(id, user_id)
  select id, user_id
  from public.weekly_reviews
  where private.references_goal_feature_v2(facts)
     or private.references_goal_feature_v2(proposals)
     or private.references_goal_feature_v2(evidence_refs)
     or private.references_goal_feature_v2(provenance)
  on conflict do nothing;

  insert into pg_temp._goal_memories(id, user_id)
  select id, user_id
  from public.memory_entries
  where type = 'goal'
     or private.references_goal_feature_v2(evidence)
     or private.references_goal_feature_v2(metadata)
  on conflict do nothing;

  insert into pg_temp._goal_insights(id, user_id)
  select id, user_id
  from public.ai_insights
  where lower(category) in ('goal', 'goals')
     or lower(source) in ('goal', 'goals')
     or private.references_goal_feature_v2(metadata)
  on conflict do nothing;

  insert into pg_temp._goal_events(id, user_id)
  select id, user_id
  from public.behavioral_events
  where event_type in (
      'goal_created', 'goal_updated', 'goal_completed', 'goal_archived'
    )
     or lower(source) in ('goal', 'goals')
     or private.references_goal_feature_v2(metadata)
  on conflict do nothing;

  insert into pg_temp._goal_notifications(id, user_id)
  select id, user_id
  from public.notifications
  where private.references_goal_feature_v2(metadata)
  on conflict do nothing;

  -- Follow every typed evidence/source reference until the dependency graph is
  -- closed. The helper is created only after the temp sets exist and is dropped
  -- again before commit.
  execute $helper$
    create function private.references_doomed_goal_record_v2(
      payload jsonb,
      owner_id uuid
    )
    returns boolean
    language plpgsql
    stable
    parallel restricted
    set search_path = pg_catalog, pg_temp
    as $body$
    declare
      relation_name text;
      record_id text;
      value jsonb;
    begin
      if payload is null then
        return false;
      end if;
      if jsonb_typeof(payload) = 'object' then
        relation_name := lower(coalesce(
          payload ->> 'table',
          payload ->> 'source',
          payload ->> 'source_kind'
        ));
        record_id := coalesce(payload ->> 'id', payload ->> 'source_id');
        if record_id is not null then
          if relation_name in ('recommendation', 'recommendations')
             and exists (
               select 1 from pg_temp._goal_recommendations
               where id::text = record_id and user_id = owner_id
             ) then return true;
          elsif relation_name in (
              'user_state_snapshot', 'user_state_snapshots', 'daily_state',
              'personal_snapshot'
            ) and exists (
              select 1 from pg_temp._goal_snapshots
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('daily_briefing', 'daily_briefings')
            and exists (
              select 1 from pg_temp._goal_briefings
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('decision_feedback', 'feedback')
            and exists (
              select 1 from pg_temp._goal_feedback
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('weekly_review', 'weekly_reviews')
            and exists (
              select 1 from pg_temp._goal_reviews
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('memory_entry', 'memory_entries', 'memory')
            and exists (
              select 1 from pg_temp._goal_memories
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('ai_insight', 'ai_insights', 'insight')
            and exists (
              select 1 from pg_temp._goal_insights
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('behavioral_event', 'behavioral_events', 'event')
            and exists (
              select 1 from pg_temp._goal_events
              where id::text = record_id and user_id = owner_id
            ) then return true;
          elsif relation_name in ('notification', 'notifications')
            and exists (
              select 1 from pg_temp._goal_notifications
              where id::text = record_id and user_id = owner_id
            ) then return true;
          end if;
        end if;
        for value in select item_value from jsonb_each(payload) item(key, item_value)
        loop
          if private.references_doomed_goal_record_v2(value, owner_id) then
            return true;
          end if;
        end loop;
        return false;
      end if;
      if jsonb_typeof(payload) = 'array' then
        return exists (
          select 1
          from jsonb_array_elements(payload) as item(item_value)
          where private.references_doomed_goal_record_v2(
            item.item_value,
            owner_id
          )
        );
      end if;
      return false;
    end;
    $body$
  $helper$;
  execute 'revoke all on function private.references_doomed_goal_record_v2(jsonb, uuid) from public, anon, authenticated, service_role';

  loop
    total_added := 0;

    insert into pg_temp._goal_recommendations(id, user_id)
    select recommendation.id, recommendation.user_id
    from public.recommendations as recommendation
    where private.references_doomed_goal_record_v2(
      recommendation.metadata,
      recommendation.user_id
    )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_snapshots(id, user_id)
    select snapshot.id, snapshot.user_id
    from public.user_state_snapshots as snapshot
    where snapshot.scope <> 'onboarding'
      and private.references_doomed_goal_record_v2(
        jsonb_build_array(snapshot.summary, snapshot.signals, snapshot.metadata),
        snapshot.user_id
      )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_briefings(id, user_id)
    select briefing.id, briefing.user_id
    from public.daily_briefings as briefing
    where exists (
        select 1
        from pg_temp._goal_recommendations as doomed
        where doomed.user_id = briefing.user_id
          and doomed.id = any(briefing.recommendation_ids)
      )
       or exists (
        select 1
        from pg_temp._goal_recommendations as doomed
        where doomed.user_id = briefing.user_id
          and doomed.id::text in (
            briefing.primary_action ->> 'recommendation_id',
            nullif(briefing.primary_action #>> '{target,recommendation_id}', '')
          )
      )
       or exists (
        select 1
        from jsonb_array_elements(briefing.support_actions) as action(value)
        join pg_temp._goal_recommendations as doomed
          on doomed.user_id = briefing.user_id
         and doomed.id::text in (
           action.value ->> 'recommendation_id',
           nullif(action.value #>> '{target,recommendation_id}', '')
         )
      )
       or exists (
        select 1
        from pg_temp._goal_snapshots as doomed
        where doomed.user_id = briefing.user_id
          and doomed.id::text = briefing.provenance ->> 'source_snapshot_id'
      )
       or private.references_doomed_goal_record_v2(
        jsonb_build_array(
          briefing.primary_action,
          briefing.support_actions,
          briefing.evidence_refs,
          briefing.provenance,
          briefing.metadata
        ),
        briefing.user_id
      )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_feedback(id, user_id)
    select feedback.id, feedback.user_id
    from public.decision_feedback as feedback
    where exists (
        select 1 from pg_temp._goal_briefings as doomed
        where doomed.id = feedback.briefing_id
          and doomed.user_id = feedback.user_id
      )
       or exists (
        select 1 from pg_temp._goal_recommendations as doomed
        where doomed.id = feedback.recommendation_id
          and doomed.user_id = feedback.user_id
      )
       or private.references_doomed_goal_record_v2(
        feedback.metadata,
        feedback.user_id
      )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_reviews(id, user_id)
    select review.id, review.user_id
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
        select 1 from pg_temp._goal_snapshots as doomed
        where doomed.id::text = review.provenance ->> 'source_snapshot_id'
          and doomed.user_id = review.user_id
      )
       or exists (
        select 1
        from jsonb_array_elements(review.evidence_refs) as evidence(value)
        where lower(coalesce(
                evidence.value ->> 'table',
                evidence.value ->> 'source',
                evidence.value ->> 'source_kind'
              )) in ('decision_feedback', 'feedback')
          and not exists (
            select 1
            from public.decision_feedback as feedback
            where feedback.id::text = coalesce(
                    evidence.value ->> 'id',
                    evidence.value ->> 'source_id'
                  )
              and feedback.user_id = review.user_id
          )
      )
       or exists (
        select 1
        from jsonb_array_elements(review.evidence_refs) as evidence(value)
        join pg_temp._goal_feedback as doomed
          on doomed.id::text = coalesce(
               evidence.value ->> 'id',
               evidence.value ->> 'source_id'
             )
         and doomed.user_id = review.user_id
        where lower(coalesce(
                evidence.value ->> 'table',
                evidence.value ->> 'source',
                evidence.value ->> 'source_kind'
              )) in ('decision_feedback', 'feedback')
      )
       or private.references_doomed_goal_record_v2(
        jsonb_build_array(
          review.facts,
          review.proposals,
          review.evidence_refs,
          review.provenance
        ),
        review.user_id
      )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_memories(id, user_id)
    select memory.id, memory.user_id
    from public.memory_entries as memory
    where private.references_doomed_goal_record_v2(
      jsonb_build_array(memory.evidence, memory.metadata),
      memory.user_id
    )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_insights(id, user_id)
    select insight.id, insight.user_id
    from public.ai_insights as insight
    where private.references_doomed_goal_record_v2(
      insight.metadata,
      insight.user_id
    )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_events(id, user_id)
    select event.id, event.user_id
    from public.behavioral_events as event
    where private.references_doomed_goal_record_v2(
      event.metadata,
      event.user_id
    )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    insert into pg_temp._goal_notifications(id, user_id)
    select notification.id, notification.user_id
    from public.notifications as notification
    where private.references_doomed_goal_record_v2(
      notification.metadata,
      notification.user_id
    )
    on conflict do nothing;
    get diagnostics added = row_count;
    total_added := total_added + added;

    exit when total_added = 0;
  end loop;

  -- Coach prose stays untouched. Only structured references and the V1
  -- full-snapshot provenance selected by the product decision are retired.
  insert into pg_temp._goal_coach_requests(request_id, user_id)
  select request.request_id, request.user_id
  from public.coach_requests as request
  where private.references_goal_feature_v2(request.response)
     or private.references_goal_feature_v2(request.used_context)
     or private.references_goal_feature_v2(request.context_parameters)
     or private.references_goal_feature_v2(request.evidence)
     or private.references_goal_feature_v2(request.agent_trace)
     or private.references_goal_feature_v2(request.error)
     or (
       request.context_version = 'personal-snapshot-v1'
       and exists (
         select 1
         from jsonb_array_elements(
           case
             when jsonb_typeof(request.evidence) = 'array'
               then request.evidence
             else '[]'::jsonb
           end
         ) as evidence(value)
         where evidence.value ->> 'source' = 'personal_snapshot'
       )
     )
  union
  select message.request_id, message.user_id
  from public.coach_messages as message
  where message.request_id is not null
    and private.references_goal_feature_v2(message.metadata)
  on conflict do nothing;

  delete from public.coach_messages as message
  where message.request_id is null
    and private.references_goal_feature_v2(message.metadata);

  delete from public.coach_messages as message
  using pg_temp._goal_coach_requests as doomed
  where message.request_id = doomed.request_id
    and message.user_id = doomed.user_id;

  update public.coach_requests as request
  set state = 'deleted',
      context_parameters = '{}'::jsonb,
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
  from pg_temp._goal_coach_requests as doomed
  where request.request_id = doomed.request_id
    and request.user_id = doomed.user_id;

  -- Delete dependants before the rows they cite. Notification lifecycle rows
  -- and memory selections follow through their established cascade FKs.
  delete from public.notifications as notification
  using pg_temp._goal_notifications as doomed
  where notification.id = doomed.id;

  delete from public.weekly_reviews as review
  using pg_temp._goal_reviews as doomed
  where review.id = doomed.id;

  delete from public.decision_feedback as feedback
  using pg_temp._goal_feedback as doomed
  where feedback.id = doomed.id;

  delete from public.daily_briefings as briefing
  using pg_temp._goal_briefings as doomed
  where briefing.id = doomed.id;

  delete from public.ai_insights as insight
  using pg_temp._goal_insights as doomed
  where insight.id = doomed.id;

  delete from public.behavioral_events as event
  using pg_temp._goal_events as doomed
  where event.id = doomed.id;

  delete from public.memory_entries as memory
  using pg_temp._goal_memories as doomed
  where memory.id = doomed.id;

  delete from public.recommendations as recommendation
  using pg_temp._goal_recommendations as doomed
  where recommendation.id = doomed.id;

  delete from public.user_state_snapshots as snapshot
  using pg_temp._goal_snapshots as doomed
  where snapshot.id = doomed.id;

  -- Assertions make the migration fail atomically if either a structural Goal
  -- trace or a known dangling dependency survived.
  if exists (
    select 1 from public.recommendations
    where private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.user_state_snapshots
    where private.references_goal_feature_v2(summary)
       or private.references_goal_feature_v2(signals)
       or private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.daily_briefings
    where private.references_goal_feature_v2(primary_action)
       or private.references_goal_feature_v2(support_actions)
       or private.references_goal_feature_v2(evidence_refs)
       or private.references_goal_feature_v2(provenance)
       or private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.decision_feedback
    where private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.weekly_reviews
    where private.references_goal_feature_v2(facts)
       or private.references_goal_feature_v2(proposals)
       or private.references_goal_feature_v2(evidence_refs)
       or private.references_goal_feature_v2(provenance)
  ) or exists (
    select 1 from public.memory_entries
    where type = 'goal'
       or private.references_goal_feature_v2(evidence)
       or private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.ai_insights
    where lower(category) in ('goal', 'goals')
       or lower(source) in ('goal', 'goals')
       or private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.behavioral_events
    where event_type in (
        'goal_created', 'goal_updated', 'goal_completed', 'goal_archived'
      )
       or lower(source) in ('goal', 'goals')
       or private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.notifications
    where private.references_goal_feature_v2(metadata)
  ) or exists (
    select 1 from public.coach_requests
    where private.references_goal_feature_v2(response)
       or private.references_goal_feature_v2(used_context)
       or private.references_goal_feature_v2(context_parameters)
       or private.references_goal_feature_v2(evidence)
       or private.references_goal_feature_v2(agent_trace)
       or private.references_goal_feature_v2(error)
  ) or exists (
    select 1 from public.coach_messages
    where private.references_goal_feature_v2(metadata)
  ) then
    raise exception 'Goal cleanup left a structured Goal trace.';
  end if;

  if exists (
    select 1
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
        where lower(coalesce(
                evidence.value ->> 'table',
                evidence.value ->> 'source',
                evidence.value ->> 'source_kind'
              )) in ('decision_feedback', 'feedback')
          and not exists (
            select 1
            from public.decision_feedback as feedback
            where feedback.id::text = coalesce(
                    evidence.value ->> 'id',
                    evidence.value ->> 'source_id'
                  )
              and feedback.user_id = review.user_id
          )
      )
  ) then
    raise exception 'Goal cleanup left a dangling Weekly Review dependency.';
  end if;

  if exists (
    select 1
    from public.coach_requests as request
    where request.context_version = 'personal-snapshot-v1'
      and exists (
        select 1
        from jsonb_array_elements(
          case
            when jsonb_typeof(request.evidence) = 'array'
              then request.evidence
            else '[]'::jsonb
          end
        ) as evidence(value)
        where evidence.value ->> 'source' = 'personal_snapshot'
      )
  ) then
    raise exception 'Goal cleanup left a V1 full-snapshot Coach turn.';
  end if;

  execute 'drop function private.references_doomed_goal_record_v2(jsonb, uuid)';
end;
$cleanup$;

revoke all on function private.remove_goal_derived_history_v2()
  from public, anon, authenticated, service_role;

select private.remove_goal_derived_history_v2();

drop function private.remove_goal_derived_history_v2();
drop function private.sanitize_goal_feature_v2(jsonb);
drop function private.references_goal_feature_v2(jsonb);
drop function private.is_goal_reference_object_v2(jsonb);
drop function private.goal_path_references_feature_v2(text);

commit;
