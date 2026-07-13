-- Phase 10: bounded, retry-safe Coach persistence and memory selection.
--
-- The model invocation remains outside a database transaction. A request is
-- first claimed without its message, then completed or failed atomically. The
-- separate usage ledger survives conversation-history deletion so deleting
-- content cannot reset the profile-local daily budget.

create or replace function private.coach_jsonb_has_exact_keys(
  p_value jsonb,
  p_keys text[]
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
begin
  if p_value is null
     or p_keys is null
     or jsonb_typeof(p_value) <> 'object' then
    return false;
  end if;
  return (p_value ?& p_keys)
    and not exists (
      select 1
      from jsonb_object_keys(p_value) as actual(key)
      where not (actual.key = any (p_keys))
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
         'goals',
         'tasks',
         'habits',
         'focus_sessions',
         'weekly_review',
         'memories',
         'coach_history'
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
  uncertainty jsonb;
  suggestion jsonb;
  safety jsonb;
  provenance jsonb;
  generated_at_text text;
  generated_at_value timestamptz;
begin
  if not private.coach_jsonb_has_exact_keys(
    p_value,
    array[
      'contract_version',
      'request_id',
      'reply',
      'uncertainty',
      'staged_suggestion',
      'safety',
      'used_context',
      'provenance'
    ]
  )
     or jsonb_typeof(p_value -> 'contract_version') <> 'string'
     or p_value ->> 'contract_version' <> 'coach-response-v1'
     or jsonb_typeof(p_value -> 'request_id') <> 'string'
     or p_value ->> 'request_id' <> p_request_id::text
     or jsonb_typeof(p_value -> 'reply') <> 'string'
     or char_length(p_value ->> 'reply') not between 1 and 4000
     or p_value -> 'used_context' is distinct from p_used_context
     or not private.coach_used_context_is_valid_v1(p_used_context) then
    return false;
  end if;

  uncertainty := p_value -> 'uncertainty';
  if not private.coach_jsonb_has_exact_keys(
    uncertainty,
    array['level', 'reason']
  )
     or jsonb_typeof(uncertainty -> 'level') <> 'string'
     or uncertainty ->> 'level' not in ('low', 'medium', 'high')
     or jsonb_typeof(uncertainty -> 'reason') <> 'string'
     or char_length(uncertainty ->> 'reason') not between 1 and 300 then
    return false;
  end if;

  suggestion := p_value -> 'staged_suggestion';
  if jsonb_typeof(suggestion) <> 'null' then
    if not private.coach_jsonb_has_exact_keys(
      suggestion,
      array['title', 'rationale']
    )
       or jsonb_typeof(suggestion -> 'title') <> 'string'
       or char_length(suggestion ->> 'title') not between 1 and 120
       or jsonb_typeof(suggestion -> 'rationale') <> 'string'
       or char_length(suggestion ->> 'rationale') not between 1 and 500 then
      return false;
    end if;
  end if;

  safety := p_value -> 'safety';
  if not private.coach_jsonb_has_exact_keys(safety, array['classification'])
     or jsonb_typeof(safety -> 'classification') <> 'string'
     or safety ->> 'classification' not in (
       'normal', 'sensitive', 'safety_redirect'
     ) then
    return false;
  end if;

  provenance := p_value -> 'provenance';
  if not private.coach_jsonb_has_exact_keys(
    provenance,
    array[
      'source',
      'provider',
      'provider_mode',
      'model_requested',
      'model_reported',
      'model_source',
      'prompt_version',
      'context_version',
      'generated_at',
      'provider_called'
    ]
  )
     or jsonb_typeof(provenance -> 'source') <> 'string'
     or provenance ->> 'source' not in ('model', 'deterministic_safety')
     or jsonb_typeof(provenance -> 'provider') <> 'string'
     or provenance ->> 'provider' not in (
       'disabled', 'local_codex_oauth', 'fake'
     )
     or jsonb_typeof(provenance -> 'provider_mode') <> 'string'
     or provenance ->> 'provider_mode' not in (
       'disabled', 'local_development_only', 'deterministic_test_only'
     )
     or jsonb_typeof(provenance -> 'model_source') <> 'string'
     or provenance ->> 'model_source' not in (
       'explicit', 'cli_default', 'not_applicable'
     )
     or jsonb_typeof(provenance -> 'prompt_version') <> 'string'
     or provenance ->> 'prompt_version' <> 'controlled-coach-prompt-v1'
     or jsonb_typeof(provenance -> 'context_version') <> 'string'
     or provenance ->> 'context_version' <> 'coach-context-v1'
     or jsonb_typeof(provenance -> 'generated_at') <> 'string'
     or jsonb_typeof(provenance -> 'provider_called') <> 'boolean'
     or (
       provenance ->> 'source' = 'model'
       and (provenance ->> 'provider_called')::boolean is not true
     )
     or (
       provenance ->> 'source' = 'deterministic_safety'
       and (provenance ->> 'provider_called')::boolean is not false
     ) then
    return false;
  end if;

  if jsonb_typeof(provenance -> 'model_requested') not in ('string', 'null')
     or jsonb_typeof(provenance -> 'model_reported') not in ('string', 'null')
     or (
       jsonb_typeof(provenance -> 'model_requested') = 'string'
       and char_length(provenance ->> 'model_requested') not between 1 and 100
     )
     or (
       jsonb_typeof(provenance -> 'model_reported') = 'string'
       and char_length(provenance ->> 'model_reported') not between 1 and 100
     ) then
    return false;
  end if;

  generated_at_text := provenance ->> 'generated_at';
  if generated_at_text !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then
    return false;
  end if;
  generated_at_value := generated_at_text::timestamptz;
  return generated_at_value is not null;
exception
  when others then
    return false;
end;
$$;

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
    and jsonb_typeof(p_value -> 'code') = 'string'
    and p_value ->> 'code' in (
      'provider_disabled',
      'provider_unavailable',
      'missing_cli',
      'not_logged_in',
      'unavailable_model',
      'account_limit',
      'provider_failure',
      'timeout',
      'invalid_output',
      'tool_free_unavailable',
      'unsafe_provider_event',
      'context_failure',
      'interrupted'
    )
    and jsonb_typeof(p_value -> 'message') = 'string'
    and char_length(p_value ->> 'message') between 1 and 300
    and jsonb_typeof(p_value -> 'retryable') = 'boolean';
$$;

create or replace function private.coach_usage_is_valid_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  prompt_bytes numeric;
  context_bytes numeric;
  reply_codepoints numeric;
begin
  if not private.coach_jsonb_has_exact_keys(
      p_value,
      array[
        'provider_called',
        'prompt_bytes',
        'context_bytes',
        'reply_codepoints'
      ]
    )
     or jsonb_typeof(p_value -> 'provider_called') <> 'boolean'
     or jsonb_typeof(p_value -> 'prompt_bytes') <> 'number'
     or jsonb_typeof(p_value -> 'context_bytes') <> 'number'
     or jsonb_typeof(p_value -> 'reply_codepoints') <> 'number' then
    return false;
  end if;

  prompt_bytes := (p_value ->> 'prompt_bytes')::numeric;
  context_bytes := (p_value ->> 'context_bytes')::numeric;
  reply_codepoints := (p_value ->> 'reply_codepoints')::numeric;
  return prompt_bytes between 0 and 131072
    and trunc(prompt_bytes) = prompt_bytes
    and context_bytes between 0 and 32768
    and trunc(context_bytes) = context_bytes
    and reply_codepoints between 0 and 4000
    and trunc(reply_codepoints) = reply_codepoints;
exception
  when others then
    return false;
end;
$$;

revoke all on function private.coach_jsonb_has_exact_keys(jsonb, text[])
  from public, anon, authenticated;
revoke all on function private.coach_used_context_is_valid_v1(jsonb)
  from public, anon, authenticated;
revoke all on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function private.coach_error_is_valid_v1(jsonb)
  from public, anon, authenticated;
revoke all on function private.coach_usage_is_valid_v1(jsonb)
  from public, anon, authenticated;
grant execute on function private.coach_jsonb_has_exact_keys(jsonb, text[])
  to service_role;
grant execute on function private.coach_used_context_is_valid_v1(jsonb)
  to service_role;
grant execute on function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
  to service_role;
grant execute on function private.coach_error_is_valid_v1(jsonb)
  to service_role;
grant execute on function private.coach_usage_is_valid_v1(jsonb)
  to service_role;

create table public.coach_requests (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  contract_version text not null default 'coach-request-v1',
  context_scope text not null,
  local_date date not null,
  message_fingerprint text,
  state text not null default 'pending',
  lease_expires_at timestamptz,
  provider text not null,
  provider_mode text not null,
  model_requested text,
  model_reported text,
  model_source text not null,
  prompt_version text not null,
  context_version text not null,
  response jsonb,
  used_context jsonb not null default '[]'::jsonb,
  error jsonb,
  created_at timestamptz not null,
  completed_at timestamptz,
  failed_at timestamptz,
  deleted_at timestamptz,
  updated_at timestamptz not null,
  constraint coach_requests_request_id_key unique (request_id),
  constraint coach_requests_request_owner_key unique (request_id, user_id),
  constraint coach_requests_contract check (
    contract_version = 'coach-request-v1'
  ),
  constraint coach_requests_context_scope check (context_scope = 'today'),
  constraint coach_requests_state check (
    state in ('pending', 'completed', 'failed', 'deleted')
  ),
  constraint coach_requests_message_fingerprint check (
    message_fingerprint is null
    or message_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint coach_requests_provider check (
    provider in ('disabled', 'local_codex_oauth', 'fake')
  ),
  constraint coach_requests_provider_mode check (
    provider_mode in (
      'disabled', 'local_development_only', 'deterministic_test_only'
    )
  ),
  constraint coach_requests_model_source check (
    model_source in ('explicit', 'cli_default', 'not_applicable')
  ),
  constraint coach_requests_model_requested check (
    model_requested is null
    or char_length(model_requested) between 1 and 100
  ),
  constraint coach_requests_model_reported check (
    model_reported is null
    or char_length(model_reported) between 1 and 100
  ),
  constraint coach_requests_model_identity check (
    (model_source = 'explicit' and model_requested is not null)
    or (model_source in ('cli_default', 'not_applicable') and model_requested is null)
  ),
  constraint coach_requests_versions check (
    prompt_version = 'controlled-coach-prompt-v1'
    and context_version = 'coach-context-v1'
  ),
  constraint coach_requests_used_context check (
    private.coach_used_context_is_valid_v1(used_context)
  ),
  constraint coach_requests_response check (
    response is null
    or private.coach_response_is_valid_v1(response, request_id, used_context)
  ),
  constraint coach_requests_error check (
    error is null or private.coach_error_is_valid_v1(error)
  ),
  constraint coach_requests_timestamps check (
    updated_at >= created_at
    and (completed_at is null or completed_at >= created_at)
    and (failed_at is null or failed_at >= created_at)
    and (deleted_at is null or deleted_at >= created_at)
  ),
  constraint coach_requests_lifecycle check (
    (
      state = 'pending'
      and message_fingerprint is not null
      and lease_expires_at is not null
      and lease_expires_at > created_at
      and response is null
      and used_context = '[]'::jsonb
      and error is null
      and completed_at is null
      and failed_at is null
      and deleted_at is null
    )
    or (
      state = 'completed'
      and message_fingerprint is not null
      and lease_expires_at is null
      and response is not null
      and error is null
      and completed_at is not null
      and failed_at is null
      and deleted_at is null
    )
    or (
      state = 'failed'
      and message_fingerprint is not null
      and lease_expires_at is null
      and response is null
      and used_context = '[]'::jsonb
      and error is not null
      and completed_at is null
      and failed_at is not null
      and deleted_at is null
    )
    or (
      state = 'deleted'
      and message_fingerprint is null
      and lease_expires_at is null
      and response is null
      and used_context = '[]'::jsonb
      and error is null
      and completed_at is null
      and failed_at is null
      and deleted_at is not null
    )
  )
);

create unique index coach_requests_one_pending_per_user_idx
  on public.coach_requests (user_id)
  where state = 'pending';

create index coach_requests_owner_local_date_idx
  on public.coach_requests (user_id, local_date, created_at desc, request_id);

create table public.coach_usage_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  user_id uuid not null,
  local_date date not null,
  outcome text not null,
  provider text not null,
  provider_mode text not null,
  model_requested text,
  model_reported text,
  model_source text not null,
  error_code text,
  counters jsonb not null,
  created_at timestamptz not null,
  constraint coach_usage_events_request_key unique (request_id),
  constraint coach_usage_events_request_owner_fk
    foreign key (request_id, user_id)
    references public.coach_requests (request_id, user_id)
    on delete cascade,
  constraint coach_usage_events_outcome check (
    outcome in ('completed', 'failed', 'safety_redirect')
  ),
  constraint coach_usage_events_provider check (
    provider in ('disabled', 'local_codex_oauth', 'fake')
  ),
  constraint coach_usage_events_provider_mode check (
    provider_mode in (
      'disabled', 'local_development_only', 'deterministic_test_only'
    )
  ),
  constraint coach_usage_events_model_source check (
    model_source in ('explicit', 'cli_default', 'not_applicable')
  ),
  constraint coach_usage_events_model_lengths check (
    (model_requested is null or char_length(model_requested) between 1 and 100)
    and (model_reported is null or char_length(model_reported) between 1 and 100)
  ),
  constraint coach_usage_events_model_identity check (
    (model_source = 'explicit' and model_requested is not null)
    or (model_source in ('cli_default', 'not_applicable') and model_requested is null)
  ),
  constraint coach_usage_events_error_code check (
    (
      outcome = 'failed'
      and error_code in (
        'provider_disabled',
        'provider_unavailable',
        'missing_cli',
        'not_logged_in',
        'unavailable_model',
        'account_limit',
        'provider_failure',
        'timeout',
        'invalid_output',
        'tool_free_unavailable',
        'unsafe_provider_event',
        'context_failure',
        'interrupted'
      )
    )
    or (outcome <> 'failed' and error_code is null)
  ),
  constraint coach_usage_events_counters check (
    private.coach_usage_is_valid_v1(counters)
  )
);

create index coach_usage_events_owner_local_date_idx
  on public.coach_usage_events (user_id, local_date, created_at, request_id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'memory_entries_id_user_key'
      and conrelid = 'public.memory_entries'::regclass
  ) then
    alter table public.memory_entries
      add constraint memory_entries_id_user_key unique (id, user_id);
  end if;
end;
$$;

create table public.coach_memory_selections (
  user_id uuid not null references public.profiles (id) on delete cascade,
  memory_id uuid not null,
  selection_version text not null default 'coach-memory-selection-v1',
  selected_at timestamptz not null,
  primary key (user_id, memory_id),
  constraint coach_memory_selections_memory_owner_fk
    foreign key (memory_id, user_id)
    references public.memory_entries (id, user_id)
    on delete cascade,
  constraint coach_memory_selections_version check (
    selection_version = 'coach-memory-selection-v1'
  )
);

create index coach_memory_selections_owner_order_idx
  on public.coach_memory_selections (user_id, selected_at desc, memory_id);

alter table public.coach_messages
  add column request_id uuid,
  add column contract_version text;

alter table public.coach_messages
  add constraint coach_messages_request_owner_fk
    foreign key (request_id, user_id)
    references public.coach_requests (request_id, user_id)
    on delete cascade,
  add constraint coach_messages_request_role_key unique (request_id, role),
  add constraint coach_messages_legacy_or_v1 check (
    (
      request_id is null
      and contract_version is null
    )
    or (
      request_id is not null
      and contract_version = 'coach-message-v1'
      and role in ('user', 'assistant')
      and metadata = '{}'::jsonb
      and (
        (role = 'user' and char_length(content) between 1 and 2000)
        or (role = 'assistant' and char_length(content) between 1 and 4000)
      )
    )
  );

create index coach_messages_owner_history_v1_idx
  on public.coach_messages (user_id, created_at desc, id desc)
  where request_id is not null;

alter table public.coach_requests enable row level security;
alter table public.coach_requests force row level security;
alter table public.coach_usage_events enable row level security;
alter table public.coach_usage_events force row level security;
alter table public.coach_memory_selections enable row level security;
alter table public.coach_memory_selections force row level security;
alter table public.coach_messages enable row level security;
alter table public.coach_messages force row level security;
alter table public.memory_entries enable row level security;
alter table public.memory_entries force row level security;

drop policy if exists "coach_messages_own_or_admin_all"
  on public.coach_messages;
drop policy if exists "memory_entries_own_or_admin_all"
  on public.memory_entries;

revoke all on table public.coach_requests
  from public, anon, authenticated, service_role;
revoke all on table public.coach_usage_events
  from public, anon, authenticated, service_role;
revoke all on table public.coach_memory_selections
  from public, anon, authenticated, service_role;
revoke all on table public.coach_messages
  from public, anon, authenticated, service_role;
revoke all on table public.memory_entries
  from public, anon, authenticated, service_role;

grant select, insert, update, delete on table public.coach_requests
  to service_role;
grant select, insert on table public.coach_usage_events
  to service_role;
grant select, insert, delete on table public.coach_messages
  to service_role;
grant select, insert, update, delete on table public.memory_entries
  to service_role;
grant select, insert, delete on table public.coach_memory_selections
  to service_role;

grant select on table public.coach_messages to authenticated;
grant select on table public.memory_entries to authenticated;
grant select on table public.coach_memory_selections to authenticated;

create policy "coach_requests_service_role_all"
  on public.coach_requests
  for all
  to service_role
  using (true)
  with check (true);

create policy "coach_usage_events_service_role_select"
  on public.coach_usage_events
  for select
  to service_role
  using (true);

create policy "coach_usage_events_service_role_insert"
  on public.coach_usage_events
  for insert
  to service_role
  with check (true);

create policy "coach_messages_own_or_admin_select"
  on public.coach_messages
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "coach_messages_service_role_select"
  on public.coach_messages
  for select
  to service_role
  using (true);

create policy "coach_messages_service_role_insert"
  on public.coach_messages
  for insert
  to service_role
  with check (true);

create policy "coach_messages_service_role_delete"
  on public.coach_messages
  for delete
  to service_role
  using (true);

create policy "memory_entries_own_or_admin_select"
  on public.memory_entries
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "memory_entries_service_role_all"
  on public.memory_entries
  for all
  to service_role
  using (true)
  with check (true);

create policy "coach_memory_selections_own_or_admin_select"
  on public.coach_memory_selections
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "coach_memory_selections_service_role_select"
  on public.coach_memory_selections
  for select
  to service_role
  using (true);

create policy "coach_memory_selections_service_role_insert"
  on public.coach_memory_selections
  for insert
  to service_role
  with check (true);

create policy "coach_memory_selections_service_role_delete"
  on public.coach_memory_selections
  for delete
  to service_role
  using (true);

create or replace function public.claim_coach_request_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_message_fingerprint text,
  p_context_scope text,
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
     or p_provider is null
     or p_provider_mode is null
     or p_model_source is null
     or p_prompt_version is null
     or p_context_version is null
     or p_daily_limit is null
     or p_message_fingerprint is null
     or p_message_fingerprint !~ '^[0-9a-f]{64}$'
     or p_context_scope is distinct from 'today'
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
     or p_prompt_version is distinct from 'controlled-coach-prompt-v1'
     or p_context_version is distinct from 'coach-context-v1'
     or p_lease_expires_at <= p_claimed_at
     or p_lease_expires_at > p_claimed_at + interval '5 minutes'
     or p_daily_limit not between 1 and 100 then
    raise exception 'Coach claim is invalid'
      using errcode = '22023';
  end if;

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

    perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));

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

    -- Only client-owned request semantics define replay identity. Local date,
    -- provider, model, prompt, and context configuration are frozen from the
    -- original claim and may legitimately differ on a later HTTP retry.
    if existing.message_fingerprint <> p_message_fingerprint
       or existing.context_scope <> p_context_scope then
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

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));

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
    context_scope,
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
    p_context_scope,
    p_local_date,
    p_message_fingerprint,
    'pending',
    p_lease_expires_at,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    p_prompt_version,
    p_context_version,
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

