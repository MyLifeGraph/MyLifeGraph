from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.today_overview import TodayOverviewResponse, TodayOverviewV2Response
from app.repositories.deadline_plan_repository import SupabaseDeadlinePlanRepository
from app.repositories.planner_repository import SupabasePlannerRepository
from app.repositories.today_overview_repository import SupabaseTodayOverviewRepository
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.planner_service import PlannerService
from app.services.today_overview_service import (
    TodayOverviewService,
    TodayOverviewUnavailableError,
)


router = APIRouter(prefix="/today", tags=["today"])


async def get_today_overview_service(request: Request) -> TodayOverviewService:
    injected = getattr(request.app.state, "today_overview_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Today persistence is not configured.",
        ) from exc
    deadline_service = DeadlinePlanService(
        repository=SupabaseDeadlinePlanRepository(client),
    )
    return TodayOverviewService(
        repository=SupabaseTodayOverviewRepository(client),
        deadline_plan_service=deadline_service,
        planner_service=PlannerService(
            repository=SupabasePlannerRepository(client),
            deadline_plans=deadline_service,
        ),
    )


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
