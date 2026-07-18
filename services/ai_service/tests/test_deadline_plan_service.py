import asyncio
import json
from datetime import UTC, date, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from app.models.deadline_plans import DeadlinePlanProposalRequest
from app.repositories.deadline_plan_repository import (
    DeadlinePlanProjection,
    DeadlinePlanningContext,
)
from app.services.deadline_plan_service import (
    DeadlinePlanService,
    _fingerprint,
    _plan_blocks,
)


PLAN_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
NOW = datetime(2026, 7, 20, 8, tzinfo=UTC)


def _request(**overrides) -> DeadlinePlanProposalRequest:
    values = {
        "request_id": str(REQUEST_ID),
        "plan_id": str(PLAN_ID),
        "base_revision": 0,
        "kind": "exam",
        "title": "Mathematics",
        "deadline_at": "2026-07-30T12:00:00+00:00",
        "estimated_total_minutes": 200,
        "credited_prior_minutes": 0,
        "preferred_session_minutes": 50,
        "max_daily_minutes": 100,
        "planning_start_on": "2026-07-20",
        "buffer_days": 1,
        "source_kind": "manual",
        "use_calendar_availability": False,
    }
    values.update(overrides)
    for key, value in list(values.items()):
        if isinstance(value, datetime):
            values[key] = value.isoformat()
        elif isinstance(value, date):
            values[key] = value.isoformat()
        elif isinstance(value, UUID):
            values[key] = str(value)
    return DeadlinePlanProposalRequest.model_validate_json(json.dumps(values))


def _context(*, schedule_items=None) -> DeadlinePlanningContext:
    return DeadlinePlanningContext(
        timezone="UTC",
        best_energy_window="variable",
        schedule_items=schedule_items or [],
        confirmed_blocks=[],
        timed_calendar_events=[],
        all_day_calendar_events=[],
        source_calendar_event=None,
        calendar_availability_current=False,
        availability_connection_id=None,
        availability_import_id=None,
    )


def test_planner_spreads_first_sessions_and_treats_buffer_as_hard() -> None:
    request = _request()
    blocks = _plan_blocks(
        request=request,
        context=_context(),
        zone=ZoneInfo("UTC"),
        local_now=NOW,
        local_deadline=request.deadline_at,
        effective_start=request.planning_start_on,
        remaining_minutes=200,
    )

    assert [minutes for _, _, minutes in blocks] == [50, 50, 50, 50]
    block_days = [starts_at.date() for starts_at, _, _ in blocks]
    assert block_days[0] == date(2026, 7, 20)
    assert block_days[-1] == date(2026, 7, 28)
    assert all(
        (right - left).days > 1
        for left, right in zip(block_days, block_days[1:])
    )
    assert all(day < date(2026, 7, 29) for day in block_days)


def test_planner_uses_exact_shortfall_instead_of_buffer_or_overlap() -> None:
    request = _request(
        deadline_at=datetime(2026, 7, 23, 12, tzinfo=UTC),
        buffer_days=1,
        estimated_total_minutes=300,
        max_daily_minutes=50,
    )
    context = _context(
        schedule_items=[
            {
                "id": "fixed",
                "weekday": date(2026, 7, 20).isoweekday(),
                "starts_at": "09:00:00",
                "ends_at": "21:00:00",
                "updated_at": NOW.isoformat(),
            },
        ],
    )
    blocks = _plan_blocks(
        request=request,
        context=context,
        zone=ZoneInfo("UTC"),
        local_now=NOW,
        local_deadline=request.deadline_at,
        effective_start=request.planning_start_on,
        remaining_minutes=300,
    )

    # Only July 20-21 are outside the hard one-day buffer; the first is busy.
    assert sum(minutes for _, _, minutes in blocks) == 50
    assert blocks[0][0].date() == date(2026, 7, 21)


def test_zero_buffer_can_use_deadline_day_but_never_pass_deadline_instant() -> None:
    local_now = datetime(2026, 7, 20, 14, 7, tzinfo=UTC)
    request = _request(
        deadline_at=datetime(2026, 7, 20, 16, 20, tzinfo=UTC),
        planning_start_on=date(2026, 7, 20),
        buffer_days=0,
        estimated_total_minutes=200,
        preferred_session_minutes=50,
        max_daily_minutes=200,
    )
    blocks = _plan_blocks(
        request=request,
        context=_context(),
        zone=ZoneInfo("UTC"),
        local_now=local_now,
        local_deadline=request.deadline_at,
        effective_start=request.planning_start_on,
        remaining_minutes=200,
    )

    assert blocks
    assert blocks[0][0] == datetime(2026, 7, 20, 14, 30, tzinfo=UTC)
    assert all(ends_at <= request.deadline_at for _, ends_at, _ in blocks)
    assert sum(minutes for _, _, minutes in blocks) == 100


