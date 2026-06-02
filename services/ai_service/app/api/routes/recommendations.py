from fastapi import APIRouter, Depends

from app.models.recommendations import RecommendationRequest, RecommendationResponse
from app.services.recommendation_engine import RecommendationEngine

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


def get_recommendation_engine() -> RecommendationEngine:
    return RecommendationEngine()


@router.post("/preview", response_model=list[RecommendationResponse])
async def preview_recommendations(
    request: RecommendationRequest | None = None,
    engine: RecommendationEngine = Depends(get_recommendation_engine),
) -> list[RecommendationResponse]:
    return await engine.preview(request or RecommendationRequest())
