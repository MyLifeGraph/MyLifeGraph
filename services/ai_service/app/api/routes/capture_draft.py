import json

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.coach import get_coach_agent_service
from app.api.problems.coach import coach_service_problem, coach_unavailable_problem
from app.coach_turn_lifecycle import CoachServiceError
from app.models.capture_draft import CaptureDraftRequest, CaptureDraftResponse
from app.services.capture_draft_service import CaptureDraftService
from app.services.coach_agent_service import CoachAgentService

router = APIRouter(prefix="/daily-capture", tags=["daily-capture"])


@router.post("/draft", response_model=CaptureDraftResponse)
async def extract_capture_draft(
    http_request: Request,
    http_response: Response,
    principal: Principal = Depends(get_current_principal),
    coach: CoachAgentService = Depends(get_coach_agent_service),
    provider_name: str | None = Header(default=None, alias="X-MyLifeGraph-Coach-Provider"),
    api_key: str | None = Header(default=None, alias="X-MyLifeGraph-Coach-Api-Key"),
) -> CaptureDraftResponse:
    http_response.headers["Cache-Control"] = "no-store"
    # Parse manually so request validation never echoes private transcript/key data.
    try:
        body = bytearray()
        async for chunk in http_request.stream():
            if len(body) + len(chunk) > 24 * 1024:
                raise ValueError("Oversized draft request.")
            body.extend(chunk)
        request = CaptureDraftRequest.model_validate(json.loads(body))
    except (ValidationError, UnicodeDecodeError, ValueError, RecursionError) as exc:
        raise HTTPException(422, detail={
            "code": "invalid_request", "message": "Review the check-in text and try again.",
            "retryable": False,
        }) from exc
    try:
        if provider_name == "operator_codex_pilot" and api_key is None:
            selected = coach.for_operator_request()
        elif provider_name is not None or api_key is not None:
            selected = coach.for_byok_request(provider_name=provider_name, api_key=api_key)
        elif coach.requires_explicit_provider:
            raise CoachServiceError(
                "provider_selection_required", "Choose a provider for the check-in draft.",
                retryable=False, status_code=422,
            )
        else:
            selected = coach
        return await CaptureDraftService(selected).extract(user_id=principal.user_id, request=request)
    except CoachServiceError as exc:
        raise coach_service_problem(exc) from exc
    except Exception as exc:
        raise coach_unavailable_problem() from exc
