from typing import assert_never

from fastapi import HTTPException, status

from app.services.feedback_service import FeedbackConflictError, FeedbackNotFoundError

type FeedbackError = FeedbackConflictError | FeedbackNotFoundError

FEEDBACK_CREATE_ERRORS = (FeedbackConflictError, FeedbackNotFoundError)
FEEDBACK_DELETE_ERRORS = (FeedbackNotFoundError,)


def feedback_problem(error: FeedbackError) -> HTTPException:
    if isinstance(error, FeedbackConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, FeedbackNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, str(error))
    assert_never(error)
