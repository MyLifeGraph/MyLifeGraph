begin;

set local lock_timeout = '5s';

-- This transition erases connected generated content. Lock the complete graph
-- in one fixed alphabetical order before inspecting the first row so a lock
-- timeout aborts without a partial retirement.
lock table public.ai_insights in share row exclusive mode;
lock table public.behavioral_events in share row exclusive mode;
lock table public.coach_memory_selections in share row exclusive mode;
lock table public.coach_messages in share row exclusive mode;
lock table public.coach_requests in access exclusive mode;
lock table public.coach_usage_events in share row exclusive mode;
lock table public.daily_briefings in access exclusive mode;
lock table public.decision_feedback in access exclusive mode;
lock table public.intake_responses in share row exclusive mode;
lock table public.memory_entries in share row exclusive mode;
lock table public.notification_action_requests in share row exclusive mode;
lock table public.notifications in share row exclusive mode;
lock table public.recommendations in access exclusive mode;
lock table public.tasks in share row exclusive mode;
lock table public.user_state_snapshots in share row exclusive mode;
lock table public.weekly_reviews in access exclusive mode;

create temporary table _recommendation_retirement_counts
on commit drop
as
select
  (select count(*) from public.coach_usage_events) as coach_usage_events,
  (
    select count(*)
    from public.notifications
    where metadata ->> 'source_kind' = 'daily_briefing'
      and (
        metadata ->> 'contract_version'
          is distinct from 'notification-generation-v1'
        or metadata ->> 'origin' is distinct from 'deterministic_backend'
      )
  ) as untyped_daily_briefing_notifications,
  (
    select count(*)
    from public.ai_insights
    where recommendation is not null
      and lower(source) not in (
        'decision_feedback', 'feedback', 'recommendation', 'recommendations'
      )
      and lower(category) not in (
        'decision_feedback', 'feedback', 'recommendation', 'recommendations'
      )
  ) as ai_insight_recommendations,
  (
    select count(*)
    from public.memory_entries
    where type = 'recommendation'
  ) as recommendation_memories;

-- Generated Briefing and Weekly Review payloads used the retired sources.
-- Their typed notification dependants are deleted first; the request ledger
-- follows through its established notification cascade.
delete from public.notifications
where metadata ->> 'contract_version' = 'notification-generation-v1'
  and metadata ->> 'origin' = 'deterministic_backend'
  and metadata ->> 'source_kind' = 'daily_briefing';

delete from public.daily_briefings;
delete from public.weekly_reviews;

-- Remove only typed keys and reference objects from surviving JSON. Ordinary
-- prose is never searched, ai_insights.recommendation remains a product field,
-- and memory_entries.type = 'recommendation' remains a valid memory kind.
create function private.is_retired_recommendation_reference_v1(payload jsonb)
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
  foreach key in array array[
    'table', 'source', 'source_kind', 'target_type', 'target_kind'
  ] loop
    if jsonb_typeof(payload -> key) = 'string'
       and lower(payload ->> key) in (
         'decision_feedback', 'feedback', 'recommendation', 'recommendations'
       ) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

create function private.references_retired_recommendation_v1(payload jsonb)
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
    if private.is_retired_recommendation_reference_v1(payload) then
      return true;
    end if;
    for key, value in select * from jsonb_each(payload) loop
      if key = any(array[
        'decision_feedback', 'decision_feedback_id', 'decision_feedback_ids',
        'feedback', 'feedback_count', 'feedback_id', 'feedback_ids',
        'feedback_ranking', 'include_recommendations', 'recommendation_bonus',
        'recommendation_count', 'recommendation_id', 'recommendation_ids',
        'recommendation_rank', 'recommendation_score', 'recommendations'
      ]) then
        return true;
      end if;
      if key in ('tables', 'sources')
         and jsonb_typeof(value) = 'array' then
        for item in
          select item_value
          from jsonb_array_elements(value) as entry(item_value)
        loop
          if jsonb_typeof(item) = 'string'
             and lower(item #>> '{}') in (
               'decision_feedback', 'feedback',
               'recommendation', 'recommendations'
             ) then
            return true;
          end if;
        end loop;
      end if;
      if private.references_retired_recommendation_v1(value) then
        return true;
      end if;
    end loop;
    return false;
  end if;
  if jsonb_typeof(payload) = 'array' then
    return exists (
      select 1
      from jsonb_array_elements(payload) as entry(item_value)
      where private.references_retired_recommendation_v1(entry.item_value)
    );
  end if;
  return false;
end;
$$;

