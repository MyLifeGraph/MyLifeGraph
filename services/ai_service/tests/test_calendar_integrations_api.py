import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.calendar_integrations import (
    CalendarConnection,
    CalendarConnectionResponse,
    CalendarEventsResponse,
    CalendarImportConsent,
    CalendarImportCounts,
    CalendarImportResponse,
    CalendarImportSummary,
    CalendarImportWindow,
)
from app.services.calendar_integration_service import CalendarConflictError


USER_ID = "calendar-user"
CONNECTION_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
IMPORT_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
REQUEST_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
NOW = datetime(2026, 7, 13, 8, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "valid-calendar-token" else None


class Service:
    def __init__(self, *, disconnect_conflict: bool = False) -> None:
        self.calls = []
        self.disconnect_conflict = disconnect_conflict

    async def get_connection(self, *, user_id: str):
        self.calls.append(("get", user_id))
        return CalendarConnectionResponse(
            contract_version="calendar-import-v1",
            origin="authenticated_backend",
            connection=None,
        )

    async def create_connection(self, *, user_id: str, request):
        self.calls.append(("create", user_id, request))
        return _connection_response(_connection())

    async def import_file(self, *, user_id: str, connection_id: UUID, request):
        self.calls.append(("import", user_id, connection_id, request))
        summary = _import_summary()
        return CalendarImportResponse(
            contract_version="calendar-import-v1",
            origin="authenticated_backend",
            connection=_connection(last_import=summary),
            import_summary=summary,
        )

    async def get_events(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        cursor: str | None,
        limit: int,
    ):
        self.calls.append(("events", user_id, connection_id, cursor, limit))
        return CalendarEventsResponse(
            contract_version="calendar-import-v1",
            origin="authenticated_backend",
            connection_id=connection_id,
            events=[],
        )

    async def disconnect(self, *, user_id: str, connection_id: UUID, request):
        self.calls.append(("disconnect", user_id, connection_id, request))
        if self.disconnect_conflict:
            raise CalendarConflictError("terminal request mismatch")
        return _connection_response(_connection(disconnected=True))

    async def delete_imported_data(
        self,
        *,
        user_id: str,
        connection_id: UUID,
        request_id: UUID,
    ):
        self.calls.append(("delete", user_id, connection_id, request_id))
        return _connection_response(_connection(disconnected=True, deleted=True))


def _consent() -> CalendarImportConsent:
    return CalendarImportConsent(
        consent_version="calendar-import-consent-v1",
        read_calendar_events=True,
        store_event_basics=True,
        provider_writes=False,
        llm_processing=False,
    )


def _import_summary() -> CalendarImportSummary:
    return CalendarImportSummary(
        id=IMPORT_ID,
        imported_at=NOW,
        window=CalendarImportWindow(
            starts_on=date(2026, 6, 29),
            ends_before=date(2026, 10, 12),
            timezone="Europe/Berlin",
        ),
        counts=CalendarImportCounts(
            accepted=0,
            cancelled=0,
            out_of_window=0,
            unsupported_recurring=0,
            invalid=0,
        ),
        source_fingerprint="a" * 64,
    )


def _connection(
    *,
    disconnected: bool = False,
    deleted: bool = False,
    last_import: CalendarImportSummary | None = None,
) -> CalendarConnection:
    return CalendarConnection(
        id=CONNECTION_ID,
        origin="authenticated_backend",
        source_kind="ical_file",
        contract_version="calendar-import-v1",
        source_label="Work calendar",
        status="disconnected" if disconnected else "connected",
        consent=_consent(),
        consented_at=NOW,
        connected_at=NOW,
        disconnected_at=NOW if disconnected else None,
        imported_data_deleted_at=NOW if deleted else None,
        last_import=last_import,
        provider_writes=False,
        llm_processed=False,
    )


def _connection_response(connection: CalendarConnection) -> CalendarConnectionResponse:
    return CalendarConnectionResponse(
        contract_version="calendar-import-v1",
        origin="authenticated_backend",
        connection=connection,
    )


async def _request(
    method: str,
    path: str,
    *,
    json=None,
    params=None,
    authenticated: bool = True,
    disconnect_conflict: bool = False,
):
    app = create_app()
    service = Service(disconnect_conflict=disconnect_conflict)
    app.state.token_verifier = Verifier()
    app.state.calendar_integration_service = service
    headers = (
        {"Authorization": "Bearer valid-calendar-token"}
        if authenticated
        else {}
    )
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(
            method,
            path,
            headers=headers,
            json=json,
            params=params,
        )
    return response, service


def test_empty_get_keeps_required_null_connection_and_derives_owner() -> None:
    response, service = asyncio.run(_request("GET", "/v1/calendar-integrations"))

    assert response.status_code == 200
    assert response.json() == {
        "contract_version": "calendar-import-v1",
        "origin": "authenticated_backend",
        "connection": None,
    }
    assert service.calls == [("get", USER_ID)]


def test_create_contract_is_strict_and_omits_absent_connection_optionals() -> None:
    body = {
        "request_id": str(REQUEST_ID),
        "source_kind": "ical_file",
        "source_label": "Work calendar",
        "consent": {
            "consent_version": "calendar-import-consent-v1",
            "read_calendar_events": True,
            "store_event_basics": True,
            "provider_writes": False,
            "llm_processing": False,
        },
    }
    response, service = asyncio.run(
        _request("POST", "/v1/calendar-integrations/connections", json=body),
    )

    assert response.status_code == 200
    assert response.json()["connection"]["id"] == str(CONNECTION_ID)
    assert "last_import" not in response.json()["connection"]
    assert "disconnected_at" not in response.json()["connection"]
    assert service.calls[0][0:2] == ("create", USER_ID)

    invalid = {**body, "consent": {**body["consent"], "provider_writes": True}}
    invalid_response, invalid_service = asyncio.run(
        _request("POST", "/v1/calendar-integrations/connections", json=invalid),
    )
    assert invalid_response.status_code == 422
    assert invalid_service.calls == []


def test_disconnect_conflict_maps_to_409() -> None:
    response, service = asyncio.run(
        _request(
            "POST",
            f"/v1/calendar-integrations/connections/{CONNECTION_ID}/disconnect",
            json={"request_id": str(REQUEST_ID)},
            disconnect_conflict=True,
        ),
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "terminal request mismatch"
    assert service.calls[0][0:2] == ("disconnect", USER_ID)


def test_delete_requires_exactly_one_request_id_and_no_unknown_query_keys() -> None:
    path = f"/v1/calendar-integrations/connections/{CONNECTION_ID}/imported-data"
    valid, valid_service = asyncio.run(
        _request("DELETE", path, params={"request_id": str(REQUEST_ID)}),
    )
    assert valid.status_code == 200
    assert valid_service.calls == [("delete", USER_ID, CONNECTION_ID, REQUEST_ID)]

    invalid_queries = [
        [],
        [("request_id", str(REQUEST_ID)), ("extra", "value")],
        [("request_id", str(REQUEST_ID)), ("request_id", str(REQUEST_ID))],
    ]
    for params in invalid_queries:
        response, service = asyncio.run(_request("DELETE", path, params=params))
        assert response.status_code == 422
        assert service.calls == []

    body_response, body_service = asyncio.run(
        _request(
            "DELETE",
            path,
            params={"request_id": str(REQUEST_ID)},
            json={"request_id": str(REQUEST_ID)},
        ),
    )
    assert body_response.status_code == 422
    assert body_response.json()["detail"] == (
        "Imported-data deletion does not accept a request body."
    )
    assert body_service.calls == []


def test_calendar_routes_require_authentication() -> None:
    response, service = asyncio.run(
        _request("GET", "/v1/calendar-integrations", authenticated=False),
    )
    assert response.status_code == 401
    assert service.calls == []
