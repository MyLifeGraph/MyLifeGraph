import asyncio
import base64
import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

import pytest

from app.models.calendar_integrations import (
    CalendarConnectionCreateRequest,
    CalendarConnectionMutationRequest,
    CalendarFileImportRequest,
)
from app.services.calendar_integration_service import (
    CalendarConflictError,
    CalendarCursorError,
    CalendarCursorStaleError,
    CalendarIntegrationService,
    _decode_cursor,
    _encode_cursor,
)
from app.repositories.calendar_integration_repository import CalendarPersistenceConflict


USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
CONNECTION_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
IMPORT_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
NOW = datetime(2026, 7, 13, 8, tzinfo=UTC)


def _connection_row() -> dict[str, Any]:
    return {
        "id": str(CONNECTION_ID),
        "user_id": USER_ID,
        "origin": "authenticated_backend",
        "source_kind": "ical_file",
        "contract_version": "calendar-import-v1",
        "source_label": "Work calendar",
        "status": "connected",
        "consent_version": "calendar-import-consent-v1",
        "read_calendar_events": True,
        "store_event_basics": True,
        "provider_writes": False,
        "llm_processing": False,
        "consented_at": NOW.isoformat(),
        "connected_at": NOW.isoformat(),
        "disconnected_at": None,
        "imported_data_deleted_at": None,
        "last_import_id": None,
        "created_at": NOW.isoformat(),
    }


def _calendar(*events: str) -> str:
    return "\r\n".join(
        ["BEGIN:VCALENDAR", "VERSION:2.0", *events, "END:VCALENDAR", ""],
    )


def _event(*lines: str) -> str:
    return "\r\n".join(["BEGIN:VEVENT", *lines, "END:VEVENT"])


class FakeCalendarRepository:
    def __init__(self) -> None:
        self.connection = _connection_row()
        self.imports: dict[UUID, dict[str, Any]] = {}
        self.imports_by_request: dict[UUID, dict[str, Any]] = {}
        self.events: dict[str, dict[str, Any]] = {}
        self.apply_calls = 0
        self.profile_calls = 0

    async def get_visible_connection(self, *, user_id: str):
        return self.connection if user_id == USER_ID else None

    async def get_connection(self, *, user_id: str, connection_id: UUID):
        if user_id == USER_ID and connection_id == CONNECTION_ID:
            return self.connection
        return None

    async def get_profile_timezone(self, *, user_id: str) -> str:
        self.profile_calls += 1
        assert user_id == USER_ID
        return "Europe/Berlin"

    async def create_connection(self, **kwargs) -> UUID:
        assert kwargs["user_id"] == USER_ID
        self.connection["source_label"] = kwargs["source_label"]
        return CONNECTION_ID

    async def get_import_by_request(self, *, user_id: str, request_id: UUID):
        assert user_id == USER_ID
        return self.imports_by_request.get(request_id)

    async def get_import(self, *, user_id: str, connection_id: UUID, import_id: UUID):
        assert user_id == USER_ID and connection_id == CONNECTION_ID
        return self.imports.get(import_id)

    async def apply_import(self, **kwargs) -> UUID:
        self.apply_calls += 1
        import_id = IMPORT_ID if self.apply_calls == 1 else uuid4()
        row = {
            "id": str(import_id),
            "user_id": kwargs["user_id"],
            "connection_id": str(kwargs["connection_id"]),
            "request_id": str(kwargs["request_id"]),
            "request_fingerprint": kwargs["request_fingerprint"],
            "input_fingerprint": kwargs["input_fingerprint"],
            "source_fingerprint": kwargs["source_fingerprint"],
            "window_starts_on": kwargs["starts_on"].isoformat(),
            "window_ends_before": kwargs["ends_before"].isoformat(),
            "timezone": kwargs["timezone"],
            "accepted_count": kwargs["counts"]["accepted"],
            "cancelled_count": kwargs["counts"]["cancelled"],
            "out_of_window_count": kwargs["counts"]["out_of_window"],
            "unsupported_recurring_count": kwargs["counts"][
                "unsupported_recurring"
            ],
            "invalid_count": kwargs["counts"]["invalid"],
            "imported_at": kwargs["imported_at"].isoformat(),
        }
        self.imports[import_id] = row
        self.imports_by_request[kwargs["request_id"]] = row
        current: dict[str, dict[str, Any]] = {}
        for payload in kwargs["events"]:
            key = str(payload["source_event_key"])
            previous = self.events.get(key)
            current[key] = {
                **payload,
                "user_id": USER_ID,
                "connection_id": str(CONNECTION_ID),
                "import_id": str(import_id),
                "origin": "authenticated_backend",
                "source_kind": "ical_file",
                "contract_version": "calendar-import-v1",
                "imported_at": (
                    previous["imported_at"]
                    if previous is not None
                    else kwargs["imported_at"].isoformat()
                ),
                "last_seen_at": kwargs["imported_at"].isoformat(),
            }
        self.events = current
        self.connection["last_import_id"] = str(import_id)
        return import_id

    async def list_events(self, **kwargs):
        ordered = sorted(
            self.events.values(),
            key=lambda row: (row["sort_date"], row["sort_time"], row["id"]),
        )
        start = kwargs["offset"]
        return ordered[start : start + kwargs["limit"]]

    async def disconnect(self, **kwargs) -> None:
        self.connection["status"] = "disconnected"
        self.connection["disconnected_at"] = kwargs["now"].isoformat()

    async def delete_imported_data(self, **kwargs) -> None:
        assert self.connection["status"] == "disconnected"
        self.events.clear()
        self.imports.clear()
        self.imports_by_request.clear()
        self.connection["last_import_id"] = None
        self.connection["imported_data_deleted_at"] = kwargs["now"].isoformat()


