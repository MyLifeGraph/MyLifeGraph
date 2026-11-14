-- Add an explicitly versioned manual stopwatch. Timed rows/wire shapes are unchanged.
-- No existing row is rewritten and no history/owner/security boundary is relaxed.
alter table public.focus_sessions alter column planned_minutes drop not null;
alter table public.focus_sessions drop constraint focus_sessions_planned_minutes_check;
alter table public.focus_sessions add constraint focus_sessions_planned_minutes_check check (
  (planned_minutes is null and coalesce(metadata ->> 'contract_version', '') = 'focus-open-end-v1')
  or (planned_minutes is not null and planned_minutes between 5 and 240
      and coalesce(metadata ->> 'contract_version', '') <> 'focus-open-end-v1')
);

create or replace function private.enforce_focus_open_end_v1()
returns trigger language plpgsql security invoker
set search_path = pg_catalog, pg_temp as $$
begin
  if new.metadata ->> 'contract_version' = 'focus-open-end-v1'
     or (tg_op = 'UPDATE' and old.metadata ->> 'contract_version' = 'focus-open-end-v1') then
    -- Trigger is deliberately INVOKER: service-only SECURITY DEFINER RPCs execute
    -- as their trusted owner, while direct authenticated Data API DML cannot.
    if current_user not in ('postgres', 'supabase_admin', 'service_role') then
      raise exception 'Open-end Focus requires the authenticated backend.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and (new.planned_minutes is distinct from old.planned_minutes
       or (new.metadata ->> 'contract_version') is distinct from (old.metadata ->> 'contract_version')) then
      raise exception 'Focus timer mode is immutable.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_focus_open_end_v1() from public, anon, authenticated, service_role;
create trigger focus_sessions_enforce_open_end_v1 before insert or update on public.focus_sessions
for each row execute function private.enforce_focus_open_end_v1();

create or replace function private.focus_session_response_v2(
  p_user_id uuid,
  p_session_id uuid,
  p_replayed boolean
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'contract_version', case when focus.planned_minutes is null
      then 'focus-open-end-v1' else 'focus-session-v2' end,
    'origin', 'authenticated_backend',
    'replayed', p_replayed,
    'id', focus.id,
    'status', focus.status,
    'started_at', focus.started_at,
    'ended_at', focus.ended_at,
    'planned_minutes', focus.planned_minutes,
    'actual_minutes', focus.actual_minutes,
    'label', focus.label,
    'task_id', focus.task_id,
    'habit_id', focus.habit_id,
    'entry_date', focus.metadata ->> 'entry_date',
    'recovery_minutes', coalesce(
      (focus.metadata ->> 'recovery_minutes')::int, 0
    ),
    'updated_at', focus.updated_at,
    'schedule_source', case when source.focus_session_id is null then null
      else jsonb_build_object(
        'source_kind', source.source_kind,
        'block_id', coalesce(
          source.deadline_plan_block_id,
          source.planner_task_block_id
        ),
        'original_starts_at', source.original_starts_at,
        'original_ends_at', source.original_ends_at,
        'original_recovery_minutes', source.original_recovery_minutes
      ) end
  )
  from public.focus_sessions as focus
  left join public.focus_session_schedule_sources as source
    on source.focus_session_id = focus.id and source.user_id = focus.user_id
  where focus.id = p_session_id and focus.user_id = p_user_id;
$$;

revoke all on function private.focus_session_response_v2(uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

create or replace function public.start_focus_open_end_v1(
  p_user_id uuid, p_request_id uuid, p_request_fingerprint text,
  p_recovery_minutes int, p_target_kind text, p_target_id uuid, p_label text, p_now timestamptz
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare
  existing public.focus_sessions%rowtype;
  profile_row public.profiles%rowtype;
  metadata jsonb;
  violated_constraint text;
begin
  if p_user_id is null or p_request_id is null or p_now is null
     or p_request_fingerprint is null or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or p_recovery_minutes is null or (p_recovery_minutes <> 0 and
       (p_recovery_minutes not between 5 and 60 or p_recovery_minutes % 5 <> 0))
     or (p_target_kind is null) <> (p_target_id is null)
     or (p_target_kind is not null and p_target_kind not in ('task', 'habit'))
     or (p_label is not null and (length(p_label) not between 1 and 160 or p_label <> btrim(p_label))) then
    raise exception 'Open-end Focus start request is invalid.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17));
  select * into existing from public.focus_sessions where id = p_request_id for update;
  if found then
    if existing.user_id <> p_user_id
       or existing.metadata ->> 'focus_request_fingerprint' is distinct from p_request_fingerprint
       or existing.metadata ->> 'contract_version' is distinct from 'focus-open-end-v1' then
      raise exception 'focus_request_conflict' using errcode = 'PT409';
    end if;
    return private.focus_session_response_v2(p_user_id, p_request_id, true);
  end if;
  select * into profile_row from public.profiles where id = p_user_id for update;
  if not found or not exists (select 1 from pg_catalog.pg_timezone_names where name = profile_row.timezone) then
    raise exception 'Account timezone is unavailable.' using errcode = 'PT409';
  end if;
  perform 1 from public.focus_sessions where user_id = p_user_id and status = 'active' for update;
  if found then raise exception 'active_focus_session' using errcode = 'PT409'; end if;
  metadata := jsonb_build_object(
    'source', 'flutter-focus-open-end', 'contract_version', 'focus-open-end-v1',
    'entry_date', to_char(p_now at time zone profile_row.timezone, 'YYYY-MM-DD'),
    'focus_request_fingerprint', p_request_fingerprint
  );
  if p_recovery_minutes > 0 then
    metadata := metadata || jsonb_build_object('recovery_minutes', p_recovery_minutes);
  end if;
  begin
    insert into public.focus_sessions (
      id, user_id, status, started_at, planned_minutes, label, task_id, habit_id, metadata, updated_at
    ) values (
      p_request_id, p_user_id, 'active', p_now, null, p_label,
      case when p_target_kind = 'task' then p_target_id else null end,
      case when p_target_kind = 'habit' then p_target_id else null end, metadata, p_now
    );
  exception when unique_violation then
    get stacked diagnostics violated_constraint = constraint_name;
    if violated_constraint = 'focus_sessions_one_active_per_user_idx' then
      raise exception 'active_focus_session' using errcode = 'PT409';
    end if;
    raise;
  end;
  return private.focus_session_response_v2(p_user_id, p_request_id, false);
end;
$$;
revoke all on function public.start_focus_open_end_v1(uuid, uuid, text, int, text, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.start_focus_open_end_v1(uuid, uuid, text, int, text, uuid, text, timestamptz)
  to service_role;
