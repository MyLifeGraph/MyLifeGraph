import base64
import binascii
import json
from datetime import UTC, datetime
from uuid import UUID

import httpx
from fastapi import Depends, Header, HTTPException, Request, status
from pydantic import AwareDatetime, BaseModel

from app.api.deps.supabase import get_supabase_client
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import get_settings
from app.models.account import PILOT_PARTICIPATION_NOTICE_VERSION


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


class UnconfiguredTokenVerifier(TokenVerifier):
    """PR1 placeholder until Supabase JWT/user lookup is wired in."""

    async def verify(self, token: str) -> Principal | None:
        return None


class SupabaseTokenVerifier(TokenVerifier):
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


async def get_token_verifier(request: Request) -> TokenVerifier:
    verifier = getattr(request.app.state, "token_verifier", None)
    if isinstance(verifier, TokenVerifier):
        return verifier
    try:
        return SupabaseTokenVerifier(get_supabase_client(request))
    except SupabaseConfigurationError:
        return UnconfiguredTokenVerifier()


async def get_verified_principal(
    authorization: str | None = Header(default=None, alias="Authorization"),
    verifier: TokenVerifier = Depends(get_token_verifier),
) -> Principal:
    token = extract_bearer_token(authorization)
    principal = await verifier.verify(token)
    if principal is None:
        raise _unauthorized()
    return principal


async def get_current_principal(
    request: Request,
    principal: Principal = Depends(get_verified_principal),
) -> Principal:
    if not get_settings().requires_pilot_participation:
        return principal
    try:
        rows = await get_supabase_client(request).select(
            "profiles",
            params={
                "select": (
                    "id,pilot_participation_notice_version,"
                    "pilot_participation_accepted_at"
                ),
                "id": f"eq.{principal.user_id}",
                "limit": "1",
            },
        )
    except (SupabaseConfigurationError, httpx.HTTPError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Pilot participation verification is unavailable.",
        ) from exc
    if not _has_current_pilot_participation(rows, user_id=principal.user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "pilot_participation_required",
                "message": (
                    "Confirm the current adult pilot notice before using "
                    "product services."
                ),
                "notice_version": PILOT_PARTICIPATION_NOTICE_VERSION,
            },
        )
    return principal


def _has_current_pilot_participation(
    rows: object,
    *,
    user_id: str,
) -> bool:
    if not isinstance(rows, list) or len(rows) != 1:
        return False
    row = rows[0]
    if not isinstance(row, dict) or set(row) != {
        "id",
        "pilot_participation_notice_version",
        "pilot_participation_accepted_at",
    }:
        return False
    if (
        row.get("id") != user_id
        or row.get("pilot_participation_notice_version")
        != PILOT_PARTICIPATION_NOTICE_VERSION
        or not isinstance(row.get("pilot_participation_accepted_at"), str)
    ):
        return False
    try:
        accepted_at = datetime.fromisoformat(
            row["pilot_participation_accepted_at"].replace("Z", "+00:00"),
        )
    except ValueError:
        return False
    return accepted_at.tzinfo is not None
