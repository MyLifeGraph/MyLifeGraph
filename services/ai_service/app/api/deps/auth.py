import base64
import binascii
import json
from datetime import UTC, datetime
from uuid import UUID

from fastapi import Header, HTTPException, Request, status
from pydantic import AwareDatetime, BaseModel

from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings


class Principal(BaseModel):
    user_id: str
    authenticated_at: AwareDatetime | None = None


_MAX_ACCESS_TOKEN_CHARS = 16 * 1024
_MAX_ACCESS_TOKEN_PAYLOAD_BYTES = 8 * 1024
_MAX_AUTHENTICATION_METHODS = 16
_RECENT_AUTHENTICATION_METHODS = frozenset(
    {
        "oauth",
        "password",
        "otp",
        "totp",
        "recovery",
        "invite",
        "sso/saml",
        "magiclink",
        "email/signup",
    },
)


def _session_authentication_time(token: str, *, user_id: str) -> datetime | None:
    """Read the latest real auth method from the already verified bearer JWT."""

    if not token or len(token) > _MAX_ACCESS_TOKEN_CHARS:
        return None
    parts = token.split(".")
    if len(parts) != 3 or not parts[1]:
        return None
    try:
        encoded = parts[1].encode("ascii")
        encoded += b"=" * (-len(encoded) % 4)
        payload_bytes = base64.b64decode(
            encoded,
            altchars=b"-_",
            validate=True,
        )
        if len(payload_bytes) > _MAX_ACCESS_TOKEN_PAYLOAD_BYTES:
            return None
        payload = json.loads(payload_bytes.decode("utf-8"))
    except (UnicodeError, binascii.Error, json.JSONDecodeError, RecursionError):
        return None
    if not isinstance(payload, dict) or payload.get("sub") != user_id:
        return None
    session_id = payload.get("session_id")
    if not isinstance(session_id, str):
        return None
    try:
        parsed_session_id = UUID(session_id)
    except ValueError:
        return None
    if str(parsed_session_id) != session_id.lower():
        return None
    methods = payload.get("amr")
    if (
        not isinstance(methods, list)
        or not methods
        or len(methods) > _MAX_AUTHENTICATION_METHODS
    ):
        return None
    timestamps: list[int] = []
    for entry in methods:
        if not isinstance(entry, dict):
            return None
        method = entry.get("method")
        timestamp = entry.get("timestamp")
        if (
            method in _RECENT_AUTHENTICATION_METHODS
            and isinstance(timestamp, int)
            and not isinstance(timestamp, bool)
        ):
            timestamps.append(timestamp)
    if not timestamps:
        return None
    try:
        return datetime.fromtimestamp(max(timestamps), tz=UTC)
    except (OverflowError, OSError, ValueError):
        return None


class TokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        raise NotImplementedError


class UnconfiguredTokenVerifier:
    """PR1 placeholder until Supabase JWT/user lookup is wired in."""

    async def verify(self, token: str) -> Principal | None:
        return None


class SupabaseTokenVerifier:
    """Verifies bearer tokens through Supabase Auth's user endpoint."""

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def verify(self, token: str) -> Principal | None:
        user = await self._client.get_user_for_token(token)
        if user is None:
            return None
        user_id = user.get("id")
        if not isinstance(user_id, str) or not user_id.strip():
            return None
        return Principal(
            user_id=user_id,
            authenticated_at=_session_authentication_time(token, user_id=user_id),
        )


def get_token_verifier() -> TokenVerifier:
    try:
        return SupabaseTokenVerifier(SupabaseRestClient.from_settings(settings))
    except SupabaseConfigurationError:
        pass
    return UnconfiguredTokenVerifier()


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or missing bearer token",
        headers={"WWW-Authenticate": "Bearer"},
    )


def extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise _unauthorized()

    scheme, separator, token = authorization.partition(" ")
    if separator != " " or scheme.lower() != "bearer" or not token.strip():
        raise _unauthorized()

    trimmed_token = token.strip()
    if len(trimmed_token) > _MAX_ACCESS_TOKEN_CHARS:
        raise _unauthorized()
    return trimmed_token


async def get_current_principal(
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> Principal:
    token = extract_bearer_token(authorization)
    verifier = getattr(request.app.state, "token_verifier", get_token_verifier())
    principal = await verifier.verify(token)
    if principal is None:
        raise _unauthorized()
    return principal
