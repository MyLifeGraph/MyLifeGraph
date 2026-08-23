import asyncio
from datetime import UTC, datetime
from uuid import UUID

import httpx
import pytest

from app.repositories.notification_repository import (
    NotificationPersistenceConflict,
    NotificationPersistenceNotFound,
    NotificationPersistenceOutcomeUnknown,
    SupabaseNotificationRepository,
)


NOTIFICATION_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
UPDATED_AT = datetime(2026, 7, 14, 8, 30, tzinfo=UTC)


class Client:
    def __init__(self, outcomes) -> None:
        self.outcomes = list(outcomes)
        self.calls = []

    async def rpc(self, function, *, params):
        self.calls.append((function, params))
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def _result(*, command="mark_read", replayed=False):
    return {
        "contract_version": "notification-lifecycle-v1",
        "notification_id": str(NOTIFICATION_ID),
        "command": command,
        "is_read": command != "mark_unread",
        "read_at": None if command == "mark_unread" else UPDATED_AT.isoformat(),
        "dismissed_at": UPDATED_AT.isoformat() if command == "dismiss" else None,
        "updated_at": UPDATED_AT.isoformat(),
        "replayed": replayed,
    }


def _http_error(code: str, message: str, status_code: int) -> httpx.HTTPStatusError:
    request = httpx.Request(
        "POST",
        "http://test/rest/v1/rpc/apply_notification_action_v1",
    )
    response = httpx.Response(
        status_code,
        request=request,
        json={"code": code, "message": message},
    )
    return httpx.HTTPStatusError("upstream", request=request, response=response)


def _apply(repository: SupabaseNotificationRepository, *, command="mark_read"):
    return asyncio.run(
        repository.apply_action(
            user_id="owner-1",
            notification_id=NOTIFICATION_ID,
            request_id=REQUEST_ID,
            command=command,
            expected_updated_at=UPDATED_AT.isoformat(),
        ),
    )


def test_notification_repository_calls_only_the_idempotent_rpc() -> None:
    client = Client([_result()])
    repository = SupabaseNotificationRepository(client)  # type: ignore[arg-type]

    response = _apply(repository)

    assert response.replayed is False
    assert client.calls == [
        (
            "apply_notification_action_v1",
            {
                "p_user_id": "owner-1",
                "p_notification_id": str(NOTIFICATION_ID),
                "p_request_id": str(REQUEST_ID),
                "p_command": "mark_read",
                "p_expected_updated_at": UPDATED_AT.isoformat(),
            },
        ),
    ]


def test_notification_repository_replays_once_after_ambiguous_response_loss() -> None:
    client = Client([httpx.ReadError("lost"), _result(replayed=True)])
    repository = SupabaseNotificationRepository(client)  # type: ignore[arg-type]

    response = _apply(repository)

    assert response.replayed is True
    assert len(client.calls) == 2
    assert client.calls[0] == client.calls[1]


@pytest.mark.parametrize("command", ["mark_read", "mark_unread", "dismiss"])
def test_notification_repository_accepts_every_lifecycle_command(command) -> None:
    client = Client([_result(command=command)])
    repository = SupabaseNotificationRepository(client)  # type: ignore[arg-type]

    response = _apply(repository, command=command)

    assert response.command == command
    assert response.is_read is (command != "mark_unread")
    assert (response.dismissed_at is not None) is (command == "dismiss")


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (
            _http_error("PT409", "Notification changed since it was loaded", 409),
            NotificationPersistenceConflict,
        ),
        (
            _http_error("PT404", "Notification is unavailable", 404),
            NotificationPersistenceNotFound,
        ),
    ],
)
def test_notification_repository_maps_conflict_and_owner_isolation(
    error: Exception,
    expected: type[Exception],
) -> None:
    repository = SupabaseNotificationRepository(  # type: ignore[arg-type]
        Client([error]),
    )

    with pytest.raises(expected):
        _apply(repository)


def test_notification_repository_rejects_two_invalid_results() -> None:
    invalid = {**_result(), "notification_id": str(REQUEST_ID)}
    repository = SupabaseNotificationRepository(  # type: ignore[arg-type]
        Client([invalid, invalid]),
    )

    with pytest.raises(NotificationPersistenceOutcomeUnknown):
        _apply(repository)


def test_notification_repository_rejects_numeric_uuid_coercion() -> None:
    numeric_uuid = int(NOTIFICATION_ID.hex, 16)
    invalid = {**_result(), "notification_id": numeric_uuid}
    repository = SupabaseNotificationRepository(  # type: ignore[arg-type]
        Client([invalid, invalid]),
    )

    with pytest.raises(NotificationPersistenceOutcomeUnknown):
        _apply(repository)


@pytest.mark.parametrize(
    "timestamp",
    [
        UPDATED_AT,
        "2026-07-14🦊08:30:00+00:00",
    ],
)
def test_notification_repository_rejects_non_json_or_non_iso_timestamps(
    timestamp: object,
) -> None:
    invalid = {**_result(), "updated_at": timestamp}
    repository = SupabaseNotificationRepository(  # type: ignore[arg-type]
        Client([invalid, invalid]),
    )

    with pytest.raises(NotificationPersistenceOutcomeUnknown):
        _apply(repository)
