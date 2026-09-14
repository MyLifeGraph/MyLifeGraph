begin;
select no_plan();
insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('ed140000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','draft-operation@example.test','{"provider":"email"}','{}',now(),now());
update public.profiles set onboarding_completed_at=now(), timezone='UTC'
where id='ed140000-0000-4000-8000-000000000001';
create function pg_temp.claim_draft(purpose text default 'daily_capture_draft') returns jsonb language sql as $$
 select public.claim_coach_operation_v1('ed140000-0000-4000-8000-000000000001','coach-request-v4',
 'ed140000-0000-4000-9000-000000000001',repeat('a',64),current_date,'openai','user_supplied_key',
 'gpt-5.6-terra','explicit',now(),now()+interval '240 seconds',20,true,purpose);
$$;
create function pg_temp.draft_response() returns jsonb language sql as $$
 select jsonb_build_object('contract_version','coach-response-v4',
 'request_id','ed140000-0000-4000-9000-000000000001',
 'reply','Check-in draft prepared. Review the fields before saving.',
 'uncertainty',jsonb_build_object('level','low','reason','No check-in has been saved.'),
 'safety',jsonb_build_object('classification','normal'),'evidence','[]'::jsonb,
 'agent_trace',jsonb_build_object('tool_call_count',0,'steps','[]'::jsonb,'limitations','[]'::jsonb),
 'provenance',jsonb_build_object('source','model','provider','openai','provider_mode','user_supplied_key',
 'model_requested','gpt-5.6-terra','model_reported','gpt-5.6-terra','model_source','explicit',
 'prompt_version','free-coach-agent-prompt-v5','context_version','personal-snapshot-v3',
 'generated_at',now(),'provider_called',true,'service_tier','not_applicable',
 'service_tier_status','not_applicable','fast_mode',false,'snapshot_row_count',0,'snapshot_bytes',0));
$$;
create function pg_temp.complete_draft(response jsonb default pg_temp.draft_response()) returns jsonb language sql as $$
 select public.complete_capture_draft_v1('ed140000-0000-4000-8000-000000000001',
 'ed140000-0000-4000-9000-000000000001',response,
 jsonb_build_object('provider_called',true,'prompt_bytes',1500,'context_bytes',0,
 'reply_codepoints',length(response->>'reply')),now());
$$;
grant execute on function pg_temp.claim_draft(text),pg_temp.draft_response(),pg_temp.complete_draft(jsonb) to service_role;
select ok(not has_function_privilege('authenticated','public.complete_capture_draft_v1(uuid,uuid,jsonb,jsonb,timestamptz)','execute'),'draft completion stays service-only');
select ok(not has_function_privilege('anon','public.claim_coach_operation_v1(uuid,text,uuid,text,date,text,text,text,text,timestamptz,timestamptz,int,boolean,text)','execute'),'draft claim stays service-only');
set local role service_role;
select is(pg_temp.claim_draft()->>'state','pending','draft claims existing quota lifecycle');
select is((select purpose from public.coach_requests where request_id='ed140000-0000-4000-9000-000000000001'),'daily_capture_draft','purpose is durable');
select throws_ok($$select pg_temp.claim_draft('chat')$$,'PT409',null,'chat cannot reuse draft identity');
select throws_ok($$insert into public.coach_messages(user_id,request_id,contract_version,role,content,metadata,created_at)
 values('ed140000-0000-4000-8000-000000000001','ed140000-0000-4000-9000-000000000001','coach-message-v1','user','raw transcript','{}',now())$$,
 '42501',null,'draft never creates chat messages');
select throws_ok($$select pg_temp.complete_draft(jsonb_set(pg_temp.draft_response(),'{reply}','"raw transcript"'))$$,'22023',null,'raw draft result cannot be persisted');
select throws_ok($$select pg_temp.complete_draft(jsonb_set(pg_temp.draft_response(),'{agent_trace,limitations}','["private words"]'))$$,'22023',null,'draft trace cannot retain text');
select is(pg_temp.complete_draft()->>'state','completed','redacted completion succeeds');
select is(pg_temp.complete_draft()->>'state','completed','exact redacted completion replays');
select throws_ok($$select public.probe_coach_operation_v1('ed140000-0000-4000-8000-000000000001','coach-request-v4',
 'ed140000-0000-4000-9000-000000000001',repeat('a',64),'openai','user_supplied_key','gpt-5.6-terra','explicit',true,'chat')$$,
 'PT409',null,'atomic probe rejects other purpose before terminal replay');
select is(public.probe_coach_operation_v1('ed140000-0000-4000-8000-000000000001','coach-request-v4',
 'ed140000-0000-4000-9000-000000000001',repeat('a',64),'openai','user_supplied_key','gpt-5.6-terra','explicit',true,'daily_capture_draft')->>'state',
 'deleted','atomic probe truthfully returns discarded draft content');
