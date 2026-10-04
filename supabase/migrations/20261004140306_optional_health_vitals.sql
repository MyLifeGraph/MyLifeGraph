-- Additive extension: optional source-backed daily BPM, independent cloud consent.
-- No manual Capture projection changes. Preserve owner lock, CAS, replay and grants.
do $migration$
declare
  definition text := pg_get_functiondef('public.apply_health_connect_v1(uuid,jsonb)'::regprocedure);
  old text;
  new text;
  replacement text[];
begin
  -- pg_get_functiondef retains source line endings; support Windows-applied SQL.
  definition := replace(definition, E'\r\n', E'\n');
  foreach replacement slice 1 in array array[
    array['(''connect'', ''disconnect'', ''delete_data'', ''sync'')', '(''connect'', ''disconnect'', ''delete_data'', ''sync'', ''enable_vitals'', ''disable_vitals'')'],
    array[$a$  if operation = 'connect' then$a$, $b$
  if operation in ('enable_vitals', 'disable_vitals') then
    if operation = 'enable_vitals' and (state ->> 'enabled' is distinct from 'true'
       or p_request ->> 'vitals_consent_version' is distinct from 'health-vitals-cloud-consent-v1') then
      raise exception 'Separate vitals consent is required.' using errcode = '22023';
    end if;
    state := state || jsonb_build_object('vitals_enabled', operation = 'enable_vitals',
      'vitals_consent_version', case when operation = 'enable_vitals' then 'health-vitals-cloud-consent-v1' else null end);
    if operation = 'disable_vitals' then
      delete from public.behavioral_events where user_id = p_user_id and source = 'health_connect'
        and event_type in ('health_connect_heart_rate', 'health_connect_resting_heart_rate');
    end if;
  elsif operation = 'connect' then
    -- A sleep/steps reconnect must not authorize extra sharing on a new device.
    state := state - 'vitals_enabled' - 'vitals_consent_version';$b$],
    array[$a$state := state || jsonb_build_object('enabled', false, 'device_id', null)$a$, $b$state := (state - 'vitals_enabled' - 'vitals_consent_version') || jsonb_build_object('enabled', false, 'device_id', null)$b$],
    array[$a$foreach metric in array array['steps', 'sleep_minutes'] loop$a$, $b$foreach metric in array array['steps', 'sleep_minutes', 'heart_rate', 'resting_heart_rate'] loop
        if metric in ('heart_rate', 'resting_heart_rate') then
          if coalesce((day_value ->> (metric || '_read'))::boolean, false) is not true then
            continue; -- Denied/unread is not an authoritative empty result.
          end if;
          if state ->> 'vitals_enabled' is distinct from 'true'
             or state ->> 'vitals_consent_version' is distinct from 'health-vitals-cloud-consent-v1' then
            raise exception 'Vitals sharing is disabled.' using errcode = '22023';
          end if;
        end if;$b$],
    array[$a$if observed_value < 0 or observed_value::text$a$, $b$if (metric in ('heart_rate', 'resting_heart_rate') and (observed_value < 1 or observed_value > 300 or observed_value <> trunc(observed_value)))
           or observed_value < 0 or observed_value::text$b$],
    array[$a$case when metric = 'steps' then 'steps_sources' else 'sleep_sources' end$a$, $b$case when metric = 'sleep_minutes' then 'sleep_sources' else metric || '_sources' end$b$],
    array[$a$'aggregation', 'health_connect_daily_total'$a$, $b$'aggregation', case when metric in ('heart_rate', 'resting_heart_rate') then 'health_connect_daily_average' else 'health_connect_daily_total' end$b$],
    array[$a$'consent_version', 'health-connect-cloud-consent-v1'
        );$a$, $b$'consent_version', case when metric in ('heart_rate', 'resting_heart_rate') then 'health-vitals-cloud-consent-v1' else 'health-connect-cloud-consent-v1' end
        );$b$],
    array[$a$case when metric = 'steps' then 'steps' else 'minutes' end$a$, $b$case when metric = 'steps' then 'steps' when metric = 'sleep_minutes' then 'minutes' else 'bpm' end$b$]
  ] loop
    old := replace(replacement[1], E'\r\n', E'\n');
    new := replace(replacement[2], E'\r\n', E'\n');
    if position(old in definition) = 0 then
      raise exception 'Health Connect function drift: review vitals migration';
    end if;
    definition := replace(definition, old, new);
  end loop;
  execute definition;
end
$migration$;
