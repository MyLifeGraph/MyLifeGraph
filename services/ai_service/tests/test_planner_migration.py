from pathlib import Path

from app.models.account import (
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
)
from app.services.account_service import ACCOUNT_EXPORT_TABLES


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260722120000_planner_v1.sql"


def _sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_planner_tables_are_additive_owner_scoped_and_backend_written() -> None:
    sql = _sql()
    product_tables = (
        "planner_preferences",
        "planner_action_plans",
        "planner_action_plan_revisions",
        "planner_task_blocks",
        "planner_habit_slots",
        "planner_commitments",
    )
    for table in (*product_tables, "planner_request_identities"):
        assert f"create table public.{table}" in sql
        assert f"alter table public.{table} enable row level security" in sql
        assert f"alter table public.{table} force row level security" in sql
    assert "from public, anon, authenticated, service_role" in sql
    assert "grant select on table public.planner_preferences" in sql
    authenticated_grants = sql[
        sql.index("grant select on table public.planner_preferences") :
        sql.index("grant select, insert, update, delete on table")
    ]
    assert authenticated_grants.rstrip().endswith("to authenticated;")
    assert "insert" not in authenticated_grants
    for table in product_tables:
        assert f"on public.{table} for select to authenticated" in sql
    assert "planner_requests_service_all" in sql
    assert "insert into public.tasks" in sql
    assert "insert into public.habits" in sql
    assert "insert into public.tasks\n  select" not in sql
    assert "insert into public.habits\n  select" not in sql


def test_planner_rpcs_are_retry_safe_owner_locked_and_service_only() -> None:
    sql = _sql()
    signatures = (
        "set_planner_preferences_v1",
        "propose_planner_action_plan_v1",
        "confirm_planner_action_plan_v1",
        "cancel_planner_action_plan_v1",
        "mutate_planner_commitment_v1",
    )
    for function in signatures:
        assert f"create or replace function public.{function}" in sql
        assert f"grant execute on function public.{function}" in sql
        assert f"revoke all on function public.{function}" in sql
    assert sql.count(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))",
    ) == 5
    assert sql.count(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13))",
    ) == 5
    assert sql.count("request_id is already bound") == 5
    assert "unique (user_id, target_kind, target_id)" in sql
    assert "planner_action_revisions_one_proposed_idx" in sql
    assert "planner_action_revisions_one_active_idx" in sql


def test_confirmation_rechecks_target_calendar_and_every_reservation_kind() -> None:
    sql = _sql()
    confirmation = sql[
        sql.index("create or replace function public.confirm_planner_action_plan_v1") :
        sql.index("create or replace function public.cancel_planner_action_plan_v1")
    ]
    conflicts = sql[
        sql.index("create or replace function private.planner_revision_conflicts") :
        sql.index("create or replace function public.confirm_planner_action_plan_v1")
    ]
    assert "for update" in confirmation
    assert "updated_at = (payload ->> 'expected_updated_at')::timestamptz" in confirmation
    assert "connection.last_import_id = revision_row.calendar_import_id" in confirmation
    assert "starts_at <= p_now" in confirmation
    assert "private.planner_revision_conflicts" in confirmation
    for table in (
        "planner_task_blocks",
        "planner_habit_slots",
        "deadline_plan_blocks",
        "schedule_items",
        "planner_commitments",
        "calendar_events",
    ):
        assert f"public.{table}" in conflicts
    assert "insert into public.tasks" in confirmation
    assert "insert into public.habits" in confirmation
    assert "set state = 'active', activated_at = p_now" in confirmation


def test_authoritative_commitments_and_target_lifecycle_only_release_slots() -> None:
    sql = _sql()
    assert "refresh_planner_commitment_attention" in sql
    assert "'commitment_conflict'" in sql
    assert "tasks_release_planner_reservations" in sql
    assert "habits_release_planner_reservations" in sql
    assert "when block.ends_at > mutation_at then 'released'" in sql
    assert "set status = 'unscheduled', current_revision = 0" in sql
    assert "attention_reasons = array['target_released']" in sql
    assert "deadline_blocks_guard_planner_reservations" in sql
    assert "Preparation block conflicts with a Planner reservation." in sql
    assert "state = 'active'" in sql
    assert "state = 'released'" in sql
    assert "state = 'completed'" not in sql


def test_account_export_includes_planner_content_but_not_retry_identity() -> None:
    expected = (
        "planner_preferences",
        "planner_action_plans",
        "planner_action_plan_revisions",
        "planner_task_blocks",
        "planner_habit_slots",
        "planner_commitments",
    )
    assert ACCOUNT_EXPORT_TABLE_NAMES[-6:] == expected
    assert tuple(table.name for table in ACCOUNT_EXPORT_TABLES)[-6:] == expected
    assert ACCOUNT_EXPORT_OMITTED_TABLES["planner_request_identities"] == (
        "backend_only_anti_replay_ledger"
    )
