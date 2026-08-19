from typing import assert_never

from fastapi import HTTPException, status

from app.services.account_service import (
    AccountConflictError,
    AccountExportTooLargeError,
    AccountNotFoundError,
    AccountOutcomeUnknownError,
    AccountUnavailableError,
    InvalidAccountTimezoneError,
    InvalidPreparationBudgetError,
)

type AccountProfileError = (
    InvalidAccountTimezoneError
    | AccountNotFoundError
    | AccountConflictError
    | AccountOutcomeUnknownError
    | AccountUnavailableError
)
type AccountPreparationBudgetError = (
    InvalidPreparationBudgetError
    | AccountNotFoundError
    | AccountConflictError
    | AccountOutcomeUnknownError
    | AccountUnavailableError
)
type AccountExportError = AccountExportTooLargeError | AccountUnavailableError
type AccountDeleteError = (
    AccountNotFoundError | AccountOutcomeUnknownError | AccountUnavailableError
)
type AccountParticipationError = (
    AccountNotFoundError | AccountOutcomeUnknownError | AccountUnavailableError
)

ACCOUNT_PROFILE_ERRORS = (
    InvalidAccountTimezoneError,
    AccountNotFoundError,
    AccountConflictError,
    AccountOutcomeUnknownError,
    AccountUnavailableError,
)
ACCOUNT_PREPARATION_BUDGET_ERRORS = (
    InvalidPreparationBudgetError,
    AccountNotFoundError,
    AccountConflictError,
    AccountOutcomeUnknownError,
    AccountUnavailableError,
)
ACCOUNT_EXPORT_ERRORS = (AccountExportTooLargeError, AccountUnavailableError)
ACCOUNT_DELETE_ERRORS = (
    AccountNotFoundError,
    AccountOutcomeUnknownError,
    AccountUnavailableError,
)
ACCOUNT_PARTICIPATION_ERRORS = (
    AccountNotFoundError,
    AccountOutcomeUnknownError,
    AccountUnavailableError,
)


def account_participation_problem(
    error: AccountParticipationError,
) -> HTTPException:
    if isinstance(error, AccountNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Account profile is unavailable.",
        )
    if isinstance(error, AccountOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Pilot participation outcome could not be determined.",
        )
    if isinstance(error, AccountUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Pilot participation acceptance could not be recorded.",
        )
    assert_never(error)


def account_profile_problem(error: AccountProfileError) -> HTTPException:
    if isinstance(error, InvalidAccountTimezoneError):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
    if isinstance(error, AccountNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Account profile is unavailable.",
        )
    if isinstance(error, AccountConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, AccountOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Account profile update outcome could not be determined.",
        )
    if isinstance(error, AccountUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Account profile could not be updated.",
        )
    assert_never(error)


def account_preparation_budget_problem(
    error: AccountPreparationBudgetError,
) -> HTTPException:
    if isinstance(error, InvalidPreparationBudgetError):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
    if isinstance(error, AccountNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Account profile is unavailable.",
        )
    if isinstance(error, AccountConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, AccountOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Preparation budget update outcome could not be determined.",
        )
    if isinstance(error, AccountUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Preparation budget could not be updated.",
        )
    assert_never(error)


def account_export_problem(error: AccountExportError) -> HTTPException:
    if isinstance(error, AccountExportTooLargeError):
        return HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, str(error))
    if isinstance(error, AccountUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Account export could not be generated.",
        )
    assert_never(error)


def account_delete_problem(error: AccountDeleteError) -> HTTPException:
    if isinstance(error, AccountNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, "Account is unavailable.")
    if isinstance(error, AccountOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Account deletion outcome could not be determined.",
        )
    if isinstance(error, AccountUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Account deletion could not be completed.",
        )
    assert_never(error)
