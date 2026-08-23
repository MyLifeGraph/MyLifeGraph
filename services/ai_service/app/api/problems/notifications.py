from typing import assert_never

from fastapi import HTTPException, status

from app.services.notification_service import (
    NotificationConflictError,
    NotificationNotFoundError,
    NotificationOutcomeUnknownError,
    NotificationServiceUnavailableError,
)

type NotificationReadError = (
    NotificationNotFoundError | NotificationServiceUnavailableError
)
type NotificationMutationError = (
    NotificationNotFoundError
    | NotificationConflictError
    | NotificationOutcomeUnknownError
    | NotificationServiceUnavailableError
)

NOTIFICATION_READ_ERRORS = (
    NotificationNotFoundError,
    NotificationServiceUnavailableError,
)
NOTIFICATION_MUTATION_ERRORS = (
    NotificationNotFoundError,
    NotificationConflictError,
    NotificationOutcomeUnknownError,
    NotificationServiceUnavailableError,
)


def notification_settings_read_problem(error: NotificationReadError) -> HTTPException:
    if isinstance(error, NotificationNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Notification settings are unavailable.",
        )
    if isinstance(error, NotificationServiceUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Notification settings persistence is unavailable.",
        )
    assert_never(error)


def notification_settings_update_problem(
    error: NotificationMutationError,
) -> HTTPException:
    if isinstance(error, NotificationNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Notification settings are unavailable.",
        )
    if isinstance(error, NotificationConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, NotificationOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Notification settings outcome could not be determined.",
        )
    if isinstance(error, NotificationServiceUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Notification settings persistence is unavailable.",
        )
    assert_never(error)


def notification_action_problem(error: NotificationMutationError) -> HTTPException:
    if isinstance(error, NotificationNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, "Notification is unavailable.")
    if isinstance(error, NotificationConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, NotificationOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Notification action outcome could not be determined.",
        )
    if isinstance(error, NotificationServiceUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Notification lifecycle persistence is unavailable.",
        )
    assert_never(error)


def notification_delivery_problem(
    error: NotificationMutationError,
) -> HTTPException:
    if isinstance(error, NotificationNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, "Notification is unavailable.")
    if isinstance(error, NotificationConflictError):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, NotificationOutcomeUnknownError):
        return HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "In-app delivery outcome could not be determined.",
        )
    if isinstance(error, NotificationServiceUnavailableError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "In-app delivery persistence is unavailable.",
        )
    assert_never(error)
