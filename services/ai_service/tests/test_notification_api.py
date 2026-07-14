import asyncio
from datetime import UTC, datetime
from uuid import UUID

import httpx
import pytest

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.notifications import (
    NotificationCategories,
    NotificationDeliveryReceiptResponse,
    NotificationLifecycleActionResponse,
    NotificationSettingsResponse,
)
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

    async def get_settings(self, *, user_id):
        self.calls.append(("get_settings", user_id))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return _settings_response()

    async def update_settings(self, *, user_id, request):
        self.calls.append(("update_settings", user_id, request))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return _settings_response(enabled=request.in_app_delivery_enabled)

    async def acknowledge_delivery(self, *, user_id, notification_id):
        self.calls.append(("delivery", user_id, notification_id))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return NotificationDeliveryReceiptResponse(
            contract_version="in-app-notification-delivery-v1",
            notification_id=notification_id,
            channel="in_app",
            delivered_at=UPDATED_AT,
            replayed=False,
        )


def _settings_response(*, enabled: bool = False) -> NotificationSettingsResponse:
    return NotificationSettingsResponse(
        contract_version="notification-settings-v1",
        in_app_delivery_enabled=enabled,
        consent_version=("in-app-notification-consent-v1" if enabled else None),
        consented_at=(UPDATED_AT if enabled else None),
        disabled_at=None,
        categories=NotificationCategories(
            focus_prompt=True,
            recovery_prompt=True,
            weekly_summary=True,
        ),
        quiet_hours=None,
        daily_limit=2,
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


async def _settings_request(
    method: str,
    *,
    body=None,
    outcome=None,
    authenticated=True,
):
    app = create_app()
    service = Service(outcome)
    app.state.token_verifier = Verifier()
    app.state.notification_service = service
    headers = {"Authorization": "Bearer valid"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(
            method,
            "/v1/notifications/settings",
            headers=headers,
            json=body,
        )
    return response, service


async def _delivery_request(*, outcome=None, authenticated=True):
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
            f"/v1/notifications/{NOTIFICATION_ID}/delivery",
            headers=headers,
            json={"contract_version": "in-app-notification-delivery-v1"},
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


def test_notification_settings_start_disabled_without_reinterpreting_preferences() -> None:
    response, service = asyncio.run(_settings_request("GET"))

    assert response.status_code == 200
    assert response.json()["in_app_delivery_enabled"] is False
    assert response.json()["categories"] == {
        "focus_prompt": True,
        "recovery_prompt": True,
        "weekly_summary": True,
    }
    assert service.calls == [("get_settings", USER_ID)]


def test_notification_settings_patch_derives_owner_and_requires_consent_version() -> None:
    body = {
        "contract_version": "notification-settings-v1",
        "request_id": str(REQUEST_ID),
        "expected_updated_at": UPDATED_AT.isoformat(),
        "in_app_delivery_enabled": True,
        "consent_version": "in-app-notification-consent-v1",
        "categories": {
            "focus_prompt": True,
            "recovery_prompt": True,
            "weekly_summary": False,
        },
        "quiet_hours": {"starts_at": "22:00", "ends_at": "07:00"},
        "daily_limit": 2,
    }

    response, service = asyncio.run(_settings_request("PATCH", body=body))

    assert response.status_code == 200
    assert response.json()["in_app_delivery_enabled"] is True
    assert service.calls[0][0:2] == ("update_settings", USER_ID)

    body["consent_version"] = "reminder-preference-v1"
    invalid, invalid_service = asyncio.run(_settings_request("PATCH", body=body))
    assert invalid.status_code == 422
    assert invalid_service.calls == []


def test_notification_settings_patch_maps_stale_or_reused_identity_conflict() -> None:
    body = {
        "contract_version": "notification-settings-v1",
        "request_id": str(REQUEST_ID),
        "expected_updated_at": UPDATED_AT.isoformat(),
        "in_app_delivery_enabled": True,
        "consent_version": "in-app-notification-consent-v1",
        "categories": {
            "focus_prompt": True,
            "recovery_prompt": True,
            "weekly_summary": False,
        },
        "quiet_hours": None,
        "daily_limit": 2,
    }

    response, service = asyncio.run(
        _settings_request(
            "PATCH",
            body=body,
            outcome=NotificationConflictError(
                "Notification settings request id was already used",
            ),
        ),
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "Notification settings request id was already used",
    }
    assert service.calls[0][0:2] == ("update_settings", USER_ID)


def test_in_app_delivery_receipt_is_owner_derived_and_conflict_is_retriable() -> None:
    response, service = asyncio.run(_delivery_request())

    assert response.status_code == 200
    assert response.json() == {
        "contract_version": "in-app-notification-delivery-v1",
        "notification_id": str(NOTIFICATION_ID),
        "channel": "in_app",
        "delivered_at": "2026-07-14T08:30:00Z",
        "replayed": False,
    }
    assert service.calls == [("delivery", USER_ID, NOTIFICATION_ID)]

    conflict, _ = asyncio.run(
        _delivery_request(
            outcome=NotificationConflictError(
                "In-app delivery is currently unavailable",
            ),
        ),
    )
    assert conflict.status_code == 409
