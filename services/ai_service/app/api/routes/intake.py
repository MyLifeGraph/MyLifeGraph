from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_intake_service
from app.api.problems.intake import INTAKE_COMPLETE_ERRORS, intake_problem
from app.models.intake import (
    IntakeCompleteRequest,
    IntakeCompleteResponse,
    IntakeSetupResponse,
)
from app.services.intake_service import IntakeService

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
    except INTAKE_COMPLETE_ERRORS as exc:
        raise intake_problem(exc) from exc
