from tests.migration_source import extract_grants, load_migration, normalize_sql


MIGRATION = load_migration(
    "20260714110000_account_export_lifestyle_entries_grant.sql",
)
GRANTS = tuple(normalize_sql(grant) for grant in extract_grants(MIGRATION))


def test_account_export_can_read_every_v1_table_created_before_service_role_grants() -> None:
    assert (
        "grant select on table public.lifestyle_entries to service_role;"
        in GRANTS
    )
    assert all("to authenticated" not in grant for grant in GRANTS)
    assert all("to anon" not in grant for grant in GRANTS)
