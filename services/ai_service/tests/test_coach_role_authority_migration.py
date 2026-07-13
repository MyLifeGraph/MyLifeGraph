from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260713224500_phase_10_role_authority_guard.sql"
).read_text()


def test_admin_authority_uses_only_protected_canonical_profile() -> None:
    normalized = " ".join(MIGRATION.lower().split())
    function_body = MIGRATION.split("as $$", 1)[1].split("$$;", 1)[0].lower()

    assert "from public.profiles where id = auth.uid()" in normalized
    assert 'public."user"' not in function_body
    assert "to_regclass" not in function_body
    assert "return coalesce(result, 'user')" in normalized


def test_authenticated_owner_cannot_delete_canonical_profile() -> None:
    normalized = " ".join(MIGRATION.lower().split())

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
