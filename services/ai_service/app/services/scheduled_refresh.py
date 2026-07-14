import asyncio
import logging
from collections.abc import Callable
from datetime import UTC, datetime

from app.models.recommendations import RecommendationGenerateRequest
from app.models.scheduled import (
    ScheduledRefreshRequest,
    ScheduledRefreshResponse,
    ScheduledUserRefreshResult,
)
from app.repositories.scheduled_refresh_repository import (
    ScheduledRefreshRepository,
    ScheduledRefreshTarget,
)
from app.services.briefing_service import BriefingPreparationError, BriefingService
from app.services.notification_service import NotificationGenerationService
from app.services.recommendation_engine import RecommendationEngine

_MAX_CONCURRENT_USERS = 5
logger = logging.getLogger(__name__)


class ScheduledRefreshService:
    """Runs bounded deterministic preparation for scheduler-triggered workflows."""

    def __init__(
        self,
        *,
        repository: ScheduledRefreshRepository,
        briefing_service: BriefingService,
        recommendation_engine: RecommendationEngine | None = None,
        notification_generation_service: NotificationGenerationService | None = None,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._briefing_service = briefing_service
        self._recommendation_engine = recommendation_engine
        self._notification_generation_service = notification_generation_service
        self._now_provider = now_provider or _utc_now

    async def refresh_daily(
        self,
        request: ScheduledRefreshRequest,
    ) -> ScheduledRefreshResponse:
        run_at = self._now_provider()
        if run_at.tzinfo is None:
            raise ValueError("Scheduled run time must include a timezone.")
        run_at = run_at.astimezone(UTC)
        targets = await self._repository.list_daily_refresh_targets(
            limit=request.limit,
            run_at=run_at,
            target_date=request.target_date,
            profile_ids=[str(profile_id) for profile_id in request.profile_ids],
            include_current=(
                request.include_recommendations or request.include_notifications
            ),
            current_selection_reason=(
                "notification_delivery"
                if request.include_notifications
                and not request.include_recommendations
                else "recommendation_refresh"
            ),
        )
        semaphore = asyncio.Semaphore(_MAX_CONCURRENT_USERS)

        async def refresh_target(
            target: ScheduledRefreshTarget,
        ) -> ScheduledUserRefreshResult:
            async with semaphore:
                return await self._refresh_user(
                    target=target,
                    request=request,
                    run_at=run_at,
                )

        results = await asyncio.gather(*(refresh_target(target) for target in targets))
        succeeded = sum(1 for result in results if result.status == "succeeded")
        failed = len(results) - succeeded
        logger.info(
            "Scheduled daily preparation completed: "
            "processed=%s succeeded=%s failed=%s",
            len(results),
            succeeded,
            failed,
        )
        return ScheduledRefreshResponse(
            run_at=run_at,
            target_date=request.target_date,
            processed=len(results),
            succeeded=succeeded,
            failed=failed,
            results=results,
        )

    async def _refresh_user(
        self,
        *,
        target: ScheduledRefreshTarget,
        request: ScheduledRefreshRequest,
        run_at: datetime,
    ) -> ScheduledUserRefreshResult:
        if target.briefing_date is None:
            logger.warning(
                "Scheduled daily preparation skipped invalid profile date: "
                "user_id=%s error=%s",
                target.user_id,
                target.error,
            )
            return ScheduledUserRefreshResult(
                user_id=target.user_id,
                status="failed",
                selection_reason=target.selection_reason,
                failed_stage="profile_date",
                error=target.error or "ValueError",
            )

        failed_stage = "briefing"
        prepared = None
        briefing = None
        try:
            prepared = await self._briefing_service.prepare_for_date(
                user_id=target.user_id,
                briefing_date=target.briefing_date,
                window_days=request.window_days,
            )
            briefing = prepared.response.briefing
            if briefing is None:
                raise RuntimeError("Briefing preparation returned no briefing.")

            recommendation_count = None
            if request.include_recommendations:
                failed_stage = "recommendations"
                if self._recommendation_engine is None:
                    raise RuntimeError("Recommendation engine is not configured.")
                recommendations = (
                    await self._recommendation_engine.generate_recommendations(
                        user_id=target.user_id,
                        request=RecommendationGenerateRequest(
                            window_days=request.recommendation_window_days,
                            force=False,
                            allow_llm_wording=False,
                        ),
                    )
                )
                recommendation_count = len(recommendations.items)

            notification_result = None
            if request.include_notifications:
                failed_stage = "notifications"
                if self._notification_generation_service is None:
                    raise RuntimeError(
                        "Notification generation service is not configured.",
                    )
                notification_result = (
                    await self._notification_generation_service.generate_for_user(
                        user_id=target.user_id,
                        delivery_date=target.briefing_date,
                        run_at=run_at,
                    )
                )

            return ScheduledUserRefreshResult(
                user_id=target.user_id,
                status="succeeded",
                briefing_date=target.briefing_date,
                selection_reason=target.selection_reason,
                snapshot_id=briefing.provenance.source_snapshot_id,
                period_key=target.briefing_date.isoformat(),
                snapshot_status=prepared.snapshot_status,
                briefing_id=briefing.id,
                briefing_status=prepared.briefing_status,
                recommendation_count=recommendation_count,
                notification_status=(
                    notification_result.status
                    if notification_result is not None
                    else None
                ),
                notification_created_count=(
                    notification_result.created_count
                    if notification_result is not None
                    else None
                ),
                notification_duplicate_count=(
                    notification_result.duplicate_count
                    if notification_result is not None
                    else None
                ),
            )
        except BriefingPreparationError as exc:
            logger.warning(
                "Scheduled daily preparation failed: user_id=%s stage=%s error=%s",
                target.user_id,
                exc.stage,
                exc.error_type,
            )
            return ScheduledUserRefreshResult(
                user_id=target.user_id,
                status="failed",
                briefing_date=target.briefing_date,
                selection_reason=target.selection_reason,
                snapshot_id=exc.snapshot_id,
                period_key=(
                    target.briefing_date.isoformat()
                    if exc.snapshot_status is not None
                    else None
                ),
                snapshot_status=exc.snapshot_status,
                failed_stage=exc.stage,
                error=exc.error_type,
            )
        except Exception as exc:
            logger.warning(
                "Scheduled daily preparation failed: user_id=%s stage=%s error=%s",
                target.user_id,
                failed_stage,
                exc.__class__.__name__,
            )
            return ScheduledUserRefreshResult(
                user_id=target.user_id,
                status="failed",
                briefing_date=target.briefing_date,
                selection_reason=target.selection_reason,
                snapshot_id=(
                    briefing.provenance.source_snapshot_id
                    if briefing is not None
                    else None
                ),
                period_key=(
                    target.briefing_date.isoformat()
                    if prepared is not None
                    else None
                ),
                snapshot_status=(
                    prepared.snapshot_status if prepared is not None else None
                ),
                briefing_id=briefing.id if briefing is not None else None,
                briefing_status=(
                    prepared.briefing_status if prepared is not None else None
                ),
                failed_stage=failed_stage,
                error=exc.__class__.__name__,
            )


def _utc_now() -> datetime:
    return datetime.now(UTC)
