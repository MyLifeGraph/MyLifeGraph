from typing import assert_never

from fastapi import HTTPException, status

from app.services.planner_errors import (
    PlannerConflictError,
    PlannerNotFoundError,
    PlannerValidationError,
)

type PlannerError = PlannerNotFoundError | PlannerConflictError | PlannerValidationError

PLANNER_ERRORS = (PlannerNotFoundError, PlannerConflictError, PlannerValidationError)


def planner_problem(error: PlannerError) -> HTTPException:
    if isinstance(error, PlannerNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, str(error))
    if isinstance(error, PlannerValidationError):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
    if isinstance(error, PlannerConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    assert_never(error)
