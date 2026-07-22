from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.planner import (
    PlannerActionMutationRequest,
    PlannerActionPlanResponse,
    PlannerActionProposalRequest,
    PlannerCommitmentArchiveRequest,
    PlannerCommitmentCreateRequest,
    PlannerCommitmentResponse,
    PlannerCommitmentUpdateRequest,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
    PlannerPreferencesUpdateRequest,
)
from app.repositories.deadline_plan_repository import SupabaseDeadlinePlanRepository
from app.repositories.planner_repository import SupabasePlannerRepository
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.planner_service import (
    PlannerConflictError,
    PlannerNotFoundError,
    PlannerService,
    PlannerValidationError,
)


router = APIRouter(prefix="/planner", tags=["planner"])


async def get_planner_service(request: Request) -> PlannerService:
    injected = getattr(request.app.state, "planner_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Planner persistence is not configured.",
        ) from exc
    return PlannerService(
        repository=SupabasePlannerRepository(client),
        deadline_plans=DeadlinePlanService(
            repository=SupabaseDeadlinePlanRepository(client),
        ),
    )


@router.get(
    "/overview",
    response_model=PlannerOverviewResponse,
    response_model_exclude_none=False,
)
async def get_planner_overview(
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerOverviewResponse:
    try:
        return await service.get_overview(user_id=principal.user_id)
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.get(
    "/preferences",
    response_model=PlannerPreferencesResponse,
    response_model_exclude_none=False,
)
async def get_planner_preferences(
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerPreferencesResponse:
    try:
        return await service.get_preferences(user_id=principal.user_id)
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.patch(
    "/preferences",
    response_model=PlannerPreferencesResponse,
    response_model_exclude_none=False,
)
async def update_planner_preferences(
    body: PlannerPreferencesUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerPreferencesResponse:
    try:
        return await service.update_preferences(
            user_id=principal.user_id,
            request=body,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.get(
    "/action-plans/{plan_id}",
    response_model=PlannerActionPlanResponse,
    response_model_exclude_none=False,
)
async def get_planner_action_plan(
    plan_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerActionPlanResponse:
    try:
        return await service.get_action_plan(
            user_id=principal.user_id,
            plan_id=plan_id,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.post(
    "/action-plans/proposals",
    response_model=PlannerActionPlanResponse,
    response_model_exclude_none=False,
)
async def propose_planner_action_plan(
    body: PlannerActionProposalRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerActionPlanResponse:
    try:
        return await service.propose(user_id=principal.user_id, request=body)
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.post(
    "/action-plans/{plan_id}/confirm",
    response_model=PlannerActionPlanResponse,
    response_model_exclude_none=False,
)
async def confirm_planner_action_plan(
    plan_id: UUID,
    body: PlannerActionMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerActionPlanResponse:
    try:
        return await service.confirm(
            user_id=principal.user_id,
            plan_id=plan_id,
            request=body,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.post(
    "/action-plans/{plan_id}/cancel",
    response_model=PlannerActionPlanResponse,
    response_model_exclude_none=False,
)
async def cancel_planner_action_plan(
    plan_id: UUID,
    body: PlannerActionMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerActionPlanResponse:
    try:
        return await service.cancel(
            user_id=principal.user_id,
            plan_id=plan_id,
            request=body,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.post(
    "/commitments",
    response_model=PlannerCommitmentResponse,
    response_model_exclude_none=False,
)
async def create_planner_commitment(
    body: PlannerCommitmentCreateRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerCommitmentResponse:
    try:
        return await service.create_commitment(
            user_id=principal.user_id,
            request=body,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.patch(
    "/commitments/{commitment_id}",
    response_model=PlannerCommitmentResponse,
    response_model_exclude_none=False,
)
async def update_planner_commitment(
    commitment_id: UUID,
    body: PlannerCommitmentUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerCommitmentResponse:
    try:
        return await service.update_commitment(
            user_id=principal.user_id,
            commitment_id=commitment_id,
            request=body,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


@router.post(
    "/commitments/{commitment_id}/archive",
    response_model=PlannerCommitmentResponse,
    response_model_exclude_none=False,
)
async def archive_planner_commitment(
    commitment_id: UUID,
    body: PlannerCommitmentArchiveRequest,
    principal: Principal = Depends(get_current_principal),
    service: PlannerService = Depends(get_planner_service),
) -> PlannerCommitmentResponse:
    try:
        return await service.archive_commitment(
            user_id=principal.user_id,
            commitment_id=commitment_id,
            request=body,
        )
    except (PlannerNotFoundError, PlannerConflictError, PlannerValidationError) as exc:
        _raise_http(exc)


def _raise_http(exc: Exception) -> None:
    if isinstance(exc, PlannerNotFoundError):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if isinstance(exc, PlannerValidationError):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        )
    raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