create function private.sanitize_retired_recommendation_v1(payload jsonb)
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
    if private.is_retired_recommendation_reference_v1(payload) then
      return null;
    end if;
    result := '{}'::jsonb;
    for key, value in select * from jsonb_each(payload) loop
      if key = any(array[
        'decision_feedback', 'decision_feedback_id', 'decision_feedback_ids',
        'feedback', 'feedback_count', 'feedback_id', 'feedback_ids',
        'feedback_ranking', 'include_recommendations', 'recommendation_bonus',
        'recommendation_count', 'recommendation_id', 'recommendation_ids',
        'recommendation_rank', 'recommendation_score', 'recommendations'
      ]) then
        continue;
      end if;
      if key in ('tables', 'sources')
         and jsonb_typeof(value) = 'array' then
        cleaned := '[]'::jsonb;
        for item in
          select item_value
          from jsonb_array_elements(value) as entry(item_value)
        loop
          if jsonb_typeof(item) = 'string'
             and lower(item #>> '{}') in (
               'decision_feedback', 'feedback',
               'recommendation', 'recommendations'
             ) then
            continue;
          end if;
          item := private.sanitize_retired_recommendation_v1(item);
          if item is not null then
            cleaned := cleaned || jsonb_build_array(item);
          end if;
        end loop;
      else
        cleaned := private.sanitize_retired_recommendation_v1(value);
      end if;
      if cleaned is not null then
        result := result || jsonb_build_object(key, cleaned);
      end if;
    end loop;
    return result;
  end if;
  if jsonb_typeof(payload) = 'array' then
    result := '[]'::jsonb;
    for item in
      select item_value
      from jsonb_array_elements(payload) as entry(item_value)
    loop
      cleaned := private.sanitize_retired_recommendation_v1(item);
      if cleaned is not null then
        result := result || jsonb_build_array(cleaned);
      end if;
    end loop;
    return result;
  end if;
  return payload;
end;
$$;

