from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION = load_migration(
    "20260713224500_phase_10_role_authority_guard.sql",
)


def test_admin_authority_uses_only_protected_canonical_profile() -> None:
    normalized = normalize_sql(MIGRATION)
    function_body = extract_function(MIGRATION, "private.current_app_role").lower()

    assert "from public.profiles where id = auth.uid()" in normalized
    assert 'public."user"' not in function_body
    assert "to_regclass" not in function_body
    assert "return coalesce(result, 'user')" in normalized


def test_authenticated_owner_cannot_delete_canonical_profile() -> None:
    normalized = normalize_sql(MIGRATION)

    assert (
        "revoke delete on table public.profiles from authenticated" in normalized
    )
    assert (
        "revoke all on function private.current_app_role() from public"
        in normalized
    )
    assert (
        "grant execute on function private.current_app_role() to anon, "
        "authenticated, service_role"
        in normalized
    )
