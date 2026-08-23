import asyncio
import hashlib
import json
from dataclasses import replace
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest

from app.models.deadline_plans import (
    DeadlinePlanBlock,
    DeadlinePlanDetail,
    DeadlinePlanIdentity,
    DeadlinePlanProgress,
    DeadlinePlanRevision,
    DeadlinePlansResponse,
)
from app.models.planner import (
    PlannerActionPlan,
    PlannerActionProposalRequest,
    PlannerActionRevision,
    PlannerHabitSlot,
    PlannerOverviewResponse,
)
from app.models.planning_timing import PlanningTimingProvenance
from app.repositories.planner_repository import (
    PlannerAvailabilityContext,
    PlannerCalendarProjection,
    PlannerOverviewContext,
    PlannerProjection,
    SupabasePlannerRepository,
)
from app.repositories.today_planner_read_repository import (
    SupabaseTodayPlannerReadRepository,
)
from app.services.planner_service import (
    PlannerConflictError,
    PlannerNotFoundError,
    PlannerService,
    _add_setup_commitments,
    _attention_items,
    _course_selection_attention,
    build_planner_overview,
)
from app.services.planner_builder import (
    _AuthoritativeInterval,
    _attention_horizon,
    _deadline_revision_conflict_sources,
    _preparation_attention_items,
    _target_overview_items,
)
from app.services.today_planner_read_context import TodayPlannerReadContextFactory


NOW = datetime(2026, 7, 20, 7, tzinfo=UTC)
USER_ID = "planner-owner"
PLAN_ID = UUID("10000000-0000-4000-8000-000000000001")
TARGET_ID = UUID("20000000-0000-4000-8000-000000000001")
REQUEST_ID = UUID("30000000-0000-4000-8000-000000000001")
IMPORT_ID = UUID("40000000-0000-4000-8000-000000000001")


class Repository:
    def __init__(self, context: PlannerAvailabilityContext) -> None:
        self.context = context
        self.projection = PlannerProjection([], [], [], [])
        self.requests: dict[UUID, dict[str, object]] = {}
        self.persist_calls = 0

    async def get_request_identity(self, *, request_id):
        return self.requests.get(request_id)

    async def load_projection(self, *, user_id, plan_id):
        assert user_id == USER_ID
        if plan_id is None or not self.projection.plans:
            return self.projection
        if str(self.projection.plans[0]["id"]) == str(plan_id):
            return self.projection
        return PlannerProjection([], [], [], [])

    async def load_availability_context(
        self,
        *,
        user_id,
        plan_id,
        target_kind,
        target_id,
        starts_on,
        ends_on,
    ):
        assert user_id == USER_ID
        assert plan_id == PLAN_ID
        assert target_id == TARGET_ID
        assert target_kind in {"task", "habit"}
        assert starts_on <= ends_on
        return self.context

    async def persist_proposal(self, **values):
        self.persist_calls += 1
        write = values["write"]
        values = {
            **values,
            "target_kind": write.target_kind,
            "target_id": write.target_id,
            "target_payload": write.target_json(),
            "revision_payload": write.revision_json(),
            "task_blocks": write.task_blocks_json(),
            "habit_slots": write.habit_slots_json(),
        }
        now = values["now"]
        revision = values["revision_payload"]
        timing = revision["timing_preference"]
        self.projection = PlannerProjection(
            plans=[
                {
                    "id": str(values["plan_id"]),
                    "user_id": values["user_id"],
                    "target_kind": values["target_kind"],
                    "target_id": str(values["target_id"]),
                    "status": "draft",
                    "current_revision": 0,
                    "latest_revision": revision["revision"],
                    "attention_reasons": [],
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                },
            ],
            revisions=[
                {
                    "id": "50000000-0000-4000-8000-000000000001",
                    "user_id": values["user_id"],
                    "plan_id": str(values["plan_id"]),
                    "revision": revision["revision"],
                    "base_revision": revision["base_revision"],
                    "state": "proposed",
                    "target_payload": values["target_payload"],
                    "timezone": revision["timezone"],
                    "best_energy_window": revision["best_energy_window"],
                    "planning_start_on": revision["planning_start_on"],
                    "planning_fingerprint": revision["planning_fingerprint"],
                    "timing_preference_source": timing["source"],
                    "timing_preference_window": timing["window"],
                    "timing_evidence_count": timing["evidence_count"],
                    "timing_evidence_starts_on": timing["evidence_starts_on"],
                    "timing_evidence_ends_on": timing["evidence_ends_on"],
                    "timing_evidence_fingerprint": timing["evidence_fingerprint"],
                    "timing_fell_back_to_setup": timing["fell_back_to_setup"],
                    "timing_warning": timing["warning"],
                    "calendar_import_id": revision["calendar_import_id"],
                    "study_setup_revision": revision["study_setup_revision"],
                    "recovery_minutes": revision["recovery_minutes"],
                    "planned_minutes": revision["planned_minutes"],
                    "unscheduled_minutes": revision["unscheduled_minutes"],
                    "created_at": now.isoformat(),
                    "activated_at": None,
                    "superseded_at": None,
                },
            ],
            task_blocks=[
                {
                    **block,
                    "user_id": values["user_id"],
                    "plan_id": str(values["plan_id"]),
                    "revision": revision["revision"],
                    "state": "proposed",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                }
                for block in values["task_blocks"]
            ],
            habit_slots=[
                {
                    **slot,
                    "user_id": values["user_id"],
                    "plan_id": str(values["plan_id"]),
                    "revision": revision["revision"],
                    "state": "proposed",
                    "created_at": now.isoformat(),
                    "updated_at": now.isoformat(),
                }
                for slot in values["habit_slots"]
            ],
        )
        self.requests[values["request_id"]] = {
            "user_id": values["user_id"],
            "operation": "proposal",
            "resource_id": str(values["plan_id"]),
            "request_fingerprint": values["request_fingerprint"],
        }
        return {"status": "draft"}


class Timing:
    def __init__(
        self,
        provenance: PlanningTimingProvenance,
        *,
        confirmation_allowed: bool = True,
    ) -> None:
        self.provenance = provenance
        self.confirmation_allowed = confirmation_allowed
        self.resolve_calls = 0
        self.confirm_calls = 0

    async def resolve(self, *, user_id: str) -> PlanningTimingProvenance:
        assert user_id == USER_ID
        self.resolve_calls += 1
        return self.provenance

    async def learned_confirmation_is_allowed(self, *, user_id: str) -> bool:
        assert user_id == USER_ID
        self.confirm_calls += 1
        return self.confirmation_allowed


def _context(
    *,
    preference: dict[str, object] | None = None,
    calendar: PlannerCalendarProjection | None = None,
    study_setup: dict[str, object] | None = None,
    schedule_items: list[dict[str, object]] | None = None,
) -> PlannerAvailabilityContext:
    return PlannerAvailabilityContext(
        timezone="UTC",
        best_energy_window="morning",
        preference=preference,
        calendar=calendar
        or PlannerCalendarProjection(
            available=False,
            connection_id=None,
            import_id=None,
            timed_events=[],
            all_day_events=[],
        ),
        schedule_items=schedule_items or [],
        commitments=[],
        task_blocks=[],
        habit_slots=[],
        deadline_blocks=[],
        target=None,
        study_setup=study_setup,
    )


def _task_request(**target_overrides: object) -> PlannerActionProposalRequest:
    target = {
        "kind": "task",
        "operation": "create",
        "target_id": str(TARGET_ID),
        "expected_updated_at": None,
        "title": "Write project report",
        "description": None,
        "priority": "high",
        "estimated_minutes": 125,
        "deadline_at": "2026-07-22T12:00:00+00:00",
        "preferred_session_minutes": 50,
    }
    target.update(target_overrides)
    return PlannerActionProposalRequest.model_validate_json(
        json.dumps(
            {
                "request_id": str(REQUEST_ID),
                "plan_id": str(PLAN_ID),
                "base_revision": 0,
                "planning_start_on": "2026-07-20",
                "target": target,
            },
        ),
    )


def _habit_request() -> PlannerActionProposalRequest:
    return PlannerActionProposalRequest.model_validate_json(
        json.dumps(
            {
                "request_id": str(REQUEST_ID),
                "plan_id": str(PLAN_ID),
                "base_revision": 0,
                "planning_start_on": "2026-07-20",
                "target": {
                    "kind": "habit",
                    "operation": "create",
                    "target_id": str(TARGET_ID),
                    "expected_updated_at": None,
                    "title": "Review notes",
                    "description": None,
                    "cadence": {
                        "kind": "weekly_target",
                        "scheduled_weekdays": [],
                        "weekly_target": 3,
                    },
                    "duration_minutes": 30,
                },
            },
        ),
    )


def _activate_revision(
    revision: PlannerActionRevision,
    *,
    planned_blocks: int | None = None,
) -> PlannerActionRevision:
    task_blocks = revision.task_blocks
    unscheduled = revision.unscheduled_minutes
    if planned_blocks is not None:
        retained = task_blocks[:planned_blocks]
        planned = sum(block.planned_minutes for block in retained)
        unscheduled += revision.planned_minutes - planned
        task_blocks = retained
    else:
        planned = revision.planned_minutes
    return PlannerActionRevision.model_validate_json(
        json.dumps(
            {
                **revision.model_dump(),
                "state": "active",
                "planned_minutes": planned,
                "unscheduled_minutes": unscheduled,
                "task_blocks": [
                    {**block.model_dump(), "state": "active"} for block in task_blocks
                ],
                "habit_slots": [
                    {**slot.model_dump(), "state": "active"}
                    for slot in revision.habit_slots
                ],
                "activated_at": NOW,
            },
            default=lambda value: (
                value.isoformat() if hasattr(value, "isoformat") else str(value)
            ),
        ),
    )


def _active_plan(
    pending: PlannerActionRevision,
    *,
    planned_blocks: int | None = None,
    attention_reasons: list[str] | None = None,
) -> PlannerActionPlan:
    active = _activate_revision(pending, planned_blocks=planned_blocks)
    reasons = attention_reasons or []
    return PlannerActionPlan(
        id=PLAN_ID,
        target_kind=active.target.kind,
        target_id=active.target.target_id,
        status=("active" if active.planned_minutes else "unscheduled"),
        current_revision=active.revision,
        latest_revision=active.revision,
        needs_attention=bool(reasons),
        attention_reasons=reasons,
        active_revision=active,
        pending_revision=None,
    )


