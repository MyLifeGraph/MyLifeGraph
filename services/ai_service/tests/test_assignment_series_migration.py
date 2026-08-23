from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    REPOSITORY_ROOT
    / "supabase"
    / "migrations"
    / "20260810092841_finite_assignment_series_v1.sql"
)


def _sql() -> str:
    return MIGRATION.read_text().lower()


def test_assignment_series_schema_is_owner_read_only_and_service_mutated() -> None:
    sql = _sql()
    for table in (
        "assignment_series",
        "assignment_series_revisions",
        "assignment_series_revision_items",
        "assignment_series_request_identities",
    ):
        assert f"create table public.{table}" in sql
        assert f"alter table public.{table} force row level security" in sql
    assert "grant select on table public.assignment_series," in sql
    assert "to authenticated" in sql
    assert "assignment_series_requests_service_all" in sql
    assert "assignment_series_request_identities\n  to authenticated" not in sql


def test_series_rpcs_are_service_only_bounded_and_atomic() -> None:
    sql = _sql()
    for function in (
        "propose_assignment_series_v1",
        "confirm_assignment_series_v1",
        "cancel_assignment_series_future_v1",
    ):
        assert f"create or replace function public.{function}" in sql
        assert f"grant execute on function public.{function}" in sql
    assert "remaining_occurrences between 1 and 20" in sql
    assert "new assignment series needs at least two occurrences" in sql
    assert "exact weekly local cadence" in sql
    assert "assignment occurrence previews conflict with one another" in sql
    assert "past or completed assignment occurrences must be preserved" in sql
    assert "perform public.confirm_deadline_plan_v1" in sql
    assert "perform public.mutate_deadline_plan_lifecycle_v1" in sql
    assert "insert into public.assignment_series_request_identities" in sql


def test_series_items_pin_independent_deadline_plan_revisions() -> None:
    sql = _sql()
    assert "foreign key (plan_id, user_id)" in sql
    assert "references public.deadline_plans (id, user_id) on delete cascade" in sql
    assert "unique (series_id, series_revision, position)" in sql
    assert "unique (series_id, series_revision, plan_id)" in sql
    assert "credited_prior_minutes')::int <> 0" in sql