create or replace function public.complete_coach_request_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_user_message text,
  p_response jsonb,
  p_used_context jsonb,
  p_usage jsonb,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.coach_requests%rowtype;
  usage_event public.coach_usage_events%rowtype;
  linked_message_count int;
  user_message text;
  assistant_message text;
  computed_fingerprint text;
  usage_outcome text;
  response_provenance jsonb;
begin
  if p_user_id is null
     or p_request_id is null
     or p_completed_at is null
     or p_user_message is null
     or p_user_message <> btrim(p_user_message)
     or char_length(p_user_message) not between 1 and 2000
     or p_response is null
     or p_used_context is null
     or p_usage is null
     or not private.coach_response_is_valid_v1(
       p_response,
       p_request_id,
       p_used_context
     )
     or not private.coach_usage_is_valid_v1(p_usage) then
    raise exception 'Coach completion is invalid'
      using errcode = '22023';
  end if;

  if (p_usage ->> 'reply_codepoints')::int
       <> char_length(p_response ->> 'reply') then
    raise exception 'Coach completion usage is inconsistent'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into target
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if not found or target.user_id <> p_user_id then
    raise exception 'Coach request identity does not match'
      using errcode = 'PT409';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));

  computed_fingerprint := encode(
    extensions.digest(convert_to(p_user_message, 'UTF8'), 'sha256'),
    'hex'
  );
  response_provenance := p_response -> 'provenance';

  if target.message_fingerprint <> computed_fingerprint
     or response_provenance ->> 'provider' <> target.provider
     or response_provenance ->> 'provider_mode' <> target.provider_mode
     or response_provenance ->> 'model_requested'
          is distinct from target.model_requested
     or response_provenance ->> 'model_source' <> target.model_source
     or response_provenance ->> 'prompt_version' <> target.prompt_version
     or response_provenance ->> 'context_version' <> target.context_version
     or (p_usage ->> 'provider_called')::boolean
          is distinct from (response_provenance ->> 'provider_called')::boolean then
    raise exception 'Coach completion does not match its claim'
      using errcode = 'PT409';
  end if;

  if p_completed_at < target.created_at then
    raise exception 'Coach completion timestamp is invalid'
      using errcode = '22023';
  end if;

  if target.state = 'completed' then
    select * into usage_event
    from public.coach_usage_events
    where request_id = p_request_id;

    select
      count(*)::int,
      max(content) filter (where role = 'user'),
      max(content) filter (where role = 'assistant')
    into linked_message_count, user_message, assistant_message
    from public.coach_messages
    where request_id = p_request_id and user_id = p_user_id;

    if target.response is distinct from p_response
       or target.used_context is distinct from p_used_context
       or usage_event.counters is distinct from p_usage
       or linked_message_count <> 2
       or user_message is distinct from p_user_message
       or assistant_message is distinct from p_response ->> 'reply' then
      raise exception 'Coach completion replay differs from stored result'
        using errcode = 'PT409';
    end if;

    return jsonb_build_object(
      'state', 'completed',
      'response', target.response
    );
  end if;

  if target.state <> 'pending' then
    raise exception 'Coach request is already terminal'
      using errcode = 'PT409';
  end if;

  usage_outcome := case
    when p_response -> 'safety' ->> 'classification' = 'safety_redirect'
      then 'safety_redirect'
    else 'completed'
  end;

  insert into public.coach_messages (
    user_id,
    request_id,
    contract_version,
    role,
    content,
    metadata,
    created_at
  ) values
  (
    p_user_id,
    p_request_id,
    'coach-message-v1',
    'user',
    p_user_message,
    '{}'::jsonb,
    target.created_at
  ),
  (
    p_user_id,
    p_request_id,
    'coach-message-v1',
    'assistant',
    p_response ->> 'reply',
    '{}'::jsonb,
    p_completed_at
  );

  update public.coach_requests
  set state = 'completed',
      lease_expires_at = null,
      model_reported = response_provenance ->> 'model_reported',
      response = p_response,
      used_context = p_used_context,
      completed_at = p_completed_at,
      updated_at = p_completed_at
  where request_id = p_request_id;

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
    p_request_id,
    p_user_id,
    target.local_date,
    usage_outcome,
    target.provider,
    target.provider_mode,
    target.model_requested,
    response_provenance ->> 'model_reported',
    target.model_source,
    null,
    p_usage,
    p_completed_at
  );

  return jsonb_build_object(
    'state', 'completed',
    'response', p_response
  );
