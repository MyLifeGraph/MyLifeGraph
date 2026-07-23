import asyncio
import hashlib
import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from app.models.planner import PlannerActionProposalRequest
from app.repositories.planner_repository import (
    PlannerAvailabilityContext,
    PlannerCalendarProjection,
    PlannerOverviewContext,
    PlannerProjection,
)
from app.services.planner_service import (
    PlannerService,
    _add_setup_commitments,
    _attention_items,
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
                    "calendar_import_id": revision["calendar_import_id"],
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


def _context(
    *,
    preference: dict[str, object] | None = None,
    calendar: PlannerCalendarProjection | None = None,
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
        schedule_items=[],
        commitments=[],
        task_blocks=[],
        habit_slots=[],
        deadline_blocks=[],
        target=None,
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
    assert replay == response
    assert repository.persist_calls == 1


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