def _overview_context(
    *,
    tasks: list[dict[str, object]] | None = None,
    habits: list[dict[str, object]] | None = None,
    plans: PlannerProjection | None = None,
    schedule_items: list[dict[str, object]] | None = None,
    commitments: list[dict[str, object]] | None = None,
    calendar: PlannerCalendarProjection | None = None,
    preference: dict[str, object] | None = None,
) -> PlannerOverviewContext:
    return PlannerOverviewContext(
        timezone="UTC",
        best_energy_window="morning",
        preference=preference,
        calendar=calendar
        or PlannerCalendarProjection(
            available=False,
            connection_id=None,
            import_id=None,
            timed_events=[],
            all_day_events=[],
        ),
        schedule_items=schedule_items or [],
        commitments=commitments or [],
        tasks=tasks or [],
        habits=habits or [],
        plans=plans or PlannerProjection([], [], [], []),
    )


def _task_row(
    *,
    target_id: UUID = TARGET_ID,
    metadata: dict[str, object] | None = None,
    source: str = "manual",
    complete: bool = True,
) -> dict[str, object]:
    return {
        "id": str(target_id),
        "title": "Write project report",
        "description": None,
        "status": "todo",
        "priority": "high",
        "estimated_minutes": 125 if complete else None,
        "deadline": "2026-07-22T12:00:00+00:00" if complete else None,
        "source": source,
        "metadata": (
            metadata
            if metadata is not None
            else ({"preferred_session_minutes": 50} if complete else {})
        ),
        "created_at": "2026-07-19T06:00:00+00:00",
        "updated_at": "2026-07-20T06:00:00+00:00",
    }


def _habit_row(
    *,
    target_id: UUID = TARGET_ID,
    managed_by: str | None = None,
    duration: int | None = None,
) -> dict[str, object]:
    metadata: dict[str, object] = {
        "cadence": "weekly_target",
        "lifecycle": "active",
    }
    if managed_by is not None:
        metadata["managed_by"] = managed_by
    if duration is not None:
        metadata["planner_duration_minutes"] = duration
    return {
        "id": str(target_id),
        "title": "Review notes",
        "description": "Read the exact course notes.",
        "frequency": "weekly",
        "target": 3,
        "active": True,
        "metadata": metadata,
        "created_at": "2026-07-19T07:00:00+00:00",
        "updated_at": "2026-07-20T06:00:00+00:00",
    }


def _active_habit_projection_for_slot(
    *,
    weekday: int,
    starts_at: time,
    ends_at: time,
) -> PlannerProjection:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_habit_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    return PlannerProjection(
        plans=[
            {
                **row,
                "status": "active",
                "current_revision": 1,
            }
            for row in repository.projection.plans
        ],
        revisions=[
            {
                **row,
                "state": "active",
                "activated_at": NOW.isoformat(),
            }
            for row in repository.projection.revisions
        ],
        task_blocks=[],
        habit_slots=[
            {
                **row,
                "state": "active",
                **(
                    {
                        "weekday": weekday,
                        "starts_at": starts_at.isoformat(),
                        "ends_at": ends_at.isoformat(),
                    }
                    if index == 0
                    else {}
                ),
            }
            for index, row in enumerate(repository.projection.habit_slots)
        ],
    )


def test_task_proposal_splits_sessions_and_replays_without_another_write() -> None:
    repository = Repository(_context())
    service = PlannerService(repository=repository, now=lambda: NOW)

    response = asyncio.run(service.propose(user_id=USER_ID, request=_task_request()))
    replay = asyncio.run(service.propose(user_id=USER_ID, request=_task_request()))

    assert response.plan.pending_revision is not None
    assert [
        block.planned_minutes for block in response.plan.pending_revision.task_blocks
    ] == [50, 50, 25]
    assert response.plan.pending_revision.planned_minutes == 125
    assert response.plan.pending_revision.unscheduled_minutes == 0
    assert response.plan.pending_revision.study_setup_revision is None
    assert response.plan.pending_revision.recovery_minutes == 0
    assert all(
        block.reserved_ends_at == block.ends_at
        for block in response.plan.pending_revision.task_blocks
    )
    assert replay == response
    assert repository.persist_calls == 1


def test_task_preview_persists_exact_learned_timing_and_habit_does_not_use_it() -> None:
    provenance = PlanningTimingProvenance(
        source="learned_personal_pattern",
        window="18-23",
        evidence_count=24,
        evidence_starts_on=date(2026, 6, 1),
        evidence_ends_on=date(2026, 7, 19),
        evidence_fingerprint="a" * 64,
    )
    timing = Timing(provenance)
    repository = Repository(_context())
    service = PlannerService(
        repository=repository,
        learned_timing=timing,
        now=lambda: NOW,
    )

    response = asyncio.run(
        service.propose(
            user_id=USER_ID,
            request=_task_request(
                deadline_at="2026-07-22T23:00:00+00:00",
            ),
        ),
    )

    pending = response.plan.pending_revision
    assert pending is not None
    assert pending.timing_preference == provenance
    assert pending.task_blocks[0].starts_at.hour == 18
    assert timing.resolve_calls == 1

    habit_timing = Timing(provenance)
    habit_repository = Repository(_context())
    habit_service = PlannerService(
        repository=habit_repository,
        learned_timing=habit_timing,
        now=lambda: NOW,
    )
    habit_response = asyncio.run(
        habit_service.propose(user_id=USER_ID, request=_habit_request()),
    )
    assert habit_response.plan.pending_revision is not None
    assert habit_response.plan.pending_revision.timing_preference.source == "setup"
    assert habit_timing.resolve_calls == 0


def test_task_preview_records_when_allocation_falls_back_to_setup_timing() -> None:
    provenance = PlanningTimingProvenance(
        source="learned_personal_pattern",
        window="18-23",
        evidence_count=24,
        evidence_starts_on=date(2026, 6, 1),
        evidence_ends_on=date(2026, 7, 19),
        evidence_fingerprint="a" * 64,
    )
    repository = Repository(
        _context(
            schedule_items=[
                {
                    "weekday": 1,
                    "starts_at": "18:00:00",
                    "ends_at": "23:00:00",
                },
            ],
        ),
    )
    service = PlannerService(
        repository=repository,
        learned_timing=Timing(provenance),
        now=lambda: NOW,
    )

    response = asyncio.run(
        service.propose(
            user_id=USER_ID,
            request=_task_request(
                estimated_minutes=50,
                deadline_at="2026-07-20T20:00:00+00:00",
                preferred_session_minutes=50,
            ),
        ),
    )

    pending = response.plan.pending_revision
    assert pending is not None
    assert pending.task_blocks[0].starts_at.hour < 18
    assert pending.timing_preference.source == "learned_personal_pattern"
    assert pending.timing_preference.window == "18-23"
    assert pending.timing_preference.fell_back_to_setup is True
    assert pending.timing_preference.evidence_fingerprint == "a" * 64


def test_learned_preview_cannot_confirm_after_permission_is_disabled() -> None:
    provenance = PlanningTimingProvenance(
        source="learned_personal_pattern",
        window="18-23",
        evidence_count=24,
        evidence_starts_on=date(2026, 6, 1),
        evidence_ends_on=date(2026, 7, 19),
        evidence_fingerprint="a" * 64,
    )
    timing = Timing(provenance, confirmation_allowed=False)
    repository = Repository(_context())
    service = PlannerService(
        repository=repository,
        learned_timing=timing,
        now=lambda: NOW,
    )
    asyncio.run(service.propose(user_id=USER_ID, request=_task_request()))

    request = type(
        "Mutation",
        (),
        {"request_id": REQUEST_ID, "expected_revision": 1},
    )()
    try:
        asyncio.run(
            service.confirm(
                user_id=USER_ID,
                plan_id=PLAN_ID,
                request=request,
            ),
        )
    except PlannerConflictError as error:
        assert "turned off" in str(error)
    else:
        raise AssertionError("Disabled learned timing confirmation was accepted.")


def test_marked_task_uses_exact_current_study_rhythm_and_recovery() -> None:
    repository = Repository(
        _context(
            study_setup={
                "setup_revision": 7,
                "focus_minutes": 45,
                "recovery_minutes": 10,
            },
        ),
    )
    service = PlannerService(repository=repository, now=lambda: NOW)

    response = asyncio.run(
        service.propose(
            user_id=USER_ID,
            request=_task_request(
                preferred_session_minutes=45,
                use_study_rhythm=True,
            ),
        ),
    )

    revision = response.plan.pending_revision
    assert revision is not None
    assert revision.study_setup_revision == 7
    assert revision.recovery_minutes == 10
    assert [block.planned_minutes for block in revision.task_blocks] == [
        45,
        45,
        35,
    ]
    assert all(block.recovery_minutes == 10 for block in revision.task_blocks)
    assert all(
        block.reserved_ends_at == block.ends_at + timedelta(minutes=10)
        for block in revision.task_blocks
    )
    assert revision.planned_minutes == 125
    assert revision.unscheduled_minutes == 0


def test_course_selection_attention_is_local_date_bounded_and_completed() -> None:
    study_setup = {
        "next_semester": {
            "course_selection_starts_on": "2026-08-15",
            "course_selection_ends_on": "2026-09-15",
            "course_selection_completed": False,
        },
    }

    assert (
        _course_selection_attention(
            study_setup,
            local_date=date(2026, 8, 14),
        )
        == []
    )
    open_items = _course_selection_attention(
        study_setup,
        local_date=date(2026, 8, 15),
    )
    overdue_items = _course_selection_attention(
        study_setup,
        local_date=date(2026, 9, 16),
    )
    completed_items = _course_selection_attention(
        {
            "next_semester": {
                **study_setup["next_semester"],
                "course_selection_completed": True,
            },
        },
        local_date=date(2026, 9, 16),
    )

    assert [item.kind for item in open_items] == ["course_selection_open"]
    assert open_items[0].target == "study_setup"
    assert [item.kind for item in overdue_items] == [
        "course_selection_overdue",
    ]
    assert completed_items == []


def test_task_without_all_scheduling_inputs_stays_explicitly_unscheduled() -> None:
    repository = Repository(_context())
    service = PlannerService(repository=repository, now=lambda: NOW)

    response = asyncio.run(
        service.propose(
            user_id=USER_ID,
            request=_task_request(
                deadline_at=None,
                preferred_session_minutes=None,
            ),
        ),
    )

    revision = response.plan.pending_revision
    assert revision is not None
    assert revision.task_blocks == []
    assert revision.planned_minutes == 0
    assert revision.unscheduled_minutes == 125


