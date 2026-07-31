from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_intake_service
from app.models.intake import (
    IntakeCompleteRequest,
    IntakeCompleteResponse,
    IntakeSetupResponse,
)
from app.services.intake_service import IntakeRevisionConflict, IntakeService

router = APIRouter(prefix="/intake", tags=["intake"])


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
