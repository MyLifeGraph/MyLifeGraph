from fastapi import Header, HTTPException, Request, status
from pydantic import BaseModel

from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings


class Principal(BaseModel):
    user_id: str


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
        return Principal(user_id=user_id)


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

    return token.strip()


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
