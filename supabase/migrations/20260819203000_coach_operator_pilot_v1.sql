-- Explicit operator-funded pilot Coach with durable dispatch accounting.

alter table public.coach_requests
  add column provider_dispatch_required boolean;

update public.coach_requests r
set provider_dispatch_required = case
  when r.response is not null
    then coalesce((r.response #>> '{provenance,provider_called}')::boolean, false)
  when r.state = 'failed'
    then coalesce((
      select (u.counters ->> 'provider_called')::boolean
      from public.coach_usage_events u
      where u.request_id = r.request_id
    ), false)
  else true
end;

alter table public.coach_requests
  alter column provider_dispatch_required set default true,
  alter column provider_dispatch_required set not null;

create or replace function private.coach_error_is_valid_v1(p_value jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select private.coach_jsonb_has_exact_keys(
      p_value,
      array['code', 'message', 'retryable']
    )
    and jsonb_typeof(p_value -> 'code') is not distinct from 'string'
    and p_value ->> 'code' in (
      'provider_disabled', 'provider_unavailable', 'missing_cli',
      'not_logged_in', 'unavailable_model', 'account_limit',
      'provider_limit', 'provider_failure', 'timeout', 'provider_timeout',
      'invalid_output', 'tool_free_unavailable', 'unsafe_provider_event',
      'context_failure', 'interrupted', 'snapshot_too_large', 'tool_limit',
      'fast_mode_unavailable'
    )
    and jsonb_typeof(p_value -> 'message') is not distinct from 'string'
    and char_length(p_value ->> 'message') between 1 and 300
    and jsonb_typeof(p_value -> 'retryable') is not distinct from 'boolean';
$$;

revoke all on function private.coach_error_is_valid_v1(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_error_is_valid_v1(jsonb)
  to service_role;

create function private.coach_response_is_valid_v4(
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
  if p_value ->> 'contract_version' is distinct from 'coach-response-v4'
     or p_value #>> '{provenance,prompt_version}'
       is distinct from 'free-coach-agent-prompt-v5'
     or p_value #>> '{provenance,context_version}'
       is distinct from 'personal-snapshot-v3' then
    return false;
  end if;

  normalized := jsonb_set(
    p_value,
    '{contract_version}',
    '"coach-response-v3"'::jsonb,
    false
  );

  if p_value #>> '{provenance,provider}' = 'operator_codex_pilot' then
    if p_value #>> '{provenance,provider_mode}'
         is distinct from 'operator_subscription_pilot'
       or p_value #>> '{provenance,model_requested}'
         is distinct from 'gpt-5.5'
       or (
         p_value #>> '{provenance,model_reported}' is not null
         and p_value #>> '{provenance,model_reported}' <> 'gpt-5.5'
       )
       or p_value #>> '{provenance,model_source}' is distinct from 'explicit'
       or p_value #>> '{provenance,service_tier}' is distinct from 'fast'
       or p_value #>> '{provenance,service_tier_status}'
         is distinct from 'configured'
       or (p_value #>> '{provenance,fast_mode}')::boolean is not true then
      return false;
    end if;
    normalized := jsonb_set(
      jsonb_set(
        normalized,
        '{provenance,provider}',
        '"local_codex_oauth"'::jsonb,
        false
      ),
      '{provenance,provider_mode}',
      '"local_development_only"'::jsonb,
      false
    );
  end if;

  return private.coach_response_is_valid_v3(
    normalized,
    p_request_id,
    p_evidence
  );
exception
  when others then
    return false;
end;
$$;

revoke all on function private.coach_response_is_valid_v4(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v4(jsonb, uuid, jsonb)
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
begin
  if p_value ->> 'contract_version' = 'coach-response-v4' then
    return private.coach_response_is_valid_v4(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;
  if p_value ->> 'contract_version' = 'coach-response-v3' then
    return private.coach_response_is_valid_v3(
      p_value,
      p_request_id,
      p_used_context
    );
  end if;
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

revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  to service_role;

alter table public.coach_requests
  drop constraint coach_requests_contract,
  drop constraint coach_requests_context_scope,
  drop constraint coach_requests_provider,
  drop constraint coach_requests_provider_mode,
  drop constraint coach_requests_versions,
  drop constraint coach_requests_used_context,
  drop constraint coach_requests_response,
  drop constraint coach_requests_agent_fields;

alter table public.coach_requests
  add constraint coach_requests_contract check (
    contract_version in (
      'coach-request-v1', 'coach-request-v2', 'coach-request-v3',
      'coach-request-v4'
    )
  ),
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
    or (
      contract_version in ('coach-request-v3', 'coach-request-v4')
      and context_scope = 'today'
      and context_parameters = '{}'::jsonb
    )
  ),
  add constraint coach_requests_provider check (
    provider in (
      'disabled', 'local_codex_oauth', 'fake', 'openai', 'gemini',
      'operator_codex_pilot'
    )
  ),
  add constraint coach_requests_provider_mode check (
    provider_mode in (
      'disabled', 'local_development_only', 'deterministic_test_only',
      'user_supplied_key', 'operator_subscription_pilot'
    )
  ),
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
      and prompt_version in (
        'free-coach-agent-prompt-v4', 'free-coach-agent-prompt-v5'
      )
      and context_version = 'personal-snapshot-v3'
    )
    or (
      contract_version = 'coach-request-v4'
      and prompt_version = 'free-coach-agent-prompt-v5'
      and context_version = 'personal-snapshot-v3'
    )
  ),
  add constraint coach_requests_used_context check (
    (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and private.coach_used_context_is_valid_v1(used_context)
    )
    or (
      contract_version in ('coach-request-v3', 'coach-request-v4')
      and private.coach_evidence_is_valid_v1(used_context)
    )
  ),
  add constraint coach_requests_response check (
    response is null
    or (
      contract_version in ('coach-request-v1', 'coach-request-v2')
      and response ->> 'contract_version' = 'coach-response-v1'
      and private.coach_response_is_valid_v1(response, request_id, used_context)
    )
    or (
      contract_version = 'coach-request-v3'
      and response ->> 'contract_version' in (
        'coach-response-v2', 'coach-response-v3'
      )
      and private.coach_response_is_valid_v1(response, request_id, used_context)
    )
    or (
      contract_version = 'coach-request-v4'
      and response ->> 'contract_version' = 'coach-response-v4'
      and private.coach_response_is_valid_v4(response, request_id, used_context)
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
      contract_version in ('coach-request-v3', 'coach-request-v4')
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
          and provider_dispatch_required is not distinct from
            (response #>> '{provenance,provider_called}')::boolean
        )
        or (
          state = 'failed'
          and evidence is null
          and agent_trace is null
          and tool_call_count is null
          and service_tier is null
        )
        or (
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
              and tool_call_count = (agent_trace ->> 'tool_call_count')::int
              and service_tier in ('fast', 'not_applicable')
            )
          )
        )
        or (
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
              and tool_call_count = (agent_trace ->> 'tool_call_count')::int
              and service_tier in ('fast', 'not_applicable')
            )
          )
        )
      )
    )
  );