def _service(repository: FakeCalendarRepository, *, now: datetime = NOW):
    return CalendarIntegrationService(
        repository=repository,
        now_provider=lambda: now,
    )


def _import_request(request_id: UUID, *, status: str = "CONFIRMED"):
    return CalendarFileImportRequest(
        request_id=request_id,
        calendar_text=_calendar(
            _event(
                "UID:meeting@example.test",
                f"STATUS:{status}",
                "DTSTART;TZID=Europe/Berlin:20260713T090000",
                "DTEND;TZID=Europe/Berlin:20260713T100000",
                "SUMMARY:Meeting",
            ),
        ),
    )


def test_create_and_import_return_strict_current_projection() -> None:
    repository = FakeCalendarRepository()
    service = _service(repository)
    created = asyncio.run(
        service.create_connection(
            user_id=USER_ID,
            request=CalendarConnectionCreateRequest.model_validate(
                {
                    "request_id": "11111111-1111-4111-8111-111111111111",
                    "source_kind": "ical_file",
                    "source_label": "  Work calendar  ",
                    "consent": {
                        "consent_version": "calendar-import-consent-v1",
                        "read_calendar_events": True,
                        "store_event_basics": True,
                        "provider_writes": False,
                        "llm_processing": False,
                    },
                },
            ),
        ),
    )
    response = asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(
                UUID("22222222-2222-4222-8222-222222222222"),
            ),
        ),
    )

    assert created.connection is not None
    assert created.connection.source_label == "Work calendar"
    assert response.import_summary.window.starts_on.isoformat() == "2026-06-29"
    assert response.import_summary.window.ends_before.isoformat() == "2026-10-12"
    assert response.import_summary.counts.accepted == 1
    assert response.connection.last_import == response.import_summary


