from typing import assert_never

from fastapi import HTTPException, status

from app.services.learning_service import (
    LearningConflictError,
    LearningContractError,
    LearningNotFoundError,
    LearningOutcomeUnknownError,
    LearningUnavailableError,
)

type LearningReadError = (
    LearningNotFoundError | LearningUnavailableError | LearningContractError
)
type LearningMutationError = (
    LearningConflictError
    | LearningNotFoundError
    | LearningOutcomeUnknownError
    | LearningContractError
    | LearningUnavailableError
)

LEARNING_READ_ERRORS = (
    LearningNotFoundError,
    LearningUnavailableError,
    LearningContractError,
)
LEARNING_MUTATION_ERRORS = (
    LearningConflictError,
    LearningNotFoundError,
    LearningOutcomeUnknownError,
    LearningContractError,
    LearningUnavailableError,
)


def learning_read_problem(error: LearningReadError) -> HTTPException:
    if isinstance(error, LearningNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Personal learning settings are unavailable.",
        )
    if isinstance(error, (LearningUnavailableError, LearningContractError)):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Personal learning settings could not be loaded.",
        )
    assert_never(error)


def learning_update_problem(error: LearningMutationError) -> HTTPException:
    if isinstance(error, LearningConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, LearningNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Personal learning settings are unavailable.",
        )
    if isinstance(error, LearningOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Personal learning update outcome could not be determined.",
        )
    if isinstance(error, LearningContractError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Personal learning update returned an invalid result.",
        )
    if isinstance(error, LearningUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Personal learning settings could not be updated.",
        )
    assert_never(error)


def learning_clear_problem(error: LearningMutationError) -> HTTPException:
    if isinstance(error, LearningConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, LearningNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Personal learning settings are unavailable.",
        )
    if isinstance(error, LearningOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Focus reflection clear outcome could not be determined.",
        )
    if isinstance(error, LearningContractError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Focus reflection clear returned an invalid result.",
        )
    if isinstance(error, LearningUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Focus reflection history could not be cleared.",
        )
    assert_never(error)
