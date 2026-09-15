-- Accept the existing, explicitly language-bound V4 claim at completion.
-- English and legacy hashes, raw saved messages, OIDs, grants, locking,
-- provenance checks, replay checks and append-only accounting stay unchanged.
begin;

do $migration$
declare
  definition text;
  old_guard text := 'if target.message_fingerprint <> computed_fingerprint';
  new_guard text := $guard$if (target.message_fingerprint <> computed_fingerprint
     and not (
       target.contract_version = 'coach-request-v4'
       and target.message_fingerprint = encode(extensions.digest(convert_to(
         '{"language_contract":"coach-language-v1","message":'
         || to_json(p_user_message)::text || ',"response_language":"de"}',
         'UTF8'), 'sha256'), 'hex')
     ))$guard$;
begin
  definition := pg_get_functiondef(
    'public.coach_complete_request_v1_locked_body(uuid,uuid,text,jsonb,jsonb,jsonb,timestamptz)'::regprocedure
  );
  if array_length(string_to_array(definition, old_guard), 1) <> 2 then
    raise exception 'Coach completion fingerprint guard drifted';
  end if;
  execute replace(definition, old_guard, new_guard);
end;
$migration$;

commit;
