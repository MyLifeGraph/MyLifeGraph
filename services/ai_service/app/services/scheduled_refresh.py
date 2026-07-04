from collections.abc import Callable
from datetime import date

from app.models.recommendations import RecommendationGenerateRequest
from app.models.scheduled import (
    ScheduledRefreshRequest,
    ScheduledRefreshResponse,
    ScheduledUserRefreshResult,
)
from app.models.snapshots import SnapshotGenerateRequest
from app.repositories.scheduled_refresh_repository import ScheduledRefreshRepository
from app.services.recommendation_engine import RecommendationEngine
from app.services.snapshot_aggregator import SnapshotAggregator


class ScheduledRefreshService:
    """Runs bounded deterministic refreshes for scheduler-triggered workflows."""

    def __init__(
        self,
        *,
        repository: ScheduledRefreshRepository,
        snapshot_aggregator: SnapshotAggregator,
        recommendation_engine: RecommendationEngine | None = None,
        today_provider: Callable[[], date] | None = None,
    ) -> None:
        self._repository = repository
        self._snapshot_aggregator = snapshot_aggregator
        self._recommendation_engine = recommendation_engine
        self._today_provider = today_provider or date.today

    async def refresh_daily(
        self,
        request: ScheduledRefreshRequest,
    ) -> ScheduledRefreshResponse:
        target_date = request.target_date or self._today_provider()
        user_ids = await self._repository.list_daily_refresh_user_ids(
            limit=request.limit,
            target_date=target_date,
        )
        results = [
            await self._refresh_user(
                user_id=user_id,
                request=request,
                target_date=target_date,
            )
            for user_id in user_ids
        ]
        succeeded = sum(1 for result in results if result.status == "succeeded")
        failed = len(results) - succeeded
        return ScheduledRefreshResponse(
            target_date=target_date,
            processed=len(results),
            succeeded=succeeded,
            failed=failed,
            results=results,
        )

    async def _refresh_user(
        self,
        *,
        user_id: str,
        request: ScheduledRefreshRequest,
        target_date: date,
    ) -> ScheduledUserRefreshResult:
        try:
            snapshot = await self._snapshot_aggregator.generate_snapshot(
                user_id=user_id,
                request=SnapshotGenerateRequest(
                    scope="daily",
                    target_date=target_date,
                    window_days=request.window_days,
                ),
            )
            recommendation_count = None
            if request.include_recommendations:
                if self._recommendation_engine is None:
                    raise RuntimeError("Recommendation engine is not configured.")
                recommendations = (
                    await self._recommendation_engine.generate_recommendations(
                        user_id=user_id,
                        request=RecommendationGenerateRequest(
                            window_days=request.recommendation_window_days,
                            force=False,
                            allow_llm_wording=False,
                        ),
                    )
                )
                recommendation_count = len(recommendations.items)

            return ScheduledUserRefreshResult(
                user_id=user_id,
                status="succeeded",
                snapshot_id=snapshot.snapshot_id,
                period_key=snapshot.period_key,
                recommendation_count=recommendation_count,
            )
        except Exception as exc:
            return ScheduledUserRefreshResult(
                user_id=user_id,
                status="failed",
                error=exc.__class__.__name__,
            )
