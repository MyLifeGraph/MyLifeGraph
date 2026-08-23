from typing import assert_never

from fastapi import HTTPException, status

from app.services.focus_service import FocusConflictError, FocusNotFoundError

type FocusError = FocusNotFoundError | FocusConflictError

FOCUS_ERRORS = (FocusNotFoundError, FocusConflictError)


def focus_problem(error: FocusError) -> HTTPException:
    if isinstance(error, FocusNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, str(error))
    if isinstance(error, FocusConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    assert_never(error)
