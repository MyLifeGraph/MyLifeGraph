from datetime import UTC, date, datetime
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.models.planner import PlannerTaskTarget
from app.models.planning_timing import PlanningTimingProvenance
from app.repositories.planning_writes import (
    DeadlineProposalPayload,
    DeadlineProposalWrite,
    PlannerProposalWrite,
    PlannerRevisionWrite,
)


PLAN_ID = UUID("10000000-0000-4000-8000-000000000001")
TARGET_ID = UUID("20000000-0000-4000-8000-000000000001")


def _deadline_payload() -> DeadlineProposalPayload:
    return DeadlineProposalPayload(
        plan_id=PLAN_ID,
        base_revision=0,
        kind="exam",
        title="Algorithms",
        deadline_at=datetime(2026, 7, 30, 12, tzinfo=UTC),
        estimated_total_minutes=120,
        credited_prior_minutes=0,
        preferred_session_minutes=45,
        max_daily_minutes=120,
        planning_start_on=date(2026, 7, 20),
        buffer_days=1,
        source_kind="manual",
        source_calendar_event_id=None,
        source_calendar_event_fingerprint=None,
        use_calendar_availability=False,
        timezone="UTC",
        best_energy_window="morning",
        availability_connection_id=None,
        availability_import_id=None,
        planning_fingerprint="a" * 64,
        timing_preference=PlanningTimingProvenance(source="setup"),
        study_setup_revision=None,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=120,
        planned_minutes=90,
        unscheduled_minutes=30,
    )


def _task_target() -> PlannerTaskTarget:
    return PlannerTaskTarget.model_validate(
        {
            "kind": "task",
            "operation": "create",
            "target_id": str(TARGET_ID),
            "expected_updated_at": None,
            "title": "Write report",
            "description": None,
            "priority": "high",
            "estimated_minutes": 60,
            "deadline_at": "2026-07-22T12:00:00Z",
            "preferred_session_minutes": 30,
            "use_study_rhythm": False,
        },
    )


def test_deadline_write_serializes_one_exact_typed_rpc_payload() -> None:
    write = DeadlineProposalWrite(
        proposal=_deadline_payload(),
        blocks=(),
    )

    payload = write.proposal_json()

    assert payload["plan_id"] == str(PLAN_ID)
    assert payload["deadline_at"] == "2026-07-30T12:00:00Z"
    assert payload["planning_start_on"] == "2026-07-20"
    assert payload["timing_preference"]["source"] == "setup"
    assert write.blocks_json() == []


def test_planner_write_rejects_cross_component_target_drift() -> None:
    target = _task_target()
    revision = PlannerRevisionWrite(
        revision=1,
        base_revision=0,
        target=target,
        timezone="UTC",
        best_energy_window="morning",
        planning_start_on=date(2026, 7, 20),
        planning_fingerprint="b" * 64,
        timing_preference=PlanningTimingProvenance(source="setup"),
        calendar_import_id=None,
        study_setup_revision=None,
        recovery_minutes=0,
        planned_minutes=0,
        unscheduled_minutes=60,
    )

    with pytest.raises(ValidationError, match="components are inconsistent"):
        PlannerProposalWrite(
            target_kind="task",
            target_id=UUID("30000000-0000-4000-8000-000000000001"),
            target=target,
            revision=revision,
            task_blocks=(),
            habit_slots=(),
        )


def test_planner_revision_rejects_skipped_or_duplicate_revision() -> None:
    target = _task_target()

    with pytest.raises(ValidationError, match="advance its base exactly once"):
        PlannerRevisionWrite(
            revision=3,
            base_revision=1,
            target=target,
            timezone="UTC",
            best_energy_window="morning",
            planning_start_on=date(2026, 7, 20),
            planning_fingerprint="b" * 64,
            timing_preference=PlanningTimingProvenance(source="setup"),
            calendar_import_id=None,
            study_setup_revision=None,
            recovery_minutes=0,
            planned_minutes=0,
            unscheduled_minutes=60,
        )
