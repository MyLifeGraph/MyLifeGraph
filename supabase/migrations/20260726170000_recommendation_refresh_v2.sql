-- Recommendation refresh v2 keeps deliberate generation atomic: the previous
-- unhandled "new" feed is retained as dismissed history and the complete new
-- deterministic set is installed under the same owner lock.

create or replace function public.replace_current_recommendations_v2(
  p_user_id uuid,
  p_rows jsonb,
  p_refreshed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  candidate jsonb;
  metadata_value jsonb;
  archived_count integer := 0;
  inserted_count integer := 0;
begin
  if p_user_id is null
     or p_refreshed_at is null
     or p_rows is null
     or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) > 5 then
    raise exception 'Invalid recommendation refresh payload'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  perform 1
  from public.profiles
  where id = p_user_id
  for share;

  if not found then
    raise exception 'Recommendation profile is unavailable'
      using errcode = 'PT404';
  end if;

  if exists (
    select 1
    from public.recommendations
    where user_id = p_user_id
      and status = 'new'
      and generated_at > p_refreshed_at
  ) then
    raise exception 'A newer recommendation refresh already exists'
      using errcode = 'PT409';
  end if;

  for candidate in
    select value
    from jsonb_array_elements(p_rows)
  loop
    if jsonb_typeof(candidate) <> 'object'
       or not candidate ?& array[
         'title',
         'reason',
         'action_label',
         'category',
         'priority',
         'confidence',
         'metadata'
       ]
       or (
         candidate - array[
           'title',
           'reason',
           'action_label',
           'category',
           'priority',
           'confidence',
           'metadata'
         ]::text[]
       ) <> '{}'::jsonb
       or length(btrim(candidate ->> 'title')) not between 1 and 160
       or length(btrim(candidate ->> 'reason')) not between 1 and 700
       or length(btrim(candidate ->> 'action_label')) not between 1 and 120
       or candidate ->> 'category' not in (
         'focus',
         'recovery',
         'movement',
         'planning'
       )
       or candidate ->> 'priority' not in (
         'low',
         'medium',
         'high',
         'critical'
       )
       or jsonb_typeof(candidate -> 'confidence') <> 'number'
       or (candidate ->> 'confidence')::numeric not between 0 and 1
       or jsonb_typeof(candidate -> 'metadata') <> 'object' then
      raise exception 'Invalid recommendation refresh row'
        using errcode = '22023';
    end if;

    metadata_value := candidate -> 'metadata';
    if not metadata_value ?& array[
         'rule_id',
         'fingerprint',
         'evidence_refs',
         'period_key',
         'source_engine_version',
         'invalidation_dependencies',
         'deterministic_scores',
         'model'
       ]
       or (
         metadata_value - array[
           'rule_id',
           'fingerprint',
           'evidence_refs',
           'period_key',
           'source_engine_version',
           'invalidation_dependencies',
           'deterministic_scores',
           'model'
         ]::text[]
       ) <> '{}'::jsonb
       or metadata_value ->> 'rule_id' not in (
         'low_recovery_sleep',
         'high_stress_low_energy',
         'focus_protection',
         'movement_nudge',
         'planning_reset'
       )
       or length(btrim(metadata_value ->> 'fingerprint')) not between 20 and 300
       or metadata_value ->> 'period_key' !~ '^[0-9]{4}-W[0-9]{2}$'
       or metadata_value ->> 'source_engine_version' <> 'deterministic-v1'
       or jsonb_typeof(metadata_value -> 'evidence_refs') <> 'array'
       or jsonb_array_length(metadata_value -> 'evidence_refs') not between 1 and 40
       or jsonb_typeof(metadata_value -> 'invalidation_dependencies') <> 'array'
       or jsonb_array_length(
         metadata_value -> 'invalidation_dependencies'
       ) > 20
       or jsonb_typeof(metadata_value -> 'deterministic_scores') <> 'object'
       or jsonb_typeof(metadata_value -> 'model') <> 'null' then
      raise exception 'Invalid recommendation refresh metadata'
        using errcode = '22023';
    end if;
  end loop;

  update public.recommendations
  set
    status = 'dismissed',
    metadata = metadata || jsonb_build_object(
      'current_feed_retired_at',
      p_refreshed_at,
      'current_feed_retired_reason',
      'replaced_by_deliberate_refresh'
    ),
    updated_at = greatest(updated_at, p_refreshed_at)
  where user_id = p_user_id
    and status = 'new';

  get diagnostics archived_count = row_count;

  insert into public.recommendations (
    user_id,
    title,
    reason,
    action_label,
    category,
    confidence,
    status,
    priority,
    metadata,
    generated_at,
    updated_at
  )
  select
    p_user_id,
    value ->> 'title',
    value ->> 'reason',
    value ->> 'action_label',
    value ->> 'category',
    (value ->> 'confidence')::numeric,
    'new',
    value ->> 'priority',
    value -> 'metadata',
    p_refreshed_at,
    p_refreshed_at
  from jsonb_array_elements(p_rows) as rows(value);

  get diagnostics inserted_count = row_count;

  return jsonb_build_object(
    'contract_version', 'recommendation-refresh-v2',
    'archived_count', archived_count,
    'inserted_count', inserted_count,
    'refreshed_at', p_refreshed_at
  );
end;
$$;

revoke all on function public.replace_current_recommendations_v2(
  uuid,
  jsonb,
  timestamptz
) from public, anon, authenticated;
grant execute on function public.replace_current_recommendations_v2(
  uuid,
  jsonb,
  timestamptz
) to service_role;
