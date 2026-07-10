from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.intake import (
    IntakeCompleteRequest,
    IntakeCompleteResponse,
    IntakeSetupResponse,
)
from app.repositories.intake_repository import SupabaseIntakeRepository
from app.repositories.recommendation_repository import SupabaseRecommendationRepository
from app.repositories.user_context_repository import SupabaseUserContextRepository
from app.services.intake_service import IntakeRevisionConflict, IntakeService
from app.services.recommendation_engine import RecommendationEngine

router = APIRouter(prefix="/intake", tags=["intake"])


async def get_intake_service(request: Request) -> IntakeService:
    injected_service = getattr(request.app.state, "intake_service", None)
    if injected_service is not None:
        return injected_service
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Intake persistence is not configured.",
        ) from exc
    return IntakeService(
        repository=SupabaseIntakeRepository(client),
        recommendation_engine=RecommendationEngine(
            user_context_repository=SupabaseUserContextRepository(client),
            recommendation_repository=SupabaseRecommendationRepository(client),
        ),
    )


@router.get(
    "/setup",
    response_model=IntakeSetupResponse,
    response_model_exclude_none=True,
)
async def get_setup(
    principal: Principal = Depends(get_current_principal),
    service: IntakeService = Depends(get_intake_service),
) -> IntakeSetupResponse:
    return await service.get_setup(user_id=principal.user_id)


@router.post(
    "/complete",
    response_model=IntakeCompleteResponse,
    response_model_exclude_none=True,
)
async def complete_intake(
    request: IntakeCompleteRequest,
    principal: Principal = Depends(get_current_principal),
    service: IntakeService = Depends(get_intake_service),
) -> IntakeCompleteResponse:
    try:
        return await service.complete_intake(
            user_id=principal.user_id,
            request=request,
        )
    except IntakeRevisionConflict as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=exc.as_detail(),
        ) from exc
