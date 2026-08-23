from tests.migration_source import load_migration, normalize_sql


MIGRATION = load_migration(
    "20260713230000_phase_10_onboarding_eligibility_guard.sql",
)


def test_authenticated_cannot_write_onboarding_eligibility_projection() -> None:
    normalized = normalize_sql(MIGRATION)

    assert (
        "revoke update (onboarding_completed_at) on table public.profiles "
        "from authenticated"
        in normalized
    )
    assert (
        "old.onboarding_completed_at is distinct from "
        "new.onboarding_completed_at"
        in normalized
    )
    assert "auth.role() in ('anon', 'authenticated')" in normalized


def test_profile_privilege_trigger_remains_private() -> None:
    normalized = normalize_sql(MIGRATION)

    assert (
        "revoke all on function private.guard_profile_privileged_fields() "
        "from public"
        in normalized
    )
