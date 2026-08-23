-- Add bounded, explicit Coach context modes without changing the established
-- V1 claim path. V2 requests bind their mode parameters to retry identity and
-- use the paired prompt/context V3 provenance.

alter table public.coach_requests
  add column context_parameters jsonb not null default '{}'::jsonb;

create or replace function private.coach_context_parameters_is_valid_v2(
  p_context_scope text,
  p_context_parameters jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  focus_session_id_text text;
begin
  if p_context_scope in ('today', 'review') then
    return p_context_parameters = '{}'::jsonb;
  end if;

  if p_context_scope = 'patterns' then
    return private.coach_jsonb_has_exact_keys(
      p_context_parameters,
      array['horizon']
    )
      and jsonb_typeof(p_context_parameters -> 'horizon') = 'string'
      and p_context_parameters ->> 'horizon' in (
        '90_days',
        '1_year',
        'all_available'
      );
  end if;

  if p_context_scope = 'focus' then
    if not private.coach_jsonb_has_exact_keys(
      p_context_parameters,
      array['focus_session_id']
    )
       or jsonb_typeof(p_context_parameters -> 'focus_session_id') <> 'string'
    then
      return false;
    end if;
    focus_session_id_text := p_context_parameters ->> 'focus_session_id';
    return focus_session_id_text = (focus_session_id_text::uuid)::text;
  end if;

  return false;
exception
  when others then
    return false;
end;
$$;

comment on function private.coach_context_parameters_is_valid_v2(text, jsonb) is
  'Validates the exact bounded parameter object for every coach-request-v2 context scope.';

revoke all on function private.coach_context_parameters_is_valid_v2(text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_context_parameters_is_valid_v2(text, jsonb)
  to service_role;

alter table public.coach_requests
  drop constraint coach_requests_contract,
  add constraint coach_requests_contract check (
    contract_version in ('coach-request-v1', 'coach-request-v2')
  ),
  drop constraint coach_requests_context_scope,
  add constraint coach_requests_context_scope check (
    (
      contract_version = 'coach-request-v1'
      and context_scope = 'today'
      and context_parameters = '{}'::jsonb
    )
    or (
      contract_version = 'coach-request-v2'
      and private.coach_context_parameters_is_valid_v2(
        context_scope,
        context_parameters
      )
    )
  ),
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
  );

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
         'goals',
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

revoke all on function private.coach_used_context_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_used_context_is_valid_v1(jsonb)
  to service_role;

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
declare
  prompt_version text;
  context_version text;
  normalized jsonb;
begin
  prompt_version := p_value #>> '{provenance,prompt_version}';
  context_version := p_value #>> '{provenance,context_version}';

  if prompt_version = 'controlled-coach-prompt-v1'
     and context_version = 'coach-context-v1' then
    return private.coach_response_is_valid_v1_only(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;

  if (
    prompt_version = 'controlled-coach-prompt-v2'
    and context_version = 'coach-context-v2'
  ) or (
    prompt_version = 'controlled-coach-prompt-v3'
    and context_version = 'coach-context-v3'
  ) then
    normalized := jsonb_set(
      jsonb_set(
        p_value,
        '{provenance,prompt_version}',
        to_jsonb('controlled-coach-prompt-v1'::text),
        false
      ),
      '{provenance,context_version}',
      to_jsonb('coach-context-v1'::text),
      false
    );
    return private.coach_response_is_valid_v1_only(
      normalized,
      p_request_id,
      p_used_context
    );
  end if;

  return false;
exception
  when others then
    return false;
end;
$$;

comment on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb) is
  'Validates strict coach-response-v1 envelopes with matching V1, sanitized V2, or sanitized V3 prompt/context provenance.';

revoke all on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) to service_role;

