-- Reuse existing durable Coach budgets without turning a draft into a chat or check-in.
alter table public.coach_requests add column purpose text not null default 'chat'
  check (purpose in ('chat', 'daily_capture_draft'));
alter table public.coach_requests add column draft_completion_fingerprint text
  check (draft_completion_fingerprint is null or (
    purpose = 'daily_capture_draft' and state = 'deleted'
    and draft_completion_fingerprint ~ '^[0-9a-f]{64}$'
  ));

create function public.probe_coach_operation_v1(
  p_user_id uuid, p_contract_version text, p_request_id uuid, p_message_fingerprint text,
  p_provider text, p_provider_mode text, p_model_requested text, p_model_source text,
  p_provider_dispatch_required boolean, p_purpose text default 'chat'
)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare existing public.coach_requests%rowtype;
begin
  if p_user_id is null or p_request_id is null or p_purpose is null
     or p_purpose not in ('chat', 'daily_capture_draft')
     or (p_purpose = 'daily_capture_draft' and p_contract_version is distinct from 'coach-request-v4') then
    raise exception 'Invalid Coach operation.' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  if (public.get_account_deletion_pending_v2(p_user_id) ->> 'pending')::boolean then
    raise exception 'Account deletion is pending.' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 11));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text, 10));
  select * into existing from public.coach_requests where request_id = p_request_id;
  if found and (existing.user_id <> p_user_id or existing.purpose <> p_purpose) then
    raise exception 'Coach operation identity conflicts.' using errcode = 'PT409';
  end if;
  return public.probe_coach_terminal_replay_v1(p_user_id, p_contract_version, p_request_id,
    p_message_fingerprint, p_provider, p_provider_mode, p_model_requested,
    p_model_source, p_provider_dispatch_required);
end;
$$;
revoke all on function public.probe_coach_operation_v1(uuid,text,uuid,text,text,text,text,text,boolean,text)
  from public, anon, authenticated;
grant execute on function public.probe_coach_operation_v1(uuid,text,uuid,text,text,text,text,text,boolean,text)
  to service_role;

create function public.claim_coach_operation_v1(
  p_user_id uuid, p_contract_version text, p_request_id uuid,
  p_message_fingerprint text, p_local_date date, p_provider text,
  p_provider_mode text, p_model_requested text, p_model_source text,
  p_claimed_at timestamptz, p_lease_expires_at timestamptz, p_daily_limit int,
  p_provider_dispatch_required boolean, p_purpose text default 'chat'
)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  existing public.coach_requests%rowtype;
  request_exists boolean;
  result jsonb;
begin
  if p_user_id is null or p_request_id is null or p_purpose is null
     or p_purpose not in ('chat', 'daily_capture_draft')
     or (p_purpose = 'daily_capture_draft' and p_contract_version is distinct from 'coach-request-v4') then
    raise exception 'Invalid Coach operation.' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  if (public.get_account_deletion_pending_v2(p_user_id) ->> 'pending')::boolean then
    raise exception 'Account deletion is pending.' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 11));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text, 10));
  select * into existing from public.coach_requests where request_id = p_request_id;
  request_exists := found;
  if request_exists and (existing.user_id <> p_user_id or existing.purpose <> p_purpose) then
    raise exception 'Coach operation identity conflicts.' using errcode = 'PT409';
  end if;
  result := public.claim_coach_request_v8(p_user_id, p_contract_version, p_request_id,
    p_message_fingerprint, p_local_date, p_provider, p_provider_mode, p_model_requested,
    p_model_source, p_claimed_at, p_lease_expires_at, p_daily_limit, p_provider_dispatch_required);
  if not request_exists and result ->> 'state' = 'pending' then
    update public.coach_requests set purpose = p_purpose
      where request_id = p_request_id and user_id = p_user_id;
  end if;
  return result;
end;
$$;
revoke all on function public.claim_coach_operation_v1(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,int,boolean,text)
  from public, anon, authenticated;
grant execute on function public.claim_coach_operation_v1(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,int,boolean,text)
  to service_role;

create function private.guard_capture_draft_messages_v1()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if exists (select 1 from public.coach_requests where request_id = new.request_id
             and purpose = 'daily_capture_draft') then
    raise exception 'Drafts cannot create conversation messages.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_capture_draft_messages_v1() from public, anon, authenticated;
create trigger guard_capture_draft_messages_v1 before insert or update on public.coach_messages
  for each row execute function private.guard_capture_draft_messages_v1();

create function public.complete_capture_draft_v1(
  p_user_id uuid, p_request_id uuid, p_response jsonb, p_usage jsonb, p_completed_at timestamptz
)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  target public.coach_requests%rowtype;
  usage_event public.coach_usage_events%rowtype;
  provenance jsonb := p_response -> 'provenance';
  completion_fingerprint text;
  operator_dispatch_id uuid;
