from datetime import UTC, datetime
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.models.notifications import (
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
)


REQUEST_ID = "11111111-1111-4111-8111-111111111111"
NOTIFICATION_ID = UUID("22222222-2222-4222-8222-222222222222")
UPDATED_AT = "2026-07-14T08:30:00+00:00"


def test_notification_lifecycle_models_accept_only_the_strict_aware_contract() -> None:
    request = NotificationLifecycleActionRequest.model_validate_json(
        (
            '{"contract_version":"notification-lifecycle-v1",'
            f'"request_id":"{REQUEST_ID}",'
            '"command":"mark_read",'
            f'"expected_updated_at":"{UPDATED_AT}"}}'
        ),
    )
    response = NotificationLifecycleActionResponse(
        contract_version="notification-lifecycle-v1",
        notification_id=NOTIFICATION_ID,
        command="mark_read",
        is_read=True,
        read_at=datetime(2026, 7, 14, 8, 31, tzinfo=UTC),
        dismissed_at=None,
        updated_at=datetime(2026, 7, 14, 8, 31, tzinfo=UTC),
        replayed=False,
    )

    assert str(request.request_id) == REQUEST_ID
    assert request.expected_updated_at.tzinfo is not None
    assert response.model_dump()["notification_id"] == NOTIFICATION_ID


@pytest.mark.parametrize(
    "timestamp",
    [
        "2026-07-14T08:30:00Z",
        "2026-07-14T10:30:00+02:00",
        "2026-07-14 08:30:00+00:00",
    ],
)
def test_notification_lifecycle_request_accepts_aware_iso_strings(
    timestamp: str,
) -> None:
    request = NotificationLifecycleActionRequest.model_validate(
        {
            "contract_version": "notification-lifecycle-v1",
            "request_id": REQUEST_ID,
            "command": "mark_read",
            "expected_updated_at": timestamp,
        },
    )

    assert request.expected_updated_at.utcoffset() is not None


@pytest.mark.parametrize(
    "timestamp",
    [
        1_721_035_800,
        "1721035800",
        "2026-07-14T08:30:00",
        "2026-07-14🦊08:30:00+00:00",
        {"value": "2026-07-14T08:30:00Z"},
        datetime(2026, 7, 14, 8, 30, tzinfo=UTC),
    ],
)
def test_notification_lifecycle_request_rejects_coerced_timestamps(
    timestamp: object,
) -> None:
    with pytest.raises(ValidationError):
        NotificationLifecycleActionRequest.model_validate(
            {
                "contract_version": "notification-lifecycle-v1",
                "request_id": REQUEST_ID,
                "command": "mark_read",
                "expected_updated_at": timestamp,
            },
        )


@pytest.mark.parametrize(
    "change",
    [
        {"contract_version": "notification-lifecycle-v2"},
        {"command": "delete"},
        {"expected_updated_at": "2026-07-14T08:30:00"},
        {"extra": True},
    ],
)
def test_notification_lifecycle_request_rejects_unknown_or_unsafe_shapes(
    change: dict[str, object],
) -> None:
    payload: dict[str, object] = {
        "contract_version": "notification-lifecycle-v1",
        "request_id": REQUEST_ID,
        "command": "mark_read",
        "expected_updated_at": UPDATED_AT,
    }
    payload.update(change)

    with pytest.raises(ValidationError):
        NotificationLifecycleActionRequest.model_validate(payload)


def test_notification_lifecycle_response_requires_aware_timestamps() -> None:
    with pytest.raises(ValidationError):
        NotificationLifecycleActionResponse(
            contract_version="notification-lifecycle-v1",
            notification_id=NOTIFICATION_ID,
            command="dismiss",
            is_read=True,
            read_at=datetime(2026, 7, 14, 8, 31),
            dismissed_at=datetime(2026, 7, 14, 8, 31),
            updated_at=datetime(2026, 7, 14, 8, 31),
            replayed=False,
        )


def test_notification_lifecycle_response_rejects_inconsistent_command_state() -> None:
    with pytest.raises(ValidationError, match="mark_unread"):
        NotificationLifecycleActionResponse(
            contract_version="notification-lifecycle-v1",
            notification_id=NOTIFICATION_ID,
            command="mark_unread",
            is_read=True,
            read_at=datetime(2026, 7, 14, 8, 31, tzinfo=UTC),
            dismissed_at=None,
            updated_at=datetime(2026, 7, 14, 8, 31, tzinfo=UTC),
            replayed=False,
        )
