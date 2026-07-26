import asyncio
import hashlib
import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from app.models.planner import PlannerActionProposalRequest
from app.models.planning_timing import PlanningTimingProvenance
from app.repositories.planner_repository import (
    PlannerAvailabilityContext,
    PlannerCalendarProjection,
    PlannerOverviewContext,
    PlannerProjection,
)
from app.services.planner_service import (
    PlannerConflictError,
    PlannerService,
    _add_setup_commitments,
    _attention_items,
    _course_selection_attention,
)


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
                    "timing_evidence_fingerprint": timing[
                        "evidence_fingerprint"
                    ],
                    "timing_fell_back_to_setup": timing[
                        "fell_back_to_setup"
                    ],
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
    assert (
        habit_response.plan.pending_revision.timing_preference.source
        == "setup"
    )
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

    assert _course_selection_attention(
        study_setup,
        local_date=date(2026, 8, 14),
    ) == []
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
