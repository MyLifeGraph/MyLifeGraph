from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.recommendations import (
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationListResponse,
)
from app.repositories.recommendation_repository import SupabaseRecommendationRepository
from app.repositories.user_context_repository import SupabaseUserContextRepository
from app.services.recommendation_engine import RecommendationEngine

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


async def get_recommendation_engine(request: Request) -> RecommendationEngine:
    injected_engine = getattr(request.app.state, "recommendation_engine", None)
    if injected_engine is not None:
        return injected_engine
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Recommendation persistence is not configured.",
        ) from exc
    return RecommendationEngine(
        user_context_repository=SupabaseUserContextRepository(client),
        recommendation_repository=SupabaseRecommendationRepository(client),
    )


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