def test_import_retry_replays_before_new_midnight_window_or_profile_read() -> None:
    repository = FakeCalendarRepository()
    request = _import_request(UUID("33333333-3333-4333-8333-333333333333"))
    first = asyncio.run(
        _service(repository).import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=request,
        ),
    )
    profile_calls = repository.profile_calls
    second = asyncio.run(
        _service(
            repository,
            now=datetime(2026, 7, 14, 23, tzinfo=UTC),
        ).import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=request,
        ),
    )

    assert repository.apply_calls == 1
    assert repository.profile_calls == profile_calls
    assert second.import_summary == first.import_summary


def test_request_id_reuse_with_different_file_conflicts() -> None:
    repository = FakeCalendarRepository()
    request_id = UUID("44444444-4444-4444-8444-444444444444")
    asyncio.run(
        _service(repository).import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(request_id),
        ),
    )

    with pytest.raises(CalendarConflictError):
        asyncio.run(
            _service(repository).import_file(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request=CalendarFileImportRequest(
                    request_id=request_id,
                    calendar_text=_import_request(request_id).calendar_text.replace(
                        "Meeting",
                        "Changed",
                    ),
                ),
            ),
        )


def test_superseded_import_request_replay_conflicts() -> None:
    repository = FakeCalendarRepository()
    service = _service(repository)
    first_request = _import_request(
        UUID("41414141-4141-4141-8141-414141414141"),
    )
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=first_request,
        ),
    )
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(
                UUID("42424242-4242-4242-8242-424242424242"),
            ),
        ),
    )

    with pytest.raises(CalendarConflictError, match="superseded"):
        asyncio.run(
            service.import_file(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request=first_request,
            ),
        )


def test_current_import_replay_conflicts_after_disconnect() -> None:
    repository = FakeCalendarRepository()
    service = _service(repository)
    request = _import_request(UUID("43434343-1111-4111-8111-434343434343"))
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=request,
        ),
    )
    asyncio.run(
        service.disconnect(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=CalendarConnectionMutationRequest(
                request_id=UUID("43434343-2222-4222-8222-434343434343"),
            ),
        ),
    )

    with pytest.raises(CalendarConflictError, match="not connected"):
        asyncio.run(
            service.import_file(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request=request,
            ),
        )


def test_import_response_conflicts_if_a_concurrent_import_supersedes_projection() -> None:
    class SupersedingRepository(FakeCalendarRepository):
        async def apply_import(self, **kwargs) -> UUID:
            import_id = await super().apply_import(**kwargs)
            self.connection["last_import_id"] = str(uuid4())
            return import_id

    repository = SupersedingRepository()

    with pytest.raises(CalendarConflictError, match="superseded"):
        asyncio.run(
            _service(repository).import_file(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request=_import_request(
                    UUID("45454545-4545-4545-8545-454545454545"),
                ),
            ),
        )


def test_cancelled_next_snapshot_removes_prior_current_event() -> None:
    repository = FakeCalendarRepository()
    service = _service(repository)
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(UUID("55555555-5555-4555-8555-555555555555")),
        ),
    )
    assert len(repository.events) == 1

    cancelled = asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(
                UUID("66666666-6666-4666-8666-666666666666"),
                status="CANCELLED",
            ),
        ),
    )

    assert cancelled.import_summary.counts.cancelled == 1
    assert cancelled.import_summary.counts.accepted == 0
    assert repository.events == {}


def test_event_cursor_is_tied_to_current_import() -> None:
    repository = FakeCalendarRepository()
    service = _service(repository)
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(UUID("77777777-7777-4777-8777-777777777777")),
        ),
    )
    page = asyncio.run(
        service.get_events(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            cursor=None,
            limit=1,
        ),
    )
    assert len(page.events) == 1
    assert page.events[0].provenance.source_label == "Work calendar"

    # A valid cursor shape for another import must be rejected as stale.
    with pytest.raises(CalendarCursorStaleError):
        asyncio.run(
            service.get_events(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                cursor=_encode_cursor(import_id=uuid4(), offset=1),
                limit=1,
            ),
        )


