from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260729160000_coach_english_prompt_v2.sql"
)


def _sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def _function_sql(sql: str, qualified_name: str) -> str:
    start = sql.index(f"create or replace function {qualified_name}(")
    end = sql.index("\n$$;", start) + len("\n$$;")
    return sql[start:end]


def test_prompt_v2_is_additive_and_keeps_v1_rows_valid() -> None:
    sql = _sql()

    assert "contract_version = 'coach-request-v3'" in sql
    assert "'free-coach-agent-prompt-v1'," in sql
    assert "'free-coach-agent-prompt-v2'" in sql
    assert "context_version = 'personal-snapshot-v1'" in sql
    assert "update public.coach_requests\nset prompt_version" not in sql
    assert "delete from public.coach_requests" not in sql


def test_response_validator_accepts_only_prompt_v1_or_v2() -> None:
    sql = _sql()
    validator = _function_sql(sql, "private.coach_response_is_valid_v2")
    wrapper = _function_sql(sql, "private.coach_response_is_valid_v1")

    assert (
        "rename to coach_response_is_valid_before_prompt_v2"
        in sql
    )
    assert "prompt_version not in (" in validator
    assert "'free-coach-agent-prompt-v1'" in validator
    assert "'free-coach-agent-prompt-v2'" in validator
    assert "jsonb_set(" in validator
    assert "private.coach_response_is_valid_before_prompt_v2(" in validator
    assert "private.coach_response_is_valid_v2(" in wrapper
    assert "private.coach_response_is_valid_before_free_agent(" in wrapper
    assert "when others then" in validator


def test_v4_claim_updates_only_a_new_pending_v1_claim() -> None:
    claim = _function_sql(_sql(), "public.claim_coach_request_v4")

    assert "security definer" in claim
    assert "set search_path = public, pg_temp" in claim
    assert "result := public.claim_coach_request_v3(" in claim
    assert "if result ->> 'state' = 'pending' then" in claim
    assert "set prompt_version = 'free-coach-agent-prompt-v2'" in claim
    assert "prompt_version = 'free-coach-agent-prompt-v1'" in claim
    assert "context_version = 'personal-snapshot-v1'" in claim
    assert "state = 'pending'" in claim
    assert "Coach V4 prompt transition failed" in claim


def test_v4_and_both_response_validators_are_service_role_only() -> None:
    compact = " ".join(_sql().split())
    for function in [
        "private.coach_response_is_valid_before_prompt_v2",
        "private.coach_response_is_valid_v2",
        "private.coach_response_is_valid_v1",
        "public.claim_coach_request_v4",
    ]:
        assert f"revoke all on function {function}(" in compact
        assert f"grant execute on function {function}(" in compact
    assert compact.count(") to service_role;") == 4
