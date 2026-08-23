from tests.migration_source import extract_function, load_migration


MIGRATION = load_migration("20260813040200_exam_plan_health_v1.sql")


def test_exam_health_snapshot_is_stable_read_only_and_service_role_only() -> None:
    function = extract_function(
        MIGRATION,
        "public.get_exam_plan_health_snapshot_v1",
    )
    assert "security definer" in function
    assert "stable" in function
    assert "set search_path = ''" in function
    assert "p_user_id uuid" in function
    assert "p_generated_at timestamptz" in function
    assert "insert into" not in function
    assert "update public." not in function
    assert "delete from" not in function
    assert "clock_timestamp" not in function
    assert "now()" not in function
    assert (
        "revoke all on function public.get_exam_plan_health_snapshot_v1(uuid, timestamptz)\n"
        "  from public, anon, authenticated, service_role;" in MIGRATION
    )
    assert (
        "grant execute on function public.get_exam_plan_health_snapshot_v1(uuid, timestamptz)\n"
        "  to service_role;" in MIGRATION
    )


def test_exam_health_snapshot_has_no_plan_or_event_limit_and_uses_one_statement() -> (
    None
):
    function = extract_function(
        MIGRATION,
        "public.get_exam_plan_health_snapshot_v1",
    )
    assert "limit 50" not in function
    assert "active_exams as (" in function
    assert "focus_totals as (" in function
    assert "focus_facts as (" in function
    assert "source.deadline_plan_block_id" in function
    assert "revision.tracked_focus_minutes_at_proposal" in function
    assert "active_block_count" in function
    assert "deadline_blocks" in function
    assert "planner_task_blocks" in function
    assert "planner_habit_slots" in function
    assert "planner_commitments" in function
    assert "calendar_timed_events" in function
    assert "calendar_all_day_events" in function
    assert "focus.started_at >= exam.first_activated_at" in function
    assert "focus.status = 'completed'" in function
    assert (
        "horizon_ends_before::timestamp at time zone profile_row.timezone" in function
    )
    assert "item.import_id" in function
    assert "import.planning_status = 'current'" in function


def test_exam_health_snapshot_is_additive_and_persists_no_health_state() -> None:
    assert "create table" not in MIGRATION
    assert "alter table" not in MIGRATION
    assert "drop table" not in MIGRATION
    assert "exam_plan_health" not in MIGRATION.replace(
        "get_exam_plan_health_snapshot_v1",
        "",
    )
