from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_focus_service
from app.models.focus import (
    FocusCapabilitiesResponse,
    FocusSessionResponse,
    FocusStartContextResponse,
    FocusStartRequest,
)
from app.services.focus_service import (
    FocusConflictError,
    FocusNotFoundError,
    FocusService,
)


router = APIRouter(prefix="/focus", tags=["focus"])


@router.get(
    "/capabilities",
    response_model=FocusCapabilitiesResponse,
)
async def get_focus_capabilities(
    _principal: Principal = Depends(get_current_principal),
) -> FocusCapabilitiesResponse:
    return FocusCapabilitiesResponse()


@router.get(
    "/start-context/{source_kind}/{block_id}",
    response_model=FocusStartContextResponse,
    response_model_exclude_none=False,
)
async def get_focus_start_context(
    source_kind: Literal["deadline_plan_block", "planner_task_block"],
    block_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusStartContextResponse:
    try:
        return await service.get_start_context(
            user_id=principal.user_id,
            source_kind=source_kind,
            block_id=block_id,
        )
    except FocusNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except FocusConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from exc


@router.post(
    "/sessions/start",
    response_model=FocusSessionResponse,
    response_model_exclude_none=False,
)
async def start_focus_session(
    request: FocusStartRequest,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResponse:
    return await _start(service, user_id=principal.user_id, request=request)


@router.post(
    "/sessions/{session_id}/finish",
    response_model=FocusSessionResponse,
    response_model_exclude_none=False,
)
async def finish_focus_session(
    session_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResponse:
    return await _finish(
        service,
        user_id=principal.user_id,
        session_id=session_id,
        terminal_status="completed",
    )


@router.post(
    "/sessions/{session_id}/abandon",
    response_model=FocusSessionResponse,
    response_model_exclude_none=False,
)
async def abandon_focus_session(
    session_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResponse:
    return await _finish(
        service,
        user_id=principal.user_id,
        session_id=session_id,
        terminal_status="abandoned",
    )


async def _start(
    service: FocusService,
    *,
    user_id: str,
    request: FocusStartRequest,
) -> FocusSessionResponse:
    try:
        return await service.start(user_id=user_id, request=request)
    except FocusNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except FocusConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from exc


async def _finish(
    service: FocusService,
    *,
    user_id: str,
    session_id: UUID,
    terminal_status: str,
) -> FocusSessionResponse:
    try:
        return await service.finish(
            user_id=user_id,
            session_id=session_id,
            terminal_status=terminal_status,
        )
    except FocusNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except FocusConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from exc
