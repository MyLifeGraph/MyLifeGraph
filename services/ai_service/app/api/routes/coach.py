import json
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.coach import get_coach_service
from app.models.coach import (
    CoachCapabilitiesResponse,
    CoachErrorDetail,
    CoachHistoryDeleteResponse,
    CoachHistoryResponse,
    CoachMemorySelectionRequest,
    CoachMemorySelectionResponse,
    CoachRequest,
    CoachResponse,
)
from app.services.coach_service import CoachService, CoachServiceError


router = APIRouter(prefix="/coach", tags=["coach"])
_MAX_COACH_REQUEST_BODY_BYTES = 32 * 1024


@router.get("/capabilities", response_model=CoachCapabilitiesResponse)
async def get_coach_capabilities(
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachCapabilitiesResponse:
    try:
        return await service.capabilities(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.post("/respond", response_model=CoachResponse)
async def respond_to_coach(
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachResponse:
    request = await _parse_model(http_request, CoachRequest)
    try:
        return await service.respond(user_id=principal.user_id, request=request)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.get("/history", response_model=CoachHistoryResponse)
async def get_coach_history(
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachHistoryResponse:
    try:
        return await service.history(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.delete("/history", response_model=CoachHistoryDeleteResponse)
async def delete_coach_history(
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachHistoryDeleteResponse:
    await _require_empty_body(http_request)
    try:
        return await service.delete_history(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.get("/memories", response_model=CoachMemorySelectionResponse)
async def get_coach_memories(
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachMemorySelectionResponse:
    try:
        return await service.memories(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.post(
    "/memories/{memory_id}/selection",
    response_model=CoachMemorySelectionResponse,
)
async def select_coach_memory(
    memory_id: str,
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachMemorySelectionResponse:
    parsed_id = _parse_uuid(memory_id)
    selection = await _parse_model(http_request, CoachMemorySelectionRequest)
    try:
        return await service.set_memory_selection(
            user_id=principal.user_id,
            memory_id=parsed_id,
            selected=selection.selected,
        )
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.delete(
    "/memories/{memory_id}/selection",
    response_model=CoachMemorySelectionResponse,
)
async def deselect_coach_memory(
    memory_id: str,
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    service: CoachService = Depends(get_coach_service),
) -> CoachMemorySelectionResponse:
    parsed_id = _parse_uuid(memory_id)
    await _require_empty_body(http_request)
    try:
        return await service.set_memory_selection(
            user_id=principal.user_id,
            memory_id=parsed_id,
            selected=False,
        )
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


async def _parse_model(http_request: Request, model_type):
    try:
        raw = bytearray()
        async for chunk in http_request.stream():
            if len(raw) + len(chunk) > _MAX_COACH_REQUEST_BODY_BYTES:
                raise ValueError
            raw.extend(chunk)
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError
        return model_type.model_validate(value)
    except (
        UnicodeDecodeError,
        json.JSONDecodeError,
        ValidationError,
        ValueError,
    ) as exc:
        raise HTTPException(
            status_code=422,
            detail=_detail(
                "invalid_request",
                "The Coach request body does not match its strict contract.",
                retryable=False,
            ),
        ) from exc


async def _require_empty_body(http_request: Request) -> None:
    async for chunk in http_request.stream():
        if chunk:
            raise HTTPException(
                status_code=422,
                detail=_detail(
                    "invalid_request",
                    "This Coach operation does not accept a request body.",
                    retryable=False,
                ),
            )


def _parse_uuid(value: str) -> UUID:
    try:
        return UUID(value)
    except (ValueError, AttributeError) as exc:
        raise HTTPException(
            status_code=422,
            detail=_detail(
                "invalid_request",
                "The Coach memory id is invalid.",
                retryable=False,
            ),
        ) from exc


def _http_error(error: CoachServiceError) -> HTTPException:
    return HTTPException(
        status_code=error.status_code,
        detail=error.detail.model_dump(mode="json"),
    )


def _generic_error() -> HTTPException:
    return HTTPException(
        status_code=503,
        detail=_detail(
            "provider_failure",
            "The Coach service is temporarily unavailable.",
            retryable=True,
        ),
    )


def _detail(code: str, message: str, *, retryable: bool) -> dict[str, object]:
    return CoachErrorDetail(
        code=code,
        message=message,
        retryable=retryable,
    ).model_dump(mode="json")
