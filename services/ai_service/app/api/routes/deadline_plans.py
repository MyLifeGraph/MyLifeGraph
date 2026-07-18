from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.deadline_plans import (
    DeadlinePlanMutationRequest,
    DeadlinePlanProposalRequest,
    DeadlinePlanResponse,
    DeadlinePlansResponse,
)
from app.repositories.deadline_plan_repository import SupabaseDeadlinePlanRepository
from app.services.deadline_plan_service import (
    DeadlinePlanConflictError,
    DeadlinePlanNotFoundError,
    DeadlinePlanService,
    DeadlinePlanValidationError,
)


router = APIRouter(prefix="/deadline-plans", tags=["deadline-plans"])


async def get_deadline_plan_service(request: Request) -> DeadlinePlanService:
    injected = getattr(request.app.state, "deadline_plan_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Deadline plan persistence is not configured.",
        ) from exc
    return DeadlinePlanService(repository=SupabaseDeadlinePlanRepository(client))


@router.get(
    "",
    response_model=DeadlinePlansResponse,
    response_model_exclude_none=True,
)
async def list_deadline_plans(
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> DeadlinePlansResponse:
    return await service.list_plans(user_id=principal.user_id)


@router.get(
    "/{plan_id}",
    response_model=DeadlinePlanResponse,
    response_model_exclude_none=True,
)
async def get_deadline_plan(
    plan_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> DeadlinePlanResponse:
    try:
        return await service.get_plan(user_id=principal.user_id, plan_id=plan_id)
    except DeadlinePlanNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc


@router.post(
    "/proposals",
    response_model=DeadlinePlanResponse,
    response_model_exclude_none=True,
)
async def propose_deadline_plan(
    request: DeadlinePlanProposalRequest,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> DeadlinePlanResponse:
    try:
        return await service.propose(user_id=principal.user_id, request=request)
    except DeadlinePlanNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except DeadlinePlanConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except DeadlinePlanValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc


@router.post(
    "/{plan_id}/confirm",
    response_model=DeadlinePlanResponse,
    response_model_exclude_none=True,
)
async def confirm_deadline_plan(
    plan_id: UUID,
    request: DeadlinePlanMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> DeadlinePlanResponse:
    return await _mutate(
        service.confirm,
        user_id=principal.user_id,
        plan_id=plan_id,
        request=request,
    )


@router.post(
    "/{plan_id}/complete",
    response_model=DeadlinePlanResponse,
    response_model_exclude_none=True,
)
async def complete_deadline_plan(
    plan_id: UUID,
    request: DeadlinePlanMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> DeadlinePlanResponse:
    return await _mutate(
        service.complete,
        user_id=principal.user_id,
        plan_id=plan_id,
        request=request,
    )


@router.post(
    "/{plan_id}/cancel",
    response_model=DeadlinePlanResponse,
    response_model_exclude_none=True,
)
async def cancel_deadline_plan(
    plan_id: UUID,
    request: DeadlinePlanMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> DeadlinePlanResponse:
    return await _mutate(
        service.cancel,
        user_id=principal.user_id,
        plan_id=plan_id,
        request=request,
    )


async def _mutate(method, *, user_id: str, plan_id: UUID, request):
    try:
        return await method(user_id=user_id, plan_id=plan_id, request=request)
    except DeadlinePlanNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except DeadlinePlanConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
