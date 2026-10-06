-- Add one explicit operator model/tier pair. Preserve historical Fast replies,
-- function OIDs/ACLs, owner locks, exact replay and append-only budgets.
begin;
do $migration$
declare
  definition text;
  old_guard text;
  new_guard text;
  guard text;
  target regprocedure;
begin
  target := 'private.coach_response_is_valid_v4(jsonb,uuid,jsonb)'::regprocedure;
  definition := pg_get_functiondef(target);
  old_guard := $old$is distinct from 'gpt-5.5'$old$;
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Operator response model guard drifted';
  end if;
  definition := replace(definition, old_guard,
    $new$is null or p_value #>> '{provenance,model_requested}' not in ('gpt-5.5', 'gpt-6.1-sol')$new$);
  foreach guard in array array[
    $guard$p_value #>> '{provenance,model_reported}' <> 'gpt-5.5'$guard$,
    $guard$p_value #>> '{provenance,service_tier}' is distinct from 'fast'$guard$,
    $guard$(p_value #>> '{provenance,fast_mode}')::boolean is not true$guard$
  ] loop
    if array_length(string_to_array(definition, guard), 1) <> 2 then
      raise exception 'Operator response provenance guard drifted';
    end if;
  end loop;
  definition := replace(definition,
    $old$p_value #>> '{provenance,model_reported}' <> 'gpt-5.5'$old$,
    $new$p_value #>> '{provenance,model_reported}' <> p_value #>> '{provenance,model_requested}'$new$);
  definition := replace(definition,
    $old$p_value #>> '{provenance,service_tier}' is distinct from 'fast'$old$,
    $new$p_value #>> '{provenance,service_tier}' is distinct from
      case when p_value #>> '{provenance,model_requested}' = 'gpt-6.1-sol'
        then 'standard' else 'fast' end$new$);
  definition := replace(definition,
    $old$(p_value #>> '{provenance,fast_mode}')::boolean is not true$old$,
    $new$(p_value #>> '{provenance,fast_mode}')::boolean is distinct from
      (p_value #>> '{provenance,model_requested}' = 'gpt-5.5')$new$);
  old_guard := 'return private.coach_response_is_valid_v3(';
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Operator response delegate drifted';
  end if;
  new_guard := $new$-- Normalize solely for the legacy structural validator; saved JSON stays exact.
  if p_value #>> '{provenance,provider}' = 'operator_codex_pilot'
     and p_value #>> '{provenance,model_requested}' = 'gpt-6.1-sol' then
    normalized := jsonb_set(normalized, '{provenance,model_requested}', '"gpt-5.5"');
    if p_value #>> '{provenance,model_reported}' is not null then
      normalized := jsonb_set(normalized, '{provenance,model_reported}', '"gpt-5.5"');
    end if;
    normalized := jsonb_set(normalized, '{provenance,service_tier}', '"fast"');
    normalized := jsonb_set(normalized, '{provenance,fast_mode}', 'true');
  end if;
  return private.coach_response_is_valid_v3($new$;
  execute replace(definition, old_guard, new_guard);

  target := 'public.claim_coach_request_v8_local_date_legacy(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer,boolean)'::regprocedure;
  definition := pg_get_functiondef(target);
  old_guard := $old$p_model_requested is distinct from 'gpt-5.5'$old$;
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Operator claim model guard drifted';
  end if;
  execute replace(definition, old_guard,
    $new$(p_model_requested is null or p_model_requested not in ('gpt-5.5', 'gpt-6.1-sol'))$new$);

  target := 'public.complete_coach_request_v3(uuid,uuid,text,jsonb,jsonb,jsonb,integer,text,jsonb,timestamptz)'::regprocedure;
  definition := pg_get_functiondef(target);
  old_guard := $old$p_service_tier not in ('fast', 'not_applicable')$old$;
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Operator completion tier guard drifted';
  end if;
  execute replace(definition, old_guard,
    $new$p_service_tier not in ('fast', 'standard', 'not_applicable')$new$);

  select pg_get_constraintdef(oid) into strict definition
  from pg_constraint where conrelid = 'public.coach_requests'::regclass
    and conname = 'coach_requests_agent_fields';
  old_guard := $old$ARRAY['fast'::text, 'not_applicable'::text]$old$;
  if array_length(string_to_array(definition, old_guard), 1) <> 4 then
    raise exception 'Coach agent field constraint drifted';
  end if;
  alter table public.coach_requests drop constraint coach_requests_agent_fields;
  execute 'alter table public.coach_requests add constraint coach_requests_agent_fields '
    || replace(definition, old_guard, $new$ARRAY['fast'::text, 'standard'::text, 'not_applicable'::text]$new$);
end;
$migration$;
commit;