revoke all on function private.is_retired_recommendation_reference_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.references_retired_recommendation_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.sanitize_retired_recommendation_v1(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.is_retired_recommendation_reference_v1(jsonb)
  to service_role;
grant execute on function private.references_retired_recommendation_v1(jsonb)
  to service_role;

update public.ai_insights
set metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(metadata);

update public.behavioral_events
set metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(metadata);

update public.intake_responses
set responses = coalesce(
      private.sanitize_retired_recommendation_v1(responses),
      '{}'::jsonb
    ),
    metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(responses)
   or private.references_retired_recommendation_v1(metadata);

update public.memory_entries
set evidence = coalesce(
      private.sanitize_retired_recommendation_v1(evidence),
      '[]'::jsonb
    ),
    metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(evidence)
   or private.references_retired_recommendation_v1(metadata);

update public.notifications
set metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(metadata);

update public.tasks
set metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(metadata);

update public.user_state_snapshots
set summary = coalesce(
      private.sanitize_retired_recommendation_v1(summary),
      '{}'::jsonb
    ),
    signals = coalesce(
      private.sanitize_retired_recommendation_v1(signals),
      '{}'::jsonb
    ),
    metadata = coalesce(
      private.sanitize_retired_recommendation_v1(metadata),
      '{}'::jsonb
    )
where private.references_retired_recommendation_v1(summary)
   or private.references_retired_recommendation_v1(signals)
   or private.references_retired_recommendation_v1(metadata);

delete from public.ai_insights
where lower(source) in (
    'decision_feedback', 'feedback', 'recommendation', 'recommendations'
  )
   or lower(category) in (
    'decision_feedback', 'feedback', 'recommendation', 'recommendations'
  );

delete from public.behavioral_events
where lower(source) in (
    'decision_feedback', 'feedback', 'recommendation', 'recommendations'
  )
   or lower(event_type) in (
    'decision_feedback', 'feedback', 'recommendation', 'recommendations'
  );

-- Coach usage events are append-only evidence that a bounded turn happened.
-- Keep them and the parent request identity, but erase all conversational and
-- generated content. Deleting messages and selections is independent of the
-- request tombstone and therefore also covers legacy rows.
delete from public.coach_messages;
delete from public.coach_memory_selections;

alter table public.coach_requests
  drop constraint coach_requests_versions,
  drop constraint coach_requests_used_context,
  drop constraint coach_requests_response,
  drop constraint coach_requests_agent_fields;

update public.coach_requests
set state = 'deleted',
    prompt_version = case
      when contract_version = 'coach-request-v3'
        then 'free-coach-agent-prompt-v4'
      else prompt_version
    end,
    context_version = case
      when contract_version = 'coach-request-v3'
        then 'personal-snapshot-v3'
      else context_version
    end,
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
    deleted_at = greatest(created_at, clock_timestamp()),
    updated_at = greatest(created_at, clock_timestamp());

-- Keep the established bounded Coach validators, but close every structured
-- source seam that could recreate the two retired product concepts. Renaming
-- first also makes the new constraints below bind to these wrappers rather
-- than to the pre-transition function OIDs.
alter function private.coach_evidence_is_valid_v1(jsonb)
  rename to coach_evidence_is_valid_before_recommendation_retirement_v1;

create function private.coach_evidence_is_valid_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  item jsonb;
  count_value numeric;
begin
  if jsonb_typeof(p_value) is distinct from 'array'
     or jsonb_array_length(p_value) > 100
     or octet_length(p_value::text) > 65536 then
    return false;
  end if;
  for item in select value from jsonb_array_elements(p_value) loop
    if not private.coach_jsonb_has_exact_keys(
      item,
      array['source', 'record_count', 'period_start', 'period_end']
    )
       or jsonb_typeof(item -> 'source') is distinct from 'string'
       or char_length(item ->> 'source') not between 1 and 80
       or lower(item ->> 'source') in (
         'decision_feedback', 'feedback', 'recommendation', 'recommendations'
       )
       or jsonb_typeof(item -> 'record_count') is distinct from 'number'
       or jsonb_typeof(item -> 'period_start') not in ('string', 'null')
       or jsonb_typeof(item -> 'period_end') not in ('string', 'null')
       or jsonb_typeof(item -> 'period_start') is distinct from
         jsonb_typeof(item -> 'period_end')
       or (
         jsonb_typeof(item -> 'period_start') = 'string'
         and char_length(item ->> 'period_start') not between 1 and 40
       )
       or (
         jsonb_typeof(item -> 'period_end') = 'string'
         and char_length(item ->> 'period_end') not between 1 and 40
       ) then
      return false;
    end if;
    count_value := (item ->> 'record_count')::numeric;
    if count_value is null
       or count_value not between 0 and 50000
       or trunc(count_value) <> count_value then
      return false;
    end if;
  end loop;
  return true;
exception
  when others then
    return false;
end;
$$;

drop function
  private.coach_evidence_is_valid_before_recommendation_retirement_v1(jsonb);

-- Keep generation retry and consent semantics in the established function,
-- while making the retired Briefing source impossible at the public RPC seam.
alter function public.create_generated_notification_v1(
  uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
  text, text, text, text, timestamptz
) rename to generated_notification_before_retirement_v1;

create function public.create_generated_notification_v1(
  p_user_id uuid,
  p_notification_id uuid,
  p_generation_key text,
  p_category text,
  p_delivery_date date,
  p_run_at timestamptz,
  p_timezone text,
  p_title text,
  p_message text,
  p_type text,
  p_priority text,
  p_action_url text,
  p_reason_code text,
  p_source_kind text,
  p_source_id text,
  p_source_generated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if p_category is null
     or p_category not in (
       'focus_prompt', 'recovery_prompt', 'weekly_summary'
     )
     or p_type is null
     or p_type not in (
       'reminder', 'warning', 'coaching', 'deadline', 'summary'
     )
     or p_priority is null
     or p_priority not in ('low', 'medium', 'high', 'critical')
     or p_action_url is null
     or p_action_url not in ('/dashboard', '/weekly-review')
     or p_source_kind is null
     or p_source_kind not in ('daily_state', 'weekly_review') then
    raise exception 'Invalid generated notification request'
      using errcode = '22023';
  end if;
  return public.generated_notification_before_retirement_v1(
    p_user_id,
    p_notification_id,
    p_generation_key,
    p_category,
    p_delivery_date,
    p_run_at,
    p_timezone,
    p_title,
    p_message,
    p_type,
    p_priority,
    p_action_url,
    p_reason_code,
    p_source_kind,
    p_source_id,
    p_source_generated_at
  );
end;
$$;

revoke all on function
  public.generated_notification_before_retirement_v1(
    uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
    text, text, text, text, timestamptz
  ) from public, anon, authenticated, service_role;
revoke all on function public.create_generated_notification_v1(
  uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
  text, text, text, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.create_generated_notification_v1(
  uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
  text, text, text, text, timestamptz
) to service_role;

-- V6 keeps the established owner/request advisory-lock and retry behavior but
-- creates new free-agent rows directly with the post-retirement provenance.
create function public.claim_coach_request_v6(
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
  existing public.coach_requests%rowtype;
  active_request public.coach_requests%rowtype;
  used_count int;
  remaining_count int;
  interrupted_error constant jsonb := jsonb_build_object(
    'code', 'interrupted',
    'message', 'The Coach request expired before completion.',
    'retryable', true
  );
  interrupted_usage constant jsonb := jsonb_build_object(
    'provider_called', false,
    'prompt_bytes', 0,
    'context_bytes', 0,
    'reply_codepoints', 0
  );
begin
  if p_user_id is null
     or p_request_id is null
     or p_local_date is null
     or p_claimed_at is null
     or p_lease_expires_at is null
     or p_provider is null
     or p_provider_mode is null
     or p_model_source is null
     or p_daily_limit is null
     or p_message_fingerprint is null
     or p_message_fingerprint !~ '^[0-9a-f]{64}$'
     or p_provider not in ('disabled', 'local_codex_oauth', 'fake')
     or p_provider_mode not in (
       'disabled', 'local_development_only', 'deterministic_test_only'
     )
     or p_model_source not in ('explicit', 'cli_default', 'not_applicable')
     or (
       p_model_requested is not null
       and char_length(p_model_requested) not between 1 and 100
     )
     or (
       p_provider = 'local_codex_oauth'
       and (
         p_provider_mode <> 'local_development_only'
         or p_model_requested is distinct from 'gpt-5.5'
         or p_model_source <> 'explicit'
       )
     )
     or (
       p_provider <> 'local_codex_oauth'
       and (
         p_model_requested is not null
         or p_model_source <> 'not_applicable'
       )
     )
     or p_lease_expires_at <= p_claimed_at
     or p_lease_expires_at > p_claimed_at + interval '5 minutes'
     or p_daily_limit <> 20 then
    raise exception 'Coach V6 claim is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into existing
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if found then
    if existing.user_id <> p_user_id
       or existing.contract_version <> 'coach-request-v3'
       or (
         existing.state <> 'deleted'
         and existing.message_fingerprint <> p_message_fingerprint
       ) then
      raise exception 'Coach request id was already used with different input'
        using errcode = 'PT409';
    end if;

    select count(*)::int into used_count
    from public.coach_requests
    where user_id = p_user_id and local_date = existing.local_date;

    if existing.state = 'deleted' then
      return jsonb_build_object(
        'state', 'deleted',
        'remaining_requests', greatest(p_daily_limit - used_count, 0),
        'response', null,
        'error', jsonb_build_object(
          'code', 'history_deleted',
          'message', 'This Coach request history was deleted.',
          'retryable', false
        )
      );
    end if;

    if existing.state = 'pending'
       and existing.lease_expires_at <= p_claimed_at then
      perform public.fail_coach_request_v1(
        p_user_id,
        p_request_id,
        interrupted_error,
        interrupted_usage,
        p_claimed_at
      );
      existing.state := 'failed';
      existing.error := interrupted_error;
    end if;

    if existing.state = 'completed' then
      return jsonb_build_object(
        'state', 'completed',
        'remaining_requests', greatest(p_daily_limit - used_count, 0),
        'response', existing.response,
        'error', null
      );
    elsif existing.state = 'failed' then
      return jsonb_build_object(
        'state', 'failed',
        'remaining_requests', greatest(p_daily_limit - used_count, 0),
        'response', null,
        'error', existing.error
      );
    end if;
    return jsonb_build_object(
      'state', 'in_progress',
      'remaining_requests', greatest(p_daily_limit - used_count, 0),
      'response', null,
      'error', null
    );
  end if;

  select * into active_request
  from public.coach_requests
  where user_id = p_user_id and state = 'pending'
  limit 1
  for update;

  if found and active_request.lease_expires_at <= p_claimed_at then
    perform public.fail_coach_request_v1(
      p_user_id,
      active_request.request_id,
      interrupted_error,
      interrupted_usage,
      p_claimed_at
    );
    active_request := null;
  end if;

  select count(*)::int into used_count
  from public.coach_requests
  where user_id = p_user_id and local_date = p_local_date;
  remaining_count := greatest(p_daily_limit - used_count, 0);

  if active_request.request_id is not null then
    return jsonb_build_object(
      'state', 'in_progress',
      'remaining_requests', remaining_count,
      'response', null,
      'error', null
    );
  end if;
  if used_count >= p_daily_limit then
    raise exception 'Coach daily request limit reached'
      using errcode = 'PT429';
  end if;

  insert into public.coach_requests (
    request_id,
    user_id,
    contract_version,
    context_scope,
    context_parameters,
    local_date,
    message_fingerprint,
    state,
    lease_expires_at,
    provider,
    provider_mode,
    model_requested,
    model_source,
    prompt_version,
    context_version,
    created_at,
    updated_at
  ) values (
    p_request_id,
    p_user_id,
    'coach-request-v3',
    'today',
    '{}'::jsonb,
    p_local_date,
    p_message_fingerprint,
    'pending',
    p_lease_expires_at,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    'free-coach-agent-prompt-v4',
    'personal-snapshot-v3',
    p_claimed_at,
    p_claimed_at
  );

  return jsonb_build_object(
    'state', 'pending',
    'remaining_requests', p_daily_limit - used_count - 1,
    'response', null,
    'error', null
  );
end;
$$;

revoke all on function public.claim_coach_request_v6(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v6(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;
revoke all on function public.claim_coach_request_v5(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;

alter function private.coach_used_context_is_valid_v1(jsonb)
  rename to coach_used_context_is_valid_before_recommendation_retirement_v1;

create function private.coach_used_context_is_valid_v1(p_value jsonb)
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

drop function
  private.coach_used_context_is_valid_before_recommendation_retirement_v1(jsonb);

alter function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  rename to coach_response_is_valid_before_recommendation_retirement_v2;

create function private.coach_response_is_valid_v2(
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
  normalized jsonb;
begin
  if p_value #>> '{provenance,prompt_version}'
       is distinct from 'free-coach-agent-prompt-v4'
     or p_value #>> '{provenance,context_version}'
       is distinct from 'personal-snapshot-v3'
     or not private.coach_evidence_is_valid_v1(p_evidence) then
    return false;
  end if;
  normalized := jsonb_set(
    jsonb_set(
      p_value,
      '{provenance,prompt_version}',
      '"free-coach-agent-prompt-v3"'::jsonb,
      false
    ),
    '{provenance,context_version}',
    '"personal-snapshot-v2"'::jsonb,
    false
  );
  return private.coach_response_is_valid_before_recommendation_retirement_v2(
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
  if not private.coach_used_context_is_valid_v1(p_used_context) then
    return false;
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

revoke all on function private.coach_evidence_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_used_context_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function
  private.coach_response_is_valid_before_recommendation_retirement_v2(
    jsonb, uuid, jsonb
  ) from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v2(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_evidence_is_valid_v1(jsonb)
  to service_role;
grant execute on function private.coach_used_context_is_valid_v1(jsonb)
  to service_role;
grant execute on function
  private.coach_response_is_valid_before_recommendation_retirement_v2(
    jsonb, uuid, jsonb
  ) to service_role;
grant execute on function private.coach_response_is_valid_v2(
  jsonb, uuid, jsonb
) to service_role;
grant execute on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) to service_role;

alter table public.coach_requests
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
      and prompt_version = 'free-coach-agent-prompt-v4'
      and context_version = 'personal-snapshot-v3'
    )
  ),
  add constraint coach_requests_used_context check (
    (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and private.coach_used_context_is_valid_v1(used_context)
    )
    or (
      contract_version = 'coach-request-v3'
      and private.coach_evidence_is_valid_v1(used_context)
    )
  ),
  add constraint coach_requests_response check (
    response is null
    or (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and response ->> 'contract_version' = 'coach-response-v1'
      and private.coach_response_is_valid_v1(
        response,
        request_id,
        used_context
      )
    )
    or (
      contract_version = 'coach-request-v3'
      and response ->> 'contract_version' = 'coach-response-v2'
      and private.coach_response_is_valid_v2(response, request_id, used_context)
    )
  ),
  add constraint coach_requests_agent_fields check (
    (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and evidence is null
      and agent_trace is null
      and tool_call_count is null
      and service_tier is null
    )
    or (
      contract_version = 'coach-request-v3'
      and (
        (
          state = 'completed'
          and evidence is not null
          and agent_trace is not null
          and tool_call_count is not null
          and service_tier is not null
          and private.coach_evidence_is_valid_v1(evidence)
          and private.coach_agent_trace_is_valid_v1(agent_trace)
          and tool_call_count between 0 and 12
          and tool_call_count = (agent_trace ->> 'tool_call_count')::int
          and service_tier in ('fast', 'not_applicable')
          and evidence is not distinct from used_context
          and evidence is not distinct from response -> 'evidence'
          and agent_trace is not distinct from response -> 'agent_trace'
          and service_tier is not distinct from
            response #>> '{provenance,service_tier}'
        )
        or (
          state = 'failed'
          and evidence is null
          and agent_trace is null
          and tool_call_count is null
          and service_tier is null
        )
        or (
          -- The established history-delete wrapper clears the response before
          -- it clears these agent fields later in the same transaction.
          state = 'deleted'
          and (
            (
              evidence is null
              and agent_trace is null
              and tool_call_count is null
              and service_tier is null
            )
            or (
              evidence is not null
              and agent_trace is not null
              and tool_call_count is not null
              and service_tier is not null
              and private.coach_evidence_is_valid_v1(evidence)
              and private.coach_agent_trace_is_valid_v1(agent_trace)
              and tool_call_count between 0 and 12
              and tool_call_count =
                (agent_trace ->> 'tool_call_count')::int
              and service_tier in ('fast', 'not_applicable')
            )
          )
        )
        or (
          -- Completion writes backend-owned evidence immediately before the
          -- established atomic body advances the request to completed.
          state = 'pending'
          and (
            (
              evidence is null
              and agent_trace is null
              and tool_call_count is null
              and service_tier is null
            )
            or (
              evidence is not null
              and agent_trace is not null
              and tool_call_count is not null
              and service_tier is not null
              and private.coach_evidence_is_valid_v1(evidence)
              and private.coach_agent_trace_is_valid_v1(agent_trace)
              and tool_call_count between 0 and 12
              and tool_call_count =
                (agent_trace ->> 'tool_call_count')::int
              and service_tier in ('fast', 'not_applicable')
            )
          )
        )
      )
    )
  );

-- Weekly Review V3 has no feedback facts or evidence source. The table is
-- empty by product decision above, so the new constraints become authoritative
-- before the V3 writer is exposed.
alter table public.weekly_reviews
  drop constraint weekly_reviews_facts_object,
  drop constraint weekly_reviews_provenance_object;

alter table public.weekly_reviews
  add constraint weekly_reviews_facts_object check (
    jsonb_typeof(facts) = 'object'
    and octet_length(facts::text) <= 65536
    and facts ?& array['tasks', 'habits', 'focus', 'recovery']
    and facts - array['tasks', 'habits', 'focus', 'recovery'] = '{}'::jsonb
    and not coalesce(
      (facts #> '{tasks}') ? 'goal_linked_completed',
      false
    )
    and not private.references_retired_recommendation_v1(facts)
  ),
  add constraint weekly_reviews_provenance_object check (
    jsonb_typeof(provenance) = 'object'
    and octet_length(provenance::text) <= 32768
    and provenance @> '{
      "engine": "deterministic",
      "contract_version": "weekly-review-v3",
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
    and not private.references_retired_recommendation_v1(provenance)
  ),
  add constraint weekly_reviews_retired_sources check (
    not private.references_retired_recommendation_v1(
      jsonb_build_array(proposals, evidence_refs)
    )
  );

create function public.persist_weekly_review_v3(
  p_user_id uuid,
  p_period_key text,
  p_source_observed_at timestamptz,
  p_row jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
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
     or not (p_row -> 'facts') ?& array[
       'tasks', 'habits', 'focus', 'recovery'
     ]
     or (p_row -> 'facts') - array[
       'tasks', 'habits', 'focus', 'recovery'
     ] <> '{}'::jsonb
     or coalesce(
       (p_row #> '{facts,tasks}') ? 'goal_linked_completed',
       false
     )
     or jsonb_typeof(p_row -> 'proposals') <> 'array'
     or p_row -> 'proposals' <> '[]'::jsonb
     or jsonb_typeof(p_row -> 'evidence_refs') <> 'array'
     or jsonb_typeof(p_row -> 'provenance') <> 'object'
     or p_row #>> '{provenance,contract_version}'
          is distinct from 'weekly-review-v3'
     or private.references_retired_recommendation_v1(p_row)
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

revoke all on function public.persist_weekly_review_v3(
  uuid, text, timestamptz, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.persist_weekly_review_v3(
  uuid, text, timestamptz, jsonb
) to service_role;

-- Drop dependants in explicit RESTRICT order. No CASCADE is used.
delete from public.decision_feedback;
drop table public.decision_feedback;

revoke all on function public.persist_weekly_review_v2(
  uuid, text, timestamptz, jsonb
) from public, anon, authenticated, service_role;
drop function public.persist_weekly_review_v2(
  uuid, text, timestamptz, jsonb
);

revoke all on function public.replace_current_recommendations_v2(
  uuid, jsonb, timestamptz
) from public, anon, authenticated, service_role;
drop function public.replace_current_recommendations_v2(
  uuid, jsonb, timestamptz
);

drop table public.recommendations;

alter table public.daily_briefings
  drop column recommendation_ids;

alter table public.daily_briefings
  drop constraint daily_briefings_metadata_object,
  add constraint daily_briefings_metadata_object check (
    jsonb_typeof(metadata) = 'object'
    and metadata @> '{
      "contract_version": "daily-briefing-v2",
      "ranking_version": "deterministic-briefing-ranker-v3"
    }'::jsonb
    and not private.references_retired_recommendation_v1(metadata)
  ),
  add constraint daily_briefings_v2_sources check (
    provenance @> '{
      "engine": "deterministic",
      "contract_version": "daily-briefing-v2",
      "baseline": "none",
      "llm_used": false
    }'::jsonb
    and not private.references_retired_recommendation_v1(
      jsonb_build_array(
        primary_action,
        support_actions,
        evidence_refs,
        provenance
      )
    )
  );

-- Replace the temporary delegating seam with a self-contained definition so
-- no executable helper retains the retired Daily Briefing source option.
create or replace function public.create_generated_notification_v1(
  p_user_id uuid,
  p_notification_id uuid,
  p_generation_key text,
  p_category text,
  p_delivery_date date,
  p_run_at timestamptz,
  p_timezone text,
  p_title text,
  p_message text,
  p_type text,
  p_priority text,
  p_action_url text,
  p_reason_code text,
  p_source_kind text,
  p_source_id text,
  p_source_generated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_preferences public.notification_preferences%rowtype;
  profile_timezone text;
  local_run_at timestamp;
  existing_notification_id uuid;
  generated_count integer;
  category_enabled boolean;
  in_quiet_hours boolean := false;
  notification_metadata jsonb;
begin
  if p_user_id is null
     or p_notification_id is null
     or p_generation_key is null
     or length(p_generation_key) not between 1 and 200
     or p_category is null
     or p_category not in ('focus_prompt', 'recovery_prompt', 'weekly_summary')
     or p_delivery_date is null
     or p_run_at is null
     or p_timezone is null
     or length(p_timezone) not between 1 and 100
     or p_title is null
     or length(btrim(p_title)) not between 1 and 120
     or p_message is null
     or length(btrim(p_message)) not between 1 and 300
     or p_type is null
     or p_type not in ('reminder', 'warning', 'coaching', 'deadline', 'summary')
     or p_priority is null
     or p_priority not in ('low', 'medium', 'high', 'critical')
     or p_action_url is null
     or p_action_url not in ('/dashboard', '/weekly-review')
     or p_reason_code is null
     or length(p_reason_code) not between 1 and 80
     or p_source_kind is null
     or p_source_kind not in ('daily_state', 'weekly_review')
     or p_source_id is null
     or length(p_source_id) not between 1 and 100
     or p_source_generated_at is null then
    raise exception 'Invalid generated notification request'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select timezone into profile_timezone
  from public.profiles
  where id = p_user_id
    and onboarding_completed_at is not null
    and role <> 'guest'
  for share;

  if not found then
    return jsonb_build_object('status', 'not_consented');
  end if;
  if profile_timezone is distinct from p_timezone then
    raise exception 'Notification timezone changed'
      using errcode = 'PT409';
  end if;

  select * into current_preferences
  from public.notification_preferences
  where user_id = p_user_id
  for update;

  if not found
     or not current_preferences.in_app_delivery_enabled
     or current_preferences.in_app_delivery_consent_version
       is distinct from 'in-app-notification-consent-v1' then
    return jsonb_build_object('status', 'not_consented');
  end if;

  select id into existing_notification_id
  from public.notifications
  where user_id = p_user_id and generation_key = p_generation_key;

  if found then
    return jsonb_build_object(
      'status', 'duplicate',
      'notification_id', existing_notification_id
    );
  end if;

  category_enabled := case p_category
    when 'focus_prompt' then current_preferences.focus_prompts_enabled
    when 'recovery_prompt' then current_preferences.recovery_prompts_enabled
    when 'weekly_summary' then current_preferences.weekly_summary_enabled
  end;
  if not category_enabled then
    return jsonb_build_object('status', 'category_disabled');
  end if;

  begin
    local_run_at := p_run_at at time zone p_timezone;
  exception when invalid_parameter_value then
    raise exception 'Notification timezone is invalid'
      using errcode = '22023';
  end;
  if local_run_at::date is distinct from p_delivery_date then
    raise exception 'Notification delivery date is invalid'
      using errcode = '22023';
  end if;

  if current_preferences.quiet_hours_start is not null then
    in_quiet_hours := case
      when current_preferences.quiet_hours_start
        < current_preferences.quiet_hours_end
        then local_run_at::time >= current_preferences.quiet_hours_start
          and local_run_at::time < current_preferences.quiet_hours_end
      else local_run_at::time >= current_preferences.quiet_hours_start
        or local_run_at::time < current_preferences.quiet_hours_end
    end;
  end if;
  if in_quiet_hours then
    return jsonb_build_object('status', 'quiet_hours');
  end if;

  select count(*) into generated_count
  from public.notifications
  where user_id = p_user_id
    and delivery_date = p_delivery_date
    and generation_key is not null;
  if generated_count >= current_preferences.daily_notification_limit then
    return jsonb_build_object('status', 'daily_limit');
  end if;

  notification_metadata := jsonb_strip_nulls(jsonb_build_object(
    'contract_version', 'notification-generation-v1',
    'origin', 'deterministic_backend',
    'category', p_category,
    'reason_code', p_reason_code,
    'delivery_date', p_delivery_date,
    'timezone', p_timezone,
    'source_kind', p_source_kind,
    'source_id', p_source_id,
    'source_generated_at', p_source_generated_at,
    'sensitive_copy_excluded', true,
    'llm_used', false
  ));

  insert into public.notifications (
    id,
    user_id,
    title,
    message,
    type,
    priority,
    is_read,
    read_at,
    action_url,
    due_at,
    metadata,
    generation_key,
    generation_category,
    delivery_date,
    created_at,
    updated_at
  ) values (
    p_notification_id,
    p_user_id,
    btrim(p_title),
    btrim(p_message),
    p_type,
    p_priority,
    false,
    null,
    p_action_url,
    p_run_at,
    notification_metadata,
    p_generation_key,
    p_category,
    p_delivery_date,
    p_run_at,
    p_run_at
  );

  return jsonb_build_object(
    'status', 'created',
    'notification_id', p_notification_id
  );
end;
$$;

drop function public.generated_notification_before_retirement_v1(
  uuid, uuid, text, text, date, timestamptz, text, text, text, text, text,
  text, text, text, text, timestamptz
);

revoke all on function public.claim_coach_request_v1(
  uuid, uuid, text, text, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v1(
  uuid, uuid, text, text, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;
revoke all on function public.claim_coach_request_v2(
  uuid, uuid, text, text, jsonb, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v2(
  uuid, uuid, text, text, jsonb, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;
revoke all on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
revoke all on function public.claim_coach_request_v4(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;

do $$
declare
  expected pg_temp._recommendation_retirement_counts%rowtype;
begin
  select * into strict expected
  from pg_temp._recommendation_retirement_counts;

  if (select count(*) from public.coach_usage_events)
       <> expected.coach_usage_events then
    raise exception 'Recommendation retirement changed Coach usage evidence.';
  end if;
  if (select count(*) from public.notifications
      where metadata ->> 'source_kind' = 'daily_briefing'
        and (
          metadata ->> 'contract_version'
            is distinct from 'notification-generation-v1'
          or metadata ->> 'origin' is distinct from 'deterministic_backend'
        )) <> expected.untyped_daily_briefing_notifications then
    raise exception 'Recommendation retirement changed an untyped notification.';
  end if;
  if (select count(*) from public.ai_insights
      where recommendation is not null
        and lower(source) not in (
          'decision_feedback', 'feedback', 'recommendation', 'recommendations'
        )
        and lower(category) not in (
          'decision_feedback', 'feedback', 'recommendation', 'recommendations'
        )) <> expected.ai_insight_recommendations then
    raise exception 'Recommendation retirement changed retained Insight advice.';
  end if;
  if (select count(*) from public.memory_entries
      where type = 'recommendation') <> expected.recommendation_memories then
    raise exception 'Recommendation retirement changed recommendation memories.';
  end if;

  if exists (select 1 from public.daily_briefings)
     or exists (select 1 from public.weekly_reviews)
     or exists (select 1 from public.coach_messages)
     or exists (select 1 from public.coach_memory_selections) then
    raise exception 'Recommendation retirement left generated history.';
  end if;
  if exists (
    select 1
    from public.coach_requests
    where state <> 'deleted'
       or context_parameters <> '{}'::jsonb
       or message_fingerprint is not null
       or lease_expires_at is not null
       or response is not null
       or used_context <> '[]'::jsonb
       or error is not null
       or evidence is not null
       or agent_trace is not null
       or tool_call_count is not null
       or service_tier is not null
       or completed_at is not null
       or failed_at is not null
       or deleted_at is null
       or (
         contract_version = 'coach-request-v3'
         and (
           prompt_version <> 'free-coach-agent-prompt-v4'
           or context_version <> 'personal-snapshot-v3'
         )
       )
  ) then
    raise exception 'Recommendation retirement left Coach content.';
  end if;

  if exists (
    select 1
    from public.notifications
    where metadata ->> 'contract_version' = 'notification-generation-v1'
      and metadata ->> 'origin' = 'deterministic_backend'
      and metadata ->> 'source_kind' = 'daily_briefing'
  ) then
    raise exception 'Recommendation retirement left a typed Briefing notification.';
  end if;

  if exists (
    select 1 from public.ai_insights
    where private.references_retired_recommendation_v1(metadata)
       or lower(source) in (
         'decision_feedback', 'feedback', 'recommendation', 'recommendations'
       )
       or lower(category) in (
         'decision_feedback', 'feedback', 'recommendation', 'recommendations'
       )
  ) or exists (
    select 1 from public.behavioral_events
    where private.references_retired_recommendation_v1(metadata)
       or lower(source) in (
         'decision_feedback', 'feedback', 'recommendation', 'recommendations'
       )
       or lower(event_type) in (
         'decision_feedback', 'feedback', 'recommendation', 'recommendations'
       )
  ) or exists (
    select 1 from public.intake_responses
    where private.references_retired_recommendation_v1(responses)
       or private.references_retired_recommendation_v1(metadata)
  ) or exists (
    select 1 from public.memory_entries
    where private.references_retired_recommendation_v1(evidence)
       or private.references_retired_recommendation_v1(metadata)
  ) or exists (
    select 1 from public.notifications
    where private.references_retired_recommendation_v1(metadata)
  ) or exists (
    select 1 from public.tasks
    where private.references_retired_recommendation_v1(metadata)
  ) or exists (
    select 1 from public.user_state_snapshots
    where private.references_retired_recommendation_v1(summary)
       or private.references_retired_recommendation_v1(signals)
       or private.references_retired_recommendation_v1(metadata)
  ) then
    raise exception 'Recommendation retirement left a structured reference.';
  end if;

  if to_regclass('public.decision_feedback') is not null
     or to_regclass('public.recommendations') is not null
     or to_regprocedure(
       'public.replace_current_recommendations_v2(uuid,jsonb,timestamp with time zone)'
     ) is not null
     or to_regprocedure(
       'public.persist_weekly_review_v2(uuid,text,timestamp with time zone,jsonb)'
     ) is not null
     or to_regprocedure(
       'public.generated_notification_before_retirement_v1(uuid,uuid,text,text,date,timestamp with time zone,text,text,text,text,text,text,text,text,text,timestamp with time zone)'
     ) is not null then
    raise exception 'Recommendation retirement left a retired database object.';
  end if;
  if exists (
    select 1
    from pg_attribute
    where attrelid = 'public.daily_briefings'::regclass
      and attname = 'recommendation_ids'
      and not attisdropped
  ) then
    raise exception 'Recommendation retirement left the Briefing id column.';
  end if;

  if to_regclass('public.skillset_profiles') is null
     or not exists (
       select 1
       from pg_attribute
       where attrelid = 'public.ai_insights'::regclass
         and attname = 'recommendation'
         and not attisdropped
     ) then
    raise exception 'Recommendation retirement removed a preserved concept.';
  end if;
  if not has_function_privilege(
       'service_role',
       'public.claim_coach_request_v6(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.claim_coach_request_v6(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.claim_coach_request_v5(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.claim_coach_request_v1(uuid,uuid,text,text,date,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.claim_coach_request_v2(uuid,uuid,text,text,jsonb,date,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)',
       'EXECUTE'
     ) then
    raise exception 'Recommendation retirement left invalid Coach grants.';
  end if;
end;
$$;

drop function private.sanitize_retired_recommendation_v1(jsonb);

commit;
