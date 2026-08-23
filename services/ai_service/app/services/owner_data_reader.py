import asyncio
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from typing import Any, Protocol, TypeVar

from app.owner_data_catalog import OwnerDataSource


class OwnerDataRepository(Protocol):
    async def get_export_watermark(
        self,
        *,
        user_id: str,
        table: OwnerDataSource,
        max_response_bytes: int,
    ) -> str | None: ...

    async def list_export_rows(
        self,
        *,
        user_id: str,
        table: OwnerDataSource,
        after_cursor: str | None,
        not_after: str,
        limit: int,
        max_response_bytes: int,
    ) -> list[dict[str, Any]]: ...


class OwnerDataReadError(RuntimeError):
    pass


class OwnerDataInvalidPageError(OwnerDataReadError):
    pass


class OwnerDataInvalidOwnerError(OwnerDataReadError):
    pass


class OwnerDataInvalidCursorError(OwnerDataReadError):
    pass


class OwnerDataSourceRowsExceededError(OwnerDataReadError):
    def __init__(self, source_name: str) -> None:
        super().__init__(source_name)
        self.source_name = source_name


class OwnerDataTotalRowsExceededError(OwnerDataReadError):
    pass


class OwnerDataSerializedBytesExceededError(OwnerDataReadError):
    pass


@dataclass(frozen=True, slots=True)
class OwnerDataReadPolicy:
    page_size: int
    max_rows_per_source: int
    max_total_rows: int
    max_serialized_bytes: int
    watermark_max_response_bytes: int
    max_concurrency: int = 4

    def validate(self) -> None:
        if any(
            value <= 0
            for value in (
                self.page_size,
                self.max_rows_per_source,
                self.max_total_rows,
                self.max_serialized_bytes,
                self.watermark_max_response_bytes,
                self.max_concurrency,
            )
        ):
            raise ValueError("Owner-data read limits must be positive.")


@dataclass(frozen=True, slots=True)
class OwnerDataReadResult:
    rows_by_source: dict[str, list[dict[str, Any]]]
    total_rows: int
    serialized_bytes: int


TransformRow = Callable[
    [OwnerDataSource, dict[str, Any]],
    dict[str, Any],
]
SerializedRowGrowth = Callable[
    [OwnerDataSource, int, dict[str, Any]],
    int,
]
PageResponseBytes = Callable[[int], int]
Item = TypeVar("Item")
Result = TypeVar("Result")


