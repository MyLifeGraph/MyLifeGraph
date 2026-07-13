from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "20260713200000_phase_10_controlled_coach.sql"
)


def _migration_sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def _function_sql(sql: str, function_name: str) -> str:
    start = sql.index(f"create or replace function public.{function_name}(")
    end = sql.index("\n$$;", start) + len("\n$$;")
    return sql[start:end]


def test_coach_tables_are_bounded_owner_linked_and_retry_safe() -> None:
    sql = _migration_sql()

    assert "create table public.coach_requests" in sql
    assert "constraint coach_requests_request_id_key unique (request_id)" in sql
    assert (
        "constraint coach_requests_request_owner_key unique (request_id, user_id)"
        in sql
    )
    assert "state in ('pending', 'completed', 'failed', 'deleted')" in sql
    assert "create unique index coach_requests_one_pending_per_user_idx" in sql
    assert "where state = 'pending'" in sql
    assert (
        "private.coach_response_is_valid_v1(response, request_id, used_context)"
        in sql
    )
    assert "octet_length(p_value::text) > 32768" in sql
    assert "char_length(p_value ->> 'reply') not between 1 and 4000" in sql

    assert "create table public.coach_usage_events" in sql
    assert "constraint coach_usage_events_request_key unique (request_id)" in sql
    assert "outcome in ('completed', 'failed', 'safety_redirect')" in sql
    assert "private.coach_usage_is_valid_v1(counters)" in sql
    assert "grant select, insert on table public.coach_usage_events" in sql
    assert "grant select, insert, update" not in sql.split(
        "on table public.coach_usage_events",
        maxsplit=1,
    )[0].split("revoke all on table public.coach_usage_events", maxsplit=1)[-1]

    assert "create table public.coach_memory_selections" in sql
    assert "primary key (user_id, memory_id)" in sql
    assert "references public.memory_entries (id, user_id)" in sql
    assert "on delete cascade" in sql


def test_existing_coach_rows_remain_legacy_and_new_turns_are_exact_pairs() -> None:
    sql = _migration_sql()

    assert "add column request_id uuid" in sql
    assert "add column contract_version text" in sql
    assert "request_id is null\n      and contract_version is null" in sql
    assert "contract_version = 'coach-message-v1'" in sql
    assert "role in ('user', 'assistant')" in sql
    assert "metadata = '{}'::jsonb" in sql
    assert "constraint coach_messages_request_role_key unique (request_id, role)" in sql
    assert "references public.coach_requests (request_id, user_id)" in sql

    complete = _function_sql(sql, "complete_coach_request_v1")
    assert "extensions.digest(convert_to(p_user_message, 'UTF8'), 'sha256')" in complete
    assert "insert into public.coach_messages" in complete
    assert "'coach-message-v1',\n    'user'" in complete
    assert "'coach-message-v1',\n    'assistant'" in complete
    assert "insert into public.coach_usage_events" in complete
    assert "set state = 'completed'" in complete
    assert "target.response is distinct from p_response" in complete
    assert "linked_message_count <> 2" in complete


def test_claim_is_message_free_locked_replay_safe_and_budgeted() -> None:
    claim = _function_sql(_migration_sql(), "claim_coach_request_v1")
    signature = claim.split(")\nreturns jsonb", maxsplit=1)[0]

    assert "p_message_fingerprint text" in signature
    assert "p_message text" not in signature
    assert "hashtextextended(p_request_id::text, 10)" in claim
    assert "hashtextextended(p_user_id::text, 11)" in claim
    assert "using errcode = 'PT409'" in claim
    assert "using errcode = 'PT429'" in claim
    assert "p_daily_limit not between 1 and 100" in claim
    assert "message_fingerprint," in claim
    assert "insert into public.coach_messages" not in claim
    assert "existing.message_fingerprint <> p_message_fingerprint" in claim
    assert "existing.context_scope <> p_context_scope" in claim
    assert "existing.local_date <> p_local_date" not in claim
    assert "existing.provider <> p_provider" not in claim
    assert "existing.model_requested is distinct from p_model_requested" not in claim
    assert "existing.prompt_version <> p_prompt_version" not in claim
    assert "existing.context_version <> p_context_version" not in claim
    assert "existing.state = 'completed'" in claim
    assert "existing.state = 'failed'" in claim
    assert "'state', 'in_progress'" in claim
    assert "existing.lease_expires_at <= p_claimed_at" in claim


