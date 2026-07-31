from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_notification_service
from app.models.notifications import (
    NotificationDeliveryReceiptRequest,
    NotificationDeliveryReceiptResponse,
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
    NotificationSettingsResponse,
    NotificationSettingsUpdateRequest,
)
from app.services.notification_service import (
    NotificationConflictError,
    NotificationNotFoundError,
    NotificationOutcomeUnknownError,
    NotificationService,
    NotificationServiceUnavailableError,
)


router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/settings", response_model=NotificationSettingsResponse)
async def get_notification_settings(
    principal: Principal = Depends(get_current_principal),
    service: NotificationService = Depends(get_notification_service),
) -> NotificationSettingsResponse:
    try:
        return await service.get_settings(user_id=principal.user_id)
    except NotificationNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification settings are unavailable.",
        ) from exc
    except NotificationServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Notification settings persistence is unavailable.",
        ) from exc


@router.patch("/settings", response_model=NotificationSettingsResponse)
async def update_notification_settings(
    body: NotificationSettingsUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    service: NotificationService = Depends(get_notification_service),
) -> NotificationSettingsResponse:
    try:
        return await service.update_settings(
            user_id=principal.user_id,
            request=body,
        )
    except NotificationNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification settings are unavailable.",
        ) from exc
    except NotificationConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except NotificationOutcomeUnknownError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Notification settings outcome could not be determined.",
        ) from exc
    except NotificationServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Notification settings persistence is unavailable.",
        ) from exc


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


@router.post(
    "/{notification_id}/delivery",
    response_model=NotificationDeliveryReceiptResponse,
)
async def acknowledge_in_app_delivery(
    notification_id: UUID,
    body: NotificationDeliveryReceiptRequest,
    principal: Principal = Depends(get_current_principal),
    service: NotificationService = Depends(get_notification_service),
) -> NotificationDeliveryReceiptResponse:
    del body
    try:
        return await service.acknowledge_delivery(
            user_id=principal.user_id,
            notification_id=notification_id,
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
            detail="In-app delivery outcome could not be determined.",
        ) from exc
    except NotificationServiceUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="In-app delivery persistence is unavailable.",
        ) from exc
