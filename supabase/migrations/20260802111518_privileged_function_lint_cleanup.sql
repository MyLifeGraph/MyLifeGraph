-- Remove the remaining local schema-lint diagnostics without editing applied
-- history or widening any application-role authority.

-- Retained legacy policies on older databases may still depend on this public
-- helper. Keep its identity, but delegate to the canonical protected role
-- projection instead of consulting the mutable optional CamelCase table.
create or replace function public.current_app_role()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select private.current_app_role();
$$;

revoke all on function public.current_app_role()
  from public, anon, authenticated, service_role;

-- This is the established Account Delete V1 body. The only behavioral-source
-- cleanup is removal of the explicitly declared legacy_index variable:
-- integer FOR loops create their own scoped variable automatically.
create or replace function public.delete_account_v1(
  p_user_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  auth_user_found boolean;
  deleted_user_id uuid;
  legacy_owner_column text;
  legacy_owner_column_exists boolean;
  legacy_owner_columns constant text[] := array[
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'id'
  ];
  legacy_rows_remain boolean;
  legacy_table_name text;
  legacy_table_names constant text[] := array[
    'FocusSession',
    'CoachMessage',
    'AIInsight',
    'ActivityLog',
    'DailyLog',
    'MemoryEntry',
    'MoodLog',
    'Notification',
    'ScheduleItem',
    'SleepLog',
    'Task',
    'Habit',
    'Goal',
    'User'
  ];
  legacy_table regclass;
  legacy_tables regclass[] := array[]::regclass[];
begin
  if p_user_id is null or p_confirmation is distinct from 'DELETE' then
    raise exception 'Exact account deletion confirmation is required'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 12));

  perform 1
  from public.calendar_request_identities
  where user_id = p_user_id
  order by request_id
  for update;

  perform 1
  from public.calendar_connections
  where user_id = p_user_id
  order by id
  for update;

  perform 1 from auth.users where id = p_user_id for update;
  auth_user_found := found;

  perform 1 from public.profiles where id = p_user_id for update;

  if cardinality(legacy_table_names) <> cardinality(legacy_owner_columns) then
    raise exception 'Legacy account owner mapping is invalid'
      using errcode = 'P0001';
  end if;

  for legacy_index in 1..cardinality(legacy_table_names)
  loop
    legacy_table_name := legacy_table_names[legacy_index];
    legacy_owner_column := legacy_owner_columns[legacy_index];
    legacy_table := to_regclass(format('public.%I', legacy_table_name));
    legacy_tables[legacy_index] := legacy_table;
    continue when legacy_table is null;

    execute format(
      'lock table public.%I in share row exclusive mode',
      legacy_table_name
    );

    select exists (
      select 1
      from pg_attribute
      where attrelid = legacy_table
        and attname = legacy_owner_column
        and attnum > 0
        and not attisdropped
    )
    into legacy_owner_column_exists;

    if not legacy_owner_column_exists then
      raise exception 'Legacy owner mapping is unavailable for table %',
        legacy_table_name
        using errcode = 'P0001';
    end if;
  end loop;

  delete from public.focus_sessions where user_id = p_user_id;

  for legacy_index in 1..cardinality(legacy_table_names)
  loop
    legacy_table_name := legacy_table_names[legacy_index];
    legacy_owner_column := legacy_owner_columns[legacy_index];
    legacy_table := legacy_tables[legacy_index];
    continue when legacy_table is null;

    execute format(
      'delete from public.%I where lower(%I::text) = $1',
      legacy_table_name,
      legacy_owner_column
    ) using p_user_id::text;
  end loop;

  for legacy_index in 1..cardinality(legacy_table_names)
  loop
    legacy_table_name := legacy_table_names[legacy_index];
    legacy_owner_column := legacy_owner_columns[legacy_index];
    legacy_table := legacy_tables[legacy_index];
    continue when legacy_table is null;
    execute format(
      'select exists (select 1 from public.%I where lower(%I::text) = $1)',
      legacy_table_name,
      legacy_owner_column
    ) into legacy_rows_remain using p_user_id::text;

    if legacy_rows_remain then
      raise exception 'Legacy account deletion did not complete for table %',
        legacy_table_name
        using errcode = 'P0001';
    end if;
  end loop;

  if not auth_user_found then
    if exists (select 1 from public.profiles where id = p_user_id) then
      raise exception 'Account deletion cascade did not complete'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'deleted', false,
      'not_found', true,
      'user_id', p_user_id
    );
  end if;

  delete from auth.users
  where id = p_user_id
  returning id into deleted_user_id;

  if deleted_user_id is null
     or exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Account deletion cascade did not complete'
      using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'deleted', true,
    'not_found', false,
    'user_id', deleted_user_id
  );
end;
$$;

revoke all on function public.delete_account_v1(uuid, text)
  from public, anon, authenticated;
grant execute on function public.delete_account_v1(uuid, text)
  to service_role;

-- Preserve the established V3 claim contract while expressing the deliberate
-- discard of fail_coach_request_v1's response with PERFORM.
create or replace function public.claim_coach_request_v3(
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
  result jsonb;
  used_count int;
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
    raise exception 'Coach V3 claim is invalid'
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

  result := public.claim_coach_request_v2(
    p_user_id,
    p_request_id,
    p_message_fingerprint,
    'today',
    '{}'::jsonb,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    'controlled-coach-prompt-v3',
    'coach-context-v3',
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit
  );

  if result ->> 'state' = 'pending' then
    update public.coach_requests
    set contract_version = 'coach-request-v3',
        prompt_version = 'free-coach-agent-prompt-v1',
        context_version = 'personal-snapshot-v1'
    where request_id = p_request_id
      and user_id = p_user_id
      and contract_version = 'coach-request-v2';
    if not found then
      raise exception 'Coach V3 claim transition failed'
        using errcode = 'PT409';
    end if;
  end if;
  return result;
end;
$$;

revoke all on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated;
grant execute on function public.claim_coach_request_v3(
  uuid, uuid, text, date, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;
