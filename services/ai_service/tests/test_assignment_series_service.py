import asyncio
import json
from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from app.models.assignment_series import AssignmentSeriesProposalRequest
from app.repositories.assignment_series_repository import AssignmentSeriesProjection
from app.repositories.deadline_plan_repository import DeadlinePlanningContext
from app.services.assignment_series_service import AssignmentSeriesService
from app.services.deadline_plan_service import DeadlinePlanService


NOW = datetime(2026, 8, 10, 8, tzinfo=UTC)
SERIES_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")


def _request(**overrides) -> AssignmentSeriesProposalRequest:
    values: dict[str, object] = {
        "contract_version": "assignment-series-v1",
        "request_id": str(REQUEST_ID),
        "series_id": str(SERIES_ID),
        "base_revision": 0,
        "title": "Weekly algorithms sheet",
        "next_deadline_at": "2026-08-17T17:00:00+02:00",
        "remaining_occurrences": 3,
        "estimated_total_minutes": 90,
        "preferred_session_minutes": 30,
        "max_daily_minutes": 60,
        "buffer_days": 1,
        "use_calendar_availability": False,
    }
    values.update(overrides)
    return AssignmentSeriesProposalRequest.model_validate_json(json.dumps(values))


class DeadlineRepository:
    def __init__(self, *, timezone: str = "Europe/Berlin") -> None:
        self.timezone = timezone
        self.plans: dict[UUID, dict[str, object]] = {}
        self.persist_calls = 0

    async def get_plan(self, *, user_id, plan_id):
        assert user_id == "owner"
        return self.plans.get(plan_id)

    async def list_completed_focus(self, **kwargs):
        return []

    async def load_planning_context(self, **kwargs):
        assert kwargs["user_id"] == "owner"
        return DeadlinePlanningContext(
            timezone=self.timezone,
            best_energy_window="variable",
            schedule_items=[],
            confirmed_blocks=[],
            timed_calendar_events=[],
            all_day_calendar_events=[],
            source_calendar_event=None,
            calendar_availability_current=False,
            availability_connection_id=None,
            availability_import_id=None,
            daily_preparation_budget_minutes=None,
            planner_recurring_commitments=[],
            planner_timed_intervals=[],
            planner_use_calendar_busy_time=False,
            study_setup=None,
        )

    async def persist_proposal(self, **kwargs):
        self.persist_calls += 1
        raise AssertionError("series preparation must not persist plans one by one")


class SeriesRepository:
    def __init__(self) -> None:
        self.projection = AssignmentSeriesProjection([], [], [])
        self.persisted: list[dict[str, object]] = []
        self.deadline_plans: dict[UUID, dict[str, object]] = {}

    async def get_request_identity(self, *, request_id):
        return None

    async def load_projection(self, *, user_id, series_id):
        assert user_id == "owner"
        return self.projection

    async def get_deadline_plans(self, *, user_id, plan_ids):
        assert user_id == "owner"
        return [self.deadline_plans[value] for value in plan_ids]

    async def persist_proposal(self, **kwargs):
        self.persisted.append(kwargs)
        revision = kwargs["base_revision"] + 1
        payload = kwargs["series_payload"]
        now = kwargs["now"].isoformat()
        current = self.projection.series[0] if self.projection.series else None
        status = current["status"] if current is not None else "draft"
        current_revision = current["current_revision"] if current is not None else 0
        active_revisions = [
            row for row in self.projection.revisions if row["state"] == "active"
        ]
        self.projection = AssignmentSeriesProjection(
            series=[
                {
                    "id": str(kwargs["series_id"]),
                    "status": status,
                    "title": current["title"]
                    if current is not None
                    else payload["title"],
                    "current_revision": current_revision,
                    "latest_revision": revision,
                    "created_at": current["created_at"] if current is not None else now,
                    "updated_at": now,
                    "first_activated_at": (
                        current.get("first_activated_at")
                        if current is not None
                        else None
                    ),
                    "cancelled_at": None,
                },
            ],
            revisions=[
                *active_revisions,
                {
                    "series_id": str(kwargs["series_id"]),
                    "revision": revision,
                    "base_revision": kwargs["base_revision"],
                    "state": "proposed",
                    **payload,
                    "created_at": now,
                    "activated_at": None,
                    "superseded_at": None,
                },
            ],
            occurrences=[
                *[
                    item
                    for item in self.projection.occurrences
                    if item["series_revision"] == current_revision
                ],
                *[
                    {
                        "series_id": str(kwargs["series_id"]),
                        "series_revision": revision,
                        "position": item["position"],
                        "action": item["action"],
                        "plan_id": item["plan_id"],
                        "plan_revision": item["plan_revision"],
                        "deadline_at": item["deadline_at"],
                    }
                    for item in kwargs["items"]
                ],
            ],
        )
        return revision


