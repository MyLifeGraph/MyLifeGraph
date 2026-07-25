-- Retire Setup Goals and Friction without weakening the existing Intake V1
-- request/revision identity. Raw retired answers are removed permanently; all
-- reproducible projections are either sanitized or invalidated, never rebuilt
-- by this migration.

-- The existing, verified core still owns the atomic reconciliation of Habits,
-- commitments, memories, snapshots, Intake state, and the profile projection.
-- Preserve it under an uncallable name, then put a compatibility adapter at its
-- former name. The adapter discards both retired arguments before the core can
-- validate or materialize them.
do $$
begin
  if to_regprocedure(
    'public.apply_intake_v1_setup_revision_with_retired_fields('
    'uuid,uuid,uuid,integer,integer,timestamp with time zone,'
    'jsonb,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb)'
  ) is null then
    alter function public.apply_intake_v1_setup_revision_without_study_setup(
      uuid, uuid, uuid, int, int, timestamptz,
      jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
    ) rename to apply_intake_v1_setup_revision_with_retired_fields;
  end if;
end
$$;

revoke all on function public.apply_intake_v1_setup_revision_with_retired_fields(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

-- INSERT ... ON CONFLICT fires its BEFORE INSERT triggers before choosing the
-- conflict path. Returning null here therefore suppresses both the legacy
-- insert and update without changing timestamps, consent, categories, limits,
-- quiet hours, or retry identity. Only the uncallable adapter below sets the
-- transaction-local guard.
create or replace function public.suppress_retired_intake_notification_write_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  if pg_catalog.current_setting(
    'mylifegraph.preserve_notification_preferences',
    true
  ) = 'on' then
    return null;
  end if;
  return new;
end;
$$;

revoke all on function public.suppress_retired_intake_notification_write_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists notification_preferences_intake_retired_write_guard_v1
  on public.notification_preferences;
create trigger notification_preferences_intake_retired_write_guard_v1
before insert or update on public.notification_preferences
for each row
execute function public.suppress_retired_intake_notification_write_v1();

create or replace function public.apply_intake_v1_setup_revision_without_study_setup(
  p_user_id uuid,
  p_intake_response_id uuid,
  p_request_id uuid,
  p_base_revision int,
  p_revision int,
  p_completed_at timestamptz,
  p_notification_preferences jsonb,
  p_goals jsonb,
  p_habits jsonb,
  p_schedule_items jsonb,
  p_memory_entries jsonb,
  p_snapshot jsonb,
  p_intake_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  result jsonb;
begin
  -- p_notification_preferences and p_goals deliberately remain in the
  -- signature for old service clients, but their values have no semantics.
  perform p_notification_preferences;
  perform p_goals;
  perform pg_catalog.set_config(
    'mylifegraph.preserve_notification_preferences',
    'on',
    true
  );
  result := public.apply_intake_v1_setup_revision_with_retired_fields(
    p_user_id,
    p_intake_response_id,
    p_request_id,
    p_base_revision,
    p_revision,
    p_completed_at,
    jsonb_build_object(
      'focus_prompts_enabled', true,
      'recovery_prompts_enabled', true,
      'weekly_summary_enabled', true
    ),
    '[]'::jsonb,
    p_habits,
    p_schedule_items,
    p_memory_entries,
    p_snapshot,
    p_intake_metadata
  );
  perform pg_catalog.set_config(
    'mylifegraph.preserve_notification_preferences',
    'off',
    true
  );
  return result;
end;
$$;

revoke all on function public.apply_intake_v1_setup_revision_without_study_setup(
  uuid, uuid, uuid, int, int, timestamptz,
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

-- This helper looks only for structured JSON keys and evidence values, not
-- ordinary prose. It remains private and uncallable so the cleanup routine can
-- be exercised repeatedly against filled migration fixtures.
create or replace function private.references_retired_personalization_v1(
  payload jsonb
)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(
    payload::text ~
      '"(primary_focus_areas|goals|friction_points|coaching_style|'
      'reminder_preference|context_note|main_friction|'
      'additional_frictions|goal_id)"[[:space:]]*:'
    or payload::text ~ '"table"[[:space:]]*:[[:space:]]*"goals"'
    or payload::text ~ '"target_type"[[:space:]]*:[[:space:]]*"goal"'
    or payload::text ~
      '"field"[[:space:]]*:[[:space:]]*"[^"]*'
      '(primary_focus_areas|goals|friction_points|coaching_style|'
      'reminder_preference|context_note|main_friction|'
      'additional_frictions|goal_id)[^"]*"'
    or payload::text ~
      '"(plan_unclear_priorities|plan_overload|plan_start_friction|'
      'evening.invalid_main_friction|'
      'evening.invalid_additional_frictions)"',
    false
  )
$$;

revoke all on function private.references_retired_personalization_v1(jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.retire_setup_goals_and_friction_v1()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $cleanup$
begin
-- Persisted Intake requests keep their identity and state, but comparison and
-- replay now see only the canonical active answers.
update public.intake_responses
set responses = responses - array[
  'primary_focus_areas',
  'goals',
  'friction_points',
  'coaching_style',
  'reminder_preference',
  'context_note'
]
where version = 'intake-v1'
  and responses ?| array[
    'primary_focus_areas',
    'goals',
    'friction_points',
    'coaching_style',
    'reminder_preference',
    'context_note'
  ];

-- Onboarding keeps only the current compact personalization fact. Provenance
-- metadata remains intact so the existing Intake identity is still auditable.
update public.user_state_snapshots
set
  summary = jsonb_strip_nulls(
    jsonb_build_object(
      'best_energy_window',
        case
          when jsonb_typeof(summary -> 'best_energy_window') = 'string'
            then summary -> 'best_energy_window'
          else null
        end,
      'fixed_commitment_count',
        case
          when jsonb_typeof(summary -> 'fixed_commitment_count') = 'number'
            then summary -> 'fixed_commitment_count'
          else '0'::jsonb
        end,
      'existing_habit_count',
        case
          when jsonb_typeof(summary -> 'existing_habit_count') = 'number'
            then summary -> 'existing_habit_count'
          else '0'::jsonb
        end,
      'routine_candidate_count',
        case
          when jsonb_typeof(summary -> 'routine_candidate_count') = 'number'
            then summary -> 'routine_candidate_count'
          else '0'::jsonb
        end,
      'active_habit_count',
        case
          when jsonb_typeof(summary -> 'active_habit_count') = 'number'
            then summary -> 'active_habit_count'
          else '0'::jsonb
        end
    )
  ),
  signals = '{}'::jsonb
where scope = 'onboarding'
  and period_key = 'setup:intake-v1'
  and (
    summary is distinct from jsonb_strip_nulls(
      jsonb_build_object(
        'best_energy_window',
          case
            when jsonb_typeof(summary -> 'best_energy_window') = 'string'
              then summary -> 'best_energy_window'
            else null
          end,
        'fixed_commitment_count',
          case
            when jsonb_typeof(summary -> 'fixed_commitment_count') = 'number'
              then summary -> 'fixed_commitment_count'
            else '0'::jsonb
          end,
        'existing_habit_count',
          case
            when jsonb_typeof(summary -> 'existing_habit_count') = 'number'
              then summary -> 'existing_habit_count'
            else '0'::jsonb
          end,
        'routine_candidate_count',
          case
            when jsonb_typeof(summary -> 'routine_candidate_count') = 'number'
              then summary -> 'routine_candidate_count'
            else '0'::jsonb
          end,
        'active_habit_count',
          case
            when jsonb_typeof(summary -> 'active_habit_count') = 'number'
              then summary -> 'active_habit_count'
            else '0'::jsonb
          end
      )
    )
    or signals <> '{}'::jsonb
  );

-- Setup-owned Goals are retained for export/history but can no longer be
-- active. Manual and foreign-managed rows are intentionally untouched.
update public.goals
set
  status = 'archived',
  metadata = metadata || jsonb_build_object('setup_state', 'archived'),
  updated_at = greatest(updated_at, statement_timestamp())
where (
    metadata ->> 'managed_by' = 'setup'
    or metadata ->> 'source' = 'intake-v1'
  )
  and (
    status <> 'archived'
    or metadata ->> 'setup_state' is distinct from 'archived'
  );

-- Delete only the three retired Setup memory families. The energy-window
-- memory and every manual or independently generated memory survive.
delete from public.memory_entries
where (
    metadata ->> 'managed_by' = 'setup'
    or metadata ->> 'source' = 'intake-v1'
  )
  and (
    type = 'goal'
    or title in ('Preferred coaching style', 'Intake context note')
  );

-- Remove retired Evening keys both from old root metadata and the V2 capture
-- branch. The expression is safe for malformed historical containers.
update public.daily_logs
set metadata = case
  when jsonb_typeof(metadata #> '{captures,evening}') = 'object' then
    jsonb_set(
      metadata - 'main_friction' - 'additional_frictions',
      '{captures,evening}',
      (metadata #> '{captures,evening}')
        - 'main_friction'
        - 'additional_frictions',
      false
    )
  else metadata - 'main_friction' - 'additional_frictions'
end
where metadata ?| array['main_friction', 'additional_frictions']
   or (
     jsonb_typeof(metadata #> '{captures,evening}') = 'object'
     and (metadata #> '{captures,evening}')
       ?| array['main_friction', 'additional_frictions']
   );

update public.behavioral_events
set metadata = case
  when jsonb_typeof(metadata #> '{captures,evening}') = 'object' then
    jsonb_set(
      metadata - 'main_friction' - 'additional_frictions',
      '{captures,evening}',
      (metadata #> '{captures,evening}')
        - 'main_friction'
        - 'additional_frictions',
      false
    )
  else metadata - 'main_friction' - 'additional_frictions'
end
where metadata ?| array['main_friction', 'additional_frictions']
   or (
     jsonb_typeof(metadata #> '{captures,evening}') = 'object'
     and (metadata #> '{captures,evening}')
       ?| array['main_friction', 'additional_frictions']
   );

-- Delete only derived rows whose structured facts/evidence still depend on a
-- retired source. Existing refresh/scheduled paths may recreate current facts;
-- this migration performs no generation.
delete from public.daily_briefings
where private.references_retired_personalization_v1(primary_action)
   or private.references_retired_personalization_v1(support_actions)
   or private.references_retired_personalization_v1(evidence_refs)
   or private.references_retired_personalization_v1(provenance)
   or private.references_retired_personalization_v1(metadata);

delete from public.weekly_reviews
where private.references_retired_personalization_v1(facts)
   or private.references_retired_personalization_v1(proposals)
   or private.references_retired_personalization_v1(evidence_refs)
   or private.references_retired_personalization_v1(provenance)
   or coalesce(facts #>> '{tasks,goal_linked_completed}', '0') <> '0';

delete from public.recommendations as recommendation
where private.references_retired_personalization_v1(recommendation.metadata)
   or (
     jsonb_typeof(recommendation.metadata -> 'evidence_refs') = 'array'
     and exists (
       select 1
       from jsonb_array_elements(
         recommendation.metadata -> 'evidence_refs'
       ) as evidence
       join public.user_state_snapshots as snapshot
         on snapshot.id::text = evidence ->> 'id'
       where evidence ->> 'table' = 'user_state_snapshots'
         and snapshot.scope = 'onboarding'
         and snapshot.period_key = 'setup:intake-v1'
     )
   )
   or (
     jsonb_typeof(recommendation.metadata -> 'evidence_refs') = 'array'
     and exists (
       select 1
       from jsonb_array_elements(
         recommendation.metadata -> 'evidence_refs'
       ) as evidence
       join public.behavioral_events as event
         on event.id::text = evidence ->> 'id'
       where evidence ->> 'table' = 'behavioral_events'
         and event.event_type = 'planning_friction'
     )
   );

delete from public.user_state_snapshots
where scope <> 'onboarding'
  and (
    private.references_retired_personalization_v1(summary)
    or private.references_retired_personalization_v1(signals)
    or private.references_retired_personalization_v1(metadata)
  );
end;
$cleanup$;

revoke all on function private.retire_setup_goals_and_friction_v1()
  from public, anon, authenticated, service_role;

select private.retire_setup_goals_and_friction_v1();

-- New Coach requests use the sanitized V2 context and prompt. Persisted V1
-- requests and responses remain valid and replayable; only newly claimed rows
-- are advanced to the paired V2 versions.
do $$
begin
  if to_regprocedure(
    'private.coach_response_is_valid_v1_only(jsonb,uuid,jsonb)'
  ) is null then
    alter function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)
      rename to coach_response_is_valid_v1_only;
  end if;
end
$$;

revoke all on function private.coach_response_is_valid_v1_only(
  jsonb, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v1_only(
  jsonb, uuid, jsonb
) to service_role;

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

  if prompt_version = 'controlled-coach-prompt-v2'
     and context_version = 'coach-context-v2' then
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
  'Validates strict coach-response-v1 envelopes with matching V1 or sanitized V2 prompt/context provenance.';

revoke all on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function private.coach_response_is_valid_v1(
  jsonb, uuid, jsonb
) to service_role;

alter table public.coach_requests
  drop constraint coach_requests_versions,
  add constraint coach_requests_versions check (
    (
      prompt_version = 'controlled-coach-prompt-v1'
      and context_version = 'coach-context-v1'
    )
    or (
      prompt_version = 'controlled-coach-prompt-v2'
      and context_version = 'coach-context-v2'
    )
  ),
  drop constraint coach_requests_response,
  add constraint coach_requests_response check (
    response is null
    or private.coach_response_is_valid_v1(response, request_id, used_context)
  );

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
  claim_result jsonb;
  is_v2 boolean;
  existing_for_owner boolean := false;
  existing_prompt_version text;
  existing_context_version text;
begin
  if p_user_id is null then
    raise exception 'Coach claim owner is invalid'
      using errcode = '22023';
  end if;

  is_v2 := p_prompt_version = 'controlled-coach-prompt-v2'
    and p_context_version = 'coach-context-v2';
  if not is_v2 and not (
    p_prompt_version = 'controlled-coach-prompt-v1'
    and p_context_version = 'coach-context-v1'
  ) then
    raise exception 'Coach claim versions are invalid'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  select
    prompt_version,
    context_version
  into
    existing_prompt_version,
    existing_context_version
  from public.coach_requests
  where request_id = p_request_id
    and user_id = p_user_id;
  existing_for_owner := found;

  if existing_for_owner and (
    existing_prompt_version is distinct from p_prompt_version
    or existing_context_version is distinct from p_context_version
  ) then
    raise exception 'Coach request id already uses different versions'
      using errcode = 'PT409';
  end if;

  claim_result := public.coach_claim_request_v1_locked_body(
    p_user_id,
    p_request_id,
    p_message_fingerprint,
    p_context_scope,
    p_local_date,
    p_provider,
    p_provider_mode,
    p_model_requested,
    p_model_source,
    case
      when is_v2 then 'controlled-coach-prompt-v1'
      else p_prompt_version
    end,
    case
      when is_v2 then 'coach-context-v1'
      else p_context_version
    end,
    p_claimed_at,
    p_lease_expires_at,
    p_daily_limit
  );

  if is_v2
     and not existing_for_owner
     and claim_result ->> 'state' = 'pending' then
    update public.coach_requests
    set
      prompt_version = p_prompt_version,
      context_version = p_context_version
    where request_id = p_request_id
      and user_id = p_user_id
      and state = 'pending'
      and prompt_version = 'controlled-coach-prompt-v1'
      and context_version = 'coach-context-v1';

    if not found then
      raise exception 'Coach V2 claim projection is inconsistent'
        using errcode = 'PT409';
    end if;
  end if;

  return claim_result;
end;
$$;

revoke all on function public.claim_coach_request_v1(
  uuid, uuid, text, text, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) from public, anon, authenticated, service_role;
grant execute on function public.claim_coach_request_v1(
  uuid, uuid, text, text, date, text, text, text, text, text, text,
  timestamptz, timestamptz, int
) to service_role;
