-- Add exactly Gemini 3.7 to the existing 3.6/3.8 provenance allowlist.
-- CREATE OR REPLACE retains OIDs/ACLs; no row, budget, lock or replay changes.
begin;
do $migration$
declare
  definition text;
  old_guard text;
  new_guard text;
  target regprocedure;
begin
  target := 'private.coach_response_is_valid_v3(jsonb,uuid,jsonb)'::regprocedure;
  definition := pg_get_functiondef(target);
  old_guard := $old$when p_value #>> '{provenance,model_requested}' = 'gemini-3.8-flash'
          then 'gemini-3.8-flash'$old$;
  new_guard := $new$when p_value #>> '{provenance,model_requested}' in ('gemini-3.7-flash', 'gemini-3.8-flash')
          then p_value #>> '{provenance,model_requested}'$new$;
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Gemini response validator definition drifted';
  end if;
  execute replace(definition, old_guard, new_guard);

  old_guard := $old$('gemini-3.6-flash', 'gemini-3.8-flash')$old$;
  new_guard := $new$('gemini-3.6-flash', 'gemini-3.7-flash', 'gemini-3.8-flash')$new$;
  foreach target in array array[
    'public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer)'::regprocedure,
    'public.claim_coach_request_v8_local_date_legacy(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,integer,boolean)'::regprocedure
  ] loop
    definition := pg_get_functiondef(target);
    if array_length(string_to_array(definition, old_guard), 1) <> 2 then
      raise exception 'Gemini claim definition drifted: %', target;
    end if;
    execute replace(definition, old_guard, new_guard);
  end loop;
end;
$migration$;
commit;
