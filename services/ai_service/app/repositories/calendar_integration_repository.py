from datetime import date, datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient
from app.models.calendar_integrations import (
    CalendarConnection,
    CalendarEvent,
    CalendarEventProvenance,
    CalendarImportConsent,
    CalendarImportCounts,
    CalendarImportSummary,
    CalendarImportWindow,
)


class CalendarPersistenceConflict(RuntimeError):
    pass


class CalendarPersistenceNotFound(RuntimeError):
    pass


class CalendarIntegrationRepository(Protocol):
    async def get_visible_connection(self, *, user_id: str) -> dict[str, Any] | None:
        pass

    async def get_connection(
        self,
        *,
        user_id: str,
        connection_id: UUID,
    ) -> dict[str, Any] | None:
        pass

    async def get_profile_timezone(self, *, user_id: str) -> str:
        pass

    async def create_connection(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        source_label: str,
        now: datetime,
    ) -> UUID:
        pass

    async def get_import_by_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        pass

    async def get_import(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        import_id: UUID,
    ) -> dict[str, Any] | None:
        pass

    async def apply_import(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        input_fingerprint: str,
        source_fingerprint: str,
        starts_on: date,
        ends_before: date,
        timezone: str,
        counts: dict[str, int],
        events: list[dict[str, object]],
        cancelled_source_keys: list[str],
        imported_at: datetime,
    ) -> UUID:
        pass

    async def list_events(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        import_id: UUID,
        offset: int,
        limit: int,
    ) -> list[dict[str, Any]]:
        pass

    async def disconnect(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
        now: datetime,
    ) -> None:
        pass

    async def delete_imported_data(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
        now: datetime,
    ) -> None:
        pass


class SupabaseCalendarIntegrationRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_visible_connection(self, *, user_id: str) -> dict[str, Any] | None:
        current = await self._client.select(
            "calendar_connections",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "imported_data_deleted_at": "is.null",
                "order": "created_at.desc,id.desc",
                "limit": "1",
            },
        )
        if current:
            return current[0]
        historical = await self._client.select(
            "calendar_connections",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "order": "created_at.desc,id.desc",
                "limit": "1",
            },
        )
        return historical[0] if historical else None

    async def get_connection(
        self,
        *,
        user_id: str,
        connection_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "calendar_connections",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "id": f"eq.{connection_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def get_profile_timezone(self, *, user_id: str) -> str:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not rows:
            raise CalendarPersistenceNotFound("Profile is unavailable.")
        timezone = rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone:
            raise ValueError("Profile timezone is invalid.")
        return timezone

    async def create_connection(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        source_label: str,
        now: datetime,
    ) -> UUID:
        result = await self._rpc(
            "create_calendar_connection_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_source_label": source_label,
                "p_now": now.isoformat(),
            },
        )
        return _rpc_uuid(result, "connection_id")

    async def get_import_by_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "calendar_imports",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "request_id": f"eq.{request_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def apply_import(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        input_fingerprint: str,
        source_fingerprint: str,
        starts_on: date,
        ends_before: date,
        timezone: str,
        counts: dict[str, int],
        events: list[dict[str, object]],
        cancelled_source_keys: list[str],
        imported_at: datetime,
    ) -> UUID:
        result = await self._rpc(
            "apply_calendar_import_v1",
            params={
                "p_user_id": user_id,
                "p_connection_id": str(connection_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_input_fingerprint": input_fingerprint,
                "p_source_fingerprint": source_fingerprint,
                "p_window_starts_on": starts_on.isoformat(),
                "p_window_ends_before": ends_before.isoformat(),
                "p_timezone": timezone,
                "p_counts": counts,
                "p_events": events,
                "p_cancelled_source_keys": cancelled_source_keys,
                "p_imported_at": imported_at.isoformat(),
            },
        )
        return _rpc_uuid(result, "import_id")

    async def get_import(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        import_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "calendar_imports",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "connection_id": f"eq.{connection_id}",
                "id": f"eq.{import_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def list_events(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        import_id: UUID,
        offset: int,
        limit: int,
    ) -> list[dict[str, Any]]:
        return await self._client.select(
            "calendar_events",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "connection_id": f"eq.{connection_id}",
                "import_id": f"eq.{import_id}",
                "order": "sort_date.asc,sort_time.asc,id.asc",
                "offset": str(offset),
                "limit": str(limit),
            },
        )

    async def disconnect(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
        now: datetime,
    ) -> None:
        await self._rpc(
            "disconnect_calendar_connection_v1",
            params={
                "p_user_id": user_id,
                "p_connection_id": str(connection_id),
                "p_request_id": str(request_id),
                "p_now": now.isoformat(),
            },
        )

    async def delete_imported_data(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
        now: datetime,
    ) -> None:
        await self._rpc(
            "delete_calendar_imported_data_v1",
            params={
                "p_user_id": user_id,
                "p_connection_id": str(connection_id),
                "p_request_id": str(request_id),
                "p_now": now.isoformat(),
            },
        )

    async def _rpc(self, function: str, *, params: dict[str, Any]) -> dict[str, Any]:
        try:
            result = await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code in {"23505", "40001", "PT409"}:
                raise CalendarPersistenceConflict(message) from exc
            if code == "22023" and "unavailable" in message.lower():
                raise CalendarPersistenceNotFound(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError(f"Calendar RPC {function} returned a non-object.")
        return result


async def calendar_connection_from_row(
    repository: SupabaseCalendarIntegrationRepository | CalendarIntegrationRepository,
    *,
    user_id: str,
    row: dict[str, Any],
) -> CalendarConnection:
    last_import = None
    raw_last_import_id = row.get("last_import_id")
    if raw_last_import_id:
        import_id = UUID(str(raw_last_import_id))
        getter = getattr(repository, "get_import", None)
        if getter is None:
            raise ValueError("Calendar repository cannot load import projection.")
        import_row = await getter(
            user_id=user_id,
            connection_id=UUID(str(row["id"])),
            import_id=import_id,
        )
        if import_row is None:
            raise ValueError("Calendar connection last import is unavailable.")
        last_import = calendar_import_from_row(import_row)
    return CalendarConnection(
        id=UUID(str(row["id"])),
        origin=row["origin"],
        source_kind=row["source_kind"],
        contract_version=row["contract_version"],
        source_label=row["source_label"],
        status=row["status"],
        consent=CalendarImportConsent(
            consent_version=row["consent_version"],
            read_calendar_events=row["read_calendar_events"],
            store_event_basics=row["store_event_basics"],
            provider_writes=row["provider_writes"],
            llm_processing=row["llm_processing"],
        ),
        consented_at=_datetime(row["consented_at"]),
        connected_at=_datetime(row["connected_at"]),
        disconnected_at=_optional_datetime(row.get("disconnected_at")),
        imported_data_deleted_at=_optional_datetime(
            row.get("imported_data_deleted_at"),
        ),
        last_import=last_import,
        provider_writes=row["provider_writes"],
        llm_processed=row["llm_processing"],
    )


def calendar_import_from_row(row: dict[str, Any]) -> CalendarImportSummary:
    return CalendarImportSummary(
        id=UUID(str(row["id"])),
        imported_at=_datetime(row["imported_at"]),
        window=CalendarImportWindow(
            starts_on=_date(row["window_starts_on"]),
            ends_before=_date(row["window_ends_before"]),
            timezone=row["timezone"],
        ),
        counts=CalendarImportCounts(
            accepted=row["accepted_count"],
            cancelled=row["cancelled_count"],
            out_of_window=row["out_of_window_count"],
            unsupported_recurring=row["unsupported_recurring_count"],
            invalid=row["invalid_count"],
        ),
        source_fingerprint=row["source_fingerprint"],
    )


def calendar_event_from_row(
    row: dict[str, Any],
    *,
    source_label: str,
) -> CalendarEvent:
    return CalendarEvent(
        id=UUID(str(row["id"])),
        title=row["title"],
        location=row.get("location"),
        event_kind=row["event_kind"],
        busy_status=row["busy_status"],
        event_status=row["event_status"],
        event_timezone=row["event_timezone"],
        timezone_source=row["timezone_source"],
        starts_at=_optional_datetime(row.get("starts_at")),
        ends_at=_optional_datetime(row.get("ends_at")),
        local_starts_at=_optional_local_datetime(row.get("local_starts_at")),
        local_ends_at=_optional_local_datetime(row.get("local_ends_at")),
        starts_on=_optional_date(row.get("starts_on")),
        ends_on=_optional_date(row.get("ends_on")),
        imported_at=_datetime(row["imported_at"]),
        last_seen_at=_datetime(row["last_seen_at"]),
        source_fingerprint=row["source_fingerprint"],
        provenance=CalendarEventProvenance(
            kind="integration",
            contract_version="calendar-import-v1",
            source_kind="ical_file",
            source_label=source_label,
            provider_writes=False,
            llm_processed=False,
        ),
    )


def _rpc_uuid(result: dict[str, Any], key: str) -> UUID:
    value = result.get(key)
    if not isinstance(value, str):
        raise ValueError(f"Calendar RPC result lacks {key}.")
    return UUID(value)


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        body = exc.response.json()
    except ValueError:
        return None, str(exc)
    if not isinstance(body, dict):
        return None, str(exc)
    code = body.get("code")
    message = body.get("message")
    return (
        str(code) if code is not None else None,
        str(message) if message is not None else str(exc),
    )


def _datetime(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Calendar timestamp is invalid.")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Calendar timestamp lacks timezone.")
    return parsed


def _optional_datetime(value: Any) -> datetime | None:
    return None if value is None else _datetime(value)


def _optional_local_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError("Calendar local timestamp is invalid.")
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is not None:
        raise ValueError("Calendar local timestamp unexpectedly has an offset.")
    return parsed


def _date(value: Any) -> date:
    if not isinstance(value, str):
        raise ValueError("Calendar date is invalid.")
    return date.fromisoformat(value)


def _optional_date(value: Any) -> date | None:
    return None if value is None else _date(value)
