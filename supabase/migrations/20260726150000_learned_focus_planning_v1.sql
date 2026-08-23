-- Optional learned Focus timing provenance for new Planner previews.

alter table public.planner_action_plan_revisions
  add column timing_preference_source text not null default 'setup',
  add column timing_preference_window text,
  add column timing_evidence_count int not null default 0,
  add column timing_evidence_starts_on date,
  add column timing_evidence_ends_on date,
  add column timing_evidence_fingerprint text,
  add column timing_fell_back_to_setup boolean not null default false,
  add column timing_warning text;

alter table public.deadline_plan_revisions
  add column timing_preference_source text not null default 'setup',
  add column timing_preference_window text,
  add column timing_evidence_count int not null default 0,
  add column timing_evidence_starts_on date,
  add column timing_evidence_ends_on date,
  add column timing_evidence_fingerprint text,
  add column timing_fell_back_to_setup boolean not null default false,
  add column timing_warning text;

alter table public.planner_action_plan_revisions
  add constraint planner_action_revision_timing_check check (
    (
      timing_preference_source = 'setup'
      and timing_preference_window is null
      and timing_evidence_count = 0
      and timing_evidence_starts_on is null
      and timing_evidence_ends_on is null
      and timing_evidence_fingerprint is null
      and (
        timing_warning is null
        or timing_warning = 'personal_patterns_unavailable'
      )
    )
    or (
      timing_preference_source = 'learned_personal_pattern'
      and target_payload ->> 'kind' = 'task'
      and timing_preference_window in ('05-09', '09-13', '13-18', '18-23')
      and timing_evidence_count between 1 and 10000
      and timing_evidence_starts_on is not null
      and timing_evidence_ends_on is not null
      and timing_evidence_starts_on <= timing_evidence_ends_on
      and timing_evidence_fingerprint ~ '^[0-9a-f]{64}$'
      and not timing_fell_back_to_setup
      and timing_warning is null
    )
  ),
  add constraint planner_action_revision_timing_warning_check check (
    timing_warning is null
    or (
      timing_warning = 'personal_patterns_unavailable'
      and timing_preference_source = 'setup'
      and timing_fell_back_to_setup
    )
  );

alter table public.deadline_plan_revisions
  add constraint deadline_plan_revision_timing_check check (
    (
      timing_preference_source = 'setup'
      and timing_preference_window is null
      and timing_evidence_count = 0
      and timing_evidence_starts_on is null
      and timing_evidence_ends_on is null
      and timing_evidence_fingerprint is null
      and (
        timing_warning is null
        or timing_warning = 'personal_patterns_unavailable'
      )
    )
    or (
      timing_preference_source = 'learned_personal_pattern'
      and timing_preference_window in ('05-09', '09-13', '13-18', '18-23')
      and timing_evidence_count between 1 and 10000
      and timing_evidence_starts_on is not null
      and timing_evidence_ends_on is not null
      and timing_evidence_starts_on <= timing_evidence_ends_on
      and timing_evidence_fingerprint ~ '^[0-9a-f]{64}$'
      and not timing_fell_back_to_setup
      and timing_warning is null
    )
  ),
  add constraint deadline_plan_revision_timing_warning_check check (
    timing_warning is null
    or (
      timing_warning = 'personal_patterns_unavailable'
      and timing_preference_source = 'setup'
      and timing_fell_back_to_setup
    )
  );

create or replace function private.guard_planning_timing_provenance_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  planning_allowed boolean;
begin
  if row(
    old.timing_preference_source,
    old.timing_preference_window,
    old.timing_evidence_count,
    old.timing_evidence_starts_on,
    old.timing_evidence_ends_on,
    old.timing_evidence_fingerprint,
    old.timing_fell_back_to_setup,
    old.timing_warning
  ) is distinct from row(
    new.timing_preference_source,
    new.timing_preference_window,
    new.timing_evidence_count,
    new.timing_evidence_starts_on,
    new.timing_evidence_ends_on,
    new.timing_evidence_fingerprint,
    new.timing_fell_back_to_setup,
    new.timing_warning
  ) and coalesce(
    current_setting('mylifegraph.timing_provenance_write', true),
    ''
  ) <> 'v1' then
    raise exception 'Planning timing provenance is immutable.'
      using errcode = 'PT409';
  end if;

  if old.state = 'proposed'
     and new.state = 'active'
     and old.timing_preference_source = 'learned_personal_pattern' then
    select (
      personal_pattern_analysis_enabled
      and learned_focus_planning_enabled
    )
    into planning_allowed
    from public.learning_preferences
    where user_id = old.user_id
    for share;
    if not coalesce(planning_allowed, false) then
      raise exception
        'Learned Focus planning was turned off. Request a new preview.'
        using errcode = 'PT409';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_planning_timing_provenance_v1()
  from public, anon, authenticated, service_role;

create trigger planner_action_timing_provenance_guard_v1
before update on public.planner_action_plan_revisions
for each row execute function private.guard_planning_timing_provenance_v1();

create trigger deadline_plan_timing_provenance_guard_v1
before update on public.deadline_plan_revisions
for each row execute function private.guard_planning_timing_provenance_v1();

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
    p_revision_payload,
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
  if changed <> 1 then
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
    p_proposal,
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
  if changed <> 1 then
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
