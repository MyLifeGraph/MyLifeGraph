import re
from pathlib import Path

import app.services.coach_snapshot as coach_snapshot_module
from app.owner_data_catalog import (
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_TABLES,
    COACH_SNAPSHOT_DESCRIPTIONS,
    COACH_SNAPSHOT_TABLES,
    OWNER_DATA_CATALOG,
    OwnerDataExportPolicy,
    OwnerDataSnapshotPolicy,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
CREATE_PUBLIC_TABLE = re.compile(
    r"\bcreate\s+table(?:\s+if\s+not\s+exists)?\s+public\.([a-z_]+)",
    flags=re.IGNORECASE,
)


def test_every_repo_owned_public_table_has_one_deliberate_policy() -> None:
    migration_tables = {
        match.group(1)
        for path in (REPOSITORY_ROOT / "supabase" / "migrations").glob("*.sql")
        for match in CREATE_PUBLIC_TABLE.finditer(path.read_text())
    }
    catalog_names = [entry.name for entry in OWNER_DATA_CATALOG]

    assert len(catalog_names) == len(set(catalog_names)) == 48
    assert set(catalog_names) == migration_tables
    assert all(
        type(entry.export_policy) is OwnerDataExportPolicy
        for entry in OWNER_DATA_CATALOG
    )
    assert all(
        type(entry.snapshot_policy) is OwnerDataSnapshotPolicy
        for entry in OWNER_DATA_CATALOG
    )


def test_export_and_snapshot_are_independent_catalog_projections() -> None:
    entries = {entry.name: entry for entry in OWNER_DATA_CATALOG}
    export_names = tuple(table.name for table in ACCOUNT_EXPORT_TABLES)
    snapshot_names = tuple(table.name for table in COACH_SNAPSHOT_TABLES)

    assert len(export_names) == 41
    assert len(snapshot_names) == 37
    assert tuple(ACCOUNT_EXPORT_OMITTED_TABLES) == (
        "daily_capture_request_identities",
        "account_setting_request_identities",
        "calendar_request_identities",
        "notification_action_requests",
        "deadline_plan_request_identities",
        "planner_request_identities",
        "learning_request_identities",
    )
    assert {
        "coach_requests",
        "coach_usage_events",
        "coach_memory_selections",
    } <= set(export_names) - set(snapshot_names)
    assert all(
        entries[name].snapshot_policy is OwnerDataSnapshotPolicy.OMIT
        for name in ACCOUNT_EXPORT_OMITTED_TABLES
    )
    assert set(COACH_SNAPSHOT_DESCRIPTIONS) == set(snapshot_names)


def test_coach_snapshot_does_not_import_account_service_implementation() -> None:
    source = Path(coach_snapshot_module.__file__).read_text()

    assert "app.services.account_service" not in source
    assert "_lossless_json_text" not in source
