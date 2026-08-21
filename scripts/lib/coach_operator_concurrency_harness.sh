#!/usr/bin/env bash

# Real multi-session proof for the operator-funded Coach budget and replay
# locks. It accepts only the already-created Recommendation-retirement RAM-only
# target and leaves no fixture or aggregate row behind.

run_coach_operator_concurrency_harness() (
  set -euo pipefail

  local container_name="$1"
  local database_name="$2"
  local log_root="$3"
  local variant="${4:-default}"
  local expected_container_pattern='^mylifegraph-recommendation-retirement-test-[0-9]+$'
  local expected_label='mylifegraph-recommendation-retirement-test'
  local label
  local index
  local status
  local successes=0
  local limited=0
  local -a pids=()
  local -a labels=()

  if [[ "$variant" == 'pg15' ]]; then
    expected_container_pattern='^mylifegraph-recommendation-retirement-pg15-[0-9]+$'
    expected_label='mylifegraph-recommendation-retirement-pg15'
  elif [[ "$variant" == 'pg17' ]]; then
    expected_container_pattern='^mylifegraph-recommendation-retirement-pg17-[0-9]+$'
    expected_label='mylifegraph-recommendation-retirement-pg17'
  elif [[ "$variant" != 'default' ]]; then
    printf '%s\n' 'Coach concurrency harness refused an unexpected variant.' >&2
    return 2
  fi
  [[ "$container_name" =~ $expected_container_pattern ]] || {
    printf '%s\n' 'Coach concurrency harness refused an unexpected container.' >&2
    return 2
  }
  [[ "$database_name" == 'mylifegraph_recommendation_retirement_test' ]] || {
    printf '%s\n' 'Coach concurrency harness refused an unexpected database.' >&2
    return 2
  }
  label="$(docker inspect --format '{{ index .Config.Labels "com.mylifegraph.owned" }}' "$container_name")"
  [[ "$label" == "$expected_label" ]] || {
    printf '%s\n' 'Coach concurrency harness ownership label is invalid.' >&2
    return 2
  }
  mkdir -m 0700 "$log_root"

  docker exec -i "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
begin;
do $$
declare
  item int;
  owner_id uuid;
  request_id uuid;
  result jsonb;
begin
  for item in 1..16 loop
    owner_id := ('ea000000-0000-4000-8000-' || lpad(item::text, 12, '0'))::uuid;
    request_id := ('ea100000-0000-4000-8000-' || lpad(item::text, 12, '0'))::uuid;
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) values (
      owner_id, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      'coach-concurrency-' || item || '@example.test',
      extensions.crypt('test-password', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{}', now(), now()
    );
    result := public.claim_coach_request_v8(
      owner_id, 'coach-request-v4', request_id, repeat('a', 64),
      date '2099-01-01', 'operator_codex_pilot',
      'operator_subscription_pilot', 'gpt-5.5', 'explicit',
      timestamptz '2099-01-01 00:00:00+00' + make_interval(secs => item),
      timestamptz '2099-01-01 00:04:00+00' + make_interval(secs => item),
      5, true
    );
    if result ->> 'state' is distinct from 'pending' then
      raise exception 'Global-budget fixture claim did not become pending.';
    end if;
  end loop;
end;
$$;
commit;
SQL

  for index in $(seq 1 16); do
    local owner_id
    local request_id
    local dispatch_id
    local reservation_id
    owner_id="$(printf 'ea000000-0000-4000-8000-%012d' "$index")"
    request_id="$(printf 'ea100000-0000-4000-8000-%012d' "$index")"
    dispatch_id="$(printf 'ea200000-0000-4000-8000-%012d' "$index")"
    reservation_id="$(printf 'ea300000-0000-4000-8000-%012d' "$index")"
    docker exec "$container_name" psql \
      -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
      -c "set role service_role; set statement_timeout='10s'; select public.record_coach_operator_dispatch_v1('$dispatch_id','$request_id','$owner_id','$reservation_id',timestamptz '2099-01-01 00:01:00+00',15);" \
      >"$log_root/global-$index.log" 2>&1 &
    pids+=("$!")
    labels+=("global-$index")
  done
  set +e
  for index in "${!pids[@]}"; do
    wait "${pids[$index]}"
    status=$?
    if [[ "$status" -eq 0 ]]; then
      successes=$((successes + 1))
    elif grep -Fq 'Coach operator global limit reached' \
      "$log_root/${labels[$index]}.log"; then
      limited=$((limited + 1))
    else
      sed -E 's/postgresql:\/\/[^[:space:]]+/postgresql:\/\/<redacted>/g' \
        "$log_root/${labels[$index]}.log" >&2
      return 1
    fi
  done
  set -e
  [[ "$successes" -eq 15 && "$limited" -eq 1 ]] || {
    printf 'Coach global concurrency mismatch: success=%s limited=%s\n' \
      "$successes" "$limited" >&2
    return 1
  }
  [[ "$(docker exec "$container_name" psql -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 -c "select concat_ws('|',(select dispatch_count from public.coach_operator_daily_budgets where utc_date=date '2099-01-01'),(select count(*) from public.coach_operator_dispatches where utc_date=date '2099-01-01'))")" == '15|15' ]] || {
    printf '%s\n' 'Coach global concurrent budget postcondition failed.' >&2
    return 1
  }

  docker exec -i "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ee000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'coach-owner-race@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
SQL
  successes=0
  limited=0
  pids=()
  labels=()
  for index in $(seq 1 6); do
    local request_id
    request_id="$(printf 'ee100000-0000-4000-8000-%012d' "$index")"
    docker exec "$container_name" psql \
      -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
      -c "begin; set local role service_role; set local statement_timeout='10s'; select public.claim_coach_request_v8('ee000000-0000-4000-8000-000000000001','coach-request-v4','$request_id',repeat('e',64),date '2099-01-04','operator_codex_pilot','operator_subscription_pilot','gpt-5.5','explicit',timestamptz '2099-01-04 00:00:00+00' + make_interval(secs=>$index),timestamptz '2099-01-04 00:04:00+00' + make_interval(secs=>$index),5,true); select public.fail_coach_request_v1('ee000000-0000-4000-8000-000000000001','$request_id',jsonb_build_object('code','provider_unavailable','message','Concurrent owner quota fixture.','retryable',true),jsonb_build_object('provider_called',false,'prompt_bytes',0,'context_bytes',0,'reply_codepoints',0),timestamptz '2099-01-04 00:05:00+00' + make_interval(secs=>$index)); commit;" \
      >"$log_root/owner-$index.log" 2>&1 &
    pids+=("$!")
    labels+=("owner-$index")
  done
  set +e
  for index in "${!pids[@]}"; do
    wait "${pids[$index]}"
    status=$?
    if [[ "$status" -eq 0 ]]; then
      successes=$((successes + 1))
    elif grep -Fq 'Coach daily request limit reached' \
      "$log_root/${labels[$index]}.log"; then
      limited=$((limited + 1))
    else
      sed -n '1,100p' "$log_root/${labels[$index]}.log" >&2
      return 1
    fi
  done
  set -e
  [[ "$successes" -eq 5 && "$limited" -eq 1 ]] || {
    printf 'Coach owner concurrency mismatch: success=%s limited=%s\n' \
      "$successes" "$limited" >&2
    return 1
  }
  [[ "$(docker exec "$container_name" psql -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 -c "select concat_ws('|',(select count(*) from public.coach_requests where user_id='ee000000-0000-4000-8000-000000000001' and operator_budget_utc_date=date '2099-01-04'),(select count(*) from public.coach_requests where user_id='ee000000-0000-4000-8000-000000000001' and state='failed'))")" == '5|5' ]] || {
    printf '%s\n' 'Coach per-owner concurrent budget postcondition failed.' >&2
    return 1
  }

  docker exec -i "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
begin;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'eb000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'coach-replay@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
select public.claim_coach_request_v8(
  'eb000000-0000-4000-8000-000000000001', 'coach-request-v4',
  'eb100000-0000-4000-8000-000000000001', repeat('b',64), date '2099-01-02',
  'operator_codex_pilot','operator_subscription_pilot','gpt-5.5','explicit',
  timestamptz '2099-01-02 00:00:00+00',
  timestamptz '2099-01-02 00:04:00+00',5,true
);
commit;
SQL
  pids=()
  for index in $(seq 1 8); do
    docker exec "$container_name" psql \
      -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
      -c "set role service_role; set statement_timeout='10s'; select public.record_coach_operator_dispatch_v1('eb200000-0000-4000-8000-000000000001','eb100000-0000-4000-8000-000000000001','eb000000-0000-4000-8000-000000000001','eb300000-0000-4000-8000-000000000001',timestamptz '2099-01-02 00:01:00+00',15);" \
      >"$log_root/replay-$index.log" 2>&1 &
    pids+=("$!")
  done
  for index in "${!pids[@]}"; do
    wait "${pids[$index]}" || {
      sed -E 's/postgresql:\/\/[^[:space:]]+/postgresql:\/\/<redacted>/g' \
        "$log_root/replay-$((index + 1)).log" >&2
      return 1
    }
  done
  [[ "$(docker exec "$container_name" psql -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 -c "select concat_ws('|',(select dispatch_count from public.coach_operator_daily_budgets where utc_date=date '2099-01-02'),(select count(*) from public.coach_operator_dispatches where request_id='eb100000-0000-4000-8000-000000000001'))")" == '1|1' ]] || {
    printf '%s\n' 'Coach same-request replay incremented budget more than once.' >&2
    return 1
  }

  docker exec -i "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
begin;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ec900000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'coach-cleanup-race@example.test',
  extensions.crypt('test-password', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
select public.claim_coach_request_v8(
  'ec900000-0000-4000-8000-000000000001','coach-request-v4',
  'ec910000-0000-4000-8000-000000000001',repeat('c',64),date '2099-01-03',
  'operator_codex_pilot','operator_subscription_pilot','gpt-5.5','explicit',
  timestamptz '2099-01-03 00:00:00+00',
  timestamptz '2099-01-03 00:01:00+00',5,true
);
select public.record_coach_operator_dispatch_v1(
  'ec920000-0000-4000-8000-000000000001',
  'ec910000-0000-4000-8000-000000000001',
  'ec900000-0000-4000-8000-000000000001',
  'ec930000-0000-4000-8000-000000000001',
  timestamptz '2099-01-03 00:00:30+00',15
);
commit;
SQL
  docker exec "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    -c "set role service_role; set statement_timeout='10s'; select public.reconcile_expired_coach_operator_dispatches_v1(timestamptz '2099-01-03 00:02:00+00');" \
    >"$log_root/reconcile.log" 2>&1 &
  local reconcile_pid="$!"
  docker exec "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 \
    -c "set role service_role; set statement_timeout='10s'; select public.prepare_account_deletion_v2('ec900000-0000-4000-8000-000000000001','ec940000-0000-4000-8000-000000000001','DELETE'); select public.mark_account_deletion_appending_v2('ec900000-0000-4000-8000-000000000001','ec940000-0000-4000-8000-000000000001'); with intent as (select ((public.get_account_deletion_intent_v2('ec900000-0000-4000-8000-000000000001')->'intent'->>'accepted_at')::timestamptz) as accepted_at) select public.accept_account_deletion_journal_v2('ec900000-0000-4000-8000-000000000001','ec940000-0000-4000-8000-000000000001',intent.accepted_at,format('deletions/v2/%s/ec940000-0000-4000-8000-000000000001/%s.json',to_char(intent.accepted_at at time zone 'UTC','YYYY/MM'),repeat('d',64)),repeat('d',64),intent.accepted_at) from intent; select public.complete_account_deletion_v2('ec900000-0000-4000-8000-000000000001','ec940000-0000-4000-8000-000000000001','DELETE',clock_timestamp());" \
    >"$log_root/delete.log" 2>&1 &
  local delete_pid="$!"
  wait "$reconcile_pid" || {
    sed -n '1,80p' "$log_root/reconcile.log" >&2
    return 1
  }
  wait "$delete_pid" || {
    sed -n '1,80p' "$log_root/delete.log" >&2
    return 1
  }
  [[ "$(docker exec "$container_name" psql -U postgres -d "$database_name" -X -At -v ON_ERROR_STOP=1 -c "select concat_ws('|',(select count(*) from auth.users where id='ec900000-0000-4000-8000-000000000001'),(select count(*) from public.coach_operator_dispatches where request_id='ec910000-0000-4000-8000-000000000001'),(select dispatch_count from public.coach_operator_daily_budgets where utc_date=date '2099-01-03'))")" == '0|0|1' ]] || {
    printf '%s\n' 'Coach reconcile/delete concurrency postcondition failed.' >&2
    return 1
  }

  docker exec -i "$container_name" psql \
    -U postgres -d "$database_name" -X -v ON_ERROR_STOP=1 <<'SQL'
delete from auth.users where email like 'coach-concurrency-%@example.test';
delete from auth.users where id = 'ee000000-0000-4000-8000-000000000001';
delete from auth.users where id = 'eb000000-0000-4000-8000-000000000001';
delete from public.account_deletion_intents
where deletion_id = 'ec940000-0000-4000-8000-000000000001';
delete from public.coach_operator_daily_budgets
where utc_date between date '2099-01-01' and date '2099-01-04';
SQL
  printf '%s\n' 'Real Coach operator concurrency harness passed.'
)
