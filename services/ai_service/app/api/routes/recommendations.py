from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.models.recommendations import (
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationListResponse,
)
from app.services.recommendation_engine import RecommendationEngine

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


async def get_recommendation_engine() -> RecommendationEngine:
    return RecommendationEngine()


@router.get("", response_model=RecommendationListResponse)
async def list_recommendations(
    principal: Principal = Depends(get_current_principal),
    engine: RecommendationEngine = Depends(get_recommendation_engine),
) -> RecommendationListResponse:
    return await engine.list_recommendations(user_id=principal.user_id)


@router.post("/generate", response_model=RecommendationGenerateResponse)
async def generate_recommendations(
    request: RecommendationGenerateRequest,
    principal: Principal = Depends(get_current_principal),
    engine: RecommendationEngine = Depends(get_recommendation_engine),
) -> RecommendationGenerateResponse:
    return await engine.generate_recommendations(
        user_id=principal.user_id,
        request=request,
    )