def test_weekly_target_habit_gets_stable_slots_for_exact_target() -> None:
    repository = Repository(_context())
    service = PlannerService(repository=repository, now=lambda: NOW)

    response = asyncio.run(service.propose(user_id=USER_ID, request=_habit_request()))

    revision = response.plan.pending_revision
    assert revision is not None
    assert [slot.weekday for slot in revision.habit_slots] == [1, 3, 5]
    assert {slot.duration_minutes for slot in revision.habit_slots} == {30}
    assert revision.planned_minutes == 90
    assert revision.unscheduled_minutes == 0


def test_calendar_consent_binds_preview_to_current_import() -> None:
    calendar = PlannerCalendarProjection(
        available=True,
        connection_id=UUID("60000000-0000-4000-8000-000000000001"),
        import_id=IMPORT_ID,
        timed_events=[
            {
                "id": "70000000-0000-4000-8000-000000000001",
                "starts_at": "2026-07-20T08:00:00+00:00",
                "ends_at": "2026-07-20T13:00:00+00:00",
                "busy_status": "busy",
            },
        ],
        all_day_events=[],
    )
    repository = Repository(
        _context(
            preference={"use_calendar_busy_time": True},
            calendar=calendar,
        ),
    )
    service = PlannerService(repository=repository, now=lambda: NOW)

    response = asyncio.run(service.propose(user_id=USER_ID, request=_task_request()))

    revision = response.plan.pending_revision
    assert revision is not None
    assert revision.calendar_import_id == IMPORT_ID
    assert all(
        not (
            block.starts_at < datetime(2026, 7, 20, 13, tzinfo=UTC)
            and block.ends_at > datetime(2026, 7, 20, 8, tzinfo=UTC)
        )
        for block in revision.task_blocks
    )
    assert len(revision.planning_fingerprint) == hashlib.sha256().digest_size * 2


def test_overview_marks_preview_stale_when_calendar_preference_changes() -> None:
    repository = Repository(_context())
    service = PlannerService(repository=repository, now=lambda: NOW)
    response = asyncio.run(service.propose(user_id=USER_ID, request=_task_request()))

    context = PlannerOverviewContext(
        timezone="UTC",
        best_energy_window="morning",
        preference={"use_calendar_busy_time": True},
        calendar=PlannerCalendarProjection(
            available=True,
            connection_id=UUID("60000000-0000-4000-8000-000000000001"),
            import_id=IMPORT_ID,
            timed_events=[],
            all_day_events=[],
        ),
        schedule_items=[],
        commitments=[],
        tasks=[],
        habits=[],
        plans=repository.projection,
    )

    attention = _attention_items(
        context=context,
        plans=[response.plan],
        days=[date(2026, 7, 20) + timedelta(days=value) for value in range(28)],
        zone=ZoneInfo("UTC"),
    )

    assert [item.kind for item in attention] == ["stale_preview"]
    assert "calendar setting" in attention[0].detail


def test_v2_stale_calendar_import_is_unavailable_and_marks_bound_preview() -> None:
    repository = Repository(
        _context(
            preference={"use_calendar_busy_time": True},
            calendar=PlannerCalendarProjection(
                available=True,
                connection_id=UUID("60000000-0000-4000-8000-000000000001"),
                import_id=IMPORT_ID,
                timed_events=[],
                all_day_events=[],
            ),
        ),
    )
    asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    context = _overview_context(
        plans=repository.projection,
        preference={"use_calendar_busy_time": True},
        calendar=PlannerCalendarProjection(
            available=False,
            connection_id=UUID("60000000-0000-4000-8000-000000000001"),
            import_id=None,
            timed_events=[],
            all_day_events=[],
        ),
    )

    overview = build_planner_overview(
        generated_at=NOW,
        context=context,
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )

    assert overview.preferences.calendar_available is False
    assert overview.preferences.current_calendar_import_id is None
    calendar_attention = [
        item
        for item in overview.needs_attention
        if item.id.startswith(f"{PLAN_ID}:calendar-stale")
    ]
    assert len(calendar_attention) == 1
    assert calendar_attention[0].kind == "stale_preview"


