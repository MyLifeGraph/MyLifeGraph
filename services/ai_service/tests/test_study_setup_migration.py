from pathlib import Path

from app.models.account import ACCOUNT_EXPORT_TABLE_NAMES
from app.services.account_service import ACCOUNT_EXPORT_TABLES


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260723120000_study_setup_v1.sql"


def _sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_study_profile_is_owner_scoped_backend_written_and_cascade_deleted() -> None:
    sql = _sql()

    assert "create table public.study_setup_profiles" in sql
    assert "references public.profiles (id) on delete cascade" in sql
    assert "alter table public.study_setup_profiles enable row level security" in sql
    assert "alter table public.study_setup_profiles force row level security" in sql
    assert (
        "revoke all on table public.study_setup_profiles "
        "from public, anon, authenticated"
    ) in sql
    assert "grant select on table public.study_setup_profiles to authenticated" in sql
    assert "study_setup_profiles_owner_select" in sql
    assert "(select auth.uid()) = user_id" in sql
    assert "study_setup_profiles_service_all" in sql


def test_study_projection_is_part_of_atomic_revisioned_intake_apply() -> None:
    sql = _sql()
    wrapper_start = sql.index(
        "create or replace function public.apply_intake_v1_setup_revision(",
    )
    wrapper_end = sql.index(
        "create or replace function private.deadline_study_reservations_conflict",
    )
    wrapper = sql[wrapper_start:wrapper_end]

    assert "apply_intake_v1_setup_revision_without_study_setup" in wrapper
    assert "canonical_row.responses -> 'study_setup'" in wrapper
    assert "state = 'applied'" in wrapper
    assert "newer.revision > value.revision" in wrapper
    assert "delete from public.study_setup_profiles" in wrapper
    assert "insert into public.study_setup_profiles" in wrapper
    assert "on conflict (user_id) do update" in wrapper
    assert "setup_revision = excluded.setup_revision" in wrapper
    assert "Canonical Study Setup shape is invalid." in wrapper
    assert "Canonical Study Focus shape is invalid." in wrapper
    assert "Canonical Study Semester shape is invalid." in wrapper
    assert "study_rhythm_changed" in wrapper


def test_study_shapes_and_recovery_reservations_fail_closed() -> None:
    sql = _sql()

    assert "p_focus_minutes not between 25 and 180" in sql
    assert "p_focus_minutes % 5 <> 0" in sql
    assert "p_recovery_minutes not between 5 and 60" in sql
    assert "jsonb_array_length(p_preparation_items) > 12" in sql
    assert "count(distinct lower(value ->> 'label'))" in sql
    assert (
        "jsonb_array_length(p_next_semester -> 'course_names') > 12"
        in sql
    )
    assert "selection_starts <= selection_ends" in sql
    assert "reserved_ends_at = ends_at + recovery_minutes * interval '1 minute'" in sql
    assert "update public.deadline_plan_blocks set reserved_ends_at = ends_at" in sql
    assert "update public.planner_task_blocks set reserved_ends_at = ends_at" in sql
    assert "tstzrange(proposed.starts_at, proposed.reserved_ends_at, '[)')" in sql


def test_planner_and_deadline_wrappers_bind_current_study_revision() -> None:
    sql = _sql()

    for function in (
        "propose_deadline_plan_v1",
        "confirm_deadline_plan_v1",
        "propose_planner_action_plan_v1",
        "confirm_planner_action_plan_v1",
    ):
        assert f"create or replace function public.{function}" in sql
        assert f"grant execute on function public.{function}" in sql
        assert f"{function}_without_study_setup" in sql
    assert "Task use_study_rhythm must be explicit." in sql
    assert "Habits cannot use the Study rhythm." in sql
    assert "Current Study rhythm is required for this Task." in sql
    assert "Study rhythm changed. Create a new deadline preview." in sql
    assert "Study rhythm changed. Create a new Planner preview." in sql
    assert "Recovery availability changed. Replan before confirmation." in sql
    assert "block.sequence <> block_count" in sql


def test_account_export_includes_study_projection() -> None:
    assert "study_setup_profiles" in ACCOUNT_EXPORT_TABLE_NAMES
    exported = {table.name: table for table in ACCOUNT_EXPORT_TABLES}
    assert exported["study_setup_profiles"].select == (
        "user_id,contract_version,focus_minutes,recovery_minutes,"
        "preparation_items,current_semester,next_semester,setup_revision,"
        "created_at,updated_at"
    )
