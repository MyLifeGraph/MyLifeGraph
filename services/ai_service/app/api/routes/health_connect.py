import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.supabase import get_supabase_client
from app.clients.supabase import SupabaseConfigurationError
from app.models.health_connect import HealthConnectCommand, HealthConnectState
from app.services.health_connect_service import HealthConnectService


router = APIRouter(prefix="/health-connect", tags=["health-connect"])


def get_health_connect_service(
    request: Request,
) -> HealthConnectService:
    try:
        return HealthConnectService(get_supabase_client(request))
    except SupabaseConfigurationError as error:
        raise _problem(error) from error


def _problem(error: Exception) -> HTTPException:
    status = 503
    message = (
        "Health Connect is unavailable. Nothing was confirmed; reload before retrying."
    )
    if isinstance(error, httpx.HTTPStatusError):
        if error.response.status_code == 409:
            status, message = 409, "Health Connect changed. Reload before retrying."
        elif error.response.status_code in (400, 403):
            status, message = (
                422,
                "Health Connect consent or sync window is no longer valid.",
            )
    return HTTPException(status_code=status, detail=message)


@router.get("", response_model=HealthConnectState)
async def read_health_connect(
    response: Response,
    principal: Principal = Depends(get_current_principal),
    service: HealthConnectService = Depends(get_health_connect_service),
):
    response.headers["Cache-Control"] = "no-store"
    try:
        return await service.read(principal.user_id)
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error


@router.post("", response_model=HealthConnectState)
async def command_health_connect(
    command: HealthConnectCommand,
    response: Response,
    principal: Principal = Depends(get_current_principal),
    service: HealthConnectService = Depends(get_health_connect_service),
):
    response.headers["Cache-Control"] = "no-store"
    try:
        return await service.apply(principal.user_id, command)
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error
