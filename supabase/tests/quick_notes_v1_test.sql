begin;
select no_plan();
insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('ec140000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'quick-notes-test@example.test', '{"provider":"email"}', '{}', now(), now()),
 ('ec140000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'quick-notes-other@example.test', '{"provider":"email"}', '{}', now(), now());
update public.profiles set onboarding_completed_at = now(), timezone = 'Europe/Berlin'
where id in ('ec140000-0000-4000-8000-000000000001', 'ec140000-0000-4000-8000-000000000002');
create function pg_temp.save_note(note_number int, note_text text default 'A private thought.', zone text default 'Europe/Berlin')
returns jsonb language sql as $$
  select public.save_quick_note_v1('ec140000-0000-4000-8000-000000000001', jsonb_build_object(
    'contract_version', 'quick-notes-v1', 'note_id', 'ec140000-0000-4000-9000-' || lpad(note_number::text,12,'0'),
    'text', note_text, 'timezone', zone));
$$;
grant execute on function pg_temp.save_note(int,text,text) to service_role;
select ok(not has_function_privilege('authenticated','public.save_quick_note_v1(uuid,jsonb)','execute'),'client cannot save by privileged RPC');
select ok(not has_function_privilege('anon','public.read_quick_notes_v1(uuid,uuid)','execute'),'anonymous cannot read notes');
select ok(not has_function_privilege('authenticated','public.delete_quick_note_v1(uuid,uuid)','execute'),'client cannot delete by privileged RPC');
select ok(not has_table_privilege('authenticated','private.quick_note_identities','select'),'replay ledger stays private');
select ok((select relforcerowsecurity from pg_class where oid='private.quick_note_identities'::regclass),'ledger forces RLS');
set local role service_role;
select is(pg_temp.save_note(1)->>'replayed','false','first save creates one note');
select is(pg_temp.save_note(1)->>'replayed','true','exact UUID and content replays');
select is((select count(*)::int from public.behavioral_events where user_id='ec140000-0000-4000-8000-000000000001'),1,'retry does not duplicate');
select is((select count(*)::int from public.daily_logs where user_id='ec140000-0000-4000-8000-000000000001'),0,'note never creates a daily check-in');
select ok((select value is null and daily_log_id is null and unit is null from public.behavioral_events where id='ec140000-0000-4000-9000-000000000001'),'note carries no metric or capture link');
select throws_ok($$select pg_temp.save_note(1,'Changed')$$,'PT409',null,'changed replay conflicts');
select throws_ok($$select pg_temp.save_note(2,'Text','UTC')$$,'PT409',null,'wrong current profile timezone conflicts');
select throws_ok($$select pg_temp.save_note(2,'   ')$$,'22023',null,'blank text rejected');
select throws_ok($$select pg_temp.save_note(2,repeat('x',2001))$$,'22023',null,'long text rejected');
select is(jsonb_array_length(public.read_quick_notes_v1('ec140000-0000-4000-8000-000000000002')->'notes'),0,'foreign owner sees no note');
select throws_ok($$select public.delete_quick_note_v1('ec140000-0000-4000-8000-000000000002','ec140000-0000-4000-9000-000000000001')$$,'PT404',null,'foreign delete rejected');
select is(public.delete_quick_note_v1('ec140000-0000-4000-8000-000000000001','ec140000-0000-4000-9000-000000000001')->>'deleted','true','owner deletes exact note');
select is(public.delete_quick_note_v1('ec140000-0000-4000-8000-000000000001','ec140000-0000-4000-9000-000000000001')->>'deleted','true','delete retries idempotently');
select throws_ok($$select pg_temp.save_note(1)$$,'PT409',null,'late retry cannot resurrect deleted note');
do $$ begin for n in 2..53 loop perform pg_temp.save_note(n); end loop; end $$;
select is(jsonb_array_length(public.read_quick_notes_v1('ec140000-0000-4000-8000-000000000001')->'notes'),50,'bounded first page');
select is(jsonb_array_length(public.read_quick_notes_v1('ec140000-0000-4000-8000-000000000001',
 (public.read_quick_notes_v1('ec140000-0000-4000-8000-000000000001')->>'next_cursor')::uuid)->'notes'),2,'cursor returns remaining notes without overlap');
select is(public.prepare_account_deletion_v2('ec140000-0000-4000-8000-000000000001',
 'ec140000-0000-4000-8000-000000000099','DELETE')->>'state','prepared','prepare deletion blocks further product access');
select throws_ok($$select pg_temp.save_note(99)$$,'42501',null,'pending deletion blocks note writes');
select throws_ok($$select public.read_quick_notes_v1('ec140000-0000-4000-8000-000000000001')$$,'42501',null,'pending deletion blocks note reads');
select throws_ok($$select public.delete_quick_note_v1('ec140000-0000-4000-8000-000000000001','ec140000-0000-4000-9000-000000000002')$$,'42501',null,'pending deletion blocks separate note deletion');
reset role;
delete from auth.users where id='ec140000-0000-4000-8000-000000000001';
select is((select count(*)::int from private.quick_note_identities where user_id='ec140000-0000-4000-8000-000000000001'),0,'account deletion cascades note retry identities');
select is((select count(*)::int from public.behavioral_events where user_id='ec140000-0000-4000-8000-000000000001'),0,'account deletion removes note content');
select * from finish();
rollback;