def test_v2_pending_stale_reason_is_ignored_when_current_facts_are_fresh() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    fresh_target = pending.target.model_copy(
        update={
            "operation": "update",
            "expected_updated_at": datetime(2026, 7, 20, 6, tzinfo=UTC),
        },
    )
    plan = response.plan.model_copy(
        update={
            "needs_attention": True,
            "attention_reasons": [
                "target_changed",
                "calendar_changed",
                "timezone_changed",
                "study_rhythm_changed",
            ],
            "pending_revision": pending.model_copy(update={"target": fresh_target}),
        },
    )
    context = _overview_context(tasks=[_task_row()])

    attention = _attention_items(
        context=context,
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    assert [item for item in attention if item.kind == "stale_preview"] == []
    assert [item for item in attention if ":persisted:" in item.id] == []


def test_v2_current_pending_target_drift_is_still_reported() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    stale_target = pending.target.model_copy(
        update={
            "operation": "update",
            "expected_updated_at": datetime(2026, 7, 20, 5, tzinfo=UTC),
        },
    )
    plan = response.plan.model_copy(
        update={
            "needs_attention": True,
            "attention_reasons": ["target_changed"],
            "pending_revision": pending.model_copy(update={"target": stale_target}),
        },
    )

    attention = _attention_items(
        context=_overview_context(tasks=[_task_row()]),
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    stale = [item for item in attention if item.kind == "stale_preview"]
    assert [(item.id, item.plan_id) for item in stale] == [
        (f"{PLAN_ID}:target-stale:1", PLAN_ID),
    ]


def test_v2_current_pending_timezone_drift_is_reported() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    fresh_target = pending.target.model_copy(
        update={
            "operation": "update",
            "expected_updated_at": datetime(2026, 7, 20, 6, tzinfo=UTC),
        },
    )
    plan = response.plan.model_copy(
        update={
            "pending_revision": pending.model_copy(
                update={"target": fresh_target, "timezone": "Europe/Berlin"},
            ),
        },
    )

    attention = _attention_items(
        context=_overview_context(tasks=[_task_row()]),
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    assert [item.id for item in attention if item.kind == "stale_preview"] == [
        f"{PLAN_ID}:timezone-stale:1",
    ]


@pytest.mark.parametrize(
    ("reason", "expected_kind"),
    [
        ("target_changed", "stale_preview"),
        ("calendar_changed", "stale_preview"),
        ("timezone_changed", "stale_preview"),
        ("study_rhythm_changed", "study_rhythm_changed"),
    ],
)
def test_v2_persisted_stale_reason_remains_visible_without_pending_preview(
    reason: str,
    expected_kind: str,
) -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    plan = _active_plan(pending).model_copy(
        update={"needs_attention": True, "attention_reasons": [reason]},
    )

    attention = _attention_items(
        context=_overview_context(tasks=[_task_row()]),
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    persisted = [item for item in attention if ":persisted:" in item.id]
    assert [(item.id, item.kind, item.plan_id) for item in persisted] == [
        (f"{PLAN_ID}:persisted:{reason}", expected_kind, PLAN_ID),
    ]


def test_overview_builder_is_pure_and_independent_of_repository() -> None:
    context = PlannerOverviewContext(
        timezone="UTC",
        best_energy_window="morning",
        preference=None,
        calendar=PlannerCalendarProjection(
            available=False,
            connection_id=None,
            import_id=None,
            timed_events=[],
            all_day_events=[],
        ),
        schedule_items=[],
        commitments=[],
        tasks=[],
        habits=[],
        plans=PlannerProjection([], [], [], []),
    )
    deadline_response = DeadlinePlansResponse(
        contract_version="deadline-plan-v1",
        origin="authenticated_backend",
        plans=[],
    )

    first = build_planner_overview(
        generated_at=NOW,
        context=context,
        deadline_response=deadline_response,
    )
    second = build_planner_overview(
        generated_at=NOW,
        context=context,
        deadline_response=deadline_response,
    )

    assert first == second
    assert first.local_date == NOW.date()
    assert len(first.days) == 7


def test_v2_zero_minute_plan_is_no_time_not_duplicate_attention() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision, planned_blocks=0)
    context = _overview_context(tasks=[_task_row()])

    _, _, tasks, _ = _target_overview_items(context=context, plans=[plan])
    attention = _attention_items(
        context=context,
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    assert [(task.title, task.reason) for task in tasks] == [
        ("Write project report", "no_time_available"),
    ]
    assert [item for item in attention if item.kind == "unscheduled"] == []


def test_v2_partial_plan_reports_exact_active_unplaced_minutes_only() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision, planned_blocks=2)
    context = _overview_context(tasks=[_task_row()])

    _, _, tasks, _ = _target_overview_items(context=context, plans=[plan])
    attention = _attention_items(
        context=context,
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    assert tasks == []
    unplaced = [item for item in attention if item.kind == "unscheduled"]
    assert len(unplaced) == 1
    assert unplaced[0].unplaced_minutes == 25
    assert unplaced[0].detail == "25 minutes could not be placed."


def test_v2_released_task_reason_wins_when_inputs_are_also_missing() -> None:
    plan = PlannerActionPlan(
        id=PLAN_ID,
        target_kind="task",
        target_id=TARGET_ID,
        status="unscheduled",
        current_revision=0,
        latest_revision=1,
        needs_attention=True,
        attention_reasons=["target_released"],
        active_revision=None,
        pending_revision=None,
    )
    context = _overview_context(tasks=[_task_row(complete=False)])

    _, _, tasks, _ = _target_overview_items(context=context, plans=[plan])
    attention = _attention_items(
        context=context,
        plans=[plan],
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
    )

    assert tasks[0].reason == "released"
    assert all("released" not in item.detail.casefold() for item in attention)


def test_v2_filters_deadline_managed_tasks_from_unscheduled_tasks() -> None:
    metadata_id = UUID("20000000-0000-4000-8000-000000000002")
    context = _overview_context(
        tasks=[
            _task_row(source="deadline-plan-v1"),
            _task_row(
                target_id=metadata_id,
                metadata={
                    "contract_version": "deadline-plan-v1",
                    "preferred_session_minutes": 50,
                },
            ),
        ],
    )

    targets, _, tasks, _ = _target_overview_items(context=context, plans=[])

    assert targets == []
    assert tasks == []


def test_v2_task_targets_include_authoritative_scheduled_task_snapshot() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision)
    row = _task_row()
    row.update(
        {
            "title": "Current scheduled task",
            "description": "Authoritative description",
            "priority": "critical",
            "estimated_minutes": 90,
        },
    )

    targets, habits, tasks, history = _target_overview_items(
        context=_overview_context(tasks=[row]),
        plans=[plan],
    )

    assert habits == []
    assert tasks == []
    assert history == []
    assert len(targets) == 1
    assert targets[0].id == TARGET_ID
    assert targets[0].title == "Current scheduled task"
    assert targets[0].description == "Authoritative description"
    assert targets[0].priority == "critical"
    assert targets[0].estimated_minutes == 90
    assert targets[0].expected_updated_at == datetime(
        2026,
        7,
        20,
        6,
        tzinfo=UTC,
    )


def test_v2_task_targets_keep_repository_order_while_unscheduled_rows_sort() -> None:
    first_id = UUID("20000000-0000-4000-8000-000000000020")
    second_id = UUID("20000000-0000-4000-8000-000000000021")
    first = _task_row(target_id=first_id)
    first["title"] = "Zulu Task"
    second = _task_row(target_id=second_id)
    second["title"] = "Alpha Task"

    targets, _, tasks, _ = _target_overview_items(
        context=_overview_context(tasks=[first, second]),
        plans=[],
    )

    assert [item.id for item in targets] == [first_id, second_id]
    assert [item.id for item in tasks] == [second_id, first_id]
    assert {item.reason for item in tasks} == {"not_planned"}
    assert {item.id for item in tasks} <= {item.id for item in targets}


def test_v2_missing_task_inputs_precede_not_planned_without_release() -> None:
    _, _, tasks, _ = _target_overview_items(
        context=_overview_context(tasks=[_task_row(complete=False)]),
        plans=[],
    )

    assert tasks[0].reason == "missing_scheduling_inputs"


def test_v2_projects_all_active_habits_with_ownership_and_real_slots() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_habit_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision)
    manual_id = UUID("20000000-0000-4000-8000-000000000002")
    context = _overview_context(
        habits=[
            _habit_row(managed_by="setup", duration=30),
            _habit_row(target_id=manual_id),
        ],
    )

    _, habits, tasks, _ = _target_overview_items(context=context, plans=[plan])

    assert tasks == []
    assert [(item.ownership, item.planning_status) for item in habits] == [
        ("setup", "scheduled"),
        ("manual", "unplanned"),
    ]
    assert habits[0].duration_minutes == 30
    assert habits[0].plan_id == PLAN_ID
    assert habits[1].duration_minutes is None
    assert habits[1].plan_id is None


def test_v2_habits_keep_repository_order_instead_of_title_order() -> None:
    first_id = UUID("20000000-0000-4000-8000-000000000010")
    second_id = UUID("20000000-0000-4000-8000-000000000011")
    first = _habit_row(target_id=first_id)
    first["title"] = "Zulu habit"
    second = _habit_row(target_id=second_id)
    second["title"] = "Alpha habit"

    _, habits, _, _ = _target_overview_items(
        context=_overview_context(habits=[first, second]),
        plans=[],
    )

    assert [item.id for item in habits] == [first_id, second_id]


def test_v2_history_identity_is_unique_by_kind_and_id() -> None:
    shared_id = UUID("20000000-0000-4000-8000-000000000012")
    task = _task_row(target_id=shared_id)
    task["status"] = "done"
    habit = _habit_row(target_id=shared_id)
    habit["active"] = False
    habit["metadata"] = {
        **habit["metadata"],
        "lifecycle": "archived",
    }

    overview = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(tasks=[task], habits=[habit]),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )

    assert {(item.kind, item.id) for item in overview.history} == {
        ("task", shared_id),
        ("habit", shared_id),
    }


@pytest.mark.parametrize(
    ("persisted_kind", "history_kind"),
    [("task", "task"), ("habit", "habit")],
)
def test_v2_model_rejects_persisted_identity_in_matching_history(
    persisted_kind: str,
    history_kind: str,
) -> None:
    shared_id = UUID("20000000-0000-4000-8000-000000000013")
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(
            tasks=[_task_row(target_id=shared_id)],
            habits=[_habit_row(target_id=shared_id)],
        ),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    assert base.unscheduled_tasks[0].id == base.habits[0].id
    payload = base.model_dump()
    payload["history"] = [
        {
            "id": shared_id,
            "kind": history_kind,
            "title": f"Archived {persisted_kind}",
        },
    ]

    with pytest.raises(ValueError, match="must be disjoint"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_model_allows_task_and_habit_to_share_uuid_across_kinds() -> None:
    shared_id = UUID("20000000-0000-4000-8000-000000000014")

    overview = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(
            tasks=[_task_row(target_id=shared_id)],
            habits=[_habit_row(target_id=shared_id)],
        ),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )

    assert overview.unscheduled_tasks[0].id == shared_id
    assert overview.habits[0].id == shared_id


def test_v2_model_requires_unscheduled_task_to_match_current_target_snapshot() -> None:
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(tasks=[_task_row()]),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["task_targets"] = []

    with pytest.raises(ValueError, match="target snapshot is inconsistent"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_model_requires_every_unreserved_open_task_to_be_unscheduled() -> None:
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(tasks=[_task_row()]),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["unscheduled_tasks"] = []

    with pytest.raises(ValueError, match="task reservation relation"):
        PlannerOverviewResponse.model_validate(payload)


@pytest.mark.parametrize("wrong_reason", ["released", "no_time_available"])
def test_v2_model_rejects_wrong_reason_for_unplanned_complete_task(
    wrong_reason: str,
) -> None:
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(tasks=[_task_row()]),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["unscheduled_tasks"][0]["reason"] = wrong_reason

    with pytest.raises(ValueError, match="unscheduled task reason"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_model_released_reason_requires_matching_release_plan_state() -> None:
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(tasks=[_task_row(complete=False)]),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["unscheduled_tasks"][0]["reason"] = "released"

    with pytest.raises(ValueError, match="unscheduled task reason"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_model_reason_precedence_keeps_release_ahead_of_missing_inputs() -> None:
    plan = PlannerActionPlan(
        id=PLAN_ID,
        target_kind="task",
        target_id=TARGET_ID,
        status="unscheduled",
        current_revision=0,
        latest_revision=1,
        needs_attention=True,
        attention_reasons=["target_released"],
        active_revision=None,
        pending_revision=None,
    )
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(tasks=[_task_row(complete=False)]),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [plan]
    payload["unscheduled_tasks"][0]["reason"] = "missing_scheduling_inputs"

    with pytest.raises(ValueError, match="unscheduled task reason"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_builder_rejects_persisted_task_plan_without_lifecycle_projection() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    update_target = pending.target.model_copy(
        update={
            "operation": "update",
            "expected_updated_at": datetime(2026, 7, 20, 6, tzinfo=UTC),
        },
    )
    update_plan = response.plan.model_copy(
        update={
            "pending_revision": pending.model_copy(update={"target": update_target}),
        },
    )

    with pytest.raises(ValueError, match="has no target projection"):
        _target_overview_items(context=_overview_context(), plans=[update_plan])


@pytest.mark.parametrize("target_kind", ["task", "habit"])
@pytest.mark.parametrize("latest_revision", [1, 2, 500])
def test_v2_cancelled_create_tombstone_does_not_require_target_projection(
    target_kind: str,
    latest_revision: int,
) -> None:
    target_id = UUID(
        "20000000-0000-4000-8000-000000000081"
        if target_kind == "task"
        else "20000000-0000-4000-8000-000000000082"
    )
    tombstone = PlannerActionPlan(
        id=UUID(
            "10000000-0000-4000-8000-000000000081"
            if target_kind == "task"
            else "10000000-0000-4000-8000-000000000082"
        ),
        target_kind=target_kind,
        target_id=target_id,
        status="cancelled",
        current_revision=0,
        latest_revision=latest_revision,
        needs_attention=False,
        attention_reasons=[],
        active_revision=None,
        pending_revision=None,
    )

    targets, habits, unscheduled, history = _target_overview_items(
        context=_overview_context(),
        plans=[tombstone],
    )

    assert targets == []
    assert habits == []
    assert unscheduled == []
    assert history == []

    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [tombstone]

    validated = PlannerOverviewResponse.model_validate(payload)

    assert validated.action_plans == [tombstone]


@pytest.mark.parametrize("target_kind", ["task", "habit"])
def test_v2_cancelled_tombstone_rejects_malformed_near_shape(
    target_kind: str,
) -> None:
    tombstone = PlannerActionPlan(
        id=UUID(
            "10000000-0000-4000-8000-000000000083"
            if target_kind == "task"
            else "10000000-0000-4000-8000-000000000084"
        ),
        target_kind=target_kind,
        target_id=UUID(
            "20000000-0000-4000-8000-000000000083"
            if target_kind == "task"
            else "20000000-0000-4000-8000-000000000084"
        ),
        status="cancelled",
        current_revision=0,
        latest_revision=2,
        needs_attention=False,
        attention_reasons=[],
        active_revision=None,
        pending_revision=None,
    )
    near_tombstone = tombstone.model_copy(
        update={
            "needs_attention": True,
            "attention_reasons": ["target_changed"],
        },
    )

    with pytest.raises(ValueError, match="has no target projection"):
        _target_overview_items(
            context=_overview_context(),
            plans=[near_tombstone],
        )

    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump(mode="json")
    payload["action_plans"] = [near_tombstone.model_dump(mode="json")]

    with pytest.raises(ValueError, match="cancelled lifecycle"):
        PlannerOverviewResponse.model_validate_json(json.dumps(payload))


@pytest.mark.parametrize("field", ["current_revision", "latest_revision"])
def test_action_plan_rejects_revision_numbers_above_sql_bound(field: str) -> None:
    payload = {
        "id": "10000000-0000-4000-8000-000000000085",
        "target_kind": "task",
        "target_id": "20000000-0000-4000-8000-000000000085",
        "status": "cancelled",
        "current_revision": 0,
        "latest_revision": 1,
        "needs_attention": False,
        "attention_reasons": [],
        "active_revision": None,
        "pending_revision": None,
    }
    payload[field] = 501

    with pytest.raises(ValueError):
        PlannerActionPlan.model_validate_json(json.dumps(payload))


@pytest.mark.parametrize("target_kind", ["task", "habit"])
def test_action_plan_requires_active_revision_and_child_states(
    target_kind: str,
) -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=(
                _task_request() if target_kind == "task" else _habit_request()
            ),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    active_plan = _active_plan(pending)
    payload = active_plan.model_dump(mode="json")
    revision = payload["active_revision"]
    assert isinstance(revision, dict)
    revision["state"] = "proposed"
    revision["activated_at"] = None
    children = (
        revision["task_blocks"]
        if target_kind == "task"
        else revision["habit_slots"]
    )
    assert isinstance(children, list) and children
    for child in children:
        child["state"] = "proposed"

    with pytest.raises(ValueError, match="active revision state"):
        PlannerActionPlan.model_validate_json(json.dumps(payload))

    child_payload = active_plan.model_dump(mode="json")
    child_revision = child_payload["active_revision"]
    assert isinstance(child_revision, dict)
    active_children = (
        child_revision["task_blocks"]
        if target_kind == "task"
        else child_revision["habit_slots"]
    )
    assert isinstance(active_children, list) and active_children
    active_children[0]["state"] = "proposed"

    with pytest.raises(ValueError, match="child state"):
        PlannerActionPlan.model_validate_json(json.dumps(child_payload))


@pytest.mark.parametrize(
    ("field", "value"),
    [("revision", 501), ("base_revision", 500)],
)
def test_action_revision_rejects_numbers_above_sql_bound(
    field: str,
    value: int,
) -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    payload = pending.model_dump(mode="json")
    payload[field] = value

    with pytest.raises(ValueError):
        PlannerActionRevision.model_validate_json(json.dumps(payload))


@pytest.mark.parametrize("target_kind", ["task", "habit"])
@pytest.mark.parametrize(
    ("changes", "message"),
    [
        ({"status": "cancelled"}, "cancelled lifecycle"),
        (
            {
                "status": "cancelled",
                "pending_revision": None,
                "needs_attention": True,
                "attention_reasons": ["target_changed"],
            },
            "cancelled lifecycle",
        ),
        ({"status": "unscheduled"}, "released lifecycle"),
    ],
)
def test_action_plan_rejects_non_sql_pending_create_lifecycle_shapes(
    target_kind: str,
    changes: dict[str, object],
    message: str,
) -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=(
                _task_request() if target_kind == "task" else _habit_request()
            ),
        ),
    )
    payload = response.plan.model_dump(mode="json")
    if target_kind == "habit":
        payload["target_kind"] = "habit"
    payload.update(changes)

    with pytest.raises(ValueError, match=message):
        PlannerActionPlan.model_validate_json(json.dumps(payload))


@pytest.mark.parametrize("target_kind", ["task", "habit"])
def test_cancelled_formerly_active_plan_remains_valid_with_history_relation(
    target_kind: str,
) -> None:
    target_id = UUID(
        "20000000-0000-4000-8000-000000000091"
        if target_kind == "task"
        else "20000000-0000-4000-8000-000000000092"
    )
    plan = PlannerActionPlan(
        id=UUID(
            "10000000-0000-4000-8000-000000000091"
            if target_kind == "task"
            else "10000000-0000-4000-8000-000000000092"
        ),
        target_kind=target_kind,
        target_id=target_id,
        status="cancelled",
        current_revision=0,
        latest_revision=2,
        needs_attention=False,
        attention_reasons=[],
        active_revision=None,
        pending_revision=None,
    )
    if target_kind == "task":
        row = _task_row(target_id=target_id)
        row["status"] = "done"
        context = _overview_context(tasks=[row])
    else:
        row = _habit_row(target_id=target_id)
        row.update(
            {
                "active": False,
                "metadata": {**row["metadata"], "lifecycle": "archived"},
            },
        )
        context = _overview_context(habits=[row])

    _, _, _, history = _target_overview_items(context=context, plans=[plan])

    assert [(item.kind, item.id) for item in history] == [(target_kind, target_id)]


def test_v2_builder_rejects_active_plan_for_inactive_habit_read_race() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_habit_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    historical = _habit_row()
    historical.update(
        {
            "active": False,
            "metadata": {
                **historical["metadata"],
                "lifecycle": "archived",
            },
        },
    )

    with pytest.raises(ValueError, match="Historical Planner Habit"):
        _target_overview_items(
            context=_overview_context(habits=[historical]),
            plans=[_active_plan(pending)],
        )


def test_v2_model_rejects_active_plan_bound_to_habit_history() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_habit_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    plan = _active_plan(pending)
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [plan]
    payload["history"] = [
        {"id": plan.target_id, "kind": "habit", "title": "Archived Habit"}
    ]

    with pytest.raises(ValueError, match="historical habit plan lifecycle"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_history_bound_prioritizes_required_plan_targets_deterministically() -> None:
    task_id = UUID("20000000-0000-4000-8000-999999999999")
    terminal_task = _task_row(target_id=task_id)
    terminal_task.update(
        {
            "status": "done",
            "created_at": "2026-07-20T23:59:00Z",
        },
    )
    released = PlannerActionPlan(
        id=UUID("10000000-0000-4000-8000-999999999999"),
        target_kind="task",
        target_id=task_id,
        status="unscheduled",
        current_revision=0,
        latest_revision=1,
        needs_attention=True,
        attention_reasons=["target_released"],
        active_revision=None,
        pending_revision=None,
    )
    archived_habits = []
    for index in range(1_000):
        row = _habit_row(
            target_id=UUID(
                f"20000000-0000-4000-8000-{index + 1:012d}",
            ),
        )
        row.update(
            {
                "active": False,
                "metadata": {**row["metadata"], "lifecycle": "archived"},
                "created_at": "2026-07-19T00:00:00Z",
            },
        )
        archived_habits.append(row)

    def project(rows: list[dict[str, object]]) -> list[tuple[str, UUID]]:
        _, _, _, history = _target_overview_items(
            context=_overview_context(
                tasks=[terminal_task],
                habits=rows,
            ),
            plans=[released],
        )
        assert len(history) == 1_000
        assert history[0].kind == "task"
        assert history[0].id == task_id
        return [(item.kind, item.id) for item in history]

    projected = project(archived_habits)
    reversed_projection = project(list(reversed(archived_habits)))

    assert projected == reversed_projection
    assert sum(kind == "habit" for kind, _ in projected) == 999

    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [released]
    payload["history"] = [
        {"kind": kind, "id": item_id, "title": f"Historical {kind}"}
        for kind, item_id in projected
    ]

    validated = PlannerOverviewResponse.model_validate(payload)

    assert len(validated.history) == 1_000
    assert validated.history[0].id == task_id


def test_v2_model_rejects_persisted_task_plan_without_target_snapshot() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    update_target = pending.target.model_copy(
        update={
            "operation": "update",
            "expected_updated_at": datetime(2026, 7, 20, 6, tzinfo=UTC),
        },
    )
    update_plan = response.plan.model_copy(
        update={
            "pending_revision": pending.model_copy(update={"target": update_target}),
        },
    )
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [update_plan]

    with pytest.raises(ValueError, match="has no target snapshot"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_builder_rejects_active_plan_for_historical_task() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    historical = _task_row()
    historical["status"] = "done"

    with pytest.raises(ValueError, match="non-released action plan"):
        _target_overview_items(
            context=_overview_context(tasks=[historical]),
            plans=[_active_plan(pending)],
        )


def test_v2_model_rejects_active_plan_bound_to_task_history() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["task_targets"] = []
    payload["unscheduled_tasks"] = []
    payload["history"] = [
        {"id": TARGET_ID, "kind": "task", "title": "Historical Task"},
    ]
    payload["action_plans"] = [_active_plan(pending)]

    with pytest.raises(ValueError, match="historical task plan lifecycle"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_pending_task_create_does_not_require_persisted_target_snapshot() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )

    overview = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(plans=repository.projection),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )

    assert overview.action_plans == [response.plan]
    assert overview.task_targets == []
    assert overview.unscheduled_tasks == []


@pytest.mark.parametrize("projection", ["habit", "unscheduled_task", "history"])
def test_v2_builder_rejects_persisted_target_bound_to_create_preview(
    projection: str,
) -> None:
    request = _habit_request() if projection == "habit" else _task_request()
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=request,
        ),
    )
    task = _task_row()
    if projection == "history":
        task["status"] = "done"
    context = _overview_context(
        tasks=[task] if projection != "habit" else [],
        habits=[_habit_row()] if projection == "habit" else [],
    )

    with pytest.raises(ValueError, match="create preview"):
        _target_overview_items(context=context, plans=[response.plan])


@pytest.mark.parametrize("projection", ["habit", "unscheduled_task", "history"])
def test_v2_model_rejects_persisted_target_bound_to_create_preview(
    projection: str,
) -> None:
    request = _habit_request() if projection == "habit" else _task_request()
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=request,
        ),
    )
    task = _task_row()
    if projection == "history":
        task["status"] = "done"
    base = build_planner_overview(
        generated_at=NOW,
        context=_overview_context(
            tasks=[task] if projection != "habit" else [],
            habits=[_habit_row()] if projection == "habit" else [],
        ),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [response.plan]
    if projection == "habit":
        payload["habits"] = [
            base.habits[0].model_copy(
                update={
                    "plan_id": response.plan.id,
                    "has_pending_preview": True,
                },
            ),
        ]

    with pytest.raises(ValueError, match="create preview"):
        PlannerOverviewResponse.model_validate(payload)


def test_v2_persisted_target_allows_matching_pending_update() -> None:
    response = asyncio.run(
        PlannerService(repository=Repository(_context()), now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    pending = response.plan.pending_revision
    assert pending is not None
    expected_updated_at = datetime(2026, 7, 20, 6, tzinfo=UTC)
    update_target = pending.target.model_copy(
        update={
            "operation": "update",
            "expected_updated_at": expected_updated_at,
        },
    )
    update_revision = pending.model_copy(update={"target": update_target})
    update_plan = response.plan.model_copy(
        update={"pending_revision": update_revision},
    )
    context = _overview_context(tasks=[_task_row()])

    task_targets, habits, tasks, history = _target_overview_items(
        context=context,
        plans=[update_plan],
    )

    assert habits == []
    assert history == []
    assert [task.id for task in tasks] == [TARGET_ID]

    base = build_planner_overview(
        generated_at=NOW,
        context=context,
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
    )
    payload = base.model_dump()
    payload["action_plans"] = [update_plan]
    payload["task_targets"] = task_targets
    payload["unscheduled_tasks"] = tasks

    validated = PlannerOverviewResponse.model_validate(payload)

    assert validated.action_plans[0].pending_revision is not None
    assert validated.action_plans[0].pending_revision.target.operation == "update"


def test_v2_conflicts_name_each_current_authoritative_origin() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision)
    block = plan.active_revision.task_blocks[0]  # type: ignore[union-attr]
    calendar_event = {
        "id": "70000000-0000-4000-8000-000000000001",
        "title": "Imported class",
        "starts_at": block.starts_at.isoformat(),
        "ends_at": block.ends_at.isoformat(),
        "busy_status": "busy",
    }
    context = _overview_context(
        tasks=[_task_row()],
        preference={"use_calendar_busy_time": True},
        schedule_items=[
            {
                "id": "80000000-0000-4000-8000-000000000001",
                "weekday": block.local_date.isoweekday(),
                "starts_at": block.starts_at.time().isoformat(),
                "ends_at": block.ends_at.time().isoformat(),
            },
        ],
        commitments=[
            {
                "id": "90000000-0000-4000-8000-000000000001",
                "status": "active",
                "recurrence": "one_off",
                "starts_at": block.starts_at.isoformat(),
                "ends_at": block.ends_at.isoformat(),
            },
        ],
        calendar=PlannerCalendarProjection(
            available=True,
            connection_id=UUID("60000000-0000-4000-8000-000000000001"),
            import_id=IMPORT_ID,
            timed_events=[calendar_event],
            all_day_events=[],
        ),
    )

    attention = _attention_items(
        context=context,
        plans=[plan],
        days=[block.local_date],
        zone=ZoneInfo("UTC"),
    )

    conflicts = [item for item in attention if item.kind == "conflict"]
    assert [item.conflict_source for item in conflicts] == [
        "calendar",
        "fixed_commitment",
        "setup",
    ]
    assert all("Nothing moved automatically." in item.detail for item in conflicts)

    unavailable = _overview_context(
        tasks=[_task_row()],
        preference={"use_calendar_busy_time": True},
        calendar=PlannerCalendarProjection(
            available=False,
            connection_id=None,
            import_id=None,
            timed_events=[calendar_event],
            all_day_events=[],
        ),
    )
    unavailable_attention = _attention_items(
        context=unavailable,
        plans=[plan],
        days=[block.local_date],
        zone=ZoneInfo("UTC"),
    )
    assert all(item.conflict_source != "calendar" for item in unavailable_attention)


@pytest.mark.parametrize(
    ("transition_day", "reason"),
    [
        (date(2026, 10, 25), "ambiguous"),
        (date(2027, 3, 28), "nonexistent"),
    ],
)
def test_v2_invalid_dst_recurrences_are_omitted_and_mark_affected_plans(
    transition_day: date,
    reason: str,
) -> None:
    zone = ZoneInfo("Europe/Berlin")
    generated_at = datetime.combine(transition_day, time.min, tzinfo=zone).astimezone(
        UTC,
    )
    projection = _active_habit_projection_for_slot(
        weekday=transition_day.isoweekday(),
        starts_at=time(2, 30),
        ends_at=time(3),
    )
    deadline_plan_id = UUID("64000000-0000-4000-8000-000000000001")
    deadline_starts_at = datetime.combine(
        transition_day,
        time(4),
        tzinfo=zone,
    )
    deadline_ends_at = deadline_starts_at + timedelta(minutes=30)
    deadline_block = DeadlinePlanBlock(
        id=UUID("64000000-0000-4000-8000-000000000002"),
        sequence=1,
        starts_at=deadline_starts_at,
        ends_at=deadline_ends_at,
        local_date=transition_day,
        local_start_time=time(4),
        local_end_time=time(4, 30),
        planned_minutes=30,
        recovery_minutes=0,
        reserved_ends_at=deadline_ends_at,
        credited_tracked_minutes=0,
        state="upcoming",
    )
    deadline_revision = DeadlinePlanRevision(
        plan_id=deadline_plan_id,
        revision=1,
        base_revision=0,
        state="active",
        kind="exam",
        title="DST preparation",
        deadline_at=deadline_ends_at + timedelta(days=7),
        estimated_total_minutes=30,
        credited_prior_minutes=0,
        preferred_session_minutes=30,
        max_daily_minutes=120,
        planning_start_on=transition_day,
        buffer_days=1,
        source_kind="manual",
        source_status="not_applicable",
        use_calendar_availability=False,
        timezone="Europe/Berlin",
        best_energy_window="morning",
        planning_fingerprint="d" * 64,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=30,
        planned_minutes=30,
        unscheduled_minutes=0,
        created_at=generated_at,
        activated_at=generated_at,
        blocks=[deadline_block],
    )
    deadline_detail = DeadlinePlanDetail(
        plan=DeadlinePlanIdentity(
            id=deadline_plan_id,
            status="active",
            kind="exam",
            title="DST preparation",
            managed_task_id=deadline_plan_id,
            original_estimated_total_minutes=30,
            original_credited_prior_minutes=0,
            current_revision=1,
            latest_revision=1,
            created_at=generated_at,
            updated_at=generated_at,
        ),
        active_revision=deadline_revision,
        progress=DeadlinePlanProgress(
            estimated_total_minutes=30,
            credited_prior_minutes=0,
            tracked_focus_minutes=0,
            accounted_minutes=0,
            remaining_minutes=30,
            completion_suggested=False,
        ),
    )
    context = replace(
        _overview_context(
            habits=[_habit_row(duration=30)],
            plans=projection,
            schedule_items=[
                {
                    "id": "64000000-0000-4000-8000-000000000003",
                    "title": "DST class",
                    "weekday": transition_day.isoweekday(),
                    "starts_at": "02:30:00",
                    "ends_at": "03:00:00",
                    "metadata": {"managed_by": "setup"},
                },
            ],
            commitments=[
                {
                    "id": "64000000-0000-4000-8000-000000000004",
                    "title": "DST weekly work",
                    "location": None,
                    "recurrence": "weekly",
                    "status": "active",
                    "starts_at": None,
                    "ends_at": None,
                    "weekday": transition_day.isoweekday(),
                    "local_starts_at": "02:30:00",
                    "local_ends_at": "03:00:00",
                    "created_at": generated_at.isoformat(),
                    "updated_at": generated_at.isoformat(),
                    "archived_at": None,
                },
            ],
        ),
        timezone="Europe/Berlin",
    )

    overview = build_planner_overview(
        generated_at=generated_at,
        context=context,
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[deadline_detail],
        ),
    )

    current_kinds = {item.kind for item in overview.days[0].items}
    assert "setup_commitment" not in current_kinds
    assert "manual_commitment" not in current_kinds
    assert "habit_slot" not in current_kinds
    assert "preparation" in current_kinds
    invalid_items = [
        item for item in overview.needs_attention if "local-time-invalid" in item.id
    ]
    assert len(invalid_items) == 2
    action_attention = next(item for item in invalid_items if item.plan_id == PLAN_ID)
    preparation_attention = next(
        item for item in invalid_items if item.plan_id == deadline_plan_id
    )
    assert action_attention.kind == "stale_preview"
    assert "Habit" in action_attention.detail
    assert "Weekly Setup" in action_attention.detail
    assert "Weekly fixed commitment" in action_attention.detail
    assert transition_day.isoformat() in action_attention.detail
    assert "02:30" in action_attention.detail
    assert reason in action_attention.detail
    assert "nothing moved automatically" in action_attention.detail
    assert preparation_attention.kind == "stale_preview"
    assert "Weekly Setup" in preparation_attention.detail
    assert "Weekly fixed commitment" in preparation_attention.detail
    assert "Habit" not in preparation_attention.detail
    assert transition_day.isoformat() in preparation_attention.detail
    assert reason in preparation_attention.detail
    assert "nothing moved automatically" in preparation_attention.detail
    action_conflicts = [
        item
        for item in overview.needs_attention
        if item.plan_id == PLAN_ID and item.kind == "conflict"
    ]
    assert len(action_conflicts) == 2
    assert {item.conflict_source for item in action_conflicts} == {
        "setup",
        "fixed_commitment",
    }
    assert not any(
        item.plan_id == deadline_plan_id and item.kind == "conflict"
        for item in overview.needs_attention
    )


def test_v2_recurring_habit_conflicts_extend_to_bounded_local_year() -> None:
    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_habit_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision)
    revision = plan.active_revision
    assert revision is not None
    slot = revision.habit_slots[0]
    # Europe/Berlin has returned to standard time on this date. The exact
    # one-day Setup validity proves inclusive local-date filtering while the
    # interval still resolves with the profile's post-DST UTC offset.
    future_local_day = date(2026, 10, 26)
    assert future_local_day.isoweekday() == slot.weekday
    context = replace(
        _overview_context(
            habits=[_habit_row(duration=30)],
            schedule_items=[
                {
                    "id": "80000000-0000-4000-8000-000000000010",
                    "title": "Future semester class",
                    "weekday": slot.weekday,
                    "starts_at": slot.starts_at,
                    "ends_at": slot.ends_at,
                    "metadata": {
                        "managed_by": "setup",
                        "valid_from": future_local_day.isoformat(),
                        "valid_until": future_local_day.isoformat(),
                    },
                },
            ],
            commitments=[
                {
                    "id": "90000000-0000-4000-8000-000000000010",
                    "title": "Weekly work",
                    "location": None,
                    "recurrence": "weekly",
                    "status": "active",
                    "starts_at": None,
                    "ends_at": None,
                    "weekday": slot.weekday,
                    "local_starts_at": slot.starts_at,
                    "local_ends_at": slot.ends_at,
                    "created_at": "2026-07-01T08:00:00Z",
                    "updated_at": "2026-07-01T08:00:00Z",
                    "archived_at": None,
                },
            ],
        ),
        timezone="Europe/Berlin",
    )
    empty_deadlines = DeadlinePlansResponse(
        contract_version="deadline-plan-v1",
        origin="authenticated_backend",
        plans=[],
    )
    horizon = _attention_horizon(
        local_date=NOW.astimezone(ZoneInfo("Europe/Berlin")).date(),
        context=context,
        plans=[plan],
        deadline_response=empty_deadlines,
        zone=ZoneInfo("Europe/Berlin"),
    )

    assert future_local_day in horizon.reservation_days
    assert len(horizon.reservation_days) <= 366
    assert len(horizon.authoritative_days) <= 368
    assert max(horizon.reservation_days) <= (
        horizon.reservation_days[0] + timedelta(days=365)
    )
    assert all(
        candidate - timedelta(days=1) in horizon.authoritative_days
        for candidate in horizon.reservation_days
    )
    assert all(
        candidate + timedelta(days=1) in horizon.authoritative_days
        for candidate in horizon.reservation_days
    )

    attention = _attention_items(
        context=context,
        plans=[plan],
        days=horizon.reservation_days,
        authoritative_days=horizon.authoritative_days,
        zone=ZoneInfo("Europe/Berlin"),
    )

    assert {item.conflict_source for item in attention if item.kind == "conflict"} == {
        "setup",
        "fixed_commitment",
    }


