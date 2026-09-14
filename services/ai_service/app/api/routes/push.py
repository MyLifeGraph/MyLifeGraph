import base64
import json
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute

from app.api.deps.auth import Principal, extract_bearer_token, get_current_principal
from app.api.deps.supabase import get_supabase_client
from app.clients.supabase import SupabaseConfigurationError
from app.models.push import PushCommand, PushState


class PrivatePushRoute(APIRoute):
    def get_route_handler(self):
        original = super().get_route_handler()

        async def handler(request):
            try:
                return await original(request)
            except RequestValidationError:
                # FastAPI normally echoes invalid input, including an FCM token.
                raise HTTPException(422, "Invalid push request.") from None

        return handler


router = APIRouter(prefix="/push", tags=["push"], route_class=PrivatePushRoute)


def verified_session_id(authorization: str, owner: str) -> str:
    """Call only after get_current_principal has verified this exact bearer."""
    try:
        token = extract_bearer_token(authorization)
        part = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
        if claims["sub"] != owner:
            raise ValueError("Owner mismatch")
        return str(UUID(claims["session_id"]))
    except (ValueError, KeyError, IndexError, TypeError) as error:
        raise HTTPException(
            401, "A current authenticated session is required."
        ) from error


def _state(value, request: Request) -> PushState:
    state = PushState.model_validate(value)
    state.available = request.app.state.settings.push_delivery_enabled
    return state


def _problem(error: Exception) -> HTTPException:
    status = 503
    if isinstance(error, httpx.HTTPStatusError):
        if error.response.status_code == 409:
            status = 409
        elif error.response.status_code in (400, 403):
            status = 422
    return HTTPException(
        status, "Push settings could not be confirmed. Reload before retrying."
    )


@router.get("", response_model=PushState)
async def get_push(
    request: Request,
    response: Response,
    principal: Principal = Depends(get_current_principal),
):
    response.headers["Cache-Control"] = "no-store"
    try:
        return _state(
            await get_supabase_client(request).rpc(
                "get_push_state_v1", params={"p_user_id": principal.user_id}
            ),
            request,
        )
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error


@router.post("", response_model=PushState)
async def command_push(
    command: PushCommand,
    request: Request,
    response: Response,
    authorization: str = Header(),
    principal: Principal = Depends(get_current_principal),
):
    response.headers["Cache-Control"] = "no-store"
    session_id = verified_session_id(authorization, principal.user_id)
    if not request.app.state.settings.push_delivery_enabled and (
        command.enabled or command.command == "register"
    ):
        raise HTTPException(503, "Android push is not activated on this server.")
    try:
        return _state(
            await get_supabase_client(request).rpc(
                "apply_push_command_v1",
                params={
                    "p_user_id": principal.user_id,
                    "p_session_id": session_id,
                    "p_request": command.model_dump(mode="json"),
                },
            ),
            request,
        )
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error