class OwnerDataReader:
    def __init__(self, *, repository: OwnerDataRepository) -> None:
        self._repository = repository

    async def collect(
        self,
        *,
        user_id: str,
        sources: Sequence[OwnerDataSource],
        policy: OwnerDataReadPolicy,
        initial_serialized_bytes: int,
        transform_row: TransformRow,
        serialized_row_growth: SerializedRowGrowth,
        page_response_bytes: PageResponseBytes,
    ) -> OwnerDataReadResult:
        policy.validate()
        if initial_serialized_bytes < 0:
            raise ValueError("Initial owner-data size must not be negative.")
        if initial_serialized_bytes > policy.max_serialized_bytes:
            raise OwnerDataSerializedBytesExceededError
        source_names = tuple(source.name for source in sources)
        if len(source_names) != len(set(source_names)):
            raise ValueError("Owner-data sources must be unique.")

        watermark_values = await _bounded_map(
            sources,
            max_concurrency=policy.max_concurrency,
            operation=lambda source: self._repository.get_export_watermark(
                user_id=user_id,
                table=source,
                max_response_bytes=policy.watermark_max_response_bytes,
            ),
        )
        watermarks = dict(zip(source_names, watermark_values, strict=True))
        state = _CollectionState(
            rows_by_source={name: [] for name in source_names},
            total_rows=0,
            serialized_bytes=initial_serialized_bytes,
        )
        active_sources = tuple(
            source for source in sources if watermarks[source.name] is not None
        )
        await _bounded_map(
            active_sources,
            max_concurrency=policy.max_concurrency,
            operation=lambda source: self._load_source(
                user_id=user_id,
                source=source,
                not_after=_watermark(watermarks[source.name]),
                policy=policy,
                state=state,
                transform_row=transform_row,
                serialized_row_growth=serialized_row_growth,
                page_response_bytes=page_response_bytes,
            ),
        )
        return OwnerDataReadResult(
            rows_by_source=state.rows_by_source,
            total_rows=state.total_rows,
            serialized_bytes=state.serialized_bytes,
        )

    async def _load_source(
        self,
        *,
        user_id: str,
        source: OwnerDataSource,
        not_after: str,
        policy: OwnerDataReadPolicy,
        state: "_CollectionState",
        transform_row: TransformRow,
        serialized_row_growth: SerializedRowGrowth,
        page_response_bytes: PageResponseBytes,
    ) -> None:
        after_cursor: str | None = None
        while True:
            async with state.lock:
                source_count = len(state.rows_by_source[source.name])
                remaining = policy.max_rows_per_source - source_count
                request_limit = min(policy.page_size, remaining + 1)
                max_response_bytes = page_response_bytes(state.serialized_bytes)
            if max_response_bytes <= 0:
                raise ValueError("Owner-data page byte bound must be positive.")
            page = await self._repository.list_export_rows(
                user_id=user_id,
                table=source,
                after_cursor=after_cursor,
                not_after=not_after,
                limit=request_limit,
                max_response_bytes=max_response_bytes,
            )
            _validate_page(
                page=page,
                source=source,
                user_id=user_id,
                after_cursor=after_cursor,
                request_limit=request_limit,
            )
            async with state.lock:
                target = state.rows_by_source[source.name]
                remaining = policy.max_rows_per_source - len(target)
                if len(page) > remaining:
                    raise OwnerDataSourceRowsExceededError(source.name)
                if state.total_rows + len(page) > policy.max_total_rows:
                    raise OwnerDataTotalRowsExceededError
                for row in page:
                    transformed = transform_row(source, row)
                    growth = serialized_row_growth(
                        source,
                        len(target),
                        transformed,
                    )
                    if growth < 0:
                        raise ValueError(
                            "Owner-data serialized growth must not be negative.",
                        )
                    if state.serialized_bytes + growth > policy.max_serialized_bytes:
                        raise OwnerDataSerializedBytesExceededError
                    target.append(transformed)
                    state.total_rows += 1
                    state.serialized_bytes += growth
                if page:
                    after_cursor = str(page[-1][source.cursor_column])
            if len(page) < request_limit:
                return


class _CollectionState:
    def __init__(
        self,
        *,
        rows_by_source: dict[str, list[dict[str, Any]]],
        total_rows: int,
        serialized_bytes: int,
    ) -> None:
        self.rows_by_source = rows_by_source
        self.total_rows = total_rows
        self.serialized_bytes = serialized_bytes
        self.lock = asyncio.Lock()


def _validate_page(
    *,
    page: object,
    source: OwnerDataSource,
    user_id: str,
    after_cursor: str | None,
    request_limit: int,
) -> None:
    if (
        not isinstance(page, list)
        or len(page) > request_limit
        or any(not isinstance(row, dict) for row in page)
    ):
        raise OwnerDataInvalidPageError
    previous = after_cursor
    for row in page:
        if row.get(source.owner_column) != user_id:
            raise OwnerDataInvalidOwnerError
        cursor = row.get(source.cursor_column)
        if (
            not isinstance(cursor, str)
            or not cursor
            or (previous is not None and cursor <= previous)
        ):
            raise OwnerDataInvalidCursorError
        previous = cursor


async def _bounded_map(
    items: Sequence[Item],
    *,
    max_concurrency: int,
    operation: Callable[[Item], Awaitable[Result]],
) -> list[Result]:
    semaphore = asyncio.Semaphore(max_concurrency)

    async def run(item: Item) -> Result:
        async with semaphore:
            return await operation(item)

    tasks = [asyncio.create_task(run(item)) for item in items]
    try:
        return await asyncio.gather(*tasks)
    except BaseException:
        for task in tasks:
            if not task.done():
                task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        raise


def _watermark(value: str | None) -> str:
    if value is None:
        raise RuntimeError("Owner-data watermark is missing.")
    return value
