import asyncio
from typing import Any

import pytest

from app.repositories.deadline_plan_repository import (
    SupabaseDeadlinePlanRepository,
)
from app.repositories.planner_repository import SupabasePlannerRepository
from app.repositories.repository_pagination import (
    select_keyset_pages,
    select_offset_pages,
)
from app.repositories.today_overview_repository import (
    SupabaseTodayOverviewRepository,
)


def run(coro):
    return asyncio.run(coro)


class OffsetClient:
    def __init__(
        self,
        rows: list[dict[str, Any]],
        *,
        overfull: bool = False,
        error: Exception | None = None,
    ) -> None:
        self.rows = rows
        self.overfull = overfull
        self.error = error
        self.calls: list[tuple[str, object]] = []

    async def select(self, table: str, *, params):
        self.calls.append((table, params))
        if self.error is not None:
            raise self.error
        values = dict(params)
        offset = int(values["offset"])
        limit = int(values["limit"])
        extra = 1 if self.overfull else 0
        return self.rows[offset : offset + limit + extra]


@pytest.mark.parametrize(
    ("row_count", "max_rows", "expected_count", "expected_pages"),
    [
        (0, 10, 0, [(3, 0)]),
        (2, 10, 2, [(3, 0)]),
        (3, 3, 3, [(3, 0)]),
        (6, 10, 6, [(3, 0), (3, 3), (3, 6)]),
        (7, 5, 5, [(3, 0), (2, 3)]),
    ],
)
def test_offset_pages_preserve_end_and_max_row_semantics(
    row_count: int,
    max_rows: int,
    expected_count: int,
    expected_pages: list[tuple[int, int]],
) -> None:
    client = OffsetClient([{"id": index} for index in range(row_count)])
    params = {"select": "id", "user_id": "eq.owner", "order": "id.asc"}

    rows = run(
        select_offset_pages(
            client,
            "items",
            params=params,
            page_size=3,
            max_rows=max_rows,
            overfull_error="source returned too many rows",
        ),
    )

    assert len(rows) == expected_count
    assert params == {
        "select": "id",
        "user_id": "eq.owner",
        "order": "id.asc",
    }
    assert [
        (int(call_params["limit"]), int(call_params["offset"]))
        for _, call_params in client.calls
    ] == expected_pages
    assert all(
        call_params["user_id"] == "eq.owner" for _, call_params in client.calls
    )


def test_offset_pages_preserve_repeated_list_params() -> None:
    client = OffsetClient([{"id": index} for index in range(4)])
    params = [
        ("entry_date", "gte.2026-07-01"),
        ("entry_date", "lte.2026-07-07"),
        ("order", "entry_date.asc,id.asc"),
    ]

    rows = run(
        select_offset_pages(
            client,
            "habit_logs",
            params=params,
            page_size=3,
            max_rows=4,
            overfull_error="source returned too many rows",
        ),
    )

    assert len(rows) == 4
    assert client.calls == [
        (
            "habit_logs",
            [*params, ("limit", "3"), ("offset", "0")],
        ),
        (
            "habit_logs",
            [*params, ("limit", "1"), ("offset", "3")],
        ),
    ]


def test_offset_pages_keep_caller_error_for_overfull_page() -> None:
    client = OffsetClient([{"id": index} for index in range(4)], overfull=True)

    with pytest.raises(ValueError, match="^exact repository error$"):
        run(
            select_offset_pages(
                client,
                "items",
                params={"order": "id.asc"},
                page_size=3,
                max_rows=5,
                overfull_error="exact repository error",
            ),
        )


@pytest.mark.parametrize(
    ("repository_type", "message"),
    [
        (
            SupabaseDeadlinePlanRepository,
            "PostgREST returned more rows than requested.",
        ),
        (
            SupabasePlannerRepository,
            "Planner source returned more rows than requested.",
        ),
        (
            SupabaseTodayOverviewRepository,
            "PostgREST returned more Today rows than requested.",
        ),
    ],
)
def test_offset_repositories_keep_exact_overfull_errors(
    repository_type,
    message: str,
) -> None:
    client = OffsetClient([{"id": index} for index in range(1_001)], overfull=True)
    repository = repository_type(client)

    with pytest.raises(ValueError) as raised:
        run(
            repository._select_pages(
                "items",
                params={"order": "id.asc"},
                max_rows=1_001,
            ),
        )

    assert str(raised.value) == message


