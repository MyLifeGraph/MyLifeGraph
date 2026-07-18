import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

from app.repositories.deadline_plan_repository import SupabaseDeadlinePlanRepository


USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
PLAN_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
EVENT_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
CONNECTION_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
IMPORT_ID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"


class Client:
    def __init__(self) -> None:
        self.calls = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        if table == "profiles":
            return [{"timezone": "Europe/Berlin"}]
        if table == "intake_responses":
            return [{"responses": {"best_energy_window": "morning"}}]
        if table == "schedule_items":
            return []
        if table == "deadline_plan_blocks":
            return []
        if table == "calendar_connections":
            if params.get("id"):
                return [
                    {
                        "id": CONNECTION_ID,
                        "status": "connected",
                        "last_import_id": IMPORT_ID,
                        "imported_data_deleted_at": None,
                    },
                ]
            return [
                {
                    "id": CONNECTION_ID,
                    "status": "connected",
                    "last_import_id": IMPORT_ID,
                    "imported_data_deleted_at": None,
                },
            ]
        if table == "calendar_events" and params.get("id"):
            return [
                {
                    "id": str(EVENT_ID),
                    "user_id": USER_ID,
                    "connection_id": CONNECTION_ID,
                    "import_id": IMPORT_ID,
                    "source_fingerprint": "a" * 64,
                },
            ]
        if table == "calendar_events":
            return []
        if table == "focus_sessions":
            return []
        raise AssertionError((table, params))

    async def rpc(self, function, *, params):
        self.calls.append((function, params))
        return []


def test_planning_context_reads_only_current_minimal_calendar_projection() -> None:
    client = Client()
    repository = SupabaseDeadlinePlanRepository(client)

    context = asyncio.run(
        repository.load_planning_context(
            user_id=USER_ID,
            plan_id=PLAN_ID,
            starts_on=date(2026, 7, 20),
            range_starts_at=datetime(2026, 7, 20, tzinfo=UTC),
            range_ends_at=datetime(2026, 8, 1, tzinfo=UTC),
            source_calendar_event_id=EVENT_ID,
            include_calendar_availability=True,
        ),
    )

    source_call = next(
        params
        for table, params in client.calls
        if table == "calendar_events" and params.get("id")
    )
    assert source_call["select"] == (
        "id,user_id,connection_id,import_id,source_fingerprint"
    )
    connection_owner_call = next(
        params
        for table, params in client.calls
        if table == "calendar_connections" and params.get("id")
    )
    assert connection_owner_call["user_id"] == f"eq.{USER_ID}"
    for table, params in client.calls:
        if table == "calendar_events" and not params.get("id"):
            assert params["connection_id"] == f"eq.{CONNECTION_ID}"
            assert params["import_id"] == f"eq.{IMPORT_ID}"
    assert context.calendar_availability_current is True
    assert str(context.availability_import_id) == IMPORT_ID


def test_focus_query_is_activation_bounded_and_has_overflow_sentinel() -> None:
    client = Client()
    repository = SupabaseDeadlinePlanRepository(client)
    activated_at = datetime(2026, 7, 20, 9, tzinfo=UTC)

    asyncio.run(
        repository.list_completed_focus(
            user_id=USER_ID,
            task_id=PLAN_ID,
            started_at_or_after=activated_at,
        ),
    )

    params = client.calls[-1][1]
    assert params["status"] == "eq.completed"
    assert params["started_at"] == f"gte.{activated_at.isoformat()}"
    assert params["limit"] == "1000"
    assert params["offset"] == "0"


class CappedPagingClient:
    def __init__(self, rows: list[dict]) -> None:
        self.rows = rows
        self.calls = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        offset = int(params.get("offset", 0))
        requested = int(params["limit"])
        effective_limit = min(requested, 1_000)
        return self.rows[offset : offset + effective_limit]


def test_focus_query_pages_past_postgrest_max_rows() -> None:
    rows = [
        {
            "id": str(index),
            "started_at": "2026-07-20T09:00:00+00:00",
            "ended_at": "2026-07-20T09:05:00+00:00",
            "actual_minutes": 5,
            "status": "completed",
        }
        for index in range(1_001)
    ]
    client = CappedPagingClient(rows)
    repository = SupabaseDeadlinePlanRepository(client)

    result = asyncio.run(
        repository.list_completed_focus(
            user_id=USER_ID,
            task_id=PLAN_ID,
            started_at_or_after=datetime(2026, 7, 20, 9, tzinfo=UTC),
        ),
    )

    assert len(result) == 1_001
    assert [params["offset"] for _, params in client.calls] == ["0", "1000"]
    assert [params["limit"] for _, params in client.calls] == ["1000", "1000"]


class CappedScheduleClient(Client):
    def __init__(self) -> None:
        super().__init__()
        self.schedule_rows = [
            {
                "id": str(index),
                "weekday": 1,
                "starts_at": "09:00:00",
                "ends_at": "10:00:00",
                "updated_at": "2026-07-20T08:00:00+00:00",
            }
            for index in range(1_001)
        ]

    async def select(self, table, *, params):
        if table != "schedule_items":
            return await super().select(table, params=params)
        self.calls.append((table, params))
        offset = int(params.get("offset", 0))
        limit = min(int(params["limit"]), 1_000)
        return self.schedule_rows[offset : offset + limit]


