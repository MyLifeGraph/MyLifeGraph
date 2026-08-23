from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION = load_migration("20260815075711_coach_byok_provider_v1.sql")
NORMALIZED = normalize_sql(MIGRATION)
DISPATCH_MIGRATION = load_migration(
    "20260815082606_coach_byok_completion_dispatch_v1.sql"
)


def test_byok_constraints_add_providers_without_a_key_column() -> None:
    assert "'disabled', 'local_codex_oauth', 'fake', 'openai', 'gemini'" in MIGRATION
    assert "'user_supplied_key'" in MIGRATION
    assert "api_key" not in NORMALIZED
    assert "alter table public.coach_requests" in NORMALIZED
    assert "alter table public.coach_usage_events" in NORMALIZED


def test_response_v3_keeps_v1_v2_compatibility_and_strict_cloud_identity() -> None:
    validator = extract_function(MIGRATION, "private.coach_response_is_valid_v3")
    for value in [
        "coach-response-v3",
        "free-coach-agent-prompt-v5",
        "personal-snapshot-v3",
        "gpt-5.6-terra",
        "gemini-3.6-flash",
        "user_supplied_key",
    ]:
        assert value in validator
    assert "private.coach_response_is_valid_v2(" in validator
    assert "coach-response-v1" in MIGRATION
    assert "coach-response-v2" in MIGRATION


def test_v7_wraps_v6_locking_and_is_the_only_executable_claim() -> None:
    claim = extract_function(MIGRATION, "public.claim_coach_request_v7")
    assert "public.claim_coach_request_v6(" in claim
    assert "created_at = p_claimed_at" in claim
    assert "state = 'pending'" in claim
    assert "free-coach-agent-prompt-v5" in claim
    assert "grant execute on function public.claim_coach_request_v7(" in NORMALIZED
    assert "revoke all on function public.claim_coach_request_v6(" in NORMALIZED


def test_completion_dispatches_v3_and_keeps_v1_v2_paths() -> None:
    validator = extract_function(
        DISPATCH_MIGRATION,
        "private.coach_response_is_valid_v1",
    )
    assert "private.coach_response_is_valid_v3(" in validator
    assert "private.coach_response_is_valid_v2(" in validator
    assert "private.coach_response_is_valid_before_free_agent(" in validator
