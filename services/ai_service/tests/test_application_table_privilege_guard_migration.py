import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION_PATH = (
    ROOT
    / "supabase/migrations/20260714103000_application_table_privilege_guard.sql"
)
MIGRATION = MIGRATION_PATH.read_text(encoding="utf-8")
NORMALIZED = " ".join(MIGRATION.lower().split())

PROJECTION_TABLES = (
    "notifications",
    "ai_insights",
    "recommendations",
    "skillset_profiles",
)
PROJECTION_TABLE_LIST = ", ".join(
    f"public.{table}" for table in PROJECTION_TABLES
)
LEGACY_TABLES = {
    "FocusSession",
    "CoachMessage",
    "AIInsight",
    "ActivityLog",
    "DailyLog",
    "MemoryEntry",
    "MoodLog",
    "Notification",
    "ScheduleItem",
    "SleepLog",
    "Task",
    "Habit",
    "Goal",
    "User",
}


def _guard_array(block_name: str) -> set[str]:
    start = MIGRATION.index(f"do ${block_name}$")
    array_start = MIGRATION.index("array array[", start)
    array_end = MIGRATION.index("]", array_start)
    return set(re.findall(r"'([A-Za-z_]+)'", MIGRATION[array_start:array_end]))


def test_guard_runs_after_the_notification_lifecycle_migration() -> None:
    lifecycle_path = (
        ROOT
        / "supabase/migrations/20260714100000_notification_lifecycle_v1.sql"
    )

    assert lifecycle_path.exists()
    assert lifecycle_path.name < MIGRATION_PATH.name


def test_guard_lists_every_repo_owned_product_and_ledger_table_created_so_far() -> None:
    created_tables: set[str] = set()
    pattern = re.compile(
        r"create\s+table(?:\s+if\s+not\s+exists)?\s+public\.([a-z][a-z0-9_]*)",
        flags=re.IGNORECASE,
    )
    for path in (ROOT / "supabase/migrations").glob("*.sql"):
        if path.name >= MIGRATION_PATH.name:
            continue
        created_tables.update(pattern.findall(path.read_text(encoding="utf-8")))

    assert _guard_array("application_table_privilege_guard") == created_tables
    assert "lifestyle_entries" in created_tables


def test_public_and_anon_lose_all_current_product_table_privileges() -> None:
    assert (
        "'revoke all privileges on table public.%i from public, anon'"
        in NORMALIZED
    )
    assert "to_regclass(format('public.%i', table_name)) is null" in NORMALIZED
    assert (
        "raise exception 'application privilege guard is missing table public.%'"
        in NORMALIZED
    )


def test_authenticated_loses_only_dangerous_privileges_across_product_tables() -> None:
    assert (
        "'revoke truncate, references, trigger on table public.%i ' "
        "'from authenticated'"
        in NORMALIZED
    )
    canonical_start = NORMALIZED.index("do $application_table_privilege_guard$")
    canonical_end = NORMALIZED.index(
        "$application_table_privilege_guard$;",
        canonical_start,
    )
    canonical_guard = NORMALIZED[canonical_start:canonical_end]
    assert "revoke insert" not in canonical_guard
    assert "revoke update" not in canonical_guard
    assert "revoke delete" not in canonical_guard


def test_optional_legacy_tables_keep_the_full_application_mutation_freeze() -> None:
    assert _guard_array("legacy_application_table_privilege_guard") == LEGACY_TABLES
    legacy_start = NORMALIZED.index(
        "do $legacy_application_table_privilege_guard$",
    )
    legacy_end = NORMALIZED.index(
        "$legacy_application_table_privilege_guard$;",
        legacy_start,
    )
    legacy_guard = NORMALIZED[legacy_start:legacy_end]

    assert "to_regclass(format('public.%i', table_name)) is not null" in legacy_guard
    assert (
        "'revoke all privileges on table public.%i from public, anon'"
        in legacy_guard
    )
    assert (
        "'revoke insert, update, delete, truncate, references, trigger ' "
        "'on table public.%i from authenticated'"
        in legacy_guard
    )


