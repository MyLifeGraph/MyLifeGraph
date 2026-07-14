from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any, Protocol
from uuid import NAMESPACE_URL, UUID, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.notifications import (
    NotificationCategory,
    NotificationDeliveryReceiptResponse,
    NotificationGenerationResult,
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
    NotificationSettingsResponse,
    NotificationSettingsUpdateRequest,
)
from app.models.weekly_reviews import WeeklyReviewReadResponse
from app.repositories.notification_repository import (
    NotificationGenerationContext,
    NotificationPersistenceConflict,
    NotificationPersistenceError,
    NotificationPersistenceNotFound,
    NotificationPersistenceOutcomeUnknown,
    NotificationRepository,
)


class NotificationConflictError(ValueError):
    pass


class NotificationNotFoundError(ValueError):
    pass


class NotificationOutcomeUnknownError(RuntimeError):
    pass


class NotificationServiceUnavailableError(RuntimeError):
    pass


class NotificationWeeklyReviewReader(Protocol):
    async def get_latest(self, *, user_id: str) -> WeeklyReviewReadResponse:
        pass


class NotificationService:
    def __init__(self, *, repository: NotificationRepository) -> None:
        self._repository = repository

    async def get_settings(self, *, user_id: str) -> NotificationSettingsResponse:
        try:
            return await self._repository.get_settings(user_id=user_id)
        except NotificationPersistenceNotFound as exc:
            raise NotificationNotFoundError(
                "Notification settings are unavailable.",
            ) from exc
        except NotificationPersistenceError as exc:
            raise NotificationServiceUnavailableError(
                "Notification settings persistence is unavailable.",
            ) from exc

    async def update_settings(
        self,
        *,
        user_id: str,
        request: NotificationSettingsUpdateRequest,
    ) -> NotificationSettingsResponse:
        try:
            return await self._repository.update_settings(
                user_id=user_id,
                request=request,
            )
        except NotificationPersistenceConflict as exc:
            raise NotificationConflictError(str(exc)) from exc
        except NotificationPersistenceNotFound as exc:
            raise NotificationNotFoundError(
                "Notification settings are unavailable.",
            ) from exc
        except NotificationPersistenceOutcomeUnknown as exc:
            raise NotificationOutcomeUnknownError(
                "Notification settings outcome could not be determined.",
            ) from exc
        except NotificationPersistenceError as exc:
            raise NotificationServiceUnavailableError(
                "Notification settings persistence is unavailable.",
            ) from exc

    async def apply_action(
        self,
        *,
        user_id: str,
        notification_id: UUID,
        request: NotificationLifecycleActionRequest,
    ) -> NotificationLifecycleActionResponse:
        try:
            return await self._repository.apply_action(
                user_id=user_id,
                notification_id=notification_id,
                request_id=request.request_id,
                command=request.command,
                expected_updated_at=request.expected_updated_at.isoformat(),
            )
        except NotificationPersistenceConflict as exc:
            raise NotificationConflictError(str(exc)) from exc
        except NotificationPersistenceNotFound as exc:
            raise NotificationNotFoundError("Notification is unavailable.") from exc
        except NotificationPersistenceOutcomeUnknown as exc:
            raise NotificationOutcomeUnknownError(
                "Notification action outcome could not be determined.",
            ) from exc
        except NotificationPersistenceError as exc:
            raise NotificationServiceUnavailableError(
                "Notification lifecycle persistence is unavailable.",
            ) from exc

    async def acknowledge_delivery(
        self,
        *,
        user_id: str,
        notification_id: UUID,
    ) -> NotificationDeliveryReceiptResponse:
        try:
            return await self._repository.acknowledge_delivery(
                user_id=user_id,
                notification_id=notification_id,
            )
        except NotificationPersistenceConflict as exc:
            raise NotificationConflictError(str(exc)) from exc
        except NotificationPersistenceNotFound as exc:
            raise NotificationNotFoundError("Notification is unavailable.") from exc
        except NotificationPersistenceOutcomeUnknown as exc:
            raise NotificationOutcomeUnknownError(
                "In-app delivery outcome could not be determined.",
            ) from exc
        except NotificationPersistenceError as exc:
            raise NotificationServiceUnavailableError(
                "In-app delivery persistence is unavailable.",
            ) from exc


@dataclass(frozen=True, slots=True)
class _NotificationCandidate:
    category: NotificationCategory
    generation_key: str
    title: str
    message: str
    notification_type: str
    priority: str
    action_url: str
    reason_code: str
    source_kind: str
    source_id: str
    source_generated_at: datetime


