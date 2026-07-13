from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260713230000_phase_10_onboarding_eligibility_guard.sql"
).read_text()


def test_authenticated_cannot_write_onboarding_eligibility_projection() -> None:
    normalized = " ".join(MIGRATION.lower().split())

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
    normalized = " ".join(MIGRATION.lower().split())

    assert (
        "revoke all on function private.guard_profile_privileged_fields() "
        "from public"
        in normalized
    )
