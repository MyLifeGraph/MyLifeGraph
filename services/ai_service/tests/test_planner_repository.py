import asyncio
from datetime import date
from uuid import UUID

from app.repositories.planner_repository import (
    SupabasePlannerRepository,
    _planner_habits,
)


CONNECTION_ID = UUID("10000000-0000-4000-8000-000000000001")
IMPORT_ID = UUID("20000000-0000-4000-8000-000000000001")


class Client:
    def __init__(self) -> None:
        self.calls = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        if table == "profiles":
            return [{"timezone": "Europe/Berlin"}]
        if table == "intake_responses":
            return [{"responses": {"best_energy_window": "morning"}}]
        return []


def test_availability_schedule_read_includes_semester_metadata() -> None:
    client = Client()
    repository = SupabasePlannerRepository(client)

    context = asyncio.run(
        repository.load_availability_context(
            user_id="owner",
            plan_id=UUID("10000000-0000-4000-8000-000000000001"),
            target_kind="task",
            target_id=UUID("20000000-0000-4000-8000-000000000001"),
            starts_on=date(2026, 7, 20),
            ends_on=date(2026, 7, 27),
        ),
    )

    assert context.schedule_items == []
    params = next(params for table, params in client.calls if table == "schedule_items")
    assert "metadata" in params["select"]


class CalendarClient:
    def __init__(self, *, planning_status: str) -> None:
        self.planning_status = planning_status
        self.calls: list[tuple[str, dict[str, str]]] = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        if table == "calendar_connections":
            return [
                {
                    "id": str(CONNECTION_ID),
                    "last_import_id": str(IMPORT_ID),
                    "status": "connected",
                    "imported_data_deleted_at": None,
                },
            ]
        if table == "calendar_imports":
            return [
                {
                    "id": str(IMPORT_ID),
                    "planning_status": self.planning_status,
                },
            ]
        if table == "calendar_events":
            return [
                {
                    "id": "30000000-0000-4000-8000-000000000001",
                    "event_kind": "timed",
                    "starts_at": "2026-07-20T08:00:00Z",
                    "ends_at": "2026-07-20T09:00:00Z",
                },
            ]
        return []


def test_stale_calendar_import_is_unavailable_without_authoritative_identity() -> None:
    client = CalendarClient(planning_status="stale")
    repository = SupabasePlannerRepository(client)

    projection = asyncio.run(
        repository._calendar(user_id="owner", include_events=True),
    )

    assert projection.available is False
    assert projection.connection_id == CONNECTION_ID
    assert projection.import_id is None
    assert projection.timed_events == []
    assert projection.all_day_events == []
    assert all(table != "calendar_events" for table, _ in client.calls)


def test_only_current_calendar_import_projects_its_exact_events() -> None:
    client = CalendarClient(planning_status="current")
    repository = SupabasePlannerRepository(client)

    projection = asyncio.run(
        repository._calendar(user_id="owner", include_events=True),
    )

    assert projection.available is True
    assert projection.import_id == IMPORT_ID
    assert len(projection.timed_events) == 1
    event_params = next(
        params for table, params in client.calls if table == "calendar_events"
    )
    assert event_params["connection_id"] == f"eq.{CONNECTION_ID}"
    assert event_params["import_id"] == f"eq.{IMPORT_ID}"


def test_shared_habit_projection_preserves_created_at_then_id_order() -> None:
    rows = _planner_habits(
        active=[
            {
                "id": "30000000-0000-4000-8000-000000000002",
                "title": "Alphabetically first",
                "created_at": "2026-07-20T09:00:00Z",
            },
        ],
        inactive=[
            {
                "id": "30000000-0000-4000-8000-000000000001",
                "title": "Alphabetically last",
                "created_at": "2026-07-20T08:00:00Z",
            },
        ],
    )

    assert [row["title"] for row in rows] == [
        "Alphabetically last",
        "Alphabetically first",
    ]
    assert [row["created_at"] for row in rows] == [
        "2026-07-20T08:00:00Z",
        "2026-07-20T09:00:00Z",
    ]


def test_overview_task_read_keeps_all_current_targets_for_authoritative_snapshots() -> None:
    client = Client()
    repository = SupabasePlannerRepository(client)

    assert asyncio.run(repository._overview_tasks(user_id="owner")) == []

    params = next(params for table, params in client.calls if table == "tasks")
    assert "status" in params["select"]
    assert "priority" in params["select"]
    assert "metadata" in params["select"]
    assert "updated_at" in params["select"]
    assert "deadline" in params["select"]
    assert "estimated_minutes" in params["select"]
    assert "status" not in params
    assert params["order"] == "created_at.asc,id.asc"
