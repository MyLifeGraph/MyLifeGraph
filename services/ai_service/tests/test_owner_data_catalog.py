import re
from pathlib import Path

import app.services.account_service as account_service_module
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
DROP_PUBLIC_TABLE = re.compile(
    r"\bdrop\s+table(?:\s+if\s+exists)?\s+public\.([a-z_]+)",
    flags=re.IGNORECASE,
)


def test_every_repo_owned_public_table_has_one_deliberate_policy() -> None:
    migration_tables: set[str] = set()
    for path in sorted(
        (REPOSITORY_ROOT / "supabase" / "migrations").glob("*.sql"),
    ):
        source = path.read_text()
        migration_tables.update(
            match.group(1) for match in CREATE_PUBLIC_TABLE.finditer(source)
        )
        migration_tables.difference_update(
            match.group(1) for match in DROP_PUBLIC_TABLE.finditer(source)
        )
    catalog_names = [entry.name for entry in OWNER_DATA_CATALOG]

    assert len(catalog_names) == len(set(catalog_names)) == 51
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

    assert len(export_names) == 43
    assert len(snapshot_names) == 39
    assert "goals" not in export_names
    assert "goals" not in snapshot_names
    assert tuple(ACCOUNT_EXPORT_OMITTED_TABLES) == (
        "daily_capture_request_identities",
        "account_setting_request_identities",
        "calendar_request_identities",
        "notification_action_requests",
        "deadline_plan_request_identities",
        "assignment_series_request_identities",
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


def test_consumers_share_neutral_reader_without_importing_each_other() -> None:
    account_source = Path(account_service_module.__file__).read_text()
    coach_source = Path(coach_snapshot_module.__file__).read_text()

    assert "OwnerDataReader(" in account_source
    assert "OwnerDataReader(" in coach_source
    assert "app.services.coach_snapshot" not in account_source
    assert "app.services.account_service" not in coach_source
    assert "_lossless_json_text" not in coach_source
