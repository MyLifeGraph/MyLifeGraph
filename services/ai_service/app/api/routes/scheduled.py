import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.api.deps.services import get_scheduled_refresh_service
from app.core.config import settings
from app.models.scheduled import ScheduledRefreshRequest, ScheduledRefreshResponse
from app.services.scheduled_refresh import ScheduledRefreshService

router = APIRouter(prefix="/scheduled", tags=["scheduled"])


def _verify_scheduled_refresh_token(token: str | None) -> None:
    expected = settings.scheduled_refresh_token.strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Scheduled refresh token is not configured.",
        )
    if not secrets.compare_digest(token or "", expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing scheduled refresh token.",
        )


async def _authorize_scheduled_refresh(
    scheduled_refresh_token: str | None = Header(
        default=None,
        alias="X-Scheduled-Refresh-Token",
    ),
) -> None:
    _verify_scheduled_refresh_token(scheduled_refresh_token)


@router.post("/daily-refresh", response_model=ScheduledRefreshResponse)
async def refresh_daily(
    request_body: ScheduledRefreshRequest,
    _: None = Depends(_authorize_scheduled_refresh),
    service: ScheduledRefreshService = Depends(get_scheduled_refresh_service),
) -> ScheduledRefreshResponse:
    return await service.refresh_daily(request_body)
