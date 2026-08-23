from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_learning_service
from app.api.problems.learning import (
    LEARNING_MUTATION_ERRORS,
    LEARNING_READ_ERRORS,
    learning_clear_problem,
    learning_read_problem,
    learning_update_problem,
)
from app.models.learning import (
    FocusReflectionHistoryClearRequest,
    FocusReflectionHistoryClearResponse,
    LearningPreferencesState,
    LearningPreferencesUpdateRequest,
    LearningPreferencesUpdateResponse,
)
from app.services.learning_service import (
    LearningService,
)


router = APIRouter(prefix="/learning", tags=["learning"])


@router.get("/preferences", response_model=LearningPreferencesState)
async def get_learning_preferences(
    principal: Principal = Depends(get_current_principal),
    service: LearningService = Depends(get_learning_service),
) -> LearningPreferencesState:
    try:
        return await service.get_preferences(user_id=principal.user_id)
    except LEARNING_READ_ERRORS as exc:
        raise learning_read_problem(exc) from exc


@router.patch(
    "/preferences",
    response_model=LearningPreferencesUpdateResponse,
)
async def update_learning_preferences(
    body: LearningPreferencesUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    service: LearningService = Depends(get_learning_service),
) -> LearningPreferencesUpdateResponse:
    try:
        return await service.update_preferences(
            user_id=principal.user_id,
            request=body,
        )
    except LEARNING_MUTATION_ERRORS as exc:
        raise learning_update_problem(exc) from exc


@router.post(
    "/focus-reflections/clear",
    response_model=FocusReflectionHistoryClearResponse,
)
async def clear_focus_reflection_history(
    body: FocusReflectionHistoryClearRequest,
    principal: Principal = Depends(get_current_principal),
    service: LearningService = Depends(get_learning_service),
) -> FocusReflectionHistoryClearResponse:
    try:
        return await service.clear_focus_reflections(
            user_id=principal.user_id,
            request=body,
        )
    except LEARNING_MUTATION_ERRORS as exc:
        raise learning_clear_problem(exc) from exc
