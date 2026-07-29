from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260728160000_free_read_only_coach_agent_v1.sql"
)
LONGITUDINAL_MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260728120000_coach_longitudinal_context_v1.sql"
)


def _migration_sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def _function_sql(sql: str, qualified_name: str) -> str:
    start = sql.index(f"create or replace function {qualified_name}(")
    end = sql.index("\n$$;", start) + len("\n$$;")
    return sql[start:end]


def test_v3_is_additive_and_keeps_legacy_contracts_readable() -> None:
    sql = _migration_sql()

    for column in [
        "evidence jsonb",
        "agent_trace jsonb",
        "tool_call_count int",
        "service_tier text",
    ]:
        assert f"add column {column}" in sql

    assert (
        "'coach-request-v1', 'coach-request-v2', 'coach-request-v3'"
        in sql
    )
    assert "contract_version = 'coach-request-v1'" in sql
    assert "contract_version = 'coach-request-v2'" in sql
    assert "contract_version = 'coach-request-v3'" in sql
    assert "context_scope = 'today'" in sql
    assert "context_parameters = '{}'::jsonb" in sql
    assert "prompt_version = 'free-coach-agent-prompt-v1'" in sql
    assert "context_version = 'personal-snapshot-v1'" in sql

    response_wrapper = _function_sql(
        sql,
        "private.coach_response_is_valid_v1",
    )
    assert "p_value ->> 'contract_version' = 'coach-response-v2'" in (
        response_wrapper
    )
    assert "private.coach_response_is_valid_before_free_agent(" in (
        response_wrapper
    )
    assert (
        "alter function private.coach_response_is_valid_v1(jsonb, uuid, jsonb)\n"
        "  rename to coach_response_is_valid_before_free_agent;"
        in sql
    )


def test_evidence_and_trace_are_exact_bounded_backend_facts() -> None:
    sql = _migration_sql()
    evidence = _function_sql(
        sql,
        "private.coach_evidence_is_valid_v1",
    )
    trace = _function_sql(
        sql,
        "private.coach_agent_trace_is_valid_v1",
    )

    assert "jsonb_typeof(p_value) is distinct from 'array'" in evidence
    assert "jsonb_array_length(p_value) > 100" in evidence
    assert "octet_length(p_value::text) > 65536" in evidence
    assert (
        "array['source', 'record_count', 'period_start', 'period_end']"
        in evidence
    )
    assert "count_value not between 0 and 50000" in evidence
    assert "trunc(count_value) <> count_value" in evidence
    assert (
        "jsonb_typeof(item -> 'period_start') is distinct from\n"
        "         jsonb_typeof(item -> 'period_end')"
        in evidence
    )

    assert (
        "array['tool_call_count', 'steps', 'limitations']"
        in trace
    )
    assert "jsonb_array_length(p_value -> 'steps') > 12" in trace
    assert (
        "count_value is distinct from jsonb_array_length(p_value -> 'steps')"
        in trace
    )
    assert "count_value not between 0 and 12" in trace
    assert "(item ->> 'sequence')::numeric <> expected_sequence" in trace
    for tool in ["inspect_data", "query_data", "run_python"]:
        assert f"'{tool}'" in trace
    assert "item ->> 'status' not in ('completed', 'failed')" in trace
    assert "count_value not between 0 and 50000" in trace
    assert "duration_value not between 0 and 180000" in trace
    assert "jsonb_array_length(p_value -> 'limitations') > 20" in trace
    assert "when others then" in evidence
    assert "when others then" in trace


def test_response_v2_binds_evidence_trace_safety_and_fast_provenance() -> None:
    validator = _function_sql(
        _migration_sql(),
        "private.coach_response_is_valid_v2",
    )

    assert (
        "array[\n"
        "      'contract_version', 'request_id', 'reply', 'uncertainty', "
        "'safety',\n"
        "      'evidence', 'agent_trace', 'provenance'\n"
        "    ]"
        in validator
    )
    assert (
        "p_value ->> 'contract_version' is distinct from 'coach-response-v2'"
        in validator
    )
    assert (
        "p_value ->> 'request_id' is distinct from p_request_id::text"
        in validator
    )
    assert "char_length(p_value ->> 'reply') not between 1 and 4000" in validator
    assert "octet_length(p_value::text) > 196608" in validator
    assert "p_value -> 'evidence' is distinct from p_evidence" in validator
    assert "private.coach_agent_trace_is_valid_v1(trace)" in validator
    assert (
        "(safety ->> 'classification' = 'safety_redirect')\n"
        "       is distinct from\n"
        "       (provenance ->> 'source' = 'deterministic_safety')"
        in validator
    )

    assert (
        "provenance ->> 'model_requested' is distinct from 'gpt-5.5'"
        in validator
    )
    assert "provenance ->> 'model_reported' <> 'gpt-5.5'" in validator
    assert (
        "provenance ->> 'service_tier' is distinct from 'fast'" in validator
    )
    assert (
        "provenance ->> 'service_tier_status' is distinct from 'configured'"
        in validator
    )
    assert "(provenance ->> 'fast_mode')::boolean is not true" in validator
    assert (
        "provenance ->> 'service_tier' is distinct from 'not_applicable'"
        in validator
    )
    assert "snapshot_row_count" in validator
    assert "snapshot_bytes" in validator
    assert "count_value not between 0 and 8388608" in validator


