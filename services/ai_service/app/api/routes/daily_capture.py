from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Path, status

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_daily_capture_service
from app.models.daily_capture import (
    DailyCaptureBranch,
    DailyCaptureWriteRequest,
    DailyCaptureWriteResponse,
)
from app.repositories.daily_capture_repository import (
    DailyCaptureConflictError,
    DailyCapturePersistenceError,
)
from app.services.daily_capture_service import (
    DailyCaptureService,
    InvalidDailyCaptureError,
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
    except InvalidDailyCaptureError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except DailyCaptureConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except DailyCapturePersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Daily Capture could not be saved.",
        ) from exc