class NotificationGenerationService:
    """Creates bounded, privacy-safe stored items from deterministic facts."""

    def __init__(
        self,
        *,
        repository: NotificationRepository,
        weekly_review_reader: NotificationWeeklyReviewReader,
    ) -> None:
        self._repository = repository
        self._weekly_review_reader = weekly_review_reader

    async def generate_for_user(
        self,
        *,
        user_id: str,
        delivery_date: date,
        run_at: datetime,
    ) -> NotificationGenerationResult:
        if run_at.tzinfo is None or run_at.utcoffset() is None:
            raise NotificationServiceUnavailableError(
                "Notification run time must include a timezone.",
            )
        run_at = run_at.astimezone(UTC)
        try:
            context = await self._repository.load_generation_context(
                user_id=user_id,
                delivery_date=delivery_date,
            )
            timezone = ZoneInfo(context.timezone)
        except ZoneInfoNotFoundError as exc:
            raise NotificationServiceUnavailableError(
                "Notification profile timezone is invalid.",
            ) from exc
        except NotificationPersistenceError as exc:
            raise NotificationServiceUnavailableError(
                "Notification generation persistence is unavailable.",
            ) from exc

        if run_at.astimezone(timezone).date() != delivery_date:
            raise NotificationServiceUnavailableError(
                "Notification delivery date does not match the profile timezone.",
            )
        if not context.settings.in_app_delivery_enabled:
            return NotificationGenerationResult(
                status="not_consented",
                category=None,
                delivery_date=delivery_date,
                created_count=0,
                duplicate_count=0,
            )

        weekly_review: dict[str, Any] | None = None
        if (
            delivery_date.isoweekday() == 1
            and context.settings.categories.weekly_summary
        ):
            try:
                review_response = await self._weekly_review_reader.get_latest(
                    user_id=user_id,
                )
                if review_response.freshness == "current":
                    review = review_response.review
                    if review is None:
                        raise ValueError(
                            "Current weekly review response has no review.",
                        )
                    weekly_review = {
                        "id": review.id,
                        "period_key": review_response.period_key,
                        "week_end": review_response.ends_on.isoformat(),
                        "generated_at": review.generated_at.isoformat(),
                    }
            except Exception as exc:
                raise NotificationServiceUnavailableError(
                    "Weekly review freshness could not be verified.",
                ) from exc

        candidates = _generation_candidates(
            context=context,
            delivery_date=delivery_date,
            weekly_review=weekly_review,
        )
        if not candidates:
            return NotificationGenerationResult(
                status="no_candidate",
                category=None,
                delivery_date=delivery_date,
                created_count=0,
                duplicate_count=0,
            )

        created = 0
        duplicates = 0
        last_status = "no_candidate"
        last_category: NotificationCategory | None = None
        effective_category: NotificationCategory | None = None
        for candidate in candidates:
            notification_id = uuid5(
                NAMESPACE_URL,
                f"{user_id}:{candidate.generation_key}",
            )
            try:
                result = await self._repository.create_generated_notification(
                    user_id=user_id,
                    notification_id=notification_id,
                    generation_key=candidate.generation_key,
                    category=candidate.category,
                    delivery_date=delivery_date,
                    run_at=run_at,
                    timezone=context.timezone,
                    title=candidate.title,
                    message=candidate.message,
                    notification_type=candidate.notification_type,
                    priority=candidate.priority,
                    action_url=candidate.action_url,
                    reason_code=candidate.reason_code,
                    source_kind=candidate.source_kind,
                    source_id=candidate.source_id,
                    source_generated_at=candidate.source_generated_at,
                )
            except NotificationPersistenceConflict as exc:
                raise NotificationConflictError(str(exc)) from exc
            except NotificationPersistenceOutcomeUnknown as exc:
                raise NotificationOutcomeUnknownError(
                    "Notification generation outcome could not be determined.",
                ) from exc
            except NotificationPersistenceError as exc:
                raise NotificationServiceUnavailableError(
                    "Notification generation persistence is unavailable.",
                ) from exc
            last_status = result.status
            last_category = candidate.category
            if result.status == "created":
                created += 1
                effective_category = candidate.category
            elif result.status == "duplicate":
                duplicates += 1
                effective_category = candidate.category
            elif result.status in {
                "not_consented",
                "quiet_hours",
                "daily_limit",
            }:
                break

        aggregate_status = (
            "created"
            if created
            else "duplicate"
            if duplicates
            else last_status
        )
        return NotificationGenerationResult(
            status=aggregate_status,
            category=effective_category or last_category,
            delivery_date=delivery_date,
            created_count=created,
            duplicate_count=duplicates,
        )