alter table public.coach_usage_events
  drop constraint coach_usage_events_provider,
  drop constraint coach_usage_events_provider_mode;

alter table public.coach_usage_events
  add constraint coach_usage_events_provider check (
    provider in (
      'disabled', 'local_codex_oauth', 'fake', 'openai', 'gemini',
      'operator_codex_pilot'
    )
  ),
  add constraint coach_usage_events_provider_mode check (
    provider_mode in (
      'disabled', 'local_development_only', 'deterministic_test_only',
      'user_supplied_key', 'operator_subscription_pilot'
    )
  );

alter table public.coach_usage_events
  drop constraint coach_usage_events_error_code,
  add constraint coach_usage_events_error_code check (
    (
      outcome = 'failed'
      and error_code is not null
      and error_code in (
        'provider_disabled', 'provider_unavailable', 'missing_cli',
        'not_logged_in', 'unavailable_model', 'account_limit',
        'provider_limit', 'provider_failure', 'timeout', 'provider_timeout',
        'invalid_output', 'tool_free_unavailable', 'unsafe_provider_event',
        'context_failure', 'interrupted', 'snapshot_too_large', 'tool_limit',
        'fast_mode_unavailable'
      )
    )
    or (outcome <> 'failed' and error_code is null)
  );

create table public.coach_operator_daily_budgets (
  utc_date date primary key,
  dispatch_count int not null,
  first_dispatched_at timestamptz not null,
  last_dispatched_at timestamptz not null,
  constraint coach_operator_daily_budgets_count check (
    dispatch_count between 1 and 15
  ),
  constraint coach_operator_daily_budgets_timestamps check (
    last_dispatched_at >= first_dispatched_at
    and (first_dispatched_at at time zone 'UTC')::date = utc_date
    and (last_dispatched_at at time zone 'UTC')::date = utc_date
  )
);

