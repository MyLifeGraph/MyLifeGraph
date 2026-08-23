import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest

from app.models.notifications import (
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
)
from app.repositories.notification_repository import (
    NotificationPersistenceConflict,
    NotificationPersistenceError,
    NotificationPersistenceNotFound,
    NotificationPersistenceOutcomeUnknown,
)
from app.services.notification_service import (
    NotificationConflictError,
    NotificationNotFoundError,
    NotificationOutcomeUnknownError,
    NotificationService,
    NotificationServiceUnavailableError,
)


NOTIFICATION_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
UPDATED_AT = datetime(2026, 7, 14, 8, 30, tzinfo=UTC)


class Repository:
    def __init__(self, outcome=None) -> None:
        self.calls = []
        self.outcome = outcome or NotificationLifecycleActionResponse(
            contract_version="notification-lifecycle-v1",
            notification_id=NOTIFICATION_ID,
            command="mark_read",
            is_read=True,
            read_at=UPDATED_AT,
            dismissed_at=None,
            updated_at=UPDATED_AT,
            replayed=False,
        )

    async def apply_action(self, **kwargs):
        self.calls.append(kwargs)
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return self.outcome


def _request() -> NotificationLifecycleActionRequest:
    return NotificationLifecycleActionRequest(
        contract_version="notification-lifecycle-v1",
        request_id=REQUEST_ID,
        command="mark_read",
        expected_updated_at=UPDATED_AT.isoformat(),
    )


def test_notification_service_passes_only_bearer_owner_and_exact_command() -> None:
    repository = Repository()
    service = NotificationService(repository=repository)

    response = asyncio.run(
        service.apply_action(
            user_id="owner-1",
            notification_id=NOTIFICATION_ID,
            request=_request(),
        ),
    )

    assert response.notification_id == NOTIFICATION_ID
    assert repository.calls == [
        {
            "user_id": "owner-1",
            "notification_id": NOTIFICATION_ID,
            "request_id": REQUEST_ID,
            "command": "mark_read",
            "expected_updated_at": UPDATED_AT.isoformat(),
        },
    ]


@pytest.mark.parametrize(
    ("persistence_error", "service_error"),
    [
        (NotificationPersistenceConflict("changed"), NotificationConflictError),
        (NotificationPersistenceNotFound("hidden"), NotificationNotFoundError),
        (
            NotificationPersistenceOutcomeUnknown("unknown"),
            NotificationOutcomeUnknownError,
        ),
        (NotificationPersistenceError("down"), NotificationServiceUnavailableError),
    ],
)
def test_notification_service_maps_persistence_errors_without_owner_leakage(
    persistence_error: Exception,
    service_error: type[Exception],
) -> None:
    service = NotificationService(repository=Repository(persistence_error))

    with pytest.raises(service_error):
        asyncio.run(
            service.apply_action(
                user_id="owner-1",
                notification_id=NOTIFICATION_ID,
                request=_request(),
            ),
        )
