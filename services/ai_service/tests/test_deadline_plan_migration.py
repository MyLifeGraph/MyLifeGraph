from pathlib import Path

from app.models.account import (
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
)
from app.services.account_service import ACCOUNT_EXPORT_TABLES


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / (
    "supabase/migrations/20260718120000_deadline_planner_v1.sql"
)


def _sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_deadline_migration_creates_backend_owned_owner_scoped_tables() -> None:
    sql = _sql()
    for table in (
        "deadline_plans",
        "deadline_plan_revisions",
        "deadline_plan_blocks",
        "deadline_plan_request_identities",
    ):
        assert f"create table public.{table}" in sql
        assert f"alter table public.{table} enable row level security" in sql
        assert f"alter table public.{table} force row level security" in sql
    assert "from public, anon, authenticated, service_role" in sql
    assert "grant select on table public.deadline_plans" in sql
    assert "grant select, insert" not in sql
    assert "grant select, insert, update, delete" not in sql
    assert "deadline_plan_requests_service_all" in sql
    assert "backend_only_anti_replay_ledger" not in sql


def test_deadline_rpcs_are_retry_safe_locked_and_service_only() -> None:
    sql = _sql()
    for function in (
        "propose_deadline_plan_v1",
        "confirm_deadline_plan_v1",
        "mutate_deadline_plan_lifecycle_v1",
        "get_deadline_plan_projection_v1",
    ):
        assert f"create or replace function public.{function}" in sql
        assert f"grant execute on function public.{function}" in sql
    assert sql.count(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))",
    ) == 3
    assert sql.count(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13))",
    ) == 3
    assert sql.count("request_id is already bound") == 3
    assert "plan_row.latest_revision <> p_base_revision" in sql
    assert "plan_row.latest_revision <> p_expected_revision" in sql
    assert "where user_id = p_user_id and status in ('draft', 'active')" in sql
    assert "You already have 50 open deadline plans." in sql
    assert "'blocks', coalesce(" in sql
    assert "jsonb_agg(" in sql
    projection_start = sql.index(
        "create or replace function public.get_deadline_plan_projection_v1",
    )
    projection_end = sql.index(
        "create or replace function private.guard_deadline_plan_managed_task",
    )
    projection = sql[projection_start:projection_end]
    assert "language sql" in projection
    assert "with open_plans as materialized" in projection
    assert "selected_plans as materialized" in projection
    assert "selected_revisions as materialized" in projection
    assert "selected_blocks as materialized" in projection
    assert "focus_totals as materialized" in projection
    assert "source_events as materialized" in projection
    # `revision` is also a scalar column name. A distinct row alias is required
    # or PostgreSQL serializes only `[1]` instead of full revision objects.
    assert "to_jsonb(revision_row)" in projection
    assert "from selected_revisions as revision_row" in projection
    for key in (
        "plan_count",
        "revision_count",
        "block_count",
        "focus_total_count",
        "calendar_event_count",
    ):
        assert f"'{key}'" in projection


def test_managed_task_gate_and_atomic_lifecycle_are_explicit() -> None:
    sql = _sql()
    assert "create trigger tasks_guard_deadline_plan_managed" in sql
    assert "mylifegraph.deadline_plan_rpc" in sql
    assert "Deadline-plan managed tasks are backend-workflow owned." in sql
    assert "pg_trigger_depth() > 1" in sql
    assert "p_plan_id, p_user_id, revision_row.title" in sql
    assert "'contract_version', 'deadline-plan-v1'" in sql
    assert "'managed_by', 'deadline-planner'" in sql
    assert "'plan_id', p_plan_id" in sql
    assert "estimated_minutes = null" in sql
    assert (
        "status = case when p_action = 'complete' then 'done' else 'cancelled'"
        in sql
    )
    assert (
        "where user_id = p_user_id and task_id = p_plan_id and status = 'active'"
        in sql
    )
    task_lock = sql.index(
        "from public.tasks\n    where id = p_plan_id",
        sql.index("if plan_row.status = 'active'"),
    )
    focus_guard = sql.index("select 1 from public.focus_sessions", task_lock)
    terminal_update = sql.index("update public.tasks", focus_guard)
    assert task_lock < focus_guard < terminal_update
    assert "for update;" in sql[task_lock:focus_guard]
    assert "if plan_row.status = 'draft'" in sql
    assert "p_action <> 'cancel'" in sql
    assert "Finish or abandon active focus before replanning." in sql
    assert "Finish or abandon active focus before confirmation." in sql
    assert "Focus progress changed; replan before confirmation." in sql
    assert sql.count("focus.started_at >= plan_row.first_activated_at") >= 4
    assert sql.count("from public.tasks as task") >= 2


def test_block_and_calendar_contracts_fail_closed() -> None:
    sql = _sql()
    assert "sequence between 1 and 120" in sql
    assert "revision between 1 and 200" in sql
    assert "ends_at - starts_at = planned_minutes * interval '1 minute'" in sql
    assert "count(distinct block.sequence) <> count(*)" in sql
    assert "block.local_date <>" in sql
    assert "block.local_start_time <>" in sql
    assert "block.local_end_time <>" in sql
    assert "block.ends_at > (p_proposal ->> 'deadline_at')::timestamptz" in sql
    assert "(p_proposal ->> 'buffer_days')::int = 0" in sql
    assert "tstzrange(proposed.starts_at, proposed.ends_at, '[)')" in sql
    assert "join public.schedule_items as fixed" in sql
    assert "event.busy_status = 'busy'" in sql
    assert "connection.last_import_id = revision_row.availability_import_id" in sql
    assert "connection.last_import_id = event.import_id" in sql
    assert "revision_row.deadline_at <= p_now" in sql
    assert "reservation_state = 'proposed' and starts_at <= p_now" in sql


def test_account_export_includes_product_rows_and_omits_request_ledger() -> None:
    expected = (
        "deadline_plans",
        "deadline_plan_revisions",
        "deadline_plan_blocks",
    )
    start = ACCOUNT_EXPORT_TABLE_NAMES.index("deadline_plans")
    assert ACCOUNT_EXPORT_TABLE_NAMES[start : start + 3] == expected
    exported_names = tuple(table.name for table in ACCOUNT_EXPORT_TABLES)
    export_start = exported_names.index("deadline_plans")
    assert exported_names[export_start : export_start + 3] == expected
    assert ACCOUNT_EXPORT_OMITTED_TABLES["deadline_plan_request_identities"] == (
        "backend_only_anti_replay_ledger"
    )
    revision_export = next(
        table
        for table in ACCOUNT_EXPORT_TABLES
        if table.name == "deadline_plan_revisions"
    )
    assert revision_export.select != "*"
    assert "request_fingerprint" not in revision_export.select
