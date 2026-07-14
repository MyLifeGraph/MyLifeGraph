import re
from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient
from app.models.notifications import (
    NotificationLifecycleActionResponse,
    NotificationLifecycleCommand,
)


class NotificationPersistenceError(RuntimeError):
    """A sanitized persistence failure at the notification boundary."""


class NotificationPersistenceConflict(NotificationPersistenceError):
    pass


class NotificationPersistenceNotFound(NotificationPersistenceError):
    pass


class NotificationPersistenceOutcomeUnknown(NotificationPersistenceError):
    pass


class NotificationRepository(Protocol):
    async def apply_action(
        self,
        *,
        user_id: str,
        notification_id: UUID,
        request_id: UUID,
        command: NotificationLifecycleCommand,
        expected_updated_at: str,
    ) -> NotificationLifecycleActionResponse:
        pass


class SupabaseNotificationRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def apply_action(
        self,
        *,
        user_id: str,
        notification_id: UUID,
        request_id: UUID,
        command: NotificationLifecycleCommand,
        expected_updated_at: str,
    ) -> NotificationLifecycleActionResponse:
        params = {
            "p_user_id": user_id,
            "p_notification_id": str(notification_id),
            "p_request_id": str(request_id),
            "p_command": command,
            "p_expected_updated_at": expected_updated_at,
        }
        ambiguous_error: Exception | None = None
        for attempt in range(2):
            try:
                result = await self._client.rpc(
                    "apply_notification_action_v1",
                    params=params,
                )
            except httpx.HTTPStatusError as exc:
                code, message = _postgres_error(exc)
                if code == "PT409":
                    raise NotificationPersistenceConflict(
                        _conflict_message(message),
                    ) from exc
                if code == "PT404":
                    raise NotificationPersistenceNotFound(
                        "Notification is unavailable.",
                    ) from exc
                if exc.response.status_code < 500:
                    raise NotificationPersistenceError(
                        "Notification lifecycle persistence rejected the request.",
                    ) from exc
                ambiguous_error = exc
            except (httpx.HTTPError, ValueError) as exc:
                ambiguous_error = exc
            else:
                try:
                    response = _response_from_rpc(result)
                except (TypeError, ValueError) as exc:
                    ambiguous_error = exc
                else:
                    if (
                        response.notification_id == notification_id
                        and response.command == command
                    ):
                        return response
                    ambiguous_error = ValueError(
                        "Notification lifecycle RPC returned a mismatched result.",
                    )

            if attempt == 0:
                continue

        raise NotificationPersistenceOutcomeUnknown(
            "Notification action outcome could not be determined.",
        ) from ambiguous_error


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        body: Any = exc.response.json()
    except ValueError:
        return None, "Notification lifecycle persistence failed."
    if not isinstance(body, dict):
        return None, "Notification lifecycle persistence failed."
    code = body.get("code")
    message = body.get("message")
    return (
        str(code) if code is not None else None,
        str(message)
        if isinstance(message, str) and message
        else "Notification lifecycle persistence failed.",
    )


def _conflict_message(message: str) -> str:
    allowed = {
        "Notification action request id was already used",
        "Notification changed since it was loaded",
        "Notification is already dismissed",
    }
    if message in allowed:
        return message
    return "Notification action conflicts with current state."


def _response_from_rpc(result: Any) -> NotificationLifecycleActionResponse:
    expected_keys = {
        "contract_version",
        "notification_id",
        "command",
        "is_read",
        "read_at",
        "dismissed_at",
        "updated_at",
        "replayed",
    }
    if not isinstance(result, dict) or set(result) != expected_keys:
        raise ValueError("Notification lifecycle RPC returned an invalid envelope.")
    if not isinstance(result["is_read"], bool) or not isinstance(
        result["replayed"],
        bool,
    ):
        raise ValueError("Notification lifecycle RPC returned an invalid state.")
    raw_notification_id = result["notification_id"]
    if not isinstance(raw_notification_id, str):
        raise ValueError(
            "Notification lifecycle RPC notification id must be a string.",
        )
    notification_id = UUID(raw_notification_id)
    read_at = _aware_datetime(result["read_at"], nullable=True)
    dismissed_at = _aware_datetime(result["dismissed_at"], nullable=True)
    updated_at = _aware_datetime(result["updated_at"], nullable=False)
    return NotificationLifecycleActionResponse(
        contract_version=result["contract_version"],
        notification_id=notification_id,
        command=result["command"],
        is_read=result["is_read"],
        read_at=read_at,
        dismissed_at=dismissed_at,
        updated_at=updated_at,
        replayed=result["replayed"],
    )


def _aware_datetime(value: Any, *, nullable: bool) -> datetime | None:
    if value is None:
        if nullable:
            return None
        raise ValueError("Notification lifecycle RPC timestamp is required.")
    if not isinstance(value, str) or re.fullmatch(
        r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"
        r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
        value,
    ) is None:
        raise ValueError("Notification lifecycle RPC timestamp is invalid.")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Notification lifecycle RPC timestamp must be aware.")
    return parsed