def test_planning_context_pages_to_the_schedule_overflow_sentinel() -> None:
    client = CappedScheduleClient()
    repository = SupabaseDeadlinePlanRepository(client)

    context = asyncio.run(
        repository.load_planning_context(
            user_id=USER_ID,
            plan_id=PLAN_ID,
            starts_on=date(2026, 7, 20),
            range_starts_at=datetime(2026, 7, 20, tzinfo=UTC),
            range_ends_at=datetime(2026, 8, 1, tzinfo=UTC),
            source_calendar_event_id=None,
            include_calendar_availability=False,
        ),
    )

    assert len(context.schedule_items) == 1_001
    schedule_calls = [
        params for table, params in client.calls if table == "schedule_items"
    ]
    assert [params["offset"] for params in schedule_calls] == ["0", "1000"]
    assert [params["limit"] for params in schedule_calls] == ["1000", "1"]


class BulkClient:
    def __init__(self, plan_ids: list[UUID], *, block_count: int = 0) -> None:
        self.plan_ids = plan_ids
        self.block_count = block_count
        self.calls = []

    async def rpc(self, function, *, params):
        self.calls.append(("rpc", function, params))
        if function == "get_deadline_plan_projection_v1":
            plans = [{"id": str(plan_id)} for plan_id in self.plan_ids]
            blocks = [
                {
                    "id": str(index),
                    "plan_id": str(self.plan_ids[index % len(self.plan_ids)]),
                }
                for index in range(self.block_count)
            ]
            focus = [
                {
                    "plan_id": str(plan_id),
                    "focus_count": 0,
                    "tracked_focus_minutes": 0,
                }
                for plan_id in self.plan_ids
            ]
            return {
                "plan_count": len(plans),
                "plans": plans,
                "revision_count": 0,
                "revisions": [],
                "block_count": len(blocks),
                "blocks": blocks,
                "focus_total_count": len(focus),
                "focus_totals": focus,
                "calendar_event_count": 0,
                "calendar_events": [],
            }
        raise AssertionError(function)


def test_fifty_plan_projection_uses_one_atomic_backend_call() -> None:
    plan_ids = [UUID(int=index + 1) for index in range(50)]
    client = BulkClient(plan_ids)
    repository = SupabaseDeadlinePlanRepository(client)

    projection = asyncio.run(
        repository.load_projection(user_id=USER_ID, plan_id=None),
    )

    assert len(projection.focus_totals) == 50
    assert len(client.calls) == 1
    assert client.calls[0][1] == "get_deadline_plan_projection_v1"
    assert client.calls[0][2] == {"p_user_id": USER_ID}


def test_bulk_block_rpc_is_not_truncated_at_postgrest_thousand_rows() -> None:
    plan_ids = [UUID(int=index + 1) for index in range(10)]
    client = BulkClient(plan_ids, block_count=1_200)
    repository = SupabaseDeadlinePlanRepository(client)

    projection = asyncio.run(
        repository.load_projection(user_id=USER_ID, plan_id=None),
    )

    assert len(projection.blocks) == 1_200


def test_detail_projection_passes_exact_plan_to_same_snapshot_rpc() -> None:
    client = BulkClient([PLAN_ID])
    repository = SupabaseDeadlinePlanRepository(client)

    projection = asyncio.run(
        repository.load_projection(user_id=USER_ID, plan_id=PLAN_ID),
    )

    assert projection.plans == [{"id": str(PLAN_ID)}]
    assert client.calls == [
        (
            "rpc",
            "get_deadline_plan_projection_v1",
            {"p_user_id": USER_ID, "p_plan_id": str(PLAN_ID)},
        ),
    ]


class AtomicSourceClient:
    def __init__(self) -> None:
        self.calls = []

    async def rpc(self, function, *, params):
        self.calls.append((function, params))
        return {
            "plan_count": 1,
            "plans": [{"id": str(PLAN_ID)}],
            "revision_count": 1,
            "revisions": [
                {
                    "plan_id": str(PLAN_ID),
                    "revision": 1,
                    "source_calendar_event_id": str(EVENT_ID),
                },
            ],
            "block_count": 0,
            "blocks": [],
            "focus_total_count": 1,
            "focus_totals": [
                {
                    "plan_id": str(PLAN_ID),
                    "focus_count": 0,
                    "tracked_focus_minutes": 0,
                },
            ],
            "calendar_event_count": 1,
            "calendar_events": [
                {
                    "id": str(EVENT_ID),
                    "connection_id": CONNECTION_ID,
                    "import_id": IMPORT_ID,
                    "source_fingerprint": "a" * 64,
                    "_connection_status": "connected",
                    "_connection_last_import_id": IMPORT_ID,
                    "_connection_imported_data_deleted_at": None,
                },
            ],
        }


def test_calendar_source_and_revision_share_one_atomic_snapshot_call() -> None:
    client = AtomicSourceClient()
    repository = SupabaseDeadlinePlanRepository(client)

    projection = asyncio.run(
        repository.load_projection(user_id=USER_ID, plan_id=PLAN_ID),
    )

    source = projection.calendar_events[str(EVENT_ID)]
    assert source["source_fingerprint"] == "a" * 64
    assert source["_connection_status"] == "connected"
    assert source["_connection_last_import_id"] == IMPORT_ID
    assert client.calls == [
        (
            "get_deadline_plan_projection_v1",
            {"p_user_id": USER_ID, "p_plan_id": str(PLAN_ID)},
        ),
    ]
