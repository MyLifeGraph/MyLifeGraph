from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.learning import (
    FocusReflectionHistoryClearRequest,
    FocusReflectionHistoryClearResponse,
    LearningPreferencesState,
    LearningPreferencesUpdateRequest,
    LearningPreferencesUpdateResponse,
)
from app.repositories.learning_repository import (
    LearningPersistenceConflict,
    LearningPersistenceError,
    LearningPersistenceNotFound,
    LearningPersistenceOutcomeUnknown,
    SupabaseLearningRepository,
)
from app.services.learning_service import LearningContractError, LearningService


router = APIRouter(prefix="/learning", tags=["learning"])


async def get_learning_service(request: Request) -> LearningService:
    injected = getattr(request.app.state, "learning_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Personal learning persistence is not configured.",
        ) from exc
    return LearningService(repository=SupabaseLearningRepository(client))


@router.get("/preferences", response_model=LearningPreferencesState)
async def get_learning_preferences(
    principal: Principal = Depends(get_current_principal),
    service: LearningService = Depends(get_learning_service),
) -> LearningPreferencesState:
    try:
        return await service.get_preferences(user_id=principal.user_id)
    except LearningPersistenceNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Personal learning settings are unavailable.",
        ) from exc
    except (LearningPersistenceError, LearningContractError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Personal learning settings could not be loaded.",
        ) from exc


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
    except LearningPersistenceConflict as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except LearningPersistenceNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Personal learning settings are unavailable.",
        ) from exc
    except LearningPersistenceOutcomeUnknown as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Personal learning update outcome could not be determined.",
        ) from exc
    except LearningContractError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Personal learning update returned an invalid result.",
        ) from exc
    except LearningPersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Personal learning settings could not be updated.",
        ) from exc


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
    except LearningPersistenceConflict as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except LearningPersistenceNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Personal learning settings are unavailable.",
        ) from exc
    except LearningPersistenceOutcomeUnknown as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Focus reflection clear outcome could not be determined.",
        ) from exc
    except LearningContractError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Focus reflection clear returned an invalid result.",
        ) from exc
    except LearningPersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Focus reflection history could not be cleared.",
        ) from exc
