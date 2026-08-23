from tests.migration_source import extract_function, load_migration


MIGRATION = load_migration(
    "20260802111518_privileged_function_lint_cleanup.sql",
)


def _function_sql(name: str) -> str:
    return extract_function(MIGRATION, f"public.{name}")


def test_legacy_role_helper_is_a_closed_canonical_compatibility_wrapper() -> None:
    role_helper = _function_sql("current_app_role")

    assert "security invoker" in role_helper
    assert "set search_path = ''" in role_helper
    assert "select private.current_app_role();" in role_helper
    assert 'public."User"' not in role_helper
    assert "drop function public.current_app_role" not in MIGRATION
    assert (
        "revoke all on function public.current_app_role()\n"
        "  from public, anon, authenticated, service_role;"
    ) in MIGRATION


def test_account_delete_removes_only_the_shadowed_declaration() -> None:
    account_delete = _function_sql("delete_account_v1")

    assert "legacy_index int;" not in account_delete
    assert account_delete.count(
        "for legacy_index in 1..cardinality(legacy_table_names)"
    ) == 3
    assert "set search_path = pg_catalog, pg_temp" in account_delete
    assert (
        "revoke all on function public.delete_account_v1(uuid, text)\n"
        "  from public, anon, authenticated;"
    ) in MIGRATION
    assert (
        "grant execute on function public.delete_account_v1(uuid, text)\n"
        "  to service_role;"
    ) in MIGRATION


def test_coach_claim_deliberately_discards_failure_response() -> None:
    coach_claim = _function_sql("claim_coach_request_v3")

    assert "ignored jsonb;" not in coach_claim
    assert "ignored := public.fail_coach_request_v1(" not in coach_claim
    assert "perform public.fail_coach_request_v1(" in coach_claim
    assert "set search_path = pg_catalog, pg_temp" in coach_claim
    assert (
        "from public, anon, authenticated;\n"
        "grant execute on function public.claim_coach_request_v3("
    ) in MIGRATION
    assert ") to service_role;" in MIGRATION