def test_planner_skips_spring_gap_and_fall_fold_intervals() -> None:
    zone = ZoneInfo("Pacific/Easter")
    for local_day in (date(2026, 4, 4), date(2026, 9, 5)):
        local_now = datetime.combine(local_day, datetime.min.time(), tzinfo=zone)
        deadline = datetime.combine(
            local_day,
            datetime.max.time().replace(microsecond=0),
            tzinfo=zone,
        )
        request = _request(
            deadline_at=deadline,
            planning_start_on=local_day,
            buffer_days=0,
            estimated_total_minutes=300,
            preferred_session_minutes=90,
            max_daily_minutes=300,
        )
        context = DeadlinePlanningContext(
            **{
                **_context().__dict__,
                "timezone": "Pacific/Easter",
                "best_energy_window": "evening",
            },
        )
        blocks = _plan_blocks(
            request=request,
            context=context,
            zone=zone,
            local_now=local_now,
            local_deadline=deadline,
            effective_start=local_day,
            remaining_minutes=300,
        )

        assert blocks
        for starts_at, ends_at, minutes in blocks:
            assert starts_at.utcoffset() == ends_at.utcoffset()
            assert (
                ends_at.astimezone(UTC) - starts_at.astimezone(UTC)
            ).total_seconds() == minutes * 60


class ReplayRepository:
    def __init__(self, request_fingerprint: str) -> None:
        self.request_fingerprint = request_fingerprint
        self.context_loaded = False

    async def get_request_identity(self, *, request_id):
        return {
            "request_id": str(request_id),
            "user_id": "owner",
            "operation": "proposal",
            "request_fingerprint": self.request_fingerprint,
            "plan_id": str(PLAN_ID),
            "result_revision": 1,
            "result_status": "draft",
        }

    async def get_plan(self, *, user_id, plan_id):
        return {
            "id": str(plan_id),
            "user_id": user_id,
            "status": "draft",
            "kind": "exam",
            "title": "Mathematics",
            "managed_task_id": None,
            "original_estimated_total_minutes": 200,
            "original_credited_prior_minutes": 0,
            "current_revision": 0,
            "latest_revision": 1,
            "first_activated_at": None,
            "created_at": "2026-07-20T08:00:00+00:00",
            "updated_at": "2026-07-20T08:00:00+00:00",
            "completed_at": None,
            "cancelled_at": None,
        }

    async def load_projection(self, *, user_id, plan_id):
        assert plan_id == PLAN_ID
        return DeadlinePlanProjection(
            plans=[await self.get_plan(user_id=user_id, plan_id=plan_id)],
            revisions=await self.list_revisions(
                user_id=user_id,
                plan_id=plan_id,
            ),
            blocks=[],
            focus_totals=[
                {
                    "plan_id": str(plan_id),
                    "focus_count": 0,
                    "tracked_focus_minutes": 0,
                },
            ],
            calendar_events={},
        )

    async def list_revisions(self, *, user_id, plan_id):
        return [
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "user_id": user_id,
                "plan_id": str(plan_id),
                "revision": 1,
                "base_revision": 0,
                "state": "proposed",
                "kind": "exam",
                "title": "Mathematics",
                "deadline_at": "2026-07-30T12:00:00+00:00",
                "estimated_total_minutes": 200,
                "credited_prior_minutes": 0,
                "preferred_session_minutes": 50,
                "max_daily_minutes": 100,
                "planning_start_on": "2026-07-20",
                "buffer_days": 1,
                "source_kind": "manual",
                "source_calendar_event_id": None,
                "source_calendar_event_fingerprint": None,
                "use_calendar_availability": False,
                "availability_connection_id": None,
                "availability_import_id": None,
                "timezone": "UTC",
                "best_energy_window": "variable",
                "planning_fingerprint": "a" * 64,
                "tracked_focus_minutes_at_proposal": 0,
                "remaining_minutes_at_proposal": 200,
                "planned_minutes": 0,
                "unscheduled_minutes": 200,
                "created_at": "2026-07-20T08:00:00+00:00",
                "activated_at": None,
                "superseded_at": None,
            },
        ]

    async def list_blocks(self, *, user_id, plan_id, revisions):
        return []

    async def list_completed_focus(self, **kwargs):
        return []

    async def get_calendar_event(self, **kwargs):
        return None

    async def load_planning_context(self, **kwargs):
        self.context_loaded = True
        raise AssertionError("exact replay must not reload planning context")


def test_exact_proposal_replay_short_circuits_stale_base_and_time() -> None:
    request = _request(deadline_at=datetime(2026, 7, 30, 12, tzinfo=UTC))
    planning_input = {
        key: value
        for key, value in request.model_dump(mode="json").items()
        if key != "request_id"
    }
    repository = ReplayRepository(_fingerprint(planning_input))
    service = DeadlinePlanService(
        repository=repository,
        now=lambda: datetime(2026, 8, 2, tzinfo=UTC),
    )

    response = asyncio.run(service.propose(user_id="owner", request=request))

    assert response.plan.latest_revision == 1
    assert response.pending_revision is not None
    assert repository.context_loaded is False
