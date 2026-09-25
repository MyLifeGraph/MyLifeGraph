begin;
select no_plan();

insert into auth.users(id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('eb250000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','checkin-push-test@example.test','{"provider":"email"}','{}',now(),now());
update public.profiles set onboarding_completed_at=now(),timezone='UTC'
where id='eb250000-0000-4000-8000-000000000001';
insert into auth.sessions(id,user_id) values
 ('eb250000-0000-4000-8000-000000000002','eb250000-0000-4000-8000-000000000001');

create function pg_temp.checkin_settings(revision bigint,request_number int,extension jsonb default '{}')
returns jsonb language sql as $$
 select public.apply_push_command_v1('eb250000-0000-4000-8000-000000000001',
 'eb250000-0000-4000-8000-000000000002',jsonb_build_object(
 'contract_version','android-push-v1','command','settings',
 'request_id','eb250000-0000-4000-8000-'||lpad(request_number::text,12,'0'),
 'expected_revision',revision,'consent_version','android-push-consent-v1',
 'enabled',true,'sleep',true,'deadlines',true,'patterns',true,
 'quiet_start',to_char((now() at time zone 'UTC')+interval '1 hour','HH24:MI'),
 'quiet_end',to_char((now() at time zone 'UTC')+interval '61 minutes','HH24:MI')) || extension);
$$;
create function pg_temp.checkin_reserve(kind text, key text, revision bigint default 2)
returns jsonb language sql as $$
 select public.reserve_push_v1('eb250000-0000-4000-8000-000000000001',kind,key,'UTC',revision,now()+interval '5 minutes');
$$;
grant execute on function pg_temp.checkin_settings(bigint,int,jsonb),pg_temp.checkin_reserve(text,text,bigint) to service_role;

select ok(not has_function_privilege('authenticated','private.checkin_push_due_v1(uuid,text,timestamp)','execute'),'capture presence helper remains backend-only');
set local role service_role;
select ok(not private.checkin_push_due_v1('eb250000-0000-4000-8000-000000000001','morning',now() at time zone 'UTC'),'check-ins default off');
select throws_ok($$select pg_temp.checkin_settings(0,10,'{"morning":true}')$$,'22023',null,'partial extension rejected');
select is(pg_temp.checkin_settings(0,11,jsonb_build_object('morning',true,'evening',true,
 'morning_time',to_char(now() at time zone 'UTC','HH24:MI'),
 'evening_time',to_char(now() at time zone 'UTC','HH24:MI')))#>>'{settings,revision}','1','explicit check-in opt-in saved');
select is(public.apply_push_command_v1('eb250000-0000-4000-8000-000000000001',
 'eb250000-0000-4000-8000-000000000002',jsonb_build_object(
 'contract_version','android-push-v1','command','register',
 'request_id','eb250000-0000-4000-8000-000000000012','expected_revision',1,
 'device_id','eb250000-0000-4000-8000-000000000003',
 'registration_id','eb250000-0000-4000-8000-000000000004',
 'token','synthetic-checkin-push-test-token'))#>>'{settings,revision}','2','register test device');
select ok(pg_temp.checkin_reserve('sleep','sleep:test') is not null,'first regular reminder');
select ok(pg_temp.checkin_reserve('deadlines','deadlines:test') is not null,'second regular reminder');
select is(pg_temp.checkin_reserve('sleep','sleep:third'),null::jsonb,'regular bucket stays capped');
select is(pg_temp.checkin_reserve('morning','wrong-day'),null::jsonb,'check-in dedupe must match current day');
select ok(pg_temp.checkin_reserve('morning','morning:'||(now() at time zone 'UTC')::date) is not null,'check-in not starved by regular budget');
select is(pg_temp.checkin_reserve('morning','morning:'||(now() at time zone 'UTC')::date),null::jsonb,'same check-in never duplicated');
reset role;
insert into public.daily_logs(user_id,entry_date,source,metadata)
values ('eb250000-0000-4000-8000-000000000001',(now() at time zone 'UTC')::date,'test',
 '{"captures":{"morning":{"capture_id":"saved-checkin"}}}');
set local role service_role;
select ok(not public.check_push_reservation_v1('eb250000-0000-4000-8000-000000000001',
 (select id from private.push_attempts where user_id='eb250000-0000-4000-8000-000000000001' and kind='morning'),
 'eb250000-0000-4000-8000-000000000004',2,'UTC'),'saving Morning after reservation suppresses dispatch');
select ok(pg_temp.checkin_reserve('evening','evening:'||(now() at time zone 'UTC')::date) is not null,'saved Morning does not suppress Evening');
select is(pg_temp.checkin_settings(2,13)#>>'{settings,morning}','true','older client settings retain check-in preference');
select is((public.get_push_state_v1('eb250000-0000-4000-8000-000000000001')#>>'{settings,evening}'),'true','older client retains Evening preference');
reset role;
select * from finish();
rollback;
