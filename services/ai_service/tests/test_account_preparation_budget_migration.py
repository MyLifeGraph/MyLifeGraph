from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260719120000_account_preparation_budget_v1.sql"
)
DEADLINE_MIGRATION = (
    ROOT / "supabase" / "migrations" / "20260718120000_deadline_planner_v1.sql"
)


def _normalized(path: Path) -> str:
    return " ".join(path.read_text(encoding="utf-8").lower().split())


def test_budget_column_is_nullable_bounded_and_not_directly_owner_writable() -> None:
    sql = _normalized(MIGRATION)

    assert "add column if not exists daily_preparation_budget_minutes int" in sql
    assert "daily_preparation_budget_minutes between 25 and 480" in sql
    assert "daily_preparation_budget_minutes % 5 = 0" in sql
    assert (
        "revoke update (daily_preparation_budget_minutes) on table public.profiles "
        "from anon, authenticated"
    ) in sql


def test_budget_rpc_is_service_role_only_owner_locked_and_idempotent() -> None:
    sql = _normalized(MIGRATION)

    assert (
        "create or replace function public.set_daily_preparation_budget_v1( "
        "p_user_id uuid, p_daily_preparation_budget_minutes int ) returns jsonb "
        "language plpgsql security definer set search_path = pg_catalog, pg_temp"
    ) in sql
    assert (
        "perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))"
        in sql
    )
    assert "where id = p_user_id" in sql
    assert "when daily_preparation_budget_minutes is distinct from" in sql
    assert (
        "revoke all on function public.set_daily_preparation_budget_v1(uuid, int) "
        "from public, anon, authenticated"
    ) in sql
    assert (
        "grant execute on function public.set_daily_preparation_budget_v1(uuid, int) "
        "to service_role"
    ) in sql


def test_confirmation_trigger_rechecks_total_budget_under_shared_owner_lock() -> None:
    sql = _normalized(MIGRATION)
    deadline_sql = _normalized(DEADLINE_MIGRATION)

    assert (
        "old.reservation_state = 'proposed' and new.reservation_state = 'active'"
        in sql
    )
    assert "active.user_id = new.user_id" in sql
    assert "candidate.user_id = new.user_id" in sql
    assert "active.local_date in ( select scoped.local_date" in sql
    assert "scoped.plan_id = new.plan_id" in sql
    assert "scoped.revision = new.revision" in sql
    assert "group by combined.local_date" in sql
    assert "having sum(combined.planned_minutes) > account_budget" in sql
    assert "using errcode = 'pt409'" in sql
    assert "before update of reservation_state" in sql
    assert (
        "create or replace function public.confirm_deadline_plan_v1" in deadline_sql
    )
    assert (
        "perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))"
        in deadline_sql
    )