begin
  if p_user_id is null or p_request_id is null or p_completed_at is null
     or p_response is null or p_usage is null
     or not private.coach_response_is_valid_v4(p_response, p_request_id, '[]'::jsonb)
     or not private.coach_usage_is_valid_v1(p_usage)
     or p_response ->> 'reply' is distinct from 'Check-in draft prepared. Review the fields before saving.'
     or p_response -> 'uncertainty' is distinct from '{"level":"low","reason":"No check-in has been saved."}'::jsonb
     or p_response -> 'safety' is distinct from '{"classification":"normal"}'::jsonb
     or p_response -> 'evidence' is distinct from '[]'::jsonb
     or p_response #> '{agent_trace,steps}' is distinct from '[]'::jsonb
     or p_response #>> '{agent_trace,tool_call_count}' is distinct from '0'
     or provenance ->> 'snapshot_row_count' is distinct from '0'
     or provenance ->> 'source' is distinct from 'model'
     or (p_usage ->> 'reply_codepoints')::int <> length(p_response ->> 'reply')
     or (p_usage ->> 'provider_called')::boolean is distinct from true
     or (provenance ->> 'provider_called')::boolean is distinct from true then
    raise exception 'Invalid redacted draft completion.' using errcode = '22023';
  end if;
  -- Completion accepts only fixed copy and allowlisted provenance, never draft text.
  if p_response #> '{agent_trace,limitations}' is distinct from '[]'::jsonb then
    raise exception 'Draft completion cannot retain transcript context.' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  if (public.get_account_deletion_pending_v2(p_user_id) ->> 'pending')::boolean then
    raise exception 'Account deletion is pending.' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 11));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text, 10));
  select * into target from public.coach_requests where request_id = p_request_id for update;
  if not found or target.user_id <> p_user_id or target.purpose <> 'daily_capture_draft'
     or target.contract_version <> 'coach-request-v4'
     or target.provider_dispatch_required is distinct from true
     or provenance ->> 'provider' is distinct from target.provider
     or provenance ->> 'provider_mode' is distinct from target.provider_mode
     or provenance ->> 'model_requested' is distinct from target.model_requested
     or provenance ->> 'model_source' is distinct from target.model_source
     or provenance ->> 'prompt_version' is distinct from target.prompt_version
     or provenance ->> 'context_version' is distinct from target.context_version
     or p_completed_at < target.created_at then
    raise exception 'Draft completion identity conflicts.' using errcode = 'PT409';
  end if;
  completion_fingerprint := encode(sha256(convert_to(jsonb_build_array(
    p_response, p_usage, extract(epoch from p_completed_at)
  )::text, 'UTF8')), 'hex');
  if target.state = 'deleted' then
    select * into usage_event from public.coach_usage_events where request_id = p_request_id;
    if target.draft_completion_fingerprint is distinct from completion_fingerprint
       or usage_event.counters is distinct from p_usage
       or usage_event.outcome is distinct from 'completed' then
      raise exception 'Draft completion replay differs.' using errcode = 'PT409';
    end if;
    return jsonb_build_object('state', 'completed', 'response', p_response);
  end if;
  if target.state <> 'pending' then
    raise exception 'Draft operation is already terminal.' using errcode = 'PT409';
  end if;
  if target.provider = 'operator_codex_pilot' then
    select dispatch_id into operator_dispatch_id from public.coach_operator_dispatches
      where request_id = p_request_id and user_id = p_user_id;
    if not found then
      raise exception 'Draft operator dispatch is missing.' using errcode = 'PT409';
    end if;
    -- Close the dispatch in this transaction. An API crash cannot leave a
    -- successful content-tombstone for an older reconciler to mark interrupted.
    perform public.finish_coach_operator_dispatch_v1(
      operator_dispatch_id, p_request_id, 'completed', null, p_completed_at
    );
  end if;
  -- Existing clients list completed requests as conversations. Use the existing
  -- content-discarded state, retaining honest completed usage and quota identity.
  update public.coach_requests set state = 'deleted', lease_expires_at = null,
    message_fingerprint = null, model_reported = provenance ->> 'model_reported',
    response = null, error = null, used_context = '[]'::jsonb,
    evidence = null, agent_trace = null, tool_call_count = null, service_tier = null,
    completed_at = null, failed_at = null, deleted_at = p_completed_at,
    updated_at = p_completed_at, draft_completion_fingerprint = completion_fingerprint
  where request_id = p_request_id;
  insert into public.coach_usage_events(request_id, user_id, local_date, outcome,
    provider, provider_mode, model_requested, model_reported, model_source, error_code, counters, created_at)
  values (p_request_id, p_user_id, target.local_date, 'completed', target.provider,
    target.provider_mode, target.model_requested, provenance ->> 'model_reported',
    target.model_source, null, p_usage, p_completed_at);
  return jsonb_build_object('state', 'completed', 'response', p_response);
end;
$$;
revoke all on function public.complete_capture_draft_v1(uuid,uuid,jsonb,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function public.complete_capture_draft_v1(uuid,uuid,jsonb,jsonb,timestamptz) to service_role;
