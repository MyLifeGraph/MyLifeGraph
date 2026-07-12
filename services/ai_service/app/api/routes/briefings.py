from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.briefings import (
    BriefingGenerateRequest,
    BriefingGenerateResponse,
    BriefingReadResponse,
)
from app.repositories.briefing_repository import SupabaseBriefingRepository
from app.repositories.snapshot_repository import SupabaseSnapshotRepository
from app.services.briefing_service import BriefingService
from app.services.snapshot_aggregator import SnapshotAggregator

router = APIRouter(prefix="/briefings", tags=["briefings"])


async def get_briefing_service(request: Request) -> BriefingService:
    injected_service = getattr(request.app.state, "briefing_service", None)
    if injected_service is not None:
        return injected_service
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Briefing persistence is not configured.",
        ) from exc
    return BriefingService(
        repository=SupabaseBriefingRepository(client),
        snapshot_aggregator=SnapshotAggregator(
            repository=SupabaseSnapshotRepository(client),
        ),
    )


@router.get("/today", response_model=BriefingReadResponse)
async def get_today_briefing(
    principal: Principal = Depends(get_current_principal),
    service: BriefingService = Depends(get_briefing_service),
) -> BriefingReadResponse:
    return await service.get_today(user_id=principal.user_id)


@router.post("/generate", response_model=BriefingGenerateResponse)
async def generate_today_briefing(
    request: BriefingGenerateRequest,
    principal: Principal = Depends(get_current_principal),
    service: BriefingService = Depends(get_briefing_service),
) -> BriefingGenerateResponse:
    return await service.generate_today(
        user_id=principal.user_id,
        request=request,
    )
