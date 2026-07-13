import asyncio
from datetime import UTC, date, datetime
from typing import Any
from uuid import UUID

import httpx
import pytest
from pydantic import ValidationError

from app.repositories.calendar_integration_repository import (
    CalendarPersistenceConflict,
    CalendarPersistenceNotFound,
    SupabaseCalendarIntegrationRepository,
    calendar_event_from_row,
)


USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
CONNECTION_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
IMPORT_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
REQUEST_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
NOW = datetime(2026, 7, 13, 8, tzinfo=UTC)
FINGERPRINT = "a" * 64


class FakeClient:
    def __init__(self) -> None:
        self.select_results: list[list[dict[str, Any]]] = []
        self.select_calls: list[tuple[str, dict[str, str]]] = []
        self.rpc_result: Any = {}
        self.rpc_error_code: str | None = None
        self.rpc_calls: list[tuple[str, dict[str, Any]]] = []

    async def select(self, table: str, *, params: dict[str, str]):
        self.select_calls.append((table, params))
        return self.select_results.pop(0)

    async def rpc(self, function: str, *, params: dict[str, Any]):
        self.rpc_calls.append((function, params))
        if self.rpc_error_code is not None:
            request = httpx.Request("POST", f"http://supabase.test/{function}")
            response = httpx.Response(
                409,
                request=request,
                json={
                    "code": self.rpc_error_code,
                    "message": "calendar persistence unavailable"
                    if self.rpc_error_code == "22023"
                    else "calendar request conflict",
                },
            )
            raise httpx.HTTPStatusError(
                "rpc failed",
                request=request,
                response=response,
            )
        return self.rpc_result


def test_visible_connection_prefers_current_then_falls_back_to_latest_tombstone() -> None:
    current = {"id": str(CONNECTION_ID), "status": "disconnected"}
    client = FakeClient()
    client.select_results = [[], [current]]
    repository = SupabaseCalendarIntegrationRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(repository.get_visible_connection(user_id=USER_ID))

    assert result == current
    assert client.select_calls == [
        (
            "calendar_connections",
            {
                "select": "*",
                "user_id": f"eq.{USER_ID}",
                "imported_data_deleted_at": "is.null",
                "order": "created_at.desc,id.desc",
                "limit": "1",
            },
        ),
        (
            "calendar_connections",
            {
                "select": "*",
                "user_id": f"eq.{USER_ID}",
                "order": "created_at.desc,id.desc",
                "limit": "1",
            },
        ),
    ]


def test_apply_import_calls_only_the_atomic_rpc_with_exact_scope() -> None:
    client = FakeClient()
    client.rpc_result = {"import_id": str(IMPORT_ID), "replayed": False}
    repository = SupabaseCalendarIntegrationRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.apply_import(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request_id=REQUEST_ID,
            request_fingerprint="b" * 64,
            input_fingerprint="c" * 64,
            source_fingerprint=FINGERPRINT,
            starts_on=date(2026, 6, 29),
            ends_before=date(2026, 10, 12),
            timezone="Europe/Berlin",
            counts={
                "accepted": 1,
                "cancelled": 0,
                "out_of_window": 0,
                "unsupported_recurring": 0,
                "invalid": 0,
            },
            events=[{"id": str(UUID(int=1))}],
            cancelled_source_keys=[],
            imported_at=NOW,
        ),
    )

    assert result == IMPORT_ID
    assert client.rpc_calls == [
        (
            "apply_calendar_import_v1",
            {
                "p_user_id": USER_ID,
                "p_connection_id": str(CONNECTION_ID),
                "p_request_id": str(REQUEST_ID),
                "p_request_fingerprint": "b" * 64,
                "p_input_fingerprint": "c" * 64,
                "p_source_fingerprint": FINGERPRINT,
                "p_window_starts_on": "2026-06-29",
                "p_window_ends_before": "2026-10-12",
                "p_timezone": "Europe/Berlin",
                "p_counts": {
                    "accepted": 1,
                    "cancelled": 0,
                    "out_of_window": 0,
                    "unsupported_recurring": 0,
                    "invalid": 0,
                },
                "p_events": [{"id": str(UUID(int=1))}],
                "p_cancelled_source_keys": [],
                "p_imported_at": NOW.isoformat(),
            },
        ),
    ]


@pytest.mark.parametrize("code", ["23505", "40001", "PT409"])
def test_rpc_uniqueness_and_serialization_errors_are_conflicts(code: str) -> None:
    client = FakeClient()
    client.rpc_error_code = code
    repository = SupabaseCalendarIntegrationRepository(client)  # type: ignore[arg-type]

    with pytest.raises(CalendarPersistenceConflict, match="request conflict"):
        asyncio.run(
            repository.disconnect(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request_id=REQUEST_ID,
                now=NOW,
            ),
        )


def test_rpc_unavailable_error_is_not_found() -> None:
    client = FakeClient()
    client.rpc_error_code = "22023"
    repository = SupabaseCalendarIntegrationRepository(client)  # type: ignore[arg-type]

    with pytest.raises(CalendarPersistenceNotFound, match="unavailable"):
        asyncio.run(
            repository.disconnect(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request_id=REQUEST_ID,
                now=NOW,
            ),
        )


def test_event_projection_rejects_last_seen_before_first_import() -> None:
    row = {
        "id": str(UUID(int=2)),
        "title": "Meeting",
        "location": None,
        "event_kind": "timed",
        "busy_status": "busy",
        "event_status": "confirmed",
        "event_timezone": "UTC",
        "timezone_source": "utc",
        "starts_at": "2026-07-13T09:00:00+00:00",
        "ends_at": "2026-07-13T10:00:00+00:00",
        "local_starts_at": "2026-07-13T09:00:00",
        "local_ends_at": "2026-07-13T10:00:00",
        "starts_on": None,
        "ends_on": None,
        "imported_at": "2026-07-13T08:00:00+00:00",
        "last_seen_at": "2026-07-13T07:59:59+00:00",
        "source_fingerprint": FINGERPRINT,
    }

    with pytest.raises(ValidationError, match="last-seen"):
        calendar_event_from_row(row, source_label="Work calendar")
