from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import (
    get_personal_patterns_service,
    get_sleep_recommendation_service,
)
from app.api.problems.insights import (
    PERSONAL_PATTERNS_ERRORS,
    personal_patterns_problem,
    SLEEP_RECOMMENDATION_ERRORS,
    sleep_recommendation_problem,
)
from app.models.personal_patterns import PersonalPatternsResponse
from app.models.sleep_recommendation import SleepRecommendationResponse
from app.services.personal_patterns_service import (
    PersonalPatternsService,
)
from app.services.sleep_recommendation_service import SleepRecommendationService


router = APIRouter(prefix="/insights", tags=["insights"])


@router.get(
    "/personal-patterns",
    response_model=PersonalPatternsResponse,
)
async def get_personal_patterns(
    principal: Principal = Depends(get_current_principal),
    service: PersonalPatternsService = Depends(get_personal_patterns_service),
) -> PersonalPatternsResponse:
    try:
        return await service.get_patterns(user_id=principal.user_id)
    except PERSONAL_PATTERNS_ERRORS as exc:
        raise personal_patterns_problem(exc) from exc


@router.get(
    "/sleep-recommendation",
    response_model=SleepRecommendationResponse,
)
async def get_sleep_recommendation(
    principal: Principal = Depends(get_current_principal),
    service: SleepRecommendationService = Depends(
        get_sleep_recommendation_service,
    ),
) -> SleepRecommendationResponse:
    try:
        return await service.get_recommendation(user_id=principal.user_id)
    except SLEEP_RECOMMENDATION_ERRORS as exc:
        raise sleep_recommendation_problem(exc) from exc
