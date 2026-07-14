import asyncio
import re
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient
from app.models.notifications import (
    NotificationCategories,
    NotificationCategory,
    NotificationDeliveryReceiptResponse,
    NotificationGenerationStatus,
    NotificationLifecycleActionResponse,
    NotificationLifecycleCommand,
    NotificationQuietHours,
    NotificationSettingsResponse,
    NotificationSettingsUpdateRequest,
)


class NotificationPersistenceError(RuntimeError):
    """A sanitized persistence failure at the notification boundary."""


class NotificationPersistenceConflict(NotificationPersistenceError):
    pass


class NotificationPersistenceNotFound(NotificationPersistenceError):
    pass


class NotificationPersistenceOutcomeUnknown(NotificationPersistenceError):
    pass


@dataclass(frozen=True, slots=True)
class NotificationGenerationContext:
    timezone: str
    settings: NotificationSettingsResponse
    briefing: dict[str, Any] | None
    daily_snapshot: dict[str, Any] | None


@dataclass(frozen=True, slots=True)
class GeneratedNotificationWriteResult:
    status: NotificationGenerationStatus
    notification_id: UUID | None


class NotificationRepository(Protocol):
    async def get_settings(self, *, user_id: str) -> NotificationSettingsResponse:
        pass

    async def update_settings(
        self,
        *,
        user_id: str,
        request: NotificationSettingsUpdateRequest,
    ) -> NotificationSettingsResponse:
        pass

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

    async def acknowledge_delivery(
        self,
        *,
        user_id: str,
        notification_id: UUID,
    ) -> NotificationDeliveryReceiptResponse:
        pass

    async def load_generation_context(
        self,
        *,
        user_id: str,
        delivery_date: date,
    ) -> NotificationGenerationContext:
        pass

    async def create_generated_notification(
        self,
        *,
        user_id: str,
        notification_id: UUID,
        generation_key: str,
        category: NotificationCategory,
        delivery_date: date,
        run_at: datetime,
        timezone: str,
        title: str,
        message: str,
        notification_type: str,
        priority: str,
        action_url: str,
        reason_code: str,
        source_kind: str,
        source_id: str,
        source_generated_at: datetime,
    ) -> GeneratedNotificationWriteResult:
        pass


class SupabaseNotificationRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_settings(self, *, user_id: str) -> NotificationSettingsResponse:
        rows = await self._client.select(
            "notification_preferences",
            params={
                "select": (
                    "focus_prompts_enabled,recovery_prompts_enabled,"
                    "weekly_summary_enabled,quiet_hours_start,quiet_hours_end,"
                    "in_app_delivery_enabled,in_app_delivery_consent_version,"
                    "in_app_delivery_consented_at,in_app_delivery_disabled_at,"
                    "daily_notification_limit,updated_at"
                ),
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if len(rows) != 1:
            raise NotificationPersistenceNotFound(
                "Notification settings are unavailable.",
            )
        try:
            return _settings_from_row(rows[0], replayed=False)
        except (TypeError, ValueError) as exc:
            raise NotificationPersistenceError(
                "Notification settings persistence returned invalid data.",
            ) from exc

    async def update_settings(
        self,
        *,
        user_id: str,
        request: NotificationSettingsUpdateRequest,
    ) -> NotificationSettingsResponse:
        quiet_hours = request.quiet_hours
        params = {
            "p_user_id": user_id,
            "p_request_id": str(request.request_id),
            "p_expected_updated_at": request.expected_updated_at.isoformat(),
            "p_in_app_delivery_enabled": request.in_app_delivery_enabled,
            "p_consent_version": request.consent_version,
            "p_focus_prompt": request.categories.focus_prompt,
            "p_recovery_prompt": request.categories.recovery_prompt,
            "p_weekly_summary": request.categories.weekly_summary,
            "p_quiet_hours_start": (
                quiet_hours.starts_at if quiet_hours is not None else None
            ),
            "p_quiet_hours_end": (
                quiet_hours.ends_at if quiet_hours is not None else None
            ),
            "p_daily_limit": request.daily_limit,
        }
        return await self._retry_rpc_response(
            function="update_notification_settings_v1",
            params=params,
            parser=_settings_from_rpc,
            mismatch=lambda response: False,
            outcome_message="Notification settings outcome could not be determined.",
        )

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

    async def acknowledge_delivery(
        self,
        *,
        user_id: str,
        notification_id: UUID,
    ) -> NotificationDeliveryReceiptResponse:
        return await self._retry_rpc_response(
            function="acknowledge_in_app_notification_v1",
            params={
                "p_user_id": user_id,
                "p_notification_id": str(notification_id),
            },
            parser=_delivery_receipt_from_rpc,
            mismatch=lambda response: response.notification_id != notification_id,
            outcome_message="In-app delivery outcome could not be determined.",
        )

    async def load_generation_context(
        self,
        *,
        user_id: str,
        delivery_date: date,
    ) -> NotificationGenerationContext:
        profile_rows, settings, briefing_rows, snapshot_rows = (
            await asyncio.gather(
                self._client.select(
                    "profiles",
                    params={
                        "select": "timezone",
                        "id": f"eq.{user_id}",
                        "onboarding_completed_at": "not.is.null",
                        "role": "neq.guest",
                        "limit": "1",
                    },
                ),
                self.get_settings(user_id=user_id),
                self._client.select(
                    "daily_briefings",
                    params={
                        "select": "id,generated_at,mode,data_quality,provenance",
                        "user_id": f"eq.{user_id}",
                        "briefing_date": f"eq.{delivery_date.isoformat()}",
                        "limit": "1",
                    },
                ),
                self._client.select(
                    "user_state_snapshots",
                    params={
                        "select": "id,generated_at,summary",
                        "user_id": f"eq.{user_id}",
                        "scope": "eq.daily",
                        "period_key": f"eq.{delivery_date.isoformat()}",
                        "limit": "1",
                    },
                ),
            )
        )
        if len(profile_rows) != 1:
            raise NotificationPersistenceNotFound(
                "Notification generation profile is unavailable.",
            )
        timezone = profile_rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone.strip():
            raise NotificationPersistenceError(
                "Notification generation timezone is invalid.",
            )
        return NotificationGenerationContext(
            timezone=timezone,
            settings=settings,
            briefing=_optional_single_row(briefing_rows),
            daily_snapshot=_optional_single_row(snapshot_rows),
        )

    async def create_generated_notification(
        self,
        *,
        user_id: str,
        notification_id: UUID,
        generation_key: str,
        category: NotificationCategory,
        delivery_date: date,
        run_at: datetime,
        timezone: str,
        title: str,
        message: str,
        notification_type: str,
        priority: str,
        action_url: str,
        reason_code: str,
        source_kind: str,
        source_id: str,
        source_generated_at: datetime,
    ) -> GeneratedNotificationWriteResult:
        try:
            result = await self._client.rpc(
                "create_generated_notification_v1",
                params={
                    "p_user_id": user_id,
                    "p_notification_id": str(notification_id),
                    "p_generation_key": generation_key,
                    "p_category": category,
                    "p_delivery_date": delivery_date.isoformat(),
                    "p_run_at": run_at.isoformat(),
                    "p_timezone": timezone,
                    "p_title": title,
                    "p_message": message,
                    "p_type": notification_type,
                    "p_priority": priority,
                    "p_action_url": action_url,
                    "p_reason_code": reason_code,
                    "p_source_kind": source_kind,
                    "p_source_id": source_id,
                    "p_source_generated_at": source_generated_at.isoformat(),
                },
            )
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code == "PT409":
                raise NotificationPersistenceConflict(
                    _conflict_message(message),
                ) from exc
            raise NotificationPersistenceError(
                "Notification generation persistence failed.",
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise NotificationPersistenceOutcomeUnknown(
                "Notification generation outcome could not be determined.",
            ) from exc
        return _generated_write_result(result)

    async def _retry_rpc_response(
        self,
        *,
        function: str,
        params: dict[str, Any],
        parser,
        mismatch,
        outcome_message: str,
    ):
        ambiguous_error: Exception | None = None
        for attempt in range(2):
            try:
                result = await self._client.rpc(function, params=params)
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
                        "Notification persistence rejected the request.",
                    ) from exc
                ambiguous_error = exc
            except (httpx.HTTPError, ValueError) as exc:
                ambiguous_error = exc
            else:
                try:
                    response = parser(result)
                except (TypeError, ValueError) as exc:
                    ambiguous_error = exc
                else:
                    if not mismatch(response):
                        return response
                    ambiguous_error = ValueError(
                        "Notification RPC returned a mismatched result.",
                    )
            if attempt == 0:
                continue
        raise NotificationPersistenceOutcomeUnknown(outcome_message) from ambiguous_error


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
        "Notification settings request id was already used",
        "Notification settings changed since they were loaded",
        "Notification timezone changed",
        "In-app delivery is currently unavailable",
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


def _settings_from_rpc(result: Any) -> NotificationSettingsResponse:
    if not isinstance(result, dict):
        raise ValueError("Notification settings RPC returned an invalid envelope.")
    return _settings_from_contract(result)


def _settings_from_row(
    row: dict[str, Any],
    *,
    replayed: bool,
) -> NotificationSettingsResponse:
    expected_keys = {
        "focus_prompts_enabled",
        "recovery_prompts_enabled",
        "weekly_summary_enabled",
        "quiet_hours_start",
        "quiet_hours_end",
        "in_app_delivery_enabled",
        "in_app_delivery_consent_version",
        "in_app_delivery_consented_at",
        "in_app_delivery_disabled_at",
        "daily_notification_limit",
        "updated_at",
    }
    if set(row) != expected_keys:
        raise ValueError("Notification settings row shape is invalid.")
    quiet_start = _clock_time(row["quiet_hours_start"])
    quiet_end = _clock_time(row["quiet_hours_end"])
    if (quiet_start is None) != (quiet_end is None):
        raise ValueError("Notification quiet hours are incomplete.")
    return NotificationSettingsResponse(
        contract_version="notification-settings-v1",
        in_app_delivery_enabled=_required_bool(
            row["in_app_delivery_enabled"],
        ),
        consent_version=row["in_app_delivery_consent_version"],
        consented_at=_aware_datetime(
            row["in_app_delivery_consented_at"],
            nullable=True,
        ),
        disabled_at=_aware_datetime(
            row["in_app_delivery_disabled_at"],
            nullable=True,
        ),
        categories=NotificationCategories(
            focus_prompt=_required_bool(row["focus_prompts_enabled"]),
            recovery_prompt=_required_bool(row["recovery_prompts_enabled"]),
            weekly_summary=_required_bool(row["weekly_summary_enabled"]),
        ),
        quiet_hours=(
            NotificationQuietHours(starts_at=quiet_start, ends_at=quiet_end)
            if quiet_start is not None and quiet_end is not None
            else None
        ),
        daily_limit=_required_int(row["daily_notification_limit"]),
        updated_at=_aware_datetime(row["updated_at"], nullable=False),
        replayed=replayed,
    )


def _settings_from_contract(result: dict[str, Any]) -> NotificationSettingsResponse:
    expected_keys = {
        "contract_version",
        "in_app_delivery_enabled",
        "consent_version",
        "consented_at",
        "disabled_at",
        "categories",
        "quiet_hours",
        "daily_limit",
        "updated_at",
        "replayed",
    }
    if set(result) != expected_keys:
        raise ValueError("Notification settings response shape is invalid.")
    categories = result["categories"]
    if not isinstance(categories, dict) or set(categories) != {
        "focus_prompt",
        "recovery_prompt",
        "weekly_summary",
    }:
        raise ValueError("Notification categories response is invalid.")
    quiet_hours = result["quiet_hours"]
    if quiet_hours is not None and (
        not isinstance(quiet_hours, dict)
        or set(quiet_hours) != {"starts_at", "ends_at"}
    ):
        raise ValueError("Notification quiet hours response is invalid.")
    return NotificationSettingsResponse(
        contract_version=result["contract_version"],
        in_app_delivery_enabled=_required_bool(
            result["in_app_delivery_enabled"],
        ),
        consent_version=result["consent_version"],
        consented_at=_aware_datetime(result["consented_at"], nullable=True),
        disabled_at=_aware_datetime(result["disabled_at"], nullable=True),
        categories=NotificationCategories(
            focus_prompt=_required_bool(categories["focus_prompt"]),
            recovery_prompt=_required_bool(categories["recovery_prompt"]),
            weekly_summary=_required_bool(categories["weekly_summary"]),
        ),
        quiet_hours=(
            NotificationQuietHours(
                starts_at=_required_clock_time(quiet_hours["starts_at"]),
                ends_at=_required_clock_time(quiet_hours["ends_at"]),
            )
            if quiet_hours is not None
            else None
        ),
        daily_limit=_required_int(result["daily_limit"]),
        updated_at=_aware_datetime(result["updated_at"], nullable=False),
        replayed=_required_bool(result["replayed"]),
    )


def _delivery_receipt_from_rpc(result: Any) -> NotificationDeliveryReceiptResponse:
    expected_keys = {
        "contract_version",
        "notification_id",
        "channel",
        "delivered_at",
        "replayed",
    }
    if not isinstance(result, dict) or set(result) != expected_keys:
        raise ValueError("In-app delivery RPC returned an invalid envelope.")
    notification_id = result["notification_id"]
    if not isinstance(notification_id, str):
        raise ValueError("In-app delivery notification id is invalid.")
    return NotificationDeliveryReceiptResponse(
        contract_version=result["contract_version"],
        notification_id=UUID(notification_id),
        channel=result["channel"],
        delivered_at=_aware_datetime(result["delivered_at"], nullable=False),
        replayed=_required_bool(result["replayed"]),
    )


def _generated_write_result(result: Any) -> GeneratedNotificationWriteResult:
    if not isinstance(result, dict) or set(result) not in (
        {"status"},
        {"status", "notification_id"},
    ):
        raise NotificationPersistenceError(
            "Notification generation persistence returned invalid data.",
        )
    status = result["status"]
    allowed_statuses = {
        "created",
        "duplicate",
        "not_consented",
        "category_disabled",
        "quiet_hours",
        "daily_limit",
    }
    if status not in allowed_statuses:
        raise NotificationPersistenceError(
            "Notification generation persistence returned invalid status.",
        )
    raw_id = result.get("notification_id")
    if status in {"created", "duplicate"}:
        if not isinstance(raw_id, str):
            raise NotificationPersistenceError(
                "Notification generation persistence returned invalid identity.",
            )
        notification_id = UUID(raw_id)
    elif raw_id is not None:
        raise NotificationPersistenceError(
            "Notification generation persistence returned unexpected identity.",
        )
    else:
        notification_id = None
    return GeneratedNotificationWriteResult(
        status=status,
        notification_id=notification_id,
    )


def _optional_single_row(rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    if len(rows) > 1:
        raise NotificationPersistenceError(
            "Notification generation source identity is ambiguous.",
        )
    return rows[0] if rows else None


def _required_bool(value: Any) -> bool:
    if not isinstance(value, bool):
        raise ValueError("Notification boolean is invalid.")
    return value


def _required_int(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Notification integer is invalid.")
    return value


def _required_clock_time(value: Any) -> str:
    normalized = _clock_time(value)
    if normalized is None:
        raise ValueError("Notification clock time is required.")
    return normalized


def _clock_time(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or re.fullmatch(
        r"(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,6})?)?",
        value,
    ) is None:
        raise ValueError("Notification clock time is invalid.")
    return value[:5]
