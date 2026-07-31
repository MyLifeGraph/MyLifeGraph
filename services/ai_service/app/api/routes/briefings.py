from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_briefing_service
from app.models.briefings import (
    BriefingGenerateRequest,
    BriefingGenerateResponse,
    BriefingReadResponse,
)
from app.services.briefing_service import BriefingService

router = APIRouter(prefix="/briefings", tags=["briefings"])


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
