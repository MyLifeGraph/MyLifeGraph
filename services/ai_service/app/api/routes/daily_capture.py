from datetime import date

from fastapi import APIRouter, Depends, Path

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_daily_capture_service
from app.api.problems.daily_capture import DAILY_CAPTURE_ERRORS, daily_capture_problem
from app.models.daily_capture import (
    DailyCaptureBranch,
    DailyCaptureWriteRequest,
    DailyCaptureWriteResponse,
)
from app.services.daily_capture_service import (
    DailyCaptureService,
)


router = APIRouter(prefix="/daily-capture", tags=["daily-capture"])


@router.put(
    "/{entry_date}/{branch}",
    response_model=DailyCaptureWriteResponse,
)
async def write_daily_capture_branch(
    body: DailyCaptureWriteRequest,
    entry_date: date = Path(),
    branch: DailyCaptureBranch = Path(),
    principal: Principal = Depends(get_current_principal),
    service: DailyCaptureService = Depends(get_daily_capture_service),
) -> DailyCaptureWriteResponse:
    try:
        return await service.write_branch(
            user_id=principal.user_id,
            entry_date=entry_date,
            branch=branch,
            request=body,
        )
    except DAILY_CAPTURE_ERRORS as exc:
        raise daily_capture_problem(exc) from exc