alter table public.coach_operator_daily_budgets enable row level security;
alter table public.coach_operator_daily_budgets force row level security;

revoke all on table public.coach_operator_daily_budgets
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.coach_operator_daily_budgets
  to service_role;

create policy "coach_operator_daily_budgets_service_role_all"
  on public.coach_operator_daily_budgets
  for all
  to service_role
  using (true)
  with check (true);

create table public.coach_operator_dispatches (
  dispatch_id uuid primary key,
  request_id uuid not null,
  user_id uuid not null,
  reservation_id uuid not null unique,
  utc_date date not null,
  state text not null default 'dispatched',
  error_code text,
  dispatched_at timestamptz not null,
  terminal_at timestamptz,
  constraint coach_operator_dispatches_request_key unique (request_id),
  constraint coach_operator_dispatches_request_owner_fk
    foreign key (request_id, user_id)
    references public.coach_requests (request_id, user_id)
    on delete cascade,
  constraint coach_operator_dispatches_state check (
    state in ('dispatched', 'completed', 'failed', 'interrupted')
  ),
  constraint coach_operator_dispatches_error check (
    (
      state = 'completed'
      and error_code is null
      and terminal_at is not null
    )
    or (
      state in ('failed', 'interrupted')
      and error_code is not null
      and char_length(error_code) between 1 and 64
      and terminal_at is not null
    )
    or (
      state = 'dispatched'
      and error_code is null
      and terminal_at is null
    )
  ),
  constraint coach_operator_dispatches_timestamps check (
    terminal_at is null or terminal_at >= dispatched_at
  )
);

create index coach_operator_dispatches_utc_date_idx
  on public.coach_operator_dispatches (utc_date, dispatched_at, dispatch_id);
create index coach_operator_dispatches_owner_idx
  on public.coach_operator_dispatches (user_id, dispatched_at, dispatch_id);

alter table public.coach_operator_dispatches enable row level security;
alter table public.coach_operator_dispatches force row level security;

revoke all on table public.coach_operator_dispatches
  from public, anon, authenticated, service_role;
grant select, insert, update on table public.coach_operator_dispatches
  to service_role;

create policy "coach_operator_dispatches_service_role_all"
  on public.coach_operator_dispatches
  for all
  to service_role
  using (true)
  with check (true);