end;
$$;

create or replace function public.fail_coach_request_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_error jsonb,
  p_usage jsonb,
  p_failed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.coach_requests%rowtype;
  usage_event public.coach_usage_events%rowtype;
begin
  if p_user_id is null
     or p_request_id is null
     or p_failed_at is null
     or p_error is null
     or p_usage is null
     or not private.coach_error_is_valid_v1(p_error)
     or not private.coach_usage_is_valid_v1(p_usage)
     or (p_usage ->> 'reply_codepoints')::int <> 0 then
    raise exception 'Coach failure is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10));

  select * into target
  from public.coach_requests
  where request_id = p_request_id
  for update;

  if not found or target.user_id <> p_user_id then
    raise exception 'Coach request identity does not match'
      using errcode = 'PT409';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));

  if p_failed_at < target.created_at then
    raise exception 'Coach failure timestamp is invalid'
      using errcode = '22023';
  end if;

  if target.state = 'failed' then
    select * into usage_event
    from public.coach_usage_events
    where request_id = p_request_id;

    if target.error is distinct from p_error
       or usage_event.outcome is distinct from 'failed'
       or usage_event.error_code is distinct from p_error ->> 'code'
       or usage_event.counters is distinct from p_usage then
      raise exception 'Coach failure replay differs from stored result'
        using errcode = 'PT409';
    end if;

    return jsonb_build_object(
      'state', 'failed',
      'error', target.error
    );
  end if;

  if target.state <> 'pending' then
    raise exception 'Coach request is already terminal'
      using errcode = 'PT409';
  end if;

  update public.coach_requests
  set state = 'failed',
      lease_expires_at = null,
      error = p_error,
      failed_at = p_failed_at,
      updated_at = p_failed_at
  where request_id = p_request_id;

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
    p_request_id,
    p_user_id,
    target.local_date,
    'failed',
    target.provider,
    target.provider_mode,
    target.model_requested,
    target.model_reported,
    target.model_source,
    p_error ->> 'code',
    p_usage,
    p_failed_at
  );

  return jsonb_build_object(
    'state', 'failed',
    'error', p_error
  );