def test_event_page_conflicts_if_projection_changes_during_page_read() -> None:
    class SupersedingRepository(FakeCalendarRepository):
        async def list_events(self, **kwargs):
            rows = await super().list_events(**kwargs)
            self.connection["last_import_id"] = str(uuid4())
            return rows

    repository = SupersedingRepository()
    service = _service(repository)
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(
                UUID("46464646-4646-4646-8646-464646464646"),
            ),
        ),
    )

    with pytest.raises(CalendarCursorStaleError, match="stale"):
        asyncio.run(
            service.get_events(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                cursor=None,
                limit=1,
            ),
        )


def test_event_cursor_requires_one_canonical_base64url_encoding() -> None:
    canonical = _encode_cursor(import_id=IMPORT_ID, offset=1)
    assert _decode_cursor(cursor=canonical, expected_import_id=IMPORT_ID) == 1

    payload = json.dumps(
        {"v": 1, "import_id": str(IMPORT_ID), "offset": 1},
    ).encode()
    noncanonical_json = base64.urlsafe_b64encode(payload).decode().rstrip("=")
    assert noncanonical_json != canonical

    for invalid in [f"{canonical}=", f"{canonical}!", noncanonical_json]:
        with pytest.raises(CalendarCursorError, match="invalid"):
            _decode_cursor(cursor=invalid, expected_import_id=IMPORT_ID)


def test_create_replay_of_terminal_connection_conflicts() -> None:
    repository = FakeCalendarRepository()
    repository.connection.update(
        {
            "status": "disconnected",
            "disconnected_at": NOW.isoformat(),
            "imported_data_deleted_at": NOW.isoformat(),
        },
    )

    with pytest.raises(CalendarConflictError, match="no longer current"):
        asyncio.run(
            _service(repository).create_connection(
                user_id=USER_ID,
                request=CalendarConnectionCreateRequest.model_validate(
                    {
                        "request_id": "43434343-4343-4343-8343-434343434343",
                        "source_kind": "ical_file",
                        "source_label": "Work calendar",
                        "consent": {
                            "consent_version": "calendar-import-consent-v1",
                            "read_calendar_events": True,
                            "store_event_basics": True,
                            "provider_writes": False,
                            "llm_processing": False,
                        },
                    },
                ),
            ),
        )


def test_disconnect_persistence_conflict_is_a_service_conflict() -> None:
    class ConflictingRepository(FakeCalendarRepository):
        async def disconnect(self, **kwargs) -> None:
            raise CalendarPersistenceConflict("terminal request mismatch")

    with pytest.raises(CalendarConflictError, match="terminal request mismatch"):
        asyncio.run(
            _service(ConflictingRepository()).disconnect(
                user_id=USER_ID,
                connection_id=CONNECTION_ID,
                request=CalendarConnectionMutationRequest(
                    request_id=UUID("44444444-1111-4111-8111-444444444444"),
                ),
            ),
        )


def test_disconnect_retains_then_delete_clears_and_returns_tombstone() -> None:
    repository = FakeCalendarRepository()
    service = _service(repository)
    asyncio.run(
        service.import_file(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=_import_request(UUID("88888888-8888-4888-8888-888888888888")),
        ),
    )
    disconnected = asyncio.run(
        service.disconnect(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request=CalendarConnectionMutationRequest(
                request_id=UUID("99999999-9999-4999-8999-999999999999"),
            ),
        ),
    )
    assert disconnected.connection is not None
    assert disconnected.connection.status == "disconnected"
    assert repository.events

    deleted = asyncio.run(
        service.delete_imported_data(
            user_id=USER_ID,
            connection_id=CONNECTION_ID,
            request_id=UUID("aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"),
        ),
    )
    assert deleted.connection is not None
    assert deleted.connection.imported_data_deleted_at == NOW
    assert deleted.connection.last_import is None
    assert repository.events == {}
