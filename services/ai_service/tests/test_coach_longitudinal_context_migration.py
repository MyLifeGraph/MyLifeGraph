from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[3]
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


def test_request_contracts_bind_versions_scopes_and_exact_parameters() -> None:
    sql = _migration_sql()
    parameters = _function_sql(
        sql,
        "private.coach_context_parameters_is_valid_v2",
    )

    assert (
        "add column context_parameters jsonb not null default '{}'::jsonb"
        in sql
    )
    assert "contract_version in ('coach-request-v1', 'coach-request-v2')" in sql
    assert "contract_version = 'coach-request-v1'" in sql
    assert "context_scope = 'today'" in sql
    assert "context_parameters = '{}'::jsonb" in sql
    assert "contract_version = 'coach-request-v2'" in sql
    assert (
        "private.coach_context_parameters_is_valid_v2(\n"
        "        context_scope,\n"
        "        context_parameters\n"
        "      )"
        in sql
    )

    assert "p_context_scope in ('today', 'review')" in parameters
    assert "p_context_parameters = '{}'::jsonb" in parameters
    assert "p_context_scope = 'patterns'" in parameters
    assert "array['horizon']" in parameters
    assert "'90_days'" in parameters
    assert "'1_year'" in parameters
    assert "'all_available'" in parameters
    assert "p_context_scope = 'focus'" in parameters
    assert "array['focus_session_id']" in parameters
    assert "focus_session_id_text::uuid" in parameters
    assert "when others then" in parameters

    assert "prompt_version = 'controlled-coach-prompt-v1'" in sql
    assert "context_version = 'coach-context-v1'" in sql
    assert "prompt_version = 'controlled-coach-prompt-v2'" in sql
    assert "context_version = 'coach-context-v2'" in sql
    assert "prompt_version = 'controlled-coach-prompt-v3'" in sql
    assert "context_version = 'coach-context-v3'" in sql


def test_longitudinal_manifest_sources_keep_the_existing_bounds() -> None:
    validator = _function_sql(
        _migration_sql(),
        "private.coach_used_context_is_valid_v1",
    )

    assert "jsonb_array_length(p_value) > 10" in validator
    assert "octet_length(p_value::text) > 32768" in validator
    for source in [
        "daily_capture",
        "focus_reflections",
        "habit_outcomes",
        "decision_feedback",
        "weekly_reviews",
        "task_lifecycle",
    ]:
        assert f"'{source}'" in validator
    assert "included_count + omitted_count <> available_count" in validator
    assert "private.coach_jsonb_has_exact_keys(" in validator


def test_response_validator_accepts_only_matching_v1_v2_or_v3_pairs() -> None:
    validator = _function_sql(
        _migration_sql(),
        "private.coach_response_is_valid_v1",
    )

    assert "prompt_version = 'controlled-coach-prompt-v1'" in validator
    assert "context_version = 'coach-context-v1'" in validator
    assert "prompt_version = 'controlled-coach-prompt-v2'" in validator
    assert "context_version = 'coach-context-v2'" in validator
    assert "prompt_version = 'controlled-coach-prompt-v3'" in validator
    assert "context_version = 'coach-context-v3'" in validator
    assert validator.count(
        "private.coach_response_is_valid_v1_only(",
    ) == 2
    assert "to_jsonb('controlled-coach-prompt-v1'::text)" in validator
    assert "to_jsonb('coach-context-v1'::text)" in validator
    assert "return false;" in validator


def test_v2_claim_is_owner_first_parameter_bound_and_replay_safe() -> None:
    claim = _function_sql(_migration_sql(), "public.claim_coach_request_v2")
    signature = claim.split(")\nreturns jsonb", maxsplit=1)[0]

    assert "p_message_fingerprint text" in signature
    assert "p_context_scope text" in signature
    assert "p_context_parameters jsonb" in signature
    assert "p_message text" not in signature
    assert "p_prompt_version text" in signature
    assert "p_context_version text" in signature
    assert "p_prompt_version is distinct from 'controlled-coach-prompt-v3'" in claim
    assert "p_context_version is distinct from 'coach-context-v3'" in claim
    assert "private.coach_context_parameters_is_valid_v2(" in claim

    owner_lock = claim.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11))",
    )
    request_lock = claim.index(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 10))",
    )
    request_row_lock = claim.index(
        "where request_id = p_request_id\n  for update",
    )
    assert owner_lock < request_lock < request_row_lock

    assert "existing.contract_version <> 'coach-request-v2'" in claim
    assert "existing.message_fingerprint <> p_message_fingerprint" in claim
    assert "existing.context_scope <> p_context_scope" in claim
    assert (
        "existing.context_parameters is distinct from p_context_parameters"
        in claim
    )
    assert "existing.local_date <> p_local_date" not in claim
    assert "existing.provider <> p_provider" not in claim
    assert "existing.model_requested is distinct from p_model_requested" not in claim
    assert "existing.prompt_version <> p_prompt_version" not in claim
    assert "existing.context_version <> p_context_version" not in claim
    assert "using errcode = 'PT409'" in claim


