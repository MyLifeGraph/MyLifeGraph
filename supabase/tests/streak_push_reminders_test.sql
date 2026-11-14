begin;
select no_plan();
select is(private.streak_capture_deadline_v1('2026-03-28','Europe/Berlin'),'2026-03-30T23:00:00Z'::timestamptz,'Berlin spring grace uses elapsed hours');
select is(private.streak_capture_deadline_v1('2026-10-24','Europe/Berlin'),'2026-10-26T22:00:00Z'::timestamptz,'Berlin autumn grace uses elapsed hours');
select is(private.streak_capture_deadline_v1('2011-12-29','Pacific/Apia'),'2012-01-01T10:00:00Z'::timestamptz,'skipped calendar midnight matches Today');
select is(private.streak_capture_deadline_v1('2026-10-31','America/Havana'),'2026-11-03T04:00:00Z'::timestamptz,'repeated midnight chooses earlier fold');
select ok(not has_function_privilege('authenticated','public.get_streak_push_candidates_v1(uuid,text,bigint)','execute'),'candidate read is service only');
select ok(not has_function_privilege('anon','private.reserve_streak_push_at_v1(uuid,text,text,text,bigint,timestamptz,timestamptz)','execute'),'private reservation cannot be used anonymously');

insert into auth.users(id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('eb140000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','streak-push@example.test','{"provider":"email"}','{}',now(),now());
update public.profiles set onboarding_completed_at=now(),timezone='UTC' where id='eb140000-0000-4000-8000-000000000001';
insert into auth.sessions(id,user_id) values('eb140000-0000-4000-8000-000000000002','eb140000-0000-4000-8000-000000000001');
create function pg_temp.streak_settings(rev bigint,req int,extension jsonb default '{}') returns jsonb language sql as $$
select public.apply_push_command_v1('eb140000-0000-4000-8000-000000000001','eb140000-0000-4000-8000-000000000002',
jsonb_build_object('contract_version','android-push-v1','command','settings','request_id','eb140000-0000-4000-8000-'||lpad(req::text,12,'0'),
'expected_revision',rev,'consent_version','android-push-consent-v1','enabled',true,'sleep',true,'deadlines',true,'patterns',true,
'quiet_start',case when extract(hour from now() at time zone 'UTC')=12 then '11:00' else '12:00' end,
'quiet_end',case when extract(hour from now() at time zone 'UTC')=12 then '11:01' else '12:01' end)||extension);
$$;
create function pg_temp.reserve_streak(kind text,key text,at_time timestamptz,expiry timestamptz,rev bigint default 2,zone text default 'UTC') returns jsonb language sql as $$
select private.reserve_streak_push_at_v1('eb140000-0000-4000-8000-000000000001',kind,key,zone,rev,expiry,at_time);
$$;
grant execute on function pg_temp.streak_settings(bigint,int,jsonb),pg_temp.reserve_streak(text,text,timestamptz,timestamptz,bigint,text) to service_role;

-- Receipts are test fixtures in this disposable database only. The independent
-- Python worker tests additionally require complete projection-consistent captures.
insert into public.daily_logs(id,user_id,entry_date,source,metadata)
values ('eb140000-0000-4000-8000-000000000010','eb140000-0000-4000-8000-000000000001','2026-11-11','test',
'{"captures":{"morning":{"capture_id":"m"},"evening":{"capture_id":"e"}}}');
insert into public.daily_capture_request_identities(request_id,user_id,entry_date,branch,request_fingerprint,capture_id,captured_at,result_daily_log_id,result_updated_at,created_at)
select ('eb140000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'eb140000-0000-4000-8000-000000000001',
'2026-11-11',branch,repeat('a',64),branch,'2026-11-11T20:00:00Z','eb140000-0000-4000-8000-000000000010','2026-11-11T20:00:00Z','2026-11-11T20:00:00Z'
from (values(101,'morning'),(102,'evening')) x(i,branch);

set local role service_role;
select is(public.get_push_state_v1('eb140000-0000-4000-8000-000000000001')#>>'{settings,streak}','false','no automatic opt-in');
select is((select count(*)::int from private.streak_push_window_v1('eb140000-0000-4000-8000-000000000001','streak_10h','2026-11-14T14:00:00Z')),0,'disabled category never due');
select is(pg_temp.streak_settings(0,20,'{"streak":true}')#>>'{settings,revision}','1','explicit opt-in');
select is(public.apply_push_command_v1('eb140000-0000-4000-8000-000000000001','eb140000-0000-4000-8000-000000000002',
jsonb_build_object('contract_version','android-push-v1','command','register','request_id','eb140000-0000-4000-8000-000000000021',
'expected_revision',1,'device_id','eb140000-0000-4000-8000-000000000003','registration_id','eb140000-0000-4000-8000-000000000004','token','synthetic-streak-device-token'))#>>'{settings,revision}','2','register session-bound device');
select is((select dedupe_key from private.streak_push_window_v1('eb140000-0000-4000-8000-000000000001','streak_10h','2026-11-14T14:00:00Z')),'streak:2026-11-12:10h','10h window uses missing day and exact offset');
select is((select count(*)::int from private.streak_push_window_v1('eb140000-0000-4000-8000-000000000001','streak_10h','2026-11-14T13:59:59Z')),0,'not early');
select is((select count(*)::int from private.streak_push_window_v1('eb140000-0000-4000-8000-000000000001','streak_10h','2026-11-14T14:15:00Z')),0,'expired window has no catch-up');
select is(pg_temp.reserve_streak('streak_10h','wrong-key','2026-11-14T14:00Z','2026-11-14T14:15Z'),null::jsonb,'date and offset identity checked');
select is(pg_temp.reserve_streak('streak_10h','streak:2026-11-12:10h','2026-11-14T14:00Z','2026-11-14T14:15Z',1),null::jsonb,'stale revision denied');
select is(pg_temp.reserve_streak('streak_10h','streak:2026-11-12:10h','2026-11-14T14:00Z','2026-11-14T14:15Z',2,'Europe/Berlin'),null::jsonb,'timezone mismatch denied');
select ok(pg_temp.reserve_streak('streak_10h','streak:2026-11-12:10h','2026-11-14T14:00Z','2026-11-14T14:15Z') is not null,'first reminder reserved');
select is(pg_temp.reserve_streak('streak_10h','streak:2026-11-12:10h','2026-11-14T14:01Z','2026-11-14T14:15Z'),null::jsonb,'duplicate worker cannot reserve twice');
select ok(private.check_push_reservation_at_v1('eb140000-0000-4000-8000-000000000001',
(select id from private.push_attempts where user_id='eb140000-0000-4000-8000-000000000001' and kind='streak_10h'),
'eb140000-0000-4000-8000-000000000004',2,'UTC','2026-11-14T14:05Z'),'fresh reservation dispatchable');
select ok(pg_temp.reserve_streak('streak_5h','streak:2026-11-12:5h','2026-11-14T19:00Z','2026-11-14T19:15Z') is not null,'second offset is independent');
select ok(public.reserve_push_v1('eb140000-0000-4000-8000-000000000001','sleep','sleep:bucket','UTC',2,now()+interval '5 minutes') is not null,'streak attempts do not consume regular budget');
select ok(public.reserve_push_v1('eb140000-0000-4000-8000-000000000001','deadlines','deadlines:bucket','UTC',2,now()+interval '5 minutes') is not null,'second regular slot remains');
select is(public.reserve_push_v1('eb140000-0000-4000-8000-000000000001','sleep','sleep:third','UTC',2,now()+interval '5 minutes'),null::jsonb,'regular cap unchanged');
reset role;
insert into public.daily_logs(id,user_id,entry_date,source,metadata)
values ('eb140000-0000-4000-8000-000000000011','eb140000-0000-4000-8000-000000000001','2026-11-12','test','{"captures":{"morning":{"capture_id":"m2"},"evening":{"capture_id":"e2"}}}');
insert into public.daily_capture_request_identities(request_id,user_id,entry_date,branch,request_fingerprint,capture_id,captured_at,result_daily_log_id,result_updated_at,created_at)
select ('eb140000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'eb140000-0000-4000-8000-000000000001',
'2026-11-12',branch,repeat('b',64),branch,'2026-11-14T19:05Z','eb140000-0000-4000-8000-000000000011','2026-11-14T19:05Z','2026-11-14T19:05Z'
from (values(103,'morning'),(104,'evening')) x(i,branch);
set local role service_role;
select ok(not private.check_push_reservation_at_v1('eb140000-0000-4000-8000-000000000001',
(select id from private.push_attempts where user_id='eb140000-0000-4000-8000-000000000001' and kind='streak_5h'),
'eb140000-0000-4000-8000-000000000004',2,'UTC','2026-11-14T19:06Z'),'saving both check-ins after reservation suppresses dispatch');
select is(pg_temp.reserve_streak('streak_10h','streak:2026-11-13:10h','2026-11-15T14:00Z','2026-11-15T14:15Z'),null::jsonb,'rolling streak cap survives day boundary');
select ok(pg_temp.reserve_streak('streak_10h','streak:2026-11-13:10h','2026-11-15T14:05Z','2026-11-15T14:15Z') is not null,'only aged-out attempts free rolling capacity');
select is(pg_temp.streak_settings(2,22)#>>'{settings,streak}','true','old client save preserves streak choice');
select is(pg_temp.streak_settings(3,23,'{"streak":false}')#>>'{settings,streak}','false','independent opt-out');
select is((select count(*)::int from private.streak_push_window_v1('eb140000-0000-4000-8000-000000000001','streak_10h','2026-11-15T14:05Z')),0,'opt-out suppresses future windows');
reset role;
select * from finish();
rollback;
