-- The first draft of this migration used one extra profile JSON argument. Drop
-- that signature defensively for local databases that applied the draft while
-- it was under development. Profile values now come only from the claimed,
-- canonical intake_responses row.
drop function if exists public.apply_intake_v1_setup_revision(
  uuid,
  uuid,
  uuid,
  int,
  int,
  timestamptz,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb
);

create or replace function public.apply_intake_v1_setup_revision(
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
set search_path = public, pg_temp
as $$
declare
  target_intake public.intake_responses%rowtype;
  latest_intake_id uuid;
  latest_applied_id uuid;
  snapshot_id uuid;
  current_profile_revision int;
  affected_count int;
  desired_count int;
  profile_repaired boolean := false;
begin
  -- Serialize every Setup apply for one user. Same-request workers converge on
  -- the applied row, and a delayed worker cannot reconcile after a later
  -- revision has committed.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select *
  into target_intake
  from public.intake_responses
  where id = p_intake_response_id
    and user_id = p_user_id
    and version = 'intake-v1'
    and request_id = p_request_id
  for update;

  if not found then
    raise exception 'Intake V1 setup revision not found'
      using errcode = '22023';
  end if;

  if target_intake.base_revision <> p_base_revision
     or target_intake.revision <> p_revision then
    raise exception 'Intake V1 setup revision identity mismatch'
      using errcode = '22023';
  end if;

  -- An applied replay is deliberately side-effect free except for repairing a
  -- missing final profile marker. Only the newest applied revision may repair
  -- that marker, and the projected display name comes from its stored response.
  if target_intake.state = 'applied' then
    select id
    into latest_applied_id
    from public.intake_responses
    where user_id = p_user_id
      and version = 'intake-v1'
      and state = 'applied'
    order by revision desc, updated_at desc, id desc
    limit 1;

    if latest_applied_id = target_intake.id then
      update public.profiles
      set
        display_name = case
          when target_intake.responses ? 'display_name'
            then target_intake.responses ->> 'display_name'
          else display_name
        end,
        onboarding_completed_at = target_intake.completed_at,
        updated_at = greatest(updated_at, target_intake.completed_at),
        setup_revision = target_intake.revision
      where id = p_user_id
        and setup_revision < target_intake.revision;
      get diagnostics affected_count = row_count;
      profile_repaired := affected_count = 1;
    end if;

    begin
      snapshot_id := nullif(target_intake.metadata ->> 'snapshot_id', '')::uuid;
    exception
      when invalid_text_representation then
        snapshot_id := null;
    end;
    if snapshot_id is null then
      select id
      into snapshot_id
      from public.user_state_snapshots
      where user_id = p_user_id
        and scope = 'onboarding'
        and period_key = 'setup:intake-v1'
      limit 1;
    end if;
    return jsonb_build_object(
      'intake_response_id', target_intake.id,
      'request_id', target_intake.request_id,
      'base_revision', target_intake.base_revision,
      'revision', target_intake.revision,
      'state', target_intake.state,
      'completed_at', target_intake.completed_at,
      'snapshot_id', snapshot_id,
      'profile_repaired', profile_repaired
    );
  end if;

  select id
  into latest_intake_id
  from public.intake_responses
  where user_id = p_user_id
    and version = 'intake-v1'
  order by revision desc, updated_at desc, id desc
  limit 1
  for update;

  if latest_intake_id is distinct from target_intake.id then
    raise exception 'Intake V1 setup revision is no longer current'
      using errcode = '40001';
  end if;

  if target_intake.state <> 'pending' then
    raise exception 'Intake V1 setup revision has invalid state'
      using errcode = '22023';
  end if;

  if p_completed_at is null then
    raise exception 'Setup completion time is required'
      using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_notification_preferences, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_intake_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'Setup objects must be JSON objects'
      using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_goals, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_habits, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_schedule_items, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_memory_entries, '[]'::jsonb)) <> 'array' then
    raise exception 'Setup materializations must be JSON arrays'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_notification_preferences -> 'focus_prompts_enabled')
       is distinct from 'boolean'
     or jsonb_typeof(p_notification_preferences -> 'recovery_prompts_enabled')
       is distinct from 'boolean'
     or jsonb_typeof(p_notification_preferences -> 'weekly_summary_enabled')
       is distinct from 'boolean'
     or jsonb_typeof(coalesce(p_snapshot -> 'summary', '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_snapshot -> 'signals', '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_snapshot -> 'metadata', '{}'::jsonb)) <> 'object'
  then
    raise exception 'Setup preference or snapshot payload is invalid'
      using errcode = '22023';
  end if;

  -- The RPC is service-role-only, but it still rejects malformed ownership
  -- metadata so a future service bug cannot turn arbitrary rows into Setup rows.
  if exists (
    select 1
    from (
      select value as item
      from jsonb_array_elements(coalesce(p_goals, '[]'::jsonb))
      union all
      select value
      from jsonb_array_elements(coalesce(p_habits, '[]'::jsonb))
      union all
      select value
      from jsonb_array_elements(coalesce(p_schedule_items, '[]'::jsonb))
      union all
      select value
      from jsonb_array_elements(coalesce(p_memory_entries, '[]'::jsonb))
    ) as desired
    where jsonb_typeof(desired.item) <> 'object'
       or coalesce(desired.item -> 'metadata' ->> 'managed_by', '') <> 'setup'
       or coalesce(desired.item -> 'metadata' ->> 'source', '') <> 'intake-v1'
       or coalesce(desired.item -> 'metadata' ->> 'revision', '')
            <> p_revision::text
       or coalesce(desired.item -> 'metadata' ->> 'setup_item_id', '') = ''
  ) then
    raise exception 'Setup materialization ownership metadata is invalid'
      using errcode = '22023';
  end if;

  select setup_revision
  into current_profile_revision
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'Authenticated profile does not exist'
      using errcode = '23503';
  end if;
  if current_profile_revision >= p_revision then
    raise exception 'Profile already projects this or a newer Setup revision'
      using errcode = '40001';
  end if;

  -- A stable UUID may update only a row already owned by Setup for this user.
  -- The ON CONFLICT predicates below repeat this check and the affected-row
  -- assertions close the race with a concurrent non-Setup insert.
  if exists (
    select 1
    from public.goals as existing
    join jsonb_array_elements(coalesce(p_goals, '[]'::jsonb)) as desired
      on existing.id = (desired ->> 'id')::uuid
    where existing.user_id <> p_user_id
       or not (
         existing.metadata ->> 'managed_by' = 'setup'
         or existing.metadata ->> 'source' = 'intake-v1'
       )
  ) then
    raise exception 'Setup goal id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  if exists (
    select 1
    from public.habits as existing
    join jsonb_array_elements(coalesce(p_habits, '[]'::jsonb)) as desired
      on existing.id = (desired ->> 'id')::uuid
    where existing.user_id <> p_user_id
       or not (
         existing.metadata ->> 'managed_by' = 'setup'
         or existing.metadata ->> 'source' = 'intake-v1'
       )
  ) then
    raise exception 'Setup habit id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  if exists (
    select 1
    from public.schedule_items as existing
    join jsonb_array_elements(coalesce(p_schedule_items, '[]'::jsonb)) as desired
      on existing.id = (desired ->> 'id')::uuid
    where existing.user_id <> p_user_id
       or not (
         existing.metadata ->> 'managed_by' = 'setup'
         or existing.metadata ->> 'source' = 'intake-v1'
       )
  ) then
    raise exception 'Setup schedule id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  if exists (
    select 1
    from public.memory_entries as existing
    join jsonb_array_elements(coalesce(p_memory_entries, '[]'::jsonb)) as desired
      on existing.id = (desired ->> 'id')::uuid
    where existing.user_id <> p_user_id
       or not (
         existing.metadata ->> 'managed_by' = 'setup'
         or existing.metadata ->> 'source' = 'intake-v1'
       )
  ) then
    raise exception 'Setup memory id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  insert into public.notification_preferences (
    user_id,
    focus_prompts_enabled,
    recovery_prompts_enabled,
    weekly_summary_enabled,
    quiet_hours_start,
    quiet_hours_end,
    updated_at
  ) values (
    p_user_id,
    (p_notification_preferences ->> 'focus_prompts_enabled')::boolean,
    (p_notification_preferences ->> 'recovery_prompts_enabled')::boolean,
    (p_notification_preferences ->> 'weekly_summary_enabled')::boolean,
    nullif(p_notification_preferences ->> 'quiet_hours_start', '')::time,
    nullif(p_notification_preferences ->> 'quiet_hours_end', '')::time,
    p_completed_at
  )
  on conflict (user_id) do update set
    focus_prompts_enabled = excluded.focus_prompts_enabled,
    recovery_prompts_enabled = excluded.recovery_prompts_enabled,
    weekly_summary_enabled = excluded.weekly_summary_enabled,
    quiet_hours_start = excluded.quiet_hours_start,
    quiet_hours_end = excluded.quiet_hours_end,
    updated_at = excluded.updated_at;

  insert into public.goals as target (
    id,
    user_id,
    title,
    status,
    metadata,
    updated_at
  )
  select
    desired.id,
    p_user_id,
    desired.title,
    desired.status,
    desired.metadata,
    p_completed_at
  from jsonb_to_recordset(coalesce(p_goals, '[]'::jsonb)) as desired(
    id uuid,
    title text,
    status text,
    metadata jsonb
  )
  on conflict (id) do update set
    title = excluded.title,
    status = excluded.status,
    metadata = excluded.metadata,
    updated_at = excluded.updated_at
  where target.user_id = p_user_id
    and (
      target.metadata ->> 'managed_by' = 'setup'
      or target.metadata ->> 'source' = 'intake-v1'
    );
  get diagnostics affected_count = row_count;
  desired_count := jsonb_array_length(coalesce(p_goals, '[]'::jsonb));
  if affected_count <> desired_count then
    raise exception 'Setup goal id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  update public.goals as existing
  set
    status = 'archived',
    metadata = existing.metadata || jsonb_build_object(
      'source', 'intake-v1',
      'managed_by', 'setup',
      'setup_item_id', coalesce(existing.metadata ->> 'setup_item_id', existing.id::text),
      'revision', p_revision,
      'setup_state', 'archived'
    ),
    updated_at = p_completed_at
  where existing.user_id = p_user_id
    and (
      existing.metadata ->> 'managed_by' = 'setup'
      or existing.metadata ->> 'source' = 'intake-v1'
    )
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_goals, '[]'::jsonb)) as desired
      where (desired ->> 'id')::uuid = existing.id
    );

  insert into public.habits as target (
    id,
    user_id,
    title,
    frequency,
    target,
    active,
    metadata,
    updated_at
  )
  select
    desired.id,
    p_user_id,
    desired.title,
    desired.frequency,
    desired.target,
    desired.active,
    desired.metadata,
    p_completed_at
  from jsonb_to_recordset(coalesce(p_habits, '[]'::jsonb)) as desired(
    id uuid,
    title text,
    frequency text,
    target int,
    active boolean,
    metadata jsonb
  )
  on conflict (id) do update set
    title = excluded.title,
    frequency = excluded.frequency,
    target = excluded.target,
    active = excluded.active,
    metadata = excluded.metadata,
    updated_at = excluded.updated_at
  where target.user_id = p_user_id
    and (
      target.metadata ->> 'managed_by' = 'setup'
      or target.metadata ->> 'source' = 'intake-v1'
    );
  get diagnostics affected_count = row_count;
  desired_count := jsonb_array_length(coalesce(p_habits, '[]'::jsonb));
  if affected_count <> desired_count then
    raise exception 'Setup habit id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  update public.habits as existing
  set
    active = false,
    metadata = existing.metadata || jsonb_build_object(
      'source', 'intake-v1',
      'managed_by', 'setup',
      'setup_item_id', coalesce(existing.metadata ->> 'setup_item_id', existing.id::text),
      'revision', p_revision,
      'setup_state', 'archived'
    ),
    updated_at = p_completed_at
  where existing.user_id = p_user_id
    and (
      existing.metadata ->> 'managed_by' = 'setup'
      or existing.metadata ->> 'source' = 'intake-v1'
    )
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_habits, '[]'::jsonb)) as desired
      where (desired ->> 'id')::uuid = existing.id
    );

  insert into public.schedule_items as target (
    id,
    user_id,
    title,
    location,
    weekday,
    starts_at,
    ends_at,
    source,
    metadata,
    updated_at
  )
  select
    desired.id,
    p_user_id,
    desired.title,
    desired.location,
    desired.weekday,
    desired.starts_at,
    desired.ends_at,
    'onboarding',
    desired.metadata,
    p_completed_at
  from jsonb_to_recordset(coalesce(p_schedule_items, '[]'::jsonb)) as desired(
    id uuid,
    title text,
    location text,
    weekday int,
    starts_at time,
    ends_at time,
    metadata jsonb
  )
  on conflict (id) do update set
    title = excluded.title,
    location = excluded.location,
    weekday = excluded.weekday,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    source = excluded.source,
    metadata = excluded.metadata,
    updated_at = excluded.updated_at
  where target.user_id = p_user_id
    and (
      target.metadata ->> 'managed_by' = 'setup'
      or target.metadata ->> 'source' = 'intake-v1'
    );
  get diagnostics affected_count = row_count;
  desired_count := jsonb_array_length(coalesce(p_schedule_items, '[]'::jsonb));
  if affected_count <> desired_count then
    raise exception 'Setup schedule id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  delete from public.schedule_items as existing
  where existing.user_id = p_user_id
    and (
      existing.metadata ->> 'managed_by' = 'setup'
      or existing.metadata ->> 'source' = 'intake-v1'
      or (
        existing.source = 'onboarding'
        and existing.metadata = '{}'::jsonb
        and existing.title = 'Math'
        and existing.location = 'Room 204'
        and existing.weekday = 1
        and existing.starts_at = '08:15'::time
        and existing.ends_at = '09:45'::time
        and existing.notes is null
      )
    )
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_schedule_items, '[]'::jsonb)) as desired
      where (desired ->> 'id')::uuid = existing.id
    );

  insert into public.memory_entries as target (
    id,
    user_id,
    type,
    title,
    content,
    strength,
    evidence,
    metadata,
    last_seen_at,
    updated_at
  )
  select
    desired.id,
    p_user_id,
    desired.type,
    desired.title,
    desired.content,
    desired.strength,
    desired.evidence,
    desired.metadata,
    p_completed_at,
    p_completed_at
  from jsonb_to_recordset(coalesce(p_memory_entries, '[]'::jsonb)) as desired(
    id uuid,
    type text,
    title text,
    content text,
    strength numeric,
    evidence jsonb,
    metadata jsonb
  )
  on conflict (id) do update set
    type = excluded.type,
    title = excluded.title,
    content = excluded.content,
    strength = excluded.strength,
    evidence = excluded.evidence,
    metadata = excluded.metadata,
    last_seen_at = excluded.last_seen_at,
    updated_at = excluded.updated_at
  where target.user_id = p_user_id
    and (
      target.metadata ->> 'managed_by' = 'setup'
      or target.metadata ->> 'source' = 'intake-v1'
    );
  get diagnostics affected_count = row_count;
  desired_count := jsonb_array_length(coalesce(p_memory_entries, '[]'::jsonb));
  if affected_count <> desired_count then
    raise exception 'Setup memory id collides with a non-Setup row'
      using errcode = '23505';
  end if;

  delete from public.memory_entries as existing
  where existing.user_id = p_user_id
    and (
      existing.metadata ->> 'managed_by' = 'setup'
      or existing.metadata ->> 'source' = 'intake-v1'
    )
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_memory_entries, '[]'::jsonb)) as desired
      where (desired ->> 'id')::uuid = existing.id
    );

  insert into public.user_state_snapshots (
    user_id,
    scope,
    period_key,
    summary,
    signals,
    source,
    generated_at,
    metadata
  ) values (
    p_user_id,
    'onboarding',
    'setup:intake-v1',
    coalesce(p_snapshot -> 'summary', '{}'::jsonb),
    coalesce(p_snapshot -> 'signals', '{}'::jsonb),
    'backend',
    p_completed_at,
    coalesce(p_snapshot -> 'metadata', '{}'::jsonb)
  )
  on conflict (user_id, scope, period_key) do update set
    summary = excluded.summary,
    signals = excluded.signals,
    source = excluded.source,
    generated_at = excluded.generated_at,
    metadata = excluded.metadata
  returning id into snapshot_id;

  update public.intake_responses
  set
    state = 'applied',
    completed_at = p_completed_at,
    updated_at = p_completed_at,
    metadata = coalesce(p_intake_metadata, '{}'::jsonb)
      || jsonb_build_object('snapshot_id', snapshot_id::text)
  where id = target_intake.id
    and user_id = p_user_id
    and version = 'intake-v1'
    and state = 'pending';
  get diagnostics affected_count = row_count;
  if affected_count <> 1 then
    raise exception 'Intake V1 setup revision changed during apply'
      using errcode = '40001';
  end if;

  update public.profiles
  set
    display_name = case
      when target_intake.responses ? 'display_name'
        then target_intake.responses ->> 'display_name'
      else display_name
    end,
    onboarding_completed_at = p_completed_at,
    updated_at = p_completed_at,
    setup_revision = p_revision
  where id = p_user_id
    and setup_revision < p_revision;
  get diagnostics affected_count = row_count;
  if affected_count <> 1 then
    raise exception 'Profile Setup projection did not advance'
      using errcode = '40001';
  end if;

  return jsonb_build_object(
    'intake_response_id', target_intake.id,
    'request_id', target_intake.request_id,
    'base_revision', target_intake.base_revision,
    'revision', target_intake.revision,
    'state', 'applied',
    'completed_at', p_completed_at,
    'snapshot_id', snapshot_id,
    'profile_repaired', false
  );
end;
$$;

revoke all on function public.apply_intake_v1_setup_revision(
  uuid,
  uuid,
  uuid,
  int,
  int,
  timestamptz,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb
) from public, anon, authenticated;

grant execute on function public.apply_intake_v1_setup_revision(
  uuid,
  uuid,
  uuid,
  int,
  int,
  timestamptz,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb,
  jsonb
) to service_role;
