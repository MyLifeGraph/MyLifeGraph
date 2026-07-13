from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "20260713213000_phase_10_coach_lock_order_guard.sql"
).read_text(encoding="utf-8")
BASE_MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "20260713200000_phase_10_controlled_coach.sql"
).read_text(encoding="utf-8")


OWNER_LOCK = (
    "perform pg_advisory_xact_lock("
    "hashtextextended(p_user_id::text, 11));"
)


def _function_body(sql: str, marker: str) -> str:
    start = sql.index(marker)
    end = sql.index("end;\n$$;", start)
    return sql[start:end]


def test_request_wrappers_take_owner_lock_before_existing_rpc_body() -> None:
    wrappers = {
        "create function public.claim_coach_request_v1(": (
            "return public.coach_claim_request_v1_locked_body("
        ),
        "create function public.complete_coach_request_v1(": (
            "return public.coach_complete_request_v1_locked_body("
        ),
        "create function public.fail_coach_request_v1(": (
            "return public.coach_fail_request_v1_locked_body("
        ),
    }

    for marker, body_call in wrappers.items():
        body = _function_body(MIGRATION, marker)
        assert body.index(OWNER_LOCK) < body.index(body_call)
        assert "security definer" in body


def test_history_delete_takes_the_same_owner_lock_before_request_row_lock() -> None:
    body = _function_body(
        BASE_MIGRATION,
        "create or replace function public.delete_coach_history_v1(",
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
    for function_name in [
        "claim_coach_request_v1",
        "complete_coach_request_v1",
        "fail_coach_request_v1",
    ]:
        revoke_start = MIGRATION.index(
            f"revoke all on function public.{function_name}("
        )
        revoke_end = MIGRATION.index(";", revoke_start)
        revoke = MIGRATION[revoke_start:revoke_end]
        assert "from public, anon, authenticated, service_role" in revoke

        grant_start = MIGRATION.index(
            f"grant execute on function public.{function_name}("
        )
        grant_end = MIGRATION.index(";", grant_start)
        grant = MIGRATION[grant_start:grant_end]
        assert ") to service_role" in grant