def _service(*, now: datetime = NOW, timezone: str = "Europe/Berlin"):
    series = SeriesRepository()
    deadline = DeadlineRepository(timezone=timezone)
    deadline_service = DeadlinePlanService(repository=deadline, now=lambda: now)
    service = AssignmentSeriesService(
        repository=series,
        deadline_repository=deadline,
        deadline_plans=deadline_service,
        now=lambda: now,
    )
    return service, series, deadline


def test_new_series_prepares_weekly_independent_plans_in_one_write() -> None:
    service, series, deadline = _service()

    result = asyncio.run(service.propose(user_id="owner", request=_request()))

    assert result.assignment_series.pending_revision is not None
    assert len(series.persisted) == 1
    assert deadline.persist_calls == 0
    items = series.persisted[0]["items"]
    assert len(items) == 3
    assert {item["action"] for item in items} == {"upsert"}
    assert len({item["plan_id"] for item in items}) == 3
    for item in items:
        assert item["proposal"]["kind"] == "assignment"
        assert item["proposal"]["credited_prior_minutes"] == 0
        assert item["proposal"]["title"] == "Weekly algorithms sheet"
    berlin = ZoneInfo("Europe/Berlin")
    due = [
        datetime.fromisoformat(item["deadline_at"]).astimezone(berlin) for item in items
    ]
    assert [value.hour for value in due] == [17, 17, 17]
    assert [
        (right.date() - left.date()).days
        for left, right in zip(due, due[1:], strict=False)
    ] == [
        7,
        7,
    ]


def test_new_series_uses_assignment_clustering_and_360_minute_cap() -> None:
    service, series, _ = _service()

    asyncio.run(
        service.propose(
            user_id="owner",
            request=_request(
                estimated_total_minutes=300,
                preferred_session_minutes=50,
                max_daily_minutes=360,
            ),
        ),
    )

    items = series.persisted[0]["items"]
    expected_starts = ["2026-08-10", "2026-08-18", "2026-08-25"]
    for item, expected_start in zip(items, expected_starts, strict=True):
        proposal = item["proposal"]
        assert proposal["kind"] == "assignment"
        assert proposal["max_daily_minutes"] == 360
        assert proposal["planning_start_on"] == expected_start
        assert {block["local_date"] for block in item["blocks"]} == {
            expected_start,
        }
        assert sum(block["planned_minutes"] for block in item["blocks"]) == 300


