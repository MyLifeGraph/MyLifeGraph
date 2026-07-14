import asyncio
from datetime import UTC, datetime
from uuid import UUID

import httpx
import pytest

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.notifications import NotificationLifecycleActionResponse
from app.services.notification_service import (
    NotificationConflictError,
    NotificationNotFoundError,
    NotificationOutcomeUnknownError,
    NotificationServiceUnavailableError,
)


USER_ID = "notification-owner"
NOTIFICATION_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
UPDATED_AT = datetime(2026, 7, 14, 8, 30, tzinfo=UTC)


class Verifier:
    async def verify(self, token):
        return Principal(user_id=USER_ID) if token == "valid" else None


class Service:
    def __init__(self, outcome=None) -> None:
        self.calls = []
        self.outcome = outcome

    async def apply_action(self, *, user_id, notification_id, request):
        self.calls.append((user_id, notification_id, request))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return NotificationLifecycleActionResponse(
            contract_version="notification-lifecycle-v1",
            notification_id=notification_id,
            command=request.command,
            is_read=True,
            read_at=UPDATED_AT,
            dismissed_at=None,
            updated_at=UPDATED_AT,
            replayed=False,
        )


def _body(**changes):
    body = {
        "contract_version": "notification-lifecycle-v1",
        "request_id": str(REQUEST_ID),
        "command": "mark_read",
        "expected_updated_at": UPDATED_AT.isoformat(),
    }
    body.update(changes)
    return body


async def _request(*, body=None, outcome=None, authenticated=True):
    app = create_app()
    service = Service(outcome)
    app.state.token_verifier = Verifier()
    app.state.notification_service = service
    headers = {"Authorization": "Bearer valid"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.post(
            f"/v1/notifications/{NOTIFICATION_ID}/actions",
            headers=headers,
            json=body,
        )
    return response, service


def test_notification_action_derives_owner_and_returns_exact_response() -> None:
    response, service = asyncio.run(_request(body=_body()))

    assert response.status_code == 200
    assert response.json() == {
        "contract_version": "notification-lifecycle-v1",
        "notification_id": str(NOTIFICATION_ID),
        "command": "mark_read",
        "is_read": True,
        "read_at": "2026-07-14T08:30:00Z",
        "dismissed_at": None,
        "updated_at": "2026-07-14T08:30:00Z",
        "replayed": False,
    }
    assert service.calls[0][0:2] == (USER_ID, NOTIFICATION_ID)


@pytest.mark.parametrize(
    "body",
    [
        _body(user_id="attacker"),
        _body(command="delete"),
        _body(expected_updated_at=1_721_035_800),
        _body(expected_updated_at="1721035800"),
        _body(expected_updated_at="2026-07-14T08:30:00"),
        _body(expected_updated_at={"value": "2026-07-14T08:30:00Z"}),
        _body(contract_version="notification-lifecycle-v2"),
    ],
)
def test_notification_action_rejects_unknown_or_invalid_request(body) -> None:
    response, service = asyncio.run(_request(body=body))

    assert response.status_code == 422
    assert service.calls == []


@pytest.mark.parametrize(
    ("outcome", "status_code"),
    [
        (NotificationNotFoundError("private"), 404),
        (NotificationConflictError("changed"), 409),
        (NotificationOutcomeUnknownError("private"), 502),
        (NotificationServiceUnavailableError("private"), 503),
    ],
)
def test_notification_action_maps_lifecycle_errors(outcome, status_code) -> None:
    response, _ = asyncio.run(_request(body=_body(), outcome=outcome))

    assert response.status_code == status_code


def test_notification_action_requires_authentication() -> None:
    response, service = asyncio.run(
        _request(body=_body(), authenticated=False),
    )

    assert response.status_code == 401
    assert service.calls == []
