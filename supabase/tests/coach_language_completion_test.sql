begin;
select plan(13);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ee000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'language-completion@example.test', crypt('test-password', gen_salt('bf')),
  now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

-- Literal hashes are shared with the Python test, including JSON escaping.
create temporary table language_case (id uuid, message text, fingerprint text);
insert into language_case values
  ('ee100000-0000-4000-8000-000000000001', E'Wie geht es mir? "Grüße"\nC:\\Tag 💤',
   '2896916f38f5adaf55de61f0e19d22610954bd1de1d0c29bdb617d6d97c0f821'),
  ('ee100000-0000-4000-8000-000000000002', 'How am I doing?',
   'af90a06e5e05d4f6ed92d49d1e0b4e21622701fe0222bd995683a7b6276f7878');
grant select on language_case to service_role;

create function pg_temp.language_response(id uuid) returns jsonb language sql as $$
  select jsonb_build_object(
    'contract_version', 'coach-response-v4', 'request_id', id,
    'reply', 'Die Daten sind begrenzt.',
    'uncertainty', jsonb_build_object('level', 'medium', 'reason', 'Wenig Daten.'),
    'safety', jsonb_build_object('classification', 'normal'),
    'evidence', '[]'::jsonb,
    'agent_trace', jsonb_build_object('tool_call_count', 0, 'steps', '[]'::jsonb,
      'limitations', jsonb_build_array('No personal-data tool was needed.')),
    'provenance', jsonb_build_object(
      'source', 'model', 'provider', 'openai', 'provider_mode', 'user_supplied_key',
      'model_requested', 'gpt-5.6-terra', 'model_reported', 'gpt-5.6-terra',
      'model_source', 'explicit', 'prompt_version', 'free-coach-agent-prompt-v5',
      'context_version', 'personal-snapshot-v3', 'generated_at', now(),
      'provider_called', true, 'service_tier', 'not_applicable',
      'service_tier_status', 'not_applicable', 'fast_mode', false,
      'snapshot_row_count', 0, 'snapshot_bytes', 0
    )
  )
$$;

create function pg_temp.finish_language(id uuid, message text) returns jsonb
language sql as $$
  select public.complete_coach_request_v3(
    'ee000000-0000-4000-8000-000000000001', id, message,
    pg_temp.language_response(id), '[]',
    pg_temp.language_response(id) -> 'agent_trace', 0, 'not_applicable',
    jsonb_build_object('provider_called', true, 'prompt_bytes', 10,
      'context_bytes', 0, 'reply_codepoints', char_length('Die Daten sind begrenzt.')),
    now()
  )
$$;

grant execute on function pg_temp.language_response(uuid) to service_role;
grant execute on function pg_temp.finish_language(uuid, text) to service_role;
set local role service_role;
select is(public.claim_coach_request_v8(
  'ee000000-0000-4000-8000-000000000001', 'coach-request-v4', id,
  fingerprint, current_date, 'openai', 'user_supplied_key', 'gpt-5.6-terra',
  'explicit', now(), now() + interval '240 seconds', 20, true
) ->> 'state', 'pending', 'German request is claimed with language-bound hash')
from language_case where id = 'ee100000-0000-4000-8000-000000000001';

select throws_ok($$
  select pg_temp.finish_language('ee100000-0000-4000-8000-000000000001', 'changed text')
$$, 'PT409', null, 'changed German message is still rejected');

select is(pg_temp.finish_language(id, message) ->> 'state', 'completed',
  'German answer completes instead of leaving a pending request')
from language_case where id = 'ee100000-0000-4000-8000-000000000001';
select is(pg_temp.finish_language(id, message) ->> 'state', 'completed',
  'German completion replay is idempotent')
from language_case where id = 'ee100000-0000-4000-8000-000000000001';

select is(public.probe_coach_terminal_replay_v1(
  'ee000000-0000-4000-8000-000000000001', 'coach-request-v4', id, fingerprint,
  'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
) ->> 'state', 'completed', 'same-language retry returns the completed answer')
from language_case where id = 'ee100000-0000-4000-8000-000000000001';
select throws_ok($$
  select public.probe_coach_terminal_replay_v1(
    'ee000000-0000-4000-8000-000000000001', 'coach-request-v4', id,
    encode(extensions.digest(convert_to(message, 'UTF8'), 'sha256'), 'hex'),
    'openai', 'user_supplied_key', 'gpt-5.6-terra', 'explicit', true
  ) from language_case where id = 'ee100000-0000-4000-8000-000000000001'
$$, 'PT409', null, 'same-id retry cannot switch to English');

select is(public.claim_coach_request_v8(
  'ee000000-0000-4000-8000-000000000001', 'coach-request-v4', id,
  fingerprint, current_date, 'openai', 'user_supplied_key', 'gpt-5.6-terra',
  'explicit', now(), now() + interval '240 seconds', 20, true
) ->> 'state', 'pending', 'next question is not blocked as already in progress')
from language_case where id = 'ee100000-0000-4000-8000-000000000002';
select is(pg_temp.finish_language(id, message) ->> 'state', 'completed',
  'historical English fingerprint completes unchanged')
from language_case where id = 'ee100000-0000-4000-8000-000000000002';
select is((select count(*)::int from public.coach_usage_events
  where user_id = 'ee000000-0000-4000-8000-000000000001'), 2,
  'two completed requests create exactly two usage rows');
select is((select count(*)::int from public.coach_messages
  where user_id = 'ee000000-0000-4000-8000-000000000001'), 4,
  'replay creates no duplicate messages');
select is((select content from public.coach_messages
  where request_id = 'ee100000-0000-4000-8000-000000000001' and role = 'user'),
  (select message from language_case where id = 'ee100000-0000-4000-8000-000000000001'),
  'saved user text remains unwrapped and unchanged');

reset role;
select ok(not has_function_privilege('service_role',
  'public.coach_complete_request_v1_locked_body(uuid,uuid,text,jsonb,jsonb,jsonb,timestamptz)',
  'execute'), 'private completion delegate remains inaccessible');
select ok(not has_function_privilege('anon',
  'public.complete_coach_request_v3(uuid,uuid,text,jsonb,jsonb,jsonb,int,text,jsonb,timestamptz)',
  'execute') and not has_function_privilege('authenticated',
  'public.complete_coach_request_v3(uuid,uuid,text,jsonb,jsonb,jsonb,int,text,jsonb,timestamptz)',
  'execute'), 'completion remains backend-only');
select * from finish();
rollback;
