from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import (
    get_today_overview_service,
    get_today_week_agenda_service,
)
from app.api.problems.today import (
    TODAY_OVERVIEW_ERRORS,
    TODAY_WEEK_AGENDA_ERRORS,
    today_overview_problem,
    today_week_agenda_problem,
)
from app.models.today_overview import TodayOverviewResponse, TodayOverviewV2Response
from app.models.today_week_agenda import TodayWeekAgendaResponse
from app.services.today_overview_service import TodayOverviewService
from app.services.today_week_agenda_service import TodayWeekAgendaService


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
    except TODAY_OVERVIEW_ERRORS as exc:
        raise today_overview_problem(exc) from exc


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
    except TODAY_OVERVIEW_ERRORS as exc:
        raise today_overview_problem(exc) from exc


@router.get(
    "/week-agenda",
    response_model=TodayWeekAgendaResponse,
    response_model_exclude_none=False,
)
async def get_today_week_agenda(
    principal: Principal = Depends(get_current_principal),
    service: TodayWeekAgendaService = Depends(get_today_week_agenda_service),
) -> TodayWeekAgendaResponse:
    try:
        return await service.get_week(user_id=principal.user_id)
    except TODAY_WEEK_AGENDA_ERRORS as exc:
        raise today_week_agenda_problem(exc) from exc