def test_fast_mode_unavailable_is_a_persistable_explicit_failure() -> None:
    error_validator = _function_sql(
        _migration_sql(),
        "private.coach_error_is_valid_v1",
    )

    assert "'fast_mode_unavailable'" in error_validator
    assert "'silent_standard_fallback'" not in error_validator


def test_usage_error_constraint_accepts_v3_failures_and_rejects_null() -> None:
    sql = _migration_sql()
    error_validator = _function_sql(
        sql,
        "private.coach_error_is_valid_v1",
    )
    usage_error_constraint = sql.split(
        "drop constraint coach_usage_events_error_code,",
        maxsplit=1,
    )[1].split(
        "\n  );\n\nalter table public.coach_requests",
        maxsplit=1,
    )[0]
    accepted_codes = [
        "provider_disabled",
        "provider_unavailable",
        "missing_cli",
        "not_logged_in",
        "unavailable_model",
        "account_limit",
        "provider_failure",
        "timeout",
        "provider_timeout",
        "invalid_output",
        "tool_free_unavailable",
        "unsafe_provider_event",
        "context_failure",
        "interrupted",
        "snapshot_too_large",
        "tool_limit",
        "fast_mode_unavailable",
    ]

    assert "add constraint coach_usage_events_error_code check (" in (
        usage_error_constraint
    )
    assert "outcome = 'failed'" in usage_error_constraint
    assert "error_code is not null" in usage_error_constraint
    assert "outcome <> 'failed' and error_code is null" in (
        usage_error_constraint
    )
    for code in accepted_codes:
        assert f"'{code}'" in error_validator
        assert f"'{code}'" in usage_error_constraint
    assert "'silent_standard_fallback'" not in usage_error_constraint


def test_completed_rows_bind_every_duplicate_backend_field() -> None:
    sql = _migration_sql()
    constraint = sql.split(
        "add constraint coach_requests_agent_fields check (",
        maxsplit=1,
    )[1].split(
        "\n  );\n\ncreate or replace function public.claim_coach_request_v3(",
        maxsplit=1,
    )[0]

    assert "state = 'completed'" in constraint
    assert "private.coach_evidence_is_valid_v1(evidence)" in constraint
    assert "private.coach_agent_trace_is_valid_v1(agent_trace)" in constraint
    assert "tool_call_count = (agent_trace ->> 'tool_call_count')::int" in (
        constraint
    )
    assert "evidence is not distinct from used_context" in constraint
    assert "evidence is not distinct from response -> 'evidence'" in constraint
    assert "agent_trace is not distinct from response -> 'agent_trace'" in (
        constraint
    )
    assert (
        "service_tier is not distinct from\n"
        "            response #>> '{provenance,service_tier}'"
        in constraint
    )
    assert "state = 'failed'" in constraint
    assert "state = 'deleted'" in constraint
    assert "state = 'pending'" in constraint


def test_v3_claim_is_message_only_owner_first_and_fixed_to_twenty() -> None:
    claim = _function_sql(_migration_sql(), "public.claim_coach_request_v3")
    signature = claim.split(")\nreturns jsonb", maxsplit=1)[0]

    assert "p_message_fingerprint text" in signature
    assert "p_message text" not in signature
    assert "p_context_scope" not in signature
    assert "p_context_parameters" not in signature
    assert "p_daily_limit int" in signature
    assert "p_daily_limit <> 20" in claim

    owner_lock = claim.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11))",
    )
    request_lock = claim.index(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10))",
    )
    row_lock = claim.index("where request_id = p_request_id\n  for update")
    assert owner_lock < request_lock < row_lock

    replay = claim.split("if found then", maxsplit=1)[1].split(
        "if existing.state = 'pending'",
        maxsplit=1,
    )[0]
    assert "existing.contract_version <> 'coach-request-v3'" in replay
    assert "existing.message_fingerprint <> p_message_fingerprint" in replay
    for backend_comparison in [
        "existing.local_date <>",
        "existing.provider <>",
        "existing.provider_mode <>",
        "existing.model_requested is distinct from",
        "existing.model_source <>",
    ]:
        assert backend_comparison not in replay
    assert "using errcode = 'PT409'" in replay


