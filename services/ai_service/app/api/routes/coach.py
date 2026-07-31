import asyncio
import json
from collections.abc import AsyncIterator
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.coach import get_coach_services
from app.composition import CoachServices
from app.models.coach import (
    CoachAgentCapabilitiesResponse,
    CoachAgentHistoryResponse,
    CoachAgentRequest,
    CoachAgentResponse,
    CoachCapabilitiesResponse,
    CoachContextOptionsResponse,
    CoachErrorDetail,
    CoachHistoryDeleteResponse,
    CoachHistoryResponse,
    CoachMemorySelectionRequest,
    CoachMemorySelectionResponse,
    CoachRequest,
    CoachResponse,
)
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_service import CoachServiceError


router = APIRouter(prefix="/coach", tags=["coach"])
_MAX_COACH_REQUEST_BODY_BYTES = 32 * 1024
_ACTIVITY_MESSAGES = {
    "Preparing a private data snapshot …",
    "Preparing a direct answer …",
    "Checking available personal data …",
    "Checking relevant history …",
    "Testing the data with isolated analysis …",
}


@router.get(
    "/capabilities",
    response_model=CoachAgentCapabilitiesResponse | CoachCapabilitiesResponse,
)
async def get_coach_capabilities(
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachAgentCapabilitiesResponse | CoachCapabilitiesResponse:
    try:
        return await services.current.capabilities(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.post(
    "/respond",
    response_model=CoachAgentResponse | CoachResponse,
)
async def respond_to_coach(
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachAgentResponse | CoachResponse:
    raw = await _read_json_object(http_request)
    try:
        if raw.get("contract_version") == "coach-request-v3":
            request = CoachAgentRequest.model_validate(raw)
            return await services.current.respond(
                user_id=principal.user_id,
                request=request,
            )
        request = CoachRequest.model_validate(raw)
        return await services.legacy.respond(
            user_id=principal.user_id,
            request=request,
        )
    except ValidationError as exc:
        raise _invalid_request() from exc
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.post("/respond/stream")
async def stream_coach_response(
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> StreamingResponse:
    raw = await _read_json_object(http_request)
    try:
        request = CoachAgentRequest.model_validate(raw)
    except ValidationError as exc:
        raise _invalid_request() from exc
    return StreamingResponse(
        _stream_turn(
            service=services.current,
            user_id=principal.user_id,
            request=request,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-store",
            "X-Accel-Buffering": "no",
        },
    )


@router.get(
    "/history",
    response_model=CoachAgentHistoryResponse | CoachHistoryResponse,
)
async def get_coach_history(
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachAgentHistoryResponse | CoachHistoryResponse:
    try:
        return await services.current.history(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.delete("/history", response_model=CoachHistoryDeleteResponse)
async def delete_coach_history(
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachHistoryDeleteResponse:
    await _require_empty_body(http_request)
    try:
        return await services.current.delete_history(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


# Deprecated compatibility reads for pre-V3 clients. The current Coach surface
# never calls these endpoints and no V3 request can carry their mode selection.
@router.get("/context-options", response_model=CoachContextOptionsResponse)
async def get_legacy_coach_context_options(
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachContextOptionsResponse:
    try:
        return await services.legacy.context_options(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.post(
    "/memories/{memory_id}/selection",
    response_model=CoachMemorySelectionResponse,
)
async def select_legacy_coach_memory(
    memory_id: str,
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachMemorySelectionResponse:
    raw = await _read_json_object(http_request)
    try:
        selection = CoachMemorySelectionRequest.model_validate(raw)
    except ValidationError as exc:
        raise _invalid_request() from exc
    try:
        return await services.legacy.set_memory_selection(
            user_id=principal.user_id,
            memory_id=_parse_uuid(memory_id),
            selected=selection.selected,
        )
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.get("/memories", response_model=CoachMemorySelectionResponse)
async def get_legacy_coach_memories(
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachMemorySelectionResponse:
    try:
        return await services.legacy.memories(user_id=principal.user_id)
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


@router.delete(
    "/memories/{memory_id}/selection",
    response_model=CoachMemorySelectionResponse,
)
async def deselect_legacy_coach_memory(
    memory_id: str,
    http_request: Request,
    principal: Principal = Depends(get_current_principal),
    services: CoachServices = Depends(get_coach_services),
) -> CoachMemorySelectionResponse:
    await _require_empty_body(http_request)
    try:
        return await services.legacy.set_memory_selection(
            user_id=principal.user_id,
            memory_id=_parse_uuid(memory_id),
            selected=False,
        )
    except CoachServiceError as exc:
        raise _http_error(exc) from exc
    except Exception as exc:
        raise _generic_error() from exc


async def _stream_turn(
    *,
    service: CoachAgentService,
    user_id: str,
    request: CoachAgentRequest,
) -> AsyncIterator[bytes]:
    queue: asyncio.Queue[tuple[str, dict[str, object]]] = asyncio.Queue(maxsize=16)

    async def activity(message: str) -> None:
        safe = (
            message if message in _ACTIVITY_MESSAGES else "Working with personal data …"
        )
        await queue.put(("activity", {"message": safe}))

    async def run() -> None:
        try:
            response = await service.respond(
                user_id=user_id,
                request=request,
                activity_callback=activity,
            )
            await queue.put(
                (
                    "completed",
                    {"response": response.model_dump(mode="json")},
                ),
            )
        except CoachServiceError as exc:
            await queue.put(
                (
                    "failed",
                    {"error": exc.detail.model_dump(mode="json")},
                ),
            )
        except asyncio.CancelledError:
            raise
        except Exception:
            await queue.put(
                (
                    "failed",
                    {
                        "error": _detail(
                            "provider_failure",
                            "The Coach service is temporarily unavailable.",
                            retryable=True,
                        ),
                    },
                ),
            )

    task = asyncio.create_task(run())
    try:
        yield _sse(
            "started",
            {
                "request_id": str(request.request_id),
                "contract_version": request.contract_version,
            },
        )
        while True:
            event, data = await queue.get()
            yield _sse(event, data)
            if event in {"completed", "failed"}:
                break
    except asyncio.CancelledError:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        raise
    finally:
        if not task.done():
            task.cancel()
        await asyncio.gather(task, return_exceptions=True)


def _sse(event: str, data: dict[str, object]) -> bytes:
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    return f"event: {event}\ndata: {payload}\n\n".encode("utf-8")


async def _read_json_object(http_request: Request) -> dict[str, object]:
    try:
        raw = bytearray()
        async for chunk in http_request.stream():
            if len(raw) + len(chunk) > _MAX_COACH_REQUEST_BODY_BYTES:
                raise ValueError
            raw.extend(chunk)
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError
        return value
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise _invalid_request() from exc


async def _require_empty_body(http_request: Request) -> None:
    async for chunk in http_request.stream():
        if chunk:
            raise _invalid_request(
                "This Coach operation does not accept a request body.",
            )


def _parse_uuid(value: str) -> UUID:
    try:
        return UUID(value)
    except (ValueError, AttributeError) as exc:
        raise _invalid_request("The Coach id is invalid.") from exc


def _invalid_request(
    message: str = "The Coach request body does not match its strict contract.",
) -> HTTPException:
    return HTTPException(
        status_code=422,
        detail=_detail("invalid_request", message, retryable=False),
    )


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
