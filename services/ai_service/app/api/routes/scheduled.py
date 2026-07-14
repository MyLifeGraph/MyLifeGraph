import secrets

from fastapi import APIRouter, Header, HTTPException, Request, status

from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.scheduled import ScheduledRefreshRequest, ScheduledRefreshResponse
from app.repositories.briefing_repository import SupabaseBriefingRepository
from app.repositories.notification_repository import SupabaseNotificationRepository
from app.repositories.recommendation_repository import SupabaseRecommendationRepository
from app.repositories.scheduled_refresh_repository import (
    SupabaseScheduledRefreshRepository,
)
from app.repositories.snapshot_repository import SupabaseSnapshotRepository
from app.repositories.user_context_repository import SupabaseUserContextRepository
from app.repositories.weekly_review_repository import SupabaseWeeklyReviewRepository
from app.services.briefing_service import BriefingService
from app.services.notification_service import NotificationGenerationService
from app.services.recommendation_engine import RecommendationEngine
from app.services.scheduled_refresh import ScheduledRefreshService
from app.services.snapshot_aggregator import SnapshotAggregator
from app.services.weekly_review_service import WeeklyReviewService

router = APIRouter(prefix="/scheduled", tags=["scheduled"])


def _verify_scheduled_refresh_token(token: str | None) -> None:
    expected = settings.scheduled_refresh_token.strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Scheduled refresh token is not configured.",
        )
    if not secrets.compare_digest(token or "", expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing scheduled refresh token.",
        )


async def get_scheduled_refresh_service(request: Request) -> ScheduledRefreshService:
    injected_service = getattr(request.app.state, "scheduled_refresh_service", None)
    if injected_service is not None:
        return injected_service
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Scheduled refresh persistence is not configured.",
        ) from exc

    snapshot_aggregator = SnapshotAggregator(
        repository=SupabaseSnapshotRepository(client),
    )
    return ScheduledRefreshService(
        repository=SupabaseScheduledRefreshRepository(client),
        briefing_service=BriefingService(
            repository=SupabaseBriefingRepository(client),
            snapshot_aggregator=snapshot_aggregator,
        ),
        recommendation_engine=RecommendationEngine(
            user_context_repository=SupabaseUserContextRepository(client),
            recommendation_repository=SupabaseRecommendationRepository(client),
        ),
        notification_generation_service=NotificationGenerationService(
            repository=SupabaseNotificationRepository(client),
            weekly_review_reader=WeeklyReviewService(
                repository=SupabaseWeeklyReviewRepository(client),
                snapshot_aggregator=snapshot_aggregator,
            ),
        ),
    )


@router.post("/daily-refresh", response_model=ScheduledRefreshResponse)
async def refresh_daily(
    request_body: ScheduledRefreshRequest,
    request: Request,
    scheduled_refresh_token: str | None = Header(
        default=None,
        alias="X-Scheduled-Refresh-Token",
    ),
) -> ScheduledRefreshResponse:
    _verify_scheduled_refresh_token(scheduled_refresh_token)
    service = await get_scheduled_refresh_service(request)
    return await service.refresh_daily(request_body)
