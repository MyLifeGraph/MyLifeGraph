from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.calendar_integrations import (
    CalendarConnectionCreateRequest,
    CalendarConnectionMutationRequest,
    CalendarConnectionResponse,
    CalendarEventsResponse,
    CalendarFileImportRequest,
    CalendarImportResponse,
)
from app.repositories.calendar_integration_repository import (
    SupabaseCalendarIntegrationRepository,
)
from app.services.calendar_ical_parser import CalendarParseError
from app.services.calendar_integration_service import (
    CalendarConflictError,
    CalendarConnectionNotFoundError,
    CalendarCursorError,
    CalendarCursorStaleError,
    CalendarIntegrationService,
)

router = APIRouter(prefix="/calendar-integrations", tags=["calendar-integrations"])


async def get_calendar_integration_service(request: Request) -> CalendarIntegrationService:
    injected = getattr(request.app.state, "calendar_integration_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Calendar integration persistence is not configured.",
        ) from exc
    return CalendarIntegrationService(
        repository=SupabaseCalendarIntegrationRepository(client),
    )


@router.get(
    "",
    response_model=CalendarConnectionResponse,
    response_model_exclude_none=True,
)
async def get_calendar_connection(
    principal: Principal = Depends(get_current_principal),
    service: CalendarIntegrationService = Depends(get_calendar_integration_service),
) -> CalendarConnectionResponse | JSONResponse:
    response = await service.get_connection(user_id=principal.user_id)
    if response.connection is None:
        # The nullable top-level field is part of the exact empty envelope.
        # Returning a Response only here keeps nested optionals omitted by the
        # route response model when a real connection exists.
        return JSONResponse(content=response.model_dump(mode="json", by_alias=True))
    return response


@router.post(
    "/connections",
    response_model=CalendarConnectionResponse,
    response_model_exclude_none=True,
)
async def create_calendar_connection(
    request: CalendarConnectionCreateRequest,
    principal: Principal = Depends(get_current_principal),
    service: CalendarIntegrationService = Depends(get_calendar_integration_service),
) -> CalendarConnectionResponse:
    try:
        return await service.create_connection(
            user_id=principal.user_id,
            request=request,
        )
    except CalendarConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.post(
    "/connections/{connection_id}/imports",
    response_model=CalendarImportResponse,
    response_model_exclude_none=True,
)
async def import_calendar_file(
    connection_id: UUID,
    request: CalendarFileImportRequest,
    principal: Principal = Depends(get_current_principal),
    service: CalendarIntegrationService = Depends(get_calendar_integration_service),
) -> CalendarImportResponse:
    try:
        return await service.import_file(
            user_id=principal.user_id,
            connection_id=connection_id,
            request=request,
        )
    except CalendarConnectionNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except CalendarConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except CalendarParseError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc


@router.get(
    "/connections/{connection_id}/events",
    response_model=CalendarEventsResponse,
    response_model_exclude_none=True,
)
async def get_calendar_events(
    connection_id: UUID,
    cursor: str | None = Query(default=None, min_length=1, max_length=512),
    limit: int = Query(default=50, ge=1, le=50),
    principal: Principal = Depends(get_current_principal),
    service: CalendarIntegrationService = Depends(get_calendar_integration_service),
) -> CalendarEventsResponse:
    try:
        return await service.get_events(
            user_id=principal.user_id,
            connection_id=connection_id,
            cursor=cursor,
            limit=limit,
        )
    except CalendarConnectionNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except CalendarCursorStaleError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except CalendarCursorError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc


@router.post(
    "/connections/{connection_id}/disconnect",
    response_model=CalendarConnectionResponse,
    response_model_exclude_none=True,
)
async def disconnect_calendar_connection(
    connection_id: UUID,
    request: CalendarConnectionMutationRequest,
    principal: Principal = Depends(get_current_principal),
    service: CalendarIntegrationService = Depends(get_calendar_integration_service),
) -> CalendarConnectionResponse:
    try:
        return await service.disconnect(
            user_id=principal.user_id,
            connection_id=connection_id,
            request=request,
        )
    except CalendarConnectionNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except CalendarConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.delete(
    "/connections/{connection_id}/imported-data",
    response_model=CalendarConnectionResponse,
    response_model_exclude_none=True,
)
async def delete_calendar_imported_data(
    connection_id: UUID,
    http_request: Request,
    request_id: UUID = Query(),
    principal: Principal = Depends(get_current_principal),
    service: CalendarIntegrationService = Depends(get_calendar_integration_service),
) -> CalendarConnectionResponse:
    if (
        set(http_request.query_params.keys()) != {"request_id"}
        or len(http_request.query_params.getlist("request_id")) != 1
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Exactly one request_id query parameter is required.",
        )
    if await http_request.body():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Imported-data deletion does not accept a request body.",
        )
    try:
        return await service.delete_imported_data(
            user_id=principal.user_id,
            connection_id=connection_id,
            request_id=request_id,
        )
    except CalendarConnectionNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except CalendarConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