def test_terminal_rpcs_are_atomic_idempotent_and_sanitized() -> None:
    sql = _migration_sql()
    complete = _function_sql(sql, "complete_coach_request_v1")
    fail = _function_sql(sql, "fail_coach_request_v1")

    assert "p_response jsonb" in complete
    assert "p_used_context jsonb" in complete
    assert "p_usage jsonb" in complete
    assert "p_value -> 'used_context' is distinct from p_used_context" in sql
    assert "usage_outcome := case" in complete
    assert "then 'safety_redirect'" in complete
    assert "return jsonb_build_object(\n      'state', 'completed'" in complete

    assert "private.coach_error_is_valid_v1(p_error)" in fail
    assert "private.coach_usage_is_valid_v1(p_usage)" in fail
    assert "usage_event.counters is distinct from p_usage" in fail
    assert "set state = 'failed'" in fail
    assert "insert into public.coach_usage_events" in fail
    assert "return jsonb_build_object(\n      'state', 'failed'" in fail

    for code in [
        "provider_disabled",
        "provider_unavailable",
        "missing_cli",
        "not_logged_in",
        "unavailable_model",
        "account_limit",
        "timeout",
        "invalid_output",
        "unsafe_provider_event",
        "provider_failure",
        "context_failure",
        "tool_free_unavailable",
        "interrupted",
    ]:
        assert f"'{code}'" in sql


def test_memory_selection_is_service_only_bounded_and_excludes_preferences() -> None:
    sql = _migration_sql()
    selection = _function_sql(sql, "set_coach_memory_selection_v1")

    assert "p_selected boolean" in selection
    assert "hashtextextended(p_user_id::text, 12)" in selection
    assert "and type <> 'preference'" in selection
    assert "if selected_count >= 8" in selection
    assert "'state', 'limit_reached'" in selection
    assert "insert into public.coach_memory_selections" in selection
    assert "delete from public.coach_memory_selections" in selection
    assert "update public.memory_entries" not in selection
    assert "insert into public.memory_entries" not in selection

    assert (
        "grant select on table public.coach_memory_selections to authenticated"
        in sql
    )
    assert "grant select, insert, delete on table public.coach_memory_selections" in sql
    assert "to service_role" in sql


def test_history_delete_tombstones_content_but_retains_usage_ledger() -> None:
    delete = _function_sql(_migration_sql(), "delete_coach_history_v1")

    assert "state = 'pending'" in delete
    assert "using errcode = 'PT409'" in delete
    assert "delete from public.coach_messages" in delete
    assert "set state = 'deleted'" in delete
    assert "message_fingerprint = null" in delete
    assert "response = null" in delete
    assert "used_context = '[]'::jsonb" in delete
    assert "error = null" in delete
    assert "delete from public.coach_usage_events" not in delete
    assert "'deleted_count', deleted_count" in delete


def test_coach_rls_removes_authenticated_mutation_and_rpcs_are_service_only() -> None:
    sql = _migration_sql()

    assert 'drop policy if exists "coach_messages_own_or_admin_all"' in sql
    assert 'drop policy if exists "memory_entries_own_or_admin_all"' in sql
    assert "grant select on table public.coach_messages to authenticated" in sql
    assert "grant select on table public.memory_entries to authenticated" in sql
    assert "grant select, insert, delete on table public.coach_messages" in sql
    assert "grant select, insert, update, delete on table public.memory_entries" in sql
    assert "force row level security" in sql

    for function_name in [
        "claim_coach_request_v1",
        "complete_coach_request_v1",
        "fail_coach_request_v1",
        "set_coach_memory_selection_v1",
        "delete_coach_history_v1",
    ]:
        function = _function_sql(sql, function_name)
        assert "security definer" in function
        assert "set search_path = public, pg_temp" in function
        assert f"revoke all on function public.{function_name}(" in sql
        assert f"grant execute on function public.{function_name}(" in sql


def test_exact_key_helper_rejects_null_and_non_object_values_before_iteration() -> None:
    sql = _migration_sql()
    start = sql.index("create or replace function private.coach_jsonb_has_exact_keys(")
    end = sql.index("\n$$;", start) + len("\n$$;")
    helper = sql[start:end]

    assert "p_value is null" in helper
    assert "jsonb_typeof(p_value) <> 'object'" in helper
    assert "return false;" in helper
    assert helper.index("jsonb_typeof(p_value) <> 'object'") < helper.index(
        "jsonb_object_keys(p_value)"
    )
    assert "when others then" in helper


def test_public_rpcs_are_defined_only_after_tables_and_rls() -> None:
    sql = _migration_sql()
    first_rpc = sql.index("create or replace function public.claim_coach_request_v1(")

    assert sql.index("create table public.coach_requests") < first_rpc
    assert sql.index("create table public.coach_usage_events") < first_rpc
    assert sql.index("create table public.coach_memory_selections") < first_rpc
    assert sql.index("force row level security") < first_rpc
