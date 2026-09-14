begin;
select no_plan();

insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('ea140000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'health-test@example.test', '{"provider":"email"}', '{}', now(), now());
update public.profiles set onboarding_completed_at = now(), timezone = 'Europe/Berlin'
where id = 'ea140000-0000-4000-8000-000000000001';
insert into public.behavioral_events(user_id, event_type, value, occurred_at, source)
values ('ea140000-0000-4000-8000-000000000001', 'manual_fixture', 8, now(), 'app');

create function pg_temp.health_command(operation text, revision bigint, request_number int, device text default 'ea140000-0000-4000-8000-000000000002')
returns jsonb language sql as $$
  select public.apply_health_connect_v1('ea140000-0000-4000-8000-000000000001', jsonb_build_object(
    'contract_version', 'health-connect-v1',
    'request_id', 'ea140000-0000-4000-8000-' || lpad(request_number::text, 12, '0'),
    'expected_revision', revision, 'command', operation,
    'device_id', case when operation in ('connect', 'sync') then device end,
    'consent_version', case when operation = 'connect' then 'health-connect-cloud-consent-v1' end,
    'timezone', case when operation = 'sync' then 'Europe/Berlin' end,
    'captured_at', case when operation = 'sync' then now() end,
    'days', case when operation = 'sync' then (
      select jsonb_agg(jsonb_build_object('date', (now() at time zone 'Europe/Berlin')::date - day_offset,
        'steps', 1000, 'sleep_minutes', 0, 'steps_sources', jsonb_build_array('com.example.watch'),
        'sleep_sources', jsonb_build_array('com.example.watch')) order by day_offset)
      from generate_series(0, 6) day_offset
    ) else '[]'::jsonb end
  ));
$$;
grant execute on function pg_temp.health_command(text, bigint, int, text) to service_role;

select ok(not has_function_privilege('authenticated', 'public.apply_health_connect_v1(uuid,jsonb)', 'execute'), 'application cannot call privileged sync');
select ok(not has_function_privilege('anon', 'public.apply_health_connect_v1(uuid,jsonb)', 'execute'), 'anonymous cannot call sync');
select is((select health_connect_settings ->> 'enabled' from public.profiles where id = 'ea140000-0000-4000-8000-000000000001'), 'false', 'sharing starts off');

set local role authenticated;
set local request.jwt.claim.sub = 'ea140000-0000-4000-8000-000000000001';
select throws_ok($$update public.profiles set health_connect_settings = '{"enabled":true,"revision":0}' where id = 'ea140000-0000-4000-8000-000000000001'$$,
 '42501', null, 'client cannot enable cloud sharing directly');
reset role;
set local role service_role;

select is(pg_temp.health_command('connect', 0, 11) #>> '{health_connect_settings,revision}', '1', 'explicit connect advances revision');
select is(pg_temp.health_command('connect', 0, 11) #>> '{health_connect_settings,revision}', '1', 'exact connect replays');
select is(pg_temp.health_command('sync', 1, 12) #>> '{health_connect_settings,revision}', '2', 'complete week saved');
select is((select count(*)::int from public.behavioral_events where source = 'health_connect' and user_id = 'ea140000-0000-4000-8000-000000000001'), 14, 'two distinct imported metrics per day');
select is(pg_temp.health_command('sync', 1, 12) #>> '{health_connect_settings,revision}', '2', 'exact sync replays without new rows');
select throws_ok($$select pg_temp.health_command('sync', 2, 13, 'ea140000-0000-4000-8000-000000000099')$$,
 '22023', null, 'a different device cannot upload');
select is(pg_temp.health_command('disconnect', 2, 14) #>> '{health_connect_settings,enabled}', 'false', 'disconnect revokes uploads');
select is((select count(*)::int from public.behavioral_events where source = 'health_connect' and user_id = 'ea140000-0000-4000-8000-000000000001'), 14, 'disconnect retains history');
select throws_ok($$select pg_temp.health_command('sync', 3, 15)$$, '22023', null, 'sync cannot bypass revoked consent');
select throws_ok($$select pg_temp.health_command('connect', 0, 11)$$, 'PT409', null, 'an older connect cannot re-enable sharing');
select is(pg_temp.health_command('delete_data', 3, 16) #>> '{health_connect_settings,revision}', '4', 'delete imports advances revision');
select is((select count(*)::int from public.behavioral_events where source = 'health_connect' and user_id = 'ea140000-0000-4000-8000-000000000001'), 0, 'imports deleted');
select is((select count(*)::int from public.behavioral_events where source = 'app' and user_id = 'ea140000-0000-4000-8000-000000000001'), 1, 'manual observations remain intact');

reset role;
select * from finish();
rollback;
