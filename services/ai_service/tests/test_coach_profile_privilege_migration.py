from tests.migration_source import load_migration, normalize_sql


MIGRATION = load_migration(
    "20260713223000_phase_10_profile_privilege_guard.sql",
)


def test_profile_identity_fields_are_not_owner_writable() -> None:
    normalized = normalize_sql(MIGRATION)

    assert (
        "revoke insert, update on table public.profiles from authenticated"
        in normalized
    )
    assert (
        "grant update ( display_name, timezone, onboarding_completed_at, "
        "updated_at ) on table public.profiles to authenticated"
        in normalized
    )
    assert "old.role is distinct from new.role" in normalized
    assert "old.auth_provider is distinct from new.auth_provider" in normalized
    assert "auth.role() in ('anon', 'authenticated')" in normalized
    assert "if tg_op = 'insert'" in normalized


def test_profile_guard_is_not_publicly_callable() -> None:
    normalized = normalize_sql(MIGRATION)

    assert (
        "revoke all on function private.guard_profile_privileged_fields() from public"
        in normalized
    )
    assert "before insert or update on public.profiles" in normalized