create function public.claim_coach_request_v8(
  p_user_id uuid,
  p_contract_version text,
  p_request_id uuid,
  p_message_fingerprint text,
  p_local_date date,
  p_provider text,
  p_provider_mode text,
  p_model_requested text,
  p_model_source text,
  p_claimed_at timestamptz,
  p_lease_expires_at timestamptz,
  p_daily_limit int,
  p_provider_dispatch_required boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  existing public.coach_requests%rowtype;
  active_request public.coach_requests%rowtype;
  result jsonb;
  total_used int;
  provider_used int;
  remaining_count int;
  provider_was_dispatched boolean;
  interrupted_error constant jsonb := jsonb_build_object(
    'code', 'interrupted',
    'message', 'The Coach request expired before completion.',
    'retryable', true
  );
  interrupted_usage jsonb;
begin
  if p_user_id is null
     or p_contract_version not in ('coach-request-v3', 'coach-request-v4')
     or p_request_id is null
     or p_local_date is null
     or p_claimed_at is null
     or p_lease_expires_at is null
     or p_provider is null
     or p_provider_mode is null
     or p_model_source is null
     or p_daily_limit is null
     or p_provider_dispatch_required is null
     or p_message_fingerprint is null
     or p_message_fingerprint !~ '^[0-9a-f]{64}$'
     or p_lease_expires_at <= p_claimed_at
     or p_lease_expires_at > p_claimed_at + interval '5 minutes'
     or (
       p_contract_version = 'coach-request-v4'
       and p_provider not in ('openai', 'gemini', 'operator_codex_pilot')
     )
     or (
       p_provider = 'openai'
       and (
         p_provider_mode <> 'user_supplied_key'
         or p_model_requested is distinct from 'gpt-5.6-terra'
         or p_model_source <> 'explicit'
       )
     )
     or (
       p_provider = 'gemini'
       and (
         p_provider_mode <> 'user_supplied_key'
         or p_model_requested is distinct from 'gemini-3.6-flash'
         or p_model_source <> 'explicit'
       )
     )
     or (
       p_provider = 'operator_codex_pilot'
       and (
         p_contract_version <> 'coach-request-v4'
         or p_provider_mode <> 'operator_subscription_pilot'
         or p_model_requested is distinct from 'gpt-5.5'
         or p_model_source <> 'explicit'
         or p_daily_limit <> 5
       )
     )
     or (p_provider <> 'operator_codex_pilot' and p_daily_limit <> 20) then
    raise exception 'Coach V8 claim is invalid' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into existing
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if found then
    if existing.user_id <> p_user_id
       or existing.contract_version <> p_contract_version
       or existing.provider <> p_provider
       or existing.provider_mode <> p_provider_mode
       or existing.model_requested is distinct from p_model_requested
       or existing.model_source <> p_model_source
       or existing.provider_dispatch_required
         is distinct from p_provider_dispatch_required
       or (
         existing.state <> 'deleted'
         and existing.message_fingerprint <> p_message_fingerprint
       ) then
      raise exception 'Coach request id was already used with different input'
        using errcode = 'PT409';
    end if;

    if p_contract_version = 'coach-request-v3' then
      return public.claim_coach_request_v7(
        p_user_id, p_request_id, p_message_fingerprint, p_local_date,
        p_provider, p_provider_mode, p_model_requested, p_model_source,
        p_claimed_at, p_lease_expires_at, 20
      );
    end if;

    select count(*)::int into total_used
    from public.coach_requests
    where user_id = p_user_id and local_date = existing.local_date;
    select count(*)::int into provider_used
    from public.coach_requests
    where user_id = p_user_id
      and local_date = existing.local_date
      and provider = 'operator_codex_pilot'
      and provider_dispatch_required;
    remaining_count := case
      when p_provider = 'operator_codex_pilot'
        then greatest(5 - provider_used, 0)
      else greatest(20 - total_used, 0)
    end;

    if existing.state = 'deleted' then
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
    if existing.state = 'pending'
       and existing.lease_expires_at <= p_claimed_at then
      select exists (
        select 1 from public.coach_operator_dispatches d
        where d.request_id = p_request_id
      ) into provider_was_dispatched;
      interrupted_usage := jsonb_build_object(
        'provider_called', provider_was_dispatched,
        'prompt_bytes', 0,
        'context_bytes', 0,
        'reply_codepoints', 0
      );
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

  if p_contract_version = 'coach-request-v3' then
    result := public.claim_coach_request_v7(
      p_user_id, p_request_id, p_message_fingerprint, p_local_date,
      p_provider, p_provider_mode, p_model_requested, p_model_source,
      p_claimed_at, p_lease_expires_at, 20
    );
    if result ->> 'state' = 'pending' then
      update public.coach_requests
      set provider_dispatch_required = p_provider_dispatch_required
      where request_id = p_request_id and user_id = p_user_id;
    end if;
    return result;
  end if;

  select * into active_request
  from public.coach_requests
  where user_id = p_user_id and state = 'pending'
  limit 1
  for update;
  if found and active_request.lease_expires_at <= p_claimed_at then
    select exists (
      select 1 from public.coach_operator_dispatches d
      where d.request_id = active_request.request_id
    ) into provider_was_dispatched;
    interrupted_usage := jsonb_build_object(
      'provider_called', provider_was_dispatched,
      'prompt_bytes', 0,
      'context_bytes', 0,
      'reply_codepoints', 0
    );
    perform public.fail_coach_request_v1(
      p_user_id,
      active_request.request_id,
      interrupted_error,
      interrupted_usage,
      p_claimed_at
    );
    active_request := null;
  end if;

  select count(*)::int into total_used
  from public.coach_requests
  where user_id = p_user_id and local_date = p_local_date;
  select count(*)::int into provider_used
  from public.coach_requests
  where user_id = p_user_id
    and local_date = p_local_date
    and provider = 'operator_codex_pilot'
    and provider_dispatch_required;

  if active_request.request_id is not null then
    return jsonb_build_object(
      'state', 'in_progress',
      'remaining_requests', case
        when p_provider = 'operator_codex_pilot'
          then greatest(5 - provider_used, 0)
        else greatest(20 - total_used, 0)
      end,
      'response', null,
      'error', null
    );
  end if;
  if total_used >= 20
     or (
       p_provider = 'operator_codex_pilot'
       and p_provider_dispatch_required
       and provider_used >= 5
     ) then
    raise exception 'Coach daily request limit reached' using errcode = 'PT429';
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
    provider_dispatch_required,
    created_at,
    updated_at
  ) values (
    p_request_id,
    p_user_id,
    'coach-request-v4',
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
    'free-coach-agent-prompt-v5',
    'personal-snapshot-v3',
    p_provider_dispatch_required,
    p_claimed_at,
    p_claimed_at
  );

  return jsonb_build_object(
    'state', 'pending',
    'remaining_requests', case
      when p_provider = 'operator_codex_pilot'
        then greatest(5 - provider_used - (
          case when p_provider_dispatch_required then 1 else 0 end
        ), 0)
      else greatest(20 - total_used - 1, 0)
    end,
    'response', null,
    'error', null
  );
