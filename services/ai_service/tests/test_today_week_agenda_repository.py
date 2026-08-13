import asyncio
from copy import deepcopy
from datetime import UTC, date, datetime
from typing import Any

import httpx
import pytest

from app.repositories.today_overview_repository import (
    SupabaseTodayOverviewRepository,
)
from app.repositories.today_week_agenda_repository import (
    SupabaseTodayWeekAgendaRepository,
)


USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
CONNECTION_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
IMPORT_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
RANGE_START = datetime(2026, 8, 9, 22, tzinfo=UTC)
RANGE_END = datetime(2026, 8, 16, 22, tzinfo=UTC)


class Client:
    def __init__(self, responses: dict[str, list[dict[str, Any]]] | None = None):
        self.responses = responses or {}
        self.calls: list[tuple[str, dict[str, Any] | list[tuple[str, str]]]] = []

    async def select(self, table: str, *, params):
        self.calls.append((table, deepcopy(params)))
        return deepcopy(self.responses.get(table, []))


def test_current_calendar_uses_one_owner_scoped_overlap_range() -> None:
    client = Client(
        {
            "calendar_connections": [
                {
                    "id": CONNECTION_ID,
                    "source_label": "University",
                    "status": "connected",
                    "last_import_id": IMPORT_ID,
                    "imported_data_deleted_at": None,
                },
            ],
            "calendar_imports": [
                {"id": IMPORT_ID, "planning_status": "current"},
            ],
            "calendar_events": [
                {
                    "id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                    "event_kind": "timed",
                },
            ],
        },
    )
    repository = SupabaseTodayWeekAgendaRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.load_calendar(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
            range_starts_at=RANGE_START,
            range_ends_at=RANGE_END,
        ),
    )

    assert result.source_label == "University"
    assert len(result.events) == 1
    assert [table for table, _ in client.calls] == [
        "calendar_connections",
        "calendar_imports",
        "calendar_events",
    ]
    event_params = client.calls[-1][1]
    assert isinstance(event_params, list)
    assert ("user_id", f"eq.{USER_ID}") in event_params
    assert ("connection_id", f"eq.{CONNECTION_ID}") in event_params
    assert ("import_id", f"eq.{IMPORT_ID}") in event_params
    overlap = next(value for key, value in event_params if key == "or")
    assert f"starts_at.lt.{RANGE_END.isoformat()}" in overlap
    assert f"ends_at.gt.{RANGE_START.isoformat()}" in overlap
    assert "starts_on.lt.2026-08-17" in overlap
    assert "ends_on.gt.2026-08-10" in overlap


def test_disconnected_calendar_is_current_empty_without_import_reads() -> None:
    client = Client()
    repository = SupabaseTodayWeekAgendaRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.load_calendar(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
            range_starts_at=RANGE_START,
            range_ends_at=RANGE_END,
        ),
    )

    assert result.source_label is None
    assert result.events == []
    assert [table for table, _ in client.calls] == ["calendar_connections"]


@pytest.mark.parametrize(
    "repository_factory,method_name",
    [
        (SupabaseTodayWeekAgendaRepository, "load_calendar"),
        (SupabaseTodayOverviewRepository, "load_current_calendar"),
    ],
)
def test_connected_calendar_without_import_is_unavailable(
    repository_factory,
    method_name: str,
) -> None:
    client = Client(
        {
            "calendar_connections": [
                {
                    "id": CONNECTION_ID,
                    "source_label": "University",
                    "status": "connected",
                    "last_import_id": None,
                    "imported_data_deleted_at": None,
                },
            ],
        },
    )
    repository = repository_factory(client)
    kwargs = {"user_id": USER_ID}
    if method_name == "load_calendar":
        kwargs.update(
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
            range_starts_at=RANGE_START,
            range_ends_at=RANGE_END,
        )

    with pytest.raises(ValueError, match="not current"):
        asyncio.run(getattr(repository, method_name)(**kwargs))

    assert [table for table, _ in client.calls] == ["calendar_connections"]


@pytest.mark.parametrize(
    "repository_factory,method_name",
    [
        (SupabaseTodayWeekAgendaRepository, "load_calendar"),
        (SupabaseTodayOverviewRepository, "load_current_calendar"),
    ],
)
def test_stale_import_never_projects_calendar_events(
    repository_factory,
    method_name: str,
) -> None:
    client = Client(
        {
            "calendar_connections": [
                {
                    "id": CONNECTION_ID,
                    "source_label": "University",
                    "status": "connected",
                    "last_import_id": IMPORT_ID,
                    "imported_data_deleted_at": None,
                },
            ],
            "calendar_imports": [
                {"id": IMPORT_ID, "planning_status": "stale"},
            ],
            "calendar_events": [{"id": "must-not-be-read"}],
        },
    )
    repository = repository_factory(client)
    kwargs = {"user_id": USER_ID}
    if method_name == "load_calendar":
        kwargs.update(
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
            range_starts_at=RANGE_START,
            range_ends_at=RANGE_END,
        )

    with pytest.raises(ValueError, match="not current"):
        asyncio.run(getattr(repository, method_name)(**kwargs))

    assert all(table != "calendar_events" for table, _ in client.calls)


