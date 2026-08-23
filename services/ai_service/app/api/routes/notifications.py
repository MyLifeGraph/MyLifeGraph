from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_notification_service
from app.api.problems.notifications import (
    NOTIFICATION_MUTATION_ERRORS,
    NOTIFICATION_READ_ERRORS,
    notification_action_problem,
    notification_delivery_problem,
    notification_settings_read_problem,
    notification_settings_update_problem,
)
from app.models.notifications import (
    NotificationDeliveryReceiptRequest,
    NotificationDeliveryReceiptResponse,
    NotificationLifecycleActionRequest,
    NotificationLifecycleActionResponse,
    NotificationSettingsResponse,
    NotificationSettingsUpdateRequest,
)
from app.services.notification_service import (
    NotificationService,
)


router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/settings", response_model=NotificationSettingsResponse)
async def get_notification_settings(
    principal: Principal = Depends(get_current_principal),
    service: NotificationService = Depends(get_notification_service),
) -> NotificationSettingsResponse:
    try:
        return await service.get_settings(user_id=principal.user_id)
    except NOTIFICATION_READ_ERRORS as exc:
        raise notification_settings_read_problem(exc) from exc


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
    except NOTIFICATION_MUTATION_ERRORS as exc:
        raise notification_settings_update_problem(exc) from exc


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
    except NOTIFICATION_MUTATION_ERRORS as exc:
        raise notification_action_problem(exc) from exc


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
    except NOTIFICATION_MUTATION_ERRORS as exc:
        raise notification_delivery_problem(exc) from exc