@pytest.mark.parametrize("target_kind", ["task", "habit"])
def test_v2_first_horizon_day_uses_previous_cross_midnight_setup_anchor(
    target_kind: str,
) -> None:
    repository = Repository(_context())
    request = _task_request() if target_kind == "task" else _habit_request()
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=request,
        ),
    )
    assert response.plan.pending_revision is not None
    plan = _active_plan(response.plan.pending_revision)
    revision = plan.active_revision
    assert revision is not None
    local_day = date(2026, 10, 26)
    zone = ZoneInfo("Europe/Berlin")
    starts_at = datetime(2026, 10, 26, 0, 10, tzinfo=zone)
    ends_at = datetime(2026, 10, 26, 0, 40, tzinfo=zone)
    if target_kind == "task":
        first = revision.task_blocks[0].model_copy(
            update={
                "starts_at": starts_at,
                "ends_at": ends_at,
                "reserved_ends_at": ends_at,
                "local_date": local_day,
                "local_start_time": time(0, 10),
                "local_end_time": time(0, 40),
            },
        )
        updated_revision = revision.model_copy(
            update={"task_blocks": [first, *revision.task_blocks[1:]]},
        )
    else:
        first = revision.habit_slots[0]
        assert first.weekday == local_day.isoweekday()
        updated_slot = PlannerHabitSlot(
            id=first.id,
            weekday=first.weekday,
            starts_at=time(0, 10),
            ends_at=time(0, 40),
            duration_minutes=first.duration_minutes,
            state="active",
        )
        updated_revision = revision.model_copy(
            update={"habit_slots": [updated_slot, *revision.habit_slots[1:]]},
        )
    plan = plan.model_copy(update={"active_revision": updated_revision})
    anchor_day = local_day - timedelta(days=1)
    context = replace(
        _overview_context(
            tasks=[_task_row()] if target_kind == "task" else [],
            habits=[_habit_row(duration=30)] if target_kind == "habit" else [],
            schedule_items=[
                {
                    "id": "80000000-0000-4000-8000-000000000020",
                    "title": "Night lab",
                    "weekday": anchor_day.isoweekday(),
                    "starts_at": "23:50:00",
                    "ends_at": "00:20:00",
                    "metadata": {
                        "managed_by": "setup",
                        "valid_from": anchor_day.isoformat(),
                        "valid_until": anchor_day.isoformat(),
                    },
                },
            ],
        ),
        timezone="Europe/Berlin",
    )
    horizon = _attention_horizon(
        local_date=local_day,
        context=context,
        plans=[plan],
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        ),
        zone=zone,
    )

    assert horizon.reservation_days[0] == local_day
    assert anchor_day in horizon.authoritative_days
    assert len(horizon.reservation_days) <= 366
    assert len(horizon.authoritative_days) <= 368

    attention = _attention_items(
        context=context,
        plans=[plan],
        days=horizon.reservation_days,
        authoritative_days=horizon.authoritative_days,
        zone=zone,
    )

    assert {item.conflict_source for item in attention if item.kind == "conflict"} == {
        "setup"
    }


