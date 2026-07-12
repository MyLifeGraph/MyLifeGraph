from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.feedback import (
    DecisionFeedbackCreateRequest,
    DecisionFeedbackDeleteResponse,
    DecisionFeedbackListResponse,
    DecisionFeedbackResponse,
)
from app.repositories.feedback_repository import SupabaseFeedbackRepository
from app.services.feedback_service import (
    FeedbackConflictError,
    FeedbackNotFoundError,
    FeedbackService,
)

router = APIRouter(prefix="/feedback", tags=["feedback"])


async def get_feedback_service(request: Request) -> FeedbackService:
    injected = getattr(request.app.state, "feedback_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Feedback persistence is not configured.",
        ) from exc
    return FeedbackService(repository=SupabaseFeedbackRepository(client))


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
    except FeedbackConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except FeedbackNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.delete("/{feedback_id}", response_model=DecisionFeedbackDeleteResponse)
async def delete_feedback(
    feedback_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FeedbackService = Depends(get_feedback_service),
) -> DecisionFeedbackDeleteResponse:
    try:
        return await service.delete(user_id=principal.user_id, feedback_id=feedback_id)
    except FeedbackNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
