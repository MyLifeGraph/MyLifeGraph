from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_today_overview_service
from app.models.today_overview import TodayOverviewResponse, TodayOverviewV2Response
from app.services.today_overview_service import (
    TodayOverviewService,
    TodayOverviewUnavailableError,
)


router = APIRouter(prefix="/today", tags=["today"])


@router.get(
    "/overview",
    response_model=TodayOverviewResponse,
    response_model_exclude_none=False,
)
async def get_today_overview(
    principal: Principal = Depends(get_current_principal),
    service: TodayOverviewService = Depends(get_today_overview_service),
) -> TodayOverviewResponse:
    try:
        return await service.get_overview(user_id=principal.user_id)
    except TodayOverviewUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get(
    "/overview-v2",
    response_model=TodayOverviewV2Response,
    response_model_exclude_none=False,
)
async def get_today_overview_v2(
    principal: Principal = Depends(get_current_principal),
    service: TodayOverviewService = Depends(get_today_overview_service),
) -> TodayOverviewV2Response:
    try:
        return await service.get_overview_v2(user_id=principal.user_id)
    except TodayOverviewUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
