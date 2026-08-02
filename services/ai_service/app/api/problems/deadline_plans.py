from typing import assert_never

from fastapi import HTTPException, status

from app.services.deadline_plan_service import (
    DeadlinePlanConflictError,
    DeadlinePlanNotFoundError,
    DeadlinePlanValidationError,
)

type DeadlinePlanError = (
    DeadlinePlanNotFoundError | DeadlinePlanConflictError | DeadlinePlanValidationError
)

DEADLINE_PLAN_READ_ERRORS = (
    DeadlinePlanNotFoundError,
    DeadlinePlanConflictError,
)
DEADLINE_PLAN_DETAIL_ERRORS = (
    DeadlinePlanNotFoundError,
    DeadlinePlanConflictError,
    DeadlinePlanValidationError,
)
DEADLINE_PLAN_GET_ERRORS = (DeadlinePlanNotFoundError,)
DEADLINE_PLAN_MUTATION_ERRORS = (
    DeadlinePlanNotFoundError,
    DeadlinePlanConflictError,
)


def deadline_plan_problem(error: DeadlinePlanError) -> HTTPException:
    if isinstance(error, DeadlinePlanNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, str(error))
    if isinstance(error, DeadlinePlanConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, DeadlinePlanValidationError):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
    assert_never(error)