def _generation_candidates(
    *,
    context: NotificationGenerationContext,
    delivery_date: date,
    weekly_review: dict[str, Any] | None,
) -> list[_NotificationCandidate]:
    candidates: list[_NotificationCandidate] = []
    daily_state = _valid_daily_state(
        context.daily_snapshot,
        delivery_date=delivery_date,
    )
    briefing = _valid_briefing(
        context.briefing,
        snapshot=context.daily_snapshot,
    )
    date_key = delivery_date.isoformat()

    if daily_state is not None and daily_state.get("mode") == "recover":
        if context.settings.categories.recovery_prompt:
            snapshot = context.daily_snapshot or {}
            source_id, generated_at = _source_identity(snapshot)
            candidates.append(
                _NotificationCandidate(
                    category="recovery_prompt",
                    generation_key=(
                        "notification-generation-v1:recovery_prompt:"
                        f"{date_key}"
                    ),
                    title="A gentler plan is ready",
                    message=(
                        "Open Today to review one manageable next step. "
                        "No private check-in details are included here."
                    ),
                    notification_type="coaching",
                    priority="medium",
                    action_url="/dashboard",
                    reason_code="current_recovery_mode",
                    source_kind="daily_state",
                    source_id=source_id,
                    source_generated_at=generated_at,
                ),
            )
    elif briefing is not None and context.settings.categories.focus_prompt:
        source_id, generated_at = _source_identity(briefing)
        candidates.append(
            _NotificationCandidate(
                category="focus_prompt",
                generation_key=f"notification-generation-v1:focus_prompt:{date_key}",
                title="Today's plan is ready",
                message="Open Today to review your next step.",
                notification_type="reminder",
                priority="medium",
                action_url="/dashboard",
                reason_code="current_daily_briefing",
                source_kind="daily_briefing",
                source_id=source_id,
                source_generated_at=generated_at,
            ),
        )

    if (
        delivery_date.isoweekday() == 1
        and context.settings.categories.weekly_summary
        and weekly_review is not None
    ):
        expected_week_end = delivery_date - timedelta(days=1)
        expected_period_key = _iso_period_key(expected_week_end)
        period_key = weekly_review.get("period_key")
        if (
            period_key == expected_period_key
            and weekly_review.get("week_end") == expected_week_end.isoformat()
        ):
            source_id, generated_at = _source_identity(weekly_review)
            candidates.append(
                _NotificationCandidate(
                    category="weekly_summary",
                    generation_key=(
                        "notification-generation-v1:weekly_summary:"
                        f"{period_key}"
                    ),
                    title="Your weekly review is ready",
                    message="Open Weekly Review to inspect the completed week.",
                    notification_type="summary",
                    priority="low",
                    action_url="/weekly-review",
                    reason_code="completed_weekly_review",
                    source_kind="weekly_review",
                    source_id=source_id,
                    source_generated_at=generated_at,
                ),
            )
    return candidates


def _iso_period_key(value: date) -> str:
    iso_year, iso_week, _ = value.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


def _valid_daily_state(
    snapshot: dict[str, Any] | None,
    *,
    delivery_date: date,
) -> dict[str, Any] | None:
    if snapshot is None:
        return None
    summary = snapshot.get("summary")
    if not isinstance(summary, dict):
        return None
    daily_state = summary.get("daily_state")
    if (
        not isinstance(daily_state, dict)
        or daily_state.get("contract_version") != "explainable-daily-state-v1"
        or daily_state.get("target_date") != delivery_date.isoformat()
        or daily_state.get("mode") not in {"push", "steady", "recover", "plan"}
    ):
        return None
    return daily_state


def _valid_briefing(
    briefing: dict[str, Any] | None,
    *,
    snapshot: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if briefing is None or snapshot is None:
        return None
    provenance = briefing.get("provenance")
    if not isinstance(provenance, dict):
        return None
    snapshot_id = snapshot.get("id")
    snapshot_generated_at = snapshot.get("generated_at")
    if (
        not isinstance(snapshot_id, str)
        or provenance.get("source_snapshot_id") != snapshot_id
        or not _same_aware_datetime(
            provenance.get("source_snapshot_generated_at"),
            snapshot_generated_at,
        )
    ):
        return None
    return briefing


def _source_identity(row: dict[str, Any]) -> tuple[str, datetime]:
    source_id = row.get("id")
    if not isinstance(source_id, str) or not source_id:
        raise NotificationServiceUnavailableError(
            "Notification source identity is invalid.",
        )
    generated_at = _parse_aware_datetime(row.get("generated_at"))
    return source_id, generated_at


def _same_aware_datetime(left: Any, right: Any) -> bool:
    try:
        return _parse_aware_datetime(left) == _parse_aware_datetime(right)
    except NotificationServiceUnavailableError:
        return False


def _parse_aware_datetime(value: Any) -> datetime:
    if not isinstance(value, str):
        raise NotificationServiceUnavailableError(
            "Notification source timestamp is invalid.",
        )
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise NotificationServiceUnavailableError(
            "Notification source timestamp is invalid.",
        ) from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise NotificationServiceUnavailableError(
            "Notification source timestamp is invalid.",
        )
    return parsed.astimezone(UTC)
