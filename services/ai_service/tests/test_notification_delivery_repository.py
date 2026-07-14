import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import httpx
import pytest

from app.models.notifications import NotificationSettingsUpdateRequest
from app.repositories.notification_repository import (
    NotificationPersistenceConflict,
    SupabaseNotificationRepository,
)


USER_ID = "11111111-1111-4111-8111-111111111111"
NOTIFICATION_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("33333333-3333-4333-8333-333333333333")
UPDATED_AT = datetime(2026, 7, 14, 8, 30, tzinfo=UTC)


def _settings_contract(*, enabled: bool, replayed: bool = False):
    return {
        "contract_version": "notification-settings-v1",
        "in_app_delivery_enabled": enabled,
        "consent_version": (
            "in-app-notification-consent-v1" if enabled else None
        ),
        "consented_at": UPDATED_AT.isoformat() if enabled else None,
        "disabled_at": None,
        "categories": {
            "focus_prompt": True,
            "recovery_prompt": False,
            "weekly_summary": True,
        },
        "quiet_hours": {"starts_at": "22:00", "ends_at": "07:00"},
        "daily_limit": 2,
        "updated_at": UPDATED_AT.isoformat(),
        "replayed": replayed,
    }


class RpcClient:
    def __init__(self, outcomes) -> None:
        self.outcomes = list(outcomes)
        self.calls = []

    async def rpc(self, function, *, params):
        self.calls.append((function, params))
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class ContextClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, str]]] = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        if table == "profiles":
            return [{"timezone": "Europe/Berlin"}]
        if table == "notification_preferences":
            return [
                {
                    "focus_prompts_enabled": True,
                    "recovery_prompts_enabled": False,
                    "weekly_summary_enabled": True,
                    "quiet_hours_start": "22:00:00",
                    "quiet_hours_end": "07:00:00",
                    "in_app_delivery_enabled": False,
                    "in_app_delivery_consent_version": None,
                    "in_app_delivery_consented_at": None,
                    "in_app_delivery_disabled_at": None,
                    "daily_notification_limit": 2,
                    "updated_at": UPDATED_AT.isoformat(),
                },
            ]
        if table == "daily_briefings":
            return [{"id": "briefing-1"}]
        if table == "user_state_snapshots":
            return [{"id": "snapshot-1"}]
        raise AssertionError(table)


def _http_error(code: str, message: str, status_code: int) -> httpx.HTTPStatusError:
    request = httpx.Request("POST", "http://test/rest/v1/rpc/function")
    response = httpx.Response(
        status_code,
        request=request,
        json={"code": code, "message": message},
    )
    return httpx.HTTPStatusError("upstream", request=request, response=response)


def test_settings_update_retries_exact_request_after_response_loss() -> None:
    client = RpcClient(
        [httpx.ReadError("lost"), _settings_contract(enabled=True, replayed=True)],
    )
    repository = SupabaseNotificationRepository(client)  # type: ignore[arg-type]
    request = NotificationSettingsUpdateRequest.model_validate(
        {
            "contract_version": "notification-settings-v1",
            "request_id": str(REQUEST_ID),
            "expected_updated_at": UPDATED_AT.isoformat(),
            "in_app_delivery_enabled": True,
            "consent_version": "in-app-notification-consent-v1",
            "categories": {
                "focus_prompt": True,
                "recovery_prompt": False,
                "weekly_summary": True,
            },
            "quiet_hours": {"starts_at": "22:00", "ends_at": "07:00"},
            "daily_limit": 2,
        },
    )

    response = asyncio.run(
        repository.update_settings(user_id=USER_ID, request=request),
    )

    assert response.replayed is True
    assert client.calls[0] == client.calls[1]
    assert client.calls[0] == (
        "update_notification_settings_v1",
        {
            "p_user_id": USER_ID,
            "p_request_id": str(REQUEST_ID),
            "p_expected_updated_at": UPDATED_AT.isoformat(),
            "p_in_app_delivery_enabled": True,
            "p_consent_version": "in-app-notification-consent-v1",
            "p_focus_prompt": True,
            "p_recovery_prompt": False,
            "p_weekly_summary": True,
            "p_quiet_hours_start": "22:00",
            "p_quiet_hours_end": "07:00",
            "p_daily_limit": 2,
        },
    )


def test_delivery_conflict_is_sanitized_for_current_settings_race() -> None:
    client = RpcClient(
        [
            _http_error(
                "PT409",
                "In-app delivery is currently unavailable",
                409,
            ),
        ],
    )
    repository = SupabaseNotificationRepository(client)  # type: ignore[arg-type]

    with pytest.raises(
        NotificationPersistenceConflict,
        match="currently unavailable",
    ):
        asyncio.run(
            repository.acknowledge_delivery(
                user_id=USER_ID,
                notification_id=NOTIFICATION_ID,
            ),
        )


def test_generation_context_is_owner_scoped_and_keeps_consent_separate() -> None:
    client = ContextClient()
    repository = SupabaseNotificationRepository(client)  # type: ignore[arg-type]

    context = asyncio.run(
        repository.load_generation_context(
            user_id=USER_ID,
            delivery_date=date(2026, 7, 14),
        ),
    )

    assert context.timezone == "Europe/Berlin"
    assert context.settings.in_app_delivery_enabled is False
    assert context.settings.categories.focus_prompt is True
    assert context.briefing == {"id": "briefing-1"}
    assert context.daily_snapshot == {"id": "snapshot-1"}
    assert {table for table, _ in client.calls} == {
        "profiles",
        "notification_preferences",
        "daily_briefings",
        "user_state_snapshots",
    }
    for table, params in client.calls:
        assert params["user_id" if table != "profiles" else "id"] == (
            f"eq.{USER_ID}"
        )
