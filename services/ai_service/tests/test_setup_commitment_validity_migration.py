from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260722234000_setup_commitment_validity_guards.sql"
)
PLANNER_MIGRATION = (
    ROOT / "supabase" / "migrations" / "20260722120000_planner_v1.sql"
)


def _sql() -> str:
    return MIGRATION.read_text().lower()


def test_validity_guard_runs_after_planner_foundation() -> None:
    assert MIGRATION.name > PLANNER_MIGRATION.name


def test_guard_keeps_undated_rows_and_uses_inclusive_setup_bounds() -> None:
    sql = _sql()

    assert "private.setup_schedule_applies_on" in sql
    assert "is distinct from 'setup'" in sql
    assert "p_local_date >= valid_from_date" in sql
    assert "p_local_date <= valid_until_date" in sql
    assert "valid_until_date < valid_from_date" in sql
    assert "valid_from_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'" in sql
    assert "valid_until_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'" in sql


def test_confirmation_guards_cover_task_habit_and_deadline_occurrences() -> None:
    sql = _sql()

    assert sql.count("private.setup_schedule_applies_on(") >= 4
    assert "revision_row.planning_start_on + occurrence.day_offset" in sql
    assert "from generate_series(0, 27)" in sql
    assert "planner task schedule guard definition drifted" in sql
    assert "planner habit schedule guard definition drifted" in sql
    assert "deadline schedule guard definition drifted" in sql


def test_helper_is_private_and_not_executable_by_application_roles() -> None:
    sql = _sql()

    assert (
        "revoke all on function private.setup_schedule_applies_on(jsonb, date)"
        in sql
    )
    assert "from public, anon, authenticated, service_role" in sql