def test_weekly_wall_clock_time_survives_daylight_saving_change() -> None:
    now = datetime(2026, 10, 1, 8, tzinfo=UTC)
    service, series, _ = _service(now=now)
    request = _request(
        next_deadline_at="2026-10-24T10:00:00+02:00",
        remaining_occurrences=2,
        max_daily_minutes=360,
    )

    asyncio.run(service.propose(user_id="owner", request=request))

    berlin = ZoneInfo("Europe/Berlin")
    deadlines = [
        datetime.fromisoformat(item["deadline_at"]).astimezone(berlin)
        for item in series.persisted[0]["items"]
    ]
    assert [(value.date().isoformat(), value.hour) for value in deadlines] == [
        ("2026-10-24", 10),
        ("2026-10-31", 10),
    ]
    assert [value.utcoffset().total_seconds() for value in deadlines] == [7200, 3600]
    assert [
        item["proposal"]["planning_start_on"] for item in series.persisted[0]["items"]
    ] == [
        "2026-10-01",
        "2026-10-25",
    ]
    assert {
        block["local_date"] for block in series.persisted[0]["items"][1]["blocks"]
    } == {"2026-10-25"}


def test_whole_series_edit_retains_completed_and_overwrites_future_revision() -> None:
    service, series, deadline = _service()
    completed_id = UUID("40000000-0000-4000-8000-000000000001")
    future_id = UUID("40000000-0000-4000-8000-000000000002")
    created = datetime(2026, 7, 1, 8, tzinfo=UTC).isoformat()
    series.projection = AssignmentSeriesProjection(
        series=[
            {
                "id": str(SERIES_ID),
                "status": "active",
                "title": "Old title",
                "current_revision": 1,
                "latest_revision": 1,
                "created_at": created,
                "updated_at": created,
                "first_activated_at": created,
                "cancelled_at": None,
            },
        ],
        revisions=[
            {
                "series_id": str(SERIES_ID),
                "revision": 1,
                "base_revision": 0,
                "state": "active",
                "title": "Old title",
                "next_deadline_at": "2026-08-03T15:00:00Z",
                "remaining_occurrences": 2,
                "estimated_total_minutes": 60,
                "preferred_session_minutes": 30,
                "max_daily_minutes": 60,
                "buffer_days": 0,
                "use_calendar_availability": False,
                "timezone": "Europe/Berlin",
                "planned_minutes": 120,
                "unscheduled_minutes": 0,
                "created_at": created,
                "activated_at": created,
                "superseded_at": None,
            },
        ],
        occurrences=[
            {
                "series_id": str(SERIES_ID),
                "series_revision": 1,
                "position": 1,
                "action": "upsert",
                "plan_id": str(completed_id),
                "plan_revision": 1,
                "deadline_at": "2026-08-03T15:00:00Z",
            },
            {
                "series_id": str(SERIES_ID),
                "series_revision": 1,
                "position": 2,
                "action": "upsert",
                "plan_id": str(future_id),
                "plan_revision": 2,
                "deadline_at": "2026-08-17T15:00:00Z",
            },
        ],
    )
    series.deadline_plans = {
        completed_id: {
            "id": str(completed_id),
            "kind": "assignment",
            "status": "completed",
            "current_revision": 1,
            "latest_revision": 1,
        },
        future_id: {
            "id": str(future_id),
            "kind": "assignment",
            "status": "active",
            "current_revision": 2,
            "latest_revision": 3,
            "managed_task_id": None,
            "first_activated_at": created,
        },
    }
    deadline.plans = dict(series.deadline_plans)
    request = _request(
        base_revision=1,
        title="New shared template",
        next_deadline_at="2026-08-18T17:00:00+02:00",
        remaining_occurrences=1,
    )

    asyncio.run(service.propose(user_id="owner", request=request))

    items = series.persisted[0]["items"]
    retained = next(item for item in items if item["plan_id"] == str(completed_id))
    replaced = next(item for item in items if item["plan_id"] == str(future_id))
    assert retained["action"] == "retain"
    assert retained["deadline_at"] == "2026-08-03T15:00:00+00:00"
    assert replaced["action"] == "upsert"
    assert replaced["plan_revision"] == 4
    assert replaced["proposal"]["base_revision"] == 3
    assert replaced["proposal"]["title"] == "New shared template"
    assert replaced["proposal"]["credited_prior_minutes"] == 0