def test_v2_final_horizon_day_uses_next_cross_midnight_authoritative_anchor() -> None:
    zone = ZoneInfo("UTC")
    local_date = NOW.date()
    final_day = local_date + timedelta(days=365)
    spill_day = final_day + timedelta(days=1)
    starts_at = datetime.combine(final_day, time(23, 50), tzinfo=zone)
    ends_at = datetime.combine(spill_day, time(0, 40), tzinfo=zone)

    repository = Repository(_context())
    response = asyncio.run(
        PlannerService(repository=repository, now=lambda: NOW).propose(
            user_id=USER_ID,
            request=_task_request(),
        ),
    )
    assert response.plan.pending_revision is not None
    action_plan = _active_plan(response.plan.pending_revision, planned_blocks=1)
    action_revision = action_plan.active_revision
    assert action_revision is not None
    action_block = action_revision.task_blocks[0].model_copy(
        update={
            "starts_at": starts_at,
            "ends_at": ends_at,
            "reserved_ends_at": ends_at,
            "local_date": final_day,
            "local_start_time": time(23, 50),
            "local_end_time": time(0, 40),
            "planned_minutes": 50,
            "recovery_minutes": 0,
        },
    )
    action_revision = action_revision.model_copy(
        update={
            "planned_minutes": 50,
            "task_blocks": [action_block],
        },
    )
    action_plan = action_plan.model_copy(
        update={"active_revision": action_revision},
    )

    deadline_plan_id = UUID("64000000-0000-4000-8000-000000000001")
    valid_same_day_block = DeadlinePlanBlock(
        id=UUID("64000000-0000-4000-8000-000000000002"),
        sequence=1,
        starts_at=starts_at - timedelta(hours=1),
        ends_at=ends_at - timedelta(hours=1),
        local_date=final_day,
        local_start_time=time(22, 50),
        local_end_time=time(23, 40),
        planned_minutes=50,
        recovery_minutes=0,
        reserved_ends_at=ends_at - timedelta(hours=1),
        credited_tracked_minutes=0,
        state="upcoming",
    )
    deadline_revision = DeadlinePlanRevision(
        plan_id=deadline_plan_id,
        revision=1,
        base_revision=0,
        state="active",
        kind="exam",
        title="Far horizon exam",
        deadline_at=ends_at + timedelta(days=1),
        estimated_total_minutes=50,
        credited_prior_minutes=0,
        preferred_session_minutes=50,
        max_daily_minutes=100,
        planning_start_on=local_date,
        buffer_days=0,
        source_kind="manual",
        source_status="not_applicable",
        use_calendar_availability=False,
        timezone="UTC",
        best_energy_window="morning",
        planning_fingerprint="d" * 64,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=50,
        planned_minutes=50,
        unscheduled_minutes=0,
        created_at=NOW,
        activated_at=NOW,
        blocks=[valid_same_day_block],
    )
    deadline_detail = DeadlinePlanDetail(
        plan=DeadlinePlanIdentity(
            id=deadline_plan_id,
            status="active",
            kind="exam",
            title="Far horizon exam",
            managed_task_id=deadline_plan_id,
            original_estimated_total_minutes=50,
            original_credited_prior_minutes=0,
            current_revision=1,
            latest_revision=1,
            created_at=NOW,
            updated_at=NOW,
        ),
        active_revision=deadline_revision,
        progress=DeadlinePlanProgress(
            estimated_total_minutes=50,
            credited_prior_minutes=0,
            tracked_focus_minutes=0,
            accounted_minutes=0,
            remaining_minutes=50,
            completion_suggested=False,
        ),
    )
    deadline_response = DeadlinePlansResponse(
        contract_version="deadline-plan-v1",
        origin="authenticated_backend",
        plans=[deadline_detail],
    )
    deadline_block = valid_same_day_block.model_copy(
        update={
            "starts_at": starts_at,
            "ends_at": ends_at,
            "reserved_ends_at": ends_at,
            "local_start_time": time(23, 50),
            "local_end_time": time(0, 40),
        },
    )
    # The conflict scanner is deliberately exercised at its bounded read edge.
    # Allocation currently avoids cross-midnight Preparation blocks, but a
    # stored instant may still project across a local date after timezone input
    # changes; attention must remain safe and truthful for that read state.
    deadline_revision = deadline_revision.model_copy(
        update={"blocks": [deadline_block]},
    )
    deadline_detail = deadline_detail.model_copy(
        update={"active_revision": deadline_revision},
    )
    deadline_response = deadline_response.model_copy(
        update={"plans": [deadline_detail]},
    )
    context = _overview_context(
        tasks=[_task_row()],
        preference={"use_calendar_busy_time": True},
        schedule_items=[
            {
                "id": "64000000-0000-4000-8000-000000000003",
                "title": "Next-day Setup",
                "weekday": spill_day.isoweekday(),
                "starts_at": "00:00:00",
                "ends_at": "00:20:00",
                "metadata": {
                    "managed_by": "setup",
                    "valid_from": spill_day.isoformat(),
                    "valid_until": spill_day.isoformat(),
                },
            },
        ],
        commitments=[
            {
                "id": "64000000-0000-4000-8000-000000000004",
                "title": "Next-day fixed commitment",
                "location": None,
                "recurrence": "weekly",
                "status": "active",
                "starts_at": None,
                "ends_at": None,
                "weekday": spill_day.isoweekday(),
                "local_starts_at": "00:00:00",
                "local_ends_at": "00:20:00",
                "created_at": NOW.isoformat(),
                "updated_at": NOW.isoformat(),
                "archived_at": None,
            },
        ],
        calendar=PlannerCalendarProjection(
            available=True,
            connection_id=UUID("64000000-0000-4000-8000-000000000005"),
            import_id=IMPORT_ID,
            timed_events=[
                {
                    "id": "64000000-0000-4000-8000-000000000006",
                    "title": "Next-day calendar event",
                    "starts_at": datetime.combine(
                        spill_day,
                        time(0, 5),
                        tzinfo=zone,
                    ).isoformat(),
                    "ends_at": datetime.combine(
                        spill_day,
                        time(0, 25),
                        tzinfo=zone,
                    ).isoformat(),
                    "busy_status": "busy",
                },
            ],
            all_day_events=[],
        ),
    )
    horizon = _attention_horizon(
        local_date=local_date,
        context=context,
        plans=[action_plan],
        deadline_response=deadline_response,
        zone=zone,
    )

    assert final_day in horizon.reservation_days
    assert spill_day not in horizon.reservation_days
    assert spill_day in horizon.authoritative_days
    assert max(horizon.reservation_days) == final_day
    assert len(horizon.reservation_days) <= 366
    assert len(horizon.authoritative_days) <= 368

    action_attention = _attention_items(
        context=context,
        plans=[action_plan],
        days=horizon.reservation_days,
        authoritative_days=horizon.authoritative_days,
        zone=zone,
    )
    preparation_attention = _preparation_attention_items(
        context=context,
        deadline_response=deadline_response,
        days=horizon.reservation_days,
        authoritative_days=horizon.authoritative_days,
        zone=zone,
        generated_at=NOW,
    )

    assert {
        item.conflict_source
        for item in action_attention
        if item.kind == "conflict" and item.plan_id == PLAN_ID
    } == {"setup", "fixed_commitment", "calendar"}
    assert {
        item.conflict_source
        for item in preparation_attention
        if item.kind == "conflict" and item.plan_id == deadline_plan_id
    } == {"setup", "fixed_commitment", "calendar"}


