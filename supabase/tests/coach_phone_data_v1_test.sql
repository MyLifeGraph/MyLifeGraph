-- Local disposable database only; all synthetic writes roll back.
begin;
select no_plan();

insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
 ('ed040000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phone-owner@example.test','{"provider":"email"}','{}',now(),now()),
 ('ed040000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phone-other@example.test','{"provider":"email"}','{}',now(),now());
update public.profiles set onboarding_completed_at=now(),timezone='Europe/Berlin'
where id in ('ed040000-0000-4000-8000-000000000001','ed040000-0000-4000-8000-000000000002');
insert into public.behavioral_events(user_id,event_type,value,occurred_at,source)
values ('ed040000-0000-4000-8000-000000000001','manual_fixture',8,now(),'app');

create function pg_temp.phone_command(operation text,revision bigint,number int,device text default 'ed040000-0000-4000-8000-000000000010',zone text default 'Europe/Berlin')
returns jsonb language sql as $$
select public.apply_coach_phone_data_v1('ed040000-0000-4000-8000-000000000001',jsonb_build_object(
 'contract_version','coach-phone-data-v1','request_id','ed040000-0000-4000-8000-'||lpad(number::text,12,'0'),
 'expected_revision',revision,'command',operation,
 'device_id',case when operation in ('enable','sync') then device end,
 'consent_version',case when operation='enable' then 'coach-phone-consent-v1' end,
 'data',case when operation='sync' then jsonb_build_object('timezone',zone,'captured_at',now(),
   'days',(select jsonb_agg(jsonb_build_object('date',(now() at time zone zone)::date-n,'minutes',30)) from generate_series(0,6)n),
   'apps',jsonb_build_array(jsonb_build_object('name','Synthetic app','minutes',210)), 'attempts_today',null) end));
$$;
grant execute on function pg_temp.phone_command(text,bigint,int,text,text) to service_role;

select ok(not has_function_privilege('authenticated','public.apply_coach_phone_data_v1(uuid,jsonb)','execute'),'client cannot call RPC');
select ok(not has_function_privilege('anon','public.apply_coach_phone_data_v1(uuid,jsonb)','execute'),'anonymous cannot call RPC');
select is((select coach_phone_data->>'enabled' from public.profiles where id='ed040000-0000-4000-8000-000000000001'),'false','default off');
set local role authenticated;
set local request.jwt.claim.sub='ed040000-0000-4000-8000-000000000001';
select throws_ok($$update public.profiles set coach_phone_data='{"enabled":true,"revision":0}' where id='ed040000-0000-4000-8000-000000000001'$$,'42501',null,'direct cloud consent mutation forbidden');
reset role;
set local role service_role;
select is(pg_temp.phone_command('enable',0,11)#>>'{coach_phone_data,revision}','1','explicit consent');
select is(pg_temp.phone_command('enable',0,11)#>>'{coach_phone_data,revision}','1','exact request replays');
select throws_ok($$select pg_temp.phone_command('sync',1,12,'ed040000-0000-4000-8000-000000000099')$$,'22023',null,'wrong device rejected');
select throws_ok($$select pg_temp.phone_command('sync',1,12,'ed040000-0000-4000-8000-000000000010','UTC')$$,'22023',null,'wrong profile timezone rejected');
select is(pg_temp.phone_command('sync',1,13)#>>'{coach_phone_data,revision}','2','explicit snapshot sync');
select is((select count(*)::int from public.behavioral_events where user_id='ed040000-0000-4000-8000-000000000001'),1,'no phone data enters correlation observations');
select is((select coach_phone_data->>'enabled' from public.profiles where id='ed040000-0000-4000-8000-000000000002'),'false','other owner unchanged');
select is(pg_temp.phone_command('disable',2,14)#>>'{coach_phone_data,enabled}','false','revoke clears enabled');
select ok((select coach_phone_data->'data'='null'::jsonb and coach_phone_last_request->'data'='null'::jsonb from public.profiles where id='ed040000-0000-4000-8000-000000000001'),'revoke removes snapshot and replay payload');
select throws_ok($$select pg_temp.phone_command('sync',2,15)$$,'PT409',null,'late sync CAS rejected');
select throws_ok($$select pg_temp.phone_command('sync',3,16)$$,'22023',null,'current revision cannot bypass revoked consent');
select throws_ok($$select pg_temp.phone_command('enable',0,11)$$,'PT409',null,'old enable cannot resurrect sharing');
select is(pg_temp.phone_command('enable',3,17)#>>'{coach_phone_data,revision}','4','explicit reconnect');
select is(pg_temp.phone_command('delete',4,18)#>>'{coach_phone_data,enabled}','false','delete revokes binding too');
reset role;
select * from finish();
rollback;
