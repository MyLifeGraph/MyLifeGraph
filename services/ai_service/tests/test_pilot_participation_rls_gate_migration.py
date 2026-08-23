from tests.migration_source import load_migration


MIGRATION = load_migration(
    "20260820150000_pilot_participation_rls_gate_v1.sql",
)


def test_participation_gate_is_private_service_role_configured_and_fail_closed() -> None:
    assert "create table private.pilot_participation_gate_v1" in MIGRATION
    assert "participation_required boolean not null default false" in MIGRATION
    assert "current_request_has_pilot_participation_v1" in MIGRATION
    assert "set row_security = off" in MIGRATION
    assert "gate_required is distinct from true" in MIGRATION
    assert "configure_pilot_participation_gate_v1(text, boolean)" in MIGRATION
    assert "get_pilot_participation_gate_v1()" in MIGRATION
    assert "from public, anon, authenticated" in MIGRATION
    assert "to service_role" in MIGRATION


def test_participation_gate_adds_restrictive_rls_to_all_product_tables() -> None:
    assert "class.relrowsecurity" in MIGRATION
    assert "as restrictive for all to authenticated" in MIGRATION
    assert "pilot_participation_required_v1" in MIGRATION
    assert "pilot_participation_profile_insert_v1" in MIGRATION
    assert "pilot_participation_profile_update_v1" in MIGRATION
    assert "pilot_participation_profile_delete_v1" in MIGRATION
    assert "for select" not in MIGRATION.split(
        "pilot_participation_profile_insert_v1",
        maxsplit=1,
    )[1]
