from typing import Protocol

from fastapi import Depends, Header, HTTPException, status
from pydantic import BaseModel


class Principal(BaseModel):
    user_id: str


class TokenVerifier(Protocol):
    async def verify(self, token: str) -> Principal | None: ...


class UnconfiguredTokenVerifier:
    """PR1 placeholder until Supabase JWT/user lookup is wired in."""

    async def verify(self, token: str) -> Principal | None:
        return None


def get_token_verifier() -> TokenVerifier:
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
    authorization: str | None = Header(default=None, alias="Authorization"),
    verifier: TokenVerifier = Depends(get_token_verifier),
) -> Principal:
    token = extract_bearer_token(authorization)
    principal = await verifier.verify(token)
    if principal is None:
        raise _unauthorized()
    return principal