def test_offset_pages_propagate_transport_errors_unchanged() -> None:
    failure = RuntimeError("transport failed")
    client = OffsetClient([], error=failure)

    with pytest.raises(RuntimeError) as raised:
        run(
            select_offset_pages(
                client,
                "items",
                params={"order": "id.asc"},
                page_size=3,
                max_rows=5,
                overfull_error="unused",
            ),
        )

    assert raised.value is failure


class KeysetClient:
    def __init__(
        self,
        pages: list[list[dict[str, Any]]],
        *,
        error: Exception | None = None,
    ) -> None:
        self.pages = pages
        self.error = error
        self.calls: list[tuple[str, object]] = []

    async def select(self, table: str, *, params):
        self.calls.append((table, params))
        if self.error is not None:
            raise self.error
        return self.pages[len(self.calls) - 1]


def _keyset_row(identifier: int) -> dict[str, Any]:
    return {
        "id": str(identifier),
        "updated_at": f"2026-07-0{identifier}T10:00:00+00:00",
    }


@pytest.mark.parametrize(
    ("pages", "expected_count", "expected_calls"),
    [
        ([[]], 0, 1),
        ([[_keyset_row(1)]], 1, 1),
        (
            [[_keyset_row(1), _keyset_row(2)], []],
            2,
            2,
        ),
        (
            [[_keyset_row(1), _keyset_row(2)], [_keyset_row(3)]],
            3,
            2,
        ),
        (
            [
                [_keyset_row(1), _keyset_row(2), _keyset_row(3)],
                [],
            ],
            3,
            2,
        ),
    ],
)
def test_keyset_pages_preserve_end_and_overfull_semantics(
    pages: list[list[dict[str, Any]]],
    expected_count: int,
    expected_calls: int,
) -> None:
    client = KeysetClient(pages)
    params = [
        ("user_id", "eq.owner"),
        ("order", "updated_at.desc,id.asc"),
    ]

    rows = run(
        select_keyset_pages(
            client,
            "items",
            params=params,
            page_size=2,
        ),
    )

    assert len(rows) == expected_count
    assert len(client.calls) == expected_calls
    assert params == [
        ("user_id", "eq.owner"),
        ("order", "updated_at.desc,id.asc"),
    ]
    assert all(("offset", "0") not in call_params for _, call_params in client.calls)
    if expected_calls > 1:
        second_params = client.calls[1][1]
        cursor = pages[0][-1]
        assert ("limit", "2") in second_params
        assert (
            "or",
            f"(updated_at.lt.{cursor['updated_at']},"
            f"and(updated_at.eq.{cursor['updated_at']},id.gt.{cursor['id']}))",
        ) in second_params


@pytest.mark.parametrize(
    ("params", "message"),
    [
        ([("select", "id")], "requires one explicit order"),
        (
            [("order", "created_at.asc,id.asc"), ("order", "id.asc")],
            "requires one explicit order",
        ),
        ([("order", "created_at.sideways,id.asc")], "order is invalid"),
        ([("order", "created_at.asc")], "requires id as the tie-breaker"),
    ],
)
def test_keyset_pages_reject_malformed_orders_before_loading(
    params: list[tuple[str, str]],
    message: str,
) -> None:
    client = KeysetClient([[]])

    with pytest.raises(ValueError, match=message):
        run(
            select_keyset_pages(
                client,
                "items",
                params=params,
                page_size=2,
            ),
        )

    assert client.calls == []


def test_keyset_pages_reject_missing_cursor_values_before_next_request() -> None:
    client = KeysetClient(
        [[_keyset_row(1), {"id": "2"}]],
    )

    with pytest.raises(ValueError, match="missing an ordered value"):
        run(
            select_keyset_pages(
                client,
                "items",
                params=[("order", "updated_at.desc,id.asc")],
                page_size=2,
            ),
        )

    assert len(client.calls) == 1


def test_keyset_pages_propagate_transport_errors_unchanged() -> None:
    failure = RuntimeError("transport failed")
    client = KeysetClient([], error=failure)

    with pytest.raises(RuntimeError) as raised:
        run(
            select_keyset_pages(
                client,
                "items",
                params=[("order", "id.asc")],
                page_size=2,
            ),
        )

    assert raised.value is failure
