from tests.migration_source import (
    extract_function,
    extract_grants,
    extract_revokes,
    load_migration,
    normalize_sql,
)


MIGRATION = load_migration("20260713213000_phase_10_coach_lock_order_guard.sql")
BASE_MIGRATION = load_migration("20260713200000_phase_10_controlled_coach.sql")


OWNER_LOCK = (
    "perform pg_advisory_xact_lock("
    "hashtextextended(p_user_id::text, 11));"
)


def test_request_wrappers_take_owner_lock_before_existing_rpc_body() -> None:
    wrappers = {
        "public.claim_coach_request_v1": (
            "return public.coach_claim_request_v1_locked_body("
        ),
        "public.complete_coach_request_v1": (
            "return public.coach_complete_request_v1_locked_body("
        ),
        "public.fail_coach_request_v1": (
            "return public.coach_fail_request_v1_locked_body("
        ),
    }

    for qualified_name, body_call in wrappers.items():
        body = extract_function(MIGRATION, qualified_name)
        assert body.index(OWNER_LOCK) < body.index(body_call)
        assert "security definer" in body


def test_history_delete_takes_the_same_owner_lock_before_request_row_lock() -> None:
    body = extract_function(
        BASE_MIGRATION,
        "public.delete_coach_history_v1",
    )

    assert body.index(OWNER_LOCK) < body.index("select * into active_request")
    assert body.index(OWNER_LOCK) < body.index("for update;")
    assert "hashtextextended(p_request_id::text" not in body


def test_renamed_rpc_bodies_are_not_executable_by_application_roles() -> None:
    for body_name in [
        "coach_claim_request_v1_locked_body",
        "coach_complete_request_v1_locked_body",
        "coach_fail_request_v1_locked_body",
    ]:
        revoke_start = MIGRATION.index(
            f"revoke all on function public.{body_name}("
        )
        revoke_end = MIGRATION.index(";", revoke_start)
        revoke = MIGRATION[revoke_start:revoke_end]
        assert "from public, anon, authenticated, service_role" in revoke

    assert "grant execute on function public.coach_claim_request_v1_locked_body" not in MIGRATION
    assert "grant execute on function public.coach_complete_request_v1_locked_body" not in MIGRATION
    assert "grant execute on function public.coach_fail_request_v1_locked_body" not in MIGRATION


def test_public_wrappers_remain_service_role_only() -> None:
    revokes = tuple(normalize_sql(statement) for statement in extract_revokes(MIGRATION))
    grants = tuple(normalize_sql(statement) for statement in extract_grants(MIGRATION))
    for function_name in [
        "claim_coach_request_v1",
        "complete_coach_request_v1",
        "fail_coach_request_v1",
    ]:
        assert any(
            revoke.startswith(
                f"revoke all on function public.{function_name}(",
            )
            and "from public, anon, authenticated, service_role" in revoke
            for revoke in revokes
        )
        assert any(
            grant.startswith(
                f"grant execute on function public.{function_name}(",
            )
            and grant.endswith("to service_role;")
            for grant in grants
        )