def test_v2_preparation_projects_timezone_and_exact_active_unplaced_reasons() -> None:
    plan_id = UUID("60000000-0000-4000-8000-000000000001")
    identity = DeadlinePlanIdentity(
        id=plan_id,
        status="active",
        kind="exam",
        title="Mathematics",
        managed_task_id=plan_id,
        original_estimated_total_minutes=120,
        original_credited_prior_minutes=0,
        current_revision=1,
        latest_revision=1,
        attention_reasons=["timezone_changed", "unplaced_minutes"],
        created_at=NOW - timedelta(days=2),
        updated_at=NOW,
    )
    revision = DeadlinePlanRevision(
        plan_id=plan_id,
        revision=1,
        base_revision=0,
        state="active",
        kind="exam",
        title="Mathematics",
        deadline_at=NOW + timedelta(days=5),
        estimated_total_minutes=120,
        credited_prior_minutes=0,
        preferred_session_minutes=50,
        max_daily_minutes=100,
        planning_start_on=NOW.date(),
        buffer_days=1,
        source_kind="manual",
        source_status="not_applicable",
        use_calendar_availability=False,
        timezone="UTC",
        best_energy_window="morning",
        planning_fingerprint="a" * 64,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=120,
        planned_minutes=0,
        unscheduled_minutes=120,
        created_at=NOW - timedelta(days=1),
        activated_at=NOW,
        blocks=[],
    )
    detail = DeadlinePlanDetail(
        plan=identity,
        active_revision=revision,
        progress=DeadlinePlanProgress(
            estimated_total_minutes=120,
            credited_prior_minutes=0,
            tracked_focus_minutes=0,
            accounted_minutes=0,
            remaining_minutes=120,
            completion_suggested=False,
        ),
    )

    attention = _preparation_attention_items(
        context=_overview_context(),
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[detail],
        ),
        days=[NOW.date() + timedelta(days=offset) for offset in range(28)],
        zone=ZoneInfo("UTC"),
        generated_at=NOW,
    )

    assert [(item.kind, item.unplaced_minutes) for item in attention] == [
        ("stale_preview", 0),
        ("unscheduled", 120),
    ]
    assert "timezone changed" in attention[0].detail


