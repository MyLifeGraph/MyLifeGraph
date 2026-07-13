import asyncio

from fastapi import HTTPException, Request, status

from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.providers.disabled import DisabledCoachProvider
from app.providers.fake import FakeCoachProvider
from app.providers.local_codex import LocalCodexCoachProvider
from app.repositories.briefing_repository import SupabaseBriefingRepository
from app.repositories.coach_context_repository import SupabaseCoachContextRepository
from app.repositories.coach_repository import SupabaseCoachRepository
from app.repositories.snapshot_repository import SupabaseSnapshotRepository
from app.repositories.weekly_review_repository import SupabaseWeeklyReviewRepository
from app.services.briefing_service import BriefingService
from app.services.coach_context import CoachContextService
from app.services.coach_service import CoachService
from app.services.snapshot_aggregator import SnapshotAggregator
from app.services.weekly_review_service import WeeklyReviewService


_GLOBAL_COACH_SEMAPHORE = asyncio.Semaphore(
    settings.local_codex_global_concurrency,
)
_GLOBAL_LOCAL_CODEX_PROVIDER = LocalCodexCoachProvider(settings)


async def get_coach_service(request: Request) -> CoachService:
    injected = getattr(request.app.state, "coach_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "provider_unavailable",
                "message": "Coach persistence is not configured.",
                "retryable": False,
            },
        ) from exc

    context_repository = SupabaseCoachContextRepository(client)
    snapshot_aggregator = SnapshotAggregator(
        repository=SupabaseSnapshotRepository(client),
    )
    context_service = CoachContextService(
        repository=context_repository,
        briefing_reader=BriefingService(
            repository=SupabaseBriefingRepository(client),
            snapshot_aggregator=snapshot_aggregator,
        ),
        weekly_review_reader=WeeklyReviewService(
            repository=SupabaseWeeklyReviewRepository(client),
            snapshot_aggregator=snapshot_aggregator,
        ),
    )
    if settings.coach_provider == "local_codex_oauth":
        # Reuse the short-lived CLI capability cache across request-scoped
        # services; concurrent reads then share one four-command preflight.
        provider = _GLOBAL_LOCAL_CODEX_PROVIDER
    elif settings.coach_provider == "fake":
        provider = FakeCoachProvider(settings)
    else:
        provider = DisabledCoachProvider()
    return CoachService(
        settings=settings,
        repository=SupabaseCoachRepository(client),
        context_repository=context_repository,
        context_service=context_service,
        provider=provider,
        global_semaphore=_GLOBAL_COACH_SEMAPHORE,
    )
