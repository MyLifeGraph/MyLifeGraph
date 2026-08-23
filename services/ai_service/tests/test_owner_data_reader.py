import asyncio
from typing import Any

import pytest

from app.owner_data_catalog import OwnerDataSource
from app.services.owner_data_reader import (
    OwnerDataInvalidCursorError,
    OwnerDataReadPolicy,
    OwnerDataReader,
)


def _source(name: str) -> OwnerDataSource:
    return OwnerDataSource(
        name=name,
        owner_column="user_id",
        select="*",
        cursor_column="id",
        watermark_column="created_at",
    )


def _policy(*, max_concurrency: int = 2) -> OwnerDataReadPolicy:
    return OwnerDataReadPolicy(
        page_size=2,
        max_rows_per_source=10,
        max_total_rows=20,
        max_serialized_bytes=10_000,
        watermark_max_response_bytes=4096,
        max_concurrency=max_concurrency,
    )


async def _collect(
    repository,
    *,
    sources: tuple[OwnerDataSource, ...],
    max_concurrency: int = 2,
):
    return await OwnerDataReader(repository=repository).collect(
        user_id="owner-1",
        sources=sources,
        policy=_policy(max_concurrency=max_concurrency),
        initial_serialized_bytes=100,
        transform_row=lambda _source, row: {
            key: value for key, value in row.items() if key != "user_id"
        },
        serialized_row_growth=lambda _source, count, _row: 2 if count else 1,
        page_response_bytes=lambda serialized_bytes: 10_000 - serialized_bytes,
    )


class OrderedRepository:
    def __init__(self) -> None:
        self.rows = {
            "alpha": [
                {"id": "a-1", "user_id": "owner-1"},
                {"id": "a-2", "user_id": "owner-1"},
                {"id": "a-3", "user_id": "owner-1"},
            ],
            "beta": [{"id": "b-1", "user_id": "owner-1"}],
            "gamma": [{"id": "g-1", "user_id": "owner-1"}],
        }
        self.phases: list[tuple[str, str]] = []
        self.watermarks_completed: set[str] = set()
        self.active_watermarks = 0
        self.active_rows = 0
        self.max_active_watermarks = 0
        self.max_active_rows = 0

    async def get_export_watermark(
        self,
        *,
        user_id: str,
        table: OwnerDataSource,
        max_response_bytes: int,
    ) -> str:
        assert user_id == "owner-1"
        assert max_response_bytes == 4096
        self.phases.append(("watermark_start", table.name))
        self.active_watermarks += 1
        self.max_active_watermarks = max(
            self.max_active_watermarks,
            self.active_watermarks,
        )
        await asyncio.sleep({"alpha": 0.003, "beta": 0.002, "gamma": 0.001}[table.name])
        self.active_watermarks -= 1
        self.watermarks_completed.add(table.name)
        self.phases.append(("watermark_end", table.name))
        return "2026-08-02T12:00:00+00:00"

    async def list_export_rows(
        self,
        *,
        user_id: str,
        table: OwnerDataSource,
        after_cursor: str | None,
        not_after: str,
        limit: int,
        max_response_bytes: int,
    ) -> list[dict[str, Any]]:
        assert user_id == "owner-1"
        assert self.watermarks_completed == set(self.rows)
        assert not_after == "2026-08-02T12:00:00+00:00"
        assert max_response_bytes > 0
        self.phases.append(("rows_start", table.name))
        self.active_rows += 1
        self.max_active_rows = max(self.max_active_rows, self.active_rows)
        await asyncio.sleep({"alpha": 0.003, "beta": 0.002, "gamma": 0.001}[table.name])
        rows = self.rows[table.name]
        if after_cursor is not None:
            rows = [row for row in rows if str(row["id"]) > after_cursor]
        self.active_rows -= 1
        self.phases.append(("rows_end", table.name))
        return rows[:limit]


def test_reader_captures_all_watermarks_then_loads_with_bounded_concurrency() -> None:
    sources = (_source("alpha"), _source("beta"), _source("gamma"))
    repository = OrderedRepository()

    result = asyncio.run(_collect(repository, sources=sources))

    assert list(result.rows_by_source) == ["alpha", "beta", "gamma"]
    assert result.rows_by_source == {
        "alpha": [{"id": "a-1"}, {"id": "a-2"}, {"id": "a-3"}],
        "beta": [{"id": "b-1"}],
        "gamma": [{"id": "g-1"}],
    }
    assert result.total_rows == 5
    assert result.serialized_bytes == 107
    first_row_index = next(
        index
        for index, (phase, _name) in enumerate(repository.phases)
        if phase == "rows_start"
    )
    watermark_end_indexes = [
        index
        for index, (phase, _name) in enumerate(repository.phases)
        if phase == "watermark_end"
    ]
    assert len(watermark_end_indexes) == 3
    assert max(watermark_end_indexes) < first_row_index
    assert repository.max_active_watermarks == 2
    assert repository.max_active_rows == 2


class FailingRepository:
    def __init__(self, *, failure: Exception | None = None) -> None:
        self.failure = failure
        self.row_started = 0
        self.all_rows_started = asyncio.Event()
        self.settled: set[str] = set()

    async def get_export_watermark(self, **_kwargs) -> str:
        return "2026-08-02T12:00:00+00:00"

    async def list_export_rows(self, *, table: OwnerDataSource, **_kwargs):
        self.row_started += 1
        if self.row_started == 3:
            self.all_rows_started.set()
        try:
            await self.all_rows_started.wait()
            if table.name == "broken" and self.failure is not None:
                raise self.failure
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            self.settled.add(table.name)
            raise


def test_failed_source_cancels_and_settles_sibling_reads() -> None:
    failure = RuntimeError("source failed")
    repository = FailingRepository(failure=failure)
    sources = (_source("alpha"), _source("broken"), _source("gamma"))

    with pytest.raises(RuntimeError) as raised:
        asyncio.run(
            _collect(
                repository,
                sources=sources,
                max_concurrency=3,
            ),
        )

    assert raised.value is failure
    assert repository.settled == {"alpha", "gamma"}


def test_reader_cancellation_cancels_and_settles_active_and_waiting_reads() -> None:
    async def scenario() -> tuple[int, set[str]]:
        repository = FailingRepository()
        repository.all_rows_started = asyncio.Event()
        sources = (_source("alpha"), _source("beta"), _source("gamma"))
        task = asyncio.create_task(
            _collect(
                repository,
                sources=sources,
                max_concurrency=2,
            ),
        )
        while repository.row_started < 2:
            await asyncio.sleep(0)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        return repository.row_started, repository.settled

    row_started, settled = asyncio.run(scenario())

    assert row_started == 2
    assert settled == {"alpha", "beta"}


def test_reader_rejects_non_monotone_cursor_before_returning_partial_data() -> None:
    class InvalidCursorRepository:
        async def get_export_watermark(self, **_kwargs) -> str:
            return "2026-08-02T12:00:00+00:00"

        async def list_export_rows(self, **_kwargs):
            return [
                {"id": "same", "user_id": "owner-1"},
                {"id": "same", "user_id": "owner-1"},
            ]

    with pytest.raises(OwnerDataInvalidCursorError):
        asyncio.run(
            _collect(
                InvalidCursorRepository(),
                sources=(_source("alpha"),),
            ),
        )