def test_v2_preparation_conflicts_name_all_authoritative_origins() -> None:
    plan_id = UUID("61000000-0000-4000-8000-000000000001")
    zone = ZoneInfo("Europe/Berlin")
    local_day = date(2026, 10, 26)
    anchor_day = local_day - timedelta(days=1)
    starts_at = datetime(2026, 10, 26, 0, 10, tzinfo=zone)
    ends_at = datetime(2026, 10, 26, 0, 40, tzinfo=zone)
    identity = DeadlinePlanIdentity(
        id=plan_id,
        status="active",
        kind="exam",
        title="Physics",
        managed_task_id=plan_id,
        original_estimated_total_minutes=120,
        original_credited_prior_minutes=0,
        current_revision=1,
        latest_revision=1,
        created_at=NOW - timedelta(days=2),
        updated_at=NOW,
    )
    block = DeadlinePlanBlock(
        id=UUID("61000000-0000-4000-8000-000000000002"),
        sequence=1,
        starts_at=starts_at,
        ends_at=ends_at,
        local_date=starts_at.date(),
        local_start_time=starts_at.time().replace(tzinfo=None),
        local_end_time=ends_at.time().replace(tzinfo=None),
        planned_minutes=30,
        recovery_minutes=0,
        reserved_ends_at=ends_at,
        credited_tracked_minutes=0,
        state="upcoming",
    )
    revision = DeadlinePlanRevision(
        plan_id=plan_id,
        revision=1,
        base_revision=0,
        state="active",
        kind="exam",
        title="Physics",
        deadline_at=datetime(2026, 10, 31, 12, tzinfo=zone),
        estimated_total_minutes=120,
        credited_prior_minutes=0,
        preferred_session_minutes=50,
        max_daily_minutes=100,
        planning_start_on=NOW.date(),
        buffer_days=1,
        source_kind="manual",
        source_status="not_applicable",
        use_calendar_availability=False,
        timezone="Europe/Berlin",
        best_energy_window="morning",
        planning_fingerprint="b" * 64,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=120,
        planned_minutes=30,
        unscheduled_minutes=90,
        created_at=NOW - timedelta(days=1),
        activated_at=NOW,
        blocks=[block],
    )
    detail = DeadlinePlanDetail(
        plan=identity,
        active_revision=revision,
        progress=DeadlinePlanProgress(
            estimated_total_minutes=120,
            credited_prior_minutes=0,
            tracked_focus_minutes=0,
            accounted_minutes=0,
            remaining_minutes=120,
            completion_suggested=False,
        ),
    )
    context = _overview_context(
        preference={"use_calendar_busy_time": True},
        schedule_items=[
            {
                "id": "62000000-0000-4000-8000-000000000001",
                "weekday": anchor_day.isoweekday(),
                "starts_at": "23:50:00",
                "ends_at": "00:20:00",
                "metadata": {
                    "managed_by": "setup",
                    "valid_from": anchor_day.isoformat(),
                    "valid_until": anchor_day.isoformat(),
                },
            },
        ],
        commitments=[
            {
                "id": "62000000-0000-4000-8000-000000000002",
                "status": "active",
                "recurrence": "one_off",
                "starts_at": starts_at.isoformat(),
                "ends_at": ends_at.isoformat(),
            },
        ],
        calendar=PlannerCalendarProjection(
            available=True,
            connection_id=UUID("62000000-0000-4000-8000-000000000003"),
            import_id=IMPORT_ID,
            timed_events=[
                {
                    "id": "62000000-0000-4000-8000-000000000004",
                    "starts_at": starts_at.isoformat(),
                    "ends_at": ends_at.isoformat(),
                    "busy_status": "busy",
                },
            ],
            all_day_events=[],
        ),
    )
    context = replace(context, timezone="Europe/Berlin")

    attention = _preparation_attention_items(
        context=context,
        deadline_response=DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[detail],
        ),
        days=[local_day],
        zone=zone,
        generated_at=NOW,
    )

    conflicts = [item for item in attention if item.kind == "conflict"]
    assert [item.conflict_source for item in conflicts] == [
        "setup",
        "fixed_commitment",
        "calendar",
    ]
    assert all("preparation plan" in item.detail for item in conflicts)


def test_preparation_conflict_lookup_is_bounded_by_block_local_days() -> None:
    class CountingIndex(dict[date, tuple[_AuthoritativeInterval, ...]]):
        def __init__(self, values):
            super().__init__(values)
            self.lookups: list[date] = []

        def get(self, key, default=None):
            self.lookups.append(key)
            return super().get(key, default)

        def __iter__(self):
            raise AssertionError("Preparation conflict lookup scanned the index.")

        def values(self):
            raise AssertionError("Preparation conflict lookup scanned all buckets.")

    local_day = date(2026, 10, 26)
    zone = ZoneInfo("Europe/Berlin")
    starts_at = datetime(2026, 10, 26, 0, 10, tzinfo=zone)
    ends_at = datetime(2026, 10, 26, 0, 40, tzinfo=zone)
    block = DeadlinePlanBlock(
        id=UUID("63000000-0000-4000-8000-000000000001"),
        sequence=1,
        starts_at=starts_at,
        ends_at=ends_at,
        local_date=local_day,
        local_start_time=time(0, 10),
        local_end_time=time(0, 40),
        planned_minutes=30,
        recovery_minutes=0,
        reserved_ends_at=ends_at,
        credited_tracked_minutes=0,
        state="upcoming",
    )
    revision = DeadlinePlanRevision(
        plan_id=UUID("63000000-0000-4000-8000-000000000002"),
        revision=1,
        base_revision=0,
        state="active",
        kind="exam",
        title="Bounded lookup",
        deadline_at=datetime(2026, 11, 1, 12, tzinfo=zone),
        estimated_total_minutes=30,
        credited_prior_minutes=0,
        preferred_session_minutes=30,
        max_daily_minutes=120,
        planning_start_on=local_day,
        buffer_days=1,
        source_kind="manual",
        source_status="not_applicable",
        use_calendar_availability=False,
        timezone="Europe/Berlin",
        best_energy_window="morning",
        planning_fingerprint="c" * 64,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=30,
        planned_minutes=30,
        unscheduled_minutes=0,
        created_at=NOW,
        activated_at=NOW,
        blocks=[block],
    )
    relevant = _AuthoritativeInterval(
        starts_at=starts_at,
        ends_at=ends_at,
        source="setup",
    )
    index = CountingIndex(
        {
            local_day + timedelta(days=offset): ((relevant,) if offset == 0 else ())
            for offset in range(366)
        },
    )

    sources = _deadline_revision_conflict_sources(
        revision=revision,
        authoritative_by_day=index,
        zone=zone,
        generated_at=NOW,
    )

    assert sources == ["setup"]
    assert index.lookups == [local_day]


def test_shared_profile_absence_keeps_planner_not_found_mapping() -> None:
    class Client:
        async def select(self, table, *, params):
            return []

    class Deadlines:
        async def list_plans(self, *, user_id):
            return DeadlinePlansResponse(
                contract_version="deadline-plan-v1",
                origin="authenticated_backend",
                plans=[],
            )

    client = Client()
    deadlines = Deadlines()
    read_contexts = TodayPlannerReadContextFactory(
        repository=SupabaseTodayPlannerReadRepository(client),
        deadline_plans=deadlines,
    )
    service = PlannerService(
        repository=SupabasePlannerRepository(client),
        deadline_plans=deadlines,
        read_context_factory=read_contexts,
        now=lambda: NOW,
    )

    with pytest.raises(
        PlannerNotFoundError,
        match="Planner profile is unavailable.",
    ):
        asyncio.run(service.get_overview(user_id=USER_ID))


def test_overview_shows_setup_commitment_only_inside_semester_dates() -> None:
    days = [date(2026, 7, 20), date(2026, 7, 27)]
    day_items = {day: [] for day in days}

    _add_setup_commitments(
        day_items=day_items,
        rows=[
            {
                "id": "90000000-0000-4000-8000-000000000001",
                "title": "Lecture",
                "weekday": 1,
                "starts_at": "09:00:00",
                "ends_at": "10:30:00",
                "metadata": {
                    "managed_by": "setup",
                    "valid_from": "2026-07-27",
                    "valid_until": "2026-12-18",
                },
            },
        ],
        days=days,
        zone=ZoneInfo("UTC"),
    )

    assert day_items[date(2026, 7, 20)] == []
    assert [item.title for item in day_items[date(2026, 7, 27)]] == ["Lecture"]
