-- Isolated fixtures; never mutates retained application data after rollback.
begin;
select no_plan();

insert into auth.users(id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('ea140001-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'health-vitals-test@example.test', '{"provider":"email"}', '{}', now(), now());
update public.profiles set onboarding_completed_at = now(), timezone = 'Europe/Berlin'
where id = 'ea140001-0000-4000-8000-000000000001';
insert into public.behavioral_events(user_id, event_type, value, occurred_at, source)
values ('ea140001-0000-4000-8000-000000000001', 'manual_fixture', 8, now(), 'app');

create function pg_temp.vitals_command(operation text, revision bigint, request_number int,
  day_extra jsonb default '{}', overrides jsonb default '{}')
returns jsonb language sql as $$
  select public.apply_health_connect_v1('ea140001-0000-4000-8000-000000000001', jsonb_build_object(
    'contract_version', 'health-connect-v1',
    'request_id', 'ea140001-0000-4000-8000-' || lpad(request_number::text, 12, '0'),
    'expected_revision', revision, 'command', operation,
    'device_id', case when operation in ('connect', 'sync') then 'ea140001-0000-4000-8000-000000000002' end,
    'consent_version', case when operation = 'connect' then 'health-connect-cloud-consent-v1' end,
    'vitals_consent_version', case when operation = 'enable_vitals' then 'health-vitals-cloud-consent-v1' end,
    'timezone', case when operation = 'sync' then 'Europe/Berlin' end,
    'captured_at', case when operation = 'sync' then now() end,
    'days', case when operation = 'sync' then (
      select jsonb_agg(jsonb_build_object('date', (now() at time zone 'Europe/Berlin')::date - day_offset,
        'steps', 1000, 'sleep_minutes', 0, 'steps_sources', jsonb_build_array('com.example.watch'),
        'sleep_sources', jsonb_build_array('com.example.watch')) || day_extra order by day_offset)
      from generate_series(0, 6) day_offset
    ) else '[]'::jsonb end
  ) || overrides);
$$;
grant execute on function pg_temp.vitals_command(text, bigint, int, jsonb, jsonb) to service_role;

select ok(not has_function_privilege('authenticated', 'public.apply_health_connect_v1(uuid,jsonb)', 'execute'), 'authenticated cannot call privileged sync');
select ok(not has_function_privilege('anon', 'public.apply_health_connect_v1(uuid,jsonb)', 'execute'), 'anonymous cannot call privileged sync');
select ok(has_function_privilege('service_role', 'public.apply_health_connect_v1(uuid,jsonb)', 'execute'), 'service grant survives extension');
set local role service_role;

select is(pg_temp.vitals_command('connect', 0, 11) #>> '{health_connect_settings,revision}', '1', 'base connect');
select throws_ok($$select pg_temp.vitals_command('enable_vitals', 1, 12, '{}', '{"vitals_consent_version":null}')$$,
 '22023', null, 'base sharing is not extra vitals consent');
select is(pg_temp.vitals_command('enable_vitals', 1, 13) #>> '{health_connect_settings,revision}', '2', 'separate consent');
select is(pg_temp.vitals_command('sync', 2, 14, '{"heart_rate_read":true,"heart_rate":70,"resting_heart_rate_read":true,"resting_heart_rate":58}') #>> '{health_connect_settings,revision}', '3', 'both daily vital averages saved');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and source = 'health_connect'), 28, 'four metrics across seven days');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and event_type in ('health_connect_heart_rate', 'health_connect_resting_heart_rate') and metadata->>'consent_version' = 'health-vitals-cloud-consent-v1' and metadata->>'aggregation' = 'health_connect_daily_average'), 14, 'vitals provenance uses independent consent and average');
select is(pg_temp.vitals_command('sync', 2, 14, '{"heart_rate_read":true,"heart_rate":70,"resting_heart_rate_read":true,"resting_heart_rate":58}') #>> '{health_connect_settings,revision}', '3', 'exact replay does not advance');
select is(pg_temp.vitals_command('sync', 3, 15) #>> '{health_connect_settings,revision}', '4', 'legacy omitted fields remain accepted');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and event_type in ('health_connect_heart_rate', 'health_connect_resting_heart_rate')), 14, 'old client does not clear vitals');
select is(pg_temp.vitals_command('sync', 4, 16, '{"heart_rate_read":false,"heart_rate":null,"resting_heart_rate_read":false}') #>> '{health_connect_settings,revision}', '5', 'permission-denied read accepted');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and event_type in ('health_connect_heart_rate', 'health_connect_resting_heart_rate')), 14, 'unread is not empty');
select is(pg_temp.vitals_command('sync', 5, 17, '{"heart_rate_read":true,"heart_rate":null,"resting_heart_rate_read":false}') #>> '{health_connect_settings,revision}', '6', 'authoritative empty HR');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and event_type = 'health_connect_heart_rate'), 0, 'only empty HR cleared');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and event_type = 'health_connect_resting_heart_rate'), 7, 'denied resting HR retained');
select is(pg_temp.vitals_command('disable_vitals', 6, 18) #>> '{health_connect_settings,revision}', '7', 'revocation advances revision');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and source = 'health_connect'), 14, 'revocation leaves only sleep and steps');
select is((select count(*)::int from public.behavioral_events where user_id = 'ea140001-0000-4000-8000-000000000001' and source = 'app'), 1, 'manual entries untouched');
select throws_ok($$select pg_temp.vitals_command('sync', 7, 19, '{"heart_rate_read":true,"heart_rate":70}')$$,
 '22023', null, 'revoked uploads fail atomically');
select throws_ok($$select pg_temp.vitals_command('enable_vitals', 1, 13)$$, 'PT409', null, 'stale consent cannot resurrect sharing');
select is(pg_temp.vitals_command('enable_vitals', 7, 20) #>> '{health_connect_settings,revision}', '8', 'explicit fresh consent');
select is(pg_temp.vitals_command('connect', 8, 21, '{}', '{"device_id":"ea140001-0000-4000-8000-000000000099"}') #>> '{health_connect_settings,revision}', '9', 'new device connects');
select ok(not coalesce((select (health_connect_settings->>'vitals_enabled')::boolean from public.profiles where id = 'ea140001-0000-4000-8000-000000000001'), false), 'new device never inherits extra consent');

reset role;
select * from finish();
rollback;
