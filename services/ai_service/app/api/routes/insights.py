from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_personal_patterns_service
from app.api.problems.insights import (
    PERSONAL_PATTERNS_ERRORS,
    personal_patterns_problem,
)
from app.models.personal_patterns import PersonalPatternsResponse
from app.services.personal_patterns_service import (
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
    except PERSONAL_PATTERNS_ERRORS as exc:
        raise personal_patterns_problem(exc) from exc
