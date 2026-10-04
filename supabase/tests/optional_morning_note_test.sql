begin;
select no_plan();
insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('ea140002-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','morning-note-test@example.test','{"provider":"email"}','{}',now(),now());
update public.profiles set onboarding_completed_at=now() where id='ea140002-0000-4000-8000-000000000001';

create function pg_temp.write_note(extra jsonb, request_number integer) returns jsonb language plpgsql as $$
declare
  previous jsonb;
  capture jsonb;
begin
  select metadata #> '{captures,morning}' into previous from public.daily_logs
  where user_id='ea140002-0000-4000-8000-000000000001' and entry_date=current_date;
  capture := jsonb_build_object('branch_version','daily-capture-v5','capture_kind','morning',
    'entry_date',current_date,'capture_id','note-test-' || request_number,
    'captured_at',now(),'sleep_hours',8,'sleep_quality',7,'current_energy',6) || extra;
  return public.apply_daily_capture_branch_v1('ea140002-0000-4000-8000-000000000001',current_date,
    'morning',('ea140002-0000-4000-8000-' || lpad(request_number::text,12,'0'))::uuid,
    repeat('a',64),previous,capture,now());
end;
$$;
grant execute on function pg_temp.write_note(jsonb,integer) to service_role;
set local role service_role;
select lives_ok($$select pg_temp.write_note('{"reflection_note":"A quiet morning"}',1)$$,'save Morning context');
select is((select metadata #>> '{captures,morning,reflection_note}' from public.daily_logs where user_id='ea140002-0000-4000-8000-000000000001'), 'A quiet morning', 'note persists');
select lives_ok($$select pg_temp.write_note('{}',2)$$,'old writer omits note');
select is((select metadata #>> '{captures,morning,reflection_note}' from public.daily_logs where user_id='ea140002-0000-4000-8000-000000000001'), 'A quiet morning', 'omitted note is preserved');
select lives_ok($$select pg_temp.write_note('{"reflection_note":""}',3)$$,'explicit clear');
select is((select metadata #>> '{captures,morning,reflection_note}' from public.daily_logs where user_id='ea140002-0000-4000-8000-000000000001'), '', 'clear stays empty');
select throws_ok($$select pg_temp.write_note(jsonb_build_object('reflection_note',repeat('x',501)),4)$$, '22023', null, 'bounded note');
select throws_ok($$select pg_temp.write_note('{"reflection_note":42}',5)$$, '22023', null, 'wrong type rejected');
select ok((select energy_level=6 and sleep_hours=8 and reflection_note is null from public.daily_logs where user_id='ea140002-0000-4000-8000-000000000001'), 'no scalar note or numerical changes');
reset role;
select ok(not has_function_privilege('authenticated','public.apply_daily_capture_branch_v1(uuid,date,text,uuid,text,jsonb,jsonb,timestamptz)','execute'),'no client write grant');
select * from finish();
rollback;