def test_v3_claim_reuses_one_pending_and_budget_guards_without_extra_usage() -> None:
    claim = _function_sql(_migration_sql(), "public.claim_coach_request_v3")
    prior_claim = _function_sql(
        LONGITUDINAL_MIGRATION.read_text(encoding="utf-8"),
        "public.claim_coach_request_v2",
    )

    assert "result := public.claim_coach_request_v2(" in claim
    assert "'today'" in claim
    assert "'{}'::jsonb" in claim
    assert "'controlled-coach-prompt-v3'" in claim
    assert "'coach-context-v3'" in claim
    assert "set contract_version = 'coach-request-v3'" in claim
    assert "prompt_version = 'free-coach-agent-prompt-v1'" in claim
    assert "context_version = 'personal-snapshot-v1'" in claim
    assert "insert into public.coach_usage_events" not in claim

    assert "where user_id = p_user_id and state = 'pending'" in prior_claim
    assert "active_request.lease_expires_at <= p_claimed_at" in prior_claim
    assert "where user_id = p_user_id and local_date = p_local_date" in (
        prior_claim
    )
    assert "if used_count >= p_daily_limit" in prior_claim
    assert "using errcode = 'PT429'" in prior_claim


def test_v2_completion_is_owner_first_and_atomically_bound_to_v3() -> None:
    complete = _function_sql(
        _migration_sql(),
        "public.complete_coach_request_v2",
    )

    assert "target.contract_version <> 'coach-request-v3'" in complete
    assert "private.coach_evidence_is_valid_v1(p_evidence)" in complete
    assert "private.coach_agent_trace_is_valid_v1(p_agent_trace)" in complete
    assert "p_response -> 'evidence' is distinct from p_evidence" in complete
    assert "p_response -> 'agent_trace' is distinct from p_agent_trace" in (
        complete
    )
    assert (
        "p_tool_call_count <> (p_agent_trace ->> 'tool_call_count')::int"
        in complete
    )
    assert "p_tool_call_count not between 0 and 12" in complete
    assert (
        "p_service_tier is distinct from\n"
        "       p_response #>> '{provenance,service_tier}'"
        in complete
    )

    owner_lock = complete.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11))",
    )
    request_lock = complete.index(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10))",
    )
    row_lock = complete.index("where request_id = p_request_id\n  for update")
    assert owner_lock < request_lock < row_lock

    assert "target.state = 'completed'" in complete
    assert "Coach V2 completion replay differs" in complete
    assert "target.state = 'pending'" in complete
    assert "set evidence = p_evidence" in complete
    assert "agent_trace = p_agent_trace" in complete
    assert "result := public.complete_coach_request_v1(" in complete


def test_history_delete_clears_agent_content_but_retains_usage() -> None:
    sql = _migration_sql()
    delete = _function_sql(sql, "public.delete_coach_history_v1")
    prior_delete = _function_sql(
        LONGITUDINAL_MIGRATION.read_text(encoding="utf-8"),
        "public.delete_coach_history_v1",
    )

    assert (
        "rename to coach_delete_history_v1_before_free_agent;"
        in sql
    )
    assert "public.coach_delete_history_v1_before_free_agent(" in delete
    assert "set evidence = null" in delete
    assert "agent_trace = null" in delete
    assert "tool_call_count = null" in delete
    assert "service_tier = null" in delete
    assert "where user_id = p_user_id and state = 'deleted'" in delete
    assert "delete from public.coach_usage_events" not in delete
    assert "public.coach_delete_history_v1_before_longitudinal_context(" in (
        prior_delete
    )


def test_new_helpers_and_rpcs_are_service_role_only() -> None:
    sql = _migration_sql()
    compact_sql = " ".join(sql.split()).replace("( ", "(").replace(" )", ")")

    for helper in [
        "private.coach_evidence_is_valid_v1(jsonb)",
        "private.coach_agent_trace_is_valid_v1(jsonb)",
        "private.coach_response_is_valid_v2(jsonb, uuid, jsonb)",
        "private.coach_response_is_valid_v1(jsonb, uuid, jsonb)",
        "private.coach_response_is_valid_before_free_agent(jsonb, uuid, jsonb)",
    ]:
        assert f"revoke all on function {helper}" in compact_sql
        assert f"grant execute on function {helper}" in compact_sql
        assert f"grant execute on function {helper} to service_role;" in compact_sql

    for rpc in [
        "public.claim_coach_request_v3",
        "public.complete_coach_request_v2",
        "public.delete_coach_history_v1",
    ]:
        function = _function_sql(sql, rpc)
        assert "security definer" in function
        assert "set search_path = public, pg_temp" in function
        assert f"revoke all on function {rpc}(" in sql
        assert f"grant execute on function {rpc}(" in sql

    assert "alter table public.coach_requests disable row level security" not in (
        sql
    )
    assert "grant update on table public.coach_requests to authenticated" not in (
        sql
    )
