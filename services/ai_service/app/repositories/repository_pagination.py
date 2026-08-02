from collections.abc import Awaitable, Callable
from typing import Any, Protocol, TypeVar

from app.clients.supabase import QueryParams


class RepositoryPageClient(Protocol):
    async def select(
        self,
        table: str,
        *,
        params: QueryParams,
    ) -> list[dict[str, Any]]: ...


Position = TypeVar("Position")
PageLoader = Callable[[int, Position], Awaitable[list[dict[str, Any]]]]
PositionAdvancer = Callable[[Position, list[dict[str, Any]]], Position]


async def _collect_pages(
    *,
    load_page: PageLoader[Position],
    page_size: int,
    initial_position: Position,
    advance_position: PositionAdvancer[Position],
    max_rows: int | None,
    overfull_error: str | None,
) -> list[dict[str, Any]]:
    if page_size <= 0:
        raise ValueError("Repository page size must be positive.")
    if max_rows is not None and max_rows < 0:
        raise ValueError("Repository row limit must not be negative.")

    rows: list[dict[str, Any]] = []
    position = initial_position
    while max_rows is None or len(rows) < max_rows:
        page_limit = (
            page_size
            if max_rows is None
            else min(page_size, max_rows - len(rows))
        )
        page = await load_page(page_limit, position)
        if overfull_error is not None and len(page) > page_limit:
            raise ValueError(overfull_error)
        rows.extend(page)
        if len(page) < page_limit:
            break
        position = advance_position(position, page)
    return rows


async def select_offset_pages(
    client: RepositoryPageClient,
    table: str,
    *,
    params: QueryParams,
    page_size: int,
    max_rows: int,
    overfull_error: str,
) -> list[dict[str, Any]]:
    async def load_page(
        page_limit: int,
        offset: int,
    ) -> list[dict[str, Any]]:
        if isinstance(params, list):
            page_params: QueryParams = [
                *params,
                ("limit", str(page_limit)),
                ("offset", str(offset)),
            ]
        else:
            page_params = {
                **params,
                "limit": str(page_limit),
                "offset": str(offset),
            }
        return await client.select(table, params=page_params)

    return await _collect_pages(
        load_page=load_page,
        page_size=page_size,
        initial_position=0,
        advance_position=lambda offset, page: offset + len(page),
        max_rows=max_rows,
        overfull_error=overfull_error,
    )


async def select_keyset_pages(
    client: RepositoryPageClient,
    table: str,
    *,
    params: list[tuple[str, str]],
    page_size: int,
) -> list[dict[str, Any]]:
    order = _order_columns(params)

    async def load_page(
        page_limit: int,
        cursor: dict[str, Any] | None,
    ) -> list[dict[str, Any]]:
        page_params = [*params, ("limit", str(page_limit))]
        if cursor is not None:
            page_params.append(("or", _keyset_filter(order, cursor)))
        return await client.select(table, params=page_params)

    return await _collect_pages(
        load_page=load_page,
        page_size=page_size,
        initial_position=None,
        advance_position=lambda _cursor, page: page[-1],
        max_rows=None,
        overfull_error=None,
    )


def _order_columns(
    params: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    values = [value for key, value in params if key == "order"]
    if len(values) != 1:
        raise ValueError("Keyset pagination requires one explicit order.")
    order: list[tuple[str, str]] = []
    for item in values[0].split(","):
        pieces = item.split(".")
        direction = pieces[1] if len(pieces) > 1 else "asc"
        if direction not in {"asc", "desc"}:
            raise ValueError("Keyset pagination order is invalid.")
        order.append((pieces[0], direction))
    if not order or order[-1][0] != "id":
        raise ValueError("Keyset pagination requires id as the tie-breaker.")
    return order


def _keyset_filter(
    order: list[tuple[str, str]],
    cursor: dict[str, Any],
) -> str:
    branches: list[str] = []
    equals: list[str] = []
    for column, direction in order:
        if column not in cursor or cursor[column] is None:
            raise ValueError("Keyset page is missing an ordered value.")
        value = str(cursor[column])
        operator = "gt" if direction == "asc" else "lt"
        comparison = f"{column}.{operator}.{value}"
        branches.append(
            comparison
            if not equals
            else f"and({','.join([*equals, comparison])})"
        )
        equals.append(f"{column}.eq.{value}")
    return f"({','.join(branches)})"
