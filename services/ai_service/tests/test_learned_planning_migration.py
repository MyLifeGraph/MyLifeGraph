from app.services.account_service import ACCOUNT_EXPORT_TABLES
from tests.migration_source import load_migration


MIGRATION = load_migration(
    "20260726150000_learned_focus_planning_v1.sql",
)
RPC_GUARD_MIGRATION = load_migration(
    "20260726180000_learned_focus_planning_rpc_guard.sql",
)
CONFIRMATION_TIME_GUARD_MIGRATION = load_migration(
    "20260726190000_planning_confirmation_timestamp_guard.sql",
)
SETUP_FALLBACK_PROVENANCE_MIGRATION = load_migration(
    "20260726200000_learned_timing_setup_fallback_provenance.sql",
)


def _sql() -> str:
    return MIGRATION


def _rpc_guard_sql() -> str:
    return RPC_GUARD_MIGRATION


def _confirmation_time_guard_sql() -> str:
    return CONFIRMATION_TIME_GUARD_MIGRATION


def _setup_fallback_provenance_sql() -> str:
    return SETUP_FALLBACK_PROVENANCE_MIGRATION


def test_revision_provenance_is_bounded_and_habits_cannot_use_it() -> None:
    sql = _sql()

    for table in (
        "public.planner_action_plan_revisions",
        "public.deadline_plan_revisions",
    ):
        assert f"alter table {table}" in sql
    for column in (
        "timing_preference_source",
        "timing_preference_window",
        "timing_evidence_count",
        "timing_evidence_starts_on",
        "timing_evidence_ends_on",
        "timing_evidence_fingerprint",
        "timing_fell_back_to_setup",
        "timing_warning",
    ):
        assert column in sql
    assert "target_payload ->> 'kind' = 'task'" in sql
    assert "'05-09', '09-13', '13-18', '18-23'" in sql
    assert "timing_evidence_count between 1 and 10000" in sql


def test_proposal_wrappers_bind_provenance_in_the_original_transaction() -> None:
    sql = _sql()

    assert "propose_planner_action_plan_with_timing_v1" in sql
    assert "propose_deadline_plan_with_timing_v1" in sql
    assert "public.propose_planner_action_plan_v1(" in sql
    assert "public.propose_deadline_plan_v1(" in sql
    assert "set_config('mylifegraph.timing_provenance_write', 'v1', true)" in sql
    assert sql.count("get diagnostics changed = row_count") == 2
    assert sql.count("grant execute on function public.propose_") == 2


def test_confirmation_rechecks_permission_and_provenance_is_immutable() -> None:
    sql = _sql()

    assert "private.guard_planning_timing_provenance_v1" in sql
    assert "Planning timing provenance is immutable." in sql
    assert "old.state = 'proposed'" in sql
    assert "new.state = 'active'" in sql
    assert "personal_pattern_analysis_enabled" in sql
    assert "learned_focus_planning_enabled" in sql
    assert "for share" in sql
    assert "using errcode = 'PT409'" in sql


def test_rpc_guard_keeps_additive_timing_outside_strict_v1_payloads() -> None:
    sql = _rpc_guard_sql()

    assert "p_revision_payload - 'timing_preference'" in sql
    assert "p_proposal - 'timing_preference'" in sql
    assert sql.count("if changed = 0 and not exists") == 2
    assert "from public.planner_action_plan_revisions" in sql
    assert "from public.deadline_plan_revisions" in sql
    assert sql.count("is not distinct from") >= 10
    assert sql.count("grant execute on function public.propose_") == 2


def test_confirmation_clock_skew_cannot_move_persisted_timestamps_backwards() -> None:
    sql = _confirmation_time_guard_sql()

    assert "confirm_planner_action_plan_v1_without_timestamp_guard" in sql
    assert "confirm_deadline_plan_v1_without_timestamp_guard" in sql
    assert sql.count(
        "perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))"
    ) == 2
    assert sql.count("greatest(p_now, coalesce(max(stamp), p_now))") == 2
    for table in (
        "public.planner_task_blocks",
        "public.planner_habit_slots",
        "public.deadline_plan_blocks",
    ):
        assert table in sql
    assert sql.count("grant execute on function public.confirm_") == 2


def test_learned_evidence_can_record_actual_setup_allocation_fallback() -> None:
    sql = _setup_fallback_provenance_sql()

    assert sql.count("drop constraint") == 2
    assert "planner_action_revision_timing_check" in sql
    assert "deadline_plan_revision_timing_check" in sql
    assert "target_payload ->> 'kind' = 'task'" in sql
    assert "and not timing_fell_back_to_setup" not in sql
    assert sql.count("timing_warning is null") >= 2


def test_account_export_keeps_deadline_timing_provenance() -> None:
    revision_export = next(
        table
        for table in ACCOUNT_EXPORT_TABLES
        if table.name == "deadline_plan_revisions"
    )

    for field in (
        "timing_preference_source",
        "timing_preference_window",
        "timing_evidence_count",
        "timing_evidence_starts_on",
        "timing_evidence_ends_on",
        "timing_evidence_fingerprint",
        "timing_fell_back_to_setup",
        "timing_warning",
    ):
        assert field in revision_export.select