end;
$$;

create or replace function public.set_coach_memory_selection_v1(
  p_user_id uuid,
  p_memory_id uuid,
  p_selected boolean,
  p_changed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  selected_count int;
begin
  if p_user_id is null
     or p_memory_id is null
     or p_selected is null
     or p_changed_at is null then
    raise exception 'Coach memory selection is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 12));

  perform 1
  from public.memory_entries
  where id = p_memory_id
    and user_id = p_user_id
    -- Intake's hidden context note and coaching-style projection currently
    -- share type='preference' without a stable sensitivity discriminator.
    -- Keep every preference memory out until a later explicit contract adds
    -- one; do not guess from mutable titles or content.
    and type <> 'preference'
  for key share;

  if not found then
    select count(*)::int into selected_count
    from public.coach_memory_selections
    where user_id = p_user_id;
    return jsonb_build_object(
      'state', 'not_found',
      'selected_count', selected_count
    );
  end if;

  if p_selected then
    if exists (
      select 1
      from public.coach_memory_selections
      where user_id = p_user_id and memory_id = p_memory_id
    ) then
      select count(*)::int into selected_count
      from public.coach_memory_selections
      where user_id = p_user_id;
      return jsonb_build_object(
        'state', 'selected',
        'selected_count', selected_count
      );
    end if;

    select count(*)::int into selected_count
    from public.coach_memory_selections
    where user_id = p_user_id;
    if selected_count >= 8 then
      return jsonb_build_object(
        'state', 'limit_reached',
        'selected_count', selected_count
      );
    end if;

    insert into public.coach_memory_selections (
      user_id,
      memory_id,
      selection_version,
      selected_at
    ) values (
      p_user_id,
      p_memory_id,
      'coach-memory-selection-v1',
      p_changed_at
    );
  else
    delete from public.coach_memory_selections
    where user_id = p_user_id and memory_id = p_memory_id;
  end if;

  select count(*)::int into selected_count
  from public.coach_memory_selections
  where user_id = p_user_id;
  return jsonb_build_object(
    'state', case when p_selected then 'selected' else 'unselected' end,
    'selected_count', selected_count
  );
end;
$$;

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
  active_request public.coach_requests%rowtype;
  deleted_count int;
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
  if p_user_id is null or p_deleted_at is null then
    raise exception 'Coach history deletion is invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));

  if exists (
    select 1
    from public.coach_requests
    where user_id = p_user_id and updated_at > p_deleted_at
  ) then
    raise exception 'Coach history deletion timestamp is invalid'
      using errcode = '22023';
  end if;

  select * into active_request
  from public.coach_requests
  where user_id = p_user_id and state = 'pending'
  limit 1
  for update;

  if found and active_request.lease_expires_at <= p_deleted_at then
    update public.coach_requests
    set state = 'failed',
        lease_expires_at = null,
        error = interrupted_error,
        failed_at = p_deleted_at,
        updated_at = p_deleted_at
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
      p_deleted_at
    ) on conflict (request_id) do nothing;
  elsif found then
    raise exception 'Coach history cannot be deleted during an active request'
      using errcode = 'PT409';
  end if;

  delete from public.coach_messages
  where user_id = p_user_id;

  with tombstoned as (
    update public.coach_requests
    set state = 'deleted',
        message_fingerprint = null,
        lease_expires_at = null,
        response = null,
        used_context = '[]'::jsonb,
        error = null,
        completed_at = null,
        failed_at = null,
        deleted_at = p_deleted_at,
        updated_at = p_deleted_at
    where user_id = p_user_id and state <> 'deleted'
    returning 1
  )
  select count(*)::int into deleted_count from tombstoned;

  return jsonb_build_object(
    'state', 'deleted',
    'deleted_count', deleted_count
  );
end;
$$;

revoke all on function public.claim_coach_request_v1(
  uuid,
  uuid,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  int
) from public, anon, authenticated;
revoke all on function public.complete_coach_request_v1(
  uuid, uuid, text, jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
revoke all on function public.fail_coach_request_v1(
  uuid, uuid, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
revoke all on function public.set_coach_memory_selection_v1(
  uuid, uuid, boolean, timestamptz
) from public, anon, authenticated;
revoke all on function public.delete_coach_history_v1(uuid, timestamptz)
  from public, anon, authenticated;

grant execute on function public.claim_coach_request_v1(
  uuid,
  uuid,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  int
) to service_role;
grant execute on function public.complete_coach_request_v1(
  uuid, uuid, text, jsonb, jsonb, jsonb, timestamptz
) to service_role;
grant execute on function public.fail_coach_request_v1(
  uuid, uuid, jsonb, jsonb, timestamptz
) to service_role;
grant execute on function public.set_coach_memory_selection_v1(
  uuid, uuid, boolean, timestamptz
) to service_role;
grant execute on function public.delete_coach_history_v1(uuid, timestamptz)
  to service_role;
