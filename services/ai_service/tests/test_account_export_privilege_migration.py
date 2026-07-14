from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION_PATH = (
    ROOT
    / "supabase/migrations/20260714110000_account_export_lifestyle_entries_grant.sql"
)
MIGRATION = " ".join(MIGRATION_PATH.read_text(encoding="utf-8").lower().split())


def test_account_export_can_read_every_v1_table_created_before_service_role_grants() -> None:
    assert (
        "grant select on table public.lifestyle_entries to service_role"
        in MIGRATION
    )
    assert "to authenticated" not in MIGRATION
    assert "to anon" not in MIGRATION