create or replace function public.claim_coach_request_v2(
  p_user_id uuid,
  p_request_id uuid,
  p_message_fingerprint text,
  p_context_scope text,
  p_context_parameters jsonb,
  p_local_date date,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_prompt_version text,
  p_context_version text,
  p_claimed_at timestamptz,
  p_lease_expires_at timestamptz,
  p_daily_limit int
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
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
     or p_context_scope is null
     or p_context_parameters is null
     or p_provider is null
     or p_provider_mode is null
     or p_model_source is null
     or p_prompt_version is null
     or p_context_version is null
     or p_daily_limit is null
     or p_message_fingerprint is null
     or p_message_fingerprint !~ '^[0-9a-f]{64}$'
     or not private.coach_context_parameters_is_valid_v2(
       p_context_scope,
       p_context_parameters
     )
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
       p_model_source = 'explicit' and p_model_requested is null
     )
     or (
       p_model_source in ('cli_default', 'not_applicable')
       and p_model_requested is not null
     )
     or p_prompt_version is distinct from 'controlled-coach-prompt-v3'
     or p_context_version is distinct from 'coach-context-v3'
     or p_lease_expires_at <= p_claimed_at
     or p_lease_expires_at > p_claimed_at + interval '5 minutes'
     or p_daily_limit not between 1 and 100 then
    raise exception 'Coach V2 claim is invalid'
      using errcode = '22023';
  end if;

  -- Keep the established owner-before-request lock order used by completion,
  -- failure, and history deletion.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into existing
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if found then
    if existing.user_id <> p_user_id then
      raise exception 'Coach request id was already used'
        using errcode = 'PT409';
    end if;

    if existing.state = 'deleted' then
      select count(*)::int into used_count
      from public.coach_requests
      where user_id = p_user_id and local_date = existing.local_date;
      remaining_count := greatest(p_daily_limit - used_count, 0);
      return jsonb_build_object(
        'state', 'deleted',
        'remaining_requests', remaining_count,
        'response', null,
        'error', jsonb_build_object(
          'code', 'history_deleted',
          'message', 'This Coach request history was deleted.',
          'retryable', false
        )
      );
    end if;

    -- Only client-owned semantics participate in V2 replay identity. Backend
    -- provider, model, local date, and prompt/context provenance stay frozen
    -- from the original claim and may differ on a later HTTP retry.
    if existing.contract_version <> 'coach-request-v2'
       or existing.message_fingerprint <> p_message_fingerprint
       or existing.context_scope <> p_context_scope
       or existing.context_parameters is distinct from p_context_parameters then
      raise exception 'Coach request id was already used with different input'
        using errcode = 'PT409';
    end if;

    if existing.state = 'pending'
       and existing.lease_expires_at <= p_claimed_at then
      update public.coach_requests
      set state = 'failed',
          lease_expires_at = null,
          error = interrupted_error,
          failed_at = p_claimed_at,
          updated_at = p_claimed_at
      where request_id = existing.request_id;

      insert into public.coach_usage_events (
        request_id,
        user_id,
        local_date,
        outcome,
        provider,
        provider_mode,
        model_requested,
        model_reported,
        model_source,
        error_code,
        counters,
        created_at
      ) values (
        existing.request_id,
        existing.user_id,
        existing.local_date,
        'failed',
        existing.provider,
        existing.provider_mode,
        existing.model_requested,
        existing.model_reported,
        existing.model_source,
        'interrupted',
        interrupted_usage,
        p_claimed_at
      ) on conflict (request_id) do nothing;

      existing.state := 'failed';
      existing.error := interrupted_error;
    end if;

    select count(*)::int into used_count
    from public.coach_requests
    where user_id = p_user_id and local_date = existing.local_date;
    remaining_count := greatest(p_daily_limit - used_count, 0);

    if existing.state = 'completed' then
      return jsonb_build_object(
        'state', 'completed',
        'remaining_requests', remaining_count,
        'response', existing.response,
        'error', null
      );
    elsif existing.state = 'failed' then
      return jsonb_build_object(
        'state', 'failed',
        'remaining_requests', remaining_count,
        'response', null,
        'error', existing.error
      );
    end if;

    return jsonb_build_object(
      'state', 'in_progress',
      'remaining_requests', remaining_count,
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
    update public.coach_requests
    set state = 'failed',
        lease_expires_at = null,
        error = interrupted_error,
        failed_at = p_claimed_at,
        updated_at = p_claimed_at
    where request_id = active_request.request_id;

    insert into public.coach_usage_events (
      request_id,
      user_id,
      local_date,
      outcome,
      provider,
      provider_mode,
      model_requested,
      model_reported,
      model_source,
      error_code,
      counters,
      created_at
    ) values (
      active_request.request_id,
      active_request.user_id,
      active_request.local_date,
      'failed',
      active_request.provider,
      active_request.provider_mode,
      active_request.model_requested,
      active_request.model_reported,
      active_request.model_source,
      'interrupted',
      interrupted_usage,
      p_claimed_at
    ) on conflict (request_id) do nothing;

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
    'coach-request-v2',
    p_context_scope,
    p_context_parameters,
    p_local_date,
    p_message_fingerprint,
    'pending',
    p_lease_expires_at,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    'controlled-coach-prompt-v3',
    'coach-context-v3',
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

comment on function public.claim_coach_request_v2(
  uuid, uuid, text, text, jsonb, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) is
  'Claims one retry-safe coach-request-v2 with exact bounded context parameters and owner-first locking.';

revoke all on function public.claim_coach_request_v2(
  uuid, uuid, text, text, jsonb, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v2(
  uuid, uuid, text, text, jsonb, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;

-- The established history delete predates context_parameters. Keep its tested
-- owner lock, lease expiry, message deletion, usage retention, and retry
-- behavior intact, then erase the new V2 selection data before returning.
alter function public.delete_coach_history_v1(uuid, timestamptz)
  rename to coach_delete_history_v1_before_longitudinal_context;

revoke all on function public.coach_delete_history_v1_before_longitudinal_context(
  uuid, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.delete_coach_history_v1(
  p_user_id uuid,
  p_deleted_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  result := public.coach_delete_history_v1_before_longitudinal_context(
    p_user_id,
    p_deleted_at
  );

  update public.coach_requests
  set context_scope = 'today',
      context_parameters = '{}'::jsonb
  where user_id = p_user_id
    and state = 'deleted'
    and contract_version = 'coach-request-v2'
    and (
      context_scope is distinct from 'today'
      or context_parameters is distinct from '{}'::jsonb
    );

  return result;
end;
$$;

comment on function public.delete_coach_history_v1(uuid, timestamptz) is
  'Deletes Coach history through the established owner-locked V1 body and removes V2 context selection data from retained tombstones.';

revoke all on function public.delete_coach_history_v1(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_coach_history_v1(uuid, timestamptz)
  to service_role;

create index if not exists tasks_user_completed_history_idx
  on public.tasks (user_id, completed_at, id)
  where status = 'done';

create index if not exists tasks_user_cancelled_history_idx
  on public.tasks (user_id, cancelled_at, id)
  where status = 'cancelled';