def test_v2_claim_preserves_budget_expiry_and_terminal_semantics() -> None:
    claim = _function_sql(_migration_sql(), "public.claim_coach_request_v2")

    assert "existing.state = 'deleted'" in claim
    assert "'code', 'history_deleted'" in claim
    assert "existing.lease_expires_at <= p_claimed_at" in claim
    assert "active_request.lease_expires_at <= p_claimed_at" in claim
    assert claim.count("insert into public.coach_usage_events") == 2
    assert "on conflict (request_id) do nothing" in claim
    assert "existing.state = 'completed'" in claim
    assert "existing.state = 'failed'" in claim
    assert "'state', 'in_progress'" in claim
    assert "where user_id = p_user_id and local_date = p_local_date" in claim
    assert "if used_count >= p_daily_limit" in claim
    assert "using errcode = 'PT429'" in claim
    assert "p_daily_limit not between 1 and 100" in claim
    assert "p_lease_expires_at > p_claimed_at + interval '5 minutes'" in claim

    assert "insert into public.coach_requests" in claim
    assert "'coach-request-v2'" in claim
    assert "p_context_scope" in claim
    assert "p_context_parameters" in claim
    assert "'controlled-coach-prompt-v3'" in claim
    assert "'coach-context-v3'" in claim
    assert "insert into public.coach_messages" not in claim


def test_v2_claim_and_helpers_are_service_role_only_without_rls_changes() -> None:
    sql = _migration_sql()
    signature = (
        "uuid, uuid, text, text, jsonb, date, text, text, text, text, text, text,\n"
        "  timestamptz, timestamptz, int"
    )

    assert (
        "revoke all on function public.claim_coach_request_v2(\n"
        f"  {signature}\n"
        ") from public, anon, authenticated, service_role;"
        in sql
    )
    assert (
        "grant execute on function public.claim_coach_request_v2(\n"
        f"  {signature}\n"
        ") to service_role;"
        in sql
    )
    assert "security definer" in _function_sql(
        sql,
        "public.claim_coach_request_v2",
    )
    assert "set search_path = public, pg_temp" in _function_sql(
        sql,
        "public.claim_coach_request_v2",
    )
    assert "alter table public.coach_requests enable row level security" not in sql
    assert "alter table public.coach_requests disable row level security" not in sql

    for helper in [
        "private.coach_context_parameters_is_valid_v2(text, jsonb)",
        "private.coach_used_context_is_valid_v1(jsonb)",
        "private.coach_response_is_valid_v1(\n  jsonb, uuid, jsonb\n)",
    ]:
        assert f"revoke all on function {helper}" in sql
        assert f"grant execute on function {helper}" in sql
        assert "to service_role;" in sql


def test_history_delete_erases_v2_context_selection_from_tombstones() -> None:
    sql = _migration_sql()
    hardened_delete = _function_sql(sql, "public.delete_coach_history_v1")

    assert (
        "alter function public.delete_coach_history_v1(uuid, timestamptz)\n"
        "  rename to coach_delete_history_v1_before_longitudinal_context;"
        in sql
    )
    assert (
        "revoke all on function "
        "public.coach_delete_history_v1_before_longitudinal_context(\n"
        "  uuid, timestamptz\n"
        ") from public, anon, authenticated, service_role;"
        in sql
    )
    assert (
        "public.coach_delete_history_v1_before_longitudinal_context("
        in hardened_delete
    )
    assert "set context_scope = 'today'" in hardened_delete
    assert "context_parameters = '{}'::jsonb" in hardened_delete
    assert "where user_id = p_user_id" in hardened_delete
    assert "and state = 'deleted'" in hardened_delete
    assert "and contract_version = 'coach-request-v2'" in hardened_delete
    assert (
        "revoke all on function public.delete_coach_history_v1("
        "uuid, timestamptz)\n"
        "  from public, anon, authenticated, service_role;"
        in sql
    )
    assert (
        "grant execute on function public.delete_coach_history_v1("
        "uuid, timestamptz)\n"
        "  to service_role;"
        in sql
    )


def test_retained_terminal_task_queries_receive_partial_indexes() -> None:
    sql = _migration_sql()

    assert (
        "create index if not exists tasks_user_completed_history_idx\n"
        "  on public.tasks (user_id, completed_at, id)\n"
        "  where status = 'done';"
        in sql
    )
    assert (
        "create index if not exists tasks_user_cancelled_history_idx\n"
        "  on public.tasks (user_id, cancelled_at, id)\n"
        "  where status = 'cancelled';"
        in sql
    )
