from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_feedback_service
from app.api.problems.feedback import (
    FEEDBACK_CREATE_ERRORS,
    FEEDBACK_DELETE_ERRORS,
    feedback_problem,
)
from app.models.feedback import (
    DecisionFeedbackCreateRequest,
    DecisionFeedbackDeleteResponse,
    DecisionFeedbackListResponse,
    DecisionFeedbackResponse,
)
from app.services.feedback_service import (
    FeedbackService,
)

router = APIRouter(prefix="/feedback", tags=["feedback"])


@router.get("", response_model=DecisionFeedbackListResponse)
async def list_feedback(
    principal: Principal = Depends(get_current_principal),
    service: FeedbackService = Depends(get_feedback_service),
) -> DecisionFeedbackListResponse:
    return await service.list_recent(user_id=principal.user_id)


@router.post("", response_model=DecisionFeedbackResponse)
async def create_feedback(
    request: DecisionFeedbackCreateRequest,
    principal: Principal = Depends(get_current_principal),
    service: FeedbackService = Depends(get_feedback_service),
) -> DecisionFeedbackResponse:
    try:
        return await service.create(user_id=principal.user_id, request=request)
    except FEEDBACK_CREATE_ERRORS as exc:
        raise feedback_problem(exc) from exc


@router.delete("/{feedback_id}", response_model=DecisionFeedbackDeleteResponse)
async def delete_feedback(
    feedback_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FeedbackService = Depends(get_feedback_service),
) -> DecisionFeedbackDeleteResponse:
    try:
        return await service.delete(user_id=principal.user_id, feedback_id=feedback_id)
    except FEEDBACK_DELETE_ERRORS as exc:
        raise feedback_problem(exc) from exc
