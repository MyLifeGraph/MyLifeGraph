from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_personal_patterns_service
from app.models.personal_patterns import PersonalPatternsResponse
from app.repositories.learning_repository import (
    LearningPersistenceError,
)
from app.repositories.personal_patterns_repository import (
    PersonalPatternsNotFound,
    PersonalPatternsPersistenceError,
)
from app.services.learning_service import LearningContractError
from app.services.personal_patterns_service import (
    PersonalPatternsDataError,
    PersonalPatternsService,
)


router = APIRouter(prefix="/insights", tags=["insights"])


@router.get(
    "/personal-patterns",
    response_model=PersonalPatternsResponse,
)
async def get_personal_patterns(
    principal: Principal = Depends(get_current_principal),
    service: PersonalPatternsService = Depends(get_personal_patterns_service),
) -> PersonalPatternsResponse:
    try:
        return await service.get_patterns(user_id=principal.user_id)
    except PersonalPatternsNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Personal pattern profile is unavailable.",
        ) from exc
    except (
        LearningPersistenceError,
        LearningContractError,
        PersonalPatternsPersistenceError,
        PersonalPatternsDataError,
    ) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Personal patterns could not be loaded.",
        ) from exc
