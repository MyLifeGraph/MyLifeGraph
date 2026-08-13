from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import (
    get_assignment_series_service,
    get_deadline_plan_service,
)
from app.api.problems.deadline_plans import (
    DEADLINE_PLAN_DETAIL_ERRORS,
    DEADLINE_PLAN_GET_ERRORS,
    DEADLINE_PLAN_MUTATION_ERRORS,
    DEADLINE_PLAN_READ_ERRORS,
    deadline_plan_problem,
)
from app.models.deadline_plans import (
    DeadlinePlanMutationRequest,
    DeadlinePlanProposalRequest,
    DeadlinePlanResponse,
    DeadlinePlansResponse,
    ExamWeekOutlookResponse,
    PreparationWorkloadDetailResponse,
    PreparationWorkloadResponse,
)
from app.models.exam_plan_health import (
    ExamPlanHealthPreviewRequest,
    ExamPlanHealthPreviewResponse,
    ExamPlanHealthResponse,
)
from app.models.assignment_series import (
    AssignmentSeriesListResponse,
    AssignmentSeriesMutationRequest,
    AssignmentSeriesProposalRequest,
    AssignmentSeriesResponse,
)
from app.services.assignment_series_service import AssignmentSeriesService
from app.services.deadline_plan_service import (
    DeadlinePlanService,
)

router = APIRouter(prefix="/deadline-plans", tags=["deadline-plans"])


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
    "/exam-week-outlook",
    response_model=ExamWeekOutlookResponse,
    response_model_exclude_none=False,
)
async def get_exam_week_outlook(
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> ExamWeekOutlookResponse:
    try:
        return await service.get_exam_week_outlook(user_id=principal.user_id)
    except DEADLINE_PLAN_READ_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.get(
    "/exam-plan-health",
    response_model=ExamPlanHealthResponse,
    response_model_exclude_none=False,
)
async def get_exam_plan_health(
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> ExamPlanHealthResponse:
    try:
        return await service.get_exam_plan_health(user_id=principal.user_id)
    except DEADLINE_PLAN_READ_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.post(
    "/exam-plan-health/preview",
    response_model=ExamPlanHealthPreviewResponse,
    response_model_exclude_none=False,
)
async def preview_exam_plan_health(
    request: ExamPlanHealthPreviewRequest,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> ExamPlanHealthPreviewResponse:
    try:
        return await service.preview_exam_plan_health(
            user_id=principal.user_id,
            request=request,
        )
    except DEADLINE_PLAN_DETAIL_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.get(
    "/workload",
    response_model=PreparationWorkloadResponse,
    response_model_exclude_none=False,
)
async def get_preparation_workload(
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> PreparationWorkloadResponse:
    try:
        return await service.get_workload(user_id=principal.user_id)
    except DEADLINE_PLAN_READ_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.get(
    "/workload/{local_date}",
    response_model=PreparationWorkloadDetailResponse,
    response_model_exclude_none=False,
)
async def get_preparation_workload_detail(
    local_date: date,
    principal: Principal = Depends(get_current_principal),
    service: DeadlinePlanService = Depends(get_deadline_plan_service),
) -> PreparationWorkloadDetailResponse:
    try:
        return await service.get_workload_detail(
            user_id=principal.user_id,
            local_date=local_date,
        )
    except DEADLINE_PLAN_DETAIL_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.get(
    "/assignment-series",
    response_model=AssignmentSeriesListResponse,
    response_model_exclude_none=True,
)
async def list_assignment_series(
    principal: Principal = Depends(get_current_principal),
    service: AssignmentSeriesService = Depends(get_assignment_series_service),
) -> AssignmentSeriesListResponse:
    try:
        return await service.list_series(user_id=principal.user_id)
    except DEADLINE_PLAN_READ_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.get(
    "/assignment-series/{series_id}",
    response_model=AssignmentSeriesResponse,
    response_model_exclude_none=True,
)
async def get_assignment_series(
    series_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: AssignmentSeriesService = Depends(get_assignment_series_service),
) -> AssignmentSeriesResponse:
    try:
        return await service.get_series(
            user_id=principal.user_id,
            series_id=series_id,
        )
    except DEADLINE_PLAN_GET_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.post(
    "/assignment-series/proposals",
    response_model=AssignmentSeriesResponse,
    response_model_exclude_none=True,
)
async def propose_assignment_series(
    request: AssignmentSeriesProposalRequest,
    principal: Principal = Depends(get_current_principal),
    service: AssignmentSeriesService = Depends(get_assignment_series_service),
) -> AssignmentSeriesResponse:
    try:
        return await service.propose(user_id=principal.user_id, request=request)
    except DEADLINE_PLAN_DETAIL_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.post(
    "/assignment-series/{series_id}/confirm",
    response_model=AssignmentSeriesResponse,
    response_model_exclude_none=True,
)
async def confirm_assignment_series(
    series_id: UUID,
    request: AssignmentSeriesMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: AssignmentSeriesService = Depends(get_assignment_series_service),
) -> AssignmentSeriesResponse:
    try:
        return await service.confirm(
            user_id=principal.user_id,
            series_id=series_id,
            request=request,
        )
    except DEADLINE_PLAN_MUTATION_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


@router.post(
    "/assignment-series/{series_id}/cancel-future",
    response_model=AssignmentSeriesResponse,
    response_model_exclude_none=True,
)
async def cancel_assignment_series_future(
    series_id: UUID,
    request: AssignmentSeriesMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: AssignmentSeriesService = Depends(get_assignment_series_service),
) -> AssignmentSeriesResponse:
    try:
        return await service.cancel_future(
            user_id=principal.user_id,
            series_id=series_id,
            request=request,
        )
    except DEADLINE_PLAN_MUTATION_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


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
    except DEADLINE_PLAN_GET_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


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
    except DEADLINE_PLAN_DETAIL_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc


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
    except DEADLINE_PLAN_MUTATION_ERRORS as exc:
        raise deadline_plan_problem(exc) from exc
