from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_focus_service
from app.api.problems.focus import FOCUS_ERRORS, focus_problem
from app.models.focus import (
    FocusCapabilitiesResponse,
    FocusSessionResult,
    FocusOpenEndCapabilitiesResponse,
    OpenEndFocusStartRequest,
    FocusStartContextResponse,
    FocusStartRequest,
    FocusTimeCorrectionRequest,
)
from app.services.focus_service import FocusService


router = APIRouter(prefix="/focus", tags=["focus"])


@router.get("/open-end/capabilities", response_model=FocusOpenEndCapabilitiesResponse)
async def get_focus_open_end_capabilities(
    _principal: Principal = Depends(get_current_principal),
) -> FocusOpenEndCapabilitiesResponse:
    return FocusOpenEndCapabilitiesResponse()


@router.post("/open-end/start", response_model=FocusSessionResult)
async def start_focus_open_end(
    request: OpenEndFocusStartRequest,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResult:
    try:
        return await service.start_open_end(user_id=principal.user_id, request=request)
    except FOCUS_ERRORS as exc:
        raise focus_problem(exc) from exc


@router.post("/sessions/{session_id}/correct-time", response_model=FocusSessionResult)
async def correct_focus_time(
    session_id: UUID,
    request: FocusTimeCorrectionRequest,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResult:
    try:
        return await service.correct_time(user_id=principal.user_id, session_id=session_id, request=request)
    except FOCUS_ERRORS as exc:
        raise focus_problem(exc) from exc


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
    except FOCUS_ERRORS as exc:
        raise focus_problem(exc) from exc


@router.post(
    "/sessions/start",
    response_model=FocusSessionResult,
    response_model_exclude_none=False,
)
async def start_focus_session(
    request: FocusStartRequest,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResult:
    return await _start(service, user_id=principal.user_id, request=request)


@router.post(
    "/sessions/{session_id}/finish",
    response_model=FocusSessionResult,
    response_model_exclude_none=False,
)
async def finish_focus_session(
    session_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResult:
    return await _finish(
        service,
        user_id=principal.user_id,
        session_id=session_id,
        terminal_status="completed",
    )


@router.post(
    "/sessions/{session_id}/abandon",
    response_model=FocusSessionResult,
    response_model_exclude_none=False,
)
async def abandon_focus_session(
    session_id: UUID,
    principal: Principal = Depends(get_current_principal),
    service: FocusService = Depends(get_focus_service),
) -> FocusSessionResult:
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
) -> FocusSessionResult:
    try:
        return await service.start(user_id=user_id, request=request)
    except FOCUS_ERRORS as exc:
        raise focus_problem(exc) from exc


async def _finish(
    service: FocusService,
    *,
    user_id: str,
    session_id: UUID,
    terminal_status: str,
) -> FocusSessionResult:
    try:
        return await service.finish(
            user_id=user_id,
            session_id=session_id,
            terminal_status=terminal_status,
        )
    except FOCUS_ERRORS as exc:
        raise focus_problem(exc) from exc
