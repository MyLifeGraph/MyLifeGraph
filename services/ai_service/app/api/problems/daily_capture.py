from typing import assert_never

from fastapi import HTTPException, status

from app.services.daily_capture_service import (
    DailyCaptureConflictError,
    DailyCaptureUnavailableError,
    InvalidDailyCaptureError,
)

type DailyCaptureError = (
    InvalidDailyCaptureError | DailyCaptureConflictError | DailyCaptureUnavailableError
)

DAILY_CAPTURE_ERRORS = (
    InvalidDailyCaptureError,
    DailyCaptureConflictError,
    DailyCaptureUnavailableError,
)


def daily_capture_problem(error: DailyCaptureError) -> HTTPException:
    if isinstance(error, InvalidDailyCaptureError):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
    if isinstance(error, DailyCaptureConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, DailyCaptureUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Daily Capture could not be saved.",
        )
    assert_never(error)