end;
$$;

revoke all on function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v8(
  uuid, text, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int, boolean
) to service_role;

create function public.complete_coach_request_v3(
  p_user_id uuid,
  p_request_id uuid,
  p_user_message text,
  p_response jsonb,
  p_evidence jsonb,
  p_agent_trace jsonb,
  p_tool_call_count int,
  p_service_tier text,
  p_usage jsonb,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  target public.coach_requests%rowtype;
  result jsonb;
begin
  if p_user_id is null
     or p_request_id is null
     or p_response is null
     or p_response ->> 'contract_version' <> 'coach-response-v4'
     or p_evidence is null
     or p_agent_trace is null
     or p_tool_call_count is null
     or p_service_tier is null
     or p_usage is null
     or p_completed_at is null
     or not private.coach_evidence_is_valid_v1(p_evidence)
     or not private.coach_agent_trace_is_valid_v1(p_agent_trace)
     or not private.coach_response_is_valid_v4(
       p_response,
       p_request_id,
       p_evidence
     )
     or p_response -> 'evidence' is distinct from p_evidence
     or p_response -> 'agent_trace' is distinct from p_agent_trace
     or p_tool_call_count <> (p_agent_trace ->> 'tool_call_count')::int
     or p_tool_call_count not between 0 and 12
     or p_service_tier is distinct from
       p_response #>> '{provenance,service_tier}'
     or p_service_tier not in ('fast', 'not_applicable') then
    raise exception 'Coach V3 completion is invalid' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));
  select * into target
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if not found
     or target.user_id <> p_user_id
     or target.contract_version <> 'coach-request-v4'
     or target.provider_dispatch_required is distinct from
       (p_response #>> '{provenance,provider_called}')::boolean then
    raise exception 'Coach V4 request identity does not match'
      using errcode = 'PT409';
  end if;

  if target.state = 'completed' then
    if target.evidence is distinct from p_evidence
       or target.agent_trace is distinct from p_agent_trace
       or target.tool_call_count is distinct from p_tool_call_count
       or target.service_tier is distinct from p_service_tier then
      raise exception 'Coach V3 completion replay differs'
        using errcode = 'PT409';
    end if;
  elsif target.state = 'pending' then
    update public.coach_requests
    set evidence = p_evidence,
        agent_trace = p_agent_trace,
        tool_call_count = p_tool_call_count,
        service_tier = p_service_tier
    where request_id = p_request_id;
  else
    raise exception 'Coach V4 request is already terminal'
      using errcode = 'PT409';
  end if;

  result := public.complete_coach_request_v1(
    p_user_id,
    p_request_id,
    p_user_message,
    p_response,
    p_evidence,
    p_usage,
    p_completed_at
  );
  return result;
end;
$$;

revoke all on function public.complete_coach_request_v3(
  uuid, uuid, text, jsonb, jsonb, jsonb, int, text, jsonb, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.complete_coach_request_v3(
  uuid, uuid, text, jsonb, jsonb, jsonb, int, text, jsonb, timestamptz
) to service_role;

create function public.record_coach_operator_dispatch_v1(
  p_dispatch_id uuid,
  p_request_id uuid,
  p_user_id uuid,
  p_reservation_id uuid,
  p_dispatched_at timestamptz,
  p_global_limit int
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  target public.coach_requests%rowtype;
  existing public.coach_operator_dispatches%rowtype;
  used_count int;
  dispatch_date date;
begin
  if p_dispatch_id is null
     or p_request_id is null
     or p_user_id is null
     or p_reservation_id is null
     or p_dispatched_at is null
     or p_global_limit <> 15 then
    raise exception 'Coach operator dispatch is invalid' using errcode = '22023';
  end if;
  dispatch_date := (p_dispatched_at at time zone 'UTC')::date;
  perform pg_advisory_xact_lock(hashtextextended(dispatch_date::text, 12));
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into existing
  from public.coach_operator_dispatches
  where dispatch_id = p_dispatch_id or request_id = p_request_id
  for update;
  if found then
    if existing.dispatch_id <> p_dispatch_id
       or existing.request_id <> p_request_id
       or existing.user_id <> p_user_id
       or existing.reservation_id <> p_reservation_id then
      raise exception 'Coach operator dispatch identity conflicts'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object('state', 'existing');
  end if;

  select * into target
  from public.coach_requests
  where request_id = p_request_id
  for update;
  if not found
     or target.user_id <> p_user_id
     or target.contract_version <> 'coach-request-v4'
     or target.provider <> 'operator_codex_pilot'
     or target.provider_mode <> 'operator_subscription_pilot'
     or not target.provider_dispatch_required
     or target.state <> 'pending'
     or target.lease_expires_at <= p_dispatched_at then
    raise exception 'Coach operator dispatch request is not eligible'
      using errcode = 'PT409';
  end if;

  select budget.dispatch_count into used_count
  from public.coach_operator_daily_budgets as budget
  where budget.utc_date = dispatch_date
  for update;
  if not found then
    used_count := 0;
  end if;
  if used_count >= p_global_limit then
    raise exception 'Coach operator global limit reached' using errcode = 'PT429';
  end if;

  insert into public.coach_operator_daily_budgets as budget (
    utc_date,
    dispatch_count,
    first_dispatched_at,
    last_dispatched_at
  ) values (
    dispatch_date,
    1,
    p_dispatched_at,
    p_dispatched_at
  )
  on conflict (utc_date) do update
  set dispatch_count = budget.dispatch_count + 1,
      last_dispatched_at = greatest(
        budget.last_dispatched_at,
        excluded.last_dispatched_at
      );

  insert into public.coach_operator_dispatches (
    dispatch_id,
    request_id,
    user_id,
    reservation_id,
    utc_date,
    state,
    dispatched_at
  ) values (
    p_dispatch_id,
    p_request_id,
    p_user_id,
    p_reservation_id,
    dispatch_date,
    'dispatched',
    p_dispatched_at
  );
  return jsonb_build_object('state', 'dispatched');
end;
$$;

create function public.finish_coach_operator_dispatch_v1(
  p_dispatch_id uuid,
  p_request_id uuid,
  p_state text,
  p_error_code text,
  p_terminal_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  target public.coach_operator_dispatches%rowtype;
begin
  if p_dispatch_id is null
     or p_request_id is null
     or p_state not in ('completed', 'failed', 'interrupted')
     or p_terminal_at is null
     or (
       (p_state = 'completed' and p_error_code is not null)
       or (
         p_state <> 'completed'
         and (
           p_error_code is null
           or char_length(p_error_code) not between 1 and 64
         )
       )
     ) then
    raise exception 'Coach operator terminal dispatch is invalid'
      using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));
  select * into target
  from public.coach_operator_dispatches
  where dispatch_id = p_dispatch_id
  for update;
  if not found or target.request_id <> p_request_id then
    raise exception 'Coach operator dispatch does not match'
      using errcode = 'PT409';
  end if;
  if target.state <> 'dispatched' then
    if target.state <> p_state
       or target.error_code is distinct from p_error_code then
      raise exception 'Coach operator terminal replay differs'
        using errcode = 'PT409';
    end if;
    return jsonb_build_object('state', 'existing');
  end if;
  if p_terminal_at < target.dispatched_at then
    raise exception 'Coach operator terminal time is invalid'
      using errcode = '22023';
  end if;
  update public.coach_operator_dispatches
  set state = p_state,
      error_code = p_error_code,
      terminal_at = p_terminal_at
  where dispatch_id = p_dispatch_id;
  return jsonb_build_object('state', p_state);
end;
$$;

create function public.reconcile_expired_coach_operator_dispatches_v1(
  p_reconciled_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  item record;
  request_row public.coach_requests%rowtype;
  reconciled_count int := 0;
  interrupted_error constant jsonb := jsonb_build_object(
    'code', 'interrupted',
    'message', 'The Coach request expired before completion.',
    'retryable', true
  );
  interrupted_usage constant jsonb := jsonb_build_object(
    'provider_called', true,
    'prompt_bytes', 0,
    'context_bytes', 0,
    'reply_codepoints', 0
  );
begin
  if p_reconciled_at is null then
    raise exception 'Coach operator reconciliation time is required'
      using errcode = '22023';
  end if;
  for item in
    select d.dispatch_id, d.request_id, d.user_id
    from public.coach_operator_dispatches d
    join public.coach_requests r
      on r.request_id = d.request_id and r.user_id = d.user_id
    where d.state = 'dispatched'
      and (
        r.state <> 'pending'
        or r.lease_expires_at <= p_reconciled_at
      )
    order by d.dispatched_at, d.dispatch_id
    limit 100
  loop
    perform pg_advisory_xact_lock(hashtextextended(item.user_id::text, 11));
    perform pg_advisory_xact_lock(hashtextextended(item.request_id::text, 10));
    perform 1
    from public.coach_operator_dispatches d
    where d.dispatch_id = item.dispatch_id and d.state = 'dispatched'
    for update;
    if not found then
      continue;
    end if;
    select * into request_row
    from public.coach_requests r
    where r.request_id = item.request_id and r.user_id = item.user_id
    for update;
    if not found then
      raise exception 'Coach operator dispatch lost its request'
        using errcode = 'PT409';
    end if;
    if request_row.state = 'pending' then
      perform public.fail_coach_request_v1(
        item.user_id,
        item.request_id,
        interrupted_error,
        interrupted_usage,
        p_reconciled_at
      );
      update public.coach_operator_dispatches
      set state = 'interrupted',
          error_code = 'interrupted',
          terminal_at = p_reconciled_at
      where dispatch_id = item.dispatch_id;
    elsif request_row.state = 'completed' then
      update public.coach_operator_dispatches
      set state = 'completed',
          terminal_at = p_reconciled_at
      where dispatch_id = item.dispatch_id;
    else
      update public.coach_operator_dispatches
      set state = 'failed',
          error_code = coalesce(request_row.error ->> 'code', 'interrupted'),
          terminal_at = p_reconciled_at
      where dispatch_id = item.dispatch_id;
    end if;
    reconciled_count := reconciled_count + 1;
  end loop;
  return jsonb_build_object(
    'state', 'reconciled',
    'reconciled_count', reconciled_count
  );
end;
$$;

revoke all on function public.record_coach_operator_dispatch_v1(
  uuid, uuid, uuid, uuid, timestamptz, int
) from public, anon, authenticated, service_role;
revoke all on function public.finish_coach_operator_dispatch_v1(
  uuid, uuid, text, text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.reconcile_expired_coach_operator_dispatches_v1(
  timestamptz
) from public, anon, authenticated, service_role;

grant execute on function public.record_coach_operator_dispatch_v1(
  uuid, uuid, uuid, uuid, timestamptz, int
) to service_role;
grant execute on function public.finish_coach_operator_dispatch_v1(
  uuid, uuid, text, text, timestamptz
) to service_role;
grant execute on function public.reconcile_expired_coach_operator_dispatches_v1(
  timestamptz
) to service_role;

revoke all on function public.claim_coach_request_v7(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
