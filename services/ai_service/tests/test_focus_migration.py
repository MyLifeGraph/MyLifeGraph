from tests.migration_source import extract_function, load_migration


MIGRATION = load_migration("20260802083219_focus_schedule_sources_v2.sql")


def _sql() -> str:
    return MIGRATION


def _function(sql: str, name: str) -> str:
    return extract_function(sql, name)


def test_schedule_source_table_is_owner_read_only_and_restrict_linked() -> None:
    sql = _sql()
    assert "create table public.focus_session_schedule_sources" in sql
    assert (
        "alter table public.focus_session_schedule_sources force row level security"
        in sql
    )
    assert (
        "grant select on table public.focus_session_schedule_sources to authenticated"
        in sql
    )
    assert "grant select, insert on table public.focus_session_schedule_sources" in sql
    assert sql.count("on delete restrict") == 2
    assert "focus_schedule_sources_owner_created_idx" in sql
    assert "focus_schedule_sources_deadline_block_idx" in sql
    assert "focus_schedule_sources_planner_block_idx" in sql
    assert "focus_schedule_sources_immutable_v2" in sql


def test_focus_start_uses_owner_then_request_then_row_lock_order() -> None:
    start = _function(_sql(), "public.start_focus_session_v2")
    owner_lock = start.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))",
    )
    request_lock = start.index(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 17))",
    )
    row_lock = start.index("for update;")
    assert owner_lock < request_lock < row_lock
    assert "focus_request_conflict" in start
    assert "active_focus_session" in start
    assert "focus_sessions_one_active_per_user_idx" in start
    assert "get stacked diagnostics violated_constraint = constraint_name" in start
    assert "private.focus_schedule_conflict_v2" in start
    assert "p_planned_minutes" in start


def test_local_instant_resolution_rejects_non_hour_dst_ambiguity() -> None:
    resolver = _function(_sql(), "private.focus_resolve_local_instant_v2")
    assert "valid_candidate_count <> 1" in resolver
    assert "probe at time zone p_timezone" in resolver
    assert "interval '1 hour'" not in resolver


def test_collision_projection_is_half_open_complete_and_source_aware() -> None:
    collision = _function(_sql(), "private.focus_schedule_conflict_v2")
    for source in (
        "public.focus_sessions",
        "public.deadline_plan_blocks",
        "public.planner_task_blocks",
        "public.planner_commitments",
        "public.schedule_items",
        "public.planner_habit_slots",
        "public.calendar_events",
    ):
        assert source in collision
    assert collision.count("'[)'") >= 5
    assert (
        "p_source_kind = 'deadline_plan_block' and block.id = p_block_id" in collision
    )
    assert "p_source_kind = 'planner_task_block' and block.id = p_block_id" in collision
    assert "calendar_availability_unavailable" in collision
    assert "profile_row.timezone_revision" in collision
    assert "focus_resolve_local_instant_v2" in collision


def test_deadline_projection_preserves_total_and_adds_source_facts() -> None:
    projection = _function(_sql(), "public.get_deadline_plan_projection_v2")
    credits = _function(_sql(), "private.deadline_block_credits_v2")
    assert "get_deadline_plan_projection_v1" in projection
    assert "'focus_facts'" in projection
    assert "source.deadline_plan_block_id" in projection
    assert "proposal_credit_left" in credits
    assert "generic_credit" in credits
    assert "focus_row.deadline_plan_block_id" in credits


def test_focus_rpcs_have_fixed_search_paths_and_service_only_grants() -> None:
    sql = _sql()
    for name in (
        "public.get_focus_start_context_v2",
        "public.start_focus_session_v2",
        "public.finish_focus_session_v2",
        "public.get_deadline_plan_projection_v2",
    ):
        function = _function(sql, name)
        assert "security definer" in function
        assert "set search_path = pg_catalog, pg_temp" in function
        assert f"grant execute on function {name}" in sql
    assert "to service_role" in sql
