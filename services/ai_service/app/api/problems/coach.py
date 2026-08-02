from fastapi import HTTPException

from app.models.coach import CoachErrorDetail
from app.services.coach_service import CoachServiceError


def invalid_coach_request_problem(
    message: str = "The Coach request body does not match its strict contract.",
) -> HTTPException:
    return HTTPException(
        status_code=422,
        detail=coach_error_detail("invalid_request", message, retryable=False),
    )


def coach_service_problem(error: CoachServiceError) -> HTTPException:
    return HTTPException(
        status_code=error.status_code,
        detail=error.detail.model_dump(mode="json"),
    )


def coach_unavailable_problem() -> HTTPException:
    return HTTPException(
        status_code=503,
        detail=coach_error_detail(
            "provider_failure",
            "The Coach service is temporarily unavailable.",
            retryable=True,
        ),
    )


def coach_error_detail(
    code: str,
    message: str,
    *,
    retryable: bool,
) -> dict[str, object]:
    return CoachErrorDetail(
        code=code,
        message=message,
        retryable=retryable,
    ).model_dump(mode="json")
