import base64
import binascii
import hashlib
import json
import re
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.calendar_integrations import (
    CALENDAR_IMPORT_CONTRACT_VERSION,
    CalendarConnectionCreateRequest,
    CalendarConnectionMutationRequest,
    CalendarConnectionResponse,
    CalendarEventsResponse,
    CalendarFileImportRequest,
    CalendarImportResponse,
)
from app.repositories.calendar_integration_repository import (
    CalendarIntegrationRepository,
    CalendarPersistenceConflict,
    CalendarPersistenceNotFound,
    calendar_connection_from_row,
    calendar_event_from_row,
    calendar_import_from_row,
)
from app.services.calendar_ical_parser import (
    MAX_CALENDAR_BYTES,
    CalendarParseError,
    parse_ical_snapshot,
)


class CalendarConnectionNotFoundError(ValueError):
    pass


class CalendarConflictError(ValueError):
    pass


class CalendarCursorError(ValueError):
    pass


class CalendarCursorStaleError(CalendarCursorError):
    pass


class CalendarIntegrationService:
    def __init__(
        self,
        *,
        repository: CalendarIntegrationRepository,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now_provider = now_provider or _utc_now

    async def get_connection(self, *, user_id: str) -> CalendarConnectionResponse:
        row = await self._repository.get_visible_connection(user_id=user_id)
        connection = (
            await calendar_connection_from_row(
                self._repository,
                user_id=user_id,
                row=row,
            )
            if row is not None
            else None
        )
        return CalendarConnectionResponse(
            contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
            origin="authenticated_backend",
            connection=connection,
        )

    async def create_connection(
        self,
        *,
        user_id: str,
        request: CalendarConnectionCreateRequest,
    ) -> CalendarConnectionResponse:
        now = self._now()
        fingerprint = _digest(
            {
                "contract_version": CALENDAR_IMPORT_CONTRACT_VERSION,
                "source_kind": request.source_kind,
                "source_label": request.source_label,
                "consent": request.consent.model_dump(mode="json"),
            },
        )
        try:
            connection_id = await self._repository.create_connection(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=fingerprint,
                source_label=request.source_label,
                now=now,
            )
        except CalendarPersistenceConflict as exc:
            raise CalendarConflictError(str(exc)) from exc
        row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        visible_row = await self._repository.get_visible_connection(user_id=user_id)
        if (
            row.get("status") != "connected"
            or row.get("imported_data_deleted_at") is not None
            or visible_row is None
            or str(visible_row.get("id")) != str(connection_id)
        ):
            raise CalendarConflictError(
                "Calendar connection request refers to a source that is no longer current.",
            )
        return CalendarConnectionResponse(
            contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
            origin="authenticated_backend",
            connection=await calendar_connection_from_row(
                self._repository,
                user_id=user_id,
                row=row,
            ),
        )

    async def import_file(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request: CalendarFileImportRequest,
    ) -> CalendarImportResponse:
        encoded = request.calendar_text.encode("utf-8")
        if len(encoded) > MAX_CALENDAR_BYTES:
            raise CalendarParseError("iCalendar input exceeds 512 KiB.")
        input_fingerprint = hashlib.sha256(encoded).hexdigest()

        # Resolve request replay before deriving a new profile-local window.
        # This preserves an exact retry across local midnight or timezone edits.
        existing = await self._repository.get_import_by_request(
            user_id=user_id,
            request_id=request.request_id,
        )
        if existing is not None:
            if (
                str(existing.get("connection_id")) != str(connection_id)
                or existing.get("input_fingerprint") != input_fingerprint
            ):
                raise CalendarConflictError(
                    "Calendar import request id was already used.",
                )
            connection_row = await self._require_connection(
                user_id=user_id,
                connection_id=connection_id,
            )
            if (
                connection_row.get("status") != "connected"
                or connection_row.get("imported_data_deleted_at") is not None
            ):
                raise CalendarConflictError("Calendar connection is not connected.")
            if str(connection_row.get("last_import_id")) != str(existing.get("id")):
                raise CalendarConflictError(
                    "Calendar import request has been superseded by a newer import.",
                )
            return CalendarImportResponse(
                contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
                origin="authenticated_backend",
                connection=await calendar_connection_from_row(
                    self._repository,
                    user_id=user_id,
                    row=connection_row,
                ),
                import_summary=calendar_import_from_row(existing),
            )

        connection_row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        if (
            connection_row.get("status") != "connected"
            or connection_row.get("imported_data_deleted_at") is not None
        ):
            raise CalendarConflictError("Calendar connection is not connected.")

        timezone_name = await self._repository.get_profile_timezone(user_id=user_id)
        try:
            timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        imported_at = self._now()
        local_today = imported_at.astimezone(timezone).date()
        starts_on = local_today - timedelta(days=14)
        ends_before = local_today + timedelta(days=91)
        parsed = parse_ical_snapshot(
            calendar_text=request.calendar_text,
            connection_id=connection_id,
            profile_timezone=timezone_name,
            starts_on=starts_on,
            ends_before=ends_before,
        )
        request_fingerprint = _digest(
            {
                "contract_version": CALENDAR_IMPORT_CONTRACT_VERSION,
                "connection_id": str(connection_id),
                "input_fingerprint": parsed.input_fingerprint,
                "starts_on": starts_on.isoformat(),
                "ends_before": ends_before.isoformat(),
                "timezone": timezone_name,
            },
        )
        try:
            import_id = await self._repository.apply_import(
                user_id=user_id,
                connection_id=connection_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                input_fingerprint=parsed.input_fingerprint,
                source_fingerprint=parsed.source_fingerprint,
                starts_on=starts_on,
                ends_before=ends_before,
                timezone=timezone_name,
                counts=parsed.counts.model_dump(mode="json"),
                events=[event.persistence_payload() for event in parsed.events],
                cancelled_source_keys=list(parsed.cancelled_source_keys),
                imported_at=imported_at,
            )
        except CalendarPersistenceConflict as exc:
            raise CalendarConflictError(str(exc)) from exc
        except CalendarPersistenceNotFound as exc:
            raise CalendarConnectionNotFoundError(str(exc)) from exc

        import_row = await self._repository.get_import(
            user_id=user_id,
            connection_id=connection_id,
            import_id=import_id,
        )
        if import_row is None:
            raise ValueError("Persisted calendar import is unavailable.")
        connection_row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        if str(connection_row.get("last_import_id")) != str(import_id):
            raise CalendarConflictError(
                "Calendar import request has been superseded by a newer import.",
            )
        return CalendarImportResponse(
            contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
            origin="authenticated_backend",
            connection=await calendar_connection_from_row(
                self._repository,
                user_id=user_id,
                row=connection_row,
            ),
            import_summary=calendar_import_from_row(import_row),
        )

    async def get_events(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        cursor: str | None,
        limit: int,
    ) -> CalendarEventsResponse:
        connection_row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        raw_import_id = connection_row.get("last_import_id")
        if raw_import_id is None:
            if cursor is not None:
                raise CalendarCursorStaleError("Calendar event cursor is stale.")
            return CalendarEventsResponse(
                contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
                origin="authenticated_backend",
                connection_id=connection_id,
                events=[],
            )
        import_id = UUID(str(raw_import_id))
        offset = _decode_cursor(cursor=cursor, expected_import_id=import_id)
        rows = await self._repository.list_events(
            user_id=user_id,
            connection_id=connection_id,
            import_id=import_id,
            offset=offset,
            limit=limit + 1,
        )
        current_connection_row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        if str(current_connection_row.get("last_import_id")) != str(import_id):
            raise CalendarCursorStaleError("Calendar event cursor is stale.")
        has_more = len(rows) > limit
        visible = rows[:limit]
        return CalendarEventsResponse(
            contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
            origin="authenticated_backend",
            connection_id=connection_id,
            import_id=import_id,
            events=[
                calendar_event_from_row(
                    row,
                    source_label=str(current_connection_row["source_label"]),
                )
                for row in visible
            ],
            next_cursor=(
                _encode_cursor(import_id=import_id, offset=offset + limit)
                if has_more
                else None
            ),
        )

    async def disconnect(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request: CalendarConnectionMutationRequest,
    ) -> CalendarConnectionResponse:
        await self._require_connection(user_id=user_id, connection_id=connection_id)
        try:
            await self._repository.disconnect(
                user_id=user_id,
                connection_id=connection_id,
                request_id=request.request_id,
                now=self._now(),
            )
        except CalendarPersistenceConflict as exc:
            raise CalendarConflictError(str(exc)) from exc
        except CalendarPersistenceNotFound as exc:
            raise CalendarConnectionNotFoundError(str(exc)) from exc
        row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        return CalendarConnectionResponse(
            contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
            origin="authenticated_backend",
            connection=await calendar_connection_from_row(
                self._repository,
                user_id=user_id,
                row=row,
            ),
        )

    async def delete_imported_data(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
    ) -> CalendarConnectionResponse:
        await self._require_connection(user_id=user_id, connection_id=connection_id)
        try:
            await self._repository.delete_imported_data(
                user_id=user_id,
                connection_id=connection_id,
                request_id=request_id,
                now=self._now(),
            )
        except CalendarPersistenceConflict as exc:
            raise CalendarConflictError(str(exc)) from exc
        except CalendarPersistenceNotFound as exc:
            raise CalendarConnectionNotFoundError(str(exc)) from exc
        row = await self._require_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        return CalendarConnectionResponse(
            contract_version=CALENDAR_IMPORT_CONTRACT_VERSION,
            origin="authenticated_backend",
            connection=await calendar_connection_from_row(
                self._repository,
                user_id=user_id,
                row=row,
            ),
        )

    async def _require_connection(
        self,
        *,
        user_id: str,
        connection_id: UUID,
    ) -> dict[str, Any]:
        row = await self._repository.get_connection(
            user_id=user_id,
            connection_id=connection_id,
        )
        if row is None:
            raise CalendarConnectionNotFoundError(
                "Calendar connection is unavailable.",
            )
        return row

    def _now(self) -> datetime:
        now = self._now_provider()
        if now.tzinfo is None:
            raise ValueError("Calendar integration clock must be timezone-aware.")
        return now


def _encode_cursor(*, import_id: UUID, offset: int) -> str:
    payload = json.dumps(
        {"v": 1, "import_id": str(import_id), "offset": offset},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")


def _decode_cursor(*, cursor: str | None, expected_import_id: UUID) -> int:
    if cursor is None:
        return 0
    if (
        not 1 <= len(cursor) <= 512
        or len(cursor) % 4 == 1
        or re.fullmatch(r"[A-Za-z0-9_-]+", cursor) is None
    ):
        raise CalendarCursorError("Calendar event cursor is invalid.")
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        raw = base64.b64decode(
            padded.encode("ascii"),
            altchars=b"-_",
            validate=True,
        )
        payload = json.loads(raw.decode("utf-8"))
    except (binascii.Error, ValueError, UnicodeError, json.JSONDecodeError) as exc:
        raise CalendarCursorError("Calendar event cursor is invalid.") from exc
    if not isinstance(payload, dict) or set(payload) != {"v", "import_id", "offset"}:
        raise CalendarCursorError("Calendar event cursor is invalid.")
    version = payload.get("v")
    raw_import_id = payload.get("import_id")
    offset = payload.get("offset")
    if (
        isinstance(version, bool)
        or not isinstance(version, int)
        or version != 1
        or not isinstance(raw_import_id, str)
        or isinstance(offset, bool)
        or not isinstance(offset, int)
        or not 0 <= offset <= 500
    ):
        raise CalendarCursorError("Calendar event cursor is invalid.")
    try:
        import_id = UUID(raw_import_id)
    except ValueError as exc:
        raise CalendarCursorError("Calendar event cursor is invalid.") from exc
    if str(import_id) != raw_import_id:
        raise CalendarCursorError("Calendar event cursor is invalid.")
    if _encode_cursor(import_id=import_id, offset=offset) != cursor:
        raise CalendarCursorError("Calendar event cursor is invalid.")
    if import_id != expected_import_id:
        raise CalendarCursorStaleError("Calendar event cursor is stale.")
    return offset


def _digest(value: object) -> str:
    canonical = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _utc_now() -> datetime:
    return datetime.now(tz=UTC)
