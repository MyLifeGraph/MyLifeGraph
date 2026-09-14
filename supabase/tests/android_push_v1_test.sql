begin;
select no_plan();

insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('eb140000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','push-test@example.test','{"provider":"email"}','{}',now(),now());
update public.profiles set onboarding_completed_at=now(),timezone='UTC'
where id='eb140000-0000-4000-8000-000000000001';
insert into auth.sessions(id,user_id) values
 ('eb140000-0000-4000-8000-000000000002','eb140000-0000-4000-8000-000000000001');

create function pg_temp.push_settings(revision bigint,request_number int,enabled boolean default true)
returns jsonb language sql as $$
  select public.apply_push_command_v1('eb140000-0000-4000-8000-000000000001',
    'eb140000-0000-4000-8000-000000000002',jsonb_build_object(
      'contract_version','android-push-v1','command','settings',
      'request_id','eb140000-0000-4000-8000-'||lpad(request_number::text,12,'0'),
      'expected_revision',revision,'consent_version','android-push-consent-v1',
      'enabled',enabled,'sleep',true,'deadlines',true,'patterns',true,
      -- Keep this test outside a deterministic 1-minute quiet window.
      'quiet_start',to_char((now() at time zone 'UTC')+interval '1 hour','HH24:MI'),
      'quiet_end',to_char((now() at time zone 'UTC')+interval '61 minutes','HH24:MI')));
$$;
create function pg_temp.register_push(revision bigint,request_number int)
returns jsonb language sql as $$
  select public.apply_push_command_v1('eb140000-0000-4000-8000-000000000001',
    'eb140000-0000-4000-8000-000000000002',jsonb_build_object(
      'contract_version','android-push-v1','command','register',
      'request_id','eb140000-0000-4000-8000-'||lpad(request_number::text,12,'0'),
      'expected_revision',revision,'device_id','eb140000-0000-4000-8000-000000000003',
      'registration_id','eb140000-0000-4000-8000-000000000004','token','synthetic-device-token-for-pgtap'));
$$;
create function pg_temp.reserve_push(kind text,key text,revision bigint default 2)
returns jsonb language sql as $$
  select public.reserve_push_v1('eb140000-0000-4000-8000-000000000001',kind,key,'UTC',revision,now()+interval '10 minutes');
$$;
grant execute on function pg_temp.push_settings(bigint,int,boolean),pg_temp.register_push(bigint,int),pg_temp.reserve_push(text,text,bigint) to service_role;

select ok(not has_table_privilege('authenticated','private.push_devices','select'),'device tokens private');
select ok(not has_function_privilege('authenticated','public.apply_push_command_v1(uuid,uuid,jsonb)','execute'),'client cannot write push');
select ok(not has_function_privilege('anon','public.reserve_push_v1(uuid,text,text,text,bigint,timestamptz)','execute'),'anonymous cannot reserve');
select ok(not has_function_privilege('authenticated','private.push_session_active_v1(uuid,uuid)','execute'),'Auth session oracle is private');
select is((select push_settings->>'enabled' from public.profiles where id='eb140000-0000-4000-8000-000000000001'),'false','push defaults off');
set local role authenticated;
set local request.jwt.claim.sub='eb140000-0000-4000-8000-000000000001';
select throws_ok($$update public.profiles set push_settings='{"enabled":true}' where id='eb140000-0000-4000-8000-000000000001'$$,
 '42501',null,'direct profile opt-in rejected');
reset role;
set local role service_role;
select throws_ok($$select pg_temp.register_push(0,10)$$,'22023',null,'registration needs explicit consent');
select is(pg_temp.push_settings(0,11)#>>'{settings,revision}','1','explicit settings saved');
select is(pg_temp.push_settings(0,11)#>>'{settings,revision}','1','exact request replayed');
select throws_ok($$select pg_temp.push_settings(0,11,false)$$,'PT409',null,'same request different payload conflicts');
select throws_ok($$select pg_temp.push_settings(0,12)$$,'PT409',null,'stale revision conflicts');
select is(pg_temp.register_push(1,13)#>>'{settings,revision}','2','registration advances revision');
select ok(not (public.get_push_state_v1('eb140000-0000-4000-8000-000000000001') ? 'token'),'token is never returned to client');
select is(jsonb_array_length(public.list_push_owners_v1()),1,'one consenting active session');
select is(pg_temp.reserve_push('sleep','stale',1),null::jsonb,'stale settings cannot send');
select ok(pg_temp.reserve_push('sleep','sleep:test') is not null,'first send reserved');
select is(pg_temp.reserve_push('sleep','sleep:test'),null::jsonb,'duplicates suppressed');
select ok(pg_temp.reserve_push('pattern','pattern:test') is not null,'second send reserved');
select is(pg_temp.reserve_push('deadlines','third'),null::jsonb,'rolling cap suppresses third send');
select ok(public.check_push_reservation_v1('eb140000-0000-4000-8000-000000000001',
 (select id from private.push_attempts where dedupe_key='sleep:test'),
 'eb140000-0000-4000-8000-000000000004',2,'UTC'),'current reserved send passes last check');
select is(pg_temp.push_settings(2,14,false)#>>'{settings,enabled}','false','opt-out retained');
select is((select count(*)::int from private.push_devices),0,'opt-out deletes active token');
select ok(not public.check_push_reservation_v1('eb140000-0000-4000-8000-000000000001',
 (select id from private.push_attempts where dedupe_key='sleep:test'),
 'eb140000-0000-4000-8000-000000000004',2,'UTC'),'revocation blocks reserved send');
select is(pg_temp.push_settings(3,15)#>>'{settings,revision}','4','explicit reenable');
select is(pg_temp.register_push(4,16)#>>'{settings,revision}','5','register after reenable');
select is(pg_temp.reserve_push('deadlines','new-after-optout',5),null::jsonb,'opt-out does not replenish budget');
update private.push_attempts set created_at=now()-interval '2 days';
select is(pg_temp.reserve_push('pattern','new-pattern',5),null::jsonb,'pattern has 30-day cooldown');
reset role;
delete from auth.sessions where id='eb140000-0000-4000-8000-000000000002';
set local role service_role;
select is(jsonb_array_length(public.list_push_owners_v1()),0,'signed-out session excluded');
select is(pg_temp.reserve_push('sleep','signedout',5),null::jsonb,'signed-out session cannot receive');
select throws_ok($$select pg_temp.push_settings(5,17)$$,'42501',null,'stale session cannot update');
reset role;
-- Exact fixture owner only; the surrounding transaction is rolled back.
delete from auth.users where id='eb140000-0000-4000-8000-000000000001';
select is((select count(*)::int from private.push_attempts where user_id='eb140000-0000-4000-8000-000000000001'),0,'account deletion cascades private attempts');
select is((select count(*)::int from private.push_requests where user_id='eb140000-0000-4000-8000-000000000001'),0,'account deletion cascades retry fingerprints');
select * from finish();
rollback;
