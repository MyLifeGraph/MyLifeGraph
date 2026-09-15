-- Add exactly Gemini 3.8, retaining 3.6 history and old-client/claim compatibility.
-- Preserve function OIDs, grants, lock order, budgets and replay identities.
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
  old_guard := $old$else 'gemini-3.6-flash'$old$;
  new_guard := $new$when 'gemini' then case
        when p_value #>> '{provenance,model_requested}' = 'gemini-3.8-flash'
          then 'gemini-3.8-flash'
        else 'gemini-3.6-flash'
      end$new$;
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Gemini response validator definition drifted';
  end if;
  execute replace(definition, old_guard, new_guard);

  old_guard := $old$p_model_requested is distinct from 'gemini-3.6-flash'$old$;
  new_guard := $new$(p_model_requested is null or p_model_requested not in
           ('gemini-3.6-flash', 'gemini-3.8-flash'))$new$;
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
