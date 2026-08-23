-- Keep additive learned-timing provenance outside the strict V1 proposal
-- payloads, and make exact proposal replays preserve their bound provenance.

create or replace function public.propose_planner_action_plan_with_timing_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_plan_id uuid,
  p_base_revision int,
  p_target_kind text,
  p_target_id uuid,
  p_target_payload jsonb,
  p_revision_payload jsonb,
  p_task_blocks jsonb,
  p_habit_slots jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  timing jsonb := p_revision_payload -> 'timing_preference';
  result_revision int;
  changed int;
begin
  if jsonb_typeof(timing) <> 'object'
     or timing ->> 'source' not in ('setup', 'learned_personal_pattern') then
    raise exception 'Planner timing provenance is invalid.'
      using errcode = '22023';
  end if;

  result := public.propose_planner_action_plan_v1(
    p_user_id,
    p_request_id,
    p_request_fingerprint,
    p_plan_id,
    p_base_revision,
    p_target_kind,
    p_target_id,
    p_target_payload,
    p_revision_payload - 'timing_preference',
    p_task_blocks,
    p_habit_slots,
    p_now
  );
  result_revision := (result ->> 'revision')::int;

  perform set_config('mylifegraph.timing_provenance_write', 'v1', true);
  update public.planner_action_plan_revisions
  set timing_preference_source = timing ->> 'source',
      timing_preference_window = nullif(timing ->> 'window', ''),
      timing_evidence_count = coalesce(
        (timing ->> 'evidence_count')::int,
        0
      ),
      timing_evidence_starts_on =
        nullif(timing ->> 'evidence_starts_on', '')::date,
      timing_evidence_ends_on =
        nullif(timing ->> 'evidence_ends_on', '')::date,
      timing_evidence_fingerprint =
        nullif(timing ->> 'evidence_fingerprint', ''),
      timing_fell_back_to_setup = coalesce(
        (timing ->> 'fell_back_to_setup')::boolean,
        false
      ),
      timing_warning = nullif(timing ->> 'warning', '')
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = result_revision
    and state = 'proposed'
    and timing_preference_source = 'setup'
    and timing_preference_window is null
    and timing_evidence_count = 0
    and timing_evidence_starts_on is null
    and timing_evidence_ends_on is null
    and timing_evidence_fingerprint is null
    and not timing_fell_back_to_setup
    and timing_warning is null;
  get diagnostics changed = row_count;

  if changed = 0 and not exists (
    select 1
    from public.planner_action_plan_revisions
    where user_id = p_user_id
      and plan_id = p_plan_id
      and revision = result_revision
      and timing_preference_source = timing ->> 'source'
      and timing_preference_window is not distinct from
        nullif(timing ->> 'window', '')
      and timing_evidence_count = coalesce(
        (timing ->> 'evidence_count')::int,
        0
      )
      and timing_evidence_starts_on is not distinct from
        nullif(timing ->> 'evidence_starts_on', '')::date
      and timing_evidence_ends_on is not distinct from
        nullif(timing ->> 'evidence_ends_on', '')::date
      and timing_evidence_fingerprint is not distinct from
        nullif(timing ->> 'evidence_fingerprint', '')
      and timing_fell_back_to_setup = coalesce(
        (timing ->> 'fell_back_to_setup')::boolean,
        false
      )
      and timing_warning is not distinct from
        nullif(timing ->> 'warning', '')
  ) then
    raise exception 'Planner timing provenance could not be bound.'
      using errcode = 'PT409';
  end if;
  return result;
end;
$$;

create or replace function public.propose_deadline_plan_with_timing_v1(
  p_user_id uuid,
  p_request_id uuid,
  p_request_fingerprint text,
  p_plan_id uuid,
  p_base_revision int,
  p_proposal jsonb,
  p_blocks jsonb,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
  timing jsonb := p_proposal -> 'timing_preference';
  result_revision int;
  changed int;
begin
  if jsonb_typeof(timing) <> 'object'
     or timing ->> 'source' not in ('setup', 'learned_personal_pattern') then
    raise exception 'Deadline timing provenance is invalid.'
      using errcode = '22023';
  end if;

  result := public.propose_deadline_plan_v1(
    p_user_id,
    p_request_id,
    p_request_fingerprint,
    p_plan_id,
    p_base_revision,
    p_proposal - 'timing_preference',
    p_blocks,
    p_now
  );
  result_revision := (result ->> 'revision')::int;

  perform set_config('mylifegraph.timing_provenance_write', 'v1', true);
  update public.deadline_plan_revisions
  set timing_preference_source = timing ->> 'source',
      timing_preference_window = nullif(timing ->> 'window', ''),
      timing_evidence_count = coalesce(
        (timing ->> 'evidence_count')::int,
        0
      ),
      timing_evidence_starts_on =
        nullif(timing ->> 'evidence_starts_on', '')::date,
      timing_evidence_ends_on =
        nullif(timing ->> 'evidence_ends_on', '')::date,
      timing_evidence_fingerprint =
        nullif(timing ->> 'evidence_fingerprint', ''),
      timing_fell_back_to_setup = coalesce(
        (timing ->> 'fell_back_to_setup')::boolean,
        false
      ),
      timing_warning = nullif(timing ->> 'warning', '')
  where user_id = p_user_id
    and plan_id = p_plan_id
    and revision = result_revision
    and state = 'proposed'
    and timing_preference_source = 'setup'
    and timing_preference_window is null
    and timing_evidence_count = 0
    and timing_evidence_starts_on is null
    and timing_evidence_ends_on is null
    and timing_evidence_fingerprint is null
    and not timing_fell_back_to_setup
    and timing_warning is null;
  get diagnostics changed = row_count;

  if changed = 0 and not exists (
    select 1
    from public.deadline_plan_revisions
    where user_id = p_user_id
      and plan_id = p_plan_id
      and revision = result_revision
      and timing_preference_source = timing ->> 'source'
      and timing_preference_window is not distinct from
        nullif(timing ->> 'window', '')
      and timing_evidence_count = coalesce(
        (timing ->> 'evidence_count')::int,
        0
      )
      and timing_evidence_starts_on is not distinct from
        nullif(timing ->> 'evidence_starts_on', '')::date
      and timing_evidence_ends_on is not distinct from
        nullif(timing ->> 'evidence_ends_on', '')::date
      and timing_evidence_fingerprint is not distinct from
        nullif(timing ->> 'evidence_fingerprint', '')
      and timing_fell_back_to_setup = coalesce(
        (timing ->> 'fell_back_to_setup')::boolean,
        false
      )
      and timing_warning is not distinct from
        nullif(timing ->> 'warning', '')
  ) then
    raise exception 'Deadline timing provenance could not be bound.'
      using errcode = 'PT409';
  end if;
  return result;
end;
$$;

revoke all on function public.propose_planner_action_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) from public, anon, authenticated;
grant execute on function public.propose_planner_action_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, text, uuid, jsonb, jsonb, jsonb, jsonb,
  timestamptz
) to service_role;

revoke all on function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.propose_deadline_plan_with_timing_v1(
  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz
) to service_role;
