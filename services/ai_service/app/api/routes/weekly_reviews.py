from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_weekly_review_service
from app.api.problems.weekly_reviews import (
    WEEKLY_REVIEW_PERIOD_ERRORS,
    weekly_review_problem,
)
from app.models.weekly_reviews import (
    WeeklyReviewGenerateRequest,
    WeeklyReviewGenerateResponse,
    WeeklyReviewReadResponse,
)
from app.services.weekly_review_service import WeeklyReviewService

router = APIRouter(prefix="/weekly-reviews", tags=["weekly-reviews"])


@router.get("/latest", response_model=WeeklyReviewReadResponse)
async def get_latest_weekly_review(
    principal: Principal = Depends(get_current_principal),
    service: WeeklyReviewService = Depends(get_weekly_review_service),
) -> WeeklyReviewReadResponse:
    return await service.get_latest(user_id=principal.user_id)


@router.get("/{period_key}", response_model=WeeklyReviewReadResponse)
async def get_weekly_review(
    period_key: str,
    principal: Principal = Depends(get_current_principal),
    service: WeeklyReviewService = Depends(get_weekly_review_service),
) -> WeeklyReviewReadResponse:
    try:
        return await service.get_period(
            user_id=principal.user_id,
            period_key=period_key,
        )
    except WEEKLY_REVIEW_PERIOD_ERRORS as exc:
        raise weekly_review_problem(exc) from exc


@router.post("/generate", response_model=WeeklyReviewGenerateResponse)
async def generate_weekly_review(
    request: WeeklyReviewGenerateRequest,
    principal: Principal = Depends(get_current_principal),
    service: WeeklyReviewService = Depends(get_weekly_review_service),
) -> WeeklyReviewGenerateResponse:
    try:
        return await service.generate(user_id=principal.user_id, request=request)
    except WEEKLY_REVIEW_PERIOD_ERRORS as exc:
        raise weekly_review_problem(exc) from exc