def test_backend_owned_projections_remain_authenticated_read_only() -> None:
    assert (
        "revoke insert, update, delete on table "
        f"{PROJECTION_TABLE_LIST} from authenticated"
        in NORMALIZED
    )
    assert (
        f"grant select on table {PROJECTION_TABLE_LIST} to authenticated"
        in NORMALIZED
    )
    assert "to public" not in NORMALIZED
    assert "to anon" not in NORMALIZED


def test_postgres_future_table_defaults_fail_closed_for_application_roles() -> None:
    assert (
        "alter default privileges for role postgres in schema public "
        "revoke all privileges on tables from public, anon"
        in NORMALIZED
    )
    assert (
        "alter default privileges for role postgres in schema public revoke "
        "truncate, references, trigger on tables from authenticated"
        in NORMALIZED
    )
    assert "alter default privileges for role supabase_admin" not in NORMALIZED
    assert "on tables from service_role" not in NORMALIZED
    assert "on tables from postgres" not in NORMALIZED


def test_table_guard_never_revokes_service_role_privileges() -> None:
    before_function_revokes = NORMALIZED.index(
        "revoke execute on function public.handle_new_user()",
    )
    table_and_default_guard = NORMALIZED[:before_function_revokes]

    assert "from service_role" not in table_and_default_guard
    assert (
        "from public, anon, authenticated, service_role"
        not in table_and_default_guard
    )


def test_auth_trigger_functions_are_not_executable_by_reusable_roles() -> None:
    for function_name in ("handle_new_user", "handle_new_auth_user"):
        assert (
            f"revoke execute on function public.{function_name}() "
            "from public, anon, authenticated, service_role"
            in NORMALIZED
        )


def test_execute_revokes_leave_the_preexisting_auth_triggers_installed() -> None:
    canonical = (
        ROOT
        / "supabase/migrations/20260618170000_create_canonical_app_schema.sql"
    ).read_text(encoding="utf-8")
    legacy = (
        ROOT / "supabase/migrations/20260602162000_auth_roles_rls.sql"
    ).read_text(encoding="utf-8")

    assert "create trigger on_auth_user_created" in canonical.lower()
    assert "execute function public.handle_new_user()" in canonical.lower()
    assert "create trigger on_auth_user_created_app_user" in legacy.lower()
    assert "execute function public.handle_new_auth_user()" in legacy.lower()
    assert "drop trigger" not in NORMALIZED
    assert "create trigger" not in NORMALIZED
    assert "create or replace function" not in NORMALIZED


def test_notification_retry_ledger_has_a_child_side_cascade_index() -> None:
    assert (
        "create index if not exists "
        "notification_action_requests_notification_owner_idx on "
        "public.notification_action_requests (notification_id, user_id)"
        in NORMALIZED
    )


def test_notification_timestamp_guards_are_new_write_only_until_cleanup() -> None:
    expected_checks = {
        "notifications_created_updated_order_check": "created_at <= updated_at",
        "notifications_read_updated_order_check": (
            "read_at is null or read_at <= updated_at"
        ),
        "notifications_dismissed_updated_order_check": (
            "dismissed_at is null or dismissed_at <= updated_at"
        ),
        "notification_action_requests_expected_result_order_check": (
            "expected_updated_at <= result_updated_at"
        ),
        "notification_action_requests_read_result_order_check": (
            "result_read_at is null or result_read_at <= result_updated_at"
        ),
        "notification_action_requests_dismissed_result_order_check": (
            "result_dismissed_at is null or result_dismissed_at <= "
            "result_updated_at"
        ),
    }

    for constraint_name, expression in expected_checks.items():
        assert (
            f"add constraint {constraint_name} check ({expression}) not valid"
            in NORMALIZED
        )
    assert "validate constraint" not in NORMALIZED
