begin;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('f9000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reversible-flow@example.test', '{}', '{}', now(), now());
insert into public.focus_sessions(id,user_id,status,started_at,ended_at,planned_minutes,actual_minutes,metadata,updated_at)
values ('f9000000-0000-4000-8000-000000000002','f9000000-0000-4000-8000-000000000001',
  'completed','2026-09-20T10:00:00Z','2026-09-20T10:30:00Z',30,30,
  '{"entry_date":"2026-09-20","recovery_minutes":0}', '2026-09-20T10:30:00Z');

select ok(not has_function_privilege('authenticated',
  'public.correct_focus_time_v1(uuid,uuid,uuid,timestamptz,integer)', 'execute'), 'correction requires service authority');
select ok(not has_table_privilege('service_role','private.focus_time_corrections','insert'), 'ledger is not directly writable');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='private.focus_time_corrections'::regclass), 'ledger forces RLS');

create temporary table correction_result as select public.correct_focus_time_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000002',
  'f9000000-0000-4000-8000-000000000003','2026-09-20T10:30:00Z',20) as result;
select is((select actual_minutes from public.focus_sessions where id='f9000000-0000-4000-8000-000000000002'),20,'canonical duration updated');
select is((select ended_at from public.focus_sessions where id='f9000000-0000-4000-8000-000000000002'),
  '2026-09-20T10:20:00Z'::timestamptz,'elapsed interval matches duration');
select is((select (metadata->'time_correction'->>'original_ended_at')::timestamptz from public.focus_sessions
  where id='f9000000-0000-4000-8000-000000000002'),'2026-09-20T10:30:00Z'::timestamptz,'original timestamp retained');
select is(public.correct_focus_time_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000002',
  'f9000000-0000-4000-8000-000000000003','2026-09-20T10:30:00Z',20)->>'replayed','true','lost response replays exactly');
select throws_ok($$select public.correct_focus_time_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000002',
  'f9000000-0000-4000-8000-000000000003','2026-09-20T10:30:00Z',19)$$,
  'PT409','Correction request changed.','retry identity cannot be repurposed');
select throws_ok($$update public.focus_sessions set ended_at='2026-09-20T10:10:00Z',actual_minutes=10
  where id='f9000000-0000-4000-8000-000000000002'$$,'23514','A terminal focus session is immutable.','direct terminal update stays blocked');
select throws_ok($$select public.correct_focus_time_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000002',
  'f9000000-0000-4000-8000-000000000004',(select (result->>'updated_at')::timestamptz from correction_result),31)$$,
  'PT409','Correction exceeds the recorded session.','cannot invent extra study time');
select throws_ok($$select public.correct_focus_time_v1(
  'f9000000-0000-4000-8000-000000000099','f9000000-0000-4000-8000-000000000002',
  'f9000000-0000-4000-8000-000000000005','2026-09-20T10:30:00Z',10)$$,
  'PT404','Focus session unavailable.','another owner cannot correct a session');

insert into public.notifications(id,user_id,title,message,type,updated_at)
values('f9000000-0000-4000-8000-000000000006','f9000000-0000-4000-8000-000000000001',
  'Reminder','Test','reminder','2026-09-20T10:00:00Z');
create temporary table dismissal as select public.apply_notification_action_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000006',
  'f9000000-0000-4000-8000-000000000007','dismiss','2026-09-20T10:00:00Z') as result;
select lives_ok($$select public.apply_notification_action_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000006',
  'f9000000-0000-4000-8000-000000000008','restore',(select (result->>'updated_at')::timestamptz from dismissal))$$,'restore succeeds');
select ok((select dismissed_at is null and is_read and read_at is not null from public.notifications
  where id='f9000000-0000-4000-8000-000000000006'),'restored notification retains its read history');
select is(public.apply_notification_action_v1(
  'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000006',
  'f9000000-0000-4000-8000-000000000008','restore',(select (result->>'updated_at')::timestamptz from dismissal))->>'replayed','true','restore replay remains idempotent');

select * from finish();
rollback;