select is((select count(*)::int from public.coach_requests where user_id='ed140000-0000-4000-8000-000000000001'
 and state='completed'),0,'old completed-only chat history has no orphan row');
select ok((select response is null and message_fingerprint is null and evidence is null and agent_trace is null
 and draft_completion_fingerprint is not null from public.coach_requests
 where request_id='ed140000-0000-4000-9000-000000000001'),'only content-free completion digest remains');
select throws_ok($$select pg_temp.complete_draft(jsonb_set(pg_temp.draft_response(),'{provenance,snapshot_bytes}','1'))$$,
 'PT409',null,'changed completion cannot replay a discarded draft');
select is((select count(*)::int from public.coach_messages where user_id='ed140000-0000-4000-8000-000000000001'),0,'no conversation pollution');
select is((select count(*)::int from public.daily_logs where user_id='ed140000-0000-4000-8000-000000000001'),0,'no check-in is created');
select is((select count(*)::int from public.coach_usage_events where user_id='ed140000-0000-4000-8000-000000000001'),1,'one durable usage event despite replay');
select is((select count(*)::int from public.coach_requests where user_id='ed140000-0000-4000-8000-000000000001' and provider_dispatch_required),1,'draft consumes the ordinary account quota');
select is(pg_temp.claim_draft()->>'state','deleted','expired draft cannot reserve a second generation');

select is(public.claim_coach_operation_v1('ed140000-0000-4000-8000-000000000001','coach-request-v4',
 'ed140000-0000-4000-9000-000000000002',repeat('b',64),current_date,'operator_codex_pilot','operator_subscription_pilot',
 'gpt-5.5','explicit',now(),now()+interval '240 seconds',5,true,'daily_capture_draft')->>'state',
 'pending','operator draft uses existing shared quota');
create function pg_temp.operator_response() returns jsonb language sql as $$
 select jsonb_set(pg_temp.draft_response(),'{request_id}','"ed140000-0000-4000-9000-000000000002"')
 || jsonb_build_object('provenance', (pg_temp.draft_response()->'provenance') || jsonb_build_object(
 'provider','operator_codex_pilot','provider_mode','operator_subscription_pilot',
 'model_requested','gpt-5.5','model_reported','gpt-5.5','service_tier','fast','service_tier_status','configured','fast_mode',true));
$$;
create function pg_temp.complete_operator() returns jsonb language sql as $$
 select public.complete_capture_draft_v1('ed140000-0000-4000-8000-000000000001',
 'ed140000-0000-4000-9000-000000000002',pg_temp.operator_response(),
 jsonb_build_object('provider_called',true,'prompt_bytes',1500,'context_bytes',0,
 'reply_codepoints',length(pg_temp.operator_response()->>'reply')),now());
$$;
select throws_ok($$select pg_temp.complete_operator()$$,'PT409',null,'operator cannot complete without its durable dispatch');
select is(public.record_coach_operator_dispatch_v1('ed140000-0000-4000-a000-000000000001',
 'ed140000-0000-4000-9000-000000000002','ed140000-0000-4000-8000-000000000001',
 'ed140000-0000-4000-b000-000000000001',now(),15)->>'state','dispatched','operator dispatch is recorded before generation');
select is(pg_temp.complete_operator()->>'state','completed','operator completion succeeds');
select is(pg_temp.complete_operator()->>'state','completed','operator completion replays');
select is((select state from public.coach_operator_dispatches where request_id='ed140000-0000-4000-9000-000000000002'),
 'completed','dispatch terminalizes atomically with content discard');
select is((select outcome from public.coach_usage_events where request_id='ed140000-0000-4000-9000-000000000002'),
 'completed','successful extraction never records a fake failure');
select is((select count(*)::int from public.coach_requests where user_id='ed140000-0000-4000-8000-000000000001'
 and state='completed'),0,'old client still sees no completed message-less turn');
select is((select dispatch_count from public.coach_operator_daily_budgets where utc_date=(now() at time zone 'UTC')::date),
 1,'global operator quota stays consumed exactly once');
select lives_ok($$select public.reconcile_expired_coach_operator_dispatches_v1(now()+interval '1 day')$$,
 'old startup reconciler tolerates successful discarded draft');
select is((select state from public.coach_operator_dispatches where request_id='ed140000-0000-4000-9000-000000000002'),
 'completed','reconciliation cannot misclassify completed extraction after crash');
select is((select count(*)::int from public.coach_usage_events where user_id='ed140000-0000-4000-8000-000000000001'),
 2,'two successful operations retain exactly two usage rows');
select is(public.prepare_account_deletion_v2('ed140000-0000-4000-8000-000000000001',
 'ed140000-0000-4000-8000-000000000099','DELETE')->>'state','prepared','deletion prepares normally after draft');
select throws_ok($$select pg_temp.claim_draft()$$,'42501',null,'pending deletion blocks draft claim/replay');
select throws_ok($$select pg_temp.complete_draft()$$,'42501',null,'pending deletion blocks draft completion/replay');
select * from finish();
rollback;
