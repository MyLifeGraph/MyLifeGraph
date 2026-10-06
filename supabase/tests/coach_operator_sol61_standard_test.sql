begin;
select plan(12);
create temporary table sol_reply as select jsonb_build_object(
  'contract_version', 'coach-response-v4',
  'request_id', 'ed610000-0000-4000-8000-000000000001',
  'reply', 'Only recorded data supports this answer.',
  'uncertainty', jsonb_build_object('level','medium','reason','Limited records.'),
  'safety', jsonb_build_object('classification','normal'),
  'evidence', '[]'::jsonb,
  'agent_trace', jsonb_build_object('tool_call_count',0,'steps','[]'::jsonb,
    'limitations',jsonb_build_array('No causal conclusion.')),
  'provenance', jsonb_build_object('source','model','provider','operator_codex_pilot',
    'provider_mode','operator_subscription_pilot','model_requested','gpt-6.1-sol',
    'model_reported','gpt-6.1-sol','model_source','explicit',
    'prompt_version','free-coach-agent-prompt-v5','context_version','personal-snapshot-v3',
    'generated_at','2026-10-06T12:00:00Z','provider_called',true,
    'service_tier','standard','service_tier_status','configured','fast_mode',false,
    'snapshot_row_count',0,'snapshot_bytes',0)) as value;

select ok(private.coach_response_is_valid_v4(value,
  'ed610000-0000-4000-8000-000000000001','[]'), 'Sol Standard provenance is valid') from sol_reply;
select ok(not private.coach_response_is_valid_v4(jsonb_set(value,'{provenance,fast_mode}','true'),
  'ed610000-0000-4000-8000-000000000001','[]'), 'Sol cannot claim Fast') from sol_reply;
select ok(not private.coach_response_is_valid_v4(jsonb_set(value,'{provenance,service_tier}','"fast"'),
  'ed610000-0000-4000-8000-000000000001','[]'), 'Sol cannot use Fast tier') from sol_reply;
select ok(not private.coach_response_is_valid_v4(jsonb_set(value,'{provenance,model_reported}','"gpt-5.5"'),
  'ed610000-0000-4000-8000-000000000001','[]'), 'reported model mismatch is rejected') from sol_reply;
select ok(not private.coach_response_is_valid_v4(jsonb_set(value,'{provenance,model_requested}','"unknown"'),
  'ed610000-0000-4000-8000-000000000001','[]'), 'unlisted model is rejected') from sol_reply;
select ok(private.coach_response_is_valid_v4(jsonb_set(jsonb_set(jsonb_set(jsonb_set(value,
  '{provenance,model_requested}','"gpt-5.5"'),'{provenance,model_reported}','"gpt-5.5"'),
  '{provenance,service_tier}','"fast"'),'{provenance,fast_mode}','true'),
  'ed610000-0000-4000-8000-000000000001','[]'), 'legacy Fast history remains valid') from sol_reply;
select ok(has_function_privilege('service_role',
  'public.complete_coach_request_v3(uuid,uuid,text,jsonb,jsonb,jsonb,integer,text,jsonb,timestamptz)','EXECUTE'),
  'service completion privilege preserved');
select ok(not has_function_privilege('authenticated',
  'public.complete_coach_request_v3(uuid,uuid,text,jsonb,jsonb,jsonb,integer,text,jsonb,timestamptz)','EXECUTE'),
  'client completion privilege denied');

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values(
  'ed600000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','sol-test@example.test',crypt('test-password',gen_salt('bf')),
  now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
set local role service_role;
select is(public.claim_coach_request_v8('ed600000-0000-4000-8000-000000000001',
  'coach-request-v4','ed610000-0000-4000-8000-000000000001',
  encode(extensions.digest(convert_to('Test Sol','UTF8'),'sha256'),'hex'), current_date,
  'operator_codex_pilot','operator_subscription_pilot','gpt-6.1-sol','explicit',
  now(),now()+interval '240 seconds',5,true)->>'state','pending','Sol claim accepted');
select is((select model_requested from public.coach_requests where request_id=
  'ed610000-0000-4000-8000-000000000001'),'gpt-6.1-sol','exact model is persisted');
reset role;
select lives_ok($sql$ select public.complete_coach_request_v3(
  'ed600000-0000-4000-8000-000000000001','ed610000-0000-4000-8000-000000000001',
  'Test Sol',(select value from sol_reply),'[]',(select value->'agent_trace' from sol_reply),
  0,'standard','{"provider_called":true,"prompt_bytes":8,"context_bytes":0,"reply_codepoints":39}',now()) $sql$,
  'Standard completion passes the existing ledger and row constraints');
select is((select response#>>'{provenance,model_requested}' from public.coach_requests
  where request_id='ed610000-0000-4000-8000-000000000001'),'gpt-6.1-sol',
  'validator normalization never rewrites saved provenance');
select * from finish();
rollback;
