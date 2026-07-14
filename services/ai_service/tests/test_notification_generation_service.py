import asyncio
from datetime import UTC, date, datetime
from types import SimpleNamespace

import pytest

from app.models.notifications import (
    NotificationCategories,
    NotificationSettingsResponse,
)
from app.repositories.notification_repository import (
    GeneratedNotificationWriteResult,
    NotificationGenerationContext,
)
from app.services.notification_service import (
    NotificationGenerationService,
    NotificationServiceUnavailableError,
)


USER_ID = "11111111-1111-4111-8111-111111111111"
DELIVERY_DATE = date(2026, 7, 13)
RUN_AT = datetime(2026, 7, 13, 8, 0, tzinfo=UTC)
GENERATED_AT = "2026-07-13T07:30:00+00:00"
SNAPSHOT_ID = "22222222-2222-4222-8222-222222222222"
BRIEFING_ID = "33333333-3333-4333-8333-333333333333"
REVIEW_ID = "44444444-4444-4444-8444-444444444444"


def _settings(
    *,
    enabled: bool = True,
    focus_prompt: bool = True,
    recovery_prompt: bool = True,
    weekly_summary: bool = True,
) -> NotificationSettingsResponse:
    return NotificationSettingsResponse(
        contract_version="notification-settings-v1",
        in_app_delivery_enabled=enabled,
        consent_version=("in-app-notification-consent-v1" if enabled else None),
        consented_at=(RUN_AT if enabled else None),
        disabled_at=None,
        categories=NotificationCategories(
            focus_prompt=focus_prompt,
            recovery_prompt=recovery_prompt,
            weekly_summary=weekly_summary,
        ),
        quiet_hours=None,
        daily_limit=2,
        updated_at=RUN_AT,
        replayed=False,
    )


def _context(
    *,
    enabled: bool = True,
    mode: str = "steady",
    focus_prompt: bool = True,
    recovery_prompt: bool = True,
    weekly_summary: bool = True,
) -> NotificationGenerationContext:
    snapshot = {
        "id": SNAPSHOT_ID,
        "generated_at": GENERATED_AT,
        "summary": {
            "daily_state": {
                "contract_version": "explainable-daily-state-v1",
                "target_date": DELIVERY_DATE.isoformat(),
                "mode": mode,
            },
        },
    }
    return NotificationGenerationContext(
        timezone="UTC",
        settings=_settings(
            enabled=enabled,
            focus_prompt=focus_prompt,
            recovery_prompt=recovery_prompt,
            weekly_summary=weekly_summary,
        ),
        daily_snapshot=snapshot,
        briefing={
            "id": BRIEFING_ID,
            "generated_at": GENERATED_AT,
            "provenance": {
                "source_snapshot_id": SNAPSHOT_ID,
                "source_snapshot_generated_at": GENERATED_AT,
            },
        },
    )


def _weekly_response(*, freshness: str = "missing") -> SimpleNamespace:
    return SimpleNamespace(
        freshness=freshness,
        period_key="2026-W28",
        starts_on=date(2026, 7, 6),
        ends_on=date(2026, 7, 12),
        review=(
            SimpleNamespace(
                id=REVIEW_ID,
                generated_at=datetime.fromisoformat(GENERATED_AT),
            )
            if freshness in {"current", "stale"}
            else None
        ),
    )


class Repository:
    def __init__(
        self,
        context: NotificationGenerationContext,
        statuses: list[str] | None = None,
    ) -> None:
        self.context = context
        self.statuses = list(statuses or ["created", "created"])
        self.context_calls: list[dict[str, object]] = []
        self.write_calls: list[dict[str, object]] = []

    async def load_generation_context(self, **kwargs):
        self.context_calls.append(kwargs)
        return self.context

    async def create_generated_notification(self, **kwargs):
        self.write_calls.append(kwargs)
        status = self.statuses.pop(0)
        return GeneratedNotificationWriteResult(
            status=status,
            notification_id=(
                kwargs["notification_id"]
                if status in {"created", "duplicate"}
                else None
            ),
        )


class WeeklyReviewReader:
    def __init__(self, response: SimpleNamespace | None = None) -> None:
        self.response = response or _weekly_response()
        self.calls: list[dict[str, object]] = []

    async def get_latest(self, **kwargs):
        self.calls.append(kwargs)
        return self.response


def _generate(
    repository: Repository,
    *,
    weekly_response: SimpleNamespace | None = None,
):
    return asyncio.run(
        NotificationGenerationService(
            repository=repository,
            weekly_review_reader=WeeklyReviewReader(weekly_response),
        ).generate_for_user(
            user_id=USER_ID,
            delivery_date=DELIVERY_DATE,
            run_at=RUN_AT,
        ),
    )


def test_generation_requires_explicit_in_app_consent_before_any_write() -> None:
    repository = Repository(_context(enabled=False))

    result = _generate(repository)

    assert result.status == "not_consented"
    assert result.created_count == 0
    assert repository.write_calls == []


def test_recovery_mode_suppresses_generic_focus_and_uses_safe_fixed_copy() -> None:
    repository = Repository(_context(mode="recover"), ["created"])

    result = _generate(repository)

    assert result.status == "created"
    assert result.category == "recovery_prompt"
    assert len(repository.write_calls) == 1
    write = repository.write_calls[0]
    assert write["generation_key"] == (
        "notification-generation-v1:recovery_prompt:2026-07-13"
    )
    assert write["reason_code"] == "current_recovery_mode"
    assert write["source_kind"] == "daily_state"
    assert write["source_id"] == SNAPSHOT_ID
    assert write["action_url"] == "/dashboard"
    assert "private check-in details" in write["message"]


def test_recovery_mode_still_suppresses_focus_when_recovery_category_is_off() -> None:
    repository = Repository(
        _context(
            mode="recover",
            focus_prompt=True,
            recovery_prompt=False,
            weekly_summary=False,
        ),
    )

    result = _generate(repository)

    assert result.status == "no_candidate"
    assert repository.write_calls == []


def test_current_monday_review_adds_one_exact_weekly_candidate() -> None:
    repository = Repository(_context())

    result = _generate(
        repository,
        weekly_response=_weekly_response(freshness="current"),
    )

    assert result.created_count == 2
    assert [call["category"] for call in repository.write_calls] == [
        "focus_prompt",
        "weekly_summary",
    ]
    assert repository.write_calls[1]["generation_key"] == (
        "notification-generation-v1:weekly_summary:2026-W28"
    )


def test_stale_weekly_review_is_not_presented_as_current() -> None:
    repository = Repository(_context(), ["created"])

    result = _generate(
        repository,
        weekly_response=_weekly_response(freshness="stale"),
    )

    assert result.created_count == 1
    assert [call["category"] for call in repository.write_calls] == [
        "focus_prompt",
    ]


def test_generation_keeps_successful_category_when_later_candidate_hits_cap() -> None:
    repository = Repository(_context(), ["created", "daily_limit"])

    result = _generate(
        repository,
        weekly_response=_weekly_response(freshness="current"),
    )

    assert result.status == "created"
    assert result.category == "focus_prompt"
    assert result.created_count == 1


def test_generation_rejects_a_date_outside_the_profile_timezone() -> None:
    repository = Repository(_context())
    service = NotificationGenerationService(
        repository=repository,
        weekly_review_reader=WeeklyReviewReader(),
    )

    with pytest.raises(NotificationServiceUnavailableError, match="profile timezone"):
        asyncio.run(
            service.generate_for_user(
                user_id=USER_ID,
                delivery_date=date(2026, 7, 12),
                run_at=RUN_AT,
            ),
        )

    assert repository.write_calls == []
