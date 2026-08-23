import re

from tests.migration_source import (
    extract_dropped_policy_names,
    extract_policy,
    load_migration,
    normalize_sql,
)

MIGRATION = load_migration(
    "20260723200707_optimize_canonical_rls_policies.sql",
)
NORMALIZED = normalize_sql(MIGRATION)

SUPERSEDED_POLICIES = {
    "profiles_select_own",
    "profiles_update_own",
    "profiles_insert_own",
    "behavioral_events_own_all",
    "lifestyle_entries_own_all",
    "notification_preferences_own_all",
}

OWNER_ADMIN_TABLES = {
    "behavioral_events",
    "daily_logs",
    "focus_sessions",
    "goals",
    "habit_logs",
    "habits",
    "lifestyle_entries",
    "notification_preferences",
    "schedule_items",
    "tasks",
}


def test_migration_drops_every_superseded_initial_policy() -> None:
    dropped = set(extract_dropped_policy_names(MIGRATION))

    assert SUPERSEDED_POLICIES <= dropped


def test_migration_rebuilds_the_complete_canonical_owner_admin_set() -> None:
    block_start = MIGRATION.index("foreach table_name in array array[")
    block_end = MIGRATION.index("]", block_start)
    tables = set(re.findall(r"'([a-z0-9_]+)'", MIGRATION[block_start:block_end]))

    assert tables == OWNER_ADMIN_TABLES
    assert "on public.profiles" in extract_policy(
        MIGRATION,
        "profiles_own_or_admin_all",
    )


def test_identity_and_role_helpers_are_initplan_safe() -> None:
    assert "auth.uid()" not in NORMALIZED.replace("(select auth.uid())", "")
    assert "private.current_app_role()" not in NORMALIZED.replace(
        "(select private.current_app_role())",
        "",
    )


def test_migration_does_not_change_privileges_or_rls_mode() -> None:
    for forbidden in (
        " grant ",
        " revoke ",
        "enable row level security",
        "disable row level security",
        "force row level security",
        "no force row level security",
    ):
        assert forbidden not in f" {NORMALIZED} "
