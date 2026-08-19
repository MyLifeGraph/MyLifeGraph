from tests.migration_source import load_migration


MIGRATION = load_migration("20260819185740_pilot_participation_v1.sql")


def test_participation_persists_only_version_and_backend_time() -> None:
    assert "pilot_participation_notice_version text" in MIGRATION
    assert "pilot_participation_accepted_at timestamptz" in MIGRATION
    assert "date_of_birth" not in MIGRATION
    assert "birth_date" not in MIGRATION
    assert "user_metadata" not in MIGRATION
    assert "profiles_pilot_participation_pair_check" in MIGRATION


def test_participation_fields_and_command_are_backend_owned() -> None:
    assert "revoke update (" in MIGRATION
    assert "from anon, authenticated" in MIGRATION
    assert "current_user in ('anon', 'authenticated')" in MIGRATION
    assert "auth.role()" not in MIGRATION
    assert "for update" in MIGRATION
    assert "security definer" in MIGRATION
    assert "accept_pilot_participation_v1(uuid, text)" in MIGRATION
    assert "from public, anon, authenticated" in MIGRATION
    assert "to service_role" in MIGRATION