def test_all_non_calendar_sources_are_dedicated_bounded_owner_range_reads() -> None:
    client = Client(
        {
            "deadline_plans": [
                {
                    "id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                    "status": "active",
                    "current_revision": 1,
                    "managed_task_id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                    "first_activated_at": "2026-08-01T08:00:00+00:00",
                },
            ],
        },
    )
    repository = SupabaseTodayWeekAgendaRepository(client)  # type: ignore[arg-type]

    async def read_sources() -> None:
        await repository.list_setup(user_id=USER_ID)
        await repository.load_preparation(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
        )
        await repository.list_focus(
            user_id=USER_ID,
            range_starts_at=RANGE_START,
            range_ends_at=RANGE_END,
        )
        await repository.load_tasks(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
        )
        await repository.load_habits(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
        )
        await repository.list_fixed_commitments(
            user_id=USER_ID,
            range_starts_at=RANGE_START,
            range_ends_at=RANGE_END,
        )

    asyncio.run(read_sources())

    assert [table for table, _ in client.calls] == [
        "schedule_items",
        "deadline_plans",
        "deadline_plan_blocks",
        "deadline_plan_revisions",
        "deadline_plan_blocks",
        "focus_sessions",
        "focus_sessions",
        "planner_action_plans",
        "planner_task_blocks",
        "tasks",
        "planner_action_plans",
        "planner_habit_slots",
        "habits",
        "habit_logs",
        "planner_commitments",
    ]
    for _, raw_params in client.calls:
        assert _param_values(raw_params, "user_id") == [f"eq.{USER_ID}"]
        limits = _param_values(raw_params, "limit")
        assert limits and int(limits[-1]) > 0
    for table, field in (
        ("deadline_plan_blocks", "local_date"),
        ("planner_task_blocks", "local_date"),
        ("habit_logs", "entry_date"),
    ):
        matches = [
            params
            for called_table, params in client.calls
            if called_table == table and _param_values(params, field)
        ]
        assert len(matches) == 1
        raw = matches[0]
        assert _param_values(raw, field) == [
            "gte.2026-08-10",
            "lte.2026-08-16",
        ]
        assert [
            value for key, value in httpx.QueryParams(raw).multi_items() if key == field
        ] == ["gte.2026-08-10", "lte.2026-08-16"]
    commitment_filters = _param_values(
        next(
            params for table, params in client.calls if table == "planner_commitments"
        ),
        "or",
    )
    assert len(commitment_filters) == 1
    assert "starts_at.lt.2026-08-16T22:00:00+00:00" in commitment_filters[0]


def test_preparation_reads_are_batched_and_do_not_scale_per_plan() -> None:
    plans = [
        {
            "id": f"10000000-0000-4000-8000-{index:012d}",
            "status": "active",
            "current_revision": 1,
            "managed_task_id": f"10000000-0000-4000-8000-{index:012d}",
            "first_activated_at": "2026-08-01T08:00:00+00:00",
        }
        for index in range(161)
    ]
    client = Client({"deadline_plans": plans})
    repository = SupabaseTodayWeekAgendaRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.load_preparation(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
        ),
    )

    assert len(result.plans) == 161
    assert [table for table, _ in client.calls] == [
        "deadline_plans",
        "deadline_plan_blocks",
        "deadline_plan_revisions",
        "deadline_plan_blocks",
        "focus_sessions",
    ]


def test_preparation_batches_focus_credit_and_exact_source_provenance() -> None:
    plan_id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    block_id = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    focus_id = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    client = Client(
        {
            "deadline_plans": [
                {
                    "id": plan_id,
                    "status": "active",
                    "current_revision": 1,
                    "managed_task_id": plan_id,
                    "first_activated_at": "2026-08-01T08:00:00+00:00",
                },
            ],
            "deadline_plan_revisions": [
                {
                    "plan_id": plan_id,
                    "revision": 1,
                    "state": "active",
                    "tracked_focus_minutes_at_proposal": 0,
                },
            ],
            "deadline_plan_blocks": [
                {
                    "id": block_id,
                    "plan_id": plan_id,
                    "revision": 1,
                    "sequence": 1,
                    "local_date": "2026-08-12",
                    "starts_at": "2026-08-12T08:00:00+00:00",
                    "ends_at": "2026-08-12T09:00:00+00:00",
                    "planned_minutes": 60,
                    "reservation_state": "active",
                },
            ],
            "focus_sessions": [
                {
                    "id": focus_id,
                    "task_id": plan_id,
                    "started_at": "2026-08-12T08:00:00+00:00",
                    "actual_minutes": 30,
                    "status": "completed",
                },
            ],
            "focus_session_schedule_sources": [
                {
                    "focus_session_id": focus_id,
                    "deadline_plan_block_id": block_id,
                },
            ],
        },
    )
    repository = SupabaseTodayWeekAgendaRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.load_preparation(
            user_id=USER_ID,
            week_starts_on=date(2026, 8, 10),
            week_ends_on=date(2026, 8, 16),
        ),
    )

    assert result.focus_facts == [
        {
            "id": focus_id,
            "plan_id": plan_id,
            "started_at": "2026-08-12T08:00:00+00:00",
            "actual_minutes": 30,
            "deadline_plan_block_id": block_id,
        },
    ]
    source_params = next(
        params
        for table, params in client.calls
        if table == "focus_session_schedule_sources"
    )
    assert _param_values(source_params, "user_id") == [f"eq.{USER_ID}"]
    assert _param_values(source_params, "source_kind") == [
        "eq.deadline_plan_block",
    ]
    assert _param_values(source_params, "created_at") == [
        "gte.2026-08-01T08:00:00+00:00",
    ]


def _param_values(
    params: dict[str, Any] | list[tuple[str, str]],
    key: str,
) -> list[str]:
    if isinstance(params, list):
        return [value for name, value in params if name == key]
    value = params.get(key)
    return [] if value is None else [str(value)]
