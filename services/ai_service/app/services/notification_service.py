from uuid import UUID

from app.models.notifications import (
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
)
from app.repositories.notification_repository import (
    NotificationPersistenceConflict,
    NotificationPersistenceError,
    NotificationPersistenceNotFound,
    NotificationPersistenceOutcomeUnknown,
    NotificationRepository,
)


class NotificationConflictError(ValueError):
    pass


class NotificationNotFoundError(ValueError):
    pass


class NotificationOutcomeUnknownError(RuntimeError):
    pass


class NotificationServiceUnavailableError(RuntimeError):
    pass


class NotificationService:
    def __init__(self, *, repository: NotificationRepository) -> None:
        self._repository = repository

    async def apply_action(
        self,
        *,
        user_id: str,
        notification_id: UUID,
        request: NotificationLifecycleActionRequest,
    ) -> NotificationLifecycleActionResponse:
        try:
            return await self._repository.apply_action(
                user_id=user_id,
                notification_id=notification_id,
                request_id=request.request_id,
                command=request.command,
                expected_updated_at=request.expected_updated_at.isoformat(),
            )
        except NotificationPersistenceConflict as exc:
            raise NotificationConflictError(str(exc)) from exc
        except NotificationPersistenceNotFound as exc:
            raise NotificationNotFoundError("Notification is unavailable.") from exc
        except NotificationPersistenceOutcomeUnknown as exc:
            raise NotificationOutcomeUnknownError(
                "Notification action outcome could not be determined.",
            ) from exc
        except NotificationPersistenceError as exc:
            raise NotificationServiceUnavailableError(
                "Notification lifecycle persistence is unavailable.",
            ) from exc
