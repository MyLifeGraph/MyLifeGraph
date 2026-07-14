from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.notifications import (
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
)
from app.repositories.notification_repository import SupabaseNotificationRepository
from app.services.notification_service import (
    NotificationConflictError,
    NotificationNotFoundError,
    NotificationOutcomeUnknownError,
    NotificationService,
    NotificationServiceUnavailableError,
)


router = APIRouter(prefix="/notifications", tags=["notifications"])


async def get_notification_service(request: Request) -> NotificationService:
    injected = getattr(request.app.state, "notification_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Notification lifecycle persistence is not configured.",
        ) from exc
    return NotificationService(
        repository=SupabaseNotificationRepository(client),
    )


@router.post(
    "/{notification_id}/actions",
    response_model=NotificationLifecycleActionResponse,
)
async def apply_notification_action(
    notification_id: UUID,
    body: NotificationLifecycleActionRequest,
    principal: Principal = Depends(get_current_principal),
    service: NotificationService = Depends(get_notification_service),
) -> NotificationLifecycleActionResponse:
    try:
        return await service.apply_action(
            user_id=principal.user_id,
            notification_id=notification_id,
            request=body,
        )
    except NotificationNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification is unavailable.",
        ) from exc
    except NotificationConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except NotificationOutcomeUnknownError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Notification action outcome could not be determined.",
        ) from exc
    except NotificationServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Notification lifecycle persistence is unavailable.",
        ) from exc
